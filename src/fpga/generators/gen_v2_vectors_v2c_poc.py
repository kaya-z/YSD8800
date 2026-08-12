#!/usr/bin/env python3
# =====================================================================
# gen_v2_vectors_v2c_poc.py  v0.1  (2026-07-09)   ★KY38: _poc 実験版
#   V2-a(C1) + V2-b(C2/C3) + V2-c(C4分岐 / C5メモリ) 統合ベクタ生成器
#
#   V2-b生成器を土台に以下を拡張:
#     - C4分岐エンコーダ br(op, rel16) [op,lo,hi]。rel16は機械算出(論点/Q5)
#       分岐先 = ラベル - (分岐命令次アドレス)。手計算オフセット排除=単一ソース
#     - C5メモリエンコーダ (★M-1反映)
#         LDW: レジスタ上位ニブル  ldw_abs(op,rd,addr)=[op, rd<<4|0, lo,hi]
#         STW: データ源下位ニブル  stw_abs(op,rs,addr)=[op, 0<<4|rs, lo,hi]
#         mem_rr(op,rd,rs)=[op, rd<<4|rs]  (0x24 LDW[rS]/0x25 STW[rD])
#         X+imm も同様(LDW上位/STW下位)
#         バイト(0x10-0x17)はレジスタ固定opゆえオペランド無しor addr/off
#     - 新観点A(C4): golden に PC を突合対象として追加(既存トレースPC流用)
#     - 新観点B(C5): STWは「STW→LDW読み戻し」構造でレジスタ突合に還元(論点5-b)
#     - データ域($0200〜)への既知値事前配置に対応(make_image拡張)
#
#   【M-1 実照合根拠(ISA2_3_v231 / emu23)】
#     LDW 0x22/0x26: rd=rb>>4 上位ニブル・set_zn更新
#     STW 0x23/0x27: rs=rb&0x0F 下位ニブル(データ源)・FLAGS不変
#     STW 0x25[rD] : rD上位=アドレス / rS下位=データ
#     LDB 0x10/0x12: A/B←zero_ext(mem8) FLAGS不変
#     STB 0x14/0x16: mem8←reg&0xFF FLAGS不変
#     分岐 0x60-64 : off=(int16_t)fetch16; pc+=2; [cond] pc=pc+off
#                    → 分岐先 = 次命令アドレス + rel16
# =====================================================================
import subprocess, sys, os

CODE_ORG = 0x0100
DATA_ORG = 0x0200          # C5データ域(コードと非干渉)
EMU = './emu23'
OUTDIR = 'v2c'

A, B, X = 0, 1, 2

# ---------- 既存エンコーダ (V2-a/b から継承) ----------
def ldw_imm(rd, imm):
    return [0x21, (rd << 4) & 0xF0, imm & 0xFF, (imm >> 8) & 0xFF]
def alu_rr(op, rd, rs):
    return [op, ((rd << 4) | (rs & 0x0F)) & 0xFF]
def alu_imm(op, rd, imm):
    return [op, (rd << 4) & 0xF0, imm & 0xFF, (imm >> 8) & 0xFF]
HALT = [0x01]

# ---------- C4 分岐エンコーダ ----------
def br(op, rel16):
    """3B [op, lo, hi]  rel16 は16bit符号付き(2の補数)を LE で格納"""
    r = rel16 & 0xFFFF
    return [op, r & 0xFF, (r >> 8) & 0xFF]

# ---------- C5 メモリエンコーダ (★M-1反映) ----------
def ldw_abs(op, rd, addr):
    """LDW rD,[imm16] 0x22 : rd 上位ニブル"""
    return [op, (rd << 4) & 0xF0, addr & 0xFF, (addr >> 8) & 0xFF]
def stw_abs(op, rs, addr):
    """STW rS,[imm16] 0x23 : ★rs 下位ニブル(データ源)"""
    return [op, (rs & 0x0F), addr & 0xFF, (addr >> 8) & 0xFF]
def mem_rr(op, rd, rs):
    """0x24 LDW[rS]/0x25 STW[rD] : [op, rd<<4|rs]
       0x24: rd=ロード先(上位)/rs=アドレス(下位)
       0x25: rd=アドレス(上位)/rs=データ源(下位)  ←実装一致"""
    return [op, ((rd << 4) | (rs & 0x0F)) & 0xFF]
def ldw_xoff(op, rd, off):
    """LDW rD,[X+imm] 0x26 : rd 上位ニブル"""
    return [op, (rd << 4) & 0xF0, off & 0xFF, (off >> 8) & 0xFF]
def stw_xoff(op, rs, off):
    """STW rS,[X+imm] 0x27 : ★rs 下位ニブル(データ源)"""
    return [op, (rs & 0x0F), off & 0xFF, (off >> 8) & 0xFF]

# バイト: ★EXTプレフィックス(0x1F)+サブオペコード方式(emu23/RTL実照合)★
#   LDB/STB[abs] = [0x1F, sub, lo, hi]  (4B)
#   LDB/STB[X]   = [0x1F, sub]          (2B)
#   sub: LDB A[imm]=0x10 A[X]=0x11 B[imm]=0x12 B[X]=0x13
#        STB A[imm]=0x14 A[X]=0x15 B[imm]=0x16 B[X]=0x17
#   レジスタA/BはsubでFIX・アドレスはimm16 or X。
EXT = 0x1F
def ldb_abs(sub, addr):  # LDB [imm16]  sub=0x10(A)/0x12(B)
    return [EXT, sub, addr & 0xFF, (addr >> 8) & 0xFF]
def ldb_x(sub):          # LDB [X]      sub=0x11(A)/0x13(B)
    return [EXT, sub]
def stb_abs(sub, addr):  # STB [imm16]  sub=0x14(A)/0x16(B)
    return [EXT, sub, addr & 0xFF, (addr >> 8) & 0xFF]
def stb_x(sub):          # STB [X]      sub=0x15(A)/0x17(B)
    return [EXT, sub]

OP = {
    'ADD':0x40,'SUB':0x42,'AND':0x50,'OR':0x52,'XOR':0x54,
    'NOT':0x56,'SHL':0x57,'SHR':0x58,'SAR':0x59,
    'ADDI':0x41,'SUBI':0x43,'ANDI':0x51,'ORI':0x53,'XORI':0x55,
    'CMP':0x44,'CMPI':0x45,
    'JMP':0x60,'BEQ':0x61,'BNE':0x62,'BLT':0x63,'BGE':0x64,
    'LDWa':0x22,'STWa':0x23,'LDWr':0x24,'STWr':0x25,'LDWx':0x26,'STWx':0x27,
    'LDBa_A':0x10,'LDBx_A':0x11,'LDBa_B':0x12,'LDBx_B':0x13,
    'STBa_A':0x14,'STBx_A':0x15,'STBa_B':0x16,'STBx_B':0x17,
}

# =====================================================================
#  ベクタ定義
#   V2-a/b は前生成器から継承(回帰維持)。ここでは C4/C5 を "prog" 方式で定義。
#   prog方式: 各ベクタが機械語列を組み立てる関数 build を持つ。
#             gen は build()→emu23黄金→(A,B,X,F,PC) を取得し突合材料化。
#   突合対象: A,B,X,F は従来通り。C4は PC も突合。C5ストアは読み戻しでレジスタ化。
# =====================================================================

# --- V2-a/b 継承ベクタ(kind方式・従来) ---
LEGACY = [
    ("ADD_pos","c1","Z0N0",[(A,0x0003),(B,0x0005)],('ADD',A,B)),
    ("ADD_zero","c1","Z1N0",[(A,0x0001),(B,0xFFFF)],('ADD',A,B)),
    ("ADD_neg","c1","Z0N1",[(A,0x7FFF),(B,0x0001)],('ADD',A,B)),
    ("SUB_pos","c1","Z0N0",[(A,0x0008),(B,0x0003)],('SUB',A,B)),
    ("SUB_zero","c1","Z1N0",[(A,0x0005),(B,0x0005)],('SUB',A,B)),
    ("SUB_neg","c1","Z0N1",[(A,0x0000),(B,0x0001)],('SUB',A,B)),
    ("AND_zero","c1","Z1N0",[(A,0xF0F0),(B,0x0F0F)],('AND',A,B)),
    ("AND_neg","c1","Z0N1",[(A,0xFFFF),(B,0x8000)],('AND',A,B)),
    ("OR_pos","c1","Z0N0",[(A,0x00F0),(B,0x000F)],('OR',A,B)),
    ("OR_neg","c1","Z0N1",[(A,0x0000),(B,0x8000)],('OR',A,B)),
    ("XOR_zero","c1","Z1N0",[(A,0xAAAA),(B,0xAAAA)],('XOR',A,B)),
    ("XOR_neg","c1","Z0N1",[(A,0x0000),(B,0x8000)],('XOR',A,B)),
    ("NOT_neg","c1","Z0N1",[(A,0x0000)],('NOT',A,0)),
    ("NOT_zero","c1","Z1N0",[(A,0xFFFF)],('NOT',A,0)),
    ("SHL_neg","c1","Z0N1",[(A,0x4000),(B,0x0001)],('SHL',A,B)),
    ("SHL_zero","c1","Z1N0",[(A,0x8000),(B,0x0001)],('SHL',A,B)),
    ("SHR_pos","c1","Z0N0",[(A,0x8000),(B,0x0001)],('SHR',A,B)),
    ("SHR_zero","c1","Z1N0",[(A,0x0001),(B,0x0001)],('SHR',A,B)),
    ("SAR_neg","c1","Z0N1",[(A,0x8000),(B,0x0001)],('SAR',A,B)),
    ("SAR_pos","c1","Z0N0",[(A,0x4000),(B,0x0001)],('SAR',A,B)),
    ("ADDI_pos","alu2","Z0N0",[(A,0x0003)],('ADDI',A,0x0005)),
    ("ADDI_zero","alu2","Z1N0",[(A,0x0001)],('ADDI',A,0xFFFF)),
    ("ADDI_neg","alu2","Z0N1",[(A,0x7FFF)],('ADDI',A,0x0001)),
    ("SUBI_pos","alu2","Z0N0",[(A,0x0008)],('SUBI',A,0x0003)),
    ("SUBI_zero","alu2","Z1N0",[(A,0x0005)],('SUBI',A,0x0005)),
    ("SUBI_neg","alu2","Z0N1",[(A,0x0000)],('SUBI',A,0x0001)),
    ("ANDI_zero","alu2","Z1N0",[(A,0xF0F0)],('ANDI',A,0x0F0F)),
    ("ANDI_neg","alu2","Z0N1",[(A,0xFFFF)],('ANDI',A,0x8000)),
    ("ANDI_pos","alu2","Z0N0",[(A,0x0F0F)],('ANDI',A,0x00FF)),
    ("ORI_pos","alu2","Z0N0",[(A,0x00F0)],('ORI',A,0x000F)),
    ("ORI_neg","alu2","Z0N1",[(A,0x0000)],('ORI',A,0x8000)),
    ("XORI_zero","alu2","Z1N0",[(A,0xAAAA)],('XORI',A,0xAAAA)),
    ("XORI_neg","alu2","Z0N1",[(A,0x0000)],('XORI',A,0x8000)),
    ("CMP_eq","cmp","Z1N0",[(A,0x1234),(B,0x1234)],('CMP',A,B)),
    ("CMP_lt","cmp","Z0N1",[(A,0x0003),(B,0x0005)],('CMP',A,B)),
    ("CMP_gt","cmp","Z0N0",[(A,0x0005),(B,0x0003)],('CMP',A,B)),
    ("CMP_wrap","cmp","Z0N1",[(A,0x0000),(B,0x0001)],('CMP',A,B)),
    ("CMPI_eq","cmpi","Z1N0",[(A,0x1234)],('CMPI',A,0x1234)),
    ("CMPI_lt","cmpi","Z0N1",[(A,0x0003)],('CMPI',A,0x0005)),
    ("CMPI_gt","cmpi","Z0N0",[(A,0x0005)],('CMPI',A,0x0003)),
    ("CMPI_wrap","cmpi","Z0N1",[(A,0x0000)],('CMPI',A,0x0001)),
]

def build_legacy(kind, inits, tail):
    code = []
    for (rd, imm) in inits:
        code += ldw_imm(rd, imm)
    if kind in ('c1','cmp'):
        op, rd, rs = tail; code += alu_rr(OP[op], rd, rs)
    elif kind in ('alu2','cmpi'):
        op, rd, imm = tail; code += alu_imm(OP[op], rd, imm)
    code += HALT
    return code, None, {}   # code, preseed(なし), meta

# ---------------------------------------------------------------------
#  C4 分岐ベクタ: build関数が (code, preseed, meta) を返す
#   rel16 は「ラベル差 - 3(分岐命令長)」で機械算出。
#   構造: init(フラグ確定) → 分岐命令 → [not-taken経路: A←0x5555; HALT]
#                                      → [taken先: A←0xAAAA; HALT]
#   分岐命令の直後3B(=next命令アドレス)から taken先までの距離を rel16 に。
#   前方分岐: not-taken経路を挟み、taken先はその後ろ。
# ---------------------------------------------------------------------
def build_branch(op_name, setup, taken_expected):
    """op_name: 'JMP'/'BEQ'/... setup: フラグ確定用命令列(codeリスト)
       taken_expected: True=分岐成立を期待 / False=不成立
       レジスタA: taken先=0xAAAA / not-taken=0x5555 を書く→どちら経路か判定
       PCも突合対象。前方分岐固定。"""
    code = []
    code += setup
    # 分岐命令位置
    br_pos = len(code)
    # not-taken経路: A←0x5555; HALT   (LDW=4B + HALT=1B = 5B)
    nt = ldw_imm(A, 0x5555) + HALT      # 5B
    # taken先: A←0xAAAA; HALT
    tk = ldw_imm(A, 0xAAAA) + HALT      # 5B
    # 分岐命令(3B) の次アドレス = br_pos+3。taken先 = br_pos+3 + len(nt)
    rel = len(nt)                        # next→taken先 の距離
    code += br(OP[op_name], rel)         # 3B
    code += nt                           # not-taken経路(5B)
    code += tk                           # taken先(5B)
    return code, None, {}

def build_branch_bwd(op_name, setup):
    """後方分岐(負rel16)検証。JMP専用。
       構造: taken先(A←0xAAAA;HALT) → skip(A←0x5555;HALT) → 分岐(後方へ)
       だが素直に組むと最初のHALTで止まる。→
       正攻法: init→ JMP fwd(skip3) → [back: A←0xAAAA;HALT]
               → [entry: JMP back(負)] の順で、entryへ前方JMP後に後方JMP。
       簡明化のため: A←0x5555 → JMP +offで後方のtaken先(A←0xAAAA;HALT)へ。
       レイアウト:
         L0: back: A←0xAAAA; HALT        (5B)  addr = base
         L1: entry: A←0x5555             (4B)
         L2:        JMP back              (3B)  next=L2+3, rel=back-(L2+3)=負
       実行開始はL1(entry)にしたいので、リセットベクタをentryに向ける。
    """
    back = ldw_imm(A, 0xAAAA) + HALT     # 5B  @CODE_ORG
    entry = ldw_imm(A, 0x5555)           # 4B  @CODE_ORG+5
    # JMP back: next = (CODE_ORG+5+4)+3, target=CODE_ORG
    jmp_next = 5 + 4 + 3
    rel = (0) - jmp_next                 # 相対(コード内オフセット基準・負)
    code = back + entry + br(OP['JMP'], rel)
    # ★実行開始はentry(CODE_ORG+5)。リセットベクタを差し替えるためentry_offを返す
    return code, None, {'entry_off': 5}

BRANCH = [
    # (id, op, setup, taken_expected)
    # JMP無条件(前方)
    ("JMP_fwd", "JMP", [], True),
    # BEQ: Z=1で成立 / Z=0で不成立。setupでフラグ作る(CMPIで等値→Z1、非等値→Z0)
    ("BEQ_taken",  "BEQ", ldw_imm(A,0x0001)+alu_imm(OP['CMPI'],A,0x0001), True),   # Z1
    ("BEQ_ntaken", "BEQ", ldw_imm(A,0x0001)+alu_imm(OP['CMPI'],A,0x0002), False),  # Z0
    ("BNE_taken",  "BNE", ldw_imm(A,0x0001)+alu_imm(OP['CMPI'],A,0x0002), True),   # Z0
    ("BNE_ntaken", "BNE", ldw_imm(A,0x0001)+alu_imm(OP['CMPI'],A,0x0001), False),  # Z1
    ("BLT_taken",  "BLT", ldw_imm(A,0x0000)+alu_imm(OP['CMPI'],A,0x0001), True),   # 0-1=FFFF→N1
    ("BLT_ntaken", "BLT", ldw_imm(A,0x0005)+alu_imm(OP['CMPI'],A,0x0003), False),  # 5-3=2→N0
    ("BGE_taken",  "BGE", ldw_imm(A,0x0005)+alu_imm(OP['CMPI'],A,0x0003), True),   # N0
    ("BGE_ntaken", "BGE", ldw_imm(A,0x0000)+alu_imm(OP['CMPI'],A,0x0001), False),  # N1
]

# ---------------------------------------------------------------------
#  C5 メモリベクタ
#   ロード系: データ域に既知値を preseed → LDW/LDB → レジスタ突合
#   ストア系: レジスタに値 → STW/STB → 同番地を LDW/LDB 読み戻し → レジスタ突合
#   preseed: {addr: (byte列)} を make_imageで配置
# ---------------------------------------------------------------------
def build_mem(kind, spec):
    """kind別にコード・preseed生成。返り: (code, preseed_dict, meta)"""
    code = []
    pre = {}
    if kind == 'ldw_abs':   # LDW A,[DATA] 値=spec['val']
        pre[DATA_ORG] = [spec['val'] & 0xFF, (spec['val']>>8)&0xFF]
        code += ldw_abs(OP['LDWa'], A, DATA_ORG) + HALT
    elif kind == 'ldw_rs':  # X=DATA; LDW A,[X](rS=X)
        pre[DATA_ORG] = [spec['val'] & 0xFF, (spec['val']>>8)&0xFF]
        code += ldw_imm(X, DATA_ORG)
        code += mem_rr(OP['LDWr'], A, X) + HALT       # 0x24 rd=A上位/rs=X下位
    elif kind == 'ldw_xoff':# X=DATA; LDW A,[X+2]
        pre[DATA_ORG+2] = [spec['val'] & 0xFF, (spec['val']>>8)&0xFF]
        code += ldw_imm(X, DATA_ORG)
        code += ldw_xoff(OP['LDWx'], A, 0x0002) + HALT
    elif kind == 'stw_abs': # A=val; STW A,[DATA]; LDW A,[DATA]読戻し
        code += ldw_imm(A, spec['val'])
        code += stw_abs(OP['STWa'], A, DATA_ORG)      # ★下位ニブル
        code += ldw_imm(A, 0x0000)                    # Aクリア(読戻し前)
        code += ldw_abs(OP['LDWa'], A, DATA_ORG) + HALT
    elif kind == 'stw_abs_B':# ★M-1回帰: B=val; STW B,[DATA]; 読戻しはBへ
        code += ldw_imm(B, spec['val'])
        code += stw_abs(OP['STWa'], B, DATA_ORG)      # rs=B(下位=1)
        code += ldw_imm(B, 0x0000)
        code += ldw_abs(OP['LDWa'], B, DATA_ORG) + HALT
    elif kind == 'stw_rd':  # X=DATA(addr); A=val; STW A,[X](0x25 rD=X上位/rS=A下位)
        code += ldw_imm(X, DATA_ORG)
        code += ldw_imm(A, spec['val'])
        code += mem_rr(OP['STWr'], X, A)              # rd=X(addr上位)/rs=A(data下位)
        code += ldw_imm(A, 0x0000)
        code += ldw_abs(OP['LDWa'], A, DATA_ORG) + HALT
    elif kind == 'stw_xoff':# X=DATA; A=val; STW A,[X+2]; 読戻し[X+2]
        code += ldw_imm(X, DATA_ORG)
        code += ldw_imm(A, spec['val'])
        code += stw_xoff(OP['STWx'], A, 0x0002)       # ★下位ニブル
        code += ldw_imm(A, 0x0000)
        code += ldw_xoff(OP['LDWx'], A, 0x0002) + HALT
    elif kind == 'ldb_abs': # mem8[DATA]=val8; LDB A,[DATA]→ゼロ拡張
        pre[DATA_ORG] = [spec['val'] & 0xFF]
        code += ldb_abs(OP['LDBa_A'], DATA_ORG) + HALT
    elif kind == 'ldb_x':   # X=DATA; mem8=val8; LDB A,[X]
        pre[DATA_ORG] = [spec['val'] & 0xFF]
        code += ldw_imm(X, DATA_ORG)
        code += ldb_x(OP['LDBx_A']) + HALT
    elif kind == 'stb_abs': # A=val; STB A,[DATA]; LDB A読戻し
        code += ldw_imm(A, spec['val'])
        code += stb_abs(OP['STBa_A'], DATA_ORG)
        code += ldw_imm(A, 0x0000)
        code += ldb_abs(OP['LDBa_A'], DATA_ORG) + HALT
    elif kind == 'stb_x':   # X=DATA; A=val; STB A,[X]; LDB読戻し
        code += ldw_imm(X, DATA_ORG)
        code += ldw_imm(A, spec['val'])
        code += stb_x(OP['STBx_A'])
        code += ldw_imm(A, 0x0000)
        code += ldb_x(OP['LDBx_A']) + HALT
    else:
        raise ValueError(kind)
    return code, pre, {}

MEM = [
    # (id, kind, spec, want_flags(Noneなら突合しない/文字列でZ/N突合))
    ("LDW_abs",  "ldw_abs",  {'val':0x1234}, "Z0N0"),
    ("LDW_zero", "ldw_abs",  {'val':0x0000}, "Z1N0"),
    ("LDW_neg",  "ldw_abs",  {'val':0x8000}, "Z0N1"),
    ("LDW_rs",   "ldw_rs",   {'val':0x2345}, "Z0N0"),
    ("LDW_xoff", "ldw_xoff", {'val':0x3456}, "Z0N0"),
    ("STW_abs",  "stw_abs",  {'val':0x4567}, None),   # STWはFLAGS不変・読戻LDWで値確認
    ("STW_absB", "stw_abs_B",{'val':0x89AB}, None),   # ★M-1回帰(データ=B)
    ("STW_rd",   "stw_rd",   {'val':0x5678}, None),
    ("STW_xoff", "stw_xoff", {'val':0x6789}, None),
    ("LDB_abs",  "ldb_abs",  {'val':0x00A5}, None),   # ゼロ拡張=0x00A5・FLAGS不変
    ("LDB_x",    "ldb_x",    {'val':0x005A}, None),
    ("STB_abs",  "stb_abs",  {'val':0x00C3}, None),
    ("STB_x",    "stb_x",    {'val':0x003C}, None),
]

# =====================================================================
def make_image(code, preseed=None, entry_off=0):
    img = bytearray(0x10000)
    entry = CODE_ORG + entry_off
    img[0x0000] = entry & 0xFF
    img[0x0001] = (entry >> 8) & 0xFF
    img[CODE_ORG:CODE_ORG+len(code)] = bytes(code)
    if preseed:
        for addr, bs in preseed.items():
            for i, b in enumerate(bs):
                img[addr+i] = b & 0xFF
    hi = CODE_ORG + len(code)
    if preseed:
        for addr, bs in preseed.items():
            hi = max(hi, addr+len(bs))
    return bytes(img[:hi])

def write_hex(hexpath, code, preseed=None, entry_off=0):
    entry = CODE_ORG + entry_off
    with open(hexpath, 'w') as f:
        f.write("@0000\n")
        f.write(f"{entry & 0xFF:02X}\n{(entry>>8)&0xFF:02X}\n")
        f.write(f"@{CODE_ORG:04X}\n")
        for b in code:
            f.write(f"{b:02X}\n")
        if preseed:
            for addr, bs in sorted(preseed.items()):
                f.write(f"@{addr:04X}\n")
                for b in bs:
                    f.write(f"{b:02X}\n")

def emu_golden(binpath, n_steps):
    """emu23を -n で実行し状態取得。
       ★PC観測点をRTL(dbg_pc=HALT後PC)と一致させるため、
         実行前トレース行(F=)ではなく実行後サマリ行(FLAGS=)を採る。
         サマリ行 = 'PC=.. SP=.. FLAGS=.. A=.. B=.. X=..'(HALT後PC)。
         A/B/X/FLAGSはHALT前後で不変ゆえサマリ行の値=最終状態。
       戻り: dict {PC,SP,F,A,B,X} or None"""
    r = subprocess.run([EMU, binpath, '-n', str(n_steps)],
                       capture_output=True, text=True, timeout=10)
    summary = None   # FLAGS= 形式(実行後サマリ・観測点=RTL一致)
    trace   = None   # F= 形式(実行前トレース・fallback)
    for line in r.stdout.splitlines():
        line = line.strip()
        if not line.startswith('PC='):
            continue
        fields = {}
        for tok in line.replace('|', ' ').split():
            if '=' in tok:
                k, v = tok.split('=', 1)
                try: fields[k] = int(v, 16)
                except ValueError: pass
        # FLAGS= を F にマップ(サマリ行)
        if 'FLAGS' in fields:
            fields['F'] = fields['FLAGS']
        if all(k in fields for k in ('PC','SP','F','A','B','X')):
            if 'FLAGS' in fields:
                summary = fields
            else:
                trace = fields
    return summary if summary is not None else trace

def flags_str(f):
    return f"Z{f & 1}N{(f>>1)&1}"

def main():
    if not os.path.exists(EMU):
        print(f"ERROR: {EMU} not found", file=sys.stderr); sys.exit(1)
    os.makedirs(OUTDIR, exist_ok=True)

    rows = []   # (id, group, PC,SP,F,A,B,X, want_pc_flag, want_flags)
    print(f"{'ID':<12} {'grp':<4} {'PC':>4} {'A':>4} {'B':>4} {'X':>4} "
          f"{'F':>2} 判定")
    print('-'*52)

    def run_vec(vid, group, code, preseed, meta, want_flags,
                want_reg=None, want_pc=None):
        entry_off = meta.get('entry_off', 0)
        img = make_image(code, preseed, entry_off)
        binp = f'{OUTDIR}/{vid}.bin'
        with open(binp,'wb') as f: f.write(img)
        write_hex(f'{OUTDIR}/{vid}.hex', code, preseed, entry_off)
        # ステップ数: 命令数を多めに見積り(各≤4B, HALT含む)。余裕もって len//2+4
        g = emu_golden(binp, len(code)//2 + 6)
        if g is None:
            print(f"{vid:<12} {group:<4}  *** golden取得失敗 ***"); return
        verdict = "OK"
        if want_flags is not None and flags_str(g['F']) != want_flags:
            verdict = f"NG(F {flags_str(g['F'])}!={want_flags})"
        print(f"{vid:<12} {group:<4} {g['PC']:4X} {g['A']:4X} {g['B']:4X} "
              f"{g['X']:4X} {g['F']:2X} {verdict}")
        rows.append((vid, group, g['PC'],g['SP'],g['F'],g['A'],g['B'],g['X'],
                     want_flags))

    # --- LEGACY (V2-a/b 回帰) ---
    for (vid,kind,want,inits,tail) in LEGACY:
        code,_,meta = build_legacy(kind, inits, tail)
        run_vec(vid, "leg", code, None, meta, want)

    # --- C4 分岐 (前方) ---
    for (vid, op, setup, taken) in BRANCH:
        code,_,meta = build_branch(op, setup, taken)
        run_vec(vid, "br", code, None, meta, None)
    # --- C4 後方分岐 ---
    code,_,meta = build_branch_bwd('JMP', [])
    run_vec("JMP_bwd", "br", code, None, meta, None)

    # --- C5 メモリ ---
    for (vid, kind, spec, want) in MEM:
        code, pre, meta = build_mem(kind, spec)
        run_vec(vid, "mem", code, pre, meta, want)

    # --- golden テキスト ---
    with open(f'{OUTDIR}/golden_v2c.txt','w') as f:
        f.write("# V2-c golden(emu23 v1.09). id grp PC SP F A B X wantF\n")
        for r in rows:
            (vid,grp,pc,sp,fl,a,b,x,wf) = r
            f.write(f"{vid} {grp} {pc:04X} {sp:04X} {fl:02X} "
                    f"{a:04X} {b:04X} {x:04X} {wf}\n")

    # --- expected hex: 1ベクタ5word (A,B,X,F,PC) ---
    with open(f'{OUTDIR}/expected_v2c.hex','w') as f:
        for r in rows:
            (vid,grp,pc,sp,fl,a,b,x,wf) = r
            f.write(f"{a:04X}\n{b:04X}\n{x:04X}\n{fl:04X}\n{pc:04X}\n")

    # --- veclist: id grp ---
    with open(f'{OUTDIR}/veclist_v2c.txt','w') as f:
        for r in rows:
            f.write(f"{r[0]} {r[1]}\n")

    print('-'*52)
    print(f"golden written: {OUTDIR}/golden_v2c.txt ({len(rows)} vectors)")
    print(f"expected hex  : {OUTDIR}/expected_v2c.hex ({len(rows)*5} words)")

if __name__ == '__main__':
    main()
