; ============================================================
; Layer 2 カーネル統合テスト v0.2
; [A + #N] を廃止、全てX経由のメモリアクセスに統一
;
; TCBアクセスパターン:
;   MOV X, A (Aにtcb_addrを計算後Xへコピー)
;   LDW/STW [X], [X+#N]
;   LDW X, [L1_WK_TMP] (Xを復元)
; ============================================================

    .vector reset   _kstart
    .vector irq0    IRQ0_HANDLER
    .vector irq1    _dummy_irq
    .vector align   _dummy_irq
    .vector syscall _dummy_irq

; 定数
TCB_POOL        EQU $1000
UART_STAT       EQU $FC84
UART_TX         EQU $FC80
CUR_TASK        EQU $E100
NEXT_TASK       EQU $E102
TASK_COUNT      EQU $E104
L1_WK_A        EQU $E020
L1_WK_B        EQU $E022
L1_WK_C        EQU $E024
L1_WK_TMP      EQU $E028
; IRQハンドラ用の追加ワーク (XをTCBアクセスに使う間の退避先)
IRQ_WK_X       EQU $E030   ; IRQハンドラ内X退避
IRQ_WK_A       EQU $E032   ; IRQハンドラ内A退避
IRQ_WK_TCB     EQU $E034   ; 現TCBアドレス
IRQ_WK_NTCB    EQU $E036   ; 次TCBアドレス

    .org $0020
_dummy_irq:
    DI
    IRET

; ============================================================
; IRQ0ハンドラ: コンテキストスイッチ
; ============================================================
    .org $0030
IRQ0_HANDLER:
    DI
    ; A,Xをワークスペースに退避（IRQ時点の値を保存）
    STW  A, [IRQ_WK_A]
    STW  X, [IRQ_WK_X]

    ; ---- 現タスクTCBアドレスを計算 ----
    LDW  A, [CUR_TASK]      ; A = cur_tid
    LDW  B, #6
    SHL  A, B               ; A = cur_tid * 64
    LDW  B, #$1000          ; TCB_POOL
    ADD  A, B               ; A = cur TCB addr
    STW  A, [IRQ_WK_TCB]   ; 退避

    ; ---- 現タスクのコンテキスト保存 ----
    MOV  X, A               ; X = cur TCB addr

    ; SAVED_X (DSP) = IRQ前のX (IRQ_WK_Xに退避済み)
    LDW  A, [IRQ_WK_X]
    STW  A, [X + #6]        ; TCB[+6] = SAVED_X

    ; SAVED_SP = IRQ前のSP = 現SP + 4
    MOV  A, SP
    ADDI A, #4
    STW  A, [X + #4]        ; TCB[+4] = SAVED_SP

    ; SAVED_PC = mem[SP+2]
    ; X は現在TCBを指しているので一時的にXを使ってSPを参照
    STW  X, [L1_WK_C]      ; TCBアドレスを別ワークに退避
    MOV  X, SP
    ADDI X, #2
    LDW  A, [X]             ; A = mem[SP+2] = IRQ時のPC
    LDW  X, [L1_WK_C]      ; TCBアドレスを復元
    STW  A, [X + #2]        ; TCB[+2] = SAVED_PC

    ; SAVED_FLAGS = mem[SP]
    STW  X, [L1_WK_C]
    MOV  X, SP
    LDW  A, [X]             ; A = mem[SP] = IRQ時のFLAGS
    LDW  X, [L1_WK_C]
    STW  A, [X + #12]       ; TCB[+12] = SAVED_FLAGS

    ; SAVED_A = IRQ前のA
    LDW  A, [IRQ_WK_A]
    STW  A, [X + #8]        ; TCB[+8] = SAVED_A

    ; STATE = READY
    LDW  A, #1              ; TASK_READY
    STW  A, [X]             ; TCB[+0] = STATE

    ; ---- ラウンドロビンスケジューラ ----
    LDW  A, [CUR_TASK]
    ADDI A, #1
_sched:
    CMPI A, #8              ; MAX_TASKS
    BLT  _sched_chk
    LDW  A, #0
_sched_chk:
    STW  A, [L1_WK_A]      ; tid退避
    LDW  B, #6
    SHL  A, B
    LDW  B, #$1000
    ADD  A, B               ; A = tcb_addr
    MOV  X, A
    LDW  B, [X]             ; B = state
    CMPI B, #1              ; TASK_READY?
    BEQ  _sched_found
    LDW  A, [L1_WK_A]
    ADDI A, #1
    JMP  _sched
_sched_found:
    LDW  B, [L1_WK_A]
    STW  B, [NEXT_TASK]
    ; X はすでに次TCBを指している
    STW  A, [IRQ_WK_NTCB]  ; 次TCBアドレスを退避

    ; ---- 次タスクのコンテキスト復元 ----
    ; CUR_TASK = NEXT_TASK
    LDW  A, [NEXT_TASK]
    STW  A, [CUR_TASK]

    ; STATE = RUNNING
    LDW  A, #2              ; TASK_RUNNING
    STW  A, [X]             ; TCB[+0] = STATE

    ; DSP (X) を次タスクのDSPに復元
    ; ← ここでXを書き換えるので以降TCBアクセス不可
    LDW  A, [X + #6]        ; A = SAVED_X (next task DSP)
    ; SPスタックに次タスクのPC,FLAGSを積む
    ; next_sp - 4 をSPにセット
    LDW  B, [X + #4]        ; B = SAVED_SP
    SUBI B, #4
    MOV  SP, B              ; SP = next_sp - 4

    LDW  B, [X + #2]        ; B = SAVED_PC
    ; SPへの間接書き込み: X経由
    STW  X, [L1_WK_C]
    MOV  X, SP
    ADDI X, #2
    STW  B, [X]             ; mem[SP+2] = SAVED_PC
    LDW  X, [L1_WK_C]

    LDW  B, [X + #12]       ; B = SAVED_FLAGS
    ORI  B, #$80            ; IE=1 (ISA2.2 ORI)
    STW  X, [L1_WK_C]
    MOV  X, SP
    STW  B, [X]             ; mem[SP+0] = FLAGS (IE=1)
    LDW  X, [L1_WK_C]

    ; DSPを復元
    MOV  X, A               ; X = next task DSP

    IRET                    ; FLAGS←pop(IE=1), PC←pop

; ============================================================
; TASK_PRINT_ID: "TN\n" をUART出力
; ============================================================
    .org $0140
TASK_PRINT_ID:
    STW  X, [L1_WK_TMP]
    LDW  X, #$FC80
_tp1:
    LDW  A, [UART_STAT]
    CMPI A, #0
    BEQ  _tp1
    LDW  A, #$54            ; 'T'
    STB  A, [X]
_tp2:
    LDW  A, [UART_STAT]
    CMPI A, #0
    BEQ  _tp2
    LDW  A, [CUR_TASK]
    LDW  B, #$30
    ADD  A, B
    STB  A, [X]
_tp3:
    LDW  A, [UART_STAT]
    CMPI A, #0
    BEQ  _tp3
    LDW  A, #$0A
    STB  A, [X]
    LDW  X, [L1_WK_TMP]
    RET

; ============================================================
; タスク0エントリ
; ============================================================
    .org $01C0
TASK0_ENTRY:
_t0_loop:
    JSR  TASK_PRINT_ID
    LDW  A, #$0800
_t0_wait:
    SUBI A, #1
    BNE  _t0_wait
    JMP  _t0_loop

; ============================================================
; タスク1エントリ
; ============================================================
    .org $0210
TASK1_ENTRY:
_t1_loop:
    JSR  TASK_PRINT_ID
    LDW  A, #$0800
_t1_wait:
    SUBI A, #1
    BNE  _t1_wait
    JMP  _t1_loop

; ============================================================
; カーネル初期化
; ============================================================
    .org $0260
_kstart:
    LDW  SP, #$FBFE
    LDW  X, #$F700
    DI

    ; カーネル変数初期化
    LDW  A, #0
    STW  A, [CUR_TASK]
    STW  A, [NEXT_TASK]
    STW  A, [TASK_COUNT]

    ; 全TCB = DEAD
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
    STW  A, [X]             ; STATE = DEAD
    LDW  B, [L1_WK_A]
    ADDI B, #1
    JMP  _init_tcb
_init_done:

    ; ---- TCB0設定 (タスク0) ----
    LDW  X, #$1000          ; TCB0アドレス
    LDW  A, #1
    STW  A, [X]             ; STATE = READY
    LDW  A, #$TASK0_ENTRY
    STW  A, [X + #2]        ; SAVED_PC
    LDW  A, #$23FE          ; call stack: $2000+0*$400+$3FE
    STW  A, [X + #4]        ; SAVED_SP
    LDW  A, #$21FE          ; data stack: $2000+0*$400+$1FE
    STW  A, [X + #6]        ; SAVED_X
    LDW  A, #0
    STW  A, [X + #8]        ; SAVED_A
    STW  A, [X + #10]       ; SAVED_B
    LDW  A, #$80            ; FLAGS: IE=1
    STW  A, [X + #12]       ; SAVED_FLAGS

    ; ---- TCB1設定 (タスク1) ----
    LDW  X, #$1040          ; TCB1アドレス ($1000 + 1*64)
    LDW  A, #1
    STW  A, [X]             ; STATE = READY
    LDW  A, #$TASK1_ENTRY
    STW  A, [X + #2]
    LDW  A, #$27FE          ; call stack: $2000+1*$400+$3FE
    STW  A, [X + #4]
    LDW  A, #$25FE          ; data stack: $2000+1*$400+$1FE
    STW  A, [X + #6]
    LDW  A, #0
    STW  A, [X + #8]
    STW  A, [X + #10]
    LDW  A, #$80
    STW  A, [X + #12]

    ; TASK_COUNT = 2
    LDW  A, #2
    STW  A, [TASK_COUNT]

    ; ---- タスク0を起動 ----
    LDW  A, #0
    STW  A, [CUR_TASK]

    ; TCB0 STATE = RUNNING
    LDW  X, #$1000
    LDW  A, #2
    STW  A, [X]

    ; タスク0のコンテキストをロード
    LDW  X, #$21FE          ; タスク0のDSP

    ; SPを設定してPC,FLAGSを積む
    LDW  A, #$23FA          ; $23FE - 4
    MOV  SP, A

    LDW  A, #$TASK0_ENTRY
    STW  X, [L1_WK_C]
    MOV  X, SP
    ADDI X, #2
    STW  A, [X]             ; mem[SP+2] = PC
    LDW  X, [L1_WK_C]

    LDW  A, #$80
    STW  X, [L1_WK_C]
    MOV  X, SP
    STW  A, [X]             ; mem[SP+0] = FLAGS
    LDW  X, [L1_WK_C]

    EI
    IRET                    ; タスク0へジャンプ

