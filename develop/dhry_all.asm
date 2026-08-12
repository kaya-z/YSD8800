; scc22 v1.00  output: dhry_all.c
; Target: YSD8800 ISA2.2
; build: gcc -std=c99 -O2 -Wall scc22.c -o scc22
;
    .org $0A00


; ============================================================
; scc22 runtime routines
; ============================================================

_putchar:
    ; A = char to output
_putchar_wait:
    LDW  B, [$FC84]
    CMPI B, #0
    BEQ  _putchar_wait
    STW  A, [$FC80]
    RET

_getchar:
    LDW  A, [$FC84]
    CMPI A, #0
    BEQ  _getchar
    LDW  A, [$FC82]
    RET

_C_MUL_A EQU $E0D4
_C_MUL_B EQU $E0D6
_C_MUL_R EQU $E0D8
_cc_mul:
    STW  A, [_C_MUL_A]
    STW  B, [_C_MUL_B]
    LDW  A, #0
    STW  A, [_C_MUL_R]
_ccmul_loop:
    LDW  B, [_C_MUL_B]
    CMPI B, #0
    BEQ  _ccmul_done
    ANDI B, #1
    BEQ  _ccmul_skip
    LDW  A, [_C_MUL_R]
    LDW  B, [_C_MUL_A]
    ADD  A, B
    STW  A, [_C_MUL_R]
_ccmul_skip:
    LDW  A, [_C_MUL_A]
    LDW  B, #1
    SHL  A, B
    STW  A, [_C_MUL_A]
    LDW  A, [_C_MUL_B]
    SHR  A, B
    STW  A, [_C_MUL_B]
    JMP  _ccmul_loop
_ccmul_done:
    LDW  A, [_C_MUL_R]
    RET

_C_DIV_A EQU $E0DA
_C_DIV_B EQU $E0DC
_C_DIV_Q EQU $E0DE
_cc_div:
    ; B / A → A
    CMPI A, #0
    BEQ  _ccdiv_zero
    STW  A, [_C_DIV_A]
    STW  B, [_C_DIV_B]
    LDW  A, #0
    STW  A, [_C_DIV_Q]
_ccdiv_loop:
    LDW  A, [_C_DIV_B]
    LDW  B, [_C_DIV_A]
    CMP  A, B
    BLT  _ccdiv_done
    SUB  A, B
    STW  A, [_C_DIV_B]
    LDW  A, [_C_DIV_Q]
    ADDI A, #1
    STW  A, [_C_DIV_Q]
    JMP  _ccdiv_loop
_ccdiv_done:
    LDW  A, [_C_DIV_Q]
    RET
_ccdiv_zero:
    LDW  A, #0
    RET

_cc_mod:
    ; B mod A → A
    STW  A, [_C_DIV_A]
    STW  B, [_C_DIV_B]
_ccmod_loop:
    LDW  A, [_C_DIV_B]
    LDW  B, [_C_DIV_A]
    CMP  A, B
    BLT  _ccmod_done
    SUB  A, B
    STW  A, [_C_DIV_B]
    JMP  _ccmod_loop
_ccmod_done:
    LDW  A, [_C_DIV_B]
    RET

; ============================================================
; User code
; ============================================================

; global: Int_Comp
Int_Comp               EQU $E300

; global: Str_Comp
Str_Comp               EQU $E302

; global: Str_2_Comp
Str_2_Comp             EQU $E321

; global: Ch_2_Comp
Ch_2_Comp              EQU $E340

; global: Int_Glob
Int_Glob               EQU $E341

; global: Ch_1_Glob
Ch_1_Glob              EQU $E343

; global: Arr_1_Glob
Arr_1_Glob             EQU $E344

; global: Arr_2_Glob
Arr_2_Glob             EQU $E3A8

; global: malloc_1
malloc_1               EQU $E40C

; global: malloc_2
malloc_2               EQU $E40D

; global: result
result                 EQU $E40E

; --- times ---
_times:

; --- dhrystone ---
_dhrystone:

; --- main ---
_main:
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, SP
    LDW  A, #10
    SUBI SP, #2
    STW  A, [SP]
    JSR  _dhrystone
    ADDI SP, #2
    STW  A, [$E40E]
    LDW  A, #0
    LDW  X, [X]
    ADDI SP, #2
    RET
    LDW  X, [X]
    ADDI SP, #2
    RET

; --- main ---
_main:

; global: Ch_1_Glob
Ch_1_Glob              EQU $E410

; global: Int_1_Par_Val
Int_1_Par_Val          EQU $E411

; global: Int_2_Par_Val
Int_2_Par_Val          EQU $E413

; ============================================================
; Data section
; ============================================================
    .org $E300
_Int_2_Par_Val:
    DW  0
_Int_1_Par_Val:
    DW  0
_Ch_1_Glob:
    DB  0
_result:
    DW  0
_malloc_2:
    DB  0
_malloc_1:
    DB  0
_Ch_1_Glob:
    DB  0
_Int_Glob:
    DW  0
_Ch_2_Comp:
    DB  0
_Int_Comp:
    DW  0
_Arr_2_Glob:
    DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0
_Arr_1_Glob:
    DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0, DW 0
_Str_2_Comp:
    DB 0, DB 0, DB 0, DB 0, DB 0, DB 0, DB 0, DB 0, DB 0, DB 0, DB 0, DB 0, DB 0, DB 0, DB 0, DB 0, DB 0, DB 0, DB 0, DB 0, DB 0, DB 0, DB 0, DB 0, DB 0, DB 0, DB 0, DB 0, DB 0, DB 0, DB 0
_Str_Comp:
    DB 0, DB 0, DB 0, DB 0, DB 0, DB 0, DB 0, DB 0, DB 0, DB 0, DB 0, DB 0, DB 0, DB 0, DB 0, DB 0, DB 0, DB 0, DB 0, DB 0, DB 0, DB 0, DB 0, DB 0, DB 0, DB 0, DB 0, DB 0, DB 0, DB 0, DB 0
