// hasm.c - ISA2.0 Assembler (2-pass, debug enabled)
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
    {"LDW",     0x21, 1, 1, 0},   // rD, #imm16
    {"LDWA",    0x22, 1, 1, 0},   // rD, [imm16]
    {"STWA",    0x23, 1, 1, 0},   // rS, [imm16]
    {"LDWR",    0x24, 1, 0, 0},   // rD, [rS]
    {"STWR",    0x25, 1, 0, 0},   // rS, [rD]
    {"LDWX",    0x26, 1, 1, 0},   // rD, [X+imm16]
    {"STWX",    0x27, 1, 1, 0},   // rS, [X+imm16]

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
    return -1;
}

static uint16_t parse_imm(const char *s, int *is_label_ref, char *label) {
    *is_label_ref = 0;
    if (s[0] == '#') s++;
    if (isdigit((unsigned char)s[0]) ||
	(s[0]=='-' && isdigit((unsigned char)s[1]))) {
      if (strstr(s, "0x") == s) return (uint16_t)strtol(s, NULL, 16);
      return (uint16_t)strtol(s, NULL, 10);
    }
    // label
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

    return x->prio - y->prio;  // ★ vector が先
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
        char orig[MAX_LINE];
        strcpy(orig, linebuf);

        char *line = trim(linebuf);
        if (*line == 0 || *line == ';') continue;

        if (is_label(line)) {
            line[strlen(line)-1] = 0;
            strcpy(symbols[sym_count].name, line);
            symbols[sym_count].addr = pc;
            sym_count++;
            continue;
        }

	//        if (line[0] == '.') {
	//            if (strncmp(line, ".org", 4) == 0) {
	//                pc = (uint16_t)strtol(line+4, NULL, 0);
	//            } else if (strncmp(line, ".word", 5) == 0) {
	//                pc += 2;
	//            } else if (strncmp(line, ".byte", 5) == 0) {
	//                pc += 1;
	//            } 
	//            continue;
	//        }

	if (line[0] == '.') {
	  if (strncmp(line, ".org", 4) == 0) {
	    pc = (uint16_t)strtol(line+4, NULL, 0);
	    
	  } else if (strncmp(line, ".word", 5) == 0) {
	    pc += 2;
	    
	  } else if (strncmp(line, ".byte", 5) == 0) {
	    pc += 1;

	  } else if (strncmp(line, ".vector", 7) == 0) {
	    /* ---- .vector <name> <addr> ---- */
	    char name[32];
	    unsigned addr;

	    /* ".vector irq0 0x0010" を読む */
	    if (sscanf(line + 7, "%31s %x", name, &addr) == 2) {
	      if (dbg_count < MAX_DBG) {
                dbg[dbg_count].addr = (uint16_t)addr;
                dbg[dbg_count].line = lineno;
		dbg[dbg_count].prio = 0;   // ★ vector は最優先
                snprintf(dbg[dbg_count].text,
                         sizeof(dbg[dbg_count].text),
                         "<%s>", name);
                dbg_count++;
	      }
	    }
	    /* PC は進めない（命令じゃない） */
	  }
	  
	  continue;
	}

	
        // instruction length
        char mnem[32];
        sscanf(line, "%31s", mnem);
        strtoupper(mnem);
        instr_t *in = find_instr(mnem);
        if (!in) {
            fprintf(stderr, "Unknown instr at line %d\n", lineno);
            return 1;
        }
        pc += 1;                 // opcode
        if (in->has_reg) pc += 1;
        if (in->has_imm) pc += 2;

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

    // write symbols
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
            } else if (strncmp(line, ".word", 5) == 0) {
                uint16_t v = (uint16_t)strtol(line+5, NULL, 0);
                fputc(v & 0xff, fb);
                fputc(v >> 8, fb);
                pc += 2;
            } else if (strncmp(line, ".byte", 5) == 0) {
                uint8_t v = (uint8_t)strtol(line+5, NULL, 0);
                fputc(v, fb);
                pc += 1;
            }
            continue;
        }

	// collect debug info
	if (dbg_count < MAX_DBG) {
	  dbg[dbg_count].addr = pc;
	  dbg[dbg_count].line = lineno;
	  dbg[dbg_count].prio = 1;   // ★ 通常命令
	  strncpy(dbg[dbg_count].text, trim(orig), sizeof(dbg[dbg_count].text)-1);
	  dbg[dbg_count].text[sizeof(dbg[dbg_count].text)-1] = 0;
	  dbg_count++;
	}

        char mnem[32], op1[64], op2[64];
        int n = sscanf(line, "%31s %63[^,], %63s", mnem, op1, op2);
        strtoupper(mnem);
        instr_t *in = find_instr(mnem);

        fputc(in->opcode, fb);
        pc++;

        if (in->has_reg) {
            int rD = -1, rS = 0;
            if (n >= 2) rD = parse_reg(trim(op1));
            if (n >= 3) rS = parse_reg(trim(op2));
            uint8_t rb = ((rD & 0xF) << 4) | (rS & 0xF);
            fputc(rb, fb);
            pc++;
        }

        if (in->has_imm) {
            int is_lbl;
            char lbl[64];
            uint16_t imm = parse_imm(n>=3?op2:op1, &is_lbl, lbl);
            if (is_lbl) {
                symbol_t *s = find_sym(lbl);
                if (!s) { fprintf(stderr, "Undefined label %s\n", lbl); return 1; }
                if (in->imm_is_rel)
                    imm = s->addr - (pc + 2);
                else
                    imm = s->addr;
            }
            fputc(imm & 0xff, fb);
            fputc(imm >> 8, fb);
            pc += 2;
        }
    }

    qsort(dbg, dbg_count, sizeof(dbgline_t), cmp_dbg);
	
    // write debug file
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

    printf("Assembled: %s\n", outbin);
    return 0;
}
