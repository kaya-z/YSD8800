// ============================================================
//  tb_cpu_iret_v0_1.sv   v0.1  (2026-07-04)
//  YSD8800 FPGA V1 : FSM第5-3段ステップ(a) IRET単体 実行TB
//
//  検証主眼(HANDOVER §2.3 / レビューD-2 / 設計メモ §5-TB1):
//   - IRET(0x04,1B): FLAGS←pop(下位8bitのみ)→PC←pop の2回pop
//       emu23実照合(v109 L1215-1216): flags=(uint8_t)pop16(); pc=pop16()
//   - pop順序: FLAGS(先)→PC(後)。SPはpop2回で+4(post-inc)
//   - 【D-2実証】FLAGS復元は下位8bitのみ({8'h00,pop[7:0]})。pop値の上位8bitは
//       捨てられる。pop値0xABCD→FLAGS=0x00CD(上位AB消滅)を確認。
//   - pop_countによる多重pop制御(2→1→0)の正当性
//
//  golden(手計算): スタックに FLAGS/PC 復帰値を手動で仕込む。
//   受理相当の積み方(push PC→push FLAGS, pre-dec)の結果状態を模擬:
//     mem[3FFC]=CD,mem[3FFD]=AB : FLAGS pop値=0xABCD (先にpop)
//     mem[3FFE]=00,mem[3FFF]=02 : PC pop値=0x0200 (後にpop)
//   リセット→PC=0100, SP=0000
//   0100 LDWI SP,#3FFC : SP=3FFC (FLAGS/PC積載済を模擬) (21 30 FC 3F)
//   0104 IRET          : FLAGS←{00,CD}=00CD,SP→3FFE / PC←0200,SP→4000 (04)
//   --- IRET復帰先 @0200 ---
//   0200 LDWI A,#0055  : A=0055 (IRET復帰の証拠) (21 00 55 00)
//   0204 HALT          : 停止 (01)
//
//   最終: A=0055, PC=0205, SP=4000, FLAGS=0x00CD(上位AB消滅=D-2実証)
// ============================================================
`timescale 1ns/1ps

import ysd8800_idec_pkg::*;

module tb_cpu_iret_v0_1;
    logic        clk, rst_n;
    logic [15:0] mem_addr;
    logic [7:0]  mem_wdata, mem_rdata;
    logic        mem_rd, mem_wr, mem_ready;
    logic [2:0]  irq_in;
    logic [15:0] dbg_pc, dbg_a, dbg_b, dbg_x, dbg_sp, dbg_flags;
    logic        dbg_halt;
    logic [2:0]  dbg_irq_pending;

    integer errors = 0;

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

        // 0100 LDWI SP,#3FFC
        mem[16'h0100]=8'h21; mem[16'h0101]=8'h30; mem[16'h0102]=8'hFC; mem[16'h0103]=8'h3F;
        // 0104 IRET
        mem[16'h0104]=8'h04;

        // --- IRET復帰先 @0200 ---
        //  ※フラグ不変命令(MOV)のみ。LDWI等のフラグ更新命令を置くと復元FLAGSが
        //    上書きされD-2検証(FLAGS=0x00CD)が観測できないため(実測で判明)。
        //  MOV B,X : B←X(=0)。MOV=FLAGS不変(実照合)。IRET復帰の証拠はPC到達で確認。
        // 0200 MOV B,X  (20 12) rD=B(1),rS=X(2)
        mem[16'h0200]=8'h20; mem[16'h0201]=8'h12;
        // 0202 HALT
        mem[16'h0202]=8'h01;

        // --- スタック内容(手動): FLAGS pop値=0xABCD, PC pop値=0x0200 ---
        mem[16'h3FFC]=8'hCD; mem[16'h3FFD]=8'hAB;  // FLAGS(先pop): 0xABCD
        mem[16'h3FFE]=8'h00; mem[16'h3FFF]=8'h02;  // PC(後pop):   0x0200

        irq_in = 3'd0;
        rst_n  = 0;
        repeat(2) @(negedge clk);
        rst_n  = 1;

        begin : run
            integer g; g=0;
            while (!dbg_halt && g<400) begin @(posedge clk); #1; g=g+1; end
        end

        if (!dbg_halt) begin $display("FAIL: not halted @PC=%04x", dbg_pc); errors=errors+1; end
        else $display("PASS: halted @PC=%04x", dbg_pc);

        // --- IRET復帰先(0200)に到達しHALT(@0202の次=0203) ---
        chk16("final PC(returned to 0200)", dbg_pc, 16'h0203);
        // --- SP: pop2回で 3FFC→4000(+4) ---
        chk16("SP(+4 pop2)", dbg_sp, 16'h4000);
        // --- 【D-2実証】FLAGS=下位8bitのみ(pop値0xABCD→0x00CD, 上位AB消滅) ---
        //  復帰先はMOV(フラグ不変)なので復元FLAGSが保持される。
        chk16("FLAGS(low8 only)", dbg_flags, 16'h00CD);

        if (errors==0) $display("CPU_IRET_TB: ALL PASS");
        else $display("CPU_IRET_TB: %0d FAIL", errors);
        $finish;
    end
endmodule
