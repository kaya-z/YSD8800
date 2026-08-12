; ============================================================
; YSD8800 マイクロカーネル kernel.asm  v0.3
; 純粋アセンブラ版 Track A
;
; v0.3変更点: TASK-SLEEP / TASK-WAKEUP 追加
; ============================================================

; ---- 定数 ----
TCB_POOL        EQU $1000
TASK_DEAD       EQU 0
TASK_READY      EQU 1
TASK_RUNNING    EQU 2
TASK_SLEEPING   EQU 3

CUR_TASK        EQU $E100
NEXT_TASK       EQU $E102
TASK_COUNT      EQU $E104

L1_WK_A        EQU $E020
L1_WK_B        EQU $E022
L1_WK_C        EQU $E024
L1_WK_TMP      EQU $E028
IRQ_WK_X       EQU $E030
IRQ_WK_A       EQU $E032

; TASK_SLEEP専用退避エリア
SLP_WK_DSP     EQU $E038   ; TASK_SLEEP内でのDSP退避
SLP_WK_PC      EQU $E03A   ; TASK_SLEEP内での戻りPC退避

UART_STAT       EQU $FC84
UART_TX         EQU $FC80

; ---- ベクタ ----
    .vector reset   _kstart
    .vector irq0    IRQ0_HANDLER
    .vector irq1    _dummy_irq
    .vector align   _dummy_irq
    .vector syscall _dummy_irq

; ---- ダミーIRQ ----

; ---- カーネルAPI（kernel.asm.binの固定アドレス）----
IRQ0_HANDLER    EQU $0030
TASK_SLEEP      EQU $01C0
TASK_WAKEUP     EQU $02C0
TASK_PRINT_ID   EQU $0300
TASK_ID         EQU $0440
TASK_EXIT       EQU $0460
TASK_CREATE     EQU $0520

    .org $0020
_dummy_irq:
    DI
    IRET

; ============================================================
; IRQ0ハンドラ（v0.2から変更なし）
; ============================================================
    .org $0030
IRQ0_HANDLER:
    DI
    STW  A, [IRQ_WK_A]
    STW  X, [IRQ_WK_X]

    ; 現TCB
    LDW  A, [CUR_TASK]
    LDW  B, #6
    SHL  A, B
    LDW  B, #$1000
    ADD  A, B
    MOV  X, A

    ; コンテキスト保存
    LDW  A, [IRQ_WK_X]
    STW  A, [X + #6]        ; SAVED_X
    MOV  A, SP
    ADDI A, #4
    STW  A, [X + #4]        ; SAVED_SP
    STW  X, [L1_WK_C]
    MOV  X, SP
    ADDI X, #2
    LDW  A, [X]
    LDW  X, [L1_WK_C]
    STW  A, [X + #2]        ; SAVED_PC
    STW  X, [L1_WK_C]
    MOV  X, SP
    LDW  A, [X]
    LDW  X, [L1_WK_C]
    STW  A, [X + #12]       ; SAVED_FLAGS
    LDW  A, [IRQ_WK_A]
    STW  A, [X + #8]        ; SAVED_A

    ; SLEEPINGはREADYに戻さない
    LDW  A, [X]
    CMPI A, #3
    BEQ  _irq_sched
    LDW  A, #1
    STW  A, [X]
_irq_sched:

    ; スケジューラ
    LDW  A, [CUR_TASK]
    ADDI A, #1
_sched:
    CMPI A, #8
    BLT  _sched_chk
    LDW  A, #0
_sched_chk:
    STW  A, [L1_WK_A]
    LDW  B, #6
    SHL  A, B
    LDW  B, #$1000
    ADD  A, B
    MOV  X, A
    LDW  B, [X]
    CMPI B, #1
    BEQ  _sched_found
    LDW  A, [L1_WK_A]
    ADDI A, #1
    JMP  _sched
_sched_found:

    ; コンテキスト復元
    LDW  A, [L1_WK_A]
    STW  A, [CUR_TASK]
    LDW  A, #2
    STW  A, [X]             ; STATE = RUNNING
    LDW  A, [X + #6]        ; 次DSP
    LDW  B, [X + #4]
    SUBI B, #4
    MOV  SP, B
    LDW  B, [X + #2]
    STW  X, [L1_WK_C]
    MOV  X, SP
    ADDI X, #2
    STW  B, [X]
    LDW  X, [L1_WK_C]
    LDW  B, [X + #12]
    ORI  B, #$80
    STW  X, [L1_WK_C]
    MOV  X, SP
    STW  B, [X]
    LDW  X, [L1_WK_C]
    MOV  X, A               ; X = 次DSP
    IRET

; ============================================================
; TASK-SLEEP  ( -- )
; 自タスクをSLEEPING状態にしてスケジューラに制御を渡す
;
; JSR経由の呼び出しなのでSPスタック:
;   [SP+0] = 戻りPC (JSRがpush)
;
; 保存:
;   saved_pc  = mem[SP]    = JSRが積んだ戻りPC
;   saved_sp  = SP + 2     = RET後のSP
;   saved_x   = DSP（X）   = 現在のデータスタックポインタ
;   saved_flags = FLAGS | IE=1（EI状態で再開）
; ============================================================
    .org $01C0
TASK_SLEEP:
    DI

    ; ---- DSP(X)とSPスタック内の戻りPCを先にワークに退避 ----
    STW  X, [SLP_WK_DSP]   ; DSPを退避
    ; 戻りPC = mem[SP]
    STW  X, [L1_WK_C]      ; Xをいったん保存（すぐ上書き）
    MOV  X, SP
    LDW  A, [X]             ; A = 戻りPC
    STW  A, [SLP_WK_PC]    ; 退避
    LDW  X, [L1_WK_C]      ; Xを戻す（まだDSPではなくL1_WK_Cの値だが直後に上書き）

    ; ---- 現TCBアドレスを計算してXにセット ----
    LDW  A, [CUR_TASK]
    LDW  B, #6
    SHL  A, B
    LDW  B, #$1000
    ADD  A, B               ; A = 現TCBアドレス
    MOV  X, A               ; X → 現TCB

    ; ---- TCBにコンテキストを保存 ----
    ; saved_pc = 戻りPC
    LDW  A, [SLP_WK_PC]
    STW  A, [X + #2]

    ; saved_sp = SP + 2（RET後のSP）
    MOV  A, SP
    ADDI A, #2
    STW  A, [X + #4]

    ; saved_x = 元のDSP
    LDW  A, [SLP_WK_DSP]
    STW  A, [X + #6]

    ; saved_flags = FLAGS | IE=1（再開時はEI）
    LDW  A, #$80
    STW  A, [X + #12]

    ; ---- STATE = SLEEPING ----
    LDW  A, #3
    STW  A, [X]

    ; ---- スケジューラで次のREADYタスクへ切り替え ----
    ; SPをカーネルスタックに切り替えてアイドルループを安全に実行
    LDW  A, #$FBFE
    MOV  SP, A
_slp_sched_outer:
    ; CUR_TASKの次から全8タスクを検索
    ; 1周してREADYなしならアイドル（EIでIRQ待ち）
    LDW  A, [CUR_TASK]
    STW  A, [L1_WK_B]       ; 開始tidを記録（1周検出用）
    ADDI A, #1
_slp_sched:
    CMPI A, #8
    BLT  _slp_sched_chk
    LDW  A, #0
_slp_sched_chk:
    ; 開始tidに戻ってきた = 1周完了 = READYなし
    LDW  B, [L1_WK_B]
    CMP  A, B
    BEQ  _slp_idle
    STW  A, [L1_WK_A]
    LDW  B, #6
    SHL  A, B
    LDW  B, #$1000
    ADD  A, B
    MOV  X, A
    LDW  B, [X]
    CMPI B, #1              ; READY?
    BEQ  _slp_sched_found
    LDW  A, [L1_WK_A]
    ADDI A, #1
    JMP  _slp_sched
_slp_idle:
    ; 全タスクSLEEPING → EIにしてIRQを待つ
    ; IRQハンドラのWAKEUPでREADYタスクが現れたら再スキャン
    EI
    NOP
    DI
    JMP  _slp_sched_outer
_slp_sched_found:
    DI

    ; ---- 次タスクのコンテキスト復元 ----
    LDW  A, [L1_WK_A]
    STW  A, [CUR_TASK]
    LDW  A, #2
    STW  A, [X]             ; STATE = RUNNING

    ; 次DSPをAに保存（後でXに設定）
    LDW  A, [X + #6]

    ; 次コールスタックにPC,FLAGSを積む
    LDW  B, [X + #4]
    SUBI B, #4
    MOV  SP, B

    LDW  B, [X + #2]
    STW  X, [L1_WK_C]
    MOV  X, SP
    ADDI X, #2
    STW  B, [X]
    LDW  X, [L1_WK_C]

    LDW  B, [X + #12]
    ORI  B, #$80
    STW  X, [L1_WK_C]
    MOV  X, SP
    STW  B, [X]
    LDW  X, [L1_WK_C]

    ; X = 次DSP（Aに保存していた値）
    MOV  X, A
    IRET

; ============================================================
; TASK-WAKEUP  ( tid -- )
; 指定タスクをSLEEPING→READY状態に変更する
; IRQハンドラ内または別タスクから呼ぶ
; 注: DSPのXを内部で使うため呼び出し側はXを使わないこと
;     (JSR前にDSPへのpushは完了させておくこと)
; ============================================================
    .org $02C0
TASK_WAKEUP:
    ; ( tid -- )  X(DSP)を破壊しない実装
    LDW  A, [X]             ; A = tid (TOS)
    ADDI X, #2              ; pop
    ; tcb_addr = TCB_POOL + tid*64 → Bに計算
    LDW  B, #6
    SHL  A, B               ; A = tid * 64
    LDW  B, #$1000          ; TCB_POOL
    ADD  A, B               ; A = TCBアドレス
    ; B = TCBアドレス（STW A,[B]のrD用）
    MOV  B, A
    ; state確認: mem[B] = TCB.state
    LDW  A, [B]             ; A = state
    CMPI A, #3              ; SLEEPING?
    BNE  _wakeup_done
    LDW  A, #1              ; TASK_READY
    STW  A, [B]             ; TCB.state = READY
_wakeup_done:
    RET                     ; X(DSP)は変更なし

; ============================================================
; TASK-PRINT-ID  デバッグ用 "TN\n" をUART出力
; ============================================================
    .org $0300
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
; タスク0: 3回出力したらSLEEP、タスク1にWAKEUPされて再開
; ============================================================

; ============================================================
; v0.4 テスト用タスク
; ============================================================
    .org $0700
TASK0_ENTRY:
    JSR  TASK_PRINT_ID
    JSR  TASK_PRINT_ID
    JSR  TASK_PRINT_ID
    JSR  TASK_EXIT
    HALT

    .org $0740
TASK1_ENTRY:
    JSR  TASK_PRINT_ID
    JSR  TASK_PRINT_ID
    JSR  TASK_PRINT_ID
    JSR  TASK_EXIT
    HALT

    .org $0780
TASK2_ENTRY:
    JSR  TASK_PRINT_ID
    JSR  TASK_PRINT_ID
    JSR  TASK_PRINT_ID
    JSR  TASK_EXIT
    HALT

; "DONE\n" を出力してHALT（全タスク終了後）
    .org $07C0
DONE_TASK:
    LDW  X, #$FC80
_dn_D:
    LDW  A, [UART_STAT]
    CMPI A, #0
    BEQ  _dn_D
    LDW  A, #$44
    STB  A, [X]
_dn_O:
    LDW  A, [UART_STAT]
    CMPI A, #0
    BEQ  _dn_O
    LDW  A, #$4F
    STB  A, [X]
_dn_N:
    LDW  A, [UART_STAT]
    CMPI A, #0
    BEQ  _dn_N
    LDW  A, #$4E
    STB  A, [X]
_dn_E:
    LDW  A, [UART_STAT]
    CMPI A, #0
    BEQ  _dn_E
    LDW  A, #$45
    STB  A, [X]
_dn_NL:
    LDW  A, [UART_STAT]
    CMPI A, #0
    BEQ  _dn_NL
    LDW  A, #$0A
    STB  A, [X]
    HALT

; ============================================================
; _kstart: v0.4テスト初期化
; ============================================================
    .org $0840
_kstart:
    LDW  SP, #$FBFE
    LDW  X, #$F700
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

    ; ---- TCB0 (タスク0: 静的生成) ----
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
    STW  A, [X + #12]

    ; ---- TCB1 (タスク1: 静的生成) ----
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
    STW  A, [X + #12]

    ; ---- TASK-CREATEでTASK2を動的生成 ----
    LDW  X, #$F7FE
    LDW  A, #$TASK2_ENTRY
    SUBI X, #2
    STW  A, [X]
    JSR  TASK_CREATE        ; ( entry_addr -- tid )
    ADDI X, #2              ; pop tid（使わない）

    ; ---- TASK-CREATEでDONE_TASKを動的生成 ----
    LDW  X, #$F7FE
    LDW  A, #$DONE_TASK
    SUBI X, #2
    STW  A, [X]
    JSR  TASK_CREATE
    ADDI X, #2              ; pop tid

    LDW  A, #0
    STW  A, [CUR_TASK]

    ; ---- タスク0を起動 ----
    LDW  X, #$1000
    LDW  A, #2
    STW  A, [X]             ; RUNNING

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
