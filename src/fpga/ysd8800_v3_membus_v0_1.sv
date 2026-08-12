// ============================================================
//  ysd8800_v3_membus_v0_1.sv   v0.1  (2026-07-11)
//  YSD8800 FPGA V3 : メモリサブシステム統合ラッパー
//
//  構成: CPU抽象バスI/F ─ アドレスデコーダ ─┬─ MMIOスタブ($FC80-$FFFF)
//                                            └─ CDCブリッジ ─ PSRAMコントローラ($0000-$FC7F)
//
//  V1のCPUコア(ysd8800_cpu_v0_1)がV1/V2で使ってきた理想メモリを、
//  本ラッパーに差し替えるだけでV3のPSRAM統合構成に置換できる
//  (CPUコア側は無変更・v3_design_memo_v0_2.md §1)。
// ============================================================
`timescale 1ns/1ps

module ysd8800_v3_membus_v0_1 (
    input  logic        cpu_clk,
    input  logic        cpu_rst_n,
    input  logic [15:0] mem_addr,
    input  logic [7:0]  mem_wdata,
    output logic [7:0]  mem_rdata,
    input  logic        mem_rd,
    input  logic        mem_wr,
    output logic        mem_ready,

    // PSRAMコントローラ用の高速クロック(§4.1・案A CDC同期方式)
    input  logic        psram_clk,
    input  logic        psram_rst_n,

    // 診断用(TB観測専用)
    output logic [15:0] dbg_mmio_last_addr,
    output logic [31:0] dbg_mmio_access_count
);

    logic [15:0] ram_addr, mmio_addr;
    logic [7:0]  ram_wdata, ram_rdata, mmio_wdata, mmio_rdata;
    logic        ram_rd, ram_wr, ram_ready, mmio_rd, mmio_wr, mmio_ready;

    ysd8800_addr_decoder_v0_1 u_decoder (
        .cpu_mem_addr(mem_addr), .cpu_mem_wdata(mem_wdata),
        .cpu_mem_rdata(mem_rdata), .cpu_mem_rd(mem_rd),
        .cpu_mem_wr(mem_wr), .cpu_mem_ready(mem_ready),
        .ram_addr(ram_addr), .ram_wdata(ram_wdata), .ram_rdata(ram_rdata),
        .ram_rd(ram_rd), .ram_wr(ram_wr), .ram_ready(ram_ready),
        .mmio_addr(mmio_addr), .mmio_wdata(mmio_wdata), .mmio_rdata(mmio_rdata),
        .mmio_rd(mmio_rd), .mmio_wr(mmio_wr), .mmio_ready(mmio_ready)
    );

    ysd8800_mmio_stub_v0_1 u_mmio_stub (
        .clk(cpu_clk), .rst_n(cpu_rst_n),
        .mmio_addr(mmio_addr), .mmio_wdata(mmio_wdata), .mmio_rdata(mmio_rdata),
        .mmio_rd(mmio_rd), .mmio_wr(mmio_wr), .mmio_ready(mmio_ready),
        .dbg_last_addr(dbg_mmio_last_addr), .dbg_access_count(dbg_mmio_access_count)
    );

    logic [15:0] psram_addr_w;
    logic [7:0]  psram_wdata_w, psram_rdata_w;
    logic        psram_we_w, psram_req_w, psram_ack_w;

    ysd8800_cdc_bridge_v0_1 u_cdc_bridge (
        .cpu_clk(cpu_clk), .cpu_rst_n(cpu_rst_n),
        .cpu_mem_addr(ram_addr), .cpu_mem_wdata(ram_wdata),
        .cpu_mem_rdata(ram_rdata), .cpu_mem_rd(ram_rd),
        .cpu_mem_wr(ram_wr), .cpu_mem_ready(ram_ready),
        .psram_clk(psram_clk), .psram_rst_n(psram_rst_n),
        .psram_addr(psram_addr_w), .psram_wdata(psram_wdata_w), .psram_we(psram_we_w),
        .psram_req(psram_req_w), .psram_ack(psram_ack_w), .psram_rdata(psram_rdata_w)
    );

    ysd8800_psram_ctrl_v0_1 #(
        .LATENCY_NORMAL(12), .LATENCY_REFRESH(15), .REFRESH_PPM(500), .PHYS_AW(16)
    ) u_psram_ctrl (
        .clk(psram_clk), .rst_n(psram_rst_n),
        .addr(psram_addr_w), .wdata(psram_wdata_w), .we(psram_we_w),
        .req(psram_req_w), .ack(psram_ack_w), .rdata(psram_rdata_w),
        .dbg_refresh_hit()
    );

endmodule
