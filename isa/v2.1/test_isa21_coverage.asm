; ============================================================
; test_isa21_coverage.asm
; YSD8800 ISA2.1 命令網羅テスト
;
; 目的: hasm21 がすべての命令・アドレッシングモード・
;       疑似命令・エンコードを正しく生成することを検証する
;
; 構成:
;   Section 0  : ベクタテーブル
;   Section 1  : Control / System  (0x00-0x06)
;   Section 2  : Data Transfer     (0x20-0x27)
;   Section 3  : Arithmetic/Logic  (0x40-0x45)
;   Section 4  : Branch / Flow     (0x60-0x69)
;   Section 5  : EXT Stack         PUSH/POP
;   Section 6  : EXT 8bit Load/Store LDB/STB
;   Section 7  : 疑似命令          DW/DB/EQU/.org/.vector
;   Section 8  : ラベル参照        前方/後方参照
;   Section 9  : 即値フォーマット  #/ #$/ 0x/ $
;   Section 10 : 全レジスタ組み合わせ
; ============================================================

; ============================================================
; Section 0: ベクタテーブル (仕様 §7.2: 0x0000 origin)
; ============================================================
; IRQ ID * 2 = アドレス
; reset=0 irq0=1 irq1=2 align=3 syscall=4
.vector reset   _start          ; 0x0000 <- addr of _start
.vector irq0    irq0_isr        ; 0x0002 <- addr of irq0_isr
.vector irq1    irq1_isr        ; 0x0004 <- addr of irq1_isr
.vector align   align_isr       ; 0x0006 <- addr of align_isr
.vector syscall syscall_isr     ; 0x0008 <- addr of syscall_isr

; ============================================================
; 定数定義 (EQU §疑似命令)
; ============================================================
IOBUF   EQU $FC80               ; I/O領域先頭 (16進 $ 形式)
RAMBASE EQU 0x4000              ; RAM先頭 (0x 形式)
CONST1  EQU 42                  ; 10進
CONST2  EQU IOBUF + 2           ; ラベル+オフセット式

; ============================================================
; Section 1: Control / System  (§5)
; ============================================================
.org $0020
_start:
; --- 1-1. NOP (0x00) ---
    NOP                         ; [0x00]

; --- 1-2. EI  (0x02) ---
    EI                          ; [0x02]

; --- 1-3. DI  (0x03) ---
    DI                          ; [0x03]

; --- 1-4. BRK (0x06) ---
;BRK			;[0x06]

; --- 1-5. SYSCALL imm16 (0x05 + imm16) ---
;     SYSCALL 0 (ID=4 だが即値はシステム定義番号)
    SYSCALL #0                  ; [0x05 0x00 0x00]
    SYSCALL #$0001              ; [0x05 0x01 0x00]
    SYSCALL #255                ; [0x05 0xFF 0x00]
    SYSCALL #$FFFF              ; [0x05 0xFF 0xFF]

; HALT は最後のみ使用 (以降のコードが実行されるよう JSR/JMP で迂回)
    JSR sec2_data_transfer

; ============================================================
; Section 2: Data Transfer  (§6.1 - 6.4)
; ============================================================
sec2_data_transfer:
; --- 2-1. MOV rD, rS (0x20) : 全レジスタペア ---
    MOV  A, B                   ; [0x20 0x01]  rD=0 rS=1
    MOV  A, X                   ; [0x20 0x02]
    MOV  A, SP                  ; [0x20 0x03]
    MOV  B, A                   ; [0x20 0x10]  rD=1 rS=0
    MOV  B, X                   ; [0x20 0x12]
    MOV  X, A                   ; [0x20 0x20]
    MOV  X, B                   ; [0x20 0x21]
    MOV  SP, A                  ; [0x20 0x30]
    MOV  SP, B                  ; [0x20 0x31]

; --- 2-2. LDW rD, #imm16 (0x21) ---
    LDW  A, #0                  ; [0x21 0x00 0x00 0x00]  ゼロ
    LDW  A, #$FFFF              ; [0x21 0x00 0xFF 0xFF]  最大値
    LDW  A, #$1234              ; [0x21 0x00 0x34 0x12]  リトルエンディアン確認
    LDW  B, #$ABCD              ; [0x21 0x10 0xCD 0xAB]
    LDW  X, #$0100              ; [0x21 0x20 0x00 0x01]
    LDW  SP, #$F800             ; [0x21 0x30 0x00 0xF8]  スタック初期化相当
    LDW  A, #42                 ; CONST1=42 の値を直接指定
    LDW  B, #$FC80              ; IOBUF=$FC80 の値を直接指定

; --- 2-3. LDW rD, [imm16]  絶対アドレス (0x22) ---
    LDW  A, [$0000]             ; ベクタ先頭
    LDW  A, [$FC80]             ; I/O領域
    LDW  B, [RAMBASE]           ; EQU定数アドレス
    LDW  B, [$FFFF]             ; 最大アドレス

; --- 2-4. STW rS, [imm16]  絶対アドレス (0x23) ---
    STW  A, [$0200]
    STW  B, [$0202]
    STW  X, [$0204]
    STW  SP, [$0206]

; --- 2-5. LDW rD, [rS]  レジスタ間接 (0x24) ---
    LDW  A, [A]                 ; rD=rS=0 (セルフ参照)
    LDW  A, [B]
    LDW  A, [X]
    LDW  A, [SP]
    LDW  B, [A]
    LDW  B, [B]
    LDW  B, [X]
    LDW  X, [A]
    LDW  X, [B]

; --- 2-6. STW rS, [rD]  レジスタ間接 (0x25) ---
    STW  A, [A]
    STW  A, [B]
    STW  A, [X]
    STW  B, [A]
    STW  B, [B]
    STW  B, [X]
    STW  X, [A]
    STW  X, [B]

; --- 2-7. LDW rD, [X + #imm16]  Xインデックス (0x26) ---
    LDW  A, [X + #0]            ; オフセット0
    LDW  A, [X + #2]
    LDW  A, [X + #$0100]
    LDW  A, [X + #$FFFE]        ; 最大オフセット (負方向)
    LDW  B, [X + #4]
    LDW  X, [X + #8]            ; Xで自分をロード

; --- 2-8. STW rS, [X + #imm16]  Xインデックス (0x27) ---
    STW  A, [X + #0]
    STW  A, [X + #2]
    STW  B, [X + #4]
    STW  X, [X + #6]

    JSR sec3_alu

; ============================================================
; Section 3: Arithmetic / Logic  (§6.5)
; ============================================================
sec3_alu:
; --- 3-1. ADD rD, rS (0x40) ---
    ADD  A, A                   ; [0x40 0x00]
    ADD  A, B                   ; [0x40 0x01]
    ADD  A, X                   ; [0x40 0x02]
    ADD  B, A                   ; [0x40 0x10]
    ADD  B, B
    ADD  X, A
    ADD  X, B

; --- 3-2. ADDI rD, #imm16 (0x41) ---
    ADDI A, #0                  ; +0
    ADDI A, #1
    ADDI A, #$FFFF              ; -1 相当 (符号なし最大)
    ADDI A, #$8000              ; 最小負数相当
    ADDI B, #100
    ADDI X, #$0002              ; X を 2 進める

; --- 3-3. SUB rD, rS (0x42) ---
    SUB  A, A                   ; [0x42 0x00] -> 0
    SUB  A, B                   ; [0x42 0x01]
    SUB  B, A
    SUB  X, A

; --- 3-4. SUBI rD, #imm16 (0x43) ---
    SUBI A, #0
    SUBI A, #1
    SUBI A, #$FFFF
    SUBI B, #2
    SUBI X, #$0002

; --- 3-5. CMP rD, rS (0x44) : FLAGS のみ変化 ---
    CMP  A, A                   ; Z=1
    CMP  A, B
    CMP  B, A
    CMP  X, A
    CMP  A, X

; --- 3-6. CMPI rD, #imm16 (0x45) ---
    CMPI A, #0
    CMPI A, #1
    CMPI A, #$FFFF
    CMPI B, #$8000
    CMPI X, #$0001

    JSR sec4_branch

; ============================================================
; Section 4: Branch / Flow  (§6.6)
; ============================================================
sec4_branch:
; --- 4-1. JMP rel16 (0x60) : 後方参照・前方参照 ---
    JMP  jmp_target             ; 前方参照 (forward)
jmp_back:
    JSR  sec5_ext_stack
    JMP  sec5_ext_stack         ; forward JMP (JSR の後で実行されない)
jmp_target:
    JMP  jmp_back               ; 後方参照 (backward)

; --- 4-2. BEQ rel16 (0x61) ---
beq_test:
    CMPI A, #0
    BEQ  beq_taken              ; Z=1 なら分岐 (forward)
    NOP
beq_taken:
    NOP

; --- 4-3. BNE rel16 (0x62) ---
bne_test:
    CMPI A, #1
    BNE  bne_taken
    NOP
bne_taken:
    NOP

; --- 4-4. BLT rel16 (0x63) ---
blt_test:
    CMPI A, #$7FFF
    BLT  blt_taken
    NOP
blt_taken:
    NOP

; --- 4-5. BGE rel16 (0x64) ---
bge_test:
    CMPI A, #0
    BGE  bge_taken
    NOP
bge_taken:
    NOP

; --- 4-6. JSR imm16 / RET (0x68/0x69) ---
    JSR  dummy_sub              ; サブルーチン呼び出し
    NOP                         ; RET後ここへ

; --- 4-7. IRET (0x04): ISR 内で使用 (§7.6) ---
;     実際の IRET は ISR セクションで確認

    JSR  sec5_ext_stack
    JMP  _end

; ============================================================
; Section 5: EXT Stack - PUSH / POP  (§6.7)
; ============================================================
sec5_ext_stack:
; --- 5-1. PUSH A (EXT 0x00) ---
    PUSH A                      ; [0x1F 0x00]
; --- 5-2. PUSH B (EXT 0x01) ---
    PUSH B                      ; [0x1F 0x01]
; --- 5-3. PUSH X (EXT 0x02) ---
    PUSH X                      ; [0x1F 0x02]
; --- 5-4. POP X (EXT 0x05) ---
    POP  X                      ; [0x1F 0x05]
; --- 5-5. POP B (EXT 0x04) ---
    POP  B                      ; [0x1F 0x04]
; --- 5-6. POP A (EXT 0x03) ---
    POP  A                      ; [0x1F 0x03]
; PUSH/POP 往復で値保存・復元の確認
    PUSH A
    PUSH B
    PUSH X
    POP  X
    POP  B
    POP  A
    RET

; ============================================================
; Section 6: EXT 8bit Load / Store  (§6.7)
; ============================================================
sec6_ext_ldb_stb:
; --- 6-1. LDB A, [addr] (EXT 0x10) ---
    LDB  A, [$0100]             ; [0x1F 0x10 0x00 0x01]
    LDB  A, [$FC80]             ; I/O先頭
    LDB  A, [IOBUF]             ; EQU定数アドレス
    LDB  A, [$FFFF]

; --- 6-2. LDB A, [X] (EXT 0x11) ---
    LDB  A, [X]                 ; [0x1F 0x11]

; --- 6-3. LDB B, [addr] (EXT 0x12) ---
    LDB  B, [$0100]             ; [0x1F 0x12 0x00 0x01]
    LDB  B, [$FC80]
    LDB  B, [IOBUF]
    LDB  B, [$FFFF]

; --- 6-4. LDB B, [X] (EXT 0x13) ---
    LDB  B, [X]                 ; [0x1F 0x13]

; --- 6-5. STB A, [addr] (EXT 0x14) ---
    STB  A, [$0200]             ; [0x1F 0x14 0x00 0x02]
    STB  A, [$FC80]
    STB  A, [IOBUF]
    STB  A, [$FFFF]

; --- 6-6. STB A, [X] (EXT 0x15) ---
    STB  A, [X]                 ; [0x1F 0x15]

; --- 6-7. STB B, [addr] (EXT 0x16) ---
    STB  B, [$0200]             ; [0x1F 0x16 0x00 0x02]
    STB  B, [$FC80]
    STB  B, [IOBUF]
    STB  B, [$FFFF]

; --- 6-8. STB B, [X] (EXT 0x17) ---
    STB  B, [X]                 ; [0x1F 0x17]
    RET

; ============================================================
; Section 7: 疑似命令  (DW / DB / EQU / .org / .vector)
; ============================================================
sec7_pseudo:
; --- 7-1. DW : 16bit 即値データ ---
    DW   $0000                  ; リトルエンディアン 00 00
    DW   $FFFF                  ; FF FF
    DW   $1234                  ; 34 12
    DW   _start                 ; ラベル参照 (アドレス値)
    DW   IOBUF                  ; EQU 参照

; --- 7-2. DB : 8bit / 文字列 ---
    DB   0                      ; 単一バイト
    DB   $FF
    DB   255
    DB   "A"                    ; 1文字
    DB   "YSD8800",0            ; 文字列 + NUL 終端
    DB   1,2,3,4,5              ; 複数数値
    DB   "ISA",0,"2.1",0        ; 文字列 + NUL * 2

; --- 7-3. EQU 各形式 ---
;   (上部定義済み: IOBUF / RAMBASE / CONST1 / CONST2)
;   追加テスト用
DUMMY_EQU EQU 0x1000

; ============================================================
; Section 8: 即値フォーマット全種  (§parse_imm)
; ============================================================
sec8_imm_formats:
; 8-1. #decimal
    LDW  A, #0
    LDW  A, #255
    LDW  A, #65535

; 8-2. #$hex (# + $ prefix)
    LDW  A, #$00
    LDW  A, #$FF
    LDW  A, #$1234
    LDW  A, #$ABCD
    LDW  A, #$FFFF

; 8-3. #0x / #0X hex
    LDW  A, #0x00
    LDW  A, #0xFF
    LDW  A, #0x1234
    LDW  A, #0xABCD

; 8-4. #Ehex  (E-leadingで16進扱い / hasm互換)
    LDW  A, #E000               ; 0xE000
    LDW  A, #FC80               ; 0xFC80

; 8-5. $hex (# なし 絶対アドレス形式)
    LDW  A, [$0000]
    LDW  A, [$FFFF]

; 8-6. 0x (# なし 即値)
    ADDI A, #0x0001

; 8-7. #$LABEL (ラベルを即値として)
    LDW  A, #$_start
    LDW  A, #$irq0_isr
    LDW  B, #$sec7_pseudo

; ============================================================
; Section 9: 全レジスタ × ALU 命令 (rD/rS 全組み合わせ確認)
; ============================================================
sec9_reg_matrix:
; ADD rD, rS : rD ∈ {A,B,X}, rS ∈ {A,B,X,SP}
    ADD  A, A
    ADD  A, B
    ADD  A, X
    ADD  A, SP
    ADD  B, A
    ADD  B, B
    ADD  B, X
    ADD  B, SP
    ADD  X, A
    ADD  X, B
    ADD  X, X
    ADD  X, SP

; SUB rD, rS
    SUB  A, A
    SUB  A, B
    SUB  A, X
    SUB  B, A
    SUB  B, B
    SUB  B, X
    SUB  X, A
    SUB  X, B
    SUB  X, X

; CMP rD, rS
    CMP  A, A
    CMP  A, B
    CMP  A, X
    CMP  B, A
    CMP  B, B
    CMP  B, X
    CMP  X, A
    CMP  X, B
    CMP  X, X

; ADDI rD
    ADDI A, #1
    ADDI B, #1
    ADDI X, #1
    ADDI SP, #2

; SUBI rD
    SUBI A, #1
    SUBI B, #1
    SUBI X, #1
    SUBI SP, #2

; CMPI rD
    CMPI A, #0
    CMPI B, #0
    CMPI X, #0

; ============================================================
; Section 10: 割り込み制御フロー (§7)
; ============================================================
; EI / DI のネストシナリオ
sec10_irq_flow:
    DI                          ; 割り込み禁止
    LDW  SP, #$F800             ; スタックポインタ初期化
    EI                          ; 割り込み許可
    NOP
    DI
    RET

; ============================================================
; 補助: dummy_sub (RET のテスト)
; ============================================================
dummy_sub:
    NOP
    RET                         ; [0x69]

; ============================================================
; 割り込みサービスルーチン (IRET テスト §7.6)
; ============================================================
irq0_isr:
    DI
    PUSH A                      ; コンテキスト保存
    PUSH B
    PUSH X
    ; --- ISR 処理 ---
    NOP
    ; --- コンテキスト復元 ---
    POP  X
    POP  B
    POP  A
    IRET                        ; [0x04] FLAGS←pop / PC←pop

irq1_isr:
    DI
    PUSH A
    NOP
    POP  A
    IRET

align_isr:
    IRET                        ; アラインメント例外ハンドラ

syscall_isr:
    ; SYSCALL 受理 (§7.7 irq_pending = syscall_id=4)
    DI
    NOP
    IRET

; ============================================================
; 終端
; ============================================================
_end:
    HALT                        ; [0x01]
