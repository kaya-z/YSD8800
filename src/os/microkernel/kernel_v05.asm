; ============================================================
; YSD8800 マイクロカーネル kernel.asm  v0.5
; 純粋アセンブラ版 Track A
;
; v0.3変更点: TASK-SLEEP / TASK-WAKEUP 追加
; v0.4変更点: TASK-ID / TASK-EXIT / TASK-CREATE 追加
;             check_layout.py によるセクション配置チェック確立
; v0.5変更点: MSG-SEND / MSG-RECV 追加 (IPC)
;             IRQ0ハンドラのstate更新をRUNNING→READYのみに修正
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

    ; RUNNINGのタスクだけREADYに戻す
    ; DEAD(0)/READY(1)/SLEEPING(3)/WAIT_MSG(4)はそのまま
    LDW  A, [X]
    CMPI A, #2              ; RUNNING?
    BNE  _irq_sched
    LDW  A, #1              ; TASK_READY
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
    .org $0360
TASK0_ENTRY:
_t0_main:
    JSR  TASK_PRINT_ID      ; "T0\n"
    JSR  TASK_PRINT_ID
    JSR  TASK_PRINT_ID
    ; タスク1をWAKEUP（もし寝ていれば）
    DI                      ; WAKEUP〜SLEEPの間はIRQ禁止
    LDW  A, #1              ; tid=1
    SUBI X, #2
    STW  A, [X]
    JSR  TASK_WAKEUP
    ; 自分はSLEEP（TASK_SLEEP内でEIになる）
    JSR  TASK_SLEEP
    JMP  _t0_main

; ============================================================
; タスク1: 3回出力したらSLEEP、タスク0にWAKEUPされて再開
; ============================================================
    .org $03C0
TASK1_ENTRY:
_t1_main:
    JSR  TASK_PRINT_ID      ; "T1\n"
    JSR  TASK_PRINT_ID
    JSR  TASK_PRINT_ID
    ; タスク0をWAKEUP
    DI                      ; WAKEUP〜SLEEPの間はIRQ禁止
    LDW  A, #0              ; tid=0
    SUBI X, #2
    STW  A, [X]
    JSR  TASK_WAKEUP
    ; 自分はSLEEP（TASK_SLEEP内でEIになる）
    JSR  TASK_SLEEP
    JMP  _t1_main

; ============================================================
; カーネル初期化
; ============================================================
    .org $0400
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

    ; ---- TCB0 (タスク0) ----
    LDW  X, #$1000
    LDW  A, #1              ; READY
    STW  A, [X]
    LDW  A, #$TASK0_ENTRY
    STW  A, [X + #2]
    LDW  A, #$23FE          ; コールスタック
    STW  A, [X + #4]
    LDW  A, #$21FE          ; データスタック
    STW  A, [X + #6]
    LDW  A, #0
    STW  A, [X + #8]
    STW  A, [X + #10]
    LDW  A, #$80            ; FLAGS: IE=1
    STW  A, [X + #12]

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
    STW  A, [X + #12]

    LDW  A, #2
    STW  A, [TASK_COUNT]
    LDW  A, #0
    STW  A, [CUR_TASK]

    ; ---- タスク0を起動 ----
    ; TCB0をRUNNINGに
    LDW  X, #$1000
    LDW  A, #2
    STW  A, [X]

    ; SPをタスク0のコールスタック先頭-4に設定
    ; $23FE - 4 = $23FA
    LDW  A, #$23FA
    MOV  SP, A

    ; mem[SP+2] = TASK0_ENTRY (PC)
    ; mem[SP+0] = $0080       (FLAGS: IE=1)
    ; Xはここでは自由に使ってよい（直後にDSPをセットし直すため）
    MOV  X, SP
    ADDI X, #2
    LDW  A, #$TASK0_ENTRY
    STW  A, [X]             ; mem[$23FC] = $02C0

    MOV  X, SP
    LDW  A, #$80
    STW  A, [X]             ; mem[$23FA] = $0080 (FLAGS)

    ; DSPをタスク0の初期値にセット
    LDW  X, #$21FE

    ; IRET: FLAGS($80)←pop → IE=1, PC($02C0)←pop → TASK0_ENTRY
    IRET

; ============================================================
; v0.4 追加: TASK-CREATE / TASK-EXIT / TASK-ID
; ============================================================

; ワーク変数
TC_WK_ENTRY    EQU $E040   ; TASK-CREATE内エントリアドレス退避
TC_WK_TID      EQU $E042   ; TASK-CREATE内tid退避

; ============================================================
; TASK-ID  ( -- tid )
; 現在のタスクIDをデータスタックにpushする
; ============================================================
    .org $0440
TASK_ID:
    SUBI X, #2
    LDW  A, [CUR_TASK]
    STW  A, [X]
    RET

; ============================================================
; TASK-EXIT  ( -- )
; 自タスクをDEAD状態にしてスケジューラに制御を渡す
; TASK-SLEEPと同じ構造だが、復帰しない（DEAD→スケジューラが選ばない）
; ============================================================
    .org $0460
TASK_EXIT:
    DI

    ; 現TCBアドレスを計算
    LDW  A, [CUR_TASK]
    LDW  B, #6
    SHL  A, B
    LDW  B, #$1000
    ADD  A, B               ; A = 現TCBアドレス
    MOV  X, A

    ; STATE = DEAD
    LDW  A, #0
    STW  A, [X]

    ; SPをカーネルスタックに切り替えてスケジューラへ
    LDW  A, #$FBFE
    MOV  SP, A

    ; READYタスクをスキャン
_exit_sched:
    LDW  A, [CUR_TASK]
    ADDI A, #1
_exit_sched_loop:
    CMPI A, #8
    BLT  _exit_sched_chk
    LDW  A, #0
_exit_sched_chk:
    ; CUR_TASKに戻ってきたらREADYなし（全DEADまたはSLEEP）
    LDW  B, [CUR_TASK]
    CMP  A, B
    BEQ  _exit_idle
    STW  A, [L1_WK_A]
    LDW  B, #6
    SHL  A, B
    LDW  B, #$1000
    ADD  A, B
    MOV  X, A
    LDW  B, [X]
    CMPI B, #1              ; READY?
    BEQ  _exit_found
    LDW  A, [L1_WK_A]
    ADDI A, #1
    JMP  _exit_sched_loop
_exit_idle:
    ; 全タスクDEAD/SLEEP → EIでIRQ待ち
    EI
    NOP
    DI
    JMP  _exit_sched
_exit_found:
    DI
    ; コンテキスト復元（TASK-SLEEPの_slp_sched_found以降と同じ）
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
; TASK-CREATE  ( entry_addr -- tid )
; 空きTCBを確保してタスクを初期化する
;
; TCBオフセット:
;   +00: state        = READY(1)
;   +02: saved_pc     = entry_addr
;   +04: saved_sp     = $2000 + tid*$400 + $3FE - 4  (コールスタック頂上-4)
;   +06: saved_x      = $2000 + tid*$400 + $1FE       (データスタック初期値)
;   +08: saved_a      = 0
;   +0A: saved_b      = 0
;   +0C: saved_flags  = $0080 (IE=1)
;
; コールスタック:  $2000 + tid*$400 〜 $23FE  (1KB)
; データスタック:  $2000 + tid*$400 + $0200 〜 $21FE (512B)
; ============================================================
    .org $0520
TASK_CREATE:
    ; TOS = entry_addr
    LDW  A, [X]             ; A = entry_addr
    ADDI X, #2              ; pop
    STW  A, [TC_WK_ENTRY]   ; 退避
    STW  X, [TC_WK_TID]     ; DSP退避（TASK-CREATEはXを使うため）

    DI

    ; 空きTCBを探す（tid=0から順に）
    LDW  A, #0
_tc_scan:
    CMPI A, #8
    BEQ  _tc_noslot         ; 空きなし
    STW  A, [L1_WK_A]       ; tid保存
    LDW  B, #6
    SHL  A, B
    LDW  B, #$1000
    ADD  A, B               ; A = TCBアドレス
    MOV  X, A
    LDW  B, [X]             ; B = state
    CMPI B, #0              ; DEAD?
    BEQ  _tc_found
    LDW  A, [L1_WK_A]
    ADDI A, #1
    JMP  _tc_scan

_tc_noslot:
    ; 空きなし → tid=$FFFF を返してEI、RET
    LDW  X, [TC_WK_TID]     ; DSP復元
    EI
    LDW  A, #$FFFF
    SUBI X, #2
    STW  A, [X]
    RET

_tc_found:
    ; tid = L1_WK_A, TCBアドレス = X
    ; コールスタック初期アドレス: $2000 + tid*$400 + $3FE
    ;   = $23FE + tid*$400
    LDW  A, [L1_WK_A]       ; A = tid
    LDW  B, #10
    SHL  A, B               ; A = tid * 1024 ($400)
    LDW  B, #$23FE
    ADD  A, B               ; A = コールスタック頂上 ($23FE + tid*$400)
    STW  A, [L1_WK_B]       ; コールスタック頂上を保存

    ; TCBを初期化
    ; [X+00] = READY
    LDW  A, #1
    STW  A, [X]

    ; [X+02] = entry_addr
    LDW  A, [TC_WK_ENTRY]
    STW  A, [X + #2]

    ; [X+04] = saved_sp = コールスタック頂上
    LDW  A, [L1_WK_B]
    STW  A, [X + #4]

    ; [X+06] = saved_x（データスタック初期値）
    ;   = $21FE + tid*$400
    LDW  A, [L1_WK_A]
    LDW  B, #10
    SHL  A, B
    LDW  B, #$21FE
    ADD  A, B
    STW  A, [X + #6]

    ; [X+08] = saved_a = 0
    LDW  A, #0
    STW  A, [X + #8]

    ; [X+0A] = saved_b = 0
    STW  A, [X + #10]

    ; [X+0C] = saved_flags = $0080（IE=1）
    LDW  A, #$80
    STW  A, [X + #12]

    ; DSP復元してtidをpush
    LDW  X, [TC_WK_TID]
    EI
    LDW  A, [L1_WK_A]
    SUBI X, #2
    STW  A, [X]
    RET

; ============================================================
; v0.5 追加: IPC (MSG-SEND / MSG-RECV)
; ============================================================
;
; TCB IPCフィールド（+10以降の予約領域）:
;   +10 : msg_data   受信バッファ（16bit）
;   +12 : msg_valid  $0001=メッセージあり $0000=なし
;   +14 : msg_sender 送信元tid（デバッグ用）
;
; タスク状態追加:
;   TASK_WAIT_MSG EQU 4  メッセージ待ちSLEEP
;
; ワーク変数:
;   IPC_WK_A  EQU $E044
;   IPC_WK_B  EQU $E046
;   IPC_WK_X  EQU $E048

TASK_WAIT_MSG   EQU 4

IPC_WK_A        EQU $E044
IPC_WK_B        EQU $E046
IPC_WK_X        EQU $E048

; TCB IPCフィールドオフセット
TCB_MSG_DATA    EQU 16   ; +10
TCB_MSG_VALID   EQU 18   ; +12
TCB_MSG_SENDER  EQU 20   ; +14

; ============================================================
; MSG-SEND  ( msg tid -- )
; 指定タスク(tid)にメッセージ(msg)を送信する
;
; 動作:
;   1. msg_data = msg, msg_valid = 1, msg_sender = CUR_TASK
;      （既存メッセージは上書き）
;   2. 対象タスクがTASK_WAIT_MSG(4)なら READY に変更
;
; 注: 送信は常に成功（上書き方式）
;     受信側がメッセージを取り出す前に再送信すると上書きされる
; ============================================================
    .org $0740
MSG_SEND:
    DI
    ; TOS = tid, NOS = msg
    LDW  A, [X]             ; A = tid
    ADDI X, #2              ; pop tid
    STW  A, [IPC_WK_A]      ; tid退避
    LDW  A, [X]             ; A = msg（新TOS）
    ADDI X, #2              ; pop msg
    STW  X, [IPC_WK_X]      ; DSP退避
    STW  A, [IPC_WK_B]      ; msg退避

    ; 対象TCBアドレスを計算
    LDW  A, [IPC_WK_A]      ; A = tid
    LDW  B, #6
    SHL  A, B
    LDW  B, #$1000
    ADD  A, B               ; A = 対象TCBアドレス
    MOV  X, A               ; X → 対象TCB

    ; msg_data / msg_valid / msg_sender を設定
    LDW  A, [IPC_WK_B]      ; A = msg
    STW  A, [X + #16]       ; TCB.msg_data = msg
    LDW  A, #1
    STW  A, [X + #18]       ; TCB.msg_valid = 1
    LDW  A, [CUR_TASK]
    STW  A, [X + #20]       ; TCB.msg_sender = CUR_TASK

    ; 対象タスクがTASK_WAIT_MSG(4)なら READY に変更
    LDW  A, [X]             ; A = state
    CMPI A, #4
    BNE  _msgsend_done
    LDW  A, #1              ; TASK_READY
    STW  A, [X]

_msgsend_done:
    LDW  X, [IPC_WK_X]     ; DSP復元
    EI
    RET

; ============================================================
; MSG-RECV  ( -- msg )
; 自タスク宛のメッセージを受信する
; メッセージがなければTASK_WAIT_MSG状態でSLEEP
; ============================================================
    .org $07E0
MSG_RECV:
    DI
    STW  X, [IPC_WK_X]      ; DSP退避

    ; 自タスクのTCBアドレス
    LDW  A, [CUR_TASK]
    LDW  B, #6
    SHL  A, B
    LDW  B, #$1000
    ADD  A, B               ; A = 自TCBアドレス
    MOV  X, A               ; X → 自TCB

    ; msg_validを確認
    LDW  A, [X + #18]       ; A = msg_valid
    CMPI A, #1
    BEQ  _msgrecv_got       ; メッセージあり

    ; ---- メッセージなし → TASK_WAIT_MSG でSLEEP ----
    ; コンテキストを保存してスケジューラへ（TASK_SLEEPと同じ手順）
    ; 戻りPC = JSRで積まれた [SP]
    STW  X, [L1_WK_C]
    MOV  X, SP
    LDW  A, [X]             ; A = 戻りPC
    LDW  X, [L1_WK_C]
    STW  A, [X + #2]        ; saved_pc

    MOV  A, SP
    ADDI A, #2
    STW  A, [X + #4]        ; saved_sp

    LDW  A, [IPC_WK_X]
    STW  A, [X + #6]        ; saved_x = DSP

    LDW  A, #$80
    STW  A, [X + #12]       ; saved_flags = IE=1

    ; STATE = TASK_WAIT_MSG (4)
    LDW  A, #4
    STW  A, [X]

    ; SPをカーネルスタックに切り替えてスケジューラへ
    LDW  A, #$FBFE
    MOV  SP, A

    ; READYタスクを探す
    LDW  A, [CUR_TASK]
    ADDI A, #1
_msgrecv_sched:
    CMPI A, #8
    BLT  _msgrecv_chk
    LDW  A, #0
_msgrecv_chk:
    LDW  B, [CUR_TASK]
    CMP  A, B
    BEQ  _msgrecv_idle      ; 全タスクBLOCKED → アイドル
    STW  A, [L1_WK_A]
    LDW  B, #6
    SHL  A, B
    LDW  B, #$1000
    ADD  A, B
    MOV  X, A
    LDW  B, [X]
    CMPI B, #1              ; READY?
    BEQ  _msgrecv_found
    LDW  A, [L1_WK_A]
    ADDI A, #1
    JMP  _msgrecv_sched
_msgrecv_idle:
    EI
    NOP
    DI
    JMP  _msgrecv_sched_restart

_msgrecv_sched_restart:
    LDW  A, [CUR_TASK]
    ADDI A, #1
    JMP  _msgrecv_sched

_msgrecv_found:
    ; 次タスクのコンテキスト復元（TASK_SLEEPと同じ）
    LDW  A, [L1_WK_A]
    STW  A, [CUR_TASK]
    LDW  A, #2
    STW  A, [X]             ; RUNNING

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

    MOV  X, A
    IRET

    ; ---- メッセージあり → msg_dataをpushしてmsg_valid=0 ----
_msgrecv_got:
    LDW  A, [X + #16]       ; A = msg_data
    LDW  B, #0
    STW  B, [X + #18]       ; msg_valid = 0
    LDW  X, [IPC_WK_X]      ; DSP復元
    SUBI X, #2
    STW  A, [X]             ; push msg
    EI
    RET
