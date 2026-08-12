// ============================================================
//  tb_cpu_fetch_v0_1.sv   v0.1  (2026-07-01)
//  YSD8800 FPGA V1 : FSMフェッチ経路TB
//
//  検証主眼(本日KY核心):
//   - リセットベクタ読み(2byte)でPC←{hi,lo}が正しくセット
//   - NOP列でPCが1ずつ前進(二重加算/滞留加算がない)
//   - HALTで停止(dbg_halt)
//   - SP初期化(0x0000)
//
//  簡易メモリ: 8bit幅・mem_ready即応(1固定)。
//   リトルエンディアン: ベクタ mem[0]=lo, mem[1]=hi。
// ============================================================
`timescale 1ns/1ps

import ysd8800_idec_pkg::*;

module tb_cpu_fetch_v0_1;
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

    // 簡易メモリ (64KB)
    logic [7:0] mem [0:65535];

    // 読み: 常時ready、組合せで rdata 供給
    assign mem_ready = 1'b1;
    always_comb mem_rdata = mem[mem_addr];

    // クロック
    initial clk = 0;
    always #5 clk = ~clk;

    // PC遷移の記録用
    logic [15:0] pc_log [0:31];
    integer      pc_cnt = 0;
    logic        prev_halt = 0;

    initial begin
        // メモリ初期化
        for (int i=0;i<65536;i=i+1) mem[i]=8'h00;
        // リセットベクタ: PC←0x0100 (lo=0x00 @0, hi=0x01 @1)
        mem[16'h0000]=8'h00;
        mem[16'h0001]=8'h01;
        // プログラム@0x0100: NOP×4, HALT
        mem[16'h0100]=8'h00; // NOP
        mem[16'h0101]=8'h00; // NOP
        mem[16'h0102]=8'h00; // NOP
        mem[16'h0103]=8'h00; // NOP
        mem[16'h0104]=8'h01; // HALT

        irq_in = 3'd0;
        rst_n  = 0;
        repeat(2) @(negedge clk);
        rst_n  = 1;

        // 実行監視: HALTになるまで、S_FETCH完了時のPCを記録
        // (簡易的に一定サイクル回して dbg_pc の遷移を観測)
        repeat(40) begin
            @(posedge clk);
            #1;
            if (dbg_halt && !prev_halt) begin
                $display("HALT reached at pc=%04x", dbg_pc);
            end
            prev_halt = dbg_halt;
        end

        // 検証: HALT到達
        if (!dbg_halt) begin
            $display("FAIL: not halted"); errors=errors+1;
        end else $display("PASS: halted");

        // 検証: SP初期化
        if (dbg_sp !== 16'h0000) begin
            $display("FAIL: SP=%04x exp0000", dbg_sp); errors=errors+1;
        end else $display("PASS: SP=0000");

        // 検証: HALT時のPCは 0x0105 (HALT命令0x0104をフェッチしPC+1後、実行でHALT)
        //   NOP×4で 0x0100→0x0104、HALTフェッチでPC+1→0x0105
        if (dbg_pc !== 16'h0105) begin
            $display("FAIL: final PC=%04x exp0105", dbg_pc); errors=errors+1;
        end else $display("PASS: final PC=0105");

        if (errors==0) $display("CPU_FETCH_TB: ALL PASS");
        else $display("CPU_FETCH_TB: %0d FAIL", errors);
        $finish;
    end

    // PC前進の連続監視(1ずつ進むか): FETCH完了直後のPCを追跡
    // dbg_pc が変化した瞬間を記録し、増分が全て+1であることを確認
    logic [15:0] last_pc = 16'hFFFF;
    always @(posedge clk) begin
        #2;
        if (rst_n && dbg_pc !== last_pc && last_pc !== 16'hFFFF) begin
            // PCが変化。増分チェック(リセット直後の0100セットは除外)
            if (last_pc >= 16'h0100 && dbg_pc >= 16'h0100) begin
                if ((dbg_pc - last_pc) != 16'd1) begin
                    $display("WARN: PC jump %04x->%04x (delta=%0d)",
                        last_pc, dbg_pc, dbg_pc-last_pc);
                end
            end
        end
        last_pc <= dbg_pc;
    end
endmodule
