//==============================================================
// tb_cpu_v8d_char_fix_v0_1.sv   v0.1  (2026-07-26)
//   YSD8800 FPGA V8-D / V3: scc23 v2.04 char ロード幅是正 検証TB
//
//   目的:
//     scc23 v2.04（char ロード幅是正・LDW→LDB化）の RTL 完全構成での
//     合否判定。PSRAM 初期値非依存性を4パターン ($00/$FF/$AA/$55) で
//     実証する。全パターンで UART が期待列と一致すれば「初期値非依存
//     ＝修正成功」を確定する。
//
//   派生元: HANDOVER_CHAT120.md §4.1（案B・フル dhry_timer.c 版）
//           tb_cpu_v8d_stb_probe_v0_1.sv の構造を参考にしつつ、
//           Dhrystone 実行時プロファイル用の診断コード群
//           (Step D/F/G/I/J・pc_hist・エントリカウンタ等) は全削除。
//           修正判定に不要なため。
//
//   パラメータ化方針:
//     parameter [7:0] PSRAM_INIT_VAL = 8'h00;
//       → 4版走行時に +define+INIT_VAL=xx で切り替え or
//         iverilog -PPSRAM_INIT_VAL=8'hFF 等で切替
//       ★1本のTBを4回走行することでコード重複を回避★
//
//   DUT    : ysd8800_cpu_v0_1 (RTL v0.5.8・無改修)
//            + ysd8800_v5_membus_v0_1 (ファイル v0.2・YSD8003結線版・無改修)
//   SDモデル: 無し (削除・案S1・Dhrystone は SD 未使用)
//            spi_miso_i=1'b1 tie-off / disk_sectors_i=32'd0 tie-off
//   プログラム: dhry_final.hex (フル dhry_timer.c ISA2.3 build・21846B・
//              scc23 v2.04 / hasm23 v1.04 / lnk23 v2.01 でビルド)
//
//   検証:
//     UART($FC80)へ putchar 出力されるバイト列を tx_valid_o パルスで
//     捕捉しFIFO配列に蓄積。HALT後に期待文字列とバイト単位で照合。
//     期待列: "N=10\nP:20" (9B・順序込み)
//       - "N=10\n" (5B): dhry_timer.c dhrystone()内・print_num(10)
//       - "P:20"  (4B): dhry_timer.c main()内・result==20
//
//   合格判定:
//     S1_halt        : HALT到達
//     S2_uart_len    : uart_cnt == 9
//     S3_uart_match  : mism_bytes == 0 (順序込み9B一致)
//     T0_negative    : TB健全性 (KY54踏襲)
//
//   ビルド例 (4パターン):
//     iverilog -g2012 -PPSRAM_INIT_VAL=8'h00 -o tb_00.vvp \
//       tb_cpu_v8d_char_fix_v0_1.sv \
//       ysd8800_cpu_v0_1_FIXED.sv ysd8800_v5_membus_v0_2.sv \
//       ysd8800_mmio_stub_v0_7.sv ysd8800_ysd8003_v0_4.sv \
//       ysd8800_ysd8002_v0_3.sv ysd8800_ysd8004_v0_1.sv \
//       ysd8800_ysd8001_v0_1.sv ysd8800_addr_decoder_v0_1.sv \
//       ysd8800_cdc_bridge_v0_2.sv ysd8800_mmu_v0_1.sv \
//       ysd8800_psram_ctrl_v0_2.sv
//     ※ INIT_VAL は 00/FF/AA/55 で切替
//
//   改版履歴:
//     v0.1 (2026-07-26) 初版。CHAT121 で作成。HANDOVER_CHAT120.md §4.1
//                       (案B・パラメータ化1本・4回走行) 準拠。
//                       PSRAM 初期化を1KBから MEM_AW=20 全域(1MB)に拡張。
//                       診断コード群を削除し、合否判定のみに集中。
//==============================================================
`timescale 1ns/1ps

module tb_cpu_v8d_char_fix_v0_1;

    // ============================================================
    //  パラメータ (4版切替用)
    //    iverilog -PPSRAM_INIT_VAL=8'h00 等で外部から指定
    // ============================================================
    parameter [7:0] PSRAM_INIT_VAL = 8'h00;

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

    // ---- SPI物理線 (案S1: 未接続tie-off) ----
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
    //  クロック
    // ============================================================
    initial cpu_clk = 0;
    always #10 cpu_clk = ~cpu_clk;
    initial psram_clk = 0;
    always #1.25 psram_clk = ~psram_clk;

    // ============================================================
    //  UARTキャプチャ
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
    //  期待文字列 (9B): "N=10\nP:20"  [V3 フル dhry_timer.c 版]
    //    emu23 v1.11 で scc23 v2.04 build の dhry_final.bin を実行し
    //    stdout 分離採取した実UART出力 (2026-07-26採取)
    //    KY-G準拠: 順序込み9B照合
    // ============================================================
    localparam integer EXP_LEN = 9;
    logic [7:0] exp_str [0:EXP_LEN-1];
    initial begin
        // "N=10\n" (5B)
        exp_str[0]="N"; exp_str[1]="="; exp_str[2]="1"; exp_str[3]="0";
        exp_str[4]="\n";
        // "P:20" (4B)
        exp_str[5]="P"; exp_str[6]=":"; exp_str[7]="2"; exp_str[8]="0";
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
    //    診断ダンプなし (合否判定のみに集中・CHAT121 スコープ)
    // ============================================================
    integer to_cyc;
    task automatic run_until_halt(input integer max_cyc);
        integer next_dump;
        to_cyc = 0;
        next_dump = 1000000;
        while (dbg_halt !== 1'b1 && to_cyc < max_cyc) begin
            @(posedge cpu_clk);
            to_cyc = to_cyc + 1;
            if (to_cyc >= next_dump) begin
                $display("  [heartbeat cyc=%0d] PC=%04h SP=%04h uart_cnt=%0d",
                         to_cyc, dbg_pc, dbg_sp, uart_cnt);
                next_dump = next_dump + 1000000;
            end
        end
        if (dbg_halt === 1'b1)
            $display("  [HALT reached at cyc=%0d]", to_cyc);
        else
            $display("  [TIMEOUT at cyc=%0d (max=%0d)]", to_cyc, max_cyc);
    endtask

    // ============================================================
    //  UART出力照合: uart_fifo[0..uart_cnt-1] vs exp_str[0..EXP_LEN-1]
    // ============================================================
    integer mism_bytes;
    task automatic compare_uart(output integer mism);
        integer i;
        begin
            mism = 0;
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
    //  MAX_CYC 根拠 (HANDOVER120 §4.1):
    //    emu23 実測 48,785 cyc × PSRAM wait 5〜20倍膨張想定 = 24万〜98万 cyc
    //    フル版 (Number_Of_Runs=10) は N=1版の約10倍で 240万〜980万 cyc 見込み
    //    上限 500万 cyc に設定。想定上限に達したらタイムアウトとして判定
    localparam integer MAX_CYC = 5000000;

    initial begin
        $display("============================================================");
        $display(" tb_cpu_v8d_char_fix_v0_1  YSD8800 FPGA V8-D V3");
        $display("   scc23 v2.04 char ロード幅是正 検証 (フル dhry_timer.c)");
        $display("   PSRAM_INIT_VAL = 8'h%02h", PSRAM_INIT_VAL);
        $display("   期待UART: \"N=10\\nP:20\" (9B)");
        $display("============================================================");

        // 案S1: SD tie-off
        spi_miso_i      = 1'b1;
        disk_sectors_i  = 32'd0;
        uart_rx_valid_i = 1'b0;
        uart_rx_data_i  = 8'h00;

        cpu_rst_n   = 0;
        psram_rst_n = 0;
        repeat (3) @(negedge psram_clk);
        psram_rst_n = 1;

        // ★V3 修正の核心: PSRAM 全域を PSRAM_INIT_VAL で初期化★
        //   CHAT119 で真因確定: 旧TBの1KB初期化のため、未初期化領域が
        //   'x や偶発値になっていた。scc23 v2.03 は char ロードで
        //   LDW=2バイト読出→上位バイトが未初期化領域を踏むと 'x 化する。
        //   scc23 v2.04 (LDB=1バイト読出) では上位バイトを読まないため
        //   初期値非依存となるはず → 本TBで4パターン走行して実証する。
        $display("[INIT] PSRAM 全域 (MEM_AW=20 → 1MB) を 8'h%02h で初期化", PSRAM_INIT_VAL);
        for (int i = 0; i < (1<<20); i = i + 1)
            u_membus.u_psram_ctrl.mem[i] = PSRAM_INIT_VAL;

        $display("[LOAD] dhry_final.hex (scc23 v2.04 build)");
        $readmemh("dhry_final.hex", u_membus.u_psram_ctrl.mem);

        repeat (3) @(negedge cpu_clk);
        cpu_rst_n = 1;

        run_until_halt(MAX_CYC);

        dump_uart();
        compare_uart(mism_bytes);
        $display("  [read] UART mism_bytes=%0d", mism_bytes);

        // ---------- 判定 ----------
        $display("--- T0: negative run (KY54踏襲: TBがFAILを出せる健全性) ---");
        chk_expect_fail("T0_negative", mism_bytes, /*wrong=*/-1);

        $display("--- S1: プログラム完走(HALT到達) ---");
        chk("S1_halt", (dbg_halt===1'b1) ? 1 : 0, 1);

        $display("--- S2: UART出力バイト数==EXP_LEN(9) ---");
        chk("S2_uart_len", uart_cnt, EXP_LEN);

        $display("--- S3: UART出力==期待文字列(mism==0・順序込み9B) ---");
        chk("S3_uart_match", mism_bytes, 0);

        $display("============================================================");
        $display(" RESULT (PSRAM_INIT_VAL=8'h%02h): PASS=%0d FAIL=%0d",
                 PSRAM_INIT_VAL, passes, errors);
        if (errors == 0) $display(" >>> V8-D V3 char_fix ALL PASS (INIT=%02h) <<<", PSRAM_INIT_VAL);
        else             $display(" >>> V8-D V3 char_fix SOME FAILED (INIT=%02h) <<<", PSRAM_INIT_VAL);
        $display("============================================================");
        $finish;
    end

    // 保険タイムアウト (500万cyc × ~20ns = 100ms シミュレーション時間の10倍)
    initial begin
        #1_000_000_000;
        $display("  [FATAL] simulation watchdog timeout");
        $finish;
    end

endmodule
