// ============================================================
//  tb_bridge_psram_20bit_v0_1.sv   v0.1  (2026-07-11)
//  YSD8800 FPGA V3.5 : CDCブリッジv0.2 + PSRAMコントローラv0.2
//                      ★20bit物理アドレス貫通の検証★
//
//  対象: ysd8800_cdc_bridge_v0_2.sv (v0.2)
//        ysd8800_psram_ctrl_v0_2.sv (v0.2)
//  設計根拠: v3_5_design_memo_v0_2.md §4.2 / §8 Q2
//
//  ------------------------------------------------------------
//  【本TBの狙い】★V3.5改修の目的そのものを守る★
//    V3実装では以下の2箇所で上位4bitが捨てられていた(KY34で検出):
//      (1) cdc_bridge  : output logic [15:0] psram_addr;  (16bit固定)
//      (2) psram_ctrl  : assign addr_lo = addr[15:0];     (上位を捨てる)
//                        logic [7:0] mem [0:65535];       (64KB固定)
//    この状態でMMUを繋いでも、論理$4000→物理$14000 のリマップが
//    【$4000に化けて】全く効かない。
//
//    本TBは「$04000 と $14000 が別アドレスとして区別されること」を
//    直接検証し、この事故を恒久的に防ぐ。
//
//    ※これが崩れるとMMUは"繋がっているのに効かない"という最も
//      発見しにくい状態になる(全ベクタが恒等写像的に振る舞い、
//      MMU_IDENT_ON(#1)だけPASSして他が謎のFAILをする)。
//  ------------------------------------------------------------
//
//  検証項目:
//    T1. 20bit書込→読出 ($14000)
//    T2. ★エイリアス非発生★ $04000 と $14000 が独立であること
//        (下位16bitが同じ $4000 同士。V3実装なら必ず衝突する)
//    T3. 上位4bit全域 ($04000/$14000/$24000/.../$F4000) の独立性
//    T4. 物理空間上限 ($FFFFF) への到達
// ============================================================
`timescale 1ns/1ps

module tb_bridge_psram_20bit_v0_1;

    localparam int PHYS_AW = 20;
    localparam int MEM_AW  = 20;    // 1MB確保

    logic               cpu_clk = 0;
    logic               cpu_rst_n;
    logic               psram_clk = 0;
    logic               psram_rst_n;

    logic [PHYS_AW-1:0] cpu_phys_addr;
    logic [7:0]         cpu_mem_wdata;
    logic [7:0]         cpu_mem_rdata;
    logic               cpu_mem_rd;
    logic               cpu_mem_wr;
    logic               cpu_mem_ready;

    logic [PHYS_AW-1:0] psram_addr;
    logic [7:0]         psram_wdata;
    logic               psram_we;
    logic               psram_req;
    logic               psram_ack;
    logic [7:0]         psram_rdata;

    // CPU 4MHz相当(125ns) / PSRAM 高速(10ns)
    always #62.5 cpu_clk   = ~cpu_clk;
    always #5    psram_clk = ~psram_clk;

    ysd8800_cdc_bridge_v0_2 #(.PHYS_AW(PHYS_AW)) u_bridge (
        .cpu_clk(cpu_clk), .cpu_rst_n(cpu_rst_n),
        .cpu_phys_addr(cpu_phys_addr), .cpu_mem_wdata(cpu_mem_wdata),
        .cpu_mem_rdata(cpu_mem_rdata), .cpu_mem_rd(cpu_mem_rd),
        .cpu_mem_wr(cpu_mem_wr), .cpu_mem_ready(cpu_mem_ready),
        .psram_clk(psram_clk), .psram_rst_n(psram_rst_n),
        .psram_addr(psram_addr), .psram_wdata(psram_wdata), .psram_we(psram_we),
        .psram_req(psram_req), .psram_ack(psram_ack), .psram_rdata(psram_rdata)
    );

    ysd8800_psram_ctrl_v0_2 #(
        .LATENCY_NORMAL(12), .LATENCY_REFRESH(15), .REFRESH_PPM(500),
        .PHYS_AW(PHYS_AW), .MEM_AW(MEM_AW)
    ) u_psram (
        .clk(psram_clk), .rst_n(psram_rst_n),
        .addr(psram_addr), .wdata(psram_wdata), .we(psram_we),
        .req(psram_req), .ack(psram_ack), .rdata(psram_rdata),
        .dbg_refresh_hit()
    );

    int pass_cnt = 0;
    int fail_cnt = 0;

    task automatic bus_write(input logic [PHYS_AW-1:0] a, input logic [7:0] d);
        begin
            @(negedge cpu_clk);
            cpu_phys_addr = a;
            cpu_mem_wdata = d;
            cpu_mem_wr    = 1'b1;
            cpu_mem_rd    = 1'b0;
            wait (cpu_mem_ready === 1'b1);
            @(negedge cpu_clk);
            cpu_mem_wr    = 1'b0;
        end
    endtask

    task automatic bus_read(input logic [PHYS_AW-1:0] a, output logic [7:0] d);
        begin
            @(negedge cpu_clk);
            cpu_phys_addr = a;
            cpu_mem_rd    = 1'b1;
            cpu_mem_wr    = 1'b0;
            wait (cpu_mem_ready === 1'b1);
            d = cpu_mem_rdata;
            @(negedge cpu_clk);
            cpu_mem_rd    = 1'b0;
        end
    endtask

    task automatic chk(input string name, input logic [7:0] exp, input logic [7:0] got);
        begin
            if (exp === got) pass_cnt++;
            else begin
                fail_cnt++;
                $display("FAIL: %s  exp=%02h got=%02h", name, exp, got);
            end
        end
    endtask

    logic [7:0] rd;

    initial begin
        $display("=== tb_bridge_psram_20bit_v0_1 : 20bit phys addr penetration ===");
        cpu_phys_addr = '0;
        cpu_mem_wdata = 8'h00;
        cpu_mem_rd    = 1'b0;
        cpu_mem_wr    = 1'b0;
        cpu_rst_n     = 1'b0;
        psram_rst_n   = 1'b0;
        repeat (5) @(posedge cpu_clk);
        cpu_rst_n   = 1'b1;
        psram_rst_n = 1'b1;
        repeat (2) @(posedge cpu_clk);

        //--------------------------------------------------------
        // T1. 20bit書込→読出 ($14000)
        //--------------------------------------------------------
        bus_write(20'h14000, 8'hA5);
        bus_read (20'h14000, rd);
        chk("T1_14000_rw", 8'hA5, rd);

        //--------------------------------------------------------
        // T2. ★エイリアス非発生★ $04000 と $14000 は独立
        //     (下位16bitはどちらも $4000。V3実装なら必ず衝突する)
        //--------------------------------------------------------
        bus_write(20'h04000, 8'h11);    // 下位側に別値を書く
        bus_read (20'h14000, rd);
        chk("T2_14000_not_clobbered", 8'hA5, rd);   // ★$14000は壊れていないこと★
        bus_read (20'h04000, rd);
        chk("T2_04000_own_value",     8'h11, rd);   // ★$04000は自分の値★

        // 逆向きも確認: $14000を書き換えても$04000は壊れない
        bus_write(20'h14000, 8'h5A);
        bus_read (20'h04000, rd);
        chk("T2_04000_not_clobbered", 8'h11, rd);
        bus_read (20'h14000, rd);
        chk("T2_14000_own_value",     8'h5A, rd);

        //--------------------------------------------------------
        // T3. 上位4bit全域の独立性 ($n4000 / n=0..15)
        //     各ページに固有値を書き、全部読み返して衝突が無いこと
        //--------------------------------------------------------
        for (int n = 0; n < 16; n++) begin
            logic [PHYS_AW-1:0] a;
            a = {n[3:0], 16'h4000};
            bus_write(a, 8'hC0 + n[7:0]);
        end
        for (int n = 0; n < 16; n++) begin
            logic [PHYS_AW-1:0] a;
            a = {n[3:0], 16'h4000};
            bus_read(a, rd);
            chk($sformatf("T3_page%0d_4000", n), 8'hC0 + n[7:0], rd);
        end

        //--------------------------------------------------------
        // T4. 物理空間上限 ($FFFFF) への到達
        //--------------------------------------------------------
        bus_write(20'hFFFFF, 8'h7E);
        bus_read (20'hFFFFF, rd);
        chk("T4_FFFFF_rw", 8'h7E, rd);
        // $0FFFF(下位16bit同値)と独立であること
        bus_write(20'h0FFFF, 8'h3C);
        bus_read (20'hFFFFF, rd);
        chk("T4_FFFFF_not_clobbered", 8'h7E, rd);

        //--------------------------------------------------------
        $display("--------------------------------------------");
        if (fail_cnt == 0)
            $display("ALL PASS (%0d vectors)", pass_cnt);
        else
            $display("FAILED: %0d / %0d", fail_cnt, pass_cnt + fail_cnt);
        $display("============================================");
        $finish;
    end

    // タイムアウト保険(原則61)
    initial begin
        #2000000;
        $display("FAIL: TIMEOUT");
        $finish;
    end

endmodule
