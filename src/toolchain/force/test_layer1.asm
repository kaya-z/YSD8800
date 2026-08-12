; Layer 1 単独テスト (ベクタテーブル付き)
    .vector reset _start
    .org $0040

; ワークスペース定数
UART_STAT   EQU $FC84
DICT_PTR    EQU $E100       ; テスト用: ワークスペース内に配置

; Layer 1 ワーク変数
WK_A        EQU $E020
WK_B        EQU $E022
WK_C        EQU $E024
WK_TMP      EQU $E028

; ---- MUL ----
FORTH_MUL:
    LDW  B, [X]
    ADDI X, #2
    LDW  A, [X]
    STW  A, [$E020]
    STW  B, [$E022]
    LDW  A, #0
    STW  A, [$E024]
_mul_loop:
    LDW  B, [$E022]
    CMPI B, #0
    BEQ  _mul_done
    ANDI B, #$0001
    BEQ  _mul_no_add
    LDW  A, [$E024]
    LDW  B, [$E020]
    ADD  A, B
    STW  A, [$E024]
_mul_no_add:
    LDW  A, [$E020]
    LDW  B, #1
    SHL  A, B
    STW  A, [$E020]
    LDW  A, [$E022]
    LDW  B, #1
    SHR  A, B
    STW  A, [$E022]
    JMP  _mul_loop
_mul_done:
    LDW  A, [$E024]
    STW  A, [X]
    RET

; ---- DIV_MOD ----
FORTH_DIV_MOD:
    LDW  B, [X]
    ADDI X, #2
    LDW  A, [X]
    CMPI B, #0
    BNE  _dm_start
    LDW  A, #$BAAD
    HALT
_dm_start:
    STW  A, [$E020]
    STW  B, [$E022]
    LDW  A, #0
    STW  A, [$E024]
_dm_loop:
    LDW  A, [$E020]
    LDW  B, [$E022]
    CMP  A, B
    BLT  _dm_done
    SUB  A, B
    STW  A, [$E020]
    LDW  A, [$E024]
    ADDI A, #1
    STW  A, [$E024]
    JMP  _dm_loop
_dm_done:
    LDW  A, [$E024]
    STW  A, [X]
    SUBI X, #2
    LDW  A, [$E020]
    STW  A, [X]
    RET

FORTH_DIV:
    JSR  FORTH_DIV_MOD
    LDW  A, [X]
    ADDI X, #2
    RET

FORTH_MOD:
    JSR  FORTH_DIV_MOD
    LDW  A, [X]             ; rem (TOS)
    ADDI X, #4              ; rem と quot を両方pop
    SUBI X, #2
    STW  A, [X]             ; rem を再push
    RET

; ---- HERE ALLOT COMMA ----
FORTH_HERE:
    LDW  A, [DICT_PTR]
    SUBI X, #2
    STW  A, [X]
    RET

FORTH_ALLOT:
    LDW  A, [X]
    ADDI X, #2
    LDW  B, [DICT_PTR]
    ADD  B, A
    STW  B, [DICT_PTR]
    RET

FORTH_COMMA:
    LDW  A, [X]
    ADDI X, #2
    LDW  B, [DICT_PTR]
    STW  A, [B]
    ADDI B, #2
    STW  B, [DICT_PTR]
    RET

; ---- MAX MIN ----
; スタック: TOS=b(後push), NOS=a(先push)
; CMP A,B = b-a
;   N=1: b<a → a がmax, b がmin
;   N=0かつZ=0: b>a → b がmax, a がmin
;   Z=1: b==a → どちらも同じ
;
; MAX ( a b -- max )
;   b < a (N=1) → a がmax: TOS(b)を捨てるだけ
;   b >= a (N=0) → b がmax: NOS(a)をbで上書きしTOSをpop
FORTH_MAX:
    LDW  A, [X]             ; A = b (TOS)
    LDW  B, [X + #2]        ; B = a (NOS)
    CMP  A, B               ; b - a
    BLT  _max_a_wins        ; N=1: b < a → a がmax
    ; b >= a → b がmax: NOS(a)をbで上書き、b(TOS)をpop
    STW  A, [X + #2]        ; NOS位置 = b
    ADDI X, #2              ; TOSをpop → b が新TOS
    RET
_max_a_wins:
    ; b < a → a がmax: TOS(b)を捨てるだけ
    ADDI X, #2              ; b を捨てる → a が新TOS
    RET

; MIN ( a b -- min )
;   b < a (N=1) → b がmin: NOS(a)をbで上書きしTOSをpop
;   b >= a (N=0) → a がmin: TOS(b)を捨てるだけ
FORTH_MIN:
    LDW  A, [X]             ; A = b (TOS)
    LDW  B, [X + #2]        ; B = a (NOS)
    CMP  A, B               ; b - a
    BGE  _min_a_wins        ; N=0: b >= a → a がmin
    ; b < a → b がmin: NOS(a)をbで上書き、b(TOS)をpop
    STW  A, [X + #2]        ; NOS位置 = b
    ADDI X, #2
    RET
_min_a_wins:
    ; b >= a → a がmin: TOS(b)を捨てる
    ADDI X, #2
    RET

; ---- WITHIN ----
; ( n lo hi -- flag )  lo <= n < hi なら $FFFF
FORTH_WITHIN:
    LDW  A, [X]             ; A = hi (TOS)
    ADDI X, #2              ; pop hi
    STW  A, [$E020]         ; save hi
    LDW  A, [X]             ; A = lo
    ADDI X, #2              ; pop lo
    STW  A, [$E022]         ; save lo
    LDW  A, [X]             ; A = n (TOS, ここに結果を書く)
    ; n >= lo ?
    LDW  B, [$E022]         ; B = lo
    CMP  A, B               ; A-B, N=1 if n<lo
    BLT  _within_false      ; n < lo → 偽
    ; n < hi ?
    LDW  B, [$E020]         ; B = hi
    CMP  A, B               ; A-B, N=0/Z=1 if n>=hi
    BGE  _within_false      ; n >= hi → 偽
    LDW  A, #$FFFF
    STW  A, [X]             ; TOS = 真
    RET
_within_false:
    LDW  A, #0
    STW  A, [X]             ; TOS = 偽
    RET

; ---- エントリポイント ----
    .org $0200
_start:
    LDW  SP, #$FFFE
    LDW  X, #$F800
    DI

    ; HERE_PTR 初期化 ($0800)
    LDW  A, #$0800
    STW  A, [DICT_PTR]

    ; T1: MUL 3*4=12
    LDW  A, #3
    SUBI X, #2
    STW  A, [X]
    LDW  A, #4
    SUBI X, #2
    STW  A, [X]
    JSR  FORTH_MUL
    LDW  A, [X]
    CMPI A, #12
    BNE  _fail
    ADDI X, #2

    ; T2: MUL 100*200=20000=$4E20
    LDW  A, #100
    SUBI X, #2
    STW  A, [X]
    LDW  A, #200
    SUBI X, #2
    STW  A, [X]
    JSR  FORTH_MUL
    LDW  A, [X]
    CMPI A, #$4E20
    BNE  _fail
    ADDI X, #2

    ; T3: MUL 255*255=65025=$FE01
    LDW  A, #255
    SUBI X, #2
    STW  A, [X]
    LDW  A, #255
    SUBI X, #2
    STW  A, [X]
    JSR  FORTH_MUL
    LDW  A, [X]
    CMPI A, #$FE01
    BNE  _fail
    ADDI X, #2

    ; T4: DIV 10/3=3
    LDW  A, #10
    SUBI X, #2
    STW  A, [X]
    LDW  A, #3
    SUBI X, #2
    STW  A, [X]
    JSR  FORTH_DIV
    LDW  A, [X]
    CMPI A, #3
    BNE  _fail
    ADDI X, #2

    ; T5: MOD 10%3=1
    LDW  A, #10
    SUBI X, #2
    STW  A, [X]
    LDW  A, #3
    SUBI X, #2
    STW  A, [X]
    JSR  FORTH_MOD
    LDW  A, [X]
    CMPI A, #1
    BNE  _fail
    ADDI X, #2

    ; T6: DIV 100/7=14
    LDW  A, #100
    SUBI X, #2
    STW  A, [X]
    LDW  A, #7
    SUBI X, #2
    STW  A, [X]
    JSR  FORTH_DIV
    LDW  A, [X]
    CMPI A, #14
    BNE  _fail
    ADDI X, #2

    ; T7: HERE=$0800, ALLOT 4 → HERE=$0804
    JSR  FORTH_HERE
    LDW  A, [X]
    CMPI A, #$0800
    BNE  _fail
    ADDI X, #2
    LDW  A, #4
    SUBI X, #2
    STW  A, [X]
    JSR  FORTH_ALLOT
    JSR  FORTH_HERE
    LDW  A, [X]
    CMPI A, #$0804
    BNE  _fail
    ADDI X, #2

    ; T8: COMMA $ABCD → mem[$0804]=$ABCD, HERE=$0806
    LDW  A, #$ABCD
    SUBI X, #2
    STW  A, [X]
    JSR  FORTH_COMMA
    JSR  FORTH_HERE
    LDW  A, [X]
    CMPI A, #$0806
    BNE  _fail
    ADDI X, #2
    LDW  A, [$0804]
    CMPI A, #$ABCD
    BNE  _fail

    ; T9: MAX(7,3)=7
    LDW  A, #7
    SUBI X, #2
    STW  A, [X]
    LDW  A, #3
    SUBI X, #2
    STW  A, [X]
    JSR  FORTH_MAX
    LDW  A, [X]
    CMPI A, #7
    BNE  _fail
    ADDI X, #2

    ; T10: MIN(7,3)=3
    LDW  A, #7
    SUBI X, #2
    STW  A, [X]
    LDW  A, #3
    SUBI X, #2
    STW  A, [X]
    JSR  FORTH_MIN
    LDW  A, [X]
    CMPI A, #3
    BNE  _fail
    ADDI X, #2

    ; T11: WITHIN(5,1,10)=$FFFF
    LDW  A, #5
    SUBI X, #2
    STW  A, [X]
    LDW  A, #1
    SUBI X, #2
    STW  A, [X]
    LDW  A, #10
    SUBI X, #2
    STW  A, [X]
    JSR  FORTH_WITHIN
    LDW  A, [X]
    CMPI A, #$FFFF
    BNE  _fail
    ADDI X, #2

    ; T12: WITHIN(0,1,10)=$0000
    LDW  A, #0
    SUBI X, #2
    STW  A, [X]
    LDW  A, #1
    SUBI X, #2
    STW  A, [X]
    LDW  A, #10
    SUBI X, #2
    STW  A, [X]
    JSR  FORTH_WITHIN
    LDW  A, [X]
    CMPI A, #0
    BNE  _fail
    ADDI X, #2

    ; T13: WITHIN(10,1,10)=$0000 (hi は範囲外)
    LDW  A, #10
    SUBI X, #2
    STW  A, [X]
    LDW  A, #1
    SUBI X, #2
    STW  A, [X]
    LDW  A, #10
    SUBI X, #2
    STW  A, [X]
    JSR  FORTH_WITHIN
    LDW  A, [X]
    CMPI A, #0
    BNE  _fail
    ADDI X, #2

    LDW  A, #$DEAD
    HALT
_fail:
    LDW  A, #$BAAD
    HALT
