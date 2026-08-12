; ============================================================
; test_ipc.asm - IPC テスト (MSG-SEND / MSG-RECV)
; ============================================================
; シナリオ:
;   タスク0: 数値 $1234 をタスク1に送信 → TASK-EXIT
;   タスク1: MSG-RECV で受信 → UART に "OK\n" 出力 → TASK-EXIT
; ============================================================

    .vector reset   _kstart
    .vector irq0    IRQ0_HANDLER
    .vector irq1    _dummy_irq
    .vector align   _dummy_irq
    .vector syscall _dummy_irq

; カーネル定数
TCB_POOL        EQU $1000
TASK_DEAD       EQU 0
TASK_READY      EQU 1
TASK_RUNNING    EQU 2
TASK_SLEEPING   EQU 3
TASK_WAIT_MSG   EQU 4

CUR_TASK        EQU $E100
L1_WK_A        EQU $E020
L1_WK_B        EQU $E022
L1_WK_C        EQU $E024
L1_WK_TMP      EQU $E028
IRQ_WK_X       EQU $E030
IRQ_WK_A       EQU $E032
SLP_WK_DSP     EQU $E038
SLP_WK_PC      EQU $E03A
TC_WK_ENTRY    EQU $E040
TC_WK_TID      EQU $E042
IPC_WK_A       EQU $E044
IPC_WK_B       EQU $E046
IPC_WK_X       EQU $E048

UART_STAT       EQU $FC84
UART_TX         EQU $FC80

; カーネルAPI（固定アドレス）
IRQ0_HANDLER    EQU $0030
TASK_SLEEP      EQU $01C0
TASK_WAKEUP     EQU $02C0
TASK_PRINT_ID   EQU $0300
TASK_ID         EQU $0440
TASK_EXIT       EQU $0460
TASK_CREATE     EQU $0520
MSG_SEND        EQU $0740
MSG_RECV        EQU $07E0

    .org $0020
_dummy_irq:
    DI
    IRET

; ============================================================
; タスク0: $1234 をタスク1(tid=1)に送信してEXIT
; ============================================================
    .org $0A00
TASK0_ENTRY:
    ; push msg=$1234
    LDW  A, #$1234
    SUBI X, #2
    STW  A, [X]
    ; push tid=1
    LDW  A, #1
    SUBI X, #2
    STW  A, [X]
    ; MSG-SEND ( msg tid -- )
    JSR  MSG_SEND
    JSR  TASK_EXIT
    HALT

; ============================================================
; タスク1: MSG-RECVで受信 → 受信値をUART出力してEXIT
; ============================================================
    .org $0A40
TASK1_ENTRY:
    ; MSG-RECV ( -- msg )
    JSR  MSG_RECV
    ; TOS = 受信したメッセージ ($1234 のはず)
    LDW  A, [X]
    ADDI X, #2              ; pop

    ; A=$1234 なら "OK\n" を出力
    LDW  B, #$1234
    CMP  A, B
    BNE  _t1_fail

    ; "OK\n" 出力
    LDW  X, #$FC80
_t1_O:
    LDW  A, [UART_STAT]
    CMPI A, #0
    BEQ  _t1_O
    LDW  A, #$4F
    STB  A, [X]
_t1_K:
    LDW  A, [UART_STAT]
    CMPI A, #0
    BEQ  _t1_K
    LDW  A, #$4B
    STB  A, [X]
_t1_NL:
    LDW  A, [UART_STAT]
    CMPI A, #0
    BEQ  _t1_NL
    LDW  A, #$0A
    STB  A, [X]
    JSR  TASK_EXIT
    HALT

_t1_fail:
    ; "NG\n" 出力
    LDW  X, #$FC80
_t1_N:
    LDW  A, [UART_STAT]
    CMPI A, #0
    BEQ  _t1_N
    LDW  A, #$4E
    STB  A, [X]
_t1_G:
    LDW  A, [UART_STAT]
    CMPI A, #0
    BEQ  _t1_G
    LDW  A, #$47
    STB  A, [X]
_t1_NL2:
    LDW  A, [UART_STAT]
    CMPI A, #0
    BEQ  _t1_NL2
    LDW  A, #$0A
    STB  A, [X]
    HALT

; ============================================================
; _kstart
; ============================================================
    .org $0B00
_kstart:
    LDW  SP, #$FBFE
    LDW  X, #$F7FE
    DI

    ; 全TCBをDEADに
    LDW  B, #0
_init_tcb:
    CMPI B, #8
    BEQ  _init_done
    STW  B, [L1_WK_A]
    MOV  A, B
    LDW  B, #6
    SHL  A, B
    LDW  B, #$1000
    ADD  A, B
    MOV  X, A
    LDW  A, #0
    STW  A, [X]
    LDW  B, [L1_WK_A]
    ADDI B, #1
    JMP  _init_tcb
_init_done:

    ; ---- TCB0 (タスク0) ----
    LDW  X, #$1000
    LDW  A, #1
    STW  A, [X]
    LDW  A, #$TASK0_ENTRY
    STW  A, [X + #2]
    LDW  A, #$23FE
    STW  A, [X + #4]
    LDW  A, #$21FE
    STW  A, [X + #6]
    LDW  A, #0
    STW  A, [X + #8]
    STW  A, [X + #10]
    LDW  A, #$80
    STW  A, [X + #12]       ; saved_flags = IE=1
    LDW  A, #0
    STW  A, [X + #18]       ; msg_valid = 0

    ; ---- TCB1 (タスク1) ----
    LDW  X, #$1040
    LDW  A, #1
    STW  A, [X]
    LDW  A, #$TASK1_ENTRY
    STW  A, [X + #2]
    LDW  A, #$27FE
    STW  A, [X + #4]
    LDW  A, #$25FE
    STW  A, [X + #6]
    LDW  A, #0
    STW  A, [X + #8]
    STW  A, [X + #10]
    LDW  A, #$80
    STW  A, [X + #12]       ; saved_flags = IE=1
    LDW  A, #0
    STW  A, [X + #18]       ; msg_valid = 0

    LDW  A, #0
    STW  A, [CUR_TASK]

    ; ---- タスク0を起動 ----
    LDW  X, #$1000
    LDW  A, #2
    STW  A, [X]

    LDW  A, #$23FA
    MOV  SP, A
    MOV  X, SP
    ADDI X, #2
    LDW  A, #$TASK0_ENTRY
    STW  A, [X]
    MOV  X, SP
    LDW  A, #$80
    STW  A, [X]

    LDW  X, #$21FE
    IRET
