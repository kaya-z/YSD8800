; ============================================================
; ftest_harness.asm v1.1 -- scc23 v2.00 float単体テスト用ハーネス
; _main(scc23生成)を呼び、戻り値A(16bit)を16進4桁でUART出力しHALT。
; [v1.1] SHR_N(即値シフト・ISA非実在)を SHR A,B(レジスタ経由)に是正(KY39)。
; UART_TX=$FC80。ISA2.3命令のみ使用。
; ============================================================
    .org  $0000
    .word _startup
    .org  $0010

UART_TX equ $FC80
RESULT  equ $F000

_startup:
    LDW  SP, #$F7FE
    JSR  _main
    STW  A, [RESULT]        ; 計算結果(Q8.8 or int)を退避
    ; --- 16進4桁出力(上位ニブルから) ---
    ; nibble3 (bit12-15)
    LDW  A, [RESULT]
    LDW  B, #12
    SHR  A, B
    JSR  _puthex_nib
    ; nibble2 (bit8-11)
    LDW  A, [RESULT]
    LDW  B, #8
    SHR  A, B
    JSR  _puthex_nib
    ; nibble1 (bit4-7)
    LDW  A, [RESULT]
    LDW  B, #4
    SHR  A, B
    JSR  _puthex_nib
    ; nibble0 (bit0-3)
    LDW  A, [RESULT]
    JSR  _puthex_nib
    ; 改行
    LDW  A, #$0A
    STW  A, [UART_TX]
    HALT

; A下位4bitを16進文字でUART出力。A破壊。
_puthex_nib:
    ANDI A, #$0F
    CMPI A, #10
    BLT  _phn_digit
    ADDI A, #$37            ; 10-15 -> 'A'-'F'
    JMP  _phn_out
_phn_digit:
    ADDI A, #$30            ; 0-9 -> '0'-'9'
_phn_out:
    STW  A, [UART_TX]
    RET
