#!/usr/bin/env python3
"""make_task_patch.py - task_demo用カーネルパッチを生成
usage: make_task_patch.py <sym_file> <output.asm>
"""
import sys

sym_file, out_file = sys.argv[1], sys.argv[2]

with open(sym_file) as f:
    syms = {p[1]: int(p[0], 16)
            for line in f
            for p in [line.strip().split()]
            if len(p) == 2}

main_addr  = syms.get('WORD_main', 0)
task1_addr = syms.get('WORD_task1_main', 0)

if not main_addr or not task1_addr:
    print(f"ERROR: WORD_main or WORD_task1_main not found in {sym_file}", file=sys.stderr)
    sys.exit(1)

patch = f"""; task_patch.asm - task_demo用カーネルパッチ（自動生成）
; TASK0_ENTRY($0360) → WORD_main        (${main_addr:04X})
; TASK1_ENTRY($03C0) → WORD_task1_main  (${task1_addr:04X})

    .org $0360
TASK0_ENTRY:
    JSR  ${main_addr:04X}
    HALT

    .org $03C0
TASK1_ENTRY:
    JSR  ${task1_addr:04X}
    HALT
"""
with open(out_file, 'w') as f:
    f.write(patch)
print(f"  task_patch: TASK0→${main_addr:04X}, TASK1→${task1_addr:04X}")
