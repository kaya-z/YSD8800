#!/usr/bin/env python3
# gen_v4_uart_vectors.py  v1.0  (2026-07-12)
# ============================================================
#  FPGA V4 / S5(a): UART TX系・STAT系 emu23協調等価ベクタ生成
#
#  【方針】(S5-ISSUE-1 の承認済み戦略)
#    (a) TX系・STAT系 → emu23協調等価（本スクリプト）
#    (b) RX系・IRQ系  → プロパティ検証（TB側で直接実施）
#
#  【なぜRXを含めないか】
#    emu23 の RX は 256サイクル周期ポーリング (emu23_v109.c L486)
#      if ((current_cycle & 0xFF) == 0) poll_rx_fn();
#    であり、-i FILE を使っても RX 到来サイクルは 256 境界に量子化される。
#    RTL の rx_valid_i は任意サイクルで打てるため、両者のタイミングは
#    構造的に一致しない。→ 最終状態比較(協調等価)は RX に適用不可。
#
#  【★確定設計#8: MMIOレジスタの上位バイト単独アクセス禁止★】
#    $FC81/$FC83/$FC85/$FC87 および UART_BAUD($FC86) の LDB 単独アクセスは
#    ベクタに含めない（yuios_memmap 規約違反 = 未定義動作。KY47）
#
#  【エンコード】emu23_v109.c 実照合（KY39）
#    LDW rD,#imm16 : 0x21 [rD<<4]         imm_lo imm_hi
#    STB rS,[abs]  : 0x1F 0x14(A)/0x16(B) addr_lo addr_hi
#    LDB rD,[abs]  : 0x1F 0x10(A)/0x12(B) addr_lo addr_hi
#    MOV rD,rS     : 0x20 [rD<<4|rS]
#    ANDI?         : ★存在しない★ → AND rD,rS を使う (0x48)  ※要実照合
#    CMPI rD,#imm16: 0x45 [rD<<4] imm_lo imm_hi   (L1409)
#    BEQ  rel16    : 0x61 off_lo off_hi   ★基準=off読取後のPC★ (L1509)
#    BNE  rel16    : 0x62 off_lo off_hi                        (L1514)
#    HALT          : 0x01
# ============================================================

import subprocess, sys, os

CODE_ORG = 0x0100
EMU = './emu23'
A, B, X, SP = 0, 1, 2, 3
SP_INIT = 0x0400

UART_TX   = 0xFC80
UART_RX   = 0xFC82
UART_STAT = 0xFC84

OUTDIR = 'v4uart'

def ldw_imm(rd, imm):
    return [0x21, (rd << 4) & 0xF0, imm & 0xFF, (imm >> 8) & 0xFF]

def ldb_abs(reg_ab, addr):
    sub = 0x10 if reg_ab == A else 0x12
    return [0x1F, sub, addr & 0xFF, (addr >> 8) & 0xFF]

def stb_abs(reg_ab, addr):
    sub = 0x14 if reg_ab == A else 0x16
    return [0x1F, sub, addr & 0xFF, (addr >> 8) & 0xFF]

def mov(rd, rs):
    return [0x20, ((rd << 4) & 0xF0) | (rs & 0x0F)]

def cmpi(rd, imm):
    return [0x45, (rd << 4) & 0xF0, imm & 0xFF, (imm >> 8) & 0xFF]

def addi(rd, imm):
    return [0x41, (rd << 4) & 0xF0, imm & 0xFF, (imm >> 8) & 0xFF]

def beq(off):
    return [0x61, off & 0xFF, (off >> 8) & 0xFF]

def bne(off):
    return [0x62, off & 0xFF, (off >> 8) & 0xFF]

HALT = [0x01]

VECTORS = []

# ------------------------------------------------------------------
# #1 UART_STAT_READ : リセット直後の UART_STAT == 0x01 (KY45)
#    ★0x00 だと送信不能になる。ここが V4 最大の落とし穴★
# ------------------------------------------------------------------
VECTORS.append(("UART_STAT_READ",
    "リセット直後 $FC84 = 0x01 (TX_READY=1) ★KY45★",
    ldw_imm(SP, SP_INIT) +
    ldb_abs(A, UART_STAT) +      # A = STAT (期待: 0x0001)
    HALT
))

# ------------------------------------------------------------------
# #2 UART_TX_BASIC : $FC80 書込 → 直後の STAT で TX_READY=0
#    ★V3.7 BUG-1(KY44) を突く: $FC80[1:0] == $FC84[1:0] == 2'b00
#      2bitデコードだと TX 書込が STAT を壊す/STAT 読が TX を読む★
# ------------------------------------------------------------------
VECTORS.append(("UART_TX_BASIC",
    "TX書込直後 TX_READY=0 (STAT=0x00) ★KY44を突く★",
    ldw_imm(SP, SP_INIT) +
    ldw_imm(A, 0x0041) +          # 'A'
    stb_abs(A, UART_TX) +         # $FC80 <= 0x41  (TX_READY=0 になる)
    ldb_abs(B, UART_STAT) +       # B = STAT (期待: 0x0000)
    HALT
))

# ------------------------------------------------------------------
# #3 UART_TX_RECOVER : TX書込 → STATポーリングで TX_READY=1 復帰を待つ
#    emu23: 4167 cycle 後に TX_READY=1 (L344/L491-494)
#    ループ回数を X に数え、復帰したことを A/B で確認する。
# ------------------------------------------------------------------
#   loop:  LDB B,[STAT]     (4B)
#          ADDI X,#1        (4B)
#          CMPI B,#0x0000   (4B)
#          BEQ loop         (3B)   ← Z=1(STAT==0)なら継続
#   BEQ の rel16 基準 = off読取後のPC = loop先頭 + 15
#   loop へ戻る offset = -15
loop_body = ldb_abs(B, UART_STAT) + addi(X, 1) + cmpi(B, 0x0000) + beq(-15)
assert len(loop_body) == 15, len(loop_body)

VECTORS.append(("UART_TX_RECOVER",
    "TX書込後 STATポーリングで TX_READY=1 復帰を待つ (4167cyc)",
    ldw_imm(SP, SP_INIT) +
    ldw_imm(X, 0x0000) +
    ldw_imm(A, 0x0042) +          # 'B'
    stb_abs(A, UART_TX) +
    loop_body +                   # 復帰まで回る
    HALT                          # 抜けた時 B=0x0001(TX_READY=1)
))

# ------------------------------------------------------------------
# #4 UART_TX_TWICE : 連続2回送信（1回目復帰待ち→2回目）
#    TX_READY の再アサート/再クリアが正しく繰り返せることの確認
# ------------------------------------------------------------------
VECTORS.append(("UART_TX_TWICE",
    "TX 2回連続送信（復帰待ちを挟む）",
    ldw_imm(SP, SP_INIT) +
    ldw_imm(X, 0x0000) +
    ldw_imm(A, 0x0031) +          # '1'
    stb_abs(A, UART_TX) +
    loop_body +                   # 1回目復帰待ち
    ldw_imm(A, 0x0032) +          # '2'
    stb_abs(A, UART_TX) +         # 2回目送信 → TX_READY=0
    ldb_abs(B, UART_STAT) +       # B = 0x0000 のはず
    HALT
))

# ------------------------------------------------------------------
# #5 UART_STAT_WTC_NOP : RX_READY=0 の状態で W2C(bit1=1)しても無害
#    かつ bit0(TX_READY)書込は【完全無視】される (emu23 L521-526)
#    ★ここで bit0 に 0 を書いても TX_READY が落ちないことを確認する★
# ------------------------------------------------------------------
VECTORS.append(("UART_STAT_WTC_NOP",
    "STAT に 0x02 書込 → RX_READY未セットなので無害。TX_READY保持",
    ldw_imm(SP, SP_INIT) +
    ldw_imm(A, 0x0002) +          # bit1=1 (W2C)
    stb_abs(A, UART_STAT) +
    ldb_abs(B, UART_STAT) +       # B = 0x0001 のはず（TX_READY保持）
    HALT
))

# ------------------------------------------------------------------
# #6 UART_STAT_WTC_BIT0_IGNORE : STAT に 0x00 を書いても TX_READY は落ちない
#    emu23 L525: bit0 への書き込みは無視（HW自動管理）
# ------------------------------------------------------------------
VECTORS.append(("UART_STAT_WTC_BIT0_IGNORE",
    "STAT に 0x00 書込 → bit0書込は無視され TX_READY=1 のまま",
    ldw_imm(SP, SP_INIT) +
    ldw_imm(A, 0x0000) +
    stb_abs(A, UART_STAT) +       # bit0=0 を書いてみる → 無視されるべき
    ldb_abs(B, UART_STAT) +       # B = 0x0001 のはず
    HALT
))

# ------------------------------------------------------------------
# #7 UART_TX_STAT_ALIAS : ★KY44 決定打★
#    $FC80(TX) と $FC84(STAT) は下位2bitが同一(2'b00)。
#    TX に 0xFF を書いた【直後】に STAT を読み、
#    STAT が 0xFF ではなく 0x00(TX_READY=0) であることを確認する。
#    2bitデコードなら STAT が 0xFF に化ける → 必ず落ちる。
# ------------------------------------------------------------------
VECTORS.append(("UART_TX_STAT_ALIAS",
    "TX に 0xFF 書込 → STAT は 0x00。2bitデコードなら 0xFF に化ける ★KY44★",
    ldw_imm(SP, SP_INIT) +
    ldw_imm(A, 0x00FF) +
    stb_abs(A, UART_TX) +
    ldb_abs(B, UART_STAT) +       # B = 0x0000 (0x00FF ではない)
    HALT
))


def run_emu23(binpath, n_steps):
    """emu23 を実行し最終トレース行から状態取得。
       ★TX書込は putchar するため stdout にゴミが混ざる。
         トレース行は 'PC=' 始まりなので行単位で選別すれば安全。★"""
    r = subprocess.run([EMU, binpath, '-n', str(n_steps)],
                       stdin=subprocess.DEVNULL,
                       capture_output=True, text=True,
                       errors='replace',   # ★TX出力に 0xFF 等の非UTF-8が混じる★
                       timeout=30)
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
            if all(k in fields for k in ('PC','SP','F','A','B','X')):
                last = fields
    if last is None:
        return None, r.stdout + r.stderr
    return (last['A'], last['B'], last['X'], last['SP'], last['F']), r.stdout


def main():
    if not os.path.exists(EMU):
        print(f"ERROR: {EMU} not found. build emu23 first.", file=sys.stderr)
        sys.exit(1)
    os.makedirs(OUTDIR, exist_ok=True)

    golden_lines = []
    for vid, (name, desc, code) in enumerate(VECTORS):
        # バイナリ生成（CODE_ORG=0x0100 に配置）
        img = bytearray(CODE_ORG) + bytearray(code)
        binpath = os.path.join(OUTDIR, f"{name}.bin")
        with open(binpath, 'wb') as f:
            f.write(img)

        # hexファイル（TB の $readmemh 用。1行1バイト）
        hexpath = os.path.join(OUTDIR, f"{name}.hex")
        with open(hexpath, 'w') as f:
            for bt in img:
                f.write("%02x\n" % bt)

        # emu23 実行（ステップ数は十分大きく取る。TX復帰ループが長い）
        n_instr = 20000
        g, out = run_emu23(binpath, n_instr)
        if g is None:
            print(f"!! [{vid} {name}] emu23 failed")
            print(out[:400])
            sys.exit(1)
        a, b, x, sp, f_ = g
        print(f"[{vid} {name:26s}] A={a:04X} B={b:04X} X={x:04X} SP={sp:04X} F={f_:02X}  ({desc})")
        golden_lines.append(f"{vid}: A={a:04X} B={b:04X} X={x:04X} SP={sp:04X} F={f_:02X}")

    with open(os.path.join(OUTDIR, 'golden_v4uart.txt'), 'w') as f:
        f.write("\n".join(golden_lines) + "\n")

    # expected hex（A,B,X,F を4ワード×ベクタ数）
    with open(os.path.join(OUTDIR, 'expected_v4uart.hex'), 'w') as f:
        for line in golden_lines:
            d = dict(tok.split('=') for tok in line.split(': ')[1].split())
            f.write("%s\n%s\n%s\n%s\n" % (d['A'], d['B'], d['X'], d['F'].zfill(4)))

    print()
    print(f"golden written: {OUTDIR}/golden_v4uart.txt ({len(VECTORS)} vectors)")
    print(f"expected hex  : {OUTDIR}/expected_v4uart.hex ({len(VECTORS)*4} words)")


if __name__ == '__main__':
    main()
