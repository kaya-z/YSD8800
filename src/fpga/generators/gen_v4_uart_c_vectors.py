#!/usr/bin/env python3
# gen_v4_uart_c_vectors.py  v1.0  (2026-07-12)
# ============================================================
#  FPGA V4 / S5(c): UART RX系・IRQ系 プロパティ検証プログラム生成
#
#  【方針】(S5-ISSUE-1)
#    RX は emu23 の 256サイクル周期ポーリング(L486)により協調等価が
#    構造的に取れない。→ emu23 ソースを真実とした【プロパティ検証】。
#    ★判定は必ず「CPUが実命令で読んだ値」= 最終レジスタ値で行う★
#    ★TB は rdata_o を直接覗かない（偽合格防止）★
#
#  【実照合(KY39/KY34)】
#    emu23_v109.c:
#      L310  : IRQ1 の irq_pending = 2 → vec = rd16(2*2) = $0004
#      L1183 : uint16_t vec = rd16((uint16_t)(irq * 2));
#      L294  : IRQ_STAT = $FCB2 (W2C, reset 0x00)
#      L295/L307 : IRQ_MASK = $FCB4 (1=マスク, reset 0x0004)
#      L298-300 : IRQ_STAT bit0=UART_RX / bit1=STOR / bit2=UART_TX
#      L996-998 : EI=0x02 / DI=0x03 / IRET=0x04
#      L1245-1255 : EXT(0x1F) PUSH A/B/X=0x00/01/02, POP A/B/X=0x03/04/05
#      L1505-1518 : BRA=0x60 / BEQ=0x61 / BNE=0x62 (rel16, 基準=off読取後PC)
#    ysd8800_ysd8001_v0_1.sv:
#      L123-124 : UART_STAT bit0=TX_READY / bit1=RX_READY
#      L180     : rx_accept = rx_valid_i & ~stat_r[RX_READY]  ← ★先着優先★
#      L344     : irq_tx_o = stat_r[TX_READY]                 ← ★レベル★
#
#  【KY54 アンチ偽合格】
#    c5/c6 のハンドラは必ずマジック値を残す。
#    ハンドラが起動しなければ回収値が初期値のままで【必ず FAIL】する構造。
# ============================================================

import os

CODE_ORG   = 0x0100
HANDLER_ORG= 0x0200      # ハンドラは $0200 に置く（コードと分離）
VEC_IRQ1   = 0x0004      # ★実照合: irq_pending=2 → vec addr = 2*2 = $0004★
SP_INIT    = 0x0400

A, B, X, SP = 0, 1, 2, 3

UART_TX   = 0xFC80
UART_RX   = 0xFC82
UART_STAT = 0xFC84
IRQ_STAT  = 0xFCB2
IRQ_MASK  = 0xFCB4

# ハンドラ痕跡置き場（RAM。PSRAM領域）
MARK_ADDR = 0x0300       # ハンドラ実行回数（16bit）
DATA_ADDR = 0x0302       # ハンドラが読んだ RX データ（16bit）

OUTDIR = 'v4uart'

# ---- エンコーダ（全て実照合済） ----
def ldw_imm(rd, imm): return [0x21, (rd << 4) & 0xF0, imm & 0xFF, (imm >> 8) & 0xFF]

# ★KY34 実照合(emu23 L1319-1331)★ LDW/STW abs は EXT ではなく独立オペコード。
#   LDW rD,[imm16] = 0x22, レジスタ = rb >> 4    (★上位nibble★)
#   STW rS,[imm16] = 0x23, レジスタ = rb & 0x0F  (★下位nibble★) ← 非対称！
def ldw_abs(rd, a):   return [0x22, (rd << 4) & 0xF0, a & 0xFF, (a >> 8) & 0xFF]
def stw_abs(rs, a):   return [0x23, rs & 0x0F,        a & 0xFF, (a >> 8) & 0xFF]
def ldb_abs(r, a):    return [0x1F, 0x10 if r==A else 0x12, a & 0xFF, (a >> 8) & 0xFF]
def stb_abs(r, a):    return [0x1F, 0x14 if r==A else 0x16, a & 0xFF, (a >> 8) & 0xFF]
def mov(rd, rs):      return [0x20, ((rd << 4) & 0xF0) | (rs & 0x0F)]
def addi(rd, imm):    return [0x41, (rd << 4) & 0xF0, imm & 0xFF, (imm >> 8) & 0xFF]
def cmpi(rd, imm):    return [0x45, (rd << 4) & 0xF0, imm & 0xFF, (imm >> 8) & 0xFF]
def bra(off):         return [0x60, off & 0xFF, (off >> 8) & 0xFF]
def beq(off):         return [0x61, off & 0xFF, (off >> 8) & 0xFF]
def bne(off):         return [0x62, off & 0xFF, (off >> 8) & 0xFF]
def push(r):          return [0x1F, 0x00 + r]
def pop(r):           return [0x1F, 0x03 + r]
EI   = [0x02]
DI   = [0x03]
IRET = [0x04]
NOP  = [0x00]
HALT = [0x01]

# ---- ウェイトループ（TB の RX 注入タイミングを稼ぐ）----
# loop: ADDI X,#1 (4B) / CMPI X,#N (4B) / BNE loop (3B) = 11B
# BNE の rel16 基準 = off読取後のPC = loop先頭+11 → 戻り offset = -11
def wait_loop(n):
    body = addi(X, 1) + cmpi(X, n) + bne(-11)
    assert len(body) == 11
    return body

VECTORS = []

# ------------------------------------------------------------------
# c1 UART_RX_READ : TBが 0x5A 注入 → CPU が $FC82 を LDB
#   期待: A=0x005A
#   ★ハングしないよう「RX_READY を待つ」のではなくウェイト後に無条件読み★
#     （TB が注入タイミングを保証する。KY54: 注入が無ければ A=0x0000 で FAIL）
# ------------------------------------------------------------------
VECTORS.append(("UART_RX_READ",
    "RX 0x5A 注入 → CPU が $FC82 を LDB。A=0x005A",
    ldw_imm(SP, SP_INIT) +
    ldw_imm(X, 0x0000) +
    wait_loop(200) +              # TB がこの間に注入する
    ldb_abs(A, UART_RX) +         # A = 0x005A のはず
    ldb_abs(B, UART_STAT) +       # B = 0x0003 (TX_READY=1, RX_READY=1)
    HALT
))

# ------------------------------------------------------------------
# c2 UART_RX_NO_SIDE_EFFECT : $FC82 を2回読む → 2回目も同値
#   emu23 実照合: RX読出は RX_READY を落とさない（W2C 方式のため）
#   期待: A=0x005A (2回目), B=0x0003 (RX_READY 保持)
# ------------------------------------------------------------------
VECTORS.append(("UART_RX_NO_SIDE_EFFECT",
    "$FC82 を2回読む → 2回目も 0x5A。RX_READY は落ちない",
    ldw_imm(SP, SP_INIT) +
    ldw_imm(X, 0x0000) +
    wait_loop(200) +
    ldb_abs(A, UART_RX) +         # 1回目（捨てる）
    ldw_imm(A, 0x0000) +          # A をクリア（1回目の値が残らないように）
    ldb_abs(A, UART_RX) +         # 2回目 → A=0x005A のはず
    ldb_abs(B, UART_STAT) +       # B=0x0003（RX_READY 保持）
    HALT
))

# ------------------------------------------------------------------
# c3 UART_STAT_WTC_RX : RX_READY=1 → $FC84 に 0x02 書込 → RX_READY のみクリア
#   ysd8001 L230-231: wr_stat && wdata[BIT_RX_READY] → RX_READY <= 0
#   期待: B=0x0001 (TX_READY 残存、RX_READY クリア)
# ------------------------------------------------------------------
VECTORS.append(("UART_STAT_WTC_RX",
    "RX_READY=1 → STAT に 0x02 書込 → RX_READY のみクリア。TX_READY 残る",
    ldw_imm(SP, SP_INIT) +
    ldw_imm(X, 0x0000) +
    wait_loop(200) +
    ldb_abs(A, UART_STAT) +       # A=0x0003（W2C 前。証拠）
    ldw_imm(B, 0x0002) +
    stb_abs(B, UART_STAT) +       # W2C: bit1=1 → RX_READY クリア
    ldb_abs(B, UART_STAT) +       # B=0x0001 のはず
    HALT
))

# ------------------------------------------------------------------
# c4 UART_RX_OVERRUN : 0x5A 注入 → クリアせずに 0xA5 注入
#   ysd8001 L180: rx_accept = rx_valid_i & ~stat_r[BIT_RX_READY]
#   → RX_READY=1 の間は新データを【受け付けない】= 先着優先
#   期待: A=0x005A（0xA5 に上書きされていない）
#   ★これが FAIL するなら後着優先実装＝emu23 と不一致★
# ------------------------------------------------------------------
VECTORS.append(("UART_RX_OVERRUN",
    "0x5A 注入 → クリアせず 0xA5 注入 → $FC82 は 0x5A のまま（先着優先）",
    ldw_imm(SP, SP_INIT) +
    ldw_imm(X, 0x0000) +
    wait_loop(400) +              # TB が 2回注入する時間を稼ぐ
    ldb_abs(A, UART_RX) +         # A=0x005A のはず（0x00A5 ではない）
    ldb_abs(B, UART_STAT) +       # B=0x0003
    HALT
))

# ------------------------------------------------------------------
# c5 UART_RX_IRQ_HANDLER : ★真のゲート★
#   RX 割込 → IRQ1 → ベクタ $0004 → ハンドラ → $FC82 読 → W2C → IRET
#
#   ★KY54 アンチ偽合格★
#     ハンドラは MARK_ADDR に 0x00A5、DATA_ADDR に読んだRX値を書く。
#     メインは HALT 前にこれらを回収する。
#     → ハンドラが起動しなければ A=0x0000 / B=0x0000 で【必ず FAIL】。
#
#   IRQ_MASK reset=0x04（bit2=TX マスク / bit0=RX 許可）なので RX 割込は通る。
#   ハンドラは IRQ_STAT を W2C しないと irq1_o がレベルで立ち続け再入する
#   → 必ず IRQ_STAT($FCB2) に bit0 を書いてクリアする。
# ------------------------------------------------------------------
main_c5 = (
    ldw_imm(SP, SP_INIT) +
    ldw_imm(A, 0x0000) +
    stw_abs(A, MARK_ADDR) +       # マーク初期化
    stw_abs(A, DATA_ADDR) +
    ldw_imm(X, 0x0000) +
    EI +                          # 割込許可
    wait_loop(400) +              # この間に TB が RX 注入 → 割込発生
    DI +                          # 以降割込を止める（回収を安定化）
    ldw_abs(A, MARK_ADDR) +       # A = 0x00A5 のはず ★ハンドラ痕跡★
    ldw_abs(B, DATA_ADDR) +       # B = 0x005A のはず ★ハンドラが読んだ値★
    HALT
)

handler_c5 = (
    push(A) +
    push(B) +
    ldb_abs(A, UART_RX) +         # ハンドラが RX データを読む
    stw_abs(A, DATA_ADDR) +       # 痕跡: 読んだ値
    ldw_imm(A, 0x0002) +
    stb_abs(A, UART_STAT) +       # UART 側 W2C（RX_READY クリア）
    ldw_imm(A, 0x0001) +
    stb_abs(A, IRQ_STAT) +        # ★YSD8004 W2C（bit0=UART_RX）→ irq1_o 落とす★
    ldw_imm(A, 0x00A5) +
    stw_abs(A, MARK_ADDR) +       # 痕跡: ハンドラ実行マーク
    pop(B) +
    pop(A) +
    IRET
)

VECTORS.append(("UART_RX_IRQ_HANDLER",
    "★真のゲート★ RX割込→IRQ1→vec$0004→ハンドラ→IRET。A=0x00A5 B=0x005A",
    main_c5, handler_c5
))

# ------------------------------------------------------------------
# c6 UART_TX_IRQ_TDRE : TX(TDRE)割込はレベル
#   ysd8001 L344: irq_tx_o = stat_r[BIT_TX_READY]  ← ★レベル★
#
#   【★重要な実照合結果（S5(c)-ISSUE-1）★】
#     emu23 L314-329 ysd8004_raise() は cpu.flags & FL_IE を【見ない】。
#     RTL L1223-1225 も同様:
#         if (state == S_IRQCHK && irq_in != 3'd0) irq_pending <= irq_in;
#     → 【IE=0 のハンドラ実行中でも irq_pending が再ラッチされる】。
#     受理(L1176 / RTL L590)のみが IE を見る。
#     ∴ ハンドラが割込源を黙らせても、黙らせる【前】に既にラッチ済みの
#       pending が IRET 後に受理され、ハンドラが【もう1回だけ】入る。
#     これは MC6809 の IRQ でも起きる古典的挙動であり、
#     OS-9 の IRQ ポーリングルーチンが「自分の仕事が無ければ即RTI」と
#     冪等に書かれている理由そのもの。RTL/emu23 とも仕様通りで【正しい】。
#
#   【検証設計】ハンドラは【1回目】で IRQ_MASK bit2 をセットする。
#     ・レベル実装 → 1回目実行中に再ラッチ → IRET後にもう1回入る → cnt=2
#     ・パルス実装 → 1回目時点で既に irq1_o=0 → 再ラッチ無し    → cnt=1
#     ∴ cnt=2 が「TDRE がレベルである」ことの証明になる。
#     かつ 1回目でマスク済みなので cnt が 3 以上になることは無い
#     （＝実装詳細である「何命令目でラッチされたか」に依存しない）。
#
#   期待: A=0x0002（レベル）、B=0x0004（ハンドラが黙らせた証拠）
# ------------------------------------------------------------------
main_c6 = (
    ldw_imm(SP, SP_INIT) +
    ldw_imm(A, 0x0000) +
    stw_abs(A, MARK_ADDR) +       # ハンドラ実行回数 = 0
    ldw_imm(X, 0x0000) +
    ldw_imm(A, 0x0000) +
    stb_abs(A, IRQ_MASK) +        # ★IRQ_MASK=0x00 → TX(bit2) 割込を【許可】★
    EI +
    wait_loop(300) +              # この間に TX 割込が入る（TX_READY=1 なので即）
    DI +
    ldw_abs(A, MARK_ADDR) +       # A = 0x0002 のはず（★レベルの証明★）
    ldb_abs(B, IRQ_MASK) +        # B = 0x0004（ハンドラが黙らせた証拠）
    HALT
)

# ハンドラ: cnt++ / 【毎回】IRQ_MASK bit2 セット（冪等）/ IRQ_STAT W2C
#   ★1回目で必ず黙らせる → cnt は最大2（レベルなら2、パルスなら1）★
#   ★OS-9 の IRQ ハンドラと同様、冪等に書く（何回入っても壊れない）★
handler_c6 = (
    push(A) +
    push(B) +
    ldw_abs(A, MARK_ADDR) +
    addi(A, 1) +
    stw_abs(A, MARK_ADDR) +       # cnt++
    ldw_imm(B, 0x0004) +
    stb_abs(B, IRQ_MASK) +        # ★毎回 TX 割込をマスク（冪等）★
    ldw_imm(A, 0x0004) +
    stb_abs(A, IRQ_STAT) +        # YSD8004 W2C (bit2=UART_TX)
    pop(B) +
    pop(A) +
    IRET
)

VECTORS.append(("UART_TX_IRQ_TDRE",
    "★TDRE=レベル★ 1回目でマスク → 余分1発入る。cnt=2 がレベルの証明",
    main_c6, handler_c6
))


def build_image(main_code, handler_code):
    """メモリイメージ生成。
       $0004: IRQ1 ベクタ (16bit LE) ← ★実照合: irq_pending=2 → vec=2*2★
       $0100: メインコード
       $0200: ハンドラ
    """
    img = bytearray(0x0400)
    if handler_code is not None:
        img[VEC_IRQ1 + 0] = HANDLER_ORG & 0xFF
        img[VEC_IRQ1 + 1] = (HANDLER_ORG >> 8) & 0xFF
        assert len(handler_code) <= (0x0300 - HANDLER_ORG), "handler too long"
        img[HANDLER_ORG:HANDLER_ORG + len(handler_code)] = bytes(handler_code)
    assert len(main_code) <= (HANDLER_ORG - CODE_ORG), "main too long"
    img[CODE_ORG:CODE_ORG + len(main_code)] = bytes(main_code)
    return img


def main():
    os.makedirs(OUTDIR, exist_ok=True)
    names = []
    for v in VECTORS:
        if len(v) == 3:
            name, desc, code = v
            handler = None
        else:
            name, desc, code, handler = v
        img = build_image(code, handler)
        hexpath = os.path.join(OUTDIR, f"{name}.hex")
        with open(hexpath, 'w') as f:
            for bt in img:
                f.write("%02x\n" % bt)
        names.append(name)
        hs = "handler@%04X" % HANDLER_ORG if handler else "no-irq"
        print(f"[{name:24s}] main={len(code):3d}B  {hs:14s}  ({desc})")

    print()
    print(f"generated {len(names)} programs into {OUTDIR}/")
    print("NOTE: golden は emu23 協調等価【不可】(S5-ISSUE-1)。")
    print("      期待値は TB 側にプロパティとして直接記述する。")


if __name__ == '__main__':
    main()
