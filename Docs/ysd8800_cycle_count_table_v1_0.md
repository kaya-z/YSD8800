# YSD8800 サイクルカウントテーブル v1.0 (2026-07-11)

## 0. 文書識別

| 項目 | 値 |
|---|---|
| 文書名 | ysd8800_cycle_count_table_v1_0.md |
| バージョン | v1.0 |
| 発行日 | 2026-07-11 |
| 対象 | YSD8800 CPUコア RTL FSM v0.5.6 (ysd8800_cpu_v0_1.sv) |
| 前提 | ★理想メモリ (mem_ready 常時1・待ちゼロ) |
| 出典 | RTL FSM 状態遷移の実測 (tb_cpi_probe_poc / probe2_poc) |
| 検証環境 | Icarus Verilog 12.0 |

---

## 1. 前提と定義 (★最重要・KY)

### 1.1 サイクルの出典は RTL FSM であって emu23 ではない

emu23 (黄金リファレンス) は **CPI=1 固定**であり、論理結果 (レジスタ値・
メモリ・FLAGS) の黄金ではあるが、**サイクル数の根拠にはできない**。本表の
サイクル数はすべて **RTL FSM (ysd8800_cpu v0.5.6) の状態遷移**を一次情報源
とし、単一命令マイクロベンチ (`tb_cpi_probe_poc.sv`) で実測した (KY34)。

### 1.2 理想メモリ前提

本表は **mem_ready 常時1 (メモリ待ちゼロ)** を前提とする。
FPGA 実機では PSRAM (64Mbit) アクセスに待ちサイクルが入るため、
**実効サイクル表は PSRAM 統合後 (V3以降) に別途作成する** (本表とは別文書)。
本表は「命令固有の最小サイクル数」を与える基準表である。

### 1.3 CPI の数え方

1 命令の CPI = その命令が S_FETCH に入ってから、次命令の S_FETCH 直前
(= S_IRQCHK を抜ける点) までに滞在する状態数。各状態は理想メモリ下で
1 サイクル。命令間で必ず通る S_IRQCHK (割込チェック) は命令間共通の
1 サイクルであり、本表の「命令固有 CPI」には含めない
(別掲の 1.4 参照)。

### 1.4 測定方式 (差分法)

較正基準命令 NOP (固有 CPI=2: S_FETCH, S_OPFETCH) を用い、
`CPI = raw(命令) - raw(NOP) + 2` で各命令の固有 CPI を算出した。
raw はリセット解除〜HALT 到達までの実クロック数。複合命令
(RET/IRET/割込受理) はセットアップ命令の既知 CPI を差し引いて較正した。

---

## 2. サイクルカウントテーブル (理想メモリ)

| 命令 | opcode | CPI | 状態連鎖 (S_ 略) | 根拠 |
|---|---|---:|---|---|
| NOP | 0x00 | 2 | FETCH, OPFETCH | 実測(基準) |
| HALT | 0x01 | (4) | FETCH, OPFETCH, HALT | 較正基準※ |
| EI | 0x02 | 2 | FETCH, OPFETCH | 実測 |
| DI | 0x03 | 2 | FETCH, OPFETCH | 実測 |
| IRET | 0x04 | 7 | FETCH, OPFETCH, EXEC_IRET, POP_LO/HI×2 | 較正 |
| SYSCALL | 0x05 | 3 | FETCH, OPFETCH, EXEC_SYSCALL | 較正 |
| MOV rD,rS | 0x20 | 4 | FETCH, OPFETCH, EXEC_ALU, WRITEBACK | 実測 |
| LDW rD,#imm | 0x21 | 6 | FETCH, OPFETCH, IMML, IMMH, EXEC_ALU, WRITEBACK | 実測 |
| LDW rD,[imm16] | 0x22 | 8 | FETCH, OPFETCH, IMML, IMMH, DECODE, MEMR_LO/HI, WRITEBACK | 実測 |
| STW rS,[imm16] | 0x23 | 7 | FETCH, OPFETCH, IMML, IMMH, DECODE, MEMW_LO/HI | 実測 |
| LDW rD,[rS] | 0x24 | 7 | FETCH, OPFETCH, DECODE, MEMR_LO/HI, WRITEBACK | 実測 |
| STW rS,[rD] | 0x25 | 6 | FETCH, OPFETCH, DECODE, MEMW_LO/HI | 同型展開 |
| LDW rD,[X+off] | 0x26 | 8 | FETCH, OPFETCH, IMML, IMMH, DECODE, MEMR_LO/HI, WRITEBACK | 同型(0x22) |
| STW rS,[X+off] | 0x27 | 7 | FETCH, OPFETCH, IMML, IMMH, DECODE, MEMW_LO/HI | 同型(0x23) |
| ADD rD,rS | 0x40 | 4 | FETCH, OPFETCH, EXEC_ALU, WRITEBACK | 実測 |
| ADDI rD,#imm | 0x41 | 6 | FETCH, OPFETCH, IMML, IMMH, EXEC_ALU, WRITEBACK | 実測 |
| SUB rD,rS | 0x42 | 4 | (ADD rr と同) | 同型(0x40) |
| SUBI rD,#imm | 0x43 | 6 | (ADDI と同) | 同型(0x41) |
| CMP rD,rS | 0x44 | 4 | FETCH, OPFETCH, EXEC_ALU, WRITEBACK | 実測 |
| CMPI rD,#imm | 0x45 | 6 | (ADDI と同・書込なし) | 同型(0x41) |
| AND rD,rS | 0x50 | 4 | (ADD rr と同) | 同型(0x40) |
| ANDI rD,#imm | 0x51 | 6 | (ADDI と同) | 同型(0x41) |
| OR rD,rS | 0x52 | 4 | (ADD rr と同) | 同型(0x40) |
| ORI rD,#imm | 0x53 | 6 | (ADDI と同) | 同型(0x41) |
| XOR rD,rS | 0x54 | 4 | (ADD rr と同) | 同型(0x40) |
| XORI rD,#imm | 0x55 | 6 | (ADDI と同) | 同型(0x41) |
| NOT rD | 0x56 | 4 | FETCH, OPFETCH, EXEC_ALU, WRITEBACK | 同型(0x40) |
| SHL rD | 0x57 | 4 | (単項 ALU) | 同型(0x40) |
| SHR rD | 0x58 | 4 | (単項 ALU) | 同型(0x40) |
| SAR rD | 0x59 | 4 | (単項 ALU) | 同型(0x40) |
| JMP rel16 | 0x60 | 5 | FETCH, OPFETCH, IMML, IMMH, EXEC_BRANCH | 実測 |
| BEQ rel16 | 0x61 | 5 | (JMP と同・成立/不成立同数) | 同型(0x60) |
| BNE rel16 | 0x62 | 5 | (JMP と同) | 同型(0x60) |
| BLT rel16 | 0x63 | 5 | (JMP と同) | 同型(0x60) |
| BGE rel16 | 0x64 | 5 | (JMP と同) | 同型(0x60) |
| JSR imm16 | 0x68 | 7 | FETCH, OPFETCH, IMML, IMMH, EXEC_JSR, PUSH_LO/HI | 実測 |
| RET | 0x69 | 7 | FETCH, OPFETCH, EXEC_RET, POP_LO/HI(+PC反映) | 較正 |
| LDB A/B,[imm16] | 1F/10,12 | 7 | FETCH, OPFETCH, SUBOP, DECODE, IMML, IMMH, MEMR8 | 実測 |
| LDB A/B,[X] | 1F/11,13 | 6 | FETCH, OPFETCH, SUBOP, DECODE, MEMR8 | 実測 |
| STB A/B,[imm16] | 1F/14,16 | 7 | FETCH, OPFETCH, SUBOP, DECODE, IMML, IMMH, MEMW8 | 実測 |
| STB A/B,[X] | 1F/15,17 | 6 | FETCH, OPFETCH, SUBOP, DECODE, MEMW8 | 実測 |
| PUSH A/B/X | 1F/00-02 | 6 | FETCH, OPFETCH, SUBOP, DECODE, PUSH_LO/HI | 実測 |
| POP A/B/X | 1F/03-05 | 6 | FETCH, OPFETCH, SUBOP, DECODE, POP_LO/HI | 実測 |

### 割込関連 (命令ではないシーケンス)

| シーケンス | CPI | 状態連鎖 | 根拠 |
|---|---:|---|---|
| 割込受理 | 9 | IRQCHK, IRQ_ACCEPT, PUSH_LO/HI×2, MEMR_LO/HI (ベクタ読) | 較正 |
| リセット | 2 | RESET_LO, RESET_HI | 実測 |

※ HALT の CPI=4 は「dbg_halt 到達検出コスト」を含む較正基準値であり、
  命令実行としての意味は持たない (停止状態への遷移コスト)。

---

## 3. CPI 分布サマリ

| CPI | 命令グループ | 代表 |
|---:|---|---|
| 2 | 制御単発 | NOP, EI, DI |
| 3 | SYSCALL | SYSCALL |
| 4 | レジスタ ALU / MOV / CMP | ADD, MOV, CMP, 論理, シフト |
| 5 | 分岐 (相対) | JMP, Bcc |
| 6 | 即値 ALU / スタック / バイト[X] | ADDI, LDW#imm, PUSH, POP, LDB[X] |
| 7 | ワードメモリ / サブルーチン / バイト[imm] | STW, LDW[rS], JSR, RET, IRET, LDB[imm], STB[imm] |
| 8 | ワードロード[imm/X+off] | LDW[imm16], LDW[X+off] |
| 9 | 割込受理シーケンス | (SYSCALL/タイマ受理共通) |

---

## 4. 設計上の考察 (MC6809 対比・参考)

YSD8800 の CPI 帯域 (2〜9) は、MC6809 の命令サイクル (2〜十数
サイクル) と同オーダーである。6809 が可変長命令・多彩なアドレッシング
モードで命令毎にサイクルが大きく変動したのと同様、YSD8800 も
アドレッシング (即値/絶対/レジスタ間接/X+offset) と 16bit メモリ
アクセス (LO/HI 2回) がサイクル数を支配する。特に

- 16bit メモリアクセスが LO/HI の 2 サイクルを要する点は、
  6809 の 16bit ロード/ストア (LDD/STD 等) が 8bit バス上で
  2 アクセスを要したのと同じ構造的要因である。
- スタック操作 (PUSH/POP=6, JSR/RET=7) が比較的重いのも、
  pre-dec/post-inc の 8bit×2 アクセス機構による。6809 の
  PSHS/PULS がレジスタ数に比例してサイクルを消費したのと
  同じく、YSD8800 も 1 レジスタあたり LO/HI 2 アクセスである。

理想メモリでこの帯域なので、PSRAM 待ちが加わる実機 (4MHz) では
各メモリアクセス状態に待ちサイクルが上乗せされる。実効性能見積もりは
V3 の PSRAM 統合後に本表を基準として算出する。

---

## 5. 検証方法 (再現手順)

```
# 単一命令 CPI 実測
iverilog -g2012 -o sim_cpi \
  ysd8800_decoder_v0_1.sv ysd8800_regfile_v0_1.sv \
  ysd8800_alu_v0_1.sv ysd8800_cpu_v0_1.sv tb_cpi_probe_poc.sv
timeout 60 vvp sim_cpi        # 各命令の raw サイクル出力

# 複合命令 (RET/IRET/受理) CPI 較正
iverilog -g2012 -o sim_cpi2 ... tb_cpi_probe2_poc.sv
timeout 60 vvp sim_cpi2
```

較正計算: `CPI = raw(命令) - raw(NOP) + 2` (NOP 固有 CPI=2 基準)。

---

## 6. 既知の注記・限界

1. 本表は理想メモリ前提。PSRAM 待ちを含む実効値は別表 (V3以降)。
2. `_poc` ハーネス (KY38) は実験用。正式版昇格はレビュー後。
3. SUB/論理/シフト/Bcc/CMPI 等の「同型展開」は、ALU 経路・状態連鎖が
   実測済み代表命令と同一構造であることに基づく。全命令の悉皆実測は
   V3 の実効値測定時に併せて行う (現時点は構造同型で十分)。
4. HALT の CPI は停止遷移コストであり、命令スループット計算には用いない。

---

## 改版履歴

| 版 | 日付 | 変更 |
|---|---|---|
| v1.0 | 2026-07-11 | 新規作成。V2 完了 (CPUコア単体検証 ALL PASS 82ベクタ) を受け、理想メモリ前提の命令サイクル表を RTL FSM 実測により確定。 |
