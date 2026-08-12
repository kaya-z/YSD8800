// ============================================================
//  tb_cpu_byte_v0_1.sv   v0.1  (2026-07-04)
//  YSD8800 FPGA V1 : FSM第4-B段(バイト LDB/STB, EXT 0x1F経由)実行TB
//
//  検証主眼:
//   - EXT(0x1F)プレフィックス→サブopデコード経路(S_SUBOP)
//   - LDB/STB × A/B × [imm16]/[X] (サブop 0x10-0x17)
//   - ゼロ拡張(LDB: 上位8bit=0), STB(下位8bitのみ書込)
//   - フラグ不変(LDB/STBはFLAGS変更しない ← LDW/set_znと対照)
//   - 奇数アドレスOK(バイトはアライメント例外なし ← rd8/wr8実照合)
//   - A/B選択= subop_r[1]
//
//  golden(手計算): X=3001(奇数)
//   0100 LDWI X,#3001 : X=3001
//   0104 LDWI B,#FFCD : B=FFCD (上位FFはゼロ拡張確認用)
//   0108 STB  B,[X]   : mem[3001]=CD (下位のみ) (1F 17) 奇数OK
//   010A LDWI A,#0000 : A=0000
//   010E LDB  A,[3001]: A=zero_ext(CD)=00CD (1F 10 01 30)
//   0112 LDWI B,#0000 : B=0000 (クリア)
//   0116 SUBI B,#0000 : B=0 → Z=1 (フラグ基準作成、LDWIでなくSUBIで)
//   011A LDB  B,[X]   : B=zero_ext(CD)=00CD, Z不変(=1のまま) (1F 13)
//   011C HALT
//  最終: A=00CD, B=00CD, X=3001, Z=1(最後のLDBで不変), mem[3001]=CD
// ============================================================
`timescale 1ns/1ps

import ysd8800_idec_pkg::*;

module tb_cpu_byte_v0_1;
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

        // 0100 LDWI X,#3001
        mem[16'h0100]=8'h21; mem[16'h0101]=8'h20; mem[16'h0102]=8'h01; mem[16'h0103]=8'h30;
        // 0104 LDWI B,#FFCD
        mem[16'h0104]=8'h21; mem[16'h0105]=8'h10; mem[16'h0106]=8'hCD; mem[16'h0107]=8'hFF;
        // 0108 STB B,[X]  (1F 17)  2バイト
        mem[16'h0108]=8'h1F; mem[16'h0109]=8'h17;
        // 010A LDWI A,#0000
        mem[16'h010A]=8'h21; mem[16'h010B]=8'h00; mem[16'h010C]=8'h00; mem[16'h010D]=8'h00;
        // 010E LDB A,[3001]  (1F 10 01 30)  A←00CD
        mem[16'h010E]=8'h1F; mem[16'h010F]=8'h10; mem[16'h0110]=8'h01; mem[16'h0111]=8'h30;
        // 0112 LDWI B,#0000
        mem[16'h0112]=8'h21; mem[16'h0113]=8'h10; mem[16'h0114]=8'h00; mem[16'h0115]=8'h00;
        // 0116 SUBI B,#0000  → B=0, Z=1 (フラグ基準)
        mem[16'h0116]=8'h43; mem[16'h0117]=8'h10; mem[16'h0118]=8'h00; mem[16'h0119]=8'h00;
        // 011A LDB B,[X]  (1F 13)  B←00CD, Z不変
        mem[16'h011A]=8'h1F; mem[16'h011B]=8'h13;
        // 011C HALT
        mem[16'h011C]=8'h01;

        irq_in = 3'd0;
        rst_n  = 0;
        repeat(2) @(negedge clk);
        rst_n  = 1;

        begin : run
            integer g; g=0;
            while (!dbg_halt && g<300) begin @(posedge clk); #1; g=g+1; end
        end

        if (!dbg_halt) begin $display("FAIL: not halted @PC=%04x", dbg_pc); errors=errors+1; end
        else $display("PASS: halted @PC=%04x", dbg_pc);

        chk16("A(LDB zero_ext)", dbg_a, 16'h00CD);
        chk16("B(LDB zero_ext)", dbg_b, 16'h00CD);
        chk16("X",              dbg_x, 16'h3001);
        // フラグ不変: SUBI後 Z=1、LDB/STBで変わらず Z=1
        if (dbg_flags[0]!==1'b1) begin
            $display("FAIL: Z=%0d exp 1(LDB/STBフラグ不変)", dbg_flags[0]); errors=errors+1;
        end else $display("PASS: Z=1 (LDB/STB フラグ不変)");
        // メモリ: 奇数アドレス3001に CD(最後のSTB B)
        if (mem[16'h3001]!==8'hCD) begin
            $display("FAIL: mem[3001]=%02x exp CD", mem[16'h3001]); errors=errors+1;
        end else $display("PASS: mem[3001]=CD (奇数アドレス書込OK)");
        // 隣接3002が汚れていないこと(バイト書込は1バイトのみ)
        if (mem[16'h3002]!==8'h00) begin
            $display("FAIL: mem[3002]=%02x exp 00 (バイト書込が隣接汚染)", mem[16'h3002]); errors=errors+1;
        end else $display("PASS: mem[3002]=00 (単一バイト書込)");

        if (errors==0) $display("CPU_BYTE_TB: ALL PASS");
        else $display("CPU_BYTE_TB: %0d FAIL", errors);
        $finish;
    end
endmodule
