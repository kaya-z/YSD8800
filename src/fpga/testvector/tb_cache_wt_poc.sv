//==============================================================
// tb_cache_wt_poc.sv   v0.1  (2026-08-31 工程②-B 段3 ゲート3)
//
//   目的（設計メモ v11_cache_stage3_design_memo_v0_2.md §4 ゲート3）:
//     (1) offset 0〜31 の★全32パターン★で、要求バイトが正しく返ること
//     (2) ★psram_ctrl 内部 blen_r が 32 になっていることを階層参照で観測★
//         ※ blen_r=1 でも 1 バイトは正しく返るため、
//            ★返却バイトの正しさだけでは M-1 の欠陥を検出できない★
//     (3) ヒット時に PSRAM へ要求が出ないこと（req 数の観測）
//     (4) CEN=0 でバイパスが成立すること
//
//   DUT: ysd8800_cache_v0_3 + ysd8800_cdc_bridge_v0_4 + ysd8800_psram_ctrl_v0_3
//        （CPU は使わず、TB が cache の CPU 側ポートを直接叩く）
//
//   ★本 TB は判定ロジック自体も疑う（原則136）★
//     ゲート(2) は「出力バイトを証拠にしない」ために設けた観測項目である。
//==============================================================
`timescale 1ps/1ps

module tb_cache_wt_poc;

    localparam int PHYS_AW = 20;
    localparam int BLEN_W  = 6;

    // ---- クロック（本番と同じ 4MHz : 32MHz = 8:1）----
    logic cpu_clk = 1'b0;
    logic psram_clk = 1'b0;
    always #125000   cpu_clk   = ~cpu_clk;     // 4 MHz
    always #15625    psram_clk = ~psram_clk;   // 32 MHz

    logic rst_n = 1'b0;

    // ---- CPU 側（TB が駆動）----
    logic                 ccr_cen;
    logic [PHYS_AW-1:0]   cpu_addr;
    logic [7:0]           cpu_wdata;
    logic [7:0]           cpu_rdata;
    logic                 cpu_rd, cpu_wr;
    logic                 cpu_ready;

    // ---- cache ⇔ bridge ----
    logic [PHYS_AW-1:0]   br_addr;
    logic [7:0]           br_wdata, br_rdata;
    logic                 br_rd, br_wr, br_ready;

    // ---- bridge ⇔ psram_ctrl ----
    logic [PHYS_AW-1:0]   ps_addr;
    logic [7:0]           ps_wdata, ps_rdata;
    logic                 ps_we, ps_req, ps_ack;
    logic [BLEN_W-1:0]    burst_len;
    logic                 beat_valid;
    logic                 dbg_refresh_hit;

    // ============================================================
    //  DUT
    // ============================================================
    ysd8800_cache_v0_3 #(
        .PHYS_AW(PHYS_AW), .BLEN_W(BLEN_W), .LINE_SIZE(32)
    ) u_cache (
        .cpu_clk(cpu_clk), .cpu_rst_n(rst_n),
        .ccr_cen_i(ccr_cen), .ccr_flush_pulse_i(1'b0),
        .cpu_phys_addr_i(cpu_addr), .cpu_wdata_i(cpu_wdata),
        .cpu_rdata_o(cpu_rdata),
        .cpu_rd_i(cpu_rd), .cpu_wr_i(cpu_wr), .cpu_ready_o(cpu_ready),
        .br_phys_addr_o(br_addr), .br_wdata_o(br_wdata),
        .br_rdata_i(br_rdata),
        .br_rd_o(br_rd), .br_wr_o(br_wr), .br_ready_i(br_ready),
        .burst_len_o(burst_len),
        .psram_clk(psram_clk), .psram_rst_n(rst_n),
        .beat_valid_i(beat_valid), .psram_rdata_i(ps_rdata)
    );

    ysd8800_cdc_bridge_v0_4 #(.PHYS_AW(PHYS_AW)) u_bridge (
        .cpu_clk(cpu_clk), .cpu_rst_n(rst_n),
        .cpu_phys_addr(br_addr), .cpu_mem_wdata(br_wdata),
        .cpu_mem_rdata(br_rdata),
        .cpu_mem_rd(br_rd), .cpu_mem_wr(br_wr), .cpu_mem_ready(br_ready),
        .psram_clk(psram_clk), .psram_rst_n(rst_n),
        .psram_addr(ps_addr), .psram_wdata(ps_wdata), .psram_we(ps_we),
        .psram_req(ps_req), .psram_ack(ps_ack), .psram_rdata(ps_rdata)
    );

    ysd8800_psram_ctrl_v0_3 #(
        .LATENCY_NORMAL(12), .LATENCY_REFRESH(15), .REFRESH_PPM(0),
        .PHYS_AW(PHYS_AW), .MEM_AW(20), .BURST_MAX(32)
    ) u_psram (
        .clk(psram_clk), .rst_n(rst_n),
        .addr(ps_addr), .wdata(ps_wdata), .we(ps_we),
        .req(ps_req), .ack(ps_ack), .rdata(ps_rdata),
        .burst_len(burst_len), .beat_valid(beat_valid),
        .dbg_refresh_hit(dbg_refresh_hit)
    );

    // ============================================================
    //  観測: blen_r（★M-1 の必須検証★）と req 回数
    // ============================================================
    logic [BLEN_W-1:0] blen_max_seen;
    integer            req_count;
    logic              ps_req_d;

    always_ff @(posedge psram_clk or negedge rst_n) begin
        if (!rst_n) begin
            blen_max_seen <= '0;
            req_count     <= 0;
            ps_req_d      <= 1'b0;
        end else begin
            ps_req_d <= ps_req;
            if (ps_req & ~ps_req_d) req_count <= req_count + 1;
            if (u_psram.blen_r > blen_max_seen) blen_max_seen <= u_psram.blen_r;
        end
    end

    // ============================================================
    //  タスク: 1バイト読出（ready まで待つ）
    // ============================================================
    integer timeout_cnt;
    // ★TKT-V1 / T-A: バスアクセスタスクは共有インクルードから取り込む★
    //   (2026-09-02) 独自実装を廃止。実装を1箇所に集約する。
    //   設計書: v12_tb_contract_design_v0_4.md §4
`include "bus_tasks.svh"

    // ============================================================
    //  本体
    // ============================================================
    integer i, errors, req_before, req_after;
    logic [7:0] rd, exp;
    localparam [PHYS_AW-1:0] BASE = 20'h02000;   // ライン境界（下位5bit=0）

    initial begin
        errors = 0;
        cpu_addr = '0; cpu_wdata = '0; cpu_rd = 0; cpu_wr = 0; ccr_cen = 1'b0;

        // メモリ初期化: mem[a] = a[7:0] ^ 8'h5A （アドレス依存の非自明値）
        for (i = 0; i < 4096; i = i + 1)
            u_psram.mem[BASE + i] = (i[7:0] ^ 8'h5A);

        repeat (10) @(posedge cpu_clk);
        rst_n = 1'b1;
        repeat (10) @(posedge cpu_clk);

        $display("=============================================");
        $display(" tb_cache_core_poc  v0.1  (段3 ゲート3)");
        $display("=============================================");

        // ---------- T1: CEN=0 バイパス ----------
        ccr_cen = 1'b0;
        do_read(BASE + 20'd7, rd);
        exp = (8'd7 ^ 8'h5A);
        if (rd !== exp) begin
            $display("[T1][FAIL] CEN=0 bypass: got=$%02x exp=$%02x", rd, exp);
            errors = errors + 1;
        end else
            $display("[T1][PASS] CEN=0 bypass read  ($%02x)", rd);
        if (blen_max_seen !== BLEN_W'(1)) begin
            $display("[T1][FAIL] CEN=0 blen_r=%0d (must be 1)", blen_max_seen);
            errors = errors + 1;
        end else
            $display("[T1][PASS] CEN=0 blen_r = 1  ★G-0 の前提★");

        // ---------- T2: CEN=1 offset 全32パターン ----------
        ccr_cen = 1'b1;
        repeat (4) @(posedge cpu_clk);

        for (i = 0; i < 32; i = i + 1) begin
            // ★毎回別ラインを使い、必ずミス→フィルを起こす★
            //   ライン先頭 = BASE + i*32、要求 offset = i
            do_read(BASE + i*32 + i, rd);
            exp = ((i*32 + i) ^ 8'h5A);
            if (rd !== exp) begin
                $display("[T2][FAIL] offset=%0d: got=$%02x exp=$%02x", i, rd, exp);
                errors = errors + 1;
            end
        end
        if (errors == 0)
            $display("[T2][PASS] offset 0..31 all 32 patterns OK");

        // ---------- T3: ★blen_r = 32 の観測（M-1 必須）★ ----------
        if (blen_max_seen !== BLEN_W'(32)) begin
            $display("[T3][FAIL] ★blen_r=%0d (expected 32)★", blen_max_seen);
            $display("           → ラインフィルがバーストになっていない。");
            $display("             D-C1 の fill_sel が初回に間に合っていない疑い。");
            errors = errors + 1;
        end else
            $display("[T3][PASS] ★blen_r = 32 を観測（バースト成立）★");

        // ---------- T4: ヒット時に PSRAM 要求が出ないこと ----------
        req_before = req_count;
        for (i = 0; i < 8; i = i + 1) begin
            do_read(BASE + 20'd0*32 + i, rd);   // 既にフィル済みライン
            exp = (i[7:0] ^ 8'h5A);
            if (rd !== exp) begin
                $display("[T4][FAIL] hit read off=%0d: got=$%02x exp=$%02x", i, rd, exp);
                errors = errors + 1;
            end
        end
        req_after = req_count;
        if (req_after !== req_before) begin
            $display("[T4][FAIL] hit issued %0d PSRAM req (must be 0)",
                     req_after - req_before);
            errors = errors + 1;
        end else
            $display("[T4][PASS] cache hit issues no PSRAM request");

        // ---------- T5: ★ライトスルー：書込→読出のコヒーレンシ★ ----------
        //   ★本テストの主眼は「値」ではなく「再フィルが起きないこと」★
        //     段3(v0_2) は書込時にラインを無効化するため、
        //     直後の読出で★再フィルが発生し値も正しくなる★。
        //     したがって値だけを見ると段3 と段4 を区別できない。
        //     ★req 増分 0★ が、キャッシュ側を実際に更新した証拠になる。
        do_write(BASE + 20'd3, 8'hA5);
        req_before = req_count;
        do_read (BASE + 20'd3, rd);
        req_after = req_count;
        if (rd !== 8'hA5) begin
            $display("[T5][FAIL] write-then-read: got=$%02x exp=$A5", rd);
            $display("           → キャッシュ側のバイト更新が効いていない");
            errors = errors + 1;
        end else if (req_after !== req_before) begin
            $display("[T5][FAIL] ★re-fill occurred (%0d req) → 段3 の無効化のまま★",
                     req_after - req_before);
            errors = errors + 1;
        end else
            $display("[T5][PASS] ★write-through update ($A5) ＋ 再フィル無し★");

        // ---------- T6: ★書込ヒットでも PSRAM に必ず書かれる（ライトスルー）★
        //   ★キャッシュだけ更新して PSRAM に書かない（＝ライトバック）★
        //     になっていないことを、★PSRAM 実体を直接見て★確認する。
        //   T5 が PASS でも T6 は独立に落ち得る（出力を証拠にしない）。
        if (u_psram.mem[BASE + 20'd3] !== 8'hA5) begin
            $display("[T6][FAIL] ★PSRAM mem[$%05x]=$%02x (expected $A5)★",
                     BASE + 3, u_psram.mem[BASE + 20'd3]);
            $display("           → ライトスルーになっていない（書き漏れ）");
            errors = errors + 1;
        end else
            $display("[T6][PASS] ★PSRAM also updated ($A5) ＝ write-through★");

        // ---------- T7: ★ノーライトアロケート（書込ミスで充填しない）★ ----------
        //   未充填ラインへ書き、PSRAM は更新されるがキャッシュには
        //   載らない（＝直後の読出でミスが起きる＝PSRAM req が増える）こと。
        req_before = req_count;
        do_write(BASE + 20'h800, 8'h3C);        // 未使用領域（未充填ライン）
        if (u_psram.mem[BASE + 20'h800] !== 8'h3C) begin
            $display("[T7][FAIL] write-miss not reflected to PSRAM");
            errors = errors + 1;
        end
        req_after = req_count;
        if (req_after === req_before) begin
            $display("[T7][FAIL] write-miss issued no PSRAM req");
            errors = errors + 1;
        end
        // 直後の読出：ノーライトアロケートならミス→フィルが起きる
        req_before = req_count;
        do_read(BASE + 20'h800, rd);
        req_after = req_count;
        if (rd !== 8'h3C) begin
            $display("[T7][FAIL] read-after-write-miss: got=$%02x exp=$3C", rd);
            errors = errors + 1;
        end else if (req_after === req_before) begin
            $display("[T7][FAIL] ★no fill occurred → write-allocate している★");
            errors = errors + 1;
        end else
            $display("[T7][PASS] no-write-allocate ＋ read-after-write OK ($3C)");

        $display("---------------------------------------------");
        if (errors == 0) $display("=== tb_cache_core_poc : ALL PASS ===");
        else             $display("=== tb_cache_core_poc : %0d FAIL ===", errors);
        $display("  observed blen_max=%0d / psram req count=%0d",
                 blen_max_seen, req_count);
        $finish;
    end

    // 保険
    initial begin
        #2_000_000_000;
        $display("[FATAL] global timeout");
        $finish;
    end

endmodule
