.vector reset 0x0100
.vector irq0  0x0200

.org 0x0100
start:
    EI
loop:
    JMP loop

.org 0x0200
irq0:
    ADDI B,#1
    IRET
