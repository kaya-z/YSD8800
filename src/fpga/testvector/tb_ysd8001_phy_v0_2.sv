//=====================================================================
// tb_ysd8001_phy_v0_2.sv
//
//   YSD8001 UART 物理層 単体テストベンチ（TKT-V12）
//
//   Project : YSD8800 / YUI OS  --- 工程②.5 TKT-V12
//   Version : v0.2（v0.1: 2026-09-21）★DUT ysd8001_v0_3・M-3 に TX_LAT=1（B-17）★
//   Date    : 2026-09-21
//   DUT     : ysd8800_ysd8001_v0_3.sv
//   Design  : v24_tktv12_uart_phy_design_v0_3_1.md §7（M-3〜M-9）
//
//   構成は TB トップの parameter で選ぶ（TB がトップなので -P が効く）:
//     iverilog -P tb_ysd8001_phy_v0_2.PHY_EN=1 -P tb_ysd8001_phy_v0_2.BAUD_EN=1 ...
//     C-0 (0/0) : M-4 のみ（+ txd 常時1）
//     C-1 (1/0) : M-3 M-4 M-5 M-7 M-8
//     C-2 (1/1) : M-3 M-4 M-5 M-6 M-7 M-8 M-9
//
//   ★観測規約（設計書 §7.1・B-10）★
//     エッジ N−1 と N の間の negedge でサンプルした値を「エッジ N の観測値」とする。
//     wr_tx が 1 であったエッジを N=0 とする。
//   ★期待値は数値のみを与え、導出を TB に書き写さない（原則67）★
//=====================================================================
`timescale 1ns / 1ps

module tb_ysd8001_phy_v0_2;

    parameter bit PHY_EN  = 1'b0;
    parameter bit BAUD_EN = 1'b0;

    //--- 期待値（設計書 §7 M-4 / §4.3。数値のみ）---
    localparam int N_C0      = 4168;
    localparam int N_C1      = 4168;
    localparam int N_C2_416  = 4171;

    logic       clk = 1'b0;
    logic       rst_n = 1'b0;
    logic       sel = 1'b0, we = 1'b0;
    logic [2:0] addr = 3'd0;
    logic [7:0] wdata = 8'h00;
    logic [7:0] rdata;
    logic       irq_rx, irq_tx;
    logic       txd, rxd, ferr;
    logic       loop = 1'b0;
    logic       rxd_drv = 1'b1;

    assign rxd = loop ? txd : rxd_drv;

    always #125 clk = ~clk;   // 4MHz

    ysd8800_ysd8001_v0_3 #(.PHY_EN(PHY_EN), .BAUD_EN(BAUD_EN)) dut (
        .clk(clk), .rst_n(rst_n),
        .sel_i(sel), .addr_i(addr), .we_i(we), .wdata_i(wdata), .rdata_o(rdata),
        .irq_rx_o(irq_rx), .irq_tx_o(irq_tx),
        .rx_valid_i(1'b0), .rx_data_i(8'h00),
        .tx_valid_o(), .tx_data_o(),
        .txd_o(txd), .rxd_i(rxd), .rx_frame_err_o(ferr)
    );

    int cyc = 0;
    always @(posedge clk) cyc <= cyc + 1;

    int pass = 0, fail = 0;
    task automatic chk(input bit ok, input string msg);
        if (ok) pass++;
        else begin fail++; $display("  [FAIL] %s", msg); end
    endtask

    //--- バス書込（1サイクル）: 戻った時点は N=0 エッジ直後の negedge ---
    int e0;
    task automatic wr(input logic [2:0] a, input logic [7:0] d);
        @(negedge clk); sel = 1; we = 1; addr = a; wdata = d;
        @(negedge clk); sel = 0; we = 0;
        e0 = cyc;
    endtask

    task automatic set_baud(input logic [15:0] b);
        wr(3'd6, b[7:0]); wr(3'd7, b[15:8]);
    endtask

    //--- ビット周期（設計書 §4.3 の配分。数値のみ）---
    localparam int TX_LAT = 1;   // ★B-17: 出力 FF 1 段（設計書 v0.4 §13／review v1.3）★

    function automatic int per(input int idx, input int br);
        if (BAUD_EN) return br + 1;
        else         return (idx == 9) ? 423 : 416;
    endfunction

    //--- M-3 + M-4: 1バイト送出の形状と TX_READY 復帰エッジ ---
    task automatic tx_shape(input logic [7:0] d, input int br, input int n_exp, input string tag);
        logic [9:0] fr;
        int k, idx, acc, n_obs, bad;
        fr = {1'b1, d, 1'b0};
        wr(3'd0, d);
        n_obs = -1; bad = 0; k = 0;
        while (n_obs < 0 && k < 200000) begin
            if (PHY_EN) begin
                // 期待ビット位置
                // ★v0.2: txd_o は FF 出力（B-17）→ 波形は TX_LAT サイクル遅れる★
                if (k < TX_LAT) begin
                    if (txd !== 1'b1) bad++;
                end else begin
                    idx = 0; acc = per(0, br);
                    while (idx < 9 && (k - TX_LAT) >= acc) begin idx++; acc += per(idx, br); end
                    if ((k - TX_LAT) < acc && txd !== fr[idx]) bad++;
                end
            end
            else if (txd !== 1'b1) bad++;
            if (dut.stat_r[0] === 1'b1) n_obs = k + 1;
            @(negedge clk); k++;
        end
        chk(bad == 0, $sformatf("%s M-3 txd shape mismatch x%0d", tag, bad));
        chk(n_obs == n_exp, $sformatf("%s M-4 N=%0d exp=%0d", tag, n_obs, n_exp));
        $display("  %s : M-4 N=%0d (exp %0d)  M-3 bad=%0d", tag, n_obs, n_exp, bad);
    endtask

    //--- 受信1バイト待ち → 読出 → W2C（M-5 手順・B-8）---
    task automatic rx_get(output logic [7:0] d, output bit ok);
        int t;
        t = 0;
        while (dut.stat_r[1] !== 1'b1 && t < 800000) begin @(negedge clk); t++; end
        ok = (t < 800000);
        @(negedge clk); sel = 1; we = 0; addr = 3'd2;
        #1 d = rdata;
        @(negedge clk); sel = 0;
        wr(3'd4, 8'h02);                 // RX_READY の W2C
    endtask

    task automatic wait_txr();
        int t; t = 0;
        while (dut.stat_r[0] !== 1'b1 && t < 800000) begin @(negedge clk); t++; end
    endtask

    //--- M-5 / M-6: ループバック ---
    int  lead_min, lead_max;
    int  t_rxv, t_txd;
    always @(posedge clk) begin
        if (dut.rx_valid_phy === 1'b1) t_rxv = cyc;
        if (dut.tx_done     === 1'b1) t_txd = cyc;
    end

    task automatic loopback(input int nbytes, input string tag);
        logic [7:0] s, r; bit ok; int miss, lead;
        miss = 0; lead_min = 1 << 30; lead_max = -(1 << 30);
        loop = 1;
        for (int i = 0; i < nbytes; i++) begin
            s = 8'(i) ^ 8'h5A;
            wait_txr();
            wr(3'd0, s);
            rx_get(r, ok);
            wait_txr();
            lead = t_txd - t_rxv;
            if (lead < lead_min) lead_min = lead;
            if (lead > lead_max) lead_max = lead;
            if (!ok || r !== s) miss++;
        end
        loop = 0;
        chk(miss == 0, $sformatf("%s loopback miss=%0d/%0d", tag, miss, nbytes));
        $display("  %s : loopback %0d bytes miss=%0d  lead(tx_done-rx_valid)=%0d..%0d",
                 tag, nbytes, miss, lead_min, lead_max);
    endtask

    //--- 手動フレーム送出（M-8 用）---
    task automatic drive_frame(input logic [7:0] d, input bit stopv, input int p);
        logic [9:0] fr; fr = {stopv, d, 1'b0};
        for (int b = 0; b < 10; b++) begin
            rxd_drv = fr[b];
            repeat (p) @(negedge clk);
        end
    endtask

    int ferr_cnt, ferr_w, ferr_wmax;
    always @(posedge clk) begin
        if (ferr === 1'b1) begin ferr_w <= ferr_w + 1; end
        else begin
            if (ferr_w > 0) begin ferr_cnt <= ferr_cnt + 1;
                if (ferr_w > ferr_wmax) ferr_wmax <= ferr_w; end
            ferr_w <= 0;
        end
    end

    int rxv_cnt;
    always @(posedge clk) if (dut.rx_valid_phy === 1'b1) rxv_cnt <= rxv_cnt + 1;

    initial begin
        logic [7:0] b0; int c0;
        ferr_cnt = 0; ferr_w = 0; ferr_wmax = 0; rxv_cnt = 0;
        $display("tb_ysd8001_phy_v0_2 v0.1  PHY_EN=%0d BAUD_EN=%0d", PHY_EN, BAUD_EN);
        repeat (4) @(negedge clk); rst_n = 1; repeat (4) @(negedge clk);

        //=== M-3/M-4 ===
        if (!PHY_EN)      tx_shape(8'hA5, 416, N_C0,     "C-0");
        else if (!BAUD_EN) tx_shape(8'hA5, 416, N_C1,     "C-1");
        else              tx_shape(8'hA5, 416, N_C2_416, "C-2");

        if (PHY_EN) begin
            //=== M-5 ===
            loopback(256, "M-5");

            //=== M-7: 1サイクルグリッチ ===
            c0 = rxv_cnt;
            @(negedge clk); rxd_drv = 0; @(negedge clk); rxd_drv = 1;
            repeat (2000) @(negedge clk);
            chk(rxv_cnt == c0 && dut.stat_r[1] == 0, "M-7 glitch accepted");
            $display("  M-7 : glitch -> rx_valid %0d", rxv_cnt - c0);

            //=== M-8: フレーミングエラー ＋ 0 保持で再発しない（C-8）===
            b0 = dut.rx_buf_r; c0 = rxv_cnt;
            drive_frame(8'h3C, 1'b0, BAUD_EN ? 417 : 416);
            repeat (5000) @(negedge clk);      // 0 のまま約 12bit 保持
            rxd_drv = 1; repeat (2000) @(negedge clk);
            chk(ferr_cnt == 1,  $sformatf("M-8 ferr pulses=%0d", ferr_cnt));
            chk(ferr_wmax == 1, $sformatf("M-8 ferr width=%0d", ferr_wmax));
            chk(rxv_cnt == c0 && dut.rx_buf_r == b0 && dut.stat_r[1] == 0,
                "M-8 data not discarded");
            $display("  M-8 : ferr pulses=%0d width=%0d rx_valid=%0d",
                     ferr_cnt, ferr_wmax, rxv_cnt - c0);
        end

        if (PHY_EN && BAUD_EN) begin
            //=== M-6: BAUD 変更（レジスタ半減系＋上位仕様式系 C-15）===
            set_baud(16'd208); loopback(16, "M-6 br=208");
            set_baud(16'd104); loopback(16, "M-6 br=104");
            set_baud(16'd207); loopback(16, "M-6 br=207");
            set_baud(16'd103); loopback(16, "M-6 br=103");

            //=== M-9: baud_r=7（baud_div=8）→ 受信成立 ===
            set_baud(16'd7);   loopback(16, "M-9 br=7");

            //=== M-9: baud_r=0 → TX 周期1で完了・RX は受信しない・ハングしない ===
            set_baud(16'd0);
            c0 = rxv_cnt; loop = 1;
            tx_shape(8'h96, 0, 11, "M-9 br=0");
            repeat (100) @(negedge clk);
            loop = 0;
            chk(rxv_cnt == c0, "M-9 br=0 RX should not receive");
            $display("  M-9 br=0 : rx_valid %0d (exp 0)", rxv_cnt - c0);
            set_baud(16'd416);
        end

        $display("----------------------------------------");
        $display(" PHY TB : PASS=%0d  FAIL=%0d  %s", pass, fail,
                 (fail == 0) ? "*** ALL PASS ***" : "*** FAIL ***");
        $finish;
    end

    initial begin #3_000_000_000; $display("TIMEOUT"); $finish; end

endmodule
