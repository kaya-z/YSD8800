// ============================================================
//  tb_cpu_irq_v0_1.sv   v0.1  (2026-07-05)
//  YSD8800 FPGA V1 : FSM第5-3段ステップ(b) 割込受理 S_IRQ_ACCEPT 実行TB
//
//  検証主眼(HANDOVER §2.3 / レビューC-1,D-1 / emu23_v109 L1174-1188 黄金照合):
//   - 受理条件: irq_pending!=0 && IE(FLAGS bit7)==1
//   - push順序: PC(先) → FLAGS(後)  [emu23 L1180-1181, pre-dec]
//   - IEクリア: push2回の「後」にIE=0 (D-1) [emu23 L1182]
//   - ベクタ:   PC ← mem[irq_pending*2] 16bit LE [emu23 L1183-1184]
//               IRQ番号エンコード: 1=timer/2=device/3=align/4=syscall
//               本TCはirq_in=1(timer) → vec=mem[1*2]=mem[2:3]
//   - C-1実証: 受理中に新irq_inが来てもベクタ番号が書き換わらない
//               (irq_latch退避)。※本TCでは単一IRQなので間接確認に留める。
//
//  golden(手計算):
//   ベクタ: mem[0002]=00, mem[0003]=03 → IRQ1ハンドラ=0x0300
//   リセット→PC=0100, SP=0000
//   0100 LDWI SP,#4000 : SP=4000                        (21 30 00 40)
//   0104 EI            : IE=1(割込許可)                  (02)
//   0105 LDWI A,#0011  : A=0011  ← 受理はこの命令の実行「後」境界で発生 (21 00 11 00)
//   0109 LDWI A,#0022  : A=0022  ← 受理されれば実行されない(Aは0011のまま) (21 00 22 00)
//   010D HALT          : (受理失敗時のフォールバック停止)          (01)
//   --- IRQ1ハンドラ @0300 ---
//   0300 LDWI B,#00AA  : B=00AA (ハンドラ到達の証拠)      (21 10 AA 00)
//   0304 HALT          : 停止                            (01)
//
//   受理シーケンス(0105実行完了→次境界S_IRQCHKで irq_pending=1 && IE=1):
//     push16(PC=0109先) → push16(FLAGS後) → IE=0 → PC←mem[2]=0300
//     SP: 4000 → 3FFE(PC push) → 3FFC(FLAGS push)
//     stack: mem[3FFE:3FFF]=0109(PC,先push,上位アドレス側)
//            mem[3FFC:3FFD]=FLAGS(後push)
//
//   最終期待: PC=0305(ハンドラHALT@0304の次), B=00AA, A=0011,
//             SP=3FFC, IE=0, irq_pending=0(受理クリア)
//             mem[3FFE]=09,mem[3FFF]=01 (push PC=0109 LE)
// ============================================================
`timescale 1ns/1ps

import ysd8800_idec_pkg::*;

module tb_cpu_irq_v0_1;
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

    task chk8(input [127:0] tag, input [7:0] got, input [7:0] exp);
        begin
            if (got !== exp) begin
                $display("FAIL[%0s] got=%02x exp=%02x", tag, got, exp); errors=errors+1;
            end else $display("PASS[%0s] =%02x", tag, got);
        end
    endtask

    initial begin
        for (int i=0;i<65536;i=i+1) mem[i]=8'h00;
        mem[16'h0000]=8'h00; mem[16'h0001]=8'h01; // reset →0x0100

        // --- IRQ1(timer) ベクタ: mem[irq_pending*2]=mem[2] → 0x0300 (LE) ---
        mem[16'h0002]=8'h00; mem[16'h0003]=8'h03;

        // 0100 LDWI SP,#4000
        mem[16'h0100]=8'h21; mem[16'h0101]=8'h30; mem[16'h0102]=8'h00; mem[16'h0103]=8'h40;
        // 0104 EI
        mem[16'h0104]=8'h02;
        // 0105 LDWI A,#0011
        mem[16'h0105]=8'h21; mem[16'h0106]=8'h00; mem[16'h0107]=8'h11; mem[16'h0108]=8'h00;
        // 0109 LDWI A,#0022  (受理されれば実行されない)
        mem[16'h0109]=8'h21; mem[16'h010A]=8'h00; mem[16'h010B]=8'h22; mem[16'h010C]=8'h00;
        // 010D HALT (フォールバック)
        mem[16'h010D]=8'h01;

        // --- IRQ1ハンドラ @0300 ---
        // 0300 LDWI B,#00AA
        mem[16'h0300]=8'h21; mem[16'h0301]=8'h10; mem[16'h0302]=8'hAA; mem[16'h0303]=8'h00;
        // 0304 HALT
        mem[16'h0304]=8'h01;

        irq_in = 3'd0;
        rst_n  = 0;
        repeat(2) @(negedge clk);
        rst_n  = 1;

        // EIが効く前にirq_inを立てると IE=0 で受理されない。
        // EI(0104)実行後の最初の命令境界で受理させるため、PC>=0105を観測して irq_in=1。
        // (EI実行完了=PCが0105に進んだ後。維持しっぱなしで次S_IRQCHKで受理)
        fork
            begin : irq_driver
                // PCが0105(EI実行後)に到達するのを待ってirq_in=1
                wait (dbg_pc == 16'h0105);
                @(posedge clk); #1;
                irq_in = 3'd1;   // timer IRQ (irq_pending=1)
                // 受理されハンドラ(0300域)に入ったらパルスを落とす(多重受理防止)
                wait (dbg_pc >= 16'h0300 && dbg_pc <= 16'h0305);
                irq_in = 3'd0;
            end
        join_none

        begin : run
            integer g; g=0;
            while (!dbg_halt && g<600) begin @(posedge clk); #1; g=g+1; end
        end

        if (!dbg_halt) begin $display("FAIL: not halted @PC=%04x", dbg_pc); errors=errors+1; end
        else $display("PASS: halted @PC=%04x", dbg_pc);

        // --- ハンドラ0300に到達しHALT(@0304の次=0305) ---
        chk16("handler reached (PC=0305)", dbg_pc, 16'h0305);
        // --- ハンドラ実行の証拠 B=00AA ---
        chk16("B(handler ran)", dbg_b, 16'h00AA);
        // --- 受理は0105実行後・0109実行前: A=0011のまま(0022でない) ---
        chk16("A(irq before 0109)", dbg_a, 16'h0011);
        // --- SP: push2回で 4000→3FFC(-4) ---
        chk16("SP(-4 push2)", dbg_sp, 16'h3FFC);
        // --- IEクリア(受理後 FLAGS bit7=0) ---
        if (dbg_flags[7] !== 1'b0) begin
            $display("FAIL: IE=%0d exp 0 (受理後IEクリア D-1)", dbg_flags[7]); errors=errors+1;
        end else $display("PASS: IE=0 (受理後クリア D-1)");
        // --- irq_pending クリア(受理済) ---
        if (dbg_irq_pending !== 3'd0) begin
            $display("FAIL: irq_pending=%0d exp 0 (受理クリア)", dbg_irq_pending); errors=errors+1;
        end else $display("PASS: irq_pending=0 (受理クリア)");
        // --- スタック: PC(先push)=0109 が mem[3FFE:3FFF] にLEで積まれている ---
        chk8("stack PC_lo @3FFE", mem[16'h3FFE], 8'h09);
        chk8("stack PC_hi @3FFF", mem[16'h3FFF], 8'h01);

        if (errors==0) $display("CPU_IRQ_TB: ALL PASS");
        else $display("CPU_IRQ_TB: %0d FAIL", errors);
        $finish;
    end
endmodule
