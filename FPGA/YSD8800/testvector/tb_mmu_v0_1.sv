// ============================================================
//  tb_mmu_v0_1.sv   v0.1  (2026-07-11)
//  YSD8800 FPGA V3.5 : MMU単体TB
//
//  対象: ysd8800_mmu_v0_1.sv (v0.1)
//  設計根拠: v3_5_design_memo_v0_2.md §5.1
//
//  検証項目:
//    T1. MCR=0 で恒等写像（全16論理ページ）        … V3等価性の基礎
//    T2. MCR=1 で {PTR[page], offset} 変換
//    T3. PTR書換の即時反映（純組合せであること）
//    T4. ページ境界($0FFF/$1000)で変換ページが切り替わる
//    T5. 設計書§9-1 OK例の再現（PTR[4]=$14 → 論理$4000 → 物理$14000）
//    T6. 恒等写像リセット値(PTR[i]=i)でMCR=1にしても変換が恒等になる
//        （V7/V8 reset vector問題への布石・レビュー所見§10.2）
// ============================================================
`timescale 1ns/1ps

module tb_mmu_v0_1;

    localparam int PHYS_AW = 20;

    logic [15:0]        logical_addr;
    logic               mmu_en;
    logic [7:0]         ptr [0:15];
    logic [PHYS_AW-1:0] physical_addr;

    ysd8800_mmu_v0_1 #(.PHYS_AW(PHYS_AW)) dut (
        .logical_addr (logical_addr),
        .mmu_en       (mmu_en),
        .ptr          (ptr),
        .physical_addr(physical_addr)
    );

    int pass_cnt = 0;
    int fail_cnt = 0;

    // 期待値照合タスク（純組合せなので #1 で伝搬を待つ）
    task automatic chk(input string name,
                       input logic [15:0] la,
                       input logic en,
                       input logic [PHYS_AW-1:0] exp);
        begin
            logical_addr = la;
            mmu_en       = en;
            #1;
            if (physical_addr === exp) begin
                pass_cnt++;
            end else begin
                fail_cnt++;
                $display("FAIL: %s  la=%04h en=%0d  exp=%05h got=%05h",
                         name, la, en, exp, physical_addr);
            end
        end
    endtask

    // 恒等写像リセット値の設定（emu23 mmu_reset(): ptr[i]=i）
    task automatic set_ident_ptr();
        begin
            for (int i = 0; i < 16; i++) ptr[i] = i[7:0];
        end
    endtask

    initial begin
        $display("=== tb_mmu_v0_1 : MMU single-module TB ===");

        //--------------------------------------------------------
        // T1. MCR=0 で恒等写像（全16論理ページ）
        //--------------------------------------------------------
        // PTRにわざと非恒等な値を入れておく（無効時は無視されるはず）
        for (int i = 0; i < 16; i++) ptr[i] = 8'hA0 + i[7:0];

        for (int p = 0; p < 16; p++) begin
            logic [15:0] la;
            la = {p[3:0], 12'h345};   // 各ページの適当なオフセット
            chk($sformatf("T1_ident_page%0d", p), la, 1'b0, {4'b0, la});
        end
        // 境界値も確認
        chk("T1_ident_0000", 16'h0000, 1'b0, 20'h00000);
        chk("T1_ident_FFFF", 16'hFFFF, 1'b0, 20'h0FFFF);

        //--------------------------------------------------------
        // T2. MCR=1 で {PTR[page], offset} 変換
        //--------------------------------------------------------
        // ptr[i] = 0xA0+i のまま。page3 → phys page 0xA3
        chk("T2_p3_off000", 16'h3000, 1'b1, 20'hA3000);
        chk("T2_p3_offFFF", 16'h3FFF, 1'b1, 20'hA3FFF);
        chk("T2_p0_off123", 16'h0123, 1'b1, 20'hA0123);
        chk("T2_pF_offABC", 16'hFABC, 1'b1, 20'hAFABC);

        //--------------------------------------------------------
        // T3. PTR書換の即時反映（純組合せであること）
        //--------------------------------------------------------
        ptr[7] = 8'h55;
        chk("T3_ptr7_55", 16'h7111, 1'b1, 20'h55111);
        ptr[7] = 8'hCC;   // 同一アドレスでPTRだけ変える
        chk("T3_ptr7_CC", 16'h7111, 1'b1, 20'hCC111);

        //--------------------------------------------------------
        // T4. ページ境界($0FFF/$1000)で変換ページが切り替わる
        //--------------------------------------------------------
        ptr[0] = 8'h30;
        ptr[1] = 8'h31;
        chk("T4_bound_0FFF", 16'h0FFF, 1'b1, 20'h30FFF);  // page0 → phys 0x30
        chk("T4_bound_1000", 16'h1000, 1'b1, 20'h31000);  // page1 → phys 0x31

        //--------------------------------------------------------
        // T5. 設計書§9-1 OK例（PTR[4]=$14 → 論理$4000 → 物理$14000）
        //--------------------------------------------------------
        ptr[4] = 8'h14;
        ptr[5] = 8'h15;
        chk("T5_doc_4000", 16'h4000, 1'b1, 20'h14000);
        chk("T5_doc_4FFF", 16'h4FFF, 1'b1, 20'h14FFF);
        chk("T5_doc_5000", 16'h5000, 1'b1, 20'h15000);

        //--------------------------------------------------------
        // T6. 恒等写像リセット値(PTR[i]=i)ならMCR=1でも変換は恒等
        //     （レビュー所見 §10.2 / V7-V8 reset vector問題への布石）
        //--------------------------------------------------------
        set_ident_ptr();
        for (int p = 0; p < 16; p++) begin
            logic [15:0] la;
            la = {p[3:0], 12'h789};
            // ptr[p]=p のとき (p<<12)|offset == logical → 上位4bitは0
            chk($sformatf("T6_identON_page%0d", p), la, 1'b1, {4'b0, la});
        end

        //--------------------------------------------------------
        $display("--------------------------------------------");
        if (fail_cnt == 0)
            $display("ALL PASS (%0d vectors)", pass_cnt);
        else
            $display("FAILED: %0d / %0d", fail_cnt, pass_cnt + fail_cnt);
        $display("============================================");
        $finish;
    end

endmodule
