// ============================================================
//  tb_cpu_memalign_v0_1.sv   v0.1  (2026-07-04)
//  YSD8800 FPGA V1 : FSM第4-A段 アライメント例外検証TB
//
//  検証主眼(本日KY核心):
//   - 奇数アドレスへのワードアクセスで irq_pending←3(align例外)
//   - 例外時メモリは書き換わらない(STW前値保持)
//   - 判断①(承認済): 検出のみ実装、受理(S_IRQ_ACCEPT)は第5段
//
//  golden:
//   0100 LDWI A,#AAAA : A=AAAA
//   0104 STW  A,[2001]: 奇数→例外。mem[2001],[2002]は0のまま。irq_pending=3
//   0108 HALT
// ============================================================
`timescale 1ns/1ps

import ysd8800_idec_pkg::*;

module tb_cpu_memalign_v0_1;
    logic        clk, rst_n;
    logic [15:0] mem_addr;
    logic [7:0]  mem_wdata, mem_rdata;
    logic        mem_rd, mem_wr, mem_ready;
    logic [2:0]  irq_in;
    logic [15:0] dbg_pc, dbg_a, dbg_b, dbg_x, dbg_sp, dbg_flags;
    logic        dbg_halt;

    integer errors = 0;

    ysd8800_cpu_v0_1 dut (
        .clk(clk), .rst_n(rst_n),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata),
        .mem_rd(mem_rd), .mem_wr(mem_wr), .mem_ready(mem_ready),
        .irq_in(irq_in),
        .dbg_pc(dbg_pc), .dbg_a(dbg_a), .dbg_b(dbg_b), .dbg_x(dbg_x),
        .dbg_sp(dbg_sp), .dbg_flags(dbg_flags), .dbg_halt(dbg_halt)
    );

    logic [7:0] mem [0:65535];
    assign mem_ready = 1'b1;
    always_comb mem_rdata = mem[mem_addr];
    always_ff @(posedge clk) begin
        if (mem_wr) mem[mem_addr] <= mem_wdata;
    end

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        for (int i=0;i<65536;i=i+1) mem[i]=8'h00;
        mem[16'h0000]=8'h00; mem[16'h0001]=8'h01; // reset →0x0100

        // 0100 LDWI A,#AAAA
        mem[16'h0100]=8'h21; mem[16'h0101]=8'h00; mem[16'h0102]=8'hAA; mem[16'h0103]=8'hAA;
        // 0104 STW A,[2001]  (rb=30: rS=A)  奇数アドレス
        mem[16'h0104]=8'h23; mem[16'h0105]=8'h30; mem[16'h0106]=8'h01; mem[16'h0107]=8'h20;
        // 0108 HALT
        mem[16'h0108]=8'h01;

        irq_in = 3'd0;
        rst_n  = 0;
        repeat(2) @(negedge clk);
        rst_n  = 1;

        begin : run
            integer g; g=0;
            while (!dbg_halt && g<100) begin @(posedge clk); #1; g=g+1; end
        end

        if (!dbg_halt) begin $display("FAIL: not halted @PC=%04x", dbg_pc); errors=errors+1; end
        else $display("PASS: halted @PC=%04x", dbg_pc);

        // irq_pending==3 (align例外) を階層参照で観測
        if (dut.irq_pending !== 3'd3) begin
            $display("FAIL: irq_pending=%0d exp 3(align)", dut.irq_pending); errors=errors+1;
        end else $display("PASS: irq_pending=3 (alignment exception検出)");

        // メモリ非書換確認: mem[2001],[2002]は0のまま
        if (mem[16'h2001]!==8'h00 || mem[16'h2002]!==8'h00) begin
            $display("FAIL: mem written @2001=%02x @2002=%02x exp 00 00",
                     mem[16'h2001], mem[16'h2002]); errors=errors+1;
        end else $display("PASS: mem非書換(例外でストア抑止)");

        if (errors==0) $display("CPU_MEMALIGN_TB: ALL PASS");
        else $display("CPU_MEMALIGN_TB: %0d FAIL", errors);
        $finish;
    end
endmodule
