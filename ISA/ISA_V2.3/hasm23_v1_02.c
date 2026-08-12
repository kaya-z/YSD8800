// hasm23.c - YSD8800 ISA2.3 Assembler v1.02
// Version: 1.02 (2026-05-23)
// v1.02: .org 後退時の既存バイト上書き検出 (W001 警告)
//        ラベル二重定義検出 (E001 エラー)
//        既存問題: VARIABLE後のWORD_*が次のVARIABLEの.orgで黙って上書きされ
//                  WORD_DI_OP/EI_OP/KERN_TASK_*コードが消失し実行時HALTする
//                  事象を再発防止するため、書込み済みバイト追跡を導入。
//        実装: 64KB written_map[] でアドレスごとに書込済みフラグを管理。
//              .org で巻き戻った後、書込み済み領域にバイトを書く際に警告。
//        備考: 通常モード(非-c)で機能。-cモードは既存の後退エラーを継続。
//
// v1.01: -c オプション追加（YOF形式オブジェクトファイル出力）
//        lnk23 Phase 1対応: GLOBAL/LOCAL/UNDEFシンボル・R_ABS16リロケーション
//
// ISA2.3変更点 (ISA2.2からの差分):
//   SYSCALL: 3バイト(opcode+imm16) → 1バイト(opcodeのみ)
//   システムコール番号はAレジスタで渡す（呼び出し側責務）
//
//   例:
//     LDW  A, #0x0010  ; A ← syscall番号
//     SYSCALL           ; 1バイト: 0x05
//
// ISA2.2からの継承機能 (変更なし):
//   ビット演算命令 (0x50-0x59):
//     AND/ANDI OR/ORI XOR/XORI NOT SHL SHR SAR
//   拡張プレフィックス (0x1F):
//     PUSH A/B/X  POP A/B/X
//     LDB A/B,[addr]  LDB A/B,[X]
//     STB A/B,[addr]  STB A/B,[X]
//
// 互換性:
//   ISA2.3はISA2.2との後方互換なし（SYSCALL命令のみ非互換）
//   SYSCALL以外の命令はhasm22と完全互換
//
// build: gcc -std=c99 -O2 -Wall hasm23.c -o hasm23

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <ctype.h>

#define MAX_SYM   1024
#define MAX_DBG   8192
#define MAX_LINE  256
#define MAX_REL   4096   /* YOF リロケーションエントリ上限 */

/* YOF リロケーション記録（-cモード用） */
typedef struct {
    uint16_t offset;    /* セクション内パッチ位置 */
    char     sym[32];   /* 参照シンボル名 */
    uint8_t  type;      /* 0=R_ABS16 */
} rel_entry_t;

static rel_entry_t rels[MAX_REL];
static int         rel_count = 0;

// ===================== EXT prefix sub-opcode table =====================
// フォーマット: { mnemonic, reg_name("A"/"B"/"X"/""), addr_mode, sub_opcode }
// addr_mode:
//   EXT_NONE   : オペランドなし          (PUSH/POP)
//   EXT_ABS    : [imm16] 続く            (LDB/STB absolute)
//   EXT_INDRX  : [X] (暗黙インデックス)  (LDB/STB [X])

#define EXT_NONE   0
#define EXT_ABS    1
#define EXT_INDRX  2

typedef struct {
    const char *mnemonic;   // "PUSH","POP","LDB","STB"
    const char *reg;        // "A","B","X","" (対象レジスタ名)
    int  addr_mode;
    uint8_t sub_opcode;
} ext_instr_t;

static ext_instr_t ext_instrs[] = {
    // Stack
    {"PUSH", "A", EXT_NONE,  0x00},
    {"PUSH", "B", EXT_NONE,  0x01},
    {"PUSH", "X", EXT_NONE,  0x02},
    {"POP",  "A", EXT_NONE,  0x03},
    {"POP",  "B", EXT_NONE,  0x04},
    {"POP",  "X", EXT_NONE,  0x05},

    // 8bit Load
    {"LDB",  "A", EXT_ABS,   0x10},
    {"LDB",  "A", EXT_INDRX, 0x11},
    {"LDB",  "B", EXT_ABS,   0x12},
    {"LDB",  "B", EXT_INDRX, 0x13},

    // 8bit Store
    {"STB",  "A", EXT_ABS,   0x14},
    {"STB",  "A", EXT_INDRX, 0x15},
    {"STB",  "B", EXT_ABS,   0x16},
    {"STB",  "B", EXT_INDRX, 0x17},
};
static int ext_instr_count = sizeof(ext_instrs)/sizeof(ext_instrs[0]);

#define EXT_PREFIX 0x1F

// ===================== ISA2.0 base instructions =====================

typedef struct {
    const char *mnemonic;
    uint8_t opcode;
    int has_reg;
    int has_imm;
    int imm_is_rel;
} instr_t;

static instr_t instrs[] = {
    // Control
    {"NOP",     0x00, 0, 0, 0},
    {"HALT",    0x01, 0, 0, 0},
    {"EI",      0x02, 0, 0, 0},
    {"DI",      0x03, 0, 0, 0},
    {"IRET",    0x04, 0, 0, 0},
    {"SYSCALL", 0x05, 0, 0, 0},  // ISA2.3: 1バイト。番号はAレジスタで渡す
    {"BRK",     0x06, 0, 0, 0},

    // Data Transfer
    {"MOV",     0x20, 1, 0, 0},

    // ALU
    {"ADD",     0x40, 1, 0, 0},
    {"ADDI",    0x41, 1, 1, 0},
    {"SUB",     0x42, 1, 0, 0},
    {"SUBI",    0x43, 1, 1, 0},
    {"CMP",     0x44, 1, 0, 0},
    {"CMPI",    0x45, 1, 1, 0},

    // ISA2.2 Bit operations (0x50-0x59)
    {"AND",     0x50, 1, 0, 0},
    {"ANDI",    0x51, 1, 1, 0},
    {"OR",      0x52, 1, 0, 0},
    {"ORI",     0x53, 1, 1, 0},
    {"XOR",     0x54, 1, 0, 0},
    {"XORI",    0x55, 1, 1, 0},
    {"NOT",     0x56, 1, 0, 0},   // rD のみ使用 (rS=0固定)
    {"SHL",     0x57, 1, 0, 0},
    {"SHR",     0x58, 1, 0, 0},
    {"SAR",     0x59, 1, 0, 0},

    // Branch / Flow
    {"JMP",     0x60, 0, 1, 1},
    {"BEQ",     0x61, 0, 1, 1},
    {"BNE",     0x62, 0, 1, 1},
    {"BLT",     0x63, 0, 1, 1},
    {"BGE",     0x64, 0, 1, 1},
    {"JSR",     0x68, 0, 1, 0},
    {"RET",     0x69, 0, 0, 0},
};
static int instr_count = sizeof(instrs)/sizeof(instrs[0]);

// ===================== Symbols / Debug =====================

typedef struct {
    char name[64];
    uint16_t addr;
} symbol_t;

typedef struct {
    uint16_t addr;
    int line;
    int prio;
    char text[128];
} dbgline_t;

static symbol_t symbols[MAX_SYM];
static int sym_count = 0;

static dbgline_t dbg[MAX_DBG];
static int dbg_count = 0;

/* v1.02: 書込み済みアドレスマップ (.org 後退時の重ね書き検出用)
 * 64KB 全アドレスに対し 1=書込済、0=未書込 を記録。
 * PASS2 で命令/データ出力時にマークし、既にマークされていれば W001 警告。 */
static uint8_t written_map[65536];
static int     overlap_warn_count = 0;
static int     curr_lineno_for_warn = 0;   /* 警告に行番号を出すための共有 */
/* 同一アドレスで何度も警告しないようにする抑制 (1アドレス1回) */
static uint8_t warned_map[65536];
/* 警告表示上限。これを超えたらメッセージを出さずカウントのみ */
#define OVERLAP_WARN_MAX 20

// ===================== Utilities =====================

static char *trim(char *s) {
    while (isspace((unsigned char)*s)) s++;
    if (*s == 0) return s;
    char *e = s + strlen(s) - 1;
    while (e > s && isspace((unsigned char)*e)) *e-- = 0;
    return s;
}

// "$xxxx" / "0xXXXX" / 数値 の何れでも正しく解析する ORG/DW 向けパーサ
static uint16_t parse_addr(const char *s) {
    while (isspace((unsigned char)*s)) s++;
    if (s[0] == '$') return (uint16_t)strtol(s + 1, NULL, 16);
    return (uint16_t)strtol(s, NULL, 0);  // 0x... / 10進
}

static void strtoupper(char *s) {
    for (; *s; s++) *s = toupper((unsigned char)*s);
}

static int is_label(const char *s) {
    size_t n = strlen(s);
    return n > 0 && s[n-1] == ':';
}

static int parse_reg(const char *s) {
    if (strcmp(s, "A")     == 0) return 0;
    if (strcmp(s, "B")     == 0) return 1;
    if (strcmp(s, "X")     == 0) return 2;
    if (strcmp(s, "SP")    == 0) return 3;
    if (strcmp(s, "PC")    == 0) return 4;
    if (strcmp(s, "FLAGS") == 0) return 5;
    return -1;
}

// 即値パーサ (ISA2.0 互換)
//   #xxxx / #$xxxx / #$LABEL / $xxxx / 0xXXXX / 10進 / LABEL
static uint16_t parse_imm(const char *s, int *is_label_ref, char *label) {
    *is_label_ref = 0;
    int had_hash = 0;

    if (s[0] == '#') { had_hash = 1; s++; }

    if (s[0] == '$') {
        s++;
        if (had_hash) {
            int all_hex = 1;
            const char *p = s;
            if (*p == '\0') { fprintf(stderr, "Invalid #$ form\n"); exit(1); }
            while (*p) { if (!isxdigit((unsigned char)*p)) { all_hex = 0; break; } p++; }
            if (all_hex) return (uint16_t)strtol(s, NULL, 16);
            *is_label_ref = 1;
            strncpy(label, s, 63); label[63] = '\0';
            return 0;
        }
        return (uint16_t)strtol(s, NULL, 16);
    }

    if (strstr(s, "0x") == s || strstr(s, "0X") == s)
        return (uint16_t)strtol(s, NULL, 16);

    if (!had_hash) {
        if (isdigit((unsigned char)s[0]) || (s[0]=='-' && isdigit((unsigned char)s[1])))
            return (uint16_t)strtol(s, NULL, 10);
        *is_label_ref = 1;
        strncpy(label, s, 63); label[63] = '\0';
        return 0;
    }

    // had_hash && not $ / 0x
    // ルール: 純粋10進数(0-9のみ) → decimal, 16進文字含む → hex
    {
        int all_hex = 1, all_dec = 1;
        const char *q = s;
        if (*q == '\0') { fprintf(stderr, "Invalid immediate after #\n"); exit(1); }
        while (*q) {
            if (!isxdigit((unsigned char)*q)) { all_hex = 0; }
            if (!isdigit((unsigned char)*q))  { all_dec = 0; }
            q++;
        }
        if (!all_hex) {
            fprintf(stderr, "Label cannot start with # (use #$LABEL): #%s\n", s);
            exit(1);
        }
        if (all_dec) return (uint16_t)strtol(s, NULL, 10);
        return (uint16_t)strtol(s, NULL, 16);
    }
}

static symbol_t *find_sym(const char *name) {
    for (int i = 0; i < sym_count; i++)
        if (strcmp(symbols[i].name, name) == 0)
            return &symbols[i];
    return NULL;
}

static uint16_t parse_equ_expr(const char *expr, int lineno) {
    char buf[128];
    strncpy(buf, expr, sizeof(buf)-1); buf[sizeof(buf)-1] = '\0';
    char *plus = strchr(buf, '+');
    if (plus) {
        *plus = 0;
        char *left = trim(buf), *right = trim(plus + 1);
        int il = 0, ir = 0; char ll[64], lr[64];
        uint16_t vl = parse_imm(left, &il, ll);
        uint16_t vr = parse_imm(right, &ir, lr);
        if (il) { symbol_t *s = find_sym(ll); if (!s) { fprintf(stderr,"Undef sym in EQU: %s line %d\n",ll,lineno); exit(1); } vl = s->addr; }
        if (ir) { symbol_t *s = find_sym(lr); if (!s) { fprintf(stderr,"Undef sym in EQU: %s line %d\n",lr,lineno); exit(1); } vr = s->addr; }
        return vl + vr;
    }
    int il = 0; char ll[64];
    uint16_t v = parse_imm(trim(buf), &il, ll);
    if (il) { symbol_t *s = find_sym(ll); if (!s) { fprintf(stderr,"Undef sym in EQU: %s line %d\n",ll,lineno); exit(1); } v = s->addr; }
    return v;
}

static instr_t *find_instr(const char *m) {
    for (int i = 0; i < instr_count; i++)
        if (strcmp(instrs[i].mnemonic, m) == 0)
            return &instrs[i];
    return NULL;
}

int cmp_dbg(const void *a, const void *b) {
    const dbgline_t *x = a, *y = b;
    if (x->addr != y->addr) return (int)x->addr - (int)y->addr;
    return x->prio - y->prio;
}

// ===================== Vector ID Map =====================

static int get_vector_id(const char *name) {
    char tmp[32];
    strncpy(tmp, name, sizeof(tmp)-1); tmp[sizeof(tmp)-1] = '\0';
    strtoupper(tmp);
    if (strcmp(tmp, "RESET")   == 0) return 0;
    if (strcmp(tmp, "IRQ0")    == 0) return 1;
    if (strcmp(tmp, "IRQ1")    == 0) return 2;
    if (strcmp(tmp, "ALIGN")   == 0) return 3;
    if (strcmp(tmp, "SYSCALL") == 0) return 4;
    return -1;
}

// ===================== Line Parser =====================

static void parse_line(char *line, char *mnem, char *op1, char *op2, int *n_args) {
    char *semi = strchr(line, ';');
    if (semi) *semi = '\0';
    line = trim(line);
    mnem[0] = op1[0] = op2[0] = '\0';
    *n_args = 0;
    if (*line == '\0') return;

    char *sp = line;
    while (*sp && !isspace((unsigned char)*sp)) sp++;
    size_t mlen = sp - line;
    strncpy(mnem, line, mlen); mnem[mlen] = '\0';
    strtoupper(mnem);
    *n_args = 1;

    line = trim(sp);
    if (*line == '\0') return;

    char *comma = strchr(line, ',');
    if (comma) {
        *comma = '\0';
        strcpy(op1, trim(line));
        strcpy(op2, trim(comma + 1));
        *n_args = 3;
    } else {
        strcpy(op1, trim(line));
        *n_args = 2;
    }
}

// ===================== EXT instruction helpers =====================

// PUSH/POP/LDB/STB のオペランド文字列を解析して ext_instr_t* を返す
// 見つからない場合は NULL
//
// mnem: "PUSH"/"POP"/"LDB"/"STB"
// op1:  "A" / "B" / "X"
// op2:  "" (PUSH/POP) / "[addr]" / "[X]" (LDB/STB)
//
// 返す情報:
//   *out_sub : サブオペコード
//   *out_addr: アドレスモード (EXT_NONE / EXT_ABS / EXT_INDRX)
static const ext_instr_t *find_ext_instr(const char *mnem, const char *reg_name, int addr_mode) {
    for (int i = 0; i < ext_instr_count; i++) {
        if (strcmp(ext_instrs[i].mnemonic, mnem) == 0 &&
            strcmp(ext_instrs[i].reg,      reg_name) == 0 &&
            ext_instrs[i].addr_mode == addr_mode)
            return &ext_instrs[i];
    }
    return NULL;
}

// op2 の "[...]" 内を解析してアドレスモードを判定
//   "[X]"    → EXT_INDRX, imm=0
//   "[addr]" → EXT_ABS,   *imm/lbl セット
// 戻り値: EXT_INDRX / EXT_ABS / -1(構文エラー)
static int parse_ext_addr(const char *op2, uint16_t *imm, int *is_lbl, char *lbl) {
    *imm = 0; *is_lbl = 0; lbl[0] = '\0';
    // "[...]" の形をチェック
    size_t len = strlen(op2);
    if (len < 2 || op2[0] != '[' || op2[len-1] != ']') return -1;

    char inside[64];
    strncpy(inside, op2+1, len-2); inside[len-2] = '\0';
    char *ins = trim(inside);

    // [X]
    if (strcmp(ins, "X") == 0) return EXT_INDRX;

    // [addr]
    *imm = parse_imm(ins, is_lbl, lbl);
    return EXT_ABS;
}

// ===================== Instruction size calculation =====================

// EXT 命令サイズ: prefix(1) + sub_opcode(1) [+ imm16(2)]
static int ext_size(int addr_mode) {
    return 2 + (addr_mode == EXT_ABS ? 2 : 0);
}

// LDW/STW サイズ計算
static int parse_ldw_stw_size(const char *mnem, const char *op2, int lineno) {
    char *op2t = trim((char*)op2);
    if (op2t[0] == '#') return 1 + 1 + 2;  // LDW rD, #imm16
    if (op2t[0] == '[' && op2t[strlen(op2t)-1] == ']') {
        char inside[64];
        size_t len = strlen(op2t);
        strncpy(inside, op2t+1, len-2); inside[len-2] = 0;
        char *ins = trim(inside);
        if (parse_reg(ins) >= 0) return 1 + 1;           // [rS]
        if (strncmp(ins,"X+",2)==0 || strncmp(ins,"X +",3)==0) return 1+1+2; // [X+imm]
        return 1 + 1 + 2;                                 // [abs]
    }
    fprintf(stderr, "Invalid operand for %s at line %d\n", mnem, lineno);
    exit(1);
}

// ===================== Main =====================

/* ============================================================
 * YOF出力（-cオプション用）
 * lnk23_design_v1_2.docx §2 に準拠
 * ============================================================ */

/* YOF固定バイト数（設計書§2参照） */
#define YOF_HDR_SZ  16
#define YOF_SEC_SZ   8
#define YOF_SYM_SZ  36
#define YOF_REL_SZ   6

/* シンボル種別（YOFと同じ定義） */
#define YSYM_GLOBAL 'G'
#define YSYM_LOCAL  'L'
#define YSYM_UNDEF  'U'

/*
 * シンボル種別の判定ルール：
 *   - アンダースコアで始まるシンボル → GLOBAL（他.objから参照可能）
 *   - それ以外 → LOCAL（.obj内スコープ）
 * ※ UNDEF（外部参照）はhasm23では発生しない（単一ファイルアセンブル）
 *   UNDEFが必要になるのはscc23が分割コンパイルに対応するPhase 2以降。
 */
static char yof_sym_kind(const char *name) {
    return (name[0] == '_') ? YSYM_GLOBAL : YSYM_LOCAL;
}

/* LE 16bit書き込み */
static void yof_wr16(FILE *f, uint16_t v) {
    fputc(v & 0xFF, f);
    fputc((v >> 8) & 0xFF, f);
}

static int write_yof(const char *outpath, const uint8_t *code, int code_size,
                     symbol_t *syms, int nsym,
                     rel_entry_t *rls, int nrel) {
    FILE *f = fopen(outpath, "wb");
    if (!f) { perror(outpath); return -1; }

    /* シンボルインデックス逆引き（リロケーションのsym_idx解決用） */
    /* sym_idxはシンボルテーブル内のインデックス */
    int sym_idx_for_rel[MAX_REL];
    for (int r = 0; r < nrel; r++) {
        sym_idx_for_rel[r] = -1;
        for (int s = 0; s < nsym; s++) {
            if (strcmp(syms[s].name, rls[r].sym) == 0) {
                sym_idx_for_rel[r] = s;
                break;
            }
        }
        if (sym_idx_for_rel[r] < 0) {
            fprintf(stderr, "hasm23: YOF: unresolved reloc sym '%s'\n", rls[r].sym);
            fclose(f);
            return -1;
        }
    }

    /* --- ヘッダ (16バイト) --- */
    /* file_offsetはセクションエントリに0固定で書くため変数不要 */
    fwrite("YOF1", 1, 4, f);           /* magic */
    fputc(1, f);                        /* version */
    fputc(1, f);                        /* sec_count = 1 (TEXTのみ) */
    yof_wr16(f, (uint16_t)nsym);       /* sym_count */
    yof_wr16(f, (uint16_t)nrel);       /* rel_count */
    fwrite("\0\0\0\0\0\0", 1, 6, f);   /* reserved */

    /* --- セクションテーブル (8バイト × 1) --- */
    fputc(0, f);                        /* type: TEXT=0 */
    fputc(0x0B, f);                     /* flags: ALLOC|EXEC|READ = 0b00001011 */
    yof_wr16(f, 0);                     /* file_offset: 0（セクションデータ先頭） */
    yof_wr16(f, (uint16_t)code_size);  /* size */
    yof_wr16(f, 0);                     /* load_addr: obj時点=0固定（R13） */

    /* --- シンボルテーブル (36バイト × nsym) --- */
    for (int i = 0; i < nsym; i++) {
        char name32[32];
        memset(name32, 0, 32);
        memcpy(name32, syms[i].name, 31); /* 31文字+NUL保証 */
        fwrite(name32, 1, 32, f);       /* name[32] */
        fputc(0, f);                    /* sec_idx: 0 (唯一のTEXTセクション) */
        yof_wr16(f, syms[i].addr);     /* offset */
        /* リロケーション対象シンボルはUNDEF('U')で出力 */
        char kind = yof_sym_kind(syms[i].name);
        for (int r2 = 0; r2 < nrel; r2++) {
            if (strcmp(rls[r2].sym, syms[i].name) == 0) { kind = YSYM_UNDEF; break; }
        }
        fputc(kind, f);
    }

    /* --- リロケーションテーブル (6バイト × nrel) --- */
    for (int r = 0; r < nrel; r++) {
        fputc(0, f);                          /* sec_idx: 0 */
        yof_wr16(f, rls[r].offset);           /* offset（パッチ位置） */
        yof_wr16(f, (uint16_t)sym_idx_for_rel[r]); /* sym_idx */
        fputc(rls[r].type, f);                /* type: R_ABS16=0 */
    }

    /* --- セクションデータ (コードバイト列) --- */
    fwrite(code, 1, code_size, f);

    fclose(f);
    return 0;
}

int main(int argc, char **argv) {
    int opt_yof = 0;   /* -c: YOF出力モード */

    if (argc < 2) {
        fprintf(stderr, "hasm23 v1.02 (2026-05-23) for YSD8800 ISA2.3\n"
                        "usage: hasm23 [-c] file.asm\n"
                        "  -c  : output YOF object file (.obj) for lnk23\n"
                        "  ISA2.3 assembler for YSD8800\n"
                        "  SYSCALL: 1 byte (ISA2.3). Set syscall number in A before SYSCALL.\n"
                        "  Extensions over ISA2.2 (unchanged):\n"
                        "    PUSH/POP A|B|X\n"
                        "    LDB/STB  A|B, [addr] | [X]\n"
                        "    AND/OR/XOR/NOT/SHL/SHR/SAR\n");
        return 1;
    }

    /* -c オプション解析 */
    const char *asm_file = NULL;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-c") == 0) {
            opt_yof = 1;
        } else if (argv[i][0] != '-') {
            asm_file = argv[i];
        } else {
            fprintf(stderr, "hasm23: unknown option: %s\n", argv[i]);
            return 1;
        }
    }
    if (!asm_file) {
        fprintf(stderr, "hasm23: no input file\n");
        return 1;
    }

    /* 常時バナー表示 (v1.02〜) */
    fprintf(stderr, "hasm23 v1.02 (2026-05-23) for YSD8800 ISA2.3\n");

    FILE *fp = fopen(asm_file, "r");
    if (!fp) { perror("open"); return 1; }

    char linebuf[MAX_LINE];
    uint16_t pc = 0;
    int lineno = 0;

    // ========== PASS 1: ラベル収集 & PC 計算 ==========
    while (fgets(linebuf, sizeof(linebuf), fp)) {
        lineno++;
        char rawbuf[MAX_LINE];          // parse_line前の生ライン保存用
        strncpy(rawbuf, linebuf, sizeof(rawbuf)-1); rawbuf[sizeof(rawbuf)-1] = '\0';
        char *line = trim(linebuf);
        if (*line == 0 || *line == ';') continue;

        if (is_label(line)) {
            line[strlen(line)-1] = 0;
            if (sym_count >= MAX_SYM) { fprintf(stderr,"Too many symbols\n"); return 1; }
            /* v1.02: ラベル二重定義チェック (E001 エラー)
             * 既存シンボル(EQU/前のラベル定義)と同名なら拒否する。
             * EQUによる外部参照placeholder(後で本体ラベルが付く)も誤検出に
             * なりうるが、ASM内では原則として禁止扱いとする。
             */
            for (int i = 0; i < sym_count; i++) {
                if (strcmp(symbols[i].name, line) == 0) {
                    fprintf(stderr, "hasm23: E001 line %d: label '%s' redefined (previous addr=$%04X)\n",
                            lineno, line, symbols[i].addr);
                    return 1;
                }
            }
            strcpy(symbols[sym_count].name, line);
            symbols[sym_count].addr = pc;
            sym_count++;
            continue;
        }

        if (line[0] == '.') {
            if (strncmp(line, ".org", 4) == 0) {
                if (opt_yof) {
                    uint16_t new_pc = parse_addr(line + 4);
                    if (new_pc > pc) pc = new_pc; /* パディング分PCを進める */
                    /* 後退は後でエラーにする（PASS2で検出） */
                } else {
                    pc = parse_addr(line + 4);
                }
            } else if (strncmp(line, ".vector", 7) == 0) {
                // サイズなし (別アドレスに書く)
            } else if (strncmp(line, ".word", 5) == 0 || strncmp(line, ".dw", 3) == 0) {
                pc += 2;
            } else if (strncmp(line, ".byte", 5) == 0 || strncmp(line, ".db", 3) == 0) {
                char *arg = trim(line + (line[1]=='b' ? 5 : 3));
                if (arg[0] == '"') pc += (uint16_t)(strlen(arg) - 2);
                else pc += 1;
            }
            continue;
        }

        // SYMBOL EQU expr
        {
            char tok1[64], tok2[64], expr[128];
            int n = sscanf(line, "%63s %63s %127s", tok1, tok2, expr);
            if (n >= 2) {
                strtoupper(tok2);
                if (strcmp(tok2, "EQU") == 0) {
                    if (n < 3) { fprintf(stderr,"Invalid EQU at line %d\n", lineno); return 1; }
                    if (sym_count >= MAX_SYM) { fprintf(stderr,"Too many symbols\n"); return 1; }
                    strcpy(symbols[sym_count].name, tok1);
                    symbols[sym_count].addr = parse_equ_expr(expr, lineno);
                    sym_count++;
                    continue;
                }
            }
        }

        char mnem[32], op1[64], op2[64];
        int n;
        parse_line(line, mnem, op1, op2, &n);
        if (mnem[0] == '\0') continue;

        // EQU (旧形式)
        if (strcmp(mnem, "EQU") == 0) {
            char lbl2[64], expr[128];
            if (sscanf(line, "%63s EQU %127s", lbl2, expr) == 2) {
                if (sym_count >= MAX_SYM) { fprintf(stderr,"Too many symbols\n"); return 1; }
                strcpy(symbols[sym_count].name, lbl2);
                symbols[sym_count].addr = parse_equ_expr(expr, lineno);
                sym_count++;
            } else { fprintf(stderr,"Invalid EQU at line %d\n", lineno); return 1; }
            continue;
        }

        // ---- EXT 命令 (PUSH/POP/LDB/STB) ----
        if (strcmp(mnem, "PUSH") == 0 || strcmp(mnem, "POP") == 0) {
            if (n < 2) { fprintf(stderr,"Expect operand for %s at line %d\n", mnem, lineno); return 1; }
            // サイズ: prefix + sub_opcode = 2
            pc += 2;
            continue;
        }
        if (strcmp(mnem, "LDB") == 0 || strcmp(mnem, "STB") == 0) {
            if (n != 3) { fprintf(stderr,"Expect 2 operands for %s at line %d\n", mnem, lineno); return 1; }
            // アドレスモード判定
            uint16_t dummy_imm; int dummy_lbl; char dummy_lb[64];
            int am = parse_ext_addr(op2, &dummy_imm, &dummy_lbl, dummy_lb);
            if (am < 0) { fprintf(stderr,"Invalid addr for %s at line %d\n", mnem, lineno); return 1; }
            pc += (uint16_t)ext_size(am);
            continue;
        }

        // ---- LDW / STW ----
        if (strcmp(mnem, "LDW") == 0 || strcmp(mnem, "STW") == 0) {
            if (n != 3) { fprintf(stderr,"Expect 2 operands for %s at line %d\n", mnem, lineno); return 1; }
            pc += (uint16_t)parse_ldw_stw_size(mnem, op2, lineno);
            continue;
        }

        // ---- DW / DB ----
        if (strcmp(mnem, "DW") == 0) { pc += 2; continue; }
        if (strcmp(mnem, "DB") == 0) {
            // parse_line() はカンマを '\0' に変換するため line は破壊済み。
            // rawbuf (parse_line前のコピー) からコメント除去してパースし直す。
            char dbbuf[MAX_LINE];
            strncpy(dbbuf, rawbuf, sizeof(dbbuf)-1); dbbuf[sizeof(dbbuf)-1] = '\0';
            char *semi2 = strchr(dbbuf, ';'); if (semi2) *semi2 = '\0';
            char *dbstart = trim(dbbuf);
            char *p = dbstart; while (*p && !isspace((unsigned char)*p)) p++; // skip "DB"
            p = trim(p);
            while (*p) {
                if (*p == '"') {
                    p++;
                    char *end = strchr(p, '"');
                    if (!end) { fprintf(stderr,"Unterminated string in DB at line %d\n", lineno); exit(1); }
                    pc += (uint16_t)(end - p);
                    p = end + 1;
                } else {
                    pc += 1;
                    while (*p && *p != ',' && !isspace((unsigned char)*p)) p++;
                }
                if (*p == ',') p++;
                p = trim(p);
            }
            continue;
        }

        // ---- 基本命令 ----
        instr_t *in = find_instr(mnem);
        if (!in) { fprintf(stderr,"Unknown instruction '%s' at line %d\n", mnem, lineno); return 1; }
        pc += 1;
        if (in->has_reg) pc += 1;
        if (in->has_imm) pc += 2;
    }

    // ========== PASS 2: コード生成 ==========
    rewind(fp);
    pc = 0; lineno = 0;

    char outbin[256], outsym[256], outdbg[256], outobj[256];
    snprintf(outbin, sizeof(outbin), "%s.bin", asm_file);
    snprintf(outsym, sizeof(outsym), "%s.sym", asm_file);
    snprintf(outdbg, sizeof(outdbg), "%s.dbg", asm_file);
    snprintf(outobj, sizeof(outobj), "%s.obj", asm_file);

    /* -cモード: コードをメモリバッファに蓄積してYOFとして出力
     * 非-cモード: 従来通りfbに直接書き出し（既存動作を完全保持） */
    static uint8_t code_buf[65536];
    int code_buf_pos = 0;

    FILE *fb = opt_yof ? NULL : fopen(outbin, "wb");
    FILE *fs = opt_yof ? NULL : fopen(outsym, "w");
    FILE *fd = fopen(outdbg, "w");
    if (!opt_yof && (!fb || !fs)) { perror("output open"); return 1; }
    if (!fd) { perror("output open dbg"); return 1; }

    /* fputc相当のマクロ: -cモードはバッファへ、通常モードはファイルへ
     * v1.02: 書込み済みアドレス追跡 (.org 後退時の重ね書き検出)
     *  - 通常モード(非-c): ftell(fb) で書込位置を取得し written_map[pos] を確認
     *    既に1なら W001 警告を1回だけ出す (同一アドレス重複警告抑制)
     *  - -c モード: code_buf_pos が書込位置。code_buf は OUT_BYTE 後に pos++ するので
     *    マーク対象は code_buf_pos (post-increment 前)
     *  - 警告は stderr に「hasm23: W001 line N: overwrite at $XXXX」形式で出力
     *  - 同一アドレスへの正規再アセンブル(通常 .org による意図的なベクタ書込み)で
     *    過剰警告にならないよう、warned_map で1回のみ抑制
     */
#define OUT_BYTE(b) do { \
    long _wpos; \
    if (opt_yof) { _wpos = code_buf_pos; code_buf[code_buf_pos++] = (uint8_t)(b); } \
    else { _wpos = ftell(fb); fputc((b), fb); } \
    if (_wpos >= 0 && _wpos < 65536) { \
        if (written_map[_wpos] && !warned_map[_wpos]) { \
            if (overlap_warn_count < OVERLAP_WARN_MAX) { \
                fprintf(stderr, "hasm23: W001 line %d: .org overlap — byte at $%04lX already written, now overwriting\n", \
                        curr_lineno_for_warn, _wpos); \
            } else if (overlap_warn_count == OVERLAP_WARN_MAX) { \
                fprintf(stderr, "hasm23: W001 (further overlap warnings suppressed; summary at end)\n"); \
            } \
            warned_map[_wpos] = 1; \
            overlap_warn_count++; \
        } \
        written_map[_wpos] = 1; \
    } \
} while(0)

    // 通常モード: シンボルテーブル出力
    if (!opt_yof) {
        for (int i = 0; i < sym_count; i++)
            fprintf(fs, "%04x %s\n", symbols[i].addr, symbols[i].name);
    }

    // DBG リセット (pass1 で溜めたものを pass2 で再収集)
    dbg_count = 0;

    while (fgets(linebuf, sizeof(linebuf), fp)) {
        lineno++;
        curr_lineno_for_warn = lineno;   /* v1.02: 警告出力用 */
        char orig[MAX_LINE];
        strcpy(orig, linebuf);
        char *line = trim(linebuf);
        if (*line == 0 || *line == ';') continue;
        if (is_label(line)) continue;

        // デバッグ情報
        if (dbg_count < MAX_DBG) {
            dbg[dbg_count].addr = pc;
            dbg[dbg_count].line = lineno;
            dbg[dbg_count].prio = 1;
            strncpy(dbg[dbg_count].text, trim(orig), sizeof(dbg[dbg_count].text)-1);
            dbg[dbg_count].text[sizeof(dbg[dbg_count].text)-1] = 0;
            dbg_count++;
        }

        if (line[0] == '.') {
            if (strncmp(line, ".org", 4) == 0) {
                if (opt_yof) {
                    /* -cモード: .orgは指定アドレスまでゼロパディングを挿入
                     * これによりベクタテーブル等の絶対配置を維持できる
                     * ただし .org でPCが戻る（後退）場合はエラー */
                    uint16_t new_pc = parse_addr(line + 4);
                    if (new_pc < pc) {
                        fprintf(stderr, "hasm23: -c mode: .org $%04X < current pc $%04X (backward .org not supported)\n", new_pc, pc);
                        return 1;
                    }
                    while (pc < new_pc) { OUT_BYTE(0x00); pc++; }
                    dbg_count--;
                    continue;
                }
                pc = parse_addr(line + 4);
                fseek(fb, pc, SEEK_SET);
            } else if (strncmp(line, ".vector", 7) == 0) {
                if (opt_yof) {
                    /* -cモード: .vectorはcode_bufの対応位置に直接書き込む */
                    char name[32], addrstr[64];
                    if (sscanf(line + 7, "%31s %63s", name, addrstr) != 2) {
                        fprintf(stderr,"Invalid .vector at line %d\n", lineno); return 1;
                    }
                    int id = get_vector_id(name);
                    if (id < 0) { fprintf(stderr,"Unknown vector '%s' at line %d\n", name, lineno); return 1; }
                    int is_lbl2 = 0; char lbl2[64] = "";
                    uint16_t handler = parse_imm(addrstr, &is_lbl2, lbl2);
                    if (is_lbl2) {
                        symbol_t *s = find_sym(lbl2);
                        if (!s) { fprintf(stderr,"Undefined label %s at line %d\n", lbl2, lineno); return 1; }
                        handler = s->addr;
                    }
                    int vec_pos = id * 2;
                    if (vec_pos + 1 < code_buf_pos) {
                        code_buf[vec_pos]   = (uint8_t)(handler & 0xFF);
                        code_buf[vec_pos+1] = (uint8_t)((handler >> 8) & 0xFF);
                    }
                    dbg_count--;
                    continue;
                }
                char name[32], addrstr[64];
                if (sscanf(line + 7, "%31s %63s", name, addrstr) != 2) {
                    fprintf(stderr,"Invalid .vector at line %d\n", lineno); return 1;
                }
                int id = get_vector_id(name);
                if (id < 0) { fprintf(stderr,"Unknown vector '%s' at line %d\n", name, lineno); return 1; }
                int is_lbl2 = 0; char lbl2[64] = "";
                uint16_t handler = parse_imm(addrstr, &is_lbl2, lbl2);
                if (is_lbl2) {
                    symbol_t *s = find_sym(lbl2);
                    if (!s) { fprintf(stderr,"Undefined label %s at line %d\n", lbl2, lineno); return 1; }
                    handler = s->addr;
                }
                // ベクタテーブルへ書き込み、書き込み位置を元に戻す
                long save_pos = ftell(fb);
                fseek(fb, (long)(id * 2), SEEK_SET);
                OUT_BYTE(handler & 0xff); OUT_BYTE(handler >> 8);
                fseek(fb, save_pos, SEEK_SET);
                // .vector は PC / DBG を変えない
                dbg_count--;
                continue;
            } else if (strncmp(line, ".word", 5) == 0 || strncmp(line, ".dw", 3) == 0) {
                char valstr[64];
                int offset = (line[1]=='w' ? 5 : 3);
                if (sscanf(line + offset, "%63s", valstr) != 1) {
                    fprintf(stderr,"Invalid .word/.dw at line %d\n", lineno); return 1;
                }
                int is_lbl2 = 0; char lbl2[64] = "";
                uint16_t v = parse_imm(valstr, &is_lbl2, lbl2);
                if (is_lbl2) { symbol_t *s = find_sym(lbl2); if (!s) { fprintf(stderr,"Undefined label %s at line %d\n",lbl2,lineno); return 1; } v = s->addr; }
                OUT_BYTE(v & 0xff); OUT_BYTE(v >> 8); pc += 2;
            } else if (strncmp(line, ".byte", 5) == 0 || strncmp(line, ".db", 3) == 0) {
                char valstr[128];
                int offset = (line[1]=='b' ? 5 : 3);
                if (sscanf(line + offset, "%127s", valstr) != 1) {
                    fprintf(stderr,"Invalid .byte/.db at line %d\n", lineno); return 1;
                }
                if (valstr[0] == '"') {
                    char *str = valstr + 1; str[strlen(str)-1] = 0;
                    for (char *c = str; *c; c++) { OUT_BYTE(*c); pc++; }
                } else {
                    int is_lbl2 = 0; char lbl2[64] = "";
                    uint8_t v = (uint8_t)parse_imm(valstr, &is_lbl2, lbl2);
                    if (is_lbl2) { symbol_t *s = find_sym(lbl2); if (!s) { fprintf(stderr,"Undefined label %s at line %d\n",lbl2,lineno); return 1; } v = (uint8_t)s->addr; }
                    OUT_BYTE(v); pc++;
                }
            }
            continue;
        }

        // SYMBOL EQU (pass2 では何もしない)
        {
            char tok1[64], tok2[64], expr[128];
            int n2 = sscanf(line, "%63s %63s %127s", tok1, tok2, expr);
            if (n2 >= 2) {
                strtoupper(tok2);
                if (strcmp(tok2, "EQU") == 0) { dbg_count--; continue; }
            }
        }

        char mnem[32], op1[64], op2[64];
        int n;
        parse_line(line, mnem, op1, op2, &n);
        if (mnem[0] == '\0') { dbg_count--; continue; }

        // EQU ニーモニック形式
        if (strcmp(mnem, "EQU") == 0) { dbg_count--; continue; }

        // ========== EXT 命令: PUSH / POP ==========
        if (strcmp(mnem, "PUSH") == 0 || strcmp(mnem, "POP") == 0) {
            if (n < 2) { fprintf(stderr,"%s: missing operand at line %d\n", mnem, lineno); return 1; }
            char reg_up[16];
            strncpy(reg_up, op1, sizeof(reg_up)-1); reg_up[sizeof(reg_up)-1] = '\0';
            strtoupper(reg_up);
            const ext_instr_t *ei = find_ext_instr(mnem, reg_up, EXT_NONE);
            if (!ei) { fprintf(stderr,"%s %s: unsupported register at line %d\n", mnem, op1, lineno); return 1; }
            OUT_BYTE(EXT_PREFIX);
            OUT_BYTE(ei->sub_opcode);
            pc += 2;
            continue;
        }

        // ========== EXT 命令: LDB / STB ==========
        if (strcmp(mnem, "LDB") == 0 || strcmp(mnem, "STB") == 0) {
            if (n != 3) { fprintf(stderr,"%s: expect 2 operands at line %d\n", mnem, lineno); return 1; }
            char reg_up[16];
            strncpy(reg_up, op1, sizeof(reg_up)-1); reg_up[sizeof(reg_up)-1] = '\0';
            strtoupper(reg_up);
            uint16_t imm2 = 0; int is_lbl2 = 0; char lbl2[64] = "";
            int am = parse_ext_addr(op2, &imm2, &is_lbl2, lbl2);
            if (am < 0) { fprintf(stderr,"%s: invalid address at line %d\n", mnem, lineno); return 1; }
            if (is_lbl2) {
                symbol_t *s = find_sym(lbl2);
                if (!s) { fprintf(stderr,"Undefined label %s at line %d\n", lbl2, lineno); return 1; }
                imm2 = s->addr;
            }
            const ext_instr_t *ei = find_ext_instr(mnem, reg_up, am);
            if (!ei) { fprintf(stderr,"%s %s,[...]: unsupported form at line %d\n", mnem, op1, lineno); return 1; }
            OUT_BYTE(EXT_PREFIX);
            OUT_BYTE(ei->sub_opcode);
            pc += 2;
            if (am == EXT_ABS) {
                OUT_BYTE(imm2 & 0xff); OUT_BYTE(imm2 >> 8);
                pc += 2;
            }
            continue;
        }

        // ========== LDW / STW ==========
        if (strcmp(mnem, "LDW") == 0 || strcmp(mnem, "STW") == 0) {
            if (n != 3) { fprintf(stderr,"Expect 2 operands for %s at line %d\n", mnem, lineno); return 1; }
            uint8_t opcode2; int has_imm2 = 0;
            int rD = -1, rS = -1;
            uint16_t imm2 = 0; int is_lbl2 = 0; char lbl2[64] = "";

            char *op1t = trim(op1);
            char *op2t = trim(op2);

            if (strcmp(mnem, "LDW") == 0) {
                rD = parse_reg(op1t);
                if (rD < 0) { fprintf(stderr,"Invalid register %s at line %d\n", op1t, lineno); return 1; }
                rS = 0;
                if (op2t[0] == '#') {
                    opcode2 = 0x21; has_imm2 = 1;
                    imm2 = parse_imm(op2t, &is_lbl2, lbl2);
                } else if (op2t[0] == '[' && op2t[strlen(op2t)-1] == ']') {
                    char inside[64]; size_t len = strlen(op2t);
                    strncpy(inside, op2t+1, len-2); inside[len-2] = 0;
                    char *ins = trim(inside);
                    int reg2 = parse_reg(ins);
                    if (reg2 >= 0) { opcode2 = 0x24; rS = reg2; }
                    else if (strncmp(ins,"X +",3)==0 || strncmp(ins,"X+",2)==0) {
                        char *off = trim(ins + (ins[1]==' ' ? 3 : 2));
                        if (off[0] != '#') { fprintf(stderr,"Expect # offset in [X+] at line %d\n", lineno); return 1; }
                        opcode2 = 0x26; has_imm2 = 1;
                        imm2 = parse_imm(off, &is_lbl2, lbl2); rS = 0;
                    } else {
                        if (ins[0] == '#') { fprintf(stderr,"No # for abs addr at line %d\n", lineno); return 1; }
                        opcode2 = 0x22; has_imm2 = 1;
                        imm2 = parse_imm(ins, &is_lbl2, lbl2); rS = 0;
                    }
                } else { fprintf(stderr,"Invalid operand for LDW at line %d\n", lineno); return 1; }
            } else { // STW
                rS = parse_reg(op1t);
                if (rS < 0) { fprintf(stderr,"Invalid register %s at line %d\n", op1t, lineno); return 1; }
                rD = 0;
                if (op2t[0] == '[' && op2t[strlen(op2t)-1] == ']') {
                    char inside[64]; size_t len = strlen(op2t);
                    strncpy(inside, op2t+1, len-2); inside[len-2] = 0;
                    char *ins = trim(inside);
                    int reg2 = parse_reg(ins);
                    if (reg2 >= 0) { opcode2 = 0x25; rD = reg2; }
                    else if (strncmp(ins,"X +",3)==0 || strncmp(ins,"X+",2)==0) {
                        char *off = trim(ins + (ins[1]==' ' ? 3 : 2));
                        if (off[0] != '#') { fprintf(stderr,"Expect # offset in [X+] at line %d\n", lineno); return 1; }
                        opcode2 = 0x27; has_imm2 = 1;
                        imm2 = parse_imm(off, &is_lbl2, lbl2); rD = 0;
                    } else {
                        if (ins[0] == '#') { fprintf(stderr,"No # for abs addr at line %d\n", lineno); return 1; }
                        opcode2 = 0x23; has_imm2 = 1;
                        imm2 = parse_imm(ins, &is_lbl2, lbl2); rD = 0;
                    }
                } else { fprintf(stderr,"Invalid operand for STW at line %d\n", lineno); return 1; }
            }
            if (is_lbl2) {
                symbol_t *s = find_sym(lbl2);
                if (!s) {
                    if (opt_yof && has_imm2) {
                        /* -cモード: UNDEFシンボル + R_ABS16リロケーション */
                        int already = 0;
                        for (int si = 0; si < sym_count; si++) {
                            if (strcmp(symbols[si].name, lbl2) == 0) { already = 1; break; }
                        }
                        if (!already && sym_count < MAX_SYM) {
                            strcpy(symbols[sym_count].name, lbl2);
                            symbols[sym_count].addr = 0;
                            sym_count++;
                        }
                        if (rel_count < MAX_REL) {
                            /* LDW/STW: opcode(1)+reg(1)=2バイト後が即値位置 */
                            rels[rel_count].offset = (uint16_t)(pc + 2);
                            memset(rels[rel_count].sym, 0, 32);
                            memcpy(rels[rel_count].sym, lbl2, 31);
                            rels[rel_count].type = 0; /* R_ABS16 */
                            rel_count++;
                        }
                        imm2 = 0;
                    } else {
                        fprintf(stderr,"Undefined label %s at line %d\n", lbl2, lineno);
                        return 1;
                    }
                } else {
                    imm2 = s->addr;
                }
            }
            OUT_BYTE(opcode2); pc++;
            OUT_BYTE(((rD & 0xF) << 4) | (rS & 0xF)); pc++;
            if (has_imm2) { OUT_BYTE(imm2 & 0xff); OUT_BYTE(imm2 >> 8); pc += 2; }
            continue;
        }

        // ========== DW / DB ==========
        if (strcmp(mnem, "DW") == 0) {
            int is_lbl2 = 0; char lbl2[64] = "";
            uint16_t v = parse_imm(op1, &is_lbl2, lbl2);
            if (is_lbl2) { symbol_t *s = find_sym(lbl2); if (!s) { fprintf(stderr,"Undefined label %s at line %d\n",lbl2,lineno); return 1; } v = s->addr; }
            OUT_BYTE(v & 0xff); OUT_BYTE(v >> 8); pc += 2;
            continue;
        }
        if (strcmp(mnem, "DB") == 0) {
            // parse_line() はカンマを '\0' に変換するため line は破壊済み。
            // orig (fgets直後のコピー) からコメント除去してパースし直す。
            char dbbuf[MAX_LINE];
            strncpy(dbbuf, orig, sizeof(dbbuf)-1); dbbuf[sizeof(dbbuf)-1] = '\0';
            char *semi2 = strchr(dbbuf, ';'); if (semi2) *semi2 = '\0';
            char *dbstart = trim(dbbuf);
            char *p = dbstart; while (*p && !isspace((unsigned char)*p)) p++; // skip "DB"
            p = trim(p);
            while (*p) {
                if (*p == '"') {
                    p++;
                    char *end = strchr(p, '"');
                    if (!end) { fprintf(stderr,"Unterminated string in DB at line %d\n",lineno); exit(1); }
                    while (p < end) { OUT_BYTE(*p++); pc++; }
                    p = end + 1;
                } else {
                    char token[64]; int ti = 0;
                    while (*p && *p != ',' && !isspace((unsigned char)*p)) token[ti++] = *p++;
                    token[ti] = 0;
                    if (ti > 0) {
                        int is_lbl2 = 0; char lbl2[64] = "";
                        uint8_t v = (uint8_t)parse_imm(token, &is_lbl2, lbl2);
                        if (is_lbl2) { symbol_t *s = find_sym(lbl2); if (!s) { fprintf(stderr,"Undefined label %s at line %d\n",lbl2,lineno); return 1; } v = (uint8_t)s->addr; }
                        OUT_BYTE(v); pc++;
                    }
                }
                if (*p == ',') p++;
                p = trim(p);
            }
            continue;
        }

        // ========== 基本命令 ==========
        {
            instr_t *in = find_instr(mnem);
            if (!in) { fprintf(stderr,"Unknown instruction '%s' at line %d\n", mnem, lineno); return 1; }
            uint16_t imm2 = 0; int is_lbl2 = 0; char lbl2[64] = "";
            int rD = -1, rS = -1;
            if (in->has_reg) {
                rD = parse_reg(trim(op1));
                // has_imm=1(ADDI/SUBI/CMPI等)はop2が即値→rS=0固定
                // has_imm=0(ADD/SUB/CMP/MOV等)はop2がレジスタ
                if (in->has_imm) {
                    rS = 0;
                } else {
                    rS = (n >= 3) ? parse_reg(trim(op2)) : 0;
                }
                if (rD < 0) { fprintf(stderr,"Invalid register at line %d\n", lineno); return 1; }
            }
            if (in->has_imm) {
                const char *imm_str = (n >= 3) ? op2 : op1;
                imm2 = parse_imm(trim((char*)imm_str), &is_lbl2, lbl2);
            }
            if (is_lbl2) {
                symbol_t *s = find_sym(lbl2);
                if (!s) {
                    if (opt_yof && in->has_imm && !in->imm_is_rel) {
                        /* -cモード: 未解決ラベル → UNDEFシンボル + R_ABS16リロケーション */
                        /* UNDEFシンボルをシンボルテーブルに追加（重複チェック） */
                        int already = 0;
                        for (int si = 0; si < sym_count; si++) {
                            if (strcmp(symbols[si].name, lbl2) == 0) { already = 1; break; }
                        }
                        if (!already) {
                            if (sym_count < MAX_SYM) {
                                strcpy(symbols[sym_count].name, lbl2);
                                symbols[sym_count].addr = 0; /* UNDEFなので0 */
                                sym_count++;
                            }
                        }
                        /* リロケーションエントリ記録 */
                        if (rel_count < MAX_REL) {
                            /* パッチ位置: opcodeの後（has_reg=1なら+1） */
                            rels[rel_count].offset = (uint16_t)(pc + 1 + in->has_reg);
                            memset(rels[rel_count].sym, 0, 32);
                            memcpy(rels[rel_count].sym, lbl2, 31);
                            rels[rel_count].type = 0; /* R_ABS16 */
                            rel_count++;
                        }
                        imm2 = 0; /* プレースホルダ */
                    } else {
                        fprintf(stderr,"Undefined label %s at line %d\n", lbl2, lineno);
                        return 1;
                    }
                } else if (in->imm_is_rel) {
                    imm2 = s->addr - (pc + 1 + in->has_reg + (in->has_imm ? 2 : 0));
                } else {
                    imm2 = s->addr;
                }
            }
            OUT_BYTE(in->opcode); pc++;
            if (in->has_reg) { OUT_BYTE(((rD & 0xF) << 4) | (rS & 0xF)); pc++; }
            if (in->has_imm) { OUT_BYTE(imm2 & 0xff); OUT_BYTE(imm2 >> 8); pc += 2; }
        }
    }

    // デバッグファイル出力
    qsort(dbg, dbg_count, sizeof(dbgline_t), cmp_dbg);
    for (int i = 0; i < dbg_count; i++)
        fprintf(fd, "%04x %d %s\n", dbg[i].addr, dbg[i].line, dbg[i].text);

    fclose(fp);
    fclose(fd);

    if (opt_yof) {
        /* -cモード: YOF出力 */
        if (write_yof(outobj, code_buf, code_buf_pos,
                      symbols, sym_count, rels, rel_count) < 0) {
            return 1;
        }
        printf("hasm23: assembled '%s' -> %s  [YOF: %d bytes code, %d syms, %d relocs]\n",
               asm_file, outobj, code_buf_pos, sym_count, rel_count);
    } else {
        /* 通常モード: .bin/.sym クローズ */
        fclose(fb);
        fclose(fs);
        printf("hasm23: assembled '%s' -> %s  (ISA2.3 / SYSCALL=1byte / EXT PUSH/POP/LDB/STB + AND/OR/XOR/NOT/SHL/SHR/SAR)\n",
               asm_file, outbin);
    }

    /* v1.02: 総括 — .org 重ね書き警告件数 */
    if (overlap_warn_count > 0) {
        fprintf(stderr, "hasm23: W001 summary: %d byte(s) were overwritten by .org backward jump(s)\n",
                overlap_warn_count);
    }

#undef OUT_BYTE
    return 0;
}
