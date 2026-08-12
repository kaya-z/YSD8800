// tb_v37_w2c_diag_poc.sv  (V3.7 S5 デバッグ用・KY38 _poc)
//   仮説B検証: ハンドラの STB A,[$FCB2] で irq_stat がクリアされているか。
//   YSD8004内部の irq_stat_r / sel_i / we_i / wdata_i を直接観測する。
`timescale 1ns/1ps
import ysd8800_idec_pkg::*;

module tb_v37_w2c_diag_poc;

    logic        cpu_clk, cpu_rst_n, psram_clk, psram_rst_n;
    logic [15:0] mem_addr;
    logic [7:0]  mem_wdata, mem_rdata;
    logic        mem_rd, mem_wr, mem_ready;
    logic [2:0]  irq_in, dbg_irq_pending;
    logic [15:0] dbg_pc, dbg_a, dbg_b, dbg_x, dbg_sp, dbg_flags;
    logic        halted;
    logic        irq_src_uart_rx, irq_src_stor, irq_src_uart_tx;
    logic        irq1;
    logic [15:0] dbg_mmio_last_addr;
    logic [31:0] dbg_mmio_access_count;

    assign irq_in = irq1 ? 3'd2 : 3'd0;

    ysd8800_cpu_v0_1 u_cpu (
        .clk(cpu_clk), .rst_n(cpu_rst_n),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata),
        .mem_rd(mem_rd), .mem_wr(mem_wr), .mem_ready(mem_ready),
        .irq_in(irq_in),
        .dbg_pc(dbg_pc), .dbg_a(dbg_a), .dbg_b(dbg_b), .dbg_x(dbg_x),
        .dbg_sp(dbg_sp), .dbg_flags(dbg_flags), .dbg_halt(halted),
        .dbg_irq_pending(dbg_irq_pending)
    );

    ysd8800_v37_membus_v0_1 #(.PHYS_AW(20), .MEM_AW(20)) u_membus (
        .cpu_clk(cpu_clk), .cpu_rst_n(cpu_rst_n),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata),
        .mem_rd(mem_rd), .mem_wr(mem_wr), .mem_ready(mem_ready),
        .psram_clk(psram_clk), .psram_rst_n(psram_rst_n),
        .irq_src_uart_rx(irq_src_uart_rx), .irq_src_stor(irq_src_stor),
        .irq_src_uart_tx(irq_src_uart_tx), .irq1_o(irq1),
        .dbg_mmio_last_addr(dbg_mmio_last_addr),
        .dbg_mmio_access_count(dbg_mmio_access_count)
    );

    initial cpu_clk = 0;
    always #10 cpu_clk = ~cpu_clk;
    initial psram_clk = 0;
    always #0.5 psram_clk = ~psram_clk;

    // ---- YSD8004 内部への直接パス ----
    wire [7:0] ys4_stat = u_membus.u_mmio_stub.u_ysd8004.irq_stat_r;
    wire [7:0] ys4_mask = u_membus.u_mmio_stub.u_ysd8004.irq_mask_r;
    wire       ys4_sel  = u_membus.u_mmio_stub.u_ysd8004.sel_i;
    wire       ys4_we   = u_membus.u_mmio_stub.u_ysd8004.we_i;
    wire [1:0] ys4_addr = u_membus.u_mmio_stub.u_ysd8004.addr_i;
    wire [7:0] ys4_wd   = u_membus.u_mmio_stub.u_ysd8004.wdata_i;

    integer nwr = 0;

    // ★MMIOバスアクセスを全部ログる（$FCB2-$FCB5 のみ）★
    always @(posedge cpu_clk) begin
        if (cpu_rst_n && ys4_sel) begin
            $display("[%6t] YS4 SEL: we=%0b addr=%0d wd=%02h | stat=%02h mask=%02h irq1=%0b pc=%04h",
                     $time, ys4_we, ys4_addr, ys4_wd, ys4_stat, ys4_mask, irq1, dbg_pc);
            if (ys4_we) nwr = nwr + 1;
        end
    end

    initial begin
        $display("=== tb_v37_w2c_diag_poc : W2C hypothesis check ===");
        irq_src_uart_rx = 0; irq_src_stor = 0; irq_src_uart_tx = 0;
        cpu_rst_n = 0; psram_rst_n = 0;
        $readmemh("v37irq/v37irq.hex", u_membus.u_psram_ctrl.mem);
        repeat (5) @(posedge cpu_clk);
        cpu_rst_n = 1; psram_rst_n = 1;

        fork
            begin
                wait (dbg_pc >= 16'h0115 && dbg_pc <= 16'h0116);
                @(posedge cpu_clk);
                irq_src_uart_rx = 1'b1;
                @(posedge cpu_clk);
                irq_src_uart_rx = 1'b0;
                $display("[%6t] >>> irq_src pulsed. stat=%02h irq1=%0b", $time, ys4_stat, irq1);
            end
        join_none

        // 十分回して、ハンドラを2周するか（=無限ループか）を見る
        #150000;
        $display("--------------------------------------------");
        $display("stat=%02h mask=%02h irq1=%0b pc=%04h halted=%0b writes=%0d",
                 ys4_stat, ys4_mask, irq1, dbg_pc, halted, nwr);
        $display("A=%04h X=%04h SP=%04h irq_pending=%0d",
                 dbg_a, dbg_x, dbg_sp, dbg_irq_pending);
        $display("--------------------------------------------");
        if (ys4_stat != 8'h00 && irq1)
            $display(">>> 仮説B成立: irq_stat がクリアされず irq1 立ちっぱなし → 無限再受理");
        else if (!halted)
            $display(">>> 別要因: stat/irq1 は正常だが HALT に到達せず");
        else
            $display(">>> 正常完走");
        $finish;
    end

endmodule
