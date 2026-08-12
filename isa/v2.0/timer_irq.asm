; =========================================
; ISA2.0 Timer Interrupt Sample
; =========================================
.vector reset 0x0000
.vector irq0  0x0010

.org 0x0000
start:
    EI
loop:
    NOP
    JMP loop

.org 0x0010
irq0:
    ADDI B, #1
    IRET
