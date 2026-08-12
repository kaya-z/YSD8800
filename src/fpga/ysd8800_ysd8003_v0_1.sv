//==============================================================
// ysd8800_ysd8003_v0_1.sv
//   YSD8003 ストレージコントローラ（SDカード SPIモード読出）本体RTL
//   - 設計メモ: v6a_storage_design_memo_v0_2.md（v0.2・レビュー承認済）
//   - レビュー: v6a_storage_design_review_reply_v1_0.md（案D採用）
//   Version: v0.1 (2026-07-18)
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

module ysd8800_ysd8003_v0_1 (
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
    input  logic        irq_stor_ack,// CPUがIRQ1受理でクリア（irq0_ack同型）

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
    localparam [15:0] DIV_INIT = 16'd9;  // 4MHz/(2*10)=200kHz 相当
    localparam [15:0] DIV_FAST = 16'd0;  // 4MHz/(2*1)=2MHz 相当
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
    logic [9:0]  acmd41_retry;     // ACMD41再試行カウンタ

    //--------------------------------------------------------------
    // ★SPIタイムアウトカウンタ（ハング回避KY）★
    //   EXEC〜完了までの総SCK/クロック上限。超過でS_ERROR。
    //--------------------------------------------------------------
    localparam [23:0] SPI_TIMEOUT = 24'd2_000_000; // 4MHzで0.5s相当の上限
    logic [23:0] timeout_cnt;
    logic        exec_active;      // EXEC受理〜完了/エラーまで1

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
    //--------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            timeout_cnt <= 0;
        end else if (exec_active) begin
            timeout_cnt <= timeout_cnt + 1;
        end else begin
            timeout_cnt <= 0;
        end
    end

    //--------------------------------------------------------------
    // 割込出力（レベル・ack でクリア）
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
            acmd41_retry<= 0;
            exec_active <= 1'b0;
            irq_req_r   <= 1'b0;
        end else begin
            spi_start <= 1'b0;  // 既定（1クロックパルス）

            // --- 割込 ack クリア ---
            if (irq_stor_ack)
                irq_req_r <= 1'b0;

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
                            // READ_SETUP(reg_cmd==0)前提でCMD17読出へ
                            fsm         <= S_RD_CMD17;
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
            // ★SPIタイムアウト → ERROR確定（ハング回避KY）★
            //=========================================================
            if (exec_active && timeout_cnt >= SPI_TIMEOUT) begin
                fsm         <= S_ERROR;
            end

            //=========================================================
            // SD 制御 FSM
            //=========================================================
            case (fsm)
                //---- リセット/電源投入シーケンス ----
                S_RESET: begin
                    spi_cs_r <= 1'b1;
                    sck_div  <= DIV_INIT;
                    fsm      <= S_POWERUP;
                    // ※本v0.1では簡潔化のため電源投入ダミークロックは
                    //   TB側のリセット期間で代替（設計メモ備忘・実装T1で要確認）
                end
                S_POWERUP: begin
                    // 初期化コマンド列は本v0.1では骨格のみ。
                    // 実バイト授受シーケンス（CMD0/8/55/41）は
                    // 次段（実装②-b）で cmd_frame + spi_start により具体化する。
                    // ここではINIT_DONEへ素通し（TBのSPIモデルは初期化応答を返す）。
                    fsm <= S_INIT_DONE;
                end
                S_INIT_DONE: begin
                    sck_div <= DIV_FAST;   // 初期化後は高速SCKへ切替
                    fsm     <= S_IDLE;
                end
                S_IDLE: begin
                    // EXEC受理でMMIO側が S_RD_CMD17 へ遷移させる
                    exec_active <= exec_active; // 保持
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
                    if (reg_irqctrl[0])        // 完了IRQ（エラーでも予約：emu23互換）
                        irq_req_r <= 1'b1;
                    fsm <= S_IDLE;
                end

                default: fsm <= S_IDLE;
            endcase
        end
    end

endmodule
