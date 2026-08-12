; ==========================================
; 割り込みネスト検証
; ==========================================

.vector reset 0x0100
.vector irq0  irq0_handler

.org 0x0100

    LDW SP,#0x7ff0
    LDW B,#0
    EI

wait:
    CMPI B,#5
    BLT wait

    STW B,[0x2300]
    HALT

; ---- handler ----
irq0_handler:

    ADDI B,#1

    CMPI B,#2
    BNE no_nest

    EI              ; ネスト許可

no_nest:
    IRET
