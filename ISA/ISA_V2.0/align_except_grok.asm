.vector reset 0x0000
.vector irq1  0x0020
.org 0x0000
start:
DI                
LDW A, #0x0001    
LDW B, [A]        
HALT              
.org 0x0020
irq1:
LDW A, #0xDEAD    
HALT              
