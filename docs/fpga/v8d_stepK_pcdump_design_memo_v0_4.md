# V8-D Step K: PC遷移生ダンプ 設計メモ

- **文書ID**: v8d_stepK_pcdump_design_memo_v0_4.md
- **作成日**: 2026-07-25
- **前版**: v0.3 (2026-07-25, 実装着手可) — Step K 実装・走行で**観測ポイント誤り判明**
- **前々版**: v0.2 (条件付き承認) / v0.1 (条件付き差戻し)
- **前工程**: CHAT116 Step I 最終結論・Step J 案(1) 承認
- **目的**: **$262D JMP _L_0150 命令の PC 加算処理**を毎cyc生ダンプで実測し、$248D へ飛ぶ機序を確定する
- **状態**: 設計中（観測ポイント訂正のみ、レビュー待ち・v0.3 との差分最小）

---

## 0. v0.3→v0.4 変更の要旨（先頭で明示）

**変更理由**: v0.3 で「$2610 の LDW A,[X+#FFFA] が真因」と誤設定し、実装・走行の結果、100 エピソード全て $2610→$24C9 の**正常経路**（Ch_Loc<'W' で while 継続）を観測するのみで真因に到達せず。CHAT116 Step I 最終結論および Step J 案(1) の観測ターゲットは **$262D JMP _L_0150** であり、v0.3 の仮説設定 (θ1a/θ1b の LDW 系) は誤り。

**変更範囲（差分最小・観測ポイントのみ）**:

| 節 | v0.3 | v0.4 |
|---|---|---|
| §2 目的 | LDW A,[X+#FFFA] の実装バグ | **$262D JMP _L_0150 の PC 加算処理**の実装バグ |
| §3.2 dump 開始条件 | PC=$2610 | **PC=$2626 (BGE命令位置)** |
| §3.2 dump 停止条件 | PC=$2618 or 50cyc | **PC=$2634 (JMP正常先=L_0150) or PC=$2630 (BGE成立時=L_0149) or 100cyc** |
| §3.2 観測窓 | 50cyc | **100cyc** |
| §6 KY | KY-K-add1〜3 | KY-K-add4 追加（観測点訂正の再発防止） |
| §7 期待結論 | LDW アドレス/writeback/PSRAM ctrl/IRQ | **JMP rel16 フェッチ/JMP PC 加算/PSRAM/IRQ** に置換 |

**変更しない範囲（v0.3 流用）**:
- 案K1（毎cyc生ダンプ）・案C（全ブロッキング代入 `=`・エピソード開始マーカ縮小）
- PSRAM信号（addr/wdata/we/req/ack/rdata）観測
- 累計5000行安全弁
- Step J 既存出力の扱い（$2618/$261A/Func_2 RET）は残す

---

## 1. 背景（v0.4 で更新）

CHAT116 Step I 最終結論（HANDOVER_CHAT116.md 記載）:

- **L_0140 ($2610) 通過=3557**、その次のラベル L_0149 ($2630)/L_0150 ($2634)/... /L_0138 通過=**全て 0**
- **$2610 と $2630 の間、32バイトの中で PC が Func_2 入口 ($248D) にジャンプ**
- 該当区間の Dhrystone 命令構造:
  - $2610〜$2625: while ループ判定合流 → Ch_Loc<'W' 判定 (BGE命令の前段)
  - **$2626: BGE _L_0149** (Ch_Loc<'W' 成立 → $2630 へ)
  - $2629: LDW A,#0 (BGE不成立時、以降 else 経路)
  - **$262D: JMP _L_0150** (`60 04 00` = offset +4、$2634 に飛ぶはず)
  - $2634: L_0150 (else 側の合流)
- **真因**: **$262D JMP _L_0150 の PC 遷移が正しく行われず、代わりに $248D に飛ぶ**

CHAT116 Step J 案(1) で承認された観測方針:
- $262D 到達時の A/B/X/SP/FLAGS
- PSRAM の $262D-$2632 の実バイト列（JMP 命令が本当に `60 04 00` か）
- JMP実行後の次PC ($2634 or $248D)

v0.3 は Step J 案(1) の**観測方針を Step K の毎cyc生ダンプ化・PSRAM信号追加で強化**するものであるべきだが、v0.3 実装では**観測ポイントを$2610に誤設定**し、真因に到達しなかった。

## 2. 目的（v0.4 で訂正）

**$262D JMP _L_0150 命令の PC 加算処理**を毎cyc生ダンプで実測し、以下の4仮説のいずれかを確定する:

| 仮説 | 予想される観測パターン |
|---|---|
| θ1: JMP rel16 のフェッチ順序異常 | PSRAM 上の $262D-$262F バイト列が `60 04 00` ではない |
| θ2: JMP PC 加算処理バグ | PSRAM バイト列は `60 04 00` 正常だが、PC=$262D 直後に $248D にジャンプ |
| θ3: PSRAM ctrl バグ (隣接干渉等) | PSRAM addr 正しいが rdata が mem[] と不一致 |
| θ4: BGE/LDW/JMP 連続実行時の相互作用 | $2626 の BGE の PC遷移が正しく完了せず、$2629/$262D で異常PC |

**（v0.3 からの変更）** 仮説を LDW 系 → JMP 系に全面訂正。

## 3. 実装方針

### 3.1 ベース

- 現 `tb_cpu_v8d_dhry_stepK_pcdump.sv` (v0.1、v0.3準拠で実装済) をベースに**観測ポイントのみ修正**して v0.2 とする
- 派生元は同じ `tb_cpu_v8d_dhry_stepJ_jmp.sv`
- ファイル名は継続: `tb_cpu_v8d_dhry_stepK_pcdump.sv` (バージョンヘッダを v0.1→v0.2 更新)

### 3.2 追加ロジック（v0.3 案K1+案C 流用、PC値のみ差分修正）

**変数** (v0.3 と同一・変更なし):
```systemverilog
logic       k_dump_active;
integer     k_dump_cnt;
integer     k_episode;
integer     k_total_dumped;
```

**動作ロジック** (case 分岐の PC 値のみ差分修正):

```systemverilog
    // PC変化検出 case 内
    16'h2626: begin  // ★v0.4 修正: dump 開始条件 (BGE命令位置)
        //   BGE _L_0149: Ch_Loc<'W' なら $2630 (L_0149) に飛ぶ (成立)
        //                Ch_Loc>='W' なら $2629 に落ちる (不成立→ else 経路 →$262D JMP)
        //   ここから dump 開始し、$262D JMP の PC 遷移を捕捉する
        k_dump_active = 1'b1;
        k_dump_cnt    = 0;
        k_episode     = k_episode + 1;
        $display("★[STEPK ep=%0d cyc=%0d] $2626 BGE到達 - JMP経路観測開始",
                 k_episode, to_cyc);
    end
    16'h2630: begin  // ★v0.4 修正: BGE成立時の正常経路 (dump 停止)
        L0149_ent = L0149_ent + 1;
        if (k_dump_active) begin
            $display("  [STEPK ep=%0d cyc=%0d] BGE成立(Ch_Loc<'W') → $2630 到達で ep 終了 (n=%0d cyc)",
                     k_episode, to_cyc, k_dump_cnt);
            k_dump_active = 1'b0;
        end
    end
    16'h2634: begin  // ★v0.4 修正: JMP _L_0150 正常先 (dump 停止・真の目的達成)
        L0150_ent = L0150_ent + 1;
        if (k_dump_active) begin
            $display("  [STEPK ep=%0d cyc=%0d] ★★JMP _L_0150 正常経路: $2634 到達で ep 終了 (n=%0d cyc)",
                     k_episode, to_cyc, k_dump_cnt);
            k_dump_active = 1'b0;
        end
    end
    16'h248D: begin  // BUG検出 (v0.3 と同一・変更なし)
        func2_ent = func2_ent + 1;
        if (k_dump_active) begin
            $display("★★★ [STEPK ep=%0d cyc=%0d] BUG DETECTED! PC=$248D 到達 (n=%0d cyc)",
                     k_episode, to_cyc, k_dump_cnt);
        end
    end
```

**毎cyc動作ブロック** (v0.3 と同一、`k_dump_cnt >= 100` に変更のみ):

```systemverilog
    if (k_dump_active) begin
        k_dump_cnt = k_dump_cnt + 1;
        k_total_dumped = k_total_dumped + 1;
        $display("  [K ep=%0d n=%0d cyc=%0d] PC=%04h A=%04h B=%04h X=%04h SP=%04h FLAGS=%04h PSRAM: req=%0b we=%0b ack=%0b addr=%05h wdata=%02h rdata=%02h",
                 k_episode, k_dump_cnt, to_cyc,
                 dbg_pc, dbg_a, dbg_b, dbg_x, dbg_sp, dbg_flags,
                 u_membus.u_psram_ctrl.req, u_membus.u_psram_ctrl.we,
                 u_membus.u_psram_ctrl.ack, u_membus.u_psram_ctrl.addr,
                 u_membus.u_psram_ctrl.wdata, u_membus.u_psram_ctrl.rdata);
        if (dbg_pc == 16'h248D) begin
            $display("  [STEPK] BUG cyc の n=%0d ダンプ済 → $finish", k_dump_cnt);
            $finish;
        end
        if (k_dump_cnt >= 100) begin  // ★v0.4 修正: 50→100
            $display("  [STEPK ep=%0d] WARN: 100cyc到達も$2630/$2634/$248D未到達→dump停止", k_episode);
            k_dump_active = 1'b0;
        end
        if (k_total_dumped >= 5000) begin
            $display("  [STEPK] SAFETY: 累計5000行到達→強制停止");
            $finish;
        end
    end
```

**PSRAM信号** (v0.3 §3.2 表と同一、変更なし):

`u_membus.u_psram_ctrl.{req,we,ack,addr,wdata,rdata}` — `ysd8800_psram_ctrl_v0_2.sv` L52-57 実源照合済

### 3.3 ダンプフォーマット（v0.4 更新）

固定カラム、毎cyc 1行（v0.3 と同フォーマット）:

```
★[STEPK ep=1 cyc=XXXXXX] $2626 BGE到達 - JMP経路観測開始
  [K ep=1 n=1 cyc=XXXXXX] PC=2626 A=... B=... X=... SP=... FLAGS=... PSRAM: req=1 we=0 ack=0 addr=02626 wdata=00 rdata=??
  ... (BGE fetch: PSRAM ack 待ち約12cyc)
  [K ep=1 n=~13] PC=2629 A=0000 ...       ← BGE不成立 → $2629 に落ちる
  ... (LDW #0 fetch)
  [K ep=1 n=~25] PC=262D A=0000 ...       ← LDW後、JMP命令フェッチ
  ... (JMP rel16 fetch: 3バイト = req/ack 3回?)
  [K ep=1 n=~50] PC=???? ← JMP実行後の次PC ($2634 or $248D)
```

**注記**: PSRAM `LATENCY_NORMAL=12` (ysd8800_psram_ctrl_v0_2.sv L43) のため、req→ack は約12cyc離れる。BGE/LDW/JMP の 3命令 = 8バイト程度のフェッチで 12cyc×3 = 36cyc、命令実行を加えて 50〜80cyc 見込み。**観測窓 100cyc で余裕あり**。

### 3.4 停止条件（優先順、v0.4 更新）

1. **$248D 到達 cyc の n=... ダンプ完了後** → `$finish`（真因確定）
2. **$2634 到達** → dump 停止・エピソード継続（BGE不成立→JMP正常経路確認）
3. **$2630 到達** → dump 停止・エピソード継続（BGE成立→JMP経路に入らなかった正常経路）
4. **累計ダンプ行数 5000超** → `$finish`（安全弁）
5. **HALT / max_cyc** → 元TB終了処理

### 3.5 既存 Step J 出力（v0.3 と同一・変更なし）

- Step J の $2614/$2618/$261A ダンプは残す（正常経路確認用）
- Step J の Func_2 RET ダンプ（10回制限）は残す
- Step J の L0139/L0143/L0145/L0140 通過カウンタ・エントリカウンタは全て残す
- **v0.3 で $2610 dump 開始としていた case を削除**（$2610 は今回は特別扱いしない・L0140_ent カウントのみ残す）

## 4. TB以外の変更

- 現 v0.1 TB ファイルを **v0.2 に版数アップ**して修正（元TB stepJ は不変）

## 5. 実行手順

1. 現 `tb_cpu_v8d_dhry_stepK_pcdump.sv` の $2610 case を「L0140_ent++ のみ」に戻す
2. $2626/$2630/$2634 case を dump 制御ロジックに変更
3. 観測窓 50cyc → 100cyc
4. バージョンヘッダを v0.1→v0.2 更新
5. iverilog ビルド（RTL 依存は v0.3 と同一で確定済）
6. **短時間走行 (max_cyc=1万) で $2626 未到達＝ダンプ0行を確認**
7. 本走 (max_cyc=1000万) で $248D 到達 or $2634 到達を観測
8. 結果を θ1〜θ4 で判定

## 6. KY再確認（v0.4 更新）

v0.3 の KY全項目を継承。v0.4 新規追加:

| KY 項目 | 対応 |
|---|---|
| （v0.3 継承 8項目） | 変更なし |
| **KY-K-add4** (v0.4 新規): **観測ポイントを HANDOVER 精読せず設定して真因に到達しない事故の再発** | v0.4 冒頭 §0/§1 で HANDOVER_CHAT116.md の Step I 最終結論・Step J 案(1) 観測方針を引用付記。**設計メモ本文の PC値は HANDOVER の記述と1対1で照合**（$2626 BGE = HANDOVER「$2626 が BGE」明記、$262D JMP = HANDOVER「$262D JMP _L_0150」明記、$248D = HANDOVER「Func_2 入口」明記）。 |

## 7. 期待される結論（v0.4 訂正、θ1-θ4 に全面置換）

| ダンプ結果 | 判定 |
|---|---|
| PSRAM $262D-$262F の rdata バイト列が `60 04 00` 以外 | **θ1** (JMP rel16 フェッチ順序異常) |
| PSRAM $262D-$262F の rdata バイト列が `60 04 00` 正常だが、$262D 直後 PC=$248D | **θ2** (JMP PC 加算処理バグ) |
| PSRAM addr 正しいが rdata と mem[] 内容が不一致 | **θ3** (PSRAM ctrl バグ) |
| $2626 BGE の PC 遷移が正しく完了せず、$2629/$262D で PC が既に異常 | **θ4** (連続実行時の相互作用) |
| $2634 に正常到達し ep 継続、後に別 ep で $248D | 「特定周回で発生」→ さらに絞込み |
| 全 ep で $2630 (BGE成立=Ch_Loc<'W') に行き、$262D 経路に来ない | 「Ch_Loc<'W' が常に成立している」→ Ch_Loc セット処理の別バグ |
| 全 ep で $2634 到達し $248D 未到達 | v0.4 でも真因未到達→ 別工程要検討 |

## 8. 確認事項（v0.3 で確定・v0.4 変更なし）

- 変数スコープ: task ローカル
- 代入セマンティクス: 全てブロッキング `=`
- $2626/$2630/$2634 のPC値: HANDOVER_CHAT116.md および現 TB L311-312, L360 のコメントで確定

## 9. v0.3→v0.4 差分の全リスト（レビュー確認用）

- §0: 変更要旨（v0.4 新規セクション）
- §1: 背景を CHAT116 Step I 結論に更新（LDWバグ → JMPバグ）
- §2: 仮説 θ1a/θ1b/θ2/θ3 → θ1/θ2/θ3/θ4 に全面置換
- §3.2 case:
  - `16'h2610:` の dump 開始・エピソード加算・$display "L0140到達"→**削除**（L0140_ent++ のみ残す）
  - `16'h2618:` の dump 停止→**削除**
  - **`16'h2626:` に dump 開始・エピソード加算・$display "$2626 BGE到達" を新規追加**
  - **`16'h2630:` に dump 停止（BGE成立正常経路）を新規追加**（既存 `L0149_ent++` は残す）
  - **`16'h2634:` に dump 停止（JMP正常先）を新規追加**（既存 `L0150_ent++` は残す）
  - `16'h248D:` の BUG検出出力→**変更なし**
- §3.2 毎cyc動作: `k_dump_cnt >= 50` → **`k_dump_cnt >= 100`**
- §3.3: サンプル出力の PC値を $2626/$2629/$262D に更新
- §3.4: 停止条件に $2634, $2630 を追加
- §6: KY-K-add4 追加
- §7: 期待結論表を全面置換

## 10. 参照資料

- v8d_stepK_pcdump_design_memo_v0_1〜v0_3.md（過去版）
- **HANDOVER_CHAT116.md** — Step I 最終結論・Step J 案(1) 観測方針（v0.4 の観測ポイント根拠）
- 過去チャット「FPGA実装の続き(V8-D)」(URL: 3df7c7b6…) Step I デバッグ報告（v0.4 §1 引用元）
- tb_cpu_v8d_dhry_stepJ_jmp.sv — L242「$2627 BGE / $2629 LDW / $262D JMP」・L360「実は $2626 が BGE」（PC値の根拠）
- ysd8800_psram_ctrl_v0_2.sv — L43 (LATENCY_NORMAL=12)・L52-57 (信号名)
- kaizen.txt 原則43（実装前レビュー）・原則57（仮説絞込）
- review_insights_v1_0.docx 原則5.1（実源照合）

## 改版履歴

| 版 | 日付 | 内容 |
|---|---|---|
| v0.1 | 2026-07-25 | 初版。CHAT117 Step K の PC遷移生ダンプ TB 設計。条件付き差戻し。 |
| v0.2 | 2026-07-25 | v0.1 レビュー反映。案K1・PSRAM信号追加・KY追加・Step J統合。条件付き承認。 |
| v0.3 | 2026-07-25 | v0.2 レビュー反映。案C（ブロッキング統一）・$248D dump 後 $finish・LATENCY 準拠サンプル。実装着手済。 |
| **v0.4** | **2026-07-25** | **観測ポイント誤り訂正**。v0.3 で $2610 の LDW に誤設定した仮説を、CHAT116 Step I 最終結論・Step J 案(1) の**$262D JMP _L_0150** に全面訂正。dump 開始 $2610→**$2626 (BGE)**、dump 停止 $2618→**$2634 (JMP正常先)/$2630 (BGE成立)**、観測窓 50→**100cyc**。KY-K-add4 追加（HANDOVER 精読不備の再発防止）。**v0.3 との差分は観測ポイント（PC値）と観測窓のみ**。案K1/案C/PSRAM信号/累計5000行安全弁は v0.3 継承。 |
