// emu23_v2_10.c v2.10 (2026-08-20): [改良4: キャッシュ下地（メモリ課金＋物理アドレストレース）]
//   設計書: emu23_cache_base_design_v0_4.md（レビュー 条件付き承認・再レビュー不要）
//   新設オプション: --mem-latency / --trace-addr / --cache-stats
//                   --cache-size / --cache-line
//   ★既定(無指定)は mem_charge() が cache_enable==0 で即 0 を返すため、
//     Dhrystone 819/48785/P:20 および -q stdout の byte-exact 一致は完全に不変（R1）★
//   ★課金式は §3.2.2 の 4 分岐（取り違え厳禁）★
//     読みヒット : 0                            （PSRAM に到達しない）
//     読みミス   : (LINE_SIZE × LAT_FILL) − 1   （ライン全体を充填・M-1）
//     書きヒット : LAT_WR − 1  ★0 ではない★    （ライトスルー・M-2）
//     書きミス   : LAT_WR − 1                   （ノーライトアロケート・M-2）
//   ★課金はバイト単位。16bit は呼出側が 2 回呼ぶ（C-7）。
//     ただし ISA2.3 の 16bit 整列制約により pa%LINE_SIZE==LINE_SIZE-1 は到達不能であり、
//     バイト単位判定は将来の非整列対応（ISA3.0）に備えた防御的実装である。
//     算術の検証は単体ハーネス t07_unit_poc.c（T-07'）が担う。★
//   ★フックは MMIO 分岐の「後」に置くこと（前に置くと MMIO も課金される・§4.3）★
//   ★mmu_translate() は 1 回だけ呼び、物理アドレス pa を課金にも使う（KY56）★
//   ★cache_enable と charge_enable は別変数（C-9）。--trace-addr 単独時は
//     「判定する・記録する・課金しない」状態が必要なため 1 変数では表現できない。★
//   ★LAT の既定値 6 は §9 で校正するまでの仮値。設計判断の根拠に用いてはならない。★
//   既知の注意: FETCH/RD8/RD16 は §3.2.2 の課金式に現れないため設定しても効果が無い
//     （定義ファイルで指定された場合は [CACHE] note を出す。黙って無視はしない）。
//   既知の注意: [CACHE] の hit/miss は書きアクセスを含む。§3.5 の損益分岐ヒット率
//     97.4% は読み側の値であり、直接比較してはならない。
//
// emu23_v2_00.c v2.00 (2026-08-18): [Phase C: machine-cycle mode -mc]
//   設計書: emu23_mc_design_v0_5.md（レビュー v1.0 条件付き承認クリア）
//   改良3: オプション -mc [file] を新設。命令ごとの固有サイクル数で cpu.cycle を歩進する。
//     ★既定(-mc 無し)は従来どおり CPI=1 固定。mc_step() が表を見ずに 1 を返すため
//       Dhrystone 819/48785/P:20 および -q stdout の byte-exact 一致は完全に不変（R1）★
//     根拠表: ysd8800_cycle_count_table_v1_0.md v1.0（理想メモリ前提。メモリ待ちは対象外=R6）
//   ★値の意味の非対称（取り違え厳禁・設計書 §3.1.1）★
//     命令   : 表の値は S_IRQCHK 非込み → 加算時に +1（mc_step() の return 一箇所のみ）
//     割込受理: 表の値(9)は S_IRQCHK 込み → 加算時に -1（二重計上防止。実加算 8）
//   ★拡張命令(0x1F 系)の CPI は 0x1F プリフィックス分(FETCH,OPFETCH,SUBOP)を内包した
//     「命令全体の総 CPI」である。mc_table[0x1F] は決して参照しない（設計書 §3.5.3）。
//     外部定義ファイルで 0x1F キーを指定するとエラー（二重計上を構造的に排除）★
//   サブオペの peek は mem[] 直読ではなく fetch8() を用いる。実行部と同一経路にしないと
//     MMU 有効時に「論理結果は正しいまま cycle だけ狂う」発見困難なバグになる（§4.2）。
//   BRK(0x06)=3: サイクル表に記載が無いが、RTL は ID_BRK を個別処理せず S_OPFETCH の
//     default: next_state = S_HALT に落ちるため HALT と同一連鎖（実源確認・§3.3）。
//   HALT(0x01)=3: 表の(4)は dbg_halt 到達検出コスト込み。状態連鎖 FETCH,OPFETCH,HALT を採る。
//   -mc の引数は可変消費（初のパターン）。次 argv が '-' 始まりでなければファイル名として
//     消費する。access() で判定しないこと（タイプミスが黙ってデフォルトに落ちる＝EMU-A の病）。
//     既知の制限: '-' で始まるファイル名は指定できない（§7.2）。
//
// ---- 以下、v1.14 までの履歴（保持） ----
// emu23_v1_14.c v1.14 (2026-08-17): [Phase B'' B-4: EMU-C]
//   設計書: emu23_bp_continue_design_v0_2.md（レビュー v1.0 条件付き承認クリア）
//   B-4 EMU-C: REPL の 'c'(continue) / 't'(trace) が BP 停止位置から再開できない件を修正。
//     原因: while の【入口】で is_break(cpu.pc) を判定していたため、BP 停止位置では
//            is_break()==1 が成立して 0 回ループとなり、1 命令も実行されずに復帰していた。
//     対策: 's' と同じ【後置判定】(do-while) 構造に変更し、必ず 1 命令実行してから
//            BP/HALT を判定する。状態変数の追加は無し。
//     ★仕様確定★ 'c'/'t' は必ず 1 命令以上実行する = 現在 PC の BP では停止しない。
//            （SWI 方式 BP を持つ古典的デバッガと同じ作法。BP 継続に必然）
//            ただし is_break() は純粋なアドレス判定であり【BP は消費されない】。
//            ループで同じ番地に戻れば、その BP で何度でも停止する。
//     ★BREAK 表示は REPL ループ冒頭が行う。'c'/'t' 側では出さないこと（二重表示になる）★
//     横展開: 同一構造の 's' は過去に [FIX BUG-8] で修正済であったが 'c'/'t' へ
//            展開されず残存していた。本修正で REPL 内 3 コマンドの構造を統一する。
//
// ---- 以下、v1.13 までの履歴（保持） ----
// emu23_v1_13.c v1.13 (2026-08-14): [Phase B'' B-2/B-3: EMU-A + EMU-B]
//   設計書: emu23_argsym_design_v0_3.md（レビュー v1.0/v1.1 反映・条件付き承認）
//   段1 EMU-B: MAX_SYM 128 -> 2048。load_sym() をループ回し切り構造に変更し、
//     打切りを sym_overflow で検出して [SYM-TRUNCATED] を stderr へ出力（-q でも出す）。
//   段2 EMU-A: argv 消費マーク方式の前置パスを load_bin() 直前に新設。
//     オプションとその引数を argv_used[] でマークし、未消費の argv[2]/argv[3] のみを
//     .dbg/.sym として位置解釈する。これにより
//     `emu23 prog.bin -i uart.bin --disk d.img` の誤認（Loaded 0 label symbols）が解消。
//     ARGV_MAX(64) 超過は起動時エラー（配列外アクセス防止）。
//   段3: --dbg <file> / --sym <file> 新設（位置引数より優先）。
//     明示指定時の fopen 失敗は [DBG-NOTFOUND]/[SYM-NOTFOUND] を stderr へ。
//     引数欠落は stderr + exit(1)。自動導出時の失敗は従来どおり黙殺。
//   ★警告は全て stderr。stdout は v1.12 と byte-exact 一致（回帰ゲート保護）。
//   ★警告文言に 'Dhrystones/sec' / 'cycles' / 'P:' を含めないこと
//     （Makefile L175 が 2>&1 で合流させ grep するため）。
//   絶対ゲート: Dhrystone 819/48785/P:20、yuios_road2.bin 56416B
//               md5 599a7f9d1ebf103f81f58450ea1b6491 — 全て一致確認済（2026-08-14）。
//
// --- 以下、前版までの履歴（KY41: 旧情報を欠落させない）---
// emu23_v1_12.c v1.12 (2026-08-11): [Phase B' 完了: B-1 TKT-03 + B-C 改良2]
//   B-1 (TKT-03): it_enable_raw_mode() に c_iflag のクリアを追加。
//     ICRNL等を落とし、Enter の CR($0D)がLF変換されずYUI OSシェルに届く。
//     設計書 emu23_interactive_mode_design_v1_6.md。
//   B-C (改良2: バス・プルアップ): MMIOアドレスデコード層を新設。
//     - B-C-1a-1: デコード層骨格（4経路・mmio_classify、非機能変更）
//     - B-C-1a-2: 8bit経路の被覆漏れ解消（YSD8002/8003/8004 計17本）
//                 + 第4状態 MMIO_MAPPED_UNSUPPORTED（UART_BAUD 8bit=$00）
//     - B-C-1a-3: MMUレジスタの --mmu 非依存化（RTL準拠）
//     - B-C-1b  : 未接続MMIO読出=$FF/$FFFF（プルアップ模倣）+ 警告α
//                 (--strict-mmioでβ即時停止) + 抑制機構(同一PC初回のみ・
//                 上限16・サマリ)
//     - B-C-2   : 既定をプルアップへ切替（--no-bus-pullupで切り戻し可）
//     設計書 emu23_device_design_v1_11.md。
//   版数確定: B-1/B-C 双方の絶対ゲート(Dhrystone 819/48785/P:20・
//     yuios_road2.bin 56416B/md5 599a7f9d1ebf103f81f58450ea1b6491)全PASS。
//   既定動作(オプション無し)はv1.11とstdout byte-exact一致・警告0件。
// emu23_v111.c v1.11 (2026-07-18): [EN是正] 発火EN条件 OR→AND化（案B）。
//   TCR bit0(TIMER_EN)かつbit1(IRQ_EN)の両方で発火許可。IRQ_EN=0で割込マスク
//   が名前どおり機能（契約回復）。RTL v0.3(L199 &)と対称。将来課題(案A: TIMER_EN
//   =0でのカウンタ停止)は未実装。詳細 v6_en_fix_design_memo_v0_1.md。
//   Dhrystone不変（0x03→有効/dhry_timer 0x0004→OR/AND両方0で二重に不変）。
// emu23_v110.c v1.10 (2026-07-13): [V5] ★黄金リファレンス改修★
//             タイマー(YSD8002)の再武装契機を「IRET命令」から「TCR bit5 IRQ_ACK書込」へ変更。
//             設計書 v5_design_memo_v0_2.md 準拠 / レビュー v5_design_review_reply_v1_0.docx 承認済。
//
//             【変更理由】v1.07(Step 8-I)以来、IRET命令をフックして YSD8002_iret() を呼び
//             タイマーを再武装していた。しかしこれは★FPGA実装不能★である。
//             ハードウェアでYSD8002が再武装するには「CPUが今IRETした」を知る必要があり、
//             CPUから iret_pulse_o（命令実行の内部事情を晒す専用線）を引くしかない。
//             MC6809はRTIを外部にブロードキャストしない。バスにそんな信号は存在しない。
//             エミュレータは命令実行をフックできるが、ハードウェアにそんなフックはない。
//             → kaizen 原則73「エミュレータの実装都合を仕様と誤認するな」
//
//             【変更点】
//               (1) static int timer_in_service を削除
//               (2) IRQ受理部の timer_in_service=1 を削除
//               (3) IRET命令内の YSD8002_iret() 呼出を削除 (v1.07 Step8-I 修正が丸ごと不要化)
//               (4) TCR($FC90) write: マスク 0x17 → 0x37 に拡張。bit5=IRQ_ACK 新設。
//                   書込時に YSD8002_rearm() を呼び、自動クリアする。
//               (5) YSD8002_iret() → YSD8002_rearm() へ改名（意味の是正）
//
//             【★互換性注意★】タイマー割込ハンドラは TCR に IRQ_ACK(bit5) を書く義務がある。
//             書かないとタイマーは発火後に自己武装解除したまま★二度と発火しない★。
//             影響: kernel_v12_7.asm IRQ0_HANDLER / startup_harness23_v15.asm _timer_handler
//
// --- 以下、旧版履歴 ---
// emu23_v109.c v1.09 (2026-06-27): [Step 8] インタラクティブモード(-it)追加。設計書
//             emu23_interactive_mode_design_v1_1.md(EMU23-MOD-004)準拠。termios raw mode化で
//             YUI OS Shell(Ph.6)のリアルタイム対話操作を実現。ECHO/ICANON/ISIG無効・エコーは
//             YUI OS UARTドライバ責務・Ctrl+D(0x04)で終了。既存破壊変更はysd8001_tick()内の
//             poll_rx呼び出しを関数ポインタ経由化した1行のみ。-q/-i/REPLは非回帰(既定poll_rx)。
// emu23_v108.c v1.08 (2026-06-25): [Step 8 V(-1)] MMU復活移植。emu22 v1.10→v1.21改版で
//             脱落したFM-11方式16ページMMU(mmu_translate/phys_mem/PTR[16]@0xFF00/MCR@0xFF10)を
//             emu22-1_10.c から復活移植。--mmu で有効化。無効時は恒等写像でv1.07とbyte-exact非干渉。
//             命令フェッチ26箇所をfetch8化。MMUデバッガコマンド(mmu/physmem)も移植。
// emu23_v107.c v1.07 (2026-06-22): [Step 8-I] IRQ優先制御修正。IRET命令(case 0x04)が
//             IRQ種別を問わず無条件にYSD8002_iret()を呼んでいた設計書(§5.3)違反を是正。
//             timer_in_serviceフラグで「タイマーIRQ復帰時のみ」再設定するよう限定し、
//             タイマーとIRQ1衝突時のタイマーIRQ大量欠落を解消。
// emu23_v106.c v1.06 (2026-06-20): [Step 8-F / F-001] REPL 'bd N'（ブレークポイント削除）修正。
//        v1.05 以前は分岐順序の誤りで cmd[0]=='b' が "bd" を先取りし bd 分岐が不到達
//        （'bd 0' が "Unknown label: d" を出すだけで削除されなかった）。
//        bd 分岐を b 分岐の前へ移動して解消。機能差分は bd のみ・他コマンド不変。
// emu23_v105.c v1.05 (2026-06-06): emu23_v104 + stack watermark計測(-w/--wm-steps/--wm-warmup)。試験専用I3-POOLは非搭載。
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
#include <termios.h>  /* [v1.09] -it raw mode terminal control */
#include <signal.h>   /* [v1.09] -it SIGTERM/SIGHUP handler for raw mode recovery */

#define MEM_SIZE 65536
#define MAX_DBG  8192
#define MAX_BP   128
#define MAX_SYM  2048   /* [v1.13] EMU-B: 128 -> 2048 (実ビルド 1164/PoC 1199 シンボル対応) */
#define ARGV_MAX 64     /* [v1.13] EMU-A: argv 消費マーク配列の上限（超過は起動時エラー） */

// FLAGS bits
#define FL_Z   0x01   // Zero
#define FL_N   0x02   // Negative
#define FL_IE  0x80   // Interrupt Enable

uint8_t mem[MEM_SIZE];

/* ===== MMU 拡張 (v1.08: emu22 v1.10 からの復活移植) =====================
 * FM-11方式 16ページMMU。移植元 emu22-1_10.c §MMU を踏襲。
 * --mmu 無効時は恒等写像で v1.07 と完全非干渉(byte-exact担保)。
 * 出典: emu22-1_10.c :61,:105-141,:355-361,:432-440
 */
#define PHYS_MEM_SIZE  (1024 * 1024)   /* MMUモード: 1MB (20bit物理アドレス) */
#define MMU_PTR_BASE   0xFF00          /* PTR[0]〜PTR[15]: 0xFF00〜0xFF0F */
#define MMU_MCR_ADDR   0xFF10          /* MMU Control Register */
#define MCR_EN         0x01            /* bit0: MMU Enable */
#define MCR_KRN_PROT   0x02            /* bit1: Kernel Protect (将来拡張) */

static int      mmu_mode = 0;          /* --mmu: MMU拡張を有効にする */
static uint8_t *phys_mem = NULL;       /* --mmu時に malloc で確保 (1MB) */

typedef struct {
    uint8_t ptr[16];  /* Page Table Registers */
    uint8_t mcr;      /* MMU Control Register */
} mmu_t;
static mmu_t mmu;

/* rd8/wr8 前方宣言 (rd16/wr16 のMMUレジスタ委譲で使用) */
uint8_t rd8(uint16_t a);
void    wr8(uint16_t a, uint8_t v);

/* 論理->物理アドレス変換 (MCR_EN無効時は恒等写像) */
static uint32_t mmu_translate(uint16_t logical) {
    if (mmu.mcr & MCR_EN) {
        uint8_t  page   = (uint8_t)(logical >> 12);
        uint16_t offset = logical & 0x0FFF;
        return ((uint32_t)mmu.ptr[page] << 12) | offset;
    }
    return (uint32_t)logical;
}

/* MMU: リセット初期化 (恒等写像, MMU無効) */
static void mmu_reset(void) {
    for (int i = 0; i < 16; i++) mmu.ptr[i] = (uint8_t)i;
    mmu.mcr = 0;
}

/* ===== 改良4: キャッシュ下地 (v2.10) 前方宣言 ==========================
 * 設計: emu23_cache_base_design_v0_4.md §5
 * ★実体は cpu_t cpu 宣言より後に置く（§5.1 配置注意・Phase C 再発防止）★
 * ここには enum とプロトタイプのみを置く（fetch8 が cpu 宣言より前にあるため）
 * ====================================================================== */
typedef enum {
    ACC_FETCH = 0, ACC_RD8, ACC_WR8, ACC_RD16, ACC_WR16
} acc_kind_t;

/* 課金＋トレース（★必ず1バイト単位で呼ぶ★）
 *  pa   : MMU変換後の物理アドレス
 *  kind : アクセス種別
 *  戻り : 追加課金サイクル数（設計書 §3.2.2 の4分岐）
 * ★R1: cache_enable==0 なら何もせず即0を返す（v2.00 と完全同一挙動）★ */
static unsigned mem_charge(uint32_t pa, acc_kind_t kind);

/* 物理メモリへの生アクセス (MMU変換済みアドレスで呼ぶ)
 * 非mmu時は従来 mem[] に落ちる=v1.07 と完全一致 */
static inline uint8_t phys_rd8(uint32_t pa) {
    if (mmu_mode) return phys_mem[pa & 0xFFFFF];
    return mem[(uint16_t)pa];
}
static inline void phys_wr8(uint32_t pa, uint8_t v) {
    if (mmu_mode) phys_mem[pa & 0xFFFFF] = v;
    else          mem[(uint16_t)pa] = v;
}

/* 命令フェッチ用8bitアクセス (MMU変換対応) */
static inline uint8_t fetch8(uint16_t a) {
    /* ★KY56: mmu_translate は1回だけ呼び、物理アドレス pa を課金にも使う★ */
    uint32_t pa = mmu_translate(a);
    mem_charge(pa, ACC_FETCH);
    return phys_rd8(pa);
}
/* ===== MMU 拡張ここまで ================================================= */

/* ===== マシンサイクル対応 (-mc) : v2.00 Phase C ==========================
 * 設計: emu23_mc_design_v0_5.md
 *
 * ★値の意味に関する規約（取り違え厳禁）★
 *  - mc_table[] / mc_table_ext[] : サイクル表の値そのまま = S_IRQCHK 非込み
 *      → 加算時に +1 する (mc_step() の return 一箇所のみ, 設計書 §3.1)
 *  - mc_irq_accept              : サイクル表の値そのまま = S_IRQCHK 込み(9)
 *      → 加算時に -1 する (二重計上防止, 設計書 §3.1.1)
 *    ※命令とIRQで補正の符号が逆である。
 *  - mc_table_ext[] の値は 0x1F プリフィックス分(FETCH,OPFETCH,SUBOP)を
 *    内包した「拡張命令1個ぶんの総CPI」。mc_table[0x1F] は決して参照しない
 *    (加算すると二重計上, 設計書 §3.5)
 */
#define MC_UNDEF       0xFFFF   /* デフォルト表に無いことを示すマーカ */
#define MC_DEFAULT_CPI 4        /* 未定義opcode遭遇時の既定CPI (表§3の最頻値) */
#define MC_CPI_MAX     1000     /* 定義ファイル値域上限 (誤記検出用, 設計書 §6.4) */

static int      mc_enable = 0;          /* 0=CPI固定1(既定) 1=マシンサイクル */
static uint16_t mc_table[256];          /* 主 opcode 用 */
static uint16_t mc_table_ext[256];      /* 0x1F サブオペ用 */
static uint16_t mc_irq_accept = 9;      /* 割込受理 (IRQCHK込み) */
static int      mc_warned_main = 0;     /* 主表 未定義警告済 (§4.3 別カウント) */
static int      mc_warned_ext  = 0;     /* 拡張表 未定義警告済 */

/* デフォルト表初期化: ysd8800_cycle_count_table_v1_0.md v1.0 §2 より転記 */
static void mc_init_default_table(void)
{
    int i;
    for (i = 0; i < 256; i++) { mc_table[i] = MC_UNDEF; mc_table_ext[i] = MC_UNDEF; }

    /* --- Control / System --- */
    mc_table[0x00] = 2;   /* NOP     */
    mc_table[0x01] = 3;   /* HALT    FETCH,OPFETCH,HALT (表の(4)は検出コスト込, §3.2) */
    mc_table[0x02] = 2;   /* EI      */
    mc_table[0x03] = 2;   /* DI      */
    mc_table[0x04] = 7;   /* IRET    */
    mc_table[0x05] = 3;   /* SYSCALL */
    mc_table[0x06] = 3;   /* BRK     表に無い。RTLは default:S_HALT で HALT と同一経路 (§3.3) */
    /* 0x1F は EXT プリフィックス。mc_table[0x1F] は参照されない (§3.5.3) */

    /* --- データ転送 --- */
    mc_table[0x20] = 4;   /* MOV  rD,rS      */
    mc_table[0x21] = 6;   /* LDW  rD,#imm    */
    mc_table[0x22] = 8;   /* LDW  rD,[imm16] */
    mc_table[0x23] = 7;   /* STW  rS,[imm16] */
    mc_table[0x24] = 7;   /* LDW  rD,[rS]    */
    mc_table[0x25] = 6;   /* STW  rS,[rD]    */
    mc_table[0x26] = 8;   /* LDW  rD,[X+off] */
    mc_table[0x27] = 7;   /* STW  rS,[X+off] */

    /* --- 算術 --- */
    mc_table[0x40] = 4;   /* ADD  rD,rS   */
    mc_table[0x41] = 6;   /* ADDI rD,#imm */
    mc_table[0x42] = 4;   /* SUB  rD,rS   */
    mc_table[0x43] = 6;   /* SUBI rD,#imm */
    mc_table[0x44] = 4;   /* CMP  rD,rS   */
    mc_table[0x45] = 6;   /* CMPI rD,#imm */

    /* --- 論理 / シフト --- */
    mc_table[0x50] = 4;   /* AND  rD,rS   */
    mc_table[0x51] = 6;   /* ANDI rD,#imm */
    mc_table[0x52] = 4;   /* OR   rD,rS   */
    mc_table[0x53] = 6;   /* ORI  rD,#imm */
    mc_table[0x54] = 4;   /* XOR  rD,rS   */
    mc_table[0x55] = 6;   /* XORI rD,#imm */
    mc_table[0x56] = 4;   /* NOT  rD      */
    mc_table[0x57] = 4;   /* SHL  rD      */
    mc_table[0x58] = 4;   /* SHR  rD      */
    mc_table[0x59] = 4;   /* SAR  rD      */

    /* --- 分岐 / サブルーチン --- */
    mc_table[0x60] = 5;   /* JMP rel16 */
    mc_table[0x61] = 5;   /* BEQ rel16 */
    mc_table[0x62] = 5;   /* BNE rel16 */
    mc_table[0x63] = 5;   /* BLT rel16 */
    mc_table[0x64] = 5;   /* BGE rel16 */
    mc_table[0x68] = 7;   /* JSR imm16 */
    mc_table[0x69] = 7;   /* RET       */

    /* --- 0x1F 拡張 (値は 0x1F 分を内包した命令全体のCPI, §3.5) --- */
    mc_table_ext[0x00] = 6;  /* PUSH A */
    mc_table_ext[0x01] = 6;  /* PUSH B */
    mc_table_ext[0x02] = 6;  /* PUSH X */
    mc_table_ext[0x03] = 6;  /* POP  A */
    mc_table_ext[0x04] = 6;  /* POP  B */
    mc_table_ext[0x05] = 6;  /* POP  X */
    mc_table_ext[0x10] = 7;  /* LDB A,[imm16] */
    mc_table_ext[0x11] = 6;  /* LDB A,[X]     */
    mc_table_ext[0x12] = 7;  /* LDB B,[imm16] */
    mc_table_ext[0x13] = 6;  /* LDB B,[X]     */
    mc_table_ext[0x14] = 7;  /* STB A,[imm16] */
    mc_table_ext[0x15] = 6;  /* STB A,[X]     */
    mc_table_ext[0x16] = 7;  /* STB B,[imm16] */
    mc_table_ext[0x17] = 6;  /* STB B,[X]     */

    mc_irq_accept = 9;       /* IRQCHK込み。加算時に -1 する (§3.1.1) */
}

/* ===== マシンサイクル対応ここまで ======================================= */

/* ===== stack watermark 計測 (v1.05 で正式統合) =====
 * 各タスクのコール/データスタック最深値を測定し、128B枠超過とguard破壊を検出。
 * -w 指定時のみ動作し、無指定時は完全に従来動作(非回帰)。
 * 設計: emu23_watermark_design v1.1 (I3-POOL等の試験専用機能は含まない) */
#define WM_CALLSTK_LO 0xF000
#define WM_CALLSTK_HI 0xF7FF
#define WM_DATASTK_LO 0xF800
#define WM_DATASTK_HI 0xFBFF
#define WM_GUARD_LO   0xFC00
#define WM_GUARD_HI   0xFC3F
#define WM_GUARD_PAT  0xA55A      /* OS が _kstart で設置する stack guard パターン */
static int      wm_enable    = 0;
static uint64_t wm_max_steps = 2000000ULL;  /* 常駐OS打切り上限 (--wm-steps で変更) */
static uint64_t wm_warmup_cycles = 2000ULL; /* 起動初期の一過性除外 (--wm-warmup で変更) */
static uint16_t wm_callsp_slot[16];  /* 各tidコールスタック最深SP (0xFFFF=未観測) */
static uint16_t wm_datax_slot[16];   /* 各tidデータスタック最深X */
/* ================================================== */


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

/* ===== 改良4: キャッシュ下地 (v2.10) 実体 ==============================
 * 設計: emu23_cache_base_design_v0_4.md §5.4 / §5.5
 * ★配置: cpu_t cpu 宣言より後（§5.1）★
 * ====================================================================== */

/* --- 状態変数 (§5.4) --- */
static int      cache_enable  = 0;      /* キャッシュ判定を行うか */
static int      charge_enable = 0;      /* 課金を行うか（★別変数★ C-9） */
static unsigned cache_size    = 16384;  /* 既定 16KB */
static unsigned cache_line    = 32;     /* 既定 32B/line */
static uint32_t *cache_tag    = NULL;   /* タグ配列 (要素数=ライン数) */
static uint8_t  *cache_valid  = NULL;   /* 有効ビット (同上) */
static FILE     *trace_fp     = NULL;   /* トレース出力先 (NULL=無効) */
static const char *lat_file_opt = NULL; /* --mem-latency の定義ファイル（段6で読込） */

/* レイテンシ (§3.3)。添字は acc_kind_t + LAT_FILL */
enum { LAT_FILL_IDX = 5 };
static unsigned lat[6] = { 6, 6, 6, 6, 6, 6 };  /* F,R8,W8,R16,W16,FILL */

/* 統計 (§5.4) */
static uint64_t stat_hit = 0, stat_miss = 0, stat_charged = 0;

/* --- インデックス計算用の導出値 (§5.5) --- */
static unsigned cache_line_shift = 0;   /* log2(cache_line) */
static unsigned cache_idx_mask   = 0;   /* ライン数-1 */

/* --- 構成検査と初期化（§6.4 / §5.5）---
 * ★サイレント丸めの禁止：不正値は必ず exit(1) で弾く★
 * 戻り: 0=正常 / 非0=エラー（呼出側が return 1 する） */
static int is_pow2(unsigned v) { return v && ((v & (v - 1)) == 0); }

static int cache_config_init(void)
{
    unsigned n, sh;

    if (!is_pow2(cache_size)) {
        fprintf(stderr, "emu23: --cache-size must be a power of 2 (got %u)\n", cache_size);
        return 1;
    }
    if (!is_pow2(cache_line)) {
        fprintf(stderr, "emu23: --cache-line must be a power of 2 (got %u)\n", cache_line);
        return 1;
    }
    if (cache_size < cache_line) {
        fprintf(stderr, "emu23: --cache-size (%u) must be >= --cache-line (%u)\n",
                cache_size, cache_line);
        return 1;
    }

    /* log2(cache_line) とライン数-1 を導出（§5.5: マスク演算の前提） */
    for (sh = 0; (1u << sh) != cache_line; sh++) { }
    cache_line_shift = sh;
    n = cache_size / cache_line;               /* ライン数 */
    cache_idx_mask = n - 1;

    cache_tag   = (uint32_t *)calloc(n, sizeof(uint32_t));
    cache_valid = (uint8_t  *)calloc(n, sizeof(uint8_t));
    if (!cache_tag || !cache_valid) {
        fprintf(stderr, "emu23: cannot allocate cache arrays (%u lines)\n", n);
        return 1;
    }
    return 0;
}

/* --- キャッシュ統計の終了時サマリ（§6.5）---
 * ★警告文言規約（Phase C §4.3 で確立）を遵守すること★
 *   Makefile が 2>&1 合流後に grep するため、
 *   'Dhrystones/sec' / 'cycles' / 'P:' の語を含めてはならない。
 *   （'charged' としているのは 'cycles' を避けるためである）
 * ★出力は cache_enable != 0 のときのみ。既定では出力しない（R1 死守）★ */
static void cache_report_summary(void)
{
    uint64_t total;
    double   rate;

    if (!cache_enable) return;

    total = stat_hit + stat_miss;
    rate  = total ? (100.0 * (double)stat_hit / (double)total) : 0.0;
    fprintf(stderr, "[CACHE] hit=%llu miss=%llu rate=%.2f%% charged=%llu\n",
            (unsigned long long)stat_hit,
            (unsigned long long)stat_miss,
            rate,
            (unsigned long long)stat_charged);
}

/* --- レイテンシ定義ファイルの読込（§6.1）---
 * 書式:  KEY  VALUE     （# 以降はコメント）
 *   FETCH / RD8 / WR8 / RD16 / WR16 / FILL
 *
 * ★未知のキーは exit(1)（サイレント破棄の禁止＝Phase C M-5 の教訓）★
 * 戻り: 0=正常 / 非0=エラー */
static int lat_load_file(const char *path)
{
    static const char *keys[6] = { "FETCH", "RD8", "WR8", "RD16", "WR16", "FILL" };
    int seen[6] = {0,0,0,0,0,0};
    char line[256];
    int  lineno = 0, i;
    FILE *fp = fopen(path, "r");

    if (!fp) {
        fprintf(stderr,
                "emu23: [--mem-latency] cannot open definition file: %s\n", path);
        return -1;                     /* ★黙殺しない★ */
    }

    while (fgets(line, sizeof(line), fp)) {
        char key[64];
        long val;
        char *p = line;
        int  n, idx = -1;

        lineno++;
        while (*p == ' ' || *p == '\t') p++;
        if (*p == '#' || *p == '\n' || *p == '\r' || *p == '\0') continue;

        n = sscanf(p, "%63s %li", key, &val);
        if (n < 2) {
            fprintf(stderr, "emu23: [--mem-latency] malformed line %d in %s\n",
                    lineno, path);
            fclose(fp);
            return -1;                 /* ★書式エラーも exit(1)★ */
        }
        for (i = 0; i < 6; i++)
            if (strcmp(key, keys[i]) == 0) { idx = i; break; }
        if (idx < 0) {
            fprintf(stderr,
                "emu23: [--mem-latency] unknown key '%s' at line %d "
                "(expected FETCH/RD8/WR8/RD16/WR16/FILL)\n", key, lineno);
            fclose(fp);
            return -1;                 /* ★未知キーは必ずエラー（§6.1）★ */
        }
        if (val < 1 || val > 65535) {
            fprintf(stderr,
                "emu23: [--mem-latency] value out of range (1..65535) at line %d\n",
                lineno);
            fclose(fp);
            return -1;
        }
        lat[idx] = (unsigned)val;
        seen[idx] = 1;
    }
    fclose(fp);

    /* ★§3.3: RD8 と RD16 に異なる値は物理的にありえない。警告して継続★ */
    if (lat[ACC_RD8] != lat[ACC_RD16])
        fprintf(stderr, "[CACHE] warning: RD8(%u) != RD16(%u); "
                "physically implausible\n", lat[ACC_RD8], lat[ACC_RD16]);
    if (lat[ACC_WR8] != lat[ACC_WR16])
        fprintf(stderr, "[CACHE] warning: WR8(%u) != WR16(%u); "
                "physically implausible\n", lat[ACC_WR8], lat[ACC_WR16]);

    /* ★§3.2.2 の課金式は読み側で FETCH/RD8/RD16 を参照しない
     *   （読みヒット=0／読みミス=LAT_FILL によるライン充填）。
     *   設定しても効果が無いことを明示する（M-5 と同型の
     *   サイレント無視を作らないため）★ */
    if (seen[ACC_FETCH] || seen[ACC_RD8] || seen[ACC_RD16])
        fprintf(stderr,
            "[CACHE] note: FETCH/RD8/RD16 are not used by the charging model "
            "(read hit=0, read miss=line fill via FILL); values recorded only\n");

    return 0;
}

/* --- トレースヘッダ出力（§6.2）---
 * ★Python 後処理（H-1）が前提の取り違えを検出できるよう、
 *   実行時の全パラメータを1行目に刻む★
 * ★mc は -mc の有無。cyc 列の単位が変わる（-mc 無しでは実行命令数）★ */
static void trace_write_header(void)
{
    if (!trace_fp) return;
    fprintf(trace_fp,
            "# emu23 v2.10 trace / mc=%d lat=F%u,R%u,W%u,FILL%u"
            " cache=%u/%u unified wt-nwa nowb\n",
            mc_enable ? 1 : 0,
            lat[ACC_FETCH], lat[ACC_RD8], lat[ACC_WR8], lat[LAT_FILL_IDX],
            cache_size, cache_line);
    fprintf(trace_fp, "cyc,pa,kind,hit\n");
}

/* ★課金＋トレース本体（段4: 4 分岐課金を実装）★
 *  pa   : MMU 変換後の物理アドレス（★必ず 1 バイト単位で呼ぶ★）
 *  kind : アクセス種別
 *  戻り : 追加課金サイクル数（設計書 §3.2.2）
 *
 * ★§3.2.2 の 4 分岐（取り違え厳禁）★
 *   読みヒット : 0                            （PSRAM に到達しない）
 *   読みミス   : (LINE_SIZE × LAT_FILL) − 1   （ライン全体を充填・M-1）
 *   書きヒット : LAT_WR − 1  ★0 ではない★    （ライトスルー・M-2）
 *   書きミス   : LAT_WR − 1                   （ノーライトアロケート・M-2）
 *
 * ★書きのヒット判定は課金額に影響しない。タグ更新の要否にのみ関係する★
 * ★16bit は呼出側がバイトごとに 2 回呼ぶ。本関数は 1 バイトだけを見る（C-7）★ */
static unsigned mem_charge(uint32_t pa, acc_kind_t kind)
{
    unsigned idx, add;
    uint32_t tag;
    int hit, is_write;

    /* ★R1 死守: 既定経路は一切の処理をせず即 0（v2.00 と完全同一）★ */
    if (!cache_enable) return 0;

    /* --- インデックスとタグ（§5.5） --- */
    idx = (unsigned)((pa >> cache_line_shift) & cache_idx_mask);
    tag = pa >> (cache_line_shift + __builtin_ctz(cache_idx_mask + 1));

    hit = (cache_valid[idx] && cache_tag[idx] == tag);
    is_write = (kind == ACC_WR8 || kind == ACC_WR16);

    /* --- 4 分岐課金（§3.2.2） --- */
    if (is_write) {
        /* ★ライトスルー: ヒット・ミスによらず PSRAM へ到達する（M-2）★
         * §3.3 に従い種別ごとの LAT を用いる（WR16 は1バイトあたりの値） */
        add = lat[kind] - 1;
        /* ノーライトアロケート: ミス時にラインを確保しない。
         * ヒット時はキャッシュ側も更新されるがタグは既に一致している。 */
    } else {
        if (hit) {
            add = 0;                        /* 読みヒットは PSRAM に到達しない */
        } else {
            /* ★M-1: ライン全体を充填する。クリティカルワードファースト無し★ */
            add = (cache_line * lat[LAT_FILL_IDX]) - 1;
            cache_valid[idx] = 1;           /* 充填したので有効化 */
            cache_tag[idx]   = tag;
        }
    }

    if (hit) stat_hit++; else stat_miss++;

    /* --- トレース出力（段5 で書式確定・ここでは行のみ出す） --- */
    if (trace_fp) {
        char k = (kind == ACC_FETCH) ? 'F' : (is_write ? 'W' : 'R');
        fprintf(trace_fp, "%llu,0x%05X,%c,%d\n",
                (unsigned long long)cpu.cycle, pa, k, hit);
    }

    /* ★課金の積算は本関数の一箇所のみ（kaizen: 変更箇所を一か所に集約）★
     * charge_enable==0 のときは判定・記録のみで cycle を動かさない（C-9） */
    if (!charge_enable) return 0;
    stat_charged += add;
    cpu.cycle += add;
    return add;
}

/* 1命令分の cycle 歩進量を返す (設計書 §4.2)
 * ★mc_enable==0 なら表を一切参照せず即 1 を返す (R1 死守)★
 * ★+1 (S_IRQCHK) の加算は本関数の return 一箇所のみ★ */
static unsigned mc_step(void)
{
    uint16_t cpi;

    if (!mc_enable) return 1;          /* ←既定経路。従来と完全同一 */

    if (cpu.ir == 0x1F) {
        /* ★実行部(case 0x1F)と同じ fetch8 経路で peek。pc は進めない★
         * mem[] 直読は MMU 有効時に実行部と異なるバイトを読むため不可 (§4.2) */
        uint8_t sub = fetch8(cpu.pc);
        cpi = mc_table_ext[sub];       /* ★0x1F 分を内包した総CPI。mc_table[0x1F]は足さない★ */
        if (cpi == MC_UNDEF) {
            if (!mc_warned_ext) {
                mc_warned_ext = 1;
                fprintf(stderr,
                    "emu23: [-mc] no cycle entry for ext opcode 0x%02X, using default %d\n",
                    sub, MC_DEFAULT_CPI);
            }
            cpi = MC_DEFAULT_CPI;
        }
    } else {
        cpi = mc_table[cpu.ir];
        if (cpi == MC_UNDEF) {
            if (!mc_warned_main) {
                mc_warned_main = 1;
                fprintf(stderr,
                    "emu23: [-mc] no cycle entry for opcode 0x%02X, using default %d\n",
                    cpu.ir, MC_DEFAULT_CPI);
            }
            cpi = MC_DEFAULT_CPI;
        }
    }
    return (unsigned)cpi + 1;          /* ★+1 = S_IRQCHK (§3.1)。IRQ側は -1 で符号が逆★ */
}

/* サイクル定義ファイルの読込 (設計書 §6)
 *   形式: '#'=コメント / 空行無視 / "<キー> <CPI>"
 *   キー: 0xNN=主opcode  X:0xNN=0x1Fサブオペ  IRQ=割込受理
 *   ★デフォルト表への差分上書き方式。記載しなかったキーは既定値を保持★
 *   ★0x1F キーはエラー（EXTプリフィックス分は X:0xNN 側に内包済=二重計上防止, §6.5）★
 * 戻り値: 0=成功。ファイルが開けない場合は呼出側で exit(1)（§6.4） */
static int mc_load_file(const char *path)
{
    FILE *fp = fopen(path, "r");
    if (!fp) {
        fprintf(stderr, "emu23: [-mc] cannot open cycle definition file: %s\n", path);
        return -1;                     /* ★黙殺しない（EMU-A の教訓）★ */
    }

    char line[256];
    int  lineno = 0;
    while (fgets(line, sizeof(line), fp)) {
        lineno++;
        char *p = line;
        while (*p == ' ' || *p == '\t') p++;
        if (*p == '#' || *p == '\n' || *p == '\r' || *p == '\0') continue;

        char key[64];
        long val;
        char extra_ch;
        int  n = sscanf(p, "%63s %li %c", key, &val, &extra_ch);
        if (n < 2) {
            fprintf(stderr, "emu23: [-mc] malformed line %d in %s\n", lineno, path);
            continue;
        }
        if (val <= 0 || val > MC_CPI_MAX) {
            fprintf(stderr, "emu23: [-mc] CPI out of range (1..%d) at line %d\n",
                    MC_CPI_MAX, lineno);
            continue;
        }

        if (strcmp(key, "IRQ") == 0) {
            mc_irq_accept = (uint16_t)val;      /* IRQCHK込みの値（§3.1.1） */
            continue;
        }

        if (key[0] == 'X' && key[1] == ':') {   /* 拡張命令: X:0xNN */
            long sub = strtol(key + 2, NULL, 0);
            if (sub < 0 || sub > 0xFF) {
                fprintf(stderr, "emu23: [-mc] bad ext opcode '%s' at line %d\n", key, lineno);
                continue;
            }
            mc_table_ext[sub] = (uint16_t)val;
            continue;
        }

        /* 主 opcode: 0xNN */
        long op = strtol(key, NULL, 0);
        if (op < 0 || op > 0xFF) {
            fprintf(stderr, "emu23: [-mc] bad opcode '%s' at line %d\n", key, lineno);
            continue;
        }
        /* ★§6.5: 0x1F は EXT プリフィックス。指定を許すと二重計上になるためエラー★ */
        if (op == 0x1F) {
            fprintf(stderr,
                "emu23: [-mc] opcode 0x1F is the EXT prefix; use 'X:0xNN' form (line %d)\n",
                lineno);
            continue;
        }
        /* §6.6: デフォルト表に無いキーは警告するが格納はする */
        if (mc_table[op] == MC_UNDEF) {
            fprintf(stderr,
                "emu23: [-mc] opcode 0x%02lX is not in the default table; "
                "entry stored but may never be used (line %d)\n", op, lineno);
        }
        mc_table[op] = (uint16_t)val;
    }
    fclose(fp);
    return 0;
}

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

/* [v1.10 V5] TCR bit5(IRQ_ACK)書込時: PERIOD設定値で次回発火サイクルを再設定 */
/* 旧名 YSD8002_iret (v1.09以前): IRET命令から呼ばれていた。                  */
/* 再武装契機がIRET命令→ハンドラのACK書込に変わったため rearm に改名。        */
static void YSD8002_rearm(uint64_t current_cycle) {
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
/* [v1.10 V5] timer_in_service を廃止。                                      */
/* 旧(v1.07 Step8-I): IRET命令をフックしてタイマーを再武装していた。          */
/* しかしIRET再武装はFPGA実装不能（CPUからiret_pulse_oを引く必要があり、     */
/* MC6809がRTIを外部にブロードキャストしない原則に反する）。                  */
/* v1.10ではTCR bit5(IRQ_ACK)書込を再武装契機とする（MC6840 PTM等の正統形）。*/
/* → 本フラグ・IRET内のYSD8002_iret呼出は不要となり削除。                    */
/* 詳細: v5_design_memo_v0_2.md §3.4 / kaizen 原則73                        */
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

/* ============================================================
 * [v1.09] インタラクティブモード(-it) サポート
 *   設計書: emu23_interactive_mode_design_v1_1.md (EMU23-MOD-004)
 * ============================================================ */

/* --- termios raw mode 制御 --- */
static struct termios it_orig_termios;
static int it_raw_mode_active = 0;

static void it_enable_raw_mode(void) {
    struct termios raw;
    if (tcgetattr(STDIN_FILENO, &it_orig_termios) == -1) return;
    raw = it_orig_termios;
    /* ECHO   : エコーはYUI OS UARTドライバの責務。emu23側は止める
     * ICANON : 行バッファリング解除（1文字単位で読む）
     * ISIG   : Ctrl+C(SIGINT)/Ctrl+Z(SIGTSTP)等をターミナルに奪われず
     *          生バイトとしてUART RXへ渡す */
    raw.c_lflag &= ~(ECHO | ICANON | ISIG);
    /* ★v1.12 TKT-03★ 入力加工を全面停止する（設計書 v1.5 §3.1.1）。
     * ICRNL を落とさないとEnterのCR($0D)がLF($0A)に変換され、
     * YUI OSシェル(SH-READLINE)は$0Dのみを行終端とするため行が確定しない。
     * IXON は ISIG を落とした設計思想(生バイトをUARTへ渡す)との一貫性のため。
     * IGNBRK|BRKINT|PARMRK|ISTRIP|INLCR|IGNCR|ICRNL|IXON は cfmakeraw(3) と
     * 同一集合。INPCK を上乗せしパリティ検査も無効化(バイナリ透過性)。 */
    raw.c_iflag &= ~(IGNBRK | BRKINT | PARMRK | ISTRIP
                     | INLCR | IGNCR | ICRNL | IXON | INPCK);
    raw.c_cc[VMIN]  = 0;   /* 非ブロッキング: 即時returnを許可 */
    raw.c_cc[VTIME] = 0;
    tcsetattr(STDIN_FILENO, TCSANOW, &raw);
    it_raw_mode_active = 1;
}

static void it_disable_raw_mode(void) {
    if (it_raw_mode_active) {
        tcsetattr(STDIN_FILENO, TCSANOW, &it_orig_termios);
        it_raw_mode_active = 0;
    }
}

/* atexit / signal ハンドラ用: raw mode残置を確実に防ぐ */
static void it_cleanup_on_exit(void) {
    it_disable_raw_mode();
}

/* -it モード専用の RX ポーリング。
 * 既存 ysd8001_poll_rx() をベースに 終了検出(Ctrl+D/0x04)のみ追加。
 * 既存 ysd8001_poll_rx() は変更しない（-q/-i 経路を汚さないため）。
 * [v1.09 あ方針] 終了は 0x04(Ctrl+D)検出に一本化。read()==0(真EOF)終了は撤去した。
 *   理由: ①raw mode+ICANON無効の対話端末では Ctrl+D は 0x04 バイトとして読まれ、
 *         真EOF(read==0)は通常発火しない＝対話用途では元々不要。
 *         ②パイプ/リダイレクト供給時に入力流し切りで read==0 が発火し、ブート完了前に
 *         emu23 が即終了してしまい、非対話での自動テスト・検証が不能になる弊害があった。
 *   対話端末の終了手段は 0x04 で確保されるため、撤去しても終了口は失われない。 */
static int it_should_exit = 0;

static void ysd8001_poll_rx_interactive(void) {
    /* オーバーラン回避：既に未読データがある場合はスキップ */
    if (ysd8001.stat & YSD8001_STAT_RX_READY) return;

    unsigned char buf;
    ssize_t n = read(STDIN_FILENO, &buf, 1);

    if (n <= 0) return;  /* n==0(EOF/データ無)・n<0(EAGAIN等): 読めるデータなし。終了はしない */

    if (buf == 0x04) {
        /* raw mode + ICANON無効では Ctrl+D が 0x04 の生バイトとして
         * 読めるため、これを唯一の終了トリガーとする */
        it_should_exit = 1;
        return;
    }

    ysd8001.rx_buf = buf;
    ysd8001.stat |= YSD8001_STAT_RX_READY;
    ysd8004_raise(IRQ_STAT_BIT_UART_RX);
}

/* RXポーリング関数ポインタ。既定は従来の poll_rx（非回帰保証）。
 * -it 指定時のみ main() で interactive 版に差し替える。 */
static void (*poll_rx_fn)(void) = ysd8001_poll_rx;

/* exec_one() から毎サイクル呼ばれる軽量関数 */
static void ysd8001_tick(uint64_t current_cycle) {
    /* RX ポーリング: 256 サイクルに 1 回 */
    if ((current_cycle & 0xFF) == 0) {
        poll_rx_fn();   /* [v1.09] 直接呼び出し→関数ポインタ経由（既定は従来動作） */
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
static int interactive_mode = 0;  /* [v1.09] -it: termios raw modeで対話的UART入出力 */

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

/* ================================================================
 * ★v1.12 B-C-1a-1: MMIOアドレスデコード層
 *   設計書: emu23_device_design_v1_9.md §2.3.4
 *   本段(1a-1)は「完全な非機能変更」である。分類のみ行い、応答・出力は
 *   一切変更しない。差分が出たら分類ロジックそのものの誤りである。
 * ================================================================ */

#define MMIO_BASE      0xFC80   /* MMIO空間下限 (memmap v2.4 §15)          */
                                /* MMIO空間上限は $FFFF (=アドレス空間終端) */

typedef enum {
    MMIO_NOT_IN_SPACE,          /* $FC80未満 = 通常メモリ                  */
    MMIO_MAPPED,                /* 実装済レジスタ・当該アクセス幅で対応     */
    MMIO_MAPPED_UNSUPPORTED,    /* 実装済だが当該アクセス幅では未対応       */
    MMIO_UNMAPPED               /* 未接続                                  */
} mmio_class_t;

/* アドレス1バイトを分類する純関数（副作用を持たせないこと）。
 *   size = そのCPUアクセスの幅(1 or 2)。分類対象バイトの幅ではない。
 *          16bitアクセスでは上位/下位バイトの双方に size=2 を渡す。
 *          （設計書 §2.3.4(3-b)。この定義を誤ると $FC86 UART_BAUD の
 *            正常な16bitアクセスが UNSUPPORTED に誤分類され退行する）
 * 注: MMUレジスタはバイト粒度（$FF00-$FF0F=PTR[0..15], $FF10=MCR）であり
 *     16bitスロット規則の適用対象外（設計書 §2.3.4(6-ex)）。
 */
static mmio_class_t mmio_classify(uint16_t addr, int size) {
    if (addr < MMIO_BASE) return MMIO_NOT_IN_SPACE;

    /* --- MMUレジスタファイル: バイト粒度・スロット規則の適用外 --- */
    if (addr >= MMU_PTR_BASE && addr <= MMU_MCR_ADDR) {
        return MMIO_MAPPED;     /* --mmu の有無によらず常にデバイス応答 */
    }

    /* --- 16bitスロット規則: 偶数アドレス起点の2バイトを1レジスタとする --- */
    {
        uint16_t slot = (uint16_t)(addr & (uint16_t)~1u);  /* スロット先頭 */

        /* YSD8001 UART: $FC80-$FC86 */
        if (slot == UART_TX || slot == UART_RX || slot == UART_STAT)
            return MMIO_MAPPED;
        if (slot == UART_BAUD) {
            /* 16bitアクセスのみサポート（ysd8001_uart_design_v1_2 L166）。
             * 8bitアクセスは「実装済だが当該幅で未対応」= 第4状態。      */
            return (size == 2) ? MMIO_MAPPED : MMIO_MAPPED_UNSUPPORTED;
        }
        /* YSD8002 タイマー: $FC90-$FC9E */
        if (slot >= TCR_ADDR && slot <= SCORE_HI)
            return MMIO_MAPPED;
        /* YSD8003 ストレージ: $FCA0-$FCB0 */
        if (slot >= SD_CMD_ADDR && slot <= SD_DISK_HI)
            return MMIO_MAPPED;
        /* YSD8004 割り込みコントローラ: $FCB2-$FCB4 */
        if (slot == IRQ_STAT_ADDR || slot == IRQ_MASK_ADDR)
            return MMIO_MAPPED;
    }
    return MMIO_UNMAPPED;
}

/* --- 段階制御フラグ（設計書 §2.3.4(3) 段階ガード・§12.2 状態遷移） ---
 *  1a-1: 全て0（完全な非機能変更）
 *  1a-2: mmio_unsup_zero=1（UNSUPPORTEDに$00応答。警告とは性格が異なるため
 *        段階ガードの対象外＝1a-2での唯一の意図的挙動変更）
 *  1b  : mmio_warn_enabled=1, bus_pullup_enabled は --bus-pullup で1
 *  1b  : --strict-mmio 指定で mmio_strict=1（プルアップの有無とは独立）    */
static int mmio_warn_enabled   = 1;  /* ★B-C-2で既定有効化（α警告・§4.3.2）*/
static int bus_pullup_enabled  = 1;  /* ★B-C-2で既定切替（§4.2.2 プルアップ）*/
static int mmio_unsup_zero     = 1;  /* ★B-C-1a-2で有効化（設計書 §2.3.4(3)注記）*/
static int mmio_strict         = 0;

/* 未接続/幅未対応の計数（§4.3.3: 打切り後も計数は継続する） */
static unsigned long mmio_cnt_unmapped = 0;
static unsigned long mmio_cnt_unsup    = 0;

/* --- 警告抑制機構（設計書 §4.3.3）---
 *  ・同一PCからの警告は初回のみ出力
 *  ・上限 MMIO_WARN_MAX=16 件で打切り（計数は継続）
 *  ・終了時に総件数サマリ（quiet_modeでも抑制しない・0件でも出力） */
#define MMIO_WARN_MAX 16
static uint16_t mmio_warn_pc[MMIO_WARN_MAX];
static int      mmio_warn_pc_n  = 0;
static int      mmio_warn_shown = 0;

/* 同一PCが既報告か（未報告ならtrueを返し記録する） */
static int mmio_warn_first_by_pc(uint16_t pc) {
    for (int i = 0; i < mmio_warn_pc_n; i++)
        if (mmio_warn_pc[i] == pc) return 0;
    if (mmio_warn_pc_n < MMIO_WARN_MAX) mmio_warn_pc[mmio_warn_pc_n++] = pc;
    return 1;
}

/* 警告1行を出力する共通処理。書式は設計書 §12.10（区切りはスペース1個固定） */
static void mmio_warn_emit(const char *tag, uint16_t addr, int is_write,
                           int size, unsigned val) {
    if (!mmio_warn_first_by_pc(cpu.pc)) return;
    if (mmio_warn_shown >= MMIO_WARN_MAX) return;
    if (is_write)
        fprintf(stderr, "[%s] wr%d addr=%04X pc=%04X val=%0*X\n",
                tag, size * 8, addr, cpu.pc, size * 2, val);
    else
        fprintf(stderr, "[%s] rd%d addr=%04X pc=%04X\n",
                tag, size * 8, addr, cpu.pc);
    if (++mmio_warn_shown == MMIO_WARN_MAX)
        fprintf(stderr, "[%s] suppressed after %d reports\n", tag, MMIO_WARN_MAX);
}

static void mmio_report_unmapped(uint16_t addr, int is_write, int size, unsigned val) {
    mmio_cnt_unmapped++;
    if (mmio_warn_enabled) mmio_warn_emit("MMIO-UNMAPPED", addr, is_write, size, val);
    if (mmio_strict) {
        fprintf(stderr,
                "[MMIO-STRICT] unmapped access addr=%04X pc=%04X %s%d -> abort\n",
                addr, cpu.pc, is_write ? "wr" : "rd", size * 8);
        exit(2);
    }
}
static void mmio_report_unsup(uint16_t addr, int is_write, int size, unsigned val) {
    mmio_cnt_unsup++;
    if (mmio_warn_enabled) mmio_warn_emit("MMIO-UNSUP", addr, is_write, size, val);
    if (mmio_strict) {
        fprintf(stderr,
                "[MMIO-STRICT] width-unsupported access addr=%04X pc=%04X -> abort\n",
                addr, cpu.pc);
        exit(2);
    }
}

/* 終了時サマリ（§4.3.3: quiet_modeでも抑制しない・0件でも必ず出力） */
static void mmio_report_summary(void) {
    fprintf(stderr, "[MMIO-SUMMARY] unmapped=%lu unsup=%lu\n",
            mmio_cnt_unmapped, mmio_cnt_unsup);
}

uint16_t rd16(uint16_t a) {
    if (a & 1) {
        printf("!! ALIGNMENT EXCEPTION (READ) @%04x\n", a);
        cpu.irq_pending = 3;  // align = IRQ id 3
        return 0;             // do NOT read, return dummy
    }
    /* ★v1.12 B-C-1a-1: デコード層（設計書 §2.3.4(3-b)）
     * バイト粒度で2回分類する。size は「CPUアクセス幅」=2 を両バイトに渡す。
     * （size=1 を渡すと $FC86 UART_BAUD の正常な16bitアクセスが
     *   UNSUPPORTED に誤分類され退行する。設計書 §2.3.4(3-b) 参照） */
    {
        mmio_class_t c_lo = mmio_classify(a, 2);
        mmio_class_t c_hi = mmio_classify((uint16_t)(a + 1), 2);
        if (c_lo == MMIO_UNMAPPED && c_hi == MMIO_UNMAPPED) {
            if (mmio_warn_enabled) mmio_report_unmapped(a, 0, 2, 0);
            if (bus_pullup_enabled) return 0xFFFF;   /* ★1bで有効化 */
        } else if (c_lo != c_hi && bus_pullup_enabled) {
            /* ★v1.12 B-C-1b: 部分ヒットはバイトごとに解決して合成
             * （設計書 §2.3.4(5)）。例: MCR($FF10)は下位=MAPPED/
             *  上位($FF11)=UNMAPPED → mcr | $FF00 を返す。 */
            uint8_t lo, hi;
            if (c_lo == MMIO_UNMAPPED) {
                if (mmio_warn_enabled) mmio_report_unmapped(a, 0, 1, 0);
                lo = 0xFF;
            } else {
                lo = rd8(a);
            }
            if (c_hi == MMIO_UNMAPPED) {
                if (mmio_warn_enabled)
                    mmio_report_unmapped((uint16_t)(a + 1), 0, 1, 0);
                hi = 0xFF;
            } else {
                hi = rd8((uint16_t)(a + 1));
            }
            return (uint16_t)(lo | ((uint16_t)hi << 8));
        }
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

    /* MMUレジスタ読み出し (16bitは各バイトをrd8委譲)
     * ★v1.12 B-C-1a-3: --mmu 非依存化（§4.1 注記） */
    if (a >= MMU_PTR_BASE && a <= MMU_MCR_ADDR) {
        return (uint16_t)rd8(a) | ((uint16_t)rd8((uint16_t)(a + 1)) << 8);
    }
    /* 通常メモリ: MMU変換 (非mmu時は恒等写像=mem[]直). ページ境界またぎは各バイト独立変換 */
    {
        /* ★KY56: pa を束縛して変換1回★
         * ★C-7: ライン境界を跨ぎうるためバイトごとに2回課金する★ */
        uint32_t pa_lo = mmu_translate(a);
        uint32_t pa_hi = mmu_translate((uint16_t)(a + 1));
        mem_charge(pa_lo, ACC_RD16);
        mem_charge(pa_hi, ACC_RD16);
        uint8_t lo = phys_rd8(pa_lo);
        uint8_t hi = phys_rd8(pa_hi);
        return (uint16_t)(lo | ((uint16_t)hi << 8));
    }
}

void wr16(uint16_t a, uint16_t v) {
    if (a & 1) {
        printf("!! ALIGNMENT EXCEPTION (WRITE) @%04x\n", a);
        cpu.irq_pending = 3;
        return;
    }
    /* ★v1.12 B-C-1a-1: デコード層（設計書 §2.3.4(3-b)） */
    {
        mmio_class_t c_lo = mmio_classify(a, 2);
        mmio_class_t c_hi = mmio_classify((uint16_t)(a + 1), 2);
        if (c_lo == MMIO_UNMAPPED && c_hi == MMIO_UNMAPPED) {
            if (mmio_warn_enabled) mmio_report_unmapped(a, 1, 2, v);
            if (bus_pullup_enabled) return;   /* 書込を捨てる（★1b） */
        }
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
        ysd8002.tcr = (uint8_t)(v & 0x37);  /* [v1.10 V5] bit0,1,2,4,5 有効 (0x17→0x37) */
        /* [v1.11 EN是正] 発火EN条件をOR→AND化（案B）。                       */
        /* TIMER_EN(bit0) かつ IRQ_EN(bit1) の両方が1のときだけ発火許可。      */
        /* これでIRQ_EN=0が名前どおり「割込マスク」として機能する（契約回復）。*/
        /* ★将来課題(案A): TIMER_EN=0でのカウンタ停止は未実装（発火のみ抑止）。*/
        /*   詳細は v6_en_fix_design_memo_v0_1.md §3 / ysd8002_timer_design。 */
        ysd8002.irq_enabled = ((ysd8002.tcr & 0x01) && (ysd8002.tcr & 0x02)) ? 1 : 0;
        /* [v1.10 V5] IRQ_ACK (bit5): タイマー割込ACK＋再武装。書込のみ・自動クリア。 */
        /* YSD8002_tickは発火時にnext_irq_cycle=UINT64_MAXで自己武装解除するため、    */
        /* ハンドラがここを叩かない限り二度と発火しない（MC6840 PTM等と同じ作法）。   */
        /* ★1割込につき1回だけ書くこと（複数回書くと周期がずれる）★                 */
        if (v & 0x20) {
            YSD8002_rearm(cpu.cycle);   /* 次回タイマー発火サイクルを再設定 */
            ysd8002.tcr &= (uint8_t)~0x20;  /* 自動クリア（読出時は常に0） */
        }
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

    /* MMUレジスタ書き込み (16bitは各バイトをwr8委譲)
     * ★v1.12 B-C-1a-3: --mmu 非依存化（§4.1 注記） */
    if (a >= MMU_PTR_BASE && a <= MMU_MCR_ADDR) {
        wr8(a,                (uint8_t)(v & 0xFF));
        wr8((uint16_t)(a + 1),(uint8_t)(v >> 8));
        return;
    }
    /* 通常メモリ: MMU変換 (非mmu時は恒等写像=mem[]直). ページ境界またぎは各バイト独立変換 */
    {
        /* ★KY56: pa を束縛して変換1回★
         * ★C-7: ライン境界を跨ぎうるためバイトごとに2回課金する★ */
        uint32_t pa_lo = mmu_translate(a);
        uint32_t pa_hi = mmu_translate((uint16_t)(a + 1));
        mem_charge(pa_lo, ACC_WR16);
        mem_charge(pa_hi, ACC_WR16);
        phys_wr8(pa_lo, (uint8_t)(v & 0xFF));
        phys_wr8(pa_hi, (uint8_t)(v >> 8));
    }
}

uint8_t rd8(uint16_t a) {
    /* ★v1.12 B-C-1a-1: デコード層（設計書 §2.3.4(3)）
     * 本段は「完全な非機能変更」。全分岐が既存経路へ抜ける。
     * 1a-2 で UNSUPPORTED の $00 応答を、1b で警告とプルアップを有効化する。 */
    switch (mmio_classify(a, 1)) {
    case MMIO_NOT_IN_SPACE:
        break;                      /* 従来どおり下へ抜ける */
    case MMIO_MAPPED:
        break;                      /* 既存のifチェーンに処理させる */
    case MMIO_MAPPED_UNSUPPORTED:
        if (mmio_warn_enabled) mmio_report_unsup(a, 0, 1, 0);
        if (mmio_unsup_zero) return 0x00;   /* ★1a-2で有効化 */
        break;                      /* 1a-1時点: 従来どおりフォールスルー */
    case MMIO_UNMAPPED:
        if (mmio_warn_enabled) mmio_report_unmapped(a, 0, 1, 0);
        if (bus_pullup_enabled) return 0xFF;  /* ★1bで有効化 */
        break;                      /* 1a-1時点: 従来どおりフォールスルー */
    }

    /* ★v1.12 B-C-1a-2: 8bitアクセス経路の被覆漏れ解消（設計書 §4.4）
     * 16bitスロットの該当バイトを返す。偶数=下位/奇数=上位（リトルエンディアン）。
     * 副作用は「下位バイト読出時のみ発動」（§4.4.3 / 全数一覧は §4.4.3.2）。 */
    {
        uint16_t slot = (uint16_t)(a & (uint16_t)~1u);
        int      hi   = (int)(a & 1);
        uint16_t val;
        int      hit  = 1;

        switch (slot) {
        /* --- YSD8002 タイマー（v1.11では8bit未処理だった8本） --- */
        case TCR_ADDR: {
            uint8_t tcr = ysd8002.tcr & 0x03;
            if (ysd8002.sw_busy) tcr |= 0x10;
            val = (uint16_t)tcr;
            break;
        }
        case PERIOD_HI: val = (uint16_t)(ysd8002.period >> 16); break;
        case PERIOD_LO: val = (uint16_t)(ysd8002.period & 0xFFFF); break;
        case CYCLE_LO:
            /* ★副作用: 下位バイト読出時のみラッチ（§4.4.3.2） */
            if (!hi) ysd8002.cycle_hi_latch = cpu.cycle >> 16;
            val = (uint16_t)(cpu.cycle & 0xFFFF);
            break;
        case CYCLE_HI:  val = (uint16_t)(ysd8002.cycle_hi_latch & 0xFFFF); break;
        case SW_RUNS_ADDR: val = ysd8002.sw_runs; break;
        case SCORE_LO:
            /* ★副作用: 下位バイト読出時のみラッチ（§4.4.3.2） */
            if (!hi) ysd8002.score_hi_latch = ysd8002.score >> 16;
            val = (uint16_t)(ysd8002.score & 0xFFFF);
            break;
        case SCORE_HI:  val = (uint16_t)(ysd8002.score_hi_latch & 0xFFFF); break;
        /* --- YSD8003 ストレージ（8bit未処理だった7本。SD_DATAは既存処理） --- */
        case SD_STAT_ADDR:
            /* ★副作用: 下位バイト読出時のみBUSYラッチをクリア（§4.4.3.2） */
            if (!hi && sd_busy_latch) { sd_busy_latch = 0; val = 0x0001; }
            else if (!hi)             { val = (uint16_t)sd_stat; }
            else                      { val = sd_busy_latch ? 0x0001
                                              : (uint16_t)sd_stat; }
            break;
        case SD_LBA_LO:   val = (uint16_t)(sd_lba & 0xFFFF); break;
        case SD_LBA_HI:   val = (uint16_t)(sd_lba >> 16); break;
        case SD_BUF_PTR:  val = sd_buf_ptr; break;
        case SD_IRQ_CTRL: val = (uint16_t)sd_irq_ctrl; break;
        case SD_DISK_LO:  val = (uint16_t)(sd_disk_sectors & 0xFFFF); break;
        case SD_DISK_HI:  val = (uint16_t)(sd_disk_sectors >> 16); break;
        /* --- YSD8004 割り込みコントローラ（8bit未処理だった2本） --- */
        case IRQ_STAT_ADDR: val = irq_stat; break;
        case IRQ_MASK_ADDR: val = irq_mask; break;
        case SD_DATA:
            /* $FCAA(下位)は既存処理へ委譲（BUF_PTR++の副作用あり）。
             * $FCAB(上位)は8bit有効レジスタの上位バイト → $00・副作用なし
             * （設計書 §2.3.4(6)）。 */
            if (hi) { val = 0x0000; break; }
            hit = 0; val = 0; break;
        default: hit = 0; val = 0; break;
        }
        if (hit) return (uint8_t)(hi ? (val >> 8) : (val & 0xFF));
    }

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
    /* MMUレジスタ読み出し
     * ★v1.12 B-C-1a-3: --mmu の有無にかかわらず常にデバイス応答する
     *   （設計書 §4.1 注記）。根拠:
     *   ① RTL の hit_ptr/hit_mcr は MCR.EN を参照しない
     *      （ysd8800_mmio_stub_v0_7.sv L237-238）
     *   ② 「MMU無効」はレジスタの不在ではなく MCR bit0=0 という状態
     *      （ysd8800_mmu_v0_1.sv L15）。でなければMCR自身が読めない
     *   ③ --mmu はエミュレータ都合のオプションでありHW構成の記述ではない */
    if (a >= MMU_PTR_BASE && a < (MMU_PTR_BASE + 16))
        return mmu.ptr[a - MMU_PTR_BASE];
    if (a == MMU_MCR_ADDR)
        return mmu.mcr;
    /* ★KY56: pa を束縛して変換1回。ここは MMIO 分岐をすべて抜けた
     *   「通常メモリ」経路であり、課金対象はここだけである（§4.3）★ */
    {
        uint32_t pa = mmu_translate(a);
        mem_charge(pa, ACC_RD8);
        return phys_rd8(pa);
    }
}

void wr8(uint16_t a, uint8_t v) {
    /* ★v1.12 B-C-1a-1: デコード層（設計書 §2.3.4(3)） */
    switch (mmio_classify(a, 1)) {
    case MMIO_NOT_IN_SPACE:
    case MMIO_MAPPED:
        break;
    case MMIO_MAPPED_UNSUPPORTED:
        if (mmio_warn_enabled) mmio_report_unsup(a, 1, 1, v);
        if (mmio_unsup_zero) return;          /* 書込は無視（★1a-2） */
        break;
    case MMIO_UNMAPPED:
        if (mmio_warn_enabled) mmio_report_unmapped(a, 1, 1, v);
        if (bus_pullup_enabled) return;       /* 書込を捨てる（★1b） */
        break;
    }

    /* ★v1.12 B-C-1a-2: 8bit書込の被覆漏れ解消（設計書 §4.4 / §4.4.3.1）
     * 書込副作用は「下位バイト書込時に発動」。ただし IRQ_STAT(W2C) と
     * BUF_PTR(9bit) は上位バイトにも意味がある（§4.4.3.1 の非対称性）。 */
    {
        uint16_t slot = (uint16_t)(a & (uint16_t)~1u);
        int      hi   = (int)(a & 1);

        switch (slot) {
        /* --- YSD8002: 駆動ビットは全て下位バイト → 上位書込は無効 --- */
        case TCR_ADDR:
            if (!hi) wr16(slot, (uint16_t)v);   /* トリガは下位バイトのみ */
            return;
        case PERIOD_HI:
            ysd8002.period = hi ? ((ysd8002.period & ~0xFF000000ULL) | ((uint64_t)v << 24))
                                : ((ysd8002.period & ~0x00FF0000ULL) | ((uint64_t)v << 16));
            return;
        case PERIOD_LO:
            ysd8002.period = hi ? ((ysd8002.period & ~0x0000FF00ULL) | ((uint64_t)v << 8))
                                : ((ysd8002.period & ~0x000000FFULL) | (uint64_t)v);
            return;
        case CYCLE_LO: case CYCLE_HI: case SCORE_LO: case SCORE_HI:
            return;                              /* 読み出し専用 */
        case SW_RUNS_ADDR:
            ysd8002.sw_runs = hi ? (uint16_t)((ysd8002.sw_runs & 0x00FF) | ((uint16_t)v << 8))
                                 : (uint16_t)((ysd8002.sw_runs & 0xFF00) | v);
            return;
        /* --- YSD8003 --- */
        case SD_CMD_ADDR:
            if (!hi) wr16(slot, (uint16_t)v);   /* EXEC起動は下位バイトのみ */
            return;
        case SD_LBA_LO:
            sd_lba = hi ? ((sd_lba & ~0x0000FF00UL) | ((uint32_t)v << 8))
                        : ((sd_lba & ~0x000000FFUL) | (uint32_t)v);
            return;
        case SD_LBA_HI:
            sd_lba = hi ? ((sd_lba & ~0xFF000000UL) | ((uint32_t)v << 24))
                        : ((sd_lba & ~0x00FF0000UL) | ((uint32_t)v << 16));
            return;
        case SD_BUF_PTR:
            /* ★9bit値: 上位バイトにも意味がある（bit8）（§4.4.3.1） */
            sd_buf_ptr = hi ? (uint16_t)((((uint16_t)v << 8) | (sd_buf_ptr & 0x00FF)) & 0x01FF)
                            : (uint16_t)(((sd_buf_ptr & 0x0100) | v) & 0x01FF);
            return;
        case SD_IRQ_CTRL:
            if (!hi) sd_irq_ctrl = (uint8_t)(v & 0x03);
            return;
        case SD_DISK_LO: case SD_DISK_HI:
            return;                              /* 読み出し専用 */
        /* --- YSD8004 --- */
        case IRQ_STAT_ADDR:
            /* ★W2C: 上位バイトにも意味がある。該当バイトのビットのみクリア */
            irq_stat &= (uint16_t)~(hi ? ((uint16_t)v << 8) : (uint16_t)v);
            return;
        case IRQ_MASK_ADDR:
            irq_mask = hi ? (uint16_t)((irq_mask & 0x00FF) | ((uint16_t)v << 8))
                          : (uint16_t)((irq_mask & 0xFF00) | v);
            return;
        case SD_DATA:
            if (hi) return;                      /* 上位バイトは無効（§2.3.4(6)） */
            break;                               /* 下位は既存処理へ委譲 */
        default: break;
        }
    }

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
    /* MMUレジスタ書き込み
     * ★v1.12 B-C-1a-3: --mmu の有無にかかわらず常にデバイス応答（§4.1 注記） */
    if (a >= MMU_PTR_BASE && a < (MMU_PTR_BASE + 16)) {
        mmu.ptr[a - MMU_PTR_BASE] = v;
        return;
    }
    if (a == MMU_MCR_ADDR) { mmu.mcr = v; return; }
    /* ★KY56: pa を束縛して変換1回。MMIO 分岐をすべて抜けた通常メモリ経路★ */
    {
        uint32_t pa = mmu_translate(a);
        mem_charge(pa, ACC_WR8);
        phys_wr8(pa, v);
    }
}

// [FIX BUG-3] fetch16: wrap address at 0xFFFF boundary
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
    size_t got;
    if (mmu_mode) {
        /* MMUモード: 物理メモリ下位へロード (移植元 emu22 v1.10 :538) */
        got = fread(phys_mem, 1, PHYS_MEM_SIZE, f);
    } else {
        got = fread(mem, 1, MEM_SIZE, f);
    }
    if (got == 0) { fprintf(stderr, "%s: empty or read error\n", fn); exit(1); }
    fclose(f);
    if (!quiet_mode)
        printf("Loaded %u bytes from %s%s\n", (unsigned)got, fn,
               mmu_mode ? " (phys)" : "");
}

// [FIX BUG-5] fscanf: %127[^\n] で幅制限追加
static void load_dbg(const char *path, int explicit_spec) {
    FILE *fp = fopen(path, "r");
    /* [v1.13] M-3: 明示指定の失敗は黙殺せず警告（自動導出は従来どおり黙殺） */
    if (!fp) {
        if (explicit_spec)
            fprintf(stderr, "[DBG-NOTFOUND] cannot open dbg file: %s\n", path);
        return;
    }
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

static void load_sym(const char *path, int explicit_spec) {
    FILE *fp = fopen(path, "r");
    /* [v1.13] M-3: 明示指定（--sym / 位置引数）の失敗は黙殺せず警告する。
     * 自動導出(explicit_spec=0)は「無いのが正常」なので従来どおり黙殺。 */
    if (!fp) {
        if (explicit_spec)
            fprintf(stderr, "[SYM-NOTFOUND] cannot open symbol file: %s\n", path);
        return;
    }
    char line[128];
    /* [v1.13] EMU-B: ループを回し切り、格納側で上限判定する。
     *   旧: while (sym_count < MAX_SYM && fgets(...))  → 打切り検出が構造的に不可能だった
     *   新: 超過分を sym_overflow で数え、last_name とともに stderr へ警告する */
    int sym_overflow = 0;
    char last_name[32] = "";
    while (fgets(line, sizeof(line), fp)) {
        char tok1[32], tok2[32];
        if (sscanf(line, "%31s %31s", tok1, tok2) != 2) continue;
        unsigned addr;
        const char *nm = NULL;
        if (isxdigit((unsigned char)tok1[0])) {
            addr = (unsigned)strtoul(tok1, NULL, 16);
            nm = tok2;
        } else if (isxdigit((unsigned char)tok2[0])) {
            addr = (unsigned)strtoul(tok2, NULL, 16);
            nm = tok1;
        } else {
            continue;
        }
        if (sym_count >= MAX_SYM) { sym_overflow++; continue; }
        snprintf(syms[sym_count].name, sizeof(syms[sym_count].name), "%s", nm);
        syms[sym_count].addr = (uint16_t)addr;
        snprintf(last_name, sizeof(last_name), "%s", nm);
        sym_count++;
    }
    fclose(fp);
    if (!quiet_mode) printf("Loaded %d label symbols\n", sym_count);
    /* [v1.13] 打切りは -q でも必ず stderr へ出す（設計書 §5.6）。
     * 警告文言に 'Dhrystones/sec' / 'cycles' / 'P:' を含めないこと（C-1 規約）。 */
    if (sym_overflow > 0) {
        fprintf(stderr,
                "[SYM-TRUNCATED] loaded=%d skipped=%d last=%s (MAX_SYM=%d)"
                " - label BP may be incomplete\n",
                sym_count, sym_overflow, last_name, MAX_SYM);
    }
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

/* --- stack watermark 報告 (-q HALT後 / repl q後 / 打切り後 に呼ぶ。stderr出力でstdout非汚染) --- */
static void wm_report(void) {
    if (!wm_enable) return;
    fprintf(stderr, "[WATERMARK] ---- stack watermark (slot-wise) ----\n");

    /* コールスタック: スロット(tid)別 */
    int call_seen = 0, call_peak = 0, call_peak_tid = -1;
    for (int t = 0; t < 16; t++) {
        if (wm_callsp_slot[t] == 0xFFFF) continue;
        call_seen++;
        uint16_t top = (uint16_t)(WM_CALLSTK_LO + t * 0x80 + 0x7E); /* 偶数化頂上 */
        int depth = (int)(top - wm_callsp_slot[t]) + 2;            /* 使用バイト(空時X=頂上+2規約) */
        if (depth < 0) depth = 0;
        if (depth > call_peak) { call_peak = depth; call_peak_tid = t; }
        fprintf(stderr, "[WATERMARK]   call tid=%2d: min_sp=$%04X  used=%3d/128 B  %s\n",
                t, wm_callsp_slot[t], depth, depth > 128 ? "*** OVER ***" : "ok");
    }
    if (!call_seen)
        fprintf(stderr, "[WATERMARK]   callstk: no SP in $F000-$F7FF observed\n");
    else
        fprintf(stderr, "[WATERMARK]   callstk PEAK: tid=%d  %d/128 B  (%d slots used)\n",
                call_peak_tid, call_peak, call_seen);

    /* データスタック: スロット(tid)別 */
    int data_seen = 0, data_peak = 0, data_peak_tid = -1;
    for (int t = 0; t < 16; t++) {
        if (wm_datax_slot[t] == 0xFFFF) continue;
        data_seen++;
        uint16_t top = (uint16_t)(WM_DATASTK_LO + t * 0x80 + 0x7E);
        int depth = (int)(top - wm_datax_slot[t]) + 2;
        if (depth < 0) depth = 0;
        if (depth > data_peak) { data_peak = depth; data_peak_tid = t; }
        fprintf(stderr, "[WATERMARK]   data tid=%2d: min_x =$%04X  used=%3d/128 B  %s\n",
                t, wm_datax_slot[t], depth, depth > 128 ? "*** OVER ***" : "ok");
    }
    if (!data_seen)
        fprintf(stderr, "[WATERMARK]   datastk: no X in $F800-$FBFF observed\n");
    else
        fprintf(stderr, "[WATERMARK]   datastk PEAK: tid=%d  %d/128 B  (%d slots used)\n",
                data_peak_tid, data_peak, data_seen);

    /* guard: OS設置 $A55A の維持を検査(スタック突き抜け検出) */
    int violated = 0; uint16_t vaddr = 0;
    for (uint16_t a = WM_GUARD_LO; a <= WM_GUARD_HI - 1; a += 2) {
        uint16_t w = (uint16_t)(mem[a] | (mem[(uint16_t)(a + 1)] << 8));
        if (w != WM_GUARD_PAT) { violated = 1; vaddr = a; break; }
    }
    if (violated)
        fprintf(stderr, "[WATERMARK]   guard $FC00-$FC3F: *** VIOLATED at $%04X ***\n", vaddr);
    else
        fprintf(stderr, "[WATERMARK]   guard $FC00-$FC3F: intact ($A55A maintained)\n");
}

void exec_one(void) {
    if (cpu.halted) return;

    uint16_t pc0 = cpu.pc;

    // --- IRQ 受理 (§7.4-7.5) ---
    // 条件: irq_pending >= 0 && IE == 1
    if (cpu.irq_pending >= 0 && (cpu.flags & FL_IE)) {
        int irq = cpu.irq_pending;
        cpu.irq_pending = -1;
        /* [v1.10 V5] timer_in_service 設定を削除（IRET再武装廃止のため） */
        push16(cpu.pc);                // PC を先に push (§7.5)
        push16((uint16_t)cpu.flags);   // FLAGS を後に push
        cpu.flags &= ~FL_IE;           // IE = 0 (WARN-1: irq_en 削除)
        uint16_t vec = rd16((uint16_t)(irq * 2));
        cpu.pc = vec;
        if (!quiet_mode)
            printf("** IRQ %d accepted, vec=%04x **\n", irq, vec);
        /* [v2.00 Phase C] 割込受理サイクル (設計書 §3.1.1 / §5.2)
         * ★表の 9 は S_IRQCHK 込みの値。S_IRQCHK は直後の FETCH で mc_step() が
         *   +1 済みとなるため、ここで 9 を足すと二重計上になる。よって -1 する。★
         * ★命令は +1、IRQ は -1 と補正の符号が逆である点に注意★ */
        if (mc_enable) cpu.cycle += (unsigned)(mc_irq_accept - 1);
        // IRQ 受理後は fetch に進む (PC は既にベクタ先)
    }

    // --- FETCH ---
    cpu.ir = fetch8(cpu.pc++);
    cpu.cycle += mc_step();   // [FIX BUG-6] ここのみインクリメント (case 0x1F 内は削除)
                              // [v2.00 Phase C] mc_enable==0 のとき mc_step()==1 で従来と同一

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
        /* [v1.10 V5] IRET時のタイマー再武装を削除。                        */
        /* 再武装はハンドラがTCR bit5(IRQ_ACK)を書くことで行う（§3.2/§3.4）*/
        /* → ハンドラ側にACK書込が必須。無いとタイマーは二度と発火しない。  */
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
        if (rd && rs) {
            uint16_t val = rd16(*rs);
            *rd = val; set_zn(*rd);
        }
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

    /* --- stack watermark 追跡(スロット別・範囲ガードで誤検出排除・ウォームアップ後) --- */
    if (wm_enable && cpu.cycle >= wm_warmup_cycles) {
        if (cpu.sp >= WM_CALLSTK_LO && cpu.sp <= WM_CALLSTK_HI) {
            int t = (cpu.sp - WM_CALLSTK_LO) / 0x80;
            if (t >= 0 && t < 16 &&
                (wm_callsp_slot[t] == 0xFFFF || cpu.sp < wm_callsp_slot[t]))
                wm_callsp_slot[t] = cpu.sp;
        }
        if (cpu.x >= WM_DATASTK_LO && cpu.x <= WM_DATASTK_HI) {
            int t = (cpu.x - WM_DATASTK_LO) / 0x80;
            if (t >= 0 && t < 16 &&
                (wm_datax_slot[t] == 0xFFFF || cpu.x < wm_datax_slot[t]))
                wm_datax_slot[t] = cpu.x;
        }
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
        //     [v1.14 / B-4 EMU-C] BP停止位置から再開できるよう後置判定(do-while)化。
        //     入口で is_break を見ると停止位置で 0 回ループになり前進しない。
        //     ★BREAK 表示は REPL ループ冒頭が行う。ここでは出さないこと（二重表示）★
        } else if (cmd[0] == 'c') {
            if (cpu.halted) { printf("CPU is halted\n"); continue; }
            do {
                exec_one();
            } while (!cpu.halted && !is_break(cpu.pc));

        // t  — trace (step + dump after each instruction)
        //     [v1.14 / B-4 EMU-C] c と同一の根本原因。後置判定(do-while)化。
        } else if (cmd[0] == 't') {
            if (cpu.halted) { printf("CPU is halted\n"); continue; }
            do {
                exec_one();
                dump_regs();
            } while (!cpu.halted && !is_break(cpu.pc));

        // bd N  — delete breakpoint N
        //   [v1.06 F-001] 'b' より前に判定すること。後ろに置くと
        //   cmd[0]=='b' が "bd" も先取りし、この分岐が不到達になる。
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

        // ===== MMU デバッガコマンド (v1.08移植: emu22 v1.10 :1253-1311) =====
        } else if (strncmp(cmd, "mmu", 3) == 0 && mmu_mode) {
            // mmu / mmu en / mmu dis / mmu ptr N V
            char sub[32] = "";
            sscanf(cmd + 3, " %31s", sub);
            if (sub[0] == '\0') {
                printf("MCR=%02X  MMU %s\n", mmu.mcr,
                       (mmu.mcr & MCR_EN) ? "ENABLED" : "disabled");
                for (int i = 0; i < 16; i++) {
                    printf("  PTR[%2d] = %02X  (log $%04X -> phys $%05X)\n",
                           i, mmu.ptr[i], i << 12,
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
            // physmem <physaddr_hex> [n]
            uint32_t pa = 0; int n = 16;
            sscanf(cmd + 7, " %x %d", &pa, &n);
            pa &= 0xFFFFF;
            printf("PHYSMEM[%05X+%d]:", pa, n);
            for (int i = 0; i < n; i++)
                printf(" %02X", phys_mem[(pa + (uint32_t)i) & 0xFFFFF]);
            printf("\n");

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
    int run_steps = 0;   /* -n N: Nステップ実行してPCトレースを出力して終了 */
    /* watermark スロット配列を未観測(0xFFFF)で初期化 */
    for (int t = 0; t < 16; t++) { wm_callsp_slot[t] = 0xFFFF; wm_datax_slot[t] = 0xFFFF; }
    int trace_from = -1; /* -b ADDR: このアドレス到達後にトレース開始 */

    if (argc < 2) {
        fprintf(stderr,
            "emu23 v2.10 (2026-08-20) for YSD8800 ISA2.3\n"
            "  - v2.10: cache groundwork: memory-access charging + physical\n"
            "           address trace ('--mem-latency', '--trace-addr',\n"
            "           '--cache-stats', '--cache-size', '--cache-line')\n"
            "           default unchanged (improvement-4)\n"
            "  - v2.00: machine-cycle mode '-mc [file]' (per-instruction CPI;\n"
            "           default remains 1 cycle/instr) (Phase C)\n"
            "  - v1.14: REPL 'c'/'t' resume from breakpoint (do-while; was 0-iteration\n"
            "           at BP due to entry-side is_break check) (B-4 EMU-C)\n"
            "  - v1.13: EMU-A argv consume-mark (--dbg/--sym, no more option\n"
            "           misread as .dbg/.sym) + EMU-B MAX_SYM 128->2048\n"
            "           with [SYM-TRUNCATED]/[SYM-NOTFOUND]/[DBG-NOTFOUND]\n"
            "  - v1.12: TKT-03 c_iflag (B-1) + MMIO decode layer, 8bit coverage,\n"
            "           bus-pullup default (B-C, improvement-2)\n"
            "  - v1.11: TCR fire-EN OR->AND (IRQ_EN now masks; plan-B EN fix)\n"
            "  - v1.10: timer re-arm via TCR bit5 IRQ_ACK (IRET auto re-arm removed) (V5)\n"
            "  - v1.09: interactive mode (-it) - termios raw mode, UART RX from keyboard (Step 8)\n"
            "  - v1.08: MMU revival port from emu22 v1.10 (FM-11 16-page MMU, --mmu) (V(-1))\n"
            "  - v1.07: IRQ priority fix - YSD8002_iret only on timer IRQ return (Step 8-I)\n"
            "  - v1.06: REPL 'bd N' breakpoint delete fixed (F-001)\n"
            "  - v1.05: stack watermark 計測機能統合 (-w)\n"
            "  - YSD8003 deferred completion IRQ (delay=512 cycles)\n"
        "  - v1.04: DBG printf removed\n"
            "  - YSD8004 irq_pending overwrite protection + IRQ_STAT re-evaluation\n"
            "usage: emu23 prog.bin [prog.dbg [prog.sym]] [options]\n"
            "  -n N         run N steps and dump trace (non-interactive)\n"
            "  -b ADDR      start tracing after reaching ADDR\n"
            "  -q           quiet: run until HALT, UART output only\n"
            "  -it          interactive: raw terminal mode, UART RX from keyboard,\n"
            "               Ctrl+D (0x04) to exit. No local echo (UART driver's job)\n"
            "  -i FILE      UART RX input file (fed byte by byte)\n"
            "               if omitted, stdin is polled non-blocking\n"
            "  --disk FILE  attach disk image (YSD8003 storage)\n"
            "  --bus-pullup      (default since v1.12) unconnected MMIO reads\n"
            "                    return $FF/$FFFF; writes discarded. Accepted as no-op\n"
            "  --no-bus-pullup   revert to pre-v1.12 fall-through behaviour (roll-back)\n"
            "  --strict-mmio     abort on unconnected MMIO access (independent of\n"
            "                    --bus-pullup)\n"
            "  -w,--watermark    measure per-task stack high-water mark (stderr)\n"
            "  --wm-steps N      step limit for -w on resident OS (default 2000000)\n"
            "  --wm-warmup N     skip first N cycles for -w (default 2000)\n"
            "  prog.dbg and prog.sym are auto-derived from prog.bin if omitted\n"
            "  --dbg <file>          specify .dbg explicitly (overrides argv[2])\n"
            "  --sym <file>          specify .sym explicitly (overrides argv[3])\n"
            "  -mc [file]            machine-cycle mode (default: 1 cycle/instr)\n"
            "                        file: cycle definition (omit to use built-in table)\n"
            "                        note: filenames starting with '-' are not accepted\n"
            "  --mem-latency [N|file]  charge memory access cycles (requires -mc)\n"
            "                        N: same latency for all kinds (omit: built-in 6)\n"
            "                        file: FETCH/RD8/WR8/RD16/WR16/FILL definitions\n"
            "  --trace-addr [file]   emit physical-address trace (omit: stderr)\n"
            "  --cache-stats         count hits/misses only (no trace output)\n"
            "  --cache-size N        cache capacity in bytes, power of 2 (default 16384)\n"
            "  --cache-line N        line size in bytes, power of 2 (default 32)\n");
        return 1;
    }

    /* -q と -i は load_bin / ysd8001_init より前に解析する必要がある */
    for (int i = 2; i < argc; i++) {
        if (strcmp(argv[i], "-q") == 0) quiet_mode = 1;
        if (strcmp(argv[i], "-it") == 0) interactive_mode = 1;  /* [v1.09] */
        /* ★v1.12 B-C-1b: MMIOバス関連オプション（設計書 §12.2 状態遷移表）
         *  --bus-pullup   : 未接続MMIOをプルアップ模倣($FF/$FFFF)にする
         *  --no-bus-pullup: 既定切替(B-C-2)後に従来挙動へ戻す切り戻し手段
         *  --strict-mmio  : 未接続アクセス検出時点で停止（プルアップとは独立）*/
        if (strcmp(argv[i], "--bus-pullup") == 0) {
            /* ★B-C-2以降: 既定で有効のため no-op。互換のため受理し廃止しない */
            bus_pullup_enabled = 1;
            mmio_warn_enabled  = 1;
        }
        if (strcmp(argv[i], "--no-bus-pullup") == 0) bus_pullup_enabled = 0;
        if (strcmp(argv[i], "--strict-mmio") == 0) {
            mmio_strict       = 1;
            mmio_warn_enabled = 1;
        }
        /* --mmu: MMU拡張有効化 (load_binより前に解析: phys_mem確保とロード先分岐のため) */
        if (strcmp(argv[i], "--mmu") == 0) {
            mmu_mode = 1;
            phys_mem = (uint8_t*)malloc(PHYS_MEM_SIZE);
            if (!phys_mem) {
                fprintf(stderr, "emu23: cannot allocate phys_mem (1MB)\n");
                return 1;
            }
            /* FPGA未初期化RAM模擬: $FF初期化 (MMU設計書 v1.1.0 §9) */
            memset(phys_mem, 0xFF, PHYS_MEM_SIZE);
            mmu_reset();   /* 恒等写像・MMU無効で起動 */
        }
        if (strcmp(argv[i], "--watermark") == 0 || strcmp(argv[i], "-w") == 0)
            wm_enable = 1;
        if (strcmp(argv[i], "--wm-steps") == 0 && i+1 < argc)
            wm_max_steps = strtoull(argv[i+1], NULL, 10);
        if (strcmp(argv[i], "--wm-warmup") == 0 && i+1 < argc)
            wm_warmup_cycles = strtoull(argv[i+1], NULL, 10);
        if (strcmp(argv[i], "-i") == 0 && i+1 < argc) {
            FILE *f = fopen(argv[i+1], "rb");
            if (!f) {
                fprintf(stderr, "emu23: cannot open -i file: %s\n", argv[i+1]);
                return 1;
            }
            ysd8001.rx_src = f;  /* ysd8001_init() より前に設定 */
        }
    }

    /* [v1.09] -q と -it の排他チェック・-it セットアップ */
    if (quiet_mode && interactive_mode) {
        fprintf(stderr, "emu23: -q and -it are mutually exclusive\n");
        return 1;
    }
    /* ★v1.12 B-C-1b: MMIOサマリを atexit 登録（設計書 §12.8.3）
     * atexit は「登録と逆順」に実行される。ここで先に登録することで
     * it_cleanup_on_exit（端末復帰）→ サマリ出力 の順になる。
     * raw mode のまま stderr へ出すと改行が \r を伴わず表示が崩れるため
     * この順序は必須である。 */
    atexit(mmio_report_summary);
    /* [v2.10 改良4] キャッシュ統計サマリ（§6.5）
     * ★cache_enable==0 のときは関数内で即 return するため既定では無出力★ */
    atexit(cache_report_summary);

    if (interactive_mode) {
        /* [v1.09 A方針] -it は -q 同様に診断ログ(IRQ accepted等)を抑制する。
         * 対話シェル用途では !quiet_mode ガード下の診断printfが画面を埋め実用不可のため。
         * 排他チェック(上記)はユーザ明示の -q と競合した場合のみ発火し、ここでの
         * 内部セットは排他チェック通過後なので誤発火しない（順序厳守）。
         * 設計書 emu23_interactive_mode_design §2.4 として追記改版。 */
        quiet_mode = 1;
        poll_rx_fn = ysd8001_poll_rx_interactive;  /* RXポーリングを対話版に差替え */
        atexit(it_cleanup_on_exit);                /* raw mode残置を確実に防ぐ */
        signal(SIGTERM, exit);                     /* kill -TERM 時もcleanup経由で復帰 */
        signal(SIGHUP,  exit);
    }

    /* ============================================================
     * [v1.13] EMU-A 前置パス（設計書 emu23_argsym_design_v0_3 §5.2）
     *   目的: オプションおよびその引数を「消費済み」としてマークし、
     *         位置引数(argv[2]/argv[3])の .dbg/.sym 誤認を防ぐ。
     *   ★既存の第1〜第4パスに相乗りしてはならない★
     *     （--disk 以降は位置引数解釈より後に走るため間に合わない）
     *   ★本パスのオプション表が実装の唯一の参照である★
     *     emu23 にオプションを追加したら必ず本表も更新すること。
     *     マーク漏れは「現行と同じ挙動」に落ちるため発見しにくい。
     * ============================================================ */
    unsigned char argv_used[ARGV_MAX] = {0};   /* 0=未消費 1=オプション本体/その引数 */
    const char *dbg_path_opt = NULL;           /* [v1.13] --dbg の値（NULL=未指定） */
    const char *sym_path_opt = NULL;           /* [v1.13] --sym の値（NULL=未指定） */
    const char *mc_file_opt  = NULL;           /* [v2.00] -mc の値（NULL=デフォルト表） */
    /* [v2.10 改良4] キャッシュ下地オプションの受け皿（設計書 §6） */
    const char *lat_arg_opt    = NULL;         /* --mem-latency の値（数値 or ファイル名） */
    const char *trace_path_opt = NULL;         /* --trace-addr の出力先（NULL=stderr） */
    const char *cache_size_opt = NULL;         /* --cache-size の値 */
    const char *cache_line_opt = NULL;         /* --cache-line の値 */
    int lat_opt_seen   = 0;                    /* --mem-latency 指定有無 */
    int trace_opt_seen = 0;                    /* --trace-addr 指定有無 */
    int cache_stats_opt = 0;                   /* --cache-stats 指定有無 */

    /* M-6: 配列外アクセス防止。上限超過は黙って壊れず明示的に弾く */
    if (argc > ARGV_MAX) {
        fprintf(stderr, "emu23: too many arguments (max %d)\n", ARGV_MAX);
        return 1;
    }

    for (int i = 2; i < argc; i++) {
        int extra = -1;                        /* 追加で消費する引数の数 */
        /* --- 追加消費 0（フラグ系）--- */
        if (strcmp(argv[i], "-q")              == 0) extra = 0;
        else if (strcmp(argv[i], "-it")        == 0) extra = 0;
        else if (strcmp(argv[i], "--bus-pullup")    == 0) extra = 0;
        else if (strcmp(argv[i], "--no-bus-pullup") == 0) extra = 0;
        else if (strcmp(argv[i], "--strict-mmio")   == 0) extra = 0;
        else if (strcmp(argv[i], "--mmu")      == 0) extra = 0;
        else if (strcmp(argv[i], "--watermark")== 0) extra = 0;
        else if (strcmp(argv[i], "-w")         == 0) extra = 0;
        /* --- 追加消費 1 --- */
        else if (strcmp(argv[i], "--wm-steps") == 0) extra = 1;
        else if (strcmp(argv[i], "--wm-warmup")== 0) extra = 1;
        else if (strcmp(argv[i], "-i")         == 0) extra = 1;
        else if (strcmp(argv[i], "--disk")     == 0) extra = 1;
        else if (strcmp(argv[i], "-n")         == 0) extra = 1;
        else if (strcmp(argv[i], "-b")         == 0) extra = 1;
        /* --- 追加消費 2 --- */
        else if (strcmp(argv[i], "-m")         == 0) extra = 2;
        /* --- [v1.13] 新設（段3で値を回収する）--- */
        /* --- [v1.13] 新設: 値を回収する。欠落は黙殺せずエラー終了（§5.5）--- */
        else if (strcmp(argv[i], "--dbg")      == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "emu23: option --dbg requires a filename\n");
                return 1;
            }
            dbg_path_opt = argv[i + 1];
            extra = 1;
        }
        else if (strcmp(argv[i], "--sym")      == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "emu23: option --sym requires a filename\n");
                return 1;
            }
            sym_path_opt = argv[i + 1];
            extra = 1;
        }
        /* --- [v2.00 Phase C] -mc : ★引数を取ることも取らないこともある初のオプション★
         *   消費数決定表（設計書 §7.2。★実装の唯一の参照★）
         *     i+1 >= argc            → extra=0 : デフォルト表
         *     argv[i+1][0] == '-'    → extra=0 : デフォルト表
         *     上記以外               → extra=1 : argv[i+1] をファイル名として採用
         *   ★access() で判定しないこと★
         *     タイプミスしたファイル名が黙ってデフォルト動作に落ちる（EMU-A と同じ病）。
         *     '-' 始まりでない以上ファイル名として扱い、開けなければ exit(1)（§6.4）。
         *   既知の制限: '-' で始まるファイル名は指定できない（§7.2・マニュアル記載）*/
        else if (strcmp(argv[i], "-mc")        == 0) {
            mc_enable = 1;
            if (i + 1 < argc && argv[i + 1][0] != '-') {
                mc_file_opt = argv[i + 1];
                extra = 1;
            } else {
                extra = 0;                     /* デフォルト表を使用 */
            }
        }

        /* ===== [v2.10 改良4] キャッシュ下地オプション（設計書 §6.7）=====
         * ★消費数表に載せること自体が、位置引数へのサイレント消費を防ぐ★
         *   （未登録だと extra=-1 → continue となり、argv[2]/argv[3] の
         *     .dbg/.sym パスとして黙って解釈されてしまう＝EMU-A と同型） */
        else if (strcmp(argv[i], "--mem-latency") == 0) {
            cache_enable = 1;                  /* §6.6 */
            lat_opt_seen = 1;
            if (i + 1 < argc && argv[i + 1][0] != '-') {
                lat_arg_opt = argv[i + 1];
                extra = 1;
            } else {
                extra = 0;                     /* 引数省略 = 既定値(全種別6)を使用 */
            }
        }
        else if (strcmp(argv[i], "--trace-addr") == 0) {
            cache_enable = 1;                  /* §6.6 */
            trace_opt_seen = 1;
            if (i + 1 < argc && argv[i + 1][0] != '-') {
                trace_path_opt = argv[i + 1];
                extra = 1;
            } else {
                extra = 0;                     /* 省略時は stderr（§6.2） */
            }
        }
        else if (strcmp(argv[i], "--cache-stats") == 0) {
            cache_enable = 1;                  /* §6.6 */
            cache_stats_opt = 1;
            extra = 0;                         /* 単独フラグ（§6.3） */
        }
        /* ★固定1: 引数欠落時に次のオプションを値と誤読してはならない（§6.7）★ */
        else if (strcmp(argv[i], "--cache-size") == 0) {
            if (i + 1 >= argc || argv[i + 1][0] == '-') {
                fprintf(stderr, "emu23: --cache-size requires a numeric argument\n");
                return 1;
            }
            cache_size_opt = argv[i + 1];
            extra = 1;
        }
        else if (strcmp(argv[i], "--cache-line") == 0) {
            if (i + 1 >= argc || argv[i + 1][0] == '-') {
                fprintf(stderr, "emu23: --cache-line requires a numeric argument\n");
                return 1;
            }
            cache_line_opt = argv[i + 1];
            extra = 1;
        }

        if (extra < 0) continue;               /* オプションでない = 位置引数候補 */
        argv_used[i] = 1;                      /* オプション本体 */
        for (int k = 1; k <= extra && i + k < argc; k++)
            argv_used[i + k] = 1;              /* その引数 */
        i += extra;                            /* 引数はオプション名として再評価しない */
    }

    load_bin(argv[1]);

    /* [v2.00 Phase C] マシンサイクル表の初期化（設計書 §7.3）
     * ★mc_enable の有無にかかわらず初期化する（-mc 無しでも mc_step() は表を見ないが、
     *   未初期化配列の参照を構造的に排除するため）★ */
    mc_init_default_table();
    if (mc_file_opt) {
        if (mc_load_file(mc_file_opt) != 0) return 1;   /* ★開けなければ exit(1)（§6.4）★ */
    }

    /* ===== [v2.10 改良4] キャッシュ下地オプションの適用（設計書 §6.4/§6.6）===== */
    {
        char *endp;
        if (cache_size_opt) {
            unsigned long v = strtoul(cache_size_opt, &endp, 0);
            if (*endp != '\0' || v == 0) {
                fprintf(stderr, "emu23: invalid --cache-size value: %s\n", cache_size_opt);
                return 1;
            }
            cache_size = (unsigned)v;
        }
        if (cache_line_opt) {
            unsigned long v = strtoul(cache_line_opt, &endp, 0);
            if (*endp != '\0' || v == 0) {
                fprintf(stderr, "emu23: invalid --cache-line value: %s\n", cache_line_opt);
                return 1;
            }
            cache_line = (unsigned)v;
        }
        /* ★2の冪検査・配列確保。--cache-size/--cache-line 単独では
         *   cache_enable は立たない（§6.4）ので挙動は v2.00 と同一★ */
        if (cache_config_init() != 0) return 1;

        /* --mem-latency の値解釈（数値＝全種別一律 / それ以外＝定義ファイル） */
        if (lat_arg_opt) {
            unsigned long v = strtoul(lat_arg_opt, &endp, 0);
            if (*endp == '\0') {
                for (int k = 0; k < 6; k++) lat[k] = (unsigned)v;
            } else {
                lat_file_opt = lat_arg_opt;    /* 定義ファイルとして読む */
            }
        }
        /* ★ヘッダ出力より前に読むこと（ヘッダに lat 値を刻むため・順序依存）★ */
        if (lat_file_opt) {
            if (lat_load_file(lat_file_opt) != 0) return 1;
        }

        /* ★併用規則（§6.6）：課金は -mc とセットのときだけ有効★ */
        if (lat_opt_seen && !mc_enable) {
            fprintf(stderr,
                    "[CACHE] --mem-latency requires -mc; charging disabled\n");
            charge_enable = 0;
        } else if (lat_opt_seen) {
            charge_enable = 1;
        }

        /* トレース出力先の確定（§6.2）
         * ★--cache-stats 併用時はファイルを「開かない」★
         *   （開いてから閉じると空ファイルが残る副作用が生じるため） */
        if (trace_opt_seen && cache_stats_opt) {
            fprintf(stderr,
                    "[CACHE] --cache-stats given; trace output suppressed\n");
        } else if (trace_opt_seen) {
            if (trace_path_opt) {
                trace_fp = fopen(trace_path_opt, "w");
                if (!trace_fp) {
                    fprintf(stderr, "emu23: cannot open trace file: %s\n", trace_path_opt);
                    return 1;
                }
            } else {
                trace_fp = stderr;
            }
            /* ★先頭に必ずヘッダ行を出す（§6.2）★
             *   -mc / lat / cache 構成の確定後に呼ぶこと（順序依存） */
            trace_write_header();
        }
        /* （--cache-stats の抑止はトレース先確定の分岐で処理済み） */
    }

    // [FIX WARN-2] change_ext にバッファを渡す
    char extbuf[256];

    /* [v1.13] EMU-A: 位置引数は「未消費」の場合のみ .dbg/.sym として解釈する。
     *   未消費   → argv[2]/argv[3] を採用（従来と完全同一＝群α保護）
     *   消費済み → change_ext() 自動導出（★EMU-A 解消★）
     * 注: 自動導出の fopen 失敗は従来どおり黙殺（存在しないのが正常なため）。 */
    /* [v1.13] EMU-A: §5.1 決定表
     *   --dbg/--sym 指定あり → その値を採用（最優先・明示指定）
     *   未指定 かつ 位置引数が未消費 → argv[2]/argv[3]（従来と完全同一＝群α保護）
     *   それ以外 → change_ext() 自動導出（★EMU-A 解消★）
     * 第2引数 explicit_spec: 1=明示指定（失敗を警告）/ 0=自動導出（失敗は黙殺） */
    if (dbg_path_opt) {
        load_dbg(dbg_path_opt, 1);
    } else if (argc >= 3 && !argv_used[2]) {
        load_dbg(argv[2], 1);
    } else {
        change_ext(extbuf, sizeof(extbuf), argv[1], ".dbg");
        load_dbg(extbuf, 0);
    }

    if (sym_path_opt) {
        load_sym(sym_path_opt, 1);
    } else if (argc >= 4 && !argv_used[3]) {
        load_sym(argv[3], 1);
    } else {
        change_ext(extbuf, sizeof(extbuf), argv[1], ".sym");
        load_sym(extbuf, 0);
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

    /* -q モード: HALT まで無制限実行、UART出力のみ stdout
     * [v1.09] !interactive_mode を追加。-it は quiet_mode=1 を内部セットするが
     * メインループは下の -it ブロックで回す必要があるため、ここで吸い込まない。
     * -q 単独時は interactive_mode=0 なので従来どおり（非回帰）。 */
    if (quiet_mode && !interactive_mode) {
        uint64_t steps = 0;
        while (!cpu.halted) {
            exec_one();
            if (wm_enable && ++steps >= wm_max_steps) break;  /* 常駐OS打切り */
        }
        fflush(stdout);
        wm_report();
        return 0;
    }

    /* [v1.09] -it モード: 対話的実行。termios raw mode化＋EOF(Ctrl+D)検出。
     * RXポーリングは既に poll_rx_fn=ysd8001_poll_rx_interactive に差替え済み。 */
    if (interactive_mode) {
        it_enable_raw_mode();
        uint64_t steps = 0;
        while (!cpu.halted && !it_should_exit) {
            exec_one();
            if (wm_enable && ++steps >= wm_max_steps) break;  /* 常駐OS打切り */
        }
        it_disable_raw_mode();
        fflush(stdout);
        wm_report();
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

    printf("YSD8800 ISA2.3 Emulator (emu23 v2.10%s) — reset vector = %04x\n",
           mmu_mode ? " +MMU" : "", cpu.pc);
    printf("Type 'help' for commands.\n");

    repl();
    wm_report();
    return 0;
}
