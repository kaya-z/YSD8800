// ============================================================
//  tb_cpu_irq_iret_v0_1.sv   v0.1  (2026-07-06)
//  YSD8800 FPGA V1 : FSM第5-3段ステップ(c) 受理→IRET往復統合 実行TB
//
//  検証主眼(stage5_3c設計メモ§3 TB-1 / レビュー回答書v1.0 承認済):
//   - 割込受理(b)とIRET(a)が1シナリオで連結し、元コンテキストへ往復復帰する。
//   - LIFO対称: 受理 push(PC→FLAGS) / IRET pop(FLAGS→PC)。SPが往復でゼロ復帰。
//   - FLAGS往復: 受理直前IE=1 → 受理でpush後IE=0 → IRETで下位8bit復元しIE=1復帰。
//     (ハンドラ先頭・復帰先ともIE不変命令(LDWI=Z/N更新のみ)を配置=v0.5.4 TB知見)
//
//  黄金照合(emu23_v109.c): 受理 L1176-1188 / IRET L1213-1216(FLAGS下位8bit→PC)
//  レジスタ番号(emu23 get_reg_ptr L1104-1112): A=0 B=1 X=2 SP=3
//  エンコード: LDWI rD,#imm = 21 (rD<<4) lo hi / IRET = 04
//
//  golden(手計算):
//   ベクタ: irq_pending=1(timer) → vec=mem[irq_pending*2]=mem[2:3]=0x0300 (LE)  ※N-1明確化
//   リセット→PC=0100, SP=0000
//   0100 LDWI SP,#4000 : SP=4000                              (21 30 00 40)
//   0104 EI            : IE=1                                 (02)
//   0105 LDWI A,#0011  : A=0011  ← 受理はこの命令の実行「後」境界で発生 (21 00 11 00)
//   0109 LDWI B,#00BB  : B=00BB  ← IRET復帰後に実行される命令(復帰の証拠) (21 10 BB 00)
//   010D HALT          : 正常終了                             (01)
//   --- timer(irq_pending=1)ハンドラ @0300 ---
//   0300 LDWI A,#00AA  : A=00AA (ハンドラ実行の証拠。Q2: A=ハンドラ証拠)  (21 00 AA 00)
//   0304 IRET          : FLAGS←pop / PC←pop で 0109 へ復帰    (04)
//
//   受理シーケンス(0105実行完了→次境界S_IRQCHKで irq_pending=1 && IE=1):
//     push16(PC=0109先) → push16(FLAGS後) → IE=0 → PC←mem[2:3]=0300
//     SP: 4000 → 3FFE(PC push) → 3FFC(FLAGS push)
//     stack: mem[3FFE:3FFF]=0109(PC先push) / mem[3FFC:3FFD]=FLAGS(後push)
//   IRET(0304):
//     FLAGS←pop16()下位8bit(IE=1復元) → PC←pop16()=0109
//     SP: 3FFC → 3FFE(FLAGS pop) → 4000(PC pop)  ★往復でSP=4000復帰
//   復帰後: 0109 LDWI B,#00BB 実行 → 010D HALT
//
//   最終期待: PC=010E(HALT@010D次), A=00AA(ハンドラ証拠), B=00BB(復帰後証拠),
//             SP=4000(往復ゼロ復帰), IE=1(FLAGS往復でIE復帰), irq_pending=0,
//             stack mem[3FFE]=09,mem[3FFF]=01(push PC=0109 LE)
// ============================================================
`timescale 1ns/1ps

import ysd8800_idec_pkg::*;

module tb_cpu_irq_iret_v0_1;
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

    task chk16(input [255:0] tag, input [15:0] got, input [15:0] exp);
        begin
            if (got !== exp) begin
                $display("FAIL[%0s] got=%04x exp=%04x", tag, got, exp); errors=errors+1;
            end else $display("PASS[%0s] =%04x", tag, got);
        end
    endtask

    task chk8(input [255:0] tag, input [7:0] got, input [7:0] exp);
        begin
            if (got !== exp) begin
                $display("FAIL[%0s] got=%02x exp=%02x", tag, got, exp); errors=errors+1;
            end else $display("PASS[%0s] =%02x", tag, got);
        end
    endtask

    initial begin
        for (int i=0;i<65536;i=i+1) mem[i]=8'h00;
        mem[16'h0000]=8'h00; mem[16'h0001]=8'h01; // reset →0x0100

        // --- timer ベクタ: irq_pending=1 → vec=mem[irq_pending*2]=mem[2:3]=0x0300 (LE) --- (N-1)
        mem[16'h0002]=8'h00; mem[16'h0003]=8'h03;

        // 0100 LDWI SP,#4000
        mem[16'h0100]=8'h21; mem[16'h0101]=8'h30; mem[16'h0102]=8'h00; mem[16'h0103]=8'h40;
        // 0104 EI
        mem[16'h0104]=8'h02;
        // 0105 LDWI A,#0011
        mem[16'h0105]=8'h21; mem[16'h0106]=8'h00; mem[16'h0107]=8'h11; mem[16'h0108]=8'h00;
        // 0109 LDWI B,#00BB  (IRET復帰後に実行される=復帰の証拠)
        mem[16'h0109]=8'h21; mem[16'h010A]=8'h10; mem[16'h010B]=8'hBB; mem[16'h010C]=8'h00;
        // 010D HALT (正常終了)
        mem[16'h010D]=8'h01;

        // --- timer(irq_pending=1)ハンドラ @0300 ---
        // 0300 LDWI A,#00AA  (ハンドラ実行の証拠。Q2: A=ハンドラ証拠)
        mem[16'h0300]=8'h21; mem[16'h0301]=8'h00; mem[16'h0302]=8'hAA; mem[16'h0303]=8'h00;
        // 0304 IRET
        mem[16'h0304]=8'h04;

        irq_in = 3'd0;
        rst_n  = 0;
        repeat(2) @(negedge clk);
        rst_n  = 1;

        // EI(0104)実行後の命令境界で受理させる。PC>=0105観測でirq_in=1。
        // ハンドラ到達(0300域)でパルスを落とす(多重受理防止)。
        fork
            begin : irq_driver
                wait (dbg_pc == 16'h0105);
                @(posedge clk); #1;
                irq_in = 3'd1;   // timer IRQ (irq_pending=1)
                wait (dbg_pc >= 16'h0300 && dbg_pc <= 16'h0305);
                irq_in = 3'd0;
            end
        join_none

        begin : run
            integer g; g=0;
            while (!dbg_halt && g<800) begin @(posedge clk); #1; g=g+1; end
        end

        if (!dbg_halt) begin $display("FAIL: not halted @PC=%04x", dbg_pc); errors=errors+1; end
        else $display("PASS: halted @PC=%04x", dbg_pc);

        // 検証点1: ハンドラ実行の証拠 A=00AA (途中で0300到達)
        chk16("A(handler ran)", dbg_a, 16'h00AA);
        // 検証点2: IRET復帰後 0109実行の証拠 B=00BB (往復復帰成立)
        chk16("B(returned & ran 0109)", dbg_b, 16'h00BB);
        // 正常終了: HALT@010D の次 PC=010E (IRETで往路の010D側へ戻った)
        chk16("halt at 010E (normal end)", dbg_pc, 16'h010E);
        // 検証点3: SP往復ゼロ復帰 push2→pop2 で 4000
        chk16("SP round-trip =4000", dbg_sp, 16'h4000);
        // 検証点4: FLAGS往復 IE=1復帰 (受理でpushしたIE=1がIRETで復元)
        if (dbg_flags[7] !== 1'b1) begin
            $display("FAIL: IE=%0d exp 1 (IRETでFLAGS往復・IE復帰)", dbg_flags[7]); errors=errors+1;
        end else $display("PASS: IE=1 (FLAGS round-trip)");
        // irq_pending 受理クリア
        if (dbg_irq_pending !== 3'd0) begin
            $display("FAIL: irq_pending=%0d exp 0", dbg_irq_pending); errors=errors+1;
        end else $display("PASS: irq_pending=0");
        // 検証点6: スタックにpushされたPC(先push)=0109 が mem[3FFE:3FFF] にLE
        chk8("stack PC_lo @3FFE", mem[16'h3FFE], 8'h09);
        chk8("stack PC_hi @3FFF", mem[16'h3FFF], 8'h01);

        if (errors==0) $display("CPU_IRQ_IRET_TB: ALL PASS");
        else $display("CPU_IRQ_IRET_TB: %0d FAIL", errors);
        $finish;
    end
endmodule
