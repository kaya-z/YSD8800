#!/usr/bin/env python3
# =====================================================================
# gen_v3_boundary_vectors.py  v0.1  (2026-07-11)
#   V3残り検証: 境界アドレス($FC7F RAM側/$FC80 MMIO側)実CPUアクセス、
#   および JSR/RET/BEQ を含む複数命令クラス連続実行シーケンス。
#
# 【役割】(gen_v2/v3_vectors.py同様の単一ソース方針・KY34偽合格防止)
#   - 簡易2パスアセンブラでラベル解決(手計算オフセットのミスを排除)
#   - emu23で実行し黄金の最終状態を自動取得
#   - RTL TB用hexを出力
#
# 【注意】emu23はMMIOに実デバイス応答(STAT等)を返すため、
#   $FC80書込み自体はSTB到達を確認する用途に限り、emu23側の
#   MMIO内部状態(UART等)は突合対象にしない。本ベクタはA/B/X/SPの
#   CPUレジスタ最終状態のみをemu23と突合する
#   (指示No.6の精神: MMIO読み出し値そのものは突合しない)。
# =====================================================================
import subprocess, sys, os

CODE_ORG = 0x0100
EMU = './emu23'
A, B, X, SP = 0, 1, 2, 3

class Asm:
    def __init__(self):
        self.instrs = []   # list of (label_or_None, length_or_None, encoder_fn_or_None)
        self.labels = {}

    def label(self, name):
        self.instrs.append((name, None, None))

    def emit(self, length, fn):
        self.instrs.append((None, length, fn))

    def ldw_imm(self, rd, imm):
        self.emit(4, lambda addr: [0x21, (rd << 4) & 0xF0, imm & 0xFF, (imm >> 8) & 0xFF])

    def addi(self, rd, imm):
        self.emit(4, lambda addr: [0x41, (rd << 4) & 0xF0, imm & 0xFF, (imm >> 8) & 0xFF])

    def cmp_rr(self, rd, rs):
        self.emit(2, lambda addr: [0x44, ((rd << 4) | (rs & 0x0F)) & 0xFF])

    def jsr(self, target_label):
        def f(addr):
            t = self.labels[target_label]
            return [0x68, t & 0xFF, (t >> 8) & 0xFF]
        self.emit(3, f)

    def ret(self):
        self.emit(1, lambda addr: [0x69])

    def beq(self, target_label):
        def f(addr):
            # rel16は「オペランド2byte読了後のPC」基準(emu23実照合)
            base = addr + 3
            t = self.labels[target_label]
            off = (t - base) & 0xFFFF
            return [0x61, off & 0xFF, (off >> 8) & 0xFF]
        self.emit(3, f)

    def stb_imm(self, reg_ab, addr_val):
        sub = 0x14 if reg_ab == A else 0x16
        self.emit(4, lambda addr: [0x1F, sub, addr_val & 0xFF, (addr_val >> 8) & 0xFF])

    def ldb_imm(self, reg_ab, addr_val):
        sub = 0x10 if reg_ab == A else 0x12
        self.emit(4, lambda addr: [0x1F, sub, addr_val & 0xFF, (addr_val >> 8) & 0xFF])

    def halt(self):
        self.emit(1, lambda addr: [0x01])

    def assemble(self):
        # パス1: 各命令の固定長(ラベル解決不要)からアドレスを確定
        addr = CODE_ORG
        for lbl, ln, fn in self.instrs:
            if fn is None:
                if lbl is not None:
                    self.labels[lbl] = addr
            else:
                addr += ln
        # パス2: ラベル確定後に本エンコード
        addr = CODE_ORG
        code = []
        for lbl, ln, fn in self.instrs:
            if fn is None:
                continue
            b = fn(addr)
            assert len(b) == ln, f"length mismatch at {addr:04x}: got {len(b)} expected {ln}"
            code += b
            addr += len(b)
        return bytes(code)

def build_program():
    a = Asm()
    a.ldw_imm(SP, 0x0400)
    a.ldw_imm(A, 0x0005)
    a.jsr("sub_inc")                      # A += 1 (via subroutine, JSR/RET経路)
    a.stb_imm(A, 0xFC7F)                  # RAM境界(最終byte)へ書込
    a.ldw_imm(B, 0x0000)
    a.ldb_imm(B, 0xFC7F)                  # 読み戻し(RAM側と一致するはず)
    a.stb_imm(A, 0xFC80)                  # MMIO境界(先頭byte)へ書込(スタブは無視するだけ)
    a.ldw_imm(X, 0x0000)
    a.cmp_rr(A, A)                        # 常にZ=1
    a.beq("skip")                         # 分岐成立のはず
    a.ldw_imm(X, 0xDEAD)                  # 分岐成立ならスキップされるべき命令
    a.label("skip")
    a.ldw_imm(X, 0xCAFE)                  # 分岐後の合流地点(必ず実行)
    a.halt()
    # サブルーチン本体
    a.label("sub_inc")
    a.addi(A, 1)
    a.ret()
    return a.assemble()

def assemble_image(code):
    img = bytearray(65536)
    img[0] = CODE_ORG & 0xFF
    img[1] = (CODE_ORG >> 8) & 0xFF
    img[CODE_ORG:CODE_ORG+len(code)] = code
    return img

def run_emu23(binpath, n_steps):
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
    os.makedirs('v3boundary', exist_ok=True)
    code = build_program()
    img = assemble_image(code)
    with open('v3boundary/BOUNDARY_JSR_BEQ.bin', 'wb') as f:
        f.write(img)
    with open('v3boundary/BOUNDARY_JSR_BEQ.hex', 'w') as f:
        for byte in img:
            f.write(f'{byte:02x}\n')
    g = run_emu23('v3boundary/BOUNDARY_JSR_BEQ.bin', len(code) + 10)
    if g is None:
        print("ERROR: emu golden取得失敗", file=sys.stderr)
        sys.exit(1)
    a, b, x, sp, f_ = g
    print(f"BOUNDARY_JSR_BEQ: A={a:04X} B={b:04X} X={x:04X} SP={sp:04X} F={f_:02X}")
    with open('v3boundary/golden_v3boundary.txt', 'w') as f:
        f.write(f"BOUNDARY_JSR_BEQ: A={a:04X} B={b:04X} X={x:04X} SP={sp:04X} F={f_:02X}\n")
    with open('v3boundary/expected_v3boundary.hex', 'w') as f:
        for w in (a, b, x, sp, f_):
            f.write(f'{w:04x}\n')
    print("golden written: v3boundary/golden_v3boundary.txt")

if __name__ == '__main__':
    main()
