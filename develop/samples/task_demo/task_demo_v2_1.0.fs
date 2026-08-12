\ task_demo_v2.fs - kernel_forth.fs を使ったタスクデモ
\ Version: 1.0
\
\ kernel_forth.fs の高レベルAPI (TASK-PRINT-ID, MSG-SEND/RECV等) を使用。
\ task_demo.fs との違い: カーネルAPIを直接ブリッジせず
\                        kernel_forth の Forth ワードを呼ぶ

\ kernel_forth.fs で定義済みのワードを使う:
\   TASK-PRINT-ID, MSG-SEND, MSG-RECV, TASK-EXIT
\   emit-char, emit-nl, put-hex4

\ ---- タスク1: 受信側 ----
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
    TASK-EXIT ;

\ ---- タスク0 (main): 送信側 ----
: main  ( -- )
    TASK-PRINT-ID   \ "T0\n" を出力
    $1234
    1
    MSG-SEND
    TASK-EXIT ;
