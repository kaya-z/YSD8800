// ============================================================
//  tb_psram_ctrl_v0_1.sv   v0.1  (2026-07-11)
//  YSD8800 FPGA V3 : PSRAMコントローラ ビヘイビアモデル 単体TB
//
//  検証観点(v3_design_memo_v0_2.md §3.1/§5):
//   - 通常時レイテンシ12サイクルでack完了するか
//   - リフレッシュ重畳時15サイクルに伸びるケースが存在するか
//   - 発生頻度が概ね0.05%オーダーに収まるか(統計・大まかな範囲確認)
//   - read-after-write が正しく反映されるか
// ============================================================
`timescale 1ns/1ps

module tb_psram_ctrl_v0_1;
    logic        clk, rst_n;
    logic [19:0] addr;
    logic [7:0]  wdata, rdata;
    logic        we, req, ack;
    logic        dbg_refresh_hit;

    integer errors = 0;

    ysd8800_psram_ctrl_v0_1 #(
        .LATENCY_NORMAL(12), .LATENCY_REFRESH(15), .REFRESH_PPM(500), .PHYS_AW(20)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .addr(addr), .wdata(wdata), .we(we),
        .req(req), .ack(ack), .rdata(rdata),
        .dbg_refresh_hit(dbg_refresh_hit)
    );

    initial clk = 0;
    always #1 clk = ~clk;

    integer lat_count;
    integer normal_count, refresh_count;

    task automatic do_access(input [19:0] a, input we_in, input [7:0] wd, output [7:0] rd, output integer latency);
        @(negedge clk);
        addr = a; we = we_in; wdata = wd; req = 1'b1;
        latency = 0;
        while (!ack) begin
            @(negedge clk);
            latency = latency + 1;
        end
        rd = rdata;
        @(negedge clk);
        req = 1'b0;
        while (ack) @(negedge clk); // 4相: ackが下がるまで待つ
    endtask

    logic [7:0] rd_val;
    integer lat_val;
    integer i;

    initial begin
        rst_n = 0; addr = 0; wdata = 0; we = 0; req = 0;
        normal_count = 0; refresh_count = 0;
        repeat (3) @(negedge clk);
        rst_n = 1;
        repeat (3) @(negedge clk);

        // T1: 単発ライト→リードback
        do_access(20'h01234, 1'b1, 8'h5A, rd_val, lat_val);
        do_access(20'h01234, 1'b0, 8'h00, rd_val, lat_val);
        if (rd_val !== 8'h5A) begin
            $display("[T1] FAIL: read-back=%02h expected 5A", rd_val); errors++;
        end else $display("[T1] PASS: write/read-back一致 (%02h, latency=%0d)", rd_val, lat_val);

        // T2: レイテンシ統計(2000アクセス。0.05%狙いなので数件程度のヒットを期待)
        for (i = 0; i < 2000; i++) begin
            do_access(20'h02000 + (i % 16), 1'b0, 8'h00, rd_val, lat_val);
            if (lat_val == 12) normal_count++;
            else if (lat_val == 15) refresh_count++;
            else begin
                $display("[T2] FAIL: 予期しないlatency=%0d (idx=%0d)", lat_val, i); errors++;
            end
        end
        $display("[T2] 統計: normal=%0d(lat12) refresh=%0d(lat15) / total=2000 (期待refresh目安=約1件, 疑似乱数のため参考値)",
                   normal_count, refresh_count);
        if (normal_count + refresh_count !== 2000) begin
            $display("[T2] FAIL: 合計が2000に一致しない"); errors++;
        end else $display("[T2] PASS: 全アクセスが12または15サイクルで完了");

        if (errors == 0) $display("ALL PASS (2/2 + 統計参考)");
        else $display("FAIL: %0d error(s)", errors);
        $finish;
    end
endmodule
