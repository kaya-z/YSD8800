# HANDOVER_CHAT83.md

- 文書名: HANDOVER_CHAT83.md
- 版数: v1.0
- 作成日: 2026-07-12
- 前チャット: 「FPGA実装と割り込みコントローラの工程問題」（HANDOVER未作成・ツール書式崩れのため）
- 本チャット: **V3.7（YSD8004 割込コントローラ）実装 — S1〜S6 全完了**
- 次チャット: **V4（UART / YSD8001）着手 ＋ emu23_device_design v1.4 改版**

---

## 0. ★★次チャットで最優先に読むこと★★

### 0.1 ★V3.7 は完了した★

**S1（レビュー）〜S6（文書改版）すべて完了。全TB ALL PASS・デグレゼロ。**

```
YSD8004 → irq1(レベル) → irq_in=2 → vec=$0004 → ハンドラ → W2C → irq1解除 → IRET
```

この割込経路が **RTL で完動**し、**emu23 v1.09 黄金と最終状態が一致**した。

### 0.2 ★次チャットの最初の作業：emu23_device_design v1.4 改版★

**ユーザー指示により、本チャットでは実施せず次チャットに送った。**

`emu23_device_design_v1_3.docx` → **v1.4**：

1. **§3.1 優先順位表から「IRQ2＝予備」の行を削除**（★ISA2.3にIRQ2は存在しない★）
2. **§3.5 将来課題を、`v3_7_design_memo_v0_3.md` §2 の内容でクローズ**（責務の帰属誤りの訂正を含む）
3. **§3.2 の「優先順位」記述に、実質序列を明記**：**`timer/align > IRQ1 > SYSCALL`**（設計メモ §2.5b）

### 0.3 ★★V4 で絶対に踏んではならない轍（BUG-1）★★

**V3.7 で `IRQ_STAT` と `IRQ_MASK` が入れ替わる重大バグを踏んだ。**

原因：デバイス内オフセット `addr_i` を **2bit** にしたこと。

| アドレス | `mmio_addr[1:0]` | 当初の解釈 | 実際 |
|---|---|---|---|
| `$FCB2` IRQ_STAT | `2'b10` | **MASK ❌** | STAT |
| `$FCB4` IRQ_MASK | `2'b00` | **STAT ❌** | MASK |

**`mmio_addr[2]` でしか区別できず、2bitでは原理的に不可能だった。**

**★S3単体TBは 21/21 ALL PASS していたのに見逃した＝偽合格★**
→ TBが `addr_i` に「自分が正しいと思う値」を直接与え、**DUTとTBが同じ誤った前提を共有**していた。

**→ V4（UART `$FC80`台）・V5（Timer）・V6（Storage `$FCA0`台）では、必ず：**

```systemverilog
// 悪い例（V3.7で踏んだ）
localparam A_STAT = 2'b00;              // TBの思い込み

// 良い例（実アドレスから機械的に導出）
localparam logic [15:0] ADDR_STAT = 16'hFC84;
localparam logic [2:0]  A_STAT    = ADDR_STAT[2:0];
```

**kaizen 原則67（TBが与える定数の出所を疑え）・原則68（検証コマンドの終了コードを鵜呑みにしない）として登録済。**

---

## 1. 現在地（2026-07-12時点）

**確定工程順**（`fpga_impl_roadmap_v1_3.docx`）:

```
V(-1) → V0 → V1 → V2 → V3 → V3.5(MMU)✅ → V3.7(YSD8004)✅ → ★V4(UART)★
  → V5(Timer) → V6-A/B(Storage) → V7(統合検証) → V8 → V9 → VD
```

| 工程 | 状態 |
|---|---|
| V3.5（MMU統合） | ✅ 完了（2026-07-11） |
| **V3.7（YSD8004 割込）** | **✅ 完了（2026-07-12・本チャット）** |
| **V4（UART / YSD8001）** | **★次工程★** |

---

## 2. 本チャットの成果

### 2.1 RTL（新規2本・改版1本）

| ファイル | 版 | 内容 |
|---|---|---|
| `ysd8800_ysd8004_v0_1.sv` | **v0.1** | **YSD8004 割込コントローラ（新規）** |
| `ysd8800_v37_membus_v0_1.sv` | **v0.1** | V3.7 メモリサブシステム統合（新規・V3.5から最小差分） |
| `ysd8800_mmio_stub_v0_3.sv` | v0.2 → **v0.3** | YSD8004をインスタンス化・`$FCB2`-`$FCB5` ルーティング |

**★CPUコア（`ysd8800_cpu_v0_1_FIXED.sv` v0.5.7）は無改修★**（V3.5に続き2フェーズ連続）

### 2.2 検証TB（7本）

| ファイル | 工程 | 結果 |
|---|---|---|
| `tb_ysd8004_v0_1.sv` | S3 単体 | **21/21 ALL PASS** |
| `tb_cpu_v37irq_v0_1.sv` | **S5 CPU結合（本丸）** | **ALL PASS** |
| `tb_cpu_v37regress_poc.sv` | S4 回帰（V2-a） | 20/20 |
| `tb_cpu_v37mem_poc.sv` | S4 回帰（V3メモリ） | 5/5 |
| `tb_cpu_v37boundary_poc.sv` | S4 回帰（境界） | 1/1 |
| `tb_cpu_v37mmu_v0_1.sv` | S4 回帰（MMU） | 6/6 |
| `tb_v37_w2c_diag_poc.sv` | 診断（BUG-1究明） | — |

**合計: 32回帰 + 21単体 + CPU結合 = 全 ALL PASS・FAIL 0・デグレゼロ**

### 2.3 生成器・スクリプト

| ファイル | 内容 |
|---|---|
| `gen_v37_irq_vectors.py` | **V3.7 黄金値生成器**（emu23 v1.09） |
| `mk_v37_tb.py` | V3.5回帰TB 4本をV3.7版へ複製 |
| `build_v37.sh` | V3.7回帰TBのビルド・実行 |

### 2.4 文書（4件）

| ファイル | 版 |
|---|---|
| `v3_7_design_memo_v0_3.md` | v0.2 → **v0.3**（実装完了・BUG-1記録） |
| `fpga_source_version_ledger_v1_3.md` | v1.2 → **v1.3**（§11新設） |
| `fpga_impl_roadmap_v1_3.docx` | v1.2 → **v1.3**（V3.7完了・次工程V4） |
| `kaizen.txt` | **原則67・68 追記**（1692 → 1802行） |

---

## 3. ★V5（Timer）への申し送り（重要・未解消）★

**多重割込の調停は emu23 では「2段構え」である。片方だけ写像すると破綻する。**
（詳細: `v3_7_design_memo_v0_3.md` §4.4b）

### 【第1段】pending保護（`ysd8004_raise()` L320-327）

```c
if (cpu.irq_pending < 0 || cpu.irq_pending == 2 || cpu.irq_pending == 4)
    cpu.irq_pending = 2;
/* ==1(timer) / ==3(align) は保護される */
```

**役割**: 後着のIRQ1が、先着の **timer(1) / align(3) を蹴落とさない**
**実質序列**: **`timer/align > IRQ1 > SYSCALL`**

### 【第2段】IRQ_STAT再評価（毎命令・L1576-1578）

**役割**: 保護で後回しになったIRQ1を、IRET後に復活させる

### ★★RTLでの成立状況★★

| 段 | RTL | 状態 |
|---|---|---|
| **第2段** | **★自動成立済★** | `irq1_o` を**レベル出力**にしたため。CPU L1224-1225 が `S_IRQCHK` のたびに `irq_in` を再ラッチする |
| **第1段** | **★未実装・V5の論点★** | CPU L1224-1225 は `irq_pending <= irq_in;` の**無条件素通しラッチ**。timer(1) pending中にYSD8004が2を出すと**上書きされうる** |

### V5で選ぶ設計（主要論点）

| 案 | 内容 | 影響 |
|---|---|---|
| **案A** | CPU の `irq_pending` 更新条件に**優先度比較**を入れる | emu23第1段を直接写像。**CPUコアRTL改修が必要** |
| **案B** | **タイマー側もレベル保持**し、蹴落とされても再評価で復活 | **CPUコア無改修**。タイマー側に保持機構 |

**どちらでも `timer/align > IRQ1 > SYSCALL` を満たすことが完了条件。**

---

## 4. 確定した設計（V4以降の入力・変更禁止）

| # | 内容 |
|---|---|
| 1 | **割込入力規約 = 1クロックパルス**（デバイス → YSD8004）。保持はYSD8004の責務 |
| 2 | **`irq1_o` は必ずレベル出力**（`IRQ_STAT != 0`）。★パルスにするとV5で取りこぼす★ |
| 3 | **接続**: `irq_in = (irq1_o ? 3'd2 : 3'd0)` |
| 4 | **IRQ_STAT ビット**: bit0=UART_RX / bit1=STOR / bit2=UART_TX |
| 5 | **IRQ_MASK リセット値 = `0x04`**（★`0x00` ではない★・bit2=TXマスク・emu23 L307） |
| 6 | **デバイスは独立モジュール**（案B）。MMIOスタブはルーティングに徹する |
| 7 | **ISAベクタ空き3枠**（`$000A`/`$000C`/`$000E`）は温存。将来の専用ベクタ割込に使える |

### V4（UART）で YSD8004 に繋ぐもの

```systemverilog
// membus のポートに既に出してある（未接続=0固定になっている）
.irq_src_uart_rx (...),   // YSD8001 RX → IRQ_STAT bit0
.irq_src_uart_tx (...),   // YSD8001 TX(TDRE) → IRQ_STAT bit2
.irq_src_stor    (...),   // V6で YSD8003 → IRQ_STAT bit1
```

---

## 5. ビルド・実行手順

```bash
# ツール（毎セッション必要）
apt-get install -y iverilog          # Icarus Verilog 12.0
gcc -O2 -o emu23 emu23_v109.c
gcc -O2 -o hasm23 hasm23_v1_04.c
gcc -O2 -o lnk23 lnk23_v2_01.c

# ベクタ生成（emu23が同ディレクトリに必要）
python3 gen_v2_vectors.py            # v2a/  (20)
python3 gen_v3_mem_vectors.py        # v3mem/ (5)
python3 gen_v3_boundary_vectors.py   # v3boundary/ (1)
python3 gen_v35_mmu_vectors.py       # v35mmu/ (6)
python3 gen_v37_irq_vectors.py       # v37irq/ ★V3.7★

# ★コンパイル順序（パッケージ依存順・必須）★
#   decoder → regfile → alu → cpu → devices → membus → tb
iverilog -g2012 -o tb.vvp \
  ysd8800_decoder_v0_1.sv ysd8800_regfile_v0_1.sv ysd8800_alu_v0_1.sv \
  ysd8800_cpu_v0_1_FIXED.sv ysd8800_ysd8004_v0_1.sv ysd8800_mmio_stub_v0_3.sv \
  ysd8800_addr_decoder_v0_1.sv ysd8800_mmu_v0_1.sv ysd8800_cdc_bridge_v0_2.sv \
  ysd8800_psram_ctrl_v0_2.sv ysd8800_v37_membus_v0_1.sv tb_cpu_v37irq_v0_1.sv

# ★ビルド成否は $? ではなく成果物で判定（原則68）★
ls -la tb.vvp || echo "BUILD FAILED"

# ★ビルドと実行は必ず分離（&&チェーン禁止）★
timeout 60 vvp tb.vvp > out.log 2>&1

# ★検証は行頭アンカー（原則68）★
grep -c "^FAIL" out.log      # grep -c FAIL はサマリ行に誤ヒットする
```

---

## 6. 技術的知見（本チャットで得たもの）

| # | 内容 |
|---|---|
| 1 | **★原則67★ 単体TBの偽合格**: TBが定数を手で書くと、DUTと同じ誤った前提を共有し ALL PASS してしまう。**I/F定数は実アドレスから機械的に導出せよ** |
| 2 | **★原則68★ `grep -c FAIL` は偽陽性**: サマリ行 `RESULT: PASS=21 FAIL=0` にヒットする。→ **`grep -c "^FAIL"`** |
| 3 | **★原則68★ パイプの `$?` はビルド成否ではない**: `iverilog ... \| grep -v "sorry:"` の `$?` は grep のもの。→ **成果物の `ls -la` で判定** |
| 4 | **`.docx` 拡張子でも実体がMarkdownのことがある**（KY43）。`file` コマンドで判定してから開く。ロードマップ・MMU設計書は Markdown、レビュー回答書は真のOOXML |
| 5 | Icarus 12.0 の `unique case` 警告（`sorry: Case unique/unique0 qualities are ignored.`）は**既知・無害** |
| 6 | emu23 の実出力形式: `PC=0116 SP=0400 F=81 A=0000 B=1234 X=BEEF`（**SP/F が A/B/X より前**） |

---

## 7. 申し送り（未解消）

| # | 内容 | 期限 |
|---|---|---|
| 1 | **`emu23_device_design_v1_3.docx` → v1.4 改版** | **★次チャット最優先★** |
| 2 | **V5 多重割込調停【第1段】の設計判断**（案A/案B） | V5着手時 |
| 3 | Ph.7（FAT12移行）・Ph.8（MMU統合）は YUI OS ロードマップに常時保持 | — |
| 4 | scc23 Phase 1以降は FPGA 作業優先で意図的に後回し | — |

---

## 8. 関連文書

| 文書 | 版 |
|---|---|
| `v3_7_design_memo_v0_3.md` | **v0.3** ★本チャットの主成果★ |
| `v3_7_design_review_reply_v1_0.docx` | v1.0（レビュー回答・承認） |
| `fpga_impl_roadmap_v1_3.docx` | **v1.3** |
| `fpga_source_version_ledger_v1_3.md` | **v1.3** |
| `kaizen.txt` | 原則68まで |
| `emu23_v109.c` | v1.09（黄金） |
| `YSD8800_MMU_Design_v1_2_0.docx` | v1.2.0 |

---

## 9. ツール版数（確認済）

| ツール | 版 |
|---|---|
| hasm23 | v1.04 |
| lnk23 | v2.01 |
| emu23 | **v1.09**（黄金） |
| scc23 | v2.03 |
| Force | v1.5 |
| Icarus Verilog | 12.0（`-g2012` 必須・毎セッション再インストール） |
