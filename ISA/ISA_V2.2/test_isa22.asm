; ============================================================
; YSD8800 ISA2.2 ビット演算命令 動作確認テスト
; test_isa22.asm
; ============================================================

    .vector reset _start
    .org $0040

_start:
    LDW  SP, #$FFFE
    DI

    ; ===== T01: AND rD,rS =====
    ; $FF0F AND $F0FF = $F00F
    LDW  A, #$FF0F
    LDW  B, #$F0FF
    AND  A, B
    CMPI A, #$F00F
    BNE  _fail

    ; ===== T02: ANDI rD,#imm16 =====
    ; $FFFF AND $00FF = $00FF
    LDW  A, #$FFFF
    ANDI A, #$00FF
    CMPI A, #$00FF
    BNE  _fail

    ; ===== T03: OR rD,rS =====
    ; $F000 OR $000F = $F00F
    LDW  A, #$F000
    LDW  B, #$000F
    OR   A, B
    CMPI A, #$F00F
    BNE  _fail

    ; ===== T04: ORI rD,#imm16 =====
    ; $F000 OR $00FF = $F0FF
    LDW  A, #$F000
    ORI  A, #$00FF
    CMPI A, #$F0FF
    BNE  _fail

    ; ===== T05: XOR rD,rS =====
    ; $FFFF XOR $F0F0 = $0F0F
    LDW  A, #$FFFF
    LDW  B, #$F0F0
    XOR  A, B
    CMPI A, #$0F0F
    BNE  _fail

    ; ===== T06: XORI rD,#imm16 =====
    ; $FFFF XOR $FF00 = $00FF
    LDW  A, #$FFFF
    XORI A, #$FF00
    CMPI A, #$00FF
    BNE  _fail

    ; ===== T07: NOT rD =====
    ; NOT $0000 = $FFFF
    LDW  A, #$0000
    NOT  A, A           ; rS は無視 (rD のみ使用)
    CMPI A, #$FFFF
    BNE  _fail

    ; NOT $FFFF = $0000
    LDW  A, #$FFFF
    NOT  A, A
    CMPI A, #$0000
    BNE  _fail

    ; NOT $5A5A = $A5A5
    LDW  A, #$5A5A
    NOT  A, A
    CMPI A, #$A5A5
    BNE  _fail

    ; ===== T08: SHL rD,rS =====
    ; $0001 SHL 4 = $0010
    LDW  A, #$0001
    LDW  B, #4
    SHL  A, B
    CMPI A, #$0010
    BNE  _fail

    ; $0001 SHL 15 = $8000
    LDW  A, #$0001
    LDW  B, #15
    SHL  A, B
    CMPI A, #$8000
    BNE  _fail

    ; ===== T09: SHR rD,rS (論理右シフト) =====
    ; $8000 SHR 1 = $4000 (符号ビットは0埋め)
    LDW  A, #$8000
    LDW  B, #1
    SHR  A, B
    CMPI A, #$4000
    BNE  _fail

    ; $00F0 SHR 4 = $000F
    LDW  A, #$00F0
    LDW  B, #4
    SHR  A, B
    CMPI A, #$000F
    BNE  _fail

    ; ===== T10: SAR rD,rS (算術右シフト) =====
    ; $8000 SAR 1 = $C000 (符号ビット保持)
    LDW  A, #$8000
    LDW  B, #1
    SAR  A, B
    CMPI A, #$C000
    BNE  _fail

    ; $FFF0 SAR 4 = $FFFF (負数の符号拡張)
    LDW  A, #$FFF0
    LDW  B, #4
    SAR  A, B
    CMPI A, #$FFFF
    BNE  _fail

    ; ===== T11: FLAGS更新確認 (AND結果=0 → Z=1) =====
    LDW  A, #$FF00
    LDW  B, #$00FF
    AND  A, B           ; A = $0000, Z=1 になるはず
    BNE  _fail          ; Z=0なら失敗

    ; ===== T12: XOR自己適用 = 0 =====
    LDW  A, #$ABCD
    XOR  A, A           ; A XOR A = 0, Z=1
    BNE  _fail

    ; ===== T13: ビットマスク操作 (Forthカーネル典型パターン) =====
    ; IE ビット (bit7=0x80) の set/clear
    LDW  A, #$02        ; FLAGS初期値 (N=1)
    ORI  A, #$80        ; IE set → $82
    CMPI A, #$82
    BNE  _fail

    LDW  A, #$82
    LDW  B, #$7F        ; ~$80 マスク
    AND  A, B           ; IE clear → $02
    CMPI A, #$02
    BNE  _fail

    ; ===== 全テスト完了 =====
    LDW  A, #$DEAD
    HALT

_fail:
    LDW  A, #$BAAD
    HALT
