// ============================================================
//  tb_mmio_mmureg_v0_1.sv   v0.1  (2026-07-11)
//  YSD8800 FPGA V3.5 : MMIOスタブ v0.2 (MMUレジスタ) 単体TB
//
//  対象: ysd8800_mmio_stub_v0_2.sv (v0.2)
//  設計根拠: v3_5_design_memo_v0_2.md §5.1
//
//  検証項目:
//    T1. リセット後の値: PTR[n]=n (恒等写像) / MCR=0x00
//        → ptr_o / mmu_en_o 出力も一致すること
//    T2. PTR[0..15] の R/W (全16本)
//    T3. MCR の R/W と mmu_en_o (bit0) の追従
//    T4. ★MCR.EN=0 でも PTR/MCR に書ける★ (Q1・鶏と卵の回避)
//    T5. ★MCR.EN=1 でも PTR/MCR に書ける★ (自己ロックアウト回避)
//    T6. 非MMU領域($FC80台/予約$FF11-$FF1F)は従来スタブ挙動(固定0x00)
//    T7. ライト無視の確認(非MMU領域に書いても内部状態が変わらない)
//    T8. mmio_ready が即時アサートされる(V3挙動不変)
// ============================================================
`timescale 1ns/1ps

module tb_mmio_mmureg_v0_1;

    logic        clk = 0;
    logic        rst_n;
    logic [15:0] mmio_addr;
    logic [7:0]  mmio_wdata;
    logic [7:0]  mmio_rdata;
    logic        mmio_rd;
    logic        mmio_wr;
    logic        mmio_ready;
    logic [127:0] ptr_flat_o;
    logic        mmu_en_o;
    logic [15:0] dbg_last_addr;
    logic [31:0] dbg_access_count;

    // packed flat から PTR[n] を取り出すヘルパ
    function automatic logic [7:0] ptr_o(input int n);
        ptr_o = ptr_flat_o[8*n +: 8];
    endfunction

    always #5 clk = ~clk;   // 10ns周期

    ysd8800_mmio_stub_v0_2 dut (
        .clk(clk), .rst_n(rst_n),
        .mmio_addr(mmio_addr), .mmio_wdata(mmio_wdata), .mmio_rdata(mmio_rdata),
        .mmio_rd(mmio_rd), .mmio_wr(mmio_wr), .mmio_ready(mmio_ready),
        .ptr_flat_o(ptr_flat_o), .mmu_en_o(mmu_en_o),
        .dbg_last_addr(dbg_last_addr), .dbg_access_count(dbg_access_count)
    );

    int pass_cnt = 0;
    int fail_cnt = 0;

    task automatic ok(input string name);
        begin pass_cnt++; end
    endtask

    task automatic ng(input string name, input logic [31:0] exp, input logic [31:0] got);
        begin
            fail_cnt++;
            $display("FAIL: %s  exp=%02h got=%02h", name, exp[7:0], got[7:0]);
        end
    endtask

    task automatic chk8(input string name, input logic [7:0] exp, input logic [7:0] got);
        begin
            if (exp === got) ok(name);
            else             ng(name, {24'b0, exp}, {24'b0, got});
        end
    endtask

    // MMIOライト(1サイクル)
    task automatic mmio_write(input logic [15:0] a, input logic [7:0] d);
        begin
            @(negedge clk);
            mmio_addr  = a;
            mmio_wdata = d;
            mmio_wr    = 1'b1;
            mmio_rd    = 1'b0;
            @(posedge clk);       // ここでレジスタに取り込まれる
            @(negedge clk);
            mmio_wr    = 1'b0;
        end
    endtask

    // MMIOリード(組合せ読み出し)
    task automatic mmio_read(input logic [15:0] a, output logic [7:0] d);
        begin
            @(negedge clk);
            mmio_addr = a;
            mmio_rd   = 1'b1;
            mmio_wr   = 1'b0;
            #1;
            d = mmio_rdata;
            if (mmio_ready !== 1'b1) begin
                fail_cnt++;
                $display("FAIL: T8_ready  addr=%04h  mmio_ready not asserted", a);
            end
            @(negedge clk);
            mmio_rd   = 1'b0;
        end
    endtask

    logic [7:0] rd;

    initial begin
        $display("=== tb_mmio_mmureg_v0_1 : MMIO stub v0.2 (MMU regs) TB ===");
        mmio_addr  = 16'h0000;
        mmio_wdata = 8'h00;
        mmio_rd    = 1'b0;
        mmio_wr    = 1'b0;
        rst_n      = 1'b0;
        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        //--------------------------------------------------------
        // T1. リセット後: PTR[n]=n (恒等写像) / MCR=0x00
        //--------------------------------------------------------
        for (int i = 0; i < 16; i++) begin
            // レジスタ出力(MMUへの供給線)を直接確認
            chk8($sformatf("T1_ptr_o[%0d]", i), i[7:0], ptr_o(i));
            // MMIOリード経由でも確認
            mmio_read(16'hFF00 + i[15:0], rd);
            chk8($sformatf("T1_rd_PTR[%0d]", i), i[7:0], rd);
        end
        mmio_read(16'hFF10, rd);
        chk8("T1_rd_MCR", 8'h00, rd);
        chk8("T1_mmu_en_o", 8'h00, {7'b0, mmu_en_o});

        //--------------------------------------------------------
        // T4. ★MCR.EN=0 でも PTR に書ける★ (鶏と卵の回避)
        //     ついでに T2 (PTR全16本 R/W) を兼ねる
        //--------------------------------------------------------
        for (int i = 0; i < 16; i++) begin
            logic [7:0] v;
            v = 8'hB0 + i[7:0];
            mmio_write(16'hFF00 + i[15:0], v);
            mmio_read (16'hFF00 + i[15:0], rd);
            chk8($sformatf("T2_T4_PTR[%0d]_rw", i), v, rd);
            chk8($sformatf("T2_T4_ptr_o[%0d]", i), v, ptr_o(i));
        end
        // この時点でまだ MCR=0 (MMU無効) のはず
        chk8("T4_mcr_still_0", 8'h00, {7'b0, mmu_en_o});

        //--------------------------------------------------------
        // T3. MCR の R/W と mmu_en_o(bit0) の追従
        //--------------------------------------------------------
        mmio_write(16'hFF10, 8'h01);              // MMU有効化
        mmio_read (16'hFF10, rd);
        chk8("T3_MCR_wr01", 8'h01, rd);
        chk8("T3_mmu_en_1", 8'h01, {7'b0, mmu_en_o});

        mmio_write(16'hFF10, 8'h00);              // MMU無効化
        mmio_read (16'hFF10, rd);
        chk8("T3_MCR_wr00", 8'h00, rd);
        chk8("T3_mmu_en_0", 8'h00, {7'b0, mmu_en_o});

        // bit0以外を立てても mmu_en_o は0のまま(bit0のみ見る)
        mmio_write(16'hFF10, 8'h02);              // bit1(KRN_PROT・将来拡張)
        mmio_read (16'hFF10, rd);
        chk8("T3_MCR_wr02", 8'h02, rd);
        chk8("T3_mmu_en_bit0only", 8'h00, {7'b0, mmu_en_o});

        //--------------------------------------------------------
        // T5. ★MCR.EN=1 でも PTR/MCR に書ける★ (自己ロックアウト回避)
        //--------------------------------------------------------
        mmio_write(16'hFF10, 8'h01);              // MMU ON
        chk8("T5_mmu_on", 8'h01, {7'b0, mmu_en_o});

        mmio_write(16'hFF04, 8'h14);              // MMU ON状態でPTR[4]書換
        mmio_read (16'hFF04, rd);
        chk8("T5_PTR4_wr_while_on", 8'h14, rd);
        chk8("T5_ptr_o4_while_on", 8'h14, ptr_o(4));

        mmio_write(16'hFF10, 8'h00);              // MMU ON状態からMCRで切り戻し
        chk8("T5_mmu_off_again", 8'h00, {7'b0, mmu_en_o});   // ★自己救済性★

        //--------------------------------------------------------
        // T6/T7. 非MMU領域は従来スタブ挙動(固定0x00・ライト無視)
        //--------------------------------------------------------
        mmio_read(16'hFC80, rd);   chk8("T6_FC80_zero", 8'h00, rd);
        mmio_read(16'hFD00, rd);   chk8("T6_FD00_zero", 8'h00, rd);
        mmio_read(16'hFF11, rd);   chk8("T6_FF11_reserved", 8'h00, rd);
        mmio_read(16'hFF1F, rd);   chk8("T6_FF1F_reserved", 8'h00, rd);
        mmio_read(16'hFFFF, rd);   chk8("T6_FFFF_zero", 8'h00, rd);

        // ライト無視: 非MMU領域に書いてもPTR/MCRは変わらない
        mmio_write(16'hFC80, 8'hDE);
        mmio_write(16'hFF11, 8'hAD);     // 予約領域
        mmio_read (16'hFC80, rd);   chk8("T7_FC80_wr_ignored", 8'h00, rd);
        mmio_read (16'hFF11, rd);   chk8("T7_FF11_wr_ignored", 8'h00, rd);
        chk8("T7_ptr_o4_unchanged", 8'h14, ptr_o(4));   // PTR[4]は壊れていない
        chk8("T7_mcr_unchanged",    8'h00, {7'b0, mmu_en_o});

        //--------------------------------------------------------
        $display("--------------------------------------------");
        if (fail_cnt == 0)
            $display("ALL PASS (%0d vectors)", pass_cnt);
        else
            $display("FAILED: %0d / %0d", fail_cnt, pass_cnt + fail_cnt);
        $display("============================================");
        $finish;
    end

    // タイムアウト保険
    initial begin
        #100000;
        $display("FAIL: TIMEOUT");
        $finish;
    end

endmodule
