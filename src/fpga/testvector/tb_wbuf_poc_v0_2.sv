//============================================================================
//  tb_wbuf_poc_v0_2.sv    ★poc（本番 TB ではない・登録対象外）★
//
//  Version : v0.1   (2026-09-18)
//  対象    : ysd8800_wbuf_v0_2.sv
//  設計書  : v23_stage25_wbuf_design_v0_2.md §7.2 / §8.2
//
//  目的    : W-1（吸収）/ W-2（ドレイン）の単体検証。
//            ★上位 TB では W-2 が全読出の 0.27% の経路でしか起きず、
//              意図した刺激を与えられない★ため単体で起こす（KY38）。
//
//  刺激    : ★非連続書込・ドレイン中の読出・8bit 単発・下隣接★ を直接与える。
//
//  模擬    : 下流（cdc_bridge+psram）を LAT サイクル応答のモデルで代用し、
//            mem[] に書き込む。★実 RTL の代用であり黄金値ではない★
//============================================================================

`timescale 1ns/1ps
`default_nettype none

module tb_wbuf_poc_v0_2;

    localparam int PHYS_AW = 20;
    localparam int LAT     = 4;
    localparam int HOLD_GRACE = 3;   // 1バイトあたりの下流応答（v19 実測 b+1≒4）

    logic clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    logic                wbuf_en;
    logic [PHYS_AW-1:0]  up_addr;
    logic [7:0]          up_wdata;
    logic                up_rd, up_wr;
    wire  [7:0]          up_rdata;
    wire                 up_ready;

    wire  [PHYS_AW-1:0]  dn_addr;
    wire  [7:0]          dn_wdata;
    wire                 dn_rd, dn_wr;
    logic [7:0]          dn_rdata;
    logic                dn_ready;

    logic                flush_req;
    wire                 flush_ack;

    wire                 dbg_hit, dbg_drain, dbg_full;
    wire                 dbg_valid;
    wire [PHYS_AW-1:0]   dbg_addr;
    wire [1:0]           dbg_be;
    wire [7:0]           dbg_d0, dbg_d1;

    ysd8800_wbuf_v0_2 #(.PHYS_AW(PHYS_AW)) dut (
        .cpu_clk(clk), .cpu_rst_n(rst_n), .wbuf_en_i(wbuf_en),
        .up_addr_i(up_addr), .up_wdata_i(up_wdata),
        .up_rd_i(up_rd), .up_wr_i(up_wr),
        .up_rdata_o(up_rdata), .up_ready_o(up_ready),
        .dn_addr_o(dn_addr), .dn_wdata_o(dn_wdata),
        .dn_rd_o(dn_rd), .dn_wr_o(dn_wr),
        .dn_rdata_i(dn_rdata), .dn_ready_i(dn_ready),
        .flush_req_i(flush_req), .flush_ack_o(flush_ack),
        .dbg_wb_hit_o(dbg_hit), .dbg_wb_drain_o(dbg_drain),
        .dbg_wb_full_o(dbg_full),
        .dbg_wb_valid_o(dbg_valid), .dbg_wb_addr_o(dbg_addr),
        .dbg_wb_be_o(dbg_be),
        .dbg_wb_data0_o(dbg_d0), .dbg_wb_data1_o(dbg_d1)
    );

    //------------------------------------------------------------------
    //  下流モデル（LAT サイクルで応答し mem[] を更新）
    //------------------------------------------------------------------
    logic [7:0] mem [0:65535];
    int         lat_cnt = 0;
    int         wr_txn  = 0;   // 下流へ出た書込トランザクション数

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dn_ready <= 1'b0; lat_cnt <= 0; wr_txn <= 0;
        end else begin
            dn_ready <= 1'b0;
            if (dn_rd || dn_wr) begin
                if (lat_cnt >= LAT-1) begin
                    lat_cnt  <= 0;
                    dn_ready <= 1'b1;
                    if (dn_wr) begin
                        mem[dn_addr[15:0]] <= dn_wdata;
                        wr_txn <= wr_txn + 1;
                    end
                    if (dn_rd) dn_rdata <= mem[dn_addr[15:0]];
                end else lat_cnt <= lat_cnt + 1;
            end else lat_cnt <= 0;
        end
    end

    //------------------------------------------------------------------
    //  判定
    //------------------------------------------------------------------
    int errors = 0;
    task automatic chk(input string name, input logic cond);
        if (!cond) begin
            $display("[FAIL] %s  (t=%0t)", name, $time);
            errors++;
        end else $display("[ ok ] %s", name);
    endtask

    //  1サイクルで受理されたか（ready を見て次サイクルで要求を下ろす）
    int cyc_used;
    task automatic do_write(input [PHYS_AW-1:0] a, input [7:0] d);
        cyc_used = 0;
        @(negedge clk);
        up_addr = a; up_wdata = d; up_wr = 1; up_rd = 0;
        @(posedge clk);
        cyc_used++;
        while (!up_ready) begin
            @(posedge clk);
            cyc_used++;
        end
        @(negedge clk);
        up_wr = 0;
    endtask

    task automatic do_read(input [PHYS_AW-1:0] a);
        cyc_used = 0;
        @(negedge clk);
        up_addr = a; up_rd = 1; up_wr = 0;
        @(posedge clk);
        cyc_used++;
        while (!up_ready) begin
            @(posedge clk);
            cyc_used++;
        end
        @(negedge clk);
        up_rd = 0;
    endtask

    int drain_seen;
    always @(posedge clk) if (dbg_drain) drain_seen++;

    initial begin
        up_addr=0; up_wdata=0; up_rd=0; up_wr=0;
        wbuf_en=1; flush_req=0; drain_seen=0;
        for (int i=0;i<65536;i++) mem[i]=8'h00;
        repeat(4) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);

        $display("=== tb_wbuf_poc_v0_2 v0.1 : W-1 / W-2 ===");

        //------------------------------------------------------------
        // W-1a : 16bit ペア（上隣接）を各1サイクルで吸収
        //------------------------------------------------------------
        do_write(20'h01000, 8'hAA);
        chk("W-1a byte0 accepted in 1 cycle", cyc_used == 1);
        $display("[PROBE] before byte1: st=%0d valid=%b be=%b drain=%b",
                 dut.st_r, dbg_valid, dbg_be, dbg_drain);
        do_write(20'h01001, 8'hBB);
        chk("W-1a byte1 accepted in 1 cycle", cyc_used == 1);

        // ドレイン完了待ち
        wait (!dbg_valid); repeat(2) @(posedge clk);
        chk("W-1a mem[1000]=AA", mem[16'h1000]==8'hAA);
        chk("W-1a mem[1001]=BB", mem[16'h1001]==8'hBB);

        //------------------------------------------------------------
        // W-1b : ★下隣接★（上位バイト先行）— M-2 の ±1 判定
        //------------------------------------------------------------
        do_write(20'h02001, 8'hCC);
        chk("W-1b high byte accepted in 1 cycle", cyc_used == 1);
        do_write(20'h02000, 8'hDD);
        chk("W-1b low  byte accepted in 1 cycle (down-adjacent)", cyc_used == 1);
        wait (!dbg_valid); repeat(2) @(posedge clk);
        chk("W-1b mem[2000]=DD", mem[16'h2000]==8'hDD);
        chk("W-1b mem[2001]=CC", mem[16'h2001]==8'hCC);

        //------------------------------------------------------------
        // W-1c : 8bit 単発（be 片側のみ）→ 下流へは1トランザクションのみ
        //------------------------------------------------------------
        wr_txn = 0;
        do_write(20'h03000, 8'hEE);
        wait (!dbg_valid); repeat(2) @(posedge clk);
        chk("W-1c mem[3000]=EE", mem[16'h3000]==8'hEE);
        chk("W-1c single byte emits 1 txn", wr_txn == 1);

        //------------------------------------------------------------
        // W-2a : ★ドレイン中の読出は待たされ、古い値を読まない★
        //------------------------------------------------------------
        mem[16'h4000] = 8'h11;          // 事前に旧値
        do_write(20'h04000, 8'h99);     // 吸収（mem はまだ 11）
        chk("W-2a write absorbed", cyc_used == 1);
        chk("W-2a buffer holds data", dbg_valid === 1'b1);
        drain_seen = 0;
        do_read(20'h04000);             // ★ドレインを待ってから読む★
        chk("W-2a read waited (>1 cycle)", cyc_used > 1);
        chk("W-2a drain observed",        drain_seen > 0);
        chk("W-2a read returns NEW value", up_rdata == 8'h99);
        chk("W-2a mem updated",            mem[16'h4000]==8'h99);

        //------------------------------------------------------------
        // W-2b : ★非連続書込は full を立てて待たせる★
        //------------------------------------------------------------
        do_write(20'h05000, 8'h55);     // 1バイト保持
        chk("W-2b first accepted", cyc_used == 1);
        do_write(20'h06000, 8'h66);     // ★非連続★
        chk("W-2b non-adjacent waited (>1 cycle)", cyc_used > 1);
        wait (!dbg_valid); repeat(2) @(posedge clk);
        chk("W-2b mem[5000]=55", mem[16'h5000]==8'h55);
        chk("W-2b mem[6000]=66", mem[16'h6000]==8'h66);

        //------------------------------------------------------------
        // W-2c : FLUSH はドレイン完了まで ack を返さない（C-4）
        //------------------------------------------------------------
        do_write(20'h07000, 8'h77);
        @(negedge clk); flush_req = 1;
        @(posedge clk);
        chk("W-2c flush_ack deasserted while dirty", flush_ack === 1'b0);
        wait (flush_ack);
        chk("W-2c flush_ack after drain", dbg_valid === 1'b0);
        chk("W-2c mem[7000]=77", mem[16'h7000]==8'h77);
        @(negedge clk); flush_req = 0;

        //------------------------------------------------------------
        // W-0(単体版) : wbuf_en=0 でバイパス（組合せ素通し）
        //------------------------------------------------------------
        wbuf_en = 0;
        repeat(2) @(posedge clk);
        wr_txn = 0;
        do_write(20'h08000, 8'h88);
        chk("W-0 bypass write takes LAT cycles", cyc_used >= LAT);
        chk("W-0 bypass mem[8000]=88", mem[16'h8000]==8'h88);
        chk("W-0 bypass buffer stays empty", dbg_valid === 1'b0);

        // 効果の定量確認：16bitペア書込 100回の総サイクル
        begin
            int t0, t1, cyc_en, cyc_byp;
            wbuf_en = 1; wait(!dbg_valid); repeat(HOLD_GRACE+2) @(posedge clk);
            t0 = $time;
            for (int i=0;i<100;i++) begin
                do_write(20'h10000 + i*2,     8'hA0+i[7:0]);
                do_write(20'h10000 + i*2 + 1, 8'hB0+i[7:0]);
            end
            wait(!dbg_valid);
            t1 = $time; cyc_en = (t1-t0)/10;
            wbuf_en = 0; repeat(4) @(posedge clk);
            t0 = $time;
            for (int i=0;i<100;i++) begin
                do_write(20'h20000 + i*2,     8'hA0+i[7:0]);
                do_write(20'h20000 + i*2 + 1, 8'hB0+i[7:0]);
            end
            t1 = $time; cyc_byp = (t1-t0)/10;
            $display("[EFFECT-A back-to-back] en=%0d cyc / bypass=%0d cyc (%.1f%%)",
                     cyc_en, cyc_byp, 100.0*(cyc_byp-cyc_en)/cyc_byp);
            // 実測相当: ペア間隔12サイクル(v21 §3.1: 12以上が49.9%)
            wbuf_en = 1; wait(!dbg_valid); repeat(4) @(posedge clk);
            t0 = $time;
            for (int i=0;i<100;i++) begin
                do_write(20'h30000 + i*2,     8'hA0+i[7:0]);
                do_write(20'h30000 + i*2 + 1, 8'hB0+i[7:0]);
                repeat(12) @(posedge clk);
            end
            wait(!dbg_valid); t1 = $time; cyc_en = (t1-t0)/10;
            wbuf_en = 0; repeat(4) @(posedge clk);
            t0 = $time;
            for (int i=0;i<100;i++) begin
                do_write(20'h40000 + i*2,     8'hA0+i[7:0]);
                do_write(20'h40000 + i*2 + 1, 8'hB0+i[7:0]);
                repeat(12) @(posedge clk);
            end
            t1 = $time; cyc_byp = (t1-t0)/10;
            $display("[EFFECT-B spaced-12] en=%0d cyc / bypass=%0d cyc (%.1f%%)",
                     cyc_en, cyc_byp, 100.0*(cyc_byp-cyc_en)/cyc_byp);
        end
        $display("-----------------------------------------");
        if (errors == 0) $display("=== tb_wbuf_poc_v0_2 : ALL PASS ===");
        else             $display("=== tb_wbuf_poc_v0_2 : FAIL (%0d) ===", errors);
        $finish;
    end

    initial begin
        #200000;
        $display("=== tb_wbuf_poc_v0_2 : TIMEOUT ===");
        $finish;
    end

endmodule

`default_nettype wire
