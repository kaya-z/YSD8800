start:
    LDW  #0
loop:
    ADDW #1
    CMP  #10
    BLT  loop
    HALT
