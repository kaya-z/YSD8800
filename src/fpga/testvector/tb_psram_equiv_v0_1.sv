// ============================================================
//  tb_psram_equiv_v0_1.sv   v0.1  (2026-08-28)
//  工程②-A 段1 検証用: psram_ctrl v0.2 / v0.3 等価性TB
//
//  設計根拠: v10_psram_burst_design_v0_3.md §5.3 段1
//
//  【目的】
//    段1は「レジスタを足しただけでFSM遷移は不変」であるため、
//    既存ベクタが【1サイクルもずれない】ことを確認する段である。
//    感度ではなく【不変】を確認する。ここでずれたら追加自体に
//    副作用があることになる。
//
//  【方式】
//    v0.2(REF)とv0.3(DUT)に完全に同一の刺激を同時印加し、
//    毎クロック ack / rdata / dbg_refresh_hit を比較する。
//    ★1サイクルでも差があれば即FAIL★
//
//    v0.3側の burst_len は常に1に固定する(②-Aの休眠条件)。
//    LFSRは両者とも同一初期値・同一更新式のためリフレッシュ
//    重畳の発生パターンも一致するはずである。
// ============================================================
`timescale 1ns/1ps

module tb_psram_equiv_v0_1;
    logic        clk, rst_n;
    logic [19:0] addr;
    logic [7:0]  wdata;
    logic        we, req;

    // REF = v0.2
    logic [7:0]  rdata_ref;
    logic        ack_ref, dbg_ref;
    // DUT = v0.3
    logic [7:0]  rdata_dut;
    logic        ack_dut, dbg_dut, beat_valid_dut;

    integer errors    = 0;
    integer cmp_cycle = 0;

    localparam int BLEN_W_TB = $clog2(32) + 1;   // = 6

    ysd8800_psram_ctrl_v0_2 #(
        .LATENCY_NORMAL(12), .LATENCY_REFRESH(15), .REFRESH_PPM(500),
        .PHYS_AW(20), .MEM_AW(20)
    ) u_ref (
        .clk(clk), .rst_n(rst_n),
        .addr(addr), .wdata(wdata), .we(we),
        .req(req), .ack(ack_ref), .rdata(rdata_ref),
        .dbg_refresh_hit(dbg_ref)
    );

    ysd8800_psram_ctrl_v0_3 #(
        .LATENCY_NORMAL(12), .LATENCY_REFRESH(15), .REFRESH_PPM(500),
        .PHYS_AW(20), .MEM_AW(20), .BURST_MAX(32)
    ) u_dut (
        .clk(clk), .rst_n(rst_n),
        .addr(addr), .wdata(wdata), .we(we),
        .req(req), .ack(ack_dut), .rdata(rdata_dut),
        .burst_len(BLEN_W_TB'(1)),          // ★②-A: 常に1(休眠)★
        .beat_valid(beat_valid_dut),
        .dbg_refresh_hit(dbg_dut)
    );

    initial clk = 0;
    always #1 clk = ~clk;

    // ---- 毎クロック比較(★1サイクルでも差があればFAIL★) ----
    always @(posedge clk) begin
        if (rst_n) begin
            cmp_cycle = cmp_cycle + 1;
            if (ack_ref !== ack_dut) begin
                $display("[EQ] FAIL @cyc=%0d ack ref=%b dut=%b",
                         cmp_cycle, ack_ref, ack_dut);
                errors = errors + 1;
            end
            if (rdata_ref !== rdata_dut) begin
                $display("[EQ] FAIL @cyc=%0d rdata ref=%02h dut=%02h",
                         cmp_cycle, rdata_ref, rdata_dut);
                errors = errors + 1;
            end
            if (dbg_ref !== dbg_dut) begin
                $display("[EQ] FAIL @cyc=%0d dbg_refresh ref=%b dut=%b",
                         cmp_cycle, dbg_ref, dbg_dut);
                errors = errors + 1;
            end
        end
    end

    task automatic do_access(input [19:0] a, input we_in, input [7:0] wd,
                             output integer lat_ref, output integer lat_dut);
        @(negedge clk);
        addr = a; we = we_in; wdata = wd; req = 1'b1;
        lat_ref = 0; lat_dut = 0;
        // 両者のackを別々に計数する(片方だけ遅れても検出できるように)
        while (!ack_ref || !ack_dut) begin
            @(negedge clk);
            if (!ack_ref) lat_ref = lat_ref + 1;
            if (!ack_dut) lat_dut = lat_dut + 1;
        end
        @(negedge clk);
        req = 1'b0;
        while (ack_ref || ack_dut) @(negedge clk);
    endtask

    integer i;
    integer lr, ld;
    integer lat_mismatch = 0;

    initial begin
        rst_n = 0; addr = 0; wdata = 0; we = 0; req = 0;
        repeat (3) @(negedge clk);
        rst_n = 1;
        repeat (3) @(negedge clk);

        $display("==================================================");
        $display("  tb_psram_equiv_v0_1 (2026-08-28)");
        $display("  REF: ysd8800_psram_ctrl_v0_2");
        $display("  DUT: ysd8800_psram_ctrl_v0_3 (burst_len=1 固定)");
        $display("  段1: FSM遷移不変の確認(1サイクルもずれないこと)");
        $display("==================================================");

        // ---- E-1: 書き込み → 読み戻し ----
        do_access(20'h0_1234, 1'b1, 8'h5A, lr, ld);
        if (lr != ld) begin
            $display("[E-1] FAIL: latency ref=%0d dut=%0d", lr, ld);
            lat_mismatch++;
        end else $display("[E-1] PASS: write latency一致 (%0d)", lr);

        do_access(20'h0_1234, 1'b0, 8'h00, lr, ld);
        if (lr != ld) begin
            $display("[E-2] FAIL: latency ref=%0d dut=%0d", lr, ld);
            lat_mismatch++;
        end else if (rdata_dut !== 8'h5A) begin
            $display("[E-2] FAIL: read-back=%02h expected 5A", rdata_dut);
            errors++;
        end else $display("[E-2] PASS: read-back一致 (%02h, latency=%0d)",
                          rdata_dut, lr);

        // ---- E-3: 上位ビットが効くこと(V3.5リマップ) ----
        do_access(20'h1_4000, 1'b1, 8'hA5, lr, ld);
        do_access(20'h0_4000, 1'b0, 8'h00, lr, ld);
        if (rdata_dut === 8'hA5) begin
            $display("[E-3] FAIL: 上位ビットが効いていない");
            errors++;
        end else $display("[E-3] PASS: $14000と$04000が別領域");

        // ---- E-4: 500アクセス連続(リフレッシュ重畳を含む) ----
        for (i = 0; i < 500; i++) begin
            do_access(20'h0_2000 + i, 1'b0, 8'h00, lr, ld);
            if (lr != ld) lat_mismatch++;
        end
        if (lat_mismatch != 0) begin
            $display("[E-4] FAIL: latency不一致 %0d件", lat_mismatch);
            errors = errors + lat_mismatch;
        end else $display("[E-4] PASS: 500アクセス全てlatency一致");

        $display("--------------------------------------------------");
        $display("  比較サイクル数: %0d", cmp_cycle);
        if (errors == 0)
            $display("=== 段1 EQUIV PASS (v0.2 と v0.3 は完全一致) ===");
        else
            $display("=== 段1 EQUIV FAIL: %0d error(s) ===", errors);
        $finish;
    end
endmodule
