// ============================================================
//  tb_cpu_v2a_v0_1.sv   v0.1  (2026-07-08)
//  YSD8800 FPGA V2-a : C1 レジスタALU 外部観測等価検証TB
//
//  検証主眼:
//   - C1 ALU命令(ADD/SUB/AND/OR/XOR/NOT/SHL/SHR/SAR)の
//     実行結果(A/B/X/FLAGS)が emu23 v1.09 黄金と外部観測等価
//   - FLAGS は下位8bitで突合(bit0=Z bit1=N)。設計メモ §4.4
//   - SPは突合対象外(選択肢1)。ただしALUがSPを壊さない保険として
//     実行後 SP==0x0000(RTLリセット値)不変を確認
//
//  黄金・入力は gen_v2_vectors.py が単一ソースから生成(偽合格防止):
//   - v2a/<id>.hex        : プログラム($readmemh)
//   - v2a/expected_v2a.hex : 期待値 1ベクタ4word(A,B,X,F) 順
//
//  観測タイミング: dbg_halt立上り時の状態(=最後の実ALU命令直後)。
//   emu23側は末尾HALT実行前トレース(設計メモ §4.3)で揃う。
// ============================================================
`timescale 1ns/1ps

import ysd8800_idec_pkg::*;

module tb_cpu_v2a_v0_1;
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

    // 簡易メモリ (64KB, 8bit幅, ready即応)
    logic [7:0] mem [0:65535];
    assign mem_ready = 1'b1;
    always_comb mem_rdata = mem[mem_addr];

    // クロック
    initial clk = 0;
    always #5 clk = ~clk;

    // ベクタ数・名前 (gen_v2_vectors.py VECTORSと同順)
    localparam int NVEC = 20;
    string vname [0:NVEC-1];

    // 期待値 (expected_v2a.hex: 1ベクタ4word A,B,X,F)
    logic [15:0] exp_mem [0:NVEC*4-1];

    // 1ベクタ実行タスク
    integer vi;
    logic [15:0] exp_a, exp_b, exp_x;
    logic [7:0]  exp_f;
    integer      cyc;

    initial begin
        // ベクタ名 (gen VECTORS順に一致させる)
        vname[0]="ADD_pos";  vname[1]="ADD_zero"; vname[2]="ADD_neg";
        vname[3]="SUB_pos";  vname[4]="SUB_zero"; vname[5]="SUB_neg";
        vname[6]="AND_zero"; vname[7]="AND_neg";
        vname[8]="OR_pos";   vname[9]="OR_neg";
        vname[10]="XOR_zero";vname[11]="XOR_neg";
        vname[12]="NOT_neg"; vname[13]="NOT_zero";
        vname[14]="SHL_neg"; vname[15]="SHL_zero";
        vname[16]="SHR_pos"; vname[17]="SHR_zero";
        vname[18]="SAR_neg"; vname[19]="SAR_pos";

        // 期待値一括読込
        $readmemh("v2a/expected_v2a.hex", exp_mem);

        irq_in = 3'd0;

        for (vi = 0; vi < NVEC; vi = vi + 1) begin
            // --- メモリ初期化 & プログラム読込 ---
            // 使用域(0x0000-0x01FF)のみクリア。全65536クリアはIcarusで
            // always_comb張り付き下の2巡目にハングするため回避(2026-07-08)。
            for (int i=0;i<16'h0200;i=i+1) mem[i]=8'h00;
            case (vi)
                0:  $readmemh("v2a/ADD_pos.hex",  mem);
                1:  $readmemh("v2a/ADD_zero.hex", mem);
                2:  $readmemh("v2a/ADD_neg.hex",  mem);
                3:  $readmemh("v2a/SUB_pos.hex",  mem);
                4:  $readmemh("v2a/SUB_zero.hex", mem);
                5:  $readmemh("v2a/SUB_neg.hex",  mem);
                6:  $readmemh("v2a/AND_zero.hex", mem);
                7:  $readmemh("v2a/AND_neg.hex",  mem);
                8:  $readmemh("v2a/OR_pos.hex",   mem);
                9:  $readmemh("v2a/OR_neg.hex",   mem);
                10: $readmemh("v2a/XOR_zero.hex", mem);
                11: $readmemh("v2a/XOR_neg.hex",  mem);
                12: $readmemh("v2a/NOT_neg.hex",  mem);
                13: $readmemh("v2a/NOT_zero.hex", mem);
                14: $readmemh("v2a/SHL_neg.hex",  mem);
                15: $readmemh("v2a/SHL_zero.hex", mem);
                16: $readmemh("v2a/SHR_pos.hex",  mem);
                17: $readmemh("v2a/SHR_zero.hex", mem);
                18: $readmemh("v2a/SAR_neg.hex",  mem);
                19: $readmemh("v2a/SAR_pos.hex",  mem);
            endcase

            exp_a = exp_mem[vi*4+0];
            exp_b = exp_mem[vi*4+1];
            exp_x = exp_mem[vi*4+2];
            exp_f = exp_mem[vi*4+3][7:0];

            // --- リセット ---
            rst_n = 0;
            repeat(2) @(negedge clk);
            rst_n = 1;

            // --- HALTまで実行 (上限サイクルで暴走防止) ---
            cyc = 0;
            while (!dbg_halt && cyc < 200) begin
                @(posedge clk); #1;
                cyc = cyc + 1;
            end

            // --- 突合 ---
            if (!dbg_halt) begin
                $display("FAIL[%0d %s]: not halted (cyc=%0d)", vi, vname[vi], cyc);
                errors = errors + 1;
            end else begin
                if (dbg_a !== exp_a) begin
                    $display("FAIL[%0d %s]: A=%04x exp=%04x",
                             vi, vname[vi], dbg_a, exp_a); errors=errors+1;
                end
                if (dbg_b !== exp_b) begin
                    $display("FAIL[%0d %s]: B=%04x exp=%04x",
                             vi, vname[vi], dbg_b, exp_b); errors=errors+1;
                end
                if (dbg_x !== exp_x) begin
                    $display("FAIL[%0d %s]: X=%04x exp=%04x",
                             vi, vname[vi], dbg_x, exp_x); errors=errors+1;
                end
                if (dbg_flags[7:0] !== exp_f) begin
                    $display("FAIL[%0d %s]: F=%02x exp=%02x",
                             vi, vname[vi], dbg_flags[7:0], exp_f); errors=errors+1;
                end
                // SP不変保険 (ALUはSPを壊さない: RTLリセット値0x0000のまま)
                if (dbg_sp !== 16'h0000) begin
                    $display("FAIL[%0d %s]: SP=%04x changed by ALU (exp 0000)",
                             vi, vname[vi], dbg_sp); errors=errors+1;
                end
            end
        end

        // --- 総括 ---
        if (errors==0) $display("CPU_V2A_TB: ALL PASS (%0d vectors)", NVEC);
        else           $display("CPU_V2A_TB: %0d FAIL", errors);
        $finish;
    end
endmodule
