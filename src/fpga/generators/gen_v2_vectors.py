#!/usr/bin/env python3
# =====================================================================
# gen_v2_vectors.py  v0.1  (2026-07-08)
#   V2-a: C1 レジスタALU 検証ベクタ生成器
#
# 【役割】(設計メモ v0.1 §4.2 単一ソース方針)
#   - 各ベクタの機械語を「ISA2_3_v231 実照合済のエンコード」で構築
#   - emu23用 bin を出力
#   - その bin を emu23_v109 で実行し「黄金の最終状態」を自動取得
#     (期待値を手計算で埋めない = KY偽合格防止 / KY34)
#   - RTL TB が読む期待値テーブル(hex)を出力
#
# 【リセットベクタ規約】(既存TB fetch / emu23 §7.3 実照合)
#   mem[0]=lo mem[1]=hi でリセットPC。実コードは CODE_ORG に配置し末尾HALT。
#
# 【観測タイミング】(設計メモ §4.3)
#   末尾HALT命令の実行前トレース = 最後の実ALU命令直後 = 最終状態。
#
# 【ISA実照合済エンコード】(ISA2_3_v231)
#   LDW rD,#imm16 = 0x21 [rD<<4|0] lo hi   (4B, imm16 LE)
#   ADD=0x40 SUB=0x42 AND=0x50 OR=0x52 XOR=0x54  (2B: op [rD<<4|rS])
#   NOT=0x56 (2B: op [rD<<4|0])
#   SHL=0x57 SHR=0x58 SAR=0x59  (2B: op [rD<<4|rS])
#   HALT=0x01 (1B)
#   reg: A=0 B=1 X=2 SP=3 ; FLAGS bit0=Z bit1=N
# =====================================================================
import subprocess, sys, os

CODE_ORG = 0x0100
EMU = './emu23'

# --- レジスタ番号 (ISA実照合) ---
A, B, X = 0, 1, 2

# --- 命令エンコーダ (ISAに無い命令は絶対に作らない) ---
def ldw_imm(rd, imm):
    """LDW rD,#imm16 = 21 [rd<<4|0] lo hi"""
    return [0x21, (rd << 4) & 0xF0, imm & 0xFF, (imm >> 8) & 0xFF]

def alu_rr(op, rd, rs):
    """2バイトALU reg-reg: op [rd<<4|rs]"""
    return [op, ((rd << 4) | (rs & 0x0F)) & 0xFF]

OP = {'ADD':0x40, 'SUB':0x42, 'AND':0x50, 'OR':0x52, 'XOR':0x54,
      'NOT':0x56, 'SHL':0x57, 'SHR':0x58, 'SAR':0x59}
HALT = [0x01]

# ---------------------------------------------------------------------
# ベクタ定義
#   各ベクタ: (id, 狙い, [初期化LDW...], (op, rd, rs))
#   rs は NOT では無視(0)。期待値は emu23 実行で取得するのでここには書かない。
# ---------------------------------------------------------------------
VECTORS = [
    # ADD: Z/N境界
    ("ADD_pos",  "Z0N0", [(A,0x0003),(B,0x0005)], ('ADD',A,B)),
    ("ADD_zero", "Z1N0", [(A,0x0001),(B,0xFFFF)], ('ADD',A,B)),
    ("ADD_neg",  "Z0N1", [(A,0x7FFF),(B,0x0001)], ('ADD',A,B)),
    # SUB
    ("SUB_pos",  "Z0N0", [(A,0x0008),(B,0x0003)], ('SUB',A,B)),
    ("SUB_zero", "Z1N0", [(A,0x0005),(B,0x0005)], ('SUB',A,B)),
    ("SUB_neg",  "Z0N1", [(A,0x0000),(B,0x0001)], ('SUB',A,B)),
    # AND
    ("AND_zero", "Z1N0", [(A,0xF0F0),(B,0x0F0F)], ('AND',A,B)),
    ("AND_neg",  "Z0N1", [(A,0xFFFF),(B,0x8000)], ('AND',A,B)),
    # OR
    ("OR_pos",   "Z0N0", [(A,0x00F0),(B,0x000F)], ('OR',A,B)),
    ("OR_neg",   "Z0N1", [(A,0x0000),(B,0x8000)], ('OR',A,B)),
    # XOR
    ("XOR_zero", "Z1N0", [(A,0xAAAA),(B,0xAAAA)], ('XOR',A,B)),
    ("XOR_neg",  "Z0N1", [(A,0x0000),(B,0x8000)], ('XOR',A,B)),
    # NOT (単項, rs無視)
    ("NOT_neg",  "Z0N1", [(A,0x0000)],            ('NOT',A,0)),
    ("NOT_zero", "Z1N0", [(A,0xFFFF)],            ('NOT',A,0)),
    # SHL (B=シフト量)
    ("SHL_neg",  "Z0N1", [(A,0x4000),(B,0x0001)], ('SHL',A,B)),
    ("SHL_zero", "Z1N0", [(A,0x8000),(B,0x0001)], ('SHL',A,B)),
    # SHR (論理右)
    ("SHR_pos",  "Z0N0", [(A,0x8000),(B,0x0001)], ('SHR',A,B)),
    ("SHR_zero", "Z1N0", [(A,0x0001),(B,0x0001)], ('SHR',A,B)),
    # SAR (算術右, 符号拡張)
    ("SAR_neg",  "Z0N1", [(A,0x8000),(B,0x0001)], ('SAR',A,B)),
    ("SAR_pos",  "Z0N0", [(A,0x4000),(B,0x0001)], ('SAR',A,B)),
]

def build_code(inits, alu):
    """初期化LDW群 + ALU命令 + HALT の機械語列を返す"""
    code = []
    for (rd, imm) in inits:
        code += ldw_imm(rd, imm)
    op, rd, rs = alu
    code += alu_rr(OP[op], rd, rs)
    code += HALT
    return code

def make_image(code):
    """リセットベクタ規約に従い 64KBイメージを作り、末尾まで返す"""
    img = bytearray(0x10000)
    img[0x0000] = CODE_ORG & 0xFF
    img[0x0001] = (CODE_ORG >> 8) & 0xFF
    img[CODE_ORG:CODE_ORG+len(code)] = bytes(code)
    return bytes(img[:CODE_ORG+len(code)])

def write_hex(hexpath, code):
    """$readmemh 用hexを出力。リセットベクタ(@0)とコード(@CODE_ORG)を
       @アドレス形式で最小記述。1バイト=1行(8bit幅mem[]に対応)。
       bin(emu23用)と同一バイト列から生成 = 単一ソース(偽合格防止)。"""
    with open(hexpath, 'w') as f:
        # リセットベクタ 2byte @0x0000
        f.write("@0000\n")
        f.write(f"{CODE_ORG & 0xFF:02X}\n")
        f.write(f"{(CODE_ORG >> 8) & 0xFF:02X}\n")
        # コード本体 @CODE_ORG
        f.write(f"@{CODE_ORG:04X}\n")
        for b in code:
            f.write(f"{b:02X}\n")

def emu_golden(binpath, n_steps):
    """emu23を -n で実行し、HALT直前(最終)トレース行から状態を取得。
       戻り: dict(PC,SP,F,A,B,X) すべてint。取得失敗はNone。"""
    r = subprocess.run([EMU, binpath, '-n', str(n_steps)],
                       capture_output=True, text=True, timeout=10)
    last = None
    for line in r.stdout.splitlines():
        line = line.strip()
        # トレース行: "PC=0100 SP=FC7E F=00 A=0000 B=0000 X=0000"
        if line.startswith('PC=') and ' F=' in line:
            fields = {}
            for tok in line.split():
                if '=' in tok:
                    k, v = tok.split('=', 1)
                    try: fields[k] = int(v, 16)
                    except ValueError: pass
            if all(k in fields for k in ('PC','SP','F','A','B','X')):
                last = fields
    return last

def main():
    if not os.path.exists(EMU):
        print(f"ERROR: {EMU} not found. build emu23 first.", file=sys.stderr)
        sys.exit(1)

    os.makedirs('v2a', exist_ok=True)
    golden_rows = []
    print(f"{'ID':<10} {'狙い':<6} {'A':>6} {'B':>6} {'X':>6} {'F':>4}  判定")
    print('-'*52)

    for (vid, want, inits, alu) in VECTORS:
        code = build_code(inits, alu)
        img = make_image(code)
        binpath = f'v2a/{vid}.bin'
        with open(binpath, 'wb') as f:
            f.write(img)
        # RTL TB用 hex (bin と同一 code から生成 = 単一ソース)
        write_hex(f'v2a/{vid}.hex', code)

        # 命令数 = LDW数 + ALU1 + HALT1。-n はHALT行まで出すよう +2 余裕。
        n_instr = len(inits) + 2
        g = emu_golden(binpath, n_instr + 2)
        if g is None:
            print(f"{vid:<10} {want:<6}  *** emu golden取得失敗 ***")
            continue

        # FLAGS下位8bitのZ/Nを抽出 (bit0=Z bit1=N)
        z = g['F'] & 0x01
        n = (g['F'] >> 1) & 0x01
        got = f"Z{z}N{n}"
        verdict = "OK" if got == want else f"NG(got {got})"
        print(f"{vid:<10} {want:<6} {g['A']:6X} {g['B']:6X} "
              f"{g['X']:6X} {g['F']:4X}  {verdict}")

        golden_rows.append((vid, g['PC'], g['SP'], g['F'],
                            g['A'], g['B'], g['X'], want, got))

    # RTL TB用 期待値テーブルを出力 (hex, 1ベクタ1行)
    with open('v2a/golden_v2a.txt', 'w') as f:
        f.write("# V2-a golden (from emu23 v1.09). "
                "id PC SP F A B X want got\n")
        for row in golden_rows:
            vid, pc, sp, fl, a, b, x, want, got = row
            f.write(f"{vid} {pc:04X} {sp:04X} {fl:02X} "
                    f"{a:04X} {b:04X} {x:04X} {want} {got}\n")

    # RTL TB用 期待値hex: 1ベクタ4ワード(A,B,X,F)を順に並べる。
    #   TBは $readmemh で読み、idx*4+{0,1,2,3} で参照。手転記を排除(偽合格防止)。
    with open('v2a/expected_v2a.hex', 'w') as f:
        for row in golden_rows:
            vid, pc, sp, fl, a, b, x, want, got = row
            f.write(f"{a:04X}\n{b:04X}\n{x:04X}\n{fl:04X}\n")

    # RTL TB用 ベクタ名リスト(SV $readmemh はファイル名を実行時に組めないため、
    #   ベクタ数とIDを別ファイルに出し、TBはヒアで列挙)。数の一致確認用。
    with open('v2a/veclist_v2a.txt', 'w') as f:
        for row in golden_rows:
            f.write(f"{row[0]}\n")

    print('-'*52)
    print(f"golden written: v2a/golden_v2a.txt ({len(golden_rows)} vectors)")
    print(f"expected hex : v2a/expected_v2a.hex ({len(golden_rows)*4} words)")

if __name__ == '__main__':
    main()
