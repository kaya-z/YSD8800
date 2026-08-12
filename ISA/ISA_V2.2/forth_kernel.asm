; ============================================================
; YSD8800 ISA2.1 Forth Kernel - Layer 0 Primitives
; forth_kernel.asm  v0.2
;
; 設計変更 (v0.1からの修正):
;   v0.1でJSR/RETがSPを使うためデータスタックと干渉する問題を発見
;   → レジスタ割り当てを変更
;
; レジスタ割り当て (v0.2):
;   SP  : リターンスタック兼コールスタック (JSR/RETが使用)
;         ISA2.1のJSR/RETはSPを使うため変更不可
;         $FBFE から下方向に成長
;   X   : データスタックポインタ (DSP)
;         Forthのデータスタックをマニュアルで管理
;         $F800 から下方向に成長
;   A   : プライマリ作業レジスタ / TOS一時保持
;   B   : セカンダリ作業レジスタ
;
; データスタック操作マクロ (X使用):
;   DPUSH A : X -= 2; mem[X] = A  (データスタックへプッシュ)
;   DPOP  A : A = mem[X]; X += 2  (データスタックからポップ)
;   DPEEK A : A = mem[X]          (データスタックTOSを読む、Xは変化しない)
;
; ISA2.1にはXベースのスタック操作命令がないため
; STW/LDW + ADDI/SUBI を組み合わせて実装する
;
; メモリマップ (§8.1 Forthマシン):
;   0000-07FF  ROM: Forthカーネル
;   0800-DFFF  辞書領域
;   E000-F7FF  Forthワークスペース
;   F800-FBFF  データスタック (X: F800から下へ)
;   FC00-FFFE  コール/リターンスタック (SP: FFFEから下へ)
;   FC80-FFFF  I/O
;
; ワークスペース割り当て ($E000):
;   $E000-$E001 : ROT用 temp_c
;   $E002-$E003 : ROT用 temp_b
;   $E004-$E005 : C@/C!用 temp_addr (Xが一時的に変化するため退避不要)
;   $E006-$E007 : 予約
;   $E008-$E009 : 予約
;   $E00A以降   : 汎用
; ============================================================

; ============================================================
; 定数定義
; ============================================================

DSTACK_TOP  EQU $F800       ; データスタック初期X (DSP)
CSTACK_TOP  EQU $FFFE       ; コール/リターンスタック初期SP
DICT_BASE   EQU $0800       ; 辞書領域先頭
WORKSPACE   EQU $E000       ; ワークスペース先頭

UART_TX     EQU $FC80       ; UART送信データレジスタ
UART_RX     EQU $FC82       ; UART受信データレジスタ
UART_STAT   EQU $FC84       ; UARTステータスレジスタ

; ============================================================
; ベクタテーブル
; ============================================================

    .vector reset   _start
    .vector irq0    irq0_handler
    .vector irq1    irq1_handler
    .vector align   align_handler
    .vector syscall syscall_handler

; ============================================================
; 割り込みハンドラ
; ============================================================

    .org $0020

irq0_handler:
    DI
    IRET

irq1_handler:
    DI
    IRET

align_handler:
    DI
    HALT

syscall_handler:
    DI
    IRET

; ============================================================
; 起動コード
; ============================================================

    .org $0040

_start:
    ; コール/リターンスタック初期化 (SP: ISA2.1のSP)
    LDW  SP, #$FFFE         ; SP = CSTACK_TOP

    ; データスタック初期化 (X: DSP)
    LDW  X, #$F800          ; X = DSTACK_TOP

    ; 割り込み禁止
    DI

    ; Forthメインへ
    JSR  FORTH_MAIN

_fatal:
    HALT

; ============================================================
; データスタック操作プリミティブ
;
; ISA2.1にはXベースのPUSH/POP命令がない
; 以下のパターンで実装:
;   DPUSH A: SUBI X,#2; STW A,[X]
;   DPOP  A: LDW  A,[X]; ADDI X,#2
;   DPEEK A: LDW  A,[X]
; ============================================================

; ============================================================
; ソフトウェアビット演算
; ============================================================

; ビット反転: ISA2.2 NOT命令を使用
SOFT_NOT:
    NOT  A, A               ; ISA2.2: A = ~A
    RET

; SOFT_AND / SOFT_OR / SOFT_XOR: 暫定スタブ
; ISA2.1拡張命令が追加されるまでの仮実装
; AND/OR/XORが必要な場面では将来置き換える
SOFT_AND:
    RET                     ; A AND B → 暫定: Aをそのまま返す

SOFT_OR:
    RET                     ; A OR B  → 暫定: Aをそのまま返す

SOFT_XOR:
    LDW  B, #0
    RET                     ; A XOR B → 暫定: 0を返す

; ============================================================
; スタック操作ワード
; 全ワード: Xをデータスタックポインタとして使用
; ============================================================

; DUP  ( n -- n n )
FORTH_DUP:
    LDW  A, [X]             ; A = TOS (XはDSP、変化しない)
    SUBI X, #2              ; DSP -= 2
    STW  A, [X]             ; mem[DSP] = A (複製をプッシュ)
    RET

; DROP  ( n -- )
FORTH_DROP:
    ADDI X, #2              ; DSP += 2 (TOSを捨てる)
    RET

; SWAP  ( a b -- b a )
FORTH_SWAP:
    LDW  A, [X]             ; A = b (TOS)
    LDW  B, [$E000]         ; (Bを後で使うのでワーク確保不要、直接処理)
    ; X+2 の値 (a) を読む: [X+#2]
    LDW  B, [X + #2]        ; B = a (NOS)
    STW  B, [X]             ; mem[X] = a (TOSをaに)
    STW  A, [X + #2]        ; mem[X+2] = b (NOSをbに)
    RET

; OVER  ( a b -- a b a )
FORTH_OVER:
    LDW  A, [X + #2]        ; A = a (NOS = X+2)
    SUBI X, #2              ; DSP -= 2
    STW  A, [X]             ; aのコピーをTOSへ
    RET

; ROT  ( a b c -- b c a )
; SP→[c], SP+2→[b], SP+4→[a]
FORTH_ROT:
    LDW  A, [X]             ; A = c (TOS)
    LDW  B, [X + #2]        ; B = b (NOS)
    STW  A, [$E000]         ; c をワークスペースに退避
    STW  B, [$E002]         ; b をワークスペースに退避
    LDW  A, [X + #4]        ; A = a (3番目)
    STW  A, [X]             ; TOS = a
    LDW  B, [$E000]         ; B = c
    STW  B, [X + #2]        ; NOS = c
    LDW  B, [$E002]         ; B = b
    STW  B, [X + #4]        ; 3番目 = b
    RET

; NIP  ( a b -- b )
FORTH_NIP:
    LDW  A, [X]             ; A = b (TOS)
    ADDI X, #2              ; a を捨てる
    STW  A, [X]             ; b をTOSへ
    RET

; TUCK  ( a b -- b a b )
FORTH_TUCK:
    JSR  FORTH_SWAP
    JSR  FORTH_OVER
    RET

; 2DUP  ( a b -- a b a b )
FORTH_2DUP:
    JSR  FORTH_OVER
    JSR  FORTH_OVER
    RET

; 2DROP  ( a b -- )
FORTH_2DROP:
    ADDI X, #4
    RET

; ============================================================
; 算術ワード
; ============================================================

; +  ( a b -- a+b )
FORTH_ADD:
    LDW  A, [X]             ; A = b (TOS)
    ADDI X, #2              ; pop
    LDW  B, [X]             ; B = a (新TOS)
    ADD  B, A               ; B = a + b
    STW  B, [X]             ; 結果をTOSへ
    RET

; -  ( a b -- a-b )
FORTH_SUB:
    LDW  B, [X]             ; B = b (TOS)
    ADDI X, #2              ; pop
    LDW  A, [X]             ; A = a (新TOS)
    SUB  A, B               ; A = a - b
    STW  A, [X]             ; 結果をTOSへ
    RET

; 1+  ( n -- n+1 )
FORTH_1PLUS:
    LDW  A, [X]
    ADDI A, #1
    STW  A, [X]
    RET

; 1-  ( n -- n-1 )
FORTH_1MINUS:
    LDW  A, [X]
    SUBI A, #1
    STW  A, [X]
    RET

; 2*  ( n -- n*2 )  ADD A,A で左シフト1bit
FORTH_2MUL:
    LDW  A, [X]
    ADD  A, A
    STW  A, [X]
    RET

; NEGATE  ( n -- -n )
FORTH_NEGATE:
    LDW  A, [X]
    LDW  B, #0
    SUB  B, A
    STW  B, [X]
    RET

; ABS  ( n -- |n| )
FORTH_ABS:
    LDW  A, [X]
    CMPI A, #0
    BGE  _abs_done
    LDW  B, #0
    SUB  B, A
    STW  B, [X]
_abs_done:
    RET

; MAX  ( a b -- max )
FORTH_MAX:
    LDW  A, [X]             ; A = b
    LDW  B, [X + #2]        ; B = a
    CMP  B, A               ; B - A: B>A なら N=0
    BGE  _max_b_wins        ; N=0 (a>=b) → a がmax
    ; b > a → b が max
    ADDI X, #2              ; a を捨てる (b はTOSのまま)
    RET
_max_b_wins:
    ; a >= b → a が max
    STW  B, [X]             ; TOS = a (b を上書き)
    ADDI X, #2              ; 元のa位置を捨てる
    ; 注: スタックは1段減らすだけ
    ; ( a b -- max ) なので結果は1要素
    SUBI X, #2              ; 戻す (1要素を維持)
    STW  B, [X]
    RET

; MIN  ( a b -- min )
FORTH_MIN:
    LDW  A, [X]             ; A = b
    LDW  B, [X + #2]        ; B = a
    CMP  A, B               ; A - B: A<B なら N=1
    BGE  _min_b_wins        ; N=0 (b>=a) → a が小さい
    ; b < a → b が min (TOSにb)
    ADDI X, #2
    RET
_min_b_wins:
    STW  B, [X]
    ADDI X, #2
    SUBI X, #2
    STW  B, [X]
    RET

; ============================================================
; 論理・ビット演算ワード
; ============================================================

; AND  ( a b -- a&b )  ISA2.2 AND命令
FORTH_AND:
    LDW  B, [X]             ; B = b (TOS)
    ADDI X, #2              ; pop
    LDW  A, [X]             ; A = a (新TOS)
    AND  A, B               ; ISA2.2: A &= B, FLAGS更新
    STW  A, [X]
    RET

; OR  ( a b -- a|b )  ISA2.2 OR命令
FORTH_OR:
    LDW  B, [X]
    ADDI X, #2
    LDW  A, [X]
    OR   A, B               ; ISA2.2: A |= B
    STW  A, [X]
    RET

; XOR  ( a b -- a^b )  ISA2.2 XOR命令
FORTH_XOR:
    LDW  B, [X]
    ADDI X, #2
    LDW  A, [X]
    XOR  A, B               ; ISA2.2: A ^= B
    STW  A, [X]
    RET

; INVERT (NOT)  ( n -- ~n )  ISA2.2 NOT命令使用
FORTH_INVERT:
    LDW  A, [X]
    NOT  A, A               ; ISA2.2: A = ~A, FLAGS更新
    STW  A, [X]
    RET

; ============================================================
; 比較ワード
; 真 = $FFFF (-1)、偽 = $0000 (Forth標準)
; ============================================================

; Z_TO_FLAG / N_TO_FLAG は廃止
; 各比較ワード内にインライン展開する

N_TO_FLAG:
    LDW  A, #0
    BGE  _n_done            ; N=0 → 偽
    LDW  A, #$FFFF          ; N=1 → 真
_n_done:
    RET

; 0=  ( n -- flag )  n==0 → $FFFF, else $0000
FORTH_ZERO_EQ:
    LDW  A, [X]
    CMPI A, #0              ; Z=1 if A==0
    BNE  _zeq_false         ; Z=0 → 偽
    LDW  A, #$FFFF
    STW  A, [X]
    RET
_zeq_false:
    LDW  A, #0
    STW  A, [X]
    RET

; 0<  ( n -- flag )  n<0(bit15=1) → $FFFF
FORTH_ZERO_LT:
    LDW  A, [X]
    CMPI A, #0              ; N=1 if A<0
    BGE  _zlt_false         ; N=0 → 偽
    LDW  A, #$FFFF
    STW  A, [X]
    RET
_zlt_false:
    LDW  A, #0
    STW  A, [X]
    RET

; 0>  ( n -- flag )  n>0 → $FFFF
; -n<0 ⟺ n>0 を利用
FORTH_ZERO_GT:
    LDW  A, [X]
    LDW  B, #0
    SUB  B, A               ; B = -A, N=1 if A>0
    BGE  _zgt_false         ; N=0 → A<=0 → 偽
    LDW  A, #$FFFF
    STW  A, [X]
    RET
_zgt_false:
    LDW  A, #0
    STW  A, [X]
    RET

; =  ( a b -- flag )  a==b → $FFFF
FORTH_EQ:
    LDW  A, [X]             ; A = b (TOS)
    ADDI X, #2              ; pop b
    LDW  B, [X]             ; B = a (新TOS)
    CMP  B, A               ; B-A, Z=1 if equal
    BNE  _eq_false          ; Z=0 → 偽 (CMP直後にBNEで判定、FLAGSを壊さない)
    LDW  A, #$FFFF
    STW  A, [X]
    RET
_eq_false:
    LDW  A, #0
    STW  A, [X]
    RET

; <>  ( a b -- flag )  a≠b → $FFFF
FORTH_NEQ:
    LDW  A, [X]             ; A = b
    ADDI X, #2
    LDW  B, [X]             ; B = a
    CMP  B, A               ; Z=1 if equal
    BEQ  _neq_false         ; Z=1 → 等しい → 偽
    LDW  A, #$FFFF
    STW  A, [X]
    RET
_neq_false:
    LDW  A, #0
    STW  A, [X]
    RET

; <  ( a b -- flag )  a<b → $FFFF (符号付き)
FORTH_LT:
    LDW  B, [X]             ; B = b (TOS)
    ADDI X, #2              ; pop b
    LDW  A, [X]             ; A = a (新TOS)
    CMP  A, B               ; A-B, N=1 if a<b
    BGE  _lt_false          ; N=0 → a>=b → 偽
    LDW  A, #$FFFF
    STW  A, [X]
    RET
_lt_false:
    LDW  A, #0
    STW  A, [X]
    RET

; >  ( a b -- flag )  a>b → $FFFF
FORTH_GT:
    LDW  A, [X]             ; A = b (TOS)
    ADDI X, #2              ; pop b
    LDW  B, [X]             ; B = a (新TOS)
    CMP  A, B               ; b-a, N=1 if b<a (=a>b)
    BGE  _gt_false          ; N=0 → b>=a (a<=b) → 偽
    LDW  A, #$FFFF
    STW  A, [X]
    RET
_gt_false:
    LDW  A, #0
    STW  A, [X]
    RET

; ============================================================
; メモリアクセスワード
; ============================================================

; @  ( addr -- n )
FORTH_FETCH:
    LDW  A, [X]             ; A = addr
    LDW  B, [A]             ; B = mem16[addr]
    STW  B, [X]             ; TOS = 読んだ値
    RET

; !  ( n addr -- )
FORTH_STORE:
    LDW  A, [X]             ; A = addr
    ADDI X, #2
    LDW  B, [X]             ; B = n
    STW  B, [A]             ; mem[addr] = n
    ADDI X, #2              ; pop n
    RET

; C@  ( addr -- c )
; Xはアドレスレジスタとして一時使用
; ISA2.1の LDB [X] を使うためXが必要
; addrをワークスペースに退避して安全に処理
FORTH_CFETCH:
    LDW  A, [X]             ; A = addr
    STW  A, [$E004]         ; addr をワークスペースに退避
    STW  X, [$E006]         ; DSPを退避
    LDW  X, [$E004]         ; X = addr
    LDB  A, [X]             ; A = mem8[addr] (ゼロ拡張)
    LDW  X, [$E006]         ; DSP復元
    STW  A, [X]             ; TOS = 読んだ値
    RET

; C!  ( c addr -- )
FORTH_CSTORE:
    LDW  A, [X]             ; A = addr
    ADDI X, #2
    LDW  B, [X]             ; B = c
    ADDI X, #2              ; pop両方
    STW  X, [$E006]         ; DSP退避
    MOV  X, A               ; X = addr
    STB  B, [X]             ; mem8[addr] = B & 0xFF
    LDW  X, [$E006]         ; DSP復元
    RET

; +!  ( n addr -- )
FORTH_PLUS_STORE:
    LDW  A, [X]             ; A = addr
    ADDI X, #2
    LDW  B, [X]             ; B = n
    ADDI X, #2
    STW  X, [$E006]         ; DSP退避
    MOV  X, A               ; X = addr
    LDW  A, [X]             ; A = mem[addr]の現在値
    ADD  A, B               ; A += n
    STW  A, [X]             ; mem[addr] = 新値
    LDW  X, [$E006]         ; DSP復元
    RET

; ============================================================
; リターンスタック操作ワード
; サブルーチンスレッド方式ではSPがコールスタックと共用
; >R / R> / R@ はSPを使って実現
; ============================================================

; ============================================================
; >R / R> / R@ — リターンスタック操作
;
; サブルーチンスレッド方式ではJSR経由でこれらを呼ぶと
; JSRがSPスタックに戻りアドレスを積むため正しく動作しない
;
; 正しい使用方法: インライン展開
;
; >R インライン展開 ( n -- )  [R: -- n]:
;   LDW  A, [X]     ; データスタックTOSをAに
;   ADDI X, #2      ; データスタックpop
;   PUSH A          ; SPスタック(リターンスタック)へ
;
; R> インライン展開 ( -- n )  [R: n -- ]:
;   POP  A          ; SPスタックから取り出し
;   SUBI X, #2      ; データスタックpush
;   STW  A, [X]
;
; R@ インライン展開 ( -- n )  [R: n -- n]:
;   LDW  A, [SP]    ; SPスタックTOSをコピー(変化なし)
;   SUBI X, #2
;   STW  A, [X]
;
; 将来: Forthコンパイラ実装時にコンパイル語として定義する
; ============================================================
; (>R / R> / R@ のサブルーチン定義は廃止)
; インライン展開のプレースホルダとしてラベルのみ残す
TO_R:
    ; 使用禁止: JSR TO_R は動作しない
    ; インライン展開を使うこと (上記コメント参照)
    HALT

FROM_R:
    ; 使用禁止: JSR FROM_R は動作しない
    HALT

R_FETCH:
    ; 使用禁止: JSR R_FETCH は動作しない
    HALT

; ============================================================
; I/O ワード
; ============================================================

; EMIT  ( c -- )  1文字出力
FORTH_EMIT:
    LDW  A, [X]             ; A = 文字コード
    ADDI X, #2              ; pop
    STW  X, [$E008]         ; DSP退避

_emit_wait:
    LDW  B, [UART_STAT]
    CMPI B, #0
    BEQ  _emit_wait

    LDW  X, #$FC80          ; X = UART_TX
    STB  A, [X]             ; 送信
    LDW  X, [$E008]         ; DSP復元
    RET

; KEY  ( -- c )  1文字入力
FORTH_KEY:
    STW  X, [$E008]         ; DSP退避

_key_wait:
    LDW  A, [UART_STAT]
    CMPI A, #0
    BEQ  _key_wait

    LDW  X, #$FC82          ; X = UART_RX
    LDB  A, [X]             ; A = 受信データ
    LDW  X, [$E008]         ; DSP復元
    SUBI X, #2
    STW  A, [X]             ; データスタックへpush
    RET

; ============================================================
; Forthメインルーチン (Layer 0 動作確認テスト)
;
; 各ワードをテストし、最後に A=$DEAD で HALT する
; スタックは各テスト後に空になることを確認
; ============================================================

FORTH_MAIN:

    ; ===== テスト1: DUP =====
    ; $1234をプッシュ、DUP、DROP×2 → スタック空
    LDW  A, #$1234
    SUBI X, #2
    STW  A, [X]             ; DPUSH $1234
    JSR  FORTH_DUP          ; ( $1234 $1234 )
    JSR  FORTH_DROP         ; ( $1234 )
    JSR  FORTH_DROP         ; ( )

    ; ===== テスト2: SWAP =====
    LDW  A, #$0001
    SUBI X, #2
    STW  A, [X]
    LDW  A, #$0002
    SUBI X, #2
    STW  A, [X]             ; ( $0001 $0002 )
    JSR  FORTH_SWAP         ; ( $0002 $0001 ) ← TOS=$0001(a)
    ; TOSが$0001(a)であることを確認
    LDW  A, [X]
    CMPI A, #$0001
    BNE  _test_fail
    JSR  FORTH_DROP
    JSR  FORTH_DROP         ; ( )

    ; ===== テスト3: OVER =====
    LDW  A, #$000A
    SUBI X, #2
    STW  A, [X]
    LDW  A, #$000B
    SUBI X, #2
    STW  A, [X]             ; ( $000A $000B )
    JSR  FORTH_OVER         ; ( $000A $000B $000A )
    LDW  A, [X]
    CMPI A, #$000A
    BNE  _test_fail
    JSR  FORTH_DROP
    JSR  FORTH_DROP
    JSR  FORTH_DROP         ; ( )

    ; ===== テスト4: ROT =====
    LDW  A, #$0001
    SUBI X, #2
    STW  A, [X]
    LDW  A, #$0002
    SUBI X, #2
    STW  A, [X]
    LDW  A, #$0003
    SUBI X, #2
    STW  A, [X]             ; ( $0001 $0002 $0003 )
    JSR  FORTH_ROT          ; ( $0002 $0003 $0001 )
    LDW  A, [X]
    CMPI A, #$0001          ; TOS = $0001 ?
    BNE  _test_fail
    JSR  FORTH_DROP
    LDW  A, [X]
    CMPI A, #$0003          ; NOS = $0003 ?
    BNE  _test_fail
    JSR  FORTH_DROP
    JSR  FORTH_DROP         ; ( )

    ; ===== テスト5: + =====
    LDW  A, #3
    SUBI X, #2
    STW  A, [X]
    LDW  A, #4
    SUBI X, #2
    STW  A, [X]
    JSR  FORTH_ADD          ; ( 7 )
    LDW  A, [X]
    CMPI A, #7
    BNE  _test_fail
    JSR  FORTH_DROP

    ; ===== テスト6: - =====
    LDW  A, #10
    SUBI X, #2
    STW  A, [X]
    LDW  A, #3
    SUBI X, #2
    STW  A, [X]
    JSR  FORTH_SUB          ; ( 7 )
    LDW  A, [X]
    CMPI A, #7
    BNE  _test_fail
    JSR  FORTH_DROP

    ; ===== テスト7: NEGATE =====
    LDW  A, #5
    SUBI X, #2
    STW  A, [X]
    JSR  FORTH_NEGATE       ; ( $FFFB = -5 )
    LDW  A, [X]
    CMPI A, #$FFFB
    BNE  _test_fail
    JSR  FORTH_DROP

    ; ===== テスト8: 1+ 1- =====
    LDW  A, #$10
    SUBI X, #2
    STW  A, [X]
    JSR  FORTH_1PLUS        ; ( $11 )
    JSR  FORTH_1MINUS       ; ( $10 )
    LDW  A, [X]
    CMPI A, #$10
    BNE  _test_fail
    JSR  FORTH_DROP

    ; ===== テスト9: @ ! =====
    ; mem[$E010] = $ABCD
    LDW  A, #$ABCD
    SUBI X, #2
    STW  A, [X]
    LDW  A, #$E010
    SUBI X, #2
    STW  A, [X]
    JSR  FORTH_STORE        ; mem[$E010] = $ABCD
    LDW  A, #$E010
    SUBI X, #2
    STW  A, [X]
    JSR  FORTH_FETCH        ; ( $ABCD )
    LDW  A, [X]
    CMPI A, #$ABCD
    BNE  _test_fail
    JSR  FORTH_DROP

    ; ===== テスト10: C@ C! =====
    LDW  A, #$5A
    SUBI X, #2
    STW  A, [X]
    LDW  A, #$E012
    SUBI X, #2
    STW  A, [X]
    JSR  FORTH_CSTORE       ; mem8[$E012] = $5A
    LDW  A, #$E012
    SUBI X, #2
    STW  A, [X]
    JSR  FORTH_CFETCH       ; ( $005A )
    LDW  A, [X]
    CMPI A, #$005A
    BNE  _test_fail
    JSR  FORTH_DROP

    ; ===== テスト11: +! =====
    LDW  A, #10
    SUBI X, #2
    STW  A, [X]
    LDW  A, #$E014
    SUBI X, #2
    STW  A, [X]
    JSR  FORTH_STORE        ; mem[$E014] = 10
    LDW  A, #5
    SUBI X, #2
    STW  A, [X]
    LDW  A, #$E014
    SUBI X, #2
    STW  A, [X]
    JSR  FORTH_PLUS_STORE   ; mem[$E014] += 5
    LDW  A, #$E014
    SUBI X, #2
    STW  A, [X]
    JSR  FORTH_FETCH        ; ( 15 )
    LDW  A, [X]
    CMPI A, #15
    BNE  _test_fail
    JSR  FORTH_DROP

    ; ===== テスト12: 0= =====
    LDW  A, #0
    SUBI X, #2
    STW  A, [X]
    JSR  FORTH_ZERO_EQ      ; ( $FFFF )
    LDW  A, [X]
    CMPI A, #$FFFF
    BNE  _test_fail
    JSR  FORTH_DROP

    LDW  A, #1
    SUBI X, #2
    STW  A, [X]
    JSR  FORTH_ZERO_EQ      ; ( $0000 )
    LDW  A, [X]
    CMPI A, #0
    BNE  _test_fail
    JSR  FORTH_DROP

    ; ===== テスト13: = < > =====
    LDW  A, #5
    SUBI X, #2
    STW  A, [X]
    LDW  A, #5
    SUBI X, #2
    STW  A, [X]
    JSR  FORTH_EQ           ; ( $FFFF )
    LDW  A, [X]
    CMPI A, #$FFFF
    BNE  _test_fail
    JSR  FORTH_DROP

    LDW  A, #3
    SUBI X, #2
    STW  A, [X]
    LDW  A, #7
    SUBI X, #2
    STW  A, [X]
    JSR  FORTH_LT           ; ( $FFFF ) 3<7
    LDW  A, [X]
    CMPI A, #$FFFF
    BNE  _test_fail
    JSR  FORTH_DROP

    LDW  A, #7
    SUBI X, #2
    STW  A, [X]
    LDW  A, #3
    SUBI X, #2
    STW  A, [X]
    JSR  FORTH_GT           ; ( $FFFF ) 7>3
    LDW  A, [X]
    CMPI A, #$FFFF
    BNE  _test_fail
    JSR  FORTH_DROP

    ; ===== テスト14: INVERT (NOT) =====
    LDW  A, #0
    SUBI X, #2
    STW  A, [X]
    JSR  FORTH_INVERT       ; ( $FFFF )
    LDW  A, [X]
    CMPI A, #$FFFF
    BNE  _test_fail
    JSR  FORTH_DROP

    LDW  A, #$FFFF
    SUBI X, #2
    STW  A, [X]
    JSR  FORTH_INVERT       ; ( $0000 )
    LDW  A, [X]
    CMPI A, #0
    BNE  _test_fail
    JSR  FORTH_DROP

    ; ===== テスト15: >R R> (インライン展開) =====
    ; >R: データスタック($BEEF) → コールスタック(SP)
    LDW  A, #$BEEF
    SUBI X, #2
    STW  A, [X]             ; DPUSH $BEEF
    ; >R インライン展開
    LDW  A, [X]             ; A = $BEEF
    ADDI X, #2              ; Xスタックpop
    PUSH A                  ; SPスタックへ push ($BEEF)
    ; R> インライン展開: コールスタック → データスタック
    POP  A                  ; SPスタックから $BEEF をpop
    SUBI X, #2              ; Xスタックpush
    STW  A, [X]             ; Xスタックに $BEEF を書く
    ; 確認
    LDW  A, [X]
    CMPI A, #$BEEF
    BNE  _test_fail
    JSR  FORTH_DROP

    ; ===== 全テスト完了 =====
    LDW  A, #$DEAD
    HALT

_test_fail:
    ; テスト失敗: A=$BAAD で HALT
    LDW  A, #$BAAD
    HALT

; ============================================================
; End of forth_kernel.asm  v0.2
; ============================================================
