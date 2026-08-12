\ kernel_forth.fs - YUI OS カーネル Forth 層
\ Version: 0.5.1
\ YSD8800 YUI OS Microkernel
\
\ 設計方針:
\   - IRQ0ハンドラ・コンテキストスイッチはアセンブラ（kernel.asm）
\   - 高レベルAPIはここで純粋Forthとして実装（移植性重視）
\   - ハードウェア依存部は CODE...END-CODE に隔離
\
\ v0.1: TASK-ID, TASK-PRINT-ID をForth化
\ v0.2: TASK-WAKEUP, TASK-CREATE, MSG-SEND, MSG-RECV をForth化
\ v0.3: ISA2.3 v2.2.1メモリマップ対応
\ v0.4: kernel.asm v0.8対応（YUI OS v2.0 Ph.1 IPC拡張）
\       TCBサイズ 64B→80B / IPC4ワード追加
\ v0.5: YUI OS v2.0 Ph.2 メモリマネージャ実装
\       - ページビットマップ管理（$E200/$E202）
\       - BMP-INIT / BMP-BIT-SET / BMP-BIT-CLR / BMP-BIT@ / BMP-FREE-COUNT
\       - FIT-START / FREE-PGNO VARIABLE（2PICK代替: Force v1.3未対応のため）
\       - ALLOC-FIT? / BMP-MARK-USED / MEM-ALLOC-PAGES / MEM-FREE-PAGES
\       - REORDER-MSG-3 / MEMMGR-DISPATCH / MEMMGR-TASK / MEMMGR-START
\       - デモタスク削除 → MEM-TEST-TASK に置き換え

\ ============================================================
\ ハードウェア定数（移植時はここを変更）
\ ============================================================
$FC80 CONSTANT UART-TX
$FC84 CONSTANT UART-STAT

\ ============================================================
\ TCB定数（v0.4: 80Bレイアウト対応）
\ ============================================================
$4000 CONSTANT TCB-POOL     \ TCBプール先頭（$4000-$427F: 8×80B=640B）
80    CONSTANT TCB-SIZE
$FBCE CONSTANT CALLSTK-BASE \ tid=0コールスタック頂上
$F9CE CONSTANT DATASTK-BASE \ tid=0データスタック頂上
$0100 CONSTANT TASK-STK-GAP \ タスク間スタック間隔

\ TCBオフセット（バイト）
0  CONSTANT TCB-STATE
2  CONSTANT TCB-PC
4  CONSTANT TCB-SP
6  CONSTANT TCB-DSP
8  CONSTANT TCB-A
12 CONSTANT TCB-FLAGS
16 CONSTANT TCB-IPC-MSG0   \ ipc_msg[0] opcode
18 CONSTANT TCB-IPC-MSG1   \ ipc_msg[1] arg0
20 CONSTANT TCB-IPC-MSG2   \ ipc_msg[2] arg1
22 CONSTANT TCB-IPC-MSG3   \ ipc_msg[3] arg2/result
24 CONSTANT TCB-IPC-VALID
26 CONSTANT TCB-IPC-SENDER

\ タスク状態定数
0 CONSTANT TASK-DEAD
1 CONSTANT TASK-READY
2 CONSTANT TASK-RUNNING
3 CONSTANT TASK-SLEEPING
4 CONSTANT TASK-WAIT-MSG
5 CONSTANT TASK-WAIT-IPC
6 CONSTANT TASK-WAIT-REPLY

\ カーネルワーク変数
$4292 CONSTANT CUR-TASK-ADDR

\ ============================================================
\ MemMgr 定数（v0.5追加）
\ ============================================================
$E200 CONSTANT PAGE-BMP-LO      \ ビットマップ下位ワード（page 0-15）
$E202 CONSTANT PAGE-BMP-HI      \ ビットマップ上位ワード（page 16-31）
$E204 CONSTANT MEM-TID-ADDR     \ MemMgr tid 格納アドレス
$C000 CONSTANT PAGE-POOL-BASE   \ ページプール先頭
32    CONSTANT PAGE-TOTAL        \ 総ページ数
28    CONSTANT PAGE-USER-MAX     \ ユーザ用ページ数（OS予約4ページ除く）
$F000 CONSTANT PAGE-BMP-HI-INIT \ HI初期値（page28-31=bit12-15=1）
$0101 CONSTANT MEM-ALLOC-OP
$0102 CONSTANT MEM-FREE-OP
$0103 CONSTANT MEM-QUERY-OP

\ ============================================================
\ MemMgr 作業変数（v0.5追加）
\ Force v1.3 が 2PICK に未対応のため VARIABLE で代替
\ Force がカーネル変数領域（$E200〜）に自動配置する
\ 注意: 生成ASMで $E206 以降に配置されていることを確認すること
\ ============================================================
VARIABLE FIT-START   \ ALLOC-FIT? / BMP-MARK-USED 用: start を退避
VARIABLE FREE-PGNO   \ MEM-FREE-PAGES 用: page_no を退避

\ ============================================================
\ アーキテクチャ層 CODE...END-CODE ブリッジ
\ ============================================================

CODE DI-OP
    DI
END-CODE
CODE EI-OP
    EI
END-CODE

CODE KERN-TASK-SLEEP
    JSR $01C0
END-CODE
CODE KERN-TASK-EXIT
    JSR $0460
END-CODE
CODE KERN-TASK-CREATE
    JSR $0520
END-CODE
CODE KERN-TASK-WAKEUP-ASM
    JSR $0380
END-CODE

\ IPC4 低レベルブリッジ
\ IPC4-SEND-ASM  ( msg3 msg2 msg1 msg0 tid -- )
CODE IPC4-SEND-ASM
    JSR $0740
END-CODE
\ IPC4-RECV-ASM  ( -- msg3 msg2 msg1 msg0 )
CODE IPC4-RECV-ASM
    JSR $07E0
END-CODE
\ IPC4-CALL-ASM  ( msg3 msg2 msg1 msg0 tid -- )
CODE IPC4-CALL-ASM
    JSR $08C0
END-CODE
\ IPC4-REPLY-ASM  ( r3 r2 r1 r0 tid -- )
CODE IPC4-REPLY-ASM
    JSR $0B00
END-CODE

\ ============================================================
\ TCB操作プリミティブ
\ ============================================================

\ TCBアドレス計算: tid → TCBアドレス
\ v0.4: tid*80 = (tid<<6) + (tid<<4)
: TCB-ADDR  ( tid -- addr )
    DUP  6 LSHIFT
    SWAP 4 LSHIFT
    +
    TCB-POOL + ;

: TCB-@  ( tid off -- val )  SWAP TCB-ADDR + @ ;
: TCB-!  ( val tid off -- )  SWAP TCB-ADDR + ! ;

: TCB-STATE@  ( tid -- state )  TCB-STATE TCB-@ ;
: TCB-STATE!  ( state tid -- )  TCB-STATE TCB-! ;

: TCB-IPC-VALID@   ( tid -- valid )   TCB-IPC-VALID  TCB-@ ;
: TCB-IPC-SENDER@  ( tid -- sender )  TCB-IPC-SENDER TCB-@ ;
: TCB-IPC-MSG0@    ( tid -- val )     TCB-IPC-MSG0   TCB-@ ;
: TCB-IPC-MSG1@    ( tid -- val )     TCB-IPC-MSG1   TCB-@ ;
: TCB-IPC-MSG2@    ( tid -- val )     TCB-IPC-MSG2   TCB-@ ;
: TCB-IPC-MSG3@    ( tid -- val )     TCB-IPC-MSG3   TCB-@ ;

\ ============================================================
\ UART出力
\ ============================================================
: emit-char  ( c -- )
    BEGIN UART-STAT @ 0= INVERT UNTIL
    UART-TX ! ;

: emit-nl  ( -- )  10 emit-char ;

\ ============================================================
\ TASK-ID  ( -- tid )
\ ============================================================
: TASK-ID  ( -- tid )
    CUR-TASK-ADDR @ ;

\ ============================================================
\ TASK-PRINT-ID  ( -- )
\ ============================================================
: TASK-PRINT-ID  ( -- )
    84 emit-char
    TASK-ID 48 + emit-char
    emit-nl ;

\ ============================================================
\ TASK-WAKEUP  ( tid -- )
\ v0.4: SLEEPING(3) / WAIT-IPC(5) → READY
\ ============================================================
: TASK-WAKEUP  ( tid -- )
    DUP TCB-STATE@
    DUP TASK-SLEEPING =
    SWAP TASK-WAIT-IPC =
    OR
    IF
        TASK-READY SWAP TCB-STATE!
    ELSE
        DROP
    THEN ;

\ ============================================================
\ TASK-CREATE  ( entry -- tid )
\ ============================================================
: TASK-CREATE  ( entry -- tid )
    KERN-TASK-CREATE ;

\ ============================================================
\ TASK-EXIT  ( -- )
\ ============================================================
: TASK-EXIT  ( -- )
    KERN-TASK-EXIT ;

\ ============================================================
\ TASK-SLEEP  ( -- )
\ ============================================================
: TASK-SLEEP  ( -- )
    KERN-TASK-SLEEP ;

\ ============================================================
\ IPC4ワード（v0.4）
\ ============================================================
: IPC4-SEND  ( msg3 msg2 msg1 msg0 tid -- )
    IPC4-SEND-ASM ;

: IPC4-RECV  ( -- msg3 msg2 msg1 msg0 )
    IPC4-RECV-ASM ;

: IPC4-CALL  ( msg3 msg2 msg1 msg0 tid -- r3 r2 r1 r0 )
    IPC4-CALL-ASM ;

: IPC4-REPLY  ( r3 r2 r1 r0 tid -- )
    IPC4-REPLY-ASM ;

\ IPC4-SENDER-DIRECT: DSPを使わずにsender tidを直接取得
\ CUR_TASK($4292)→tid→TCB[$4000+tid*80+26]を読む
\ スタック上のデータを破壊しない
CODE IPC4-SENDER-DIRECT  ( -- tid )
    DI                       ; IRQ競合防止（L1_WK_TMP/L1_WK_C共有）
    STW  X, [$4288]          ; DSP退避（IRQ_WK_X流用）
    LDW  A, [$4292]          ; A = CUR_TASK
    STW  A, [$4286]          ; L1_WK_TMP = tid
    LDW  B, #6
    SHL  A, B                ; A = tid*64
    STW  A, [$4284]          ; L1_WK_C
    LDW  A, [$4286]          ; A = tid
    LDW  B, #4
    SHL  A, B                ; A = tid*16
    LDW  B, [$4284]          ; B = tid*64
    ADD  A, B                ; A = tid*80
    LDW  B, #$4000
    ADD  A, B                ; A = TCB addr
    MOV  X, A                ; X = TCB addr
    LDW  A, [X + #26]        ; A = TCB[+26] = ipc_sender
    LDW  X, [$4288]          ; DSP復元
    SUBI X, #2
    STW  A, [X]              ; push tid
    EI
END-CODE

: IPC4-SENDER  ( -- tid )
    TASK-ID TCB-IPC-SENDER@ ;

\ ============================================================
\ v0.5: メモリマネージャ（MemMgr）実装
\ ============================================================

\ ============================================================
\ ビットマップ操作ワード
\ ============================================================

\ BMP-INIT  ( -- )
\ ページビットマップ初期化
\ page 0-15: 全空き（$0000）
\ page 16-27: 空き、page 28-31: OS予約（$F000）
: BMP-INIT  ( -- )
    0                PAGE-BMP-LO !
    PAGE-BMP-HI-INIT PAGE-BMP-HI ! ;

\ BMP-BIT-SET  ( page_no -- )
\ 指定ページを使用中（bit=1）にセット
: BMP-BIT-SET  ( page_no -- )
    DUP 16 <
    IF
        1 SWAP LSHIFT
        PAGE-BMP-LO @ OR
        PAGE-BMP-LO !
    ELSE
        16 -
        1 SWAP LSHIFT
        PAGE-BMP-HI @ OR
        PAGE-BMP-HI !
    THEN ;

\ BMP-BIT-CLR  ( page_no -- )
\ 指定ページを空き（bit=0）にクリア
: BMP-BIT-CLR  ( page_no -- )
    DUP 16 <
    IF
        1 SWAP LSHIFT INVERT
        PAGE-BMP-LO @ AND
        PAGE-BMP-LO !
    ELSE
        16 -
        1 SWAP LSHIFT INVERT
        PAGE-BMP-HI @ AND
        PAGE-BMP-HI !
    THEN ;

\ BMP-BIT@  ( page_no -- flag )
\ 指定ページのビット状態を返す（0=空き、0以外=使用中）
: BMP-BIT@  ( page_no -- flag )
    DUP 16 <
    IF
        1 SWAP LSHIFT
        PAGE-BMP-LO @ AND
    ELSE
        16 -
        1 SWAP LSHIFT
        PAGE-BMP-HI @ AND
    THEN
    0= INVERT ;

\ BMP-FREE-COUNT  ( -- n )
\ 空きページ数を返す（全32ページスキャン）
\ page_no をRスタックで管理し、データスタックには count のみを置く
\ Force v1.3: BEGIN/WHILE後のA残骸問題を回避。REPEAT後DUP DROPでcount→A確定
: BMP-FREE-COUNT  ( -- n )
    0 >R             \ R=page_no=0
    0                \ count（データスタック上）
    BEGIN R@ PAGE-TOTAL < WHILE
        R@ BMP-BIT@ 0=
        IF 1+ THEN   \ 空きなら count++
        R> 1+ >R     \ page_no++
    REPEAT
    R> DROP          \ page_noをRから捨てる
    DUP DROP ;       \ Force TOS=A残骸対策: count を A に確定してRET

\ ============================================================
\ ページ割り当て補助ワード
\ ============================================================

\ ALLOC-FIT?  ( start n -- flag )
\ start から n ページ全てが空きか確認する
\ -1=全空き（成功）、0=失敗
: ALLOC-FIT?  ( start n -- flag )
    OVER FIT-START !         \ start を変数に退避
    0                        \ start n i=0
    BEGIN DUP OVER < WHILE   \ i < n
        FIT-START @ OVER +   \ start n i (start+i)
        BMP-BIT@             \ start n i bit
        IF                   \ 使用中→失敗
            DROP DROP        \ n i 捨て
            0 EXIT
        THEN
        1+                   \ i++
    REPEAT
    DROP DROP -1 ;           \ n i 捨て、-1（成功）を返す

\ BMP-MARK-USED  ( start n -- )
\ start から n ページを使用中にマーク
: BMP-MARK-USED  ( start n -- )
    OVER FIT-START !         \ start を変数に退避
    0                        \ start n i=0
    BEGIN DUP OVER < WHILE   \ i < n
        FIT-START @ OVER +   \ start n i (start+i)
        BMP-BIT-SET
        1+
    REPEAT
    DROP DROP DROP ;         \ start n i 捨て

\ ============================================================
\ MEM-ALLOC-PAGES  ( n -- addr )
\ n 連続ページを First Fit で割り当て
\ 戻り値: 先頭アドレス（失敗=0）
: MEM-ALLOC-PAGES  ( n -- addr )
    DUP 0=              IF DROP 0 EXIT THEN
    DUP PAGE-USER-MAX > IF DROP 0 EXIT THEN

    DUP >R                        \ R=n
    PAGE-USER-MAX SWAP -          \ max_start = 28-n

    0                             \ max_start start=0
    BEGIN
        DUP OVER > INVERT WHILE   \ start <= max_start
        DUP R@ ALLOC-FIT?
        IF
            DUP R@ BMP-MARK-USED  \ 使用中マーク
            256 * PAGE-POOL-BASE + \ addr = $C000 + start*256
            SWAP DROP             \ max_start 捨て
            R> DROP EXIT          \ addr を返す
        THEN
        1+                        \ start++
    REPEAT
    DROP DROP R> DROP 0 ;         \ 失敗: 0

\ ============================================================
\ MEM-FREE-PAGES  ( addr n -- )
\ addr から n ページを解放
\ ============================================================
: MEM-FREE-PAGES  ( addr n -- )
    DUP 0= IF DROP DROP EXIT THEN

    OVER PAGE-POOL-BASE -         \ n (addr-$C000)
    DUP 0< IF
        DROP DROP EXIT
    THEN
    8 RSHIFT                      \ n page_no
    DUP 255 > IF DROP DROP EXIT THEN

    DUP PAGE-USER-MAX >= IF
        DROP DROP EXIT
    THEN

    OVER FREE-PGNO !              \ n を退避
    OVER                          \ n page_no page_no
    FREE-PGNO @ +                 \ n page_no (page_no+n)
    PAGE-USER-MAX > IF
        DROP DROP EXIT
    THEN

    FREE-PGNO !                   \ n → FREE-PGNO
    FREE-PGNO @ SWAP              \ page_no n
    FREE-PGNO !                   \ page_no を確定退避、n はスタック

    0                             \ n i=0
    BEGIN DUP OVER < WHILE        \ i < n
        FREE-PGNO @ OVER +        \ n i (page_no+i)
        BMP-BIT-CLR
        1+
    REPEAT
    DROP DROP ;

\ ============================================================
\ IPC4 メッセージ整列ワード
\ ============================================================

\ REORDER-MSG-3  ( msg3 msg2 msg1 msg0 -- op arg0 arg1 )
: REORDER-MSG-3  ( msg3 msg2 msg1 msg0 -- arg1 arg0 op )
    \ msg0=op, msg1=arg0, msg2=arg1, msg3=不使用
    \ msg3 を捨てるため >R して NIP的処理
    >R >R >R     \ R: msg2 msg1 msg0 退避
    DROP         \ msg3を捨てる
    R> R> R> ;   \ msg2(arg1) msg1(arg0) msg0(op) を順に戻す → TOS=op

\ ============================================================
\ MemMgr サーバタスク
\ ============================================================

\ MEMMGR-DISPATCH  ( op arg0 arg1 client_tid -- )
: MEMMGR-DISPATCH  ( arg1 arg0 op client_tid -- )
    \ REORDER-MSG-3 出力 arg1 arg0 op(TOS)
    \ + IPC4-SENDER で client_tid push: arg1 arg0 op client_tid(TOS)
    \ ※実際の呼び出しでは MEMMGR-TASK 側で処理
    >R                            \ R=client_tid → arg1 arg0 op(TOS)

    \ --- MEM_ALLOC ($0101) ---
    DUP MEM-ALLOC-OP = IF
        DROP                      \ op を捨てる → arg1 arg0(TOS=pages)
        SWAP DROP                 \ arg1 を捨てる → arg0=pages(TOS)
        MEM-ALLOC-PAGES           \ addr
        >R
        0 0 0
        R>                        \ r0=addr
        R> IPC4-REPLY
        EXIT
    THEN

    \ --- MEM_FREE ($0102) ---
    DUP MEM-FREE-OP = IF
        DROP                      \ op を捨てる → arg1(n) arg0(addr)(TOS)
        SWAP                      \ arg0(addr) arg1(n)(TOS) ← MEM-FREE-PAGES の引数順
        MEM-FREE-PAGES
        0 0 0 0 R> IPC4-REPLY
        EXIT
    THEN

    \ --- MEM_QUERY ($0103) ---
    MEM-QUERY-OP = IF
        DROP DROP                 \ arg1 arg0 を捨てる
        BMP-FREE-COUNT            \ count
        >R
        0 0 0
        R>                        \ r0=count
        R> IPC4-REPLY
        EXIT
    THEN

    DROP DROP
    0 0 0 0 R> IPC4-REPLY ;

\ MEMMGR-TASK  ( -- )
: MEMMGR-TASK  ( -- )
    BMP-INIT
    BEGIN
        IPC4-RECV                 \ ( -- msg3 msg2 msg1 msg0 )
        IPC4-SENDER-DIRECT >R     \ R=tid（DSP不使用で安全取得）
        REORDER-MSG-3             \ ( -- op arg0 arg1 )
        R>                        \ ( -- op arg0 arg1 tid )
        MEMMGR-DISPATCH
    AGAIN ;

\ MEMMGR-START  ( -- )
CODE MEMMGR-TASK-ADDR  ( -- addr )
    SUBI X, #2
    LDW  A, #WORD_MEMMGR_TASK
    STW  A, [X]
END-CODE

: MEMMGR-START  ( -- )
    MEMMGR-TASK-ADDR TASK-CREATE
    MEM-TID-ADDR ! ;

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
