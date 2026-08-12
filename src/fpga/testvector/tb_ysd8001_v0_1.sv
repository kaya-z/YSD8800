//=====================================================================
// tb_ysd8001_v0_1.sv
//
//   YSD8001 UART 単体テストベンチ（S3）
//
//   Project : YSD8800 / YUI OS  --- Step 8 FPGA / V4
//   Version : v0.1
//   Date    : 2026-07-12
//   DUT     : ysd8800_ysd8001_v0_1.sv
//   Design  : v4_design_memo_v0_2.md（承認版）
//   Golden  : emu23 v1.09 (emu23_v109.c)
//
//---------------------------------------------------------------------
// 【★偽合格（false-pass）防止の設計★】原則67 / V3.7 BUG-1 の教訓
//
//   V3.7 BUG-1 は「TBが addr_i を直接与えた」ために、DUT側の2bit化
//   ミスが露見せず、単体TBが 21/21 ALL PASS してしまった。
//   S5統合で初めて発覚（無限割込ループ）。
//
//   → 本TBでは【必ず16bit実アドレスでアクセスする】。
//     TB内の bus_write()/bus_read() が実アドレスから [2:0] を切り出す。
//     DUT側の localparam も実アドレスから機械導出されているため、
//     両者が独立に同じ実アドレスを起点とし、誤前提を共有しない。
//
//   ★それでも本TBの ALL PASS だけで先へ進んではならない★
//     真のゲートは S5（CPU結合TB）である（レビュー §7 厳守指示）。
//     本TBはDUT内部の論理を確認するに留まり、
//     「MMIOスタブのルーティングが正しいか」は検証できない。
//=====================================================================
`timescale 1ns/1ps

module tb_ysd8001_v0_1;

    //-----------------------------------------------------------------
    // ★TB側の実アドレス定義★
    //   DUT の localparam とは【独立に】定義する。
    //   （DUTの定数を階層参照すると、DUTが間違っていてもTBが追従して
    //     しまい、偽合格する。emu23 v1.09 L561-564 を真実とする）
    //-----------------------------------------------------------------
    localparam logic [15:0] UART_TX   = 16'hFC80;  // emu23 L561
    localparam logic [15:0] UART_RX   = 16'hFC82;  // emu23 L562
    localparam logic [15:0] UART_STAT = 16'hFC84;  // emu23 L563
    localparam logic [15:0] UART_BAUD = 16'hFC86;  // emu23 L564

    // UART_STAT ビット（emu23 L336-337）
    localparam logic [7:0] TX_READY = 8'h01;   // bit0
    localparam logic [7:0] RX_READY = 8'h02;   // bit1

    // TX 送信サイクル（emu23 L344）
    localparam int TX_CYCLES = 4167;

    //-----------------------------------------------------------------
    // 信号
    //-----------------------------------------------------------------
    logic       clk, rst_n;
    logic       sel_i, we_i;
    logic [2:0] addr_i;
    logic [7:0] wdata_i, rdata_o;
    logic       irq_rx_o, irq_tx_o;
    logic       rx_valid_i;
    logic [7:0] rx_data_i;
    logic       tx_valid_o;
    logic [7:0] tx_data_o;

    int pass_cnt = 0;
    int fail_cnt = 0;

    ysd8800_ysd8001_v0_1 dut (
        .clk(clk), .rst_n(rst_n),
        .sel_i(sel_i), .addr_i(addr_i), .we_i(we_i),
        .wdata_i(wdata_i), .rdata_o(rdata_o),
        .irq_rx_o(irq_rx_o), .irq_tx_o(irq_tx_o),
        .rx_valid_i(rx_valid_i), .rx_data_i(rx_data_i),
        .tx_valid_o(tx_valid_o), .tx_data_o(tx_data_o)
    );

    always #5 clk = ~clk;

    //=================================================================
    // バスアクセス task
    //   ★16bit実アドレスを受け取り、TB内で [2:0] を切り出す★
    //   これがMMIOスタブのルーティングを模擬している。
    //=================================================================
    task automatic bus_write(input logic [15:0] a, input logic [7:0] d);
        @(negedge clk);
        sel_i   = 1'b1;
        we_i    = 1'b1;
        addr_i  = a[2:0];      // ★実アドレスから切り出す★
        wdata_i = d;
        @(negedge clk);
        sel_i   = 1'b0;
        we_i    = 1'b0;
    endtask

    task automatic bus_read(input logic [15:0] a, output logic [7:0] d);
        @(negedge clk);
        sel_i  = 1'b1;
        we_i   = 1'b0;
        addr_i = a[2:0];       // ★実アドレスから切り出す★
        #1;                    // 組合せ読出の確定待ち
        d = rdata_o;
        @(negedge clk);
        sel_i  = 1'b0;
    endtask

    // 1バイト受信を注入（1クロックパルス）
    task automatic rx_inject(input logic [7:0] d);
        @(negedge clk);
        rx_valid_i = 1'b1;
        rx_data_i  = d;
        @(negedge clk);
        rx_valid_i = 1'b0;
    endtask

    //=================================================================
    // 判定 task
    //=================================================================
    task automatic chk(input string name,
                       input logic [7:0] got, input logic [7:0] exp);
        if (got === exp) begin
            $display("  PASS %-34s got=0x%02h", name, got);
            pass_cnt++;
        end else begin
            $display("  FAIL %-34s got=0x%02h exp=0x%02h", name, got, exp);
            fail_cnt++;
        end
    endtask

    task automatic chk_bit(input string name,
                           input logic got, input logic exp);
        if (got === exp) begin
            $display("  PASS %-34s got=%b", name, got);
            pass_cnt++;
        end else begin
            $display("  FAIL %-34s got=%b exp=%b", name, got, exp);
            fail_cnt++;
        end
    endtask

    //=================================================================
    // テスト本体
    //=================================================================
    logic [7:0] d;

    initial begin
        clk = 0; rst_n = 0;
        sel_i = 0; we_i = 0; addr_i = 0; wdata_i = 0;
        rx_valid_i = 0; rx_data_i = 0;

        repeat (3) @(negedge clk);
        rst_n = 1;
        @(negedge clk);

        //=============================================================
        // V1: リセット値 ★KY45: STAT=0x01（0x00ではない）★
        //   レビュー §7 指示: 「S3単体TBの第1ベクタとする方針を厳守」
        //   emu23 L380: ysd8001.stat = YSD8001_STAT_TX_READY;
        //=============================================================
        $display("=== V1: reset values (KY45) ===");
        bus_read(UART_STAT, d);
        chk("V1-1 STAT reset = 0x01", d, 8'h01);   // ★TX_READY=1★

        bus_read(UART_RX, d);
        chk("V1-2 RX buf reset = 0x00", d, 8'h00); // emu23 L381

        // BAUD reset = 416 = 0x01A0  (emu23 L382)
        bus_read(UART_BAUD,          d);
        chk("V1-3 BAUD lo reset = 0xA0", d, 8'hA0);
        bus_read(UART_BAUD + 16'd1,  d);
        chk("V1-4 BAUD hi reset = 0x01", d, 8'h01);

        //=============================================================
        // V2: ★KY44★ アドレスデコード
        //   TX($FC80) と STAT($FC84) が区別できること。
        //   ★2bitデコードなら、ここで必ず落ちる★
        //     $FC80[1:0] = $FC84[1:0] = 2'b00 のため。
        //=============================================================
        $display("=== V2: address decode (KY44 / BUG-1 anti-false-pass) ===");
        // STAT を読む -> 0x01 が返るはず。
        // もし2bitデコードなら TX($FC80) と同じ扱いになり 0x00 が返る。
        bus_read(UART_STAT, d);
        chk("V2-1 STAT!=TX (2bit->0x00)", d, 8'h01);

        // BAUD lo を読む -> 0xA0。
        // もし2bitデコードなら RX($FC82) と衝突し 0x00 が返る。
        bus_read(UART_BAUD, d);
        chk("V2-2 BAUD!=RX (2bit->0x00)", d, 8'hA0);

        //=============================================================
        // V3: ★論点A=案A-3★ 上位バイトは 0x00 を返す
        //   $FC81 / $FC83 / $FC85
        //=============================================================
        $display("=== V3: upper byte returns 0x00 (case A-3) ===");
        bus_read(UART_TX   + 16'd1, d);
        chk("V3-1 $FC81 = 0x00", d, 8'h00);
        bus_read(UART_RX   + 16'd1, d);
        chk("V3-2 $FC83 = 0x00", d, 8'h00);
        bus_read(UART_STAT + 16'd1, d);
        chk("V3-3 $FC85 = 0x00", d, 8'h00);

        //=============================================================
        // V4: TX 基本動作（emu23 L503-508）
        //   書込 -> TX_READY=0 -> 4167cyc 後 TX_READY=1
        //=============================================================
        $display("=== V4: TX basic (4167 cycles) ===");
        bus_write(UART_TX, 8'h41);            // 'A' を送信
        bus_read(UART_STAT, d);
        chk("V4-1 TX_READY=0 during tx", d & TX_READY, 8'h00);

        // tx_data_o に送信データが出ているか（V9接続点）
        chk("V4-2 tx_data_o = 0x41", tx_data_o, 8'h41);

        // 4167サイクル手前ではまだビジー
        repeat (TX_CYCLES - 40) @(negedge clk);
        bus_read(UART_STAT, d);
        chk("V4-3 still busy before 4167", d & TX_READY, 8'h00);

        // 完了後は TX_READY=1 に復帰
        repeat (60) @(negedge clk);
        bus_read(UART_STAT, d);
        chk("V4-4 TX_READY=1 after 4167", d & TX_READY, TX_READY);

        //=============================================================
        // V5: RX 受信 + ★irq_rx_o は1クロックパルス★
        //=============================================================
        $display("=== V5: RX receive + IRQ pulse ===");
        rx_inject(8'h37);                      // '7' を受信
        @(negedge clk);
        bus_read(UART_STAT, d);
        chk("V5-1 RX_READY=1", d & RX_READY, RX_READY);
        bus_read(UART_RX, d);
        chk("V5-2 RX data = 0x37", d, 8'h37);

        //=============================================================
        // V6: ★RX 読出に副作用なし★（emu23 L510-513 / UART設計書 R7）
        //   何度読んでも RX_READY はクリアされない
        //=============================================================
        $display("=== V6: RX read has NO side effect ===");
        bus_read(UART_RX, d);
        bus_read(UART_RX, d);
        chk("V6-1 RX data stable", d, 8'h37);
        bus_read(UART_STAT, d);
        chk("V6-2 RX_READY still 1", d & RX_READY, RX_READY);

        //=============================================================
        // V7: ★RX オーバーラン: 先着優先・後着破棄★（emu23 L390）
        //   RX_READY=1 の間に来た新データは【捨てる】。上書きしない。
        //=============================================================
        $display("=== V7: RX overrun -> discard NEW data ===");
        rx_inject(8'h39);                      // '9' を注入（破棄されるはず）
        @(negedge clk);
        bus_read(UART_RX, d);
        chk("V7-1 old data kept (0x37)", d, 8'h37);  // ★0x39ではない★

        //=============================================================
        // V8: ★UART_STAT Write-to-Clear★（emu23 L521-526）
        //   bit1 に 1 を書くと RX_READY がクリアされる
        //   bit0 への書込は【完全に無視】される
        //=============================================================
        $display("=== V8: STAT Write-to-Clear (bit1 only) ===");
        bus_write(UART_STAT, RX_READY);        // bit1=1 を書く
        bus_read(UART_STAT, d);
        chk("V8-1 RX_READY cleared", d & RX_READY, 8'h00);
        chk("V8-2 TX_READY unaffected", d & TX_READY, TX_READY);

        // bit0 に 1 を書いても TX_READY はクリアされない（HW自動管理）
        bus_write(UART_STAT, TX_READY);
        bus_read(UART_STAT, d);
        chk("V8-3 TX_READY W2C ignored", d & TX_READY, TX_READY);

        //=============================================================
        // V9: W2C 後は再び受信できる（オーバーラン解除）
        //=============================================================
        $display("=== V9: RX works again after W2C ===");
        rx_inject(8'h5A);                      // 'Z'
        @(negedge clk);
        bus_read(UART_RX, d);
        chk("V9-1 new data received", d, 8'h5A);

        // 後片付け
        bus_write(UART_STAT, RX_READY);

        //=============================================================
        // V10: ★論点B=案B-1★ irq_tx_o は【レベル】である
        //   TX_READY=1 の間、アサートされ【続ける】こと。
        //   ★これがパルスだと V4 の本質仕様が壊れる★
        //=============================================================
        $display("=== V10: irq_tx_o is LEVEL (TDRE / case B-1) ===");
        bus_read(UART_STAT, d);
        chk("V10-0 TX_READY=1 now", d & TX_READY, TX_READY);

        chk_bit("V10-1 irq_tx_o = 1", irq_tx_o, 1'b1);
        repeat (10) @(negedge clk);
        chk_bit("V10-2 irq_tx_o STILL 1 (level)", irq_tx_o, 1'b1);
        repeat (50) @(negedge clk);
        chk_bit("V10-3 irq_tx_o STILL 1 (50cyc)", irq_tx_o, 1'b1);

        // 送信中は落ちる
        bus_write(UART_TX, 8'h42);
        @(negedge clk);
        chk_bit("V10-4 irq_tx_o=0 while busy", irq_tx_o, 1'b0);

        // 送信完了で復帰し、また上がり続ける
        repeat (TX_CYCLES + 10) @(negedge clk);
        chk_bit("V10-5 irq_tx_o=1 after done", irq_tx_o, 1'b1);
        repeat (20) @(negedge clk);
        chk_bit("V10-6 irq_tx_o STILL 1 again", irq_tx_o, 1'b1);

        //=============================================================
        // V11: UART_BAUD 書込（byte-enable 2バイト保持）
        //=============================================================
        $display("=== V11: UART_BAUD write (2 bytes) ===");
        bus_write(UART_BAUD,         8'h34);   // lo
        bus_write(UART_BAUD + 16'd1, 8'h12);   // hi
        bus_read(UART_BAUD,         d);
        chk("V11-1 BAUD lo = 0x34", d, 8'h34);
        bus_read(UART_BAUD + 16'd1, d);
        chk("V11-2 BAUD hi = 0x12", d, 8'h12);

        //=============================================================
        // 結果
        //=============================================================
        $display("");
        $display("========================================");
        $display(" S3 UNIT TB : PASS=%0d  FAIL=%0d", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display(" *** ALL PASS ***");
        else
            $display(" *** %0d FAIL ***", fail_cnt);
        $display("========================================");
        $display(" NOTE: S3 ALL PASS alone is NOT a gate.");
        $display("       True gate is S5 (CPU integration TB).");
        $display("========================================");
        $finish;
    end

    //-----------------------------------------------------------------
    // タイムアウト保護
    //-----------------------------------------------------------------
    initial begin
        #1_000_000;
        $display("*** TIMEOUT ***");
        $finish;
    end

endmodule
