.vector reset 0x0002     ; reset handler = start のアドレスに自動設定

.org 0x0002             ; ベクタテーブル（0x0000）と重ならない場所からコード開始
start:
    DI
    LDW X, #0x2000
    LDW A, #0xABCD
    STW A, [X + #0x10]
    LDW B, [X + #0x10]
    CMP A, B
    BEQ success
    LDW A, #0xFFFF
    HALT
success:
    LDW A, #0x0000
    HALT
