// ============================================================
//  tb_cpu_v37irq_v0_1.sv   v0.1  (2026-07-12)
//  YSD8800 FPGA V3.7 S5 : CPU結合TB（YSD8004 → IRQ1 → 割込受理）
//
//  DUT   : ysd8800_v37_membus_v0_1 + ysd8800_cpu_v0_1_FIXED (v0.5.7 無改修)
//  設計  : v3_7_design_memo_v0_2.md（承認版）
//  黄金  : emu23 v1.09 / gen_v37_irq_vectors.py が生成
//          → v37irq/v37irq.hex (イメージ) / golden_v37irq.txt (期待値)
//
//  ------------------------------------------------------------
//  【方式】案①（本チャットで承認）
//    emu23 には YSD8004 に外から割込を上げる手段が無い（ysd8004_raise は
//    UART/Storage が呼ぶ内部関数。V4/V6未実装のため使えない）。
//    そこで:
//      emu23 : SYSCALL(irq=4) → vec=rd16(8)=$0200
//      RTL   : YSD8004経由IRQ1(irq=2) → vec=rd16(4)=$0200
//    ★ベクタ $0004 と $0008 の両方を同一ハンドラ($0200)に向ける★ことで、
//    起動経路が違っても【受理シーケンスと最終状態】を黄金照合できる。
//
//  【★突合対象から A を除外★】
//    ハンドラは IRQ_STAT($FCB2) を A に読む。
//      emu23: デバイス未発火 → IRQ_STAT=0x00 → A=0x0000
//      RTL  : YSD8004発火済 → IRQ_STAT=0x01 → A=0x0001
//    これは【意図した差】。A は黄金突合せず、RTL固有チェック(=0x0001)を行う。
//    → 逆に A=0x0001 が読めることが【YSD8004がバスに乗っている実証】になる。
//
//  【黄金期待値】(emu23 v1.09 実行結果)
//      B  = 1234   （割込を跨いで保持）
//      X  = BEEF   ★ハンドラ到達の痕跡★
//      SP = 0400   ★IRETでpush2回(4byte)が正しく戻った★
//      F  = 81     ★IRETでIE=1が復元された（受理時は 01=IE0）★
//      A  = 0001   ★RTL固有: YSD8004 IRQ_STAT bit0★
//
//  【検証項目】
//    1. irq1_o が YSD8004 から立つ（irq_src パルス → レベル出力）
//    2. CPU が受理し vec=$0004 → PC=$0200（ハンドラ）へ飛ぶ
//    3. ハンドラが IRQ_STAT を読める（A=0x0001）
//    4. ハンドラの Write-to-Clear で irq1_o が下がる ★多重受理防止★
//    5. IRET で SP/FLAGS が復元される（黄金一致）
//    6. 最終レジスタが黄金一致（A除く）
// ============================================================
`timescale 1ns/1ps

import ysd8800_idec_pkg::*;

module tb_cpu_v37irq_v0_1;

    logic        cpu_clk, cpu_rst_n;
    logic        psram_clk, psram_rst_n;

    logic [15:0] mem_addr;
    logic [7:0]  mem_wdata, mem_rdata;
    logic        mem_rd, mem_wr, mem_ready;

    logic [2:0]  irq_in;
    logic [2:0]  dbg_irq_pending;
    logic [15:0] dbg_pc, dbg_a, dbg_b, dbg_x, dbg_sp;
    logic [15:0] dbg_flags;
    logic        halted;

    // ---- YSD8004 割込I/F ----
    logic irq_src_uart_rx, irq_src_stor, irq_src_uart_tx;
    logic irq1;                        // ★YSD8004 → CPU（レベル）★

    logic [15:0] dbg_mmio_last_addr;
    logic [31:0] dbg_mmio_access_count;

    integer errors = 0;

    // ============================================================
    //  ★V3.7の本丸: YSD8004 の irq1(レベル) を CPU の irq_in へ★
    //    irq_in = 2 (IRQ1) → vec = rd16(2*2) = rd16($0004)
    //    ハンドラが IRQ_STAT をクリアすれば irq1 が下がり、
    //    S_IRQCHK での再ラッチ(L1224-1225)が起きない = 多重受理しない。
    //    （逆にクリアし忘れれば再受理される = emu23 の再評価機構と同挙動）
    // ============================================================
    assign irq_in = irq1 ? 3'd2 : 3'd0;

    // ---- CPUコア（★無改修 v0.5.7★）----
    ysd8800_cpu_v0_1 u_cpu (
        .clk(cpu_clk), .rst_n(cpu_rst_n),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata),
        .mem_rd(mem_rd), .mem_wr(mem_wr), .mem_ready(mem_ready),
        .irq_in(irq_in),
        .dbg_pc(dbg_pc), .dbg_a(dbg_a), .dbg_b(dbg_b), .dbg_x(dbg_x),
        .dbg_sp(dbg_sp), .dbg_flags(dbg_flags),
        .dbg_halt(halted),
        .dbg_irq_pending(dbg_irq_pending)
    );

    // ---- V3.7 メモリサブシステム（YSD8004内蔵）----
    ysd8800_v37_membus_v0_1 #(.PHYS_AW(20), .MEM_AW(20)) u_membus (
        .cpu_clk(cpu_clk), .cpu_rst_n(cpu_rst_n),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata),
        .mem_rd(mem_rd), .mem_wr(mem_wr), .mem_ready(mem_ready),
        .psram_clk(psram_clk), .psram_rst_n(psram_rst_n),
        .irq_src_uart_rx(irq_src_uart_rx),
        .irq_src_stor   (irq_src_stor),
        .irq_src_uart_tx(irq_src_uart_tx),
        .irq1_o         (irq1),
        .dbg_mmio_last_addr(dbg_mmio_last_addr),
        .dbg_mmio_access_count(dbg_mmio_access_count)
    );

    // クロック: CPU 4MHz相当(period=20) : PSRAM 80MHz相当(period=1)
    initial cpu_clk = 0;
    always #10 cpu_clk = ~cpu_clk;
    initial psram_clk = 0;
    always #0.5 psram_clk = ~psram_clk;

    // ---- 観測用 ----
    logic irq_fired;        // irq1 が立ったことがある
    logic handler_reached;  // PC が $0200 台に入った
    logic irq1_cleared;     // ハンドラ後に irq1 が下がった
    logic [15:0] a_in_handler;   // ハンドラが読んだ IRQ_STAT

    // ---- watchdog ----
    initial begin
        #400000;
        $display("FAIL: WATCHDOG TIMEOUT (halted=%0b pc=%04h)", halted, dbg_pc);
        $display("RESULT: FAIL");
        $finish;
    end

    initial begin
        $display("============================================");
        $display(" tb_cpu_v37irq_v0_1 : V3.7 S5 CPU integration");
        $display("   YSD8004 -> IRQ1 -> CPU accept -> handler");
        $display("============================================");

        irq_src_uart_rx = 1'b0;
        irq_src_stor    = 1'b0;
        irq_src_uart_tx = 1'b0;
        irq_fired       = 1'b0;
        handler_reached = 1'b0;
        irq1_cleared    = 1'b0;
        a_in_handler    = 16'hFFFF;

        cpu_rst_n   = 1'b0;
        psram_rst_n = 1'b0;

        // 黄金と同一イメージをPSRAMへロード
        $readmemh("v37irq/v37irq.hex", u_membus.u_psram_ctrl.mem);

        repeat (5) @(posedge cpu_clk);
        cpu_rst_n   = 1'b1;
        psram_rst_n = 1'b1;

        // ---- リセット直後: irq1 は下がっているはず ----
        @(posedge cpu_clk);
        if (irq1 !== 1'b0) begin
            $display("FAIL: [0] irq1 asserted at reset (IRQ_STAT must be 0)");
            errors = errors + 1;
        end else begin
            $display("PASS: [0] irq1 deasserted at reset");
        end

        // 本体を走らせる。SYSCALL($0116手前)に到達する前に割込を入れる。
        //   本体: LDW SP / LDW B / LDW X / LDW A / STB A,[IRQ_MASK] / EI / SYSCALL / HALT
        //   EI 実行後(IE=1)でないと受理されないため、EI通過を待つ。
        //   EI は本体先頭から 4+4+4+4+4 = 20バイト目 → $0114。
        //   よって PC が $0115 に達したら（EI実行済）割込を上げる。
        fork
            begin : irq_driver
                wait (dbg_pc >= 16'h0115 && dbg_pc <= 16'h0116);
                @(posedge cpu_clk);
                $display("INFO: EI passed (pc=%04h). raising irq_src_uart_rx.", dbg_pc);
                irq_src_uart_rx = 1'b1;      // ★1クロックパルス（§4.3規約）★
                @(posedge cpu_clk);
                irq_src_uart_rx = 1'b0;
            end
        join_none

        // ---- 観測ループ ----
        forever begin
            @(posedge cpu_clk);

            if (irq1 && !irq_fired) begin
                irq_fired = 1'b1;
                $display("PASS: [1] irq1 asserted by YSD8004 (level) @pc=%04h", dbg_pc);
            end

            // ハンドラ($0200-$020C)に到達
            if (!handler_reached && dbg_pc >= 16'h0200 && dbg_pc <= 16'h0210) begin
                handler_reached = 1'b1;
                $display("PASS: [2] handler reached: pc=%04h (vec $0004 -> $0200)", dbg_pc);
            end

            // ハンドラ内で A に IRQ_STAT が読まれた時点を捕捉
            //   LDB A,[$FCB2] 完了後 pc=$0204。この時 A = IRQ_STAT。
            if (handler_reached && dbg_pc == 16'h0208 && a_in_handler === 16'hFFFF)
                a_in_handler = dbg_a;

            // ハンドラのW2C後、irq1 が下がる
            if (irq_fired && !irq1 && !irq1_cleared && handler_reached) begin
                irq1_cleared = 1'b1;
                $display("PASS: [4] irq1 deasserted by handler W2C @pc=%04h", dbg_pc);
            end

            if (halted) begin
                $display("INFO: HALT at pc=%04h", dbg_pc);
                repeat (2) @(posedge cpu_clk);
                check_final();
                $finish;
            end
        end
    end

    // ------------------------------------------------------------
    //  最終照合（黄金: emu23 v1.09）
    // ------------------------------------------------------------
    task automatic check_final();
        begin
            $display("--------------------------------------------");
            $display("final: A=%04h B=%04h X=%04h SP=%04h F=%02h",
                     dbg_a, dbg_b, dbg_x, dbg_sp, dbg_flags[7:0]);
            $display("--------------------------------------------");

            if (!irq_fired) begin
                $display("FAIL: [1] irq1 never asserted");
                errors = errors + 1;
            end
            if (!handler_reached) begin
                $display("FAIL: [2] handler never reached (vec $0004 broken?)");
                errors = errors + 1;
            end

            // [3] ★YSD8004がバスに乗っている実証★ IRQ_STAT bit0 = 1 を読めたか
            if (a_in_handler === 16'h0001)
                $display("PASS: [3] handler read IRQ_STAT = 0001 (YSD8004 on bus)");
            else begin
                $display("FAIL: [3] handler read IRQ_STAT = %04h (exp 0001)", a_in_handler);
                errors = errors + 1;
            end

            // [4] W2C で irq1 が落ちたか（多重受理防止）
            if (irq1_cleared)
                ; // 既に PASS 表示済
            else begin
                $display("FAIL: [4] irq1 not cleared by handler W2C (irq1=%0b)", irq1);
                errors = errors + 1;
            end
            if (irq1 !== 1'b0) begin
                $display("FAIL: [4b] irq1 still asserted at end", irq1);
                errors = errors + 1;
            end

            // [5][6] 黄金照合（★A は除外★）
            chk("[6] B  (preserved)", dbg_b,         16'h1234);
            chk("[6] X  (handler mark BEEF)", dbg_x, 16'hBEEF);
            chk("[5] SP (IRET restored)", dbg_sp,    16'h0400);
            chk("[5] F  (IE restored=81)", {8'h00, dbg_flags[7:0]}, 16'h0081);

            // irq_pending がクリアされているか
            if (dbg_irq_pending !== 3'd0) begin
                $display("FAIL: irq_pending=%0d (exp 0)", dbg_irq_pending);
                errors = errors + 1;
            end

            $display("============================================");
            if (errors == 0)
                $display("ALL PASS (V3.7 S5: YSD8004->IRQ1->accept->handler->IRET, emu23協調等価)");
            else
                $display("RESULT: %0d FAIL", errors);
            $display("============================================");
        end
    endtask

    task automatic chk(input string nm, input logic [15:0] act, input logic [15:0] exp);
        begin
            if (act === exp)
                $display("PASS: %-28s act=%04h exp=%04h", nm, act, exp);
            else begin
                $display("FAIL: %-28s act=%04h exp=%04h", nm, act, exp);
                errors = errors + 1;
            end
        end
    endtask

endmodule
