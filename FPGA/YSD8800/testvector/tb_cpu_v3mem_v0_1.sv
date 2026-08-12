// ============================================================
//  tb_cpu_v3mem_v0_1.sv   v0.1  (2026-07-11)
//  YSD8800 FPGA V3 : 実CPUコア + V3メモリサブシステム
//                     メモリ系命令(LDW/STW/PUSH/POP/LDB/STB)
//                     emu23協調等価検証
//
//  対象: 絶対アドレス(0x22/0x23)・インデックス[X+imm16](0x26/0x27)・
//        レジスタ間接[rS]/[rD](0x24/0x25)・PUSH/POP(0x1F 0x00-0x05)・
//        LDB/STB(0x1F 0x10-0x17)。tb_cpu_v3_v0_1.sv(ALU系)を補完し、
//        S_MEMR_LO/HI・S_MEMW_LO/HI・S_PUSH_LO/HI・S_POP_LO/HI・
//        S_MEMR8/S_MEMW8の各stateをV3実メモリ経路(CDCブリッジ+
//        PSRAMビヘイビアモデル)で網羅する。
//
//  SP初期値差異(emu23既定FC7E vs RTL既定0000)はgen_v3_mem_vectors.py
//  側で全ベクタ先頭にLDW SP,#imm16を挿入し中和済(V2-d方式踏襲)。
//  本TBはSPも突合対象に含める(V2-aと異なりSP操作の正しさが検証
//  対象そのものであるため)。
// ============================================================
`timescale 1ns/1ps

import ysd8800_idec_pkg::*;

module tb_cpu_v3mem_v0_1;
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

    ysd8800_v3_membus_v0_1 u_membus (
        .cpu_clk(cpu_clk), .cpu_rst_n(cpu_rst_n),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata),
        .mem_rd(mem_rd), .mem_wr(mem_wr), .mem_ready(mem_ready),
        .psram_clk(psram_clk), .psram_rst_n(psram_rst_n),
        .dbg_mmio_last_addr(dbg_mmio_last_addr),
        .dbg_mmio_access_count(dbg_mmio_access_count)
    );

    initial cpu_clk = 0;
    always #10 cpu_clk = ~cpu_clk;
    initial psram_clk = 0;
    always #0.5 psram_clk = ~psram_clk;

    localparam int NVEC = 5;
    string vname [0:NVEC-1];
    logic [15:0] exp_mem [0:NVEC*5-1];
    logic [15:0] exp_a, exp_b, exp_x, exp_sp;
    logic [7:0]  exp_f;
    integer vi, cyc;

    initial begin
        vname[0]="STW_LDW_ABS";
        vname[1]="STW_LDW_XI";
        vname[2]="STW_LDW_INDIRECT";
        vname[3]="PUSH_POP";
        vname[4]="LDB_STB";

        $readmemh("v3mem/expected_v3mem.hex", exp_mem);

        irq_in = 3'd0;
        psram_rst_n = 0;
        repeat (3) @(negedge psram_clk);
        psram_rst_n = 1;

        for (vi = 0; vi < NVEC; vi = vi + 1) begin
            for (int i = 0; i < 16'h0500; i = i + 1)
                u_membus.u_psram_ctrl.mem[i] = 8'h00;
            case (vi)
                0: $readmemh("v3mem/STW_LDW_ABS.hex",       u_membus.u_psram_ctrl.mem);
                1: $readmemh("v3mem/STW_LDW_XI.hex",        u_membus.u_psram_ctrl.mem);
                2: $readmemh("v3mem/STW_LDW_INDIRECT.hex",  u_membus.u_psram_ctrl.mem);
                3: $readmemh("v3mem/PUSH_POP.hex",          u_membus.u_psram_ctrl.mem);
                4: $readmemh("v3mem/LDB_STB.hex",           u_membus.u_psram_ctrl.mem);
            endcase

            exp_a  = exp_mem[vi*5+0];
            exp_b  = exp_mem[vi*5+1];
            exp_x  = exp_mem[vi*5+2];
            exp_sp = exp_mem[vi*5+3];
            exp_f  = exp_mem[vi*5+4][7:0];

            cpu_rst_n = 0;
            repeat (3) @(negedge cpu_clk);
            cpu_rst_n = 1;

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
                if (dbg_sp !== exp_sp) begin
                    $display("FAIL[%0d %s]: SP=%04h exp=%04h", vi, vname[vi], dbg_sp, exp_sp); errors++;
                end
                if (dbg_flags[7:0] !== exp_f) begin
                    $display("FAIL[%0d %s]: F=%02h exp=%02h", vi, vname[vi], dbg_flags[7:0], exp_f); errors++;
                end
                if (errors == 0 || vi == 0)
                    $display("[%0d %s] A=%04h B=%04h X=%04h SP=%04h F=%02h",
                              vi, vname[vi], dbg_a, dbg_b, dbg_x, dbg_sp, dbg_flags[7:0]);
            end
        end

        if (dbg_mmio_access_count !== 32'd0) begin
            $display("FAIL: MMIOアクセスが検出された(count=%0d)。V3memベクタはRAM限定のはず。",
                       dbg_mmio_access_count);
            errors++;
        end

        if (errors == 0)
            $display("ALL PASS (%0d/%0d vectors, LDW/STW絶対・XI・間接・PUSH/POP・LDB/STB全網羅, MMIO非タッチ確認済)",
                       NVEC, NVEC);
        else
            $display("FAIL: %0d error(s)", errors);
        $finish;
    end
endmodule
