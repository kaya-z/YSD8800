        ;========================
        ; Vector table
        ;========================
        .org 0x0000
        JMP start

        .org 0x0010        ; IRQ0 (timer) - unused
        JMP irq0

        .org 0x0020        ; IRQ1 (alignment exception)
        JMP align_fault

        ;========================
        ; Main program
        ;========================
        .org 0x0100
start:
        EI                  ; 割り込み許可（必須）
        NOP                 ; 1byte
        NOP                 ; 1byte → ここで PC は奇数になり得る

        ; X = 奇数アドレスを作る
        LDWA X, #0x0101      ; ← 奇数アドレス

        ; ★ここで Alignment Exception が発生するはず
        LDW A, [X]          ; data_rd16(0x0101)

        ; ここには来ない
        HALT

loop:
        JMP loop

        ;========================
        ; IRQ handlers
        ;========================
irq0:
        IRET

align_fault:
        ; アラインメント例外に入った証拠として B++
        ADDI B, #1
        HALT
