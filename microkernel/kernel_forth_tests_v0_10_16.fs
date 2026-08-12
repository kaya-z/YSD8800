\ kernel_forth_tests_v0_10_16.fs - YUI OS テストタスク退避 (CHAT58分離)
\ 元: kernel_forth_v0_10_16.fs。OS-START未起動デッドコード(v0.10.13起動除外済)。
\ MEM/UART/STOR-TEST群・DIAG群・PUTC-HEX群・BC-STR。検証時はここから復活。

\ === [退避: MEM-TEST-TASK] 元 行1122-1165 ===

\ ============================================================
\ MEM-TEST-TASK  ( -- )
\ 期待出力: M → 8（空き28の下1桁） → A → R
\ ============================================================
: MEM-TEST-TASK  ( -- )
    BEGIN
        0 TCB-ADDR TCB-STATE + @
        TASK-WAIT-IPC =
    UNTIL

    77 emit-char emit-nl          \ 'M'

    \ (1) MEM_QUERY
    0 0 0 MEM-QUERY-OP
    MEM-TID-ADDR @ IPC4-CALL
    >R DROP DROP DROP R>          \ r0(count)を残しr3 r2 r1をDROP
    \ 10進2桁表示 (count < 100 を前提)
    0 SWAP                        \ tens=0 count
    BEGIN DUP 10 >= WHILE
        10 - SWAP 1+ SWAP
    REPEAT                        \ tens ones
    SWAP 48 + emit-char           \ 十の位
    48 + emit-char emit-nl        \ 一の位

    \ (2) MEM_ALLOC
    0 0 2 MEM-ALLOC-OP
    MEM-TID-ADDR @ IPC4-CALL
    >R DROP DROP DROP R>          \ r0(addr)を残しr3 r2 r1をDROP
    DUP 0= IF
        DROP 70 emit-char
    ELSE
        65 emit-char
    THEN
    emit-nl

    \ (3) MEM_FREE
    >R
    0 2 R> MEM-FREE-OP
    MEM-TID-ADDR @ IPC4-CALL
    DROP DROP DROP DROP
    82 emit-char emit-nl          \ 'R'

    TASK-EXIT ;

\ === [退避: BC-STR+UART-TEST-TASK+UART-TEST-TASK-ADDR+UART-TEST-START] 元 行1332-1386 ===

\ ============================================================
\ v0.6: UARTテストタスク
\ 期待出力: ABCXD
\ yuios_ph3_uart_design_v1_2.docx §7
\ ============================================================

\ テスト用文字列 "BC\0" は kernel.asm v0.12.0 の $FC60 に配置
\ v0.7: $E230→$E260 → v0.7.1: $F040 → v0.8.0: $FC60（OS共有変数領域）
\ yuios_ph3_storage_design_v1_2.md §2.1
$FC60 CONSTANT BC-STR

: UART-TEST-TASK  ( -- )
    \ T1: PUTC 'A'($41)
    \ IPC4-CALL ( msg3 msg2 msg1 msg0 tid -- r3 r2 r1 r0 )
    \ msg0=op, msg1=arg0(char), msg2=arg1(unused), msg3=unused
    0 0 $41 UART-PUTC-OP  UART-DRV-TID @  IPC4-CALL
    DROP DROP DROP DROP

    \ T2: PUTS "BC"
    \ msg0=op, msg1=arg0(addr), msg2=arg1(unused), msg3=unused
    0 0 BC-STR UART-PUTS-OP  UART-DRV-TID @  IPC4-CALL
    DROP DROP DROP DROP

    \ T3-T4: GETC（バッファ空→ブロック、IRQで起床）
    0 0 0 UART-GETC-OP  UART-DRV-TID @  IPC4-CALL
    \ ( -- r3 r2 r1 r0 ) r0=受信文字
    SWAP DROP SWAP DROP SWAP DROP   \ r0のみ残す

    \ T5: 受信文字をエコーバック
    \ スタック: char (TOS) — GETCで受け取った文字
    \ msg0=op, msg1=arg0(char), msg2=0, msg3=0 の順に積む
    >R                               \ R:char, stack: empty
    0 0                              \ msg3=0, msg2=0
    R>                               \ msg3=0, msg2=0, msg1=char (TOS=char)
    UART-PUTC-OP                     \ msg0=UART-PUTC-OP
    UART-DRV-TID @                   \ tid
    IPC4-CALL
    DROP DROP DROP DROP

    \ T6: 完了マーカー 'D'($44)
    0 0 $44 UART-PUTC-OP  UART-DRV-TID @  IPC4-CALL
    DROP DROP DROP DROP

    BEGIN AGAIN ;                   \ 完了後は無限ループで停止待ち

CODE UART-TEST-TASK-ADDR  ( -- addr )
    SUBI X, #2
    LDW  A, #WORD_UART_TEST_TASK
    STW  A, [X]
END-CODE

: UART-TEST-START  ( -- )
    UART-TEST-TASK-ADDR TASK-CREATE
    DROP ;                          \ tidは不要なのでDROP

\ === [退避: STOR-TEST-TASK+STOR-TEST-TASK-ADDR+STOR-TEST-START+PUTC-HEX1+PUTC-HEX4+DIAG-STR-TID+DIAG-ALL-TIDS] 元 行1696-1818 ===

\ ============================================================
\ v0.7: ストレージテストタスク
\ 期待出力: ABCXD の後にスペース+'P'
\ yuios_ph3_storage_design_v1_2.md §7
\ ============================================================
: STOR-TEST-TASK  ( -- )
    \ S0: スペース出力（区切り）
    0 0 $20 UART-PUTC-OP UART-DRV-TID @ IPC4-CALL
    DROP DROP DROP DROP

    \ S1: src_buf にパターン書き込み（最初の8B: "STOR_TST"）
    $53 TEST-SRC-BUF       C!       \ 'S'
    $54 TEST-SRC-BUF 1 +   C!       \ 'T'
    $4F TEST-SRC-BUF 2 +   C!       \ 'O'
    $52 TEST-SRC-BUF 3 +   C!       \ 'R'
    $5F TEST-SRC-BUF 4 +   C!       \ '_'
    $54 TEST-SRC-BUF 5 +   C!       \ 'T'
    $53 TEST-SRC-BUF 6 +   C!       \ 'S'
    $54 TEST-SRC-BUF 7 +   C!       \ 'T'

    \ S2: STOR_WRITE LBA=10 (v0.10.1: 案α LBA衝突対処、LBA=0 はスーパーブロック専用)
    \ IPC4-CALL ( msg3 msg2 msg1 msg0 tid -- r3 r2 r1 r0 )
    \ msg2=arg1(src), msg1=arg0(LBA), msg0=op
    0 TEST-SRC-BUF 10 STOR-WRITE-OP STOR-DRV-TID @ IPC4-CALL
    >R DROP DROP DROP R>            \ r0のみ残す
    0= INVERT IF
        0 0 $46 UART-PUTC-OP UART-DRV-TID @ IPC4-CALL  \ 'F'
        DROP DROP DROP DROP
        $32 UART-PUTC-IMPL          \ v0.7.2: '2' = S2失敗
        BEGIN AGAIN                 \ v0.7.2: EXIT→暴走を回避
    THEN

    \ S3: STOR_READ LBA=10 → dst_buf (v0.10.1: 案α LBA衝突対処)
    0 TEST-DST-BUF 10 STOR-READ-OP STOR-DRV-TID @ IPC4-CALL
    >R DROP DROP DROP R>
    0= INVERT IF
        0 0 $46 UART-PUTC-OP UART-DRV-TID @ IPC4-CALL
        DROP DROP DROP DROP
        $33 UART-PUTC-IMPL          \ v0.7.2: '3' = S3失敗
        BEGIN AGAIN
    THEN

    \ S4: src と dst の最初の8B を比較
    \ Force v1.2 は DO/LOOP 未対応のため BEGIN/WHILE/REPEAT で実装
    \ stack使用: i (0..7)
    0
    BEGIN
        DUP 8 <
    WHILE
        \ stack: i
        DUP TEST-SRC-BUF + C@       \ stack: i src[i]
        OVER TEST-DST-BUF + C@      \ stack: i src[i] dst[i]
        <> IF
            DROP                    \ i捨て
            0 0 $46 UART-PUTC-OP UART-DRV-TID @ IPC4-CALL  \ 'F'
            DROP DROP DROP DROP
            $34 UART-PUTC-IMPL      \ v0.7.2: '4' = S4不一致
            BEGIN AGAIN
        THEN
        1 +
    REPEAT
    DROP                            \ i捨て

    \ S5: 全致 → 'P' 出力
    0 0 $50 UART-PUTC-OP UART-DRV-TID @ IPC4-CALL  \ 'P'
    DROP DROP DROP DROP
    BEGIN AGAIN ;                   \ v0.7.2: タスク終了暴走防止

CODE STOR-TEST-TASK-ADDR  ( -- addr )
    SUBI X, #2
    LDW  A, #WORD_STOR_TEST_TASK
    STW  A, [X]
END-CODE

: STOR-TEST-START  ( -- )
    STOR-TEST-TASK-ADDR TASK-CREATE
    DROP ;                          \ tidは不要なのでDROP

\ ============================================================
\ OS-START  ( -- )  v0.7: Ph.3-B対応メインエントリ
\ 起動順序: MEMMGR-START → UART-START → STOR-START → UART-TEST-START → STOR-TEST-START
\ その後ルートタスクは待機ループ
\ yuios_ph3_storage_design_v1_2.md §7.3
\ ============================================================
\ ------------------------------------------------------------
\ [HYP5-DIAG] PUTC-HEX1  ( nibble -- )  下位4bitをhex1桁で出力
\ ------------------------------------------------------------
: PUTC-HEX1  ( n -- )
    $0F AND
    DUP 10 < IF $30 + ELSE $37 + THEN
    UART-PUTC-IMPL ;

\ [HYP5-DIAG] PUTC-HEX4  ( w -- )  16bitをhex4桁で出力
: PUTC-HEX4  ( w -- )
    DUP 12 RSHIFT PUTC-HEX1
    DUP  8 RSHIFT PUTC-HEX1
    DUP  4 RSHIFT PUTC-HEX1
                  PUTC-HEX1 ;

\ [HYP5-DIAG] DIAG-STR-TID  ( -- )  STOR-DRV-TID を [STR=XXXX] 形式で出力
: DIAG-STR-TID  ( -- )
    $5B UART-PUTC-IMPL              \ '['
    $53 UART-PUTC-IMPL              \ 'S'
    $54 UART-PUTC-IMPL              \ 'T'
    $52 UART-PUTC-IMPL              \ 'R'
    $3D UART-PUTC-IMPL              \ '='
    STOR-DRV-TID @ PUTC-HEX4
    $5D UART-PUTC-IMPL              \ ']'
    ;

\ [HYP8-DIAG] DIAG-ALL-TIDS  ( -- )  全タスクtidを出力
: DIAG-ALL-TIDS  ( -- )
    $5B UART-PUTC-IMPL              \ '['
    $55 UART-PUTC-IMPL              \ 'U'
    $3D UART-PUTC-IMPL              \ '='
    UART-DRV-TID @ PUTC-HEX4
    $2C UART-PUTC-IMPL              \ ','
    $53 UART-PUTC-IMPL              \ 'S'
    $3D UART-PUTC-IMPL              \ '='
    STOR-DRV-TID @ PUTC-HEX4
    $5D UART-PUTC-IMPL              \ ']'
    ;
