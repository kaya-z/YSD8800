// emu22_mmu.c - YSD8800 ISA2.2 Emulator with FM-11 style MMU Extension
// Version: 1.0.0
// YSD8800 Forthカーネルプロジェクト
//
// ISA2.2 対応命令:
//   ビット演算: AND/ANDI/OR/ORI/XOR/XORI/NOT/SHL/SHR/SAR (0x50-0x59)
//
// MMU拡張 (FM-11方式ページング):
//   ページサイズ  : 4KB
//   論理ページ数  : 16 (64KB / 4KB)
//   物理アドレス  : 20bit / 1MB (256物理ページ × 4KB)
//
//   MMU制御レジスタ (論理アドレス, メモリマップドI/O):
//     0xFF00-0xFF0F : PTR[0]-PTR[15]  論理→物理ページ番号 (各8bit)
//     0xFF10        : MCR  bit0=MMU_EN, bit1=KRN_PROT(将来)
//
//   アドレス変換 (MCR bit0=1 の時):
//     page   = logical >> 12
//     offset = logical & 0x0FFF
//     phys   = (PTR[page] << 12) | offset  (20bit)
//
//   MCR bit0=0 の時: 恒等写像 (phys = logical)
//   リセット時: PTR[n]=n, MCR=0
//
// I/Oアドレス (論理アドレス, MMU変換前に処理):
//   0xFC80 : UART TX  (write: 下位8bitを stdout へ出力)
//   0xFC82 : UART RX  (read: 0, 未実装)
//   0xFC84 : UART STAT (read: bit0=TX_READY=1)
//
// emu22.c (ISA2.2) からの変更点:
//   - 物理メモリを uint8_t phys_mem[1MB] に拡張
//   - mmu_t 構造体 (ptr[16], mcr) 追加
//   - rd8/wr8/rd16/wr16/fetch16 に MMU 変換を組み込み
//   - UART/MMUレジスタは論理アドレス段階でトラップ (MMU変換前)
//   - cpu_t に timer_cycle フィールド追加 (emu22.c と同一)
//   - デバッガに mmu / physmem コマンド追加
//   - プロンプト: (emu22_mmu)
//   - バッチモード: -n/-b/-m オプション
//
// emu22.c から引き継いだ修正点:
//   BUG-1 [MEDIUM] BRK: halts and prints trap message
//   BUG-2 [HIGH]   rd16(): alignment exception → early return
//   BUG-3 [HIGH]   fetch16(): address wrap safe
//   BUG-4 [MEDIUM] disas(): advances pc by actual instruction size
//   BUG-5 [MEDIUM] load_dbg: fscanf width limiter added
//   BUG-6 [MEDIUM] EXT prefix: no duplicate cpu.cycle++
//   BUG-7 [MEDIUM] timer IRQ: cycle > 0 guard via timer_cycle
//   BUG-8 [MEDIUM] step: is_break check after each exec_one()
//   WARN-1 [LOW]   cpu.irq_en removed; use (cpu.flags & FL_IE) exclusively
//   WARN-2 [LOW]   change_ext: caller-supplied buffer
//   WARN-4 [LOW]   dump_regs: FLAGS printed as %02X
//   WARN-5 [LOW]   IRET: explicit (uint8_t) cast on pop16()
//
// build: gcc -std=c99 -O2 -Wall -Wextra emu22_mmu.c -o emu22_mmu

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <ctype.h>

// ─── 物理メモリ: 1MB ───────────────────────────────────────────────────────
#define PHYS_MEM_SIZE  (1024 * 1024)   // 1MB (20bit物理アドレス)
#define LOG_MEM_SIZE   65536           // 論理アドレス空間: 64KB
#define MAX_DBG        8192
#define MAX_BP         128
#define MAX_SYM        128

// ─── I/O アドレス (論理アドレス, MMU変換前に処理) ───────────────────────────
#define UART_TX    0xFC80
#define UART_RX    0xFC82
#define UART_STAT  0xFC84

// ─── MMU レジスタアドレス (論理) ────────────────────────────────────────────
#define MMU_PTR_BASE   0xFF00   // PTR[0]〜PTR[15]: 0xFF00〜0xFF0F
#define MMU_MCR_ADDR   0xFF10   // MMU Control Register
#define MCR_EN         0x01     // bit0: MMU Enable
#define MCR_KRN_PROT   0x02     // bit1: Kernel Protect (将来拡張)

// FLAGS bits
#define FL_Z   0x01   // Zero
#define FL_N   0x02   // Negative
#define FL_IE  0x80   // Interrupt Enable

// ─── 物理メモリ ──────────────────────────────────────────────────────────────
uint8_t phys_mem[PHYS_MEM_SIZE];

// ─── MMU 状態 ─────────────────────────────────────────────────────────────────
typedef struct {
    uint8_t ptr[16];  // Page Table Registers: 論理ページ番号 → 物理ページ番号
    uint8_t mcr;      // MMU Control Register
} mmu_t;

mmu_t mmu;

// ─── MMU: アドレス変換 ───────────────────────────────────────────────────────
static uint32_t mmu_translate(uint16_t logical) {
    if (mmu.mcr & MCR_EN) {
        uint8_t  page   = (uint8_t)(logical >> 12);
        uint16_t offset = logical & 0x0FFF;
        return ((uint32_t)mmu.ptr[page] << 12) | offset;
    }
    return (uint32_t)logical;  // MMU無効: 恒等写像
}

// ─── MMU: リセット初期化 (恒等写像, MMU無効) ─────────────────────────────────
static void mmu_reset(void) {
    for (int i = 0; i < 16; i++) mmu.ptr[i] = (uint8_t)i;
    mmu.mcr = 0;
}

// ─── CPU ─────────────────────────────────────────────────────────────────────
typedef struct {
    uint16_t pc;
    uint16_t a, b;
    uint16_t x;
    uint16_t sp;
    uint8_t  flags;       // bit0=Z  bit1=N  bit7=IE
    uint8_t  ir;
    int      irq_pending; // -1=none, >=0=IRQ id
    int      halted;
    uint64_t cycle;
    uint64_t timer_cycle; // 次のタイマーIRQを発火するcycle値
} cpu_t;

cpu_t cpu;

// ─── DBG / BP / SYM ──────────────────────────────────────────────────────────
typedef struct { uint16_t addr; int line; char text[128]; } dbgline_t;
static dbgline_t dbg[MAX_DBG];
static int dbg_count = 0;

static uint16_t breakpoints[MAX_BP];
static int bp_count = 0;

typedef struct { char name[32]; uint16_t addr; } sym_t;
static sym_t syms[MAX_SYM];
static int sym_count = 0;

// ─── メモリアクセス ──────────────────────────────────────────────────────────
//
// I/O 処理の優先順位 (論理アドレス):
//   1. UART  (0xFC80-0xFC84)  — MMU変換なし
//   2. MMU レジスタ (0xFF00-0xFF10) — MMU変換なし
//   3. 通常メモリ — MMU変換あり

// --- 8bit ---

uint8_t rd8(uint16_t la) {
    // UART
    if (la == UART_STAT) return 0x01;  // TX always ready
    if (la == UART_RX)   return 0x00;  // no input
    // MMU レジスタ読み出し
    if (la >= MMU_PTR_BASE && la < (MMU_PTR_BASE + 16))
        return mmu.ptr[la - MMU_PTR_BASE];
    if (la == MMU_MCR_ADDR)
        return mmu.mcr;
    // 通常メモリ (MMU変換)
    uint32_t pa = mmu_translate(la);
    if (pa >= PHYS_MEM_SIZE) {
        printf("!! PHYS ADDR OVERFLOW rd8 la=%04x pa=%05x\n", la, pa);
        return 0xFF;
    }
    return phys_mem[pa];
}

void wr8(uint16_t la, uint8_t v) {
    // UART TX
    if (la == UART_TX) { putchar((int)v); fflush(stdout); return; }
    // MMU レジスタ書き込み
    if (la >= MMU_PTR_BASE && la < (MMU_PTR_BASE + 16)) {
        mmu.ptr[la - MMU_PTR_BASE] = v; return;
    }
    if (la == MMU_MCR_ADDR) { mmu.mcr = v & 0x03; return; }
    // 通常メモリ (MMU変換)
    uint32_t pa = mmu_translate(la);
    if (pa >= PHYS_MEM_SIZE) {
        printf("!! PHYS ADDR OVERFLOW wr8 la=%04x pa=%05x\n", la, pa);
        return;
    }
    phys_mem[pa] = v;
}

// --- 16bit ---

uint16_t rd16(uint16_t la) {
    // [BUG-2] アラインメント例外
    if (la & 1) {
        printf("!! ALIGNMENT EXCEPTION (READ) @%04x\n", la);
        cpu.irq_pending = 3;
        return 0;
    }
    // UART
    if (la == UART_STAT) return 0x0001;
    if (la == UART_RX)   return 0x0000;
    // 通常メモリ (MMU変換)
    uint32_t pa = mmu_translate(la);
    if (pa + 1 >= PHYS_MEM_SIZE) {
        printf("!! PHYS ADDR OVERFLOW rd16 la=%04x pa=%05x\n", la, pa);
        return 0xFFFF;
    }
    return (uint16_t)(phys_mem[pa] | ((uint16_t)phys_mem[pa + 1] << 8));
}

void wr16(uint16_t la, uint16_t v) {
    if (la & 1) {
        printf("!! ALIGNMENT EXCEPTION (WRITE) @%04x\n", la);
        cpu.irq_pending = 3;
        return;
    }
    // UART TX (STW で書く場合: Forthカーネル対応)
    if (la == UART_TX) { putchar((int)(v & 0xFF)); fflush(stdout); return; }
    // 通常メモリ (MMU変換)
    uint32_t pa = mmu_translate(la);
    if (pa + 1 >= PHYS_MEM_SIZE) {
        printf("!! PHYS ADDR OVERFLOW wr16 la=%04x pa=%05x\n", la, pa);
        return;
    }
    phys_mem[pa]     = (uint8_t)(v & 0xFF);
    phys_mem[pa + 1] = (uint8_t)(v >> 8);
}

// フェッチ用 (アライン不要, MMU変換あり)
static uint16_t fetch16(uint16_t la) {
    uint32_t pa = mmu_translate(la);
    if (pa + 1 >= PHYS_MEM_SIZE) return 0xFFFF;
    return (uint16_t)(phys_mem[pa] | ((uint16_t)phys_mem[pa + 1] << 8));
}

// ─── スタック ─────────────────────────────────────────────────────────────────
static void push16(uint16_t v) { cpu.sp -= 2; wr16(cpu.sp, v); }
static uint16_t pop16(void)    { uint16_t v = rd16(cpu.sp); cpu.sp += 2; return v; }

// ─── ユーティリティ ───────────────────────────────────────────────────────────
static int is_break(uint16_t pc) {
    for (int i = 0; i < bp_count; i++) if (breakpoints[i] == pc) return 1;
    return 0;
}
static const char *dbg_lookup(uint16_t pc) {
    for (int i = 0; i < dbg_count; i++) if (dbg[i].addr == pc) return dbg[i].text;
    return "";
}
static int lookup_sym(const char *name, uint16_t *out) {
    for (int i = 0; i < sym_count; i++) {
        if (strcmp(syms[i].name, name) == 0) { *out = syms[i].addr; return 1; }
    }
    return 0;
}
static void change_ext(char *buf, size_t sz, const char *path, const char *ext) {
    strncpy(buf, path, sz - 1); buf[sz - 1] = '\0';
    char *p = strrchr(buf, '.');
    if (p) { strncpy(p, ext, sz - (size_t)(p - buf) - 1); buf[sz-1] = '\0'; }
    else   { strncat(buf, ext, sz - strlen(buf) - 1); }
}

// ─── ダンプ ───────────────────────────────────────────────────────────────────
static void dump_regs(void) {
    printf("PC=%04X SP=%04X FLAGS=%02X A=%04X B=%04X X=%04X  | %s\n",
           cpu.pc, cpu.sp, cpu.flags, cpu.a, cpu.b, cpu.x, dbg_lookup(cpu.pc));
}

static void dump_mmu(void) {
    printf("MMU: %s  MCR=%02X\n",
           (mmu.mcr & MCR_EN) ? "ENABLED" : "disabled", mmu.mcr);
    for (int i = 0; i < 16; i++) {
        printf("  PTR[%2d]  log %04X-%04X  ->  phys %05X-%05X  (page# %02X)\n",
               i,
               (unsigned)(i * 0x1000),
               (unsigned)(i * 0x1000 + 0x0FFF),
               (unsigned)mmu.ptr[i] * 0x1000,
               (unsigned)mmu.ptr[i] * 0x1000 + 0x0FFF,
               mmu.ptr[i]);
    }
}

static void dump_mem(uint16_t addr, int n) {
    for (int i = 0; i < n; i += 16) {
        printf("%04x: ", (unsigned)(addr + i));
        for (int j = 0; j < 16; j++) {
            if (i+j < n) printf("%02x ", rd8((uint16_t)(addr + i + j)));
            else printf("   ");
        }
        printf(" |");
        for (int j = 0; j < 16 && i+j < n; j++) {
            uint8_t c = rd8((uint16_t)(addr + i + j));
            putchar((c >= 0x20 && c <= 0x7e) ? c : '.');
        }
        printf("|\n");
    }
}

static void dump_phys(uint32_t addr, int n) {
    for (int i = 0; i < n; i += 16) {
        uint32_t ba = addr + (uint32_t)i;
        printf("%05x: ", ba);
        for (int j = 0; j < 16; j++) {
            uint32_t a = ba + (uint32_t)j;
            if (i+j < n && a < PHYS_MEM_SIZE) printf("%02x ", phys_mem[a]);
            else printf("   ");
        }
        printf("\n");
    }
}

static void dump_memw(uint16_t addr, int n) {
    if (addr & 1) printf("!! WARN: unaligned word dump @%04x\n", addr);
    for (int i = 0; i < n; i += 8) {
        uint16_t base = (uint16_t)(addr + i * 2);
        printf("%04x: ", base);
        for (int j = 0; j < 8 && i+j < n; j++) {
            uint16_t a = (uint16_t)(base + j * 2);
            printf("%04x ", rd16(a));
        }
        printf("\n");
    }
}

// ─── ローダ ───────────────────────────────────────────────────────────────────
static void load_bin(const char *fn) {
    FILE *f = fopen(fn, "rb");
    if (!f) { perror(fn); exit(1); }
    // MMU無効（恒等写像）状態なので phys_mem[0] = logical[0] に直接ロード
    size_t got = fread(phys_mem, 1, LOG_MEM_SIZE, f);
    if (got == 0) { fprintf(stderr, "%s: empty or read error\n", fn); exit(1); }
    fclose(f);
    printf("Loaded %u bytes from %s (phys 0x00000)\n", (unsigned)got, fn);
}

static void load_dbg(const char *path) {
    FILE *fp = fopen(path, "r");
    if (!fp) return;
    while (!feof(fp) && dbg_count < MAX_DBG) {
        dbgline_t *d = &dbg[dbg_count];
        if (fscanf(fp, "%hx %127[^\n]", &d->addr, d->text) == 2) dbg_count++;
        else { int c; while ((c = fgetc(fp)) != '\n' && c != EOF) {} }
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
            syms[sym_count].addr = (uint16_t)addr; sym_count++;
        } else if (isxdigit((unsigned char)tok2[0])) {
            addr = (unsigned)strtoul(tok2, NULL, 16);
            snprintf(syms[sym_count].name, sizeof(syms[sym_count].name), "%s", tok1);
            syms[sym_count].addr = (uint16_t)addr; sym_count++;
        }
    }
    fclose(fp);
    printf("Loaded %d label symbols\n", sym_count);
}

// ─── 逆アセンブラ (ISA2.2対応) ───────────────────────────────────────────────
// [BUG-4] 命令の実バイト長を返す
static int instr_size(uint16_t la) {
    uint32_t pa = mmu_translate(la);
    if (pa >= PHYS_MEM_SIZE) return 1;
    uint8_t op = phys_mem[pa];
    switch (op) {
    // 1 byte: operandなし
    case 0x00: case 0x01: case 0x02: case 0x03:
    case 0x04: case 0x06: case 0x69:
        return 1;
    // 3 bytes: opcode + imm16 (regバイトなし)
    case 0x05: case 0x60: case 0x61: case 0x62:
    case 0x63: case 0x64: case 0x68:
        return 3;
    // 2 bytes: opcode + regバイト (immなし)
    case 0x20: case 0x24: case 0x25:
    case 0x40: case 0x42: case 0x44:
    // ISA2.2: ビット演算 (2 bytes)
    case 0x50: case 0x52: case 0x54: case 0x56:
    case 0x57: case 0x58: case 0x59:
        return 2;
    // 4 bytes: opcode + regバイト + imm16
    case 0x21: case 0x22: case 0x23: case 0x26: case 0x27:
    case 0x41: case 0x43: case 0x45:
    // ISA2.2: ビット演算即値 (4 bytes)
    case 0x51: case 0x53: case 0x55:
        return 4;
    // EXT prefix (0x1F): sub-opcodeで可変
    case 0x1F: {
        uint32_t pa2 = mmu_translate((uint16_t)(la + 1));
        if (pa2 >= PHYS_MEM_SIZE) return 2;
        uint8_t sub = phys_mem[pa2];
        switch (sub) {
        case 0x00: case 0x01: case 0x02: // PUSH A/B/X
        case 0x03: case 0x04: case 0x05: // POP  A/B/X
        case 0x11: case 0x13:            // LDB A/B,[X]
        case 0x15: case 0x17:            // STB A/B,[X]
            return 2;
        case 0x10: case 0x12:            // LDB A/B,[imm16]
        case 0x14: case 0x16:            // STB A/B,[imm16]
            return 4;
        default: return 2;
        }
    }
    default: return 1;
    }
}

static void disas(uint16_t addr, int n) {
    uint16_t pc = addr;
    for (int i = 0; i < n; i++) {
        const char *s = dbg_lookup(pc);
        uint32_t    pa = mmu_translate(pc);
        uint8_t     op = (pa < PHYS_MEM_SIZE) ? phys_mem[pa] : 0xFF;
        int         sz = instr_size(pc);
        printf("%04x[%05x]: ", pc, pa);
        for (int j = 0; j < sz && j < 5; j++) {
            uint32_t pj = mmu_translate((uint16_t)(pc + j));
            printf("%02x ", (pj < PHYS_MEM_SIZE) ? phys_mem[pj] : 0xFF);
        }
        for (int j = sz; j < 5; j++) printf("   ");
        if (s && *s) printf("  %s", s);
        else         printf("  op=%02x (%d bytes)", op, sz);
        printf("\n");
        pc = (uint16_t)(pc + sz);
    }
}

// ─── CPU helpers ──────────────────────────────────────────────────────────────
static void set_zn(uint16_t v) {
    if (v == 0)       cpu.flags |=  FL_Z; else cpu.flags &= (uint8_t)~FL_Z;
    if (v & 0x8000)   cpu.flags |=  FL_N; else cpu.flags &= (uint8_t)~FL_N;
}
static uint16_t *get_reg_ptr(uint8_t id) {
    switch (id) {
    case 0: return &cpu.a;
    case 1: return &cpu.b;
    case 2: return &cpu.x;
    case 3: return &cpu.sp;
    default: return NULL;
    }
}

// ─── exec_one ────────────────────────────────────────────────────────────────
void exec_one(void) {
    if (cpu.halted) return;
    uint16_t pc0 = cpu.pc;

    // ワークスペース突入デバッグ (emu22.c 互換)
    if (cpu.pc >= 0xE000 && cpu.pc < 0xE100)
        printf("[DBG] Jumping into workspace! PC=%04X\n", cpu.pc);

    // --- IRQ 受理 (§7.4-7.5) ---
    if (cpu.irq_pending >= 0 && (cpu.flags & FL_IE)) {
        int irq = cpu.irq_pending;
        cpu.irq_pending = -1;
        push16(cpu.pc);
        push16((uint16_t)cpu.flags);
        cpu.flags &= (uint8_t)~FL_IE;
        uint16_t vec = rd16((uint16_t)(irq * 2));
        cpu.pc = vec;
        printf("** IRQ %d accepted, vec=%04x **\n", irq, vec);
    }

    // --- FETCH ---
    {
        uint32_t fpa = mmu_translate(cpu.pc);
        cpu.ir = (fpa < PHYS_MEM_SIZE) ? phys_mem[fpa] : 0xFF;
    }
    cpu.pc++;
    cpu.cycle++;  // [BUG-6] ここのみインクリメント

    // --- DECODE / EXEC ---
    switch (cpu.ir) {

    // ── Control / System (0x00-0x1F) ─────────────────────────────────────────

    case 0x00: /* NOP */ break;

    case 0x01: /* HALT */
        cpu.halted = 1;
        break;

    case 0x02: /* EI */
        cpu.flags |= FL_IE;
        break;

    case 0x03: /* DI */
        cpu.flags &= (uint8_t)~FL_IE;
        break;

    case 0x04: /* IRET  FLAGS←pop / PC←pop (§7.6) */
        cpu.flags = (uint8_t)pop16();  // [WARN-5]
        cpu.pc    = pop16();
        // タイマーIRQクリア & 次タイマー再設定 (emu22.c と同一)
        if (cpu.irq_pending == 1) cpu.irq_pending = -1;
        cpu.timer_cycle = cpu.cycle + 30000;
        break;

    case 0x05: { /* SYSCALL imm16 */
        uint16_t imm = fetch16(cpu.pc); cpu.pc += 2;
        printf("** SYSCALL %u triggered **\n", (unsigned)imm);
        cpu.irq_pending = 4;
        break;
    }

    case 0x06: /* BRK [BUG-1] */
        printf("** BRK at %04x **\n", pc0);
        cpu.halted = 1;
        break;

    // ── ISA2.1 EXT prefix (0x1F) ─────────────────────────────────────────────
    case 0x1F: {
        uint32_t sub_pa = mmu_translate(cpu.pc);
        uint8_t  sub    = (sub_pa < PHYS_MEM_SIZE) ? phys_mem[sub_pa] : 0xFF;
        cpu.pc++;

        switch (sub) {
        // PUSH
        case 0x00: push16(cpu.a); break;
        case 0x01: push16(cpu.b); break;
        case 0x02: push16(cpu.x); break;
        // POP
        case 0x03: cpu.a = pop16(); break;
        case 0x04: cpu.b = pop16(); break;
        case 0x05: cpu.x = pop16(); break;
        // LDB A,[imm16]
        case 0x10: { uint16_t a = fetch16(cpu.pc); cpu.pc += 2; cpu.a = rd8(a); break; }
        // LDB A,[X]
        case 0x11: cpu.a = rd8(cpu.x); break;
        // LDB B,[imm16]
        case 0x12: { uint16_t a = fetch16(cpu.pc); cpu.pc += 2; cpu.b = rd8(a); break; }
        // LDB B,[X]
        case 0x13: cpu.b = rd8(cpu.x); break;
        // STB A,[imm16]
        case 0x14: { uint16_t a = fetch16(cpu.pc); cpu.pc += 2; wr8(a, (uint8_t)(cpu.a & 0xFF)); break; }
        // STB A,[X]
        case 0x15: wr8(cpu.x, (uint8_t)(cpu.a & 0xFF)); break;
        // STB B,[imm16]
        case 0x16: { uint16_t a = fetch16(cpu.pc); cpu.pc += 2; wr8(a, (uint8_t)(cpu.b & 0xFF)); break; }
        // STB B,[X]
        case 0x17: wr8(cpu.x, (uint8_t)(cpu.b & 0xFF)); break;
        default:
            printf("Unknown EXT sub %02x at %04x\n", sub, pc0);
            cpu.halted = 1;
            break;
        }
        break;
    }

    // ── Data Transfer (0x20-0x3F) ─────────────────────────────────────────────

    case 0x20: { /* MOV rD, rS */
        uint8_t rb = rd8(cpu.pc++);
        uint16_t *rd = get_reg_ptr(rb >> 4); uint16_t *rs = get_reg_ptr(rb & 0xF);
        if (rd && rs) *rd = *rs;
        break;
    }
    case 0x21: { /* LDW rD, #imm16 */
        uint8_t rb = rd8(cpu.pc++);
        uint16_t imm = fetch16(cpu.pc); cpu.pc += 2;
        uint16_t *rd = get_reg_ptr(rb >> 4);
        if (rd) { *rd = imm; set_zn(*rd); }
        break;
    }
    case 0x22: { /* LDW rD, [imm16] */
        uint8_t rb = rd8(cpu.pc++);
        uint16_t imm = fetch16(cpu.pc); cpu.pc += 2;
        uint16_t *rd = get_reg_ptr(rb >> 4);
        if (rd) { *rd = rd16(imm); set_zn(*rd); }
        break;
    }
    case 0x23: { /* STW rS, [imm16] */
        uint8_t rb = rd8(cpu.pc++);
        uint16_t imm = fetch16(cpu.pc); cpu.pc += 2;
        uint16_t *rs = get_reg_ptr(rb & 0xF);
        if (rs) wr16(imm, *rs);
        break;
    }
    case 0x24: { /* LDW rD, [rS] */
        uint8_t rb = rd8(cpu.pc++);
        uint16_t *rd = get_reg_ptr(rb >> 4); uint16_t *rs = get_reg_ptr(rb & 0xF);
        if (rd && rs) { *rd = rd16(*rs); set_zn(*rd); }
        break;
    }
    case 0x25: { /* STW rS, [rD] */
        uint8_t rb = rd8(cpu.pc++);
        uint16_t *rd = get_reg_ptr(rb >> 4); uint16_t *rs = get_reg_ptr(rb & 0xF);
        if (rd && rs) wr16(*rd, *rs);
        break;
    }
    case 0x26: { /* LDW rD, [X + imm16] */
        uint8_t rb = rd8(cpu.pc++);
        uint16_t imm = fetch16(cpu.pc); cpu.pc += 2;
        uint16_t *rd = get_reg_ptr(rb >> 4);
        if (rd) { uint16_t a = (uint16_t)(cpu.x + imm); *rd = rd16(a); set_zn(*rd); }
        break;
    }
    case 0x27: { /* STW rS, [X + imm16] */
        uint8_t rb = rd8(cpu.pc++);
        uint16_t imm = fetch16(cpu.pc); cpu.pc += 2;
        uint16_t *rs = get_reg_ptr(rb & 0xF);
        if (rs) { uint16_t a = (uint16_t)(cpu.x + imm); wr16(a, *rs); }
        break;
    }

    // ── Arithmetic (0x40-0x4F) ───────────────────────────────────────────────

    case 0x40: { /* ADD rD, rS */
        uint8_t rb = rd8(cpu.pc++);
        uint16_t *rd = get_reg_ptr(rb >> 4); uint16_t *rs = get_reg_ptr(rb & 0xF);
        if (rd && rs) { *rd += *rs; set_zn(*rd); }
        break;
    }
    case 0x41: { /* ADDI rD, #imm16 */
        uint8_t rb = rd8(cpu.pc++);
        uint16_t imm = fetch16(cpu.pc); cpu.pc += 2;
        uint16_t *rd = get_reg_ptr(rb >> 4);
        if (rd) { *rd += imm; set_zn(*rd); }
        break;
    }
    case 0x42: { /* SUB rD, rS */
        uint8_t rb = rd8(cpu.pc++);
        uint16_t *rd = get_reg_ptr(rb >> 4); uint16_t *rs = get_reg_ptr(rb & 0xF);
        if (rd && rs) { *rd -= *rs; set_zn(*rd); }
        break;
    }
    case 0x43: { /* SUBI rD, #imm16 */
        uint8_t rb = rd8(cpu.pc++);
        uint16_t imm = fetch16(cpu.pc); cpu.pc += 2;
        uint16_t *rd = get_reg_ptr(rb >> 4);
        if (rd) { *rd -= imm; set_zn(*rd); }
        break;
    }
    case 0x44: { /* CMP rD, rS */
        uint8_t rb = rd8(cpu.pc++);
        uint16_t *rd = get_reg_ptr(rb >> 4); uint16_t *rs = get_reg_ptr(rb & 0xF);
        if (rd && rs) set_zn((uint16_t)(*rd - *rs));
        break;
    }
    case 0x45: { /* CMPI rD, #imm16 */
        uint8_t rb = rd8(cpu.pc++);
        uint16_t imm = fetch16(cpu.pc); cpu.pc += 2;
        uint16_t *rd = get_reg_ptr(rb >> 4);
        if (rd) set_zn((uint16_t)(*rd - imm));
        break;
    }

    // ── ISA2.2 Bit Operations (0x50-0x59) ────────────────────────────────────

    case 0x50: { /* AND rD, rS */
        uint8_t rb = rd8(cpu.pc++);
        uint16_t *rd = get_reg_ptr(rb >> 4); uint16_t *rs = get_reg_ptr(rb & 0xF);
        if (rd && rs) { *rd &= *rs; set_zn(*rd); }
        break;
    }
    case 0x51: { /* ANDI rD, #imm16 */
        uint8_t rb = rd8(cpu.pc++);
        uint16_t imm = fetch16(cpu.pc); cpu.pc += 2;
        uint16_t *rd = get_reg_ptr(rb >> 4);
        if (rd) { *rd &= imm; set_zn(*rd); }
        break;
    }
    case 0x52: { /* OR rD, rS */
        uint8_t rb = rd8(cpu.pc++);
        uint16_t *rd = get_reg_ptr(rb >> 4); uint16_t *rs = get_reg_ptr(rb & 0xF);
        if (rd && rs) { *rd |= *rs; set_zn(*rd); }
        break;
    }
    case 0x53: { /* ORI rD, #imm16 */
        uint8_t rb = rd8(cpu.pc++);
        uint16_t imm = fetch16(cpu.pc); cpu.pc += 2;
        uint16_t *rd = get_reg_ptr(rb >> 4);
        if (rd) { *rd |= imm; set_zn(*rd); }
        break;
    }
    case 0x54: { /* XOR rD, rS */
        uint8_t rb = rd8(cpu.pc++);
        uint16_t *rd = get_reg_ptr(rb >> 4); uint16_t *rs = get_reg_ptr(rb & 0xF);
        if (rd && rs) { *rd ^= *rs; set_zn(*rd); }
        break;
    }
    case 0x55: { /* XORI rD, #imm16 */
        uint8_t rb = rd8(cpu.pc++);
        uint16_t imm = fetch16(cpu.pc); cpu.pc += 2;
        uint16_t *rd = get_reg_ptr(rb >> 4);
        if (rd) { *rd ^= imm; set_zn(*rd); }
        break;
    }
    case 0x56: { /* NOT rD */
        uint8_t rb = rd8(cpu.pc++);
        uint16_t *rd = get_reg_ptr(rb >> 4);
        if (rd) { *rd = (uint16_t)(~(*rd)); set_zn(*rd); }
        break;
    }
    case 0x57: { /* SHL rD, rS  — 論理左シフト */
        uint8_t rb = rd8(cpu.pc++);
        uint16_t *rd = get_reg_ptr(rb >> 4); uint16_t *rs = get_reg_ptr(rb & 0xF);
        if (rd && rs) {
            uint16_t sh = *rs & 0x0F;
            *rd = (uint16_t)(*rd << sh); set_zn(*rd);
        }
        break;
    }
    case 0x58: { /* SHR rD, rS  — 論理右シフト (0埋め) */
        uint8_t rb = rd8(cpu.pc++);
        uint16_t *rd = get_reg_ptr(rb >> 4); uint16_t *rs = get_reg_ptr(rb & 0xF);
        if (rd && rs) {
            uint16_t sh = *rs & 0x0F;
            *rd = (uint16_t)(*rd >> sh); set_zn(*rd);
        }
        break;
    }
    case 0x59: { /* SAR rD, rS  — 算術右シフト (符号ビット保持) */
        uint8_t rb = rd8(cpu.pc++);
        uint16_t *rd = get_reg_ptr(rb >> 4); uint16_t *rs = get_reg_ptr(rb & 0xF);
        if (rd && rs) {
            uint16_t sh = *rs & 0x0F;
            int16_t sv = (int16_t)(*rd);
            *rd = (uint16_t)(sv >> sh); set_zn(*rd);
        }
        break;
    }

    // ── Branch / Flow (0x60-0x7F) ─────────────────────────────────────────────

    case 0x60: { /* JMP rel16 */
        int16_t off = (int16_t)fetch16(cpu.pc); cpu.pc += 2;
        cpu.pc = (uint16_t)(cpu.pc + off);
        break;
    }
    case 0x61: { /* BEQ rel16 */
        int16_t off = (int16_t)fetch16(cpu.pc); cpu.pc += 2;
        if (cpu.flags & FL_Z) cpu.pc = (uint16_t)(cpu.pc + off);
        break;
    }
    case 0x62: { /* BNE rel16 */
        int16_t off = (int16_t)fetch16(cpu.pc); cpu.pc += 2;
        if (!(cpu.flags & FL_Z)) cpu.pc = (uint16_t)(cpu.pc + off);
        break;
    }
    case 0x63: { /* BLT rel16 */
        int16_t off = (int16_t)fetch16(cpu.pc); cpu.pc += 2;
        if (cpu.flags & FL_N) cpu.pc = (uint16_t)(cpu.pc + off);
        break;
    }
    case 0x64: { /* BGE rel16 */
        int16_t off = (int16_t)fetch16(cpu.pc); cpu.pc += 2;
        if (!(cpu.flags & FL_N)) cpu.pc = (uint16_t)(cpu.pc + off);
        break;
    }
    case 0x68: { /* JSR imm16 */
        uint16_t tgt = fetch16(cpu.pc); cpu.pc += 2;
        push16(cpu.pc);
        cpu.pc = tgt;
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

    if (cpu.halted) {
        printf("*** HALT at %04x ***\n", pc0);
        dump_regs();
        return;
    }

    // --- タイマー IRQ (30000サイクルごと) [BUG-7] ---
    if (cpu.cycle >= cpu.timer_cycle && cpu.irq_pending < 0) {
        cpu.irq_pending  = 1;
        cpu.timer_cycle  = UINT64_MAX; // IRETが次タイミングを再設定
    }
}

// ─── REPL ────────────────────────────────────────────────────────────────────
static void repl(void) {
    char cmd[128];
    while (1) {
        if (cpu.halted) printf("[HALTED] ");
        else if (is_break(cpu.pc)) printf("** BREAK @%04x **\n", cpu.pc);

        printf("PC=%04x A=%04x B=%04x X=%04x SP=%04x F=%02x | %s\n",
               cpu.pc, cpu.a, cpu.b, cpu.x, cpu.sp, cpu.flags,
               dbg_lookup(cpu.pc));
        printf("(emu22_mmu) ");
        if (!fgets(cmd, sizeof(cmd), stdin)) break;

        if (cmd[0] == 's') {
            if (cpu.halted) { printf("CPU is halted\n"); continue; }
            int n = 1;
            if (sscanf(cmd+1, "%d", &n) != 1) n = 1;
            while (n-- > 0 && !cpu.halted) { exec_one(); if (is_break(cpu.pc)) break; }  // [BUG-8]

        } else if (cmd[0] == 'c') {
            if (cpu.halted) { printf("CPU is halted\n"); continue; }
            while (!cpu.halted && !is_break(cpu.pc)) exec_one();

        } else if (cmd[0] == 't') {
            if (cpu.halted) { printf("CPU is halted\n"); continue; }
            while (!cpu.halted && !is_break(cpu.pc)) { exec_one(); dump_regs(); }

        } else if (cmd[0] == 'b') {
            if (cmd[1] == '\n' || cmd[1] == '\0') {
                printf("Num  Addr\n");
                for (int i = 0; i < bp_count; i++) printf("%-4d %04x\n", i, breakpoints[i]);
                continue;
            }
            char arg[64];
            if (sscanf(cmd+1, "%63s", arg) != 1) { printf("Usage: b <addr|label>\n"); continue; }
            uint16_t addr;
            if (sscanf(arg, "%hx", &addr) != 1) {
                if (!lookup_sym(arg, &addr)) { printf("Unknown label: %s\n", arg); continue; }
            }
            if (bp_count >= MAX_BP) printf("Too many breakpoints\n");
            else { breakpoints[bp_count++] = addr; printf("Breakpoint %d set at %04x\n", bp_count-1, addr); }

        } else if (strncmp(cmd, "bd", 2) == 0) {
            int idx;
            if (sscanf(cmd+2, "%d", &idx) == 1 && idx >= 0 && idx < bp_count) {
                for (int i = idx; i < bp_count-1; i++) breakpoints[i] = breakpoints[i+1];
                bp_count--;
                printf("Breakpoint %d deleted\n", idx);
            } else printf("Usage: bd <num>\n");

        } else if (strncmp(cmd, "regs", 4) == 0) {
            dump_regs();

        // ── MMU コマンド群 ───────────────────────────────────────────────────
        } else if (strncmp(cmd, "mmu", 3) == 0) {
            char sub[16] = "";
            sscanf(cmd+3, "%15s", sub);
            if (sub[0] == '\0' || sub[0] == '\n') {
                dump_mmu();
            } else if (strcmp(sub, "en") == 0) {
                mmu.mcr |= MCR_EN; printf("MMU ENABLED\n");
            } else if (strcmp(sub, "dis") == 0) {
                mmu.mcr &= (uint8_t)~MCR_EN; printf("MMU disabled\n");
            } else if (strcmp(sub, "ptr") == 0) {
                int n, v;
                if (sscanf(cmd+3+3, "%d %x", &n, &v) == 2 && n >= 0 && n < 16) {
                    mmu.ptr[n] = (uint8_t)v;
                    printf("PTR[%d] = %02x  (log %04x-%04x -> phys %05x-%05x)\n",
                           n, mmu.ptr[n],
                           n * 0x1000, n * 0x1000 + 0xFFF,
                           (unsigned)mmu.ptr[n] * 0x1000,
                           (unsigned)mmu.ptr[n] * 0x1000 + 0xFFF);
                } else printf("Usage: mmu ptr <0-15> <physpage_hex>\n");
            } else {
                printf("mmu | mmu en | mmu dis | mmu ptr N V\n");
            }

        // ── physmem: 物理メモリ直接ダンプ ────────────────────────────────────
        } else if (strncmp(cmd, "physmem", 7) == 0) {
            unsigned addr = 0; int n = 64;
            sscanf(cmd+7, "%x %d", &addr, &n);
            if (addr < PHYS_MEM_SIZE) dump_phys((uint32_t)addr, n);
            else printf("physmem: addr %05x out of range (max %05x)\n", addr, PHYS_MEM_SIZE-1);

        } else if (strncmp(cmd, "disas", 5) == 0) {
            uint16_t addr = cpu.pc; int n = 10;
            sscanf(cmd+5, "%hx %d", &addr, &n);
            disas(addr, n);

        } else if (strncmp(cmd, "memw", 4) == 0) {
            uint16_t addr = cpu.pc; int n = 8;
            sscanf(cmd+4, "%hx %d", &addr, &n);
            dump_memw(addr, n);

        } else if (strncmp(cmd, "mem", 3) == 0) {
            uint16_t addr = cpu.pc; int n = 64;
            sscanf(cmd+3, "%hx %d", &addr, &n);
            dump_mem(addr, n);

        } else if (strncmp(cmd, "irq", 3) == 0) {
            int n;
            if (sscanf(cmd+3, "%d", &n) == 1) { printf("** IRQ %d injected **\n", n); cpu.irq_pending = n; }
            else printf("usage: irq <id>\n");

        } else if (strncmp(cmd, "reset", 5) == 0) {
            mmu_reset();
            cpu.pc          = rd16(0x0000);
            cpu.flags       = 0;
            cpu.irq_pending = -1;
            cpu.halted      = 0;
            cpu.cycle       = 0;
            cpu.timer_cycle = 30000;
            printf("CPU+MMU reset. PC=%04x\n", cpu.pc);

        } else if (cmd[0] == 'q') {
            break;

        } else if (strncmp(cmd, "help", 4) == 0 || cmd[0] == '?') {
            printf(
                "Commands:\n"
                "  s [N]            step N instructions (default 1)\n"
                "  c                continue until halt/breakpoint\n"
                "  t                trace (step + dump regs each)\n"
                "  b <addr|lbl>     set breakpoint\n"
                "  bd <N>           delete breakpoint N\n"
                "  b                list breakpoints\n"
                "  regs             show registers\n"
                "  disas [a [n]]    disassemble n instructions from a (shows phys addr)\n"
                "  mem  [a [n]]     dump n bytes (logical, via MMU)\n"
                "  memw [a [n]]     dump n words (logical, via MMU)\n"
                "  physmem [a [n]]  dump n bytes from physical address a\n"
                "  mmu              show MMU state (all PTRs)\n"
                "  mmu en           enable MMU\n"
                "  mmu dis          disable MMU\n"
                "  mmu ptr N V      set PTR[N] = V (hex physical page number)\n"
                "  irq <id>         inject IRQ\n"
                "  reset            reset CPU+MMU (memory unchanged)\n"
                "  q                quit\n"
            );
        }
    }
}

// ─── main ────────────────────────────────────────────────────────────────────
int main(int argc, char **argv) {
    int      run_steps  = 0;   // -n N: Nステップ実行してトレース出力後終了
    int      trace_from = -1;  // -b ADDR: このアドレス到達後にトレース開始
    int      dump_addr  = -1;
    int      dump_len   = 0;

    if (argc < 2) {
        fprintf(stderr,
            "YSD8800 ISA2.2 Emulator + MMU Extension  (emu22_mmu v1.0.0)\n"
            "usage: emu22_mmu prog.bin [prog.dbg [prog.sym]] [-n N] [-b ADDR] [-m ADDR N]\n"
            "  -n N         run N steps and dump trace (non-interactive)\n"
            "  -b ADDR      start tracing after reaching ADDR (hex)\n"
            "  -m ADDR N    after trace, dump N words from ADDR (hex)\n"
            "  prog.dbg / prog.sym are auto-derived from prog.bin if omitted\n"
            "\n"
            "MMU: FM-11 style 4KB paging, 16 logical pages -> 1MB physical\n"
            "     PTR[0..15] at 0xFF00..0xFF0F  MCR at 0xFF10\n"
            "UART: TX=0xFC80 RX=0xFC82 STAT=0xFC84\n");
        return 1;
    }

    // 物理メモリ初期化
    memset(phys_mem, 0xFF, sizeof(phys_mem));

    load_bin(argv[1]);

    char extbuf[256];
    if (argc >= 3 && argv[2][0] != '-') load_dbg(argv[2]);
    else { change_ext(extbuf, sizeof(extbuf), argv[1], ".dbg"); load_dbg(extbuf); }
    if (argc >= 4 && argv[3][0] != '-') load_sym(argv[3]);
    else { change_ext(extbuf, sizeof(extbuf), argv[1], ".sym"); load_sym(extbuf); }

    // CPU 初期化
    memset(&cpu, 0, sizeof(cpu));
    cpu.sp          = 0xFFFE;
    cpu.irq_pending = -1;

    // MMU 初期化
    mmu_reset();

    // リセットベクタ (MMU無効状態なので logical=physical)
    cpu.pc          = rd16(0x0000);
    cpu.timer_cycle = 30000;

    // オプション解析
    for (int i = 2; i < argc; i++) {
        if (strcmp(argv[i], "-n") == 0 && i+1 < argc) run_steps  = atoi(argv[++i]);
        if (strcmp(argv[i], "-b") == 0 && i+1 < argc) trace_from = (int)strtol(argv[++i], NULL, 16);
        if (strcmp(argv[i], "-m") == 0 && i+2 < argc) {
            dump_addr = (int)strtol(argv[++i], NULL, 16);
            dump_len  = atoi(argv[++i]);
        }
    }

    if (run_steps > 0) {
        // ── バッチモード ────────────────────────────────────────────────────
        int tracing = (trace_from < 0);
        int traced  = 0;
        uint64_t total = 0;
        uint64_t max_total = (uint64_t)run_steps * (trace_from >= 0 ? 1000 : 1) + 10000000ULL;
        while (!cpu.halted && total++ < max_total) {
            if (!tracing && cpu.pc == (uint16_t)trace_from) tracing = 1;
            if (tracing) {
                printf("PC=%04X SP=%04X F=%02X A=%04X B=%04X X=%04X\n",
                       cpu.pc, cpu.sp, cpu.flags, cpu.a, cpu.b, cpu.x);
                if (++traced >= run_steps) break;
            }
            exec_one();
        }
        if (cpu.halted)
            printf("*** HALT at %04X ***\n", cpu.pc);
        else if (trace_from >= 0 && traced == 0)
            printf("--- addr %04X not reached in %llu steps ---\n",
                   trace_from, (unsigned long long)total);
        else
            printf("--- %d steps traced ---\n", traced);
        fflush(stdout);
        if (dump_addr >= 0) {
            printf("MEM[%04X+%d]:", dump_addr, dump_len);
            for (int i = 0; i < dump_len; i++)
                printf(" %04X", rd16((uint16_t)(dump_addr + i*2)));
            printf("\n");
        }
        return 0;
    }

    // ── インタラクティブモード ──────────────────────────────────────────────
    printf("YSD8800 ISA2.2 Emulator + MMU Extension  (emu22_mmu v1.0.0)\n");
    printf("  Physical memory : %d KB\n", PHYS_MEM_SIZE / 1024);
    printf("  MMU             : disabled (identity map, PTR[n]=n)\n");
    printf("  Reset vector    : %04x\n", cpu.pc);
    printf("Type 'help' for commands.\n\n");

    repl();
    return 0;
}
