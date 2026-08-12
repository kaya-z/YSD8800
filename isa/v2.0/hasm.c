// hasm.c - ISA2.0 Assembler v2.10
//  - EQU/DW/DB + LDW/STW + Vector Table
//  - #E000 形式を 0xE000 の即値として扱う
//  - #$LABEL でラベル即値 (LABEL のアドレス) をロード
//  - #LABEL はエラー (互換性維持)
//  - DB は複数要素対応: DB "DUP",0 / DB 1,2,3 など
// build: gcc -std=c99 -O2 -Wall hasm.c -o hasm

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <ctype.h>

#define MAX_SYM   1024
#define MAX_DBG   8192
#define MAX_LINE  256

// ===================== ISA2.0 =====================

typedef struct {
    const char *mnemonic;
    uint8_t opcode;
    int has_reg;      // has reg byte (rD|rS)
    int has_imm;      // has imm16
    int imm_is_rel;   // relative (for branches)
} instr_t;

static instr_t instrs[] = {
    // Control
    {"NOP",     0x00, 0, 0, 0},
    {"HALT",    0x01, 0, 0, 0},
    {"EI",      0x02, 0, 0, 0},
    {"DI",      0x03, 0, 0, 0},
    {"IRET",    0x04, 0, 0, 0},
    {"SYSCALL", 0x05, 0, 1, 0},
    {"BRK",     0x06, 0, 0, 0},

    // Data Transfer
    {"MOV",     0x20, 1, 0, 0},   // rD, rS

    // ALU
    {"ADD",     0x40, 1, 0, 0},
    {"ADDI",    0x41, 1, 1, 0},
    {"SUB",     0x42, 1, 0, 0},
    {"SUBI",    0x43, 1, 1, 0},
    {"CMP",     0x44, 1, 0, 0},
    {"CMPI",    0x45, 1, 1, 0},

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

// ===================== Utilities =====================

static char *trim(char *s) {
    while (isspace((unsigned char)*s)) s++;
    if (*s == 0) return s;
    char *e = s + strlen(s) - 1;
    while (e > s && isspace((unsigned char)*e)) *e-- = 0;
    return s;
}

static void strtoupper(char *s) {
    for (; *s; s++) *s = toupper((unsigned char)*s);
}

static int is_label(const char *s) {
    size_t n = strlen(s);
    return n > 0 && s[n-1] == ':';
}

static int parse_reg(const char *s) {
    if (strcmp(s, "A") == 0) return 0;
    if (strcmp(s, "B") == 0) return 1;
    if (strcmp(s, "X") == 0) return 2;
    if (strcmp(s, "SP") == 0) return 3;
    if (strcmp(s, "PC") == 0) return 4;
    if (strcmp(s, "FLAGS") == 0) return 5;
    return -1;
}

// 即値/ラベルパーサ
//  - $xxxx      → 16進
//  - 0x....     → 16進
//  - 数字       → 10進
//  - LABEL      → ラベル参照
//  - #1234      → 10進即値
//  - #0x1234    → 16進即値
//  - #$1234     → 16進即値
//  - #E000      → 16進即値 (E000h)
//  - #$LABEL    → ラベル即値 (LABEL のアドレス)
//  - #LABEL     → エラー
static uint16_t parse_imm(const char *s, int *is_label_ref, char *label) {
    *is_label_ref = 0;
    int had_hash = 0;

    if (s[0] == '#') {
        had_hash = 1;
        s++;
    }

    // $xxxx or #$xxxx / #$LABEL
    if (s[0] == '$') {
        s++;
        if (had_hash) {
            // #$... → 数値 or ラベル
            int all_hex = 1;
            const char *p = s;
            if (*p == '\0') {
                fprintf(stderr, "Invalid #$ form: empty after $\n");
                exit(1);
            }
            while (*p) {
                if (!isxdigit((unsigned char)*p)) {
                    all_hex = 0;
                    break;
                }
                p++;
            }
            if (all_hex) {
                return (uint16_t)strtol(s, NULL, 16);
            } else {
                // #$LABEL → ラベル即値
                *is_label_ref = 1;
                strncpy(label, s, 63);
                label[63] = '\0';
                return 0;
            }
        } else {
            // $xxxx → 16進数
            return (uint16_t)strtol(s, NULL, 16);
        }
    }

    // 0x... / 0X...
    if (!had_hash && (strstr(s, "0x") == s || strstr(s, "0X") == s)) {
        return (uint16_t)strtol(s, NULL, 16);
    }
    if (had_hash && (strstr(s, "0x") == s || strstr(s, "0X") == s)) {
        return (uint16_t)strtol(s, NULL, 16);
    }

    // 数値 (10進) or #E000 などの16進
    if (!had_hash) {
        if (isdigit((unsigned char)s[0]) ||
            (s[0]=='-' && isdigit((unsigned char)s[1]))) {
            return (uint16_t)strtol(s, NULL, 10);
        }
        // ラベル参照
        *is_label_ref = 1;
        strncpy(label, s, 63);
        label[63] = '\0';
        return 0;
    } else {
        // had_hash == 1, s は '$' でも '0x' でもない
        // ここで #E000 のような 16進文字列を許可する
        int all_hex = 1;
        const char *p = s;
        if (*p == '\0') {
            fprintf(stderr, "Invalid immediate after #: empty\n");
            exit(1);
        }
        while (*p) {
            if (!isxdigit((unsigned char)*p)) {
                all_hex = 0;
                break;
            }
            p++;
        }
        if (all_hex) {
            return (uint16_t)strtol(s, NULL, 16);
        }

        // それ以外 (#LABEL など) はエラー
        fprintf(stderr, "Label cannot start with # (use #$LABEL for label immediates): #%s\n", s);
        exit(1);
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
    strcpy(buf, expr);
    char *plus = strchr(buf, '+');
    if (plus) {
        *plus = 0;
        char *left = trim(buf);
        char *right = trim(plus + 1);
        int is_lbl_l = 0, is_lbl_r = 0;
        char lbl_l[64], lbl_r[64];
        uint16_t val_l = parse_imm(left, &is_lbl_l, lbl_l);
        uint16_t val_r = parse_imm(right, &is_lbl_r, lbl_r);
        if (is_lbl_l) {
            symbol_t *s = find_sym(lbl_l);
            if (!s) {
                fprintf(stderr, "Undefined symbol in EQU: %s at line %d\n", lbl_l, lineno);
                exit(1);
            }
            val_l = s->addr;
        }
        if (is_lbl_r) {
            symbol_t *s = find_sym(lbl_r);
            if (!s) {
                fprintf(stderr, "Undefined symbol in EQU: %s at line %d\n", lbl_r, lineno);
                exit(1);
            }
            val_r = s->addr;
        }
        return val_l + val_r;
    } else {
        int is_lbl = 0;
        char lbl[64];
        uint16_t val = parse_imm(trim(buf), &is_lbl, lbl);
        if (is_lbl) {
            symbol_t *s = find_sym(lbl);
            if (!s) {
                fprintf(stderr, "Undefined symbol in EQU: %s at line %d\n", lbl, lineno);
                exit(1);
            }
            val = s->addr;
        }
        return val;
    }
}

static instr_t *find_instr(const char *m) {
    for (int i = 0; i < instr_count; i++)
        if (strcmp(instrs[i].mnemonic, m) == 0)
            return &instrs[i];
    return NULL;
}

int cmp_dbg(const void *a, const void *b)
{
    const dbgline_t *x = a;
    const dbgline_t *y = b;

    if (x->addr != y->addr)
        return (int)x->addr - (int)y->addr;

    return x->prio - y->prio;
}

// ===================== Vector ID Map =====================

static int get_vector_id(const char *name) {
    char tmp[32];
    strncpy(tmp, name, sizeof(tmp)-1);
    tmp[sizeof(tmp)-1] = '\0';
    strtoupper(tmp);
    if (strcmp(tmp, "RESET") == 0)   return 0;
    if (strcmp(tmp, "IRQ0") == 0)    return 1;
    if (strcmp(tmp, "IRQ1") == 0)    return 2;
    if (strcmp(tmp, "ALIGN") == 0)   return 3;
    if (strcmp(tmp, "SYSCALL") == 0) return 4;
    return -1;
}

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
    strncpy(mnem, line, mlen);
    mnem[mlen] = '\0';
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

// LDW/STW サイズ計算
static int parse_ldw_stw_size(const char *mnem, const char *op1, const char *op2, int lineno) {
    (void)mnem;
    (void)op1;
    char *op2t = trim((char*)op2);
    int has_imm = 0;

    if (op2t[0] == '#') {
        has_imm = 1;
    } else if (op2t[0] == '[' && op2t[strlen(op2t)-1] == ']') {
        char inside[64];
        strncpy(inside, op2t+1, strlen(op2t)-2);
        inside[strlen(op2t)-2] = 0;
        char *ins = trim(inside);
        int reg = parse_reg(ins);
        if (reg >= 0) {
            has_imm = 0;
        } else if (strncmp(ins, "X +", 3) == 0 || strncmp(ins, "X+", 2) == 0) {
            has_imm = 1;
        } else {
            has_imm = 1;
        }
    } else {
        fprintf(stderr, "Invalid operand for %s at line %d\n", mnem, lineno);
        exit(1);
    }
    return 1 + 1 + (has_imm ? 2 : 0);
}

// ===================== Main =====================

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: hasm file.asm\n");
        return 1;
    }

    FILE *fp = fopen(argv[1], "r");
    if (!fp) { perror("open"); return 1; }

    char linebuf[MAX_LINE];
    uint16_t pc = 0;
    int lineno = 0;

    // -------- PASS 1: labels & PC --------
    while (fgets(linebuf, sizeof(linebuf), fp)) {
        lineno++;
        char *line = trim(linebuf);
        if (*line == 0 || *line == ';') continue;

        if (is_label(line)) {
            line[strlen(line)-1] = 0;
            strcpy(symbols[sym_count].name, line);
            symbols[sym_count].addr = pc;
            sym_count++;
            continue;
        }

        if (line[0] == '.') {
            if (strncmp(line, ".org", 4) == 0) {
                pc = (uint16_t)strtol(line+4, NULL, 0);
            } else if (strncmp(line, ".vector", 7) == 0) {
                char name[32];
                if (sscanf(line + 7, "%31s", name) == 1) {
                    if (dbg_count < MAX_DBG) {
                        dbg[dbg_count].addr = 0;
                        dbg[dbg_count].line = lineno;
                        dbg[dbg_count].prio = 0;
                        snprintf(dbg[dbg_count].text, sizeof(dbg[dbg_count].text), "<%s>", name);
                        dbg_count++;
                    }
                }
            } else if (strncmp(line, ".word", 5) == 0 || strncmp(line, ".dw", 3) == 0) {
                pc += 2;
            } else if (strncmp(line, ".byte", 5) == 0 || strncmp(line, ".db", 3) == 0) {
                // .byte/.db はここでは 1トークン扱いにせず、後で DB と同じロジックにしてもよいが
                // ひとまず従来どおり: 文字列なら長さ、数値なら1バイト
                char *arg = trim(line + (line[1] == 'b' ? 5 : 3));
                if (arg[0] == '"') {
                    pc += strlen(arg) - 2;
                } else {
                    pc += 1;
                }
            }
            continue;
        }

        // "SYMBOL EQU expr" 形式
        {
            char tok1[64], tok2[64], expr[128];
            int n = sscanf(line, "%63s %63s %127s", tok1, tok2, expr);
            if (n >= 2) {
                strtoupper(tok2);
                if (strcmp(tok2, "EQU") == 0) {
                    if (n < 3) {
                        fprintf(stderr, "Invalid EQU at line %d\n", lineno);
                        return 1;
                    }
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

        // 旧形式 "EQU label expr"
        if (strcmp(mnem, "EQU") == 0) {
            char lbl[64], expr[128];
            if (sscanf(line, "%63s EQU %127s", lbl, expr) == 2) {
                strcpy(symbols[sym_count].name, lbl);
                symbols[sym_count].addr = parse_equ_expr(expr, lineno);
                sym_count++;
            } else {
                fprintf(stderr, "Invalid EQU at line %d\n", lineno);
                return 1;
            }
            continue;
        }

        if (strcmp(mnem, "LDW") == 0 || strcmp(mnem, "STW") == 0) {
            if (n != 3) {
                fprintf(stderr, "Expect 2 operands for %s at line %d\n", mnem, lineno);
                return 1;
            }
            pc += parse_ldw_stw_size(mnem, op1, op2, lineno);
        } else if (strcmp(mnem, "DW") == 0) {
            pc += 2;
        } else if (strcmp(mnem, "DB") == 0) {
            // DB は複数要素対応
            char *p = line + 2; // "DB" の後ろ
            p = trim(p);
            while (*p) {
                if (*p == '"') {
                    p++;
                    char *end = strchr(p, '"');
                    if (!end) {
                        fprintf(stderr, "Unterminated string in DB at line %d\n", lineno);
                        exit(1);
                    }
                    pc += (end - p);  // 文字数
                    p = end + 1;
                } else {
                    // 数値1バイト
                    pc += 1;
                    while (*p && *p != ',' && !isspace((unsigned char)*p)) p++;
                }
                if (*p == ',') p++;
                p = trim(p);
            }
        } else {
            instr_t *in = find_instr(mnem);
            if (!in) {
                fprintf(stderr, "Unknown instr at line %d\n", lineno);
                return 1;
            }
            pc += 1;
            if (in->has_reg) pc += 1;
            if (in->has_imm) pc += 2;
        }
    }

    // -------- PASS 2: emit --------
    rewind(fp);
    pc = 0;
    lineno = 0;

    char outbin[256], outsym[256], outdbg[256];
    snprintf(outbin, sizeof(outbin), "%s.bin", argv[1]);
    snprintf(outsym, sizeof(outsym), "%s.sym", argv[1]);
    snprintf(outdbg, sizeof(outdbg), "%s.dbg", argv[1]);

    FILE *fb = fopen(outbin, "wb");
    FILE *fs = fopen(outsym, "w");
    FILE *fd = fopen(outdbg, "w");

    for (int i = 0; i < sym_count; i++)
        fprintf(fs, "%04x %s\n", symbols[i].addr, symbols[i].name);

    while (fgets(linebuf, sizeof(linebuf), fp)) {
        lineno++;
        char orig[MAX_LINE];
        strcpy(orig, linebuf);

        char *line = trim(linebuf);
        if (*line == 0 || *line == ';') continue;
        if (is_label(line)) continue;

        if (line[0] == '.') {
            if (strncmp(line, ".org", 4) == 0) {
                pc = (uint16_t)strtol(line+4, NULL, 0);
                fseek(fb, pc, SEEK_SET);
            } else if (strncmp(line, ".vector", 7) == 0) {
                char name[32], addrstr[64];
                if (sscanf(line + 7, "%31s %63s", name, addrstr) != 2) {
                    fprintf(stderr, "Invalid .vector at line %d\n", lineno);
                    return 1;
                }
                int id = get_vector_id(name);
                if (id < 0) {
                    fprintf(stderr, "Unknown vector name '%s' at line %d\n", name, lineno);
                    return 1;
                }
                uint16_t vec_addr = (uint16_t)(id * 2);

                int is_lbl = 0;
                char lbl[64] = "";
                uint16_t handler = parse_imm(addrstr, &is_lbl, lbl);
                if (is_lbl) {
                    symbol_t *s = find_sym(lbl);
                    if (!s) {
                        fprintf(stderr, "Undefined label %s at line %d\n", lbl, lineno);
                        return 1;
                    }
                    handler = s->addr;
                }

                fseek(fb, vec_addr, SEEK_SET);
                fputc(handler & 0xff, fb);
                fputc(handler >> 8, fb);
                continue;
            } else if (strncmp(line, ".word", 5) == 0 || strncmp(line, ".dw", 3) == 0) {
                char valstr[64];
                int offset = (line[1]=='w' ? 5 : 3);
                if (sscanf(line + offset, "%63s", valstr) != 1) {
                    fprintf(stderr, "Invalid .word/.dw at line %d\n", lineno);
                    return 1;
                }
                int is_lbl = 0;
                char lbl[64] = "";
                uint16_t v = parse_imm(valstr, &is_lbl, lbl);
                if (is_lbl) {
                    symbol_t *s = find_sym(lbl);
                    if (!s) {
                        fprintf(stderr, "Undefined label %s at line %d\n", lbl, lineno);
                        return 1;
                    }
                    v = s->addr;
                }
                fputc(v & 0xff, fb);
                fputc(v >> 8, fb);
                pc += 2;
                continue;
            } else if (strncmp(line, ".byte", 5) == 0 || strncmp(line, ".db", 3) == 0) {
                char valstr[128];
                int offset = (line[1]=='b' ? 5 : 3);
                if (sscanf(line + offset, "%127s", valstr) != 1) {
                    fprintf(stderr, "Invalid .byte/.db at line %d\n", lineno);
                    return 1;
                }
                if (valstr[0] == '"') {
                    char *str = valstr + 1;
                    str[strlen(str)-1] = 0;
                    for (char *c = str; *c; c++) {
                        fputc(*c, fb);
                        pc++;
                    }
                } else {
                    int is_lbl = 0;
                    char lbl[64] = "";
                    uint8_t v = (uint8_t)parse_imm(valstr, &is_lbl, lbl);
                    if (is_lbl) {
                        symbol_t *s = find_sym(lbl);
                        if (!s) {
                            fprintf(stderr, "Undefined label %s at line %d\n", lbl, lineno);
                            return 1;
                        }
                        v = (uint8_t)s->addr;
                    }
                    fputc(v, fb);
                    pc += 1;
                }
                continue;
            }
            continue;
        }

        // "SYMBOL EQU expr" 行は PASS2 では何もしない
        {
            char tok1[64], tok2[64], expr[128];
            int n = sscanf(line, "%63s %63s %127s", tok1, tok2, expr);
            if (n >= 2) {
                strtoupper(tok2);
                if (strcmp(tok2, "EQU") == 0) {
                    continue;
                }
            }
        }

        if (dbg_count < MAX_DBG) {
            dbg[dbg_count].addr = pc;
            dbg[dbg_count].line = lineno;
            dbg[dbg_count].prio = 1;
            strncpy(dbg[dbg_count].text, trim(orig), sizeof(dbg[dbg_count].text)-1);
            dbg[dbg_count].text[sizeof(dbg[dbg_count].text)-1] = 0;
            dbg_count++;
        }

        char mnem[32], op1[64], op2[64];
        int n;
        parse_line(line, mnem, op1, op2, &n);

        if (mnem[0] == '\0') continue;

        if (strcmp(mnem, "EQU") == 0) {
            continue;
        }

        // DW/DB 疑似命令
        if (strcmp(mnem, "DW") == 0) {
            int is_lbl = 0;
            char lbl[64];
            uint16_t v = parse_imm(op1, &is_lbl, lbl);
            if (is_lbl) {
                symbol_t *s = find_sym(lbl);
                if (!s) {
                    fprintf(stderr, "Undefined label %s at line %d\n", lbl, lineno);
                    return 1;
                }
                v = s->addr;
            }
            fputc(v & 0xff, fb);
            fputc(v >> 8, fb);
            pc += 2;
            continue;
        }
        if (strcmp(mnem, "DB") == 0) {
            char *p = line + 2;
            p = trim(p);
            while (*p) {
                if (*p == '"') {
                    p++;
                    char *end = strchr(p, '"');
                    if (!end) {
                        fprintf(stderr, "Unterminated string in DB at line %d\n", lineno);
                        exit(1);
                    }
                    while (p < end) {
                        fputc(*p++, fb);
                        pc++;
                    }
                    p = end + 1;
                } else {
                    char token[64];
                    int ti = 0;
                    while (*p && *p != ',' && !isspace((unsigned char)*p)) {
                        token[ti++] = *p++;
                    }
                    token[ti] = 0;
                    if (ti > 0) {
                        int is_lbl = 0;
                        char lbl[64];
                        uint8_t v = (uint8_t)parse_imm(token, &is_lbl, lbl);
                        if (is_lbl) {
                            symbol_t *s = find_sym(lbl);
                            if (!s) {
                                fprintf(stderr, "Undefined label %s at line %d\n", lbl, lineno);
                                return 1;
                            }
                            v = (uint8_t)s->addr;
                        }
                        fputc(v, fb);
                        pc++;
                    }
                }
                if (*p == ',') p++;
                p = trim(p);
            }
            continue;
        }

        uint8_t opcode = 0;
        int has_reg = 0;
        int has_imm = 0;
        int imm_is_rel = 0;
        int rD = -1, rS = -1;
        uint16_t imm = 0;
        int is_lbl = 0;
        char lbl[64] = "";

        if (strcmp(mnem, "LDW") == 0 || strcmp(mnem, "STW") == 0) {
            if (n != 3) {
                fprintf(stderr, "Expect 2 operands for %s at line %d\n", mnem, lineno);
                return 1;
            }
            has_reg = 1;
            char *op1t = trim(op1);
            char *op2t = trim(op2);

            if (strcmp(mnem, "LDW") == 0) {
                rD = parse_reg(op1t);
                if (rD < 0) {
                    fprintf(stderr, "Invalid register %s at line %d\n", op1t, lineno);
                    return 1;
                }
                rS = 0;
                if (op2t[0] == '#') {
                    opcode = 0x21;
                    has_imm = 1;
                    imm = parse_imm(op2t, &is_lbl, lbl);
                } else if (op2t[0] == '[' && op2t[strlen(op2t)-1] == ']') {
                    char inside[64];
                    strncpy(inside, op2t+1, strlen(op2t)-2);
                    inside[strlen(op2t)-2] = 0;
                    char *ins = trim(inside);
                    int reg = parse_reg(ins);
                    if (reg >= 0) {
                        opcode = 0x24;
                        has_imm = 0;
                        rS = reg;
                    } else if (strncmp(ins, "X +", 3) == 0 || strncmp(ins, "X+", 2) == 0) {
                        char *off_start = ins + (ins[1] == ' ' ? 3 : 2);
                        char *off = trim(off_start);
                        if (off[0] != '#') {
                            fprintf(stderr, "Expect # for offset in [X +] at line %d\n", lineno);
                            return 1;
                        }
                        opcode = 0x26;
                        has_imm = 1;
                        imm = parse_imm(off, &is_lbl, lbl);
                        rS = 0;
                    } else {
                        if (ins[0] == '#') {
                            fprintf(stderr, "No # for absolute address at line %d\n", lineno);
                            return 1;
                        }
                        opcode = 0x22;
                        has_imm = 1;
                        imm = parse_imm(ins, &is_lbl, lbl);
                        rS = 0;
                    }
                } else {
                    fprintf(stderr, "Invalid operand for LDW at line %d\n", lineno);
                    return 1;
                }
            } else {  // STW
                rS = parse_reg(op1t);
                if (rS < 0) {
                    fprintf(stderr, "Invalid register %s at line %d\n", op1t, lineno);
                    return 1;
                }
                rD = 0;
                if (op2t[0] == '[' && op2t[strlen(op2t)-1] == ']') {
                    char inside[64];
                    strncpy(inside, op2t+1, strlen(op2t)-2);
                    inside[strlen(op2t)-2] = 0;
                    char *ins = trim(inside);
                    int reg = parse_reg(ins);
                    if (reg >= 0) {
                        opcode = 0x25;
                        has_imm = 0;
                        rD = reg;
                    } else if (strncmp(ins, "X +", 3) == 0 || strncmp(ins, "X+", 2) == 0) {
                        char *off_start = ins + (ins[1] == ' ' ? 3 : 2);
                        char *off = trim(off_start);
                        if (off[0] != '#') {
                            fprintf(stderr, "Expect # for offset in [X +] at line %d\n", lineno);
                            return 1;
                        }
                        opcode = 0x27;
                        has_imm = 1;
                        imm = parse_imm(off, &is_lbl, lbl);
                        rD = 0;
                    } else {
                        if (ins[0] == '#') {
                            fprintf(stderr, "No # for absolute address at line %d\n", lineno);
                            return 1;
                        }
                        opcode = 0x23;
                        has_imm = 1;
                        imm = parse_imm(ins, &is_lbl, lbl);
                        rD = 0;
                    }
                } else {
                    fprintf(stderr, "Invalid operand for STW at line %d\n", lineno);
                    return 1;
                }
            }
        } else {
            instr_t *in = find_instr(mnem);
            if (!in) {
                fprintf(stderr, "Unknown instr at line %d\n", lineno);
                return 1;
            }
            opcode = in->opcode;
            has_reg = in->has_reg;
            has_imm = in->has_imm;
            imm_is_rel = in->imm_is_rel;

            if (has_reg) {
                rD = parse_reg(trim(op1));
                rS = (n >= 3) ? parse_reg(trim(op2)) : 0;
                if (rD < 0) {
                    fprintf(stderr, "Invalid register at line %d\n", lineno);
                    return 1;
                }
            }
            if (has_imm) {
                const char *imm_str = (n >= 3) ? op2 : op1;
                imm = parse_imm(trim((char*)imm_str), &is_lbl, lbl);
            }
        }

        if (is_lbl) {
            symbol_t *s = find_sym(lbl);
            if (!s) {
                fprintf(stderr, "Undefined label %s at line %d\n", lbl, lineno);
                return 1;
            }
            if (imm_is_rel) {
                imm = s->addr - (pc + 1 + has_reg + (has_imm ? 2 : 0));
            } else {
                imm = s->addr;
            }
        }

        fputc(opcode, fb);
        pc++;
        if (has_reg) {
            uint8_t rb = ((rD & 0xF) << 4) | (rS & 0xF);
            fputc(rb, fb);
            pc++;
        }
        if (has_imm) {
            fputc(imm & 0xff, fb);
            fputc(imm >> 8, fb);
            pc += 2;
        }
    }

    qsort(dbg, dbg_count, sizeof(dbgline_t), cmp_dbg);

    for (int i = 0; i < dbg_count; i++) {
        fprintf(fd, "%04x %d %s\n",
                dbg[i].addr,
                dbg[i].line,
                dbg[i].text);
    }

    fclose(fp);
    fclose(fb);
    fclose(fs);
    fclose(fd);

    printf("Assembled: %s  (v2.10: #$LABEL + #E000 + LDW/STW + EQU/DW/DB + multi-DB)\n", outbin);
    return 0;
}
