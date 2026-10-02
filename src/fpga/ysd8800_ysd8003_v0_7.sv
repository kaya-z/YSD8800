//==============================================================
// ysd8800_ysd8003_v0_7.sv
//   YSD8003 ストレージコントローラ（SDカード SPIモード読出）本体RTL
//   - 設計メモ: v6a_storage_design_memo_v0_2.md（v0.2・レビュー承認済）
//   - レビュー: v6a_storage_design_review_reply_v1_0.md（案D採用）
//   Version: v0.7 (2026-10-01)  ← TKT-V16(e) review r4.0 F-2 対応（U-15・S-2）
//     v0.7 (2026-10-01 TKT-V16(e) F-2/U-15): S_ERROR で保留EXEC（exec_pending）を破棄する（1行）。
//       従来（v0_4〜v0_6）は、保留EXECがある状態で初期化がERRORになると、S_ERROR→S_IDLE で
//       保留EXECが消化されて CMD17 へ進み、reg_stat が ERROR→READY に上書きされ、かつその CMD17 は
//       タイムアウト監視外（exec_watch 解除済み）だった。OS からは「初期化に失敗したカードの読出しが
//       成功に見える」経路（S-2）。★正常系（初期化成功）には影響しない（S_ERROR は異常時のみ）★
//       ★module 名を v0_6 → v0_7 へ昇格（ファイル名と一致）★
//   （以下は v0.6 時点の記述を保持）
//   Version: v0.6 (2026-09-30)  ← TKT-V16(e) タイムアウト再設計（v26_tktv16_clock_plan_design_v0_3.md §6）
//     v0.6 (2026-09-30 TKT-V16(e)) ★振る舞いを意図的に変える変更（4MHzで正常系は不変・異常系の上限が変わる）★:
//       (1) ACMD41_TMO = CPU_HZ x 1.5（@4MHz=6,000,000）を新設。最初のACMD41発行時に起動する
//           専用の時間ベースタイマ。規格（SDPLS §4.2.3）: 最初のACMD41から1秒以内に初期化完了。
//           反復判定点（R1=0x01受信時）で ACMD41_TMO 超過ならS_ERROR。
//       (2) ACMD41_RETRY_MAX（回数上限512・約0.3s）を撤去（R-2: 回数と時間の二重上限を廃止）。
//       (3) SPI_TIMEOUT（0.5s共用）を INIT_TMO = CPU_HZ x 2.0（@4MHz=8,000,000・初期化全体の監視）と
//           EXEC_TMO = CPU_HZ x 0.5（@4MHz=2,000,000・CMD17・現行値据置）に分離（R-3）。
//       (4) ★設計書 v0.3 に無かった追加事項（実装中に実源で判明・かやぬま氏承認 2026-09-30 案1）★:
//           保留EXEC（初期化中に受理）では exec_active=1 のまま timeout_cnt が継続するため、
//           INIT_TMO/EXEC_TMO の分離だけでは「遅い初期化の直後に保留EXECが即ERROR」となる。
//           初期化フェーズ終了時（init_active の立下り）に timeout_cnt を再起動し、
//           EXEC_TMO を CMD17 開始から計測する（保留EXEC時の最悪ストール = INIT_TMO + EXEC_TMO）。
//       (5) timeout_cnt を 24bit → 32bit（CPU_HZ 引上げ時に INIT_TMO が24bitを超えるため）。
//       (6) 全タイムアウトを CPU_HZ から整数演算・64bit幅で導出。32bitに収まらなければ時刻0で $fatal。
//       (7) ★module 名を v0_5 → v0_6 へ昇格しファイル名と一致（案1）★
//       (8) ★既存不具合の是正（実測で発見・かやぬま氏承認 2026-09-30 案B）★:
//           S_IDLE の `exec_active <= exec_active`（保持）が MMIO 書込みの `exec_active <= 1'b1` を
//           後勝ちで上書きし、初期化完了後の通常EXEC（FSM=S_IDLE で受理）では exec_active が 1 に
//           ならなかった。このため EXEC（CMD17）のタイムアウトは v0_4 以来、定常経路で無効だった
//           （トークンが来ないカードで BUSY のまま。旧v0_5・v0_6初版で SCEN=3 により再現）。
//           EXECタイムアウト専用フラグ exec_watch を新設し、timeout_cnt の加算とタイムアウト判定を
//           exec_active から exec_watch へ切替。exec_active／spi_inflight／wait-state の挙動は不変
//           （boot基準値不変）。wait-state（案(D)）の是正は新チケット TKT-V18 で別途設計。
//   （以下は v0.5 時点の記述を保持）
//   Version: v0.5 (2026-09-30)  ← TKT-V16(d) CPU_HZ化（v26_tktv16_clock_plan_design_v0_3.md §5 K-3/K-4）
//     v0.5 (2026-09-30 TKT-V16(d)) 周波数依存定数の単一パラメータ化（4MHzでビット一致）:
//       ・parameter int CPU_HZ（既定 4_000_000）を追加。
//       ・DIV_INIT = ceil(CPU_HZ/(2*200k)) - 1（@4MHz = 9）／
//         DIV_FAST = max(0, ceil(CPU_HZ/(2*25M)) - 1)（@4MHz = 0）を整数演算・64bit幅で導出。
//       ・エラボレーション時検査（$fatal）: 初期化SCK 100〜400kHz、高速SCK <= 25MHz。
//       ・★module 名を v0_1（据置運用）→ v0_5 へ昇格しファイル名と一致（案1・②RTL総点検H-001の是正）★
//       ・SPI_TIMEOUT / ACMD41_RETRY_MAX は (e) の対象のため本版では無変更（振る舞い不変）。
//   （以下は v0.4 時点の記述を保持）
//   Version: v0.4 (2026-07-20)  ← EXEC受理を初期化完了までガード（A案・上位結合統合修正）
//     v0.4 (2026-07-20 CHAT110/A案) 上位結合統合TBで判明した初期化競合を修正:
//       CPU経由の統合TBでリセット解除直後にEXEC($FCA0=2)が発行されると、
//       旧v0.3はfsm現在値を無視して無条件に fsm<=S_RD_CMD17 へ遷移していた。
//       このためSD初期化(CMD0/CMD8/CMD55/ACMD41)未完のままCMD17を送出し、
//       R1応答が得られずS_ERROR確定→RESULT=$FFFFで統合TB S2 FAILとなっていた。
//       修正(A案・4点):
//       (1) exec_pending レジスタを新設（初期化未完中に受理したEXECの保留）。
//       (2) EXEC受理時、init_active=1なら fsm遷移せず exec_pending<=1 のみ。
//           init_active=0（初期化完了済）なら従来どおり即 S_RD_CMD17。
//       (3) S_IDLE で exec_pending 立っていれば消化し S_RD_CMD17 へ遷移。
//       (4) busy_latch/reg_stat落ち/bufptr=0/exec_active=1 は両経路で共通実施。
//       timeout_cnt誤爆なし（総cyc≈16.8k ≪ SPI_TIMEOUT=2M）。
//       検証: 統合TB tb_cpu_v6sdread ALL PASS(4/0)・512B全一致(MISM=0/RESULT=0)、
//             単体TB tb_ysd8003_v0_3 回帰 9/0 維持。
//   Version: v0.3 (2026-07-19)  ← irq_stor_o を完了時1クロックパルス化（上位結合対応）
//     v0.3 (2026-07-19 CHAT109/Step1) 上位結合(V6-A)対応:
//       irq_stor_o をレベル出力(ack クリア)から「完了時1クロックパルス」へ変更。
//       理由: IRQ1はYSD8004集約系統で、割込保持はYSD8004の責務(パルス入力規約)。
//       デバイス側はパルス通知でよい(HANDOVER_CHAT108 §2.3・(B-2)確定案)。
//       - irq_req_r を「毎クロック既定0、S_RD_DONE/S_ERROR完了時のみ1」の
//         パルスレジスタへ変更(spi_start と同型)。ack クリア経路は廃止。
//       - irq_stor_ack ポートは未使用化(YSD8004がW1Cで保持/クリアを担うため)。
//       単体TB(tb_ysd8003_v0_3)のT4もパルス検出へ同時更新(1変更1検証)。
//   Version: v0.2 (2026-07-19)  ← SD初期化シーケンス具体化（実装②-b）
//     v0.1 (2026-07-18) 本体RTL初版。SD初期化はS_POWERUP→S_INIT_DONE素通しの骨格。
//     v0.2 (2026-07-19) 電源投入ダミー＋CMD0/CMD8/CMD55/ACMD41 実バイト授受を実装。
//                       共通S_INIT_R1でR1受信、init_activeでTO保護、ACMD41 retry上限追加。
//     v0.2 (2026-07-19 追記/CHAT107) CMD17読出を完全動作させる修正2件:
//       (1) S_RD_R1でR1=0x00受信成功時、S_RD_TOKENへ遷移する際にトークン受信用の
//           転送(spi_tx<=0xFF; spi_start<=1)を発行（発行漏れ修正）。トークン待ちハング解消。
//       (2) SPIタイムアウト検出(exec/init_active && timeout_cnt>=SPI_TIMEOUT)を
//           case文の【後】へ移動。case前だと同一always内NBAで後勝ちのcase設定に
//           打ち消されTOが無効化されていた不具合を修正。
//       並行して sd_spi_model を v0.2 化（CS deassertでビット境界リセット／送出
//       tx_shift二重ドライブ解消／バイト境界MSB二重出力の位相是正）。
//       結果: T1/T2(512Bデータ一致)/T3(READY,ERROR clear)/T4(IRQ) 全PASS。
//     v0.2 (2026-07-19 追記/CHAT107) T6も解決しALL PASS(9/0):
//       T6失敗の真因はTB側にあり、RTLは正しかった。(a)mmio_write NBA遅延で
//       EXEC未受理のS_IDLEを誤検出→TB判定を2段化。(b)busy_latch=1回目STAT読で
//       BUSYを返す案D/emu23互換仕様のため、TBのSTAT読みを2回読み契約に修正。
//       ※RTL本体は無修正でTB整合により全緑。busy_latchはS_ERROR経由でも
//         「1回目BUSU→2回目でERROR」を返す仕様（emu23互換）で正しい。
//
// 【本デバイスの位置づけ】
//   emu23 の YSD8003 は fread で512Bを即時memcpyしSPIを隠蔽している。
//   本RTLはその隠蔽層を実SPI状態機械として起こす（本テーマの山場）。
//   MMIOレジスタI/F（$FCA0-$FCB0）だけを emu23 互換に保ち、OS無改修を狙う。
//
// 【案(D): STAT読み wait-state 化（設計メモ§2.3）】
//   SPI転送完了まで STAT読み($FCA2) に対して ready_o=0 でCPUを待たせる。
//   完了/タイムアウトで ready_o=1 + READY/ERROR 返却。
//   → OSの sd_wait_ready 2回読み（sd_sample.c）が無改修で成立。
//   ★MC6809 MRDY クロックストレッチ相当。V3 mem_ready 滞留の再利用。★
//
// 【ハング回避KY（設計メモ§8・最重要）】
//   SPIタイムアウトカウンタ。規定SCK超過で ERROR(bit1) 確定→ready_o=1返却。
//   ready_o を永久に0にしない（CPUハング絶対回避）。
//
// 【MMIOレジスタ（$FCA0-$FCB0・emu23_v111.c L295-303 互換）】
//   $FCA0 SD_CMD   W  0=READ_SETUP 1=WRITE_SETUP 2=EXEC
//   $FCA2 SD_STAT  R  bit0=BUSY bit1=ERROR bit2=READY（★案D wait-state対象★）
//   $FCA4 SD_LBA_LO R/W LBA下位16bit
//   $FCA6 SD_LBA_HI R/W LBA上位16bit
//   $FCA8 SD_BUF_PTR R/W バッファポインタ0-511（EXEC時0リセット）
//   $FCAA SD_DATA   R/W PIOデータ8bit・自動BUF_PTR++
//   $FCAC SD_IRQ_CTRL R/W bit0=IRQ_EN bit1=ERR_EN
//   $FCAE SD_DISK_LO R  総セクタ数下位16bit
//   $FCB0 SD_DISK_HI R  総セクタ数上位16bit
//   ※本デバイスは $FCA0-$FCBF の32バイト枠 → アドレス下位5bit(addr_i[4:0])
//
// 【アクセス粒度】
//   バス作法はUART/Timer同様の8bitバイトアクセス。16bitレジスタは
//   上位/下位2バイトに割付（emu23の16bitワードI/Fをバイト分解で互換）。
//   偶数アドレス=下位バイト, 奇数アドレス=上位バイト。
//==============================================================
`timescale 1ns/1ps

module ysd8800_ysd8003_v0_7 #(
    //--- ★v0.5 TKT-V16(d): CPUクロック周波数[Hz]（単一パラメータ）★
    //   DIV_INIT/DIV_FAST をここから導出（§5 K-3/K-4）。(b)完成までは既定値で運用（R-4）
    parameter int CPU_HZ = 4_000_000
) (
    input  logic        clk,
    input  logic        rst_n,

    // --- MMIO バス I/F ($FCA0-$FCBF) ---
    input  logic        sel_i,       // 本デバイス選択 (hit_ys3 & access)
    input  logic [4:0]  addr_i,      // アドレス下位5bit（$FCA0-$FCBF）
    input  logic        we_i,        // 1=write / 0=read
    input  logic [7:0]  wdata_i,
    output logic [7:0]  rdata_o,

    // --- 案(D) wait-state 制御 ---
    //   通常アクセスは 1（即応答）。STAT読み中にSPI未完なら 0（CPUストール）。
    output logic        ready_o,

    // --- 割込出力（レベル・Timer irq_timer_o 同型）---
    output logic        irq_stor_o,  // → YSD8004 IRQ1(STOR)
    input  logic        irq_stor_ack,// v0.3で未使用（YSD8004 W1C保持に移行）。互換のためポートは残置

    // --- SPI 物理線（Tang Nano 9K GPIO へ）---
    output logic        spi_cs_n,
    output logic        spi_sck,
    output logic        spi_mosi,
    input  logic        spi_miso,

    // --- 総セクタ数（上位/TBから供給。emu23 --disk相当）---
    input  logic [31:0] disk_sectors_i
);

    //--------------------------------------------------------------
    // アドレス定数（下位5bit）
    //--------------------------------------------------------------
    localparam [4:0] A_CMD_L    = 5'h00; // $FCA0
    localparam [4:0] A_CMD_H    = 5'h01;
    localparam [4:0] A_STAT_L   = 5'h02; // $FCA2 ★wait-state対象★
    localparam [4:0] A_STAT_H   = 5'h03;
    localparam [4:0] A_LBA_LO_L = 5'h04; // $FCA4
    localparam [4:0] A_LBA_LO_H = 5'h05;
    localparam [4:0] A_LBA_HI_L = 5'h06; // $FCA6
    localparam [4:0] A_LBA_HI_H = 5'h07;
    localparam [4:0] A_BUFP_L   = 5'h08; // $FCA8
    localparam [4:0] A_BUFP_H   = 5'h09;
    localparam [4:0] A_DATA_L   = 5'h0A; // $FCAA
    localparam [4:0] A_DATA_H   = 5'h0B;
    localparam [4:0] A_IRQC_L   = 5'h0C; // $FCAC
    localparam [4:0] A_IRQC_H   = 5'h0D;
    localparam [4:0] A_DISK_LO_L= 5'h0E; // $FCAE
    localparam [4:0] A_DISK_LO_H= 5'h0F;
    localparam [4:0] A_DISK_HI_L= 5'h10; // $FCB0
    localparam [4:0] A_DISK_HI_H= 5'h11;

    //--------------------------------------------------------------
    // レジスタ群
    //--------------------------------------------------------------
    logic [7:0]  reg_cmd;        // 最後のSD_CMD（0/1）
    logic [2:0]  reg_stat;       // bit0=BUSY bit1=ERROR bit2=READY
    logic [31:0] reg_lba;
    logic [8:0]  reg_bufptr;     // 0-511
    logic [1:0]  reg_irqctrl;    // bit0=IRQ_EN bit1=ERR_EN
    logic        busy_latch;     // EXEC→1, STAT1回目読でクリア

    // セクタバッファ 512B（分散RAM/LUTRAM: 諮問2レビュー決定）
    logic [7:0]  sd_buf [0:511];
    // DATA読出値: always_comb内の配列可変selectを避けるためassignで切出し
    //   （iverilog "constant selects in always_*" 警告回避＋合成でLUTRAM読出に素直）
    logic [7:0]  sd_buf_dout;
    assign sd_buf_dout = sd_buf[reg_bufptr];

    // --- 原則59: always_comb 内の定数ビット選択を避け assign で事前抽出 ---
    //   （Timer ysd8002 と同方針。comb では名前参照のみにする）
    logic [7:0] lba_b0, lba_b1, lba_b2, lba_b3;
    logic [7:0] bufptr_b0, bufptr_b1;
    logic [7:0] disk_b0, disk_b1, disk_b2, disk_b3;
    logic [7:0] stat_busy_val, stat_norm_val, irqc_val;
    assign lba_b0 = reg_lba[7:0];
    assign lba_b1 = reg_lba[15:8];
    assign lba_b2 = reg_lba[23:16];
    assign lba_b3 = reg_lba[31:24];
    assign bufptr_b0 = reg_bufptr[7:0];
    assign bufptr_b1 = {7'b0, reg_bufptr[8]};
    assign disk_b0 = disk_sectors_i[7:0];
    assign disk_b1 = disk_sectors_i[15:8];
    assign disk_b2 = disk_sectors_i[23:16];
    assign disk_b3 = disk_sectors_i[31:24];
    assign stat_busy_val = 8'h01;              // BUSY
    assign stat_norm_val = {5'b0, reg_stat};
    assign irqc_val = {6'b0, reg_irqctrl};

    //--------------------------------------------------------------
    // STAT bit 定義
    //--------------------------------------------------------------
    localparam [2:0] STAT_BUSY  = 3'b001;
    localparam [2:0] STAT_ERROR = 3'b010;
    localparam [2:0] STAT_READY = 3'b100;

    //--------------------------------------------------------------
    // SCK 2段固定分周（諮問3レビュー決定）
    //   初期化: 低速（100-400kHz相当・大分周）/ 読出: 高速（小分周）
    //   4MHz clk 前提。SCK = clk / (2*(DIV+1)) 相当の簡易分周。
    //   ★実カード規格の初期化低速要件を満たす。RTL内部自動切替でOS非依存★
    //--------------------------------------------------------------
    //--------------------------------------------------------------
    // ★v0.5 TKT-V16(d): SCK 分周値を CPU_HZ から導出（設計書 §5 K-3/K-4）★
    //   DIV_INIT = ceil(CPU_HZ/(2*200k)) - 1   切上げ → 初期化 SCK <= 200kHz を保証
    //                                          （@4MHz = 9 → 200kHz）
    //   DIV_FAST = max(0, ceil(CPU_HZ/(2*25M)) - 1)   切上げ → SCK <= 25MHz
    //                                          （@4MHz = 0 → 2MHz）
    //   iverilog v12 制約（原則146）: 整数演算・64bit 幅を明示
    //--------------------------------------------------------------
    localparam logic [63:0] DIV_INIT_C = (64'(CPU_HZ) + 64'd399_999) / 64'd400_000;    // ceil(CPU_HZ/400k)
    localparam logic [63:0] DIV_FAST_C = (64'(CPU_HZ) + 64'd49_999_999) / 64'd50_000_000; // ceil(CPU_HZ/50M)
    localparam logic [15:0] DIV_INIT = (DIV_INIT_C > 64'd1) ? 16'(DIV_INIT_C - 64'd1) : 16'd0;
    localparam logic [15:0] DIV_FAST = (DIV_FAST_C > 64'd1) ? 16'(DIV_FAST_C - 64'd1) : 16'd0;

    //--- SCK 範囲検査（時刻 0 で $fatal）---------------------------------
    //   初期化 SCK = CPU_HZ/(2*(DIV_INIT+1)) が 100〜400kHz、
    //   高速   SCK = CPU_HZ/(2*(DIV_FAST+1)) が <= 25MHz でなければ致命。
    //   （除算を避け、分母を掛けた形で比較）
    localparam logic [63:0] SCK_INIT_DEN = 64'd2 * (64'(DIV_INIT) + 64'd1);
    localparam logic [63:0] SCK_FAST_DEN = 64'd2 * (64'(DIV_FAST) + 64'd1);
    generate
        if ((DIV_INIT_C < 64'd1) || (DIV_INIT_C > 64'd65536) ||
            (64'(CPU_HZ) > 64'd400_000 * SCK_INIT_DEN) ||
            (64'(CPU_HZ) < 64'd100_000 * SCK_INIT_DEN) ||
            (64'(CPU_HZ) > 64'd25_000_000 * SCK_FAST_DEN)) begin : g_bad_sck
            initial $fatal(1, "YSD8003: SCK out of range (init 100-400kHz / fast <=25MHz) (CPU_HZ=%0d)", CPU_HZ);
        end
    endgenerate
    logic [15:0] sck_div;
    logic [15:0] sck_cnt;
    logic        sck_tick;   // SCK半周期トグルタイミング
    logic        sck_r;      // 生成SCK

    //--------------------------------------------------------------
    // SPI 8bit 転送エンジン（mode0: SCK立上りでMISOサンプル・立下りでMOSI更新）
    //--------------------------------------------------------------
    logic [7:0]  spi_tx;        // 送信バイト
    logic [7:0]  spi_rx;        // 受信バイト
    logic [3:0]  spi_bitcnt;
    logic        spi_start;     // 1バイト転送開始要求
    logic        spi_busy;      // 転送中
    logic        spi_done;      // 1バイト完了パルス
    logic        sck_phase;     // 0=次は立上り, 1=次は立下り

    assign spi_cs_n = spi_cs_r;
    assign spi_sck  = sck_r;
    assign spi_mosi = spi_tx[7];
    logic  spi_cs_r;

    //--------------------------------------------------------------
    // SD 制御 FSM
    //--------------------------------------------------------------
    typedef enum logic [4:0] {
        S_RESET,        // リセット直後
        S_POWERUP,      // CS=1で74クロック以上のダミー（電源安定）
        S_CMD0,         // GO_IDLE
        S_CMD8,         // SEND_IF_COND
        S_CMD55,        // APP_CMD
        S_ACMD41,       // SD_SEND_OP_COND（未完なら再ループ）
        S_INIT_R1,      // 初期化コマンド共通のR1受信待ち
        S_INIT_DONE,    // 初期化完了・アイドル
        S_IDLE,         // EXEC待ち
        S_RD_CMD17,     // CMD17送出
        S_RD_R1,        // R1待ち
        S_RD_TOKEN,     // データトークン0xFE待ち
        S_RD_DATA,      // 512バイト受信
        S_RD_CRC,       // CRC16 2バイト読み捨て
        S_RD_DONE,      // 読出完了→READY・IRQ
        S_ERROR         // エラー確定
    } fsm_t;
    fsm_t fsm;

    // コマンド送出用シーケンサ補助
    logic [7:0]  cmd_frame [0:5];  // 6バイトコマンドフレーム
    logic [2:0]  cmd_byte_idx;     // 0-5
    logic [3:0]  resp_wait_cnt;    // R1待ちのNCRカウンタ
    logic [8:0]  data_cnt;         // 512バイトカウンタ
    logic        crc_second;       // CRC16 2バイト目フラグ
    //   ★v0.6 TKT-V16(e): acmd41_retry / ACMD41_RETRY_MAX（回数上限）は撤去。
    //     ACMD41 の上限は時間ベースの ACMD41_TMO（下記）に一本化（R-2）。★
    logic [31:0] acmd41_cnt;       // ★v0.6★ ACMD41フェーズ経過クロック（最初のACMD41発行で起動）
    logic        acmd41_run;       // ★v0.6★ 1=ACMD41タイマ動作中
    logic [6:0]  powerup_cnt;      // 電源投入ダミークロック（74clk以上）バイトカウンタ
    fsm_t        init_next;        // 初期化R1受信後に進む状態
    logic [7:0]  init_expect;      // 期待R1値（0x01=idle / 0x00=ready）

    //--------------------------------------------------------------
    // ★SPIタイムアウト（ハング回避KY）★  ★v0.6 TKT-V16(e) 再設計（設計書 §6.3）★
    //   ・ACMD41_TMO = CPU_HZ x 1.5 : ACMD41フェーズ専用（規格 §4.2.3 の1秒超・R-5）
    //   ・INIT_TMO   = CPU_HZ x 2.0 : 初期化全体の監視（ACMD41_TMO故障時の保護も兼ねる・R-3）
    //   ・EXEC_TMO   = CPU_HZ x 0.5 : CMD17（現行値据置・§4.6.2.1 最小100msに適合）
    //   @4MHz: 6,000,000 / 8,000,000 / 2,000,000。iverilog v12制約（原則146）: 整数演算・64bit幅。
    //   32bitに収まらない CPU_HZ は時刻0で $fatal。
    //--------------------------------------------------------------
    localparam logic [63:0] ACMD41_TMO_L = (64'(CPU_HZ) * 64'd3) / 64'd2;
    localparam logic [63:0] INIT_TMO_L   =  64'(CPU_HZ) * 64'd2;
    localparam logic [63:0] EXEC_TMO_L   =  64'(CPU_HZ) / 64'd2;
    localparam logic [31:0] ACMD41_TMO   = ACMD41_TMO_L[31:0];
    localparam logic [31:0] INIT_TMO     = INIT_TMO_L[31:0];
    localparam logic [31:0] EXEC_TMO     = EXEC_TMO_L[31:0];
    generate
        if ((ACMD41_TMO_L < 64'd1) || (EXEC_TMO_L < 64'd1) ||
            (INIT_TMO_L > 64'h0000_0000_FFFF_FFFF)) begin : g_bad_tmo
            initial $fatal(1, "YSD8003: timeout out of 32bit range (CPU_HZ=%0d)", CPU_HZ);
        end
    endgenerate
    logic [31:0] timeout_cnt;      // ★v0.6: 24bit→32bit★ 初期化終了時に再起動（フェーズ別計測）
    logic        init_active_d;    // ★v0.6★ init_active の1クロック遅延（フェーズ判定・再起動検出）
    logic        exec_active;      // EXEC受理〜完了/エラーまで1
    //   ★v0.6 TKT-V16(e) exec_watch★ EXECタイムアウト監視専用フラグ（案B・かやぬま氏承認 2026-09-30）。
    //     既存不具合: S_IDLE の `exec_active <= exec_active`（保持）が MMIO 書込みの
    //     `exec_active <= 1'b1` を後勝ちで上書きし、初期化完了後の通常EXECで exec_active が
    //     1にならず、EXECタイムアウトが定常経路で無効だった（v0_4 以来・実測で確認）。
    //     exec_active／spi_inflight／wait-state の挙動は変えない（boot基準値不変・是正は TKT-V18）。
    //     exec_watch は S_IDLE 等で代入しないため上書きされない。
    logic        exec_watch;
    logic        exec_pending;     // ★A案★初期化未完中に受理したEXECの保留フラグ
    logic        init_active;      // 初期化シーケンス進行中=1（ハング回避:TO保護対象）

    //--------------------------------------------------------------
    // ★案(D) wait-state 判定★
    //   STAT読み かつ EXEC進行中(READY/ERROR未確定) の間 ready_o=0。
    //   完了(READY)またはERROR確定で ready_o=1。他アクセスは常に1。
    //--------------------------------------------------------------
    logic stat_read_access;
    assign stat_read_access = sel_i & ~we_i & (addr_i == A_STAT_L);

    // EXEC進行中 = exec_active かつ まだREADY(bit2)もERROR(bit1)も立っていない
    //   ※3bitマスクのビット反転を1bitへ縮退させると意図とズレるため明示ビット指定
    logic spi_inflight;
    assign spi_inflight = exec_active & ~reg_stat[2] & ~reg_stat[1];

    always_comb begin
        // 既定: 即応答
        ready_o = 1'b1;
        // STAT読みで、かつSPI未完なら 待たせる
        if (stat_read_access && spi_inflight)
            ready_o = 1'b0;
    end

    //--------------------------------------------------------------
    // 読み出しデータ（rdata_o）
    //--------------------------------------------------------------
    always_comb begin
        rdata_o = 8'h00;
        if (sel_i && !we_i) begin
            case (addr_i)
                A_CMD_L:    rdata_o = reg_cmd;
                A_CMD_H:    rdata_o = 8'h00;
                A_STAT_L:    rdata_o = busy_latch ? stat_busy_val : stat_norm_val;
                A_STAT_H:    rdata_o = 8'h00;
                A_LBA_LO_L:  rdata_o = lba_b0;
                A_LBA_LO_H:  rdata_o = lba_b1;
                A_LBA_HI_L:  rdata_o = lba_b2;
                A_LBA_HI_H:  rdata_o = lba_b3;
                A_BUFP_L:    rdata_o = bufptr_b0;
                A_BUFP_H:    rdata_o = bufptr_b1;
                A_DATA_L:    rdata_o = sd_buf_dout;  // 読出でBUF_PTR++は順序側
                A_DATA_H:    rdata_o = 8'h00;
                A_IRQC_L:    rdata_o = irqc_val;
                A_IRQC_H:    rdata_o = 8'h00;
                A_DISK_LO_L: rdata_o = disk_b0;
                A_DISK_LO_H: rdata_o = disk_b1;
                A_DISK_HI_L: rdata_o = disk_b2;
                A_DISK_HI_H: rdata_o = disk_b3;
                default:     rdata_o = 8'h00;
            endcase
        end
    end

    //--------------------------------------------------------------
    // SCK 分周生成
    //--------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sck_cnt  <= 0;
            sck_tick <= 1'b0;
        end else if (spi_busy) begin
            if (sck_cnt == sck_div) begin
                sck_cnt  <= 0;
                sck_tick <= 1'b1;
            end else begin
                sck_cnt  <= sck_cnt + 1;
                sck_tick <= 1'b0;
            end
        end else begin
            sck_cnt  <= 0;
            sck_tick <= 1'b0;
        end
    end

    //--------------------------------------------------------------
    // SPI 8bit 転送エンジン（mode0）
    //   sck_phase=0: SCK立上り相当（MISOをspi_rxへ取込）
    //   sck_phase=1: SCK立下り相当（MOSI=spi_tx[7]更新・次ビットへ）
    //--------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            spi_busy   <= 1'b0;
            spi_done   <= 1'b0;
            spi_bitcnt <= 0;
            sck_r      <= 1'b0;
            sck_phase  <= 1'b0;
            spi_rx     <= 8'h00;
        end else begin
            spi_done <= 1'b0;
            if (spi_start && !spi_busy) begin
                spi_busy   <= 1'b1;
                spi_bitcnt <= 0;
                sck_r      <= 1'b0;
                sck_phase  <= 1'b0;
            end else if (spi_busy && sck_tick) begin
                if (sck_phase == 1'b0) begin
                    // 立上り: MISO取込
                    sck_r  <= 1'b1;
                    spi_rx <= {spi_rx[6:0], spi_miso};
                    sck_phase <= 1'b1;
                end else begin
                    // 立下り: 次ビットへ・MOSIシフト
                    sck_r  <= 1'b0;
                    spi_tx <= {spi_tx[6:0], 1'b1};
                    sck_phase <= 1'b0;
                    if (spi_bitcnt == 4'd7) begin
                        spi_busy <= 1'b0;
                        spi_done <= 1'b1;
                    end else begin
                        spi_bitcnt <= spi_bitcnt + 1;
                    end
                end
            end
        end
    end

    //--------------------------------------------------------------
    // タイムアウトカウンタ（ハング回避）
    //   ★v0.6 TKT-V16(e)★ フェーズ別計測:
    //     初期化フェーズ終了（init_active の立下り）で 0 に再起動する。
    //     保留EXEC（初期化中に受理・exec_active=1 のまま継続）でも、EXEC_TMO は
    //     CMD17 開始から計測される（遅い初期化の直後に即ERRORとなるのを防ぐ）。
    //     再起動の1クロック（init_active=0 / init_active_d=1）は、判定側が
    //     init_active_d をフェーズ選択に使うため INIT_TMO で評価され、旧カウント値で
    //     EXEC_TMO を誤判定することはない。
    //--------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            timeout_cnt   <= 0;
            init_active_d <= 1'b0;
        end else begin
            init_active_d <= init_active;
            if (init_active_d && !init_active) begin
                timeout_cnt <= 0;                   // ★初期化フェーズ終了→EXEC計測を再起動★
            end else if (exec_watch || init_active) begin   // ★v0.6: exec_active→exec_watch★
                timeout_cnt <= timeout_cnt + 1;
            end else begin
                timeout_cnt <= 0;
            end
        end
    end

    //--------------------------------------------------------------
    // 割込出力（完了時1クロックパルス・v0.3）
    //   YSD8004集約系統に接続。保持/クリアはYSD8004(W1C)の責務。
    //   本デバイスはパルス通知のみ（YSD8004パルス入力規約に整合）。
    //--------------------------------------------------------------
    logic irq_req_r;
    assign irq_stor_o = irq_req_r;

    //--------------------------------------------------------------
    // メイン順序回路: レジスタ書込 + FSM
    //   ※簡潔化のため、SPIバイト授受は spi_start/spi_done で駆動する
    //     高位FSMをここに置く。sck_div は fsm により INIT/FAST を選択。
    //--------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_cmd     <= 8'h00;
            reg_stat    <= STAT_READY; // 初期値READY（emu23 sd_stat初期bit2）
            reg_lba     <= 32'h0;
            reg_bufptr  <= 9'h0;
            reg_irqctrl <= 2'h0;
            busy_latch  <= 1'b0;
            fsm         <= S_RESET;
            spi_start   <= 1'b0;
            spi_tx      <= 8'hFF;
            spi_cs_r    <= 1'b1;    // 非選択
            sck_div     <= DIV_INIT;
            cmd_byte_idx<= 0;
            resp_wait_cnt <= 0;
            data_cnt    <= 0;
            crc_second  <= 1'b0;
            acmd41_cnt  <= 0;      // ★v0.6: acmd41_retry 撤去→時間ベースタイマ★
            acmd41_run  <= 1'b0;
            exec_active <= 1'b0;
            exec_watch  <= 1'b0;   // ★v0.6 TKT-V16(e)★
            exec_pending<= 1'b0;   // ★A案★
            init_active <= 1'b0;
            powerup_cnt <= 0;
            init_next   <= S_CMD0;
            init_expect <= 8'h01;
            irq_req_r   <= 1'b0;
        end else begin
            spi_start <= 1'b0;  // 既定（1クロックパルス）
            irq_req_r <= 1'b0;  // 既定0（v0.3：完了時のみ1にする1クロックパルス）
            // ※ irq_stor_ack は未使用化。保持/クリアはYSD8004(W1C)の責務。
            // ★v0.6 TKT-V16(e)★ ACMD41タイマ歩進（既定）。起動/停止は下のFSM(case)内で
            //   同一always_ff内の後勝ち代入により上書きする（S_ACMD41 / S_INIT_DONE / S_ERROR）。
            if (acmd41_run) acmd41_cnt <= acmd41_cnt + 1;

            //=========================================================
            // MMIO 書込（sel & we）
            //=========================================================
            if (sel_i && we_i) begin
                case (addr_i)
                    A_CMD_L: begin
                        if (wdata_i == 8'd2) begin
                            // EXEC: SPI読出FSM起動
                            busy_latch  <= 1'b1;
                            reg_stat    <= 3'b000;   // READY落ち
                            reg_bufptr  <= 9'h0;     // EXEC時BUF_PTR=0
                            exec_active <= 1'b1;
                            exec_watch  <= 1'b1;         // ★v0.6: EXECタイムアウト監視開始★
                            // ★A案★初期化未完(init_active=1)中はfsm遷移せず保留。
                            //   初期化完了(S_IDLE)でpendingを消化しS_RD_CMD17へ。
                            //   完了済みなら従来どおり即遷移。
                            if (init_active) begin
                                exec_pending <= 1'b1;
                            end else begin
                                // READ_SETUP(reg_cmd==0)前提でCMD17読出へ
                                fsm          <= S_RD_CMD17;
                            end
                        end else begin
                            reg_cmd <= wdata_i;      // 0=READ_SETUP 1=WRITE_SETUP
                        end
                    end
                    A_LBA_LO_L: reg_lba[7:0]   <= wdata_i;
                    A_LBA_LO_H: reg_lba[15:8]  <= wdata_i;
                    A_LBA_HI_L: reg_lba[23:16] <= wdata_i;
                    A_LBA_HI_H: reg_lba[31:24] <= wdata_i;
                    A_BUFP_L:   reg_bufptr[7:0] <= wdata_i;
                    A_BUFP_H:   reg_bufptr[8]   <= wdata_i[0];
                    A_DATA_L: begin
                        sd_buf[reg_bufptr] <= wdata_i;
                        reg_bufptr <= (reg_bufptr == 9'd511) ? 9'd0
                                                             : reg_bufptr + 1;
                    end
                    A_IRQC_L:   reg_irqctrl <= wdata_i[1:0];
                    default: ;
                endcase
            end

            //=========================================================
            // MMIO 読出の副作用（BUSYラッチクリア・DATA読出でBUF_PTR++）
            //=========================================================
            if (sel_i && !we_i) begin
                if (addr_i == A_STAT_L && busy_latch) begin
                    busy_latch <= 1'b0;   // 1回目STAT読でクリア
                end
                if (addr_i == A_DATA_L) begin
                    reg_bufptr <= (reg_bufptr == 9'd511) ? 9'd0
                                                         : reg_bufptr + 1;
                end
            end

            //=========================================================
            // SD 制御 FSM
            //=========================================================
            case (fsm)
                //---- リセット/電源投入シーケンス ----
                S_RESET: begin
                    spi_cs_r    <= 1'b1;     // CS=1（電源投入ダミーはCS非選択で行う）
                    sck_div     <= DIV_INIT; // 初期化は低速SCK
                    init_active <= 1'b1;     // ★ここから初期化フェーズ:TO保護対象★
                    powerup_cnt <= 0;
                    fsm         <= S_POWERUP;
                end

                //---- 電源投入ダミークロック（CS=1/MOSI=1で74clk以上）----
                S_POWERUP: begin
                    // CS非選択のまま0xFFを10バイト(=80clk)送出しカードを安定させる
                    spi_cs_r <= 1'b1;
                    if (spi_done || powerup_cnt == 0) begin
                        if (powerup_cnt >= 7'd10) begin
                            fsm <= S_CMD0;   // ダミー完了→CMD0へ
                        end else begin
                            powerup_cnt <= powerup_cnt + 1;
                            spi_tx    <= 8'hFF;
                            spi_start <= 1'b1;
                        end
                    end
                end

                //---- CMD0 GO_IDLE_STATE（正CRC 0x95・R1=0x01期待）----
                S_CMD0: begin
                    spi_cs_r <= 1'b0;        // CS選択
                    cmd_frame[0] <= 8'h40;   // 0x40|0
                    cmd_frame[1] <= 8'h00;
                    cmd_frame[2] <= 8'h00;
                    cmd_frame[3] <= 8'h00;
                    cmd_frame[4] <= 8'h00;
                    cmd_frame[5] <= 8'h95;   // CMD0正CRC7
                    cmd_byte_idx <= 0;
                    spi_tx    <= 8'h40;
                    spi_start <= 1'b1;
                    resp_wait_cnt <= 0;
                    init_next   <= S_CMD8;
                    init_expect <= 8'h01;    // idle
                    fsm <= S_INIT_R1;
                end

                //---- CMD8 SEND_IF_COND（正CRC 0x87・arg=0x1AA・R1=0x01期待）----
                S_CMD8: begin
                    spi_cs_r <= 1'b0;
                    cmd_frame[0] <= 8'h48;   // 0x40|8
                    cmd_frame[1] <= 8'h00;
                    cmd_frame[2] <= 8'h00;
                    cmd_frame[3] <= 8'h01;   // 電圧範囲
                    cmd_frame[4] <= 8'hAA;   // チェックパターン
                    cmd_frame[5] <= 8'h87;   // CMD8正CRC7
                    cmd_byte_idx <= 0;
                    spi_tx    <= 8'h48;
                    spi_start <= 1'b1;
                    resp_wait_cnt <= 0;
                    init_next   <= S_CMD55;
                    init_expect <= 8'h01;    // R7先頭R1=idle（残4バイトはR1後に読捨せず簡略化）
                    fsm <= S_INIT_R1;
                end

                //---- CMD55 APP_CMD（次コマンドをACMD化・R1=0x01期待）----
                S_CMD55: begin
                    spi_cs_r <= 1'b0;
                    cmd_frame[0] <= 8'h77;   // 0x40|55
                    cmd_frame[1] <= 8'h00;
                    cmd_frame[2] <= 8'h00;
                    cmd_frame[3] <= 8'h00;
                    cmd_frame[4] <= 8'h00;
                    cmd_frame[5] <= 8'h01;   // ダミーCRC|停止bit
                    cmd_byte_idx <= 0;
                    spi_tx    <= 8'h77;
                    spi_start <= 1'b1;
                    resp_wait_cnt <= 0;
                    init_next   <= S_ACMD41;
                    init_expect <= 8'h01;    // idle
                    fsm <= S_INIT_R1;
                end

                //---- ACMD41 SD_SEND_OP_COND（HCS=1・R1=0x00で完了/非0は再ループ）----
                S_ACMD41: begin
                    // ★v0.6 TKT-V16(e)★ 最初のACMD41発行でACMD41_TMOタイマ起動（規格 §4.2.3）。
                    //   再ループ(S_CMD55経由)では acmd41_run=1 のため再起動しない。
                    if (!acmd41_run) begin
                        acmd41_run <= 1'b1;
                        acmd41_cnt <= 0;
                    end
                    spi_cs_r <= 1'b0;
                    cmd_frame[0] <= 8'h69;   // 0x40|41
                    cmd_frame[1] <= 8'h40;   // HCS=1（bit30）
                    cmd_frame[2] <= 8'h00;
                    cmd_frame[3] <= 8'h00;
                    cmd_frame[4] <= 8'h00;
                    cmd_frame[5] <= 8'h01;   // ダミーCRC|停止bit
                    cmd_byte_idx <= 0;
                    spi_tx    <= 8'h69;
                    spi_start <= 1'b1;
                    resp_wait_cnt <= 0;
                    init_next   <= S_INIT_DONE;
                    init_expect <= 8'h00;    // ready（完了）
                    fsm <= S_INIT_R1;
                end

                //---- 初期化コマンド共通のR1受信待ち ----
                S_INIT_R1: begin
                    if (spi_done) begin
                        if (cmd_byte_idx < 3'd5) begin
                            // フレーム残バイト送出
                            cmd_byte_idx <= cmd_byte_idx + 1;
                            spi_tx    <= cmd_frame[cmd_byte_idx + 1];
                            spi_start <= 1'b1;
                        end else begin
                            // 全バイト送出済み→R1受信
                            if (spi_rx == init_expect) begin
                                // 期待R1一致→次コマンドへ
                                spi_cs_r <= 1'b1;   // 一旦CS解除（コマンド間）
                                fsm <= init_next;
                            end else if (spi_rx == 8'hFF) begin
                                // NCR: まだ応答前→もう1バイトクロック
                                resp_wait_cnt <= resp_wait_cnt + 1;
                                if (resp_wait_cnt > 4'd8) begin
                                    fsm <= S_ERROR;
                                end else begin
                                    spi_tx    <= 8'hFF;
                                    spi_start <= 1'b1;
                                end
                            end else begin
                                // ACMD41で未完(0x01)なら再ループ（★v0.6: 時間上限 ACMD41_TMO で監視★）
                                //   回数上限(ACMD41_RETRY_MAX)は撤去。判定点は R1=0x01 受信時
                                //   （転送の途中では打ち切らない）。1周回は約0.8ms@200kHzのため
                                //   判定分解能は 1ms 未満。最終保護は INIT_TMO（全体監視）。
                                if (init_next == S_INIT_DONE && spi_rx == 8'h01) begin
                                    if (acmd41_cnt >= ACMD41_TMO) begin
                                        fsm <= S_ERROR;  // ★ハング回避:ACMD41_TMO超過★
                                    end else begin
                                        spi_cs_r <= 1'b1;
                                        fsm <= S_CMD55;  // CMD55からやり直し
                                    end
                                end else begin
                                    // 想定外R1→エラー
                                    fsm <= S_ERROR;
                                end
                            end
                        end
                    end
                end

                S_INIT_DONE: begin
                    sck_div     <= DIV_FAST;   // 初期化後は高速SCKへ切替
                    spi_cs_r    <= 1'b1;
                    init_active <= 1'b0;       // ★初期化フェーズ終了★
                    acmd41_run  <= 1'b0;       // ★v0.6: ACMD41タイマ停止★
                    fsm         <= S_IDLE;
                end
                S_IDLE: begin
                    // 通常のEXEC受理はMMIO側が即 S_RD_CMD17 へ遷移させる。
                    // ★A案★初期化未完中に保留したEXEC(exec_pending)をここで消化。
                    if (exec_pending) begin
                        exec_pending <= 1'b0;
                        fsm          <= S_RD_CMD17;
                    end else begin
                        exec_active <= exec_active; // 保持
                    end
                end

                //---- CMD17 単一ブロック読出 ----
                S_RD_CMD17: begin
                    spi_cs_r <= 1'b0;
                    // CMD17フレーム: 0x51, LBA[31:0](バイト), CRC7|1=0x01
                    cmd_frame[0] <= 8'h51;               // 0x40|17
                    cmd_frame[1] <= reg_lba[31:24];
                    cmd_frame[2] <= reg_lba[23:16];
                    cmd_frame[3] <= reg_lba[15:8];
                    cmd_frame[4] <= reg_lba[7:0];
                    cmd_frame[5] <= 8'h01;               // CRCダミー|停止bit
                    cmd_byte_idx <= 0;
                    spi_tx    <= 8'h51;
                    spi_start <= 1'b1;
                    resp_wait_cnt <= 0;
                    fsm <= S_RD_R1;
                end
                S_RD_R1: begin
                    // コマンド6バイト送出→R1(0x00)待ち
                    if (spi_done) begin
                        if (cmd_byte_idx < 3'd5) begin
                            cmd_byte_idx <= cmd_byte_idx + 1;
                            spi_tx    <= cmd_frame[cmd_byte_idx + 1];
                            spi_start <= 1'b1;
                        end else begin
                            // 全バイト送出済み→R1受信（0xFFを送りつつ受信）
                            if (spi_rx == 8'h00) begin
                                fsm <= S_RD_TOKEN;
                                spi_tx    <= 8'hFF;   // トークン受信用クロック開始
                                spi_start <= 1'b1;
                            end else begin
                                // NCR: FF等ならもう1バイトクロック
                                resp_wait_cnt <= resp_wait_cnt + 1;
                                if (resp_wait_cnt > 4'd8) begin
                                    fsm <= S_ERROR;
                                end else begin
                                    spi_tx    <= 8'hFF;
                                    spi_start <= 1'b1;
                                end
                            end
                        end
                    end
                end
                S_RD_TOKEN: begin
                    // データトークン0xFE待ち
                    if (spi_done) begin
                        if (spi_rx == 8'hFE) begin
                            data_cnt <= 0;
                            spi_tx    <= 8'hFF;
                            spi_start <= 1'b1;
                            fsm <= S_RD_DATA;
                        end else begin
                            spi_tx    <= 8'hFF;
                            spi_start <= 1'b1;  // トークン来るまでクロック継続
                        end
                    end
                end
                S_RD_DATA: begin
                    // 512バイト受信→sd_bufへ
                    if (spi_done) begin
                        sd_buf[data_cnt[8:0]] <= spi_rx;
                        if (data_cnt == 9'd511) begin
                            crc_second <= 1'b0;
                            spi_tx    <= 8'hFF;
                            spi_start <= 1'b1;
                            fsm <= S_RD_CRC;
                        end else begin
                            data_cnt <= data_cnt + 1;
                            spi_tx    <= 8'hFF;
                            spi_start <= 1'b1;
                        end
                    end
                end
                S_RD_CRC: begin
                    // CRC16 2バイト読み捨て
                    if (spi_done) begin
                        if (!crc_second) begin
                            crc_second <= 1'b1;
                            spi_tx    <= 8'hFF;
                            spi_start <= 1'b1;
                        end else begin
                            fsm <= S_RD_DONE;
                        end
                    end
                end
                S_RD_DONE: begin
                    spi_cs_r    <= 1'b1;       // CS解除
                    reg_stat    <= STAT_READY; // READY確定（wait-state解除トリガ）
                    exec_active <= 1'b0;
                    exec_watch  <= 1'b0;       // ★v0.6: EXECタイムアウト監視終了★
                    // 完了IRQ（IRQ_EN時・レベル）
                    if (reg_irqctrl[0])
                        irq_req_r <= 1'b1;
                    fsm <= S_IDLE;
                end

                //---- エラー ----
                S_ERROR: begin
                    spi_cs_r    <= 1'b1;
                    reg_stat    <= STAT_ERROR; // ERROR確定（wait-state解除）
                    exec_active <= 1'b0;
                    exec_watch  <= 1'b0;       // ★v0.6: EXECタイムアウト監視終了★
                    init_active <= 1'b0;       // 初期化エラー時のTO暴走防止
                    acmd41_run  <= 1'b0;       // ★v0.6: ACMD41タイマ停止★
                    exec_pending<= 1'b0;       // ★v0.7 TKT-V16(e) F-2/U-15: 保留EXECを破棄★
                                               //   （破棄しないと S_IDLE で消化され CMD17 へ進み、
                                               //    reg_stat が ERROR→READY に上書きされ、かつ監視外）
                    if (reg_irqctrl[0])        // 完了IRQ（エラーでも予約：emu23互換）
                        irq_req_r <= 1'b1;
                    fsm <= S_IDLE;
                end

                default: fsm <= S_IDLE;
            endcase

            //=========================================================
            // ★SPIタイムアウト → ERROR確定（ハング回避KY）★
            //   case文の後に置くことで、待ち状態がcase内で再発行する
            //   fsm遷移（spi_start再クロック等）を上書きしてERROR確定する。
            //   （case前に置くと同一always内NBAで後勝ちのcase設定に
            //     打ち消されTOが無効化される不具合をCHAT107で修正）
            //   ★v0.6 TKT-V16(e)★ 上限をフェーズ別に選択:
            //     init_active_d=1（初期化フェーズ）→ INIT_TMO ／ 0（EXEC）→ EXEC_TMO。
            //     init_active_d は timeout_cnt の再起動と同位相のため、フェーズ境界の
            //     1クロックで旧カウント値がEXEC_TMOと比較されることはない。
            //=========================================================
            if ((exec_watch || init_active) &&
                (timeout_cnt >= (init_active_d ? INIT_TMO : EXEC_TMO))) begin
                fsm <= S_ERROR;
            end
        end
    end

endmodule
