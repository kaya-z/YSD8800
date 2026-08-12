; ============================================================
; YSD8800 マイクロカーネル kernel.asm  v0.10
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
; v0.10: YUI OS v2.0 Ph.3-A5 UARTドライバ対応
;   - IRQ1ベクタを IRQ1_HANDLER に差替
;   - IRQ1_HANDLER 新設 (yuios_ph3_uart_design_v1_2.docx §5.3)
;   - rx_push サブルーチン追加 (§5.4)
;   - wake_uart_waiter サブルーチン追加 (§5.5, IPC4_REPLY コピペベース)
;   - IRQ1ワーク変数追加: IRQ1_WK_A/B/X/BYTE ($42A2-$42A8)
;   - 新規MMIO定数: UART_RX($FC82), IRQ_STAT($FCB2), IRQ_MASK($FCB4)
;   - UARTリングバッファ定数: UART_RX_RING_BUF($E210)他
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
;   $0D00        IRQ1_HANDLER (v0.10新設)
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

; v0.10追加: IRQ1専用ワーク変数 ($42A2-$42A8)
; IRQ0のIRQ_WK_X/IRQ_WK_Aとは別領域 (混用禁止)
; yuios_ph3_uart_design_v1_2.docx §5.6
IRQ1_WK_A           EQU $42A2       ; IRQ1用 A退避
IRQ1_WK_B           EQU $42A4       ; IRQ1用 B退避
IRQ1_WK_X           EQU $42A6       ; IRQ1用 X退避
IRQ1_WK_BYTE        EQU $42A8       ; 受信バイト一時保管

MEM_TID_ADDR        EQU $E204

; ================================================================
; UART / IRQ MMIO (v0.10追加)
; YSD8001 UART ($FC80-$FC8F)
; YSD8004 IRQC ($FCB2-$FCB4)
; ================================================================
UART_RX             EQU $FC82
IRQ_STAT            EQU $FCB2
IRQ_MASK            EQU $FCB4

; ================================================================
; UART受信リングバッファ変数 ($E210-$E228)
; yuios_ph3_uart_design_v1_2.docx §2.2
; ================================================================
UART_RX_RING_BUF    EQU $E210       ; 16B リングバッファ本体
UART_RX_HEAD        EQU $E220       ; 書き込み位置 (0-15)
UART_RX_TAIL        EQU $E222       ; 読み出し位置 (0-15)
UART_RX_COUNT       EQU $E224       ; バッファ内バイト数 (0-16)
UART_DRV_TID        EQU $E226       ; UARTドライバタスクID
UART_WAIT_TID       EQU $E228       ; UART_GETC待ちクライアントtid (0=なし)

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
    .vector irq1    IRQ1_HANDLER    ; v0.10: UARTドライバ対応 (_dummy_irqから差替)
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
; IRQ1ハンドラ ($0D00)  v0.10新設
; UART RX割り込み処理 (YSD8001 RX → YSD8004 IRQ_STAT bit0)
; yuios_ph3_uart_design_v1_2.docx §5.3
;
; 処理順序 (必須 - 順序変更禁止):
;   S0: A/B/X退避
;   S1/S2: IRQ_STAT bit0確認 (UART RX由来判定)
;   S3: UART_RX読出 (副作用なし - RX_READYはクリアされない)
;   S4: rx_push(byte) → リングバッファ格納
;   S5: UART_STAT WTC ($0002書込) → RX_READYクリア [最重要: S6より先]
;   S6: IRQ_STAT WTC (bit0クリア) [S5より後である必要あり]
;   S7: UART_WAIT_TIDが非0なら wake_uart_waiter
;   S8: A/B/X復帰, IRET
;
; 警告: S5を欠くとRX_READY=1継続→IRQ1無限ループ
; 警告: S5/S6順序逆転でも多重発火する (§5.2参照)
; ================================================================
    .org $0D00
IRQ1_HANDLER:
    ; --- S0: レジスタ退避 ---
    STW  A, [IRQ1_WK_A]
    STW  B, [IRQ1_WK_B]
    STW  X, [IRQ1_WK_X]

    ; --- S1/S2: IRQ_STAT bit0確認 ---
    LDW  A, [IRQ_STAT]
    ANDI A, #$0001
    BEQ  _irq1_done             ; UART RXでなければ復帰

    ; --- S3: UART_RX読出 (RX_READYはクリアされない) ---
    LDW  A, [UART_RX]
    ANDI A, #$00FF              ; 下位8bitのみが受信値

    ; --- S4: リングバッファ書込 ---
    JSR  rx_push                ; A=byte を push (COUNT>=16なら破棄)

    ; --- S5: UART_STAT WTC (RX_READYクリア) ---
    ; 【最重要】S6より前に実行すること。逆順で多重発火する。
    LDW  B, #$0002
    STW  B, [UART_STAT]

    ; --- S6: IRQ_STAT WTC (bit0クリア) ---
    LDW  B, #$0001
    STW  B, [IRQ_STAT]

    ; --- S7: 待機中クライアントを起こす ---
    JSR  wake_uart_waiter

_irq1_done:
    ; --- S8: レジスタ復帰, IRET ---
    LDW  A, [IRQ1_WK_A]
    LDW  B, [IRQ1_WK_B]
    LDW  X, [IRQ1_WK_X]
    IRET

; ================================================================
; rx_push  (IRQ1_HANDLERから呼ばれる)
; 入力: A = 受信バイト (下位8bit有効)
; 破壊: A, B, X (退避なし - 呼び出し元IRQ1_HANDLERが全退避済)
; yuios_ph3_uart_design_v1_2.docx §5.4
;
; 更新順序: HEAD先 → COUNT後 (逆順禁止)
; COUNT>=16の場合は破棄 (オーバーラン)
; ================================================================
rx_push:
    STW  A, [IRQ1_WK_BYTE]     ; byte退避

    LDW  A, [UART_RX_COUNT]
    LDW  B, #16
    CMP  A, B
    BGE  _rx_push_overrun       ; COUNT >= 16 → 破棄

    ; --- (1) データ書込 ---
    LDW  B, [UART_RX_HEAD]     ; B = HEAD (インデックス 0-15)
    LDW  A, #$E210              ; UART_RX_RING_BUF
    ADD  A, B                   ; A = &buf[HEAD]
    MOV  X, A                   ; X = &buf[HEAD]
    LDW  A, [IRQ1_WK_BYTE]
    STB  A, [X]                 ; buf[HEAD] = byte (STB A,[X])

    ; --- (2) HEAD更新 (先) ---
    LDW  A, [UART_RX_HEAD]     ; A = 現HEAD
    ADDI A, #1
    ANDI A, #$000F              ; HEAD = (HEAD + 1) mod 16
    STW  A, [UART_RX_HEAD]

    ; --- (3) COUNT更新 (後) ---
    LDW  A, [UART_RX_COUNT]
    ADDI A, #1
    STW  A, [UART_RX_COUNT]

_rx_push_overrun:
    RET

; ================================================================
; wake_uart_waiter  (IRQ1_HANDLERから呼ばれる)
; UART_GETC待ちクライアントへ直接REPLY相当処理を実施する
;
; 【必須ルール】本サブルーチンはIPC4_REPLY (L841以降) をコピーベースに
; 実装している。将来IPC4_REPLYが拡張された場合は本関数も追従すること。
; (yuios_ph3_uart_design_v1_2.docx §5.5.1 / §10.4 規約3)
;
; 入力: UART_WAIT_TID = 待ちクライアントtid (0=なし)
; 出力: クライアントTCBに ipc_msg[0]=byte, ipc_valid=1, state=READY
;       UART_WAIT_TID = 0 (クリア)
; 破壊: A, B, X (呼び出し元IRQ1_HANDLERが全退避済)
; IRQコンテキスト内なのでDI/EIは不要
; yuios_ph3_uart_design_v1_2.docx §5.5
; ================================================================
wake_uart_waiter:
    ; A2': UART_WAIT_TIDからtid取得 (DSP不使用)
    LDW  A, [UART_WAIT_TID]
    BEQ  _wake_done             ; 0なら待機者なし

    ; A3: tid → TCBアドレス計算
    ; IPC4_REPLY (L847-L857) と同一の5命令ブロックをコピー
    ; (tid*80+$4000 = (tid<<6)+(tid<<4)+$4000)
    STW  A, [L1_WK_TMP]        ; tid退避
    LDW  B, #6
    SHL  A, B                   ; A = tid*64
    STW  A, [L1_WK_C]          ; tid*64退避
    LDW  A, [L1_WK_TMP]        ; tid復元
    LDW  B, #4
    SHL  A, B                   ; A = tid*16
    LDW  B, [L1_WK_C]          ; B = tid*64
    ADD  A, B                   ; A = tid*80
    LDW  B, #$4000
    ADD  A, B                   ; A = TCBアドレス
    STW  A, [IPC4_WK_SRCTCB]   ; IPC4_REPLYと同じワーク変数を流用
    MOV  X, A                   ; X = TCBアドレス

    ; A4': ipc_msg[0]=byte (rx_pop結果), msg[1..3]=0
    ; rx_pop: TAIL位置からbyteを取得し TAIL/COUNT更新
    JSR  rx_pop                 ; A = byte (下位8bit)
    STW  A, [X + #16]           ; TCB+16 = ipc_msg[0] = byte
    LDW  A, #0
    STW  A, [X + #18]           ; TCB+18 = ipc_msg[1] = 0
    STW  A, [X + #20]           ; TCB+20 = ipc_msg[2] = 0
    STW  A, [X + #22]           ; TCB+22 = ipc_msg[3] = 0

    ; A5: ipc_valid = 1 (IPC4_REPLYと同一)
    LDW  A, #1
    STW  A, [X + #24]           ; TCB+24 = ipc_valid

    ; A6: ipc_sender = CUR_TASK (IPC4_REPLYと同一、互換性のため)
    LDW  A, [CUR_TASK]
    STW  A, [X + #26]           ; TCB+26 = ipc_sender

    ; A7: state==6(WAIT_REPLY)なら1(READY)へ遷移
    ; 【極めて重要】条件判定を省略すると state破壊の危険あり
    ; IPC4_REPLY (L887-L891) と同一のロジック
    LDW  A, [X]                 ; state取得
    CMPI A, #6                  ; TASK_WAIT_REPLY?
    BNE  _wake_no_state_change
    LDW  A, #1
    STW  A, [X]                 ; TASK_READY

_wake_no_state_change:
    ; UART_WAIT_TID = 0 (待機解除 - 最後に行うこと)
    LDW  A, #0
    STW  A, [UART_WAIT_TID]

_wake_done:
    RET

; ================================================================
; rx_pop  (wake_uart_waiterから呼ばれる)
; リングバッファから1バイト取得
; 入力: COUNT>0であること (呼び出し側が保証)
; 出力: A = byte (下位8bit)
; 破壊: A, B, X
; 更新順序: TAIL先 → COUNT後 (逆順禁止)
; ================================================================
rx_pop:
    LDW  X, [UART_RX_TAIL]     ; X = TAIL (インデックス)
    LDW  A, #$E210              ; UART_RX_RING_BUF
    ADD  A, X                   ; A = &buf[TAIL]
    MOV  X, A                   ; X = &buf[TAIL]
    LDB  A, [X]                 ; A = buf[TAIL] (LDB A,[X])
    ANDI A, #$00FF              ; 下位8bitのみ (LDB符号拡張クリア)

    ; TAIL更新 (先)
    MOV  B, X                   ; B = TAIL (インデックス)
    ADDI B, #1
    ANDI B, #$000F              ; TAIL = (TAIL+1) mod 16
    STW  B, [UART_RX_TAIL]

    ; COUNT更新 (後)
    LDW  B, [UART_RX_COUNT]
    SUBI B, #1
    STW  B, [UART_RX_COUNT]

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

    ; UART変数初期化（$E210-$E228）v0.10追加
    ; yuios_ph3_uart_design_v1_2.docx §4.2
    LDW  A, #0
    LDW  X, #$E220
    STW  A, [X]              ; UART_RX_HEAD($E220) = 0
    LDW  X, #$E222
    STW  A, [X]              ; UART_RX_TAIL($E222) = 0
    LDW  X, #$E224
    STW  A, [X]              ; UART_RX_COUNT($E224) = 0
    LDW  X, #$E226
    STW  A, [X]              ; UART_DRV_TID($E226) = 0
    LDW  X, #$E228
    STW  A, [X]              ; UART_WAIT_TID($E228) = 0

    ; テスト文字列 "BC\0" を $E230 に配置 v0.10追加
    ; kernel_forth_v06.fs BC-STR CONSTANT $E230 と対応
    LDW  X, #$E230
    LDW  A, #$42             ; 'B'
    STB  A, [X]
    LDW  X, #$E231
    LDW  A, #$43             ; 'C'
    STB  A, [X]
    LDW  X, #$E232
    LDW  A, #0               ; NUL
    STB  A, [X]

    ; TCB0 = OS-START（tid=0）
    ; v0.10: Ph.3対応 OS-START から起動（MEMMGR→UART→UART-TEST の順で起動）
    ; WORD_OS_START = $D817（kernel_forth_v06_final.asm.sym より）
    LDW  X, #$4000
    LDW  A, #1
    STW  A, [X]              ; READY（後でRUNNINGに変更）
    LDW  A, #$D817
    STW  A, [X + #2]         ; PC = WORD_OS_START
    LDW  A, #$FBCE
    STW  A, [X + #4]         ; コールスタック top（tid=0）
    LDW  A, #$F9CE
    STW  A, [X + #6]         ; データスタック top（tid=0）
    LDW  A, #$80
    STW  A, [X + #12]        ; FLAGS

    ; TCB1以降: DEAD状態のまま（OS-STARTがTASK-CREATEで動的に生成）

    ; MEM-TID-ADDR ($E204) = 0（MemMgr は tid=0 → OS-STARTが再設定）
    LDW  A, #0
    STW  A, [MEM_TID_ADDR]

    LDW  A, #1
    STW  A, [TASK_COUNT]     ; 起動タスク数 = 1（tid=0のみ）
    LDW  A, #0
    STW  A, [CUR_TASK]

    ; tid=0（OS-START）を RUNNING で直接起動
    LDW  X, #$4000
    LDW  A, #2
    STW  A, [X]              ; RUNNING
    LDW  A, #$FBCA
    MOV  SP, A
    MOV  X, SP
    ADDI X, #2
    LDW  A, #$D817           ; WORD_OS_START
    STW  A, [X]
    MOV  X, SP
    LDW  A, #$80
    STW  A, [X]
    LDW  X, #$F9CE           ; DSP初期値（tid=0用）
    IRET
