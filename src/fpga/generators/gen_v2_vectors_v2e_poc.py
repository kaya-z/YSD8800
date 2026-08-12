#!/usr/bin/env python3
# =====================================================================
# gen_v2_vectors_v2d_poc.py  v0.1  (2026-07-10)   ★KY38: _poc 実験版
#   V2-a(C1)+V2-b(C2/C3)+V2-c(C4分岐/C5メモリ)+V2-d(C6スタック/C7サブルーチン)
#   統合ベクタ生成器
#
#   V2-c生成器を土台に以下を拡張(V2-d・HANDOVER_CHAT77 §3準拠):
#     - C6スタックエンコーダ (★EXTプレフィックス0x1F方式・実照合済)
#         PUSH A/B/X = [0x1F, 0x00/0x01/0x02]  FLAGS不変
#         POP  A/B/X = [0x1F, 0x03/0x04/0x05]  FLAGS不変
#         push16=SP-=2;wr16 / pop16=rd16;SP+=2 (pre-dec/post-inc・6809同方向)
#     - C7サブルーチンエンコーダ (実照合済)
#         JSR imm16 = [0x68, lo, hi]  push16(nextPC); PC<-imm  FLAGS不変
#         RET       = [0x69]          PC<-pop16               FLAGS不変
#     - 補助エンコーダ:
#         LDW SP,#imm = [0x21, 0x30, lo, hi]  SP初期化(reg3=SP上位ニブル)
#         MOV X,SP    = [0x20, 0x23]          SP観測(X<-SP・JSR_SPmove用)
#     - ★SP突合(6word化): V2-d新規ベクタのみ expected に SP を追加(6word)。
#         既存64(LEGACY/BRANCH/MEM)は SP除外継続(5word)= HANDOVER §2 Q4方針。
#     - ★SP初期値問題対策: V2-d各ベクタ先頭で LDW SP,#0xFC7E 明示初期化。
#         emu23初期SP=0xFC7E / RTLリセットSP=0x0000 の差を無効化し突合復帰。
#         ($FC7E=emu素環境 / $F87E=YUI OS運用時memmap ← HANDOVER §2 Q1補足)
#     - ★KY: push/popエンコーダは必ず[0x1F,sub]の2バイトを返す。
#         生成後に「PUSH/POP命令先頭バイト==0x1F」を assert(EXT漏れ再発防止)。
#
#   【C6/C7 実照合根拠(emu23_v109.c・2026-07-10照合)】
#     PUSH/POP: case 0x1F sub 0x00-0x05・push16(L832)/pop16(L837)
#     JSR 0x68(L1529): target=fetch16; push16(nextPC); pc=target
#     RET 0x69(L1535): pc=pop16
#     MOV 0x20(L1305): rd=rb>>4, rs=rb&0x0F → MOV X,SP=[0x20,0x23]
#     LDW 0x21(L1312): rd=rb>>4, set_zn → LDW SP,#imm=[0x21,0x30,lo,hi]
#     reg: A=0 B=1 X=2 SP=3 (get_reg_ptr L1104)
#
#   --- 以下 V2-c からの継承記述 ---
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
OUTDIR = 'v2e'

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

# ---------- C6 スタックエンコーダ (★EXTプレフィックス0x1F方式) ----------
#   ★KY(2026-07-10): push/popは必ず[0x1F,sub]の2バイト。単体returnは禁止。
#   sub: PUSH A/B/X=0x00/0x01/0x02  POP A/B/X=0x03/0x04/0x05
SP = 3                          # レジスタ番号 SP=3 (get_reg_ptr実照合)
SP_INIT = 0xFC7E                # emu23初期SP。RTL(0x0000)との差を無効化する明示初期化値
PUSH_SUB = {A:0x00, B:0x01, X:0x02}
POP_SUB  = {A:0x03, B:0x04, X:0x05}
def push_reg(reg):       # PUSH A/B/X = [0x1F, 0x00/0x01/0x02]
    return [EXT, PUSH_SUB[reg]]
def pop_reg(reg):        # POP  A/B/X = [0x1F, 0x03/0x04/0x05]
    return [EXT, POP_SUB[reg]]
def ldw_sp_init(imm=SP_INIT):   # LDW SP,#imm = [0x21, 0x30, lo, hi] (rD=SP=3上位)
    return [0x21, (SP << 4) & 0xF0, imm & 0xFF, (imm >> 8) & 0xFF]
def mov_x_sp():          # MOV X,SP = [0x20, 0x23] (rD=X=2上位 / rS=SP=3下位)
    return [0x20, (X << 4) | (SP & 0x0F)]

# ---------- C7 サブルーチンエンコーダ ----------
def jsr(target):         # JSR imm16 = [0x68, lo, hi]
    return [0x68, target & 0xFF, (target >> 8) & 0xFF]
def ret():               # RET = [0x69]
    return [0x69]

# ---------- C8 制御割込エンコーダ (★V2-e追加・emu23_v109実照合) ----------
#   EI      = [0x02]  flags |= 0x80 (FL_IE=1)         (emu23 L1205)
#   DI      = [0x03]  flags &= ~0x80 (FL_IE=0)        (emu23 L1209)
#   IRET    = [0x04]  flags=(uint8_t)pop16; pc=pop16  (emu23 L1213)
#   SYSCALL = [0x05]  irq_pending=4 (その場は飛ばない) (emu23 L1225)
#   ★N-1: SYSCALLはその場でvecへ飛ばない。次サイクル受理フェーズで飛ぶ。
#   ★KY39: いずれもトップレベル1バイト命令(EXTプレフィックス不要)。
FL_IE = 0x80
def ei():                # EI      = [0x02]
    return [0x02]
def di():                # DI      = [0x03]
    return [0x03]
def iret():              # IRET    = [0x04]
    return [0x04]
def syscall():           # SYSCALL = [0x05]
    return [0x05]

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
#  C6 スタック / C7 サブルーチン ベクタ (V2-d・SP突合対象)
#   全ベクタ先頭で LDW SP,#SP_INIT を置き、RTLリセットSP(0x0000)との差を無効化。
#   突合: A,B,X,F,PC,SP の6word。スタック整合はPUSH→POP読み戻し+レジスタ突合。
#   ★KY: push/pop命令の先頭バイト==0x1F を build 内で assert。
# ---------------------------------------------------------------------
def _assert_ext(seq, what):
    """push/pop命令列の先頭バイトが0x1F(EXT)であることを確認(EXT漏れ検出)"""
    assert seq and seq[0] == 0x1F, f"EXT漏れ: {what} 先頭={seq[0]:#04x}(!=0x1F)"
    return seq

def build_stack(kind, spec):
    """C6スタックベクタ。返り: (code, preseed, meta)。
       各ベクタ先頭でSP初期化。push/popはEXT assert付き。"""
    code = ldw_sp_init()          # SP=SP_INIT で明示初期化
    if kind == 'push_pop':
        # reg に val → PUSH reg → reg クリア → POP reg → 値が戻る(レジスタ突合)
        reg = spec['reg']; val = spec['val']
        code += ldw_imm(reg, val)
        code += _assert_ext(push_reg(reg), f"PUSH r{reg}")
        code += ldw_imm(reg, 0x0000)
        code += _assert_ext(pop_reg(reg), f"POP r{reg}")
        code += HALT
    elif kind == 'cross_ab':
        # A=aval,B=bval → PUSH A;PUSH B → POP A;POP B (A↔B交換=LIFO確認)
        code += ldw_imm(A, spec['aval'])
        code += ldw_imm(B, spec['bval'])
        code += _assert_ext(push_reg(A), "PUSH A")
        code += _assert_ext(push_reg(B), "PUSH B")
        code += _assert_ext(pop_reg(A), "POP A")   # A←旧B
        code += _assert_ext(pop_reg(B), "POP B")   # B←旧A
        code += HALT
    elif kind == 'sp_decr':
        # PUSH1回でSPが2減る(SP_INIT-2)。X←SPで観測+SP直接突合。
        code += ldw_imm(A, spec['val'])
        code += _assert_ext(push_reg(A), "PUSH A")
        code += mov_x_sp()          # X←SP(=SP_INIT-2)
        code += HALT
    elif kind == 'sp_incr':
        # PUSH→POPでSPが元に戻る(SP_INIT)。X←SPで観測+SP突合。
        code += ldw_imm(A, spec['val'])
        code += _assert_ext(push_reg(A), "PUSH A")
        code += _assert_ext(pop_reg(A), "POP A")
        code += mov_x_sp()          # X←SP(=SP_INIT)
        code += HALT
    elif kind == 'multi_push':
        # A,B,X 3値を順にPUSH → 逆順にPOPで戻す(LIFO・3段)。
        #   PUSH A,B,X → POP X,B,A で各レジスタが元値に戻る(全突合)
        code += ldw_imm(A, spec['aval'])
        code += ldw_imm(B, spec['bval'])
        code += ldw_imm(X, spec['xval'])
        code += _assert_ext(push_reg(A), "PUSH A")
        code += _assert_ext(push_reg(B), "PUSH B")
        code += _assert_ext(push_reg(X), "PUSH X")
        code += ldw_imm(A, 0x0000)
        code += ldw_imm(B, 0x0000)
        code += ldw_imm(X, 0x0000)
        code += _assert_ext(pop_reg(X), "POP X")   # X←旧X(LIFO先頭)
        code += _assert_ext(pop_reg(B), "POP B")   # B←旧B
        code += _assert_ext(pop_reg(A), "POP A")   # A←旧A
        code += HALT
    else:
        raise ValueError(kind)
    return code, None, {}

STACK = [
    # (id, kind, spec)  SP突合対象・6word
    ("PUSH_POP_A", "push_pop", {'reg':A, 'val':0x1234}),
    ("PUSH_POP_B", "push_pop", {'reg':B, 'val':0x5678}),
    ("PUSH_POP_X", "push_pop", {'reg':X, 'val':0x9ABC}),
    ("CROSS_AB",   "cross_ab", {'aval':0x1111, 'bval':0x2222}),
    ("SP_DECR",    "sp_decr",  {'val':0xA5A5}),
    ("SP_INCR",    "sp_incr",  {'val':0x5A5A}),
    ("MULTI_PUSH", "multi_push",{'aval':0x0A0A,'bval':0x0B0B,'xval':0x0C0C}),
]

# ---------------------------------------------------------------------
#  C7 サブルーチン ベクタ
#   JSR/RET は絶対アドレス。サブルーチンは CODE_ORG からの固定配置。
#   ★配置設計: [init+JSR+HALT] を先に置き、その後ろにサブルーチン本体。
#     JSR target は emu23黄金で実アドレスを踏むので、gen側で target を
#     「サブルーチン先頭の絶対アドレス」に機械算出(手計算オフセット排除)。
# ---------------------------------------------------------------------
def build_sub(kind, spec):
    """C7サブルーチンベクタ。返り: (code, preseed, meta)。"""
    if kind == 'jsr_ret':
        # main: SP init; JSR sub; (戻り後)A←0xBEEF; HALT
        # sub : A←0xCAFE; RET
        # 期待: サブでA=0xCAFE→RET→mainでA=0xBEEF上書き→HALT。
        #   「RETが正しくmainに戻った」ことをA=0xBEEFで確認(戻らなければCAFEのまま)。
        pre_jsr = ldw_sp_init()                       # 4B
        # main本体を先に組み、sub先頭の絶対アドレスを算出
        # レイアウト: [pre_jsr][JSR sub(3B)][A←BEEF(4B)][HALT(1B)][sub...]
        main_after_jsr = ldw_imm(A, 0xBEEF) + HALT    # 5B
        sub_body = ldw_imm(A, 0xCAFE) + ret()         # 4B+1B=5B
        sub_addr = CODE_ORG + len(pre_jsr) + 3 + len(main_after_jsr)
        code = pre_jsr + jsr(sub_addr) + main_after_jsr + sub_body
        return code, None, {}
    elif kind == 'jsr_spmove':
        # JSR実行でSPが2減る(戻り先PC push)。sub内でX←SPを観測し、
        #   RET前にHALTすることでsub内SP(=SP_INIT-2)を突合。
        # main: SP init; JSR sub; HALT(fallback)
        # sub : X←SP; HALT   (RETせずsub内で止め、JSRによるSP-=2を観測)
        pre_jsr = ldw_sp_init()                       # 4B
        main_after_jsr = list(HALT)                   # 1B (fallback・到達しない)
        sub_body = mov_x_sp() + HALT                  # 2B+1B=3B
        sub_addr = CODE_ORG + len(pre_jsr) + 3 + len(main_after_jsr)
        code = pre_jsr + jsr(sub_addr) + main_after_jsr + sub_body
        return code, None, {}
    elif kind == 'nest_jsr':
        # 2段ネスト: main→sub1→sub2→(RET)→sub1→(RET)→main
        # main: SP init; JSR sub1; A←0x00FF(戻り確認); HALT
        # sub1: B←0x0011; JSR sub2; B←B|0x0100(sub2から戻った印); RET
        # sub2: X←0x2222; RET
        # 期待: 全段正しく戻ればA=0x00FF,B=0x0111,X=0x2222,SP=SP_INIT
        pre_jsr = ldw_sp_init()                       # 4B
        main_after = ldw_imm(A, 0x00FF) + HALT        # 5B
        base = CODE_ORG + len(pre_jsr)                # JSR sub1 の番地
        sub1_addr = base + 3 + len(main_after)        # sub1先頭
        # sub1本体を仮組みしてsub2番地算出
        #   sub1: B←0x0011(4B); JSR sub2(3B); B←B|0x0100 => ORI B,#0x0100(4B); RET(1B)
        sub1_head = ldw_imm(B, 0x0011)                # 4B
        sub1_tail = alu_imm(OP['ORI'], B, 0x0100) + ret()  # 4B+1B=5B
        sub2_addr = sub1_addr + len(sub1_head) + 3 + len(sub1_tail)
        sub1 = sub1_head + jsr(sub2_addr) + sub1_tail
        sub2 = ldw_imm(X, 0x2222) + ret()             # 4B+1B=5B
        code = pre_jsr + jsr(sub1_addr) + main_after + sub1 + sub2
        return code, None, {}
    elif kind == 'ret_only':
        # RET単体検証(HANDOVER §2 Q5是正): PUSH #imm は無いので
        #   「戻り先番地をLDWでregに→PUSH→RET」で手動スタック構築。
        # 積む値=HALT配置番地。RETがpop16した先(HALT)で停止すれば成功。
        # main: SP init; A←(halt_addr); PUSH A; RET  → PC=halt_addr へ
        #   halt_addr: A←0xD00D; HALT  (RETで到達した印にA上書き)
        pre = ldw_sp_init()                           # 4B
        # レイアウト: [pre][A←halt_addr(4B)][PUSH A(2B)][RET(1B)][halt: A←D00D(4B);HALT(1B)]
        halt_addr = CODE_ORG + len(pre) + 4 + 2 + 1
        target_seq = ldw_imm(A, halt_addr)            # 4B (Aに戻り先番地)
        push_seq = _assert_ext(push_reg(A), "PUSH A(ret_only)")  # 2B
        halt_body = ldw_imm(A, 0xD00D) + HALT         # 4B+1B
        code = pre + target_seq + push_seq + ret() + halt_body
        return code, None, {}
    else:
        raise ValueError(kind)

SUB = [
    # (id, kind, spec)  SP突合対象・6word
    ("JSR_RET",     "jsr_ret",    {}),
    ("JSR_SPmove",  "jsr_spmove", {}),
    ("NEST_JSR",    "nest_jsr",   {}),
    ("RET_only_chk","ret_only",   {}),
]

# ---------------------------------------------------------------------
#  C8 制御割込 ベクタ (★V2-e新規)
#   grp=ctl: EI/DI/IRET 命令単体  / grp=irq: SYSCALL受理シーケンス
#   全ベクタ先頭でSP初期化。SP突合対象(6word)。
#   ★受理系(irq)はベクタ$0008にhandler番地を preseed で書く(§2.3/R-1)。
#   ★IRETの「積むPC/FLAGSの順」は手計算せず emu23黄金に委ねる(HANDOVER §6)。
# ---------------------------------------------------------------------
IRQ4_VEC = 0x0008         # ★R-1確定: SYSCALL単独→irq_pending=4→vec=rd16($0008)
HANDLER_ORG = 0x0300      # 受理ハンドラ配置番地(コード域$0100〜と非干渉)

def build_ctl(kind, spec):
    """C8制御命令単体ベクタ。返り: (code, preseed, meta)。"""
    code = ldw_sp_init()                      # SP=SP_INIT で明示初期化
    if kind == 'ei_set':
        # EI で FLAGS.IE(0x80) がセット。F=0x80 を突合。
        code += ei()
        code += HALT
    elif kind == 'di_clear':
        # EI後 DI で IE クリア。F=0x00(他ビット非汚染)を突合。
        code += ei()
        code += di()
        code += HALT
    elif kind == 'iret_basic':
        # 手動で [PC][FLAGS] を積み IRET。PC←戻り先, F←積値下位8bit。
        #   IRET は flags=(u8)pop16; pc=pop16 (先flags pop→後pc pop)。
        #   LIFO: 先popされるflagsを後push / 後popされるpcを先push。
        #   ★積むPC=戻り先(target)番地。target: A←0xD1CE; HALT。
        #   ★積むFLAGS=0x0021(下位8bit=0x21が復元されるか確認)。
        pre = ldw_sp_init()                   # 4B (SP初期化・codeを組み直す)
        # レイアウト: [pre][A←target(4B)][PUSH A(2B)]      ← PC を先push
        #             [A←flags_val(4B)][PUSH A(2B)]        ← FLAGS を後push
        #             [IRET(1B)] → target へ
        #             target: A←0xD1CE(4B); HALT(1B)
        target = CODE_ORG + 4 + (4+2) + (4+2) + 1
        flags_val = 0x0021                    # 下位8bit=0x21(Z=1,N=0,他)
        code = pre
        code += ldw_imm(A, target)            # A←戻り先番地
        code += _assert_ext(push_reg(A), "PUSH PC(iret_basic)")
        code += ldw_imm(A, flags_val)         # A←積むFLAGS
        code += _assert_ext(push_reg(A), "PUSH FLAGS(iret_basic)")
        code += iret()
        code += ldw_imm(A, 0xD1CE) + HALT     # target: 到達印
        return code, None, {}
    elif kind == 'iret_mask':
        # FLAGS上位に1を積み IRET。(uint8_t)キャストで上位が0にマスク。
        #   積むFLAGS=0xFF80(上位0xFF・下位0x80)。復元後 F=0x80(下位8bitのみ)。
        pre = ldw_sp_init()
        target = CODE_ORG + 4 + (4+2) + (4+2) + 1
        flags_val = 0xFF80                    # 上位0xFF→マスクされ下位0x80のみ残る
        code = pre
        code += ldw_imm(A, target)
        code += _assert_ext(push_reg(A), "PUSH PC(iret_mask)")
        code += ldw_imm(A, flags_val)
        code += _assert_ext(push_reg(A), "PUSH FLAGS(iret_mask)")
        code += iret()
        code += ldw_imm(A, 0xD1CE) + HALT
        return code, None, {}
    else:
        raise ValueError(kind)
    return code, None, {}

def build_irq(kind, spec):
    """C8割込受理ベクタ。返り: (code, preseed, meta)。
       ★ベクタ$0008=HANDLER_ORG を preseed で書き、SYSCALL受理で飛ばす。"""
    vec_seed = {IRQ4_VEC: [HANDLER_ORG & 0xFF, (HANDLER_ORG >> 8) & 0xFF]}
    if kind == 'sys_accept':
        # main: SP init; EI; SYSCALL; HALT(fallback・受理で踏まない)
        # handler@$0300: A←0x1234; HALT
        # 期待: A=0x1234(受理到達), SP=SP_INIT-4(push×2), F IE=0
        main = ldw_sp_init() + ei() + syscall() + HALT
        handler = ldw_imm(A, 0x1234) + HALT
        preseed = dict(vec_seed)
        preseed[HANDLER_ORG] = handler
        return main, preseed, {}
    elif kind == 'sys_noEI':
        # EI無しで SYSCALL(IE=0で受理されない)。irq_pending立つが非受理。
        # main: SP init; SYSCALL; A←0xBEAD; HALT
        #   受理されなければ SYSCALL後そのまま次命令(A←0xBEAD)実行しHALT。
        #   黄金が示す最終状態(A=0xBEAD, 受理せず)をRTLと突合。
        main = ldw_sp_init() + syscall() + ldw_imm(A, 0xBEAD) + HALT
        handler = ldw_imm(A, 0x1234) + HALT   # 置くが到達しないはず
        preseed = dict(vec_seed)
        preseed[HANDLER_ORG] = handler
        return main, preseed, {}
    elif kind == 'sys_iret':
        # 受理→handler内IRET→main復帰→HALT(往復対称・C-2三者一致)。
        # main: SP init; EI; SYSCALL; (受理)→handler→IRET→ここに戻る
        #       ↓戻り先: A←0xFACE; HALT
        # handler@$0300: (受理到達印)B←0x00C8; IRET
        # 期待: A=0xFACE(復帰到達), B=0x00C8(handler通過), SP=SP_INIT(往復で戻る)
        main = ldw_sp_init() + ei() + syscall() + ldw_imm(A, 0xFACE) + HALT
        handler = ldw_imm(B, 0x00C8) + iret()
        preseed = dict(vec_seed)
        preseed[HANDLER_ORG] = handler
        return main, preseed, {}
    else:
        raise ValueError(kind)

CTL = [
    # (id, kind, spec)  SP突合対象・6word
    ("EI_set",     "ei_set",     {}),
    ("DI_clear",   "di_clear",   {}),
    ("IRET_basic", "iret_basic", {}),
    ("IRET_mask",  "iret_mask",  {}),
]

IRQV = [
    # (id, kind, spec)  SP突合対象・6word
    ("SYS_accept", "sys_accept", {}),
    ("SYS_noEI",   "sys_noEI",   {}),
    ("SYS_iret",   "sys_iret",   {}),
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

    # --- C6 スタック (V2-d・SP突合) ---
    for (vid, kind, spec) in STACK:
        code, pre, meta = build_stack(kind, spec)
        run_vec(vid, "stk", code, pre, meta, None)

    # --- C7 サブルーチン (V2-d・SP突合) ---
    for (vid, kind, spec) in SUB:
        code, pre, meta = build_sub(kind, spec)
        run_vec(vid, "sub", code, pre, meta, None)

    # --- C8 制御命令単体 (V2-e・SP突合) ---
    for (vid, kind, spec) in CTL:
        code, pre, meta = build_ctl(kind, spec)
        run_vec(vid, "ctl", code, pre, meta, None)

    # --- C8 割込受理 (V2-e・SP突合) ---
    for (vid, kind, spec) in IRQV:
        code, pre, meta = build_irq(kind, spec)
        run_vec(vid, "irq", code, pre, meta, None)

    # --- golden テキスト ---
    with open(f'{OUTDIR}/golden_v2e.txt','w') as f:
        f.write("# V2-e golden(emu23 v1.09). id grp PC SP F A B X wantF\n")
        for r in rows:
            (vid,grp,pc,sp,fl,a,b,x,wf) = r
            f.write(f"{vid} {grp} {pc:04X} {sp:04X} {fl:02X} "
                    f"{a:04X} {b:04X} {x:04X} {wf}\n")

    # --- expected hex: 1ベクタ6word (A,B,X,F,PC,SP) ---
    #   ★V2-d拡張: 6word目にSP追加。SP突合の可否はTB側でgrp判定。
    #   ★V2-e拡張: SP突合対象grpに ctl/irq を追加(stk/sub/ctl/irq)。
    #   既存64(leg/br/mem)もSP値は出力するがTBで突合対象外(HANDOVER §2 Q4)。
    with open(f'{OUTDIR}/expected_v2e.hex','w') as f:
        for r in rows:
            (vid,grp,pc,sp,fl,a,b,x,wf) = r
            f.write(f"{a:04X}\n{b:04X}\n{x:04X}\n{fl:04X}\n{pc:04X}\n{sp:04X}\n")

    # --- veclist: id grp (TBがSP突合対象grp[stk/sub/ctl/irq]を判定するのに使用) ---
    with open(f'{OUTDIR}/veclist_v2e.txt','w') as f:
        for r in rows:
            f.write(f"{r[0]} {r[1]}\n")

    # --- SP突合対象(stk/sub/ctl/irq)の件数レポート ---
    n_sp = sum(1 for r in rows if r[1] in ('stk','sub','ctl','irq'))
    print('-'*52)
    print(f"golden written: {OUTDIR}/golden_v2e.txt ({len(rows)} vectors)")
    print(f"expected hex  : {OUTDIR}/expected_v2e.hex ({len(rows)*6} words)")
    print(f"SP突合対象(stk/sub/ctl/irq): {n_sp} vectors / 全{len(rows)}")

if __name__ == '__main__':
    main()
