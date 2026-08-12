// ============================================================
//  ysd8800_mmio_stub_v0_1.sv   v0.1  (2026-07-11)
//  YSD8800 FPGA V3 : MMIOスタブ(V4以降で実デバイスへ置換予定)
//
//  設計根拠: v3_design_memo_v0_2.md §4.2
//   - 即時mem_readyアサート
//   - リードは固定値0x00(バイト粒度)
//   - ライトは無視(内部状態変化なし)
//   - IRQは上げない(V3スコープ外)
//   - 診断用: 最終アクセスアドレスラッチ + アクセスカウンタ
//     (デコーダ誤りで RAM アクセスが MMIO に吸われる事故を
//      TB から観測可能にするため)
// ============================================================
`timescale 1ns/1ps

module ysd8800_mmio_stub_v0_1 (
    input  logic        clk,
    input  logic        rst_n,

    input  logic [15:0] mmio_addr,
    input  logic [7:0]  mmio_wdata,
    output logic [7:0]  mmio_rdata,
    input  logic        mmio_rd,
    input  logic        mmio_wr,
    output logic         mmio_ready,

    // 診断用出力(TB観測専用・機能には無関係)
    output logic [15:0] dbg_last_addr,
    output logic [31:0] dbg_access_count
);

    logic access;
    assign access = mmio_rd | mmio_wr;

    // 即時ready(組合せ)。ライトは無視・リードは固定値0x00。
    assign mmio_ready = access;
    assign mmio_rdata = 8'h00;

    // 診断ラッチ・カウンタ
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dbg_last_addr    <= 16'h0000;
            dbg_access_count <= 32'h0000_0000;
        end else if (access) begin
            dbg_last_addr    <= mmio_addr;
            dbg_access_count <= dbg_access_count + 32'd1;
        end
    end

endmodule
