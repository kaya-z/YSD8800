\ kernel_forth_tests_filemgr.fs - FILEMGR-TEST-TASK 退避ファイル
\ 由来: kernel_forth v0.10.13 から (b)当座辞書圧縮のため切り出し (2026-06-09)
\ 用途: FileMgr 再検証時に本体へ include で合体し、OS-START に
\       FILEMGR-TEST-START を一時追加して使用する。
\ 注意: 本体側に FT-FID($1860) / FT-*-BUF CONSTANT 定義が残存しているため、
\       本ファイル単独では完結しない。本体と組で使うこと。
\ ====================================================================

\ --------------------------------------------------------------------
\ FILEMGR-TEST-TASK  ( -- )                                   v0.10.3
\ v0.10.2d: 仮説ε検証用。FILE_STAT を即送信→'Q' 出力
\ v0.10.3 (Step 5-2): FILE_STAT 後に FILE-LIST-TEST を追加
\   - 試験 buf = TEST-DST-BUF + $100（=$EF00, 256B）
\     ※設計書 v1.5.2 §8.4.3.1 訂正後（旧 v1.5/v1.5.1 の $F900 はタスクスタック衝突）
\   - 期待 r0=1（mkfs が hello.txt 1個を作成）→ 'L' 出力
\   - r0≠1 なら 'l'（小文字）出力で識別
\ バッファは TEST-SRC-BUF/DST-BUF と衝突しないように +$80 / +$100 オフセット使用。
\ --------------------------------------------------------------------
: FILEMGR-TEST-TASK  ( -- )
    \ "no.txt\0" を TEST-SRC-BUF+$80 へ ($EC80, S5 後でも安全)
    $6E TEST-SRC-BUF $80 +     C!
    $6F TEST-SRC-BUF $80 + 1 + C!
    $2E TEST-SRC-BUF $80 + 2 + C!
    $74 TEST-SRC-BUF $80 + 3 + C!
    $78 TEST-SRC-BUF $80 + 4 + C!
    $74 TEST-SRC-BUF $80 + 5 + C!
    $00 TEST-SRC-BUF $80 + 6 + C!

    \ FILE_STAT 送信
    0 TEST-DST-BUF $80 + TEST-SRC-BUF $80 + FILE-STAT-OP FILEMGR-TID-ADDR @ IPC4-CALL
    >R DROP DROP DROP R>

    E-NOENT = IF
        $51 FILEMGR-PUTC                \ 'Q' (FILEMGR-PUTC 使用、オリジナルv0.10.2 と同形)
    ELSE
        $71 FILEMGR-PUTC                \ 'q'
    THEN

    \ v0.10.3 (Step 5-2): FILE-LIST-TEST
    \   IPC4-CALL ( msg3 msg2 msg1 msg0 tid -- r0 r1 r2 r3 )
    \   FILE_LIST: msg3=0, msg2=buf_size, msg1=buf_addr, msg0=op
    0                                       \ msg3 = arg2 = 0 (予約)
    $100                                    \ msg2 = arg1 = buf_size = 256
    TEST-DST-BUF $100 +                     \ msg1 = arg0 = buf_addr = $EF00
    FILE-LIST-OP                            \ msg0 = $0207
    FILEMGR-TID-ADDR @                      \ tid = FILEMGR-TID
    IPC4-CALL                               \ ( -- r0 r1 r2 r3 ), r0 = エントリ数
    >R DROP DROP DROP R>                    \ r1/r2/r3 を捨てて r0 のみ残す

    1 = IF
        $4C FILEMGR-PUTC                \ 'L' (FILE-LIST-IMPL 完了)
    ELSE
        $6C FILEMGR-PUTC                \ 'l' (失敗)
    THEN

    \ v0.10.4 (Step 5-3): FILE-OPEN-TEST
    \   設計書 v1.6.1 §8.4.4.2。"hello.txt"(mkfs --add-file で作成)を OPEN。
    \   最小空きindex方式(§5.3.3)により最初の OPEN は必ず fid=0 → r0=0 なら 'O'
    \   "hello.txt\0" を TEST-SRC-BUF+$A0 へ ($ECA0, 他テストバッファと非衝突)
    $68 TEST-SRC-BUF $A0 +     C!       \ 'h'
    $65 TEST-SRC-BUF $A0 + 1 + C!       \ 'e'
    $6C TEST-SRC-BUF $A0 + 2 + C!       \ 'l'
    $6C TEST-SRC-BUF $A0 + 3 + C!       \ 'l'
    $6F TEST-SRC-BUF $A0 + 4 + C!       \ 'o'
    $2E TEST-SRC-BUF $A0 + 5 + C!       \ '.'
    $74 TEST-SRC-BUF $A0 + 6 + C!       \ 't'
    $78 TEST-SRC-BUF $A0 + 7 + C!       \ 'x'
    $74 TEST-SRC-BUF $A0 + 8 + C!       \ 't'
    $00 TEST-SRC-BUF $A0 + 9 + C!       \ NUL

    \ FILE_OPEN 送信: msg3=arg2=0, msg2=arg1=0, msg1=arg0=name_addr, msg0=op
    0                                       \ msg3 = arg2 = 0
    0                                       \ msg2 = arg1 = 0
    TEST-SRC-BUF $A0 +                      \ msg1 = arg0 = name_addr
    FILE-OPEN-OP                            \ msg0 = $0201
    FILEMGR-TID-ADDR @                      \ tid
    IPC4-CALL                               \ ( -- r0 r1 r2 r3 ), r0 = fid or error
    >R DROP DROP DROP R>                    \ r1/r2/r3 を捨てて r0 のみ残す

    DUP FT-FID !                            \ ★v0.10.5: fid を CLOSE 用に保存
    0 = IF
        $4F FILEMGR-PUTC                \ 'O' (fid=0 で OPEN 成功)
    ELSE
        $6F FILEMGR-PUTC                \ 'o' (失敗 or fid≠0)
    THEN

    \ v0.10.6 (Step 5-5): FILE-READ-TEST
    \   設計書 v1.7.1 §8.4.5.3。O1 で得た fid(=FT-FID) に対し size=16 で READ。
    \   hello.txt の中身 "Hello, YUI OS!\n"(15B・mkfs --add-file が改行込み15B書込)を
    \   FT-DST-BUF へ読む。期待 r0=15（actual。size=16>残り15 で部分読み・EOF）かつ
    \   FT-DST-BUF[0]=='H'。★設計書 §8.4.5.3 は「14B」想定だったが mkfs_yuifs_v1_1.py
    \   の実装は 'Hello, YUI OS!\n'=15B（改行込み）であり、実態に合わせ 15 で検証する
    \   （設計書改版で §8.4.5.3 を 15B へ訂正予定・Step 5-5 報告事項）。
    \   ★OPEN→READ→CLOSE の順（CLOSE 後の fid で READ すると E-BADF になるため）。
    \   FILE_READ: msg3=arg2=size, msg2=arg1=dst, msg1=arg0=fid, msg0=op
    16                                      \ msg3 = arg2 = size = 16
    FT-DST-BUF                              \ msg2 = arg1 = dst = $EE00
    FT-FID @                                \ msg1 = arg0 = fid（OPEN で得た値）
    FILE-READ-OP                            \ msg0 = $0203
    FILEMGR-TID-ADDR @                      \ tid
    IPC4-CALL                               \ ( -- r0 r1 r2 r3 ), r0 = actual / err
    >R DROP DROP DROP R>                    \ r1/r2/r3 を捨てて r0 のみ残す

    \ 検証: r0==15 かつ FT-DST-BUF[0]=='H'($48) なら 'R'、それ以外は 'r'
    15 = IF
        FT-DST-BUF C@ $48 = IF
            $52 FILEMGR-PUTC            \ 'R' (READ 成功・actual=15・先頭'H')
        ELSE
            $72 FILEMGR-PUTC            \ 'r' (actual=15 だが先頭≠'H'＝コピー異常)
        THEN
    ELSE
        $72 FILEMGR-PUTC                \ 'r' (actual≠15)
    THEN

    \ ====== v0.10.10 (Step 5-SEEK): FILE-SEEK-TEST (§8.4.7) ======
    \   設計書 v1.9.3 §8.4.7。OPEN 済み fid(=FT-FID) に SEEK を試験（READ 後・CLOSE 前）。
    \   FS1: SEEK(fid, offset=5) → r0==5、続く READ で hello.txt[5]==','($2C)。
    \   FS3: SEEK(fid, offset=16=size+1) → E_INVAL($FE09)。
    \   FS4: SEEK(不正fid=FS-MAX-OPEN=4) → E_BADF($FE04)。
    \   3項全合格で 'S'($53)、いずれか不合格で 's'($73)。EQ=$FFFF カノニカルゆえ AND 合成可。
    \   IPC4-CALL: msg3=arg2=0, msg2=arg1=offset, msg1=arg0=fid, msg0=op
    \ FS1: SEEK offset=5 → r0==5
    0  5  FT-FID @  FILE-SEEK-OP  FILEMGR-TID-ADDR @  IPC4-CALL
    >R DROP DROP DROP R>                    \ r0 のみ
    5 =                                     \ flagS1a = (r0==5)
    \ FS1続: offset=5 から READ → 先頭が ','($2C) か（pos 反映の確認）
    16  FT-DST-BUF  FT-FID @  FILE-READ-OP  FILEMGR-TID-ADDR @  IPC4-CALL
    DROP DROP DROP DROP                     \ READ の戻りは使わない（先頭バイトで判定）
    FT-DST-BUF C@ $2C =                     \ flagS1b = (先頭==',')
    AND                                     \ flagS1
    \ FS3: SEEK offset=16(>size=15) → E_INVAL
    0  16  FT-FID @  FILE-SEEK-OP  FILEMGR-TID-ADDR @  IPC4-CALL
    >R DROP DROP DROP R>
    E-INVAL =                               \ flagS3
    AND
    \ FS4: SEEK 不正fid=FS-MAX-OPEN(=4) → E_BADF
    0  0  FS-MAX-OPEN  FILE-SEEK-OP  FILEMGR-TID-ADDR @  IPC4-CALL
    >R DROP DROP DROP R>
    E-BADF =                                \ flagS4
    AND
    IF
        $53 FILEMGR-PUTC                \ 'S' (SEEK 試験 FS1/FS3/FS4 全合格)
    ELSE
        $73 FILEMGR-PUTC                \ 's' (いずれか失敗)
    THEN

    \ v0.10.5 (Step 5-4): FILE-CLOSE-TEST
    \   設計書 v1.6.1 §8.4.4.3。O1 で得た fid(=FT-FID) を CLOSE。
    \   FILE_CLOSE: msg3=0, msg2=0, msg1=fid, msg0=op
    0                                       \ msg3 = arg2 = 0
    0                                       \ msg2 = arg1 = 0
    FT-FID @                                \ msg1 = arg0 = fid（OPEN で得た値）
    FILE-CLOSE-OP                           \ msg0 = $0202
    FILEMGR-TID-ADDR @                      \ tid
    IPC4-CALL                               \ ( -- r0 r1 r2 r3 ), r0 = E-OK / E-BADF
    >R DROP DROP DROP R>                    \ r1/r2/r3 を捨てて r0 のみ残す

    0 = IF
        $43 FILEMGR-PUTC                \ 'C' (CLOSE 成功)
    ELSE
        $63 FILEMGR-PUTC                \ 'c' (失敗)
    THEN

    \ v0.10.7 (Step 5-6a): FILE-WRITE-TEST
    \   設計書 v1.8.1 §8.4.6.2。新規ファイル "wtest.txt" を size=6 "WRITE!" で WRITE。
    \   r0=0(E-OK) なら 'W'、それ以外 'w'。期待出力 …QLORCW。
    \   name "wtest.txt\0"(10B) を TEST-SRC-BUF+$C0 ($ECC0)、
    \   src  "WRITE!"(6B)       を TEST-SRC-BUF+$E0 ($ECE0) へ用意（他テストと非衝突）。
    $77 TEST-SRC-BUF $C0 +     C!       \ 'w'
    $74 TEST-SRC-BUF $C0 + 1 + C!       \ 't'
    $65 TEST-SRC-BUF $C0 + 2 + C!       \ 'e'
    $73 TEST-SRC-BUF $C0 + 3 + C!       \ 's'
    $74 TEST-SRC-BUF $C0 + 4 + C!       \ 't'
    $2E TEST-SRC-BUF $C0 + 5 + C!       \ '.'
    $74 TEST-SRC-BUF $C0 + 6 + C!       \ 't'
    $78 TEST-SRC-BUF $C0 + 7 + C!       \ 'x'
    $74 TEST-SRC-BUF $C0 + 8 + C!       \ 't'
    $00 TEST-SRC-BUF $C0 + 9 + C!       \ NUL
    $57 TEST-SRC-BUF $E0 +     C!       \ 'W'
    $52 TEST-SRC-BUF $E0 + 1 + C!       \ 'R'
    $49 TEST-SRC-BUF $E0 + 2 + C!       \ 'I'
    $54 TEST-SRC-BUF $E0 + 3 + C!       \ 'T'
    $45 TEST-SRC-BUF $E0 + 4 + C!       \ 'E'
    $21 TEST-SRC-BUF $E0 + 5 + C!       \ '!'

    \ FILE_WRITE: msg3=arg2=size, msg2=arg1=src, msg1=arg0=name, msg0=op
    6                                       \ msg3 = arg2 = size = 6
    TEST-SRC-BUF $E0 +                      \ msg2 = arg1 = src
    TEST-SRC-BUF $C0 +                      \ msg1 = arg0 = name
    FILE-WRITE-OP                           \ msg0 = $0204
    FILEMGR-TID-ADDR @                      \ tid
    IPC4-CALL                               \ ( -- r0 r1 r2 r3 )
    >R DROP DROP DROP R>                    \ r0 のみ残す

    0 = IF
        $57 FILEMGR-PUTC                \ 'W' (WRITE 成功)
    ELSE
        $77 FILEMGR-PUTC                \ 'w' (失敗)
    THEN

    \ v0.10.7 (Step 5-6a): 読み返し相互検証（設計書 §8.4.6.3・任意）
    \   WRITE した "wtest.txt"(中身 "WRITE!" 6B) を OPEN→READ で読み返し、
    \   書いた内容と一致するか確認。READ は Step 5-5 実証済みのため、書いたものが
    \   読めれば DE 登録・データ書込・SB 更新の一貫した正しさの強い証拠。
    \   期待: actual=6 かつ FT-DST-BUF[0]=='W'($57) → 'V'(verify)、else 'v'。
    \   name "wtest.txt" は TEST-SRC-BUF+$C0 に既に用意済み（WRITE-TEST で設定）。

    \ wtest.txt を OPEN（最小空きindex方式。hello.txt は CLOSE 済みなので fid=0 期待）
    0 0 TEST-SRC-BUF $C0 + FILE-OPEN-OP FILEMGR-TID-ADDR @ IPC4-CALL
    >R DROP DROP DROP R>                    \ r0 = fid or error
    DUP FT-FID !                            \ fid を保存（READ・後始末用）
    0< IF                                   \ OPEN 失敗（fid<0=エラー）
        $76 FILEMGR-PUTC                    \ 'v' (OPEN 失敗で検証不可)
    ELSE
        \ READ: size=16, dst=FT-DST-BUF, fid=FT-FID
        16 FT-DST-BUF FT-FID @ FILE-READ-OP FILEMGR-TID-ADDR @ IPC4-CALL
        >R DROP DROP DROP R>                \ r0 = actual
        6 = IF                              \ actual==6 ?
            FT-DST-BUF C@ $57 = IF          \ 先頭 'W' ?
                $56 FILEMGR-PUTC            \ 'V' (読み返し一致＝WRITE 完全成功)
            ELSE
                $76 FILEMGR-PUTC            \ 'v' (actual=6 だが内容不一致)
            THEN
        ELSE
            $76 FILEMGR-PUTC                \ 'v' (actual≠6)
        THEN
    THEN

    \ ──────────────────────────────────────────────────────────
    \ v0.10.8 (Step 5-6b): FILE-WRITE-MULTI-TEST（設計書 §8.4.6.6・恒久テスト）
    \   size=1024（2セクタ・端数なし）をパターン byte[i]=(i&$FF) で WRITE→汚染→
    \   OPEN→READ→サンプル点検証。一致なら 'X'（失敗 'x'）。期待出力 …QLORCWVX。
    \   バッファ案C: FT-RW-BUF=$EC00（1024B・src/dst時系列共用）、name=FT-NAME2-BUF=$5060。
    \   ★既存テスト（hello/wtest）は完了済みのため $EC00-$EFFF を時系列再利用可。
    \ ──────────────────────────────────────────────────────────
    \ P1: FT-RW-BUF[0..1023] に byte[i]=(i AND $FF) を FILL
    0 >R                                    \ R: i=0
    BEGIN  R@ 1024 <  WHILE
        R@ $FF AND                          \ ( i&$FF )  書き込む値
        FT-RW-BUF R@ +                      \ ( val addr )
        C!                                  \ buf[i] = i&$FF
        R> 1 + >R                           \ i++
    REPEAT
    R> DROP

    \ "w1k.txt\0"(8B) を FT-NAME2-BUF ($5060) へ
    $77 FT-NAME2-BUF     C!                 \ 'w'
    $31 FT-NAME2-BUF 1 + C!                 \ '1'
    $6B FT-NAME2-BUF 2 + C!                 \ 'k'
    $2E FT-NAME2-BUF 3 + C!                 \ '.'
    $74 FT-NAME2-BUF 4 + C!                 \ 't'
    $78 FT-NAME2-BUF 5 + C!                 \ 'x'
    $74 FT-NAME2-BUF 6 + C!                 \ 't'
    $00 FT-NAME2-BUF 7 + C!                 \ NUL

    \ P2: name=w1k.txt・src=FT-RW-BUF・size=1024 で FILE_WRITE
    1024                                    \ msg3 = arg2 = size = 1024
    FT-RW-BUF                               \ msg2 = arg1 = src
    FT-NAME2-BUF                            \ msg1 = arg0 = name
    FILE-WRITE-OP                           \ msg0 = $0204
    FILEMGR-TID-ADDR @                      \ tid
    IPC4-CALL                               \ ( -- r0 r1 r2 r3 )
    >R DROP DROP DROP R>                    \ r0 のみ残す
    0<> IF                                  \ WRITE 失敗
        $78 FILEMGR-PUTC                    \ 'x'（WRITE 失敗）
    ELSE
        \ P3: FT-RW-BUF[0..1023] を $FF で上書き（読み戻し前の汚染）
        FT-RW-BUF $FF 1024 MEMSET-B

        \ P4: w1k.txt を OPEN → fid を size=1024 で FT-RW-BUF へ READ
        0 0 FT-NAME2-BUF FILE-OPEN-OP FILEMGR-TID-ADDR @ IPC4-CALL
        >R DROP DROP DROP R>                \ r0 = fid or error
        DUP FT-FID !                        \ fid を保存
        0< IF                               \ OPEN 失敗
            DROP $78 FILEMGR-PUTC           \ 'x'（OPEN 失敗）
        ELSE
            DROP
            \ READ: size=1024, dst=FT-RW-BUF, fid=FT-FID
            1024 FT-RW-BUF FT-FID @ FILE-READ-OP FILEMGR-TID-ADDR @ IPC4-CALL
            >R DROP DROP DROP R>            \ r0 = actual
            \ P5: r0==1024 かつ サンプル点 buf[0/511/512/513/1023] 一致判定
            1024 = IF
                FT-RW-BUF        C@ $00 =   \ buf[0]   == $00
                FT-RW-BUF 511 +  C@ $FF =   \ buf[511] == $FF
                AND
                FT-RW-BUF 512 +  C@ $00 =   \ buf[512] == $00（★セクタ境界・KY26本丸）
                AND
                FT-RW-BUF 513 +  C@ $01 =   \ buf[513] == $01
                AND
                FT-RW-BUF 1023 + C@ $FF =   \ buf[1023]== $FF（末尾）
                AND
                IF
                    $58 FILEMGR-PUTC        \ 'X'（5-6b 往復検証 全一致＝完全成功）
                ELSE
                    $78 FILEMGR-PUTC        \ 'x'（サンプル点不一致）
                THEN
            ELSE
                $78 FILEMGR-PUTC            \ 'x'（actual≠1024）
            THEN
            \ P6: CLOSE
            0 0 FT-FID @ FILE-CLOSE-OP FILEMGR-TID-ADDR @ IPC4-CALL
            >R DROP DROP DROP R> DROP       \ r0 は捨てる
        THEN
    THEN

    \ ====== v0.10.11 (Step 5-DELETE): FILE-DELETE-TEST (§6.5.6-5) ======
    \   テスト時点の open 状態: hello.txt=close / wtest.txt=open(fid0,'V'検証で開いたまま) / w1k.txt=close(P6)
    \   FD1: 未open "w1k.txt"(FT-NAME2-BUF) を DELETE → r0==E-OK(0)
    \   FD2: 同 "w1k.txt" を再 DELETE → E-NOENT（削除確認）
    \   FD3: open中 "wtest.txt"(TEST-SRC-BUF+$C0,fid0) を DELETE → E-BUSY（open中拒否・§4.6）
    \   3項全合格で 'Y'($59)、いずれか失敗で 'y'($79)。EQ=$FFFF カノニカルゆえ AND 合成可。
    \   IPC4-CALL: msg3=arg2=0, msg2=arg1=0, msg1=arg0=name_addr, msg0=op
    \ FD1: 未open w1k.txt DELETE → E-OK
    0  0  FT-NAME2-BUF  FILE-DELETE-OP  FILEMGR-TID-ADDR @  IPC4-CALL
    >R DROP DROP DROP R>                     \ r0 のみ
    0 =                                     \ flagD1 = (r0==E-OK)
    \ FD2: 再 DELETE w1k.txt → E-NOENT
    0  0  FT-NAME2-BUF  FILE-DELETE-OP  FILEMGR-TID-ADDR @  IPC4-CALL
    >R DROP DROP DROP R>
    E-NOENT =                               \ flagD2
    AND
    \ FD3: open中 wtest.txt DELETE → E-BUSY
    \   ★name を FT-NAME2-BUF へ再セット（TEST-SRC-BUF+$C0=$ECC0 は MULTI-TEST が
    \     FT-RW-BUF $EC00-$EFFF を上書きして破壊済みのため）。wtest.txt は fid0 で open 中。
    $77 FT-NAME2-BUF     C!  $74 FT-NAME2-BUF 1 + C!  $65 FT-NAME2-BUF 2 + C!
    $73 FT-NAME2-BUF 3 + C!  $74 FT-NAME2-BUF 4 + C!  $2E FT-NAME2-BUF 5 + C!
    $74 FT-NAME2-BUF 6 + C!  $78 FT-NAME2-BUF 7 + C!  $74 FT-NAME2-BUF 8 + C!
    $00 FT-NAME2-BUF 9 + C!                  \ "wtest.txt\0"
    0  0  FT-NAME2-BUF  FILE-DELETE-OP  FILEMGR-TID-ADDR @  IPC4-CALL
    >R DROP DROP DROP R>
    E-BUSY =                                \ flagD3
    AND
    IF
        $59 FILEMGR-PUTC                \ 'Y' (DELETE 試験 FD1/FD2/FD3 全合格)
    ELSE
        $79 FILEMGR-PUTC                \ 'y' (いずれか失敗)
    THEN

    BEGIN AGAIN ;

CODE FILEMGR-TEST-TASK-ADDR  ( -- addr )
    SUBI X, #2
    LDW  A, #WORD_FILEMGR_TEST_TASK
    STW  A, [X]
END-CODE

: FILEMGR-TEST-START  ( -- )
    FILEMGR-TEST-TASK-ADDR TASK-CREATE
    DROP ;
