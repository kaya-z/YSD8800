//=====================================================================
// tb_ysd8004_v0_1.sv
//
//   YSD8004 割り込みコントローラ 単体テストベンチ
//
//   Project : YSD8800 / YUI OS  --- Step 8 FPGA / V3.7 S3
//   Version : v0.1
//   Date    : 2026-07-12
//   DUT     : ysd8800_ysd8004_v0_1.sv (v0.1)
//   Design  : v3_7_design_memo_v0_2.md §5.2（検証項目8件）
//   Golden  : emu23 v1.09 (L294-329, L629-630, L761-762)
//
//   検証項目（設計メモ §5.2）:
//     1. リセット値（IRQ_STAT=0x00 / IRQ_MASK=0x04）★最重要 KY-A★
//     2. IRQ_MASK の R/W
//     3. IRQ_STAT の Write-to-Clear（1を書いたビットのみクリア・0は不変）
//     4. マスク動作（マスクされた源は IRQ_STAT に立たない）
//     5. 集約（複数源同時 → IRQ1 が1本アサート）
//     6. レベル保持（IRQ_STAT != 0 の間 IRQ1 アサート継続）★KY-D★
//     7. クリア後の IRQ1 デアサート
//     8. 上位バイト（$FCB3/$FCB5）が 0x00 を返すこと ★KY-B★
//
//   注: vvp の stdout は SIGTERM で失われうるため、in-sim watchdog を置く
//       （kaizen: rc=124 誤診断の再発防止）
//=====================================================================

`timescale 1ns / 1ps

module tb_ysd8004_v0_1;

    //--- アドレス定数（★実アドレス $FCB2..$FCB5 の下位3bit★）---
    //  ★【S5 BUG-1 の教訓】★
    //    当初この定数を「$FCB2基点の2bitオフセット(0,1,2,3)」としていたが、
    //    実際にスタブが渡すのは mmio_addr の下位ビットであり、
    //      $FCB2[1:0]=2'b10 / $FCB4[1:0]=2'b00
    //    となって STAT と MASK が入れ替わっていた。
    //    単体TBがaddr_iを「自分の思う値」で与えていたため露見せず、
    //    S5統合で無限割込ループとして初めて発覚した。
    //    → TBも【実アドレスから機械的に導出】する形に改める（偽合格防止）。
    localparam logic [15:0] ADDR_STAT = 16'hFCB2;
    localparam logic [15:0] ADDR_MASK = 16'hFCB4;

    localparam logic [2:0] A_STAT_LO = ADDR_STAT[2:0];         // 3'b010
    localparam logic [2:0] A_STAT_HI = (ADDR_STAT[2:0] + 3'd1); // 3'b011
    localparam logic [2:0] A_MASK_LO = ADDR_MASK[2:0];         // 3'b100
    localparam logic [2:0] A_MASK_HI = (ADDR_MASK[2:0] + 3'd1); // 3'b101

    //--- IRQ_STAT ビット（emu23 L298-300）---
    localparam logic [7:0] B_UART_RX = 8'h01;
    localparam logic [7:0] B_STOR    = 8'h02;
    localparam logic [7:0] B_UART_TX = 8'h04;

    logic       clk;
    logic       rst_n;
    logic       sel_i;
    logic [2:0] addr_i;
    logic       we_i;
    logic [7:0] wdata_i;
    logic [7:0] rdata_o;
    logic       irq_src_uart_rx;
    logic       irq_src_stor;
    logic       irq_src_uart_tx;
    logic       irq1_o;

    integer pass_cnt = 0;
    integer fail_cnt = 0;

    ysd8800_ysd8004_v0_1 dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .sel_i           (sel_i),
        .addr_i          (addr_i),
        .we_i            (we_i),
        .wdata_i         (wdata_i),
        .rdata_o         (rdata_o),
        .irq_src_uart_rx (irq_src_uart_rx),
        .irq_src_stor    (irq_src_stor),
        .irq_src_uart_tx (irq_src_uart_tx),
        .irq1_o          (irq1_o)
    );

    //--- クロック 10ns ---
    initial clk = 1'b0;
    always #5 clk = ~clk;

    //--- watchdog（stdout消失対策）---
    initial begin
        #20000;
        $display("FAIL: WATCHDOG TIMEOUT");
        $finish;
    end

    //-----------------------------------------------------------------
    // タスク
    //-----------------------------------------------------------------
    task automatic chk8(input string name, input logic [7:0] act, input logic [7:0] exp);
        begin
            if (act === exp) begin
                pass_cnt++;
                $display("PASS: %-42s act=%02h exp=%02h", name, act, exp);
            end else begin
                fail_cnt++;
                $display("FAIL: %-42s act=%02h exp=%02h", name, act, exp);
            end
        end
    endtask

    task automatic chk1(input string name, input logic act, input logic exp);
        begin
            if (act === exp) begin
                pass_cnt++;
                $display("PASS: %-42s act=%0b exp=%0b", name, act, exp);
            end else begin
                fail_cnt++;
                $display("FAIL: %-42s act=%0b exp=%0b", name, act, exp);
            end
        end
    endtask

    // MMIO 書込（1サイクル）
    task automatic bus_wr(input logic [2:0] a, input logic [7:0] d);
        begin
            @(negedge clk);
            sel_i   = 1'b1;
            we_i    = 1'b1;
            addr_i  = a;
            wdata_i = d;
            @(negedge clk);
            sel_i   = 1'b0;
            we_i    = 1'b0;
            wdata_i = 8'h00;
        end
    endtask

    // MMIO 読出（組合せ出力なので値をサンプル）
    task automatic bus_rd(input logic [2:0] a, output logic [7:0] d);
        begin
            @(negedge clk);
            sel_i  = 1'b1;
            we_i   = 1'b0;
            addr_i = a;
            #1;
            d = rdata_o;
            @(negedge clk);
            sel_i  = 1'b0;
        end
    endtask

    // 割込源を1クロックパルスで与える（§4.3 規約）
    task automatic pulse_src(input logic rx, input logic st, input logic tx);
        begin
            @(negedge clk);
            irq_src_uart_rx = rx;
            irq_src_stor    = st;
            irq_src_uart_tx = tx;
            @(negedge clk);
            irq_src_uart_rx = 1'b0;
            irq_src_stor    = 1'b0;
            irq_src_uart_tx = 1'b0;
        end
    endtask

    //-----------------------------------------------------------------
    // 本体
    //-----------------------------------------------------------------
    logic [7:0] d;
    integer     i;

    initial begin
        $display("=== tb_ysd8004_v0_1 : YSD8004 unit test (V3.7 S3) ===");

        sel_i           = 1'b0;
        we_i            = 1'b0;
        addr_i          = 3'b000;
        wdata_i         = 8'h00;
        irq_src_uart_rx = 1'b0;
        irq_src_stor    = 1'b0;
        irq_src_uart_tx = 1'b0;

        rst_n = 1'b0;
        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        //=============================================================
        // [1] リセット値 ★最重要・KY-A★  emu23 L303/L307
        //=============================================================
        $display("--- [1] reset values (KY-A) ---");
        bus_rd(A_STAT_LO, d);
        chk8("1a IRQ_STAT reset = 0x00", d, 8'h00);
        bus_rd(A_MASK_LO, d);
        chk8("1b IRQ_MASK reset = 0x04 (NOT 0x00)", d, 8'h04);
        chk1("1c irq1 deasserted at reset", irq1_o, 1'b0);

        //=============================================================
        // [8] 上位バイトが 0x00 を返す ★KY-B★（先に確認しておく）
        //=============================================================
        $display("--- [8] upper byte returns 0x00 (KY-B) ---");
        bus_rd(A_STAT_HI, d);
        chk8("8a $FCB3 (STAT hi) = 0x00", d, 8'h00);
        bus_rd(A_MASK_HI, d);
        chk8("8b $FCB5 (MASK hi) = 0x00", d, 8'h00);

        //=============================================================
        // [2] IRQ_MASK の R/W   emu23 L630/L762
        //=============================================================
        $display("--- [2] IRQ_MASK read/write ---");
        bus_wr(A_MASK_LO, 8'h00);          // 全許可
        bus_rd(A_MASK_LO, d);
        chk8("2a IRQ_MASK <= 0x00", d, 8'h00);
        bus_wr(A_MASK_LO, 8'h07);          // 全マスク
        bus_rd(A_MASK_LO, d);
        chk8("2b IRQ_MASK <= 0x07", d, 8'h07);
        bus_wr(A_MASK_LO, 8'hFF);
        bus_rd(A_MASK_LO, d);
        chk8("2c IRQ_MASK <= 0xFF", d, 8'hFF);

        //=============================================================
        // [4] マスク動作: マスクされた源は STAT に立たない
        //     emu23 L315-316: allowed = bits & ~irq_mask; if(0) return;
        //=============================================================
        $display("--- [4] mask blocks source ---");
        bus_wr(A_MASK_LO, 8'h07);          // 全マスク
        pulse_src(1'b1, 1'b1, 1'b1);       // 3源同時パルス
        bus_rd(A_STAT_LO, d);
        chk8("4a all masked -> STAT stays 0x00", d, 8'h00);
        chk1("4b all masked -> irq1 = 0", irq1_o, 1'b0);

        // 部分マスク: RX のみ許可（mask=0x06 → bit1,2 マスク）
        bus_wr(A_MASK_LO, 8'h06);
        pulse_src(1'b1, 1'b1, 1'b1);       // 3源同時
        bus_rd(A_STAT_LO, d);
        chk8("4c mask=0x06 -> only RX latched", d, B_UART_RX);
        chk1("4d irq1 asserted", irq1_o, 1'b1);

        // クリアして次へ
        bus_wr(A_STAT_LO, 8'hFF);
        bus_rd(A_STAT_LO, d);
        chk8("4e cleared", d, 8'h00);

        //=============================================================
        // [5] 集約: 複数源同時 → IRQ1 が1本
        //=============================================================
        $display("--- [5] aggregation ---");
        bus_wr(A_MASK_LO, 8'h00);          // 全許可
        pulse_src(1'b1, 1'b1, 1'b1);
        bus_rd(A_STAT_LO, d);
        chk8("5a 3 sources -> STAT = 0x07", d, 8'h07);
        chk1("5b single irq1 line asserted", irq1_o, 1'b1);

        //=============================================================
        // [6] レベル保持 ★KY-D★
        //     STAT != 0 の間、irq1 はアサートされ続ける（パルスでない）
        //=============================================================
        $display("--- [6] level hold (KY-D) ---");
        for (i = 0; i < 10; i++) begin
            @(negedge clk);
            if (irq1_o !== 1'b1) begin
                fail_cnt++;
                $display("FAIL: 6 irq1 dropped at cycle %0d (must be LEVEL)", i);
            end
        end
        pass_cnt++;
        $display("PASS: %-42s held 10 cycles", "6 irq1 stays asserted (level)");

        //=============================================================
        // [3] Write-to-Clear   emu23 L761: irq_stat &= ~v
        //     1を書いたビットのみクリア。0を書いたビットは不変。
        //=============================================================
        $display("--- [3] Write-to-Clear ---");
        // 現在 STAT = 0x07
        bus_wr(A_STAT_LO, B_STOR);         // bit1 のみクリア
        bus_rd(A_STAT_LO, d);
        chk8("3a W2C: write 0x02 -> STAT = 0x05", d, 8'h05);
        chk1("3b irq1 still asserted (STAT!=0)", irq1_o, 1'b1);

        bus_wr(A_STAT_LO, 8'h00);          // 0書込 → 何も消えない
        bus_rd(A_STAT_LO, d);
        chk8("3c W2C: write 0x00 -> STAT unchanged", d, 8'h05);

        //=============================================================
        // [7] クリア後の irq1 デアサート
        //=============================================================
        $display("--- [7] deassert after full clear ---");
        bus_wr(A_STAT_LO, 8'hFF);          // 全クリア
        bus_rd(A_STAT_LO, d);
        chk8("7a STAT = 0x00", d, 8'h00);
        chk1("7b irq1 deasserted", irq1_o, 1'b0);

        //=============================================================
        // 総括
        //=============================================================
        $display("=====================================================");
        $display("RESULT: PASS=%0d  FAIL=%0d", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display("*** ALL PASS ***");
        else
            $display("*** %0d FAIL ***", fail_cnt);
        $display("=====================================================");
        $finish;
    end

endmodule
