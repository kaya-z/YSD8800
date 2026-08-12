// [V3.7 S4] tb_cpu_v35boundary_poc.sv より自動複製 (mk_v37_tb.py v1.0 / 2026-07-12)
//   変更点: membus を ysd8800_v37_membus_v0_1 に差し替え、
//           YSD8004割込ポートを接続(割込源は0固定)。判定内容は同一。
//   目的  : V3.7統合による V3.5相当機能のデグレ検出（回帰）
// ============================================================
//  tb_cpu_v35boundary_poc.sv  (V3.5 regression PoC / KY38)
//  実CPU + V3.5メモリサブシステム(MMU統合・MCR=0)
//
//  対象ベクタ: v3boundary/BOUNDARY_JSR_BEQ (gen_v3_boundary_vectors.py)
//  黄金:       A=0006 B=0006 X=CAFE SP=0400 F=02  (emu23 v1.09)
//
//  【狙い】S5-3: 境界アドレス($FC7F RAM側/$FC80 MMIO側)の判定が
//    MMU統合後も【論理アドレス】で正しく行われることの実証。
//    MCR=0なのでMMUは恒等写像 => V3とbit-exact等価のはず。
//
//    ★設計メモ §2 の核心★
//    デコーダはMMUの【前段】にあり、論理アドレスで$FC80判定する。
//    このベクタは$FC7F(RAM)と$FC80(MMIO)の両方に触るため、
//    デコーダの振り分けが壊れれば必ずFAILする。
// ============================================================
`timescale 1ns/1ps

module tb_cpu_v37boundary_poc;

    logic v37_irq1;   // ★V3.7: YSD8004 IRQ1観測（本TBでは0のはず）★

    logic        cpu_clk, cpu_rst_n;
    logic        psram_clk, psram_rst_n;
    logic [15:0] mem_addr;
    logic [7:0]  mem_wdata, mem_rdata;
    logic        mem_rd, mem_wr, mem_ready;
    logic [2:0]  irq_in;   // CPUコア実I/Fは3bit(ビルド警告で判明・KY34)

    logic [15:0] dbg_pc, dbg_a, dbg_b, dbg_x, dbg_sp, dbg_flags;
    logic        dbg_halt;
    logic [15:0] dbg_mmio_last_addr;
    logic [31:0] dbg_mmio_access_count;
    logic        dbg_mmu_en;
    logic [19:0] dbg_phys_addr;
    logic [127:0] dbg_ptr_flat;

    integer errors = 0;

    ysd8800_cpu_v0_1 dut_cpu (
        .clk(cpu_clk), .rst_n(cpu_rst_n),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata),
        .mem_rd(mem_rd), .mem_wr(mem_wr), .mem_ready(mem_ready),
        .irq_in(irq_in),
        .dbg_pc(dbg_pc), .dbg_a(dbg_a), .dbg_b(dbg_b), .dbg_x(dbg_x),
        .dbg_sp(dbg_sp), .dbg_flags(dbg_flags), .dbg_halt(dbg_halt)
    );

    ysd8800_v37_membus_v0_1 #(.PHYS_AW(20), .MEM_AW(20)) u_membus (
        // ★V3.7: 割込I/F（本TBでは未使用。割込源は0固定）★
        .irq_src_uart_rx(1'b0),
        .irq_src_stor   (1'b0),
        .irq_src_uart_tx(1'b0),
        .irq1_o         (v37_irq1),
        .cpu_clk(cpu_clk), .cpu_rst_n(cpu_rst_n),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata),
        .mem_rd(mem_rd), .mem_wr(mem_wr), .mem_ready(mem_ready),
        .psram_clk(psram_clk), .psram_rst_n(psram_rst_n),
        .dbg_mmio_last_addr(dbg_mmio_last_addr),
        .dbg_mmio_access_count(dbg_mmio_access_count),
        .dbg_mmu_en(dbg_mmu_en),
        .dbg_phys_addr(dbg_phys_addr),
        .dbg_ptr_flat(dbg_ptr_flat)
    );

    initial cpu_clk = 0;
    always #10 cpu_clk = ~cpu_clk;
    initial psram_clk = 0;
    always #0.5 psram_clk = ~psram_clk;

    // 黄金値(emu23 v1.09 / gen_v3_boundary_vectors.py)
    localparam logic [15:0] EXP_A  = 16'h0006;
    localparam logic [15:0] EXP_B  = 16'h0006;
    localparam logic [15:0] EXP_X  = 16'hCAFE;
    localparam logic [15:0] EXP_SP = 16'h0400;
    localparam logic [15:0] EXP_F  = 16'h0002;

    initial begin
        $display("=== tb_cpu_v35boundary_poc : boundary($FC7F/$FC80)+JSR/RET/BEQ ===");
        irq_in      = 3'b000;
        cpu_rst_n   = 1'b0;
        psram_rst_n = 1'b0;

        // ベクタイメージをPSRAMへロード
        $readmemh("v3boundary/BOUNDARY_JSR_BEQ.hex", u_membus.u_psram_ctrl.mem);

        repeat (5) @(posedge cpu_clk);
        cpu_rst_n   = 1'b1;
        psram_rst_n = 1'b1;

        // HALTまで実行(タイムアウト付き)
        fork
            begin
                wait (dbg_halt === 1'b1);
            end
            begin
                repeat (20000) @(posedge cpu_clk);
                $display("FAIL: TIMEOUT (HALT not reached)");
                errors++;
            end
        join_any
        disable fork;

        repeat (2) @(posedge cpu_clk);

        $display("[BOUNDARY_JSR_BEQ] A=%04h B=%04h X=%04h SP=%04h F=%02h",
                 dbg_a, dbg_b, dbg_x, dbg_sp, dbg_flags);

        if (dbg_a  !== EXP_A)  begin errors++; $display("FAIL: A  exp=%04h got=%04h", EXP_A,  dbg_a);  end
        if (dbg_b  !== EXP_B)  begin errors++; $display("FAIL: B  exp=%04h got=%04h", EXP_B,  dbg_b);  end
        if (dbg_x  !== EXP_X)  begin errors++; $display("FAIL: X  exp=%04h got=%04h", EXP_X,  dbg_x);  end
        if (dbg_sp !== EXP_SP) begin errors++; $display("FAIL: SP exp=%04h got=%04h", EXP_SP, dbg_sp); end
        if (dbg_flags !== EXP_F) begin errors++; $display("FAIL: F exp=%02h got=%02h", EXP_F, dbg_flags); end

        // ★MMIO到達確認★ $FC80へのSTBがMMIO側に振り分けられたこと
        if (dbg_mmio_access_count == 0) begin
            errors++;
            $display("FAIL: MMIO access count = 0 ($FC80 STB did not reach MMIO)");
        end else begin
            $display("[INFO] MMIO access count=%0d last_addr=%04h (expect $FC80 reached)",
                     dbg_mmio_access_count, dbg_mmio_last_addr);
        end

        // ★MMU無効確認★ MCR=0(リセット値)のままであること
        if (dbg_mmu_en !== 1'b0) begin
            errors++;
            $display("FAIL: MCR.EN should be 0 (V3 equivalent mode)");
        end

        $display("--------------------------------------------");
        if (errors == 0)
            $display("ALL PASS (1/1 vector, boundary $FC7F/$FC80 + JSR/RET/BEQ, MMU disabled)");
        else
            $display("FAILED: %0d errors", errors);
        $display("============================================");
        $finish;
    end

endmodule
