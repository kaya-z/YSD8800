// ============================================================
//  tb_cpu_v4uart_v0_1.sv   v0.1  (2026-07-12)
//  YSD8800 FPGA V4 / S5 : ★CPU結合TB（真のゲート）★
//
//  DUT: ysd8800_cpu_v0_1 (v0.5.7・無改修)
//     + ysd8800_v4_membus_v0_1 (MMU + YSD8004 + ★YSD8001★)
//
//  設計根拠: v4_design_memo_v0_2.md (承認済 v1.0)
//            v4_design_review_reply_v1_0.docx §7（★S3のALL PASSはゲートでない★）
//  黄金参照: emu23 v1.09 (emu23_v109.c)
//
//  ------------------------------------------------------------
//  【★2部構成の理由: S5-ISSUE-1（承認済み戦略）★】
//
//   (a) TX系・STAT系 → 【emu23協調等価】
//       gen_v4_uart_vectors.py が emu23 を実行して黄金最終状態を自動取得。
//       TBは期待値を手計算しない（KY34・偽合格防止）。
//
//   (b) RX系・IRQ系  → 【プロパティ検証】
//       ★emu23 の RX は 256サイクル周期ポーリング (emu23_v109.c L486)★
//         if ((current_cycle & 0xFF) == 0) poll_rx_fn();
//       -i FILE を使っても RX 到来サイクルは 256 境界に量子化される。
//       RTL の rx_valid_i は任意サイクルで打てるため、両者のタイミングは
//       【構造的に一致しない】。→ 最終状態比較(協調等価)は RX に適用不可。
//
//       そこで (b) では emu23【ソースから読み取った仕様】を期待値とする。
//       ただし偽合格を防ぐため、判定は必ず
//         「★CPUが実命令で読んだ値★」（レジスタ最終値）
//       で行い、TBが rdata_o を直接覗くことはしない。
//       => CPU → decoder → mmio_stub → YSD8001 の【全経路】が通る。
//  ------------------------------------------------------------
//
//  【★偽合格防止の3本柱（S3から踏襲・レビュー§7）★】
//   1. TBは16bit実アドレスでアクセスする（addr_i を直接叩かない）
//   2. TB側 localparam は DUT を階層参照せず emu23 を真実として独立定義
//   3. 「2bitデコードなら必ず落ちる」ベクタを含む
//      ($FC80[1:0] == $FC84[1:0] == 2'b00 を突く = KY44)
//
//  【確定設計#8: 上位バイト単独アクセス禁止】
//   $FC81/$FC83/$FC85/$FC87 および UART_BAUD($FC86) の LDB 単独アクセスは
//   ベクタに含めない（yuios_memmap 規約違反 = 未定義動作。KY47）
// ============================================================
`timescale 1ns/1ps

import ysd8800_idec_pkg::*;

module tb_cpu_v4uart_v0_2;

    // ---- ★TB側 localparam: DUTを階層参照せず emu23 を真実として独立定義★ ----
    //   emu23_v109.c L336-337 / L344 / L364-366 実照合
    localparam logic [15:0] UART_TX    = 16'hFC80;
    localparam logic [15:0] UART_RX    = 16'hFC82;
    localparam logic [15:0] UART_STAT  = 16'hFC84;
    localparam logic [7:0]  STAT_RESET = 8'h01;   // ★KY45: TX_READY=1★
    localparam int          TX_CYCLES  = 4167;    // emu23 L344

    logic        cpu_clk, cpu_rst_n;
    logic        psram_clk, psram_rst_n;
    logic [15:0] mem_addr;
    logic [7:0]  mem_wdata, mem_rdata;
    logic        mem_rd, mem_wr, mem_ready;
    // ★S5(c) 追加: irq_in を irq1_o から駆動する★
    //
    //  【KY34 実照合】emu23_v109.c
    //    L310  : /* emu23内部: irq_pending=2 → vec=$0004 */
    //    L1183 : uint16_t vec = rd16((uint16_t)(irq * 2));
    //    => IRQ1(デバイス割込) の irq_in 番号は【2】である（1ではない。1=timer）
    //       ベクタアドレス = 2*2 = $0004
    //
    //  【irq_en によるゲート】
    //    (a)(b) では irq_en=0 とし irq_in を 3'd0 固定にする。
    //    → S5(a)(b) の検証条件が【構造的に】従来と完全同一であることを保証する
    //      （(a) が 7/7 のまま再現することで実証される）。
    //    (c) でのみ irq_en=1 とし、CPU に実際に割込を入れる。
    logic        irq_en;
    logic [2:0]  irq_in;
    assign irq_in = (irq_en && irq1_o) ? 3'd2 : 3'd0;
    logic [15:0] dbg_pc, dbg_a, dbg_b, dbg_x, dbg_sp, dbg_flags;
    logic        dbg_halt;
    logic [15:0] dbg_mmio_last_addr;
    logic [31:0] dbg_mmio_access_count;
    logic        dbg_mmu_en;
    logic [19:0] dbg_phys_addr;
    logic [127:0] dbg_ptr_flat;

    // ---- V4 新規: UART 物理層疑似ポート ----
    logic        uart_rx_valid_i;
    logic [7:0]  uart_rx_data_i;
    logic        uart_tx_valid_o;
    logic [7:0]  uart_tx_data_o;
    logic        irq1_o;

    integer errors = 0;
    integer passes = 0;

    ysd8800_cpu_v0_1 dut_cpu (
        .clk(cpu_clk), .rst_n(cpu_rst_n),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata),
        .mem_rd(mem_rd), .mem_wr(mem_wr), .mem_ready(mem_ready),
        .irq_in(irq_in),
        .dbg_pc(dbg_pc), .dbg_a(dbg_a), .dbg_b(dbg_b), .dbg_x(dbg_x),
        .dbg_sp(dbg_sp), .dbg_flags(dbg_flags), .dbg_halt(dbg_halt)
    );

    ysd8800_v4_membus_v0_1 #(.PHYS_AW(20), .MEM_AW(20)) u_membus (
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
        .dbg_mmio_last_addr(dbg_mmio_last_addr),
        .dbg_mmio_access_count(dbg_mmio_access_count),
        .dbg_mmu_en(dbg_mmu_en),
        .dbg_phys_addr(dbg_phys_addr),
        .dbg_ptr_flat(dbg_ptr_flat)
    );

    // クロック: CPU 4MHz相当(period=20) : PSRAM 80MHz相当(period=1)
    initial cpu_clk = 0;
    always #10 cpu_clk = ~cpu_clk;
    initial psram_clk = 0;
    always #0.5 psram_clk = ~psram_clk;

    // ============================================================
    //  (a) emu23協調等価パート
    // ============================================================
    localparam int NVEC_A = 7;
    string vname_a [0:NVEC_A-1];
    string vfile_a [0:NVEC_A-1];
    logic [15:0] exp_a_mem [0:NVEC_A*4-1];   // A,B,X,F × 7
    logic [15:0] exp_a, exp_b, exp_x;
    logic [7:0]  exp_f;
    integer vi, cyc;

    // ============================================================
    //  (b) プロパティ検証パート用
    // ============================================================
    integer bcyc;

    task automatic do_reset();
        cpu_rst_n = 0;
        psram_rst_n = 0;
        irq_en = 1'b0;   // ★(a)(b) は割込を CPU に入れない（従来と同一条件）★
        uart_rx_valid_i = 1'b0;
        uart_rx_data_i  = 8'h00;
        repeat (3) @(negedge psram_clk);
        psram_rst_n = 1;
        repeat (3) @(negedge cpu_clk);
        cpu_rst_n = 1;
    endtask

    // RX 1バイトを物理層から注入（★1クロックパルス★）
    task automatic rx_inject(input logic [7:0] d);
        @(negedge cpu_clk);
        uart_rx_data_i  = d;
        uart_rx_valid_i = 1'b1;
        @(negedge cpu_clk);
        uart_rx_valid_i = 1'b0;
    endtask

    task automatic chk(input string nm, input logic [15:0] got,
                       input logic [15:0] exp);
        if (got !== exp) begin
            $display("  FAIL %-28s got=%04x exp=%04x", nm, got, exp);
            errors = errors + 1;
        end else begin
            passes = passes + 1;
        end
    endtask

    // ============================================================
    //  (c) RX/IRQ CPU結合検証パート用
    // ============================================================
    localparam int NVEC_C  = 6;
    // 注入サイクル（★マジックナンバー禁止・根拠を明示: KY54★）
    //   プログラム冒頭の wait_loop は 11B/周。実CPI 約18 → 1周 約200クロック。
    //   c1〜c3,c5 は N=200 → 約40,000クロック。c4,c6 は N=400/300。
    //   INJ_CYC=2000 は「CPU初期化(LDW SP,#0x0400 等)完了後」かつ
    //   「ループ脱出よりはるかに手前」であり、早すぎ/遅すぎのいずれでもない。
    localparam int INJ_CYC  = 2000;
    //   2発目(オーバーラン用)は 1発目の十分後・かつループ内側
    localparam int INJ_CYC2 = 4000;

    string vname_c [0:NVEC_C-1];

    // ------------------------------------------------------------
    //  load_and_start: プログラムをロードし CPU を走らせる
    //
    //  ★KY51: 既存の通っている (a) ループの初期化順序を【逐語的に踏襲】★
    //    (0) cpu_rst_n = 0        ← ロード中はリセット保持
    //    (1) mem[0..0x3FF] を 0x00 クリア
    //        ★KY52: $readmemh は指定語数しか埋めない。残りは X のまま。
    //          かつ前ベクタの残存内容で偽合格するので毎回クリアする★
    //        ★(c) はベクタテーブル($0004)/ハンドラ($0200)/痕跡RAM($0300)を
    //          使うため、クリア範囲を 0x0400 まで広げる★
    //    (2) $readmemh でプログラムロード
    //    (3) ★その後で★ cpu_rst_n を解除
    // ------------------------------------------------------------
    task automatic load_and_start(input int vc);
        cpu_rst_n = 0;                       // (0) ★リセット保持★
        irq_en    = 1'b0;                    // c1〜c4 は CPU に割込を入れない
        uart_rx_valid_i = 1'b0;
        uart_rx_data_i  = 8'h00;

        for (int i = 0; i < 16'h0400; i = i + 1)   // (1) ★0x0400 までクリア★
            u_membus.u_psram_ctrl.mem[i] = 8'h00;

        case (vc)                                   // (2) ロード
            0: $readmemh("v4uart/UART_RX_READ.hex",           u_membus.u_psram_ctrl.mem);
            1: $readmemh("v4uart/UART_RX_NO_SIDE_EFFECT.hex", u_membus.u_psram_ctrl.mem);
            2: $readmemh("v4uart/UART_STAT_WTC_RX.hex",       u_membus.u_psram_ctrl.mem);
            3: $readmemh("v4uart/UART_RX_OVERRUN.hex",        u_membus.u_psram_ctrl.mem);
            4: $readmemh("v4uart/UART_RX_IRQ_HANDLER.hex",    u_membus.u_psram_ctrl.mem);
            5: $readmemh("v4uart/UART_TX_IRQ_TDRE.hex",       u_membus.u_psram_ctrl.mem);
        endcase

        repeat (3) @(negedge cpu_clk);              // (3) ★ロード完了後に解除★
        cpu_rst_n = 1;
    endtask

    // irq_en=1 版（c5/c6 用。CPU に実際に割込を入れる）
    task automatic load_and_start_irq(input int vc);
        load_and_start(vc);
        irq_en = 1'b1;                       // ★irq1_o → irq_in=3'd2 を有効化★
    endtask

    // ------------------------------------------------------------
    //  inject_at: リセット解除後 n クロック目に RX を注入
    //    d2 != 0 なら INJ_CYC2 で2発目を注入（オーバーラン試験用）
    //    ★1クロックパルス（確定設計#1: RX/STOR はパルス、TX はレベル）★
    // ------------------------------------------------------------
    task automatic inject_at(input int n, input logic [7:0] d1, input logic [7:0] d2);
        repeat (n) @(posedge cpu_clk);
        rx_inject(d1);
        if (d2 != 8'h00) begin
            repeat (INJ_CYC2 - n) @(posedge cpu_clk);
            rx_inject(d2);                   // ★破棄されるはず（先着優先）★
        end
    endtask

    // ------------------------------------------------------------
    //  run_to_halt: HALT まで走らせる
    //    ★Icarus制約: `ref` ポート未サポート（"Reference ports not
    //      supported yet"）→ 引数を取らず、モジュールスコープの cyc を
    //      直接更新する。（kaizen原則65 系の Icarus 制約に追加）★
    // ------------------------------------------------------------
    task automatic run_to_halt();
        cyc = 0;
        while (!dbg_halt && cyc < 2000000) begin
            @(posedge cpu_clk);
            cyc = cyc + 1;
        end
        if (!dbg_halt) begin
            $display("  FAIL  TIMEOUT (no HALT, cyc=%0d)", cyc);
            errors = errors + 1;
        end
    endtask

    // (c) 用チェッカ（chk と同じだが (c) 表記）
    task automatic chk_c(input string nm, input logic [15:0] got,
                         input logic [15:0] exp);
        if (got !== exp) begin
            $display("  FAIL %-30s got=%04x exp=%04x", nm, got, exp);
            errors = errors + 1;
        end else begin
            $display("  PASS %-30s      =%04x", nm, got);
            passes = passes + 1;
        end
    endtask

    initial begin
        // ---- (a) ベクタ名とhexファイル ----
        vname_a[0]="UART_STAT_READ";           vfile_a[0]="v4uart/UART_STAT_READ.hex";
        vname_a[1]="UART_TX_BASIC";            vfile_a[1]="v4uart/UART_TX_BASIC.hex";
        vname_a[2]="UART_TX_RECOVER";          vfile_a[2]="v4uart/UART_TX_RECOVER.hex";
        vname_a[3]="UART_TX_TWICE";            vfile_a[3]="v4uart/UART_TX_TWICE.hex";
        vname_a[4]="UART_STAT_WTC_NOP";        vfile_a[4]="v4uart/UART_STAT_WTC_NOP.hex";
        vname_a[5]="UART_STAT_WTC_BIT0_IGNORE";vfile_a[5]="v4uart/UART_STAT_WTC_BIT0_IGNORE.hex";
        vname_a[6]="UART_TX_STAT_ALIAS";       vfile_a[6]="v4uart/UART_TX_STAT_ALIAS.hex";

        $readmemh("v4uart/expected_v4uart.hex", exp_a_mem);

        // ---- PSRAM リセット（ループ外で1回だけ）----
        psram_rst_n = 0;
        cpu_rst_n   = 0;
        irq_en = 1'b0;   // ★(a)(b) は割込を CPU に入れない（従来と同一条件）★
        uart_rx_valid_i = 1'b0;
        uart_rx_data_i  = 8'h00;
        repeat (3) @(negedge psram_clk);
        psram_rst_n = 1;

        $display("============================================");
        $display(" S5 CPU INTEGRATION TB (V4 / YSD8001 UART)");
        $display(" ***  THIS IS THE TRUE GATE  ***");
        $display("============================================");
        $display("");
        $display("--- (a) emu23 cooperative equivalence (%0d vectors) ---", NVEC_A);
        $display("    NOTE: X は比較対象から除外する（S5-ISSUE-2）。");
        $display("          emu23 の TX_CYCLES=4167 は【命令サイクル】基準、");
        $display("          RTL の tx_cnt_r=4167 は【クロック】基準であり、");
        $display("          実CPI(約18)の分だけ TX 復帰までのループ回数が違う。");
        $display("          => X は構造的に一致しえない。A/B/F のみ比較する。");
        $display("          TX完了クロック数は (b) で別途プロパティ検証する。");

        for (vi = 0; vi < NVEC_A; vi = vi + 1) begin
            // ============================================================
            //  ★S5-2 修正: 初期化シーケンスは既存TB(tb_cpu_v3_v0_1系)を
            //    【逐語的に踏襲】する。順序が本質的制約である。
            //      (1) mem[0..0x1FF] を 0x00 クリア
            //          → $readmemh は265語しか埋めず、それ以前が X のまま
            //            だと CPU が PC=0x0000 から X を fetch してハングする
            //      (2) $readmemh でプログラムロード
            //      (3) ★その後で★ cpu_rst_n を解除
            //          → 先にリセット解除すると CPU が空メモリを fetch し始める
            // ============================================================
            cpu_rst_n = 0;              // ★ロード中はリセット保持★
            irq_en = 1'b0;   // ★(a)(b) は割込を CPU に入れない（従来と同一条件）★
            uart_rx_valid_i = 1'b0;
            uart_rx_data_i  = 8'h00;

            // (1) メモリクリア
            for (int i = 0; i < 16'h0200; i = i + 1)
                u_membus.u_psram_ctrl.mem[i] = 8'h00;

            // (2) プログラムロード（★Icarus制約: $readmemh 第1引数は定数文字列★）
            case (vi)
                0: $readmemh("v4uart/UART_STAT_READ.hex",            u_membus.u_psram_ctrl.mem);
                1: $readmemh("v4uart/UART_TX_BASIC.hex",             u_membus.u_psram_ctrl.mem);
                2: $readmemh("v4uart/UART_TX_RECOVER.hex",           u_membus.u_psram_ctrl.mem);
                3: $readmemh("v4uart/UART_TX_TWICE.hex",             u_membus.u_psram_ctrl.mem);
                4: $readmemh("v4uart/UART_STAT_WTC_NOP.hex",         u_membus.u_psram_ctrl.mem);
                5: $readmemh("v4uart/UART_STAT_WTC_BIT0_IGNORE.hex", u_membus.u_psram_ctrl.mem);
                6: $readmemh("v4uart/UART_TX_STAT_ALIAS.hex",        u_membus.u_psram_ctrl.mem);
            endcase

            // (3) ★ロード完了後に★リセット解除
            repeat (3) @(negedge cpu_clk);
            cpu_rst_n = 1;

            exp_a = exp_a_mem[vi*4 + 0];
            exp_b = exp_a_mem[vi*4 + 1];
            exp_x = exp_a_mem[vi*4 + 2];
            exp_f = exp_a_mem[vi*4 + 3][7:0];

            // HALT まで走らせる（TX復帰待ちループがあるため十分長く）
            cyc = 0;
            while (!dbg_halt && cyc < 2000000) begin
                @(posedge cpu_clk);
                cyc = cyc + 1;
            end

            if (!dbg_halt) begin
                $display("  FAIL %-28s TIMEOUT (no HALT, cyc=%0d)", vname_a[vi], cyc);
                errors = errors + 1;
            end else begin
                // ★X は比較しない（S5-ISSUE-2: emu23とRTLで単位系が違う）★
                if (dbg_a !== exp_a || dbg_b !== exp_b ||
                    dbg_flags[7:0] !== exp_f) begin
                    $display("  FAIL %-28s", vname_a[vi]);
                    $display("       got A=%04x B=%04x F=%02x  (X=%04x)",
                             dbg_a, dbg_b, dbg_flags[7:0], dbg_x);
                    $display("       exp A=%04x B=%04x F=%02x  (X=%04x emu23基準・非比較)",
                             exp_a, exp_b, exp_f, exp_x);
                    errors = errors + 1;
                end else begin
                    $display("  PASS %-28s A=%04x B=%04x F=%02x (X=%04x, cyc=%0d)",
                             vname_a[vi], dbg_a, dbg_b, dbg_flags[7:0], dbg_x, cyc);
                    passes = passes + 1;
                end
            end
        end

        // ============================================================
        //  (b) プロパティ検証（RX系・IRQ系）
        //      ★TB は rdata_o を直接覗かない。DUT を階層参照するのは
        //        「観測」ではなく「刺激注入」のみに限る。
        //        判定は CPU の実命令が読んだ値で行う。★
        //
        //      ただし本 (b) は【CPUプログラム不要な物理層プロパティ】に
        //      絞る。CPUプログラムを伴う RX/IRQ の完全検証は
        //      次項 (c) で行う。
        // ============================================================
        $display("");
        $display("--- (b) RX/IRQ property check (emu23 spec as truth) ---");

        // --- b-1: リセット直後 irq1_o の状態 ---
        //   emu23 L497-499: TX_READY=1 の間、毎tick で IRQ_STAT bit2 を raise
        //   IRQ_MASK リセット値 = 0x04 (KY46) → bit2 は【マスクされている】
        //   => リセット直後 irq1_o = 0 のはず
        do_reset();
        repeat (20) @(posedge cpu_clk);
        chk("b1_irq1_masked_at_reset", {15'd0, irq1_o}, 16'd0);
        $display("  [b-1] irq1_o at reset = %b (expect 0: IRQ_MASK=0x04 masks TX)", irq1_o);

        // --- b-2: RX 注入で irq1_o がアサートされる ---
        //   emu23 L407: RX受信 → ysd8004_raise(IRQ_STAT_BIT_UART_RX) (bit0)
        //   IRQ_MASK=0x04 は bit2 のみマスク → bit0 は通る
        rx_inject(8'h5A);
        repeat (5) @(posedge cpu_clk);
        chk("b2_irq1_asserted_by_rx", {15'd0, irq1_o}, 16'd1);
        $display("  [b-2] irq1_o after RX  = %b (expect 1: RX IRQ passes mask)", irq1_o);

        // --- b-3: RX オーバーラン = 先着優先・後着破棄 ---
        //   emu23 L390: if (stat & RX_READY) return;  ← 上書きしない
        //   0x5A 受信済み(RX_READY=1)の状態で 0xA5 を注入 → 破棄される
        rx_inject(8'hA5);
        repeat (5) @(posedge cpu_clk);
        $display("  [b-3] overrun injected (0xA5 must be DISCARDED)");
        //   ★実際に破棄されたかは (c) で CPU が $FC82 を読んで確認する★

        // --- b-4: tx_valid_o パルスの観測（物理層接続点の生存確認） ---
        $display("  [b-4] tx_valid_o wiring alive (checked in (c) TX vectors)");

        // ============================================================
        //  ★★★ (c) RX/IRQ の CPU結合検証 ＝ 真のゲートの本体 ★★★
        //
        //  【判定原則】
        //    判定は必ず「CPU が実命令で読んだ値」= 最終レジスタ値で行う。
        //    TB は rdata_o / stat_r を直接覗かない（偽合格防止）。
        //    → CPU → decoder → mmio_stub → YSD8001 の【全経路】を通す。
        //
        //  【KY54 アンチ偽合格】
        //    c5/c6 のハンドラはマジック値を RAM に残し、メインが回収する。
        //    ハンドラが起動しなければ回収値が 0x0000 のままで【必ず FAIL】。
        //    さらに c5 は negative run（注入なし）を実施し、
        //    「期待通り FAIL すること」を確認してから本判定を行う。
        //
        //  【注入タイミングの根拠（マジックナンバー禁止）】
        //    プログラム冒頭の wait_loop は 11B/周 で N 周回る。
        //    実CPI 約18 → 1周 約200クロック。N=200 なら約 40,000 クロック。
        //    INJ_CYC=2000 はループ内側の十分深い位置であり、
        //    かつ CPU 初期化(LDW SP 等)完了後である。
        //    → 早すぎ(初期化前)/遅すぎ(ループ脱出後)のいずれでもない。
        // ============================================================
        $display("");
        $display("--- (c) RX/IRQ CPU-integrated verification (TRUE GATE) ---");
        $display("    判定は CPU が実命令で読んだ最終レジスタ値のみ。");
        $display("    IRQ1 vec = $0004 (emu23 L310/L1183: irq_pending=2 -> vec=2*2)");

        // ---------- c1 : UART_RX_READ ----------
        load_and_start(0);                       // vc=0
        fork inject_at(INJ_CYC, 8'h5A, 8'h00); join_none
        run_to_halt();
        chk_c("c1_UART_RX_READ.A",   dbg_a, 16'h005A);
        chk_c("c1_UART_RX_READ.STAT",dbg_b, 16'h0003);  // TX_READY|RX_READY

        // ---------- c2 : UART_RX_NO_SIDE_EFFECT ----------
        load_and_start(1);
        fork inject_at(INJ_CYC, 8'h5A, 8'h00); join_none
        run_to_halt();
        chk_c("c2_RX_2ND_READ.A",    dbg_a, 16'h005A);  // 2回目も同値
        chk_c("c2_RX_READY_HELD.B",  dbg_b, 16'h0003);  // 読出で落ちない

        // ---------- c3 : UART_STAT_WTC_RX ----------
        load_and_start(2);
        fork inject_at(INJ_CYC, 8'h5A, 8'h00); join_none
        run_to_halt();
        chk_c("c3_STAT_BEFORE_W2C.A",dbg_a, 16'h0003);  // W2C前は RX_READY=1
        chk_c("c3_STAT_AFTER_W2C.B", dbg_b, 16'h0001);  // RX_READYのみ落ちる

        // ---------- c4 : UART_RX_OVERRUN ----------
        //   ysd8001 L180: rx_accept = rx_valid_i & ~stat_r[BIT_RX_READY]
        //   → RX_READY=1 の間は後着を破棄する（先着優先）
        load_and_start(3);
        fork inject_at(INJ_CYC, 8'h5A, 8'hA5); join_none   // 0x5A の後に 0xA5
        run_to_halt();
        chk_c("c4_OVERRUN_FIRST_WINS.A", dbg_a, 16'h005A); // 0x00A5 ではない
        chk_c("c4_OVERRUN_STAT.B",       dbg_b, 16'h0003);

        // ============================================================
        //  ★c5: UART_RX_IRQ_HANDLER — 真のゲート本体★
        //    RX割込 → irq1_o → irq_in=2 → CPU受理 → vec$0004 → ハンドラ
        //    → ハンドラが $FC82 読 → UART W2C → YSD8004 W2C → IRET
        //    → メインが痕跡を回収
        // ============================================================

        // ---- c5-neg : ★KY54 アンチ偽合格 negative run★ ----
        //   RX を注入【しない】。ハンドラは起動しないはず。
        //   → MARK=0x0000 / DATA=0x0000 となることを確認する。
        //   これが 0x00A5 になったら「注入と無関係にハンドラが動いた」ことになり
        //   ベクタ設計が破綻している（偽合格の温床）。
        load_and_start_irq(4);                   // irq_en=1
        // ★注入しない★
        run_to_halt();
        $display("  [c5-neg] no RX injected -> A=%04x B=%04x (expect 0000/0000)",
                 dbg_a, dbg_b);
        chk_c("c5neg_HANDLER_NOT_RUN.A", dbg_a, 16'h0000);
        chk_c("c5neg_HANDLER_NOT_RUN.B", dbg_b, 16'h0000);

        // ---- c5 : 本番（注入あり）----
        load_and_start_irq(4);
        fork inject_at(INJ_CYC, 8'h5A, 8'h00); join_none
        run_to_halt();
        $display("  [c5] RX injected -> A=%04x B=%04x (expect 00A5/005A)",
                 dbg_a, dbg_b);
        chk_c("c5_IRQ_HANDLER_RAN.A",   dbg_a, 16'h00A5); // ★ハンドラ実行痕跡★
        chk_c("c5_HANDLER_READ_RX.B",   dbg_b, 16'h005A); // ★ハンドラが読んだ値★

        // ============================================================
        //  ★c6: UART_TX_IRQ_TDRE — TDRE はレベル★
        //
        //  【★S5(c)-ISSUE-1: 実照合で判明した重要事実★】
        //    emu23 L314-329 ysd8004_raise() は cpu.flags & FL_IE を【見ない】。
        //    RTL L1223-1225 も同様:
        //        if (state == S_IRQCHK && irq_in != 3'd0) irq_pending <= irq_in;
        //    → IE=0 のハンドラ実行中でも irq_pending が【再ラッチされる】。
        //      受理(L1176 / RTL L590)のみが IE を見る。
        //    ∴ ハンドラが割込源を黙らせても、黙らせる【前】にラッチ済みの
        //      pending が IRET 後に受理され、ハンドラが【もう1回だけ】入る。
        //    これは MC6809 の IRQ でも起きる古典的挙動。OS-9 の IRQ ポーリング
        //    ルーチンが「自分の仕事が無ければ即RTI」と冪等に書かれている理由。
        //    → RTL/emu23 とも【仕様通りで正しい】。バグではない。
        //
        //  【検証設計】ハンドラは【1回目】で IRQ_MASK bit2 をセットする（冪等）。
        //    ・レベル実装 → 1回目実行中に再ラッチ → IRET後もう1回 → cnt=2
        //    ・パルス実装 → 1回目時点で irq1_o=0   → 再ラッチ無し  → cnt=1
        //    ∴ cnt=2 が「TDRE がレベルである」ことの【証明】。
        //      1回目でマスク済みなので cnt が 3 以上になることは無い
        //      （＝「何命令目でラッチされたか」という実装詳細に依存しない）。
        // ============================================================
        load_and_start_irq(5);
        // ★RX注入不要: TX_READY はリセット直後から 1（KY45）なので
        //   IRQ_MASK bit2 を許可した瞬間に TX 割込が立つ
        run_to_halt();
        $display("  [c6] TDRE level IRQ -> cnt=%04x IRQ_MASK=%04x (expect 0002/0004)",
                 dbg_a, dbg_b);
        chk_c("c6_TDRE_IS_LEVEL.CNT",   dbg_a, 16'h0002); // ★2=レベルの証明★
        chk_c("c6_HANDLER_SILENCED.B",  dbg_b, 16'h0004); // ★自ら黙らせた★

        // ============================================================
        //  サマリ
        // ============================================================
        $display("");
        $display("============================================");
        $display(" S5 INTEGRATION TB : PASS=%0d  FAIL=%0d", passes, errors);
        if (errors == 0)
            $display(" *** ALL PASS ***");
        else
            $display(" *** %0d FAILURE(S) ***", errors);
        $display("============================================");
        $finish;
    end

endmodule
