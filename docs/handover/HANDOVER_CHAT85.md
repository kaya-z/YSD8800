# HANDOVER_CHAT85.md

- 作成日: 2026-07-12
- 前チャット: CHAT85（FPGA V4 = YSD8001 UART / S4完了・S5(a)(b)完了）
- 次チャット: CHAT86
- 中断理由: 計画的区切り（ログ長大化を避けるため。HANDOVER_CHAT84 §10.3 の方針通り）

---

## 0. 次チャットの最優先事項

### 0.1 S5(c) — RX/IRQ の CPU結合検証（★真のゲートの残り★）

S5(a)(b) は ALL PASS したが、**HANDOVER_CHAT84 §8 の計画のうち #3〜#6 が未実施**である。
現状の (b) は **TB が `irq1_o` を直接覗いているだけ**で、CPUプログラムを通していない。
レビュー §7 の「真のゲート」要件を**完全には満たしていない**。

### 0.2 ★申し送り（CHAT84 から継続・未実施）★

`emu23_device_design` v1.4 → v1.5 改版：

> 確定設計#1 を「RX/STOR=1クロックパルス、**TX=レベル**（TDRE方式のため例外）」に改訂したことを
> `emu23_device_design` の次回改版で明文化のこと（**KY41: 旧記述は取消線で保持**）。

S6（文書改版）で実施。

---

## 1. V4 の進捗状況

| Step | 内容 | 状態 |
|---|---|---|
| S1 | 設計メモ作成 → レビュー → 承認 | ✅ 完了 |
| S2 | YSD8001 RTL 実装 | ✅ 完了 |
| S3 | YSD8001 単体TB | ✅ 完了（31/31 ALL PASS・★本チャットで再現確認済★） |
| **S4** | MMIOスタブv0.4 / membus v4 統合 ＋ 全回帰 | ✅ **完了（32/32 ALL PASS）** |
| **S5(a)** | CPU結合TB・TX/STAT系 emu23協調等価 | ✅ **完了（7/7 PASS）** |
| **S5(b)** | CPU結合TB・RX/IRQ 物理層プロパティ | ✅ **完了（2/2 PASS）** |
| **S5(c)** | **CPU結合TB・RX/IRQ ハンドラ経由検証** | 🔧 **未着手（次チャット）** |
| S6 | 文書改版 | ⬜ 未着手（別チャット推奨） |

---

## 2. ★S4 回帰結果（V4構成・デグレなし）★

| TB | ベクタ数 | 結果 |
|---|---|---|
| `tb_cpu_v4regress_poc` | 20/20 | ✅ ALL PASS |
| `tb_cpu_v4mem_poc` | 5/5 | ✅ ALL PASS |
| `tb_cpu_v4boundary_poc` | 1/1 | ✅ ALL PASS |
| `tb_cpu_v4mmu_v0_1` | 6/6 | ✅ ALL PASS |
| **合計** | **32/32** | ✅ |

- **ビルド警告 0件**（未接続ポートなし → 偽合格の余地なし）
- ベクタ数が V3.5 時点と完全一致（TBが空回りしていない証明）
- `boundary` で `MMIO access count=1 last_addr=fc80` → V4のMMIO経路が実際に叩かれている

**→ YSD8001 を内蔵しても既存機能は不変であることを実証した。**

---

## 3. ★S5(a) 結果（emu23協調等価・7ベクタ ALL PASS）★

| # | ベクタ | 結果 | 意義 |
|---|---|---|---|
| 0 | `UART_STAT_READ` | A=0001 | **KY45 実証**（リセット値 0x01） |
| 1 | `UART_TX_BASIC` | B=0000 | TX書込後 TX_READY=0 |
| 2 | `UART_TX_RECOVER` | B=0001 | 4167クロック後 TX_READY=1 復帰 |
| 3 | `UART_TX_TWICE` | B=0000 | TX 2回連続送信 |
| 4 | `UART_STAT_WTC_NOP` | B=0001 | W2C(bit1) は RX_READY未セット時 無害 |
| 5 | `UART_STAT_WTC_BIT0_IGNORE` | B=0001 | **bit0書込は完全無視**（TX_READY保持） |
| 6 | `UART_TX_STAT_ALIAS` | B=0000 | **★KY44 決定打★** TX に 0xFF → STAT は 0x00（0xFF に化けない）|

**#6 が PASS したことで、3bitデコードが実際に効いていることが実証された。**
（2bitデコードなら STAT が 0xFF に化けて必ず落ちるベクタ）

---

## 4. ★★本チャットで判明した重要問題（次チャット必読）★★

### 4.1 S5-ISSUE-1: RX のタイミングは emu23 と RTL で構造的に一致しない

**emu23_v109.c L486（実照合）:**
```c
if ((current_cycle & 0xFF) == 0) { poll_rx_fn(); }   // ★256サイクル周期ポーリング★
```

**`-i FILE` を使っても RX 到来サイクルは 256 境界に量子化される。**
RTL の `rx_valid_i` は任意サイクルで打てるため、両者は一致しえない。

**→ RX に「emu23を走らせて最終状態比較」（協調等価）は適用不可。**

**★HANDOVER_CHAT84 §8 の「RX黄金参照は `-i FILE` で決定論的にする」は誤りである。★**
ファイル入力にしても 256サイクル周期ポーリングは残る。

**承認済み代替戦略:**
- (a) TX系・STAT系 → emu23協調等価
- (b)(c) RX系・IRQ系 → **プロパティ検証**（emu23ソースを真実とした仕様アサーション）
  - ただし判定は必ず **「CPUが実命令で読んだ値」**（レジスタ最終値）で行う
  - TB が `rdata_o` を直接覗くのは**禁止**（偽合格防止）
  - → CPU → decoder → mmio_stub → YSD8001 の**全経路**を通す

### 4.2 ★S5-ISSUE-2: emu23 と RTL で「サイクル」の単位系が違う★

| | 単位 | TX_CYCLES=4167 の意味 |
|---|---|---|
| **emu23** | **命令サイクル**（`cpu.cycle` は命令実行カウンタ） | 4167**命令** |
| **RTL** | **クロック**（`tx_cnt_r` は clk ごとにダウンカウント） | 4167**クロック** |

**実測:** TX復帰待ちループの回数が emu23=1043回、RTL=58回。**比 ≒ 18 : 1 = 実CPI**。

**→ RTL は仕様通り。「TX完了までのループ回数 X」を協調等価の比較対象にしたベクタ設計が誤りだった。**
**→ S5(a) では X を比較対象から除外し、A/B/F のみ比較している。**

**★これは V5(タイマー YSD8002) で必ず再発する問題である。★**
タイマーも emu23 はサイクル基準でカウントする。**V5 設計時に必ず単位系を明示すること。**

### 4.3 ★S5-ISSUE-3: 回帰TBの初期化シーケンスは順序が本質的制約★

**新規TBを `do_reset()` のような便利タスクに包んだ結果、偽合格と真の失敗を同時に引き起こした。**

**既存の通っているTB（`tb_cpu_v3_v0_1` 系）の正しい順序:**
```systemverilog
cpu_rst_n = 0;                                   // (0) ★リセット保持★
for (int i=0; i<16'h0200; i++) mem[i] = 8'h00;   // (1) ★メモリ 0x00 クリア★
$readmemh("xxx.hex", u_membus.u_psram_ctrl.mem); // (2) プログラムロード
repeat (3) @(negedge cpu_clk);
cpu_rst_n = 1;                                   // (3) ★ロード完了後に★リセット解除
```

**誤った順序で何が起きたか:**
- `do_reset()` を先に呼ぶ → CPU が空メモリを fetch し始める
- `$readmemh` は 265語しか埋めない → **それ以前の領域が X（不定）のまま**
- CPU は PC=0x0000 から **X を fetch** してハング（`mmio_access_count=0` が証拠）
- **★2番目以降のベクタは「前ベクタのメモリ内容が残っていた」ため偽合格した★**

---

## 5. 本チャットで登録した KY

| KY# | 内容 |
|---|---|
| **KY49** | **HANDOVER に「完成」と書かれていても、プロジェクトナレッジへの登録漏れがありうる**。<br>実際、`ysd8800_ysd8001_v0_1.sv`（DUT本体）が未登録で S4 が実行不能だった。<br>→ **チャット冒頭で HANDOVER の成果物テーブルに載る全ファイルの `ls` 実在確認を行う**（kaizen原則64 の実例再発） |
| **KY50** | **「黄金参照と協調等価をとる」前に、【比較する量の単位系が一致しているか】を必ず確認する**。<br>emu23 の「サイクル」は命令サイクル、RTL の「サイクル」はクロック。**実CPI(約18)の分だけズレる**。<br>→ サイクル数・ループ回数・タイムアウト値は**協調等価の比較対象にしてはならない** |
| **KY51** | **新規TBを作る際、既存の通っているTBの初期化シーケンスを【逐語的に踏襲】せよ**。<br>`do_reset()` のような便利タスクに包むと、**「順序」という本質的制約が隠れる**。<br>特に「メモリクリア → ロード → リセット解除」の順序は絶対。 |
| **KY52** | **`$readmemh` は指定語数しか埋めない。残りは X のまま**。<br>→ ロード前に**必ず対象領域を 0x00 クリア**すること。<br>→ さらに**2番目以降のベクタは前ベクタの残存内容で偽合格する**ので、毎回クリアする |
| **KY53** | **Python `subprocess` で emu23 を呼ぶ際は `stdin=subprocess.DEVNULL` と `errors='replace'` を必ず付ける**。<br>・stdin 未指定 → emu23 の RX ポーリングが親の stdin を読んでブロック<br>・`text=True` のみ → TX出力に 0xFF 等が混じると **`UnicodeDecodeError`**<br>★「タイムアウトに見えたが実は UnicodeDecodeError だった」という誤診を実際に犯した★ |

---

## 6. 成果物（★全てプロジェクトナレッジ登録が必要★）

| ファイル | 内容 | 状態 |
|---|---|---|
| `ysd8800_ysd8001_v0_1.sv` | **YSD8001 UART RTL** | ✅ **★CHAT84で登録漏れ。本チャットで再取得・S3再現確認済(31/31)★** |
| `tb_cpu_v4uart_v0_1.sv` | **S5 CPU結合TB**（(a)7ベクタ + (b)2チェック） | ✅ 完成（9/9 ALL PASS） |
| `gen_v4_uart_vectors.py` | S5(a) 協調等価ベクタ生成（emu23自動実行） | ✅ 完成 |
| `mk_v4_regress_tb.py` | V3.5回帰TB → V4 membus 用への機械変換 | ✅ 完成 |
| `tb_cpu_v4regress_poc.sv` | V4回帰TB（20ベクタ・自動生成） | ✅ ALL PASS |
| `tb_cpu_v4mem_poc.sv` | V4回帰TB（5ベクタ・自動生成） | ✅ ALL PASS |
| `tb_cpu_v4boundary_poc.sv` | V4回帰TB（1ベクタ・自動生成） | ✅ ALL PASS |
| `tb_cpu_v4mmu_v0_1.sv` | V4回帰TB（6ベクタ・自動生成） | ✅ ALL PASS |
| `run_v4_regress.sh` | V4回帰一括実行スクリプト | ✅ 完成 |
| `tb_v4_hang_diag_poc.sv` | S5-ISSUE-3 診断用PoC（KY38） | ✅ 役目終了 |

---

## 7. S5(c) の検証ベクタ計画（次チャット）

**★判定は必ず「CPUが実命令で読んだ値」で行う。TBが rdata_o を直接覗かない。★**

| # | 名称 | 内容 | 期待値 |
|---|---|---|---|
| c1 | `UART_RX_READ` | TBが `rx_valid_i` で 0x5A 注入 → CPUが `$FC82` を LDB | A=0x005A |
| c2 | `UART_RX_NO_SIDE_EFFECT` | `$FC82` を**2回**読む → 2回目も同じ値。かつ `$FC84` の RX_READY=1 のまま | A=0x005A, B=0x0003 |
| c3 | `UART_STAT_WTC_RX` | RX_READY=1 → `$FC84` に 0x02 書込 → RX_READY のみクリア | B=0x0001 (TX_READY残) |
| c4 | `UART_RX_OVERRUN` | 0x5A 注入 → **クリアせずに** 0xA5 注入 → `$FC82` は **0x5A のまま**（先着優先） | A=0x005A |
| c5 | `UART_RX_IRQ_HANDLER` | RX割込 → IRQ1 → ハンドラ → `$FC82`読 → `$FC84` W2C → IRET | ハンドラ実行痕跡 |
| c6 | `UART_TX_IRQ_TDRE` | IRQ_MASK bit2 クリア → **TX_READY=1 の間 IRQ1 がアサートされ続ける**（レベル） | 再入確認 |

### ★TB側でのRX注入方法（確立済み）★

```systemverilog
task automatic rx_inject(input logic [7:0] d);
    @(negedge cpu_clk);
    uart_rx_data_i  = d;
    uart_rx_valid_i = 1'b1;
    @(negedge cpu_clk);
    uart_rx_valid_i = 1'b0;   // ★1クロックパルス★
endtask
```

**★注入タイミングの制御が課題★**
CPUプログラムが `$FC82` を読む**前に**注入する必要がある。
案: プログラム冒頭に長めのNOPループを入れ、TB は所定サイクル後に注入する。
（emu23 との協調等価は取らないので、TB が自由にタイミングを決めてよい）

### ★c6（TDRE）の注意★

`irq_tx_o` は**レベル信号**（`assign irq_tx_o = stat_r[BIT_TX_READY];`）。
IRQ_MASK bit2 をクリアすると **TX_READY=1 の間ずっと IRQ1 がアサートされ続ける**。
W2C しても TX_READY は落ちない（bit0書込は無視）ので、**割込が再入し続ける**。
これが正しい TDRE の挙動である（emu23 L496-499 と等価）。
**ハンドラは「TXするものが無ければ IRQ_MASK bit2 をセットして黙らせる」のが正しい使い方。**

---

## 8. 環境メモ

```bash
apt-get install -y iverilog          # 12.0（毎セッション再インストール）
gcc -O2 -o emu23 emu23_v109.c        # 回帰ベクタ生成に必須

# ベクタ生成（.hex はリポジトリに無い。都度生成）
python3 gen_v2_vectors.py            # -> v2a/
python3 gen_v3_mem_vectors.py        # -> v3mem/
python3 gen_v3_boundary_vectors.py   # -> v3boundary/
python3 gen_v35_mmu_vectors.py       # -> v35mmu/
python3 gen_v4_uart_vectors.py       # -> v4uart/   ★本チャットで新規★

# V4回帰TBの生成（V3.5から機械変換）
python3 mk_v4_regress_tb.py

# 一括回帰
bash run_v4_regress.sh

# iverilog コンパイル順序: decoder を最初に
iverilog -g2012 -s <top> -o out.vvp \
    ysd8800_decoder_v0_1.sv ysd8800_alu_v0_1.sv ysd8800_regfile_v0_1.sv \
    ysd8800_cpu_v0_1_FIXED.sv ysd8800_addr_decoder_v0_1.sv \
    ysd8800_mmu_v0_1.sv ysd8800_cdc_bridge_v0_2.sv ysd8800_psram_ctrl_v0_2.sv \
    ysd8800_ysd8001_v0_1.sv ysd8800_ysd8004_v0_1.sv \
    ysd8800_mmio_stub_v0_4.sv ysd8800_v4_membus_v0_1.sv <tb>.sv

# ★階層パス（実照合済）★
#   PSRAMメモリ: u_membus.u_psram_ctrl.mem
#   （u_psram ではない）

# ★FAIL確認は行頭で厳密に★（サマリ行 "FAIL=0" への偽陽性を避ける）
grep -E "^  FAIL" run.log
```

---

## 9. 改版履歴

| 版 | 日付 | 内容 | 担当 |
|---|---|---|---|
| v1.0 | 2026-07-12 | CHAT85 からの引き継ぎ。**S4 完了（V4全回帰 32/32 ALL PASS・デグレなし）**、**S5(a) 完了（協調等価 7/7）**、**S5(b) 完了（物理層プロパティ 2/2）**。★S5(c)（RX/IRQ の CPU結合検証）が未実施であり、レビュー§7の「真のゲート」要件を完全には満たしていない★。KY49〜KY53 登録。 | Claude |
