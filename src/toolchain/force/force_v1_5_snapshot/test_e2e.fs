\ test_e2e.fs v2 - factorialを除外してまず基本動作確認

$FC80 CONSTANT UART-TX
$FC84 CONSTANT UART-STAT

: emit-char  ( c -- )
  BEGIN UART-STAT @ 0<> UNTIL
  UART-TX ! ;

: emit-nl  ( -- )  10 emit-char ;

: check  ( got exp -- )
  OVER OVER = IF
    DROP DROP
    79 emit-char 75 emit-char emit-nl
  ELSE
    DROP DROP
    78 emit-char 71 emit-char emit-nl
  THEN ;

: double  ( n -- 2n )  2* ;

: abs-val  ( n -- |n| )
  DUP 0< IF NEGATE THEN ;

: max2  ( a b -- max )
  OVER OVER < IF SWAP THEN DROP ;

: min2  ( a b -- min )
  OVER OVER > IF SWAP THEN DROP ;

: main  ( -- )
  6 double          12 check
  0 double           0 check
  5 abs-val          5 check
  -3 abs-val         3 check
  3 7 max2           7 check
  9 2 max2           9 check
  3 7 min2           3 check
  9 2 min2           2 check
  10 3 +            13 check
  10 3 -             7 check
  $0F $FF AND       15 check
  $F0 $0F OR       255 check
  $FF INVERT         0 check
  HALT ;
