.vector reset   start
.vector irq0    irq0_handler
.vector align   align_handler
.vector syscall syscall_handler

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
    LDW A, #0x0000   ; X成功の目印
    ; alignテスト: 奇数アクセス
    LDW A, #0x2001   ; 奇数アドレス
    LDW B, [A]       ; align例外発生
    ; syscallテスト: ここに到達しないはず（align後IRETで復帰）
    SYSCALL #42      ; syscall (imm=42は任意)
    HALT             ; ここには到達しないはず

irq0_handler:
    LDW A, #0x1234   ; IRQ0目印
    IRET

align_handler:
    LDW A, #0xDEAD   ; align目印
    IRET

syscall_handler:
    LDW A, #0xBEEF   ; syscall目印（A=BEEF）
    IRET
