// emu22.c - YSD8800 ISA2.2 Emulator
// Version: 1.10
// YSD8800 Forthカーネルプロジェクト
//
// ISA2.2 対応命令:
//   ビット演算: AND/ANDI/OR/ORI/XOR/XORI/NOT/SHL/SHR/SAR (0x50-0x59)
//
// v1.00: emu21.c ベース、ISA2.2命令追加
// v1.01: wr16() に UART_TX 書き込み対応を追加
//        （Force生成コードは STW で UART_TX に書き込むため）
// v1.02: -q (quiet) オプション追加 — UART出力のみ表示
// v1.10: --mmu オプション追加 — FM-11方式MMU拡張を統合（emu22_mmu を廃止）
//        物理メモリを最大1MB(--mmuオプション時)に拡張
//        MMUなし時は従来どおり64KBフラット動作
//        UART改善: STAT/RX を rd16() でも正しくトラップ
//
// MMU拡張 (--mmu 指定時, FM-11方式ページング):
//   ページサイズ  : 4KB
//   論理ページ数  : 16 (64KB / 4KB)
//   物理アドレス  : 20bit / 1MB (256物理ページ × 4KB)
//   MMU制御レジスタ (論理アドレス, メモリマップドI/O):
//     0xFF00-0xFF0F : PTR[0]-PTR[15]  論理→物理ページ番号 (各8bit)
//     0xFF10        : MCR  bit0=MMU_EN, bit1=KRN_PROT(将来)
//   アドレス変換 (MCR bit0=1 の時):
//     page   = logical >> 12
//     offset = logical & 0x0FFF
//     phys   = (PTR[page] << 12) | offset  (20bit)
//   MCR bit0=0 の時: 恒等写像 (phys = logical)
//   リセット時: PTR[n]=n, MCR=0
//
// I/Oアドレス (論理アドレス, MMU変換前に処理):
//   0xFC80 : UART TX  (write: 下位8bitを stdout へ出力, 8bit/16bit両対応)
//   0xFC82 : UART RX  (read: 0, 未実装)
//   0xFC84 : UART STAT (read: bit0=TX_READY=1, 8bit/16bit両対応)
//
// emu21.c から引き継いだ修正点:
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
// build: gcc -std=c99 -O2 -Wall -Wextra emu22.c -o emu22

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <ctype.h>

// ─── メモリサイズ ──────────────────────────────────────────────────────────────
#define MEM_SIZE       65536           // 通常モード: 64KB
#define PHYS_MEM_SIZE  (1024 * 1024)   // MMUモード: 1MB (20bit物理アドレス)
#define MAX_DBG        8192
#define MAX_BP         128
#define MAX_SYM        128

// ─── FLAGS bits ───────────────────────────────────────────────────────────────
#define FL_Z   0x01   // Zero
#define FL_N   0x02   // Negative
#define FL_IE  0x80   // Interrupt Enable

// ─── I/O アドレス (論理アドレス, MMU変換前に処理) ────────────────────────────
//
// YSD8001 UART コントローラ ($FC80〜$FC85)
//   $FC80 DATA : 書き=TX送信, 読み=RX受信（TX/RX兼用データレジスタ）
//   $FC82 CTRL : （将来拡張用：ボーレート設定等、現在は予約）
//   $FC84 STAT : bit0=TX_READY, bit1=RX_READY, bit2=RX_IRQ_EN
//
// IRQ 共用バス方式（MC6809系と同様のデバイス別STATポーリング）:
//   IRQ2番を外部デバイス共用バスとする。複数デバイスが同じIRQ2番を共用し、
//   ISRが各デバイスのSTATレジスタをポーリングして割り込み発生元を特定する。
//   新デバイス追加時はSTATにIRQ_ENビットを持たせるだけでよい。
//   FPGAでも各デバイスモジュールが独立したSTATを持つため拡張が容易。
//
// IRQ番号割り当て:
//   IRQ 0: リザーブ
//   IRQ 1: タイマー
//   IRQ 2: 外部デバイス共用バス (YSD8001 UART RX等)
//   IRQ 3: アライメント例外
//
#define YSD8001_BASE       0xFC80  // YSD8001 ベースアドレス
#define YSD8001_DATA       0xFC80  // DATAレジスタ (TX書き込み/RX読み出し兼用)
#define YSD8001_CTRL       0xFC82  // CTRLレジスタ (将来拡張用、現在予約)
#define YSD8001_STAT       0xFC84  // STATレジスタ
#define YSD8001_STAT_TX_READY  0x01  // bit0: TX送信可能
#define YSD8001_STAT_RX_READY  0x02  // bit1: RX受信データあり
#define YSD8001_STAT_RX_IRQ_EN 0x04  // bit2: RX割り込み許可
#define YSD8001_IRQ_NUM    2       // 外部デバイス共用バス IRQ番号
#define YSD8001_REG_END    0xFC86  // YSD8001レジスタ範囲終端

// 後方互換エイリアス
#define UART_TX   YSD8001_DATA
#define UART_STAT YSD8001_STAT

// ─── MMU レジスタアドレス (論理) ─────────────────────────────────────────────
#define MMU_PTR_BASE   0xFF00   // PTR[0]〜PTR[15]: 0xFF00〜0xFF0F
#define MMU_MCR_ADDR   0xFF10   // MMU Control Register
#define MCR_EN         0x01     // bit0: MMU Enable
#define MCR_KRN_PROT   0x02     // bit1: Kernel Protect (将来拡張)

// ─── ランタイムオプション ─────────────────────────────────────────────────────
static int quiet_mode = 0;   /* -q: UART出力のみ (PC=/プロンプト非表示) */
static int mmu_mode   = 0;   /* --mmu: MMU拡張を有効にする */

// ─── メモリ ───────────────────────────────────────────────────────────────────
static uint8_t  mem[MEM_SIZE];    /* 通常モード用 (64KB) */
static uint8_t *phys_mem = NULL;  /* --mmu時に malloc で確保 (1MB) */

// ─── MMU 状態 ─────────────────────────────────────────────────────────────────
typedef struct {
    uint8_t ptr[16];  /* Page Table Registers */
    uint8_t mcr;      /* MMU Control Register */
} mmu_t;

static mmu_t mmu;

// ─── MMU: アドレス変換 ────────────────────────────────────────────────────────
static uint32_t mmu_translate(uint16_t logical) {
    if (mmu.mcr & MCR_EN) {
        uint8_t  page   = (uint8_t)(logical >> 12);
        uint16_t offset = logical & 0x0FFF;
        return ((uint32_t)mmu.ptr[page] << 12) | offset;
    }
    return (uint32_t)logical;
}

// ─── MMU: リセット初期化 (恒等写像, MMU無効) ──────────────────────────────────
static void mmu_reset(void) {
    for (int i = 0; i < 16; i++) mmu.ptr[i] = (uint8_t)i;
    mmu.mcr = 0;
}

// ================= YSD8001 UART ===========
//
// YSD8001はYSD8800システム向けUARTコントローラIC。
// emu22では関数として分離し、将来の専用デバイスICサポートへの
// 予備実装とする。FPGA実装時は同一レジスタマップを持つ
// SystemVerilogモジュール ysd8001.sv として実装予定。
//
// RXバッファ: 1バイト（rx_data + RX_READY フラグ）
//   将来は rx_buf[N] の循環バッファへ拡張可能な設計とする。
//   拡張時は rx_data を uint8_t rx_buf[N] と
//   rx_head/rx_tail インデックスに置き換えるだけでよい。
//
// RX入力ソース（exec_one()毎に ysd8001_poll_rx() で取得）:
//   -i file 指定時 : ファイルから1文字ずつ供給
//                    ファイル末尾到達で RX_READY=0 に戻る
//   -i なし時      : stdin を非ブロッキングポーリング
//                    データなければ即座に RX_READY=0 を返す
//
#include <fcntl.h>   // fcntl, O_NONBLOCK (非ブロッキングstdin用)
#include <unistd.h>  // STDIN_FILENO

typedef struct {
    uint8_t  stat;      // STATレジスタ (TX_READY | RX_READY | RX_IRQ_EN)
    uint8_t  rx_data;   // RX受信データ（1バイトバッファ）
    FILE    *rx_src;    // RX入力ソース (NULL=stdin, non-NULL=-iで指定したファイル)
    int      rx_stdin_nb; // 1=stdinを非ブロッキング設定済み
    // 将来拡張: uint8_t rx_buf[N]; int rx_head, rx_tail;
} ysd8001_t;

static ysd8001_t ysd8001;

// YSD8001 初期化
static void ysd8001_reset(void) {
    ysd8001.stat        = YSD8001_STAT_TX_READY;  // TX常時Ready、RX未受信
    ysd8001.rx_data     = 0x00;
    // rx_src は main()のオプション解析で設定済みの場合があるので上書きしない
    // （未設定の場合のみ NULL = stdin ポーリングモードに初期化）
    if (ysd8001.rx_src == NULL)
        ysd8001.rx_stdin_nb = 0;  // stdin非ブロッキング未設定
}

// YSD8001 STATレジスタ読み出し
static uint8_t ysd8001_read_stat(void) {
    return ysd8001.stat;
}

// YSD8001 DATAレジスタ読み出し（RX受信データ取得）
// 読み出し後 RX_READY をクリア（1バイトバッファ消費）
static uint8_t ysd8001_read_data(void) {
    uint8_t v = ysd8001.rx_data;
    ysd8001.stat &= (uint8_t)~YSD8001_STAT_RX_READY;  // RX_READY クリア
    return v;
}

// YSD8001 DATAレジスタ書き込み（TX送信）
// エミュレータでは stdout への putchar として実装
static void ysd8001_write_data(uint8_t v) {
    putchar((int)v);
    fflush(stdout);
    // TX_READY は常時セット（エミュレータでは送信遅延なし）
}

// YSD8001 STATレジスタ書き込み（RX_IRQ_EN等の設定）
// TX_READY/RX_READY は読み取り専用ビットなので書き込み無効
static void ysd8001_write_stat(uint8_t v) {
    // RX_IRQ_EN (bit2) のみ書き込み可能
    uint8_t ro_bits = YSD8001_STAT_TX_READY | YSD8001_STAT_RX_READY;
    ysd8001.stat = (ysd8001.stat & ro_bits) | ((uint8_t)v & (uint8_t)~ro_bits);
}

// YSD8001 RXデータ受信（1バイトをバッファに積む）
// RX_IRQ_EN=1 なら IRQ2 を発生させる
// ※ cpu_t 定義後に実装（前方宣言）
static void ysd8001_rx_receive(uint8_t v);

// YSD8001 RXポーリング（exec_one()から毎サイクル呼び出す）
// RX_READY=0（バッファ空）の時のみ次の1バイトを取得しようとする
// ポーリング頻度を抑えるため一定サイクル間隔で実行する
static void ysd8001_poll_rx(void) {
    // バッファに既にデータがあれば何もしない
    if (ysd8001.stat & YSD8001_STAT_RX_READY) return;

    int c = EOF;

    if (ysd8001.rx_src != NULL) {
        // ─── ファイル入力モード ───────────────────────────────
        c = fgetc(ysd8001.rx_src);
        // ファイル末尾到達時は rx_src を閉じてNULLに戻す（以降はstdinへ）
        if (c == EOF) {
            fclose(ysd8001.rx_src);
            ysd8001.rx_src = NULL;
        }
    } else {
        // ─── stdin 非ブロッキングポーリングモード ───────────────
        // 初回のみ stdin を非ブロッキングに設定
        if (!ysd8001.rx_stdin_nb) {
            int flags = fcntl(STDIN_FILENO, F_GETFL, 0);
            if (flags >= 0)
                fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK);
            ysd8001.rx_stdin_nb = 1;
        }
        c = getchar();
        // EAGAIN (データなし) の場合は EOF と同様に無視
    }

    if (c != EOF) {
        ysd8001_rx_receive((uint8_t)c);
    }
}

// YSD8001 I/Oアドレストラップ判定
// la がYSD8001のレジスタ範囲($FC80〜$FC83)かどうか返す
static inline int ysd8001_is_addr(uint16_t la) {
    return (la >= YSD8001_BASE && la < YSD8001_REG_END);
}

// YSD8001 8bit読み出しハンドラ
static uint8_t ysd8001_rd8(uint16_t la) {
    if (la == YSD8001_DATA) return ysd8001_read_data();
    if (la == YSD8001_CTRL) return 0x00;               // CTRL: 将来拡張用、現在0を返す
    if (la == YSD8001_STAT) return ysd8001_read_stat();
    return 0xFF;  // 未定義レジスタ
}

// YSD8001 8bit書き込みハンドラ
static void ysd8001_wr8(uint16_t la, uint8_t v) {
    if (la == YSD8001_DATA) { ysd8001_write_data(v); return; }
    if (la == YSD8001_CTRL) { return; }                // CTRL: 将来拡張用、現在は無視
    if (la == YSD8001_STAT) { ysd8001_write_stat(v); return; }
}

// YSD8001 16bit読み出しハンドラ
// STW A,[UART_TX] との互換性：DATAへの16bitアクセスは下位バイトのみ有効
static uint16_t ysd8001_rd16(uint16_t la) {
    if (la == YSD8001_DATA) return (uint16_t)ysd8001_read_data();
    if (la == YSD8001_CTRL) return 0x0000;
    if (la == YSD8001_STAT) return (uint16_t)ysd8001_read_stat();
    return 0xFFFF;
}

// YSD8001 16bit書き込みハンドラ
// STW A,[UART_TX] の場合: 下位バイト(A & 0xFF)のみ送信
static void ysd8001_wr16(uint16_t la, uint16_t v) {
    if (la == YSD8001_DATA) { ysd8001_write_data((uint8_t)(v & 0xFF)); return; }
    if (la == YSD8001_CTRL) { return; }
    if (la == YSD8001_STAT) { ysd8001_write_stat((uint8_t)(v & 0xFF)); return; }
}

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

// YSD8001 RXデータ受信の実装 (cpu_t定義後に配置)
static void ysd8001_rx_receive(uint8_t v) {
    ysd8001.rx_data = v;
    ysd8001.stat   |= YSD8001_STAT_RX_READY;
    // RX割り込み許可中であれば外部デバイス共用IRQ(IRQ2)を発生
    if (ysd8001.stat & YSD8001_STAT_RX_IRQ_EN) {
        cpu.irq_pending = YSD8001_IRQ_NUM;
    }
}

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
//
// I/O 処理の優先順位 (論理アドレス):
//   1. UART  (0xFC80-0xFC84)       — MMU変換なし
//   2. MMUレジスタ (0xFF00-0xFF10) — MMU変換なし (--mmuモード時のみ)
//   3. 通常メモリ                  — MMU変換あり (--mmuモード時)
//
// [FIX BUG-2] rd16: early return on alignment fault; wrap at 0xFFFF

// ─── 物理メモリへの生アクセス (MMU変換済みアドレスで呼ぶ) ─────────────────────
static inline uint8_t phys_rd8(uint32_t pa) {
    if (mmu_mode) return phys_mem[pa & 0xFFFFF];
    return mem[(uint16_t)pa];
}
static inline void phys_wr8(uint32_t pa, uint8_t v) {
    if (mmu_mode) phys_mem[pa & 0xFFFFF] = v;
    else          mem[(uint16_t)pa] = v;
}

// ─── 8bit アクセス ────────────────────────────────────────────────────────────
uint8_t rd8(uint16_t la) {
    // YSD8001 トラップ (MMU変換前)
    if (ysd8001_is_addr(la)) return ysd8001_rd8(la);
    // MMUレジスタ読み出し (--mmuモード時)
    if (mmu_mode) {
        if (la >= MMU_PTR_BASE && la < (MMU_PTR_BASE + 16))
            return mmu.ptr[la - MMU_PTR_BASE];
        if (la == MMU_MCR_ADDR)
            return mmu.mcr;
    }
    return phys_rd8(mmu_translate(la));
}

void wr8(uint16_t la, uint8_t v) {
    // YSD8001 トラップ (MMU変換前)
    if (ysd8001_is_addr(la)) { ysd8001_wr8(la, v); return; }
    // MMUレジスタ書き込み (--mmuモード時)
    if (mmu_mode) {
        if (la >= MMU_PTR_BASE && la < (MMU_PTR_BASE + 16)) {
            mmu.ptr[la - MMU_PTR_BASE] = v;
            return;
        }
        if (la == MMU_MCR_ADDR) { mmu.mcr = v; return; }
    }
    phys_wr8(mmu_translate(la), v);
}

// ─── 16bit アクセス ───────────────────────────────────────────────────────────
// [FIX BUG-2] rd16: early return on alignment fault
uint16_t rd16(uint16_t la) {
    if (la & 1) {
        printf("!! ALIGNMENT EXCEPTION (READ) @%04x\n", la);
        cpu.irq_pending = 3;
        return 0;
    }
    // YSD8001 トラップ (MMU変換前)
    if (ysd8001_is_addr(la)) return ysd8001_rd16(la);
    // MMUレジスタ読み出し (--mmuモード時, 16bitアクセスは想定外だが安全に処理)
    if (mmu_mode && la >= MMU_PTR_BASE && la <= MMU_MCR_ADDR) {
        return (uint16_t)rd8(la) | ((uint16_t)rd8((uint16_t)(la + 1)) << 8);
    }
    // 通常メモリ: ページ境界またぎに対応（各バイト独立に変換）
    uint8_t lo = phys_rd8(mmu_translate(la));
    uint8_t hi = phys_rd8(mmu_translate((uint16_t)(la + 1)));
    return (uint16_t)(lo | ((uint16_t)hi << 8));
}

void wr16(uint16_t la, uint16_t v) {
    if (la & 1) {
        printf("!! ALIGNMENT EXCEPTION (WRITE) @%04x\n", la);
        cpu.irq_pending = 3;
        return;
    }
    // YSD8001 トラップ (MMU変換前)
    if (ysd8001_is_addr(la)) { ysd8001_wr16(la, v); return; }
    // MMUレジスタ書き込み (--mmuモード時)
    if (mmu_mode && la >= MMU_PTR_BASE && la <= MMU_MCR_ADDR) {
        wr8(la,              (uint8_t)(v & 0xFF));
        wr8((uint16_t)(la+1),(uint8_t)(v >> 8));
        return;
    }
    // 通常メモリ: ページ境界またぎに対応
    phys_wr8(mmu_translate(la),              (uint8_t)(v & 0xFF));
    phys_wr8(mmu_translate((uint16_t)(la+1)),(uint8_t)(v >> 8));
}

// ─── 命令フェッチ用アクセス (MMU変換対応) ────────────────────────────────────
static inline uint8_t fetch8(uint16_t a) {
    return phys_rd8(mmu_translate(a));
}

// [FIX BUG-3] fetch16: wrap address at 0xFFFF boundary / MMU変換対応
static uint16_t fetch16(uint16_t a) {
    uint8_t lo = fetch8(a);
    uint8_t hi = fetch8((uint16_t)(a + 1));
    return (uint16_t)(lo | ((uint16_t)hi << 8));
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
    if (mmu_mode) {
        /* --mmuモード: phys_mem の先頭（物理$0000）にロード */
        size_t got = fread(phys_mem, 1, PHYS_MEM_SIZE, f);
        if (got == 0) { fprintf(stderr, "%s: empty or read error\n", fn); exit(1); }
        fclose(f);
        if (!quiet_mode)
            printf("Loaded %u bytes from %s (phys 0x%05x)\n", (unsigned)got, fn, 0);
    } else {
        /* 通常モード: mem[64KB] にロード */
        size_t got = fread(mem, 1, MEM_SIZE, f);
        if (got == 0) { fprintf(stderr, "%s: empty or read error\n", fn); exit(1); }
        fclose(f);
        if (!quiet_mode) printf("Loaded %u bytes from %s\n", (unsigned)got, fn);
    }
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
        uint8_t  op  = fetch8(pc);
        int      sz  = instr_size(pc);

        // hex bytes
        printf("%04x: ", pc);
        for (int j = 0; j < sz && j < 5; j++)
            printf("%02x ", fetch8((uint16_t)(pc + j)));
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

    // YSD8001 RXポーリング（256サイクルに1回チェック、オーバーヘッド最小化）
    if ((cpu.cycle & 0xFF) == 0) ysd8001_poll_rx();

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
    cpu.ir = fetch8(cpu.pc++);
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
        // irq_pendingもクリア: IRET前に蓄積したタイマーIRQを捨てる
        if (cpu.irq_pending == 1) cpu.irq_pending = -1;  // タイマーIRQのみクリア
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
        uint8_t sub = fetch8(cpu.pc++);
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
        uint8_t rb = fetch8(cpu.pc++);
        uint16_t *rd = get_reg_ptr(rb >> 4);
        uint16_t *rs = get_reg_ptr(rb & 0x0F);
        if (rd && rs) *rd = *rs;
        break;
    }
    case 0x21: { /* LDW rD, #imm16 */
        uint8_t rb = fetch8(cpu.pc++);
        uint16_t imm = fetch16(cpu.pc); cpu.pc += 2;
        uint16_t *rd = get_reg_ptr(rb >> 4);
        if (rd) { *rd = imm; set_zn(*rd); }
        break;
    }
    case 0x22: { /* LDW rD, [imm16] */
        uint8_t rb = fetch8(cpu.pc++);
        uint16_t imm = fetch16(cpu.pc); cpu.pc += 2;
        uint16_t *rd = get_reg_ptr(rb >> 4);
        if (rd) { *rd = rd16(imm); set_zn(*rd); }
        break;
    }
    case 0x23: { /* STW rS, [imm16] */
        uint8_t rb = fetch8(cpu.pc++);
        uint16_t imm = fetch16(cpu.pc); cpu.pc += 2;
        uint16_t *rs = get_reg_ptr(rb & 0x0F);
        if (rs) wr16(imm, *rs);
        break;
    }
    case 0x24: { /* LDW rD, [rS] */
        uint8_t rb = fetch8(cpu.pc++);
        uint16_t *rd = get_reg_ptr(rb >> 4);
        uint16_t *rs = get_reg_ptr(rb & 0x0F);
        if (rd && rs) { *rd = rd16(*rs); set_zn(*rd); }
        break;
    }
    case 0x25: { /* STW rS, [rD]  — rD=アドレス rS=データ */
        uint8_t rb = fetch8(cpu.pc++);
        uint16_t *rd = get_reg_ptr(rb >> 4);
        uint16_t *rs = get_reg_ptr(rb & 0x0F);
        if (rd && rs) wr16(*rd, *rs);
        break;
    }
    case 0x26: { /* LDW rD, [X + imm16] */
        uint8_t rb = fetch8(cpu.pc++);
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
        uint8_t rb = fetch8(cpu.pc++);
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
        uint8_t rb = fetch8(cpu.pc++);
        uint16_t *rd = get_reg_ptr(rb >> 4);
        uint16_t *rs = get_reg_ptr(rb & 0x0F);
        if (rd && rs) { *rd += *rs; set_zn(*rd); }
        break;
    }
    case 0x41: { /* ADDI rD, #imm16 */
        uint8_t rb = fetch8(cpu.pc++);
        uint16_t imm = fetch16(cpu.pc); cpu.pc += 2;
        uint16_t *rd = get_reg_ptr(rb >> 4);
        if (rd) { *rd += imm; set_zn(*rd); }
        break;
    }
    case 0x42: { /* SUB rD, rS */
        uint8_t rb = fetch8(cpu.pc++);
        uint16_t *rd = get_reg_ptr(rb >> 4);
        uint16_t *rs = get_reg_ptr(rb & 0x0F);
        if (rd && rs) { *rd -= *rs; set_zn(*rd); }
        break;
    }
    case 0x43: { /* SUBI rD, #imm16 */
        uint8_t rb = fetch8(cpu.pc++);
        uint16_t imm = fetch16(cpu.pc); cpu.pc += 2;
        uint16_t *rd = get_reg_ptr(rb >> 4);
        if (rd) { *rd -= imm; set_zn(*rd); }
        break;
    }
    case 0x44: { /* CMP rD, rS  — FLAGS のみ変化 */
        uint8_t rb = fetch8(cpu.pc++);
        uint16_t *rd = get_reg_ptr(rb >> 4);
        uint16_t *rs = get_reg_ptr(rb & 0x0F);
        if (rd && rs) set_zn((uint16_t)(*rd - *rs));
        break;
    }
    case 0x45: { /* CMPI rD, #imm16  — FLAGS のみ変化 */
        uint8_t rb = fetch8(cpu.pc++);
        uint16_t imm = fetch16(cpu.pc); cpu.pc += 2;
        uint16_t *rd = get_reg_ptr(rb >> 4);
        if (rd) set_zn((uint16_t)(*rd - imm));
        break;
    }

    // ---- ISA2.2 Bit operations (0x50-0x59) ----

    case 0x50: { /* AND rD, rS */
        uint8_t rb = fetch8(cpu.pc++);
        uint16_t *rd = get_reg_ptr(rb >> 4);
        uint16_t *rs = get_reg_ptr(rb & 0x0F);
        if (rd && rs) { *rd &= *rs; set_zn(*rd); }
        break;
    }
    case 0x51: { /* ANDI rD, #imm16 */
        uint8_t rb = fetch8(cpu.pc++);
        uint16_t imm = fetch16(cpu.pc); cpu.pc += 2;
        uint16_t *rd = get_reg_ptr(rb >> 4);
        if (rd) { *rd &= imm; set_zn(*rd); }
        break;
    }
    case 0x52: { /* OR rD, rS */
        uint8_t rb = fetch8(cpu.pc++);
        uint16_t *rd = get_reg_ptr(rb >> 4);
        uint16_t *rs = get_reg_ptr(rb & 0x0F);
        if (rd && rs) { *rd |= *rs; set_zn(*rd); }
        break;
    }
    case 0x53: { /* ORI rD, #imm16 */
        uint8_t rb = fetch8(cpu.pc++);
        uint16_t imm = fetch16(cpu.pc); cpu.pc += 2;
        uint16_t *rd = get_reg_ptr(rb >> 4);
        if (rd) { *rd |= imm; set_zn(*rd); }
        break;
    }
    case 0x54: { /* XOR rD, rS */
        uint8_t rb = fetch8(cpu.pc++);
        uint16_t *rd = get_reg_ptr(rb >> 4);
        uint16_t *rs = get_reg_ptr(rb & 0x0F);
        if (rd && rs) { *rd ^= *rs; set_zn(*rd); }
        break;
    }
    case 0x55: { /* XORI rD, #imm16 */
        uint8_t rb = fetch8(cpu.pc++);
        uint16_t imm = fetch16(cpu.pc); cpu.pc += 2;
        uint16_t *rd = get_reg_ptr(rb >> 4);
        if (rd) { *rd ^= imm; set_zn(*rd); }
        break;
    }
    case 0x56: { /* NOT rD  — ビット反転 */
        uint8_t rb = fetch8(cpu.pc++);
        uint16_t *rd = get_reg_ptr(rb >> 4);
        if (rd) { *rd = (uint16_t)(~(*rd)); set_zn(*rd); }
        break;
    }
    case 0x57: { /* SHL rD, rS  — 論理左シフト */
        uint8_t rb = fetch8(cpu.pc++);
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
        uint8_t rb = fetch8(cpu.pc++);
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
        uint8_t rb = fetch8(cpu.pc++);
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
        if (!quiet_mode)
            printf("Unknown opcode %02x at %04x\n", cpu.ir, pc0);
        cpu.halted = 1;  /* 不明命令でHALT */
        cpu.halted = 1;
        break;
    }

    // HALT 直後の状態表示
    if (cpu.halted) {
        if (!quiet_mode) {
            printf("*** HALT at %04x ***\n", pc0);
            dump_regs();
        }
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

        printf(mmu_mode ? "(emu22+mmu) " : "(emu22) ");
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
        } else if (strncmp(cmd, "mmu", 3) == 0 && mmu_mode) {
            // mmu          : MMU状態ダンプ
            // mmu en       : MMU有効化
            // mmu dis      : MMU無効化
            // mmu ptr N V  : PTR[N] に物理ページ番号V(hex)をセット
            char sub[32] = "";
            sscanf(cmd + 3, " %31s", sub);
            if (sub[0] == '\0') {
                // 状態ダンプ
                printf("MCR=%02X  MMU %s\n", mmu.mcr,
                       (mmu.mcr & MCR_EN) ? "ENABLED" : "disabled");
                for (int i = 0; i < 16; i++) {
                    printf("  PTR[%2d] = %02X  (log $%04X -> phys $%05X)\n",
                           i, mmu.ptr[i],
                           i << 12,
                           (uint32_t)mmu.ptr[i] << 12);
                }
            } else if (strcmp(sub, "en") == 0) {
                mmu.mcr |= MCR_EN; printf("MMU ENABLED\n");
            } else if (strcmp(sub, "dis") == 0) {
                mmu.mcr &= (uint8_t)~MCR_EN; printf("MMU disabled\n");
            } else if (strcmp(sub, "ptr") == 0) {
                int n, v;
                if (sscanf(cmd + 3, " ptr %d %x", &n, &v) == 2 &&
                    n >= 0 && n < 16 && v >= 0 && v < 256) {
                    mmu.ptr[n] = (uint8_t)v;
                    printf("PTR[%d] = %02X\n", n, v);
                } else printf("Usage: mmu ptr <0-15> <physpage_hex>\n");
            } else {
                printf("mmu | mmu en | mmu dis | mmu ptr N V\n");
            }
        } else if (strncmp(cmd, "physmem", 7) == 0 && mmu_mode) {
            // physmem <physaddr_hex> [n]  : 物理メモリ直接ダンプ
            uint32_t pa = 0; int n = 16;
            sscanf(cmd + 7, " %x %d", &pa, &n);
            pa &= 0xFFFFF;
            printf("PHYSMEM[%05X+%d]:", pa, n);
            for (int i = 0; i < n; i++)
                printf(" %02X", phys_mem[(pa + (uint32_t)i) & 0xFFFFF]);
            printf("\n");
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
                "  mem  [a [n]]   dump n bytes from a (logical addr)\n"
                "  memw [a [n]]   dump n words from a (logical addr)\n"
                "  irq <id>       inject IRQ\n"
                "  reset          reset CPU (memory unchanged)\n"
                "  q              quit\n"
            );
            if (mmu_mode) printf(
                "MMU commands (--mmu mode):\n"
                "  mmu              dump MMU state (PTR/MCR)\n"
                "  mmu en           enable MMU (MCR bit0=1)\n"
                "  mmu dis          disable MMU (MCR bit0=0)\n"
                "  mmu ptr N V      set PTR[N]=V (hex physpage)\n"
                "  physmem A [n]    dump n bytes from physical addr A (hex)\n"
            );
        }
        // unknown command: silently ignore (user may have pressed Enter)
    }
}

// ================= Main ================

int main(int argc, char **argv) {
    int run_steps  = 0;   /* -n N: Nステップ実行してPCトレースを出力して終了 */
    int trace_from = -1;  /* -b ADDR: このアドレス到達後にトレース開始 */
    int dump_addr  = -1;  /* -m ADDR N: N命令実行後にADDRからNワードをダンプ */
    int dump_len   = 0;

    if (argc < 2) {
        fprintf(stderr,
            "usage: emu22 prog.bin [prog.dbg [prog.sym]] [options]\n"
            "options:\n"
            "  --mmu        enable MMU (FM-11 style paging, 1MB physical)\n"
            "  -q           quiet: run until HALT, show UART output only\n"
            "  -i FILE      UART RX input file (fed to emulated UART RX byte by byte)\n"
            "               if omitted, stdin is polled non-blocking\n"
            "  -n N         run N steps and dump trace (non-interactive)\n"
            "  -b ADDR      start tracing after reaching ADDR (hex)\n"
            "  -m ADDR N    after trace, dump N words from ADDR (hex)\n"
            "  prog.dbg / prog.sym are auto-derived from prog.bin if omitted\n"
            "\n"
            "MMU: FM-11 style 4KB paging, 16 logical pages -> 1MB physical\n"
            "     PTR[0..15] at $FF00..$FF0F  MCR at $FF10\n"
            "UART (YSD8001): DATA=$FC80 CTRL=$FC82(rsv) STAT=$FC84  RX-IRQ=IRQ2\n");
        return 1;
    }

    /* オプションを先にスキャン (load_bin前に mmu_mode/quiet_mode が必要) */
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--mmu") == 0) mmu_mode   = 1;
        if (strcmp(argv[i], "-q")    == 0) quiet_mode = 1;
        if (strcmp(argv[i], "-i") == 0 && i+1 < argc) {
            /* -i file: RX入力ファイルを開く（ysd8001_reset()前に設定） */
            FILE *f = fopen(argv[i+1], "rb");
            if (!f) { fprintf(stderr, "emu22: cannot open -i file: %s\n", argv[i+1]); return 1; }
            ysd8001.rx_src = f;  /* ysd8001_reset()より前に設定 */
        }
    }

    /* --mmuモード: phys_memをmallocで確保し0xFFで初期化 */
    if (mmu_mode) {
        phys_mem = (uint8_t *)malloc(PHYS_MEM_SIZE);
        if (!phys_mem) { fprintf(stderr, "malloc failed for phys_mem\n"); return 1; }
        memset(phys_mem, 0xFF, PHYS_MEM_SIZE);
    }

    load_bin(argv[1]);

    /* dbg/sym ファイル: argv[2]/[3] が '-' 始まりでなければファイル名として扱う */
    char extbuf[256];
    if (argc >= 3 && argv[2][0] != '-') load_dbg(argv[2]);
    else { change_ext(extbuf, sizeof(extbuf), argv[1], ".dbg"); load_dbg(extbuf); }
    if (argc >= 4 && argv[3][0] != '-') load_sym(argv[3]);
    else { change_ext(extbuf, sizeof(extbuf), argv[1], ".sym"); load_sym(extbuf); }

    /* CPU初期化 */
    memset(&cpu, 0, sizeof(cpu));
    cpu.sp          = 0xFFFE;
    cpu.irq_pending = -1;
    cpu.timer_cycle = 30000;

    /* MMU初期化 (--mmuモード時, 恒等写像・MMU無効) */
    mmu_reset();

    /* YSD8001 UART初期化 */
    ysd8001_reset();

    /* リセットベクタ読み出し (MMU無効状態なので logical=physical) */
    cpu.pc = rd16(0x0000);

    /* 全オプション解析 */
    for (int i = 2; i < argc; i++) {
        if (strcmp(argv[i], "-n") == 0 && i+1 < argc)
            run_steps  = atoi(argv[++i]);
        else if (strcmp(argv[i], "-b") == 0 && i+1 < argc)
            trace_from = (int)strtol(argv[++i], NULL, 16);
        else if (strcmp(argv[i], "-q") == 0)
            quiet_mode = 1;
        else if (strcmp(argv[i], "--mmu") == 0)
            ; /* 処理済み */
        else if (strcmp(argv[i], "-i") == 0 && i+1 < argc)
            i++;  /* 処理済み（先行スキャン済み）、引数をスキップ */
        else if (strcmp(argv[i], "-m") == 0 && i+2 < argc) {
            dump_addr = (int)strtol(argv[++i], NULL, 16);
            dump_len  = atoi(argv[++i]);
        }
    }

    /* -q モード: HALTまで実行してUART出力のみ表示 */
    if (quiet_mode && run_steps == 0) {
        while (!cpu.halted)
            exec_one();
        return 0;
    }

    if (run_steps > 0) {
        /* バッチモード */
        int tracing = (trace_from < 0);
        int traced   = 0;
        uint64_t total = 0;
        uint64_t max_total = (uint64_t)run_steps * (trace_from >= 0 ? 1000 : 1) + 10000000ULL;
        while (!cpu.halted && total++ < max_total) {
            if (!tracing && cpu.pc == (uint16_t)trace_from)
                tracing = 1;
            if (tracing) {
                printf("PC=%04X SP=%04X F=%02X A=%04X B=%04X X=%04X\n",
                       cpu.pc, cpu.sp, cpu.flags, cpu.a, cpu.b, cpu.x);
                if (++traced >= run_steps) break;
            }
            exec_one();
        }
        if (cpu.halted)
            printf("*** HALT at %04X ***\n", cpu.pc - 1);
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

    /* インタラクティブモード: バナー表示 */
    printf("YSD8800 ISA2.2 Emulator  (emu22 v1.10");
    if (mmu_mode) printf(" + MMU");
    printf(")\n");
    if (mmu_mode) {
        printf("  Physical memory : %d KB\n", PHYS_MEM_SIZE / 1024);
        printf("  MMU             : disabled (identity map, PTR[n]=n)\n");
    }
    printf("  Reset vector    : %04x\n", cpu.pc);
    printf("Type 'help' for commands.\n\n");

    repl();

    if (mmu_mode && phys_mem) free(phys_mem);
    return 0;
}
