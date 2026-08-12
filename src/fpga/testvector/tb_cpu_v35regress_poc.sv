// ============================================================
//  tb_cpu_v35regress_poc.sv   (V3.5 regression PoC / KY38)
//  元TB: tb_cpu_v3_v0_1.sv
//  変更: ysd8800_v3_membus_v0_1 -> ysd8800_v35_membus_v0_1
//                                  (PHYS_AW=20, MEM_AW=20)
//  狙い: MCR=0(リセット値)でMMUは恒等写像 => V3とbit-exact等価。
//        V3でALL PASSしたベクタがV3.5構成でも再現することを確認
//        する(デグレ無の証明・v3_5_design_memo_v0_2.md §4.4/S5)。
// ============================================================
// ============================================================
//  tb_cpu_v3_v0_1.sv   v0.1  (2026-07-11)
//  YSD8800 FPGA V3 : 実CPUコア + V3メモリサブシステム
//                     emu23協調等価検証(V2-aベクタ再利用)
//
//  設計根拠: v3_design_memo_v0_2.md §5
//   「この結合TBはV2のTBとほぼ同じ構造を流用できる(相違点は
//    ビヘイビアメモリをPSRAMコントローラ+アドレスデコーダに
//    差し替えるのみ)」を実践。tb_cpu_v2a_v0_1.svと同一の
//    V2-aベクタ(20件・ADD/SUB/AND/OR/XOR/NOT/SHL/SHR/SAR)を
//    実CPUコア(ysd8800_cpu_v0_1)+V3メモリサブシステム
//    (ysd8800_v3_membus_v0_1、PSRAMビヘイビアモデル使用)で
//    再実行し、emu23黄金値(golden_v2a.txt)と一致するか確認する。
//
//  ★指示No.6(§4.2)通り、V2-aベクタはRAM領域($0100番地台)のみ
//    使用でMMIOに触れないため、そのままV3の協調等価ベクタとして
//    適格(除外処理不要)。
// ============================================================
`timescale 1ns/1ps

import ysd8800_idec_pkg::*;

module tb_cpu_v35regress_poc;
    logic        cpu_clk, cpu_rst_n;
    logic        psram_clk, psram_rst_n;
    logic [15:0] mem_addr;
    logic [7:0]  mem_wdata, mem_rdata;
    logic        mem_rd, mem_wr, mem_ready;
    logic [2:0]  irq_in;
    logic [15:0] dbg_pc, dbg_a, dbg_b, dbg_x, dbg_sp, dbg_flags;
    logic        dbg_halt;
    logic [15:0] dbg_mmio_last_addr;
    logic [31:0] dbg_mmio_access_count;

    integer errors = 0;

    ysd8800_cpu_v0_1 dut_cpu (
        .clk(cpu_clk), .rst_n(cpu_rst_n),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata),
        .mem_rd(mem_rd), .mem_wr(mem_wr), .mem_ready(mem_ready),
        .irq_in(irq_in),
        .dbg_pc(dbg_pc), .dbg_a(dbg_a), .dbg_b(dbg_b), .dbg_x(dbg_x),
        .dbg_sp(dbg_sp), .dbg_flags(dbg_flags), .dbg_halt(dbg_halt)
    );

    ysd8800_v35_membus_v0_1 #(.PHYS_AW(20), .MEM_AW(20)) u_membus (
        .cpu_clk(cpu_clk), .cpu_rst_n(cpu_rst_n),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata),
        .mem_rd(mem_rd), .mem_wr(mem_wr), .mem_ready(mem_ready),
        .psram_clk(psram_clk), .psram_rst_n(psram_rst_n),
        .dbg_mmio_last_addr(dbg_mmio_last_addr),
        .dbg_mmio_access_count(dbg_mmio_access_count)
    );

    // クロック: CPU 4MHz相当(period=20) : PSRAM 80MHz相当(period=1) = 20:1
    initial cpu_clk = 0;
    always #10 cpu_clk = ~cpu_clk;
    initial psram_clk = 0;
    always #0.5 psram_clk = ~psram_clk;

    localparam int NVEC = 20;
    string vname [0:NVEC-1];
    logic [15:0] exp_mem [0:NVEC*4-1];
    logic [15:0] exp_a, exp_b, exp_x;
    logic [7:0]  exp_f;
    integer vi, cyc;

    initial begin
        vname[0]="ADD_pos";  vname[1]="ADD_zero"; vname[2]="ADD_neg";
        vname[3]="SUB_pos";  vname[4]="SUB_zero"; vname[5]="SUB_neg";
        vname[6]="AND_zero"; vname[7]="AND_neg";
        vname[8]="OR_pos";   vname[9]="OR_neg";
        vname[10]="XOR_zero";vname[11]="XOR_neg";
        vname[12]="NOT_neg"; vname[13]="NOT_zero";
        vname[14]="SHL_neg"; vname[15]="SHL_zero";
        vname[16]="SHR_pos"; vname[17]="SHR_zero";
        vname[18]="SAR_neg"; vname[19]="SAR_pos";

        $readmemh("v2a/expected_v2a.hex", exp_mem);

        irq_in = 3'd0;
        psram_rst_n = 0;
        repeat (3) @(negedge psram_clk);
        psram_rst_n = 1;

        for (vi = 0; vi < NVEC; vi = vi + 1) begin
            // PSRAMコントローラ内蔵メモリへ直接ロード(階層参照・TB専用)
            for (int i = 0; i < 16'h0200; i = i + 1)
                u_membus.u_psram_ctrl.mem[i] = 8'h00;
            case (vi)
                0:  $readmemh("v2a/ADD_pos.hex",  u_membus.u_psram_ctrl.mem);
                1:  $readmemh("v2a/ADD_zero.hex", u_membus.u_psram_ctrl.mem);
                2:  $readmemh("v2a/ADD_neg.hex",  u_membus.u_psram_ctrl.mem);
                3:  $readmemh("v2a/SUB_pos.hex",  u_membus.u_psram_ctrl.mem);
                4:  $readmemh("v2a/SUB_zero.hex", u_membus.u_psram_ctrl.mem);
                5:  $readmemh("v2a/SUB_neg.hex",  u_membus.u_psram_ctrl.mem);
                6:  $readmemh("v2a/AND_zero.hex", u_membus.u_psram_ctrl.mem);
                7:  $readmemh("v2a/AND_neg.hex",  u_membus.u_psram_ctrl.mem);
                8:  $readmemh("v2a/OR_pos.hex",   u_membus.u_psram_ctrl.mem);
                9:  $readmemh("v2a/OR_neg.hex",   u_membus.u_psram_ctrl.mem);
                10: $readmemh("v2a/XOR_zero.hex", u_membus.u_psram_ctrl.mem);
                11: $readmemh("v2a/XOR_neg.hex",  u_membus.u_psram_ctrl.mem);
                12: $readmemh("v2a/NOT_neg.hex",  u_membus.u_psram_ctrl.mem);
                13: $readmemh("v2a/NOT_zero.hex", u_membus.u_psram_ctrl.mem);
                14: $readmemh("v2a/SHL_neg.hex",  u_membus.u_psram_ctrl.mem);
                15: $readmemh("v2a/SHL_zero.hex", u_membus.u_psram_ctrl.mem);
                16: $readmemh("v2a/SHR_pos.hex",  u_membus.u_psram_ctrl.mem);
                17: $readmemh("v2a/SHR_zero.hex", u_membus.u_psram_ctrl.mem);
                18: $readmemh("v2a/SAR_neg.hex",  u_membus.u_psram_ctrl.mem);
                19: $readmemh("v2a/SAR_pos.hex",  u_membus.u_psram_ctrl.mem);
            endcase

            exp_a = exp_mem[vi*4+0];
            exp_b = exp_mem[vi*4+1];
            exp_x = exp_mem[vi*4+2];
            exp_f = exp_mem[vi*4+3][7:0];

            cpu_rst_n = 0;
            repeat (3) @(negedge cpu_clk);
            cpu_rst_n = 1;

            // PSRAM統合によりレイテンシが伸びるため上限サイクルを拡大
            cyc = 0;
            while (!dbg_halt && cyc < 3000) begin
                @(posedge cpu_clk); #1;
                cyc = cyc + 1;
            end

            if (!dbg_halt) begin
                $display("FAIL[%0d %s]: not halted (cyc=%0d)", vi, vname[vi], cyc);
                errors = errors + 1;
            end else begin
                if (dbg_a !== exp_a) begin
                    $display("FAIL[%0d %s]: A=%04h exp=%04h", vi, vname[vi], dbg_a, exp_a); errors++;
                end
                if (dbg_b !== exp_b) begin
                    $display("FAIL[%0d %s]: B=%04h exp=%04h", vi, vname[vi], dbg_b, exp_b); errors++;
                end
                if (dbg_x !== exp_x) begin
                    $display("FAIL[%0d %s]: X=%04h exp=%04h", vi, vname[vi], dbg_x, exp_x); errors++;
                end
                if (dbg_flags[7:0] !== exp_f) begin
                    $display("FAIL[%0d %s]: F=%02h exp=%02h", vi, vname[vi], dbg_flags[7:0], exp_f); errors++;
                end
            end
        end

        // MMIO非タッチの確認(指示No.6: V3ベクタはRAM領域のみのはず)
        if (dbg_mmio_access_count !== 32'd0) begin
            $display("FAIL: MMIOアクセスが検出された(count=%0d)。V2aベクタはRAM限定のはず。",
                       dbg_mmio_access_count);
            errors++;
        end

        if (errors == 0)
            $display("ALL PASS (%0d/%0d vectors, emu23協調等価, MMIO非タッチ確認済)", NVEC, NVEC);
        else
            $display("FAIL: %0d error(s)", errors);
        $finish;
    end
endmodule
