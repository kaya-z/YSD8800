\ Force end-to-end テスト v1
\ 基本的なForth構文をすべてカバー

\ 定数定義
42 CONSTANT answer
3 CONSTANT THREE

\ 変数定義
VARIABLE counter

\ VALUE定義
0 VALUE cur-task

\ DEFER宣言
DEFER irq-disable
DEFER irq-enable

\ シンプルなコロン定義
: double  ( n -- n*2 )
  2* ;

: square  ( n -- n*n )
  DUP * ;

\ IF/THEN
: abs-val  ( n -- |n| )
  DUP 0< IF NEGATE THEN ;

\ IF/ELSE/THEN
: max2  ( a b -- max )
  OVER OVER < IF SWAP THEN DROP ;

\ BEGIN/WHILE/REPEAT
: count-down  ( n -- )
  BEGIN DUP 0> WHILE 1- REPEAT DROP ;

\ BEGIN/UNTIL
: wait-zero  ( -- )
  BEGIN counter @ 0= UNTIL ;

\ ネストした制御構造
: clamp  ( n lo hi -- n' )
  ROT              \ lo hi n
  OVER OVER < IF   \ lo hi n, if n < lo
    DROP OVER      \ lo lo
  ELSE
    SWAP           \ lo n hi
    OVER OVER > IF
      DROP         \ lo hi
    ELSE
      NIP          \ lo n
      NIP          \ n
    THEN
  THEN
  NIP ;

\ CODE...END-CODE
CODE di-impl
    DI
END-CODE

CODE ei-impl
    EI
END-CODE

\ IS
['] di-impl IS irq-disable
['] ei-impl IS irq-enable

\ VALUEへのTO
5 TO cur-task
