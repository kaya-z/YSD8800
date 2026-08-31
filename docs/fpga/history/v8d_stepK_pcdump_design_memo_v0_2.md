# V8-D Step K: PC遷移生ダンプ 設計メモ

- **文書ID**: v8d_stepK_pcdump_design_memo_v0_2.md
- **作成日**: 2026-07-25
- **前版**: v0.1 (2026-07-25) — 条件付き差戻し（必修正2件・推奨修正3件・確認事項2件）
- **前工程**: CHAT116 Step J（$2610→$248Dへのジャンプ局在完了・機序未特定）
- **目的**: PC=$2610到達後の PC 遷移＋PSRAMバス信号を **毎cyc生ダンプ** し、$248D へ飛ぶ機序を確定する
- **状態**: 設計中（v0.1 レビュー反映済、再レビュー待ち）

---

## 1. 背景

CHAT116 の Step A〜J で、V8-D Dhrystone RTL 実行時に:

- **PC=$2610 (L_0140) 到達後、$2614/$2618/$261A/$2626 のいずれにも到達せず、$248D (Func_2入口) にジャンプ**していることが判明。
- Ch_Loc の STB/LDW 混在（scc23 コード生成側の 8/16bit 混在）は候補だが、**Ch_Loc 汚れは A レジスタに影響するだけで PC には無関係**のはず。
- **$2610 実行中に PC が破壊される機序**が未解明。

## 2. 目的

$2610 到達後、CPU が実際にどの PC を辿って $248D に至るかを **1cyc 毎の生ダンプ**で実測し、以下の3仮説のいずれかを確定する:

| 仮説 | 予想される PC 遷移パターン |
|---|---|
| θ1a: LDW A,[X+#FFFA] のアドレス生成バグ | $2610 実行中の PSRAM addr が $260A (=X-6) 以外 |
| θ1b: LDW writeback バグ (PCへの誤書込) | PSRAM addr/rdata 正しいが PC が書換わる |
| θ2: IRQ 受理経路の異常 | $2610 実行後、IRQベクタ相当 ($0025 or 他) を経由して $248D |
| θ3: PSRAM ctrl バグ (隣接干渉等) | PSRAM addr 正しいが rdata が mem[] 内容と不一致 |

**（v0.1 からの変更）** レビュー指摘2により、旧θ1 を θ1a/θ1b に細分化し、θ3 を PSRAM ctrl バグとして明示。

## 3. 実装方針

### 3.1 ベース

- `tb_cpu_v8d_dhry_stepJ_jmp.sv` を派生
- 新ファイル名: `tb_cpu_v8d_dhry_stepK_pcdump.sv`
- 派生元は HANDOVER 9.3 指針に従い明示（ファイル先頭コメント）

### 3.2 追加ロジック — 案K1（毎cyc生ダンプ）採用

**【v0.1 からの重大変更】**  
レビュー指摘1（PC変化検出＝1cyc毎の等号不成立）を受け、**PC変化条件を廃止**。PC不変マルチサイクル命令中も毎cyc観測する **観測モデル切替** を行う。

**新規変数** (task run_until_halt のローカル、確認事項1で確定):
```systemverilog
logic       k_dump_active;   // ダンプ実施中フラグ ($2610到達で1、$2618到達で0)
integer     k_dump_cnt;      // ダンプ中のcyc数 (0..50)
integer     k_episode;       // 何回目の$2610通過エピソードか (1..N)
integer     k_total_dumped;  // 累計ダンプ行数 (安全弁)
```

**動作ロジック** (task内 while ループの各 iteration で):

```
[イベント発生] (PC変化検出 case 内)
  PC=$2610 (L0140到達): 
    k_dump_active <= 1
    k_dump_cnt    <= 0
    k_episode     <= k_episode + 1
    "★[STEPK ep=N cyc=...] L0140到達 — 生ダンプ開始 A=%h X=%h [X-6..X-5]=%h %h" 
    ↑ Step J の post_jmp_dump_cnt 分岐から統合 (指摘5)

  PC=$2618 (正常経路到達):
    if (k_dump_active) begin
      k_dump_active <= 0
      "  [STEPK ep=N cyc=...] 正常経路: $2618到達で ep 終了 (n=%0d cyc消費)" 表示
    end

  PC=$248D (異常ジャンプ検出):
    if (k_dump_active) begin
      "★★★ [STEPK ep=N cyc=...] BUG DETECTED! PC=$248D 到達 (n=%0d cyc消費)"
      "★★★  最後の5cycのPSRAM/PCを再掲: (省略可)"
      $finish
    end

[毎cyc動作] (task while 内 @(posedge cpu_clk) 直後・PC変化検出とは独立):
  if (k_dump_active) begin
    k_dump_cnt++
    $display("  [K ep=%0d n=%0d cyc=%0d] PC=%04h A=%04h B=%04h X=%04h SP=%04h FLAGS=%04h PSRAM: req=%0b we=%0b ack=%0b addr=%05h wdata=%02h rdata=%02h",
             k_episode, k_dump_cnt, to_cyc,
             dbg_pc, dbg_a, dbg_b, dbg_x, dbg_sp, dbg_flags,
             u_membus.u_psram_ctrl.req,
             u_membus.u_psram_ctrl.we,
             u_membus.u_psram_ctrl.ack,
             u_membus.u_psram_ctrl.addr,
             u_membus.u_psram_ctrl.wdata,
             u_membus.u_psram_ctrl.rdata);
    k_total_dumped++
    if (k_dump_cnt >= 50) begin
      $display("  [STEPK ep=%0d] WARN: 50cyc到達も$2618/$248Dいずれも未到達→dump停止", k_episode);
      k_dump_active <= 0;
    end
    if (k_total_dumped >= 5000) begin
      $display("  [STEPK] SAFETY: 累計5000行到達→強制停止");
      $finish;
    end
  end
```

**PSRAMバス信号名の実源確認結果**（レビュー指摘2 対応・v0.2 で追加）:

`ysd8800_psram_ctrl_v0_2.sv` L52-57 の module ポートで確定:

| 信号名 | 用途 | 幅 |
|---|---|---|
| `u_membus.u_psram_ctrl.addr` | 物理アドレス | `[PHYS_AW-1:0]` |
| `u_membus.u_psram_ctrl.wdata` | 書込データ | `[7:0]` |
| `u_membus.u_psram_ctrl.we` | Write Enable | `[0]` |
| `u_membus.u_psram_ctrl.req` | Request | `[0]` |
| `u_membus.u_psram_ctrl.ack` | Acknowledge | `[0]` |
| `u_membus.u_psram_ctrl.rdata` | 読出データ | `[7:0]` |

### 3.3 ダンプフォーマット（v0.2 更新）

固定カラム、**毎cyc 1行**（PC不変中も出力）:

```
  [K ep=1 n=1 cyc=123456] PC=2610 A=0059 B=0052 X=FC90 SP=FC7A FLAGS=0080 PSRAM: req=1 we=0 ack=0 addr=0260A wdata=00 rdata=00
  [K ep=1 n=2 cyc=123457] PC=2610 A=0059 B=0052 X=FC90 SP=FC7A FLAGS=0080 PSRAM: req=1 we=0 ack=0 addr=0260A wdata=00 rdata=00
  [K ep=1 n=3 cyc=123458] PC=2610 A=0059 B=0052 X=FC90 SP=FC7A FLAGS=0080 PSRAM: req=1 we=0 ack=1 addr=0260A wdata=00 rdata=F7
  ...
```

- `ep`: L0140通過エピソード番号（1,2,3,...）
- `n`: 当該エピソード内での cyc カウンタ（1..50、PC変化条件なし）
- `cyc`: 絶対サイクル数

### 3.4 停止条件（優先順）

1. **$248D 到達** → `$finish`（真因確定）
2. **累計ダンプ行数 5000超** → `$finish`（安全弁、暴走ログ防止）
3. **HALT 到達** → 元TBの終了処理へ（$248Dに至らず完走した場合）
4. **max_cyc 到達** → タイムアウト（元TBのWARN）

### 3.5 既存 Step J 出力の扱い（v0.2 更新・指摘5対応）

- **Step J の $2610 到達時ダンプ (post_jmp_dump_cnt<3) は削除**し、Step K のエピソード開始出力に統合（同一cyc二重発火回避）。
- Step J の $2614/$2618/$261A ダンプは**残す**（正常経路確認用）。ただし $2618 は Step K の dump 停止側とも連携。
- Step J の Func_2 RET ダンプ（10回制限）は**残す**（$248D到達時の post-mortem 補助）。
- Step J の L0139/L0143/L0145/L0140 通過カウンタ・エントリカウンタは**全て残す**。

## 4. TB以外の変更

- 元TB (`tb_cpu_v8d_dhry_stepJ_jmp.sv`) は**変更しない**（原本保持）。
- 派生元は新TB冒頭に明記。

## 5. 実行手順

1. **PSRAM信号名を実源確認済**（v0.2 §3.2 の表参照。実装時 grep 再確認不要）
2. `tb_cpu_v8d_dhry_stepK_pcdump.sv` を作成
3. iverilog でビルド確認（構文エラーなし）
4. **短時間走行 (max_cyc=1万) で「$2610未到達＝ダンプ0行」を確認**（KY防止策）
5. **本走 (max_cyc=1000万) で $248D 到達 or 5000行安全弁 or タイムアウト**
6. ログを解析し θ1a/θ1b/θ2/θ3 のどれか確定
7. 確定結果を次チャットHANDOVERに記録

## 6. KY再確認（v0.2 更新・指摘4対応）

CHAT117 KY「観測窓は50cycに厳格制限＋累計行数安全弁」に加え、v0.2 で **KY-K-add1, KY-K-add2** を追加:

| KY 項目 | 対応 |
|---|---|
| 観測窓 50cyc 制限 | k_dump_cnt >= 50 で dump_active=0 |
| $2610未到達時ダンプ抑止 | k_dump_active 初期値=0、L0140到達でのみラッチ |
| 固定カラム出力 | `%0d %04h %02h %0b %05h` 統一 |
| ファイル名 stepJ と混同回避 | `stepK_pcdump` 命名 |
| 短時間走行での事前確認 | 手順 4 で 1万cyc 走行 |
| 累計行数安全弁 | k_total_dumped >= 5000 で $finish |
| **KY-K-add1**: 毎cyc `$display` の I/O 待ちで iverilog 実行速度が数十倍遅くなる懸念 | $2610到達までは k_dump_active=0 で完全抑止（既存KYと整合）。$248D 検出後は即 $finish で走行短縮。 |
| **KY-K-add2**: PSRAM バス信号名が RTL 実源で確定するまで、設計メモの仮の信号名で TB を書くと構文エラー or 想定外信号を拾う | v0.2 §3.2 で `ysd8800_psram_ctrl_v0_2.sv` L52-57 を実源照合済み。実装時は §3.2 の表通りに使用（addr/wdata/we/req/ack/rdata）。 |

## 7. 期待される結論（v0.2 更新・指摘2対応で細分化）

| ダンプ結果 | 判定 |
|---|---|
| $2610 LDW 中の PSRAM read アドレスが $260A (=X-6) 以外 | **θ1a** (LDW アドレス生成バグ) |
| PSRAM read addr 正しいが rdata と mem[] 内容が不一致 | **θ3** (PSRAM ctrl バグ) |
| PSRAM addr/rdata 正しいが PC が書き換わる | **θ1b** (LDW writeback バグ = PC への誤書込) |
| $2610 → IRQベクタ ($0025 等) → $248D の中間PC出現 | **θ2** (IRQ 受理経路) |
| $2618 に正常到達し ep 継続、後に別 ep で $248D | 「特定周回で発生」→さらに絞込み必要 |
| $2618 に毎回正常到達し $248D 到達せず | 「別経路で $248D 到達」→他ラベルにも Step K 相当を追加 |

## 8. 確認事項の確定（v0.2 で確定・確認事項1,2対応）

- **変数スコープ**: **task ローカルで確定**（シミュレーション1回で完結、波形観測不要）。
- **$2618 正常経路根拠**: `v8d_expansion_analysis_v1_0.md §2 Step J` にて $2618 は **0回通過** と確認済。$2618 到達＝正常経路確定と定義する。

## 9. レビュー項目（v0.2 で残す確認）

- [ ] 案K1 で毎cyc `$display` の I/O 待ちが実測でどれくらいか（KY-K-add1 の見込み妥当性）
- [ ] $248D 到達後、Step J の Func_2 RET ダンプ（10回制限）が邪魔にならないか
- [ ] PSRAM 信号名アクセスパス `u_membus.u_psram_ctrl.<sig>` は Step J L322-334 の `u_membus.u_psram_ctrl.mem[]` と同構造で問題ないか

## 10. v0.1 → v0.2 変更点サマリ

| 節 | v0.1 | v0.2 |
|---|---|---|
| §2 目的 | θ1/θ2/θ3 の3仮説 | **θ1a/θ1b/θ2/θ3 に細分化**（指摘2） |
| §3.2 追加ロジック | PC変化検出時のみダンプ | **PC変化条件廃止・毎cyc生ダンプ**（指摘1・案K1） |
| §3.2 ダンプ項目 | PC/A/B/X/SP/FLAGS | **+ PSRAM req/we/ack/addr/wdata/rdata**（指摘2） |
| §3.3 フォーマット | 「1行1cyc（PC変化時のみ）」 | **「毎cyc 1行」に変更**（PC不変中も出力） |
| §3.5 Step J 併存 | 全て残す | **$2610 ダンプは Step K に統合**（指摘5） |
| §6 KY表 | 6項目 | **+ KY-K-add1, KY-K-add2**（指摘4） |
| §7 期待結論 | 4行 | **6行に細分化**（θ1a/θ1b 分離・$2618継続/未到達も追加） |
| §8 確認事項 | レビュー項目に列挙 | **task ローカル / expansion_analysis §2 参照** で確定 |

## 11. 参照資料

- v8d_stepK_pcdump_design_memo_v0_1.md（前版）
- v8d_stepK_pcdump_design_memo_v0_1_review_v1_0.docx（レビュー指摘書）
- tb_cpu_v8d_dhry_stepJ_jmp.sv（派生元）— L263-269 (while構造)・L276 ($248D検出)・L316-337 ($2610ダンプ、v0.2で統合)
- ysd8800_psram_ctrl_v0_2.sv — L52-57 (PSRAMバス信号名確定)
- v8d_expansion_analysis_v1_0.md — §2 Step J・§5 仮説
- HANDOVER_CHAT116.md — 本工程の直前状態
- kaizen.txt — 原則43 (実装前レビュー)・原則76 (RTL実測)
- review_insights_v1_0.docx — 原則5.1 (実源照合)

## 改版履歴

| 版 | 日付 | 内容 |
|---|---|---|
| v0.1 | 2026-07-25 | 初版。CHAT117 Step K の PC遷移生ダンプ TB 設計を記述。条件付き差戻し。 |
| v0.2 | 2026-07-25 | レビュー指摘反映。必修正2件（案K1採用/PSRAM信号追加）・推奨修正3件（KY追加/Step J統合/post-mortem対応）・確認事項2件（taskローカル/$2618根拠）を全て反映。§7 期待結論を θ1a/θ1b/θ2/θ3 に細分化。 |
