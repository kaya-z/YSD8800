# HANDOVER_CHAT78.md  (2026-07-11発行)
## 次チャット引継ぎ: FPGA V2-e（C8制御割込）実装

発行元: FPGA実装チャット（V2-d完了・V2-e設計承認まで）
宛先  : V2-e実装チャット（本引継ぎで gen/TB 実装→検証→ALL PASS を行う）
前提原則: 原則43（設計レビュー承認済→実装OK）/ KY34（実ファイルが真実）/ KY38/39/41

---

## 0. 一行サマリ

V2-e（C8制御割込 EI/DI/SYSCALL/IRET/割込受理）は**設計メモv0.2でレビュー承認済（Mなし）**。
本チャットで **gen_v2_vectors_v2e_poc.py と tb_cpu_v2e_v0_1.sv を実装**し、
既存75＋新規約6〜8本の ALL PASS を出せば **V2完了**。

---

## 1. 現在地（工程）

```
🔧 Step 8 FPGA V2 CPUコア単体検証
   ├ ✅ V2-a(C1)/V2-b(C2/C3)/V2-c(C4/C5) ALL PASS
   ├ ✅ V2-d(C6スタック/C7サブルーチン) ALL PASS(75)・承認済
   └ 🔧 V2-e(C8制御割込)
       ├ ✅ 設計メモ v0.2 承認済(Mなし)  ← 前チャット完了
       └ ⬜ gen/TB実装→検証→ALL PASS→V2完了  ← ★本チャットのゴール
⬜ V2完了後: サイクルカウントテーブル一括作成 → V3以降
```

---

## 2. 必須成果物（プロジェクト/添付から入手）

本チャット冒頭で以下を作業DIRに集めること。★はV2-e実装の直接土台。

| ファイル | 役割 | 備考 |
|---|---|---|
| ★v2e_design_memo_v0_2.md | V2-e設計メモ(承認済) | 実装の唯一の指示書 |
| ★gen_v2_vectors_v2d_poc.py | 生成器の土台 | これをv2e_pocに拡張 |
| ★tb_cpu_v2d_v0_1.sv | TBの土台 | これをv2e_v0_1に拡張 |
| ★emu23_v109.c | 黄金リファレンス | ビルドして黄金取得 |
| ysd8800_decoder/regfile/alu/cpu_v0_1.sv | RTL(4本) | コンパイル対象 |
| mk_sysprobe_poc.py | R-1実測プローブ | 受理vec=$0008の再現材料 |

★V2-d/c/bの成果物はプロジェクト未登録の可能性大（前チャットでも都度アップ
  いただいた）。冒頭で ls 確認し、無ければユーザーにアップ依頼すること。

---

## 3. 設計メモv0.2 の確定事項（実装が従うべき仕様）

### 3.1 検証対象命令（emu23_v109実照合済・KY34）
| 命令 | opcode | エンコード | 挙動 | FLAGS |
|---|---|---|---|---|
| EI | 0x02 | [0x02] | flags\|=0x80(IE=1) | IE=1 |
| DI | 0x03 | [0x03] | flags&=~0x80 | IE=0 |
| IRET | 0x04 | [0x04] | flags=(u8)pop16; pc=pop16 | pop復元(下位8bit) |
| SYSCALL | 0x05 | [0x05] | irq_pending=4 (その場飛ばない) | 不変 |
| 割込受理 | - | - | push16(PC);push16(FLAGS);IE=0;PC=rd16(irq*2) | IE=0 |

補助(V2-d流用): LDW SP,#imm=[0x21,0x30,lo,hi] / PUSH A=[0x1F,0x00] / MOV X,SP=[0x20,0x23]

### 3.2 ★論点R-1（決着済・最重要・実装で踏むな）
**SYSCALL単独では irq_pending=4 のまま → 受理 vec=rd16($0008)。**
- 4→2正規化(emu23 L318-325)は ysd8004_raise()内・irq_stat!=0ガード内で、
  UART等デバイス経由時のみ発動。SYSCALL単独では通らない。
- RTL(irq_pending=4<<1=$0008)と一致。RTL修正不要。
- ★よって SYSCALL受理ベクタは **$0008** に handler番地を置く（$0004ではない）。
- 再現: `python3 mk_sysprobe_poc.py; ./emu23 /tmp/sysprobe.bin -n 30`
  → "IRQ 4 accepted, vec=0300"・A=0x0008・SP=FC7A で確認可。

### 3.3 SYSCALL受理シーケンス（黄金取得法）
```
ベクタ $0008 = handler_addr    ; SYSCALL単独→irq=4→vec=rd16($0008)
main : LDW SP,#0xFC7E; EI; SYSCALL; (受理でここは踏まない)
       ↓次サイクル受理: push16(PC=SYSCALL次番地); push16(FLAGS); IE=0; PC←rd16($0008)
handler: A←0x1234; HALT
観測: A=0x1234(受理到達) / SP=SP_INIT-4(push×2) / F IE=0
```
gen側は emu23 をそのまま走らせるだけ（黄金が正・特別処理不要）。

---

## 4. ベクタ設計（設計メモ§4・約6〜8本）

grp: ctl（制御命令単体）/ irq（受理）。全ベクタ先頭で LDW SP初期化。SP突合対象。

### C8-ctl（4本）
| id | 内容 | 主観測 |
|---|---|---|
| EI_set     | LDW SP; EI; HALT              | F=0x80 |
| DI_clear   | LDW SP; EI; DI; HALT          | F=0x00(他ビット非汚染) |
| IRET_basic | 手動push[PC][FLAGS]; IRET      | PC=戻り先, F=積値の下位8bit |
| IRET_mask  | FLAGS上位に1を積み IRET         | F上位が0にマスク((u8)確認) |

### C8-irq（2〜4本・レビューでSYS_noEI推奨）
| id | 内容 | 主観測 |
|---|---|---|
| SYS_accept | ベクタ$0008=handler;EI;SYSCALL;handler:A←0x1234;HALT | A=0x1234,SP=SP_INIT-4,IE=0 |
| SYS_noEI   | EI無しでSYSCALL(IE=0で非受理) | irq_pending立つが非受理→黄金で挙動確認 |
| SYS_iret   | 受理→handler内IRET→main復帰→HALT | 往復対称(PC/FLAGS/SP戻る) |

★IRET_basic/IRET_mask/SYS_iret は「手でスタックに戻り先を積む」構造。
  V2-d の RET_only_chk 手法（LDWでregに番地→PUSH→…）を流用する。
  PUSH #imm は存在しない（PUSHはレジスタのみ・KY39既出）。

---

## 5. 実装手順（設計メモ§6）

1. gen_v2_vectors_v2e_poc.py 作成
   - v2d_poc をコピー土台に、C8エンコーダ(ei/di/iret/syscall)追加
   - ベクタ$0008へhandler番地を書く make_image 拡張（IRQベクタ配置）
   - grp='ctl'/'irq' 追加・OUTDIR='v2e'・expected 6word継続
2. 生成実行→黄金取得→C8/C7 golden目視（SYS_accept: A=1234/SP-=4/IE=0）
3. tb_cpu_v2e_v0_1.sv 作成
   - NVEC=75+新規本数、vname/vgrp追加、load_prog case追加
   - v2d/→v2e/ パス置換
4. コンパイル(decoder→regfile→alu→cpu→tb)→vvp(timeout)→grep -c FAIL
5. ALL PASS 確認 → V2-e完了 → V2完了 → レビュー

---

## 6. ★KY申し送り（本設計の危険・設計メモ§7）

**危険**: 割込受理の「push するPC値」の取り違え。emu23が受理時に push する
cpu.pc は「SYSCALL実行後・次fetch前」＝**SYSCALL次番地**。gen/TBで「SYSCALL
命令の番地」と誤認すると期待PC(復帰先)が1命令ずれる。

**防止策**:
1. 受理の期待値は emu23黄金をそのまま使う（手計算しない・KY34）。
2. SYS_iret で「受理pushしたPC == IRET復帰PC == SYSCALL次番地」の三者一致を
   黄金で確認してから実装（レビューC-2）。
3. handler到達(A=0x1234) と SP-=4 の両方が揃って初めて受理成功と判定
   （片方だけでは push回数/vec先の誤りを見逃す）。

本チャット冒頭で新たなKYを1つ挙げること（本申し送りは前提知識として活用）。

---

## 7. レビュー所見の実装反映メモ（承認済・織り込むこと）

- Q2: SYS_noEI（IE=0で非受理）を入れる価値大 → 実装する。
  受理ガード `irq_pending>=0 && (flags&FL_IE)`(L1176)のIE=0側分岐を検証する唯一のケース。
- Q4: IRET_mask は残す（多層防御・FLAGS復元幅を将来16bit化した回帰を検出）。
- C-2: SYS_iret 三者一致を必ず通す。
- N-1: SYSCALLは別サイクル受理。RTL FSMは S_EXEC_SYSCALL→S_IRQCHK→S_IRQ_ACCEPT。
  「その場でvec飛び」と誤実装しないこと。

---

## 8. 本チャット未処理の積み残し（V2-e実装とは別・忘却防止）

以下は V2-e実装の本流ではないが、latest記載の持ち越し。指示があれば対応:
- E-1: kaizen.txt へ教訓登録「emu内部コメントは特定経路前提のことがあり、
  命令単独挙動と混同しない。断定前に実走で確認(KY34)」（R-1の好例）。
- 設計メモ V2-b/c/d/e の v0.x→v1.0 確定（正式版昇格）。
- 成果物のプロジェクトナレッジ登録（V2-b/c/d/e一式）。
- tool_version_ledger 更新（gen_v2d/tb_v2d/v2e設計メモ）。
- latest へ 2026-07-11 分日報記載。

---

## 9. 環境再現（前チャット実績・そのまま使える）

```
apt-get install -y iverilog          # Icarus Verilog 12.0
gcc -O2 -o emu23 emu23_v109.c        # 黄金
iverilog -g2012 -o sim ...(順序: decoder regfile alu cpu tb)
timeout 90 vvp sim > run.txt         # KY29 timeout必須
grep -c FAIL run.txt                 # 規律5 全件確認(tail厳禁)
```

## 10. ツール版数（2026-07-11時点）
Force v1.5 / hasm23 v1.04 / lnk23 v2.01 / emu23 v1.09 / scc23 v2.03
kernel_forth v0.10.18 / ysd8800_cpu RTL FSM v0.5.6 / Icarus Verilog 12.0

---
（本HANDOVERはユーザー明示指示により発行。次チャットは本文書の確認→
  ロードマップ確認→KY活動→「ご安全に！」で着手する）
