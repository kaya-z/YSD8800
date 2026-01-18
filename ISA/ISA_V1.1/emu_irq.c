/*
 * emu_irq.c – mycpu ISA v1.1 emulator with IRQ
 *
 * Model:
 *  - 1 instruction = 1 clock
 *  - maskable IRQ
 *  - vector at 0xFFFE
 *  - CLI / SEI / RTI
 */

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

/* ================= CPU state ================= */

uint8_t  mem[65536];

uint16_t A, B, X;
uint16_t PC, SP, FP;

uint8_t  ZF, NF;
uint8_t  IF;     /* interrupt mask */
uint8_t  irq;    /* external IRQ line */

uint64_t clk;

/* ================= asm source ================= */

typedef struct {
    uint16_t pc;
    char line[128];
} srcline_t;

srcline_t srclines[2048];
int nsrc;

/* ================= breakpoints ================= */

uint16_t breakpoints[32];
int nbp;

/* ================= helpers ================= */

uint8_t mem8(uint16_t a) { return mem[a]; }
uint16_t mem16(uint16_t a) { return (mem[a]<<8)|mem[a+1]; }

void setZN(uint16_t v)
{
    ZF = (v == 0);
    NF = (v & 0x8000) != 0;
}

/* ================= source support ================= */

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

/* ================= IRQ logic ================= */

void check_irq(void)
{
    if (irq && !IF) {
        /* push PC */
        SP -= 2;
        mem[SP]   = PC >> 8;
        mem[SP+1] = PC & 0xFF;

        /* push flags: N Z I */
        SP--;
        mem[SP] = (NF<<0) | (ZF<<1) | (IF<<2);

        IF = 1;       /* mask IRQ */
        irq = 0;      /* clear line */

        PC = mem16(0xFFFE);
    }
}

/* ================= execute 1 clock ================= */

void exec_1clk(void)
{
    check_irq();

    uint16_t pc0 = PC;
    uint8_t  op  = mem8(PC++);

    const char *src = find_srcline(pc0);
    if (src) printf("ASM: %s\n", src);

    printf("CLK %-6llu PC=%04X OP=%02X ", clk, pc0, op);

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

    case 0x31: { /* CMP #imm */
        uint16_t v = mem16(PC); PC += 2;
        uint16_t r = A - v;
        ZF = (r == 0);
        NF = (r & 0x8000) != 0;
        printf("CMP #$%04X\n", v);
        break;
    }

    case 0x33: { /* BLT */
        int8_t d = (int8_t)mem8(PC++);
        if (NF) PC += d;
        printf("BLT %d\n", d);
        break;
    }

    case 0x41: { /* RET */
        PC = mem16(SP); SP += 2;
        printf("RET\n");
        break;
    }

    case 0x70: /* CLI */
        IF = 0;
        printf("CLI\n");
        break;

    case 0x71: /* SEI */
        IF = 1;
        printf("SEI\n");
        break;

    case 0x72: { /* RTI */
        uint8_t f = mem[SP++];
        NF = (f>>0)&1;
        ZF = (f>>1)&1;
        IF = (f>>2)&1;

        PC = mem16(SP);
        SP += 2;
        printf("RTI\n");
        break;
    }

    case 0xFF:
        printf("HALT\n");
        exit(0);

    default:
        printf("ILLEGAL\n");
        exit(1);
    }

    printf("      A=%04X Z=%d N=%d I=%d SP=%04X\n",
           A, ZF, NF, IF, SP);

    clk++;
}

/* ================= debugger ================= */

int is_bp(uint16_t pc)
{
    for (int i=0;i<nbp;i++)
        if (breakpoints[i]==pc) return 1;
    return 0;
}

void debugger(void)
{
    char buf[128];
    while (1) {
        printf("(emu) ");
        if (!fgets(buf,sizeof(buf),stdin)) exit(0);

        if (buf[0]=='s') exec_1clk();
        else if (buf[0]=='c') {
            do { exec_1clk(); } while (!is_bp(PC));
        }
        else if (buf[0]=='b') {
            uint16_t a=strtol(buf+1,NULL,16);
            breakpoints[nbp++]=a;
            printf("bp %04X\n",a);
        }
        else if (!strncmp(buf,"irq",3)) {
            irq=1;
            printf("IRQ asserted\n");
        }
        else if (buf[0]=='r') {
            printf("PC=%04X A=%04X SP=%04X I=%d CLK=%llu\n",
                   PC,A,SP,IF,clk);
        }
        else if (buf[0]=='q') exit(0);
    }
}

/* ================= main ================= */

void load_bin(const char *f)
{
    FILE *fp=fopen(f,"rb");
    if(!fp){perror(f);exit(1);}
    fread(mem,1,65536,fp);
    fclose(fp);
}

int main(int argc,char**argv)
{
    if(argc<2){printf("usage: emu bin\n");return 1;}

    load_bin(argv[1]);
    load_sym(argv[1]);

    PC=0; SP=0xFFFE; FP=0;
    A=B=X=0;
    ZF=NF=0;
    IF=1; irq=0;
    clk=0;

    debugger();
    return 0;
}
