\ test_run.fs - Force生成コードの動作確認
\ abs-val / max2 / count-down を呼んで結果をUART出力

\ ---- 定数 ----
$FC80 CONSTANT UART-TX
$FC84 CONSTANT UART-STAT

\ ---- ユーティリティ ----
: emit-char  ( c -- )
  BEGIN UART-STAT @ 0<> UNTIL
  UART-TX ! ;

: emit-digit  ( n -- )   \ 0-15 を '0'-'9'/'A'-'F' で出力
  DUP 10 < IF
    48 +           \ '0'
  ELSE
    55 +           \ 'A'-6 = 55
  THEN
  emit-char ;

: emit-hex  ( n -- )     \ 16進4桁出力
  DUP 12 RSHIFT 15 AND emit-digit
  DUP  8 RSHIFT 15 AND emit-digit
  DUP  4 RSHIFT 15 AND emit-digit
              15 AND emit-digit ;

: emit-nl   ( -- )   10 emit-char ;

: check  ( result expected label -- )
  \ result == expected なら "OK" else "NG: got xxxx"
  = IF
    79 emit-char 75 emit-char emit-nl   \ "OK\n"
  ELSE
    78 emit-char 71 emit-char 58 emit-char  \ "NG:"
    emit-hex emit-nl
  THEN ;

\ ---- テスト本体 ----
: run-tests  ( -- )
  \ abs-val(5) = 5
  5 abs-val  5  check
  \ abs-val(-3) = 3
  -3 abs-val  3  check
  \ max2(3,7) = 7
  3 7 max2  7  check
  \ max2(9,2) = 9
  9 2 max2  9  check
  \ double(6) = 12
  6 double  12  check
  \ square(4) = 16
  4 square  16  check ;
