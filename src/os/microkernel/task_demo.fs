\ task_demo.fs - YSD8800 ISA2.2 マルチタスクデモ (Forth + kernel v0.5)
\ Force v1.0
\ Version: 1.1
\
\ カーネルのタスク切り替えとメッセージパッシングを使うデモ。
\
\ タスク構成:
\   タスク0: "T0:RDY\n" を出力 → タスク1に $1234 を MSG-SEND → TASK-EXIT
\   タスク1: MSG-RECV で受信  → "T1:RX:1234\n" を出力 → TASK-EXIT
\
\ メモリ配置:
\   $0000-$08E9: kernel.asm
\   $0360:       TASK0_ENTRY → WORD_main       (task_patch.asm)
\   $03C0:       TASK1_ENTRY → WORD_task1_main (task_patch.asm)
\   $0A00-:      Force生成コード（このファイル）
\
\ ビルド: make task_demo
\ 実行:   ./emu22 build/task_demo/task_demo.bin -q
\ 期待出力:
\   T0:RDY
\   T1:RX:1234

\ ---- I/Oポート ----
$FC80 CONSTANT UART-TX
$FC84 CONSTANT UART-STAT

\ ---- カーネルAPI ブリッジ ----
\ カーネルはForthデータスタック(X)規約でAPIを公開している

CODE TASK-EXIT    ( -- )
    JSR $0460
END-CODE

CODE MSG-SEND     ( msg tid -- )
    JSR $0740
END-CODE

CODE MSG-RECV     ( -- msg )
    JSR $07E0
END-CODE

\ ---- UART出力 ----
: emit-char  ( c -- )
    BEGIN UART-STAT @ 0<> UNTIL
    UART-TX ! ;

: emit-nl  ( -- )  10 emit-char ;

\ ---- 16進出力 ----
: put-hex1  ( n -- )
    15 AND
    DUP 10 < IF 48 + ELSE 55 + THEN
    emit-char ;

: put-hex4  ( n -- )
    DUP 12 RSHIFT put-hex1
    DUP  8 RSHIFT put-hex1
    DUP  4 RSHIFT put-hex1
                  put-hex1 ;

\ ---- タスク1: 受信側 ----
\ TASK1_ENTRY ($03C0) → WORD_task1_main にリダイレクト済み
: task1-main  ( -- )
    MSG-RECV
    84 emit-char    \ T
    49 emit-char    \ 1
    58 emit-char    \ :
    82 emit-char    \ R
    88 emit-char    \ X
    58 emit-char    \ :
    put-hex4
    emit-nl
    TASK-EXIT
    HALT ;          \ 全タスク終了後に停止

\ ---- タスク0 (main): 送信側 ----
\ TASK0_ENTRY ($0360) → WORD_main にリダイレクト済み
: main  ( -- )
    84 emit-char    \ T
    48 emit-char    \ 0
    58 emit-char    \ :
    82 emit-char    \ R
    68 emit-char    \ D
    89 emit-char    \ Y
    emit-nl
    $1234           \ msg
    1               \ tid=1
    MSG-SEND
    TASK-EXIT ;
