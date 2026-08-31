# V8-b 本番 TB 設計書 v0.2 レビュー指摘書

- **文書ID**: v8b_prod_design_memo_v0_2_review_v1_0.md
- **レビュア**: Claude（設計レビュー担当）
- **レビュー対象**: v8b_prod_design_memo_v0_2.md
- **レビュー日**: 2026-07-31
- **前版レビュー**: v8b_prod_design_memo_v0_1_review_v1_0.md（差戻し・必修正5件・補足3件）
- **判定**: **条件付き承認** — v0.1 指摘全反映確認。加えて実源照合による副産物5件（A1〜A5）は設計品質を大きく向上。ただし §3.1 コード例に**実装で即失敗する具体的な誤り3件**（`sd_spi_model_v0_3_poc` のポート・`disk_sectors_i` の幅・`irq_in` 生成ロジック省略）があり、v0.3 で修正必須

---

## 1. 総評

v0.1 レビュー指摘 **全 8 件（必修正5件・補足3件）が完全反映**されている。特に：

- **必修正1（DUT 構造）**：V8-a TB を参考実源として明示採用、CPU コア + membus 別インスタンス化に修正
- **必修正3（M-1 到達 PC）**：`$5100` → `_kstart` = **`$0E00`** に訂正、実源 kernel_v12_8.asm L1330-1331 で確認済
- **必修正5（"123MD" 由来）**：Shell マーカー説を撤回し、**FILEMGR タスクの YUIFS 起動進捗マーカー** に正しく訂正。しかも **v0.1 では気づけなかった "0" プレフィックス**（L2785 の `$30 FILEMGR-PUTC \ '0' SB-LOAD 開始`）まで発見し、期待出力を `"0123MD"`（6バイト）に更新
- **補足6（sd_image.hex サイズ）**：`24,576B` は**ファイルサイズ**、実データは **8,192B（16セクタ）**。原因は「1行3バイト（"XX\n"）× 8,192行 = 24,576」だった、と実源で検証。私も `wc -l /mnt/project/sd_image.hex` = 8,192 で確認済

**加えて実源照合の副産物として §0.2 の A1〜A5 の 5 件の設計改善**は、設計書として単なる指摘対応を超える価値を提供：

- **A3（失敗マーカー 'i'/'g'/'v' の弁別性）**：L2788/2794/2802 で確認済。原則87 の応用として YUIFS 起動失敗を即時識別可能。**優れた発見**
- **A4（ソースコメント信用禁止）**：`WORD_OS_START = $e988` コメントを sym 実測 `$D295` で上書き。v1.3 教訓4「コメント記述と実出力の照合」を実源照合ルールに昇華
- **A5（PSRAM 全域初期化）**：V8-a の 1KB 限定初期化が V8-D の PSRAM 1KB 事故の直接源だったという因果関係の指摘は、原則94 の根本原因への言及

**しかし §3.1 の SystemVerilog コード例に、iverilog でコンパイル即失敗する誤りが 3 件**あります。v0.3 で修正して再レビューを推奨します（実装ブロック）。

---

## 2. 実源照合サマリ

| 実源 | 該当箇所 | v0.2 記述との照合 |
|---|---|---|
| kernel_v12_8.asm | L1330 `.org $0E00` / L1331 `_kstart:` | §4 M-1 判定「`dbg_pc == 16'h0E00`」と**完全一致** |
| kernel_v12_8.asm | L1332 `LDW SP, #$477E` | §7 CL-3「`dbg_sp == 16'h477E`」と**完全一致** |
| kernel_forth_v0_10_18.fs | L2785 `$30 FILEMGR-PUTC \ '0' SB-LOAD 開始` | §1「'0' : SB-LOAD 開始」と**完全一致** |
| kernel_forth_v0_10_18.fs | L2788 `$69 \ 'i' I/O エラー` | §4 失敗マーカー表「i / $69」と**完全一致** |
| kernel_forth_v0_10_18.fs | L2794 `$67 \ 'g' magic 不一致` | §4 失敗マーカー表「g / $67」と**完全一致** |
| kernel_forth_v0_10_18.fs | L2802 `$76 \ 'v' ver_major 不一致` | §4 失敗マーカー表「v / $76」と**完全一致** |
| kernel_forth_v0_10_18.fs | L3398 `SH-CMD0 $76 = IF SH-CMD-VER` | UART RX 経由 'v' シェルコマンド由来の false positive リスクあり（本番は RX なしなので実務上問題なし） |
| /mnt/project/sd_image.hex | ファイルサイズ 24,576B / 行数 8,192 | §3.3「1行3バイト × 8,192 行 = 24,576」と**完全一致** |
| /mnt/project/sd_image.hex | 先頭3バイト `59 55 49` (=YUI) | §3.3 YUIFS マジックの存在を確認 |
| ysd8800_v5_membus_v0_2.sv | L162 `module ysd8800_v5_membus_v0_1` | §3.1「module 名 `_v0_1`」と**完全一致** |
| ysd8800_v5_membus_v0_2.sv | **L197 `input logic [31:0] disk_sectors_i`** | §3.1 の `.disk_sectors_i(16'd16)` と**乖離**（幅は 32bit） |
| sd_spi_model_v0_3_poc.sv | **L41-45 ポート `cs_n / sck / mosi / miso` のみ** | §3.1 の `.clk(psram_clk)` と**乖離**（clk ポート存在せず） |
| tb_cpu_v8catls_poc.sv | L84 `assign irq_in = irq_timer_o ? 3'd1 : (irq1_o ? 3'd2 : 3'd0)` | §3.1 「V8-a の … を踏襲」と記述あるが、**コード例に irq_in 生成ロジック未記載** |
| tb_cpu_v8catls_poc.sv | L131-136 SD インスタンス（cs_n/sck/mosi/miso のみ） | v0.2 §3.1 が乖離している根拠 |
| tb_cpu_v8catls_poc.sv | L278 `disk_sectors_i = 32'd131072` | V8-a では 32bit 幅で代入。v0.2 は 16bit 幅で乖離 |
| ysd8800_cpu_v0_1_FIXED.sv | L586-591, L602-604 リセット状態遷移 | リセット時 state = S_RESET_LO → S_RESET_HI → PC 設定。**「リセット直後 cycle=1 で dbg_pc == $0E00」の想定は成立しない**（軽微・§7 CL-3 の表現に注意） |

**結論**: v0.1 指摘反映と §0.2 副産物発見の**技術的根拠は実源と完全一致**。ただし **§3.1 コード例に iverilog で即エラーになる誤り3件**あり。

---

## 3. 指摘一覧

| # | 区分 | 内容 | 対応 |
|---|---|---|---|
| 1 | **必修正** | §3.1 SD SPI モデルインスタンス化で `.clk(psram_clk)` — **`clk` ポートは実源に存在しない**（cs_n/sck/mosi/miso のみ） | 削除。V8-a L131-136 と同じ形式に |
| 2 | **必修正** | §3.1 `.disk_sectors_i(16'd16)` — 実源は **32bit 幅** (`input logic [31:0]`) | `32'd16` に修正 |
| 3 | **必修正** | §3.1 `irq_in` 生成ロジックがコード例に**未記載**（コメントでは V8-a 踏襲と言及のみ） | `assign irq_in = irq_timer_o ? 3'd1 : (irq1_o ? 3'd2 : 3'd0);` を明示 |
| 4 | 補足 | §7 CL-3「リセット直後（`_kstart` 実行前）: `dbg_pc == 16'h0E00`」の「リセット直後」表現は、CPU リセット状態遷移（S_RESET_LO → S_RESET_HI → 実行）と齟齬 | 「リセットベクタ読出完了後・`_kstart` 実行前」に修正 |
| 5 | 補足 | §4 失敗マーカー 'v' は SH-CMD-VER の起動先頭文字（L3398）としても使われる。本番は UART RX なしなので実務上問題ないが、将来 RX 刺激追加時に false positive リスクあり | v0.3 §4 失敗マーカー表に注記追加：「UART RX なし前提で有効」 |

---

## 4. 指摘1（必修正）: §3.1 SD SPI モデルの `.clk` ポート誤記

### 4.1 該当箇所

v0.2 §3.1 コード例（L124-128）:

```systemverilog
// --- 補助 1: SD SPI モデル ---
sd_spi_model_v0_3_poc u_sd (
    .clk(psram_clk),
    .cs_n(spi_cs_n_o), .sck(spi_sck_o),
    .mosi(spi_mosi_o), .miso(spi_miso_i)
);
```

### 4.2 実源事実

**sd_spi_model_v0_3_poc.sv L41-45**（原文引用）:

```systemverilog
module sd_spi_model_v0_3_poc (
    input  logic cs_n,     // チップセレクト（0=選択）
    input  logic sck,      // SPIクロック（ホスト生成）
    input  logic mosi,     // Master Out Slave In（ホスト→カード）
    output logic miso      // Master In Slave Out（カード→ホスト）
);
```

**`clk` ポートは存在しない**。SD SPI モデルは `sck` を CPU 側から受け取り、内部同期は `sck` エッジで駆動される（SPI モデルとして正しい設計）。

**tb_cpu_v8catls_poc.sv L131-136**（V8-a 実源）:

```systemverilog
sd_spi_model_v0_3_poc sdmodel (
    .cs_n (spi_cs_n_o),
    .sck  (spi_sck_o),
    .mosi (spi_mosi_o),
    .miso (spi_miso_i)
);
```

### 4.3 修正提案

v0.3 §3.1 コード例を V8-a と同じ形に：

```systemverilog
sd_spi_model_v0_3_poc u_sd (
    .cs_n (spi_cs_n_o),
    .sck  (spi_sck_o),
    .mosi (spi_mosi_o),
    .miso (spi_miso_i)
);
```

### 4.4 影響

**このまま実装すると iverilog コンパイル時に「port `clk` not found」エラーで即失敗**。TB が起動すらしない。実装ブロッカー。

---

## 5. 指摘2（必修正）: §3.1 `disk_sectors_i` のビット幅ミスマッチ

### 5.1 該当箇所

v0.2 §3.1（L120）:

```systemverilog
.disk_sectors_i(16'd16)  // 16 セクタ = 8KB
```

### 5.2 実源事実

**ysd8800_v5_membus_v0_2.sv L197**（原文引用）:

```systemverilog
input  logic [31:0] disk_sectors_i,   // SD容量(セクタ数)
```

ポートは **32bit 幅**。v0.2 は **16bit リテラル**を接続している。

**tb_cpu_v8catls_poc.sv L79, L278**（V8-a 実源）:

```systemverilog
logic [31:0] disk_sectors_i;
...
disk_sectors_i  = 32'd131072;
```

V8-a では 32bit で代入。

### 5.3 修正提案

`32'd16` に修正。

```systemverilog
.disk_sectors_i(32'd16)  // 16 セクタ = 8KB
```

### 5.4 影響

iverilog は通常 warning で通すが、**幅ミスマッチによる意図せぬ動作**（上位ビットが x/0 のどちらになるかシミュレータ依存）が発生しうる。ビット幅は明示的に合わせるのが SV の作法。

---

## 6. 指摘3（必修正）: §3.1 `irq_in` 生成ロジックの省略

### 6.1 該当箇所

v0.2 §3.1（L102）:

```systemverilog
.irq_in(irq_in),
```

および L132 のコメント：

```
- **IRQ 結合**：V8-a の `assign irq_in = irq_timer_o ? 3'd1 : (irq1_o ? 3'd2 : 3'd0);` を踏襲
```

### 6.2 懸念

- コード例では `.irq_in(irq_in)` と接続しているだけで、**`irq_in` の生成ロジック**（assign 文）が抜けている
- コメントで V8-a を踏襲すると書いているだけで、**具体的な代入文がコード例に含まれない**
- 実装時に見落とすと、`irq_in` が未定義（logic wire だが assign なし）で、常に x のまま。CPU が割込を受理せずタイマーが機能しない

### 6.3 実源事実

**tb_cpu_v8catls_poc.sv L84**（V8-a 実源）:

```systemverilog
assign irq_in = irq_timer_o ? 3'd1 : (irq1_o ? 3'd2 : 3'd0);
```

### 6.4 修正提案

v0.3 §3.1 コード例に irq_in 生成ロジックを明示追加：

```systemverilog
// --- 内部信号（IRQ 結合） ---
logic [2:0] irq_in;
assign irq_in = irq_timer_o ? 3'd1 : (irq1_o ? 3'd2 : 3'd0);

// --- DUT 1: CPU コア (無改修) ---
ysd8800_cpu_v0_1 dut_cpu (
    .clk(cpu_clk), .rst_n(cpu_rst_n),
    ...
    .irq_in(irq_in),
    ...
);
```

### 6.5 影響

- irq_in 未定義 → タイマー割込が到達せず → **kernel v12.8 のスケジューラが起動しない** → BOOT-MSG 到達不可
- Phase-2 で M-3 未到達となり FAIL するが、原因が「TB の irq_in 未定義」なのか「実際のスケジューラ挙動異常」なのか切り分けが困難

---

## 7. 指摘4（補足）: §7 CL-3「リセット直後」表現の曖昧さ

### 7.1 該当箇所

v0.2 §7 CL-3（原文引用）:

> **リセット直後**（`_kstart` 実行前）: **`dbg_pc == 16'h0E00`**、`_kstart` 実行後（数 cycle 後）: **`dbg_sp == 16'h477E`**

### 7.2 実源事実

**ysd8800_cpu_v0_1_FIXED.sv L586-591**（リセット状態遷移・原文引用）:

```systemverilog
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        state <= S_RESET_LO;
    else
        state <= next_state;
end
```

**L602-604**（リセットベクタ読出）:

```systemverilog
case (state)
    // --- リセットベクタ読み(2byte) ---
    S_RESET_LO: begin
        if (mem_ready) next_state = S_RESET_HI;
    end
```

**リセット解除後の流れ**：
1. cycle=1: state = S_RESET_LO、PC 未確定
2. cycle=n (mem_ready 待ち): リセットベクタの下位バイト読出
3. cycle=m: S_RESET_HI、上位バイト読出
4. cycle=k: PC = リセットベクタ ($0E00) が設定される

**「リセット直後」に `dbg_pc == $0E00` は成立しない**（リセットベクタ読出待ちの間は PC 未確定）。

### 7.3 修正提案

v0.3 §7 CL-3 の表現を以下に修正：

> **リセットベクタ読出完了後（`_kstart` 実行前）**: `dbg_pc == 16'h0E00`
> **`_kstart` 実行後（`LDW SP, #$477E` 完了後）**: `dbg_sp == 16'h477E`

実装時は「`dbg_pc == 16'h0E00` を最初に検出した cycle」で assert する形（M-1 の判定と同じロジックで CL-3 assert を行う）が実装しやすい。

### 7.4 影響

**軽微**。M-1 の判定ロジックが「dbg_pc == $0E00 になった cycle を検出」する形で書かれれば、CL-3 assert もそこに紐付けられる。**実装ブロッカーではない**が、TB 実装時の混乱を避けるための記述精度化。

---

## 8. 指摘5（補足）: §4 失敗マーカー 'v' の false positive 注記

### 8.1 該当箇所

v0.2 §4 失敗マーカー表（原文引用）:

> | `'v'` | $76 | ver_major 不一致 | image version と kernel v12.8 の想定不一致 |

### 8.2 懸念

**kernel_forth_v0_10_18.fs L3398**（原文引用）:

```
SH-CMD0 $76 = IF SH-CMD-VER EXIT THEN                        \ 'v' ver
```

`'v'` は **UART RX で受信したシェルコマンドの先頭文字**としても使われる。Shell の入力エコー（RX 経由の 'v' が Shell 内でエコーバックされる場合）で TX に 'v' が出現する可能性。

### 8.3 実務上の判断

v0.2 §3.1 で `.uart_rx_valid_i(1'b0)` と設定（本番は UART RX なし）。**RX なし前提なら Shell コマンドは発生せず、TX の 'v' は FILEMGR の ver_major 不一致マーカーに限定**。

したがって v0.2 の判定は妥当。ただし将来 UC-1 の議論で **RX 刺激追加**する場合、失敗マーカー判定に false positive が入り込む懸念がある。

### 8.4 修正提案

v0.3 §4 失敗マーカー表に注記追加：

> **注記（v0.3 追加）**：本表の判定は `uart_rx_valid_i = 1'b0`（本番 idle）前提で有効。将来 RX 刺激を追加する場合、`'v'` は Shell コマンド（SH-CMD-VER の入力エコー）由来の可能性があり、判定条件の再検討が必要。'i'/'g' はコマンドとしては未使用のため RX 追加後も判定有効。

### 8.5 影響

現状の本番 TB では実務上問題なし。**将来の UC-1 対応時の注意喚起**として設計書に注記を残す価値あり。

---

## 9. 承認条件

**判定: 条件付き承認**

**必修正（v0.3 必達・実装着手前）:**

- 指摘1: §3.1 SD SPI モデルの `.clk(psram_clk)` を削除、V8-a と同じ 4 ポートのみに
- 指摘2: §3.1 `.disk_sectors_i` を `32'd16` に修正
- 指摘3: §3.1 に `irq_in` 生成ロジックを明示的に追加

**推奨修正（v0.3 対応推奨・実装ブロックなし）:**

- 指摘4: §7 CL-3 の「リセット直後」を「リセットベクタ読出完了後」に修正
- 指摘5: §4 失敗マーカー表に「UART RX なし前提で有効」の注記追加

**実装着手について:**

- v0.3 で必修正 3 件を反映した上で、TB 実装（`tb_cpu_v8b_prod_v0_1.sv`）に着手可
- v0.3 の再レビューは軽量で済む（コード例の 3 箇所修正のみ）

---

## 10. 特に評価すべき点

### 10.1 実源照合の徹底ぶり

v0.1 レビューの「実源照合15箇所中11箇所で乖離」の指摘を受け、v0.2 では **§0.1 レビュー指摘反映 8 件 + §0.2 副産物発見 5 件、計 13 件を実源根拠付きで確定**。特に：

- **A4「ソースコメント信用禁止・sym 実測値絶対」**：kernel_v12_8.asm L1475 コメントの `$e988` を sym 実測 `$D295` で置換。原則76（実源照合）の運用強化として理想的
- **A5「V8-a の 1KB 限定初期化が V8-D の PSRAM 事故源」**：既存 TB を「単に踏襲」せず、V8-D 事故の根本原因まで遡って改善対象として特定。原則94 の応用として深い

### 10.2 v0.1 の誤記を隠さず記録

v0.2 §0.1 対照表と §3.1/§3.2/§8 の各セクションで **「v0.1 誤記」を明示的に記録**したまま「v0.2 訂正」を並記。設計負債の「直す前に記録」姿勢を、本設計書自体に適用している。原則77 の理想的実践。

### 10.3 期待出力の "0" プレフィックス発見

v0.1 レビュー時、私も L2792-2810 は確認したが L2785 の '0' マーカーには気づかなかった。v0.2 の再照合で **`$30 FILEMGR-PUTC \ '0' SB-LOAD 開始`** を発見し、期待出力を **`"0123MD"`（6バイト）** に更新した点は、レビューを超える発見。M-5 判定文字列がより厳密になり、原則87（弁別能力）がさらに強化された。

### 10.4 失敗マーカー弁別性の追加（A3）

L2788/2794/2802 の失敗マーカー `'i'/'g'/'v'` を発見し、**§6.2 FAIL 判定に「YUIFS 起動失敗の即時識別」を追加**。原則87 の応用として、単に「PASS 判定」だけでなく「FAIL 原因の弁別」まで組み込んだ判定基準は、TB としてのデバッグ効率を大きく向上させる。

### 10.5 §12 レビュー教訓の反映

v0.1 レビュー §10 で提案した「Pre 工程申し送り情報の伝達精度」を §12 として組み込み、以下 4 点の運用改善を明記：

1. 設計書起票前に Pre 工程確定事実一覧の照合
2. ソースコメント信用禁止
3. 実源照合副産物の設計書明示
4. 次回 HANDOVER に「確定した実源事実の項目一覧」を反映依頼

**レビュー教訓を「今回だけ守る」ではなく「今後の運用ルールに昇華する」姿勢**は、原則43 の理想的な回転。

---

## 11. 本レビューでの追記

**教訓（コード例レベルの実源照合の重要性）**: 

v0.2 は「アドレス値・レジスタ初期値・シンボル解決」といったマクロレベルの実源照合を徹底したが、**SystemVerilog コード例のポート接続・ビット幅・assign 文といったミクロレベルの実源照合**は行き届いていなかった。SD SPI モデルの `.clk(psram_clk)` は「V8-a を踏襲」と書きながら実際には V8-a と異なる形になっており、これは「V8-a の TB を実際にコピペで確認していない」ことを示唆する。

**運用強化提案**: 設計書に SystemVerilog コード例を含める場合、**V8-a の該当箇所を diff 感覚で並べて確認**することを推奨。今回のように「V8-a を踏襲」と書きながら実は V8-a と異なるコードになる、というミスを防ぐには、V8-a の該当行を設計書の付録に転記して並記するのも一手（少なくとも初版起票時）。

**または、コード例をレビュー前に iverilog でコンパイル（DUT の中身は空 module でよい）してポート接続の syntactic 正当性だけでも確認**する運用も有効。今回の指摘1〜3 はコンパイル一発で全て検出できる。

---

## 12. 参照資料

- v8b_prod_design_memo_v0_2.md（レビュー対象）
- v8b_prod_design_memo_v0_1_review_v1_0.md（前版指摘書・8 件全反映確認）
- **ysd8800_v5_membus_v0_2.sv** L162, L197 (disk_sectors_i 32bit)
- **sd_spi_model_v0_3_poc.sv** L41-45（ポート cs_n/sck/mosi/miso のみ）
- **tb_cpu_v8catls_poc.sv** L79, L84（irq_in 生成）, L131-136（SD インスタンス）, L278（disk_sectors_i 32'd131072）
- **ysd8800_cpu_v0_1_FIXED.sv** L586-591, L602-604（リセット状態遷移）
- **kernel_v12_8.asm** L1330-1332（_kstart / SP 初期化）
- **kernel_forth_v0_10_18.fs** L2785（'0' マーカー）, L2788/2794/2802（失敗マーカー）, L3398（'v' シェルコマンド）
- **/mnt/project/sd_image.hex** ファイルサイズ 24,576B / 行数 8,192 / 先頭 "YUI"
- kaizen.txt 原則43, 76, 87, 94
- review_insights_v1_0.docx 原則5.1

---

## 改版履歴

| 版 | 日付 | 内容 |
|---|---|---|
| v1.0 | 2026-07-31 | 初版。v8b_prod_design_memo_v0_2.md に対するレビュー。v0.1 指摘8件全反映確認・§0.2 副産物5件も妥当。ただし §3.1 コード例に iverilog 即エラー要因3件（SD `.clk` 不在ポート・`disk_sectors_i` 幅・`irq_in` 生成省略）。条件付き承認、v0.3 で必修正3件反映後に実装着手可。 |

— 以上 —
