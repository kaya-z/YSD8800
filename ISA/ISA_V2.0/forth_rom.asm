; -------------------------------------------------
; YSD8800 ROM Forth Kernel
; ISA2.0 / hasm
; Subroutine Threaded Forth
; -------------------------------------------------

.org 0000

RESET:
    JMP COLD


; -------------------------------------------------
; I/O
; -------------------------------------------------

UART_DATA  EQU 0FF00h
UART_STAT  EQU 0FF02h


; -------------------------------------------------
; kernel variables
; -------------------------------------------------

LATEST  DW 0
HERE    DW 0
STATE   DW 0
RP      DW 0

INLEN   DW 0

INPUTBUF
DB 0
DB 0
DB 0
DB 0
DB 0
DB 0
DB 0
DB 0
DB 0
DB 0
DB 0
DB 0
DB 0
DB 0
DB 0
DB 0
DB 0
DB 0
DB 0
DB 0
DB 0
DB 0
DB 0
DB 0
DB 0
DB 0
DB 0
DB 0
DB 0
DB 0
DB 0
DB 0


; -------------------------------------------------
; cold start
; -------------------------------------------------

COLD

    MOV SP,0FC7Eh

    MOV A,0F7FEh
    STW A,[RP]

    MOV A,0800h
    STW A,[HERE]

    MOV A,0
    STW A,[LATEST]

    JMP QUIT


; -------------------------------------------------
; QUIT
; -------------------------------------------------

QUIT

    JSR INTERPRET
    JMP QUIT


; -------------------------------------------------
; UART primitives
; -------------------------------------------------

EMIT

    POP A
    STW A,[UART_DATA]
    RET


KEY

    LDW A,[UART_DATA]
    PUSH A
    RET


; -------------------------------------------------
; stack ops
; -------------------------------------------------

DUP

    POP A
    PUSH A
    PUSH A
    RET


DROP

    POP A
    RET


SWAP

    POP A
    POP B
    PUSH A
    PUSH B
    RET


OVER

    POP A
    POP B
    PUSH B
    PUSH A
    PUSH B
    RET


; -------------------------------------------------
; arithmetic
; -------------------------------------------------

PLUS

    POP A
    POP B
    ADD A,B
    PUSH A
    RET


MINUS

    POP B
    POP A
    SUB A,B
    PUSH A
    RET


MUL

    POP B
    POP A

    MOV X,0

MUL_LOOP

    CMP B,0
    JE MUL_DONE

    ADD X,A
    DEC B
    JMP MUL_LOOP

MUL_DONE

    PUSH X
    RET


; -------------------------------------------------
; output number
; -------------------------------------------------

DOT

    POP A
    JSR PRINTNUM
    RET


PRINTNUM

    PUSH A
    MOV B,10

    MOV X,0

PN1

    CMP A,0
    JE PN2

    DIV A,B
    PUSH B
    INC X
    JMP PN1

PN2

PN3

    CMP X,0
    JE PN4

    POP A
    ADD A,'0'
    STW A,[UART_DATA]
    DEC X
    JMP PN3

PN4

    POP A
    RET


; -------------------------------------------------
; WORD
; -------------------------------------------------

WORD

    MOV X,INPUTBUF
    MOV B,0

W_SKIP

    LDW A,[UART_DATA]
    CMP A,' '
    JE W_SKIP

W_STORE

    STB A,[X]
    INC X
    INC B

W_NEXT

    LDW A,[UART_DATA]
    CMP A,' '
    JE W_DONE

    STB A,[X]
    INC X
    INC B
    JMP W_NEXT

W_DONE

    MOV A,B
    STW A,[INLEN]
    RET


; -------------------------------------------------
; FIND
; -------------------------------------------------

FIND

    LDW X,[LATEST]

F_LOOP

    CMP X,0
    JE F_NOT

    LDW B,[X]

    LDW A,[X+2]
    CMP A,[INLEN]
    JNE F_NEXT

    MOV A,X
    ADD A,3
    MOV X,A

    JSR CMPNAME
    JE F_FOUND

F_NEXT

    MOV X,B
    JMP F_LOOP

F_FOUND

    ADD X,3
    ADD X,[INLEN]

    LDW A,[X]
    PUSH A
    RET

F_NOT

    MOV A,0
    PUSH A
    RET


; -------------------------------------------------
; CMPNAME
; -------------------------------------------------

CMPNAME

    MOV B,0

CMP_LOOP

    CMP B,[INLEN]
    JE CMP_OK

    LDB A,[INPUTBUF+B]
    LDB X,[X+B]

    CMP A,X
    JNE CMP_FAIL

    INC B
    JMP CMP_LOOP

CMP_OK

    MOV A,0
    RET

CMP_FAIL

    MOV A,1
    RET


; -------------------------------------------------
; NUMBER
; -------------------------------------------------

NUMBER

    MOV X,INPUTBUF
    MOV B,[INLEN]

    MOV A,0

NUM_LOOP

    CMP B,0
    JE NUM_DONE

    LDB X,[INPUTBUF]
    SUB X,'0'

    MUL A,10
    ADD A,X

    INC INPUTBUF
    DEC B

    JMP NUM_LOOP

NUM_DONE

    PUSH A
    RET


; -------------------------------------------------
; EXECUTE
; -------------------------------------------------

EXECUTE

    POP A
    STW A,[TMP]
    JSR TMP
    RET

TMP DW 0


; -------------------------------------------------
; INTERPRET
; -------------------------------------------------

INTERPRET

INT_NEXT

    JSR WORD
    JSR FIND

    POP A

    CMP A,0
    JE INT_NUM

INT_EXEC

    PUSH A
    JSR EXECUTE
    JMP INT_NEXT

INT_NUM

    JSR NUMBER
    JMP INT_NEXT


; -------------------------------------------------
; dictionary (initial words)
; -------------------------------------------------

.org 0800

; example entry

DW 0
DB 3
DB 'D','U','P'
DW DUP
