#!/usr/bin/env python3
# =====================================================================
# gen_v35_mmu_vectors.py  v0.2  (2026-07-11)
#   V3.5: MMU有効時の外部観測等価検証ベクタ生成器
#
# 【改版履歴】
#   v0.1 (2026-07-11) 新規作成。6ベクタ定義。
#   v0.2 (2026-07-11) ★不具合修正★
#        - MMU操作ヘルパ(set_ptr/mmu_on/mmu_off)がAレジスタを破壊するため、
#          #5 MMU_PTR_RW / #6 MMU_MMIO_BYPASS で読んだPTR[7]の値が
#          最終状態に残らなかった。
#        - mov(X,A) による退避を追加(MOV=0x20 [rD<<4|rS] 実照合済)。
#        - ヘルパに「A破壊」警告コメントを追加(再発防止)。
#        - 突合対象: #5 X=$0055 / #6 X=$0055,B=$3C3C
#
# 【役割】(gen_v2/gen_v3同様の単一ソース方針・KY34偽合格防止)
#   - emu23 v1.09 を --mmu 付きで実行し黄金の最終状態を自動取得
#   - RTL TBが読む期待値テーブル(hex)を出力
#
# 【★MMU設計書 v1.1.0 の遵守事項★】(v3_5_design_memo_v0_2.md §5.2)
#   §9-1: PTR[0](コードページ)を変更してからMMU ONにしてはならない。
#         => page4/page5 のみリマップする。page0には触れない。
#   §9-2: emu23 --mmu は phys_mem を $FF 初期化する(L1851実照合)。
#         MMU ON前に対象物理ページを $00 クリアしないと偽FAILになる。
#   §9-3: MCR=1にした瞬間から命令フェッチも変換される。
#         page0のコードはPTR[0]=0(恒等)のままなので安全。
#
# 【MMIO協調ベクタ除外原則】(レビュー回答書 §4)
#   突合対象はCPUレジスタ(A/B/X/SP/F)の最終状態のみ。
#   MMUレジスタ($FF00-$FF10)以外のMMIOには一切触れない。
#
# 【SP初期値の中和】(V2-d方式)
#   全ベクタ先頭に LDW SP,#imm16 を明示挿入。
#
# 【エンコード】(emu23_v109.c実照合・gen_v3_mem_vectors.pyと同一)
#   LDW rD,#imm16  = 0x21 [rD<<4] lo hi
#   LDW rD,[imm16] = 0x22 [rD<<4] lo hi
#   STW rS,[imm16] = 0x23 [rS]    lo hi
#   LDB A,[imm16]  = 0x1F 0x10 lo hi  / LDB B = 0x1F 0x12
#   STB A,[imm16]  = 0x1F 0x14 lo hi  / STB B = 0x1F 0x16
#   HALT           = 0x01
#   reg: A=0 B=1 X=2 SP=3 ; FLAGS bit0=Z bit1=N
#
# 【MMUレジスタ】PTR[n]=$FF00+n (8bit) / MCR=$FF10 (bit0=EN)
# =====================================================================
import subprocess, sys, os

CODE_ORG = 0x0100
EMU = './emu23'
A, B, X, SP = 0, 1, 2, 3

SP_INIT  = 0x0400
MCR_ADDR = 0xFF10
PTR_BASE = 0xFF00

def ldw_imm(rd, imm):
    return [0x21, (rd << 4) & 0xF0, imm & 0xFF, (imm >> 8) & 0xFF]

def ldw_abs(rd, addr):
    return [0x22, (rd << 4) & 0xF0, addr & 0xFF, (addr >> 8) & 0xFF]

def stw_abs(rs, addr):
    return [0x23, rs & 0x0F, addr & 0xFF, (addr >> 8) & 0xFF]

def ldb_imm(reg_ab, addr):
    sub = 0x10 if reg_ab == A else 0x12
    return [0x1F, sub, addr & 0xFF, (addr >> 8) & 0xFF]

def stb_imm(reg_ab, addr):
    sub = 0x14 if reg_ab == A else 0x16
    return [0x1F, sub, addr & 0xFF, (addr >> 8) & 0xFF]

HALT = [0x01]

def mov(rd, rs):
    """MOV rD,rS = 0x20 [rD<<4 | rS]  (emu23_v109.c L1305-1309 実照合)
       reg id: A=0 B=1 X=2 SP=3       (emu23_v109.c L1104-1111 実照合)"""
    return [0x20, ((rd << 4) & 0xF0) | (rs & 0x0F)]

# =====================================================================
# ★★★ 警告: 以下のMMU操作ヘルパは内部で A レジスタを破壊する ★★★
#
#   set_ptr() / mmu_on() / mmu_off() はいずれも
#     LDW A,#imm16  →  STB A,[MMIO]
#   の2命令列であり、実行後 A の内容は失われる。
#
#   【v0.1の不具合(2026-07-11 発見)】
#     #5/#6 で get_ptr(A,7) により読んだ PTR[7]=$55 が、直後の
#     mmu_on()/mmu_off() に上書きされて最終状態に残らなかった。
#
#   【回避策】
#     読んだ値は mov(X, A) で X へ退避してから MMU操作を呼ぶこと。
#     X は本ヘルパ群では一切使っていないため退避先として安全。
# =====================================================================

# ---- MMU操作ヘルパ(MMUレジスタは8bitなのでSTBを使う) ----
def set_ptr(page, phys_page):
    """★A破壊★"""
    return ldw_imm(A, phys_page) + stb_imm(A, PTR_BASE + page)

def get_ptr(reg_ab, page):
    """指定レジスタに読み込む(Aは破壊しない)"""
    return ldb_imm(reg_ab, PTR_BASE + page)

def mmu_on():
    """★A破壊★"""
    return ldw_imm(A, 0x0001) + stb_imm(A, MCR_ADDR)

def mmu_off():
    """★A破壊★"""
    return ldw_imm(A, 0x0000) + stb_imm(A, MCR_ADDR)

def get_mcr(reg_ab):
    return ldb_imm(reg_ab, MCR_ADDR)

def clear_word(addr):
    """MMU OFF状態(論理=物理)で1ワードを$0000クリア(§9-2)"""
    return ldw_imm(A, 0x0000) + stw_abs(A, addr)

# ---------------------------------------------------------------------
# ベクタ定義
# ---------------------------------------------------------------------
VECTORS = []

# --- #1 MMU_IDENT_ON: PTR恒等のままMCR=1 -> 挙動不変 -------------------
# リセット時PTR[i]=i(恒等写像)なので、MCR=1にしても変換は恒等。
# => 通常のメモリアクセスが従来通り動くこと。
VECTORS.append(("MMU_IDENT_ON", "PTR恒等のままMMU ON→挙動不変",
    ldw_imm(SP, SP_INIT) +
    clear_word(0x0250) +
    mmu_on() +
    ldw_imm(A, 0x1234) + stw_abs(A, 0x0250) +
    ldw_imm(B, 0x0000) + ldw_abs(B, 0x0250) +
    HALT))

# --- #2 MMU_REMAP_P4: PTR[4]=$14 -> 論理$4000 -> 物理$14000 ------------
# §9-2: MMU ONする前に、リマップ先物理$14000をクリアできない
#   (MMU OFFでは論理$4000=物理$4000にしか届かない)。
#   => 書込→読出のround-tripなので、書いた値をそのまま読めばよい。
#      (未初期化$FFの影響を受けない)
VECTORS.append(("MMU_REMAP_P4", "PTR[4]=$14 論理$4000→物理$14000",
    ldw_imm(SP, SP_INIT) +
    set_ptr(4, 0x14) +
    mmu_on() +
    ldw_imm(A, 0x5678) + stw_abs(A, 0x4000) +
    ldw_imm(B, 0x0000) + ldw_abs(B, 0x4000) +
    HALT))

# --- #3 MMU_ISOLATION: MMU ONで書いた値がMMU OFFの物理に漏れない -------
# §9-2 の手順を忠実に踏む:
#   (1) MMU OFF状態で 論理$4000(=物理$4000) を $0000 クリア
#   (2) PTR[4]=$14 にして MMU ON
#   (3) 論理$4000(=物理$14000) に $A5A5 を書く
#   (4) MMU OFF に戻して 論理$4000(=物理$4000) を読む
#   (5) => $0000 のまま(物理$14000とは別物であること)
VECTORS.append(("MMU_ISOLATION", "MMU ON書込が物理$4000に漏れない",
    ldw_imm(SP, SP_INIT) +
    clear_word(0x4000) +
    set_ptr(4, 0x14) +
    mmu_on() +
    ldw_imm(A, 0xA5A5) + stw_abs(A, 0x4000) +
    mmu_off() +
    ldw_imm(B, 0xFFFF) + ldw_abs(B, 0x4000) +
    HALT))

# --- #4 MMU_BOUNDARY: PTR[4]/PTR[5]で $4FFF/$5000 が別ページへ ---------
# 4KB境界をまたぐ2つのアドレスがそれぞれのPTRで独立に変換されること。
# (境界を跨ぐ16bitアクセスは奇数アドレス=align例外のため原理上発生しない
#  => バイトアクセスで個別に確認する。レビュー回答書 §4)
VECTORS.append(("MMU_BOUNDARY", "PTR[4]=$14/PTR[5]=$15 境界個別変換",
    ldw_imm(SP, SP_INIT) +
    set_ptr(4, 0x14) +
    set_ptr(5, 0x15) +
    mmu_on() +
    ldw_imm(A, 0x0011) + stb_imm(A, 0x4FFF) +   # page4末尾 -> 物理$14FFF
    ldw_imm(A, 0x0022) + stb_imm(A, 0x5000) +   # page5先頭 -> 物理$15000
    ldw_imm(A, 0x0000) + ldb_imm(A, 0x4FFF) +   # A=$11 のはず
    ldw_imm(B, 0x0000) + ldb_imm(B, 0x5000) +   # B=$22 のはず
    HALT))

# --- #5 MMU_PTR_RW: PTR/MCRのリードバック ------------------------------
# ★v0.2修正★ mmu_on() が A を破壊するため、PTR[7]の読み値を X へ退避する。
#   突合: X=$0055(PTRリードバック) / B=$0001(MCRリードバック)
VECTORS.append(("MMU_PTR_RW", "PTR/MCRのR/W確認",
    ldw_imm(SP, SP_INIT) +
    set_ptr(7, 0x55) +
    ldw_imm(A, 0x0000) + get_ptr(A, 7) +        # A=$55 のはず
    mov(X, A) +                                 # ★X へ退避(mmu_on()がA破壊)★
    mmu_on() +
    ldw_imm(B, 0x0000) + get_mcr(B) +           # B=$01 のはず
    HALT))

# --- #6 MMU_MMIO_BYPASS: ★レビュー条件★ MMIOは変換を受けない ---------
# MMU ONかつPTR[15](=$F000台)を書き換えた状態で、$FF00台のMMUレジスタに
# アクセスし、変換を受けずに正しく読み書きできることを確認する。
#
# ★狙い(レビュー回答書 §4)★
#   §2の核心「MMIOは変換外」をTBで恒久的に守る。ここが崩れると
#   MMUの自己ロックアウトが起き、しかもMMU ON時にしか顕在化しない
#   (原則63の典型)。
#
# 手順:
#   (1) PTR[15] = $1F にする ($F000台をリマップ = MMUレジスタと同じ論理ページ!)
#   (2) MMU ON
#   (3) この状態で PTR[7] に書き込み、読み返す
#       -> MMIOが変換対象なら $FF07 は物理$1F007 に飛んでMMUレジスタに
#          届かず、読み返しが失敗する(または$FFが返る)
#       -> 変換外なら正しく $55 が読める
#   (4) さらに MCR に書いて MMU OFF に戻せること(自己救済性)を確認
#       -> ここが効かなければMMUを切り戻せない = 自己ロックアウト
#   (5) MMU OFF後、論理$4000(=物理$4000)が読めること(切り戻し成功の証明)
#
# ★v0.2修正★ mmu_off() が A を破壊するため、PTR[7]の読み値を X へ退避する。
#   突合: X=$0055(MMIO非変換の証明) / B=$3C3C(切り戻し成功の証明)
VECTORS.append(("MMU_MMIO_BYPASS", "★MMIO非変換の実証(自己ロックアウト回避)",
    ldw_imm(SP, SP_INIT) +
    clear_word(0x4000) +                        # MMU OFFで物理$4000をクリア
    ldw_imm(A, 0x3C3C) + stw_abs(A, 0x4000) +   # 物理$4000に既知値を置く
    set_ptr(15, 0x1F) +                         # ★PTR[15]=$1F ($F000台をリマップ)★
    mmu_on() +                                  # ★MMU ON★
    set_ptr(7, 0x55) +                          # MMU ON状態でPTR[7]書込
    ldw_imm(A, 0x0000) + get_ptr(A, 7) +        # ★A=$55 が読めるか(変換外の証明)★
    mov(X, A) +                                 # ★X へ退避(mmu_off()がA破壊)★
    mmu_off() +                                 # ★MCRでMMU OFF(自己救済性)★
    ldw_imm(B, 0x0000) + ldw_abs(B, 0x4000) +   # ★B=$3C3C(切り戻し成功の証明)★
    HALT))

# ---------------------------------------------------------------------
def assemble(prog):
    code = bytearray(prog)
    img = bytearray(65536)
    img[0] = CODE_ORG & 0xFF
    img[1] = (CODE_ORG >> 8) & 0xFF
    img[CODE_ORG:CODE_ORG+len(code)] = code
    return img

def run_emu23_mmu(binpath, n_steps):
    """emu23を --mmu 付きで実行し、最終トレース行から状態を取得。
       -q はtrace抑制のため付けない(HANDOVER §7)。"""
    r = subprocess.run([EMU, binpath, '--mmu', '-n', str(n_steps)],
                       capture_output=True, text=True, timeout=20)
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
        return None, r.stdout
    return (last['A'], last['B'], last['X'], last['SP'], last['F']), r.stdout

def main():
    if not os.path.exists(EMU):
        print(f"ERROR: {EMU} not found. build emu23 first.", file=sys.stderr)
        sys.exit(1)

    os.makedirs('v35mmu', exist_ok=True)
    print(f"{'ID':18s} {'狙い':36s} {'A':6s}{'B':6s}{'X':6s}{'SP':6s}{'F':4s}")
    print("-" * 86)

    golden_lines = []
    exp_words = []
    veclist = []

    for vid, purpose, prog in VECTORS:
        img = assemble(prog)
        binpath = f'v35mmu/{vid}.bin'
        hexpath = f'v35mmu/{vid}.hex'
        with open(binpath, 'wb') as f:
            f.write(img)
        with open(hexpath, 'w') as f:
            for byte in img:
                f.write(f'{byte:02x}\n')

        n_instr = len(prog) + 16
        g, out = run_emu23_mmu(binpath, n_instr)
        if g is None:
            print(f"{vid:18s} *** emu golden取得失敗 ***")
            print(out[:500], file=sys.stderr)
            sys.exit(1)
        a, b, x, sp, f_ = g
        print(f"{vid:18s} {purpose:36s} {a:04X}  {b:04X}  {x:04X}  {sp:04X}  {f_:02X}")
        golden_lines.append(f"{vid}: A={a:04X} B={b:04X} X={x:04X} SP={sp:04X} F={f_:02X}")
        exp_words += [a, b, x, sp, f_]
        veclist.append(vid)

    with open('v35mmu/golden_v35mmu.txt', 'w') as f:
        f.write('\n'.join(golden_lines) + '\n')
    with open('v35mmu/expected_v35mmu.hex', 'w') as f:
        for w in exp_words:
            f.write(f'{w:04x}\n')
    with open('v35mmu/veclist_v35mmu.txt', 'w') as f:
        f.write('\n'.join(veclist) + '\n')

    print(f"\ngolden written: v35mmu/golden_v35mmu.txt ({len(VECTORS)} vectors)")
    print(f"expected hex  : v35mmu/expected_v35mmu.hex ({len(exp_words)} words)")

if __name__ == '__main__':
    main()
