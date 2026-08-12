// ============================================================
//  tb_cpu_align_irq_v0_1.sv   v0.1  (2026-07-06)
//  YSD8800 FPGA V1 : FSM第5-3段ステップ(c) アライメント例外受理 実行TB (E-1)
//
//  検証主眼(stage5_3c設計メモ§3 TB-2 / レビュー回答書v1.0 承認・確定事項):
//   - 奇数アドレスへの16bitアクセス(LDW/STW)で align例外 → irq_pending=3
//     → 通常受理経路で vec=mem[irq_pending*2]=mem[6:7] のハンドラへ → IRET復帰。
//   - E-1: LDW経路・STW経路の両方で受理往復が成立(rd16/wr16対称, 回答書§4 E-1)。
//   - Q3(確定): align例外でpushされるPC = 例外命令の「次命令PC」(黄金=emu23が正)。
//     emu23: FETCH pc++ → オペランド pc++ → rd16/wr16でirq_pending=3 & early return。
//     この時点でPCは次命令を指す。RTLもS_DECODE検出・PCはfetch時更新済で同挙動を検証。
//   - C-1(確定): align例外命令は副作用なし(fault-then-continue, MC6809のSWI/割込と
//     同思想=次命令PC退避・命令リトライなし)。LDWのロード先レジスタは不変。
//     ※C-1の一意判定のため A初期値/ハンドラ書込値/期待値 を3つとも別値に設計(本日KY)。
//
//  黄金照合(emu23_v109.c): align rd16 L577-578 / wr16 L646-647 (共に irq_pending=3),
//    受理 L1176-1188, IRET L1213-1216。
//  レジスタ番号: A=0 B=1 X=2 SP=3。
//  エンコード:
//    LDWI rD,#imm = 21 (rD<<4) lo hi
//    LDW  A,[X]   = 24 02   (rD=A=0, rS=X=2 ; eff_addr=rS=X)
//    STW  A,[X]   = 25 20   (rD=X=2=アドレス, rS=A=0=データ ; eff_addr=rD=X ★役割逆転)
//    IRET         = 04
//
//  ---- ケース構成(同一TB内で2ケースを順に実行し、間でリセット) ----
//  【共通メモリ配置】
//   reset vec : mem[0:1] = 00 01 → PC=0x0100
//   align vec : mem[6:7] = 00 03 → align(irq_pending=3)ハンドラ=0x0300
//
//  【Case-LDW】
//   0100 LDWI SP,#4000                 (21 30 00 40)
//   0104 EI                            (02)
//   0105 LDWI A,#1234  A=0x1234        (21 00 34 12)  ← C-1: この値が保持されるべき
//   0109 LDWI X,#2001  X=0x2001(奇数)  (21 20 01 20)
//   010D LDW  A,[X]    ★align例外(2001奇数)→irq_pending=3, A書換なし(C-1) (24 02)
//   010F HALT          ← align push PC=次命令=0x010F を検証(Q3)          (01)
//   --- alignハンドラ @0300 ---
//   0300 LDWI B,#00AA  B=0x00AA(ハンドラ到達の証拠, Aは触らない)         (21 10 AA 00)
//   0304 IRET          FLAGS←pop/PC←pop → 0x010F へ復帰                 (04)
//   期待: 復帰後010F HALT。A=0x1234(不変=C-1), B=0x00AA(ハンドラ実行),
//         push PC=010F(次命令=Q3), SP=4000(往復), IE=1(往復復帰)
//
//  【Case-STW】(0x010D を STW A,[X] に変更。他同一)
//   010D STW  A,[X]    ★align例外(wr16,2001奇数)→irq_pending=3            (25 20)
//   期待: LDWと同様に受理往復。STWは書込なので「書込が起きない」ことは
//         mem[2000:2001]が不変(00)で確認(wr16 early return)。
// ============================================================
`timescale 1ns/1ps

import ysd8800_idec_pkg::*;

module tb_cpu_align_irq_v0_1;
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

    // 共通プログラムロード。opD=0x010D命令(LDW or STW)を引数で差し替え。
    task load_program(input [7:0] op_lo, input [7:0] op_hi);
        integer i;
        begin
            for (i=0;i<65536;i=i+1) mem[i]=8'h00;
            mem[16'h0000]=8'h00; mem[16'h0001]=8'h01;      // reset → 0x0100
            mem[16'h0006]=8'h00; mem[16'h0007]=8'h03;      // align vec(irq3*2=6) → 0x0300
            // 0100 LDWI SP,#4000
            mem[16'h0100]=8'h21; mem[16'h0101]=8'h30; mem[16'h0102]=8'h00; mem[16'h0103]=8'h40;
            // 0104 EI
            mem[16'h0104]=8'h02;
            // 0105 LDWI A,#1234  (C-1: 保持されるべき値)
            mem[16'h0105]=8'h21; mem[16'h0106]=8'h00; mem[16'h0107]=8'h34; mem[16'h0108]=8'h12;
            // 0109 LDWI X,#2001  (奇数アドレス)
            mem[16'h0109]=8'h21; mem[16'h010A]=8'h20; mem[16'h010B]=8'h01; mem[16'h010C]=8'h20;
            // 010D  <op>  (LDW A,[X]=24 02  or  STW A,[X]=25 20) ★align例外
            mem[16'h010D]=op_lo; mem[16'h010E]=op_hi;
            // 010F HALT
            mem[16'h010F]=8'h01;
            // --- alignハンドラ @0300 ---
            // 0300 LDWI B,#00AA
            mem[16'h0300]=8'h21; mem[16'h0301]=8'h10; mem[16'h0302]=8'hAA; mem[16'h0303]=8'h00;
            // 0304 IRET
            mem[16'h0304]=8'h04;
        end
    endtask

    task run_reset;
        begin
            irq_in = 3'd0;
            rst_n  = 0;
            repeat(2) @(negedge clk);
            rst_n  = 1;
        end
    endtask

    task run_until_halt(output integer gcnt);
        integer g;
        begin
            g=0;
            while (!dbg_halt && g<800) begin @(posedge clk); #1; g=g+1; end
            gcnt=g;
        end
    endtask

    integer gc;

    initial begin
        // =======================================================
        //  Case-LDW : LDW A,[X] で align例外(read)
        // =======================================================
        $display("=== Case-LDW (LDW A,[X], read align) ===");
        load_program(8'h24, 8'h02);   // LDW A,[X]
        run_reset();
        run_until_halt(gc);

        if (!dbg_halt) begin $display("FAIL: LDW not halted @PC=%04x", dbg_pc); errors=errors+1; end
        else $display("PASS: LDW halted @PC=%04x", dbg_pc);
        // 受理往復: ハンドラ到達→IRET→010F HALTの次=0110
        chk16("LDW: PC end(0110)",      dbg_pc, 16'h0110);
        chk16("LDW: B handler ran(00AA)",dbg_b, 16'h00AA);
        // C-1: align例外命令(LDW A,[X])は副作用なし → A不変(0x1234保持)
        chk16("LDW: A unchanged(C-1)",   dbg_a, 16'h1234);
        // SP往復ゼロ復帰
        chk16("LDW: SP round-trip(4000)",dbg_sp, 16'h4000);
        // IE往復復帰
        if (dbg_flags[7]!==1'b1) begin $display("FAIL: LDW IE=%0d exp1",dbg_flags[7]); errors=errors+1; end
        else $display("PASS: LDW IE=1 (round-trip)");
        // irq_pending 受理クリア
        if (dbg_irq_pending!==3'd0) begin $display("FAIL: LDW irqp=%0d exp0",dbg_irq_pending); errors=errors+1; end
        else $display("PASS: LDW irq_pending=0");
        // Q3: align push PC = 次命令PC = 0x010F。stack(SP=4000→pop済なので mem上に残る)
        //   push順: PC(先,上位アドレス側 3FFE) → FLAGS(後, 3FFC)
        chk8("LDW: push PC_lo @3FFE(Q3=0F)", mem[16'h3FFE], 8'h0F);
        chk8("LDW: push PC_hi @3FFF(Q3=01)", mem[16'h3FFF], 8'h01);

        // =======================================================
        //  Case-STW : STW A,[X] で align例外(write)
        // =======================================================
        $display("=== Case-STW (STW A,[X], write align) ===");
        load_program(8'h25, 8'h20);   // STW A,[X]  (rD=X=アドレス, rS=A=データ)
        run_reset();
        run_until_halt(gc);

        if (!dbg_halt) begin $display("FAIL: STW not halted @PC=%04x", dbg_pc); errors=errors+1; end
        else $display("PASS: STW halted @PC=%04x", dbg_pc);
        chk16("STW: PC end(0110)",      dbg_pc, 16'h0110);
        chk16("STW: B handler ran(00AA)",dbg_b, 16'h00AA);
        // STW align: 書込は起きない(wr16 early return) → mem[2000:2001]不変(00)
        chk8("STW: no write @2000(C-1)", mem[16'h2000], 8'h00);
        chk8("STW: no write @2001(C-1)", mem[16'h2001], 8'h00);
        chk16("STW: SP round-trip(4000)",dbg_sp, 16'h4000);
        if (dbg_flags[7]!==1'b1) begin $display("FAIL: STW IE=%0d exp1",dbg_flags[7]); errors=errors+1; end
        else $display("PASS: STW IE=1 (round-trip)");
        if (dbg_irq_pending!==3'd0) begin $display("FAIL: STW irqp=%0d exp0",dbg_irq_pending); errors=errors+1; end
        else $display("PASS: STW irq_pending=0");
        chk8("STW: push PC_lo @3FFE(Q3=0F)", mem[16'h3FFE], 8'h0F);
        chk8("STW: push PC_hi @3FFF(Q3=01)", mem[16'h3FFF], 8'h01);

        if (errors==0) $display("CPU_ALIGN_IRQ_TB: ALL PASS");
        else $display("CPU_ALIGN_IRQ_TB: %0d FAIL", errors);
        $finish;
    end
endmodule
