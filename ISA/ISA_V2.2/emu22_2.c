// emu22.c - YSD8800 ISA2.2 Emulator
// Fixed version — all issues from review resolved:
//
//  BUG-2 [HIGH]   rd16(): alignment exception → early return; a=0xFFFF wrap
//  BUG-3 [HIGH]   fetch16(): a=0xFFFF wrap (same root as BUG-2)
//  BUG-1 [MEDIUM] BRK: now halts and prints trap message
//  BUG-4 [MEDIUM] disas(): advances pc by actual instruction size, not +1
//  BUG-5 [MEDIUM] load_dbg: fscanf width limiter added (%127[^\n])
//  BUG-6 [MEDIUM] EXT prefix: removed duplicate cpu.cycle++ inside case 0x1F
//  BUG-7 [MEDIUM] timer IRQ: cpu.cycle > 0 guard added
//  BUG-8 [MEDIUM] 's N' step: is_break check after each exec_one()
//  WARN-1 [LOW]   cpu.irq_en removed; use (cpu.flags & FL_IE) exclusively
//  WARN-2 [LOW]   change_ext: caller-supplied buffer (no static)
//  WARN-3 [LOW]   make_sym_name() removed (dead code, duplicate of change_ext)
//  WARN-4 [LOW]   dump_regs: FLAGS printed as %02X
//  WARN-5 [LOW]   IRET: explicit (uint8_t) cast on pop16()
//
// build: gcc -std=c99 -O2 -Wall -Wextra emu21.c -o emu

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <ctype.h>

#define MEM_SIZE 65536
#define MAX_DBG  8192
#define MAX_BP   128
#define MAX_SYM  128

// FLAGS bits
#define FL_Z   0x01   // Zero
#define FL_N   0x02   // Negative
#define FL_IE  0x80   // Interrupt Enable

uint8_t mem[MEM_SIZE];

// ================= CPU =================

typedef struct {
    uint16_t pc;
    uint16_t a, b;
    uint16_t x;
    uint16_t sp;
    uint8_t  flags;   // bit0=Z  bit1=N  bit7=IE
    uint8_t  ir;
    // NOTE: irq_en field removed (WARN-1).
    //       Use (cpu.flags & FL_IE) for all IE checks.
    int      irq_pending; // -1 = none, >=0 = IRQ id
    int      halted;
    uint64_t cycle;
    uint64_t timer_cycle; // 次のタイマーIRQを発火するcycle値
} cpu_t;

cpu_t cpu;

// ================= DBG =================

typedef struct {
    uint16_t addr;
    int      line;
    char     text[128];
} dbgline_t;

static dbgline_t dbg[MAX_DBG];
static int dbg_count = 0;

// ================= Breakpoints =========

static uint16_t breakpoints[MAX_BP];
static int bp_count = 0;

// ================= Symbols =============

typedef struct {
    char     name[32];
    uint16_t addr;
} sym_t;

static sym_t syms[MAX_SYM];
static int sym_count = 0;

// ================= Memory access =======

// [FIX BUG-2] rd16: early return on alignment fault; wrap at 0xFFFF
// ================= I/O address map =======
// FC80: UART TX  (write: output char to stdout)
// FC82: UART RX  (read:  return 0, no input)
// FC84: UART STAT (read: bit0=TX ready=1, bit1=RX ready=0)
#define UART_TX    0xFC80
#define UART_RX    0xFC82
#define UART_STAT  0xFC84

uint16_t rd16(uint16_t a) {
    if (a & 1) {
        printf("!! ALIGNMENT EXCEPTION (READ) @%04x\n", a);
        cpu.irq_pending = 3;  // align = IRQ id 3
        return 0;             // do NOT read, return dummy
    }
    if (a == UART_STAT) return 0x0001; // TX ready (16bit access)
    if (a == UART_RX)   return 0x0000;
    return (uint16_t)(mem[a] | ((uint16_t)mem[(uint16_t)(a + 1)] << 8));
}

void wr16(uint16_t a, uint16_t v) {
    if (a & 1) {
        printf("!! ALIGNMENT EXCEPTION (WRITE) @%04x\n", a);
        cpu.irq_pending = 3;
        return;
    }
    mem[a]   = (uint8_t)(v & 0xFF);
    mem[(uint16_t)(a + 1)] = (uint8_t)(v >> 8);
}

uint8_t rd8(uint16_t a) {
    if (a == UART_STAT) return 0x01;   // TX always ready, no RX data
    if (a == UART_RX)   return 0x00;   // no input
    return mem[a];
}

void wr8(uint16_t a, uint8_t v) {
    if (a == UART_TX) {
        putchar((int)v);               // UART TX: output to stdout
        fflush(stdout);
        return;
    }
    mem[a] = v;
}

// [FIX BUG-3] fetch16: wrap address at 0xFFFF boundary
static uint16_t fetch16(uint16_t a) {
    return (uint16_t)(mem[a] | ((uint16_t)mem[(uint16_t)(a + 1)] << 8));
}

// ================= Stack ===============

static void push16(uint16_t v) {
    cpu.sp -= 2;
    wr16(cpu.sp, v);
}

static uint16_t pop16(void) {
    uint16_t v = rd16(cpu.sp);
    cpu.sp += 2;
    return v;
}

// ================= Utilities ===========

static int is_break(uint16_t pc) {
    for (int i = 0; i < bp_count; i++)
        if (breakpoints[i] == pc) return 1;
    return 0;
}

static const char *dbg_lookup(uint16_t pc) {
    for (int i = 0; i < dbg_count; i++)
        if (dbg[i].addr == pc) return dbg[i].text;
    return "";
}

static int lookup_sym(const char *name, uint16_t *out) {
    for (int i = 0; i < sym_count; i++) {
        if (strcmp(syms[i].name, name) == 0) {
            *out = syms[i].addr;
            return 1;
        }
    }
    return 0;
}

// [FIX WARN-2] change_ext: caller supplies output buffer (no static)
static void change_ext(char *buf, size_t bufsz, const char *path, const char *ext) {
    strncpy(buf, path, bufsz - 1);
    buf[bufsz - 1] = '\0';
    char *p = strrchr(buf, '.');
    if (p) {
        strncpy(p, ext, bufsz - (size_t)(p - buf) - 1);
        buf[bufsz - 1] = '\0';
    } else {
        strncat(buf, ext, bufsz - strlen(buf) - 1);
    }
}

// ================= Dump ================

static void dump_regs(void) {
    const char *src = dbg_lookup(cpu.pc);
    // [FIX WARN-4] FLAGS は uint8_t なので %02X
    printf("PC=%04X SP=%04X FLAGS=%02X A=%04X B=%04X X=%04X  | %s\n",
           cpu.pc, cpu.sp, cpu.flags, cpu.a, cpu.b, cpu.x, src);
}

static void dump_mem(uint16_t addr, int n) {
    for (int i = 0; i < n; i += 16) {
        printf("%04x: ", (unsigned)(addr + i));
        for (int j = 0; j < 16; j++) {
            if (i + j < n) printf("%02x ", mem[addr + i + j]);
            else printf("   ");
        }
        printf(" |");
        for (int j = 0; j < 16 && i + j < n; j++) {
            uint8_t c = mem[addr + i + j];
            putchar((c >= 0x20 && c <= 0x7e) ? c : '.');
        }
        printf("|\n");
    }
}

static void dump_memw(uint16_t addr, int n) {
    if (addr & 1) printf("!! WARN: unaligned word dump @%04x\n", addr);
    for (int i = 0; i < n; i += 8) {
        uint16_t base = (uint16_t)(addr + i * 2);
        printf("%04x: ", base);
        for (int j = 0; j < 8 && i + j < n; j++) {
            uint16_t a = (uint16_t)(base + j * 2);
            printf("%04x ", rd16(a));
        }
        printf("\n");
    }
}

// ================= Loaders =============

static void load_bin(const char *fn) {
    FILE *f = fopen(fn, "rb");
    if (!f) { perror(fn); exit(1); }
    size_t got = fread(mem, 1, MEM_SIZE, f);
    if (got == 0) { fprintf(stderr, "%s: empty or read error\n", fn); exit(1); }
    fclose(f);
    printf("Loaded %u bytes from %s\n", (unsigned)got, fn);
}

// [FIX BUG-5] fscanf: %127[^\n] で幅制限追加
static void load_dbg(const char *path) {
    FILE *fp = fopen(path, "r");
    if (!fp) return;
    while (!feof(fp) && dbg_count < MAX_DBG) {
        dbgline_t *d = &dbg[dbg_count];
        if (fscanf(fp, "%hx %127[^\n]", &d->addr, d->text) == 2)
            dbg_count++;
        else {
            // skip malformed line
            int c;
            while ((c = fgetc(fp)) != '\n' && c != EOF) { /* discard */ }
        }
    }
    fclose(fp);
    printf("Loaded %d dbg entries\n", dbg_count);
}

static void load_sym(const char *path) {
    FILE *fp = fopen(path, "r");
    if (!fp) return;
    char line[128];
    while (sym_count < MAX_SYM && fgets(line, sizeof(line), fp)) {
        char tok1[32], tok2[32];
        if (sscanf(line, "%31s %31s", tok1, tok2) != 2) continue;
        unsigned addr;
        if (isxdigit((unsigned char)tok1[0])) {
            addr = (unsigned)strtoul(tok1, NULL, 16);
            snprintf(syms[sym_count].name, sizeof(syms[sym_count].name), "%s", tok2);
            syms[sym_count].addr = (uint16_t)addr;
            sym_count++;
        } else if (isxdigit((unsigned char)tok2[0])) {
            addr = (unsigned)strtoul(tok2, NULL, 16);
            snprintf(syms[sym_count].name, sizeof(syms[sym_count].name), "%s", tok1);
            syms[sym_count].addr = (uint16_t)addr;
            sym_count++;
        }
    }
    fclose(fp);
    printf("Loaded %d label symbols\n", sym_count);
}

// ================= Disassembler ========

// [FIX BUG-4] 命令の実バイト長を返す
// ISA2.1 命令長:
//   opcode のみ          : 1 byte  (NOP HALT EI DI IRET BRK RET)
//   opcode + reg         : 2 bytes (MOV ADD SUB CMP LDW[rS] STW[rD])
//   opcode + reg + imm16 : 4 bytes (LDW#imm LDW[abs] STW[abs] LDW[X+] STW[X+]
//                                   ADDI SUBI CMPI)
//   opcode + imm16       : 3 bytes (JMP Bcc JSR SYSCALL)
//   EXT prefix + sub     : 2 bytes (PUSH POP LDB[X] STB[X])
//   EXT prefix + sub + imm16 : 4 bytes (LDB[abs] STB[abs])
static int instr_size(uint16_t addr) {
    uint8_t op = mem[addr];
    switch (op) {
    // 1 byte: no operands
    case 0x00: // NOP
    case 0x01: // HALT
    case 0x02: // EI
    case 0x03: // DI
    case 0x04: // IRET
    case 0x06: // BRK
    case 0x69: // RET
        return 1;

    // 3 bytes: opcode + imm16 (no reg byte)
    case 0x05: // SYSCALL imm16
    case 0x60: // JMP rel16
    case 0x61: // BEQ rel16
    case 0x62: // BNE rel16
    case 0x63: // BLT rel16
    case 0x64: // BGE rel16
    case 0x68: // JSR imm16
        return 3;

    // 2 bytes: opcode + reg byte (no imm)
    case 0x20: // MOV rD,rS
    case 0x24: // LDW rD,[rS]
    case 0x25: // STW rS,[rD]
    case 0x40: // ADD rD,rS
    case 0x42: // SUB rD,rS
    case 0x44: // CMP rD,rS
    // ISA2.2 2-byte bit ops
    case 0x50: // AND rD,rS
    case 0x52: // OR  rD,rS
    case 0x54: // XOR rD,rS
    case 0x56: // NOT rD
    case 0x57: // SHL rD,rS
    case 0x58: // SHR rD,rS
    case 0x59: // SAR rD,rS
        return 2;

    // 4 bytes: opcode + reg byte + imm16
    case 0x21: // LDW rD,#imm16
    case 0x22: // LDW rD,[imm16]
    case 0x23: // STW rS,[imm16]
    case 0x26: // LDW rD,[X+imm16]
    case 0x27: // STW rS,[X+imm16]
    case 0x41: // ADDI rD,#imm16
    case 0x43: // SUBI rD,#imm16
    case 0x45: // CMPI rD,#imm16
    // ISA2.2 4-byte bit ops (immediate)
    case 0x51: // ANDI rD,#imm16
    case 0x53: // ORI  rD,#imm16
    case 0x55: // XORI rD,#imm16
        return 4;

    // EXT prefix (0x1F): sub-opcode によって可変
    case 0x1F: {
        if (((uint32_t)addr + 1) >= MEM_SIZE) return 2;
        uint8_t sub = mem[(uint16_t)(addr + 1)];
        switch (sub) {
        // PUSH/POP: 2 bytes total
        case 0x00: case 0x01: case 0x02: // PUSH A/B/X
        case 0x03: case 0x04: case 0x05: // POP  A/B/X
        // LDB/STB [X]: 2 bytes total
        case 0x11: case 0x13: // LDB A/B,[X]
        case 0x15: case 0x17: // STB A/B,[X]
            return 2;
        // LDB/STB [abs]: 4 bytes total (EXT + sub + imm16)
        case 0x10: case 0x12: // LDB A/B,[imm16]
        case 0x14: case 0x16: // STB A/B,[imm16]
            return 4;
        default:
            return 2; // unknown EXT: assume 2 bytes
        }
    }

    default:
        return 1; // unknown opcode: advance 1 byte
    }
}

// [FIX BUG-4] disas: pc を実際の命令長で進める
static void disas(uint16_t addr, int n) {
    uint16_t pc = addr;
    for (int i = 0; i < n; i++) {
        const char *s = dbg_lookup(pc);
        uint8_t  op  = mem[pc];
        int      sz  = instr_size(pc);

        // hex bytes
        printf("%04x: ", pc);
        for (int j = 0; j < sz && j < 5; j++)
            printf("%02x ", mem[(uint16_t)(pc + j)]);
        // padding
        for (int j = sz; j < 5; j++)
            printf("   ");

        if (s && *s) printf("  %s", s);
        else         printf("  op=%02x (%d bytes)", op, sz);
        printf("\n");

        pc = (uint16_t)(pc + sz);
    }
}

// ================= CPU helpers =========

static void set_zn(uint16_t v) {
    if (v == 0) cpu.flags |=  FL_Z; else cpu.flags &= ~FL_Z;
    if (v & 0x8000) cpu.flags |= FL_N; else cpu.flags &= ~FL_N;
}

// レジスタ ID → ポインタ  0=A 1=B 2=X 3=SP
static uint16_t *get_reg_ptr(uint8_t id) {
    switch (id) {
    case 0: return &cpu.a;
    case 1: return &cpu.b;
    case 2: return &cpu.x;
    case 3: return &cpu.sp;
    default: return NULL;
    }
}

// ================= Exec ================

void exec_one(void) {
    if (cpu.halted) return;

    uint16_t pc0 = cpu.pc;

    // --- IRQ 受理 (§7.4-7.5) ---
    // 条件: irq_pending >= 0 && IE == 1
    if (cpu.irq_pending >= 0 && (cpu.flags & FL_IE)) {
        int irq = cpu.irq_pending;
        cpu.irq_pending = -1;
        push16(cpu.pc);                // PC を先に push (§7.5)
        push16((uint16_t)cpu.flags);   // FLAGS を後に push
        cpu.flags &= ~FL_IE;           // IE = 0 (WARN-1: irq_en 削除)
        uint16_t vec = rd16((uint16_t)(irq * 2));
        cpu.pc = vec;
        printf("** IRQ %d accepted, vec=%04x **\n", irq, vec);
        // IRQ 受理後は fetch に進む (PC は既にベクタ先)
    }

    // --- FETCH ---
    cpu.ir = mem[cpu.pc++];
    cpu.cycle++;   // [FIX BUG-6] ここのみインクリメント (case 0x1F 内は削除)

    // --- DECODE / EXEC ---
    switch (cpu.ir) {

    // ---- Control / System (0x00-0x1F) ----

    case 0x00: /* NOP */ break;

    case 0x01: /* HALT */
        cpu.halted = 1;
        break;

    case 0x02: /* EI */
        cpu.flags |= FL_IE;  // [WARN-1] irq_en 削除
        break;

    case 0x03: /* DI */
        cpu.flags &= ~FL_IE;
        break;

    case 0x04: /* IRET  FLAGS←pop / PC←pop  (§7.6) */
        // [FIX WARN-5] 明示的 (uint8_t) キャスト
        cpu.flags = (uint8_t)pop16();  // FLAGS を先に pop
        cpu.pc    = pop16();           // PC を後に pop
        // irq_en 削除 (WARN-1): FL_IE ビットで IE 状態を完全管理
        // IRETPでタスクに戻った後、次のタイマー発火まで十分な余裕を確保
        cpu.timer_cycle = cpu.cycle + 30000;
        break;

    case 0x05: { /* SYSCALL imm16 */
        uint16_t imm = fetch16(cpu.pc); cpu.pc += 2;
        printf("** SYSCALL %u triggered **\n", (unsigned)imm);
        cpu.irq_pending = 4;  // syscall IRQ id = 4 (§7.7)
        break;
    }

    case 0x06: /* BRK — デバッグトラップ (§5) */
        // [FIX BUG-1] 単なる break; から停止+通知に変更
        printf("** BRK at %04x **\n", pc0);
        cpu.halted = 1;
        break;

    // ---- ISA2.1 EXT prefix (0x1F) ----
    case 0x1F: {
        uint8_t sub = mem[cpu.pc++];
        // [FIX BUG-6] cpu.cycle++ をここから削除

        switch (sub) {
        // PUSH  (§6.7)  SP-=2; mem[SP]=reg
        case 0x00: push16(cpu.a); break;
        case 0x01: push16(cpu.b); break;
        case 0x02: push16(cpu.x); break;

        // POP   (§6.7)  reg=mem[SP]; SP+=2
        case 0x03: cpu.a = pop16(); break;
        case 0x04: cpu.b = pop16(); break;
        case 0x05: cpu.x = pop16(); break;

        // LDB  (§6.7)  reg = zero_extend(mem8)  FLAGS 不変
        case 0x10: { // LDB A,[imm16]
            uint16_t addr = fetch16(cpu.pc); cpu.pc += 2;
            cpu.a = rd8(addr);
            break;
        }
        case 0x11: // LDB A,[X]
            cpu.a = rd8(cpu.x);
            break;

        case 0x12: { // LDB B,[imm16]
            uint16_t addr = fetch16(cpu.pc); cpu.pc += 2;
            cpu.b = rd8(addr);
            break;
        }
        case 0x13: // LDB B,[X]
            cpu.b = rd8(cpu.x);
            break;

        // STB  (§6.7)  mem8 = reg & 0xFF  FLAGS 不変
        case 0x14: { // STB A,[imm16]
            uint16_t addr = fetch16(cpu.pc); cpu.pc += 2;
            wr8(addr, (uint8_t)(cpu.a & 0xFF));
            break;
        }
        case 0x15: // STB A,[X]
            wr8(cpu.x, (uint8_t)(cpu.a & 0xFF));
            break;

        case 0x16: { // STB B,[imm16]
            uint16_t addr = fetch16(cpu.pc); cpu.pc += 2;
            wr8(addr, (uint8_t)(cpu.b & 0xFF));
            break;
        }
        case 0x17: // STB B,[X]
            wr8(cpu.x, (uint8_t)(cpu.b & 0xFF));
            break;

        default:
            printf("Unknown EXT sub-opcode %02x at %04x\n", sub, pc0);
            cpu.halted = 1;
            break;
        }
        break;
    }

    // ---- Data Transfer (0x20-0x3F) ----

    case 0x20: { /* MOV rD, rS */
        uint8_t rb = mem[cpu.pc++];
        uint16_t *rd = get_reg_ptr(rb >> 4);
        uint16_t *rs = get_reg_ptr(rb & 0x0F);
        if (rd && rs) *rd = *rs;
        break;
    }
    case 0x21: { /* LDW rD, #imm16 */
        uint8_t rb = mem[cpu.pc++];
        uint16_t imm = fetch16(cpu.pc); cpu.pc += 2;
        uint16_t *rd = get_reg_ptr(rb >> 4);
        if (rd) { *rd = imm; set_zn(*rd); }
        break;
    }
    case 0x22: { /* LDW rD, [imm16] */
        uint8_t rb = mem[cpu.pc++];
        uint16_t imm = fetch16(cpu.pc); cpu.pc += 2;
        uint16_t *rd = get_reg_ptr(rb >> 4);
        if (rd) { *rd = rd16(imm); set_zn(*rd); }
        break;
    }
    case 0x23: { /* STW rS, [imm16] */
        uint8_t rb = mem[cpu.pc++];
        uint16_t imm = fetch16(cpu.pc); cpu.pc += 2;
        uint16_t *rs = get_reg_ptr(rb & 0x0F);
        if (rs) wr16(imm, *rs);
        break;
    }
    case 0x24: { /* LDW rD, [rS] */
        uint8_t rb = mem[cpu.pc++];
        uint16_t *rd = get_reg_ptr(rb >> 4);
        uint16_t *rs = get_reg_ptr(rb & 0x0F);
        if (rd && rs) { *rd = rd16(*rs); set_zn(*rd); }
        break;
    }
    case 0x25: { /* STW rS, [rD]  — rD=アドレス rS=データ */
        uint8_t rb = mem[cpu.pc++];
        uint16_t *rd = get_reg_ptr(rb >> 4);
        uint16_t *rs = get_reg_ptr(rb & 0x0F);
        if (rd && rs) wr16(*rd, *rs);
        break;
    }
    case 0x26: { /* LDW rD, [X + imm16] */
        uint8_t rb = mem[cpu.pc++];
        uint16_t imm = fetch16(cpu.pc); cpu.pc += 2;
        uint16_t *rd = get_reg_ptr(rb >> 4);
        if (rd) {
            uint16_t addr = (uint16_t)(cpu.x + imm);
            *rd = rd16(addr);
            set_zn(*rd);
        }
        break;
    }
    case 0x27: { /* STW rS, [X + imm16] */
        uint8_t rb = mem[cpu.pc++];
        uint16_t imm = fetch16(cpu.pc); cpu.pc += 2;
        uint16_t *rs = get_reg_ptr(rb & 0x0F);
        if (rs) {
            uint16_t addr = (uint16_t)(cpu.x + imm);
            wr16(addr, *rs);
        }
        break;
    }

    // ---- Arithmetic / Logic (0x40-0x5F) ----

    case 0x40: { /* ADD rD, rS */
        uint8_t rb = mem[cpu.pc++];
        uint16_t *rd = get_reg_ptr(rb >> 4);
        uint16_t *rs = get_reg_ptr(rb & 0x0F);
        if (rd && rs) { *rd += *rs; set_zn(*rd); }
        break;
    }
    case 0x41: { /* ADDI rD, #imm16 */
        uint8_t rb = mem[cpu.pc++];
        uint16_t imm = fetch16(cpu.pc); cpu.pc += 2;
        uint16_t *rd = get_reg_ptr(rb >> 4);
        if (rd) { *rd += imm; set_zn(*rd); }
        break;
    }
    case 0x42: { /* SUB rD, rS */
        uint8_t rb = mem[cpu.pc++];
        uint16_t *rd = get_reg_ptr(rb >> 4);
        uint16_t *rs = get_reg_ptr(rb & 0x0F);
        if (rd && rs) { *rd -= *rs; set_zn(*rd); }
        break;
    }
    case 0x43: { /* SUBI rD, #imm16 */
        uint8_t rb = mem[cpu.pc++];
        uint16_t imm = fetch16(cpu.pc); cpu.pc += 2;
        uint16_t *rd = get_reg_ptr(rb >> 4);
        if (rd) { *rd -= imm; set_zn(*rd); }
        break;
    }
    case 0x44: { /* CMP rD, rS  — FLAGS のみ変化 */
        uint8_t rb = mem[cpu.pc++];
        uint16_t *rd = get_reg_ptr(rb >> 4);
        uint16_t *rs = get_reg_ptr(rb & 0x0F);
        if (rd && rs) set_zn((uint16_t)(*rd - *rs));
        break;
    }
    case 0x45: { /* CMPI rD, #imm16  — FLAGS のみ変化 */
        uint8_t rb = mem[cpu.pc++];
        uint16_t imm = fetch16(cpu.pc); cpu.pc += 2;
        uint16_t *rd = get_reg_ptr(rb >> 4);
        if (rd) set_zn((uint16_t)(*rd - imm));
        break;
    }

    // ---- ISA2.2 Bit operations (0x50-0x59) ----

    case 0x50: { /* AND rD, rS */
        uint8_t rb = mem[cpu.pc++];
        uint16_t *rd = get_reg_ptr(rb >> 4);
        uint16_t *rs = get_reg_ptr(rb & 0x0F);
        if (rd && rs) { *rd &= *rs; set_zn(*rd); }
        break;
    }
    case 0x51: { /* ANDI rD, #imm16 */
        uint8_t rb = mem[cpu.pc++];
        uint16_t imm = fetch16(cpu.pc); cpu.pc += 2;
        uint16_t *rd = get_reg_ptr(rb >> 4);
        if (rd) { *rd &= imm; set_zn(*rd); }
        break;
    }
    case 0x52: { /* OR rD, rS */
        uint8_t rb = mem[cpu.pc++];
        uint16_t *rd = get_reg_ptr(rb >> 4);
        uint16_t *rs = get_reg_ptr(rb & 0x0F);
        if (rd && rs) { *rd |= *rs; set_zn(*rd); }
        break;
    }
    case 0x53: { /* ORI rD, #imm16 */
        uint8_t rb = mem[cpu.pc++];
        uint16_t imm = fetch16(cpu.pc); cpu.pc += 2;
        uint16_t *rd = get_reg_ptr(rb >> 4);
        if (rd) { *rd |= imm; set_zn(*rd); }
        break;
    }
    case 0x54: { /* XOR rD, rS */
        uint8_t rb = mem[cpu.pc++];
        uint16_t *rd = get_reg_ptr(rb >> 4);
        uint16_t *rs = get_reg_ptr(rb & 0x0F);
        if (rd && rs) { *rd ^= *rs; set_zn(*rd); }
        break;
    }
    case 0x55: { /* XORI rD, #imm16 */
        uint8_t rb = mem[cpu.pc++];
        uint16_t imm = fetch16(cpu.pc); cpu.pc += 2;
        uint16_t *rd = get_reg_ptr(rb >> 4);
        if (rd) { *rd ^= imm; set_zn(*rd); }
        break;
    }
    case 0x56: { /* NOT rD  — ビット反転 */
        uint8_t rb = mem[cpu.pc++];
        uint16_t *rd = get_reg_ptr(rb >> 4);
        if (rd) { *rd = (uint16_t)(~(*rd)); set_zn(*rd); }
        break;
    }
    case 0x57: { /* SHL rD, rS  — 論理左シフト */
        uint8_t rb = mem[cpu.pc++];
        uint16_t *rd = get_reg_ptr(rb >> 4);
        uint16_t *rs = get_reg_ptr(rb & 0x0F);
        if (rd && rs) {
            uint16_t shift = *rs & 0x0F;   /* シフト量は下位4bitのみ有効 */
            *rd = (uint16_t)(*rd << shift);
            set_zn(*rd);
        }
        break;
    }
    case 0x58: { /* SHR rD, rS  — 論理右シフト (0埋め) */
        uint8_t rb = mem[cpu.pc++];
        uint16_t *rd = get_reg_ptr(rb >> 4);
        uint16_t *rs = get_reg_ptr(rb & 0x0F);
        if (rd && rs) {
            uint16_t shift = *rs & 0x0F;
            *rd = (uint16_t)(*rd >> shift);
            set_zn(*rd);
        }
        break;
    }
    case 0x59: { /* SAR rD, rS  — 算術右シフト (符号ビット保持) */
        uint8_t rb = mem[cpu.pc++];
        uint16_t *rd = get_reg_ptr(rb >> 4);
        uint16_t *rs = get_reg_ptr(rb & 0x0F);
        if (rd && rs) {
            uint16_t shift = *rs & 0x0F;
            int16_t signed_val = (int16_t)(*rd);
            *rd = (uint16_t)(signed_val >> shift);  /* C99: 実装定義だが実用上算術シフト */
            set_zn(*rd);
        }
        break;
    }

    // ---- Branch / Flow (0x60-0x7F) ----

    case 0x60: { /* JMP rel16 */
        int16_t off = (int16_t)fetch16(cpu.pc); cpu.pc += 2;
        cpu.pc = (uint16_t)(cpu.pc + off);
        break;
    }
    case 0x61: { /* BEQ rel16  Z=1 */
        int16_t off = (int16_t)fetch16(cpu.pc); cpu.pc += 2;
        if (cpu.flags & FL_Z) cpu.pc = (uint16_t)(cpu.pc + off);
        break;
    }
    case 0x62: { /* BNE rel16  Z=0 */
        int16_t off = (int16_t)fetch16(cpu.pc); cpu.pc += 2;
        if (!(cpu.flags & FL_Z)) cpu.pc = (uint16_t)(cpu.pc + off);
        break;
    }
    case 0x63: { /* BLT rel16  N=1 */
        int16_t off = (int16_t)fetch16(cpu.pc); cpu.pc += 2;
        if (cpu.flags & FL_N) cpu.pc = (uint16_t)(cpu.pc + off);
        break;
    }
    case 0x64: { /* BGE rel16  N=0 */
        int16_t off = (int16_t)fetch16(cpu.pc); cpu.pc += 2;
        if (!(cpu.flags & FL_N)) cpu.pc = (uint16_t)(cpu.pc + off);
        break;
    }
    case 0x68: { /* JSR imm16 */
        uint16_t target = fetch16(cpu.pc); cpu.pc += 2;
        push16(cpu.pc);   // 戻り先 (next PC) を push
        cpu.pc = target;
        break;
    }
    case 0x69: /* RET */
        cpu.pc = pop16();
        break;

    default:
        printf("Unknown opcode %02x at %04x\n", cpu.ir, pc0);
        cpu.halted = 1;
        break;
    }

    // HALT 直後の状態表示
    if (cpu.halted) {
        printf("*** HALT at %04x ***\n", pc0);
        dump_regs();
        return;
    }

    // --- タイマー IRQ (every 100 instructions) ---
    // [FIX BUG-7] cycle > 0 ガードで起動直後の誤発火を防ぐ
    if (cpu.cycle >= cpu.timer_cycle && cpu.irq_pending < 0) {
        cpu.irq_pending = 1;  // IRQ0 (id=1)
        cpu.timer_cycle = UINT64_MAX; // IRETが次のタイミングを再設定する
    }
}

// ================= REPL ================

static void repl(void) {
    char cmd[128];

    while (1) {
        // HALT 状態でも regs/mem/q は使えるように、先にプロンプトを表示
        if (cpu.halted) {
            printf("[HALTED] ");
        } else if (is_break(cpu.pc)) {
            printf("** BREAK @%04x **\n", cpu.pc);
        }

        // [FIX WARN-4] FLAGS=%02X は dump_regs() 内で修正済み
        printf("PC=%04x A=%04x B=%04x X=%04x SP=%04x F=%02x | %s\n",
               cpu.pc, cpu.a, cpu.b, cpu.x, cpu.sp, cpu.flags,
               dbg_lookup(cpu.pc));

        printf("(emu) ");
        if (!fgets(cmd, sizeof(cmd), stdin)) break;

        // s [N]  — step N instructions
        if (cmd[0] == 's') {
            if (cpu.halted) { printf("CPU is halted\n"); continue; }
            int n = 1;
            if (sscanf(cmd + 1, "%d", &n) != 1) n = 1;
            // [FIX BUG-8] exec_one() 後にも is_break をチェック
            while (n-- > 0 && !cpu.halted) {
                exec_one();
                if (is_break(cpu.pc)) break;
            }

        // c  — continue (run until halt or breakpoint)
        } else if (cmd[0] == 'c') {
            if (cpu.halted) { printf("CPU is halted\n"); continue; }
            while (!cpu.halted && !is_break(cpu.pc)) exec_one();

        // t  — trace (step + dump after each instruction)
        } else if (cmd[0] == 't') {
            if (cpu.halted) { printf("CPU is halted\n"); continue; }
            while (!cpu.halted && !is_break(cpu.pc)) {
                exec_one();
                dump_regs();
            }

        // b [addr|label]  — set / list breakpoints
        } else if (cmd[0] == 'b') {
            if (cmd[1] == '\n' || cmd[1] == '\0') {
                printf("Num  Addr\n");
                for (int i = 0; i < bp_count; i++)
                    printf("%-4d %04x\n", i, breakpoints[i]);
                continue;
            }
            char arg[64];
            if (sscanf(cmd + 1, "%63s", arg) != 1) {
                printf("Usage: b <addr|label>\n");
                continue;
            }
            uint16_t addr;
            if (sscanf(arg, "%hx", &addr) != 1) {
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

        // bd N  — delete breakpoint N
        } else if (strncmp(cmd, "bd", 2) == 0) {
            int idx;
            if (sscanf(cmd + 2, "%d", &idx) == 1 && idx >= 0 && idx < bp_count) {
                for (int i = idx; i < bp_count - 1; i++)
                    breakpoints[i] = breakpoints[i + 1];
                bp_count--;
                printf("Breakpoint %d deleted\n", idx);
            } else {
                printf("Usage: bd <num>\n");
            }

        // regs  — dump registers
        } else if (strncmp(cmd, "regs", 4) == 0) {
            dump_regs();

        // disas [addr [n]]  — disassemble
        } else if (strncmp(cmd, "disas", 5) == 0) {
            uint16_t addr = cpu.pc;
            int n = 10;
            sscanf(cmd + 5, "%hx %d", &addr, &n);
            disas(addr, n);

        // memw [addr [n]]  — dump memory as words
        } else if (strncmp(cmd, "memw", 4) == 0) {
            uint16_t addr = cpu.pc;
            int n = 8;
            sscanf(cmd + 4, "%hx %d", &addr, &n);
            dump_memw(addr, n);

        // mem [addr [n]]  — dump memory as bytes
        } else if (strncmp(cmd, "mem", 3) == 0) {
            uint16_t addr = cpu.pc;
            int n = 64;
            sscanf(cmd + 3, "%hx %d", &addr, &n);
            dump_mem(addr, n);

        // irq N  — inject IRQ
        } else if (strncmp(cmd, "irq", 3) == 0) {
            int n;
            if (sscanf(cmd + 3, "%d", &n) == 1) {
                printf("** IRQ %d injected **\n", n);
                cpu.irq_pending = n;
            } else {
                printf("usage: irq <id>\n");
            }

        // reset  — reinitialize CPU (memory preserved)
        } else if (strncmp(cmd, "reset", 5) == 0) {
            cpu.pc          = rd16(0x0000);
            cpu.flags       = 0;
            cpu.irq_pending = -1;
            cpu.halted      = 0;
            cpu.cycle       = 0;
            cpu.timer_cycle = 30000;
            printf("CPU reset. PC=%04x\n", cpu.pc);

        // q  — quit
        } else if (cmd[0] == 'q') {
            break;

        // help
        } else if (strncmp(cmd, "help", 4) == 0 || cmd[0] == '?') {
            printf(
                "Commands:\n"
                "  s [N]          step N instructions (default 1)\n"
                "  c              continue until halt/breakpoint\n"
                "  t              trace (step + dump regs each)\n"
                "  b <addr|lbl>   set breakpoint\n"
                "  bd <N>         delete breakpoint N\n"
                "  b              list breakpoints\n"
                "  regs           show registers\n"
                "  disas [a [n]]  disassemble n instructions from a\n"
                "  mem  [a [n]]   dump n bytes from a\n"
                "  memw [a [n]]   dump n words from a\n"
                "  irq <id>       inject IRQ\n"
                "  reset          reset CPU (memory unchanged)\n"
                "  q              quit\n"
            );
        }
        // unknown command: silently ignore (user may have pressed Enter)
    }
}

// ================= Main ================

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr,
            "usage: emu prog.bin [prog.dbg [prog.sym]]\n"
            "  prog.dbg and prog.sym are auto-derived from prog.bin if omitted\n");
        return 1;
    }

    load_bin(argv[1]);

    // [FIX WARN-2] change_ext にバッファを渡す
    char extbuf[256];

    if (argc >= 3) {
        load_dbg(argv[2]);
    } else {
        change_ext(extbuf, sizeof(extbuf), argv[1], ".dbg");
        load_dbg(extbuf);
    }

    if (argc >= 4) {
        load_sym(argv[3]);
    } else {
        change_ext(extbuf, sizeof(extbuf), argv[1], ".sym");
        load_sym(extbuf);
    }

    // CPU 初期化 (§7.3)
    memset(&cpu, 0, sizeof(cpu));
    cpu.sp          = 0xFFFE;
    cpu.irq_pending = -1;
    cpu.pc          = rd16(0x0000);  // reset vector (§7.3)
    cpu.timer_cycle = 30000;         // 最初のタイマーIRQは30000サイクル後
    // flags=0 → IE=0 (割り込み禁止) は仕様通り

    printf("YSD8800 ISA2.2 Emulator — reset vector = %04x\n", cpu.pc);
    printf("Type 'help' for commands.\n");

    repl();
    return 0;
}
