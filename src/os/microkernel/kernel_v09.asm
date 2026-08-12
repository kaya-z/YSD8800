; ============================================================
; YSD8800 マイクロカーネル kernel.asm  v0.9.1
; 純粋アセンブラ版 Track A
;
; v0.3: TASK-SLEEP / TASK-WAKEUP 追加
; v0.4: TASK-ID / TASK-EXIT / TASK-CREATE 追加
; v0.5: MSG-SEND / MSG-RECV 追加
; v0.6: 全タスクDEAD時 HALT
; v0.7: ISA2.3 v2.2.1メモリマップ対応
; v0.8: YUI OS v2.0 Ph.1 IPC拡張対応
;   - TCBサイズ 64B→80B (8タスク×80B=640B: $4000-$427F)
;   - TCBアドレス計算: tid*80=(tid<<6)+(tid<<4)
;     パターン: STW A,[L1_WK_TMP]; LDW B,#6; SHL A,B;
;               STW A,[L1_WK_C]; LDW A,[L1_WK_TMP];
;               LDW B,#4; SHL A,B; LDW B,[L1_WK_C];
;               ADD A,B; LDW B,#$4000; ADD A,B
;   - ワーク変数 $4280〜 (TCBプール直後)
;   - 新タスク状態: TASK_WAIT_IPC(5), TASK_WAIT_REPLY(6)
;   - TCB+16〜+30: IPC4フィールド
;   - 旧MSG_SEND/MSG_RECV廃止
;   - _sched_common 共通スケジューラ導入(org衝突解消)
;     TASK_SLEEP/TASK_EXIT から JMP で呼び出し
;   - IPC4_SEND/IPC4_RECV/IPC4_CALL/IPC4_REPLY 追加
;
; メモリマップ (ROM):
;   $0000-$000F  ベクタテーブル
;   $0020        _dummy_irq
;   $0030-$01BF  IRQ0_HANDLER (~276B)
;   $01C0-$02BF  TASK_SLEEP   (~104B)
;   $02C0-$036F  _sched_common (~168B)
;   $0380-$03CF  TASK_WAKEUP  (~72B)
;   $03D0-$040F  TASK_PRINT_ID
;   $0440        TASK_ID
;   $0460-$051F  TASK_EXIT
;   $0520-$073F  TASK_CREATE
;   $0700-$073F  TASK0/1 デモエントリ
;   $0740        IPC4_SEND
;   $07E0        IPC4_RECV
;   $0880        IPC4_CALL
;   $0B00        IPC4_REPLY
;   $0E00        _kstart
; ============================================================

; ================================================================
; 定数定義
; ================================================================
TCB_POOL            EQU $4000
TCB_SIZE            EQU 80

TASK_DEAD           EQU 0
TASK_READY          EQU 1
TASK_RUNNING        EQU 2
TASK_SLEEPING       EQU 3
TASK_WAIT_MSG       EQU 4
TASK_WAIT_IPC       EQU 5
TASK_WAIT_REPLY     EQU 6

; TCBオフセット
TCB_STATE           EQU 0
TCB_SAVED_PC        EQU 2
TCB_SAVED_SP        EQU 4
TCB_SAVED_X         EQU 6
TCB_SAVED_A         EQU 8
TCB_SAVED_B         EQU 10
TCB_SAVED_FLAGS     EQU 12
TCB_RSVD1           EQU 14
TCB_IPC_MSG0        EQU 16
TCB_IPC_MSG1        EQU 18
TCB_IPC_MSG2        EQU 20
TCB_IPC_MSG3        EQU 22
TCB_IPC_VALID       EQU 24
TCB_IPC_SENDER      EQU 26
TCB_PRIORITY        EQU 28
TCB_RSVD2           EQU 30

; ================================================================
; カーネルワーク変数 ($4280〜)
;
; tid*80計算パターン (A=tid入力, A=TCBアドレス出力, B破壊):
;   STW A,[L1_WK_TMP]      ; tid退避
;   LDW B,#6; SHL A,B      ; A=tid*64
;   STW A,[L1_WK_C]        ; tid*64退避
;   LDW A,[L1_WK_TMP]      ; tid復元
;   LDW B,#4; SHL A,B      ; A=tid*16
;   LDW B,[L1_WK_C]        ; B=tid*64
;   ADD A,B                 ; A=tid*80
;   LDW B,#$4000; ADD A,B  ; A=TCBアドレス
;
; L1_WK_A  = ループ変数(現スキャンtid)
; L1_WK_B  = 1周検出用開始tid (ループ中読むだけ)
; L1_WK_C  = tid*64中間値
; L1_WK_TMP= tid一時退避
; ================================================================
L1_WK_A             EQU $4280
L1_WK_B             EQU $4282
L1_WK_C             EQU $4284
L1_WK_TMP           EQU $4286
IRQ_WK_X            EQU $4288
IRQ_WK_A            EQU $428A
SLP_WK_DSP          EQU $428C
SLP_WK_PC           EQU $428E
MISC_WK_X           EQU $4290
CUR_TASK            EQU $4292
NEXT_TASK           EQU $4294
TASK_COUNT          EQU $4296
TC_WK_ENTRY         EQU $4298
TC_WK_TID           EQU $429A
IPC4_WK_X           EQU $429C
IPC4_WK_DST         EQU $429E
IPC4_WK_SRCTCB      EQU $42A0

MEM_TID_ADDR        EQU $E204

CALLSTK_BASE        EQU $FBCE
DATASTK_BASE        EQU $F9CE
TASK_STK_GAP        EQU $0100
KERN_SP             EQU $FBCE
UART_STAT           EQU $FC84
UART_TX             EQU $FC80

; ================================================================
; ベクタ
; ================================================================
    .vector reset   _kstart
    .vector irq0    IRQ0_HANDLER
    .vector irq1    _dummy_irq
    .vector align   _dummy_irq
    .vector syscall _dummy_irq

    .org $0020
_dummy_irq:
    DI
    IRET

; ================================================================
; IRQ0ハンドラ ($0030)
; スケジューラはここに展開（JSR不可のため）
; ================================================================
    .org $0030
IRQ0_HANDLER:
    DI
    STW  A, [IRQ_WK_A]
    STW  X, [IRQ_WK_X]

    ; 現TCBアドレス計算
    LDW  A, [CUR_TASK]
    STW  A, [L1_WK_TMP]
    LDW  B, #6
    SHL  A, B
    STW  A, [L1_WK_C]
    LDW  A, [L1_WK_TMP]
    LDW  B, #4
    SHL  A, B
    LDW  B, [L1_WK_C]
    ADD  A, B
    LDW  B, #$4000
    ADD  A, B
    MOV  X, A

    ; コンテキスト保存
    LDW  A, [IRQ_WK_X]
    STW  A, [X + #6]
    MOV  A, SP
    ADDI A, #4
    STW  A, [X + #4]
    STW  X, [MISC_WK_X]
    MOV  X, SP
    ADDI X, #2
    LDW  A, [X]
    LDW  X, [MISC_WK_X]
    STW  A, [X + #2]
    STW  X, [MISC_WK_X]
    MOV  X, SP
    LDW  A, [X]
    LDW  X, [MISC_WK_X]
    STW  A, [X + #12]
    LDW  A, [IRQ_WK_A]
    STW  A, [X + #8]

    ; RUNNING→READY
    LDW  A, [X]
    CMPI A, #2
    BNE  _irq_sched
    LDW  A, #1
    STW  A, [X]

_irq_sched:
    LDW  A, [CUR_TASK]
    STW  A, [L1_WK_B]
    ADDI A, #1
_sched:
    CMPI A, #8
    BLT  _sched_chk
    LDW  A, #0
_sched_chk:
    STW  A, [L1_WK_A]
    STW  A, [L1_WK_TMP]
    LDW  B, #6
    SHL  A, B
    STW  A, [L1_WK_C]
    LDW  A, [L1_WK_TMP]
    LDW  B, #4
    SHL  A, B
    LDW  B, [L1_WK_C]
    ADD  A, B
    LDW  B, #$4000
    ADD  A, B
    MOV  X, A
    LDW  B, [X]
    CMPI B, #1
    BEQ  _sched_found
    LDW  A, [L1_WK_A]
    ADDI A, #1
    JMP  _sched

_sched_found:
    LDW  A, [L1_WK_A]
    STW  A, [CUR_TASK]
    LDW  A, #2
    STW  A, [X]
    LDW  A, [X + #6]
    LDW  B, [X + #4]
    SUBI B, #4
    MOV  SP, B
    LDW  B, [X + #2]
    STW  X, [MISC_WK_X]
    MOV  X, SP
    ADDI X, #2
    STW  B, [X]
    LDW  X, [MISC_WK_X]
    LDW  B, [X + #12]
    ORI  B, #$80
    STW  X, [MISC_WK_X]
    MOV  X, SP
    STW  B, [X]
    LDW  X, [MISC_WK_X]
    MOV  X, A
    IRET

; ================================================================
; TASK-SLEEP ($01C0)
; コンテキスト保存のみ実施、_sched_common へ JMP
; ================================================================
    .org $01C0
TASK_SLEEP:
    DI

    ; DSPと戻りPCを退避
    STW  X, [SLP_WK_DSP]
    STW  X, [MISC_WK_X]
    MOV  X, SP
    LDW  A, [X]
    STW  A, [SLP_WK_PC]
    LDW  X, [MISC_WK_X]

    ; 現TCBアドレス計算
    LDW  A, [CUR_TASK]
    STW  A, [L1_WK_TMP]
    LDW  B, #6
    SHL  A, B
    STW  A, [L1_WK_C]
    LDW  A, [L1_WK_TMP]
    LDW  B, #4
    SHL  A, B
    LDW  B, [L1_WK_C]
    ADD  A, B
    LDW  B, #$4000
    ADD  A, B
    MOV  X, A

    ; コンテキスト保存
    LDW  A, [SLP_WK_PC]
    STW  A, [X + #2]
    MOV  A, SP
    ADDI A, #2
    STW  A, [X + #4]
    LDW  A, [SLP_WK_DSP]
    STW  A, [X + #6]
    LDW  A, #$80
    STW  A, [X + #12]
    LDW  A, #3
    STW  A, [X]                 ; SLEEPING

    ; SPをカーネルスタックに切り替え
    LDW  A, #$FBCE
    MOV  SP, A

    ; 共通スケジューラへ
    JMP  _sched_common

; ================================================================
; _sched_common ($02C0)
; TASK_SLEEP / TASK_EXIT から JMP で呼び出される共通スケジューラ
; 入力: SP=カーネルSP($FBCE), CUR_TASK=現タスク
; 動作: READYタスクを探してコンテキスト復元+IRET
; ================================================================
    .org $02C0
_sched_common:
    LDW  A, [CUR_TASK]
    STW  A, [L1_WK_B]          ; 開始tid（1周検出用）
    ADDI A, #1
_sc_sched:
    CMPI A, #8
    BLT  _sc_chk
    LDW  A, #0
_sc_chk:
    LDW  B, [L1_WK_B]          ; 開始tidと比較（読むだけ）
    CMP  A, B
    BEQ  _sc_idle
    STW  A, [L1_WK_A]
    ; TCBアドレス計算（L1_WK_Bは上書きしない）
    STW  A, [L1_WK_TMP]
    LDW  B, #6
    SHL  A, B
    STW  A, [L1_WK_C]
    LDW  A, [L1_WK_TMP]
    LDW  B, #4
    SHL  A, B
    LDW  B, [L1_WK_C]
    ADD  A, B
    LDW  B, #$4000
    ADD  A, B
    MOV  X, A
    LDW  B, [X]
    CMPI B, #1
    BEQ  _sc_found
    LDW  A, [L1_WK_A]
    ADDI A, #1
    JMP  _sc_sched
_sc_idle:
    EI
    NOP
    DI
    JMP  _sched_common

_sc_found:
    DI
    LDW  A, [L1_WK_A]
    STW  A, [CUR_TASK]
    LDW  A, #2
    STW  A, [X]                 ; RUNNING
    LDW  A, [X + #6]            ; 次DSP
    LDW  B, [X + #4]
    SUBI B, #4
    MOV  SP, B
    LDW  B, [X + #2]
    STW  X, [MISC_WK_X]
    MOV  X, SP
    ADDI X, #2
    STW  B, [X]
    LDW  X, [MISC_WK_X]
    LDW  B, [X + #12]
    ORI  B, #$80
    STW  X, [MISC_WK_X]
    MOV  X, SP
    STW  B, [X]
    LDW  X, [MISC_WK_X]
    MOV  X, A
    IRET

; ================================================================
; TASK-WAKEUP ($0380)
; SLEEPING(3) or WAIT_IPC(5) → READY
; ================================================================
    .org $0380
TASK_WAKEUP:
    LDW  A, [X]                 ; A = tid (TOS)
    ADDI X, #2
    STW  A, [L1_WK_TMP]
    LDW  B, #6
    SHL  A, B
    STW  A, [L1_WK_C]
    LDW  A, [L1_WK_TMP]
    LDW  B, #4
    SHL  A, B
    LDW  B, [L1_WK_C]
    ADD  A, B
    LDW  B, #$4000
    ADD  A, B
    MOV  X, A                   ; X = TCBアドレス
    LDW  A, [X]
    CMPI A, #3
    BEQ  _wakeup_do             ; SLEEPING
    CMPI A, #5
    BEQ  _wakeup_do             ; WAIT_IPC
    JMP  _wakeup_done
_wakeup_do:
    LDW  A, #1
    STW  A, [X]                 ; READY
_wakeup_done:
    RET

; ================================================================
; TASK-PRINT-ID ($03D0)
; デバッグ用 "TN\n" をUART出力
; ================================================================
    .org $03D0
TASK_PRINT_ID:
    STW  X, [MISC_WK_X]
    LDW  X, #$FC80
_tp1:
    LDW  A, [UART_STAT]
    CMPI A, #0
    BEQ  _tp1
    LDW  A, #$54                ; 'T'
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
    LDW  A, #$0A                ; LF
    STB  A, [X]
    LDW  X, [MISC_WK_X]
    RET

; ================================================================
; TASK-ID ($0440)
; ================================================================
    .org $0440
TASK_ID:
    SUBI X, #2
    LDW  A, [CUR_TASK]
    STW  A, [X]
    RET

; ================================================================
; TASK-EXIT ($0460)
; 自タスクをDEAD状態にして _sched_common へ JMP
; ================================================================
    .org $0460
TASK_EXIT:
    DI

    ; 現TCBアドレス計算
    LDW  A, [CUR_TASK]
    STW  A, [L1_WK_TMP]
    LDW  B, #6
    SHL  A, B
    STW  A, [L1_WK_C]
    LDW  A, [L1_WK_TMP]
    LDW  B, #4
    SHL  A, B
    LDW  B, [L1_WK_C]
    ADD  A, B
    LDW  B, #$4000
    ADD  A, B
    MOV  X, A

    LDW  A, #0
    STW  A, [X]                 ; DEAD

    LDW  A, #$FBCE
    MOV  SP, A
    JMP  _sched_common          ; 共通スケジューラへ
    ; 注: TASK_EXIT は全タスクDEADのとき _sc_idle でEI+NOP+DI ループになる
    ;     完全にDEADな場合はHALTが望ましいが _sched_common 内では
    ;     全DEADと全SLEEPを区別しない。将来版で対応予定。

; ================================================================
; TASK-CREATE ($0520)
; v0.8: TCBサイズ80B, IPC4フィールド初期化
; ================================================================
    .org $0520
TASK_CREATE:
    LDW  A, [X]
    ADDI X, #2
    STW  A, [TC_WK_ENTRY]
    STW  X, [TC_WK_TID]
    DI

    LDW  A, #0
_tc_scan:
    CMPI A, #8
    BEQ  _tc_noslot
    STW  A, [L1_WK_A]
    STW  A, [L1_WK_TMP]
    LDW  B, #6
    SHL  A, B
    STW  A, [L1_WK_C]
    LDW  A, [L1_WK_TMP]
    LDW  B, #4
    SHL  A, B
    LDW  B, [L1_WK_C]
    ADD  A, B
    LDW  B, #$4000
    ADD  A, B
    MOV  X, A
    LDW  B, [X]
    CMPI B, #0
    BEQ  _tc_found
    LDW  A, [L1_WK_A]
    ADDI A, #1
    JMP  _tc_scan

_tc_noslot:
    LDW  X, [TC_WK_TID]
    EI
    LDW  A, #$FFFF
    SUBI X, #2
    STW  A, [X]
    RET

_tc_found:
    ; X=空きTCBアドレス, L1_WK_A=tid
    ; コールスタック頂上: CALLSTK_BASE - tid*TASK_STK_GAP
    LDW  A, [L1_WK_A]
    LDW  B, #8
    SHL  A, B                   ; tid*256
    LDW  B, #$FBCE
    SUB  B, A
    MOV  A, B
    STW  A, [MISC_WK_X]

    ; TCB初期化
    LDW  A, #1
    STW  A, [X]                 ; READY
    LDW  A, [TC_WK_ENTRY]
    STW  A, [X + #2]
    LDW  A, [MISC_WK_X]
    STW  A, [X + #4]            ; saved_sp

    ; データスタック頂上: DATASTK_BASE - tid*TASK_STK_GAP
    LDW  A, [L1_WK_A]
    LDW  B, #8
    SHL  A, B
    LDW  B, #$F9CE
    SUB  B, A
    MOV  A, B
    STW  A, [X + #6]            ; saved_x

    LDW  A, #0
    STW  A, [X + #8]
    STW  A, [X + #10]
    LDW  A, #$80
    STW  A, [X + #12]           ; saved_flags = IE=1
    LDW  A, #0
    STW  A, [X + #14]
    STW  A, [X + #16]
    STW  A, [X + #18]
    STW  A, [X + #20]
    STW  A, [X + #22]
    STW  A, [X + #24]           ; ipc_valid = 0
    STW  A, [X + #26]
    STW  A, [X + #28]
    STW  A, [X + #30]

    LDW  X, [TC_WK_TID]
    EI
    LDW  A, [L1_WK_A]
    SUBI X, #2
    STW  A, [X]
    RET

; ================================================================
; TASK0_ENTRY ($0700)
; v0.9: MEM-TEST-TASK Forth ワードの呼び出し
; WORD_MEM_TEST_TASK = $CED4 (kernel_forth_v05.asm.sym より)
; ================================================================
    .org $0700
TASK0_ENTRY:
    JSR $CED4
    JMP TASK0_ENTRY

; ================================================================
; IPC4-SEND ($0740)  ( msg3 msg2 msg1 msg0 tid -- )
; 非ブロッキング送信
; MISC_WK_X=DSP退避, IPC4_WK_SRCTCB=TCBアドレス保存
; XをDSP/TCB交互に切り替えてmsg転送
; ================================================================
    .org $0740
IPC4_SEND:
    DI
    LDW  A, [X]
    ADDI X, #2
    STW  X, [MISC_WK_X]
    STW  A, [IPC4_WK_DST]
    STW  A, [L1_WK_TMP]
    LDW  B, #6
    SHL  A, B
    STW  A, [L1_WK_C]
    LDW  A, [L1_WK_TMP]
    LDW  B, #4
    SHL  A, B
    LDW  B, [L1_WK_C]
    ADD  A, B
    LDW  B, #$4000
    ADD  A, B
    STW  A, [IPC4_WK_SRCTCB]
    LDW  X, [MISC_WK_X]
    LDW  A, [X]
    ADDI X, #2
    STW  X, [MISC_WK_X]
    LDW  X, [IPC4_WK_SRCTCB]
    STW  A, [X + #16]
    LDW  X, [MISC_WK_X]
    LDW  A, [X]
    ADDI X, #2
    STW  X, [MISC_WK_X]
    LDW  X, [IPC4_WK_SRCTCB]
    STW  A, [X + #18]
    LDW  X, [MISC_WK_X]
    LDW  A, [X]
    ADDI X, #2
    STW  X, [MISC_WK_X]
    LDW  X, [IPC4_WK_SRCTCB]
    STW  A, [X + #20]
    LDW  X, [MISC_WK_X]
    LDW  A, [X]
    ADDI X, #2
    STW  X, [MISC_WK_X]
    LDW  X, [IPC4_WK_SRCTCB]
    STW  A, [X + #22]
    LDW  A, #1
    STW  A, [X + #24]
    LDW  A, [CUR_TASK]
    STW  A, [X + #26]
    LDW  A, [X]
    CMPI A, #5
    BNE  _ipc4send_done
    LDW  A, #1
    STW  A, [X]
_ipc4send_done:
    LDW  X, [MISC_WK_X]
    EI
    RET

; ================================================================
; IPC4-RECV ($07E0)  ( -- msg3 msg2 msg1 msg0 )
; ================================================================
    .org $07E0
IPC4_RECV:
    DI
    STW  X, [MISC_WK_X]
    LDW  A, [CUR_TASK]
    STW  A, [L1_WK_TMP]
    LDW  B, #6
    SHL  A, B
    STW  A, [L1_WK_C]
    LDW  A, [L1_WK_TMP]
    LDW  B, #4
    SHL  A, B
    LDW  B, [L1_WK_C]
    ADD  A, B
    LDW  B, #$4000
    ADD  A, B
    STW  A, [IPC4_WK_SRCTCB]
    MOV  X, A
    LDW  A, [X + #24]
    CMPI A, #1
    BEQ  _ipc4recv_got
    STW  X, [IPC4_WK_X]
    ; v0.9 fix: TCB.PC = _ipc4recv_got（再開時にmsg読み出しから継続）
    LDW  A, #$_ipc4recv_got
    STW  A, [X + #2]
    MOV  A, SP
    ADDI A, #2
    STW  A, [X + #4]
    LDW  A, [MISC_WK_X]
    STW  A, [X + #6]
    LDW  A, #$80
    STW  A, [X + #12]
    LDW  A, #5
    STW  A, [X]
    LDW  A, #$FBCE
    MOV  SP, A
    JMP  _sched_common
_ipc4recv_got:
    ; v0.9b fix: MISC_WK_Xは他の処理で破壊される可能性があるため、
    ; スケジューラが復元したXをそのまま使う（DSPは正しくF9CE等）
    STW  X, [IPC4_WK_X]
    LDW  X, [IPC4_WK_SRCTCB]
    LDW  A, [X + #22]
    LDW  X, [IPC4_WK_X]
    SUBI X, #2
    STW  A, [X]
    STW  X, [IPC4_WK_X]
    LDW  X, [IPC4_WK_SRCTCB]
    LDW  A, [X + #20]
    LDW  X, [IPC4_WK_X]
    SUBI X, #2
    STW  A, [X]
    STW  X, [IPC4_WK_X]
    LDW  X, [IPC4_WK_SRCTCB]
    LDW  A, [X + #18]
    LDW  X, [IPC4_WK_X]
    SUBI X, #2
    STW  A, [X]
    STW  X, [IPC4_WK_X]
    LDW  X, [IPC4_WK_SRCTCB]
    LDW  A, [X + #16]
    LDW  B, #0
    STW  B, [X + #24]
    LDW  X, [IPC4_WK_X]
    SUBI X, #2
    STW  A, [X]
    EI
    RET

; ================================================================
; IPC4-CALL ($0880)  ( msg3 msg2 msg1 msg0 tid -- r3 r2 r1 r0 )
; ================================================================
    .org $08C0
IPC4_CALL:
    DI
    LDW  A, [X]
    ADDI X, #2
    STW  X, [MISC_WK_X]
    STW  A, [IPC4_WK_DST]
    STW  A, [L1_WK_TMP]
    LDW  B, #6
    SHL  A, B
    STW  A, [L1_WK_C]
    LDW  A, [L1_WK_TMP]
    LDW  B, #4
    SHL  A, B
    LDW  B, [L1_WK_C]
    ADD  A, B
    LDW  B, #$4000
    ADD  A, B
    STW  A, [IPC4_WK_SRCTCB]
    LDW  X, [MISC_WK_X]
    LDW  A, [X]
    ADDI X, #2
    STW  X, [MISC_WK_X]
    LDW  X, [IPC4_WK_SRCTCB]
    STW  A, [X + #16]
    LDW  X, [MISC_WK_X]
    LDW  A, [X]
    ADDI X, #2
    STW  X, [MISC_WK_X]
    LDW  X, [IPC4_WK_SRCTCB]
    STW  A, [X + #18]
    LDW  X, [MISC_WK_X]
    LDW  A, [X]
    ADDI X, #2
    STW  X, [MISC_WK_X]
    LDW  X, [IPC4_WK_SRCTCB]
    STW  A, [X + #20]
    LDW  X, [MISC_WK_X]
    LDW  A, [X]
    ADDI X, #2
    STW  X, [MISC_WK_X]
    LDW  X, [IPC4_WK_SRCTCB]
    STW  A, [X + #22]
    LDW  A, #1
    STW  A, [X + #24]
    LDW  A, [CUR_TASK]
    STW  A, [X + #26]
    LDW  A, [X]
    CMPI A, #5
    BNE  _ipc4call_block
    LDW  A, #1
    STW  A, [X]
_ipc4call_block:
    LDW  A, [CUR_TASK]
    STW  A, [L1_WK_TMP]
    LDW  B, #6
    SHL  A, B
    STW  A, [L1_WK_C]
    LDW  A, [L1_WK_TMP]
    LDW  B, #4
    SHL  A, B
    LDW  B, [L1_WK_C]
    ADD  A, B
    LDW  B, #$4000
    ADD  A, B
    STW  A, [IPC4_WK_X]
    MOV  X, A
    LDW  A, #$IPC4_CALL_RESUME
    STW  A, [X + #2]
    MOV  A, SP
    ADDI A, #2
    STW  A, [X + #4]
    LDW  A, [MISC_WK_X]
    STW  A, [X + #6]
    LDW  A, #$80
    STW  A, [X + #12]
    LDW  A, #0
    STW  A, [X + #24]
    LDW  A, #6
    STW  A, [X]
    LDW  A, #$FBCE
    MOV  SP, A
    JMP  _sched_common
IPC4_CALL_RESUME:
    DI
    LDW  A, [CUR_TASK]
    STW  A, [L1_WK_TMP]
    LDW  B, #6
    SHL  A, B
    STW  A, [L1_WK_C]
    LDW  A, [L1_WK_TMP]
    LDW  B, #4
    SHL  A, B
    LDW  B, [L1_WK_C]
    ADD  A, B
    LDW  B, #$4000
    ADD  A, B
    STW  A, [IPC4_WK_SRCTCB]
    STW  X, [IPC4_WK_X]
    LDW  X, [IPC4_WK_SRCTCB]
    LDW  A, [X + #22]
    LDW  X, [IPC4_WK_X]
    SUBI X, #2
    STW  A, [X]
    STW  X, [IPC4_WK_X]
    LDW  X, [IPC4_WK_SRCTCB]
    LDW  A, [X + #20]
    LDW  X, [IPC4_WK_X]
    SUBI X, #2
    STW  A, [X]
    STW  X, [IPC4_WK_X]
    LDW  X, [IPC4_WK_SRCTCB]
    LDW  A, [X + #18]
    LDW  X, [IPC4_WK_X]
    SUBI X, #2
    STW  A, [X]
    STW  X, [IPC4_WK_X]
    LDW  X, [IPC4_WK_SRCTCB]
    LDW  A, [X + #16]
    LDW  B, #0
    STW  B, [X + #24]
    LDW  X, [IPC4_WK_X]
    SUBI X, #2
    STW  A, [X]
    EI
    RET

; ================================================================
; IPC4-REPLY ($0B00)  ( r3 r2 r1 r0 tid -- )
; ================================================================
    .org $0B00
IPC4_REPLY:
    DI
    LDW  A, [X]
    ADDI X, #2
    STW  X, [MISC_WK_X]
    STW  A, [IPC4_WK_DST]
    STW  A, [L1_WK_TMP]
    LDW  B, #6
    SHL  A, B
    STW  A, [L1_WK_C]
    LDW  A, [L1_WK_TMP]
    LDW  B, #4
    SHL  A, B
    LDW  B, [L1_WK_C]
    ADD  A, B
    LDW  B, #$4000
    ADD  A, B
    STW  A, [IPC4_WK_SRCTCB]
    LDW  X, [MISC_WK_X]
    LDW  A, [X]
    ADDI X, #2
    STW  X, [MISC_WK_X]
    LDW  X, [IPC4_WK_SRCTCB]
    STW  A, [X + #16]
    LDW  X, [MISC_WK_X]
    LDW  A, [X]
    ADDI X, #2
    STW  X, [MISC_WK_X]
    LDW  X, [IPC4_WK_SRCTCB]
    STW  A, [X + #18]
    LDW  X, [MISC_WK_X]
    LDW  A, [X]
    ADDI X, #2
    STW  X, [MISC_WK_X]
    LDW  X, [IPC4_WK_SRCTCB]
    STW  A, [X + #20]
    LDW  X, [MISC_WK_X]
    LDW  A, [X]
    ADDI X, #2
    STW  X, [MISC_WK_X]
    LDW  X, [IPC4_WK_SRCTCB]
    STW  A, [X + #22]
    LDW  A, #1
    STW  A, [X + #24]
    LDW  A, [CUR_TASK]
    STW  A, [X + #26]
    LDW  A, [X]
    CMPI A, #6
    BNE  _ipc4reply_done
    LDW  A, #1
    STW  A, [X]
_ipc4reply_done:
    LDW  X, [MISC_WK_X]
    EI
    RET


; ================================================================
; カーネル初期化 ($0E00)
; ================================================================
    .org $0E00
_kstart:
    LDW  SP, #$FBCE
    LDW  X, #$F800
    DI

    ; 全TCBゼロクリア (8タスク×80B)
    LDW  B, #0
_init_tcb:
    CMPI B, #8
    BEQ  _init_done
    STW  B, [L1_WK_A]
    MOV  A, B
    STW  A, [L1_WK_TMP]
    LDW  B, #6
    SHL  A, B
    STW  A, [L1_WK_C]
    LDW  A, [L1_WK_TMP]
    LDW  B, #4
    SHL  A, B
    LDW  B, [L1_WK_C]
    ADD  A, B
    LDW  B, #$4000
    ADD  A, B
    MOV  X, A
    LDW  A, #0
    STW  A, [X + #0]
    STW  A, [X + #2]
    STW  A, [X + #4]
    STW  A, [X + #6]
    STW  A, [X + #8]
    STW  A, [X + #10]
    STW  A, [X + #12]
    STW  A, [X + #14]
    STW  A, [X + #16]
    STW  A, [X + #18]
    STW  A, [X + #20]
    STW  A, [X + #22]
    STW  A, [X + #24]
    STW  A, [X + #26]
    STW  A, [X + #28]
    STW  A, [X + #30]
    STW  A, [X + #32]
    STW  A, [X + #34]
    STW  A, [X + #36]
    STW  A, [X + #38]
    STW  A, [X + #40]
    STW  A, [X + #42]
    STW  A, [X + #44]
    STW  A, [X + #46]
    STW  A, [X + #48]
    STW  A, [X + #50]
    STW  A, [X + #52]
    STW  A, [X + #54]
    STW  A, [X + #56]
    STW  A, [X + #58]
    STW  A, [X + #60]
    STW  A, [X + #62]
    STW  A, [X + #64]
    STW  A, [X + #66]
    STW  A, [X + #68]
    STW  A, [X + #70]
    STW  A, [X + #72]
    STW  A, [X + #74]
    STW  A, [X + #76]
    STW  A, [X + #78]
    LDW  B, [L1_WK_A]
    ADDI B, #1
    JMP  _init_tcb
_init_done:

    ; TCB0 = MEMMGR-TASK（tid=0）
    ; WORD_MEMMGR_TASK = $CE7F（kernel_forth_v05.asm.sym より）
    LDW  X, #$4000
    LDW  A, #1
    STW  A, [X]              ; READY（後でRUNNINGに変更）
    LDW  A, #$CE7F
    STW  A, [X + #2]         ; PC = WORD_MEMMGR_TASK
    LDW  A, #$FBCE
    STW  A, [X + #4]         ; コールスタック top（tid=0）
    LDW  A, #$F9CE
    STW  A, [X + #6]         ; データスタック top（tid=0）
    LDW  A, #$80
    STW  A, [X + #12]        ; FLAGS

    ; TCB1 = MEM-TEST-TASK（tid=1）TASK0_ENTRY経由
    LDW  X, #$4050
    LDW  A, #1
    STW  A, [X]              ; READY
    LDW  A, #$TASK0_ENTRY
    STW  A, [X + #2]         ; PC
    LDW  A, #$FACE
    STW  A, [X + #4]         ; コールスタック top（tid=1）
    LDW  A, #$F8CE
    STW  A, [X + #6]         ; データスタック top（tid=1）
    LDW  A, #$80
    STW  A, [X + #12]

    ; MEM-TID-ADDR ($E204) = 0（MemMgr は tid=0）
    LDW  A, #0
    STW  A, [MEM_TID_ADDR]

    LDW  A, #2
    STW  A, [TASK_COUNT]
    LDW  A, #0
    STW  A, [CUR_TASK]

    ; tid=0（MEMMGR-TASK）を RUNNING で直接起動
    LDW  X, #$4000
    LDW  A, #2
    STW  A, [X]              ; RUNNING
    LDW  A, #$FBCA
    MOV  SP, A
    MOV  X, SP
    ADDI X, #2
    LDW  A, #$CE7F           ; WORD_MEMMGR_TASK
    STW  A, [X]
    MOV  X, SP
    LDW  A, #$80
    STW  A, [X]
    LDW  X, #$F9CE           ; DSP初期値（tid=0用）
    IRET
