        ; =========================
        ; Register move test
        ; =========================

        .org 0x0000

start:
        LDW A, #0x1234
        MOV B, A
        ADDI B, #1
        MOV X, B
        HALT
