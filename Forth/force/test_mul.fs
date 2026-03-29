\ test_mul.fs - 乗算テスト

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

: main  ( -- )
  4 5 *    20 check
  7 7 *    49 check
  0 99 *    0 check
  1 42 *   42 check
  12 12 * 144 check
  HALT ;
