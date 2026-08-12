        ; =========================
        ; Minimal test for hasm/emu
        ; =========================

        .org 0x0000

start:
        LDW A, #1        ; A = 1
        ADDI A, #2       ; A = 3
        HALT
