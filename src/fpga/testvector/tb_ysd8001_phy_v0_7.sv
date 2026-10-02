//=====================================================================
// tb_ysd8001_phy_v0_7.sv
//
//   YSD8001 UART 物理層 単体テストベンチ（TKT-V12）
//
//   Project : YSD8800 / YUI OS  --- 工程②.5 TKT-V12
//   Version : v0.7（2026-09-23）★M-12 追加（ボーレート誤差掃引 p=380〜460）・TB 全体タイムアウト 8e9 ns★
//             v0.6（2026-09-23）M-15 追加（真の全二重・TX 独立監視）
//             v0.5（2026-09-23）M-14 追加（PHY 経由オーバーラン＋復帰・review C-22）
//             v0.4（2026-09-23）M-13 追加（連続フレーム・アイドル 0）
//             v0.3（2026-09-23）M-11 追加（独立刺激源による RX 正常受信）・表示版数修正
//             v0.2（2026-09-21）DUT ysd8001_v0_3・M-3 に TX_LAT=1（B-17）
//             v0.1（2026-09-21）初版 M-3〜M-9
//   Date    : 2026-09-23
//   DUT     : ysd8800_ysd8001_v0_3.sv
//   Design  : v24_tktv12_uart_phy_design_v0_3_1.md §7（M-3〜M-9）
//             v24_tktv12_uart_phy_design_v0_4.md §13.4（M-11〜M-15）
//             review_v24_tktv12_uart_phy_v1_3.md C-19（C-1 は p=416/417 の両方）
//
//   構成は TB トップの parameter で選ぶ（TB がトップなので -P が効く）:
//     iverilog -P tb_ysd8001_phy_v0_7.PHY_EN=1 -P tb_ysd8001_phy_v0_7.BAUD_EN=1 ...
//     C-0 (0/0) : M-4 のみ（+ txd 常時1）
//     C-1 (1/0) : M-3 M-4 M-5 M-7 M-8 M-11(p=416/417)
//     C-2 (1/1) : M-3 M-4 M-5 M-6 M-7 M-8 M-9 M-11(br=416/208/104/7) M-13 M-14 M-15 M-12
//
//   ★観測規約（設計書 §7.1・B-10）★
//     エッジ N−1 と N の間の negedge でサンプルした値を「エッジ N の観測値」とする。
//     wr_tx が 1 であったエッジを N=0 とする。
//   ★期待値は数値のみを与え、導出を TB に書き写さない（原則67）★
//=====================================================================
`timescale 1ns / 1ps

module tb_ysd8001_phy_v0_7;

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

    //--- M-11〜: 独立刺激源による受信（設計書 v0.4 §13.4）---
    //   刺激源＝TB の drive_frame（値は TB カウンタ i）、判定源＝同じ TB 値。
    //   DUT の TX／出力から期待値を作らない（原則67）。送出と受信は並行。
    //   idle = フレーム間アイドル（ビット数、0 なら stop 直後に次の start）
    task automatic rx_indep(input int n, input int p, input int idle, input string tag);
        logic [7:0] r; bit ok; int miss, tmo, f0, v0;
        miss = 0; tmo = 0; f0 = ferr_cnt; v0 = rxv_cnt;
        rxd_drv = 1'b1; loop = 0;
        fork
            begin
                for (int i = 0; i < n; i++) begin
                    drive_frame(8'(i), 1'b1, p);
                    repeat (idle * p) @(negedge clk);
                end
            end
            begin
                for (int i = 0; i < n; i++) begin
                    rx_get(r, ok);
                    if (!ok) tmo++;
                    else if (r !== 8'(i)) begin
                        if (miss < 4) $display("    %s byte#%0d got %02h exp %02h", tag, i, r, 8'(i));
                        miss++;
                    end
                end
            end
        join
        repeat (2 * p) @(negedge clk);   // 余剰受信の検出窓
        chk(miss == 0 && tmo == 0, $sformatf("%s miss=%0d tmo=%0d / %0d", tag, miss, tmo, n));
        chk(ferr_cnt == f0,        $sformatf("%s FE=%0d", tag, ferr_cnt - f0));
        chk(rxv_cnt - v0 == n,     $sformatf("%s rx_valid=%0d exp %0d", tag, rxv_cnt - v0, n));
        $display("  %s : %0d bytes p=%0d idle=%0d miss=%0d tmo=%0d FE=%0d rx_valid=%0d",
                 tag, n, p, idle, miss, tmo, ferr_cnt - f0, rxv_cnt - v0);
    endtask

    //--- M-12: ボーレート誤差耐性（設計書 v0.4 §13.4／review v1.3 B-19・R-8）---
    //   1 点 = n バイト・アイドル idle ビット。受信側は送出完了まで RX_READY を
    //   ポーリングし受理バイトを全収集（取りこぼしでも待ち続けない）。
    //   期待値は TB 定数列 pat(i)（原則67）。合格 = n 個順番一致 かつ FE 増加 0。
    function automatic logic [7:0] pat(input int i);
        return 8'((i * 37) ^ 8'h55);
    endfunction
    task automatic rx_point(input int n, input int p, input int idle, output bit pass, output int got, output int fe);
        logic [7:0] qa[0:63]; int qn; logic [7:0] r; bit dd; int f0;   // ★iverilog 12: automatic 内キューは時刻0異常終了→固定長★
        qn = 0; dd = 0; f0 = ferr_cnt;
        rxd_drv = 1'b1; loop = 0;
        repeat (20 * p) @(negedge clk);                  // 受信器を初期状態へ
        if (dut.stat_r[1] !== 1'b0) wr(3'd4, 8'h02);
        fork
            begin
                for (int i = 0; i < n; i++) begin
                    drive_frame(pat(i), 1'b1, p);
                    repeat (idle * p) @(negedge clk);
                end
                repeat (2 * p) @(negedge clk);
                dd = 1;
            end
            begin
                while (!dd) begin
                    if (dut.stat_r[1] === 1'b1) begin
                        @(negedge clk); sel = 1; we = 0; addr = 3'd2;
                        #1 r = rdata;
                        @(negedge clk); sel = 0;
                        wr(3'd4, 8'h02);
                        if (qn < 64) qa[qn] = r;
                        qn++;
                    end
                    @(negedge clk);
                end
            end
        join
        got = qn; fe = ferr_cnt - f0;
        pass = (got == n) && (fe == 0);
        if (pass) for (int i = 0; i < n; i++) if (qa[i] !== pat(i)) pass = 0;
    endtask

    task automatic rx_sweep(input int n, input int p0, input int p1, input int idle);
        bit ok; int got, fe, p_lo, p_hi, bad_in;
        logic res[0:511]; // 添字 = p（iverilog は連想配列非対応のため固定長）
        for (int p = p0; p <= p1; p++) begin
            rx_point(n, p, idle, ok, got, fe);
            res[p] = ok;
            if (!ok) $display("    M-12 p=%0d (%0.1f%%) : NG got=%0d FE=%0d", p, (p - 417) * 100.0 / 417, got, fe);
        end
        p_lo = 417; while (p_lo - 1 >= p0 && res[p_lo - 1]) p_lo--;
        p_hi = 417; while (p_hi + 1 <= p1 && res[p_hi + 1]) p_hi++;
        bad_in = 0; for (int p = 396; p <= 438; p++) if (!res[p]) bad_in++;
        chk(res[417],                       "M-12 nominal p=417 NG");
        chk(bad_in == 0,                    $sformatf("M-12 NG points in 396..438 = %0d", bad_in));
        chk(p_lo >= 393 && p_lo <= 395,     $sformatf("M-12 p_lo=%0d vs pred 394 (+-1)", p_lo));
        chk(p_hi >= 439 && p_hi <= 441,     $sformatf("M-12 p_hi=%0d vs pred 440 (+-1)", p_hi));
        $display("  M-12 : window p_lo=%0d p_hi=%0d (pred 394/440)  NG-in-396..438=%0d", p_lo, p_hi, bad_in);
    endtask

    //--- M-15: 真の全二重（設計書 v0.4 §13.4）---
    //   CPU 役 1 本がバスを逐次使用（TX 書込／RX 読出＋W2C）＝バス競合なし。
    //   RX 刺激源 : 列 B = $FF-i（降順）、TX 開始から半ビット遅れ、アイドル 0。
    //   TX 監視   : txd を受動観測する独立 UART 受信器（中央サンプル）→ 列 A = i と照合。
    //   期待値は全て TB 定数列（原則67）。
    task automatic full_duplex(input int n, input int p, input string tag);
        int txi, rxi, rx_miss, tx_miss, tx_fe, tx_got, tmo, f0;
        logic [7:0] r, m;
        bit done;
        txi = 0; rxi = 0; rx_miss = 0; tx_miss = 0; tx_fe = 0; tx_got = 0; tmo = 0;
        done = 0; f0 = ferr_cnt;
        rxd_drv = 1'b1; loop = 0;
        if (dut.stat_r[1] !== 1'b0) wr(3'd4, 8'h02);
        fork
            //-- CPU 役 --
            begin
                while ((txi < n || rxi < n) && tmo < 20 * n * 10 * p) begin
                    if (txi < n && dut.stat_r[0] === 1'b1) begin
                        wr(3'd0, 8'(txi)); txi++;
                    end
                    if (rxi < n && dut.stat_r[1] === 1'b1) begin
                        @(negedge clk); sel = 1; we = 0; addr = 3'd2;
                        #1 r = rdata;
                        @(negedge clk); sel = 0;
                        wr(3'd4, 8'h02);
                        if (r !== 8'(8'hFF - rxi)) begin
                            if (rx_miss < 4) $display("    %s RX#%0d got %02h exp %02h", tag, rxi, r, 8'(8'hFF - rxi));
                            rx_miss++;
                        end
                        rxi++;
                    end
                    @(negedge clk); tmo++;
                end
            end
            //-- RX 刺激源（半ビット位相差）--
            begin
                repeat (p / 2) @(negedge clk);
                for (int i = 0; i < n; i++) drive_frame(8'(8'hFF - i), 1'b1, p);
            end
            //-- TX 監視（独立 UART 受信器）--
            begin
                for (int i = 0; i < n; i++) begin
                    @(negedge txd);
                    repeat (p / 2) @(negedge clk);
                    if (txd !== 1'b0) tx_fe++;
                    for (int b = 0; b < 8; b++) begin
                        repeat (p) @(negedge clk);
                        m[b] = txd;
                    end
                    repeat (p) @(negedge clk);
                    if (txd !== 1'b1) tx_fe++;
                    if (m !== 8'(i)) begin
                        if (tx_miss < 4) $display("    %s TX#%0d got %02h exp %02h", tag, i, m, 8'(i));
                        tx_miss++;
                    end
                    tx_got++;
                end
            end
        join
        repeat (2 * p) @(negedge clk);
        chk(txi == n && rxi == n,          $sformatf("%s CPU tx=%0d rx=%0d / %0d (tmo)", tag, txi, rxi, n));
        chk(rx_miss == 0,                  $sformatf("%s RX miss=%0d", tag, rx_miss));
        chk(tx_miss == 0 && tx_fe == 0 && tx_got == n,
                                           $sformatf("%s TX miss=%0d fe=%0d got=%0d", tag, tx_miss, tx_fe, tx_got));
        chk(ferr_cnt == f0,                $sformatf("%s RX FE=%0d", tag, ferr_cnt - f0));
        $display("  %s : %0d bytes p=%0d  TX got=%0d miss=%0d fe=%0d  RX got=%0d miss=%0d FE=%0d",
                 tag, n, p, tx_got, tx_miss, tx_fe, rxi, rx_miss, ferr_cnt - f0);
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
        $display("tb_ysd8001_phy_v0_7 v0.7  PHY_EN=%0d BAUD_EN=%0d", PHY_EN, BAUD_EN);
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

        //=== M-11: 独立フレーム正常受信（$00〜$FF 全値・アイドル 2 ビット）===
        if (PHY_EN && !BAUD_EN) begin
            rx_indep(256, 416, 2, "M-11 C-1 p=416");   // C-1 公称（review C-19）
            rx_indep(256, 417, 2, "M-11 C-1 p=417");   // 設計書 §13.4 記載値
        end
        if (PHY_EN && BAUD_EN) begin
            set_baud(16'd416); rx_indep(256, 417, 2, "M-11 br=416");
            set_baud(16'd208); rx_indep(256, 209, 2, "M-11 br=208");
            set_baud(16'd104); rx_indep(256, 105, 2, "M-11 br=104");
            set_baud(16'd7);   rx_indep(256,   8, 2, "M-11 br=7");
            set_baud(16'd416);

            //=== M-13: 連続フレーム（stop 直後に次 start・アイドル 0）===
            rx_indep(256, 417, 0, "M-13 br=416");

            //=== M-14: PHY 経由オーバーラン（後着破棄）＋復帰（review C-22）===
            //   期待値は TB 定数のみ（$5A/$C3/$3C）。RX_READY は W2C しない限り保持。
            begin
                logic [7:0] r3, buf_late, rd1; bit ok3; int f0, v0, vlate;
                f0 = ferr_cnt; v0 = rxv_cnt;
                if (dut.stat_r[1] !== 1'b0) wr(3'd4, 8'h02);   // 前提: RX_READY=0
                drive_frame(8'h5A, 1'b1, 417); repeat (2 * 417) @(negedge clk);
                chk(dut.stat_r[1] === 1'b1 && dut.rx_buf_r === 8'h5A, "M-14 1st byte not accepted");
                drive_frame(8'hC3, 1'b1, 417); repeat (2 * 417) @(negedge clk);
                vlate = rxv_cnt - v0; buf_late = dut.rx_buf_r;
                chk(vlate == 2,                 $sformatf("M-14 PHY rx_valid=%0d exp 2", vlate));
                chk(buf_late === 8'h5A,         $sformatf("M-14 rx_buf_r=%02h exp 5A (late byte must be dropped)", buf_late));
                chk(dut.stat_r[1] === 1'b1,     "M-14 RX_READY lost");
                @(negedge clk); sel = 1; we = 0; addr = 3'd2;
                #1 rd1 = rdata;
                @(negedge clk); sel = 0;
                chk(rd1 === 8'h5A,              $sformatf("M-14 MMIO read=%02h exp 5A", rd1));
                wr(3'd4, 8'h02);                                   // W2C
                chk(dut.stat_r[1] === 1'b0,     "M-14 W2C failed");
                // 復帰: 3 バイト目は正常受信
                fork
                    drive_frame(8'h3C, 1'b1, 417);
                    rx_get(r3, ok3);
                join
                chk(ok3 && r3 === 8'h3C,        $sformatf("M-14 recovery read=%02h ok=%0d exp 3C", r3, ok3));
                chk(ferr_cnt == f0,             $sformatf("M-14 FE=%0d", ferr_cnt - f0));
                $display("  M-14 : rx_valid=%0d  buf_after_late=%02h  read=%02h  recovery=%02h  FE=%0d",
                         vlate, buf_late, rd1, r3, ferr_cnt - f0);
            end

            //=== M-15: 真の全二重（TX 列 A 昇順 / RX 列 B 降順・半ビット位相差）===
            full_duplex(64, 417, "M-15 br=416");

            //=== M-12: ボーレート誤差耐性掃引（br=416・32 バイト・アイドル 2）===
            set_baud(16'd416);
            rx_sweep(32, 380, 460, 2);
        end

        $display("----------------------------------------");
        $display(" PHY TB : PASS=%0d  FAIL=%0d  %s", pass, fail,
                 (fail == 0) ? "*** ALL PASS ***" : "*** FAIL ***");
        $finish;
    end

    initial begin #(64'd8_000_000_000); $display("TIMEOUT"); $finish; end

endmodule
