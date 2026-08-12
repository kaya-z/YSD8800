/*
 * emu_1clk.c – mycpu ISA v1.0 reference emulator
 *
 * Model:
 *  - 1 instruction = 1 clock
 *  - FPGA friendly (no hidden work)
 *  - step / continue / break
 *  - asm source line display
 */

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

/* =========================================================
 * CPU state
 * ========================================================= */

uint8_t  mem[65536];

uint16_t A, B, X;
uint16_t PC, SP, FP;

uint8_t  ZF, NF;

uint64_t clk;   /* global clock */

/* =========================================================
 * source line table
 * ========================================================= */

typedef struct {
    uint16_t pc;
    char line[128];
} srcline_t;

srcline_t srclines[2048];
int nsrc;

/* =========================================================
 * breakpoints
 * ========================================================= */

uint16_t breakpoints[32];
int nbp;

/* =========================================================
 * helpers
 * ========================================================= */

uint8_t mem8(uint16_t a) { return mem[a]; }

uint16_t mem16(uint16_t a)
{
    return (mem[a] << 8) | mem[a+1];
}

void setZN(uint16_t v)
{
    ZF = (v == 0);
    NF = (v & 0x8000) != 0;
}

/* =========================================================
 * asm source support
 * ========================================================= */

const char *find_srcline(uint16_t pc)
{
    for (int i = nsrc - 1; i >= 0; i--)
        if (srclines[i].pc <= pc)
            return srclines[i].line;
    return NULL;
}

void load_sym(const char *bin)
{
    char name[256];
    snprintf(name, sizeof(name), "%s.sym", bin);

    FILE *f = fopen(name, "r");
    if (!f) return;

    while (fscanf(f, "%hx %[^\n]\n",
                  &srclines[nsrc].pc,
                  srclines[nsrc].line) == 2)
        nsrc++;

    fclose(f);
}

/* =========================================================
 * instruction execution (1 clk)
 * ========================================================= */

void exec_1clk(void)
{
    uint16_t pc0 = PC;
    uint8_t op   = mem8(PC++);

    const char *src = find_srcline(pc0);
    if (src)
        printf("ASM: %s\n", src);

    printf("CLK %llu  PC=%04X  OP=%02X  ", clk, pc0, op);

    switch (op) {

    case 0x10: { /* LDW #imm */
        uint16_t v = mem16(PC); PC += 2;
        A = v; setZN(A);
        printf("LDW #$%04X\n", v);
        break;
    }

    case 0x20: { /* ADDW #imm */
        uint16_t v = mem16(PC); PC += 2;
        A += v; setZN(A);
        printf("ADDW #$%04X\n", v);
        break;
    }

    case 0x21: { /* SUBW #imm */
        uint16_t v = mem16(PC); PC += 2;
        A -= v; setZN(A);
        printf("SUBW #$%04X\n", v);
        break;
    }

    case 0x30: { /* STW abs */
        uint16_t a = mem16(PC); PC += 2;
        mem[a]   = A >> 8;
        mem[a+1] = A & 0xFF;
        printf("STW $%04X\n", a);
        break;
    }

    case 0x31: { /* CMP #imm */
        uint16_t v = mem16(PC); PC += 2;
        uint16_t r = A - v;
        ZF = (r == 0);
        NF = (r & 0x8000) != 0;
        printf("CMP #$%04X\n", v);
        break;
    }

    case 0x33: { /* BLT disp */
        int8_t d = (int8_t)mem8(PC++);
        if (NF) PC = PC + d;
        printf("BLT %d\n", d);
        break;
    }

    case 0x34: { /* BGE disp */
        int8_t d = (int8_t)mem8(PC++);
        if (!NF) PC = PC + d;
        printf("BGE %d\n", d);
        break;
    }

    case 0x41: { /* RET */
        PC = mem16(SP);
        SP += 2;
        printf("RET\n");
        break;
    }

    case 0x50: { /* JSR */
        uint16_t a = mem16(PC); PC += 2;
        SP -= 2;
        mem[SP]   = PC >> 8;
        mem[SP+1] = PC & 0xFF;
        PC = a;
        printf("JSR $%04X\n", a);
        break;
    }

    case 0xFF:
        printf("HALT\n");
        exit(0);

    default:
        printf("ILLEGAL\n");
        exit(1);
    }

    printf("      A=%04X Z=%d N=%d SP=%04X\n", A, ZF, NF, SP);
    clk++;
}

/* =========================================================
 * debugger
 * ========================================================= */

int is_bp(uint16_t pc)
{
    for (int i = 0; i < nbp; i++)
        if (breakpoints[i] == pc)
            return 1;
    return 0;
}

void debugger(void)
{
    char buf[128];

    while (1) {
        printf("(emu) ");
        if (!fgets(buf, sizeof(buf), stdin))
            exit(0);

        if (buf[0] == 's') {
            exec_1clk();
        }
        else if (buf[0] == 'c') {
            do {
                exec_1clk();
            } while (!is_bp(PC));
        }
        else if (buf[0] == 'b') {
            uint16_t a = strtol(buf+1, NULL, 16);
            breakpoints[nbp++] = a;
            printf("breakpoint set at %04X\n", a);
        }
        else if (buf[0] == 'r') {
            printf("PC=%04X A=%04X SP=%04X Z=%d N=%d CLK=%llu\n",
                   PC, A, SP, ZF, NF, clk);
        }
        else if (buf[0] == 'q') {
            exit(0);
        }
    }
}

/* =========================================================
 * loader / main
 * ========================================================= */

void load_bin(const char *f)
{
    FILE *fp = fopen(f, "rb");
    if (!fp) {
        perror(f);
        exit(1);
    }
    fread(mem, 1, 65536, fp);
    fclose(fp);
}

int main(int argc, char **argv)
{
    if (argc < 2) {
        printf("usage: emu binfile\n");
        return 1;
    }

    load_bin(argv[1]);
    load_sym(argv[1]);

    PC = 0x0000;
    SP = 0xFFFE;
    FP = 0;
    A = B = X = 0;
    ZF = NF = 0;
    clk = 0;

    debugger();
    return 0;
}
