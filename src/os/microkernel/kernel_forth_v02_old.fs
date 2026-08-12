\ kernel_forth.fs - YUI OS カーネル Forth 層
\ Version: 0.2
\ YSD8800 YUI OS Microkernel
\
\ 設計方針:
\   - IRQ0ハンドラ・コンテキストスイッチはアセンブラ（kernel_core.asm）
\   - 高レベルAPIはここで純粋Forthとして実装（移植性重視）
\   - ハードウェア依存部は CODE...END-CODE に隔離
\
\ v0.1: TASK-ID, TASK-PRINT-ID をForth化
\ v0.2: TASK-WAKEUP, TASK-CREATE, MSG-SEND, MSG-RECV をForth化

\ ============================================================
\ ハードウェア定数（移植時はここを変更）
\ ============================================================
$FC80 CONSTANT UART-TX
$FC84 CONSTANT UART-STAT

\ TCB定数
$1000 CONSTANT TCB-POOL     \ TCBプール先頭アドレス
6     CONSTANT TCB-SHIFT    \ TCBサイズ = 64 = 1<<6
$23FE CONSTANT CALLSTK-BASE \ タスク0のコールスタック頂上
$21FE CONSTANT DATASTK-BASE \ タスク0のデータスタック頂上
$0400 CONSTANT TASK-STK-GAP \ タスク間のスタック間隔

\ TCBオフセット（定数）
0  CONSTANT TCB-STATE
2  CONSTANT TCB-PC
4  CONSTANT TCB-SP
6  CONSTANT TCB-DSP
12 CONSTANT TCB-FLAGS

\ タスク状態
0  CONSTANT TASK-DEAD
1  CONSTANT TASK-READY
2  CONSTANT TASK-RUNNING
3  CONSTANT TASK-SLEEPING
4  CONSTANT TASK-WAIT-MSG

\ カーネルワーク変数
$E100 CONSTANT CUR-TASK-ADDR

\ ============================================================
\ アーキテクチャ層 CODE...END-CODE ブリッジ
\ 移植時はここのアドレスを書き換える
\ ============================================================

\ 割り込み制御
CODE DI-OP
    DI
END-CODE
CODE EI-OP
    EI
END-CODE

\ コンテキストスイッチを伴う低レベルAPI（アセンブラ版を呼ぶ）
CODE KERN-TASK-SLEEP
    JSR $01C0
END-CODE
CODE KERN-TASK-EXIT
    JSR $0460
END-CODE
CODE KERN-TASK-CREATE
    JSR $0520
END-CODE
CODE KERN-TASK-WAKEUP-ASM
    JSR $02C0
END-CODE

\ ============================================================
\ TCB操作プリミティブ（移植性のある実装）
\ ============================================================

\ TCBアドレス計算: tid → TCBアドレス
: TCB-ADDR  ( tid -- addr )
    6 LSHIFT
    $1000 + ;

\ TCBフィールドアクセス（汎用）
\ TCB-@ ( tid off -- val ) : tid のTCB[off]を読む
: TCB-@  ( tid off -- val )  SWAP TCB-ADDR + @ ;
\ TCB-! ( val tid off -- )  : tid のTCB[off]に書く
: TCB-!  ( val tid off -- )  SWAP TCB-ADDR + ! ;

\ 専用アクセサ（よく使うもの）
: TCB-STATE@  ( tid -- state )  0  TCB-@ ;
: TCB-STATE!  ( state tid -- )  0  TCB-! ;

\ ============================================================
\ UART 出力
\ ============================================================
: emit-char  ( c -- )
    BEGIN UART-STAT @ 0<> UNTIL
    UART-TX ! ;

: emit-nl  ( -- )  10 emit-char ;

\ ============================================================
\ TASK-ID  ( -- tid )
\ ============================================================
: TASK-ID  ( -- tid )
    CUR-TASK-ADDR @ ;

\ ============================================================
\ TASK-PRINT-ID  ( -- )
\ "Tn\n" を UART 出力
\ ============================================================
: TASK-PRINT-ID  ( -- )
    84 emit-char
    TASK-ID 48 + emit-char
    emit-nl ;

\ ============================================================
\ TASK-WAKEUP  ( tid -- )
\ 純粋Forth実装
\ ============================================================
: TASK-WAKEUP  ( tid -- )
    DUP TCB-STATE@
    TASK-SLEEPING = IF
        TASK-READY SWAP TCB-STATE!
    ELSE
        DROP
    THEN ;

\ ============================================================
\ TASK-CREATE  ( entry -- )
\ ============================================================
: TASK-CREATE  ( entry -- )
    KERN-TASK-CREATE ;

\ ============================================================
\ TASK-EXIT  ( -- )
\ ============================================================
: TASK-EXIT  ( -- )
    KERN-TASK-EXIT ;

\ ============================================================
\ TASK-SLEEP  ( -- )
\ ============================================================
: TASK-SLEEP  ( -- )
    KERN-TASK-SLEEP ;

\ ============================================================
\ MSG-SEND  ( msg tid -- )
\ 対象タスクのTCBにメッセージを格納し、WAIT-MSGならREADYに
\ ============================================================
: MSG-SEND  ( msg tid -- )
    DI-OP
    DUP TCB-ADDR        \ msg tid tcbaddr
    ROT OVER 16 + !     \ tid tcbaddr  (TCB.msg_data = msg)
    1   OVER 18 + !     \ tid tcbaddr  (TCB.msg_valid = 1)
    TASK-ID OVER 20 + ! \ tid tcbaddr  (TCB.msg_sender = CUR_TASK)
    DUP @ TASK-WAIT-MSG = IF
        TASK-READY SWAP !
    ELSE
        DROP
    THEN
    SWAP DROP
    EI-OP ;

\ ============================================================
\ MSG-RECV  ( -- msg )
\ メッセージを受信、なければ TASK-WAIT-MSG でブロック
\ ============================================================
: MSG-RECV  ( -- msg )
    DI-OP
    TASK-ID TCB-ADDR        \ tcbaddr
    DUP 18 + @ 0= IF        \ メッセージなし?
        TASK-WAIT-MSG OVER ! \ TCB.state = WAIT-MSG
        EI-OP
        TASK-SLEEP
        DI-OP
        TASK-ID TCB-ADDR    \ 再取得
    THEN
    DUP 16 + @              \ tcbaddr msg
    0 ROT 18 + !            \ msg  (TCB.msg_valid = 0)
    EI-OP ;
