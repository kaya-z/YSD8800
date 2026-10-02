// tb_ca_contract_poc.sv  v0.1 (2026-09-02)
//   ★C-α'（境界①）の陽性/陰性試験★
//   設計書: v12_tb_contract_design_v0_3.md §3.5.2
//     陰性1: 実CPU相当（ready次サイクルに★新しい★要求）→ 発火しないこと
//     陰性2: ready と同時に要求を下げる          → 発火しないこと
//     陽性 : ★段4 の壊れた版（同一要求を保持）★  → ★発火すること★
//   KY38: _poc 接尾辞。本番ソースではない。
`timescale 1ns/1ps
module tb_ca_contract_poc;

    localparam int PHYS_AW = 20;

    logic cpu_clk = 0, cpu_rst_n = 0;
    logic ccr_cen_i = 1'b0;          // ★CEN=0（純素通し）で契約のみを見る★
    logic ccr_flush_pulse_i = 1'b0;
    logic [PHYS_AW-1:0] cpu_phys_addr_i = '0;
    logic [7:0] cpu_wdata_i = '0;
    logic [7:0] cpu_rdata_o;
    logic cpu_rd_i = 0, cpu_wr_i = 0;
    logic cpu_ready_o;

    logic [PHYS_AW-1:0] br_phys_addr_o;
    logic [7:0] br_wdata_o;
    logic [7:0] br_rdata_i = 8'hA5;
    logic br_rd_o, br_wr_o;
    logic br_ready_i = 0;
    logic [5:0] burst_len_o;

    logic psram_clk = 0, psram_rst_n = 0;
    logic beat_valid_i = 0;
    logic [7:0] psram_rdata_i = '0;

    always #5  cpu_clk   = ~cpu_clk;
    always #5  psram_clk = ~psram_clk;

    ysd8800_cache_v0_3 #(.PHYS_AW(PHYS_AW)) dut (.*);

    // ---- 下流模擬: 要求受理から2サイクル後に ready を1サイクル返す ----
    int lat;
    always @(posedge cpu_clk) begin
        if (!cpu_rst_n) begin br_ready_i <= 0; lat <= 0; end
        else begin
            br_ready_i <= 0;
            if ((br_rd_o || br_wr_o) && !br_ready_i) begin
                if (lat == 1) begin br_ready_i <= 1; lat <= 0; end
                else lat <= lat + 1;
            end else lat <= 0;
        end
    end

    // ==== 陰性1: 実CPU相当（ready後、★新しいアドレス★で継続）====
    task automatic seq_real_cpu(input logic [PHYS_AW-1:0] a);
        @(posedge cpu_clk);
        cpu_phys_addr_i <= a; cpu_rd_i <= 1'b1;
        do @(posedge cpu_clk); while (!cpu_ready_o);
        cpu_phys_addr_i <= a + 1;      // ★新しい要求（アドレス変化）★
        cpu_rd_i        <= 1'b1;
        do @(posedge cpu_clk); while (!cpu_ready_o);
        cpu_rd_i <= 1'b0;
    endtask

    // ==== 陰性2: ready と同時に下げる（正しい do_read）====
    task automatic seq_good(input logic [PHYS_AW-1:0] a);
        @(posedge cpu_clk);
        cpu_phys_addr_i <= a; cpu_rd_i <= 1'b1;
        do @(posedge cpu_clk); while (!cpu_ready_o);
        cpu_rd_i <= 1'b0;
    endtask

    // ==== 陽性: ★段4 の壊れた版（ready 検出の1cyc後に下げる）====
    task automatic seq_broken(input logic [PHYS_AW-1:0] a);
        @(posedge cpu_clk);
        cpu_phys_addr_i <= a; cpu_rd_i <= 1'b1;
        do @(posedge cpu_clk); while (!cpu_ready_o);
        @(posedge cpu_clk);            // ★1cyc 余計に保持 = 同一要求の再送★
        cpu_rd_i <= 1'b0;
    endtask

    initial begin
        repeat(3) @(posedge cpu_clk);
        cpu_rst_n = 1; psram_rst_n = 1;
        repeat(2) @(posedge cpu_clk);

        $display("== 陰性1: 実CPU相当 (ready後 新しいアドレスで継続) ==");
        seq_real_cpu(20'h02000);
        repeat(3) @(posedge cpu_clk);

        $display("== 陰性2: ready と同時に下げる ==");
        seq_good(20'h03000);
        repeat(3) @(posedge cpu_clk);

        $display("== 陽性: 段4のバグ相当 (ready後に同一要求を保持) ==");
        seq_broken(20'h04000);
        repeat(4) @(posedge cpu_clk);

        $display("== 終了 ==");
        $finish;
    end
endmodule
