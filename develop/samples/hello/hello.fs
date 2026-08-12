\ hello.fs - YSD8800 ISA2.2 Hello World (Forth)
\ Force v1.0 でコンパイル
\
\ ビルド方法:
\   make hello_fs
\ または手動:
\   ./force/force samples/hello/hello.fs -o build/hello_fs/hello.asm
\   ./hasm22 build/hello_fs/hello.asm
\   python3 scripts/make_harness.py build/hello_fs/hello.asm.sym > build/hello_fs/harness.asm
\   ./hasm22 build/hello_fs/harness.asm
\   python3 scripts/merge_simple.py \
\       build/hello_fs/hello.asm.bin build/hello_fs/harness.asm.bin \
\       build/hello_fs/hello.bin
\   ./emu22 build/hello_fs/hello.bin -n 200000

$FC80 CONSTANT UART-TX
$FC84 CONSTANT UART-STAT

: emit-char  ( c -- )
    BEGIN UART-STAT @ 0<> UNTIL
    UART-TX ! ;

: emit-nl  ( -- )  10 emit-char ;

: main  ( -- )
    72 emit-char    \ H
    101 emit-char   \ e
    108 emit-char   \ l
    108 emit-char   \ l
    111 emit-char   \ o
    44 emit-char    \ ,
    32 emit-char    \  
    89 emit-char    \ Y
    83 emit-char    \ S
    68 emit-char    \ D
    56 emit-char    \ 8
    56 emit-char    \ 8
    48 emit-char    \ 0
    48 emit-char    \ 0
    33 emit-char    \ !
    emit-nl
    HALT ;
