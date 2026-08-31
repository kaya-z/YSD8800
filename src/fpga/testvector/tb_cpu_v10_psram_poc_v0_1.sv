// =====================================================================
//  tb_cpu_v10_psram_poc_v0_1.sv   v0.1  (2026-08-20)
//   理想メモリ環境での CPI 測定 TB (emu23 改良4 段9 / M-5 手順0)
//
//  【目的】
//    emu23 の -mc (マシンサイクル模擬) が返すサイクル数と、
//    RTL の実クロック数を【同一の母数】で突合する。
//    母数は YSD8002 の SW_START..SW_STOP 区間 (score_r) とする。
//    ★emu23 側の "cycles=" も同一区間である (emu23 §9.1 注記)★
//
//  【派生元】tb_cpu_v8b_prod_v0_2.sv
//  【変更点】
//    (1) membus を ysd8800_v5_membus_v0_1 に差替 (理想メモリ)
//    (2) psram_clk を廃止 (理想メモリは cpu_clk 単一クロック)
//    (3) UART/SPI のマイルストーン判定を削除 (CPI 測定に不要)
//    (4) +IMG=<file> でロードする hex を指定可能に
//    (5) score_r 確定 (sw_busy_r の立下り) で結果を表示し終了
//
//  【KY38】_poc 接尾辞。V8-b 確定構成には一切手を触れていない。
//  【KY34】CPU コアは ysd8800_cpu_v0_1_FIXED.sv (v0.5.8) を無改修使用。
//
//  【重要・HANDOVER_CHAT139 §5.3】
//    RTL は SP を初期化しない。測定用 asm を自作する場合は
//    LDW SP,#$FC7E を必ず書くこと。本 TB は Dhrystone/YUI OS の
//    正規イメージを流すため、スタートアップが SP を設定する。
// =====================================================================
`timescale 1ns/1ps

module tb_cpu_v10_psram_poc;

    // ---- クロック・リセット ----
    logic cpu_clk;
    logic cpu_rst_n;

    initial cpu_clk = 0;
    always #125 cpu_clk = ~cpu_clk;      // 4MHz  (v8b_prod v0.2 と同一)

    // ★PSRAM 版は独立クロック 32MHz（v8b_prod v0.2 と同一）★
    // ★段10 掃引対応: psram_clk 半周期を +PSHALF= で外部指定可能★
    //   既定 15.625ns = 32MHz (v8b_prod v0.2 と同一)
    //   掃引例: +PSHALF=31.25 → 16MHz / +PSHALF=62.5 → 8MHz
    //   LAT-1(f) = A/f + B の A(psram依存分) と B(cpu依存分) を分離するため。
    real ps_half;
    logic psram_clk;
    initial begin
        if (!$value$plusargs("PSHALF=%f", ps_half)) ps_half = 15.625;
        $display("[V10] psram_clk half-period = %0.4f ns (%.3f MHz)",
                 ps_half, 1000.0/(2.0*ps_half));
        psram_clk = 0;
        forever #(ps_half) psram_clk = ~psram_clk;
    end

    // ---- CPU <-> membus 抽象バス ----
    logic [15:0] mem_addr;
    logic [7:0]  mem_wdata, mem_rdata;
    logic        mem_rd, mem_wr, mem_ready;

    // ---- 割込 ----
    logic [2:0] irq_in;
    logic       irq1_o, irq_timer_o, irq0_ack;

    // ★V8-b 本番 TB と同一の割込結線 (irq_in[0] にタイマー系 irq1_o)★
    assign irq_in = irq1_o ? 3'd1 : 3'd0;

    // ---- SPI (SD モデル: CPI 測定では未使用・idle 固定) ----
    logic spi_cs_n_o, spi_sck_o, spi_mosi_o;

    // ---- UART (送信のみ観測・受信は idle) ----
    logic       uart_tx_valid_o;
    logic [7:0] uart_tx_data_o;

    // ---- 診断 ----
    logic [15:0] dbg_pc, dbg_sp;
    logic        dbg_halt;

    // ---- サイクルカウンタ (参考値: リセット解除〜) ----
    integer cycle_count;
    initial cycle_count = 0;
    always @(posedge cpu_clk) begin
        if (cpu_rst_n) cycle_count <= cycle_count + 1;
    end

    // ---- イメージファイル名 ----
    string img_hex;

    // =================================================================
    //  DUT 1: CPU コア (v0.5.8・無改修)
    // =================================================================
    ysd8800_cpu_v0_1 u_cpu (
        .clk(cpu_clk), .rst_n(cpu_rst_n),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata),
        .mem_rd(mem_rd), .mem_wr(mem_wr), .mem_ready(mem_ready),
        .irq_in(irq_in),
        .dbg_pc(dbg_pc), .dbg_sp(dbg_sp), .dbg_halt(dbg_halt),
        .irq0_ack(irq0_ack)
    );

    // =================================================================
    //  DUT 2: 理想メモリ版 membus (_poc)
    // =================================================================
    ysd8800_v5_membus_v0_1 #(.PHYS_AW(20), .MEM_AW(20)) u_membus (
        .cpu_clk(cpu_clk), .cpu_rst_n(cpu_rst_n),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata),
        .mem_rd(mem_rd), .mem_wr(mem_wr), .mem_ready(mem_ready),
        .psram_clk(psram_clk), .psram_rst_n(cpu_rst_n),   // ★実PSRAM: 32MHz独立ドメイン★
        .irq1_o(irq1_o), .irq_timer_o(irq_timer_o), .irq0_ack(irq0_ack),
        .spi_cs_n_o(spi_cs_n_o), .spi_sck_o(spi_sck_o),
        .spi_mosi_o(spi_mosi_o), .spi_miso_i(1'b1),
        .uart_tx_valid_o(uart_tx_valid_o), .uart_tx_data_o(uart_tx_data_o),
        .uart_rx_valid_i(1'b0), .uart_rx_data_i(8'h00),
        .disk_sectors_i(32'd16)
    );


    // =================================================================
    //  リセット + イメージロード
    // =================================================================
    integer i;
    initial begin
        cpu_rst_n = 1'b0;

        if (!$value$plusargs("IMG=%s", img_hex)) img_hex = "dhry_final.hex";

        // メモリクリア (X 伝播防止)
        for (i = 0; i < (1<<20); i = i + 1)
            u_membus.u_psram_ctrl.mem[i] = 8'h00;

        $readmemh(img_hex, u_membus.u_psram_ctrl.mem);
        $display("[V10] image  = %0s", img_hex);
        $display("[V10] mem[0] = $%02x  mem[1] = $%02x",
                 u_membus.u_psram_ctrl.mem[0], u_membus.u_psram_ctrl.mem[1]);

        repeat (10) @(negedge cpu_clk);
        cpu_rst_n = 1'b1;
        $display("[V10] reset released");
    end

    // =================================================================
    //  ★測定: YSD8002 score_r 区間★
    // =================================================================
    //  sw_busy_r の立下り = SW_STOP = score_r 確定。
    //  ここで表示して終了する。emu23 の "cycles=" と同一定義。
    logic sw_busy_d;
    always @(posedge cpu_clk) begin
        if (!cpu_rst_n) begin
            sw_busy_d <= 1'b0;
        end else begin
            sw_busy_d <= u_membus.u_mmio_stub.u_ysd8002.sw_busy_r;
            if (sw_busy_d && !u_membus.u_mmio_stub.u_ysd8002.sw_busy_r) begin
                $display("=====================================");
                $display("[V10] ★score_r = %0d clk★",
                         u_membus.u_mmio_stub.u_ysd8002.score_r);
                $display("[V10]  (ref) cycle_count = %0d", cycle_count);
                $display("=====================================");
                $finish;
            end
        end
    end

    // ---- HALT 検出 (score 未確定のまま止まった場合) ----
    always @(posedge cpu_clk) begin
        if (cpu_rst_n && dbg_halt) begin
            $display("[V10] HALT @pc=$%04x  cycle_count=%0d", dbg_pc, cycle_count);
            $finish;
        end
    end

    // ---- タイムアウト ----
    initial begin
        #2_000_000_000;                   // 2s @4MHz = 8M clk (段10 掃引で低速条件に対応)
        $display("[V10] ★TIMEOUT★ cycle_count=%0d pc=$%04x", cycle_count, dbg_pc);
        $finish;
    end

endmodule

// =====================================================================
//  改版履歴
//   v0.1 (2026-08-20) 新規作成。段9 M-5 手順0 の再測定用。
//                     レビュー N-2 を受け、再現可能な資産として整備。
// =====================================================================
