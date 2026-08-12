/*
 * hasm.c – hand assembler for mycpu ISA v1.0
 *
 * Features:
 *  - 2-pass assembler
 *  - label / forward reference support
 *  - PC-relative branch (8bit disp)
 *  - -g option: generate .sym for emulator
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <ctype.h>

#define MAXSYM   256
#define MAXFIX   256
#define MAXCODE  65536

/* =========================================================
 * symbol table
 * ========================================================= */

typedef struct {
    char     name[32];
    uint16_t addr;
} sym_t;

static sym_t symtab[MAXSYM];
static int nsym;

/* =========================================================
 * branch fixups
 * ========================================================= */

typedef struct {
    char     label[32];
    uint16_t pc;     /* address of branch opcode */
} fix_t;

static fix_t fixups[MAXFIX];
static int nfix;

/* =========================================================
 * code buffer
 * ========================================================= */

static uint8_t  code[MAXCODE];
static uint16_t pc;

/* =========================================================
 * debug (.sym)
 * ========================================================= */

static int debug_flag = 0;
static FILE *symfp = NULL;

/* =========================================================
 * utilities
 * ========================================================= */

static void die(const char *msg)
{
    fprintf(stderr, "hasm: %s\n", msg);
    exit(1);
}

static int findsym(const char *s)
{
    for (int i = 0; i < nsym; i++)
        if (!strcmp(symtab[i].name, s))
            return i;
    return -1;
}

static void addsym(const char *s, uint16_t addr)
{
    if (nsym >= MAXSYM)
        die("symbol table overflow");

    if (findsym(s) >= 0)
        die("duplicate label");

    strncpy(symtab[nsym].name, s, sizeof(symtab[nsym].name)-1);
    symtab[nsym].addr = addr;
    nsym++;
}

static uint16_t parse_num(const char *s)
{
    while (isspace(*s)) s++;
    if (!strncmp(s, "0x", 2))
        return (uint16_t)strtol(s, NULL, 16);
    return (uint16_t)strtol(s, NULL, 10);
}

static char *trim(char *s)
{
    while (isspace(*s)) s++;
    for (char *p = s + strlen(s) - 1; p >= s && isspace(*p); p--)
        *p = 0;
    return s;
}

static void emit8(uint8_t v)   { code[pc++] = v; }
static void emit16(uint16_t v)
{
    emit8(v >> 8);
    emit8(v & 0xFF);
}

/* =========================================================
 * pass 1 – build symbol table / pc layout
 * ========================================================= */

static void pass1(FILE *fp)
{
    char line[256];
    pc = 0;
    nsym = 0;
    nfix = 0;

    while (fgets(line, sizeof(line), fp)) {
        char *p = trim(line);
        if (*p == 0 || *p == ';')
            continue;

        /* label */
        char *c = strchr(p, ':');
        if (c) {
            *c = 0;
            addsym(trim(p), pc);
            p = trim(c + 1);
            if (*p == 0)
                continue;
        }

        /* instruction size */
        if (!strncmp(p, "LDW", 3)) pc += 3;
        else if (!strncmp(p, "ADDW", 4)) pc += 3;
        else if (!strncmp(p, "SUBW", 4)) pc += 3;
        else if (!strncmp(p, "CMP", 3)) pc += 3;
        else if (!strncmp(p, "STW", 3)) pc += 3;
        else if (!strncmp(p, "JSR", 3)) pc += 3;
        else if (!strncmp(p, "JMP", 3)) pc += 3;
        else if (!strncmp(p, "BEQ", 3)) pc += 2;
        else if (!strncmp(p, "BNE", 3)) pc += 2;
        else if (!strncmp(p, "BLT", 3)) pc += 2;
        else if (!strncmp(p, "BGE", 3)) pc += 2;
        else if (!strncmp(p, "RET", 3)) pc += 1;
        else if (!strncmp(p, "HALT", 4)) pc += 1;
        else
            die("unknown mnemonic (pass1)");
    }
}

/* =========================================================
 * pass 2 – emit code / record fixups / generate .sym
 * ========================================================= */

static void pass2(FILE *fp)
{
    char line[256];
    char orig[256];
    pc = 0;

    while (fgets(line, sizeof(line), fp)) {
        strcpy(orig, line);             /* save original line */
        char *p = trim(line);
        if (*p == 0 || *p == ';')
            continue;

        /* label */
        char *c = strchr(p, ':');
        if (c) {
            *c = 0;
            p = trim(c + 1);
            if (*p == 0)
                continue;
        }

        /* record source line */
        if (debug_flag && symfp) {
            fprintf(symfp, "%04X %s", pc, trim(orig));
            if (orig[strlen(orig)-1] != '\n')
                fputc('\n', symfp);
        }

        /* instructions */

        if (!strncmp(p, "LDW", 3)) {
            emit8(0x10);
            emit16(parse_num(strchr(p, '#') + 1));
        }
        else if (!strncmp(p, "ADDW", 4)) {
            emit8(0x20);
            emit16(parse_num(strchr(p, '#') + 1));
        }
        else if (!strncmp(p, "SUBW", 4)) {
            emit8(0x21);
            emit16(parse_num(strchr(p, '#') + 1));
        }
        else if (!strncmp(p, "CMP", 3)) {
            emit8(0x31);
            emit16(parse_num(strchr(p, '#') + 1));
        }
        else if (!strncmp(p, "STW", 3)) {
            emit8(0x30);
            emit16(parse_num(p + 3));
        }
        else if (!strncmp(p, "JSR", 3)) {
            emit8(0x50);
            emit16(parse_num(p + 3));
        }
        else if (!strncmp(p, "JMP", 3)) {
            emit8(0x42);
            emit16(parse_num(p + 3));
        }
        else if (!strncmp(p, "BEQ", 3) ||
                 !strncmp(p, "BNE", 3) ||
                 !strncmp(p, "BLT", 3) ||
                 !strncmp(p, "BGE", 3)) {

            uint8_t op;
            if (p[1] == 'E') op = 0x31;
            else if (p[1] == 'N') op = 0x32;
            else if (p[1] == 'L') op = 0x33;
            else                  op = 0x34;

            emit8(op);
            emit8(0); /* placeholder */

            strncpy(fixups[nfix].label, trim(p + 3),
                    sizeof(fixups[nfix].label)-1);
            fixups[nfix].pc = pc - 2;
            nfix++;
        }
        else if (!strncmp(p, "RET", 3)) {
            emit8(0x41);
        }
        else if (!strncmp(p, "HALT", 4)) {
            emit8(0xFF);
        }
        else
            die("unknown mnemonic (pass2)");
    }

    /* resolve branches */
    for (int i = 0; i < nfix; i++) {
        int s = findsym(fixups[i].label);
        if (s < 0)
            die("undefined label");

        uint16_t from = fixups[i].pc + 2;
        int16_t disp =
            (int16_t)symtab[s].addr - (int16_t)from;

        if (disp < -128 || disp > 127)
            die("branch out of range");

        code[fixups[i].pc + 1] = (uint8_t)disp;
    }
}

/* =========================================================
 * main
 * ========================================================= */

int main(int argc, char **argv)
{
    if (argc < 3) {
        fprintf(stderr,
            "usage: hasm [-g] input.asm output.bin\n");
        return 1;
    }

    int arg = 1;
    if (!strcmp(argv[arg], "-g")) {
        debug_flag = 1;
        arg++;
    }

    const char *infile  = argv[arg++];
    const char *outfile = argv[arg++];

    FILE *fp = fopen(infile, "r");
    if (!fp) die("cannot open input");

    if (debug_flag) {
        char name[256];
        snprintf(name, sizeof(name), "%s.sym", outfile);
        symfp = fopen(name, "w");
        if (!symfp) die("cannot open .sym file");
    }

    pass1(fp);
    rewind(fp);
    pass2(fp);
    fclose(fp);

    if (symfp)
        fclose(symfp);

    FILE *out = fopen(outfile, "wb");
    if (!out) die("cannot open output");

    fwrite(code, 1, pc, out);
    fclose(out);

    return 0;
}
