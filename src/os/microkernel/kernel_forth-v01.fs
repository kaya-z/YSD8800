\ kernel_forth.fs - YUI OS カーネル Forth 層
\ Version: 0.1
\ YSD8800 YUI OS Microkernel
\
\ kernel_core.asm（アセンブラ層）の上に乗る高レベルAPI。
\ Force v1.0 でコンパイル、ysd8800_kern.tgt を使用。
\
\ アーキテクチャ:
\   kernel_core.asm  $0030-$08E9  IRQ0ハンドラ、低レベルAPI
\   kernel_forth.fs  $0A00-       高レベルAPI（このファイル）
\
\ 移植性方針（YUI OS設計原則）:
\   - ハードウェア依存部は CODE...END-CODE に隔離
\   - 高レベルロジックは純粋 Forth で記述
\   - アーキテクチャ固有定数は CONSTANT で定義

\ ============================================================
\ ハードウェア定数
\ ============================================================
$FC80 CONSTANT UART-TX
$FC84 CONSTANT UART-STAT

\ カーネルワーク変数アドレス
$E100 CONSTANT CUR-TASK-ADDR   \ 現タスクID格納アドレス

\ ============================================================
\ アーキテクチャ層（CODE...END-CODE でアセンブラ直接記述）
\ 移植時はここを書き換える
\ ============================================================

\ 割り込み制御
CODE DI-OP
    DI
END-CODE
CODE EI-OP
    EI
END-CODE

\ カーネルコアAPI呼び出しブリッジ
CODE KERN-TASK-SLEEP
    JSR $01C0
END-CODE
CODE KERN-TASK-WAKEUP
    JSR $02C0
END-CODE
CODE KERN-TASK-EXIT
    JSR $0460
END-CODE
CODE KERN-TASK-CREATE
    JSR $0520
END-CODE
CODE KERN-MSG-SEND
    JSR $0740
END-CODE
CODE KERN-MSG-RECV
    JSR $07E0
END-CODE

\ ============================================================
\ UART 出力（移植性のある実装）
\ ============================================================

\ 1文字出力
: emit-char  ( c -- )
    BEGIN UART-STAT @ 0<> UNTIL
    UART-TX ! ;

\ 改行出力
: emit-nl  ( -- )  10 emit-char ;

\ ============================================================
\ TASK-ID  ( -- tid )
\ 現タスクのIDをスタックに積む
\ kernel_core の CUR_TASK ($E100) を読むだけ
\ ============================================================
: TASK-ID  ( -- tid )
    CUR-TASK-ADDR @ ;

\ ============================================================
\ TASK-PRINT-ID  ( -- )
\ "Tn\n" を UART 出力（T0, T1, ...）
\ ============================================================
: TASK-PRINT-ID  ( -- )
    84 emit-char        \ 'T'
    TASK-ID 48 + emit-char  \ '0'〜'7'
    emit-nl ;

\ ============================================================
\ 高レベル API（Forth で実装）
\ ============================================================

\ TASK-SLEEP: 自タスクをスリープ
: TASK-SLEEP  ( -- )
    KERN-TASK-SLEEP ;

\ TASK-WAKEUP: 指定タスクを起床
: TASK-WAKEUP  ( tid -- )
    KERN-TASK-WAKEUP ;

\ TASK-EXIT: 自タスクを終了
: TASK-EXIT  ( -- )
    KERN-TASK-EXIT ;

\ TASK-CREATE: 新タスク生成
: TASK-CREATE  ( entry -- )
    KERN-TASK-CREATE ;

\ MSG-SEND: メッセージ送信
: MSG-SEND  ( msg tid -- )
    KERN-MSG-SEND ;

\ MSG-RECV: メッセージ受信（ブロッキング）
: MSG-RECV  ( -- msg )
    KERN-MSG-RECV ;

\ ============================================================
\ 16進数出力ユーティリティ
\ ============================================================

: put-hex1  ( n -- )
    15 AND
    DUP 10 < IF 48 + ELSE 55 + THEN
    emit-char ;

: put-hex4  ( n -- )
    DUP 12 RSHIFT put-hex1
    DUP  8 RSHIFT put-hex1
    DUP  4 RSHIFT put-hex1
                  put-hex1 ;

\ ============================================================
\ メインエントリ（テスト用）
\ kernel_core の _kstart から呼ばれる
\ ============================================================
: main  ( -- )
    TASK-PRINT-ID
    HALT ;
