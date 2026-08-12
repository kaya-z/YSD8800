; disasm22 v1.00  ISA2.2 disassembler
; Binary: test_uart.asm.bin
;

; --- EQU / symbol definitions ---
UART_STAT            EQU $FC84
L1_WK_A              EQU $E020
L1_WK_B              EQU $E022
L1_WK_TMP            EQU $E028


    .org $0000
    .vector reset      _start

    .org $0020
FORTH_TYPE:
    LDW  A, [X]                  ; [0020] 24 02  | LDW  A, [X]
    ADDI X, #$0002               ; [0022] 41 20 02 00  | ADDI X, #2
    LDW  B, [X]                  ; [0026] 24 12  | LDW  B, [X]
    ADDI X, #$0002               ; [0028] 41 20 02 00  | ADDI X, #2
    CMPI A, #$0000               ; [002C] 45 00 00 00  | CMPI A, #0
    BEQ  _type_done              ; [0030] 61 55 00  | BEQ  _type_done
    STW  A, [L1_WK_A]            ; [0033] 23 00 20 E0  | STW  A, [L1_WK_A]
    STW  B, [L1_WK_B]            ; [0037] 23 01 22 E0  | STW  B, [L1_WK_B]
_type_loop:
    LDW  A, [L1_WK_A]            ; [003B] 22 00 20 E0  | LDW  A, [L1_WK_A]
    CMPI A, #$0000               ; [003F] 45 00 00 00  | CMPI A, #0
    BEQ  _type_done              ; [0043] 61 42 00  | BEQ  _type_done
    STW  X, [L1_WK_TMP]          ; [0046] 23 02 28 E0  | STW  X, [L1_WK_TMP]
    LDW  X, [L1_WK_B]            ; [004A] 22 20 22 E0  | LDW  X, [L1_WK_B]
    LDB  A, [X]                  ; [004E] 1F 11  | LDB  A, [X]
    LDW  X, [L1_WK_TMP]          ; [0050] 22 20 28 E0  | LDW  X, [L1_WK_TMP]
_type_emit_wait:
    LDW  B, [UART_STAT]          ; [0054] 22 10 84 FC  | LDW  B, [UART_STAT]
    CMPI B, #$0000               ; [0058] 45 10 00 00  | CMPI B, #0
    BEQ  _type_emit_wait         ; [005C] 61 F5 FF  | BEQ  _type_emit_wait
    STW  X, [L1_WK_TMP]          ; [005F] 23 02 28 E0  | STW  X, [L1_WK_TMP]
    LDW  X, #$FC80               ; [0063] 21 20 80 FC  | LDW  X, #$FC80
    STB  A, [X]                  ; [0067] 1F 15  | STB  A, [X]
    LDW  X, [L1_WK_TMP]          ; [0069] 22 20 28 E0  | LDW  X, [L1_WK_TMP]
    LDW  A, [L1_WK_B]            ; [006D] 22 00 22 E0  | LDW  A, [L1_WK_B]
    ADDI A, #$0001               ; [0071] 41 00 01 00  | ADDI A, #1
    STW  A, [L1_WK_B]            ; [0075] 23 00 22 E0  | STW  A, [L1_WK_B]
    LDW  A, [L1_WK_A]            ; [0079] 22 00 20 E0  | LDW  A, [L1_WK_A]
    SUBI A, #$0001               ; [007D] 43 00 01 00  | SUBI A, #1
    STW  A, [L1_WK_A]            ; [0081] 23 00 20 E0  | STW  A, [L1_WK_A]
    JMP  _type_loop              ; [0085] 60 B3 FF  | JMP  _type_loop
_type_done:
    RET                          ; [0088] 69  | RET
    NOP                          ; [0089] 00  | .org $0090
    NOP                          ; [008A] 00 
    NOP                          ; [008B] 00 
    NOP                          ; [008C] 00 
    NOP                          ; [008D] 00 
    NOP                          ; [008E] 00 
    NOP                          ; [008F] 00 
_start:
    LDW  SP, #$FFFE              ; [0090] 21 30 FE FF  | LDW  SP, #$FFFE
    LDW  X, #$F800               ; [0094] 21 20 00 F8  | LDW  X, #$F800
    DI                           ; [0098] 03  | DI
    LDW  A, #$msg                ; [0099] 21 00 E0 00  | LDW  A, #$msg
    SUBI X, #$0002               ; [009D] 43 20 02 00  | SUBI X, #2
    STW  A, [X]                  ; [00A1] 25 20  | STW  A, [X]
    LDW  A, #$0011               ; [00A3] 21 00 11 00  | LDW  A, #17
    SUBI X, #$0002               ; [00A7] 43 20 02 00  | SUBI X, #2
    STW  A, [X]                  ; [00AB] 25 20  | STW  A, [X]
    JSR  FORTH_TYPE              ; [00AD] 68 20 00  | JSR  FORTH_TYPE
    LDW  A, #$msg2               ; [00B0] 21 00 F0 00  | LDW  A, #$msg2
    SUBI X, #$0002               ; [00B4] 43 20 02 00  | SUBI X, #2
    STW  A, [X]                  ; [00B8] 25 20  | STW  A, [X]
    LDW  A, #$000B               ; [00BA] 21 00 0B 00  | LDW  A, #11
    SUBI X, #$0002               ; [00BE] 43 20 02 00  | SUBI X, #2
    STW  A, [X]                  ; [00C2] 25 20  | STW  A, [X]
    JSR  FORTH_TYPE              ; [00C4] 68 20 00  | JSR  FORTH_TYPE
    LDW  A, #$DEAD               ; [00C7] 21 00 AD DE  | LDW  A, #$DEAD
    HALT                         ; [00CB] 01  | HALT

    .org $00E0
msg:
    ; .db $48  ; unknown op=48   ; [00E0] 48  | DB  "Hello, YSD8800!", $0A
    ; .db $65  ; unknown op=65   ; [00E1] 65 
    ; .db $6C  ; unknown op=6C   ; [00E2] 6C 
    ; .db $6C  ; unknown op=6C   ; [00E3] 6C 
    ; .db $6F  ; unknown op=6F   ; [00E4] 6F 
    ; .db $2C  ; unknown op=2C   ; [00E5] 2C 
    MOV  FLAGS, ?9               ; [00E6] 20 59 
    ORI  PC, #$3838              ; [00E8] 53 44 38 38 
    ; .db $30  ; unknown op=30   ; [00EC] 30 
    ; .db $30  ; unknown op=30   ; [00ED] 30 
    LDW  A, #$614C               ; [00EE] 21 0A 4C 61 
    ; .db $79  ; unknown op=79   ; [00F2] 79 
    ; .db $65  ; unknown op=65   ; [00F3] 65 
    ; .db $72  ; unknown op=72   ; [00F4] 72 
    MOV  SP, B                   ; [00F5] 20 31 
    MOV  PC, ?F                  ; [00F7] 20 4F 
    ; .db $4B  ; unknown op=4B   ; [00F9] 4B 
    ; .db $0A  ; unknown op=0A   ; [00FA] 0A 
