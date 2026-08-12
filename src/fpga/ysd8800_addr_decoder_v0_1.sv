// ============================================================
//  ysd8800_addr_decoder_v0_1.sv   v0.1  (2026-07-11)
//  YSD8800 FPGA V3 : アドレスデコーダ
//
//  設計根拠: v3_design_memo_v0_2.md §2/§4.3
//   - $0000-$FC7F -> RAM側(PSRAM経路)
//   - $FC80-$FFFF -> MMIO側(スタブ、V4以降で実デバイス化)
//   - 恒等写像のみ(MMU変換はV3.5でCPU側の手前に別途挿入)
//
//  純粋組合せ回路(assign文のみ。Icarus always_comb定数ビット選択
//   制約の回避方針・kaizen.txt既定パターンに準拠)。
// ============================================================
`timescale 1ns/1ps

module ysd8800_addr_decoder_v0_1 (
    // CPU側 (上流・ysd8800_cpu_v0_1の抽象バスI/Fそのまま)
    input  logic [15:0] cpu_mem_addr,
    input  logic [7:0]  cpu_mem_wdata,
    output logic [7:0]  cpu_mem_rdata,
    input  logic        cpu_mem_rd,
    input  logic        cpu_mem_wr,
    output logic         cpu_mem_ready,

    // RAM側 (下流・CDCブリッジ経由でPSRAMへ)
    output logic [15:0] ram_addr,
    output logic [7:0]  ram_wdata,
    input  logic [7:0]  ram_rdata,
    output logic        ram_rd,
    output logic        ram_wr,
    input  logic        ram_ready,

    // MMIO側 (下流・V3時点はスタブ)
    output logic [15:0] mmio_addr,
    output logic [7:0]  mmio_wdata,
    input  logic [7:0]  mmio_rdata,
    output logic        mmio_rd,
    output logic        mmio_wr,
    input  logic        mmio_ready
);

    // 境界判定: $FC80以降をMMIOとする(yuios_memmap_design_v2_4.md §4.2)
    logic is_mmio;
    assign is_mmio = (cpu_mem_addr >= 16'hFC80);

    // RAM側配線
    assign ram_addr  = cpu_mem_addr;
    assign ram_wdata = cpu_mem_wdata;
    assign ram_rd    = cpu_mem_rd & ~is_mmio;
    assign ram_wr    = cpu_mem_wr & ~is_mmio;

    // MMIO側配線
    assign mmio_addr  = cpu_mem_addr;
    assign mmio_wdata = cpu_mem_wdata;
    assign mmio_rd    = cpu_mem_rd & is_mmio;
    assign mmio_wr    = cpu_mem_wr & is_mmio;

    // CPUへの戻り(振り分けmux)
    assign cpu_mem_rdata = is_mmio ? mmio_rdata  : ram_rdata;
    assign cpu_mem_ready = is_mmio ? mmio_ready  : ram_ready;

endmodule
