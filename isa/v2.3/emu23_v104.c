// emu23.c - YSD8800 ISA2.3 Emulator
// Version: 1.04 (2026-05-18)
// v1.04からの変更 [Ph.3.5 デバッグ残骸除去]:
//   - exec_one() 内の $E000-$E100 突入検出デバッグ printf を削除
//     （-q モード時も stdout に [DBG] が混入していた問題を解消）
//
// ISA2.3変更点 (ISA2.2からの差分):
//   SYSCALL: 3バイト(opcode+imm16) → 1バイト(opcodeのみ)
//   システムコール番号はAレジスタで渡す（案B: 常にIRQ4発火）
//
// v1.03からの変更 [Ph.3-B ストレージドライバ対応]:
//   [YSD8003] EXEC 完了 IRQ の遅延化（512cycle後発火）
//             - sd_irq_delay 変数追加、メインループでデクリメント
//             - SD_CMD=2 (EXEC) 受理時に sd_irq_delay = 512 で予約
//             - 0到達時に ysd8004_raise(IRQ_STAT_BIT_STOR)
//   [YSD8004] ysd8004_raise() IRQ pending 上書き保護（既知課題K1暫定対処）
//             - 高優先IRQ（IRQ0=タイマー, IRQ3=アラインメント）を蹴落とさない
//             - IRQ_STAT bit保持→IRET後の再評価機構で再pending化
//   [メインループ] IRQ_STAT 再評価機構追加
//             - 毎命令: irq_pending<0 && irq_stat!=0 なら IRQ1 を再pending
//   設計書: emu23_v103_design_v1_4.docx, yuios_ph3_storage_design_v1_2.docx
//
// v1.02からの変更:
//   [YSD8001] UART モジュール化（ysd8001_t 構造体 + ysd8001_xxx() 関数群）
//   [YSD8001] TX タイミングモデル: 4167cycle/byte (9600bps@4MHz)
//   [YSD8001] RX 割り込み (YSD8004 経由 IRQ1 bit0)
//   [YSD8001] TX 割り込み (TDRE方式、YSD8004 経由 IRQ1 bit2)
//   [YSD8001] UART_STAT Write-to-Clear (bit1 RX_READY のみ対象)
//   [YSD8001] UART_BAUD ($FC86) 予約定義（読み書き可、動作影響なし）
//   [YSD8001] -i FILE オプション復活（emu22 v1.10 から再移植）
//   [YSD8001] stdin 非ブロッキングポーリング (-i 未指定時)
//   設計書: ysd8001_uart_design_v1_1.docx, emu23_v102_design_v1_2.docx
//   既知の課題: §7.4 IRQ 優先制御（v1.01 から継承、別工程で対応予定）
//
// v1.01からの変更:
//   [YSD8002] MMIO化: $FC90-$FC9E レジスタ追加（TCR/PERIOD/CYCLE/SW_RUNS/SCORE）
//   [YSD8002] SYSCALL 0x0010/0x0011 のif/else chain削除 → IRQ4発火のみ
//   [YSD8002] IRET処理: PERIOD設定値で次回発火計算
//   [YSD8003] ストレージ実装: $FCA0-$FCB0（SD_CMD/SD_STAT/LBA/BUF_PTR/DATA/IRQ_CTRL/DISK）
//   [YSD8003] BUSYラッチ方式・fread/fwrite即時実行
//   [YSD8003] --disk <imagefile> オプション追加
//   [YSD8004] 割り込みコントローラ: $FCB2-$FCB4（IRQ_STAT Write-to-Clear/IRQ_MASK）
//   [YSD8004] ysd8004_raise() 関数追加
//   設計書: emu23_device_design_v1_2.docx
//
// v1.00からの継承:
//   [ISA2.3] SYSCALL: imm16フェッチ削除・Aレジスタディスパッチ・常時IRQ4発火
//   [YSD8002] ysd8002_t 構造体・init/tick/iret/report
//   [YSD8001] UART TX/RX/STAT ($FC80-$FC84)
//
// emu22 v1.23からの継承変更点:
//   v1.23: ウォッチポイント全削除（Step 8-C完了クリーン版）
//   v1.22: -q オプション復活
//   v1.21: スタック初期値 $FC7E
//   v1.20: YSD8001 UART サポート、MMU 対応
//
// build: gcc -std=c99 -O2 -Wall -Wno-unused-function emu23.c -o emu23

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <ctype.h>
#include <fcntl.h>    /* [v1.02] O_NONBLOCK for stdin polling */
#include <unistd.h>   /* [v1.02] STDIN_FILENO, read() */

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
    uint8_t  flags;
    uint8_t  ir;
    int      irq_pending;
    int      halted;
    uint64_t cycle;
    /* timer_cycle 削除: ysd8002_t に移管 */
} cpu_t;

cpu_t cpu;

// ================= YSD8002 タイマー抽象化 =================
// YSD8002: YSD8800用タイマーチップ（仮想デバイス）
// 設計書: ysd8002_timer_design_v1_0.docx / toolchain23_design_v1_1.docx

typedef struct {
    uint64_t cpu_freq_hz;      /* 動作クロック [Hz]  デフォルト: 4,000,000 */
    uint64_t irq_hz;           /* タイマーIRQ周波数  デフォルト: 100       */
    uint64_t cycles_per_irq;   /* = cpu_freq_hz / irq_hz (PERIODから設定) */
    uint64_t next_irq_cycle;   /* 次回IRQ発火サイクル値                    */
    int      irq_enabled;      /* タイマーIRQ有効フラグ (1=有効)           */
    /* MMIO レジスタ: $FC90-$FC9E */
    uint8_t  tcr;              /* TCR $FC90: bit0=TIMER_EN bit1=IRQ_EN      */
    uint32_t period;           /* PERIOD $FC92/$FC94 (32bit: HI<<16|LO)    */
    uint16_t sw_runs;          /* SW_RUNS $FC9A: Number_Of_Runs設定         */
    uint64_t score;            /* SCORE $FC9C/$FC9E: 経過サイクル数         */
    uint64_t sw_start_cycle;   /* SW_STARTトリガ発行時のサイクル値         */
    int      sw_busy;          /* SW_BUSY: 計測中フラグ (TCR bit4 R)       */
    uint64_t cycle_hi_latch;   /* CYCLE_HIラッチ (CYCLE_LO $FC96読み出し時) */
    uint64_t score_hi_latch;   /* SCORE_HIラッチ (SCORE_LO $FC9C読み出し時) */
} ysd8002_t;

static ysd8002_t ysd8002;

static void YSD8002_init(uint64_t cpu_freq_hz, uint64_t irq_hz) {
    ysd8002.cpu_freq_hz    = cpu_freq_hz;
    ysd8002.irq_hz         = irq_hz;
    ysd8002.cycles_per_irq = cpu_freq_hz / irq_hz;
    ysd8002.next_irq_cycle = ysd8002.cycles_per_irq;  /* 1周期後に初回発火 */
    ysd8002.irq_enabled    = 1;
    ysd8002.tcr            = 0x03;  /* TIMER_EN=1 IRQ_EN=1 デフォルト */
    ysd8002.period         = (uint32_t)(cpu_freq_hz / irq_hz);
    ysd8002.sw_runs        = 0;
    ysd8002.score          = 0;
    ysd8002.sw_start_cycle = 0;
    ysd8002.sw_busy        = 0;
    ysd8002.cycle_hi_latch = 0;
    ysd8002.score_hi_latch = 0;
}

/* 戻り値: 1=IRQ発火すべき 0=待機中 */
static int YSD8002_tick(uint64_t current_cycle) {
    if (!ysd8002.irq_enabled) return 0;
    if (current_cycle >= ysd8002.next_irq_cycle) {
        ysd8002.next_irq_cycle = UINT64_MAX;  /* IREtが次を設定するまで停止 */
        return 1;
    }
    return 0;
}

/* IRET時: PERIOD設定値で次回発火サイクルを再設定 */
static void YSD8002_iret(uint64_t current_cycle) {
    uint64_t period = (ysd8002.period > 0) ? (uint64_t)ysd8002.period
                                            : ysd8002.cycles_per_irq;
    ysd8002.next_irq_cycle = current_cycle + period;
}

/* HALT時の統計出力 */
static void YSD8002_report(uint64_t total_cycles) {
    uint64_t elapsed_ms = total_cycles * 1000ULL / ysd8002.cpu_freq_hz;
    fprintf(stderr, "[YSD8002] cpu_freq=%llu Hz  irq_hz=%llu\n",
            (unsigned long long)ysd8002.cpu_freq_hz,
            (unsigned long long)ysd8002.irq_hz);
    fprintf(stderr, "[YSD8002] total_cycles=%llu  elapsed=%llu ms\n",
            (unsigned long long)total_cycles,
            (unsigned long long)elapsed_ms);
}

// ================= YSD8003 ストレージ =================
// YSD8003: YSD8800用ストレージコントローラ（仮想デバイス）
// 設計書: emu23_device_design_v1_2.docx

#define SD_CMD_ADDR   0xFCA0  /* SD_CMD:    0=READ_SETUP 1=WRITE_SETUP 2=EXEC */
#define SD_STAT_ADDR  0xFCA2  /* SD_STAT:   bit0=BUSY bit1=ERROR bit2=READY   */
#define SD_LBA_LO     0xFCA4  /* LBA_LO:    LBAアドレス下位16bit              */
#define SD_LBA_HI     0xFCA6  /* LBA_HI:    LBAアドレス上位16bit              */
#define SD_BUF_PTR    0xFCA8  /* BUF_PTR:   バッファポインタ (0-511)          */
#define SD_DATA       0xFCAA  /* DATA:      PIOデータ(8bit)・自動BUF_PTR++   */
#define SD_IRQ_CTRL   0xFCAC  /* IRQ_CTRL:  bit0=IRQ_EN bit1=ERR_EN           */
#define SD_DISK_LO    0xFCAE  /* DISK_LO:   総セクタ数 下位16bit              */
#define SD_DISK_HI    0xFCB0  /* DISK_HI:   総セクタ数 上位16bit              */

static uint8_t  sd_buf[512];        /* セクタバッファ                         */
static int      sd_busy_latch = 0;  /* BUSYラッチ: EXEC→1, 1回目STAT読→0   */
static FILE    *disk_fp = NULL;     /* --diskオプションで開くファイル         */
static uint32_t sd_lba = 0;         /* 現在LBAアドレス                        */
static uint16_t sd_buf_ptr = 0;     /* BUF_PTRレジスタ (0-511)               */
static uint8_t  sd_irq_ctrl = 0;    /* IRQ_CTRLレジスタ                       */
static uint8_t  sd_cmd = 0;         /* 最後のSD_CMDコマンド                   */
static uint8_t  sd_stat = 0;        /* SD_STATレジスタ (bit2=READY初期値)    */
static uint32_t sd_disk_sectors = 0;/* 総セクタ数                             */

/* [v1.03] EXEC 完了 IRQ 遅延機構 */
/* EXEC 受理時に sd_irq_delay = 512 で予約、メインループで毎命令デクリメント */
/* 0 到達時に ysd8004_raise(IRQ_STAT_BIT_STOR) で IRQ1 発火 */
/* 設計書: emu23_v103_design_v1_4.docx §2 */
static int      sd_irq_delay = 0;   /* 残りサイクル数。0=非予約、>0=予約中    */
#define SD_IRQ_DELAY_CYCLES  512    /* EXEC受理→IRQ発火までのサイクル数      */

// ================= YSD8004 割り込みコントローラ =================
// YSD8004: YSD8800用割り込みコントローラ（仮想デバイス）
// 設計書: emu23_device_design_v1_2.docx

#define IRQ_STAT_ADDR 0xFCB2  /* IRQ_STAT: Write-to-Clear方式              */
#define IRQ_MASK_ADDR 0xFCB4  /* IRQ_MASK: 1=マスク 0=許可                 */

/* IRQ_STAT ビット定義 */
#define IRQ_STAT_BIT_UART_RX 0x0001  /* [v1.02] bit0: YSD8001 UART RX */
#define IRQ_STAT_BIT_STOR    0x0002  /* bit1: YSD8003 ストレージ完了/エラー  */
#define IRQ_STAT_BIT_UART_TX 0x0004  /* [v1.02] bit2: YSD8001 UART TX (TDRE) */

static uint16_t irq_stat = 0;   /* IRQ_STATレジスタ                         */
static uint16_t irq_mask = 0x0004; /* IRQ_MASKレジスタ (0=許可) リセット値: bit2=TX IRQマスク (ysd8001_uart_design_v1_2 §3.6) */

/* YSD8004経由IRQ1発火: 許可ビットのみSTATにOR、非0ならIRQ1をpending */
/* emu23内部: irq_pending=2 → vec=$0004（ベクタテーブルIRQ1エントリ）*/
/* [v1.03] IRQ pending 上書き保護: 高優先IRQ（IRQ0=1, IRQ3=3）を蹴落とさない */
/*         保護でブロックされた場合も irq_stat は保持され、メインループの */
/*         IRQ_STAT 再評価機構で再pending化される */
static void ysd8004_raise(uint16_t bits) {
    uint16_t allowed = bits & ~irq_mask;  /* マスクで許可されたビットのみ */
    if (allowed == 0) return;
    irq_stat |= allowed;
    if (irq_stat != 0) {
        /* [v1.03] pending保護: 既存の高優先IRQを蹴落とさない */
        /* 0=IRQ0(タイマー、未受理), 3=IRQ3(アラインメント) は保護 */
        /* 既存IRQ1(=2)上書きは無害、IRQ4(=4 SYSCALL)上書きはIRQ1優先で正当 */
        if (cpu.irq_pending < 0 ||         /* 何もpending無し */
            cpu.irq_pending == 2 ||        /* 既にIRQ1 → 上書き無害 */
            cpu.irq_pending == 4) {        /* SYSCALL → IRQ1優先で上書きOK */
            cpu.irq_pending = 2;  /* ベクタ $0004 = IRQ1（YSD8004経由） */
        }
        /* それ以外（irq_pending == 1 or 3）は保護: irq_stat に残し再評価機構で復活 */
    }
}

// ================= YSD8001 UART =================
// [v1.02] YSD8001: YSD8800用UARTチップ（仮想デバイス）
// 設計書: ysd8001_uart_design_v1_1.docx, emu23_v102_design_v1_2.docx

/* UART_STAT ビット定義 */
#define YSD8001_STAT_TX_READY  0x0001  /* bit0: 送信レジスタ書き込み可能 */
#define YSD8001_STAT_RX_READY  0x0002  /* bit1: 受信バッファにデータあり */

/* UART_STAT Write-to-Clear マスク（bit1 のみ WTC 対象） */
#define YSD8001_STAT_WTC_MASK  0x0002

/* TX タイミング定数: 9600 bps @ 4 MHz の 1 バイト送信時間
   = 10 bit × (4M/9600) = 4166.67 → 4167 サイクル */
#define YSD8001_TX_CYCLES      4167

typedef struct {
    /* レジスタ状態 */
    uint16_t stat;             /* UART_STAT ($FC84) */
    uint8_t  rx_buf;           /* UART_RX 内部バッファ */
    uint16_t baud;             /* UART_BAUD ($FC86) 予約定義、動作影響なし */

    /* TX タイミングモデル */
    uint64_t tx_complete_cycle;/* TX_READY=1 復帰サイクル (UINT64_MAX で停止) */

    /* RX 入力源 */
    FILE    *rx_src;           /* -i FILE 指定時のファイル、NULL=stdin */
    int      rx_stdin_nb;      /* stdin 非ブロッキング設定済みフラグ */
} ysd8001_t;

static ysd8001_t ysd8001;

/* 初期化（main から1回だけ呼び出し） */
static void ysd8001_init(void) {
    ysd8001.stat = YSD8001_STAT_TX_READY;  /* TX_READY=1, RX_READY=0 */
    ysd8001.rx_buf = 0x00;
    ysd8001.baud = 416;  /* 9600 bps @ 4MHz 相当（予約定義） */
    ysd8001.tx_complete_cycle = UINT64_MAX;  /* TX 動作なし */
    /* rx_src は main() で先行設定済みなら保持、未設定なら NULL（=stdin） */

    /* stdin 非ブロッキング設定（rx_src==NULL の場合のみ） */
    if (ysd8001.rx_src == NULL && !ysd8001.rx_stdin_nb) {
        int fl = fcntl(STDIN_FILENO, F_GETFL, 0);
        if (fl != -1) fcntl(STDIN_FILENO, F_SETFL, fl | O_NONBLOCK);
        ysd8001.rx_stdin_nb = 1;
    }
}

/* リセット（REPL の reset コマンド等から呼ばれる） */
static void ysd8001_reset(void) {
    ysd8001.stat = YSD8001_STAT_TX_READY;
    ysd8001.rx_buf = 0x00;
    ysd8001.baud = 416;
    ysd8001.tx_complete_cycle = UINT64_MAX;
    /* rx_src, rx_stdin_nb は意図的に保持（再オープン不要） */
}

/* 入力源（ファイル or stdin）から 1 バイト読み込み、受信バッファに格納 */
static void ysd8001_poll_rx(void) {
    /* オーバーラン回避：既に未読データがある場合はスキップ */
    if (ysd8001.stat & YSD8001_STAT_RX_READY) return;

    int c = -1;
    if (ysd8001.rx_src != NULL) {
        /* ファイル入力源 */
        int ch = fgetc(ysd8001.rx_src);
        if (ch != EOF) c = ch;
    } else {
        /* stdin 非ブロッキング読み込み */
        unsigned char buf;
        ssize_t n = read(STDIN_FILENO, &buf, 1);
        if (n == 1) c = buf;
    }

    if (c >= 0) {
        ysd8001.rx_buf = (uint8_t)c;
        ysd8001.stat |= YSD8001_STAT_RX_READY;
        ysd8004_raise(IRQ_STAT_BIT_UART_RX);
    }
}

/* exec_one() から毎サイクル呼ばれる軽量関数 */
static void ysd8001_tick(uint64_t current_cycle) {
    /* RX ポーリング: 256 サイクルに 1 回 */
    if ((current_cycle & 0xFF) == 0) {
        ysd8001_poll_rx();
    }

    /* TX_READY 復帰判定 */
    if (current_cycle >= ysd8001.tx_complete_cycle) {
        ysd8001.stat |= YSD8001_STAT_TX_READY;
        ysd8001.tx_complete_cycle = UINT64_MAX;  /* 1回限り */
    }

    /* TX 割り込み（TDRE）: TX_READY=1 の間継続的に発火要求 */
    if (ysd8001.stat & YSD8001_STAT_TX_READY) {
        ysd8004_raise(IRQ_STAT_BIT_UART_TX);
    }
}

/* UART_TX への書き込み: 即時 putchar、TX_READY=0、完了サイクルセット */
static void ysd8001_tx_write(uint8_t v) {
    putchar((int)v);
    fflush(stdout);
    ysd8001.stat &= ~YSD8001_STAT_TX_READY;  /* bit0 クリア */
    ysd8001.tx_complete_cycle = cpu.cycle + YSD8001_TX_CYCLES;
}

/* UART_RX 読み出し: 副作用なし（RX_READY はクリアしない） */
static uint8_t ysd8001_rx_read(void) {
    return ysd8001.rx_buf;
}

/* UART_STAT 読み出し */
static uint16_t ysd8001_stat_read(void) {
    return ysd8001.stat;
}

/* UART_STAT 書き込み: Write-to-Clear (bit1 RX_READY のみ) */
static void ysd8001_stat_write(uint16_t v) {
    if (v & YSD8001_STAT_RX_READY) {
        ysd8001.stat &= ~YSD8001_STAT_RX_READY;
    }
    /* bit0 (TX_READY) への書き込みは無視（HW 自動管理） */
}

// ================= DBG =================

typedef struct {
    uint16_t addr;
    int      line;
    char     text[128];
} dbgline_t;

static dbgline_t dbg[MAX_DBG];
static int dbg_count = 0;
static int quiet_mode = 0;  /* -q: 診断メッセージを抑制、UART出力のみ stdout */

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
// YSD8001 UART
#define UART_TX    0xFC80
#define UART_RX    0xFC82
#define UART_STAT  0xFC84
#define UART_BAUD  0xFC86  /* [v1.02] ボーレート分周値（予約定義） */
// YSD8002 タイマー ($FC90-$FC9E) → SD_CMD_ADDR 等は上で定義済み
#define TCR_ADDR      0xFC90
#define PERIOD_HI     0xFC92
#define PERIOD_LO     0xFC94
#define CYCLE_LO      0xFC96
#define CYCLE_HI      0xFC98
#define SW_RUNS_ADDR  0xFC9A
#define SCORE_LO      0xFC9C
#define SCORE_HI      0xFC9E

uint16_t rd16(uint16_t a) {
    if (a & 1) {
        printf("!! ALIGNMENT EXCEPTION (READ) @%04x\n", a);
        cpu.irq_pending = 3;  // align = IRQ id 3
        return 0;             // do NOT read, return dummy
    }
    /* YSD8001 UART [v1.02] */
    if (a == UART_STAT) return ysd8001_stat_read();
    if (a == UART_RX)   return (uint16_t)ysd8001_rx_read();
    if (a == UART_BAUD) return ysd8001.baud;
    /* YSD8002 タイマー MMIO */
    if (a == TCR_ADDR) {
        uint8_t tcr = ysd8002.tcr & 0x03;  /* TIMER_EN, IRQ_EN */
        if (ysd8002.sw_busy) tcr |= 0x10;  /* bit4: SW_BUSY */
        return (uint16_t)tcr;
    }
    if (a == PERIOD_HI)  return (uint16_t)(ysd8002.period >> 16);
    if (a == PERIOD_LO)  return (uint16_t)(ysd8002.period & 0xFFFF);
    if (a == CYCLE_LO) {
        /* CYCLE_LO読み出し時にCYCLE_HIをラッチ */
        ysd8002.cycle_hi_latch = cpu.cycle >> 16;
        return (uint16_t)(cpu.cycle & 0xFFFF);
    }
    if (a == CYCLE_HI)   return (uint16_t)(ysd8002.cycle_hi_latch & 0xFFFF);
    if (a == SW_RUNS_ADDR) return ysd8002.sw_runs;
    if (a == SCORE_LO) {
        /* SCORE_LO読み出し時にSCORE_HIをラッチ */
        ysd8002.score_hi_latch = ysd8002.score >> 16;
        return (uint16_t)(ysd8002.score & 0xFFFF);
    }
    if (a == SCORE_HI)   return (uint16_t)(ysd8002.score_hi_latch & 0xFFFF);
    /* YSD8003 ストレージ MMIO */
    if (a == SD_STAT_ADDR) {
        uint16_t stat;
        if (sd_busy_latch) {
            stat = 0x0001;          /* BUSY=1 */
            sd_busy_latch = 0;      /* 1回目読み出しでクリア */
        } else {
            stat = (uint16_t)sd_stat;
        }
        return stat;
    }
    if (a == SD_LBA_LO)   return (uint16_t)(sd_lba & 0xFFFF);
    if (a == SD_LBA_HI)   return (uint16_t)(sd_lba >> 16);
    if (a == SD_BUF_PTR)  return sd_buf_ptr;
    if (a == SD_DATA) {
        uint8_t v = sd_buf[sd_buf_ptr & 0x1FF];
        sd_buf_ptr = (uint16_t)((sd_buf_ptr + 1) & 0x1FF);
        return (uint16_t)v;
    }
    if (a == SD_IRQ_CTRL) return (uint16_t)sd_irq_ctrl;
    if (a == SD_DISK_LO)  return (uint16_t)(sd_disk_sectors & 0xFFFF);
    if (a == SD_DISK_HI)  return (uint16_t)(sd_disk_sectors >> 16);
    /* YSD8004 割り込みコントローラ */
    if (a == IRQ_STAT_ADDR) return irq_stat;
    if (a == IRQ_MASK_ADDR) return irq_mask;

    return (uint16_t)(mem[a] | ((uint16_t)mem[(uint16_t)(a + 1)] << 8));
}

void wr16(uint16_t a, uint16_t v) {
    if (a & 1) {
        printf("!! ALIGNMENT EXCEPTION (WRITE) @%04x\n", a);
        cpu.irq_pending = 3;
        return;
    }
    /* YSD8001 UART [v1.02] */
    if (a == UART_TX) {
        ysd8001_tx_write((uint8_t)(v & 0xFF));
        return;
    }
    if (a == UART_STAT) {
        ysd8001_stat_write(v);  /* Write-to-Clear */
        return;
    }
    if (a == UART_BAUD) {
        ysd8001.baud = v;  /* 予約定義: 値を保持するのみ */
        return;
    }
    /* YSD8002 タイマー MMIO */
    if (a == TCR_ADDR) {
        ysd8002.tcr = (uint8_t)(v & 0x17);  /* bit0,1,2,4 有効 */
        ysd8002.irq_enabled = (ysd8002.tcr & 0x03) ? 1 : 0;
        if (v & 0x04) {
            /* SW_START: 計測開始トリガ（自動クリア・再発行でリセット）*/
            ysd8002.sw_start_cycle = cpu.cycle;
            ysd8002.sw_busy = 1;
        }
        if (v & 0x08) {
            /* SW_STOP: 計測停止トリガ（自動クリア・SCORE確定）*/
            if (ysd8002.sw_busy) {
                ysd8002.score   = cpu.cycle - ysd8002.sw_start_cycle;
                ysd8002.sw_busy = 0;
                /* Dhrystones/sec 算出・表示 */
                uint64_t elapsed = ysd8002.score;
                if (elapsed > 0 && ysd8002.sw_runs > 0) {
                    uint64_t elapsed_us = elapsed * 1000000ULL / ysd8002.cpu_freq_hz;
                    if (elapsed_us > 0) {
                        uint64_t dps = (uint64_t)ysd8002.sw_runs * 1000000ULL / elapsed_us;
                        fprintf(stderr, "--- Dhrystones/sec = %llu ---\n",
                                (unsigned long long)dps);
                        fprintf(stderr, "    cycles=%llu  elapsed=%llu us\n",
                                (unsigned long long)elapsed,
                                (unsigned long long)elapsed_us);
                        fprintf(stderr, "    cpu_freq=%llu Hz  Number_Of_Runs=%u\n",
                                (unsigned long long)ysd8002.cpu_freq_hz,
                                (unsigned)ysd8002.sw_runs);
                    }
                }
            }
        }
        return;
    }
    if (a == PERIOD_HI) {
        ysd8002.period = (uint32_t)(((uint32_t)v << 16) | (ysd8002.period & 0xFFFF));
        /* PERIOD変更時はcycles_per_irqも更新 */
        if (ysd8002.period > 0) ysd8002.cycles_per_irq = ysd8002.period;
        return;
    }
    if (a == PERIOD_LO) {
        ysd8002.period = (uint32_t)((ysd8002.period & 0xFFFF0000) | (uint32_t)v);
        if (ysd8002.period > 0) ysd8002.cycles_per_irq = ysd8002.period;
        return;
    }
    if (a == SW_RUNS_ADDR) { ysd8002.sw_runs = v; return; }
    /* CYCLE/SCORE は読み出し専用: 書き込み無視 */
    if (a == CYCLE_LO || a == CYCLE_HI) return;
    if (a == SCORE_LO || a == SCORE_HI) return;
    /* YSD8003 ストレージ MMIO */
    if (a == SD_CMD_ADDR) {
        uint8_t cmd_val = (uint8_t)(v & 0xFF);
        if (cmd_val == 2) {
            /* EXEC: fread/fwrite即時実行 */
            sd_busy_latch = 1;
            sd_stat = 0x00;  /* BUSY中はREADY=0 */
            sd_buf_ptr = 0;  /* EXEC時にBUF_PTRリセット */
            if (disk_fp) {
                long offset = (long)sd_lba * 512L;
                if (fseek(disk_fp, offset, SEEK_SET) != 0) {
                    sd_stat = 0x02;  /* ERROR */
                } else if (sd_cmd == 0) {
                    /* READ_SETUP後のEXEC */
                    size_t got = fread(sd_buf, 1, 512, disk_fp);
                    sd_stat = (got == 512) ? 0x04 : 0x02;  /* READY or ERROR */
                } else {
                    /* WRITE_SETUP後のEXEC */
                    size_t put = fwrite(sd_buf, 1, 512, disk_fp);
                    fflush(disk_fp);
                    sd_stat = (put == 512) ? 0x04 : 0x02;
                }
            } else {
                sd_stat = 0x02;  /* ディスク未接続 → ERROR */
            }
            /* [v1.03] IRQ_EN有効時は遅延IRQ予約（512cycle後発火）*/
            /*         即時 ysd8004_raise() ではなく sd_irq_delay にスケジューリング */
            /*         多重EXEC時も前値を上書きして再予約（多重予約防止）*/
            /*         エラー時も予約する: ドライバはSTAT読出で判定する */
            if (sd_irq_ctrl & 0x01) {
                sd_irq_delay = SD_IRQ_DELAY_CYCLES;  /* [v1.03] 直接代入で多重予約防止 */
            }
        } else {
            sd_cmd = cmd_val;  /* 0=READ_SETUP 1=WRITE_SETUP */
        }
        return;
    }
    if (a == SD_LBA_LO) { sd_lba = (sd_lba & 0xFFFF0000) | (uint32_t)v; return; }
    if (a == SD_LBA_HI) { sd_lba = (sd_lba & 0x0000FFFF) | ((uint32_t)v << 16); return; }
    if (a == SD_BUF_PTR) { sd_buf_ptr = v & 0x01FF; return; }
    if (a == SD_DATA) {
        sd_buf[sd_buf_ptr & 0x1FF] = (uint8_t)(v & 0xFF);
        sd_buf_ptr = (uint16_t)((sd_buf_ptr + 1) & 0x1FF);
        return;
    }
    if (a == SD_IRQ_CTRL) { sd_irq_ctrl = (uint8_t)(v & 0x03); return; }
    /* DISK_LO/HI: 読み出し専用 */
    if (a == SD_DISK_LO || a == SD_DISK_HI) return;
    /* YSD8004 割り込みコントローラ */
    if (a == IRQ_STAT_ADDR) { irq_stat &= ~v; return; }  /* Write-to-Clear */
    if (a == IRQ_MASK_ADDR) { irq_mask = v; return; }

    mem[a]   = (uint8_t)(v & 0xFF);
    mem[(uint16_t)(a + 1)] = (uint8_t)(v >> 8);
}

uint8_t rd8(uint16_t a) {
    /* YSD8001 UART [v1.02] */
    if (a == UART_STAT) return (uint8_t)(ysd8001_stat_read() & 0xFF);
    if (a == UART_RX)   return ysd8001_rx_read();
    /* UART_BAUD は 16bit 専用のため rd8 では扱わない（仕様書 v1.1 §3.5） */
    /* YSD8003: DATA は8bitアクセスも同様（BUF_PTR自動インクリメント）*/
    if (a == SD_DATA) {
        uint8_t v = sd_buf[sd_buf_ptr & 0x1FF];
        sd_buf_ptr = (uint16_t)((sd_buf_ptr + 1) & 0x1FF);
        return v;
    }
    return mem[a];
}

void wr8(uint16_t a, uint8_t v) {
    /* YSD8001 UART [v1.02] */
    if (a == UART_TX) {
        ysd8001_tx_write(v);
        return;
    }
    if (a == UART_STAT) {
        ysd8001_stat_write((uint16_t)v);
        return;
    }
    /* YSD8003: DATA は8bitアクセスも同様 */
    if (a == SD_DATA) {
        sd_buf[sd_buf_ptr & 0x1FF] = v;
        sd_buf_ptr = (uint16_t)((sd_buf_ptr + 1) & 0x1FF);
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
    if (!quiet_mode)
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
    if (!quiet_mode) printf("Loaded %d dbg entries\n", dbg_count);
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
    if (!quiet_mode) printf("Loaded %d label symbols\n", sym_count);
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
    case 0x05: // SYSCALL  [ISA2.3: 1バイト]
        return 1;
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
        if (!quiet_mode)
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
        YSD8002_iret(cpu.cycle);       // [YSD8002] 次回タイマー発火サイクル再設定
        break;

    case 0x05: { /* SYSCALL  [ISA2.3: 1バイト・Aレジスタ番号渡し] */
        /* imm16フェッチなし（1バイト命令）*/
        /* 設計書 emu23_device_design_v1_2.docx §4.1: IRQ4発火のみ（if/else chain廃止）*/
        /* Dhrystone計測はYSD8002 MMIO（SW_START/SW_STOP）で実施 */
        if (!quiet_mode)
            fprintf(stderr, "** SYSCALL #%04X triggered **\n", (unsigned)cpu.a);
        cpu.irq_pending = 4;
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
        if (rd && rs) {
            uint16_t val = rd16(*rs);
            *rd = val; set_zn(*rd);
        }
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
        if (!quiet_mode) {
            printf("*** HALT at %04x ***\n", pc0);
            dump_regs();
        }
        YSD8002_report(cpu.cycle);  /* [YSD8002] タイマー統計（stderr）*/
        return;
    }

    // --- タイマー IRQ (YSD8002) ---
    if (cpu.irq_pending < 0 && YSD8002_tick(cpu.cycle)) {
        cpu.irq_pending = 1;  /* IRQ0 = タイマー */
    }

    // --- [v1.03] YSD8003 EXEC 完了 IRQ 遅延機構 ---
    // 設計書: emu23_v103_design_v1_4.docx §2.5
    // EXEC受理時に sd_irq_delay = 512 で予約、命令毎に -1
    // 0到達時に ysd8004_raise() で IRQ1 発火（保護ロジック適用）
    if (sd_irq_delay > 0) {
        sd_irq_delay--;
        if (sd_irq_delay == 0) {
            ysd8004_raise(IRQ_STAT_BIT_STOR);
        }
    }

    // --- [v1.03] IRQ_STAT 再評価機構 ---
    // 設計書: emu23_v103_design_v1_4.docx §3.3 / §5.4
    // ysd8004_raise() の pending 保護でブロックされた IRQ1 を、高優先 IRQ 完了後
    // （IRET後）に自然に復活させるための機構
    // タイマー再評価（L1285）と同じパターン
    if (cpu.irq_pending < 0 && irq_stat != 0) {
        cpu.irq_pending = 2;  /* IRQ1 を再 pending */
    }

    // --- [v1.02] YSD8001 UART tick (RX poll, TX timing, TX irq) ---
    ysd8001_tick(cpu.cycle);
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
            YSD8002_init(ysd8002.cpu_freq_hz, ysd8002.irq_hz); /* [YSD8002] 周波数設定維持 */
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
    int run_steps = 0;   /* -n N: Nステップ実行してPCトレースを出力して終了 */
    int trace_from = -1; /* -b ADDR: このアドレス到達後にトレース開始 */

    if (argc < 2) {
        fprintf(stderr,
            "emu23 v1.04 (2026-05-18) for YSD8800 ISA2.3\n"
            "  - YSD8003 deferred completion IRQ (delay=512 cycles)\n"
        "  - v1.04: DBG printf removed\n"
            "  - YSD8004 irq_pending overwrite protection + IRQ_STAT re-evaluation\n"
            "usage: emu23 prog.bin [prog.dbg [prog.sym]] [options]\n"
            "  -n N         run N steps and dump trace (non-interactive)\n"
            "  -b ADDR      start tracing after reaching ADDR\n"
            "  -q           quiet: run until HALT, UART output only\n"
            "  -i FILE      UART RX input file (fed byte by byte)\n"
            "               if omitted, stdin is polled non-blocking\n"
            "  --disk FILE  attach disk image (YSD8003 storage)\n"
            "  prog.dbg and prog.sym are auto-derived from prog.bin if omitted\n");
        return 1;
    }

    /* -q と -i は load_bin / ysd8001_init より前に解析する必要がある */
    for (int i = 2; i < argc; i++) {
        if (strcmp(argv[i], "-q") == 0) quiet_mode = 1;
        if (strcmp(argv[i], "-i") == 0 && i+1 < argc) {
            FILE *f = fopen(argv[i+1], "rb");
            if (!f) {
                fprintf(stderr, "emu23: cannot open -i file: %s\n", argv[i+1]);
                return 1;
            }
            ysd8001.rx_src = f;  /* ysd8001_init() より前に設定 */
        }
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
    cpu.sp          = 0xFC7E;  /* ISA2.2 仕様: スタック領域 $F800-$FC7F */
    cpu.irq_pending = -1;
    cpu.pc          = rd16(0x0000);  // reset vector (§7.3)
    YSD8002_init(4000000ULL, 100ULL); /* [YSD8002] 4MHz / 100Hz = 40,000 cycles/tick */
    ysd8001_init();  /* [v1.02] YSD8001 UART 初期化 */
    // flags=0 → IE=0 (割り込み禁止) は仕様通り

    /* --disk オプション解析・ディスクイメージ初期化 */
    for (int i = 2; i < argc; i++) {
        if (strcmp(argv[i], "--disk") == 0 && i+1 < argc) {
            i++;
            disk_fp = fopen(argv[i], "r+b");
            if (!disk_fp) {
                /* 存在しない場合は新規作成 */
                disk_fp = fopen(argv[i], "w+b");
            }
            if (!disk_fp) {
                fprintf(stderr, "emu23: cannot open disk image: %s\n", argv[i]);
            } else {
                /* 総セクタ数を計算 */
                fseek(disk_fp, 0, SEEK_END);
                long fsz = ftell(disk_fp);
                fseek(disk_fp, 0, SEEK_SET);
                sd_disk_sectors = (fsz > 0) ? (uint32_t)(fsz / 512) : 0;
                sd_stat = 0x04;  /* READY */
                if (!quiet_mode)
                    fprintf(stderr, "[YSD8003] disk: %s (%u sectors)\n",
                            argv[i], (unsigned)sd_disk_sectors);
            }
        }
    }

    /* -n/-b オプションを解析 */
    for (int i = 2; i < argc; i++) {
        if (strcmp(argv[i], "-n") == 0 && i+1 < argc)
            run_steps = atoi(argv[++i]);
        else if (strcmp(argv[i], "-b") == 0 && i+1 < argc)
            trace_from = (int)strtol(argv[++i], NULL, 16);
    }

    int dump_addr = -1, dump_len = 0;

    /* -m ADDR N: N命令実行後にADDRからNワードをダンプ */
    for (int i = 2; i < argc; i++) {
        if (strcmp(argv[i], "-m") == 0 && i+2 < argc) {
            dump_addr = (int)strtol(argv[++i], NULL, 16);
            dump_len  = atoi(argv[++i]);
        }
    }

    /* -q モード: HALT まで無制限実行、UART出力のみ stdout */
    if (quiet_mode) {
        while (!cpu.halted) exec_one();
        fflush(stdout);
        return 0;
    }

    if (run_steps > 0) {
        /* バッチモード */
        /* -b ADDR指定時: アドレスに最初に到達した後 run_steps 命令をトレース */
        /* -b なし: 最初から run_steps 命令をトレース */
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
        /* メモリダンプ */
        if (dump_addr >= 0) {
            printf("MEM[%04X+%d]:", dump_addr, dump_len);
            for (int i = 0; i < dump_len; i++)
                printf(" %04X", rd16((uint16_t)(dump_addr + i*2)));
            printf("\n");
        }
        return 0;
    }

    printf("YSD8800 ISA2.3 Emulator (emu23 v1.03) — reset vector = %04x\n", cpu.pc);
    printf("Type 'help' for commands.\n");

    repl();
    return 0;
}
