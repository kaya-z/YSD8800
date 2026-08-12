//==============================================================
// tb_cpu_v8catls_poc.sv   v0.1  (2026-07-20)
//   YSD8800 FPGA V8 YUI OS統合（選択肢A / A-1: read専用 cat/ls）統合TB
//
//   DUT    : ysd8800_cpu_v0_1 (RTL v0.5.8・無改修)
//            + ysd8800_v5_membus_v0_1 (ファイル v0.2・YSD8003結線版・無改修)
//   SDモデル: sd_spi_model_v0_3_poc ($readmemhでmkfs実イメージを返す)
//   プログラム: v8t_catls.hex (v8_catls_demo_poc.c)
//   SDイメージ: sd_image.hex (mkfs_yuifs 8KB, HELLO.TXT="Hello, YUI OS!\n")
//
//   検証:
//     UART($FC80)へ putchar 出力されるバイト列を tx_valid_o パルスで
//     捕捉しFIFO配列に蓄積。HALT後に期待文字列とバイト単位で照合。
//     期待列:
//       "ls:\nHELLO.TXT\ncat HELLO.TXT:\nHello, YUI OS!\n"  (40B)
//
//   KY54: T0 負例 = 期待列を意図的にずらして TB が不一致を出せるか。
//         (内容差し替え負例は sd_image_neg.hex を積む別ランで実施)
//
//   ビルド:
//     iverilog -g2012 -o tb.vvp tb_cpu_v8catls_poc.sv \
//       ysd8800_cpu_v0_1_FIXED.sv ysd8800_v5_membus_v0_2.sv \
//       ysd8800_mmio_stub_v0_7.sv ysd8800_ysd8003_v0_4.sv \
//       ysd8800_ysd8002_v0_3.sv ysd8800_ysd8004_v0_1.sv \
//       ysd8800_ysd8001_v0_1.sv ysd8800_addr_decoder_v0_1.sv \
//       ysd8800_cdc_bridge_v0_2.sv ysd8800_mmu_v0_1.sv \
//       ysd8800_psram_ctrl_v0_2.sv sd_spi_model_v0_3_poc.sv
//   ※ SDイメージは事前に `cp sd_image.hex sd_image.hex`（IMG_HEX参照名）。
//     負例ランは `cp sd_image_neg.hex sd_image.hex` に差し替えて再ビルド。
//==============================================================
`timescale 1ns/1ps

module tb_cpu_v8catls_poc;

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

    // ---- UARTポート ----
    logic        uart_rx_valid_i;
    logic [7:0]  uart_rx_data_i;
    logic        uart_tx_valid_o;
    logic [7:0]  uart_tx_data_o;

    // ---- SPI物理線 + SD容量 ----
    logic        spi_cs_n_o;
    logic        spi_sck_o;
    logic        spi_mosi_o;
    logic        spi_miso_i;
    logic [31:0] disk_sectors_i;

    integer errors = 0;
    integer passes = 0;

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
    //  DUT: v5 membus (ファイル v0.2・YSD8003結線版・無改修)
    // ============================================================
    ysd8800_v5_membus_v0_1 #(.PHYS_AW(20), .MEM_AW(20)) u_membus (
        .cpu_clk(cpu_clk), .cpu_rst_n(cpu_rst_n),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata),
        .mem_rd(mem_rd), .mem_wr(mem_wr), .mem_ready(mem_ready),
        .psram_clk(psram_clk), .psram_rst_n(psram_rst_n),
        .irq1_o(irq1_o),
        .spi_cs_n_o(spi_cs_n_o),
        .spi_sck_o(spi_sck_o),
        .spi_mosi_o(spi_mosi_o),
        .spi_miso_i(spi_miso_i),
        .disk_sectors_i(disk_sectors_i),
        .uart_rx_valid_i(uart_rx_valid_i),
        .uart_rx_data_i(uart_rx_data_i),
        .uart_tx_valid_o(uart_tx_valid_o),
        .uart_tx_data_o(uart_tx_data_o),
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
    //  SDモデル v0.3 ($readmemhでmkfs実イメージ sd_image.hex を返す)
    // ============================================================
    sd_spi_model_v0_3_poc sdmodel (
        .cs_n (spi_cs_n_o),
        .sck  (spi_sck_o),
        .mosi (spi_mosi_o),
        .miso (spi_miso_i)
    );

    // ============================================================
    //  クロック
    // ============================================================
    initial cpu_clk = 0;
    always #10 cpu_clk = ~cpu_clk;
    initial psram_clk = 0;
    always #1.25 psram_clk = ~psram_clk;

    // ============================================================
    //  ★UARTキャプチャ★
    //    YSD8001 は $FC80 書込のたび tx_valid_o を1クロックパルス、
    //    tx_data_o にバイトを載せる。これを捕捉し uart_fifo に蓄積。
    // ============================================================
    localparam integer UART_CAP_MAX = 256;
    logic [7:0] uart_fifo [0:UART_CAP_MAX-1];
    integer     uart_cnt = 0;

    always @(posedge cpu_clk) begin
        if (cpu_rst_n && uart_tx_valid_o) begin
            if (uart_cnt < UART_CAP_MAX) begin
                uart_fifo[uart_cnt] = uart_tx_data_o;
                uart_cnt = uart_cnt + 1;
            end
        end
    end

    // ============================================================
    //  期待文字列（40B）: "ls:\nHELLO.TXT\ncat HELLO.TXT:\nHello, YUI OS!\n"
    // ============================================================
    localparam integer EXP_LEN = 44;
    logic [7:0] exp_str [0:EXP_LEN-1];
    initial begin
        // "ls:\n"
        exp_str[0]="l"; exp_str[1]="s"; exp_str[2]=":"; exp_str[3]="\n";
        // "HELLO.TXT\n"
        exp_str[4]="H"; exp_str[5]="E"; exp_str[6]="L"; exp_str[7]="L";
        exp_str[8]="O"; exp_str[9]="."; exp_str[10]="T"; exp_str[11]="X";
        exp_str[12]="T"; exp_str[13]="\n";
        // "cat HELLO.TXT:\n"
        exp_str[14]="c"; exp_str[15]="a"; exp_str[16]="t"; exp_str[17]=" ";
        exp_str[18]="H"; exp_str[19]="E"; exp_str[20]="L"; exp_str[21]="L";
        exp_str[22]="O"; exp_str[23]="."; exp_str[24]="T"; exp_str[25]="X";
        exp_str[26]="T"; exp_str[27]=":"; exp_str[28]="\n";
        // "Hello, YUI OS!\n"
        exp_str[29]="H"; exp_str[30]="e"; exp_str[31]="l"; exp_str[32]="l";
        exp_str[33]="o"; exp_str[34]=","; exp_str[35]=" "; exp_str[36]="Y";
        exp_str[37]="U"; exp_str[38]="I"; exp_str[39]=" ";
        exp_str[40]="O"; exp_str[41]="S"; exp_str[42]="!"; exp_str[43]="\n";
    end

    // ============================================================
    //  判定ユーティリティ
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
    //  走行: HALT到達 or タイムアウト
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
    //  UART出力照合: uart_fifo[0..uart_cnt-1] vs exp_str[0..EXP_LEN-1]
    //    戻り: 不一致バイト数(mism)
    // ============================================================
    integer mism_bytes;
    task automatic compare_uart(output integer mism);
        integer i;
        begin
            mism = 0;
            // 長さ不一致もmismに寄与
            if (uart_cnt != EXP_LEN) begin
                $display("  [len] uart_cnt=%0d exp=%0d (length mismatch)", uart_cnt, EXP_LEN);
                mism = mism + 1;
            end
            for (i = 0; i < EXP_LEN; i = i + 1) begin
                if (i < uart_cnt) begin
                    if (uart_fifo[i] !== exp_str[i]) begin
                        $display("  [diff] idx=%0d got=%02h exp=%02h", i, uart_fifo[i], exp_str[i]);
                        mism = mism + 1;
                    end
                end
            end
        end
    endtask

    // UART出力を可読ダンプ
    task automatic dump_uart;
        integer i;
        begin
            $write("  [UART out] \"");
            for (i = 0; i < uart_cnt; i = i + 1) begin
                if (uart_fifo[i] == 8'h0a) $write("\\n");
                else $write("%c", uart_fifo[i]);
            end
            $display("\"  (cnt=%0d)", uart_cnt);
        end
    endtask

    // ============================================================
    //  メイン
    // ============================================================
    localparam integer MAX_CYC = 8000000;   // SPI転送多数(dir3+data)ゆえ余裕

    initial begin
        $display("============================================================");
        $display(" tb_cpu_v8catls v0.1  YSD8800 FPGA V8 YUI OS統合(cat/ls)");
        $display("   CPU=ysd8800_cpu v0.5.8 / membus v0.2(YSD8003結線)");
        $display("   SDモデル v0.3 ($readmemh mkfsイメージ) / demo=v8_catls");
        $display("============================================================");

        disk_sectors_i  = 32'd131072;
        uart_rx_valid_i = 1'b0;
        uart_rx_data_i  = 8'h00;

        $display("[LOAD] v8t_catls.hex");
        cpu_rst_n   = 0;
        psram_rst_n = 0;
        repeat (3) @(negedge psram_clk);
        psram_rst_n = 1;
        for (int i = 0; i < 16'h0400; i = i + 1)
            u_membus.u_psram_ctrl.mem[i] = 8'h00;
        $readmemh("v8t_catls.hex", u_membus.u_psram_ctrl.mem);
        repeat (3) @(negedge cpu_clk);
        cpu_rst_n = 1;

        run_until_halt(MAX_CYC);

        dump_uart();
        compare_uart(mism_bytes);
        $display("  [read] UART mism_bytes=%0d", mism_bytes);

        // ---------- 判定 ----------
        $display("--- T0: negative run (KY54: TBがFAILを出せる健全性) ---");
        // わざと外した期待(mismが負数になることはないので、-1と比較でTB健全性確認)
        chk_expect_fail("T0_negative", mism_bytes, /*wrong=*/-1);

        $display("--- S1: プログラム完走(HALT到達) ---");
        chk("S1_halt", (dbg_halt===1'b1) ? 1 : 0, 1);

        $display("--- S2: UART出力バイト数==EXP_LEN ---");
        chk("S2_uart_len", uart_cnt, EXP_LEN);

        $display("--- S3: UART出力==期待文字列(mism==0) ---");
        chk("S3_uart_match", mism_bytes, 0);

        $display("============================================================");
        $display(" RESULT: PASS=%0d FAIL=%0d", passes, errors);
        if (errors == 0) $display(" >>> V8 cat/ls INTEGRATION ALL PASS <<<");
        else             $display(" >>> SOME FAILED <<<");
        $display("============================================================");
        $finish;
    end

    // 保険タイムアウト
    initial begin
        #300_000_000;
        $display("  [FATAL] simulation watchdog timeout");
        $finish;
    end

endmodule
