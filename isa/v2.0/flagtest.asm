; ==========================================
; FLAGS´°Á´¸¡¾Ú
; ==========================================

.vector reset 0x0100
.org 0x0100

    LDW SP, #0x7ff0

; ---- Z flag (ADD) ----
    LDW A, #1
    LDW B, #0xffff
    ADD A, B         ; 1 + (-1) = 0
    BEQ z_ok
    LDW A,#0xdead
    STW A,[0x2100]
    HALT
z_ok:
    LDW A,#1
    STW A,[0x2100]

; ---- N flag (SUB) ----
    LDW A,#1
    LDW B,#2
    SUB A,B          ; -1 ¢ª 0xffff
    BLT n_ok         ; N=1
    LDW A,#0xdead
    STW A,[0x2102]
    HALT
n_ok:
    LDW A,#1
    STW A,[0x2102]

; ---- positive boundary ----
    LDW A,#0x7fff
    ADDI A,#1        ; 0x8000
    BLT neg_ok
    LDW A,#0xdead
    STW A,[0x2104]
    HALT
neg_ok:
    LDW A,#1
    STW A,[0x2104]

    HALT
