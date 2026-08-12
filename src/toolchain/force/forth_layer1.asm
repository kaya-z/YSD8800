; ============================================================
; YSD8800 Forth Kernel - Layer 1
; forth_layer1.asm  v0.1
;
; アセンブラ(hasm22)で実装するサポートワード群
; forth_kernel.asm(Layer 0)の続きとして使用する
;
; データスタックポインタ: X レジスタ (TOS=[X])
; コール/リターンスタック: SP レジスタ (JSR/RET専用)
; スタック規約: TOS=後からpushした値, NOS=[X+2]
;
; Layer 1 ワークスペース ($E020-$E02F):
;   $E020-$E021: MUL/DIV/WITHIN  a_work
;   $E022-$E023: MUL/DIV/WITHIN  b_work / hi
;   $E024-$E025: MUL/DIV         result / quot
;   $E028-$E029: C@/C!/TYPE      X退避用
;
; 実装ワード一覧:
;   A. 算術拡張: FORTH_MUL FORTH_DIV_MOD FORTH_DIV FORTH_MOD
;   B. メモリ管理: FORTH_HERE FORTH_ALLOT FORTH_COMMA FORTH_C_COMMA
;   C. 文字列I/O: FORTH_COUNT FORTH_TYPE
;   D. 比較拡張: FORTH_MAX FORTH_MIN FORTH_WITHIN
;
; 定数 (forth_kernel.asmで定義済み — 単体アセンブル時は以下を有効化)
; UART_STAT   EQU $FC84
;   UART_STAT EQU $FC84
; ============================================================

; 辞書ポインタ格納アドレス
DICT_PTR    EQU $E100       ; HERE ポインタ (ワークスペース内)
; 注: forth_kernel.asmでの辞書初期化後、このアドレスに$0800を書くこと

; Layer 1 ワークスペース定数
L1_WK_A     EQU $E020
L1_WK_B     EQU $E022
L1_WK_C     EQU $E024
L1_WK_TMP   EQU $E028

; ============================================================
; A. 算術拡張
; ============================================================

; MUL  ( a b -- a*b )  16bit符号なし乗算
; シフト加算法 (Russian Peasant Multiplication)
; 計算量: O(16) = 16ループ固定
FORTH_MUL:
    LDW  B, [X]             ; B = b (TOS)
    ADDI X, #2              ; pop b
    LDW  A, [X]             ; A = a (新TOS = 結果書き込み先)
    STW  A, [L1_WK_A]       ; a_work = a
    STW  B, [L1_WK_B]       ; b_work = b
    LDW  A, #0
    STW  A, [L1_WK_C]       ; result = 0
_mul_loop:
    LDW  B, [L1_WK_B]       ; B = b_work
    CMPI B, #0
    BEQ  _mul_done
    ANDI B, #$0001           ; bit0を取り出す (FLAGS更新)
    BEQ  _mul_no_add
    LDW  A, [L1_WK_C]
    LDW  B, [L1_WK_A]
    ADD  A, B               ; result += a_work
    STW  A, [L1_WK_C]
_mul_no_add:
    LDW  A, [L1_WK_A]       ; a_work <<= 1 (SHL ISA2.2)
    LDW  B, #1
    SHL  A, B
    STW  A, [L1_WK_A]
    LDW  A, [L1_WK_B]       ; b_work >>= 1 (SHR ISA2.2)
    LDW  B, #1
    SHR  A, B
    STW  A, [L1_WK_B]
    JMP  _mul_loop
_mul_done:
    LDW  A, [L1_WK_C]
    STW  A, [X]             ; TOS = result
    RET

; /MOD  ( a b -- rem quot )  16bit符号なし除算+余り
; アルゴリズム: 引き算の繰り返し
; 戻り値: TOS=rem, NOS=quot
FORTH_DIV_MOD:
    LDW  B, [X]             ; B = b (除数, TOS)
    ADDI X, #2
    LDW  A, [X]             ; A = a (被除数, 新TOS)
    CMPI B, #0              ; ゼロ除算チェック
    BNE  _dm_start
    LDW  A, #$BAAD
    HALT                    ; ゼロ除算: 致命的エラー
_dm_start:
    STW  A, [L1_WK_A]       ; a_work = a (余り候補)
    STW  B, [L1_WK_B]       ; b_work = b (除数)
    LDW  A, #0
    STW  A, [L1_WK_C]       ; quot = 0
_dm_loop:
    LDW  A, [L1_WK_A]
    LDW  B, [L1_WK_B]
    CMP  A, B               ; a_work - b_work
    BLT  _dm_done           ; a_work < b_work → 完了
    SUB  A, B               ; a_work -= b_work
    STW  A, [L1_WK_A]
    LDW  A, [L1_WK_C]
    ADDI A, #1
    STW  A, [L1_WK_C]       ; quot++
    JMP  _dm_loop
_dm_done:
    ; スタックに ( rem quot ) を積む: quot がNOS, rem がTOS
    LDW  A, [L1_WK_C]
    STW  A, [X]             ; 現TOS位置 = quot
    SUBI X, #2
    LDW  A, [L1_WK_A]
    STW  A, [X]             ; 新TOS = rem
    RET

; /  ( a b -- a/b )  商のみ
FORTH_DIV:
    JSR  FORTH_DIV_MOD      ; ( rem quot )
    LDW  A, [X]             ; A = rem (TOS)
    ADDI X, #2              ; rem をpop
    RET                     ; quot が新TOS

; MOD  ( a b -- a%b )  余りのみ
FORTH_MOD:
    JSR  FORTH_DIV_MOD      ; ( rem quot )
    ; quot(NOS)を捨て、rem(TOS)だけ残す
    LDW  A, [X]             ; A = rem (TOS)
    ADDI X, #4              ; rem と quot を両方pop
    SUBI X, #2              ; 1スロット確保
    STW  A, [X]             ; rem を再push
    RET

; ============================================================
; B. メモリ管理 (辞書ポインタ操作)
; ============================================================

; HERE  ( -- addr )  辞書ポインタの現在値を返す
FORTH_HERE:
    LDW  A, [DICT_PTR]
    SUBI X, #2
    STW  A, [X]
    RET

; ALLOT  ( n -- )  辞書ポインタをnバイト進める
FORTH_ALLOT:
    LDW  A, [X]
    ADDI X, #2
    LDW  B, [DICT_PTR]
    ADD  B, A
    STW  B, [DICT_PTR]
    RET

; ,  ( n -- )  16bit値nを辞書に書き込みHEREを2進める
FORTH_COMMA:
    LDW  A, [X]
    ADDI X, #2
    LDW  B, [DICT_PTR]
    STW  A, [B]             ; mem[HERE] = n
    ADDI B, #2
    STW  B, [DICT_PTR]      ; HERE += 2
    RET

; C,  ( c -- )  8bit値cを辞書に書き込みHEREを1進める
FORTH_C_COMMA:
    LDW  A, [X]
    ADDI X, #2
    LDW  B, [DICT_PTR]
    STW  X, [L1_WK_TMP]    ; X(DSP)退避
    MOV  X, B               ; X = HERE
    STB  A, [X]             ; mem8[HERE] = c & 0xFF (ISA2.1 EXT)
    LDW  X, [L1_WK_TMP]    ; X(DSP)復元
    LDW  B, [DICT_PTR]
    ADDI B, #1
    STW  B, [DICT_PTR]      ; HERE += 1
    RET

; ============================================================
; C. 文字列 I/O
; ============================================================

; COUNT  ( caddr -- addr+1 n )
; counted string (先頭1バイトが長さ) から addr+1 と長さを返す
FORTH_COUNT:
    LDW  A, [X]             ; A = caddr (TOS)
    STW  X, [L1_WK_TMP]    ; X退避
    MOV  X, A               ; X = caddr
    LDB  B, [X]             ; B = 長さ (mem8[caddr], ISA2.1 EXT)
    LDW  X, [L1_WK_TMP]    ; X復元
    ADDI A, #1              ; addr+1
    STW  A, [X]             ; TOS = addr+1
    SUBI X, #2
    STW  B, [X]             ; 新TOS = n (長さ)
    RET

; TYPE  ( addr n -- )  addr から n 文字を EMIT で出力
FORTH_TYPE:
    LDW  A, [X]             ; A = n (TOS)
    ADDI X, #2
    LDW  B, [X]             ; B = addr
    ADDI X, #2
    CMPI A, #0              ; n == 0 なら何もしない
    BEQ  _type_done
    STW  A, [L1_WK_A]       ; count 保存
    STW  B, [L1_WK_B]       ; addr 保存
_type_loop:
    LDW  A, [L1_WK_A]
    CMPI A, #0
    BEQ  _type_done
    ; 1文字読み出し (X経由でLDB)
    STW  X, [L1_WK_TMP]    ; X退避
    LDW  X, [L1_WK_B]      ; X = addr
    LDB  A, [X]             ; A = mem8[addr]
    LDW  X, [L1_WK_TMP]    ; X復元
    ; EMIT (UARTに1文字送信)
_type_emit_wait:
    LDW  B, [UART_STAT]     ; UART_STAT EQU $FC84
    CMPI B, #0
    BEQ  _type_emit_wait
    STW  X, [L1_WK_TMP]
    LDW  X, #$FC80          ; UART_TX
    STB  A, [X]
    LDW  X, [L1_WK_TMP]
    ; addr++, count--
    LDW  A, [L1_WK_B]
    ADDI A, #1
    STW  A, [L1_WK_B]
    LDW  A, [L1_WK_A]
    SUBI A, #1
    STW  A, [L1_WK_A]
    JMP  _type_loop
_type_done:
    RET

; ============================================================
; D. 比較拡張
; ============================================================
; スタック規約: ( a b -- result )
;   push順: a を先に、b を後にpush
;   TOS=[X]=b, NOS=[X+2]=a
; CMP A,B = b-a: N=1 if b<a

; MAX  ( a b -- max )
;   b < a (N=1) → a がmax: TOS(b)を捨てる
;   b >= a (N=0) → b がmax: NOS(a)をbで上書き、TOS(b)をpop
FORTH_MAX:
    LDW  A, [X]             ; A = b (TOS)
    LDW  B, [X + #2]        ; B = a (NOS)
    CMP  A, B               ; b - a
    BLT  _max_a_wins        ; N=1: b < a → a がmax
    STW  A, [X + #2]        ; NOS = b (bがmax)
    ADDI X, #2              ; TOS(旧b)をpop → bが新TOS
    RET
_max_a_wins:
    ADDI X, #2              ; TOS(b)を捨てる → aが新TOS
    RET

; MIN  ( a b -- min )
;   b >= a (N=0) → a がmin: TOS(b)を捨てる
;   b < a (N=1) → b がmin: NOS(a)をbで上書き、TOS(b)をpop
FORTH_MIN:
    LDW  A, [X]             ; A = b (TOS)
    LDW  B, [X + #2]        ; B = a (NOS)
    CMP  A, B               ; b - a
    BGE  _min_a_wins        ; N=0: b >= a → a がmin
    STW  A, [X + #2]        ; NOS = b (bがmin)
    ADDI X, #2
    RET
_min_a_wins:
    ADDI X, #2
    RET

; WITHIN  ( n lo hi -- flag )  lo <= n < hi なら $FFFF
; マイクロカーネルのアドレス範囲チェック用
FORTH_WITHIN:
    LDW  A, [X]             ; A = hi (TOS)
    ADDI X, #2
    STW  A, [L1_WK_A]       ; save hi
    LDW  A, [X]             ; A = lo
    ADDI X, #2
    STW  A, [L1_WK_B]       ; save lo
    LDW  A, [X]             ; A = n (TOS = 結果書き込み先)
    LDW  B, [L1_WK_B]       ; B = lo
    CMP  A, B               ; n - lo: N=1 if n<lo
    BLT  _within_false      ; n < lo → 偽
    LDW  B, [L1_WK_A]       ; B = hi
    CMP  A, B               ; n - hi: Z=1 if n==hi, N=0 if n>=hi
    BGE  _within_false      ; n >= hi → 偽
    LDW  A, #$FFFF
    STW  A, [X]
    RET
_within_false:
    LDW  A, #0
    STW  A, [X]
    RET

; ============================================================
; End of forth_layer1.asm  v0.1
; ============================================================
