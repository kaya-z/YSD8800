// ============================================================
//  tb_bridge_psram_integ_v0_1.sv   v0.1  (2026-07-11)
//  YSD8800 FPGA V3 : CDCブリッジ + PSRAMコントローラ 結合TB
//
//  目的: Step2(CDCブリッジ)とStep3(PSRAMコントローラ)を実結合し、
//        両者のreq/ack契約(4相ハンドシェイク)が実際に噛み合うかを
//        確認する(単体TBはそれぞれ内蔵スタブ/簡易応答モデルで
//        代用していたため、実結合の確認は本TBが初)。
//  検証観点: CPU抽象バスI/F側から見て、単発リード/ライト・
//            背中合わせ連続リードが最終的に正しく完了するか。
// ============================================================
`timescale 1ns/1ps

module tb_bridge_psram_integ_v0_1;
    logic        cpu_clk, cpu_rst_n;
    logic [15:0] cpu_mem_addr;
    logic [7:0]  cpu_mem_wdata, cpu_mem_rdata;
    logic        cpu_mem_rd, cpu_mem_wr, cpu_mem_ready;

    logic        psram_clk, psram_rst_n;
    logic [15:0] br_addr;
    logic [7:0]  br_wdata, br_rdata;
    logic        br_we, br_req, br_ack;
    logic        dbg_refresh_hit;

    integer errors = 0;

    ysd8800_cdc_bridge_v0_1 bridge (
        .cpu_clk(cpu_clk), .cpu_rst_n(cpu_rst_n),
        .cpu_mem_addr(cpu_mem_addr), .cpu_mem_wdata(cpu_mem_wdata),
        .cpu_mem_rdata(cpu_mem_rdata), .cpu_mem_rd(cpu_mem_rd),
        .cpu_mem_wr(cpu_mem_wr), .cpu_mem_ready(cpu_mem_ready),
        .psram_clk(psram_clk), .psram_rst_n(psram_rst_n),
        .psram_addr(br_addr), .psram_wdata(br_wdata), .psram_we(br_we),
        .psram_req(br_req), .psram_ack(br_ack), .psram_rdata(br_rdata)
    );

    ysd8800_psram_ctrl_v0_1 #(
        .LATENCY_NORMAL(12), .LATENCY_REFRESH(15), .REFRESH_PPM(500), .PHYS_AW(16)
    ) psram (
        .clk(psram_clk), .rst_n(psram_rst_n),
        .addr(br_addr), .wdata(br_wdata), .we(br_we),
        .req(br_req), .ack(br_ack), .rdata(br_rdata),
        .dbg_refresh_hit(dbg_refresh_hit)
    );

    // CPU 4MHz相当 : PSRAM 80MHz相当 = 20:1 (tb_cdc_bridge_v0_1と同一比)
    initial cpu_clk = 0;
    always #10 cpu_clk = ~cpu_clk;
    initial psram_clk = 0;
    always #0.5 psram_clk = ~psram_clk;

    task automatic do_read(input [15:0] addr, output [7:0] rdata);
        @(negedge cpu_clk);
        cpu_mem_addr = addr; cpu_mem_rd = 1'b1; cpu_mem_wr = 1'b0;
        @(posedge cpu_mem_ready);
        rdata = cpu_mem_rdata;
        @(negedge cpu_clk);
        cpu_mem_rd = 1'b0;
    endtask

    task automatic do_write(input [15:0] addr, input [7:0] wdata);
        @(negedge cpu_clk);
        cpu_mem_addr = addr; cpu_mem_wdata = wdata;
        cpu_mem_wr = 1'b1; cpu_mem_rd = 1'b0;
        @(posedge cpu_mem_ready);
        @(negedge cpu_clk);
        cpu_mem_wr = 1'b0;
    endtask

    logic [7:0] rd1, rd2;

    initial begin
        cpu_rst_n = 0; psram_rst_n = 0;
        cpu_mem_addr = 0; cpu_mem_wdata = 0; cpu_mem_rd = 0; cpu_mem_wr = 0;
        repeat (3) @(negedge cpu_clk);
        cpu_rst_n = 1; psram_rst_n = 1;
        repeat (3) @(negedge cpu_clk);

        // T1: 単発ライト→リードback(実結合の基本疎通)
        do_write(16'h4000, 8'hC3);
        do_read(16'h4000, rd1);
        if (rd1 !== 8'hC3) begin
            $display("[T1] FAIL: got %02h expected C3", rd1); errors++;
        end else $display("[T1] PASS: 実結合write/read-back一致 (%02h)", rd1);

        // T2: 背中合わせ連続リード(rdを下げずにアドレス変更)
        @(negedge cpu_clk);
        cpu_mem_addr = 16'h4000; cpu_mem_rd = 1'b1; cpu_mem_wr = 1'b0;
        @(posedge cpu_mem_ready);
        rd1 = cpu_mem_rdata;
        @(negedge cpu_clk);
        cpu_mem_addr = 16'h4001; // rd=1のまま
        @(posedge cpu_mem_ready);
        rd2 = cpu_mem_rdata;
        @(negedge cpu_clk);
        cpu_mem_rd = 1'b0;
        if (rd1 !== 8'hC3) begin
            $display("[T2] FAIL: rd1=%02h expected C3", rd1); errors++;
        end else $display("[T2] PASS: 実結合・背中合わせ連続読出しも完走 (rd1=%02h, rd2=%02h)", rd1, rd2);

        if (errors == 0) $display("ALL PASS (2/2)");
        else $display("FAIL: %0d error(s)", errors);
        $finish;
    end
endmodule
