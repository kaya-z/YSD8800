// emu.c - ISA2.0 Emulator (clocked, debug, FPGA-minded)
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <ctype.h>

#define MEM_SIZE 65536
#define MAX_DBG  8192
#define MAX_BP   128
#define MAX_SYM   128

#define IRQ0_VECTOR 0x0010

// flags
#define FL_Z   0x01
#define FL_N   0x02
#define FL_IE  0x80   // ★ 追加：Interrupt Enable

uint8_t mem[MEM_SIZE];

// ================= CPU =================

typedef struct {
    uint16_t pc;
    uint16_t a, b;
    uint16_t x;
    uint16_t sp;
    uint8_t  flags;   // bit0 Z, bit1 N
    uint8_t  ir;
    uint16_t imm;
    int irq_en;
    int irq_pending;
    int halted;
    uint64_t cycle;
} cpu_t;

cpu_t cpu;

uint16_t irq_vector[8] = {
  0x0010, // IRQ0: timer
  0x0020, // IRQ1: alignment exception
  0x0030, // IRQ2: external
};


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
   //        printf("!! WARN: unaligned 16-bit read @%04x\n", a);
   printf("!! ALIGNMENT EXCEPTION @%04x\n", a);
   cpu.irq_pending= 1;   /* IRQ1 = alignment */
 }
 
  return mem[a] | (mem[a+1] << 8);
}

void wr16(uint16_t a, uint16_t v) {
    mem[a]   = v & 0xff;
    mem[a+1] = v >> 8;
}

int is_break(uint16_t pc) {
    for (int i = 0; i < bp_count; i++)
        if (breakpoints[i] == pc) return 1;
    return 0;
}


const char *dbg_lookup(uint16_t pc)
{
    for (int i = 0; i < dbg_count; i++) {
        if (dbg[i].addr == pc)
            return dbg[i].text;
    }
    return "";
}


//const char *dbg_lookup(uint16_t pc)
//{
//    const char *last = NULL;

//    for (int i = 0; i < dbg_count; i++) {
//        if (dbg[i].addr > pc)
//            break;
//        last = dbg[i].text;
//    }
//    return last;
//}


//const char *dbg_lookup(uint16_t pc)
//{
//    for (int i = 0; i < dbg_count; i++) {
//        if (dbg[i].addr == pc)
//            return dbg[i].text;
//    }
//    return NULL;
//}

//const char *dbg_lookup(uint16_t pc) {
//    for (int i = dbg_count-1; i >= 0; i--) {
//        if (dbg[i].addr <= pc)
//            return dbg[i].text;
//    }
//    return "";
//}

void push16(uint16_t v) {
    cpu.sp -= 2;
    wr16(cpu.sp, v);
}

uint16_t pop16(void) {
    uint16_t v = rd16(cpu.sp);
    cpu.sp += 2;
    return v;
}

int lookup_sym(const char *name, uint16_t *out)
{
    for (int i = 0; i < sym_count; i++) {
        if (strcmp(syms[i].name, name) == 0) {
            *out = syms[i].addr;
            return 1;
        }
    }
    return 0;
}

void make_sym_name(char *out, const char *bin)
{
    strcpy(out, bin);
    char *p = strrchr(out, '.');
    if (p) strcpy(p, ".sym");
    else strcat(out, ".sym");
}

char *change_ext(const char *path, const char *ext)
{
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

static void dump_mem(uint16_t addr, int n)
{
    int i, j;

    for (i = 0; i < n; i += 16) {
        printf("%04x: ", addr + i);

        /* hex part */
        for (j = 0; j < 16; j++) {
            if (i + j < n)
                printf("%02x ", mem[addr + i + j]);
            else
                printf("   ");
        }

        printf(" |");

        /* ascii part */
        for (j = 0; j < 16 && i + j < n; j++) {
            uint8_t c = mem[addr + i + j];
            if (c >= 0x20 && c <= 0x7e)
                putchar(c);
            else
                putchar('.');
        }

        printf("|\n");
    }
}

static void dump_memw(uint16_t addr, int n)
{
    int i;

    if (addr & 1) {
        printf("!! WARN: unaligned word dump @%04x\n", addr);
    }

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

uint16_t fetch16(uint16_t a)
{
    /* 命令フェッチは常に byte address 可 */
    return mem[a] | (mem[a+1] << 8);
}


//static void check_irq(void)
//{

//}


// ================= DUMP Register =========

void dump_regs(void) {

  const char *src = dbg_lookup(cpu.pc);

 printf("PC=%04X SP=%04X FLAGS=%04X A=%04X B=%04X X=%04X  |",
          cpu.pc, cpu.sp, cpu.flags,cpu.a, cpu.b, cpu.x);

  
  // printf("PC=%04x A=%04x B=%04x X=%04x | ",
  //	 cpu.pc, cpu.a, cpu.b, cpu.x);

  if (src)
    printf("%s", src);
  
  printf("\n");
  
}

// ================= Loaders =================

void load_bin(const char *fn) {
    FILE *f = fopen(fn, "rb");
    if (!f) { perror(fn); exit(1); }
    fread(mem, 1, MEM_SIZE, f);
    fclose(f);
}

void load_dbg(const char *path)
{
    FILE *fp = fopen(path, "r");
    if (!fp) {
        perror(path);
        exit(1);
    }

    while (!feof(fp) && dbg_count < 1024) {
        dbgline_t *d = &dbg[dbg_count];
        if (fscanf(fp, "%hx %[^\n]", &d->addr, d->text) == 2) {
            dbg_count++;
        }
    }
    fclose(fp);

    printf("Loaded %d dbg entries\n", dbg_count);
	
}

//void load_dbg(const char *fn) {
//    FILE *f = fopen(fn, "r");
//    if (!f) return;
//    while (!feof(f) && dbg_count < MAX_DBG) {
//        fscanf(f, "%hx %d %[^\n]\n",
//            &dbg[dbg_count].addr,
//            &dbg[dbg_count].line,
//            dbg[dbg_count].text);
//        dbg_count++;
//    }
//    fclose(f);
//}


void load_sym(const char *path)
{
    FILE *fp = fopen(path, "r");
    if (!fp) {
        /* sym は必須ではない */
        fprintf(stderr, "No sym file: %s\n", path);
        return;
    }

    char line[128];

while (sym_count < MAX_SYM && fgets(line, sizeof(line), fp)) {
    char tok1[32], tok2[32];
    unsigned addr;

    if (sscanf(line, "%31s %31s", tok1, tok2) != 2)
        continue;

    /* 0000 start 形式 */
    if (isxdigit((unsigned char)tok1[0])) {
        addr = (unsigned)strtol(tok1, NULL, 16);
        strncpy(syms[sym_count].name, tok2,
                sizeof(syms[sym_count].name));
        syms[sym_count].addr = (uint16_t)addr;
        sym_count++;
    }
    /* start 0000 形式 */
    else if (isxdigit((unsigned char)tok2[0])) {
        addr = (unsigned)strtol(tok2, NULL, 16);
        strncpy(syms[sym_count].name, tok1,
                sizeof(syms[sym_count].name));
        syms[sym_count].addr = (uint16_t)addr;
        sym_count++;
    }
}

    fclose(fp);

    printf("Loaded %d label symbols\n", sym_count);
}

void disas(uint16_t addr, int n)
{
    uint16_t pc = addr;

    for (int i = 0; i < n; i++) {
        const char *s = dbg_lookup(pc);

	if (s && *s)
	  printf("%04x: %s\n", pc, s);
	else
	  printf("%04x:\n", pc);
	
	//	if (!s) s = "";
	//
	//        printf("%04x: %s\n", pc, s);

        /* 命令長が不明なので 1バイトずつ進める */
	        pc += 1;

    }
}


// ================= Exec =================

void set_zn(uint16_t v) {
    if (v == 0) cpu.flags |= 1;
    else cpu.flags &= ~1;
    if (v & 0x8000) cpu.flags |= 2;
    else cpu.flags &= ~2;
}

void exec_one(void) {
    uint16_t pc0 = cpu.pc;

    // IRQ accept (instruction boundary)
    if (cpu.irq_pending >= 0 && (cpu.flags & FL_IE)) {
      int irq = cpu.irq_pending;
      cpu.irq_pending = -1;

      push16(cpu.pc);
      push16(cpu.flags);

      cpu.flags &= ~FL_IE; // 割り込み禁止（ネスト防止）
      cpu.irq_en = 0;

      cpu.pc = irq_vector[irq];

      printf("** IRQ %d accepted **\n", irq);
      printf("PC=%04x A=%04x B=%04x X=%04x | %s\n",
	     cpu.pc, cpu.a, cpu.b, cpu.x, dbg_lookup(cpu.pc));
    }

    
    // FETCH
    cpu.ir = mem[cpu.pc++];
    cpu.cycle++;

    // DECODE/EXEC
    switch (cpu.ir) {
    case 0x00: /* NOP */ break;
    case 0x01: cpu.halted = 1; break;

    case 0x20: { // MOV rD,rS
        uint8_t rb = mem[cpu.pc++];
        uint16_t *rd = (rb>>4)==0 ? &cpu.a : (rb>>4)==1 ? &cpu.b : &cpu.x;
        uint16_t *rs = (rb&0xf)==0 ? &cpu.a : (rb&0xf)==1 ? &cpu.b : &cpu.x;
        *rd = *rs;
        set_zn(*rd);
        break;
    }

    case 0x21: { // LDW rD,#imm
        uint8_t rb = mem[cpu.pc++];
        uint16_t imm = rd16(cpu.pc); cpu.pc+=2;
        uint16_t *rd = (rb>>4)==0 ? &cpu.a : (rb>>4)==1 ? &cpu.b : &cpu.x;
        *rd = imm;
        set_zn(*rd);
        break;
    }

    case 0x41: { // ADDI rD,#imm
        uint8_t rb = mem[cpu.pc++];
        uint16_t imm = rd16(cpu.pc); cpu.pc+=2;
        uint16_t *rd = (rb>>4)==0 ? &cpu.a : (rb>>4)==1 ? &cpu.b : &cpu.x;
        *rd += imm;
        set_zn(*rd);
        break;
    }

    case 0x60: { // JMP rel
        int16_t off = (int16_t)fetch16(cpu.pc); cpu.pc+=2;
        cpu.pc += off;
        break;
    }

    case 0x62: { // BNE rel
        int16_t off = (int16_t)fetch16(cpu.pc); cpu.pc+=2;
        if (!(cpu.flags & 1)) cpu.pc += off;
        break;
    }

    case 0x02: // EI
      cpu.flags |= FL_IE;
      cpu.irq_en = 1;
      break;

    case 0x03: // DI
      cpu.flags &= ~FL_IE;
      cpu.irq_en = 0;
      break;

    case 0x04: // IRET
      cpu.flags = pop16();
      cpu.pc    = pop16();
      cpu.irq_en = (cpu.flags & FL_IE) != 0;
      break;

    default:
        printf("Unknown opcode %02x at %04x\n", cpu.ir, pc0);
        cpu.halted = 1;
        break;
    }

    cpu.cycle++;

    if (cpu.halted) {
      printf("*** HALT ***\n");
    }

    // simple timer IRQ (every 10 instructions)
    if ((cpu.cycle % 10) == 0) {
      cpu.irq_pending = 0;
    }
    
}




// ================= CLI =================

void repl(void) {
    char cmd[128];
    while (!cpu.halted) {
        if (is_break(cpu.pc)) {
            printf("** BREAK @%04x **\n", cpu.pc);
        }
        printf("PC=%04x A=%04x B=%04x X=%04x | %s\n",
            cpu.pc, cpu.a, cpu.b, cpu.x, dbg_lookup(cpu.pc));
        printf("(emu) ");
        if (!fgets(cmd, sizeof(cmd), stdin)) break;

        if (cmd[0]=='s') {
	  //	  exec_one();

	  int n = 1;

	  /* s N の場合 */
	  if (sscanf(cmd + 1, "%d", &n) != 1)
	    n = 1;
	  
	  while (n-- > 0 && !cpu.halted && !is_break(cpu.pc)) {
	    exec_one();
	  }
	  
        } else if (cmd[0]=='c') {
            while (!cpu.halted && !is_break(cpu.pc))
	      exec_one();
        } else if (cmd[0]=='b') {
	  //            uint16_t a;
	  //            sscanf(cmd+1, "%hx", &a);
	  //            breakpoints[bp_count++] = a;


	  if (cmd[1] == '\n' || cmd[1] == '\0') {
	    int i;
	    printf("Num  Addr\n");
	    for (i = 0; i < bp_count; i++) {
	      printf("%-4d %04x\n", i, breakpoints[i]);
	    }
	    continue;
	  }

	  char arg[64];
	  if (sscanf(cmd + 1, "%63s", arg) != 1) {
	    printf("Usage: b <addr|label>\n");
	    continue;
	  }
	  
	  uint16_t addr;

	  /* 16進数か？ */
	  if (sscanf(arg, "%hx", &addr) == 1) {
	    /* addr OK */
	  } else {
	    /* label として解釈 */
	    if (!lookup_sym(arg, &addr)) {
	      printf("Unknown label: %s\n", arg);
	      continue;
	    }
	  }

	  if (bp_count >= MAX_BP) {
	    printf("Too many breakpoints\n");
	  } else {
	    breakpoints[bp_count++] = addr;
	    printf("Breakpoint %d set at %04x\n", bp_count - 1, addr);
	  }

	}else if (cmd[0]=='t') {
	      while (!cpu.halted && !is_break(cpu.pc)) {
		//		dump_regs();		
		exec_one();
	      }
	}else if (strncmp(cmd, "regs", 4) == 0) {
	  dump_regs();

	} else if (strncmp(cmd, "disas", 5) == 0) {
	  uint16_t addr = cpu.pc;
	  int n = 10;

	  /* disas addr n */
	  sscanf(cmd + 5, "%hx %d", &addr, &n);
	  disas(addr, n);

	}else if (strncmp(cmd, "memw", 4) == 0) {
	  uint16_t addr = cpu.pc;
	  int n = 8;   // デフォルト 8 word

	  /* memw addr n */
	  sscanf(cmd + 4, "%hx %d", &addr, &n);
	  
	  dump_memw(addr, n);

	  
	}else if (strncmp(cmd, "mem", 3) == 0) {
	  uint16_t addr = cpu.pc;
	  int n = 16;

	  /* mem addr n */
	  if (sscanf(cmd + 3, "%hx %d", &addr, &n) >= 1) {
	    /* ok */
	  }
	  
	  dump_mem(addr, n);

	}else if (strncmp(cmd, "irq", 3) == 0) {
	  int n;
	  if (sscanf(cmd + 3, "%d", &n) == 1) {
	    printf("** IRQ %d triggered **\n", n);
	    cpu.irq_pending = n;
	  } else {
	    printf("usage: irq <num>\n");
	  }
	  
	}else if (cmd[0]=='q') {
	  break;
        }
    }
}



// ================= Main =================

int main(int argc, char **argv) {

  // if (argc < 2) {
  //      printf("usage: emu prog.bin\n");
  //      return 1;
  //  }

  //  load_bin(argv[1]);

  //  char dbgfn[256];
  //  snprintf(dbgfn, sizeof(dbgfn), "%s.dbg", argv[1]);
  //  load_dbg(dbgfn);

  // repl();


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

  //初期化
  memset(&cpu, 0, sizeof(cpu));
  cpu.sp = 0xfffe;
  cpu.irq_pending = -1;

  repl();
  
  return 0;
}
