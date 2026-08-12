#!/usr/bin/env python3
# check_isa21_coverage.py
# YSD8800 ISA2.1 命令網羅テスト 検証スクリプト
#
# 使い方:
#   hasm21 test_isa21_coverage.asm
#   python3 check_isa21_coverage.py test_isa21_coverage.asm.bin \
#                                   test_isa21_coverage.asm.sym
#
# 仕様書: ISA2.1仕様書 (V2.1.0)
# 各テスト: アドレス・バイト列・エンコードを仕様と直接照合する

import sys
import struct

# ──────────────────────────────────────────
# Utility
# ──────────────────────────────────────────

PASS = "\033[32mPASS\033[0m"
FAIL = "\033[31mFAIL\033[0m"
INFO = "\033[36mINFO\033[0m"

pass_count = 0
fail_count = 0
section_results: dict[str, list] = {}
current_section = "uncategorized"

def section(name: str):
    global current_section
    current_section = name
    section_results.setdefault(name, [])
    print(f"\n{'='*60}")
    print(f"  {name}")
    print(f"{'='*60}")

def check(label: str, got: bytes, expected: bytes):
    global pass_count, fail_count
    ok = (got == expected)
    tag = PASS if ok else FAIL
    got_hex      = " ".join(f"{b:02X}" for b in got)
    expected_hex = " ".join(f"{b:02X}" for b in expected)
    if ok:
        print(f"  [{tag}] {label}")
        print(f"          bytes: {got_hex}")
        pass_count += 1
    else:
        print(f"  [{tag}] {label}")
        print(f"          got:      {got_hex}")
        print(f"          expected: {expected_hex}")
        fail_count += 1
    section_results[current_section].append(ok)

def at(addr: int, length: int) -> bytes:
    """バイナリから指定アドレス・長さを取得"""
    return bytes(data[addr: addr + length])

def w16(addr: int) -> int:
    return data[addr] | (data[addr+1] << 8)

def rel16(target_addr: int, pc_after: int) -> bytes:
    """rel16 = target - pc_after (リトルエンディアン2バイト)"""
    v = (target_addr - pc_after) & 0xFFFF
    return bytes([v & 0xFF, v >> 8])

# ──────────────────────────────────────────
# Load binary / symbols
# ──────────────────────────────────────────

if len(sys.argv) < 3:
    print(f"usage: python3 {sys.argv[0]} <bin> <sym>")
    sys.exit(1)

with open(sys.argv[1], "rb") as f:
    data = bytearray(f.read())

syms: dict[str, int] = {}
with open(sys.argv[2]) as f:
    for line in f:
        parts = line.strip().split()
        if len(parts) == 2:
            syms[parts[1]] = int(parts[0], 16)

print(f"[{INFO}] Binary: {sys.argv[1]}  ({len(data)} bytes)")
print(f"[{INFO}] Symbols: {len(syms)} entries")

# ──────────────────────────────────────────
# Section 0: ベクタテーブル  §7.2
# ──────────────────────────────────────────
section("Section 0: ベクタテーブル (§7.2)")

# vector_address = irq_id * 2  (リトルエンディアン)
for vec_id, vec_name, sym_name in [
    (0, "reset",   "_start"),
    (1, "irq0",    "irq0_isr"),
    (2, "irq1",    "irq1_isr"),
    (3, "align",   "align_isr"),
    (4, "syscall", "syscall_isr"),
]:
    addr = vec_id * 2
    expected_val = syms[sym_name]
    expected_bytes = bytes([expected_val & 0xFF, expected_val >> 8])
    check(f".vector {vec_name} -> 0x{expected_val:04X}  @0x{addr:04X}",
          at(addr, 2), expected_bytes)

# ──────────────────────────────────────────
# Section 1: Control / System  §5
# ──────────────────────────────────────────
section("Section 1: Control / System (§5, 0x00-0x06)")

pc = syms["_start"]

check("NOP (0x00)",  at(pc, 1), b"\x00");  pc += 1
check("EI  (0x02)",  at(pc, 1), b"\x02");  pc += 1
check("DI  (0x03)",  at(pc, 1), b"\x03");  pc += 1
check("BRK (0x06)",  at(pc, 1), b"\x06");  pc += 1

check("SYSCALL #0      [0x05 0x00 0x00]", at(pc,3), bytes([0x05,0x00,0x00])); pc+=3
check("SYSCALL #$0001  [0x05 0x01 0x00]", at(pc,3), bytes([0x05,0x01,0x00])); pc+=3
check("SYSCALL #255    [0x05 0xFF 0x00]", at(pc,3), bytes([0x05,0xFF,0x00])); pc+=3
check("SYSCALL #$FFFF  [0x05 0xFF 0xFF]", at(pc,3), bytes([0x05,0xFF,0xFF])); pc+=3

# JSR sec2_data_transfer
sec2 = syms["sec2_data_transfer"]
check("JSR sec2_data_transfer (0x68)",
      at(pc,3), bytes([0x68, sec2&0xFF, sec2>>8])); pc+=3

# HALT は _end で確認
check("HALT (0x01) @ _end", at(syms["_end"],1), b"\x01")

# ──────────────────────────────────────────
# Section 2: Data Transfer  §6.1-6.4
# ──────────────────────────────────────────
section("Section 2: Data Transfer (§6.1-6.4, 0x20-0x27)")

pc = syms["sec2_data_transfer"]

# § レジスタ番号対応
# A=0 B=1 X=2 SP=3 PC=4 FLAGS=5
REG = {"A":0,"B":1,"X":2,"SP":3,"PC":4,"FLAGS":5}

def reg_byte(rD, rS): return (REG[rD]<<4) | REG[rS]

# 2-1. MOV rD, rS (0x20)
for rD, rS in [("A","B"),("A","X"),("A","SP"),
                ("B","A"),("B","X"),
                ("X","A"),("X","B"),
                ("SP","A"),("SP","B")]:
    rb = reg_byte(rD,rS)
    check(f"MOV {rD},{rS}  [0x20 {rb:02X}]",
          at(pc,2), bytes([0x20, rb])); pc+=2

# 2-2. LDW rD, #imm16 (0x21)
for rD, imm in [("A",0x0000),("A",0xFFFF),("A",0x1234),
                ("B",0xABCD),("X",0x0100),("SP",0xF800),
                ("A",42),      # CONST1=42
                ("B",0xFC80)]: # IOBUF=$FC80
    rb = reg_byte(rD,"A") & 0xF0  # rS=0
    check(f"LDW {rD},#0x{imm:04X}  [0x21 {rb:02X} {imm&0xFF:02X} {imm>>8:02X}]",
          at(pc,4), bytes([0x21, rb, imm&0xFF, imm>>8])); pc+=4

# 2-3. LDW rD, [imm16]  絶対 (0x22)
for rD, addr_val in [("A",0x0000),("A",0xFC80),("B",0x4000),("B",0xFFFF)]:
    rb = reg_byte(rD,"A") & 0xF0
    check(f"LDW {rD},[0x{addr_val:04X}]  [0x22 {rb:02X} ...]",
          at(pc,4), bytes([0x22, rb, addr_val&0xFF, addr_val>>8])); pc+=4

# 2-4. STW rS, [imm16]  絶対 (0x23)
for rS, addr_val in [("A",0x0200),("B",0x0202),("X",0x0204),("SP",0x0206)]:
    rb = (0<<4) | REG[rS]   # rD=0 rS=レジスタ
    check(f"STW {rS},[0x{addr_val:04X}]  [0x23 {rb:02X} ...]",
          at(pc,4), bytes([0x23, rb, addr_val&0xFF, addr_val>>8])); pc+=4

# 2-5. LDW rD, [rS]  レジスタ間接 (0x24)
for rD, rS in [("A","A"),("A","B"),("A","X"),("A","SP"),
               ("B","A"),("B","B"),("B","X"),
               ("X","A"),("X","B")]:
    rb = reg_byte(rD,rS)
    check(f"LDW {rD},[{rS}]  [0x24 {rb:02X}]",
          at(pc,2), bytes([0x24, rb])); pc+=2

# 2-6. STW rS, [rD]  レジスタ間接 (0x25)
for rS, rD in [("A","A"),("A","B"),("A","X"),
               ("B","A"),("B","B"),("B","X"),
               ("X","A"),("X","B")]:
    rb = reg_byte(rD,rS)
    check(f"STW {rS},[{rD}]  [0x25 {rb:02X}]",
          at(pc,2), bytes([0x25, rb])); pc+=2

# 2-7. LDW rD, [X + #imm16] (0x26)
for rD, imm in [("A",0),("A",2),("A",0x0100),("A",0xFFFE),
                ("B",4),("X",8)]:
    rb = reg_byte(rD,"A") & 0xF0   # rS フィールド=0 (X 暗黙)
    check(f"LDW {rD},[X+#{imm}]  [0x26 {rb:02X} ...]",
          at(pc,4), bytes([0x26, rb, imm&0xFF, imm>>8])); pc+=4

# 2-8. STW rS, [X + #imm16] (0x27)
for rS, imm in [("A",0),("A",2),("B",4),("X",6)]:
    rb = (0<<4) | REG[rS]  # rD=0
    check(f"STW {rS},[X+#{imm}]  [0x27 {rb:02X} ...]",
          at(pc,4), bytes([0x27, rb, imm&0xFF, imm>>8])); pc+=4

# JSR sec3_alu
sec3 = syms["sec3_alu"]
check("JSR sec3_alu", at(pc,3), bytes([0x68, sec3&0xFF, sec3>>8])); pc+=3

# ──────────────────────────────────────────
# Section 3: Arithmetic / Logic  §6.5
# ──────────────────────────────────────────
section("Section 3: Arithmetic / Logic (§6.5, 0x40-0x45)")

pc = syms["sec3_alu"]

# ADD rD, rS (0x40)
for rD, rS in [("A","A"),("A","B"),("A","X"),
               ("B","A"),("B","B"),
               ("X","A"),("X","B")]:
    rb = reg_byte(rD,rS)
    check(f"ADD {rD},{rS}  [0x40 {rb:02X}]",
          at(pc,2), bytes([0x40,rb])); pc+=2

# ADDI rD, #imm16 (0x41)
for rD, imm in [("A",0),("A",1),("A",0xFFFF),("A",0x8000),("B",100),("X",2)]:
    rb = reg_byte(rD,"A") & 0xF0
    check(f"ADDI {rD},#{imm}  [0x41 {rb:02X} ...]",
          at(pc,4), bytes([0x41,rb,imm&0xFF,imm>>8])); pc+=4

# SUB rD, rS (0x42)
for rD, rS in [("A","A"),("A","B"),("B","A"),("X","A")]:
    rb = reg_byte(rD,rS)
    check(f"SUB {rD},{rS}  [0x42 {rb:02X}]",
          at(pc,2), bytes([0x42,rb])); pc+=2

# SUBI rD, #imm16 (0x43)
for rD, imm in [("A",0),("A",1),("A",0xFFFF),("B",2),("X",2)]:
    rb = reg_byte(rD,"A") & 0xF0
    check(f"SUBI {rD},#{imm}  [0x43 {rb:02X} ...]",
          at(pc,4), bytes([0x43,rb,imm&0xFF,imm>>8])); pc+=4

# CMP rD, rS (0x44)
for rD, rS in [("A","A"),("A","B"),("B","A"),("X","A"),("A","X")]:
    rb = reg_byte(rD,rS)
    check(f"CMP {rD},{rS}  [0x44 {rb:02X}]",
          at(pc,2), bytes([0x44,rb])); pc+=2

# CMPI rD, #imm16 (0x45)
for rD, imm in [("A",0),("A",1),("A",0xFFFF),("B",0x8000),("X",1)]:
    rb = reg_byte(rD,"A") & 0xF0
    check(f"CMPI {rD},#{imm}  [0x45 {rb:02X} ...]",
          at(pc,4), bytes([0x45,rb,imm&0xFF,imm>>8])); pc+=4

# JSR sec4_branch
sec4 = syms["sec4_branch"]
check("JSR sec4_branch", at(pc,3), bytes([0x68,sec4&0xFF,sec4>>8])); pc+=3

# ──────────────────────────────────────────
# Section 4: Branch / Flow  §6.6
# ──────────────────────────────────────────
section("Section 4: Branch / Flow (§6.6, 0x60-0x69)")

pc = syms["sec4_branch"]

# JMP target: rel16 = target - (pc+3)  [opcode(1)+imm16(2)]
def jmp_bytes(opcode, from_pc, target):
    pc_after = from_pc + 3
    rel = (target - pc_after) & 0xFFFF
    return bytes([opcode, rel&0xFF, rel>>8])

jmp_tgt  = syms["jmp_target"]
jmp_back = syms["jmp_back"]
sec5     = syms["sec5_ext_stack"]

# JMP jmp_target (forward)
check("JMP jmp_target (forward, 0x60)",
      at(pc,3), jmp_bytes(0x60, pc, jmp_tgt)); pc+=3

# jmp_back: JSR sec5_ext_stack
check("JSR sec5_ext_stack @jmp_back",
      at(pc,3), bytes([0x68,sec5&0xFF,sec5>>8])); pc+=3

# JMP sec5_ext_stack (JMP forward after JSR)
check("JMP sec5_ext_stack (forward, dead code after JSR)",
      at(pc,3), jmp_bytes(0x60, pc, sec5)); pc+=3

# jmp_target: JMP jmp_back (backward)
assert pc == jmp_tgt, f"PC={pc:#x} expected jmp_target={jmp_tgt:#x}"
check("JMP jmp_back (backward, 0x60)",
      at(pc,3), jmp_bytes(0x60, pc, jmp_back)); pc+=3

# beq_test
beq_taken = syms["beq_taken"]
check("CMPI A,#0 @beq_test",
      at(pc,4), bytes([0x45,0x00,0x00,0x00])); pc+=4
check("BEQ  beq_taken (0x61 forward)",
      at(pc,3), jmp_bytes(0x61,pc,beq_taken)); pc+=3
check("NOP  (before beq_taken)",
      at(pc,1), b"\x00"); pc+=1
check("NOP  (beq_taken label)",
      at(pc,1), b"\x00"); pc+=1

# bne_test
bne_taken = syms["bne_taken"]
check("CMPI A,#1 @bne_test",
      at(pc,4), bytes([0x45,0x00,0x01,0x00])); pc+=4
check("BNE  bne_taken (0x62)",
      at(pc,3), jmp_bytes(0x62,pc,bne_taken)); pc+=3
check("NOP  (before bne_taken)", at(pc,1), b"\x00"); pc+=1
check("NOP  (bne_taken)",        at(pc,1), b"\x00"); pc+=1

# blt_test
blt_taken = syms["blt_taken"]
check("CMPI A,#$7FFF @blt_test",
      at(pc,4), bytes([0x45,0x00,0xFF,0x7F])); pc+=4
check("BLT  blt_taken (0x63)",
      at(pc,3), jmp_bytes(0x63,pc,blt_taken)); pc+=3
check("NOP  (before blt_taken)", at(pc,1), b"\x00"); pc+=1
check("NOP  (blt_taken)",        at(pc,1), b"\x00"); pc+=1

# bge_test
bge_taken = syms["bge_taken"]
check("CMPI A,#0 @bge_test",
      at(pc,4), bytes([0x45,0x00,0x00,0x00])); pc+=4
check("BGE  bge_taken (0x64)",
      at(pc,3), jmp_bytes(0x64,pc,bge_taken)); pc+=3
check("NOP  (before bge_taken)", at(pc,1), b"\x00"); pc+=1
check("NOP  (bge_taken)",        at(pc,1), b"\x00"); pc+=1

# JSR dummy_sub / NOP
dummy_sub = syms["dummy_sub"]
check("JSR  dummy_sub (0x68)",
      at(pc,3), bytes([0x68,dummy_sub&0xFF,dummy_sub>>8])); pc+=3
check("NOP  (after JSR return)", at(pc,1), b"\x00"); pc+=1

# dummy_sub: NOP + RET
check("NOP @ dummy_sub",  at(dummy_sub,1), b"\x00")
check("RET @ dummy_sub+1 (0x69)", at(dummy_sub+1,1), b"\x69")

# JSR sec5 / JMP _end
check("JSR sec5_ext_stack", at(pc,3),
      bytes([0x68,sec5&0xFF,sec5>>8])); pc+=3
_end = syms["_end"]
check("JMP _end (0x60)",    at(pc,3), jmp_bytes(0x60,pc,_end)); pc+=3

# ──────────────────────────────────────────
# Section 5: EXT Stack PUSH/POP  §6.7
# ──────────────────────────────────────────
section("Section 5: EXT Stack PUSH/POP (§6.7, prefix=0x1F)")

pc = syms["sec5_ext_stack"]

EXT = 0x1F
pushpop = [
    ("PUSH A", 0x00), ("PUSH B", 0x01), ("PUSH X", 0x02),
    ("POP  X", 0x05), ("POP  B", 0x04), ("POP  A", 0x03),
    # 往復セット
    ("PUSH A", 0x00), ("PUSH B", 0x01), ("PUSH X", 0x02),
    ("POP  X", 0x05), ("POP  B", 0x04), ("POP  A", 0x03),
]
for name, sub in pushpop:
    check(f"{name}  [0x1F {sub:02X}]",
          at(pc,2), bytes([EXT,sub])); pc+=2

check("RET (end of sec5)", at(pc,1), b"\x69"); pc+=1

# ──────────────────────────────────────────
# Section 6: EXT LDB / STB  §6.7
# ──────────────────────────────────────────
section("Section 6: EXT 8bit Load/Store LDB/STB (§6.7, prefix=0x1F)")

pc = syms["sec6_ext_ldb_stb"]

# (mnemonic, reg, addr_mode, sub_opcode, [imm16 or None])
ldb_stb_cases = [
    # LDB A, [addr]  0x10
    ("LDB A,[0x0100]", 0x10, 0x0100),
    ("LDB A,[0xFC80]", 0x10, 0xFC80),
    ("LDB A,[IOBUF]",  0x10, 0xFC80),
    ("LDB A,[0xFFFF]", 0x10, 0xFFFF),
    # LDB A, [X]  0x11
    ("LDB A,[X]",      0x11, None),
    # LDB B, [addr]  0x12
    ("LDB B,[0x0100]", 0x12, 0x0100),
    ("LDB B,[0xFC80]", 0x12, 0xFC80),
    ("LDB B,[IOBUF]",  0x12, 0xFC80),
    ("LDB B,[0xFFFF]", 0x12, 0xFFFF),
    # LDB B, [X]  0x13
    ("LDB B,[X]",      0x13, None),
    # STB A, [addr]  0x14
    ("STB A,[0x0200]", 0x14, 0x0200),
    ("STB A,[0xFC80]", 0x14, 0xFC80),
    ("STB A,[IOBUF]",  0x14, 0xFC80),
    ("STB A,[0xFFFF]", 0x14, 0xFFFF),
    # STB A, [X]  0x15
    ("STB A,[X]",      0x15, None),
    # STB B, [addr]  0x16
    ("STB B,[0x0200]", 0x16, 0x0200),
    ("STB B,[0xFC80]", 0x16, 0xFC80),
    ("STB B,[IOBUF]",  0x16, 0xFC80),
    ("STB B,[0xFFFF]", 0x16, 0xFFFF),
    # STB B, [X]  0x17
    ("STB B,[X]",      0x17, None),
]
for name, sub, imm in ldb_stb_cases:
    if imm is None:
        check(f"{name}  [0x1F {sub:02X}]",
              at(pc,2), bytes([EXT,sub])); pc+=2
    else:
        check(f"{name}  [0x1F {sub:02X} {imm&0xFF:02X} {imm>>8:02X}]",
              at(pc,4), bytes([EXT,sub,imm&0xFF,imm>>8])); pc+=4

check("RET (end of sec6)", at(pc,1), b"\x69"); pc+=1

# ──────────────────────────────────────────
# Section 7: 疑似命令
# ──────────────────────────────────────────
section("Section 7: 疑似命令 DW / DB / EQU (§アセンブラ)")

pc = syms["sec7_pseudo"]

# DW
check("DW $0000  [00 00]",   at(pc,2), bytes([0x00,0x00])); pc+=2
check("DW $FFFF  [FF FF]",   at(pc,2), bytes([0xFF,0xFF])); pc+=2
check("DW $1234  [34 12]",   at(pc,2), bytes([0x34,0x12])); pc+=2
start_val = syms["_start"]
check(f"DW _start [0x{start_val:04X} LE]",
      at(pc,2), bytes([start_val&0xFF,start_val>>8])); pc+=2
iobuf_val = 0xFC80
check(f"DW IOBUF  [0x{iobuf_val:04X} LE]",
      at(pc,2), bytes([iobuf_val&0xFF,iobuf_val>>8])); pc+=2

# DB
check("DB 0         [00]",       at(pc,1), bytes([0x00]));   pc+=1
check("DB $FF       [FF]",       at(pc,1), bytes([0xFF]));   pc+=1
check("DB 255       [FF]",       at(pc,1), bytes([0xFF]));   pc+=1
check('DB "A"       [41]',       at(pc,1), bytes([0x41]));   pc+=1

# DB "YSD8800",0  = 7文字 + NUL = 8バイト
ysd = b"YSD8800\x00"
check('DB "YSD8800",0  [8 bytes]', at(pc,len(ysd)), ysd); pc+=len(ysd)

# DB 1,2,3,4,5
check("DB 1,2,3,4,5  [01 02 03 04 05]",
      at(pc,5), bytes([1,2,3,4,5])); pc+=5

# DB "ISA",0,"2.1",0  = 4+4 = 8バイト
isa = b"ISA\x002.1\x00"
check('DB "ISA",0,"2.1",0  [8 bytes]',
      at(pc,len(isa)), isa); pc+=len(isa)

# EQU 確認 (シンボルテーブル値)
check("EQU IOBUF=$FC80",
      bytes([syms.get("IOBUF",0)&0xFF,syms.get("IOBUF",0)>>8]),
      bytes([0x80,0xFC]))
check("EQU RAMBASE=0x4000",
      bytes([syms.get("RAMBASE",0)&0xFF,syms.get("RAMBASE",0)>>8]),
      bytes([0x00,0x40]))
check("EQU CONST1=42",
      bytes([syms.get("CONST1",0)&0xFF]),
      bytes([42]))

# ──────────────────────────────────────────
# Section 8: 即値フォーマット
# ──────────────────────────────────────────
section("Section 8: 即値フォーマット全種 (§parse_imm)")

pc = syms["sec8_imm_formats"]

# 8-1. #decimal
for imm in [0, 255, 65535]:
    check(f"LDW A,#{imm} (decimal)",
          at(pc,4), bytes([0x21,0x00,imm&0xFF,imm>>8])); pc+=4

# 8-2. #$hex
for imm in [0x00, 0xFF, 0x1234, 0xABCD, 0xFFFF]:
    check(f"LDW A,#$0x{imm:04X} (#$ form)",
          at(pc,4), bytes([0x21,0x00,imm&0xFF,imm>>8])); pc+=4

# 8-3. #0x form
for imm in [0x00, 0xFF, 0x1234, 0xABCD]:
    check(f"LDW A,#0x{imm:04X} (0x form)",
          at(pc,4), bytes([0x21,0x00,imm&0xFF,imm>>8])); pc+=4

# 8-4. #Ehex (E-leading hex)
for imm in [0xE000, 0xFC80]:
    check(f"LDW A,#0x{imm:04X} (E/F leading hex)",
          at(pc,4), bytes([0x21,0x00,imm&0xFF,imm>>8])); pc+=4

# 8-5. $hex (absolute address in [])
for imm in [0x0000, 0xFFFF]:
    check(f"LDW A,[$0x{imm:04X}] ($ abs form)",
          at(pc,4), bytes([0x22,0x00,imm&0xFF,imm>>8])); pc+=4

# 8-6. #0x (ADDI)
check("ADDI A,#0x0001",
      at(pc,4), bytes([0x41,0x00,0x01,0x00])); pc+=4

# 8-7. #$LABEL  (ASM: LDW A,#$_start / LDW A,#$irq0_isr / LDW B,#$sec7_pseudo)
lbl_rD = {"_start": 0, "irq0_isr": 0, "sec7_pseudo": 1}  # A=0, B=1
for lbl in ["_start","irq0_isr","sec7_pseudo"]:
    v = syms[lbl]
    rb = lbl_rD[lbl] << 4  # rS=0
    check(f"LDW {('A','B')[lbl_rD[lbl]]},#$LABEL={lbl} (0x{v:04X})",
          at(pc,4), bytes([0x21, rb, v&0xFF, v>>8])); pc+=4

# ──────────────────────────────────────────
# Section 9: 全レジスタ × ALU
# ──────────────────────────────────────────
section("Section 9: 全レジスタ × ALU 命令 (rD/rS 組み合わせ)")

pc = syms["sec9_reg_matrix"]

# ADD rD, rS  (0x40)
add_cases = [(rD,rS) for rD in ["A","B","X"] for rS in ["A","B","X","SP"]]
for rD,rS in add_cases:
    rb = reg_byte(rD,rS)
    check(f"ADD {rD},{rS}", at(pc,2), bytes([0x40,rb])); pc+=2

# SUB rD, rS  (0x42)
sub_cases = [(rD,rS) for rD in ["A","B","X"] for rS in ["A","B","X"]]
for rD,rS in sub_cases:
    rb = reg_byte(rD,rS)
    check(f"SUB {rD},{rS}", at(pc,2), bytes([0x42,rb])); pc+=2

# CMP rD, rS  (0x44)
for rD,rS in sub_cases:
    rb = reg_byte(rD,rS)
    check(f"CMP {rD},{rS}", at(pc,2), bytes([0x44,rb])); pc+=2

# ADDI rD (0x41)
for rD in ["A","B","X","SP"]:
    rb = reg_byte(rD,"A") & 0xF0
    imm_val = 2 if rD == "SP" else 1
    check(f"ADDI {rD},#{imm_val}", at(pc,4), bytes([0x41,rb,imm_val,0x00])); pc+=4

# SUBI rD (0x43)
for rD in ["A","B","X","SP"]:
    rb = reg_byte(rD,"A") & 0xF0
    imm_val = 2 if rD == "SP" else 1
    check(f"SUBI {rD},#{imm_val}", at(pc,4), bytes([0x43,rb,imm_val,0x00])); pc+=4

# CMPI rD (0x45)
for rD in ["A","B","X"]:
    rb = reg_byte(rD,"A") & 0xF0
    check(f"CMPI {rD},#0", at(pc,4), bytes([0x45,rb,0x00,0x00])); pc+=4

# ──────────────────────────────────────────
# Section 10: 割り込み制御フロー
# ──────────────────────────────────────────
section("Section 10: 割り込み制御フロー (§7)")

pc = syms["sec10_irq_flow"]
check("DI  (0x03)", at(pc,1), b"\x03"); pc+=1
check("LDW SP,#$F800 スタック初期化",
      at(pc,4), bytes([0x21,0x30,0x00,0xF8])); pc+=4
check("EI  (0x02)", at(pc,1), b"\x02"); pc+=1
check("NOP (0x00)", at(pc,1), b"\x00"); pc+=1
check("DI  (0x03)", at(pc,1), b"\x03"); pc+=1
check("RET (0x69)", at(pc,1), b"\x69"); pc+=1

# IRET @ irq0_isr (0x04)
section("Section 10b: ISR + IRET 確認 (§7.6)")
isr_pc = syms["irq0_isr"]
expected_isr = bytes([
    0x1F,0x00,  # PUSH A
    0x1F,0x01,  # PUSH B
    0x1F,0x02,  # PUSH X
    0x00,       # NOP
    0x1F,0x05,  # POP X
    0x1F,0x04,  # POP B
    0x1F,0x03,  # POP A
    0x04,       # IRET
])
check("irq0_isr: PUSH A/B/X + NOP + POP X/B/A + IRET",
      at(isr_pc, len(expected_isr)), expected_isr)

isr_pc = syms["align_isr"]
check("align_isr: IRET のみ", at(isr_pc,1), b"\x04")

isr_pc = syms["syscall_isr"]
check("syscall_isr: NOP + IRET", at(isr_pc,2), bytes([0x00,0x04]))

# ──────────────────────────────────────────
# 集計
# ──────────────────────────────────────────
print(f"\n{'='*60}")
print(f"  結果サマリー")
print(f"{'='*60}")

all_pass = True
for sec, results in section_results.items():
    n  = len(results)
    ok = sum(results)
    ng = n - ok
    status = "✓" if ng == 0 else "✗"
    print(f"  {status} {sec[:52]:<52s}  {ok:3d}/{n:3d}")
    if ng:
        all_pass = False

print(f"\n  Total : PASS={pass_count}  FAIL={fail_count}"
      f"  ({pass_count}/{pass_count+fail_count})")
if all_pass:
    print(f"\n  \033[32m★ 全テスト PASS ★\033[0m")
else:
    print(f"\n  \033[31m✗ {fail_count} テスト FAIL\033[0m")

sys.exit(0 if all_pass else 1)
