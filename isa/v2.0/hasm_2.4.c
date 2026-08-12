// hasm.c - ISA2.0 Assembler v2.4 (Vector Table Support + rel offset fix)
// build: gcc -std=c99 -O2 -Wall hasm.c -o hasm
// Updated by Grok for new YSD8800 interrupt specification (vector table at 0x0000)
// .vector <name> <addr> is now equivalent to .org (id*2) .dw <addr>
// Fixed by Grok v2.4: corrected rel16 offset calculation for branch instructions
//                    imm = s.addr - (pc + 1 + has_reg + (has_imm ? 2 : 0))
// Generated/Modified by Grok

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

static uint16_t parse_imm(const char *s, int *is_label_ref, char *label) {
    *is_label_ref = 0;
    int has_hash = 0;
    if (s[0] == '#') {
        has_hash = 1;
        s++;
    }
    if (isdigit((unsigned char)s[0]) ||
        (s[0]=='-' && isdigit((unsigned char)s[1]))) {
        if (strstr(s, "0x") == s) return (uint16_t)strtol(s, NULL, 16);
        return (uint16_t)strtol(s, NULL, 10);
    }
    if (has_hash) {
        fprintf(stderr, "Label cannot start with #\n");
        exit(1);
    }
    *is_label_ref = 1;
    strcpy(label, s);
    return 0;
}

static symbol_t *find_sym(const char *name) {
    for (int i = 0; i < sym_count; i++)
        if (strcmp(symbols[i].name, name) == 0)
            return &symbols[i];
    return NULL;
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

static int parse_ldw_stw_size(const char *mnem, const char *op1, const char *op2, int lineno) {
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
            } else if (strncmp(line, ".byte", 5) == 0) {
                pc += 1;
            }
            continue;
        }

        char mnem[32], op1[64], op2[64];
        int n;
        parse_line(line, mnem, op1, op2, &n);

        if (mnem[0] == '\0') continue;

        if (strcmp(mnem, "LDW") == 0 || strcmp(mnem, "STW") == 0) {
            if (n != 3) {
                fprintf(stderr, "Expect 2 operands for %s at line %d\n", mnem, lineno);
                return 1;
            }
            pc += parse_ldw_stw_size(mnem, op1, op2, lineno);
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
            } else if (strncmp(line, ".byte", 5) == 0) {
                uint8_t v = (uint8_t)strtol(line+5, NULL, 0);
                fputc(v, fb);
                pc += 1;
                continue;
            }
            continue;
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

        uint8_t opcode;
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

    printf("Assembled: %s  (v2.4 vector table enabled)\n", outbin);
    return 0;
}
