\ kernel_forth.fs - YUI OS カーネル Forth 層
\ Version: 0.3
\ YSD8800 YUI OS Microkernel
\
\ 設計方針:
\   - IRQ0ハンドラ・コンテキストスイッチはアセンブラ（kernel.asm）
\   - 高レベルAPIはここで純粋Forthとして実装（移植性重視）
\   - ハードウェア依存部は CODE...END-CODE に隔離
\
\ v0.1: TASK-ID, TASK-PRINT-ID をForth化
\ v0.2: TASK-WAKEUP, TASK-CREATE, MSG-SEND, MSG-RECV をForth化
\ v0.3: ISA2.3 v2.2.1メモリマップ対応（TCBプール$4000,スタック$F800-$FBCF,ワーク変数$42xx）

\ ============================================================
\ ハードウェア定数（移植時はここを変更）
\ ============================================================
$FC80 CONSTANT UART-TX
$FC84 CONSTANT UART-STAT

\ TCB定数
$4000 CONSTANT TCB-POOL     \ TCBプール先頭アドレス（RAM $4000-$41FF）
6     CONSTANT TCB-SHIFT    \ TCBサイズ = 64 = 1<<6
$FBCE CONSTANT CALLSTK-BASE \ tid=0コールスタック頂上（Stacks領域 $F800-$FBCF）
$F9CE CONSTANT DATASTK-BASE \ tid=0データスタック頂上（Stacks領域）
$0100 CONSTANT TASK-STK-GAP \ タスク間スタック間隔（256B）

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
$4220 CONSTANT CUR-TASK-ADDR \ カーネル状態変数（RAM $4220-）

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
    TCB-POOL + ;

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
    BEGIN UART-STAT @ 0= INVERT UNTIL
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
CODE MSG-SEND  ( msg tid -- )
    JSR $0740
END-CODE

\ ============================================================
\ MSG-RECV  ( -- msg )
\ メッセージを受信、なければ TASK-WAIT-MSG でブロック
\ ============================================================
CODE MSG-RECV  ( -- msg )
    JSR $07E0
END-CODE
