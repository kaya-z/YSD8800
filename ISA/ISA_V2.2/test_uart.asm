; UART / TYPE 動作確認テスト
    .vector reset _start

UART_STAT   EQU $FC84
L1_WK_A     EQU $E020
L1_WK_B     EQU $E022
L1_WK_TMP   EQU $E028

; TYPE  ( addr n -- )
    .org $0020
FORTH_TYPE:
    LDW  A, [X]
    ADDI X, #2
    LDW  B, [X]
    ADDI X, #2
    CMPI A, #0
    BEQ  _type_done
    STW  A, [L1_WK_A]
    STW  B, [L1_WK_B]
_type_loop:
    LDW  A, [L1_WK_A]
    CMPI A, #0
    BEQ  _type_done
    STW  X, [L1_WK_TMP]
    LDW  X, [L1_WK_B]
    LDB  A, [X]
    LDW  X, [L1_WK_TMP]
_type_emit_wait:
    LDW  B, [UART_STAT]
    CMPI B, #0
    BEQ  _type_emit_wait
    STW  X, [L1_WK_TMP]
    LDW  X, #$FC80
    STB  A, [X]
    LDW  X, [L1_WK_TMP]
    LDW  A, [L1_WK_B]
    ADDI A, #1
    STW  A, [L1_WK_B]
    LDW  A, [L1_WK_A]
    SUBI A, #1
    STW  A, [L1_WK_A]
    JMP  _type_loop

_type_done:
    RET

    .org $0090
_start:
    LDW  SP, #$FFFE
    LDW  X, #$F800
    DI

    ; "Hello, YSD8800!\n" を出力
    LDW  A, #$msg
    SUBI X, #2
    STW  A, [X]
    LDW  A, #17
    SUBI X, #2
    STW  A, [X]
    JSR  FORTH_TYPE

    ; "Layer 1 OK\n" を出力
    LDW  A, #$msg2
    SUBI X, #2
    STW  A, [X]
    LDW  A, #11
    SUBI X, #2
    STW  A, [X]
    JSR  FORTH_TYPE

    LDW  A, #$DEAD
    HALT

    .org $00E0
msg:
    DB  "Hello, YSD8800!", $0A
msg2:
    DB  "Layer 1 OK", $0A
