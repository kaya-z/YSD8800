\ counter.fs - YSD8800 ISA2.2 カウンタサンプル (Forth)
\ Force v1.0
\
\ 0〜9 を1行ずつ出力して "Done!" で終了する。
\
\ ビルド: make counter_fs

$FC80 CONSTANT UART-TX
$FC84 CONSTANT UART-STAT

: emit-char  ( c -- )
    BEGIN UART-STAT @ 0<> UNTIL
    UART-TX ! ;

: emit-nl  ( -- )  10 emit-char ;

: put-digit  ( n -- )
    48 +  emit-char ;   \ '0' = 48

: main  ( -- )
    0
    BEGIN
        DUP 10 <
    WHILE
        DUP put-digit
        emit-nl
        1+
    REPEAT
    DROP
    \ Done!
    68 emit-char   \ D
    111 emit-char  \ o
    110 emit-char  \ n
    101 emit-char  \ e
    33 emit-char   \ !
    emit-nl
    HALT ;
