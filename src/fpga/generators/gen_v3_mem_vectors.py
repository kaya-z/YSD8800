#!/usr/bin/env python3
# =====================================================================
# gen_v3_mem_vectors.py  v0.1  (2026-07-11)
#   V3: メモリ系命令(LDW/STW絶対・[X+imm16]・[rS]間接・PUSH/POP・LDB/STB)
#   の外部観測等価検証ベクタ生成器
#
# 【役割】(gen_v2_vectors.py同様の単一ソース方針・KY34偽合格防止)
#   - ISA2_3_v231実照合済(emu23_v109.c L1300-1400/1242-1290)エンコードで
#     機械語を構築
#   - emu23で実行し黄金の最終状態を自動取得(期待値を手計算で埋めない)
#   - RTL TBが読む期待値テーブル(hex)を出力
#
# 【対象命令のエンコード】(emu23_v109.c実照合)
#   LDW rD,#imm16    = 0x21 [rD<<4]      lo hi
#   LDW rD,[imm16]   = 0x22 [rD<<4]      lo hi   (絶対アドレス)
#   STW rS,[imm16]   = 0x23 [rS]         lo hi   (絶対アドレス)
#   LDW rD,[rS]      = 0x24 [rD<<4|rS]           (レジスタ間接)
#   STW rS,[rD]      = 0x25 [rD<<4|rS]           (rD=アドレスレジスタ rS=データ)
#   LDW rD,[X+imm16] = 0x26 [rD<<4]      lo hi   (インデックス)
#   STW rS,[X+imm16] = 0x27 [rS]         lo hi   (インデックス)
#   PUSH A/B/X       = 0x1F 0x00/0x01/0x02
#   POP  A/B/X       = 0x1F 0x03/0x04/0x05
#   LDB A,[imm16]    = 0x1F 0x10 lo hi
#   LDB B,[imm16]    = 0x1F 0x12 lo hi
#   STB A,[imm16]    = 0x1F 0x14 lo hi
#   STB B,[imm16]    = 0x1F 0x16 lo hi
#   HALT             = 0x01
#   reg: A=0 B=1 X=2 SP=3 ; FLAGS bit0=Z bit1=N
# =====================================================================
import subprocess, sys, os

CODE_ORG = 0x0100
EMU = './emu23'

A, B, X, SP = 0, 1, 2, 3

def ldw_imm(rd, imm):
    return [0x21, (rd << 4) & 0xF0, imm & 0xFF, (imm >> 8) & 0xFF]

def ldw_abs(rd, addr):
    return [0x22, (rd << 4) & 0xF0, addr & 0xFF, (addr >> 8) & 0xFF]

def stw_abs(rs, addr):
    return [0x23, rs & 0x0F, addr & 0xFF, (addr >> 8) & 0xFF]

def ldw_ind(rd, rs):
    return [0x24, ((rd << 4) | (rs & 0x0F)) & 0xFF]

def stw_ind(rd_addr, rs_data):
    return [0x25, ((rd_addr << 4) | (rs_data & 0x0F)) & 0xFF]

def ldw_xi(rd, imm):
    return [0x26, (rd << 4) & 0xF0, imm & 0xFF, (imm >> 8) & 0xFF]

def stw_xi(rs, imm):
    return [0x27, rs & 0x0F, imm & 0xFF, (imm >> 8) & 0xFF]

def push(reg):
    return [0x1F, 0x00 + reg]      # A=0x00 B=0x01 X=0x02

def pop(reg):
    return [0x1F, 0x03 + reg]      # A=0x03 B=0x04 X=0x05

def ldb_imm(reg_ab, addr):
    sub = 0x10 if reg_ab == A else 0x12
    return [0x1F, sub, addr & 0xFF, (addr >> 8) & 0xFF]

def stb_imm(reg_ab, addr):
    sub = 0x14 if reg_ab == A else 0x16
    return [0x1F, sub, addr & 0xFF, (addr >> 8) & 0xFF]

HALT = [0x01]

# ---------------------------------------------------------------------
# ベクタ定義: (id, 狙い, プログラム(バイト列関数呼び出しの連結))
#
# 【SP初期値の中和】(V2-d既定の教訓・kaizen.txt既知事項)
#   emu23はリセット時SP=0xFC7E既定、RTLはS_RESET_HIでSP<=0x0000。
#   この差異は全ベクタ共通で「先頭にLDW SP,#imm16を明示挿入」して
#   両者を同一の既知値に揃えることで中和する(V2-d方式の踏襲)。
# ---------------------------------------------------------------------
SP_INIT = 0x0400

VECTORS = [
    ("STW_LDW_ABS", "絶対アドレスSTW/LDW round-trip",
        ldw_imm(SP, SP_INIT) +
        ldw_imm(A, 0x1234) + stw_abs(A, 0x0250) +
        ldw_imm(B, 0x0000) + ldw_abs(B, 0x0250) + HALT),

    ("STW_LDW_XI", "インデックス[X+imm16] round-trip",
        ldw_imm(SP, SP_INIT) +
        ldw_imm(X, 0x0300) + ldw_imm(A, 0x5678) + stw_xi(A, 0x0010) +
        ldw_imm(B, 0x0000) + ldw_xi(B, 0x0010) + HALT),

    ("STW_LDW_INDIRECT", "レジスタ間接[rS]/[rD] round-trip",
        ldw_imm(SP, SP_INIT) +
        ldw_imm(X, 0x0260) + ldw_imm(A, 0x9ABC) + stw_ind(X, A) +
        ldw_imm(B, 0x0000) + ldw_ind(B, X) + HALT),

    ("PUSH_POP", "スタックPUSH/POP round-trip(SP復帰確認)",
        ldw_imm(SP, SP_INIT) +
        ldw_imm(A, 0xBEEF) + push(A) +
        ldw_imm(A, 0x0000) + pop(A) + HALT),

    ("LDB_STB", "バイトLDB/STB round-trip(ゼロ拡張確認)",
        ldw_imm(SP, SP_INIT) +
        ldw_imm(A, 0x00AB) + stb_imm(A, 0x0270) +
        ldw_imm(B, 0x0000) + ldb_imm(B, 0x0270) + HALT),
]

def assemble(prog):
    code = bytearray(prog)
    img = bytearray(65536)
    img[0] = CODE_ORG & 0xFF
    img[1] = (CODE_ORG >> 8) & 0xFF
    img[CODE_ORG:CODE_ORG+len(code)] = code
    return img

def run_emu23(binpath, n_steps):
    """emu23を-nで実行し、最終トレース行(PC=.. SP=.. F=.. A=.. B=.. X=..)
       から状態を取得する(gen_v2_vectors.py emu_golden実照合と同一形式)。"""
    r = subprocess.run([EMU, binpath, '-n', str(n_steps)],
                        capture_output=True, text=True, timeout=10)
    last = None
    for line in r.stdout.splitlines():
        line = line.strip()
        if line.startswith('PC=') and ' F=' in line:
            fields = {}
            for tok in line.split():
                if '=' in tok:
                    k, v = tok.split('=', 1)
                    try: fields[k] = int(v, 16)
                    except ValueError: pass
            if all(k in fields for k in ('PC', 'SP', 'F', 'A', 'B', 'X')):
                last = fields
    if last is None:
        return None
    return last['A'], last['B'], last['X'], last['SP'], last['F']

def main():
    if not os.path.exists(EMU):
        print(f"ERROR: {EMU} not found. build emu23 first.", file=sys.stderr)
        sys.exit(1)

    os.makedirs('v3mem', exist_ok=True)
    print(f"{'ID':10s} {'狙い':30s} {'A':6s}{'B':6s}{'X':6s}{'SP':6s}{'F':4s}")
    print("-" * 70)
    golden_lines = []
    exp_words = []
    for vid, purpose, prog in VECTORS:
        img = assemble(prog)
        binpath = f'v3mem/{vid}.bin'
        hexpath = f'v3mem/{vid}.hex'
        with open(binpath, 'wb') as f:
            f.write(img)
        with open(hexpath, 'w') as f:
            for byte in img:
                f.write(f'{byte:02x}\n')
        n_instr = len(prog) + 4  # 命令数概算+余裕
        g = run_emu23(binpath, n_instr)
        if g is None:
            print(f"{vid:10s} *** emu golden取得失敗 ***")
            sys.exit(1)
        a, b, x, sp, f_ = g
        print(f"{vid:10s} {purpose:30s} {a:04X}  {b:04X}  {x:04X}  {sp:04X}  {f_:02X}")
        golden_lines.append(f"{vid}: A={a:04X} B={b:04X} X={x:04X} SP={sp:04X} F={f_:02X}")
        exp_words += [a, b, x, sp, f_]

    with open('v3mem/golden_v3mem.txt', 'w') as f:
        f.write('\n'.join(golden_lines) + '\n')
    with open('v3mem/expected_v3mem.hex', 'w') as f:
        for w in exp_words:
            f.write(f'{w:04x}\n')
    print(f"\ngolden written: v3mem/golden_v3mem.txt ({len(VECTORS)} vectors)")
    print(f"expected hex  : v3mem/expected_v3mem.hex ({len(exp_words)} words)")

if __name__ == '__main__':
    main()
