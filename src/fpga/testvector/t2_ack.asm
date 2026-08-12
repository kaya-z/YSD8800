; ================================================================
;  t2_ack.asm   v0.1  (2026-07-14)
;  YSD8800 FPGA V5 / S8 統合TB テストプログラム
;
;  【検証内容】
;    T3: ★TCR-ACK($0023) を書けば周期発火する（再武装）★
;        = V5 の中核。CPU からの特殊信号（iret_pulse_o）なしで再武装が成立する。
;
;  【t1_noack.asm との差分は ★ACK 2命令★ のみ】
;      LDW  B, #$0023
;      STW  B, [TCR]
;    → t1(ACKなし) が CNT=1、t2(ACKあり) が CNT>=2 になれば、
;      ★差分が ACK であることが機械的に立証される★（対照実験）
;
;  【★書込値が $0023 である理由（原則74）★】
;    TCR write は【状態ビットも常に上書きする】(メモリマップドI/Oの原則)。
;    ACK単独 $0020 を書くと TIMER_EN/IRQ_EN が 0 に落ち、
;    ★ACK が ACK 自身を殺してタイマーが恒久停止する★。
;    よって状態ビット込みの完全値 $0023 = TIMER_EN|IRQ_EN|IRQ_ACK を書く。
;    （kernel_v12_8.asm L458-459 と同一の作法）
;
;  【ACK の挿入位置】
;    ★割込入口・レジスタ退避直後★（kernel_v12_8.asm L449-459 と同じ）
;    ・A/B は退避済み → 破壊してよい
;    ・分岐前 → 必ず1回だけ通る（ACK重複なし）
;
;  【判定】
;    最後に A ← CNT して HALT。★CPUが実命令で読んだ値★で判定。
;    期待: CNT >= 2 （周期発火している）
;
;  【黄金参照】emu23_v110.c
;    L694-704 TCR書込: (v & 0x20) → YSD8002_rearm(cpu.cycle)
;    L269-272 YSD8002_rearm(): next_irq_cycle = cycle + period
;
;  ★ISA2.3 に存在する命令のみ使用★
; ================================================================

TCR         EQU $FC90       ; emu23_v110.c L596
TCR_ACK     EQU $0023       ; TIMER_EN|IRQ_EN|IRQ_ACK  ★原則74★

CNT         EQU $0200       ; ハンドラ呼出回数
OUTC        EQU $0202
INC_        EQU $0204
SAVE_A      EQU $0210
SAVE_B      EQU $0212

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

    ; ★PERIOD は書かない（デフォルト 40000）★
    ;   初回発火は next_irq_cycle=40000。
    ;   ★ACK 後の再武装は next = cycle + period = cycle + 40000★
    ;   → 周期 40000 で発火し続ける。

    ; TCR = $0003 (TIMER_EN | IRQ_EN)
    LDW  A, #3
    STW  A, [TCR]

    EI

    ; ---- 二重ループ: 外200 × 内1000 = 20万回 ----
    ;   ★t1 より長く回す★（周期発火を複数回観測するため）
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
    LDW  B, #200
    CMP  A, B
    BLT  OUTLP

    DI
    ; ★判定値: A ← CNT （CPUが実命令で読んだ値）★
    LDW  A, [CNT]
    HALT

; ================ タイマー割込ハンドラ（★ACK を書く★）================
TIMER_ISR:
    DI
    STW  A, [SAVE_A]
    STW  B, [SAVE_B]

    ;--- ★★TCR-ACK ＋ 再武装（V5 の中核）★★ ---
    ;   kernel_v12_8.asm L458-459 と同一
    LDW  B, #$TCR_ACK       ; $0023 = TIMER_EN|IRQ_EN|IRQ_ACK
    STW  B, [TCR]           ; TCR($FC90) ← ACK＋再武装
    ;-------------------------------------------

    LDW  A, [CNT]
    ADDI A, #1
    STW  A, [CNT]

    LDW  B, [SAVE_B]
    LDW  A, [SAVE_A]
    IRET
