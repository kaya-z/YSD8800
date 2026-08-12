
\ ============================================================
\ [SHELL] Ph.6 Forth 常駐 Shell (Level 1)  phase1: help+run骨格
\   設計: yuios_ph6_shell_design_v1_1.md (review v1.1 条件なし承認)
\   実装注記: 65Bバッファは Force VARIABLE では確保困難のため DATA域
\   ($DC00-$DCFF)上端側に CONSTANT固定アドレスで確保。VARIABLE自動配置
\   (下から上昇・現状$DC52)とバッファ($DC80+)で非衝突。索引はVARIABLEで持つ。
\ ============================================================
$DC80 CONSTANT SH-CMD-BUF        \ コマンド名 16B
$DC90 CONSTANT SH-ARG-BUF        \ 引数 16B
$DCB0 CONSTANT SH-LINE-BUF       \ 入力行 65B ($DCB0-$DCF0)
$DCA0 CONSTANT SH-PROMPT-BUF     \ "YUI> " 6B
$DCA6 CONSTANT SH-RUN-KW         \ "run" 4B
$DCAA CONSTANT SH-HELP-KW        \ "help" 5B ($DCAA-$DCAE)
VARIABLE SH-LINE-LEN             \ 行長(0-64)
VARIABLE SH-SI                   \ parse: source index
VARIABLE SH-DI                   \ parse: dest index
VARIABLE SH-DST                  \ parse: dest buffer ptr

: SH-INIT-STRINGS  ( -- )
    $59 SH-PROMPT-BUF C! $55 SH-PROMPT-BUF 1 + C! $49 SH-PROMPT-BUF 2 + C!
    $3E SH-PROMPT-BUF 3 + C! $20 SH-PROMPT-BUF 4 + C! $00 SH-PROMPT-BUF 5 + C!
    $72 SH-RUN-KW C! $75 SH-RUN-KW 1 + C! $6E SH-RUN-KW 2 + C! $00 SH-RUN-KW 3 + C!
    $68 SH-HELP-KW C! $65 SH-HELP-KW 1 + C! $6C SH-HELP-KW 2 + C! $70 SH-HELP-KW 3 + C! $00 SH-HELP-KW 4 + C! ;

: SH-EMIT   ( ch -- )      0 0 ROT UART-PUTC-OP UART-DRV-TID @ IPC4-CALL DROP DROP DROP DROP ;
: SH-TYPE   ( straddr -- ) 0 0 ROT UART-PUTS-OP UART-DRV-TID @ IPC4-CALL DROP DROP DROP DROP ;
: SH-KEY    ( -- ch )      0 0 0   UART-GETC-OP UART-DRV-TID @ IPC4-CALL >R DROP DROP DROP R> ;
: SH-CR     ( -- )         $0D SH-EMIT  $0A SH-EMIT ;

: SH-READLINE  ( -- )
    0 SH-LINE-LEN !
    BEGIN
        SH-KEY
        DUP $0D = IF
            DROP  0 SH-LINE-BUF SH-LINE-LEN @ + C!  SH-CR EXIT
        THEN
        DUP $08 = OVER $7F = OR IF
            DROP
            SH-LINE-LEN @ 0> IF
                $08 SH-EMIT $20 SH-EMIT $08 SH-EMIT
                SH-LINE-LEN @ 1- SH-LINE-LEN !
            THEN
        ELSE
            DUP SH-EMIT
            SH-LINE-LEN @ 64 < IF
                DUP SH-LINE-BUF SH-LINE-LEN @ + C!
                SH-LINE-LEN @ 1+ SH-LINE-LEN !
            ELSE DROP THEN
        THEN
    AGAIN ;

\ NUL終端文字列の等値比較 ( a b -- flag )  index は使わずポインタ前進
: SH-STR=  ( a b -- flag )
    BEGIN
        OVER C@ OVER C@            \ ( a b ca cb )
        OVER OVER = IF
            DROP DROP              \ ( a b )
            DUP C@ 0= IF DROP DROP -1 EXIT THEN
            1+ SWAP 1+ SWAP        \ ( a+1 b+1 )
        ELSE
            DROP DROP DROP DROP 0 EXIT
        THEN
    AGAIN ;

\ 空白スキップ: SH-SI を空白以外まで進める
: SH-SKIP-SP  ( -- )
    BEGIN SH-LINE-BUF SH-SI @ + C@ $20 = WHILE SH-SI @ 1+ SH-SI ! REPEAT ;

\ 1語を dstbuf へコピー(空白/NUL終端・最大15)。SH-SI を語の次へ進める
: SH-COPY-WORD  ( dstbuf -- )
    SH-DST !  0 SH-DI !
    BEGIN
        SH-LINE-BUF SH-SI @ + C@   \ ( ch )
        DUP $20 = OVER 0= OR IF    \ 語終端(空白orNUL)?
            DROP
            0  SH-DST @ SH-DI @ +  C!   \ dst[di]=NUL ( byte=0 addr )
            EXIT
        THEN
        SH-DI @ 15 < IF            \ ( ch )
            SH-DST @ SH-DI @ +  C! \ dst[di]=ch ( byte=ch addr )
            SH-DI @ 1+ SH-DI !
        ELSE DROP THEN
        SH-SI @ 1+ SH-SI !
    AGAIN ;

: SH-PARSE  ( -- )
    0 SH-SI !
    SH-SKIP-SP
    SH-CMD-BUF SH-COPY-WORD
    SH-SKIP-SP
    SH-ARG-BUF SH-COPY-WORD ;

: SH-CMD-HELP  ( -- )
    \ help本文は1行ずつEMITで出力(文字列バッファ節約)
    $72 SH-EMIT $75 SH-EMIT $6E SH-EMIT $20 SH-EMIT
    $3C SH-EMIT $6E SH-EMIT $3E SH-EMIT SH-CR     \ "run <n>"
    $68 SH-EMIT $65 SH-EMIT $6C SH-EMIT $70 SH-EMIT SH-CR ;  \ "help"

: SH-CMD-RUN   ( -- )
    SH-ARG-BUF C@ 0= IF
        $3F SH-EMIT SH-CR EXIT                     \ 引数なし→'?'
    THEN
    0 0 SH-ARG-BUF PROC-EXEC-OP PROC-TID-ADDR @ IPC4-CALL
    >R DROP DROP DROP R>
    DUP 0< IF DROP $21 SH-EMIT SH-CR EXIT THEN     \ exec失敗→'!'
    0 0 ROT PROC-WAIT-OP PROC-TID-ADDR @ IPC4-CALL
    DROP DROP DROP DROP ;

\ --- [SHELL phase2] ps コマンド追加 ---
\ ps-buf: tid一覧格納 32B(16件×2B)。VAR_*上昇域($DC5A)とSHバッファ($DC80)の間 $DC60 に固定。
$DC60 CONSTANT SH-PS-BUF         \ 32B ($DC60-$DC7F)
VARIABLE SH-PS-N                 \ PROC_LIST が返した件数
VARIABLE SH-PS-I                 \ ループindex

\ "ps" キーワード ($DCAF は1B空き→不足。SH-PS-KW を辞書内VARIABLE風に置けないので
\  SH-INIT-STRINGS で SH-ARG-BUF後方未使用や専用領域に。ここは $DCF1(SH-LINE上端後)3B使用)
$DCF1 CONSTANT SH-PS-KW          \ "ps\0" 3B ($DCF1-$DCF3)

: SH-INIT-PS-KW  ( -- )
    $70 SH-PS-KW C!  $73 SH-PS-KW 1 + C!  $00 SH-PS-KW 2 + C! ;

\ tid(0-15)を10進2桁未満で出力(除算不使用)
: SH-EMIT-TID  ( tid -- )
    DUP 10 < IF
        $30 + SH-EMIT                      \ 1桁
    ELSE
        $31 SH-EMIT                        \ 十の位'1'
        10 - $30 + SH-EMIT                 \ 一の位
    THEN ;

: SH-CMD-PS  ( -- )
    \ 0 bufsize buf PROC-LIST-OP procmgr IPC4-CALL → r0=count
    0  32  SH-PS-BUF  PROC-LIST-OP  PROC-TID-ADDR @  IPC4-CALL
    >R DROP DROP DROP R>                   \ r0=count
    SH-PS-N !
    0 SH-PS-I !
    BEGIN
        SH-PS-I @ SH-PS-N @ <
    WHILE
        SH-PS-BUF SH-PS-I @ 2* + @        \ tid = buf[i]
        SH-EMIT-TID
        $20 SH-EMIT                        \ 区切り空白
        SH-PS-I @ 1+ SH-PS-I !
    REPEAT
    SH-CR ;

: SH-DISPATCH  ( -- )
    SH-CMD-BUF C@ 0= IF EXIT THEN
    SH-CMD-BUF SH-RUN-KW  SH-STR= IF SH-CMD-RUN  EXIT THEN
    SH-CMD-BUF SH-HELP-KW SH-STR= IF SH-CMD-HELP EXIT THEN
    SH-CMD-BUF SH-PS-KW   SH-STR= IF SH-CMD-PS   EXIT THEN
    $3F SH-EMIT SH-CR ;

: SHELL-TASK  ( -- )
    SH-INIT-STRINGS
    SH-INIT-PS-KW
    BEGIN
        SH-PROMPT-BUF SH-TYPE
        SH-READLINE
        SH-LINE-LEN @ 0> IF
            SH-PARSE
            SH-DISPATCH
        THEN
    AGAIN ;
CODE SHELL-TASK-ADDR  ( -- addr )
    SUBI X, #2
    LDW  A, #WORD_SHELL_TASK
    STW  A, [X]
END-CODE
: SHELL-START  ( -- )  SHELL-TASK-ADDR TASK-CREATE DROP ;
\ ============================================================
\ [SHELL] ここまで
\ ============================================================

