// emu2.c - ISA2.0 Emulator (Full Implementation)
// by Grok (modified from original to match new IRQ IDs: align=3, syscall=4)
// Fixed HALT handling: skip timer IRQ set after halted=1
// Fixed dump_mem typo: mem[addr + i + j) → mem[addr + i + j]
// build: gcc -std=c99 -O2 -Wall emu2.c -o emu

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <ctype.h>

#define MEM_SIZE 65536
#define MAX_DBG  8192
#define MAX_BP   128
#define MAX_SYM  128

// flags
#define FL_Z   0x01
#define FL_N   0x02
#define FL_IE  0x80   // Interrupt Enable

uint8_t mem[MEM_SIZE];

// ================= CPU =================

typedef struct {
    uint16_t pc;
    uint16_t a, b;
    uint16_t x;
    uint16_t sp;
    uint8_t  flags;   // bit0 Z, bit1 N, bit7 IE
    uint8_t  ir;
    int irq_en;
    int irq_pending;
    int halted;
    uint64_t cycle;
} cpu_t;

cpu_t cpu;

// ================= DBG =================

typedef struct {
    uint16_t addr;
    int line;
    char text[128];
} dbgline_t;

static dbgline_t dbg[MAX_DBG];
static int dbg_count = 0;

// ================= BP ==================

uint16_t breakpoints[MAX_BP];
int bp_count = 0;


// ================= SYM ==================

typedef struct {
    char name[32];
    uint16_t addr;
} sym_t;

sym_t syms[MAX_SYM];
int sym_count = 0;

// ================= Utils =================

uint16_t rd16(uint16_t a) {
    if (a & 1) {
       printf("!! ALIGNMENT EXCEPTION @%04x\n", a);
       cpu.irq_pending = 3;   /* align = 3 */
    }
    return mem[a] | (mem[a+1] << 8);
}

void wr16(uint16_t a, uint16_t v) {
    if (a & 1) {
       printf("!! ALIGNMENT EXCEPTION (WRITE) @%04x\n", a);
       cpu.irq_pending = 3;   /* align = 3 */
       return;
    }
    mem[a]   = v & 0xff;
    mem[a+1] = v >> 8;
}

int is_break(uint16_t pc) {
    for (int i = 0; i < bp_count; i++)
        if (breakpoints[i] == pc) return 1;
    return 0;
}

const char *dbg_lookup(uint16_t pc) {
    for (int i = 0; i < dbg_count; i++) {
        if (dbg[i].addr == pc)
            return dbg[i].text;
    }
    return "";
}

void push16(uint16_t v) {
    cpu.sp -= 2;
    wr16(cpu.sp, v);
}

uint16_t pop16(void) {
    uint16_t v = rd16(cpu.sp);
    cpu.sp += 2;
    return v;
}

int lookup_sym(const char *name, uint16_t *out) {
    for (int i = 0; i < sym_count; i++) {
        if (strcmp(syms[i].name, name) == 0) {
            *out = syms[i].addr;
            return 1;
        }
    }
    return 0;
}

void make_sym_name(char *out, const char *bin) {
    strcpy(out, bin);
    char *p = strrchr(out, '.');
    if (p) strcpy(p, ".sym");
    else strcat(out, ".sym");
}

char *change_ext(const char *path, const char *ext) {
    static char buf[256];
    char *p;
    strncpy(buf, path, sizeof(buf));
    buf[sizeof(buf) - 1] = '\0';
    p = strrchr(buf, '.');
    if (p) {
        strcpy(p, ext);
    } else {
        strncat(buf, ext, sizeof(buf) - strlen(buf) - 1);
    }
    return buf;
}

static void dump_mem(uint16_t addr, int n) {
    int i, j;
    for (i = 0; i < n; i += 16) {
        printf("%04x: ", addr + i);
        for (j = 0; j < 16; j++) {
            if (i + j < n) printf("%02x ", mem[addr + i + j]);
            else printf("   ");
        }
        printf(" |");
        for (j = 0; j < 16 && i + j < n; j++) {
            uint8_t c = mem[addr + i + j];
            if (c >= 0x20 && c <= 0x7e) putchar(c);
            else putchar('.');
        }
        printf("|\n");
    }
}

static void dump_memw(uint16_t addr, int n) {
    int i;
    if (addr & 1) printf("!! WARN: unaligned word dump @%04x\n", addr);
    for (i = 0; i < n; i += 8) {
        uint16_t base = addr + i * 2;
        printf("%04x: ", base);
        for (int j = 0; j < 8 && i + j < n; j++) {
            uint16_t a = base + j * 2;
            uint16_t v = rd16(a);
            printf("%04x ", v);
        }
        printf("\n");
    }
}

uint16_t fetch16(uint16_t a) {
    return mem[a] | (mem[a+1] << 8);
}

// ================= DUMP Register =========

void dump_regs(void) {
    const char *src = dbg_lookup(cpu.pc);
    printf("PC=%04X SP=%04X FLAGS=%04X A=%04X B=%04X X=%04X  |",
            cpu.pc, cpu.sp, cpu.flags, cpu.a, cpu.b, cpu.x);
    if (src) printf("%s", src);
    printf("\n");
}

// ================= Loaders =================

void load_bin(const char *fn) {
    FILE *f = fopen(fn, "rb");
    if (!f) { perror(fn); exit(1); }
    fread(mem, 1, MEM_SIZE, f);
    fclose(f);
}

void load_dbg(const char *path) {
    FILE *fp = fopen(path, "r");
    if (!fp) return;
    while (!feof(fp) && dbg_count < MAX_DBG) {
        dbgline_t *d = &dbg[dbg_count];
        if (fscanf(fp, "%hx %[^\n]", &d->addr, d->text) == 2) {
            dbg_count++;
        }
    }
    fclose(fp);
    printf("Loaded %d dbg entries\n", dbg_count);
}

void load_sym(const char *path) {
    FILE *fp = fopen(path, "r");
    if (!fp) return;
    char line[128];
    while (sym_count < MAX_SYM && fgets(line, sizeof(line), fp)) {
        char tok1[32], tok2[32];
        unsigned addr;
        if (sscanf(line, "%31s %31s", tok1, tok2) != 2) continue;
        if (isxdigit((unsigned char)tok1[0])) {
            addr = (unsigned)strtol(tok1, NULL, 16);
            strncpy(syms[sym_count].name, tok2, sizeof(syms[sym_count].name));
            syms[sym_count].addr = (uint16_t)addr;
            sym_count++;
        } else if (isxdigit((unsigned char)tok2[0])) {
            addr = (unsigned)strtol(tok2, NULL, 16);
            strncpy(syms[sym_count].name, tok1, sizeof(syms[sym_count].name));
            syms[sym_count].addr = (uint16_t)addr;
            sym_count++;
        }
    }
    fclose(fp);
    printf("Loaded %d label symbols\n", sym_count);
}

void disas(uint16_t addr, int n) {
    uint16_t pc = addr;
    for (int i = 0; i < n; i++) {
        const char *s = dbg_lookup(pc);
        if (s && *s) printf("%04x: %s\n", pc, s);
        else printf("%04x:\n", pc);
        pc += 1;
    }
}

// ================= Exec =================

void set_zn(uint16_t v) {
    if (v == 0) cpu.flags |= FL_Z;
    else cpu.flags &= ~FL_Z;
    if (v & 0x8000) cpu.flags |= FL_N;
    else cpu.flags &= ~FL_N;
}

// レジスタID解決ヘルパー: 0=A, 1=B, 2=X, 3=SP
uint16_t *get_reg_ptr(uint8_t id) {
    switch (id) {
        case 0: return &cpu.a;
        case 1: return &cpu.b;
        case 2: return &cpu.x;
        case 3: return &cpu.sp;
        default: return NULL; // PC(4), FLAGS(5) への直接アクセスは通常命令では制限
    }
}

void exec_one(void) {
    uint16_t pc0 = cpu.pc;

    // IRQ accept
    if (cpu.irq_pending >= 0 && (cpu.flags & FL_IE)) {
      int irq = cpu.irq_pending;
      cpu.irq_pending = -1;
      push16(cpu.pc);
      push16(cpu.flags);
      cpu.flags &= ~FL_IE;
      cpu.irq_en = 0;
      uint16_t vec = rd16(irq * 2);
      cpu.pc = vec;
      printf("** IRQ %d accepted **\n", irq);
    }

    // FETCH
    cpu.ir = mem[cpu.pc++];
    cpu.cycle++;

    // DECODE/EXEC
    switch (cpu.ir) {
    // --- Control / System (0x00 - 0x1F) ---
    case 0x00: /* NOP */ break;
    case 0x01: /* HALT */ cpu.halted = 1; break;
    case 0x02: /* EI */ cpu.flags |= FL_IE; cpu.irq_en = 1; break;
    case 0x03: /* DI */ cpu.flags &= ~FL_IE; cpu.irq_en = 0; break;
    case 0x04: /* IRET */
        cpu.flags = pop16();
        cpu.pc    = pop16();
        cpu.irq_en = (cpu.flags & FL_IE) != 0;
        break;
    case 0x05: { /* SYSCALL imm16 */
        uint16_t imm = fetch16(cpu.pc); cpu.pc += 2;
        printf("** SYSCALL %d triggered **\n", imm);
        // Soft IRQとして処理 (ID=4を使用)
        cpu.irq_pending = 4;
        break;
    }
    case 0x06: /* BRK */ break;

    // --- Data Transfer (0x20 - 0x3F) ---
    case 0x20: { /* MOV rD, rS */
        uint8_t rb = mem[cpu.pc++];
        uint16_t *rd = get_reg_ptr(rb >> 4);
        uint16_t *rs = get_reg_ptr(rb & 0x0F);
        if (rd && rs) {
            *rd = *rs;
        }
        break;
    }
    case 0x21: { /* LDW rD, #imm16 */
        uint8_t rb = mem[cpu.pc++];
        uint16_t imm = fetch16(cpu.pc); cpu.pc += 2;
        uint16_t *rd = get_reg_ptr(rb >> 4);
        if (rd) {
            *rd = imm;
            set_zn(*rd);
        }
        break;
    }
    case 0x22: { /* LDW rD, [imm16] */
        uint8_t rb = mem[cpu.pc++];
        uint16_t imm = fetch16(cpu.pc); cpu.pc += 2;
        uint16_t *rd = get_reg_ptr(rb >> 4);
        if (rd) {
            *rd = rd16(imm);
            set_zn(*rd);
        }
        break;
    }
    case 0x23: { /* STW rS, [imm16] */
        uint8_t rb = mem[cpu.pc++];
        uint16_t imm = fetch16(cpu.pc); cpu.pc += 2;
        uint16_t *rs = get_reg_ptr(rb & 0x0F);
        if (rs) {
            wr16(imm, *rs);
        }
        break;
    }
    case 0x24: { /* LDW rD, [rS] */
        uint8_t rb = mem[cpu.pc++];
        uint16_t *rd = get_reg_ptr(rb >> 4);
        uint16_t *rs = get_reg_ptr(rb & 0x0F);
        if (rd && rs) {
            *rd = rd16(*rs);
            set_zn(*rd);
        }
        break;
    }
    case 0x25: { /* STW rS, [rD] */
        uint8_t rb = mem[cpu.pc++];
        uint16_t *rd = get_reg_ptr(rb >> 4); // Address
        uint16_t *rs = get_reg_ptr(rb & 0x0F); // Data
        if (rd && rs) {
            wr16(*rd, *rs);
        }
        break;
    }
    case 0x26: { /* LDW rD, [X + imm16] */
        uint8_t rb = mem[cpu.pc++];
        uint16_t imm = fetch16(cpu.pc); cpu.pc += 2;
        uint16_t *rd = get_reg_ptr(rb >> 4);
        if (rd) {
            uint16_t addr = cpu.x + imm;
            *rd = rd16(addr);
            set_zn(*rd);
        }
        break;
    }
    case 0x27: { /* STW rS, [X + imm16] */
        uint8_t rb = mem[cpu.pc++];
        uint16_t imm = fetch16(cpu.pc); cpu.pc += 2;
        uint16_t *rs = get_reg_ptr(rb & 0x0F); // rS field for source data
        if (rs) {
            uint16_t addr = cpu.x + imm;
            wr16(addr, *rs);
        }
        break;
    }

    // --- Arithmetic / Logic (0x40 - 0x5F) ---
    case 0x40: { /* ADD rD, rS */
        uint8_t rb = mem[cpu.pc++];
        uint16_t *rd = get_reg_ptr(rb >> 4);
        uint16_t *rs = get_reg_ptr(rb & 0x0F);
        if (rd && rs) {
            *rd += *rs;
            set_zn(*rd);
        }
        break;
    }
    case 0x41: { /* ADDI rD, #imm16 */
        uint8_t rb = mem[cpu.pc++];
        uint16_t imm = fetch16(cpu.pc); cpu.pc += 2;
        uint16_t *rd = get_reg_ptr(rb >> 4);
        if (rd) {
            *rd += imm;
            set_zn(*rd);
        }
        break;
    }
    case 0x42: { /* SUB rD, rS */
        uint8_t rb = mem[cpu.pc++];
        uint16_t *rd = get_reg_ptr(rb >> 4);
        uint16_t *rs = get_reg_ptr(rb & 0x0F);
        if (rd && rs) {
            *rd -= *rs;
            set_zn(*rd);
        }
        break;
    }
    case 0x43: { /* SUBI rD, #imm16 */
        uint8_t rb = mem[cpu.pc++];
        uint16_t imm = fetch16(cpu.pc); cpu.pc += 2;
        uint16_t *rd = get_reg_ptr(rb >> 4);
        if (rd) {
            *rd -= imm;
            set_zn(*rd);
        }
        break;
    }
    case 0x44: { /* CMP rD, rS */
        uint8_t rb = mem[cpu.pc++];
        uint16_t *rd = get_reg_ptr(rb >> 4);
        uint16_t *rs = get_reg_ptr(rb & 0x0F);
        if (rd && rs) {
            uint16_t res = *rd - *rs;
            set_zn(res);
        }
        break;
    }
    case 0x45: { /* CMPI rD, #imm16 */
        uint8_t rb = mem[cpu.pc++];
        uint16_t imm = fetch16(cpu.pc); cpu.pc += 2;
        uint16_t *rd = get_reg_ptr(rb >> 4);
        if (rd) {
            uint16_t res = *rd - imm;
            set_zn(res);
        }
        break;
    }

    // --- Branch / Flow (0x60 - 0x7F) ---
    case 0x60: { /* JMP rel16 */
        int16_t off = (int16_t)fetch16(cpu.pc); cpu.pc += 2;
	printf("%x\n",cpu.pc);
        cpu.pc += off;
        break;
    }
    case 0x61: { /* BEQ rel16 (Z=1) */
        int16_t off = (int16_t)fetch16(cpu.pc); cpu.pc += 2;
        if (cpu.flags & FL_Z) cpu.pc += off;
        break;
    }
    case 0x62: { /* BNE rel16 (Z=0) */
        int16_t off = (int16_t)fetch16(cpu.pc); cpu.pc += 2;
        if (!(cpu.flags & FL_Z)) cpu.pc += off;
        break;
    }
    case 0x63: { /* BLT rel16 (N=1) */
        int16_t off = (int16_t)fetch16(cpu.pc); cpu.pc += 2;
        if (cpu.flags & FL_N) cpu.pc += off;
        break;
    }
    case 0x64: { /* BGE rel16 (N=0) */
        int16_t off = (int16_t)fetch16(cpu.pc); cpu.pc += 2;
	printf("%x\n",off);
        if (!(cpu.flags & FL_N)) cpu.pc += off;
        break;
    }
    case 0x68: { /* JSR imm16 */
        uint16_t target = fetch16(cpu.pc); cpu.pc += 2;
        push16(cpu.pc);
        cpu.pc = target;
        break;
    }
    case 0x69: { /* RET */
        cpu.pc = pop16();
        break;
    }

    default:
        printf("Unknown opcode %02x at %04x\n", cpu.ir, pc0);
        cpu.halted = 1;
        break;
    }

    if (cpu.halted) {
      printf("*** HALT ***\n");
      //      dump_regs();
      return;  // 追加: HALT後即return（timerセットスキップ）
    }

    // simple timer IRQ (every 100 instructions)
    if ((cpu.cycle % 100) == 0 && cpu.irq_pending < 0) {
      cpu.irq_pending = 1; // IRQ0 simulation (ID=1)
    }

    
}

// ================= CLI =================

void repl(void) {
    char cmd[128];
    while (!cpu.halted) {
        if (is_break(cpu.pc)) {
            printf("** BREAK @%04x **\n", cpu.pc);
        }
        
        // 簡易表示: 次の命令も表示すると便利だが、ここでは現状維持
        printf("PC=%04x A=%04x B=%04x X=%04x SP=%04x F=%02x | %s\n",
            cpu.pc, cpu.a, cpu.b, cpu.x, cpu.sp, cpu.flags, dbg_lookup(cpu.pc));
        
        printf("(emu) ");
        if (!fgets(cmd, sizeof(cmd), stdin)) break;

        if (cmd[0]=='s') {
            int n = 1;
            if (sscanf(cmd + 1, "%d", &n) != 1) n = 1;
            while (n-- > 0 && !cpu.halted && !is_break(cpu.pc)) {
                exec_one();
            }
        } else if (cmd[0]=='c') {
            while (!cpu.halted && !is_break(cpu.pc)) exec_one();
        } else if (cmd[0]=='b') {
            if (cmd[1] == '\n' || cmd[1] == '\0') {
                int i;
                printf("Num  Addr\n");
                for (i = 0; i < bp_count; i++) printf("%-4d %04x\n", i, breakpoints[i]);
                continue;
            }
            char arg[64];
            if (sscanf(cmd + 1, "%63s", arg) != 1) {
                printf("Usage: b <addr|label>\n");
                continue;
            }
            uint16_t addr;
            if (sscanf(arg, "%hx", &addr) == 1) { /* addr OK */ }
            else {
                if (!lookup_sym(arg, &addr)) {
                    printf("Unknown label: %s\n", arg);
                    continue;
                }
            }
            if (bp_count >= MAX_BP) printf("Too many breakpoints\n");
            else {
                breakpoints[bp_count++] = addr;
                printf("Breakpoint %d set at %04x\n", bp_count - 1, addr);
            }
        } else if (cmd[0]=='t') {
            while (!cpu.halted && !is_break(cpu.pc)) { exec_one();  dump_regs();}
        } else if (strncmp(cmd, "regs", 4) == 0) {
            dump_regs();
        } else if (strncmp(cmd, "disas", 5) == 0) {
            uint16_t addr = cpu.pc;
            int n = 10;
            sscanf(cmd + 5, "%hx %d", &addr, &n);
            disas(addr, n);
        } else if (strncmp(cmd, "memw", 4) == 0) {
            uint16_t addr = cpu.pc;
            int n = 8;
            sscanf(cmd + 4, "%hx %d", &addr, &n);
            dump_memw(addr, n);
        } else if (strncmp(cmd, "mem", 3) == 0) {
            uint16_t addr = cpu.pc;
            int n = 16;
            if (sscanf(cmd + 3, "%hx %d", &addr, &n) >= 1) {}
            dump_mem(addr, n);
        } else if (strncmp(cmd, "irq", 3) == 0) {
            int n;
            if (sscanf(cmd + 3, "%d", &n) == 1) {
                printf("** IRQ %d triggered **\n", n);
                cpu.irq_pending = n;
            } else {
                printf("usage: irq <num>\n");
            }
        } else if (cmd[0]=='q') {
            break;
        }
    }
}

// ================= Main =================

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: emu prog.bin [prog.dbg] [prog.sym]\n");
        return 1;
    }

    load_bin(argv[1]);
  
    if (argc >= 3) {
        load_dbg(argv[2]);
    } else {
        load_dbg(change_ext(argv[1], ".dbg"));
    }

    if (argc >= 4) {
        load_sym(argv[3]);
    } else {
        load_sym(change_ext(argv[1], ".sym"));
    }

    // 初期化
    memset(&cpu, 0, sizeof(cpu));
    cpu.sp = 0xfffe;
    cpu.irq_pending = -1;
    cpu.pc = rd16(0x0000);   // reset vector
    
    repl();
  
    return 0;
}
