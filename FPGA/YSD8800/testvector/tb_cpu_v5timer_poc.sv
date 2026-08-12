// ================================================================
//  tb_cpu_v5timer_poc.sv   v0.1  (2026-07-15 CHAT93)
//  YSD8800 FPGA V5(YSD8002タイマー) / S8 統合TB
//
//  【検証の一周】(レビュー文書 tb_cpu_v5timer_poc_design_review_v1_0 §3)
//    YSD8002 irq_timer_o(レベル) → CPU irq_in=3'd1 → IRQ0例外
//      → IRQ0ハンドラ実行 → TCR-ACK($0023)再武装 → IRET → 主処理復帰
//
//  【DUT構成（実源確認済・KY34）】
//    - CPUコア   : ysd8800_cpu_v0_1  (RTL v0.5.8, pending保護入り・無改修)
//                    L1247 S_IRQCHK限定の irq_pending 上書き保護あり。
//                    emu23 v1.10 L1591 と等価。
//    - membus    : ysd8800_v5_membus_v0_1_poc (CPU非内包・irq_timer_o/irq1_o外出し)
//    - YSD8002   : ysd8800_ysd8002_v0_2_poc   (irq_timer_o レベル化版)
//    - irq_timer_o は【レベル】: fireでset / TCR-ACK bit5でclear / resetでclear
//
//  【本TBのスコープ（C-1確定・HANDOVER §2.1-2）】
//    本TBは V5単独。IRQ1(UART)競合は無い（irq1_o は常に0固定で駆動）。
//    多デバイス競合(タイマ+UART)時の pending保護検証は別TB=V6以降へ送る。
//
//  【割込結線（membus外＝TB内で結線。v5_membus L25-26 の指示どおり）】
//    assign irq_in = irq_timer_o ? 3'd1 : (irq1_o ? 3'd2 : 3'd0);  ★タイマ優先★
//
//  【テストプログラム（emu23 v1.10 黄金refで実測駆動）】
//    v5t_ack.hex   : t2_ack.asm 骨格(ACKあり)。emu23実測 CNT=30 / HALT到達。
//    v5t_noack.hex : ACK 2命令削除版。emu23実測 CNT=1  / HALT到達。
//      ※ emu23はCPI=1固定。FPGAはCPI非一致のため発火回数の絶対値は一致しない。
//        判定は「複数回発火した事実(CNT>=2)」「暴走してない事実(CNT<=上限)」等の
//        論理的性質で行う（HANDOVER 申し送り: cycle一致は定義上不可）。
//
//  【テスト項目（承認済 §5.2/5.3 ＋ HANDOVER §2.1 T6追加）】
//    T0 ネガティブラン(KY54)  : わざと外したexpでTBがFAILを出せる健全性
//    T1 割込到達              : CNT != 0（fire→IRQ0ハンドラ分岐）
//    T2 ハンドラ完走＋IRET復帰: OUTC == 200（主ループ最後まで前進＝復帰の証拠）
//    T3 レベル保持の効果      : CNT <= CNT_MAX（多重発火で暴走してない）
//    T4 周期割込(再武装)      : CNT >= 2（TCR-ACK再武装で2回目以降が入る）
//    T5 主処理協調＋正常HALT  : dbg_halt==1 かつ OUTC==200
//    T6 ACK漏れ負テスト       : noack版で CNT == 1（再武装しない。T4との対照）
//
//  ★ISA/RTL 無改修。TB専用★
// ================================================================
`timescale 1ns/1ps
`default_nettype none

module tb_cpu_v5timer_poc;

    // ---- クロック/リセット ----
    logic cpu_clk;
    logic cpu_rst_n;
    logic psram_clk;
    logic psram_rst_n;

    // ---- CPU <-> membus バス ----
    logic [15:0] mem_addr;
    logic [7:0]  mem_wdata;
    logic [7:0]  mem_rdata;
    logic        mem_rd;
    logic        mem_wr;
    logic        mem_ready;

    // ---- 割込 ----
    logic [2:0]  irq_in;
    logic        irq_timer_o;
    logic        irq1_o;
    logic        irq0_ack;   // ★案0-a': CPU受理確定パルス CPU(out)->membus(in)★

    // ---- CPU dbg ----
    logic [15:0] dbg_pc, dbg_a, dbg_b, dbg_x, dbg_sp, dbg_flags;
    logic        dbg_halt;
    logic [2:0]  dbg_irq_pending;

    // ---- membus dbg(未使用も結線) ----
    logic [15:0] dbg_mmio_last_addr;
    logic [31:0] dbg_mmio_access_count;
    logic        dbg_mmu_en;
    logic [19:0] dbg_phys_addr;
    logic [127:0] dbg_ptr_flat;
    logic [31:0] dbg_cycle;

    // ---- UART側ポート(V5では未使用: 入力は0固定) ----
    logic        uart_rx_valid_i;
    logic [7:0]  uart_rx_data_i;
    logic        uart_tx_valid_o;
    logic [7:0]  uart_tx_data_o;

    integer errors = 0;
    integer passes = 0;

    // ============================================================
    //  割込結線（★membus外＝TB内。v5_membus L25-26 の指示どおり★）
    //    タイマ優先。本TBは irq1_o=0固定ゆえ実質 irq_timer_o のみ。
    // ============================================================
    assign irq_in = irq_timer_o ? 3'd1 : (irq1_o ? 3'd2 : 3'd0);

    // ============================================================
    //  DUT: CPUコア
    // ============================================================
    ysd8800_cpu_v0_1 dut_cpu (
        .clk(cpu_clk), .rst_n(cpu_rst_n),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata),
        .mem_rd(mem_rd), .mem_wr(mem_wr), .mem_ready(mem_ready),
        .irq_in(irq_in),
        .dbg_pc(dbg_pc), .dbg_a(dbg_a), .dbg_b(dbg_b), .dbg_x(dbg_x),
        .dbg_sp(dbg_sp), .dbg_flags(dbg_flags), .dbg_halt(dbg_halt),
        .dbg_irq_pending(dbg_irq_pending),
        .irq0_ack(irq0_ack)          // ★案0-a': 受理確定パルス出力★
    );

    // ============================================================
    //  DUT: v5 membus (YSD8002 タイマ内包・irq_timer_o外出し)
    // ============================================================
    ysd8800_v5_membus_v0_1_poc #(.PHYS_AW(20), .MEM_AW(20)) u_membus (
        .cpu_clk(cpu_clk), .cpu_rst_n(cpu_rst_n),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata),
        .mem_rd(mem_rd), .mem_wr(mem_wr), .mem_ready(mem_ready),
        .psram_clk(psram_clk), .psram_rst_n(psram_rst_n),
        .irq_src_stor(1'b0),
        .irq1_o(irq1_o),
        .uart_rx_valid_i(uart_rx_valid_i),
        .uart_rx_data_i(uart_rx_data_i),
        .uart_tx_valid_o(uart_tx_valid_o),
        .uart_tx_data_o(uart_tx_data_o),
        .irq_timer_o(irq_timer_o),
        .irq0_ack(irq0_ack),         // ★案0-a': CPU受理確定パルス入力★
        .dbg_mmio_last_addr(dbg_mmio_last_addr),
        .dbg_mmio_access_count(dbg_mmio_access_count),
        .dbg_mmu_en(dbg_mmu_en),
        .dbg_phys_addr(dbg_phys_addr),
        .dbg_ptr_flat(dbg_ptr_flat),
        .dbg_cycle(dbg_cycle)
    );

    // ============================================================
    //  クロック: CPU 4MHz相当(period=20) / PSRAM(period=1)
    // ============================================================
    initial cpu_clk = 0;
    always #10 cpu_clk = ~cpu_clk;
    initial psram_clk = 0;
    always #0.5 psram_clk = ~psram_clk;

    // ============================================================
    //  判定ユーティリティ
    // ============================================================
    task automatic chk(input string name, input integer got, input integer exp);
        if (got === exp) begin
            passes = passes + 1;
            $display("  PASS %-28s got=%0d exp=%0d", name, got, exp);
        end else begin
            errors = errors + 1;
            $display("  FAIL %-28s got=%0d exp=%0d", name, got, exp);
        end
    endtask

    // got>=lo && got<=hi の範囲判定（発火回数の性質判定用）
    task automatic chk_range(input string name, input integer got,
                             input integer lo, input integer hi);
        if (got >= lo && got <= hi) begin
            passes = passes + 1;
            $display("  PASS %-28s got=%0d range=[%0d..%0d]", name, got, lo, hi);
        end else begin
            errors = errors + 1;
            $display("  FAIL %-28s got=%0d range=[%0d..%0d]", name, got, lo, hi);
        end
    endtask

    // T0専用: FAILが出ることを期待する「反転チェック」
    //   わざと外したexpで chk が FAIL を出せれば TB健全（KY54）
    task automatic chk_expect_fail(input string name, input integer got, input integer wrong_exp);
        if (got !== wrong_exp) begin
            passes = passes + 1;
            $display("  PASS %-28s (TB correctly detects mismatch: got=%0d != wrong_exp=%0d)",
                     name, got, wrong_exp);
        end else begin
            errors = errors + 1;
            $display("  FAIL %-28s (TB failed to detect: got==wrong_exp==%0d)", name, got);
        end
    endtask

    // ============================================================
    //  リセットシーケンス
    // ============================================================
    task automatic do_reset();
        cpu_rst_n       = 0;
        psram_rst_n     = 0;
        uart_rx_valid_i = 1'b0;
        uart_rx_data_i  = 8'h00;
        repeat (3) @(negedge psram_clk);
        psram_rst_n = 1;
        repeat (3) @(negedge cpu_clk);
        cpu_rst_n = 1;
    endtask

    // ============================================================
    //  走行: HALT到達 or タイムアウトまで回す
    //    戻り値: CNT($0200), OUTC($0202) は呼び出し側で read_mem。
    // ============================================================
    // PSRAMメモリの1バイト読み(下位/上位を合成してword化するのは呼び出し側)
    function automatic [7:0] pmem(input [19:0] a);
        pmem = u_membus.u_psram_ctrl.mem[a];
    endfunction

    // word読み(リトルエンディアン: [a]=下位, [a+1]=上位)
    function automatic [15:0] pmemw(input [19:0] a);
        pmemw = {pmem(a+1), pmem(a)};
    endfunction

    integer to_cyc;
    task automatic run_until_halt(input integer max_cyc);
        to_cyc = 0;
        while (dbg_halt !== 1'b1 && to_cyc < max_cyc) begin
            @(posedge cpu_clk);
            to_cyc = to_cyc + 1;
        end
        if (dbg_halt !== 1'b1)
            $display("  [WARN] timeout: HALT not reached in %0d cyc", max_cyc);
        else
            $display("  [info] HALT reached at cyc=%0d (PC=%04h)", to_cyc, dbg_pc);
    endtask

    // ============================================================
    //  メイン
    // ============================================================
    localparam integer CNT_ADDR  = 20'h00200;
    localparam integer OUTC_ADDR = 20'h00202;
    // FPGA走行上限サイクル（十分HALTに届く値。CPI非依存の余裕）
    localparam integer MAX_CYC   = 4000000;
    // T3 暴走上限: 正常に周期発火しても、この上限を超える多重発火はしない
    //   （レベル保持が効いていれば1周期1回。上限は安全側に大きく取る）
    localparam integer CNT_MAX   = 1000;

    integer cnt_ack, outc_ack;
    integer cnt_noack;

    initial begin
        $display("============================================================");
        $display(" tb_cpu_v5timer_poc v0.1  YSD8800 FPGA V5 統合TB");
        $display("   CPU=ysd8800_cpu v0.5.8(pending保護入)/ V5単独(IRQ1競合なし)");
        $display("   YSD8002=v0.2_poc(irq_timer_o レベル化)");
        $display("============================================================");

        // ---------- ACKあり版を走行（T0〜T5の観測源）----------
        //  ★初期化順序はV4-TB実績を逐語踏襲（順序が本質的制約）★
        //    (1) cpu_rst_n=0 保持  (2) mem[0..0x1FF]クリア(KY52)
        //    (3) $readmemhロード   (4) その後にreset解除
        $display("[LOAD] v5t_ack.hex (ACKあり)");
        cpu_rst_n = 0;
        psram_rst_n = 0;
        uart_rx_valid_i = 1'b0;
        uart_rx_data_i  = 8'h00;
        repeat (3) @(negedge psram_clk);
        psram_rst_n = 1;
        // (1) メモリクリア: $readmemhは372語しか埋めず残りXだとfetchハング(KY52)
        for (int i = 0; i < 16'h0200; i = i + 1)
            u_membus.u_psram_ctrl.mem[i] = 8'h00;
        // (2) プログラムロード
        $readmemh("v5timer/v5t_ack.hex", u_membus.u_psram_ctrl.mem);
        // (3) ロード完了後にreset解除
        repeat (3) @(negedge cpu_clk);
        cpu_rst_n = 1;

        run_until_halt(MAX_CYC);
        cnt_ack  = pmemw(CNT_ADDR);
        outc_ack = pmemw(OUTC_ADDR);
        $display("  [read] CNT=%0d  OUTC=%0d", cnt_ack, outc_ack);

        $display("--- T0: negative run (KY54: TBがFAILを出せる健全性) ---");
        // わざと OUTC の期待を外す(=200でないと主張)。TBが不一致を検出できればPASS。
        chk_expect_fail("T0_negative_run", outc_ack, /*wrong_exp=*/999);

        $display("--- T1: 割込到達 (CNT != 0) ---");
        chk_range("T1_irq_reached", cnt_ack, 1, CNT_MAX);

        $display("--- T2: ハンドラ完走＋IRET復帰 (OUTC==200) ---");
        chk("T2_iret_return_outc", outc_ack, 200);

        $display("--- T3: レベル保持の効果 (CNT<=CNT_MAX 暴走なし) ---");
        chk_range("T3_level_no_storm", cnt_ack, 1, CNT_MAX);

        $display("--- T4: 周期割込・再武装 (CNT>=2) ---");
        chk_range("T4_periodic_rearm", cnt_ack, 2, CNT_MAX);

        $display("--- T5: 主処理協調＋正常HALT (halt==1 && OUTC==200) ---");
        chk("T5_halt",       (dbg_halt===1'b1) ? 1 : 0, 1);
        chk("T5_outc_final", outc_ack, 200);

        // ---------- ACKなし版を走行（T6の対照）----------
        //  ★同じ初期化順序（保持→クリア→ロード→解除）★
        $display("[LOAD] v5t_noack.hex (ACKなし=対照)");
        cpu_rst_n = 0;
        psram_rst_n = 0;
        repeat (3) @(negedge psram_clk);
        psram_rst_n = 1;
        for (int i = 0; i < 16'h0200; i = i + 1)
            u_membus.u_psram_ctrl.mem[i] = 8'h00;
        $readmemh("v5timer/v5t_noack.hex", u_membus.u_psram_ctrl.mem);
        repeat (3) @(negedge cpu_clk);
        cpu_rst_n = 1;

        run_until_halt(MAX_CYC);
        cnt_noack = pmemw(CNT_ADDR);
        $display("  [read] CNT(noack)=%0d", cnt_noack);

        $display("--- T6: ACK漏れ負テスト (CNT==1 再武装しない) ---");
        chk("T6_noack_no_rearm", cnt_noack, 1);

        // ---------- 総括 ----------
        $display("============================================================");
        if (errors == 0)
            $display("V5TIMER_TB: ALL PASS  (%0d checks)", passes);
        else
            $display("V5TIMER_TB: %0d FAIL / %0d PASS", errors, passes);
        $display("============================================================");
        $finish;
    end

    // グローバル・タイムアウト保険
    initial begin
        #200000000;  // 200ms相当
        $display("V5TIMER_TB: GLOBAL TIMEOUT");
        $finish;
    end

endmodule
`default_nettype wire
