//==============================================================
// tb_ysd8003_v0_1.sv
//   YSD8003 ストレージコントローラ v0.2 テストベンチ
//   DUT: ysd8800_ysd8003_v0_1 (ファイル ysd8800_ysd8003_v0_2.sv)
//   SDモデル: sd_spi_model_v0_1_poc
//   Version: v0.1 (2026-07-19)
//
// 【検証方針（設計メモ§検証・案D）】
//   判定軸 = OSが観測する外部契約（レジスタ遷移）。cycle等価は放棄。
//   emu23一致は使わない（隠蔽層をRTLで起こしたため）。
//
// 【KY54: negative先行】
//   T5(neg): トークン不達/不正 → ERROR(bit1)確定・ready返却
//   T6(neg): SPIタイムアウト → ERROR確定・ready返却（★ハングしない★）
//   T1: 初期化シーケンス完走（CMD0/8/55/41順）
//   T2: CMD17 → 512B 既知パターン(lba*512+i)一致
//   T3: STAT BUSY→READY遷移・SD_DATA 512回読出一致
//   T4: 完了IRQ(IRQ1)レベル立ち・ackで落ち
//==============================================================
`timescale 1ns/1ps

module tb_ysd8003_v0_1;

    //----------------------------------------------------------
    // クロック・リセット
    //----------------------------------------------------------
    logic clk;
    logic rst_n;

    initial clk = 1'b0;
    always #5 clk = ~clk;   // 100MHz（TB用・論理検証のみ）

    //----------------------------------------------------------
    // DUT I/F
    //----------------------------------------------------------
    logic        sel_i;
    logic [4:0]  addr_i;
    logic        we_i;
    logic [7:0]  wdata_i;
    logic [7:0]  rdata_o;
    logic        ready_o;
    logic        irq_stor_o;
    logic        irq_stor_ack;
    logic        spi_cs_n;
    logic        spi_sck;
    logic        spi_mosi;
    logic        spi_miso;
    logic [31:0] disk_sectors_i;

    // T6用: SDモデルのMISOを殺す（応答なし）スイッチ
    logic        kill_miso;
    logic        model_miso;
    assign spi_miso = kill_miso ? 1'b1 : model_miso;  // kill時は常時FF（応答なし）

    //----------------------------------------------------------
    // MMIOアドレス定数（DUTと一致）
    //----------------------------------------------------------
    localparam [4:0] A_CMD_L    = 5'h00;
    localparam [4:0] A_STAT_L   = 5'h02;
    localparam [4:0] A_LBA_LO_L = 5'h04;
    localparam [4:0] A_LBA_HI_L = 5'h06;
    localparam [4:0] A_BUFP_L   = 5'h08;
    localparam [4:0] A_DATA_L   = 5'h0A;
    localparam [4:0] A_IRQC_L   = 5'h0C;

    //----------------------------------------------------------
    // DUT インスタンス
    //----------------------------------------------------------
    ysd8800_ysd8003_v0_1 dut (
        .clk(clk), .rst_n(rst_n),
        .sel_i(sel_i), .addr_i(addr_i), .we_i(we_i),
        .wdata_i(wdata_i), .rdata_o(rdata_o), .ready_o(ready_o),
        .irq_stor_o(irq_stor_o), .irq_stor_ack(irq_stor_ack),
        .spi_cs_n(spi_cs_n), .spi_sck(spi_sck),
        .spi_mosi(spi_mosi), .spi_miso(spi_miso),
        .disk_sectors_i(disk_sectors_i)
    );

    //----------------------------------------------------------
    // SDモデル インスタンス
    //----------------------------------------------------------
    sd_spi_model_v0_1_poc sdmodel (
        .cs_n(spi_cs_n), .sck(spi_sck),
        .mosi(spi_mosi), .miso(model_miso)
    );

    //----------------------------------------------------------
    // 試験統計
    //----------------------------------------------------------
    integer pass_cnt = 0;
    integer fail_cnt = 0;

    task check(input string name, input logic cond);
        begin
            if (cond) begin
                pass_cnt = pass_cnt + 1;
                $display("[PASS] %s", name);
            end else begin
                fail_cnt = fail_cnt + 1;
                $display("[FAIL] %s", name);
            end
        end
    endtask

    //----------------------------------------------------------
    // MMIO書込タスク（1クロックパルス）
    //----------------------------------------------------------
    task mmio_write(input [4:0] a, input [7:0] d);
        begin
            @(posedge clk);
            sel_i   <= 1'b1;
            we_i    <= 1'b1;
            addr_i  <= a;
            wdata_i <= d;
            @(posedge clk);
            sel_i   <= 1'b0;
            we_i    <= 1'b0;
        end
    endtask

    //----------------------------------------------------------
    // MMIO読出タスク（ready_o待ち合わせ付き＝案D wait-state対応）
    //   STAT読みはSPI進行中 ready_o=0 でストールしうる。
    //   ready_o=1 のサイクルでrdata_oを確定。
    //----------------------------------------------------------
    task mmio_read(input [4:0] a, output [7:0] d);
        begin
            @(posedge clk);
            sel_i  <= 1'b1;
            we_i   <= 1'b0;
            addr_i <= a;
            // ready_o=1 になるまで待つ（wait-state吸収）
            @(posedge clk);
            while (ready_o !== 1'b1) @(posedge clk);
            d = rdata_o;
            sel_i <= 1'b0;
        end
    endtask

    //----------------------------------------------------------
    // 初期化完了待ち（fsm S_IDLE到達を階層参照で監視）
    //   OS相当: 初期化はリセット後自動進行。ここでは完了を待つ。
    //----------------------------------------------------------
    task wait_init_done(input integer max_cyc);
        integer i;
        begin
            i = 0;
            // dut.fsm がS_IDLE(=7)へ来るまで待つ（初期化自動完走）
            while (dut.fsm !== dut.S_IDLE && i < max_cyc) begin
                @(posedge clk); i = i + 1;
            end
        end
    endtask

    //----------------------------------------------------------
    // メインシーケンス
    //----------------------------------------------------------
    logic [7:0] rd;
    integer     k;
    integer     mism;

    initial begin
        // 初期値
        sel_i=0; we_i=0; addr_i=0; wdata_i=0;
        irq_stor_ack=0; kill_miso=0;
        disk_sectors_i = 32'd131072; // 64MB相当

        rst_n = 1'b0;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;

        //======================================================
        // T1: 初期化シーケンス完走（negative群の前に土台確認）
        //   ※本来KY54でnegを先にやるが、初期化完走は全testの
        //     前提土台のため最初に土台成立のみ確認する。
        //     真のnegative(T5/T6)はEXEC系で先行実施する。
        //======================================================
        wait_init_done(100000);
        check("T1: init sequence reaches S_IDLE", dut.fsm === dut.S_IDLE);

        //======================================================
        // T6(negative先行): SPIタイムアウト → ERROR → ready返却
        //   kill_misoでSDモデル応答を殺し、EXEC投入。
        //   ready_oが永久0にならず、STAT=ERRORでreadyが返ることを確認。
        //======================================================
        kill_miso = 1'b1;              // 応答を殺す
        mmio_write(A_LBA_LO_L, 8'h00);
        mmio_write(A_LBA_HI_L, 8'h00);
        mmio_write(A_CMD_L, 8'd0);     // READ_SETUP
        mmio_write(A_CMD_L, 8'd2);     // EXEC

        // タイムアウトまで待つ（SPI_TIMEOUT=2e6。TB短縮のため階層で監視）
        // ready_oが最終的に1で返り、STATにERROR(bit1)が立つこと。
        begin
            integer t; t=0;
            // fsmがS_IDLEへ戻る（S_ERROR処理後）まで、上限付きで待つ
            while (dut.fsm !== dut.S_IDLE && t < 5000000) begin
                @(posedge clk); t=t+1;
            end
            check("T6: timeout returns to S_IDLE (no hang)",
                  dut.fsm === dut.S_IDLE);
        end
        mmio_read(A_STAT_L, rd);
        check("T6: STAT ERROR bit set after timeout", rd[1] === 1'b1);
        check("T6: ready_o eventually high (no hang)", ready_o === 1'b1);
        kill_miso = 1'b0;

        // ERROR状態リセットのためDUTリセット
        rst_n = 1'b0; repeat (5) @(posedge clk); rst_n = 1'b1;
        wait_init_done(100000);

        //======================================================
        // T2/T3: CMD17読出 → 512B既知パターン一致・STAT遷移
        //======================================================
        // LBA=1 を読む（既知パターン = (1*512+i)&0xFF）
        mmio_write(A_LBA_LO_L, 8'h01);
        mmio_write(A_LBA_HI_L, 8'h00);
        // 完了IRQ有効化（T4用）
        mmio_write(A_IRQC_L, 8'h01);
        mmio_write(A_CMD_L, 8'd0);     // READ_SETUP
        mmio_write(A_CMD_L, 8'd2);     // EXEC

        // STAT読みでBUSY→READY遷移を待つ（案D: readyストール吸収）
        rd = 8'h00;
        begin
            integer t; t=0;
            while (!(rd[2]) && t < 5000000) begin
                mmio_read(A_STAT_L, rd);
                t=t+1;
            end
            check("T3: STAT READY after CMD17", rd[2] === 1'b1);
            check("T3: STAT ERROR clear on success", rd[1] === 1'b0);
        end

        // T4: 完了IRQレベル確認
        check("T4: IRQ level high on completion", irq_stor_o === 1'b1);
        // ack → IRQ落ち
        @(posedge clk); irq_stor_ack <= 1'b1;
        @(posedge clk); irq_stor_ack <= 1'b0;
        repeat (2) @(posedge clk);
        check("T4: IRQ drops after ack", irq_stor_o === 1'b0);

        // T2: 512B既知パターン一致（SD_DATAを512回読出）
        mism = 0;
        for (k = 0; k < 512; k = k + 1) begin
            mmio_read(A_DATA_L, rd);
            if (rd !== ((1*512 + k) & 8'hFF)) mism = mism + 1;
        end
        check("T2: 512B data matches (lba*512+i)", mism === 0);
        if (mism != 0) $display("   -> mismatch count = %0d", mism);

        //======================================================
        // T5(negative): トークン不正 → ERROR
        //   SDモデルは正常トークンを返すため、ここでは
        //   「不正LBA(disk範囲外)」でモデルがillegal応答する経路や
        //   token不達をkill_misoで再現する簡易版とする。
        //   本v0.1では T6 のタイムアウト経路がERROR確定を代表検証。
        //   （SDモデルがトークン不正を注入できないため、T5は
        //     モデル拡張後に本格化。ここでは記録のみ）
        //======================================================
        $display("[INFO] T5: token-error injection requires SD model ext (deferred to model v0.2)");

        //======================================================
        // 結果集計
        //======================================================
        $display("========================================");
        $display("RESULT: PASS=%0d FAIL=%0d", pass_cnt, fail_cnt);
        if (fail_cnt == 0) $display("ALL PASS");
        else               $display("SOME FAILED");
        $display("========================================");
        $finish;
    end

    //----------------------------------------------------------
    // ウォッチドッグ（TB自体のハング防止）
    //----------------------------------------------------------
    initial begin
        #200000000;  // 200ms相当で強制終了
        $display("[TB-WATCHDOG] simulation timeout - forced finish");
        $display("RESULT: PASS=%0d FAIL=%0d (WATCHDOG)", pass_cnt, fail_cnt);
        $finish;
    end

endmodule
