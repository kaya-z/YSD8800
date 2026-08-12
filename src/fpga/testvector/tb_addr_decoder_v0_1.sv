// ============================================================
//  tb_addr_decoder_v0_1.sv   v0.1  (2026-07-11)
//  YSD8800 FPGA V3 : アドレスデコーダ+MMIOスタブ 単体TB
//
//  検証観点(v3_design_memo_v0_2.md §4.2/§5):
//   - $FC7F(RAM側)/$FC80(MMIO側)の境界1バイト差で振り分けを確認
//   - MMIOアクセスがdbg_last_addr/dbg_access_countに反映されるか
//   - MMIOリードが固定値0x00を返すか、ライトが無視されるか
//   - RAM側はダミー理想メモリ(本TB限定・CDC/PSRAMはV3次段)
// ============================================================
`timescale 1ns/1ps

module tb_addr_decoder_v0_1;
    logic        clk, rst_n;

    logic [15:0] cpu_mem_addr;
    logic [7:0]  cpu_mem_wdata, cpu_mem_rdata;
    logic        cpu_mem_rd, cpu_mem_wr, cpu_mem_ready;

    logic [15:0] ram_addr;
    logic [7:0]  ram_wdata, ram_rdata;
    logic        ram_rd, ram_wr, ram_ready;

    logic [15:0] mmio_addr;
    logic [7:0]  mmio_wdata, mmio_rdata;
    logic        mmio_rd, mmio_wr, mmio_ready;
    logic [15:0] dbg_last_addr;
    logic [31:0] dbg_access_count;

    integer errors = 0;

    ysd8800_addr_decoder_v0_1 dut_dec (
        .cpu_mem_addr(cpu_mem_addr), .cpu_mem_wdata(cpu_mem_wdata),
        .cpu_mem_rdata(cpu_mem_rdata), .cpu_mem_rd(cpu_mem_rd),
        .cpu_mem_wr(cpu_mem_wr), .cpu_mem_ready(cpu_mem_ready),
        .ram_addr(ram_addr), .ram_wdata(ram_wdata), .ram_rdata(ram_rdata),
        .ram_rd(ram_rd), .ram_wr(ram_wr), .ram_ready(ram_ready),
        .mmio_addr(mmio_addr), .mmio_wdata(mmio_wdata), .mmio_rdata(mmio_rdata),
        .mmio_rd(mmio_rd), .mmio_wr(mmio_wr), .mmio_ready(mmio_ready)
    );

    ysd8800_mmio_stub_v0_1 dut_mmio (
        .clk(clk), .rst_n(rst_n),
        .mmio_addr(mmio_addr), .mmio_wdata(mmio_wdata), .mmio_rdata(mmio_rdata),
        .mmio_rd(mmio_rd), .mmio_wr(mmio_wr), .mmio_ready(mmio_ready),
        .dbg_last_addr(dbg_last_addr), .dbg_access_count(dbg_access_count)
    );

    // RAM側ダミー理想メモリ(本TB限定・次段でCDC+PSRAMに置換)
    logic [7:0] ram_model [0:65535];
    assign ram_ready = 1'b1;
    always_comb ram_rdata = ram_model[ram_addr];
    always_ff @(posedge clk) begin
        if (ram_wr) ram_model[ram_addr] <= ram_wdata;
    end

    initial clk = 0;
    always #5 clk = ~clk;

    task automatic do_read(input [15:0] addr, output [7:0] rdata);
        @(negedge clk);
        cpu_mem_addr = addr; cpu_mem_rd = 1'b1; cpu_mem_wr = 1'b0;
        @(negedge clk);
        while (!cpu_mem_ready) @(negedge clk);
        rdata = cpu_mem_rdata;
        cpu_mem_rd = 1'b0;
    endtask

    task automatic do_write(input [15:0] addr, input [7:0] wdata);
        @(negedge clk);
        cpu_mem_addr = addr; cpu_mem_wdata = wdata;
        cpu_mem_wr = 1'b1; cpu_mem_rd = 1'b0;
        @(negedge clk);
        while (!cpu_mem_ready) @(negedge clk);
        cpu_mem_wr = 1'b0;
    endtask

    logic [7:0] rd;

    initial begin
        rst_n = 0; cpu_mem_addr = 16'h0000; cpu_mem_wdata = 8'h00;
        cpu_mem_rd = 0; cpu_mem_wr = 0;
        ram_model[16'h0000] = 8'hAA;
        ram_model[16'hFC7F] = 8'h55;
        repeat (3) @(negedge clk);
        rst_n = 1;
        @(negedge clk);

        // T1: RAM領域先頭($0000)がRAM側へ振り分けられるか
        do_read(16'h0000, rd);
        if (rd !== 8'hAA) begin
            $display("[T1] FAIL: expected AA got %02h", rd); errors++;
        end else if (dbg_access_count !== 32'd0) begin
            $display("[T1] FAIL: MMIO access_count changed (%0d)", dbg_access_count); errors++;
        end else $display("[T1] PASS: $0000 -> RAM側 (rdata=%02h)", rd);

        // T2: RAM領域末尾($FC7F)がRAM側へ振り分けられるか(境界直下)
        do_read(16'hFC7F, rd);
        if (rd !== 8'h55) begin
            $display("[T2] FAIL: expected 55 got %02h", rd); errors++;
        end else if (dbg_access_count !== 32'd0) begin
            $display("[T2] FAIL: MMIO access_count changed (%0d)", dbg_access_count); errors++;
        end else $display("[T2] PASS: $FC7F -> RAM側 (rdata=%02h)", rd);

        // T3: MMIO領域先頭($FC80)がMMIO側へ振り分けられるか(境界直上)
        do_read(16'hFC80, rd);
        if (rd !== 8'h00) begin
            $display("[T3] FAIL: expected 00(stub) got %02h", rd); errors++;
        end else if (dbg_last_addr !== 16'hFC80 || dbg_access_count !== 32'd1) begin
            $display("[T3] FAIL: dbg_last_addr=%04h count=%0d (expected FC80/1)",
                      dbg_last_addr, dbg_access_count); errors++;
        end else $display("[T3] PASS: $FC80 -> MMIO側 (rdata=%02h, count=%0d)", rd, dbg_access_count);

        // T4: MMIO領域末尾($FFFF)がMMIO側へ振り分けられるか
        do_read(16'hFFFF, rd);
        if (rd !== 8'h00) begin
            $display("[T4] FAIL: expected 00(stub) got %02h", rd); errors++;
        end else if (dbg_last_addr !== 16'hFFFF || dbg_access_count !== 32'd2) begin
            $display("[T4] FAIL: dbg_last_addr=%04h count=%0d (expected FFFF/2)",
                      dbg_last_addr, dbg_access_count); errors++;
        end else $display("[T4] PASS: $FFFF -> MMIO側 (count=%0d)", dbg_access_count);

        // T5: MMIOライトが無視される(ram_modelに影響せず、readyのみ返る)
        do_write(16'hFC90, 8'hFF);
        if (dbg_access_count !== 32'd3) begin
            $display("[T5] FAIL: write not counted (count=%0d)", dbg_access_count); errors++;
        end else $display("[T5] PASS: MMIOライト無視・カウンタのみ増加 (count=%0d)", dbg_access_count);

        // T6: RAMライトがRAM側に届く(ram_modelへの書込を確認)
        do_write(16'h1234, 8'h7E);
        if (ram_model[16'h1234] !== 8'h7E) begin
            $display("[T6] FAIL: ram_model[1234]=%02h expected 7E", ram_model[16'h1234]); errors++;
        end else if (dbg_access_count !== 32'd3) begin
            $display("[T6] FAIL: MMIO access_count changed on RAM write (%0d)", dbg_access_count); errors++;
        end else $display("[T6] PASS: RAMライト到達・MMIOカウンタ不変 (count=%0d)", dbg_access_count);

        if (errors == 0) $display("ALL PASS (6/6)");
        else $display("FAIL: %0d error(s)", errors);
        $finish;
    end
endmodule
