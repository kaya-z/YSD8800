        ; =========================
        ; Loop & branch test
        ; =========================

        .org 0x0000

start:
        LDW A, #5        ; loop counter
loop:
        ADDI A, #-1
        BNE loop
        HALT
