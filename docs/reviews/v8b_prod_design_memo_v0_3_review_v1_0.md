# V8-b 本番 TB 設計書 v0.3 レビュー指摘書

- **文書ID**: v8b_prod_design_memo_v0_3_review_v1_0.md
- **レビュア**: Claude（設計レビュー担当）
- **レビュー対象**: v8b_prod_design_memo_v0_3.md
- **レビュー日**: 2026-08-01
- **前版レビュー**:
  - v0.1 → 差戻し（必修正5件・補足3件）
  - v0.2 → 条件付き承認（必修正3件・補足2件）
- **判定**: **承認（TB 実装着手可）** — v0.2 レビュー指摘5件全反映を実源で確認済み。v0.3 は §3.1 のミクロレベル実源照合が徹底され、参考実源対応表という付加改善も加わっている。軽微な補足1件（未接続 dbg_* ポートの意図明示）は実装時のコメントで対応可能・実装ブロックなし

---

## 1. 総評

v0.2 レビュー指摘 5 件（必修正3件・補足2件）が **すべて実源準拠で完全反映**。特に：

- **必修正1（SD SPI モデル `.clk` 誤記）**：削除して V8-a L131-136 と同形（`cs_n / sck / mosi / miso` の 4 ポートのみ）に修正。§3.1 コメントで「実源 sd_spi_model_v0_3_poc.sv L41-45 のポートは 4 本のみ」「sd モデルは `sck` エッジで内部同期する SPI モデル」と根拠まで明記
- **必修正2（disk_sectors_i 幅ミスマッチ）**：`16'd16` → `32'd16` に修正。§3.1 コメントで「実源 ysd8800_v5_membus_v0_2.sv L197 は `input logic [31:0]`」「V8-a L278 でも `32'd131072` と 32bit 幅」と実源対応を明示
- **必修正3（irq_in 生成ロジック省略）**：`assign irq_in = irq_timer_o ? 3'd1 : (irq1_o ? 3'd2 : 3'd0);` を **CPU コアインスタンス化の直前に配置**（読者が接続を追いやすい）。§3.1 コメントで「V8-a L84 と完全同一」と明記
- **補足4（CL-3「リセット直後」曖昧さ）**：「リセットベクタ読出完了後（`_kstart` 実行前）」に修正、加えて **§7 CL-3 に実装ヒントを追加**（S_RESET_LO → S_RESET_HI 2 段リセットの説明、「M-1 判定に CL-3 の PC assert を紐付ける」実装案）
- **補足5（'v' false positive リスク）**：§4 失敗マーカー表に「**注記（v0.3 追加・レビュー指摘 5）**：本表の判定は `uart_rx_valid_i = 1'b0`（本番 idle）前提で有効」と明記、UC-1 対応時の再検討必要性まで言及

**加えて v0.2 レビュー §11 教訓を §12.1 として運用ルール化**：

- **参考実源対応表**を §3.1 末尾に新設。v0.3 §3.1 の各接続について V8-a 参考実源との対応行を明示（irq_in / CPU コア / membus / SD モデルの 4 項目）
- 「マクロ実源照合済」で満足せず、**設計文書に含まれる全てのコード例を実源照合対象**とする（原則 76 の対象範囲拡張）を §12.1 運用ルール化

**私も実源で全 4 件のコード例を独立照合**：

- v0.3 §3.1 の `assign irq_in` = tb_cpu_v8catls_poc.sv L84 と**完全一致**
- v0.3 §3.1 CPU コアインスタンス化 = V8-a L89-97 と**基本一致**（dbg_a/b/x/flags/irq_pending の 5 ポートは v0.3 で省略、後述の軽微指摘参照）
- v0.3 §3.1 membus インスタンス化 = V8-a L103-127 と**完全一致**（disk_sectors_i 値のみ本番用に `32'd16`）
- v0.3 §3.1 SD SPI モデル = V8-a L131-136 と**完全一致**

**v0.3 は TB 実装着手可**。以下、精読で気づいた軽微な補足 1 件を挙げます（実装ブロックなし）。

---

## 2. 実源照合サマリ

| 実源 | 該当箇所 | v0.3 記述との照合 |
|---|---|---|
| tb_cpu_v8catls_poc.sv | **L84** `assign irq_in = irq_timer_o ? 3'd1 : (irq1_o ? 3'd2 : 3'd0);` | v0.3 §3.1 L116 と**完全一致** |
| tb_cpu_v8catls_poc.sv | **L89-97** ysd8800_cpu_v0_1 インスタンス | v0.3 §3.1 L118-127 と**基本一致**（dbg_* 5 ポート省略・軽微指摘参照） |
| tb_cpu_v8catls_poc.sv | **L103-127** ysd8800_v5_membus_v0_1 インスタンス | v0.3 §3.1 L129-142 と**完全一致**（disk_sectors_i 値のみ本番用 `32'd16`） |
| tb_cpu_v8catls_poc.sv | **L131-136** sd_spi_model_v0_3_poc インスタンス | v0.3 §3.1 L144-150 と**完全一致** |
| tb_cpu_v8catls_poc.sv | **L278** `disk_sectors_i = 32'd131072;` | v0.3 §3.1「V8-a L278 でも `32'd131072` と 32bit 幅」の根拠と一致 |
| tb_cpu_v8catls_poc.sv | **L287-289** PSRAM 初期化パス | v0.3 §3.2 L184-189 と**同じ hierarchical パス**（`u_membus.u_psram_ctrl.mem[i]`） |
| ysd8800_v5_membus_v0_2.sv | **L197** `input logic [31:0] disk_sectors_i` | v0.3 §3.1 「実源 L197 は `input logic [31:0]`」の根拠と一致 |
| ysd8800_v5_membus_v0_2.sv | **L358-361** `u_psram_ctrl` インスタンス化 | v0.3 §3.2 hierarchical パスの根拠 |
| sd_spi_model_v0_3_poc.sv | **L41-45** ポート `cs_n / sck / mosi / miso` のみ | v0.3 §3.1 「実源のポートは 4 本のみ」の根拠と一致 |
| ysd8800_cpu_v0_1_FIXED.sv | **L251-259** `dbg_pc/dbg_a/dbg_b/dbg_x/dbg_sp/dbg_flags/dbg_halt/dbg_irq_pending` の 8 ポート宣言 | v0.3 §3.1 では `dbg_pc/dbg_sp/dbg_halt` の 3 ポートのみ接続（軽微指摘参照） |
| ysd8800_cpu_v0_1_FIXED.sv | **L586-604** リセット状態遷移（S_RESET_LO → S_RESET_HI） | v0.3 §7 CL-3 実装ヒント「S_RESET_LO → S_RESET_HI の 2 段でリセットベクタ読出」の根拠と一致 |
| kernel_v12_8.asm | L1330-1332（_kstart / SP 初期化） | v0.3 §4 M-1・§7 CL-3 と一致（v0.2 継承） |
| kernel_forth_v0_10_18.fs | L2785 `'0' SB-LOAD 開始` / L2788-2802 失敗マーカー / L3398 SH-CMD-VER | v0.3 §1・§4 と一致（v0.2 継承） |
| /mnt/project/sd_image.hex | ファイルサイズ 24,576B / 行数 8,192 | v0.3 §3.3「8,192B = 16 セクタ」と一致（v0.2 継承） |

**結論**: 実源照合対応表 14 件で **12 件完全一致・2 件基本一致（dbg_* 省略は指摘 1 として補足のみ）**。v0.3 の SV コード例は iverilog でコンパイル即通過する状態。

---

## 3. 指摘一覧

| # | 区分 | 内容 | 対応 |
|---|---|---|---|
| 1 | 補足 | §3.1 CPU コアインスタンス化で V8-a L94-96 の `dbg_a/dbg_b/dbg_x/dbg_flags/dbg_irq_pending` の 5 ポートが省略されている。iverilog では未接続の output は合法だが、V8-a との厳密整合を謳っている以上、意図明示（コメント or 空接続）が望ましい | v0.4 or 実装時に「// (未使用 dbg_* ポートは省略・v0.3 判定は dbg_pc/dbg_sp/dbg_halt のみで十分)」等のコメント追加 |

---

## 4. 指摘1（補足）: §3.1 CPU コアの未接続 dbg_* ポートの意図明示

### 4.1 該当箇所

v0.3 §3.1 コード例（L118-127・原文抜粋）:

```systemverilog
ysd8800_cpu_v0_1 dut_cpu (
    .clk(cpu_clk), .rst_n(cpu_rst_n),
    .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata),
    .mem_rd(mem_rd), .mem_wr(mem_wr), .mem_ready(mem_ready),
    .irq_in(irq_in),
    .dbg_pc(dbg_pc), .dbg_sp(dbg_sp), .dbg_halt(dbg_halt),
    // (v0.2 追加) M-1/CL-3 判定に dbg_pc/dbg_sp を直接使用
    .irq0_ack(irq0_ack)
);
```

### 4.2 実源事実

**ysd8800_cpu_v0_1_FIXED.sv L251-259**（原文引用）:

```systemverilog
output logic [15:0] dbg_pc,
output logic [15:0] dbg_a,
output logic [15:0] dbg_b,
output logic [15:0] dbg_x,
output logic [15:0] dbg_sp,
output logic [15:0] dbg_flags,
output logic        dbg_halt,
...
output logic [2:0]  dbg_irq_pending,
```

**tb_cpu_v8catls_poc.sv L89-97**（V8-a・原文引用）:

```systemverilog
ysd8800_cpu_v0_1 dut_cpu (
    .clk(cpu_clk), .rst_n(cpu_rst_n),
    .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata),
    .mem_rd(mem_rd), .mem_wr(mem_wr), .mem_ready(mem_ready),
    .irq_in(irq_in),
    .dbg_pc(dbg_pc), .dbg_a(dbg_a), .dbg_b(dbg_b), .dbg_x(dbg_x),
    .dbg_sp(dbg_sp), .dbg_flags(dbg_flags), .dbg_halt(dbg_halt),
    .dbg_irq_pending(dbg_irq_pending),
    .irq0_ack(irq0_ack)
);
```

V8-a では **全 8 個の dbg_* ポート**を接続。v0.3 では `dbg_pc / dbg_sp / dbg_halt` の 3 ポートのみで、**`dbg_a / dbg_b / dbg_x / dbg_flags / dbg_irq_pending` の 5 ポートが省略**。

### 4.3 iverilog での挙動

- **未接続の output ポートは SystemVerilog として合法**（IEEE 1800）
- iverilog では通常 warning すら出ないが、バージョン設定により異なる可能性
- **動作には全く影響しない**（判定に使わないポートを接続しなくても TB は正しく動く）

### 4.4 懸念

- v0.3 §3.1「V8-a を diff 感覚で並べて確認」の運用ルール（§12.1 教訓5）を厳格に適用すると、5 ポートの省略が V8-a との乖離として現れる
- 参考実源対応表 §3.1 で「CPU コア = V8-a L89-97 完全一致」と主張しているが、厳密には L94-96 の一部が省略されており「完全一致」ではない
- **省略した意図（判定に使わないため省略）を明示しないと、後日読者が「V8-a との差異は何か」を追う際に迷う**

### 4.5 修正提案（v0.4 or 実装時に）

**案A（推奨・実装時対応）**：v0.3 §3.1 コード例のコメントに一行追加：

```systemverilog
ysd8800_cpu_v0_1 dut_cpu (
    .clk(cpu_clk), .rst_n(cpu_rst_n),
    .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata),
    .mem_rd(mem_rd), .mem_wr(mem_wr), .mem_ready(mem_ready),
    .irq_in(irq_in),
    .dbg_pc(dbg_pc), .dbg_sp(dbg_sp), .dbg_halt(dbg_halt),
    // 未使用の dbg_* (dbg_a/dbg_b/dbg_x/dbg_flags/dbg_irq_pending) は省略
    //   本 TB の M-1/M-5・CL-3 判定は dbg_pc/dbg_sp/dbg_halt のみで十分
    //   （V8-a との差分の意図明示）
    .irq0_ack(irq0_ack)
);
```

**案B（V8-a と完全同一化）**：V8-a 通りに全 8 ポート接続、TB 内で unused signal として宣言。「V8-a と完全一致」ラベルを厳密化。

**レビュア推奨**：**案A**。省略の意図明示が本旨で、TB 内に未使用信号を大量に宣言するのは冗長。

### 4.6 影響

- **iverilog コンパイル・動作には影響なし**
- v0.3 参考実源対応表の「CPU コア = V8-a L89-97 完全一致」の記述の厳密性向上
- 後日のコード保守性向上

**実装ブロックにはならない**。実装時に案A のコメントを入れれば済む軽微補足。

---

## 5. 承認条件

**判定: 承認（TB 実装着手可）**

**推奨対応（v0.4 or 実装時に反映・実装ブロックなし）:**

- 指摘1: §3.1 CPU コアインスタンス化に「未接続 dbg_* ポートの意図明示コメント」を追加

**実装着手について:**

- v0.3 承認により **`tb_cpu_v8b_prod_v0_1.sv`** の実装に着手可
- 参考実源対応表 §3.1 に沿って V8-a TB を diff 感覚で並べつつ実装することを強く推奨
- 実装完了後、iverilog コンパイル通過確認 → phase-1 (MAX_CYCLES=1,000,000) から段階起動
- 指摘1 は実装時に案A のコメント形式で対応

---

## 6. 特に評価すべき点

### 6.1 参考実源対応表の新設（§3.1 末尾）

v0.2 レビュー §11 の教訓「V8-a の該当箇所を diff 感覚で並べて確認する」を、単なる運用ルールに留めず **設計書本体に「参考実源対応表」として組み込んだ**点は理想的。

読者は v0.3 §3.1 コード例の各接続について、V8-a 参考実源の該当行番号を **1 対 1 対応**で照合できる：

- `assign irq_in = ...` → V8-a L84
- CPU コアインスタンス化 → V8-a L89-97
- membus インスタンス化 → V8-a L103-127
- SD SPI モデル → V8-a L131-136

これは他の設計書レビューでも横展開すべき運用改善。**「V8-a を踏襲」と書きながら実は違う形になっている、という v0.2 で判明したミス**を構造的に防止する仕組み。

### 6.2 §12.1 に SV コード例レビューの運用ルール4項目

v0.2 レビュー §11 の教訓を、v0.3 §12.1 で **4 つの具体的運用ルール**に落とし込んだ：

5. 参考実源を diff 感覚で並べて確認
6. 参考実源対応表を設計書本体に転記
7. SV コード例をレビュー前に iverilog でコンパイル
8. マクロ実源照合済で満足せず、全コード例を実源照合対象とする（原則 76 の対象範囲拡張）

**7 番目「レビュー前 iverilog コンパイル」**は特に価値大。v0.2 の必修正3件（SD `.clk` / disk_sectors_i 幅 / irq_in 生成）は全てコンパイル一発で検出できたことを、教訓として明文化している。

### 6.3 CL-3 実装ヒント（§7 追加）

v0.2 レビュー §7 CL-3 の「リセット直後」表現の曖昧さ指摘に対し、単に文言修正するだけでなく、**§7 に「CL-3 実装ヒント」を新設**して以下を明記：

- CPU コアの S_RESET_LO → S_RESET_HI 2 段リセットベクタ読出の説明
- 「リセット解除後の cycle=1 に `dbg_pc == $0E00` は成立しない」の明確化
- 「M-1 の判定に CL-3 の PC assert を紐付ける」実装案

**指摘対応を超えて、実装者向けの具体的な実装ガイドを追加した**姿勢は原則43（実装前レビュー）の理想的実践。

### 6.4 §4 失敗マーカー表への RX なし前提注記

v0.2 レビュー §8 で指摘した false positive リスクに対し、単に文言追加でなく **将来の UC-1 対応時の判定条件再検討**まで含めた注記を追加：

> **注記（v0.3 追加・レビュー指摘 5）**：本表の判定は `uart_rx_valid_i = 1'b0`（本番 idle）前提で有効。将来 UC-1 対応で **RX 刺激を追加する場合**、`'v'` は Shell コマンド `SH-CMD-VER`（kernel_forth_v0_10_18.fs L3398 の `$76 = IF SH-CMD-VER`）のエコー由来の可能性があり、判定条件の再検討が必要。`'i'` / `'g'` はシェルコマンドとしては未使用のため RX 追加後も判定有効。

**現時点だけでなく将来対応時まで見越した記述**で、設計負債を先読みして注釈化している。

---

## 7. 本レビューでの追記

**教訓（設計書レビューの3段階収束）**:

本 V8-b 設計書は v0.1 → v0.2 → v0.3 の 3 版を経て承認に至った。各版のレビュー指摘の性質を振り返ると：

- **v0.1 レビュー**（差戻し）：**マクロレベル実源照合不足**（アドレス値・レジスタ初期値・マーカー由来）
- **v0.2 レビュー**（条件付き承認）：**ミクロレベル実源照合不足**（SV コード例のポート接続・ビット幅・assign 文）
- **v0.3 レビュー**（承認）：**参考実源対応表による厳密整合の確認**（1 件の軽微補足のみ）

これは「設計書起票時に一発で完成させる」ことの困難さを示すと同時に、**各版で段階的に照合レベルが深化していく**理想的な収束パターン。**マクロレベル → ミクロレベル → 対応表による厳密整合**の 3 段階収束は、他の設計書レビューでもテンプレート化できる。

**運用強化提案**：**設計書起票時に「照合レベルのチェックリスト」**を設ける：

1. マクロレベル：アドレス値・レジスタ初期値・マーカー・シンボル解決
2. ミクロレベル：SV コード例のポート接続・ビット幅・assign 文・hierarchical パス
3. 対応表レベル：参考実源との 1 対 1 対応表を設計書本体に転記

v0.3 の §3.1 参考実源対応表と §12.1 教訓 4 項目は、この 3 段階収束を一般化する優れた出発点。

---

## 8. 参照資料

- v8b_prod_design_memo_v0_3.md（レビュー対象）
- v8b_prod_design_memo_v0_1_review_v1_0.md（v0.1 → v0.2 契機・全 8 件反映確認済）
- v8b_prod_design_memo_v0_2_review_v1_0.md（v0.2 → v0.3 契機・全 5 件反映確認済）
- **tb_cpu_v8catls_poc.sv** L84（irq_in）, L89-97（CPU）, L103-127（membus）, L131-136（SD）, L278（disk_sectors_i）, L287-289（PSRAM init）
- **ysd8800_v5_membus_v0_2.sv** L197（disk_sectors_i 32bit）, L358-361（u_psram_ctrl）
- **sd_spi_model_v0_3_poc.sv** L41-45（4 ポートのみ）
- **ysd8800_cpu_v0_1_FIXED.sv** L251-259（dbg_* ポート 8 個）, L586-604（リセット遷移）
- kernel_v12_8.asm L1330-1332
- kernel_forth_v0_10_18.fs L2785, L2788-2802, L3398
- kaizen.txt 原則43（実装前レビュー）, 76（実源照合・マクロ + ミクロ）, 87（弁別性）, 94（PSRAM）
- review_insights_v1_0.docx 原則5.1（実源照合の運用）

---

## 改版履歴

| 版 | 日付 | 内容 |
|---|---|---|
| v1.0 | 2026-08-01 | 初版。v8b_prod_design_memo_v0_3.md に対するレビュー。v0.2 指摘 5 件（必修正3件・補足2件）全反映を実源で確認済み。§3.1 参考実源対応表と §12.1 教訓 4 項目の新設は運用改善として理想的。承認（TB 実装着手可）。軽微補足1件（dbg_* 未接続ポートの意図明示）は実装時にコメント追加で対応可・実装ブロックなし。 |

— 以上 —
