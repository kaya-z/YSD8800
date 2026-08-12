; ================================================================
;  t1_noack.asm   v0.3  (2026-07-14)
;  YSD8800 FPGA V5 / S8 統合TB テストプログラム
;
;  【検証内容】
;    T1: タイマー割込が CPU に届く（IRQ0 → vec $0002）
;    T2: ★ACK を書かなければ二度と発火しない（自己武装解除）★
;
;  【判定】
;    ハンドラが呼ばれるたびに CNT($0200) をインクリメントする。
;    ★ACK を書かない★ ので、CNT は【1】で止まるはず。
;    最後に A ← CNT して HALT。★CPUが実命令で読んだ値★で判定（偽合格防止）。
;
;  ------------------------------------------------------------
;  【★v0.3 修正: PERIOD を書き換えない★】原則76（実源照合で判明）
;
;    v0.2 は PERIOD=200 を書いて短時間発火を狙ったが【発火しなかった】。
;    真因（emu23_v110.c 実源）:
;      YSD8002_init() : next_irq_cycle = cycles_per_irq;  ← ★初期値=40000★
;      PERIOD_LO 書込 (L741-744):
;          ysd8002.period = ...;
;          if (period > 0) ysd8002.cycles_per_irq = period;
;          ★next_irq_cycle は更新しない★
;    → PERIOD を書いても【初回発火は next_irq_cycle=40000 のまま】。
;      PERIOD は次回 rearm（YSD8002_rearm: next = cycle + period）から効く。
;    → これは emu23 の仕様であり不具合ではない。
;
;    よって本TBは ★PERIOD を書き換えず、デフォルト 40000 を使う★。
;      emu23 : 40000【命令】後に初回発火
;      RTL   : 40000【クロック】後 (≒2200命令) に初回発火   ← 単位が違う(D8)
;    どちらも「初回発火する」点は同じであり、D10（論理結果一致）には十分。
;  ------------------------------------------------------------
;
;  【黄金参照】emu23_v110.c
;    L1947 cpu.pc = rd16(0x0000)  → ★$0000 は【reset】ベクタ★
;    L1221 vec = rd16(irq*2)      → IRQ0(irq=1) のベクタは $0002
;    L258-263 YSD8002_tick()      → 発火時 next_irq_cycle=UINT64_MAX(自己武装解除)
;    L596 TCR=$FC90
;
;  ★ISA2.3 に存在する命令のみ使用★
; ================================================================

TCR         EQU $FC90       ; emu23_v110.c L596

CNT         EQU $0200       ; ハンドラ呼出回数
OUTC        EQU $0202       ; 外側ループカウンタ
INC_        EQU $0204       ; 内側ループカウンタ
SAVE_A      EQU $0210       ; ハンドラのA退避

; ================ ベクタテーブル ================
    .org  $0000
    .word START             ; ★reset★

    .org  $0002
    .word TIMER_ISR         ; ★IRQ0: YSD8002 タイマー★

    .org  $0004
    .word $0000             ; IRQ1 (未使用)

; ================ 本体 ================
    .org  $0100
START:
    DI

    LDW  A, #0
    STW  A, [CNT]
    STW  A, [OUTC]

    ; ★PERIOD は書かない（デフォルト 40000 を使う）★

    ; TCR = $0003 (TIMER_EN | IRQ_EN)   ※★ACK は書かない★
    LDW  A, #3
    STW  A, [TCR]

    EI

    ; ---- 二重ループ: 外50 × 内1000 = 5万回 ----
    ;   emu23: 1周あたり数命令 → 十分 40000 命令を超える
    ;   RTL  : クロックはさらに約18倍進む → 十分 40000 クロックを超える
OUTLP:
    LDW  A, #0
    STW  A, [INC_]
INLP:
    LDW  A, [INC_]
    ADDI A, #1
    STW  A, [INC_]
    LDW  B, #1000
    CMP  A, B
    BLT  INLP

    LDW  A, [OUTC]
    ADDI A, #1
    STW  A, [OUTC]
    LDW  B, #50
    CMP  A, B
    BLT  OUTLP

    DI
    ; ★判定値: A ← CNT （CPUが実命令で読んだ値）★
    LDW  A, [CNT]
    HALT

; ================ タイマー割込ハンドラ（★ACK を書かない★）================
TIMER_ISR:
    DI
    STW  A, [SAVE_A]
    LDW  A, [CNT]
    ADDI A, #1
    STW  A, [CNT]
    LDW  A, [SAVE_A]
    IRET
