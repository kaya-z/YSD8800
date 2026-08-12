#!/usr/bin/env python3
"""make_harness.py - シンボルテーブルからハーネスASMを生成"""
import sys, re

sym_file = sys.argv[1]
with open(sym_file) as f:
    syms = {p[1]: int(p[0], 16)
            for line in f
            for p in [line.strip().split()]
            if len(p) == 2}

main_addr = syms.get('_main', syms.get('WORD_main', 0))
if main_addr == 0:
    print(f"; ERROR: _main not found in {sym_file}", file=sys.stderr)
    sys.exit(1)

print(f"""; auto-generated harness (make_harness.py)
    .vector reset _cstart
    .vector irq0  _cdummy
    .vector irq1  _cdummy
    .vector align _cdummy
    .vector syscall _cdummy
_main_addr EQU ${main_addr:04X}
    .org $0010
_cdummy:
    DI
    IRET
    .org $0018
_cstart:
    LDW  SP, #$FBFE
    LDW  X,  #$F7FE
    DI
    JSR  _main_addr
    HALT
""")
