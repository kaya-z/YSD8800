.vector reset   start
.vector irq0    irq0_handler
.vector align   align_handler

.org 0x0010          ; コード領域（ベクタテーブルと重ならない）
start:
    LDW SP, #0xfffe
    EI
    LDW X, #0x2000
    LDW A, #0xABCD
    STW A, [X + #0x10]
    LDW B, [X + #0x10]
    CMP A, B
    BEQ success
    LDW A, #0xFFFF   ; 失敗
    HALT
success:
    LDW A, #0x0000   ; 成功の目印
    ; ここでアライメント例外テスト追加
    LDW A, #0x2001   ; 奇数アドレス (0x2001) をAにセット
    LDW B, [A]       ; 奇数アドレスへのLDWでalign例外発生
    HALT             ; ここには到達しないはず

irq0_handler:
    LDW A, #0x1234   ; IRQ0が入った証拠
    IRET

align_handler:
    LDW A, #0xDEAD   ; アライメント例外が入った証拠（A=DEAD）
    IRET             ; テストのためIRET（本番では適切に処理）
