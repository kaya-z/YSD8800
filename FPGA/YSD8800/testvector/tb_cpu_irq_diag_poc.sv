// ============================================================
//  tb_cpu_irq_diag_poc.sv   (診断用・KY38 _poc / 本番不変)
//  目的: 割込受理7FAILの原因切り分け。
//   - EI(0104)実行後、rf_flags[7](IE)が実際に1になるか
//   - irq_in=1投入後、irq_pending がいつ1になるか(S_IRQCHK限定取込の位相)
//   - S_IRQCHK通過時の (irq_pending, flags_ie) を毎回ダンプ
//  観測は dut への階層参照で行う(dbgポート非依存)。
// ============================================================
`timescale 1ns/1ps
import ysd8800_idec_pkg::*;

module tb_cpu_irq_diag_poc;
    logic        clk, rst_n;
    logic [15:0] mem_addr;
    logic [7:0]  mem_wdata, mem_rdata;
    logic        mem_rd, mem_wr, mem_ready;
    logic [2:0]  irq_in;
    logic [15:0] dbg_pc, dbg_a, dbg_b, dbg_x, dbg_sp, dbg_flags;
    logic        dbg_halt;
    logic [2:0]  dbg_irq_pending;

    ysd8800_cpu_v0_1 dut (
        .clk(clk), .rst_n(rst_n),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata),
        .mem_rd(mem_rd), .mem_wr(mem_wr), .mem_ready(mem_ready),
        .irq_in(irq_in),
        .dbg_pc(dbg_pc), .dbg_a(dbg_a), .dbg_b(dbg_b), .dbg_x(dbg_x),
        .dbg_sp(dbg_sp), .dbg_flags(dbg_flags), .dbg_halt(dbg_halt),
        .dbg_irq_pending(dbg_irq_pending)
    );

    logic [7:0] mem [0:65535];
    assign mem_ready = 1'b1;
    always_comb mem_rdata = mem[mem_addr];
    always_ff @(posedge clk) if (mem_wr) mem[mem_addr] <= mem_wdata;

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        for (int i=0;i<65536;i=i+1) mem[i]=8'h00;
        mem[16'h0000]=8'h00; mem[16'h0001]=8'h01;   // reset →0x0100
        mem[16'h0002]=8'h00; mem[16'h0003]=8'h03;   // IRQ1 vec →0x0300
        // 0100 LDWI SP,#4000
        mem[16'h0100]=8'h21; mem[16'h0101]=8'h30; mem[16'h0102]=8'h00; mem[16'h0103]=8'h40;
        mem[16'h0104]=8'h02;                        // EI
        // 0105 LDWI A,#0011
        mem[16'h0105]=8'h21; mem[16'h0106]=8'h00; mem[16'h0107]=8'h11; mem[16'h0108]=8'h00;
        // 0109 LDWI A,#0022
        mem[16'h0109]=8'h21; mem[16'h010A]=8'h00; mem[16'h010B]=8'h22; mem[16'h010C]=8'h00;
        mem[16'h010D]=8'h01;                        // HALT
        mem[16'h0300]=8'h21; mem[16'h0301]=8'h10; mem[16'h0302]=8'hAA; mem[16'h0303]=8'h00;
        mem[16'h0304]=8'h01;

        irq_in = 3'd0;
        rst_n  = 0;
        repeat(2) @(negedge clk);
        rst_n  = 1;

        fork
            begin : irq_driver
                wait (dbg_pc == 16'h0105);
                @(posedge clk); #1;
                irq_in = 3'd1;
                $display(">> irq_in=1 asserted @time=%0t PC=%04x", $time, dbg_pc);
                wait (dbg_pc >= 16'h0300 && dbg_pc <= 16'h0305);
                irq_in = 3'd0;
            end
        join_none

        // 各posedge後に内部状態をダンプ。EIの書込サイクルを1つも漏らさない。
        //  ir(ラッチ済opcode)・dec_ie_set・rf_we_flags・rf_flags[7] を並べる。
        begin : mon
            integer g;
            for (g=0; g<40 && !dbg_halt; g=g+1) begin
                @(posedge clk); #1;
                $display("t=%0t st=%0d PC=%04x ir=%02x ie_set=%0d we_fl=%0d IE=%0d irqp=%0d",
                    $time, dut.state, dbg_pc, dut.ir, dut.dec_ie_set,
                    dut.rf_we_flags, dut.rf_flags[7], dut.irq_pending);
            end
        end

        $display("--- final: PC=%04x A=%04x IE=%0d irqp=%0d ---",
                 dbg_pc, dbg_a, dbg_flags[7], dbg_irq_pending);
        $finish;
    end
endmodule
