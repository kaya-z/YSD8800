// ============================================================
//  tb_cpu_v6sdread.sv   v0.1  (2026-07-19)
//  YSD8800 FPGA V6-A / CHAT109 Step4 統合テストベンチ
//    module = tb_cpu_v6sdread
//    DUT    : ysd8800_cpu_v0_1 (RTL v0.5.8・無改修)
//             + ysd8800_v5_membus_v0_1 (ファイル v0.2・YSD8003結線版)
//    SDモデル: sd_spi_model_v0_1_poc (ファイル sd_spi_model_v0_2_poc.sv)
//    プログラム: v6t_sdread.hex (v6t_sdread.asm)
//
//  【検証内容】
//    CPU が実バス経由で YSD8003 へ CMD17 読出を発行し、512B を PIO で
//    読み出して既知パターン(data[i]=(LBA*512+i)&0xFF, LBA=1)と照合する。
//    ★実 MMIO デコード($FCA0-$FCB1)・実 wait-state(ready合流)・CPUストール
//      ・irq直結(本テストはポーリングのため未使用)を統合検証する。★
//
//  【判定 (単体TB T2/T3 を CPU経由で再現)】
//    S1: HALT 到達 (プログラム完走)
//    S2: RESULT($0306) == 0    (512B 全一致 = 成功)
//    S3: MISM($0300) == 0      (不一致カウント 0・S2の裏付け)
//    負例(KY54): わざと外した期待値で TB が FAIL を検出できることを先に確認。
//
//  【V5-TB(tb_cpu_v5timer_short)からの流用と差分】
//    流用: クロック(4MHz相当)・reset順序・pmem/pmemw・run_until_halt・chk。
//    差分: (1)membus は irq_src_stor 削除・SPI4線/disk_sectors 追加(v0.2)。
//          (2)SDモデルを spi 線へ接続。(3)ロードhex差替。(4)判定を RESULT に。
//
//  ★実行は新チャットで行う(本チャットは作成のみ)★
//    参照ビルド:
//      iverilog -g2012 -o tb.vvp tb_cpu_v6sdread.sv \
//        ysd8800_cpu_v0_1_FIXED.sv ysd8800_v5_membus_v0_2.sv \
//        ysd8800_mmio_stub_v0_7.sv ysd8800_ysd8003_v0_3.sv \
//        ysd8800_ysd8002_v0_3.sv ysd8800_ysd8004_v0_1.sv \
//        ysd8800_ysd8001_v0_1.sv ysd8800_addr_decoder_v0_1.sv \
//        ysd8800_cdc_bridge_v0_2.sv ysd8800_mmu_v0_1.sv \
//        ysd8800_psram_ctrl_v0_2.sv sd_spi_model_v0_2_poc.sv
//      timeout 600 vvp tb.vvp
// ============================================================
`timescale 1ns/1ps

module tb_cpu_v6sdread;

    // ---- クロック/リセット ----
    logic cpu_clk;
    logic cpu_rst_n;
    logic psram_clk;
    logic psram_rst_n;

    // ---- CPU <-> membus バス ----
    logic [15:0] mem_addr;
    logic [7:0]  mem_wdata;
    logic [7:0]  mem_rdata;
    logic        mem_rd;
    logic        mem_wr;
    logic        mem_ready;

    // ---- 割込 ----
    logic [2:0]  irq_in;
    logic        irq_timer_o;
    logic        irq1_o;
    logic        irq0_ack;

    // ---- CPU dbg ----
    logic [15:0] dbg_pc, dbg_a, dbg_b, dbg_x, dbg_sp, dbg_flags;
    logic        dbg_halt;
    logic [2:0]  dbg_irq_pending;

    // ---- membus dbg ----
    logic [15:0] dbg_mmio_last_addr;
    logic [31:0] dbg_mmio_access_count;
    logic        dbg_mmu_en;
    logic [19:0] dbg_phys_addr;
    logic [127:0] dbg_ptr_flat;
    logic [31:0] dbg_cycle;

    // ---- UART側ポート(本Tでは未使用: 入力0固定) ----
    logic        uart_rx_valid_i;
    logic [7:0]  uart_rx_data_i;
    logic        uart_tx_valid_o;
    logic [7:0]  uart_tx_data_o;

    // ---- ★V6-A新規: SPI物理線 + SD容量★ ----
    logic        spi_cs_n_o;
    logic        spi_sck_o;
    logic        spi_mosi_o;
    logic        spi_miso_i;
    logic [31:0] disk_sectors_i;

    integer errors = 0;
    integer passes = 0;

    // ============================================================
    //  割込結線（本TBはポーリング読出のため irq は実質未使用）
    //    タイマ優先の式は V5 と同型を維持(irq_timer_o=0固定で実質 irq1_o)。
    // ============================================================
    assign irq_in = irq_timer_o ? 3'd1 : (irq1_o ? 3'd2 : 3'd0);

    // ============================================================
    //  DUT: CPUコア (無改修)
    // ============================================================
    ysd8800_cpu_v0_1 dut_cpu (
        .clk(cpu_clk), .rst_n(cpu_rst_n),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata),
        .mem_rd(mem_rd), .mem_wr(mem_wr), .mem_ready(mem_ready),
        .irq_in(irq_in),
        .dbg_pc(dbg_pc), .dbg_a(dbg_a), .dbg_b(dbg_b), .dbg_x(dbg_x),
        .dbg_sp(dbg_sp), .dbg_flags(dbg_flags), .dbg_halt(dbg_halt),
        .dbg_irq_pending(dbg_irq_pending),
        .irq0_ack(irq0_ack)
    );

    // ============================================================
    //  DUT: v5 membus (ファイル v0.2・YSD8003結線版)
    //    ★irq_src_stor は削除された(stub内部で直結)★
    //    ★spi_*_o / spi_miso_i / disk_sectors_i を新規結線★
    // ============================================================
    ysd8800_v5_membus_v0_1 #(.PHYS_AW(20), .MEM_AW(20)) u_membus (
        .cpu_clk(cpu_clk), .cpu_rst_n(cpu_rst_n),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata),
        .mem_rd(mem_rd), .mem_wr(mem_wr), .mem_ready(mem_ready),
        .psram_clk(psram_clk), .psram_rst_n(psram_rst_n),
        .irq1_o(irq1_o),
        // ★V6-A: SPI物理層 + SD容量★
        .spi_cs_n_o(spi_cs_n_o),
        .spi_sck_o(spi_sck_o),
        .spi_mosi_o(spi_mosi_o),
        .spi_miso_i(spi_miso_i),
        .disk_sectors_i(disk_sectors_i),
        // UART(未使用)
        .uart_rx_valid_i(uart_rx_valid_i),
        .uart_rx_data_i(uart_rx_data_i),
        .uart_tx_valid_o(uart_tx_valid_o),
        .uart_tx_data_o(uart_tx_data_o),
        // タイマ(未使用だが結線維持)
        .irq_timer_o(irq_timer_o),
        .irq0_ack(irq0_ack),
        .dbg_mmio_last_addr(dbg_mmio_last_addr),
        .dbg_mmio_access_count(dbg_mmio_access_count),
        .dbg_mmu_en(dbg_mmu_en),
        .dbg_phys_addr(dbg_phys_addr),
        .dbg_ptr_flat(dbg_ptr_flat),
        .dbg_cycle(dbg_cycle)
    );

    // ============================================================
    //  SDモデル (SPI物理層の黄金リファレンス)
    //    LBA=n の 512B は data[i]=(n*512+i)&0xFF を返す(単体TB T2 と同一)。
    // ============================================================
    sd_spi_model_v0_1_poc sdmodel (
        .cs_n (spi_cs_n_o),
        .sck  (spi_sck_o),
        .mosi (spi_mosi_o),
        .miso (spi_miso_i)
    );

    // ============================================================
    //  クロック: CPU 4MHz相当(period=20) / PSRAM(period=2.5)
    //    ★V5-TB と同じ 8:1 比(案X)★
    // ============================================================
    initial cpu_clk = 0;
    always #10 cpu_clk = ~cpu_clk;
    initial psram_clk = 0;
    always #1.25 psram_clk = ~psram_clk;

    // ============================================================
    //  判定ユーティリティ (V5-TB流用)
    // ============================================================
    task automatic chk(input string name, input integer got, input integer exp);
        if (got === exp) begin
            passes = passes + 1;
            $display("  PASS %-28s got=%0d exp=%0d", name, got, exp);
        end else begin
            errors = errors + 1;
            $display("  FAIL %-28s got=%0d exp=%0d", name, got, exp);
        end
    endtask

    // 負例(KY54): わざと外した期待値で TB が不一致を検出できればPASS
    task automatic chk_expect_fail(input string name, input integer got, input integer wrong_exp);
        if (got !== wrong_exp) begin
            passes = passes + 1;
            $display("  PASS %-28s (TB detects mismatch: got=%0d != wrong=%0d)",
                     name, got, wrong_exp);
        end else begin
            errors = errors + 1;
            $display("  FAIL %-28s (TB missed: got==wrong==%0d)", name, got);
        end
    endtask

    // ============================================================
    //  PSRAMメモリ参照 (V5-TB流用)
    // ============================================================
    function automatic [7:0] pmem(input [19:0] a);
        pmem = u_membus.u_psram_ctrl.mem[a];
    endfunction
    function automatic [15:0] pmemw(input [19:0] a);
        pmemw = {pmem(a+1), pmem(a)};   // リトルエンディアン
    endfunction

    // ============================================================
    //  走行: HALT到達 or タイムアウトまで
    // ============================================================
    integer to_cyc;
    task automatic run_until_halt(input integer max_cyc);
        to_cyc = 0;
        while (dbg_halt !== 1'b1 && to_cyc < max_cyc) begin
            @(posedge cpu_clk);
            to_cyc = to_cyc + 1;
        end
        if (dbg_halt !== 1'b1)
            $display("  [WARN] timeout: HALT not reached in %0d cyc", max_cyc);
        else
            $display("  [info] HALT reached at cyc=%0d (PC=%04h)", to_cyc, dbg_pc);
    endtask

    // ============================================================
    //  メイン
    // ============================================================
    localparam integer MISM_ADDR   = 20'h00300;
    localparam integer RESULT_ADDR = 20'h00306;
    // SPI 実転送を含むため十分大きく取る(単体TB完走実績×余裕)
    localparam integer MAX_CYC     = 5000000;

    integer mism_v, result_v;

    initial begin
        $display("============================================================");
        $display(" tb_cpu_v6sdread v0.1  YSD8800 FPGA V6-A 統合TB");
        $display("   CPU=ysd8800_cpu v0.5.8 / membus v0.2(YSD8003結線)");
        $display("   YSD8003 CMD17読出 → 512B照合(LBA=1)");
        $display("============================================================");

        // SD容量: 64MB相当(単体TB と同値)
        disk_sectors_i  = 32'd131072;
        uart_rx_valid_i = 1'b0;
        uart_rx_data_i  = 8'h00;

        // ---------- プログラムロード(順序はV4/V5-TB実績を踏襲) ----------
        //   (1)reset保持 (2)mem[0..0x3FF]クリア(KY52) (3)$readmemh (4)reset解除
        $display("[LOAD] v6t_sdread.hex");
        cpu_rst_n   = 0;
        psram_rst_n = 0;
        repeat (3) @(negedge psram_clk);
        psram_rst_n = 1;
        // (1) メモリクリア: 未初期化X領域でのfetchハング防止(KY52)。
        //     結果領域($0300-)まで含めクリアするため 0x0400 まで。
        for (int i = 0; i < 16'h0400; i = i + 1)
            u_membus.u_psram_ctrl.mem[i] = 8'h00;
        // (2) プログラムロード
        $readmemh("v6t_sdread.hex", u_membus.u_psram_ctrl.mem);
        // (3) ロード完了後にreset解除
        repeat (3) @(negedge cpu_clk);
        cpu_rst_n = 1;

        // ---------- 走行 ----------
        run_until_halt(MAX_CYC);

        mism_v   = pmemw(MISM_ADDR);
        result_v = pmemw(RESULT_ADDR);
        $display("  [read] MISM=%0d  RESULT=%0d (0x%04h)", mism_v, result_v, result_v);

        // ---------- 判定 ----------
        $display("--- T0: negative run (KY54: TBがFAILを出せる健全性) ---");
        chk_expect_fail("T0_negative", result_v, /*wrong=*/16'hDEAD);

        $display("--- S1: プログラム完走(HALT到達) ---");
        chk("S1_halt", (dbg_halt===1'b1) ? 1 : 0, 1);

        $display("--- S2: RESULT==0 (512B全一致=成功) ---");
        chk("S2_result_zero", result_v, 0);

        $display("--- S3: MISM==0 (不一致カウント0) ---");
        chk("S3_mism_zero", mism_v, 0);

        $display("============================================================");
        $display(" RESULT: PASS=%0d FAIL=%0d", passes, errors);
        if (errors == 0) $display(" >>> V6-A INTEGRATION ALL PASS <<<");
        else             $display(" >>> SOME FAILED <<<");
        $display("============================================================");
        $finish;
    end

    // 保険タイムアウト(シミュレーション暴走防止)
    initial begin
        #200_000_000;   // 200ms
        $display("  [FATAL] simulation watchdog timeout");
        $finish;
    end

endmodule
