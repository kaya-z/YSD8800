; ==========================================
; branch符号拡張テスト
; ==========================================

.vector reset 0x0100
.org 0x0100

    LDW SP,#0x7ff0

; ---- forward branch ----
    JMP forward
    LDW A,#0xdead
    STW A,[0x2200]
forward:
    LDW A,#1
    STW A,[0x2200]

; ---- backward branch ----
    LDW B,#5
loop:
    SUBI B,#1
    BNE loop

    STW B,[0x2202]   ; expect 0

; ---- -1 branch test ----
    LDW A,#0
self:
    ADDI A,#1
    CMPI A,#3
    BLT self

    STW A,[0x2204]   ; expect 3

    HALT
