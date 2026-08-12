# V8-D Step K: PC遷移生ダンプ 設計メモ

- **文書ID**: v8d_stepK_pcdump_design_memo_v0_1.md
- **作成日**: 2026-07-25
- **前工程**: CHAT116 Step J（$2610→$248Dへのジャンプ局在完了・機序未特定）
- **目的**: PC=$2610到達後の PC 遷移を 1cyc 毎に生ダンプし、$248D へ飛ぶ機序を確定する
- **状態**: 設計中（レビュー待ち）

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
| θ1: LDW A,[X+#FFFA] 実装バグ | $2610 の LDW 実行中に PC が直接 $248D になる（中間 PC なし） |
| θ2: IRQ 受理経路の異常 | $2610 実行後、IRQベクタ相当（$0025 or 他）を経由して $248D に到達 |
| θ3: 別の PC 破壊経路 | 上記以外の中間 PC が出現 |

## 3. 実装方針

### 3.1 ベース

- `tb_cpu_v8d_dhry_stepJ_jmp.sv` を派生
- 新ファイル名: `tb_cpu_v8d_dhry_stepK_pcdump.sv`
- 派生元は HANDOVER 9.3 指針に従い明示（ファイル先頭コメント）

### 3.2 追加ロジック（最小追加）

**新規変数** (task run_until_halt のローカル or module scope):
```systemverilog
logic       k_dump_active;   // ダンプ実施中フラグ (L0140到達で1、通常経路or異常到達で0)
integer     k_dump_cnt;      // ダンプ中のcyc数 (0..50)
integer     k_episode;       // 何回目のL0140通過エピソードか (1..N)
integer     k_total_dumped;  // 累計ダンプ行数 (安全弁)
```

**動作ロジック** (PC変化検出 case 文の中):
```
[イベント発生]
  PC=$2610 (L0140到達): 
    k_dump_active <= 1
    k_dump_cnt    <= 0
    k_episode     <= k_episode + 1
    "★[STEPK ep=N] L0140到達 cyc=..." 表示

  PC=$2618 (通常経路到達 = STW A,[SP] 直後):
    k_dump_active <= 0
    "  [STEPK ep=N] 正常経路: $2618到達で ep 終了" 表示（1行）

  PC=$248D (異常ジャンプ検出):
    "★★★ [STEPK ep=N] BUG DETECTED! PC=$248D 到達 cyc=..." 表示
    最終遷移サマリを表示
    $finish

[毎cyc動作] (task内 while ループの各 iteration で):
  if (k_dump_active && dbg_pc !== pc_prev) begin
    k_dump_cnt++
    $display("  [K ep=%0d n=%0d cyc=%0d] PC=%04h A=%04h B=%04h X=%04h SP=%04h FLAGS=%04h",
             k_episode, k_dump_cnt, to_cyc,
             dbg_pc, dbg_a, dbg_b, dbg_x, dbg_sp, dbg_flags);
    if (k_dump_cnt >= 50) begin
      $display("  [STEPK ep=%0d] WARN: 50cyc到達も$2618/$248Dいずれも未到達→dump停止", k_episode);
      k_dump_active <= 0;
    end
    if (k_total_dumped >= 5000) begin
      $display("  [STEPK] SAFETY: 累計5000行到達→強制停止");
      $finish;
    end
    k_total_dumped++
  end
```

### 3.3 ダンプフォーマット

固定カラム、1行1cyc（PC変化時のみ = 命令実行1回に相当）:
```
  [K ep=1 n=1 cyc=123456] PC=2610 A=0059 B=0052 X=FC90 SP=FC7A FLAGS=0080
  [K ep=1 n=2 cyc=123458] PC=2614 A=0000 B=0052 X=FC90 SP=FC7A FLAGS=0004
  ...
```

- `ep`: L0140通過エピソード番号（1,2,3,...）
- `n`: 当該エピソード内での命令実行数（1..50）
- `cyc`: 絶対サイクル数

### 3.4 停止条件（優先順）

1. **$248D 到達** → `$finish`（真因確定）
2. **累計ダンプ行数 5000超** → `$finish`（安全弁、暴走ログ防止）
3. **HALT 到達** → 元TBの終了処理へ（$248Dに至らず完走した場合）
4. **max_cyc 到達** → タイムアウト（元TBのWARN）

### 3.5 既存 Step J 出力の扱い

- Step J の $2610 到達時ダンプ（3回制限）は**残す**（比較用）。
- Step J の $2614/$2618/$261A ダンプは**残す**（正常経路確認用）。
- Step J の Func_2 RET ダンプ（10回制限）は**残す**。

## 4. TB以外の変更

- 元TB (`tb_cpu_v8d_dhry_stepJ_jmp.sv`) は**変更しない**（原本保持）。
- 派生元は新TB冒頭に明記。

## 5. 実行手順

1. `tb_cpu_v8d_dhry_stepK_pcdump.sv` を作成
2. iverilog でビルド確認（構文エラーなし）
3. **短時間走行 (max_cyc=1万) で「$2610未到達＝ダンプ0行」を確認**（KY防止策5番）
4. **本走 (max_cyc=1000万) で $248D 到達 or 5000行安全弁 or タイムアウト**
5. ログを解析し θ1/θ2/θ3 のどれか確定
6. 確定結果を CHAT117 HANDOVER に記録

## 6. KY再確認

CHAT117 KY「観測窓は50cycに厳格制限＋累計行数安全弁」を全て実装済み:

| KY 項目 | 対応 |
|---|---|
| 観測窓 50cyc 制限 | k_dump_cnt >= 50 で dump_active=0 |
| $2610未到達時ダンプ抑止 | k_dump_active 初期値=0、L0140到達でのみラッチ |
| 固定カラム出力 | `%0d %04h` 統一 |
| ファイル名 stepJ と混同回避 | `stepK_pcdump` 命名 |
| 短時間走行での事前確認 | 手順 3 で 1万cyc 走行 |
| 累計行数安全弁 | k_total_dumped >= 5000 で $finish |

## 7. 期待される結論

| ダンプ結果 | 判定 |
|---|---|
| $2610 → $248D で PC が1cycで飛ぶ | θ1 (LDW実装バグ) 濃厚 |
| $2610 → $0025 or 他ベクタ → $248D | θ2 (IRQ受理経路) 濃厚 |
| $2610 → 未知の中間PC → $248D | θ3 (未知経路)、追加調査必要 |
| $2618 に正常到達し ep 継続、後に別 ep で $248D | 「特定周回で発生」→さらに絞込み必要 |

## 8. レビュー項目

- [ ] `k_dump_active` のラッチ範囲は task ローカルで良いか（module scope 不要か）
- [ ] `k_total_dumped >= 5000` の閾値は妥当か（もっと少なく or 多く）
- [ ] `$2618` を「正常経路」とする根拠は Step J で確認済みか
- [ ] `$248D` 到達検出は PC変化検出 case 内で良いか（既存 `func2_ent` カウンタと同一ロジックで良いか）
- [ ] ダンプ抑止条件に「A=Ch_Loc 期待値と一致するか」等の条件は不要か

## 改版履歴

| 版 | 日付 | 内容 |
|---|---|---|
| v0.1 | 2026-07-25 | 初版。CHAT117 Step K の PC遷移生ダンプ TB 設計を記述。レビュー待ち。 |
