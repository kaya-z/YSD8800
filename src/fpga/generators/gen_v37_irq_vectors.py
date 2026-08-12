#!/usr/bin/env python3
# =====================================================================
# gen_v37_irq_vectors.py  v0.1  (2026-07-12)
#   V3.7 S5: CPU結合検証（YSD8004 → IRQ1 → 割込受理シーケンス）
#
# 【方式】案①（レビュー承認・本チャットで判断）
#   emu23 では YSD8004 に外から割込を上げる手段が無い（ysd8004_raise は
#   内部関数で、実デバイス=UART/Storage が呼ぶ。V4/V6未実装のため使えない）。
#   一方 RTL の YSD8004 は irq_src_* ポートをTBから直接叩ける。
#   → 「割込の起こし方」が非対称なので、以下に分割して検証する:
#
#     (a) CPU の【割込受理シーケンス】…★emu23黄金で厳密照合★
#         emu23: SYSCALL(0x05) で irq_pending=4 → vec=rd16(4*2)=$0008
#         RTL  : YSD8004経由IRQ1  → irq_pending=2 → vec=rd16(2*2)=$0004
#         ベクタ$0004と$0008の【両方】を同一ハンドラ($0200)に向けることで、
#         起動経路が違っても【最終レジスタ状態が一致する】ことを照合できる。
#         受理シーケンス自体(push PC→push FLAGS→IE=0→vec→IRET)は同一。
#
#     (b) YSD8004 の内部動作 … S3単体TB(tb_ysd8004_v0_1)で検証済(21/21)
#     (c) 接続(irq1_o→irq_in=2→vec=$0004) … 本TBのRTL側で確認
#
# 【★突合対象から A を除外する★】
#   ハンドラは IRQ_STAT($FCB2)を A に読む。
#     emu23: デバイス未発火のため IRQ_STAT = 0x00 → A=0x0000
#     RTL  : YSD8004が発火済のため IRQ_STAT = 0x01 → A=0x0001
#   これは【意図した差】であり不一致ではない。よって A は突合しない。
#   → 突合対象: B / X / SP / FLAGS （X=$BEEF がハンドラ到達の痕跡）
#   RTL側では A=0x0001 であることを別途チェックする（YSD8004読出の実証）。
#
# 【黄金参照】emu23 v1.09
#   受理: L1176-1188  push16(PC)→push16(FLAGS)→IE=0→PC=rd16(irq*2)
#   IRET: L1213       FLAGS←pop / PC←pop
#   YSD8004: L294-295 IRQ_STAT=$FCB2 / IRQ_MASK=$FCB4
# =====================================================================
import subprocess, sys, os

EMU = './emu23'
OUTDIR = 'v37irq'
A, B, X, SP = 0, 1, 2, 3

CODE_ORG    = 0x0100
HANDLER_ORG = 0x0200

IRQ_STAT = 0xFCB2
IRQ_MASK = 0xFCB4

# ---- 命令エンコード（emu23_v109.c 実照合・KY39）----
def ldw_imm(rd, imm):  return [0x21, (rd << 4) & 0xF0, imm & 0xFF, (imm >> 8) & 0xFF]
def ldb_imm(r, addr):  return [0x1F, 0x10 if r == A else 0x12, addr & 0xFF, (addr >> 8) & 0xFF]
def stb_imm(r, addr):  return [0x1F, 0x14 if r == A else 0x16, addr & 0xFF, (addr >> 8) & 0xFF]
EI      = [0x02]
DI      = [0x03]
IRET    = [0x04]
SYSCALL = [0x05]
HALT    = [0x01]


def build_image():
    """64KB イメージを組み立てる。ベクタ/本体/ハンドラを配置。"""
    img = [0x00] * 0x10000

    # ---- ベクタテーブル ($0000-$000F, 16bit LE) ----
    #   vec = rd16(irq * 2)
    #     irq=0 : $0000  reset
    #     irq=1 : $0002  timer
    #     irq=2 : $0004  ★IRQ1 (YSD8004)★
    #     irq=3 : $0006  align
    #     irq=4 : $0008  ★SYSCALL★
    def put16(addr, val):
        img[addr]     = val & 0xFF
        img[addr + 1] = (val >> 8) & 0xFF

    put16(0x0000, CODE_ORG)       # reset → 本体
    put16(0x0002, HANDLER_ORG)    # timer  (未使用)
    put16(0x0004, HANDLER_ORG)    # ★IRQ1  → 共通ハンドラ★
    put16(0x0006, HANDLER_ORG)    # align  (未使用)
    put16(0x0008, HANDLER_ORG)    # ★SYSCALL → 共通ハンドラ★

    # ---- 本体 ($0100) ----
    body = []
    body += ldw_imm(SP, 0x0400)      # SP初期化（KY: SP初期値不一致対策）
    body += ldw_imm(B,  0x1234)      # Bに既知値（IRET後も保持される事の確認）
    body += ldw_imm(X,  0x0000)      # Xクリア（ハンドラ到達で$BEEFになる）
    body += ldw_imm(A,  0x0000)      # IRQ_MASK <- 0x0000 (全許可)
    body += stb_imm(A, IRQ_MASK)     #   ★リセット値0x04を0にする★
    body += EI                       # 割込許可 (IE=1)
    #  ここで割込が入る:
    #    emu23 : SYSCALL で自ら起こす
    #    RTL   : TBが YSD8004 に irq_src_uart_rx パルスを与える
    #            (RTL用イメージでは SYSCALL を NOP相当=DI/EI に置換しない。
    #             同一イメージを使い、RTLでは SYSCALL 到達前に割込が入る)
    body += SYSCALL                  # ← emu23 の割込起点
    body += HALT

    for i, b in enumerate(body):
        img[CODE_ORG + i] = b

    # ---- 共通ハンドラ ($0200) ----
    #   IRQ_STAT を読む → Write-to-Clear → 痕跡X=$BEEF → IRET
    hnd = []
    hnd += ldb_imm(A, IRQ_STAT)      # A <- IRQ_STAT
                                     #   emu23: 0x00 / RTL: 0x01 ← 意図した差
    hnd += stb_imm(A, IRQ_STAT)      # Write-to-Clear（読んだ値をそのまま書く）
                                     #   RTL: 0x01書込でbit0クリア → irq1_o が下がる
    hnd += ldw_imm(X, 0xBEEF)        # ★ハンドラ到達の痕跡★
    hnd += IRET                      # FLAGS←pop / PC←pop
    for i, b in enumerate(hnd):
        img[HANDLER_ORG + i] = b

    return img, len(body), len(hnd)


def run_emu(binpath, nsteps=200):
    """emu23 を走らせて最終レジスタ状態を得る（-q なしでtrace取得）"""
    r = subprocess.run([EMU, binpath, '-n', str(nsteps)],
                       capture_output=True, text=True, timeout=30)
    return r.stdout + r.stderr


def parse_final(out):
    """emu23 の最終状態行から A/B/X/SP/FLAGS を抜く

    emu23 v1.09 実出力形式（実照合）:
        PC=0116 SP=0400 F=81 A=0000 B=1234 X=BEEF
        PC=0117 SP=0400 FLAGS=81 A=0000 B=1234 X=BEEF  |
    ※ SP/F が A/B/X より前に出る。F= と FLAGS= の両形式がある。
    """
    import re
    for line in reversed(out.splitlines()):
        m = re.search(r'SP=([0-9a-fA-F]{4})\s+F(?:LAGS)?=([0-9a-fA-F]{2,4})\s+'
                      r'A=([0-9a-fA-F]{4})\s+B=([0-9a-fA-F]{4})\s+X=([0-9a-fA-F]{4})',
                      line)
        if m:
            sp = int(m.group(1), 16)
            f  = int(m.group(2), 16)
            a  = int(m.group(3), 16)
            b  = int(m.group(4), 16)
            x  = int(m.group(5), 16)
            return a, b, x, sp, f
    return None, None, None, None, None


def main():
    os.makedirs(OUTDIR, exist_ok=True)

    img, blen, hlen = build_image()
    print("body   : %d bytes @ $%04X" % (blen, CODE_ORG))
    print("handler: %d bytes @ $%04X" % (hlen, HANDLER_ORG))

    # ---- emu23 用 bin ----
    binpath = os.path.join(OUTDIR, 'v37irq.bin')
    with open(binpath, 'wb') as f:
        f.write(bytes(img))

    out = run_emu(binpath)
    # IRQ受理のログが出ているか（黄金の証拠）
    acc = [l for l in out.splitlines() if 'IRQ' in l and 'accepted' in l]
    print("--- emu23 IRQ accept log ---")
    for l in acc:
        print("  " + l.strip())
    if not acc:
        print("  (none)  ★SYSCALLが受理されていない可能性★")

    a, b, x, sp, fl = parse_final(out)
    print("--- emu23 golden (final) ---")
    print("  A=%04x B=%04x X=%04x SP=%04x F=%s"
          % (a, b, x, sp, ('%02x' % fl) if fl is not None else '??'))

    if x != 0xBEEF:
        print("!! ERROR: X != BEEF  → ハンドラに到達していない")
        print(out[-1500:])
        sys.exit(1)

    # ---- RTL 用 hex (PSRAMモデル $readmemh 用: 1バイト/行) ----
    hexpath = os.path.join(OUTDIR, 'v37irq.hex')
    with open(hexpath, 'w') as f:
        for byte in img:
            f.write("%02x\n" % byte)

    # ---- 黄金値をテキストで残す ----
    gpath = os.path.join(OUTDIR, 'golden_v37irq.txt')
    with open(gpath, 'w') as f:
        f.write("# golden_v37irq.txt  (emu23 v1.09 / 2026-07-12)\n")
        f.write("# V3.7 S5: 割込受理シーケンス黄金値（emu23はSYSCALL起点 vec=$0008）\n")
        f.write("# ★A は突合対象外★ (emu23:IRQ_STAT=00 / RTL:IRQ_STAT=01 = 意図した差)\n")
        f.write("A  %04x   # 参考値のみ（突合しない）\n" % a)
        f.write("B  %04x\n" % b)
        f.write("X  %04x\n" % x)
        f.write("SP %04x\n" % sp)
        f.write("F  %02x\n" % (fl if fl is not None else 0))

    print("golden written: %s" % gpath)
    print("hex    written: %s (%d bytes)" % (hexpath, len(img)))
    print()
    print("=== RTL TB が照合すべき期待値（A除く）===")
    print("  B  = %04x" % b)
    print("  X  = %04x   ★ハンドラ到達の痕跡★" % x)
    print("  SP = %04x   ★IRETでpush2回分が戻っている★" % sp)
    print("  F  = %02x" % (fl if fl is not None else 0))
    print("  A  = 0001   ★RTL固有: YSD8004 IRQ_STAT bit0 を読んだ値★")


if __name__ == '__main__':
    main()
