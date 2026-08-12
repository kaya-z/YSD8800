\ task_demo_v2.fs - kernel_forth.fs APIを使うタスクデモ
\ Version: 1.1
\
\ kernel_forth.fs と結合して使う。
\ ビルド: make task_demo_v2

\ ---- 16進出力ユーティリティ（アプリ層） ----
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
    TASK-PRINT-ID
    $1234
    1
    MSG-SEND
    TASK-EXIT ;
