# 第5-3段(c) 受理→IRET往復統合 + align例外受理　設計メモ / レビュー資料
- 文書: stage5_3c_design_memo_v0_1.md  v0.1  (2026-07-06)
- 対象: ysd8800_cpu_v0_1.sv v0.5.6 (FPGA V1 CPUコア)
- 設計根拠: fpga_v1_cpucore_design_v1_1.md §6(FSM)/§7.4-7.6(受理/IRET)
- 黄金参照: emu23_v109.c (受理 L1176-1188 / IRET L1213-1223 / align L558,577-578,646-647)
- 位置づけ: 原則43準拠。**本メモのレビュー承認後にTB作成へ着手**する。

---

## 1. 背景と(c)のスコープ確定

第5-3段は割込まわりを3ステップに分割:
- (a) IRET単体 … v0.5.4で実装・CPU_IRET_TB ALL PASS 済
- (b) 割込受理 S_IRQ_ACCEPT … v0.5.6で真因修正し CPU_IRQ_TB ALL PASS 済(本日)
- (c) **本メモ**: 受理とIRETを1シナリオで往復させる統合検証 + align例外の受理往復

### 実照合で判明した重要事実
(c)で新規に書く**RTLロジックは原則ゼロ**。必要パーツは全て実装済:
| 要素 | 実装状況 | 実ソース位置 |
|---|---|---|
| 割込受理 S_IRQ_ACCEPT | ✅ v0.5.6 | cpu.sv 受理FSM一式 |
| IRET pop2 (FLAGS下位8bit→PC) | ✅ v0.5.4 | cpu.sv L999-1000, S_EXEC_IRET |
| align検出 mem_misaligned | ✅ | cpu.sv L361-362 (eff_addr[0]&dec_mem_w16) |
| align→irq_pending←3 | ✅ | cpu.sv L1103-1104 |
| align→S_IRQCHK遷移 | ✅ | cpu.sv L671 |

→ (c)は **統合TB 2本の新規作成による実証** が本体。RTL変更が発生するのは
   TBが不整合を暴いた場合に限る(その場合は原因を本メモに追記し再レビュー)。

---

## 2. 黄金(emu23_v109.c)の往復仕様(実照合)

### 2.1 受理 (L1176-1188)
```
if (irq_pending>=0 && (flags & FL_IE)) {   // FL_IE=0x80=bit7
    irq = irq_pending; irq_pending = -1;
    push16(PC);                 // (1) PC先push
    push16(flags);              // (2) FLAGS後push (IE=1のまま)
    flags &= ~FL_IE;            // (3) push後にIE=0
    PC = rd16(irq*2);           // (4) ベクタ先へ
}
```
### 2.2 IRET (L1213-1223)
```
flags = (uint8_t)pop16();       // (1) FLAGS先pop = 下位8bitのみ(上位0クリア)
PC    = pop16();                // (2) PC後pop
```
### 2.3 往復の対称性(LIFO)
- pushは PC→FLAGS の順 ⇒ スタック上はFLAGSが上(SP側)。
- popは FLAGS→PC の順 ⇒ 上のFLAGSから取る。完全対称。✓
- IEの往復: 受理直前のflags(IE=1)をpush→IRETで下位8bit復元しbit7=IE復帰。
  (b)で修正したIE=bit7と整合。✓
- **非対称点(意図的)**: IRETはFLAGS下位8bitのみ復元(上位8bit=0)。
  RTL側もL999-1000で {8'h00, mem_lo} と同仕様。黄金一致済。✓

### 2.4 align例外 (L558, 577-578, 646-647)
- 検出: 16bitワードアクセスで addr&1 (read/write両方)。
- 反応: irq_pending = 3。align固有処理なし=通常受理経路を流用。
- ベクタ: rd16(3*2)=mem[6:7]。
- PC: 例外検出時 early return(命令未完了扱い)。命令fetchでPC++済のため、
  受理でpushされるPCは **align例外命令の次命令PC** となる(emu23挙動)。
  ※RTL側はS_DECODEで検出しirq_pending←3、PCはfetch時に更新済のため同挙動を想定。
    TBで実PC値を実測し黄金と突き合わせる(下記TB-2の検証点)。

---

## 3. 作成するTB (2本)

### TB-1: tb_cpu_irq_iret_v0_1.sv (受理→IRET往復統合)
**目的**: 通常IRQ(timer/device)を受理→ハンドラ→IRETで元コンテキストへ復帰、
        の1周を検証。(a)(b)が連結して動くことの実証。

**プログラム構成(擬似)**:
```
0100 LDWI SP,#4000        ; スタック初期化
0104 EI                   ; IE=1
0105 LDWI A,#0011         ; ★この命令実行前後で割込投入
0109 LDWI B,#00BB         ; 復帰後に実行される命令
010D HALT
; --- ハンドラ (vec=IRQ1=mem[2:3]=0x0300) ---
0300 LDWI A,#00AA         ; ハンドラ実行の証拠
0304 IRET                 ; 復帰
```
**irq投入**: PC==0105到達後にirq_in=1アサート、ハンドラ到達で解除。

**検証点(assert)**:
1. ハンドラ到達: 途中でPC==0300を通過(A=0x00AA書込)。
2. 復帰PC正当性: IRET後 0109から再開しB=0x00BB。
3. スタック復元: IRET完了後 SP==4000 (push2→pop2で往復ゼロ)。
4. FLAGS往復: 復帰後IE==1 (受理でpushしたIE=1がIRETで復帰)。
   ※ハンドラ内でIEを変えない前提。ハンドラ先頭はフラグ不変命令(LDWI=Z/N更新
     のみ,IE不変)を置く(v0.5.4 TB知見: FLAGS検証は復帰先にフラグ不変命令)。
5. 最終A: 0011(受理前)→ハンドラAA→復帰後0109でBに触るのでA=00AA維持 or
   復帰後Aを再ロードしない設計にしてA=00AA を確認(ハンドラ実行の残存証拠)。
   ※TB確定時にA/Bの役割を1つに固定(責務単一原則)。
6. スタック内容: @3FFE/3FFF にpushされたPC_lo/hi = 0x09/0x01。

### TB-2: tb_cpu_align_irq_v0_1.sv (align例外受理, E-1)
**目的**: 奇数アドレスへの16bitアクセスでalign例外→irq_pending=3→受理→
        ベクタ3(mem[6:7])のハンドラ→IRET、をLDW/STW両経路で検証(レビュー条件E-1)。

**プログラム構成(擬似, LDW経路)**:
```
0000 vec0: 00 01          ; reset=0x0100
0006 vec3: 00 03          ; align vec = 0x0300 (irq3*2=6)
0100 LDWI SP,#4000
0104 EI
0105 LDWI X,#2001         ; 奇数アドレス
0109 LDW  A,[X]           ; ★align例外(2001は奇数)→irq_pending=3
010D HALT
0300 LDWI A,#00AA         ; alignハンドラ
0304 IRET
```
**STW経路**: 0109を STW A,[X] に変えた版(同一TB内で2ケース or 別TB)。

**検証点(assert)**:
1. align検出: irq_pending が 3 になる(内部観測 or 受理成立で間接確認)。
2. ベクタ3受理: PC==0300到達(A=0x00AA)。
3. LDW/STW両経路で1.2.が成立(E-1)。
4. 受理でpushされたPC値を実測し、黄金(次命令PC=010D)と一致するか確認。
   ※ここは黄金挙動の確定が必要な唯一の論点(§2.4)。RTLの実PC値をログ出力し、
     emu23の同プログラム実行時のpush値と突き合わせる。乖離あれば本メモに追記し
     再レビュー(RTL修正 or 仕様確認)。

---

## 4. KY / リスク

- **KY(本日, (c)固有)**: (b)で修正したIE=bit7と、IRETのFLAGS下位8bit復元の
  食い違い、およびalign(irq3)がtimer/device(irq1/2)と同一受理経路を正しく通るかの
  ベクタ番号取り違え。
  **防止策**: (1)IRET復元幅を黄金L1215で実照合済(下位8bit,bit7含む,整合確認済)。
  (2)alignは受理経路をirq_latch経由で番号非依存に流用する既存構造を利用、TBで
  ベクタ3先着を実測。(3)統合TBは動作確実な既存TB(irq/iret)を複製し最小差分で構成。

- **リスク低**: RTLは既存パーツの連結。新規ロジック追加なしを想定。
- **リスク中(唯一)**: §2.4/§3のTB-2検証点4、align例外時のpush PC値の黄金一致。
  ここだけ挙動未実測。TBで実測し黄金照合する方針(乖離時は再レビュー)。

---

## 5. 検証計画(レビュー承認後に実施)

1. TB-1(往復統合)作成 → ビルド(ls確認) → 実行 → ALL PASS。
2. TB-2(align受理, LDW/STW)作成 → 同上。検証点4で黄金PC照合。
3. 既存全7TB(fetch/mem/memalign/byte/iret/irq + 新2本)回帰 ALL PASS(C-3)。
4. 成果を cpu.sv履歴に追記(RTL変更なければTB追加とマイルストン記録のみ, 版は
   v0.5.6据置 or TB群確定でv0.5.7判断)。

---

## 6. レビュー依頼事項(承認/指摘をお願いします)

- Q1: (c)を「統合TB 2本の実証」と位置づけ、RTLは原則無変更とする方針で可か。
- Q2: TB-1の復帰後レジスタ役割(A=ハンドラ証拠/B=復帰後証拠)の割当で可か。
- Q3: TB-2のalign例外push PC値、黄金(emu23)実測との突合を検証点とする方針で可か。
      (RTLとemu23で挙動が異なった場合、どちらを正とするか事前合意したい。
       原則は「外部観測等価」だが、例外PCは往復さえ閉じれば実害小とも言える。)
- Q4: align例外はワードアクセスのみ(バイトは整列扱い)。この前提で可か(既存実装通り)。
