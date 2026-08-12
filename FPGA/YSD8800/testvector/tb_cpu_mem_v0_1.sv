// ============================================================
//  tb_cpu_mem_v0_1.sv   v0.1  (2026-07-04)
//  YSD8800 FPGA V1 : FSM第4-A段(メモリ LDW/STW ワード)実行TB
//
//  検証主眼:
//   - 全アドレッシング: [imm16](0x22/23), [rS]/[rD](0x24/25), [X+imm](0x26/27)
//   - エンディアン=LE (mem[a]=下位, mem[a+1]=上位)
//   - LDW=Z/N更新, STW=フラグ不変
//   - STW[rD](0x25): rD=アドレス, rS=データ ★役割逆転
//   - LDW[rS](0x24): rD=書込先, rS=アドレス
//   - アライメント例外は別TB(tb_cpu_memalign)で検証
//
//  golden(手計算):
//   0100 LDWI A,#1234 : A=1234
//   0104 LDWI X,#2000 : X=2000
//   0108 STW  A,[2000]: mem[2000]=1234 (rb=30: rS=A)
//   010C LDW  B,[2000]: B=1234, Z0 N0 (rb=10: rD=B)
//   0110 LDWI A,#BEEF : A=BEEF
//   0114 STW  A,[X+4] : mem[2004]=BEEF (rb=30: rS=A, X=2000)
//   0118 LDW  B,[X+4] : B=BEEF, Z0 N1 (rb=10: rD=B)
//   011C LDWI A,#2008 : A=2008 (アドレス)
//   0120 LDWI B,#00FF : B=00FF (データ)
//   0124 STW  B,[A]   : mem[2008]=00FF (rb=01: rD=A=addr, rS=B=data)
//   0126 LDW  X,[A]   : X=00FF, Z0 N0 (rb=20: rD=X, rS=A=addr)
//   0128 HALT
//  最終: A=2008 B=00FF X=00FF, mem[2000]=1234 mem[2004]=BEEF mem[2008]=00FF
// ============================================================
`timescale 1ns/1ps

import ysd8800_idec_pkg::*;

module tb_cpu_mem_v0_1;
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

    // 簡易メモリ・常時ready。書込(mem_wr)対応。
    logic [7:0] mem [0:65535];
    assign mem_ready = 1'b1;
    always_comb mem_rdata = mem[mem_addr];
    always_ff @(posedge clk) begin
        if (mem_wr) mem[mem_addr] <= mem_wdata;
    end

    initial clk = 0;
    always #5 clk = ~clk;

    task chk16(input [127:0] tag, input [15:0] got, input [15:0] exp);
        begin
            if (got !== exp) begin
                $display("FAIL[%0s] got=%04x exp=%04x", tag, got, exp); errors=errors+1;
            end else $display("PASS[%0s] =%04x", tag, got);
        end
    endtask

    initial begin
        for (int i=0;i<65536;i=i+1) mem[i]=8'h00;
        mem[16'h0000]=8'h00; mem[16'h0001]=8'h01; // reset →0x0100

        // 0100 LDWI A,#1234
        mem[16'h0100]=8'h21; mem[16'h0101]=8'h00; mem[16'h0102]=8'h34; mem[16'h0103]=8'h12;
        // 0104 LDWI X,#2000
        mem[16'h0104]=8'h21; mem[16'h0105]=8'h20; mem[16'h0106]=8'h00; mem[16'h0107]=8'h20;
        // 0108 STW A,[2000]  (rb=30: rS=A)
        mem[16'h0108]=8'h23; mem[16'h0109]=8'h30; mem[16'h010A]=8'h00; mem[16'h010B]=8'h20;
        // 010C LDW B,[2000]  (rb=10: rD=B)
        mem[16'h010C]=8'h22; mem[16'h010D]=8'h10; mem[16'h010E]=8'h00; mem[16'h010F]=8'h20;
        // 0110 LDWI A,#BEEF
        mem[16'h0110]=8'h21; mem[16'h0111]=8'h00; mem[16'h0112]=8'hEF; mem[16'h0113]=8'hBE;
        // 0114 STW A,[X+4]  (rb=30: rS=A)
        mem[16'h0114]=8'h27; mem[16'h0115]=8'h30; mem[16'h0116]=8'h04; mem[16'h0117]=8'h00;
        // 0118 LDW B,[X+4]  (rb=10: rD=B)
        mem[16'h0118]=8'h26; mem[16'h0119]=8'h10; mem[16'h011A]=8'h04; mem[16'h011B]=8'h00;
        // 011C LDWI A,#2008
        mem[16'h011C]=8'h21; mem[16'h011D]=8'h00; mem[16'h011E]=8'h08; mem[16'h011F]=8'h20;
        // 0120 LDWI B,#00FF
        mem[16'h0120]=8'h21; mem[16'h0121]=8'h10; mem[16'h0122]=8'hFF; mem[16'h0123]=8'h00;
        // 0124 STW B,[A]  (rb=01: rD=A=addr, rS=B=data)  2バイト命令
        mem[16'h0124]=8'h25; mem[16'h0125]=8'h01;
        // 0126 LDW X,[A]  (rb=20: rD=X, rS=A=addr)       2バイト命令
        mem[16'h0126]=8'h24; mem[16'h0127]=8'h20;
        // 0128 HALT
        mem[16'h0128]=8'h01;

        irq_in = 3'd0;
        rst_n  = 0;
        repeat(2) @(negedge clk);
        rst_n  = 1;

        // HALT到達まで実行
        begin : run
            integer g; g=0;
            while (!dbg_halt && g<300) begin @(posedge clk); #1; g=g+1; end
        end

        if (!dbg_halt) begin $display("FAIL: not halted @PC=%04x", dbg_pc); errors=errors+1; end
        else $display("PASS: halted @PC=%04x", dbg_pc);

        // レジスタ最終値
        chk16("A", dbg_a, 16'h2008);
        chk16("B", dbg_b, 16'h00FF);
        chk16("X", dbg_x, 16'h00FF);
        // LDW最終(X=00FF)のフラグ: Z0 N0
        if (dbg_flags[0]!==1'b0 || dbg_flags[1]!==1'b0) begin
            $display("FAIL: final flags Z=%0d N=%0d exp Z0 N0", dbg_flags[0], dbg_flags[1]);
            errors=errors+1;
        end else $display("PASS: final flags Z0 N0");

        // メモリ内容(LE: [a]=下位, [a+1]=上位)
        chk16("mem2000", {mem[16'h2001],mem[16'h2000]}, 16'h1234);
        chk16("mem2004", {mem[16'h2005],mem[16'h2004]}, 16'hBEEF);
        chk16("mem2008", {mem[16'h2009],mem[16'h2008]}, 16'h00FF);

        if (errors==0) $display("CPU_MEM_TB: ALL PASS");
        else $display("CPU_MEM_TB: %0d FAIL", errors);
        $finish;
    end
endmodule
