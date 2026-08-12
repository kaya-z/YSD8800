# 第5-3段(IRET + 割込受理) 実装設計メモ

- ファイル名: stage5_3_design_memo_v0_1.md
- バージョン: v0.1
- 作成日: 2026-07-04
- 対象: ysd8800_cpu_v0_1.sv (v0.5.3 → v0.5.4予定)
- 位置づけ: HANDOVER §2.3/§2.5/§2.6の承認済設計を、実装レベル(状態遷移・
  カウンタ制御)に具体化。emu23_v109.c 実照合済。レビュー後に実装着手(原則43)。

---

## 1. emu23実照合結果(確定事実)

### 1.1 IRET (0x04, 1バイト, L1213-1224)
```c
cpu.flags = (uint8_t)pop16();  // FLAGSを先にpop、下位8bitのみ(上位0クリア)
cpu.pc    = pop16();           // PCを後にpop
// timer_in_service再アームはソフト固有→FPGA不要(HANDOVER §5)
```
- pop 2回。順序: FLAGS(先)→PC(後)。
- FLAGSは pop値の**下位8bitのみ**。RTL: `rf_flags ← {8'h00, pop値[7:0]}`。

### 1.2 割込受理 (S_IRQCHK判定→受理, L1174-1189)
```c
if (irq_pending>=0 && (flags&FL_IE)) {  // RTL等価: irq_pending!=0 && flags_ie
    int irq = irq_pending; irq_pending=-1; // RTL: irq_pending→0
    push16(cpu.pc);              // PCを先にpush
    push16((uint16_t)cpu.flags); // FLAGSを後にpush(16bit化、上位0)
    cpu.flags &= ~FL_IE;         // IE=0
    vec = rd16(irq*2);           // ベクタ=mem[irq*2] 16bit LE
    cpu.pc = vec;
}
```
- push 2回。順序: PC(先)→FLAGS(後)。IRETのpop順(FLAGS→PC)とLIFO対称。
- ベクタ = mem[irq_pending*2] の16bit(LE)。irq_pending値(1/2/3/4)そのまま使用。
- 受理条件は S_IRQCHK に実装済(L496): `irq_pending!=0 && flags_ie`。

---

## 2. 多重push/pop制御方式(本段の新規要素)

第5-1/5-2段は push/pop 各1回で、S_PUSH_HI/S_POP_HI完了で即S_IRQCHKへ戻った。
第5-3段は IRET=pop2回、割込受理=push2回。**同一のLO/HI機構をループ**させる。

### 2.1 カウンタ(pop_count/push_count)
- 意味: **残り回数**。2→(1回処理)→1→(1回処理)→0。
- 減算タイミング: **S_PUSH_HI/S_POP_HI の mem_ready ワンショット**(SP更新と同一
  サイクル)。7/01 KY(滞留中加算禁止)と同期。
- 判定: HI完了時 `count==1`(=今回が最後) なら S_IRQCHK/ベクタ読みへ、
  `count>1`(=まだ続く) なら S_PUSH_LO/S_POP_LO へ戻る。

### 2.2 IRET状態遷移(pop2回)
```
S_OPFETCH(else,ID_IRET) → S_EXEC_IRET
  [S_EXEC_IRET] ff: stack_ctx←CTX_IRET, pop_count←2
  → S_POP_LO → S_POP_HI  (1回目=FLAGS pop)
     HI完了: FLAGS←{8'h00,pop[7:0]}, SP+=2, pop_count←1
             pop_count(旧)==2>1 なので → S_POP_LO へ戻る
  → S_POP_LO → S_POP_HI  (2回目=PC pop)
     HI完了: PC←pop16, SP+=2, pop_count←0
             pop_count(旧)==1 なので → S_IRQCHK
```
- pop値の書込先はpop_countで分岐:
  - pop_count==2(1回目): FLAGS←{8'h00, mem_rdata? or 合成値[7:0]}
  - pop_count==1(2回目): PC←合成値
- ※pop_countの「旧値」判定: HI完了combで現pop_countを見て分岐、ffで減算。
  combとffは同一サイクルの現pop_countを参照(減算は次エッジ反映)。

### 2.3 割込受理状態遷移(push2回+ベクタ読み)
```
S_IRQCHK(受理条件成立) → S_IRQ_ACCEPT
  [S_IRQ_ACCEPT] ff: stack_ctx←CTX_IRQ, push_count←2, push_src←rf_pc(1回目=PC)
  → S_PUSH_LO → S_PUSH_HI  (1回目=PC push)
     HI完了: SP-=2, push_count←1, 次データ push_src←rf_flags(2回目=FLAGS)
             push_count(旧)==2>1 → S_PUSH_LO へ戻る
  → S_PUSH_LO → S_PUSH_HI  (2回目=FLAGS push)
     HI完了: SP-=2, push_count←0, IE=0(flags更新), → ベクタ読みへ
  → S_MEMR_LO → S_MEMR_HI  (stack_ctx=CTX_IRQVEC, addr=irq_pending*2)
     HI完了: PC←{hi,lo}(vec), → S_FETCH
```
- push_srcの更新: S_IRQ_ACCEPTでPC、1回目HI完了でFLAGS。2段階セット。
- IE=0: 2回目FLAGS push完了時にrf_flags[7]←0(pushするFLAGSは旧値=IE前、
  IEクリアはpush後)。emu23順序: push(flags)後にflags&=~FL_IE。
  → **pushするFLAGSはIE=1のまま(旧値)、IEクリアはpush後の更新**。要注意。
- ベクタアドレス: irq_pending*2。irq_pendingはこの時点で保持(受理でクリアしない
  ならベクタ計算後にクリア)。emu23はirq_pending=-1を先に代入するが、vec計算に
  irq(ローカル退避)を使う。RTLはirq_pendingを**ベクタ読み完了まで保持**し、
  S_FETCH移行時(またはS_IRQ_ACCEPT入口でlatch)。
  → 設計: irq_pending は S_MEMR(CTX_IRQVEC)のaddr計算に使うため受理シーケンス
    完了まで保持。ベクタ読み完了時(次S_FETCH)ではirq処理済み。念のため
    ベクタ読みHI完了でirq_pending←0クリア。

### 2.4 ベクタ読みのS_MEMR_LO/HI流用(論点K)
- stack_ctx=CTX_IRQVEC でメモリリード機構(S_MEMR_LO/HI)を流用。
- アドレス源: 通常はaddr_r。ベクタ読みは irq_pending*2。
  → mem出力alwaysで stack_ctx==CTX_IRQVEC のとき mem_addr=irq_vec_addr。
     irq_vec_addr = {irq_pending, 1'b0} = irq_pending*2 (assign抽出)。
- 完了時(S_MEMR_HI, ctx=CTX_IRQVEC): PC←load_data相当({hi,lo}), →S_FETCH。
  通常のロード(S_WRITEBACK経由)と分岐が必要。

---

## 3. 状態遷移まとめ(next_state)

| 状態 | 条件 | 次状態 |
|---|---|---|
| S_OPFETCH(else) | ID_IRET | S_EXEC_IRET |
| S_EXEC_IRET | - | S_POP_LO |
| S_POP_HI | mem_ready & pop_count>1 | S_POP_LO (継続) |
| S_POP_HI | mem_ready & pop_count==1 | S_IRQCHK (最後) |
| S_IRQCHK | irq_pending!=0 & IE | S_IRQ_ACCEPT |
| S_IRQ_ACCEPT | - | S_PUSH_LO |
| S_PUSH_HI | mem_ready & ctx=IRQ & push_count>1 | S_PUSH_LO (継続) |
| S_PUSH_HI | mem_ready & ctx=IRQ & push_count==1 | S_MEMR_LO (ベクタ読み) |
| S_MEMR_HI | mem_ready & ctx=IRQVEC | S_FETCH (PC←vec) |

※既存のS_PUSH_HI(CTX_PUSH/JSR: →S_IRQCHK)、S_POP_HI(CTX_POP/RET: →S_IRQCHK)、
  S_MEMR_HI(通常ロード: →S_WRITEBACK)は維持。ctx/countで分岐追加。

---

## 4. レビュー確認事項(M/C/N/E/D)

- **D-1**: pushするFLAGSはIE=1(旧値)、IEクリアはpush後 — この順序でよいか
  (emu23: push16(flags)後に flags&=~FL_IE)。→ 割込ハンドラ内でIRET時に復元
  されるFLAGSはIE=1になる(受理前の状態)。妥当。
- **D-2**: IRETのFLAGS復元は下位8bitのみ({8'h00, pop[7:0]})。上位8bitが0に
  なる。emu23 (uint8_t)キャストと一致。上位ビットに意味のあるフラグが無いこと
  を前提(FL_IE=bit7, FL_Z=bit0, FL_N=bit1 が下位8bitに収まる)。確認要。
- **C-1**: ベクタアドレス irq_pending*2 は {irq_pending, 1'b0}。irq_pendingは
  3bitなので最大4→vec=mem[8]。ベクタテーブルは mem[2..8]。mem[0/1]はリセット
  ベクタと重複しないか(irq_pending=0は受理されないのでvec=mem[0]は不発生)。OK。
- **C-2**: pop_count/push_countの初期値2、減算はHI完了ワンショット。滞留中
  (mem_ready=0)は減算しない。SP更新と同期。7/01 KY遵守。
- **E-1**: アライメント例外(irq_pending=3)の受理もこの機構で完結。ハンドラvec=
  mem[6]。第4-A段で検出済のirq_pending=3が、次S_IRQCHKで受理される流れを要TB。
- **N-1**: timer_in_service(emu23 IRET/受理内)はソフト固有。FPGA実装せず(HANDOVER
  §5)。

---

## 5. TB計画(第5-3段)

1. **IRET単体**: スタックにFLAGS/PC相当値を積んだ状態からIRET→FLAGS/PC復元、
   SP+4往復。手動でmem[]にスタック内容を仕込む。
2. **割込受理単体**: IE=1でirq_in投入→受理(PC/FLAGS push, IE=0, vec飛び)→
   ハンドラ実行。ベクタテーブルmem[irq*2]を仕込む。
3. **受理→IRET往復(統合)**: irq_in→受理→ハンドラ→IRET→復帰。PC/FLAGS/SPが
   受理前に戻ることを確認(最重要・LIFO対称の検証)。
4. **アライメント例外**: 奇数アドレスLDW→irq_pending=3→受理→ハンドラ(vec=mem[6])。
