; scc23 v1.00 (2026-04-16)  source: dhry_timer.c
; Target: YSD8800 ISA2.3
;
    .org $0100

; ============================================================
; C Runtime  org=$0100
; ============================================================

_putchar:
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, SP
    LDW  A, [X + #4]
_putchar_wait:
    LDW  B, [$FC84]
    CMPI B, #0
    BEQ  _putchar_wait
    STW  A, [$FC80]
    LDW  X, [X]
    ADDI SP, #2
    RET

_getchar:
    LDW  A, [$FC84]
    CMPI A, #0
    BEQ  _getchar
    LDW  A, [$FC82]
    RET

_puts:
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, SP
    LDW  A, [X + #4]
    STW  A, [$FBD2]
_puts_loop:
    SUBI SP, #2
    STW  X, [SP]
    LDW  X, [$FBD2]
    LDB  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    CMPI A, #0
    BEQ  _puts_done
_puts_wait:
    LDW  B, [$FC84]
    CMPI B, #0
    BEQ  _puts_wait
    STW  A, [$FC80]
    LDW  A, [$FBD2]
    ADDI A, #1
    STW  A, [$FBD2]
    JMP  _puts_loop
_puts_done:
    LDW  B, [$FC84]
    CMPI B, #0
    BEQ  _puts_done
    LDW  A, #10
    STW  A, [$FC80]
    LDW  X, [X]
    ADDI SP, #2
    RET

_strcpy:
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, SP
    ; [M23] dst=args[0]=[X+4], src=args[1]=[X+6]
    LDW  A, [X + #4]
    STW  A, [$FBD2]
    LDW  B, [X + #6]
    STW  B, [$FBD4]
_strcpy_loop:
    SUBI SP, #2
    STW  X, [SP]
    LDW  X, [$FBD4]
    LDB  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    CMPI A, #0
    BEQ  _strcpy_done
    SUBI SP, #2
    STW  X, [SP]
    LDW  X, [$FBD2]
    STB  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    LDW  A, [$FBD2]
    ADDI A, #1
    STW  A, [$FBD2]
    LDW  A, [$FBD4]
    ADDI A, #1
    STW  A, [$FBD4]
    JMP  _strcpy_loop
_strcpy_done:
    SUBI SP, #2
    STW  X, [SP]
    LDW  X, [$FBD2]
    STB  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    LDW  A, [X + #4]
    LDW  X, [X]
    ADDI SP, #2
    RET

_strcmp:
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, SP
    LDW  A, [X + #4]
    STW  A, [$FBD2]
    LDW  A, [X + #6]
    STW  A, [$FBD4]
_strcmp_loop:
    SUBI SP, #2
    STW  X, [SP]
    LDW  X, [$FBD2]
    LDB  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  A, [SP]
    SUBI SP, #2
    STW  X, [SP]
    LDW  X, [$FBD4]
    LDB  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    LDW  A, [SP]
    ADDI SP, #2
    CMP  A, B
    BNE  _strcmp_diff
    CMPI A, #0
    BEQ  _strcmp_eq
    LDW  A, [$FBD2]
    ADDI A, #1
    STW  A, [$FBD2]
    LDW  A, [$FBD4]
    ADDI A, #1
    STW  A, [$FBD4]
    JMP  _strcmp_loop
_strcmp_eq:
    LDW  A, #0
    LDW  X, [X]
    ADDI SP, #2
    RET
_strcmp_diff:
    SUB  A, B
    LDW  X, [X]
    ADDI SP, #2
    RET

_memcpy:
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, SP
    LDW  A, [X + #4]
    STW  A, [$FBD6]
    LDW  A, [X + #6]
    STW  A, [$FBD8]
    LDW  A, [X + #8]
    STW  A, [$FBDA]
_memcpy_loop:
    LDW  A, [$FBDA]
    CMPI A, #0
    BEQ  _memcpy_done
    SUBI A, #1
    STW  A, [$FBDA]
    SUBI SP, #2
    STW  X, [SP]
    LDW  X, [$FBD8]
    LDB  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    LDW  X, [$FBD6]
    STB  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    LDW  A, [$FBD8]
    ADDI A, #1
    STW  A, [$FBD8]
    LDW  A, [$FBD6]
    ADDI A, #1
    STW  A, [$FBD6]
    JMP  _memcpy_loop
_memcpy_done:
    LDW  A, [X + #4]
    LDW  X, [X]
    ADDI SP, #2
    RET

_C_MUL_A EQU $FBDC
_C_MUL_B EQU $FBDE
_C_MUL_R EQU $FBE0
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

_C_DIV_A EQU $FBE2
_C_DIV_B EQU $FBE4
_C_DIV_Q EQU $FBE6
_cc_div:
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


    .org $0400

; ============================================================
; User code
; ============================================================
    JMP  _main      ; entry point ($0400)


; --- print_num ---
_print_num:
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, SP
    SUBI SP, #2
    LDW  A, [X + #4]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #10
    LDW  B, [SP]
    ADDI SP, #2
    CMP  B, A
    BGE  _L_0014
    LDW  A, #0
    JMP  _L_0015
_L_0014:
    LDW  A, #1
_L_0015:
    CMPI A, #0
    BEQ  _L_0016
    LDW  A, [X + #4]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #10
    LDW  B, [SP]
    ADDI SP, #2
    JSR  _cc_div
    SUBI SP, #2
    STW  A, [SP]
    JSR  _print_num
    ADDI SP, #2
_L_0016:
    LDW  A, #48
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #4]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #10
    LDW  B, [SP]
    ADDI SP, #2
    JSR  _cc_mod
    LDW  B, [SP]
    ADDI SP, #2
    ADD  B, A
    MOV  A, B
    SUBI SP, #2
    STW  A, [SP]
    JSR  _putchar
    ADDI SP, #2
_L_0013:
    LDW  X, [X]
    ADDI SP, #2
    ADDI SP, #2
    RET

; --- timer_start ---
_timer_start:
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, SP
    SUBI SP, #2
    LDW  A, #0x0010
    SYSCALL
_L_0018:
    LDW  X, [X]
    ADDI SP, #2
    ADDI SP, #2
    RET

; --- main ---
_main:
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, SP
    SUBI SP, #2
    SUBI SP, #2
    LDW  A, #10
    SUBI SP, #2
    STW  A, [SP]
    JSR  _dhrystone
    ADDI SP, #2
    SUBI SP, #2
    STW  A, [SP]
    MOV  A, X
    SUBI A, #4
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, [X + #$FFFC]
    CMPI A, #0
    BEQ  _L_0020
    LDW  A, #80
    SUBI SP, #2
    STW  A, [SP]
    JSR  _putchar
    ADDI SP, #2
    JMP  _L_0021
_L_0020:
    LDW  A, #70
    SUBI SP, #2
    STW  A, [SP]
    JSR  _putchar
    ADDI SP, #2
_L_0021:
    LDW  A, #58
    SUBI SP, #2
    STW  A, [SP]
    JSR  _putchar
    ADDI SP, #2
    LDW  A, [$544C]
    SUBI SP, #2
    STW  A, [SP]
    JSR  _print_num
    ADDI SP, #2
    LDW  A, #0
    ADDI SP, #2
    JMP  _L_0019
_L_0019:
    LDW  X, [X]
    ADDI SP, #2
    ADDI SP, #2
    RET

; --- dhrystone ---
_dhrystone:
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, SP
    SUBI SP, #2
    SUBI SP, #2
    SUBI SP, #2
    SUBI SP, #2
    SUBI SP, #2
    SUBI SP, #2
    SUBI SP, #32
    SUBI SP, #32
    SUBI SP, #2
    SUBI SP, #2
    LDW  A, #$53F8
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #$4002
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, #$5422
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #$4000
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, [$4002]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [$4000]
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, #0
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [$4000]
    ADDI A, #2
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, #2
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [$4000]
    ADDI A, #4
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, #40
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [$4000]
    ADDI A, #4
    ADDI A, #2
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, #$_S_0000
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [$4000]
    ADDI A, #4
    ADDI A, #4
    SUBI SP, #2
    STW  A, [SP]
    JSR  _strcpy
    ADDI SP, #4
    LDW  A, #$_S_0001
    SUBI SP, #2
    STW  A, [SP]
    MOV  A, X
    SUBI A, #44
    SUBI SP, #2
    STW  A, [SP]
    JSR  _strcpy
    ADDI SP, #4
    LDW  A, #10
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #$4070
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #8
    LDW  B, #50
    JSR  _cc_mul
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #7
    LDW  B, [SP]
    ADDI SP, #2
    ADD  A, B
    LDW  B, #1
    SHL  A, B
    LDW  B, [SP]
    ADDI SP, #2
    ADD  A, B
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, [X + #4]
    SUBI SP, #2
    STW  A, [SP]
    MOV  A, X
    SUBI A, #80
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, #78
    SUBI SP, #2
    STW  A, [SP]
    JSR  _putchar
    ADDI SP, #2
    LDW  A, #61
    SUBI SP, #2
    STW  A, [SP]
    JSR  _putchar
    ADDI SP, #2
    LDW  A, [X + #$FFB0]
    SUBI SP, #2
    STW  A, [SP]
    JSR  _print_num
    ADDI SP, #2
    LDW  A, #10
    SUBI SP, #2
    STW  A, [SP]
    JSR  _putchar
    ADDI SP, #2
    JSR  _timer_start
    LDW  A, #1
    SUBI SP, #2
    STW  A, [SP]
    MOV  A, X
    SUBI A, #78
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
_L_0023:
    LDW  A, [X + #$FFB2]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #$FFB0]
    LDW  B, [SP]
    ADDI SP, #2
    CMP  B, A
    BLT  _L_0027
    BEQ  _L_0027
    LDW  A, #0
    JMP  _L_0028
_L_0027:
    LDW  A, #1
_L_0028:
    CMPI A, #0
    BEQ  _L_0026
    JMP  _L_0025
_L_0024:
    MOV  A, X
    SUBI A, #78
    STW  A, [$FBD0]
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    LDW  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    ADDI A, #1
    MOV  B, A
    LDW  A, [$FBD0]
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    JMP  _L_0023
_L_0025:
    JSR  _Proc_5
    JSR  _Proc_4
    LDW  A, #2
    SUBI SP, #2
    STW  A, [SP]
    MOV  A, X
    SUBI A, #4
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, #3
    SUBI SP, #2
    STW  A, [SP]
    MOV  A, X
    SUBI A, #6
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, #$_S_0002
    SUBI SP, #2
    STW  A, [SP]
    MOV  A, X
    SUBI A, #76
    SUBI SP, #2
    STW  A, [SP]
    JSR  _strcpy
    ADDI SP, #4
    LDW  A, #1
    SUBI SP, #2
    STW  A, [SP]
    MOV  A, X
    SUBI A, #12
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    MOV  A, X
    SUBI A, #76
    SUBI SP, #2
    STW  A, [SP]
    MOV  A, X
    SUBI A, #44
    SUBI SP, #2
    STW  A, [SP]
    JSR  _Func_2
    ADDI SP, #4
    CMPI A, #0
    BEQ  _L_0029
    LDW  A, #0
    JMP  _L_0030
_L_0029:
    LDW  A, #1
_L_0030:
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #$4006
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
_L_0031:
    LDW  A, [X + #$FFFC]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #$FFFA]
    LDW  B, [SP]
    ADDI SP, #2
    CMP  B, A
    BLT  _L_0033
    LDW  A, #0
    JMP  _L_0034
_L_0033:
    LDW  A, #1
_L_0034:
    CMPI A, #0
    BEQ  _L_0032
    LDW  A, #5
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #$FFFC]
    LDW  B, [SP]
    ADDI SP, #2
    JSR  _cc_mul
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #$FFFA]
    LDW  B, [SP]
    ADDI SP, #2
    SUB  B, A
    MOV  A, B
    SUBI SP, #2
    STW  A, [SP]
    MOV  A, X
    SUBI A, #8
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    MOV  A, X
    SUBI A, #8
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #$FFFA]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #$FFFC]
    SUBI SP, #2
    STW  A, [SP]
    JSR  _Proc_7
    ADDI SP, #6
    MOV  A, X
    SUBI A, #4
    SUBI SP, #2
    STW  A, [SP]
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    LDW  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #1
    LDW  B, [SP]
    ADDI SP, #2
    ADD  B, A
    MOV  A, B
    SUBI SP, #2
    STW  A, [SP]
    LDW  B, [SP]
    ADDI SP, #2
    LDW  A, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    JMP  _L_0031
_L_0032:
    LDW  A, [X + #$FFF8]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #$FFFC]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #$4070
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #$400C
    SUBI SP, #2
    STW  A, [SP]
    JSR  _Proc_8
    ADDI SP, #8
    LDW  A, [$4000]
    SUBI SP, #2
    STW  A, [SP]
    JSR  _Proc_1
    ADDI SP, #2
    LDW  A, #65
    SUBI SP, #2
    STW  A, [SP]
    MOV  A, X
    SUBI A, #10
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STB  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
_L_0035:
    LDW  A, [X + #$FFF6]
    SUBI SP, #2
    STW  A, [SP]
    LDB  A, [$400A]
    LDW  B, [SP]
    ADDI SP, #2
    CMP  B, A
    BLT  _L_0039
    BEQ  _L_0039
    LDW  A, #0
    JMP  _L_0040
_L_0039:
    LDW  A, #1
_L_0040:
    CMPI A, #0
    BEQ  _L_0038
    JMP  _L_0037
_L_0036:
    MOV  A, X
    SUBI A, #10
    STW  A, [$FBD0]
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    LDW  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    ADDI A, #1
    MOV  B, A
    LDW  A, [$FBD0]
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    JMP  _L_0035
_L_0037:
    LDW  A, [X + #$FFF4]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #67
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #$FFF6]
    SUBI SP, #2
    STW  A, [SP]
    JSR  _Func_1
    ADDI SP, #4
    LDW  B, [SP]
    ADDI SP, #2
    CMP  B, A
    BEQ  _L_0041
    LDW  A, #0
    JMP  _L_0042
_L_0041:
    LDW  A, #1
_L_0042:
    CMPI A, #0
    BEQ  _L_0043
    MOV  A, X
    SUBI A, #12
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #0
    SUBI SP, #2
    STW  A, [SP]
    JSR  _Proc_6
    ADDI SP, #4
    LDW  A, #$_S_0003
    SUBI SP, #2
    STW  A, [SP]
    MOV  A, X
    SUBI A, #76
    SUBI SP, #2
    STW  A, [SP]
    JSR  _strcpy
    ADDI SP, #4
    LDW  A, [X + #$FFB2]
    SUBI SP, #2
    STW  A, [SP]
    MOV  A, X
    SUBI A, #6
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, [X + #$FFB2]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #$4004
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
_L_0043:
    JMP  _L_0036
_L_0038:
    LDW  A, [X + #$FFFA]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #$FFFC]
    LDW  B, [SP]
    ADDI SP, #2
    JSR  _cc_mul
    SUBI SP, #2
    STW  A, [SP]
    MOV  A, X
    SUBI A, #6
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, [X + #$FFFA]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #$FFF8]
    LDW  B, [SP]
    ADDI SP, #2
    JSR  _cc_div
    SUBI SP, #2
    STW  A, [SP]
    MOV  A, X
    SUBI A, #4
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, #7
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #$FFFA]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #$FFF8]
    LDW  B, [SP]
    ADDI SP, #2
    SUB  B, A
    MOV  A, B
    LDW  B, [SP]
    ADDI SP, #2
    JSR  _cc_mul
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #$FFFC]
    LDW  B, [SP]
    ADDI SP, #2
    SUB  B, A
    MOV  A, B
    SUBI SP, #2
    STW  A, [SP]
    MOV  A, X
    SUBI A, #6
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    MOV  A, X
    SUBI A, #4
    SUBI SP, #2
    STW  A, [SP]
    JSR  _Proc_2
    ADDI SP, #2
    JMP  _L_0024
_L_0026:
    LDW  A, #10
    PUSH A
    LDW  A, #0x0011
    SYSCALL
    ADDI SP, #2
    LDW  A, #0
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #$544C
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, #$544C
    SUBI SP, #2
    STW  A, [SP]
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    LDW  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [$4004]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #5
    LDW  B, [SP]
    ADDI SP, #2
    CMP  B, A
    BEQ  _L_0045
    LDW  A, #0
    JMP  _L_0046
_L_0045:
    LDW  A, #1
_L_0046:
    LDW  B, [SP]
    ADDI SP, #2
    ADD  B, A
    MOV  A, B
    SUBI SP, #2
    STW  A, [SP]
    LDW  B, [SP]
    ADDI SP, #2
    LDW  A, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, #$544C
    SUBI SP, #2
    STW  A, [SP]
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    LDW  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [$4006]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #1
    LDW  B, [SP]
    ADDI SP, #2
    CMP  B, A
    BEQ  _L_0047
    LDW  A, #0
    JMP  _L_0048
_L_0047:
    LDW  A, #1
_L_0048:
    LDW  B, [SP]
    ADDI SP, #2
    ADD  B, A
    MOV  A, B
    SUBI SP, #2
    STW  A, [SP]
    LDW  B, [SP]
    ADDI SP, #2
    LDW  A, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, #$544C
    SUBI SP, #2
    STW  A, [SP]
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    LDW  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  A, [SP]
    LDB  A, [$4008]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #65
    LDW  B, [SP]
    ADDI SP, #2
    CMP  B, A
    BEQ  _L_0049
    LDW  A, #0
    JMP  _L_0050
_L_0049:
    LDW  A, #1
_L_0050:
    LDW  B, [SP]
    ADDI SP, #2
    ADD  B, A
    MOV  A, B
    SUBI SP, #2
    STW  A, [SP]
    LDW  B, [SP]
    ADDI SP, #2
    LDW  A, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, #$544C
    SUBI SP, #2
    STW  A, [SP]
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    LDW  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  A, [SP]
    LDB  A, [$400A]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #66
    LDW  B, [SP]
    ADDI SP, #2
    CMP  B, A
    BEQ  _L_0051
    LDW  A, #0
    JMP  _L_0052
_L_0051:
    LDW  A, #1
_L_0052:
    LDW  B, [SP]
    ADDI SP, #2
    ADD  B, A
    MOV  A, B
    SUBI SP, #2
    STW  A, [SP]
    LDW  B, [SP]
    ADDI SP, #2
    LDW  A, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, #$544C
    SUBI SP, #2
    STW  A, [SP]
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    LDW  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #$400C
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #8
    LDW  B, #1
    SHL  A, B
    LDW  B, [SP]
    ADDI SP, #2
    ADD  A, B
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    LDW  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #7
    LDW  B, [SP]
    ADDI SP, #2
    CMP  B, A
    BEQ  _L_0053
    LDW  A, #0
    JMP  _L_0054
_L_0053:
    LDW  A, #1
_L_0054:
    LDW  B, [SP]
    ADDI SP, #2
    ADD  B, A
    MOV  A, B
    SUBI SP, #2
    STW  A, [SP]
    LDW  B, [SP]
    ADDI SP, #2
    LDW  A, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, #$544C
    SUBI SP, #2
    STW  A, [SP]
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    LDW  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #$4070
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #8
    LDW  B, #50
    JSR  _cc_mul
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #7
    LDW  B, [SP]
    ADDI SP, #2
    ADD  A, B
    LDW  B, #1
    SHL  A, B
    LDW  B, [SP]
    ADDI SP, #2
    ADD  A, B
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    LDW  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #$FFB0]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #10
    LDW  B, [SP]
    ADDI SP, #2
    ADD  B, A
    MOV  A, B
    LDW  B, [SP]
    ADDI SP, #2
    CMP  B, A
    BEQ  _L_0055
    LDW  A, #0
    JMP  _L_0056
_L_0055:
    LDW  A, #1
_L_0056:
    LDW  B, [SP]
    ADDI SP, #2
    ADD  B, A
    MOV  A, B
    SUBI SP, #2
    STW  A, [SP]
    LDW  B, [SP]
    ADDI SP, #2
    LDW  A, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, #$544C
    SUBI SP, #2
    STW  A, [SP]
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    LDW  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [$4000]
    ADDI A, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    LDW  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #0
    LDW  B, [SP]
    ADDI SP, #2
    CMP  B, A
    BEQ  _L_0057
    LDW  A, #0
    JMP  _L_0058
_L_0057:
    LDW  A, #1
_L_0058:
    LDW  B, [SP]
    ADDI SP, #2
    ADD  B, A
    MOV  A, B
    SUBI SP, #2
    STW  A, [SP]
    LDW  B, [SP]
    ADDI SP, #2
    LDW  A, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, #$544C
    SUBI SP, #2
    STW  A, [SP]
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    LDW  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [$4000]
    ADDI A, #4
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    LDW  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #2
    LDW  B, [SP]
    ADDI SP, #2
    CMP  B, A
    BEQ  _L_0059
    LDW  A, #0
    JMP  _L_0060
_L_0059:
    LDW  A, #1
_L_0060:
    LDW  B, [SP]
    ADDI SP, #2
    ADD  B, A
    MOV  A, B
    SUBI SP, #2
    STW  A, [SP]
    LDW  B, [SP]
    ADDI SP, #2
    LDW  A, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, #$544C
    SUBI SP, #2
    STW  A, [SP]
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    LDW  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [$4000]
    ADDI A, #4
    ADDI A, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    LDW  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #17
    LDW  B, [SP]
    ADDI SP, #2
    CMP  B, A
    BEQ  _L_0061
    LDW  A, #0
    JMP  _L_0062
_L_0061:
    LDW  A, #1
_L_0062:
    LDW  B, [SP]
    ADDI SP, #2
    ADD  B, A
    MOV  A, B
    SUBI SP, #2
    STW  A, [SP]
    LDW  B, [SP]
    ADDI SP, #2
    LDW  A, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, #$544C
    SUBI SP, #2
    STW  A, [SP]
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    LDW  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #$_S_0004
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [$4000]
    ADDI A, #4
    ADDI A, #4
    SUBI SP, #2
    STW  A, [SP]
    JSR  _strcmp
    ADDI SP, #4
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #0
    LDW  B, [SP]
    ADDI SP, #2
    CMP  B, A
    BEQ  _L_0063
    LDW  A, #0
    JMP  _L_0064
_L_0063:
    LDW  A, #1
_L_0064:
    LDW  B, [SP]
    ADDI SP, #2
    ADD  B, A
    MOV  A, B
    SUBI SP, #2
    STW  A, [SP]
    LDW  B, [SP]
    ADDI SP, #2
    LDW  A, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, #$544C
    SUBI SP, #2
    STW  A, [SP]
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    LDW  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [$4002]
    ADDI A, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    LDW  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #0
    LDW  B, [SP]
    ADDI SP, #2
    CMP  B, A
    BEQ  _L_0065
    LDW  A, #0
    JMP  _L_0066
_L_0065:
    LDW  A, #1
_L_0066:
    LDW  B, [SP]
    ADDI SP, #2
    ADD  B, A
    MOV  A, B
    SUBI SP, #2
    STW  A, [SP]
    LDW  B, [SP]
    ADDI SP, #2
    LDW  A, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, #$544C
    SUBI SP, #2
    STW  A, [SP]
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    LDW  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [$4002]
    ADDI A, #4
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    LDW  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #1
    LDW  B, [SP]
    ADDI SP, #2
    CMP  B, A
    BEQ  _L_0067
    LDW  A, #0
    JMP  _L_0068
_L_0067:
    LDW  A, #1
_L_0068:
    LDW  B, [SP]
    ADDI SP, #2
    ADD  B, A
    MOV  A, B
    SUBI SP, #2
    STW  A, [SP]
    LDW  B, [SP]
    ADDI SP, #2
    LDW  A, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, #$544C
    SUBI SP, #2
    STW  A, [SP]
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    LDW  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [$4002]
    ADDI A, #4
    ADDI A, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    LDW  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #18
    LDW  B, [SP]
    ADDI SP, #2
    CMP  B, A
    BEQ  _L_0069
    LDW  A, #0
    JMP  _L_0070
_L_0069:
    LDW  A, #1
_L_0070:
    LDW  B, [SP]
    ADDI SP, #2
    ADD  B, A
    MOV  A, B
    SUBI SP, #2
    STW  A, [SP]
    LDW  B, [SP]
    ADDI SP, #2
    LDW  A, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, #$544C
    SUBI SP, #2
    STW  A, [SP]
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    LDW  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #$_S_0005
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [$4002]
    ADDI A, #4
    ADDI A, #4
    SUBI SP, #2
    STW  A, [SP]
    JSR  _strcmp
    ADDI SP, #4
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #0
    LDW  B, [SP]
    ADDI SP, #2
    CMP  B, A
    BEQ  _L_0071
    LDW  A, #0
    JMP  _L_0072
_L_0071:
    LDW  A, #1
_L_0072:
    LDW  B, [SP]
    ADDI SP, #2
    ADD  B, A
    MOV  A, B
    SUBI SP, #2
    STW  A, [SP]
    LDW  B, [SP]
    ADDI SP, #2
    LDW  A, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, #$544C
    SUBI SP, #2
    STW  A, [SP]
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    LDW  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #$FFFC]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #5
    LDW  B, [SP]
    ADDI SP, #2
    CMP  B, A
    BEQ  _L_0073
    LDW  A, #0
    JMP  _L_0074
_L_0073:
    LDW  A, #1
_L_0074:
    LDW  B, [SP]
    ADDI SP, #2
    ADD  B, A
    MOV  A, B
    SUBI SP, #2
    STW  A, [SP]
    LDW  B, [SP]
    ADDI SP, #2
    LDW  A, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, #$544C
    SUBI SP, #2
    STW  A, [SP]
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    LDW  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #$FFFA]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #13
    LDW  B, [SP]
    ADDI SP, #2
    CMP  B, A
    BEQ  _L_0075
    LDW  A, #0
    JMP  _L_0076
_L_0075:
    LDW  A, #1
_L_0076:
    LDW  B, [SP]
    ADDI SP, #2
    ADD  B, A
    MOV  A, B
    SUBI SP, #2
    STW  A, [SP]
    LDW  B, [SP]
    ADDI SP, #2
    LDW  A, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, #$544C
    SUBI SP, #2
    STW  A, [SP]
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    LDW  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #$FFF8]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #7
    LDW  B, [SP]
    ADDI SP, #2
    CMP  B, A
    BEQ  _L_0077
    LDW  A, #0
    JMP  _L_0078
_L_0077:
    LDW  A, #1
_L_0078:
    LDW  B, [SP]
    ADDI SP, #2
    ADD  B, A
    MOV  A, B
    SUBI SP, #2
    STW  A, [SP]
    LDW  B, [SP]
    ADDI SP, #2
    LDW  A, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, #$544C
    SUBI SP, #2
    STW  A, [SP]
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    LDW  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #$FFF4]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #1
    LDW  B, [SP]
    ADDI SP, #2
    CMP  B, A
    BEQ  _L_0079
    LDW  A, #0
    JMP  _L_0080
_L_0079:
    LDW  A, #1
_L_0080:
    LDW  B, [SP]
    ADDI SP, #2
    ADD  B, A
    MOV  A, B
    SUBI SP, #2
    STW  A, [SP]
    LDW  B, [SP]
    ADDI SP, #2
    LDW  A, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, #$544C
    SUBI SP, #2
    STW  A, [SP]
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    LDW  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #$_S_0006
    SUBI SP, #2
    STW  A, [SP]
    MOV  A, X
    SUBI A, #44
    SUBI SP, #2
    STW  A, [SP]
    JSR  _strcmp
    ADDI SP, #4
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #0
    LDW  B, [SP]
    ADDI SP, #2
    CMP  B, A
    BEQ  _L_0081
    LDW  A, #0
    JMP  _L_0082
_L_0081:
    LDW  A, #1
_L_0082:
    LDW  B, [SP]
    ADDI SP, #2
    ADD  B, A
    MOV  A, B
    SUBI SP, #2
    STW  A, [SP]
    LDW  B, [SP]
    ADDI SP, #2
    LDW  A, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, #$544C
    SUBI SP, #2
    STW  A, [SP]
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    LDW  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #$_S_0007
    SUBI SP, #2
    STW  A, [SP]
    MOV  A, X
    SUBI A, #76
    SUBI SP, #2
    STW  A, [SP]
    JSR  _strcmp
    ADDI SP, #4
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #0
    LDW  B, [SP]
    ADDI SP, #2
    CMP  B, A
    BEQ  _L_0083
    LDW  A, #0
    JMP  _L_0084
_L_0083:
    LDW  A, #1
_L_0084:
    LDW  B, [SP]
    ADDI SP, #2
    ADD  B, A
    MOV  A, B
    SUBI SP, #2
    STW  A, [SP]
    LDW  B, [SP]
    ADDI SP, #2
    LDW  A, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, [$544C]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #20
    LDW  B, [SP]
    ADDI SP, #2
    CMP  B, A
    BEQ  _L_0085
    LDW  A, #0
    JMP  _L_0086
_L_0085:
    LDW  A, #1
_L_0086:
    ADDI SP, #78
    JMP  _L_0022
_L_0022:
    LDW  X, [X]
    ADDI SP, #2
    ADDI SP, #2
    RET

; --- Proc_1 ---
_Proc_1:
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, SP
    SUBI SP, #2
    SUBI SP, #2
    LDW  A, [X + #4]
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    LDW  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  A, [SP]
    MOV  A, X
    SUBI A, #4
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    LDW  A, #42
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [$4000]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #4]
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    LDW  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  A, [SP]
    JSR  _memcpy
    ADDI SP, #6
    LDW  A, #5
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #4]
    ADDI A, #4
    ADDI A, #2
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, [X + #4]
    ADDI A, #4
    ADDI A, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    LDW  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #$FFFC]
    ADDI A, #4
    ADDI A, #2
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, [X + #4]
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    LDW  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #$FFFC]
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, [X + #$FFFC]
    SUBI SP, #2
    STW  A, [SP]
    JSR  _Proc_3
    ADDI SP, #2
    LDW  A, [X + #$FFFC]
    ADDI A, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    LDW  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #0
    LDW  B, [SP]
    ADDI SP, #2
    CMP  B, A
    BEQ  _L_0088
    LDW  A, #0
    JMP  _L_0089
_L_0088:
    LDW  A, #1
_L_0089:
    CMPI A, #0
    BEQ  _L_0090
    LDW  A, #6
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #$FFFC]
    ADDI A, #4
    ADDI A, #2
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, [X + #$FFFC]
    ADDI A, #4
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #4]
    ADDI A, #4
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    LDW  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  A, [SP]
    JSR  _Proc_6
    ADDI SP, #4
    LDW  A, [$4000]
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    LDW  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #$FFFC]
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, [X + #$FFFC]
    ADDI A, #4
    ADDI A, #2
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #10
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #$FFFC]
    ADDI A, #4
    ADDI A, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    LDW  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  A, [SP]
    JSR  _Proc_7
    ADDI SP, #6
    JMP  _L_0091
_L_0090:
    LDW  A, #42
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #4]
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    LDW  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #4]
    SUBI SP, #2
    STW  A, [SP]
    JSR  _memcpy
    ADDI SP, #6
_L_0091:
    ADDI SP, #2
_L_0087:
    LDW  X, [X]
    ADDI SP, #2
    ADDI SP, #2
    RET

; --- Proc_2 ---
_Proc_2:
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, SP
    SUBI SP, #2
    SUBI SP, #2
    SUBI SP, #2
    LDW  A, [X + #4]
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    LDW  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #10
    LDW  B, [SP]
    ADDI SP, #2
    ADD  B, A
    MOV  A, B
    SUBI SP, #2
    STW  A, [SP]
    MOV  A, X
    SUBI A, #4
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
_L_0093:
    LDB  A, [$4008]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #65
    LDW  B, [SP]
    ADDI SP, #2
    CMP  B, A
    BEQ  _L_0095
    LDW  A, #0
    JMP  _L_0096
_L_0095:
    LDW  A, #1
_L_0096:
    CMPI A, #0
    BEQ  _L_0097
    MOV  A, X
    SUBI A, #4
    SUBI SP, #2
    STW  A, [SP]
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    LDW  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #1
    LDW  B, [SP]
    ADDI SP, #2
    SUB  B, A
    MOV  A, B
    SUBI SP, #2
    STW  A, [SP]
    LDW  B, [SP]
    ADDI SP, #2
    LDW  A, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, [X + #$FFFC]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [$4004]
    LDW  B, [SP]
    ADDI SP, #2
    SUB  B, A
    MOV  A, B
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #4]
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, #0
    SUBI SP, #2
    STW  A, [SP]
    MOV  A, X
    SUBI A, #6
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
_L_0097:
    LDW  A, [X + #$FFFA]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #0
    LDW  B, [SP]
    ADDI SP, #2
    CMP  B, A
    BNE  _L_0099
    LDW  A, #0
    JMP  _L_0100
_L_0099:
    LDW  A, #1
_L_0100:
    CMPI A, #0
    BNE  _L_0093
_L_0094:
    ADDI SP, #4
_L_0092:
    LDW  X, [X]
    ADDI SP, #2
    ADDI SP, #2
    RET

; --- Proc_3 ---
_Proc_3:
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, SP
    SUBI SP, #2
    LDW  A, [$4000]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #0
    LDW  B, [SP]
    ADDI SP, #2
    CMP  B, A
    BNE  _L_0102
    LDW  A, #0
    JMP  _L_0103
_L_0102:
    LDW  A, #1
_L_0103:
    CMPI A, #0
    BEQ  _L_0104
    LDW  A, [$4000]
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    LDW  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #4]
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
_L_0104:
    LDW  A, [$4000]
    ADDI A, #4
    ADDI A, #2
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [$4004]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #10
    SUBI SP, #2
    STW  A, [SP]
    JSR  _Proc_7
    ADDI SP, #6
_L_0101:
    LDW  X, [X]
    ADDI SP, #2
    ADDI SP, #2
    RET

; --- Proc_4 ---
_Proc_4:
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, SP
    SUBI SP, #2
    SUBI SP, #2
    LDB  A, [$4008]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #65
    LDW  B, [SP]
    ADDI SP, #2
    CMP  B, A
    BEQ  _L_0107
    LDW  A, #0
    JMP  _L_0108
_L_0107:
    LDW  A, #1
_L_0108:
    SUBI SP, #2
    STW  A, [SP]
    MOV  A, X
    SUBI A, #4
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, [X + #$FFFC]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [$4006]
    LDW  B, [SP]
    ADDI SP, #2
    OR   B, A
    MOV  A, B
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #$4006
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, #66
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #$400A
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STB  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    ADDI SP, #2
_L_0106:
    LDW  X, [X]
    ADDI SP, #2
    ADDI SP, #2
    RET

; --- Proc_5 ---
_Proc_5:
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, SP
    SUBI SP, #2
    LDW  A, #65
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #$4008
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STB  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, #0
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #$4006
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
_L_0109:
    LDW  X, [X]
    ADDI SP, #2
    ADDI SP, #2
    RET

; --- Proc_6 ---
_Proc_6:
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, SP
    SUBI SP, #2
    LDW  A, [X + #4]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #6]
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, [X + #4]
    SUBI SP, #2
    STW  A, [SP]
    JSR  _Func_3
    ADDI SP, #2
    CMPI A, #0
    BEQ  _L_0111
    LDW  A, #0
    JMP  _L_0112
_L_0111:
    LDW  A, #1
_L_0112:
    CMPI A, #0
    BEQ  _L_0113
    LDW  A, #3
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #6]
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
_L_0113:
    LDW  A, [X + #4]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #0
    LDW  B, [SP]
    CMP  B, A
    BNE  _L_0116
    LDW  A, #0
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #6]
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    ADDI SP, #2
    JMP  _L_0115
_L_0116:
    LDW  A, #1
    LDW  B, [SP]
    CMP  B, A
    BNE  _L_0117
    LDW  A, [$4004]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #100
    LDW  B, [SP]
    ADDI SP, #2
    CMP  B, A
    CMP  A, B
    BLT  _L_0118
    LDW  A, #0
    JMP  _L_0119
_L_0118:
    LDW  A, #1
_L_0119:
    CMPI A, #0
    BEQ  _L_0120
    LDW  A, #0
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #6]
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    JMP  _L_0121
_L_0120:
    LDW  A, #3
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #6]
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
_L_0121:
    ADDI SP, #2
    JMP  _L_0115
_L_0117:
    LDW  A, #2
    LDW  B, [SP]
    CMP  B, A
    BNE  _L_0122
    LDW  A, #1
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #6]
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    ADDI SP, #2
    JMP  _L_0115
_L_0122:
    LDW  A, #3
    LDW  B, [SP]
    CMP  B, A
    BNE  _L_0123
    ADDI SP, #2
    JMP  _L_0115
_L_0123:
    LDW  A, #4
    LDW  B, [SP]
    CMP  B, A
    BNE  _L_0124
    LDW  A, #2
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #6]
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    ADDI SP, #2
    JMP  _L_0115
_L_0124:
    ADDI SP, #2
_L_0115:
_L_0110:
    LDW  X, [X]
    ADDI SP, #2
    ADDI SP, #2
    RET

; --- Proc_7 ---
_Proc_7:
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, SP
    SUBI SP, #2
    SUBI SP, #2
    LDW  A, [X + #4]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #2
    LDW  B, [SP]
    ADDI SP, #2
    ADD  B, A
    MOV  A, B
    SUBI SP, #2
    STW  A, [SP]
    MOV  A, X
    SUBI A, #4
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, [X + #6]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #$FFFC]
    LDW  B, [SP]
    ADDI SP, #2
    ADD  B, A
    MOV  A, B
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #8]
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    ADDI SP, #2
_L_0125:
    LDW  X, [X]
    ADDI SP, #2
    ADDI SP, #2
    RET

; --- Proc_8 ---
_Proc_8:
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, SP
    SUBI SP, #2
    SUBI SP, #2
    SUBI SP, #2
    LDW  A, [X + #8]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #5
    LDW  B, [SP]
    ADDI SP, #2
    ADD  B, A
    MOV  A, B
    SUBI SP, #2
    STW  A, [SP]
    MOV  A, X
    SUBI A, #6
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, [X + #10]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #4]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #$FFFA]
    LDW  B, #1
    SHL  A, B
    LDW  B, [SP]
    ADDI SP, #2
    ADD  A, B
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, [X + #4]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #$FFFA]
    LDW  B, #1
    SHL  A, B
    LDW  B, [SP]
    ADDI SP, #2
    ADD  A, B
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    LDW  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #4]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #$FFFA]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #1
    LDW  B, [SP]
    ADDI SP, #2
    ADD  B, A
    MOV  A, B
    LDW  B, #1
    SHL  A, B
    LDW  B, [SP]
    ADDI SP, #2
    ADD  A, B
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, [X + #$FFFA]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #4]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #$FFFA]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #30
    LDW  B, [SP]
    ADDI SP, #2
    ADD  B, A
    MOV  A, B
    LDW  B, #1
    SHL  A, B
    LDW  B, [SP]
    ADDI SP, #2
    ADD  A, B
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, [X + #$FFFA]
    SUBI SP, #2
    STW  A, [SP]
    MOV  A, X
    SUBI A, #4
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
_L_0127:
    LDW  A, [X + #$FFFC]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #$FFFA]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #1
    LDW  B, [SP]
    ADDI SP, #2
    ADD  B, A
    MOV  A, B
    LDW  B, [SP]
    ADDI SP, #2
    CMP  B, A
    BLT  _L_0131
    BEQ  _L_0131
    LDW  A, #0
    JMP  _L_0132
_L_0131:
    LDW  A, #1
_L_0132:
    CMPI A, #0
    BEQ  _L_0130
    JMP  _L_0129
_L_0128:
    MOV  A, X
    SUBI A, #4
    STW  A, [$FBD0]
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    LDW  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    ADDI A, #1
    MOV  B, A
    LDW  A, [$FBD0]
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    JMP  _L_0127
_L_0129:
    LDW  A, [X + #$FFFA]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #6]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #$FFFA]
    LDW  B, #50
    JSR  _cc_mul
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #$FFFC]
    LDW  B, [SP]
    ADDI SP, #2
    ADD  A, B
    LDW  B, #1
    SHL  A, B
    LDW  B, [SP]
    ADDI SP, #2
    ADD  A, B
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    JMP  _L_0128
_L_0130:
    LDW  A, [X + #6]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #$FFFA]
    LDW  B, #50
    JSR  _cc_mul
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #$FFFA]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #1
    LDW  B, [SP]
    ADDI SP, #2
    SUB  B, A
    MOV  A, B
    LDW  B, [SP]
    ADDI SP, #2
    ADD  A, B
    LDW  B, #1
    SHL  A, B
    LDW  B, [SP]
    ADDI SP, #2
    ADD  A, B
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    LDW  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #1
    LDW  B, [SP]
    ADDI SP, #2
    ADD  B, A
    MOV  A, B
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #6]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #$FFFA]
    LDW  B, #50
    JSR  _cc_mul
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #$FFFA]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #1
    LDW  B, [SP]
    ADDI SP, #2
    SUB  B, A
    MOV  A, B
    LDW  B, [SP]
    ADDI SP, #2
    ADD  A, B
    LDW  B, #1
    SHL  A, B
    LDW  B, [SP]
    ADDI SP, #2
    ADD  A, B
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, [X + #4]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #$FFFA]
    LDW  B, #1
    SHL  A, B
    LDW  B, [SP]
    ADDI SP, #2
    ADD  A, B
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    LDW  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #6]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #$FFFA]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #20
    LDW  B, [SP]
    ADDI SP, #2
    ADD  B, A
    MOV  A, B
    LDW  B, #50
    JSR  _cc_mul
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #$FFFA]
    LDW  B, [SP]
    ADDI SP, #2
    ADD  A, B
    LDW  B, #1
    SHL  A, B
    LDW  B, [SP]
    ADDI SP, #2
    ADD  A, B
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, #5
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #$4004
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    ADDI SP, #4
_L_0126:
    LDW  X, [X]
    ADDI SP, #2
    ADDI SP, #2
    RET

; --- Func_1 ---
_Func_1:
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, SP
    SUBI SP, #2
    SUBI SP, #2
    SUBI SP, #2
    LDW  A, [X + #4]
    SUBI SP, #2
    STW  A, [SP]
    MOV  A, X
    SUBI A, #4
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STB  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, [X + #$FFFC]
    SUBI SP, #2
    STW  A, [SP]
    MOV  A, X
    SUBI A, #6
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STB  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, [X + #$FFFA]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #6]
    LDW  B, [SP]
    ADDI SP, #2
    CMP  B, A
    BNE  _L_0134
    LDW  A, #0
    JMP  _L_0135
_L_0134:
    LDW  A, #1
_L_0135:
    CMPI A, #0
    BEQ  _L_0136
    LDW  A, #0
    ADDI SP, #4
    JMP  _L_0133
    JMP  _L_0137
_L_0136:
    LDW  A, [X + #$FFFC]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #$4008
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STB  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, #1
    ADDI SP, #4
    JMP  _L_0133
_L_0137:
_L_0133:
    LDW  X, [X]
    ADDI SP, #2
    ADDI SP, #2
    RET

; --- Func_2 ---
_Func_2:
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, SP
    SUBI SP, #2
    SUBI SP, #2
    SUBI SP, #2
    LDW  A, #2
    SUBI SP, #2
    STW  A, [SP]
    MOV  A, X
    SUBI A, #4
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
_L_0139:
    LDW  A, [X + #$FFFC]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #2
    LDW  B, [SP]
    ADDI SP, #2
    CMP  B, A
    BLT  _L_0141
    BEQ  _L_0141
    LDW  A, #0
    JMP  _L_0142
_L_0141:
    LDW  A, #1
_L_0142:
    CMPI A, #0
    BEQ  _L_0140
    LDW  A, [X + #6]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #$FFFC]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #1
    LDW  B, [SP]
    ADDI SP, #2
    ADD  B, A
    MOV  A, B
    LDW  B, [SP]
    ADDI SP, #2
    ADD  A, B
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    LDB  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #4]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #$FFFC]
    LDW  B, [SP]
    ADDI SP, #2
    ADD  A, B
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    LDB  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  A, [SP]
    JSR  _Func_1
    ADDI SP, #4
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #0
    LDW  B, [SP]
    ADDI SP, #2
    CMP  B, A
    BEQ  _L_0143
    LDW  A, #0
    JMP  _L_0144
_L_0143:
    LDW  A, #1
_L_0144:
    CMPI A, #0
    BEQ  _L_0145
    LDW  A, #65
    SUBI SP, #2
    STW  A, [SP]
    MOV  A, X
    SUBI A, #6
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STB  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    MOV  A, X
    SUBI A, #4
    SUBI SP, #2
    STW  A, [SP]
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    LDW  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #1
    LDW  B, [SP]
    ADDI SP, #2
    ADD  B, A
    MOV  A, B
    SUBI SP, #2
    STW  A, [SP]
    LDW  B, [SP]
    ADDI SP, #2
    LDW  A, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
_L_0145:
    JMP  _L_0139
_L_0140:
    LDW  A, [X + #$FFFA]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #87
    LDW  B, [SP]
    ADDI SP, #2
    CMP  B, A
    BGE  _L_0149
    LDW  A, #0
    JMP  _L_0150
_L_0149:
    LDW  A, #1
_L_0150:
    CMPI A, #0
    BEQ  _L_0147
    LDW  A, [X + #$FFFA]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #90
    LDW  B, [SP]
    ADDI SP, #2
    CMP  B, A
    BLT  _L_0151
    LDW  A, #0
    JMP  _L_0152
_L_0151:
    LDW  A, #1
_L_0152:
    CMPI A, #0
    BEQ  _L_0147
    LDW  A, #1
    JMP  _L_0148
_L_0147:
    LDW  A, #0
_L_0148:
    CMPI A, #0
    BEQ  _L_0153
    LDW  A, #7
    SUBI SP, #2
    STW  A, [SP]
    MOV  A, X
    SUBI A, #4
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
_L_0153:
    LDW  A, [X + #$FFFA]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #82
    LDW  B, [SP]
    ADDI SP, #2
    CMP  B, A
    BEQ  _L_0155
    LDW  A, #0
    JMP  _L_0156
_L_0155:
    LDW  A, #1
_L_0156:
    CMPI A, #0
    BEQ  _L_0157
    LDW  A, #1
    ADDI SP, #4
    JMP  _L_0138
    JMP  _L_0158
_L_0157:
    LDW  A, [X + #6]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, [X + #4]
    SUBI SP, #2
    STW  A, [SP]
    JSR  _strcmp
    ADDI SP, #4
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #0
    LDW  B, [SP]
    ADDI SP, #2
    CMP  B, A
    CMP  A, B
    BLT  _L_0159
    LDW  A, #0
    JMP  _L_0160
_L_0159:
    LDW  A, #1
_L_0160:
    CMPI A, #0
    BEQ  _L_0161
    MOV  A, X
    SUBI A, #4
    SUBI SP, #2
    STW  A, [SP]
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    LDW  A, [X]
    LDW  X, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #7
    LDW  B, [SP]
    ADDI SP, #2
    ADD  B, A
    MOV  A, B
    SUBI SP, #2
    STW  A, [SP]
    LDW  B, [SP]
    ADDI SP, #2
    LDW  A, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, [X + #$FFFC]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #$4004
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, #1
    ADDI SP, #4
    JMP  _L_0138
    JMP  _L_0162
_L_0161:
    LDW  A, #0
    ADDI SP, #4
    JMP  _L_0138
_L_0162:
_L_0158:
_L_0138:
    LDW  X, [X]
    ADDI SP, #2
    ADDI SP, #2
    RET

; --- Func_3 ---
_Func_3:
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, SP
    SUBI SP, #2
    SUBI SP, #2
    LDW  A, [X + #4]
    SUBI SP, #2
    STW  A, [SP]
    MOV  A, X
    SUBI A, #4
    LDW  B, [SP]
    ADDI SP, #2
    SUBI SP, #2
    STW  X, [SP]
    MOV  X, A
    STW  B, [X]
    LDW  X, [SP]
    ADDI SP, #2
    MOV  A, B
    LDW  A, [X + #$FFFC]
    SUBI SP, #2
    STW  A, [SP]
    LDW  A, #2
    LDW  B, [SP]
    ADDI SP, #2
    CMP  B, A
    BEQ  _L_0164
    LDW  A, #0
    JMP  _L_0165
_L_0164:
    LDW  A, #1
_L_0165:
    CMPI A, #0
    BEQ  _L_0166
    LDW  A, #1
    ADDI SP, #2
    JMP  _L_0163
    JMP  _L_0167
_L_0166:
    LDW  A, #0
    ADDI SP, #2
    JMP  _L_0163
_L_0167:
_L_0163:
    LDW  X, [X]
    ADDI SP, #2
    ADDI SP, #2
    RET

; ============================================================
; Data section  org=$4000
; ============================================================
    .org $4000
_Ptr_Glob:
    DW  0
_Next_Ptr_Glob:
    DW  0
_Int_Glob:
    DW  0
_Bool_Glob:
    DW  0
_Ch_1_Glob:
    DW  0
_Ch_2_Glob:
    DW  0
_Arr_1_Glob:
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
_Arr_2_Glob:
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
_malloc_1:
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
_malloc_2:
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
    DW  0
_result:
    DW  0
_Reg:
    DW  0
_Begin_Time:
    DW  0
_End_Time:
    DW  0
_User_Time:
    DW  0

; String literal pool
_S_0007:
    DB  68, 72, 82, 89, 83, 84, 79, 78, 69, 32, 80, 82, 79, 71, 82, 65, 77, 44, 32, 50, 39, 78, 68, 32, 83, 84, 82, 73, 78, 71, 0
_S_0006:
    DB  68, 72, 82, 89, 83, 84, 79, 78, 69, 32, 80, 82, 79, 71, 82, 65, 77, 44, 32, 49, 39, 83, 84, 32, 83, 84, 82, 73, 78, 71, 0
_S_0005:
    DB  68, 72, 82, 89, 83, 84, 79, 78, 69, 32, 80, 82, 79, 71, 82, 65, 77, 44, 32, 83, 79, 77, 69, 32, 83, 84, 82, 73, 78, 71, 0
_S_0004:
    DB  68, 72, 82, 89, 83, 84, 79, 78, 69, 32, 80, 82, 79, 71, 82, 65, 77, 44, 32, 83, 79, 77, 69, 32, 83, 84, 82, 73, 78, 71, 0
_S_0003:
    DB  68, 72, 82, 89, 83, 84, 79, 78, 69, 32, 80, 82, 79, 71, 82, 65, 77, 44, 32, 51, 39, 82, 68, 32, 83, 84, 82, 73, 78, 71, 0
_S_0002:
    DB  68, 72, 82, 89, 83, 84, 79, 78, 69, 32, 80, 82, 79, 71, 82, 65, 77, 44, 32, 50, 39, 78, 68, 32, 83, 84, 82, 73, 78, 71, 0
_S_0001:
    DB  68, 72, 82, 89, 83, 84, 79, 78, 69, 32, 80, 82, 79, 71, 82, 65, 77, 44, 32, 49, 39, 83, 84, 32, 83, 84, 82, 73, 78, 71, 0
_S_0000:
    DB  68, 72, 82, 89, 83, 84, 79, 78, 69, 32, 80, 82, 79, 71, 82, 65, 77, 44, 32, 83, 79, 77, 69, 32, 83, 84, 82, 73, 78, 71, 0
