// ============================================================
//  tb_cache_flush_poc.sv   v0.1   (2026-09-03 工程②-B ★段5-a★)
//
//  目的: 機能 A（FLUSH による全ライン無効化）の検証
//    F1 : ★複数ライン（index=0 / 中間 / 255）を載せ、FLUSH 後に
//          全ラインがミスすること★         ← 実装計画 v0.2 §4.1.2 / M-1
//    F2 : FLUSH の読出が常に 0（W1T）        ← 同 §4 表
//
//  ★F2 は mmio_stub の性質であり、本 TB（キャッシュ単体）では
//    検証できない。§4 の注記を参照（本 TB では F2 を扱わない）。★
//
//  判定器:
//    ★req_count（ps_req の立上り計数）を主★とする。
//    これは段4 の tb_cache_wt_poc で実測値 36 として運用済であり、
//    ★判定器そのものが一度検証されている★（実装計画 §4.1.3 / C-2）。
//    階層参照（u_cache.valid_r）は★補助★に留める。
//
//  TKT-V1 / T-A: バスアクセスは bus_tasks.svh を include して使う。
//                独自タスクを書かない。
//  設計根拠: v13_stage5_impl_plan_v0_2.md §2.2 A / §4.1.1 / §4.1.2
// ============================================================
`timescale 1ps/1ps

module tb_cache_flush_poc;

    localparam int PHYS_AW = 20;
    localparam int BLEN_W  = 6;
    localparam int IDX_W   = 8;      // 256 ライン

    // ---- クロック（本番と同じ 4MHz : 32MHz = 8:1）----
    logic cpu_clk = 1'b0;
    logic psram_clk = 1'b0;
    always #125000   cpu_clk   = ~cpu_clk;     // 4 MHz
    always #15625    psram_clk = ~psram_clk;   // 32 MHz

    logic rst_n = 1'b0;

    // ---- CPU 側（TB が駆動）----
    logic                 ccr_cen;
    logic                 ccr_flush;       // ★段5-a: 直接駆動する★
    logic [PHYS_AW-1:0]   cpu_addr;
    logic [7:0]           cpu_wdata;
    logic [7:0]           cpu_rdata;
    logic                 cpu_rd, cpu_wr;
    logic                 cpu_ready;

    // ---- cache <-> bridge ----
    logic [PHYS_AW-1:0]   br_addr;
    logic [7:0]           br_wdata, br_rdata;
    logic                 br_rd, br_wr, br_ready;

    // ---- bridge <-> psram_ctrl ----
    logic [PHYS_AW-1:0]   ps_addr;
    logic [7:0]           ps_wdata, ps_rdata;
    logic                 ps_we, ps_req, ps_ack;
    logic [BLEN_W-1:0]    burst_len;
    logic                 beat_valid;
    logic                 dbg_refresh_hit;

    // ============================================================
    //  DUT  ★ysd8800_cache_v0_4（段5-a）★
    // ============================================================
    ysd8800_cache_v0_4 #(
        .PHYS_AW(PHYS_AW), .BLEN_W(BLEN_W), .LINE_SIZE(32)
    ) u_cache (
        .cpu_clk(cpu_clk), .cpu_rst_n(rst_n),
        .ccr_cen_i(ccr_cen), .ccr_flush_pulse_i(ccr_flush),
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
    //  観測: req 回数（★主判定器★・段4 で検証済）
    // ============================================================
    integer            req_count;
    logic              ps_req_d;

    always_ff @(posedge psram_clk or negedge rst_n) begin
        if (!rst_n) begin
            req_count <= 0;
            ps_req_d  <= 1'b0;
        end else begin
            ps_req_d <= ps_req;
            if (ps_req & ~ps_req_d) req_count <= req_count + 1;
        end
    end

    // ============================================================
    //  タスク: 共有インクルード（T-A・独自実装しない）
    // ============================================================
    integer timeout_cnt;
`include "bus_tasks.svh"

    // ★探針（一時）: cen_rise / flush_req の発火を観測する★
    always @(posedge cpu_clk) begin
        if (u_cache.cen_rise)
            $display("      [probe] cen_rise=1 @%0t cen_i=%b cen_d=%b",
                     $time, u_cache.ccr_cen_i, u_cache.ccr_cen_d);
    end

    // ============================================================
    //  ★FLUSH パルス発行（1 cpu_clk 幅）★
    //    実装計画 §4.4.1: ccr_flush_pulse_i はバスではなく
    //    DUT の一入力ポートであり、規律1（bus_tasks 使用）の対象外。
    // ============================================================
    task automatic do_flush();
        begin
            @(negedge cpu_clk);
            ccr_flush = 1'b1;
            @(negedge cpu_clk);
            ccr_flush = 1'b0;
            @(negedge cpu_clk);
        end
    endtask

    // ============================================================
    //  ★F1 の対象ライン（M-1：index が散るように選ぶ）★
    //    index = addr[12:5]（32B ライン・256 ライン）
    //      A0 = 20'h00000 -> index = 0     ★下端★
    //      A1 = 20'h01000 -> index = 128   ★中間★
    //      A2 = 20'h01FE0 -> index = 255   ★上端（必須）★
    //    ★上端を必ず含める。ビット幅の書き間違いは上端で最初に露見する★
    // ============================================================
    localparam [PHYS_AW-1:0] A0 = 20'h00000;
    localparam [PHYS_AW-1:0] A1 = 20'h01000;
    localparam [PHYS_AW-1:0] A2 = 20'h01FE0;

    integer errors;
    integer rq0, rq1;
    logic [7:0] rd;

    // ★F5 用（C-8 のハング検出）★
    localparam int F5_WD = 400;      // ウォッチドッグ長（cpu_clk サイクル）
    logic       f5_done, f5_hang;
    logic [7:0] f5_rd;

    // 期待値: ★TB が明示的にプリロードした値★
    //   (2026-09-03) 当初は「psram_ctrl の初期値＝アドレス下位8bit」と
    //   ★仮定★していたが、mem は未初期化（x）であり誤りだった。
    //   ★TB が置いた値でなければ、期待値の根拠が無い★（KY78・原則136）。
    function [7:0] expv(input [PHYS_AW-1:0] a);
        expv = a[7:0] ^ 8'h5A;
    endfunction

    // ★PSRAM モデルのメモリをプリロードする★
    //   対象は F1 が触る 3 ライン（各 32B）に限る。
    integer pi;
    task automatic preload_line(input [PHYS_AW-1:0] base);
        begin
            for (pi = 0; pi < 32; pi = pi + 1)
                u_psram.mem[base + pi] = (base[7:0] + pi[7:0]) ^ 8'h5A;
        end
    endtask

    task automatic idx_report(input [PHYS_AW-1:0] a);
        $display("      addr=%05h -> index=%0d", a, a[12:5]);
    endtask

    initial begin
        errors   = 0;
        f5_hang  = 1'b0;
        f5_done  = 1'b0;
        ccr_cen  = 1'b0;
        ccr_flush= 1'b0;
        cpu_addr = '0; cpu_wdata = '0; cpu_rd = 1'b0; cpu_wr = 1'b0;

        repeat (4) @(posedge cpu_clk);
        rst_n = 1'b1;
        repeat (4) @(posedge cpu_clk);

        // ★PSRAM に既知の値を置く（期待値の根拠を TB 側に持つ）★
        preload_line(A0);
        preload_line(A1);
        preload_line(A2);

        $display("=============================================");
        $display(" tb_cache_flush_poc : 段5-a (機能A: FLUSH)");
        $display("=============================================");

        // ---- キャッシュ有効化（★negedge で駆動：レース回避★）----
        @(negedge cpu_clk);
        ccr_cen = 1'b1;
        repeat (2) @(posedge cpu_clk);

        // ==========================================================
        //  F1: 複数ラインを載せ、FLUSH 後に全ラインがミスすること
        // ==========================================================
        $display("[F1] 対象ライン（index が散ることを確認）:");
        idx_report(A0); idx_report(A1); idx_report(A2);

        // --- (1) 3本を載せる（初回は必ずミス＝フィル） ---
        do_read(A0, rd);
        if (rd !== expv(A0)) begin errors=errors+1; $display("[F1][FAIL] A0 data %02h != %02h", rd, expv(A0)); end
        do_read(A1, rd);
        if (rd !== expv(A1)) begin errors=errors+1; $display("[F1][FAIL] A1 data %02h != %02h", rd, expv(A1)); end
        do_read(A2, rd);
        if (rd !== expv(A2)) begin errors=errors+1; $display("[F1][FAIL] A2 data %02h != %02h", rd, expv(A2)); end

        // --- (2) 再読出で 3本ともヒットすること（載った証拠） ---
        rq0 = req_count;
        do_read(A0, rd);
        do_read(A1, rd);
        do_read(A2, rd);
        rq1 = req_count;
        if (rq1 !== rq0) begin
            errors = errors + 1;
            $display("[F1][FAIL] ★フラッシュ前なのにミスした★ req %0d -> %0d", rq0, rq1);
        end else begin
            $display("[F1][ OK ] フラッシュ前: 3本ともヒット (req 増加 0)");
        end
        // 補助: 階層参照
        $display("      (補助) valid[0]=%b valid[128]=%b valid[255]=%b",
                 u_cache.valid_r[0], u_cache.valid_r[128], u_cache.valid_r[255]);

        // --- (3) FLUSH 発行 ---
        do_flush();
        $display("[F1] FLUSH 発行");
        $display("      (補助) valid[0]=%b valid[128]=%b valid[255]=%b",
                 u_cache.valid_r[0], u_cache.valid_r[128], u_cache.valid_r[255]);

        // --- (4) ★全ラインがミスすること（req が 3 増える）★ ---
        rq0 = req_count;
        do_read(A0, rd);
        if (rd !== expv(A0)) begin errors=errors+1; $display("[F1][FAIL] A0 data after flush"); end
        do_read(A1, rd);
        if (rd !== expv(A1)) begin errors=errors+1; $display("[F1][FAIL] A1 data after flush"); end
        do_read(A2, rd);
        if (rd !== expv(A2)) begin errors=errors+1; $display("[F1][FAIL] A2 data after flush"); end
        rq1 = req_count;

        if ((rq1 - rq0) !== 3) begin
            errors = errors + 1;
            $display("[F1][FAIL] ★フラッシュ漏れ★ 期待 req +3 だが +%0d (%0d -> %0d)",
                     rq1-rq0, rq0, rq1);
            $display("           → valid_r[cur_idx] だけ / 下位ビットだけ をクリアしていないか");
        end else begin
            $display("[F1][PASS] ★全3ライン（index=0/128/255）がミス: req +3★");
        end

        // ==========================================================
        //  ★F3' : CEN=1 維持中はフラッシュしないこと（陰性対照）★
        //    実装計画 v0.2 §4.1.4 / M-2
        //    F1 の逆向きの試験。F1（フラッシュしたら必ずミス）と対にして
        //    ★判定器が両方向に感度を持つ★ことを示す（KY54）。
        // ==========================================================
        // 3本を載せ直す（直前の F1 でフラッシュ済のため）
        do_read(A0, rd); do_read(A1, rd); do_read(A2, rd);

        rq0 = req_count;
        do_read(A0, rd);
        if (rd !== expv(A0)) begin errors=errors+1; $display("[F3'][FAIL] A0 data"); end
        do_read(A1, rd);
        if (rd !== expv(A1)) begin errors=errors+1; $display("[F3'][FAIL] A1 data"); end
        do_read(A2, rd);
        if (rd !== expv(A2)) begin errors=errors+1; $display("[F3'][FAIL] A2 data"); end
        rq1 = req_count;

        if ((rq1 - rq0) !== 0) begin
            errors = errors + 1;
            $display("[F3'][FAIL] ★CEN=1 の定常状態でフラッシュしている★ req +%0d (期待 0)",
                     rq1-rq0);
            $display("            → 立上り検出が ccr_cen のレベル駆動になっていないか");
        end else begin
            $display("[F3'][PASS] ★CEN=1 維持中はフラッシュしない (req +0)★");
        end

        // ==========================================================
        //  ★F3 : CEN 0->1 の立上りで暗黙フラッシュ（D-B6）★
        // ==========================================================
        // いま 3本が載っている状態。CEN を落として上げ直す。
        // ★制御信号は negedge で駆動する★
        //   (2026-09-03) posedge で駆動すると DUT の always_ff と
        //   ★評価順序のレース★になり、ccr_cen_d が新値を捕まえて
        //   ★立上りが消える★（実測: cen_rise が一度も発火しなかった）。
        //   do_flush() が negedge 駆動で正しく動いていたのと同じ理由。
        @(negedge cpu_clk);
        ccr_cen = 1'b0;
        repeat (3) @(negedge cpu_clk);
        ccr_cen = 1'b1;
        repeat (3) @(posedge cpu_clk);
        $display("[F3] CEN 0->1 立上り実施");
        $display("      (補助) valid[0]=%b valid[128]=%b valid[255]=%b",
                 u_cache.valid_r[0], u_cache.valid_r[128], u_cache.valid_r[255]);

        rq0 = req_count;
        do_read(A0, rd);
        if (rd !== expv(A0)) begin errors=errors+1; $display("[F3][FAIL] A0 data"); end
        do_read(A1, rd);
        if (rd !== expv(A1)) begin errors=errors+1; $display("[F3][FAIL] A1 data"); end
        do_read(A2, rd);
        if (rd !== expv(A2)) begin errors=errors+1; $display("[F3][FAIL] A2 data"); end
        rq1 = req_count;

        if ((rq1 - rq0) !== 3) begin
            errors = errors + 1;
            $display("[F3][FAIL] ★CEN 立上りで暗黙フラッシュされていない★ req +%0d (期待 3)",
                     rq1-rq0);
            $display("           → D-B6 未実装。KY-B4: 古いタグが残り不整合を起こす");
        end else begin
            $display("[F3][PASS] ★CEN 立上りで全3ラインが無効化された (req +3)★");
        end

        // ==========================================================
        //  ★F4 : フィル途中の FLUSH でラインが復活しないこと★
        //    設計書 §7.6 / C-4 / KY-B9
        //    ★実装計画 v0.2 §3.2/§4.4.1：ccr_flush_pulse_i は
        //      バスではなく DUT の一入力ポートであり、
        //      直接駆動は規律1（bus_tasks 使用）の対象外である。★
        //      現行システムでは CPU が滞留するため到達不能であり、
        //      ★単体 TB のポート直接駆動でしか検証できない。★
        // ==========================================================
        do_flush();                       // まず全て無効化
        repeat (2) @(posedge cpu_clk);

        fork
            // スレッド1: A0 を読む（ミス→フィルが走る）
            begin
                do_read(A0, rd);
            end
            // スレッド2: フィル進行中に FLUSH を撃ち込む
            begin
                wait (u_cache.fill_active_r === 1'b1);
                @(negedge cpu_clk);
                ccr_flush = 1'b1;
                @(negedge cpu_clk);
                ccr_flush = 1'b0;
                $display("[F4] フィル進行中に FLUSH 発行 (fill_active=%b)",
                         u_cache.fill_active_r);
            end
        join

        repeat (2) @(posedge cpu_clk);
        $display("      (補助) fill_abort_r=%b valid[0]=%b",
                 u_cache.fill_abort_r, u_cache.valid_r[0]);

        // --- 復活していないこと ---
        if (u_cache.valid_r[0] !== 1'b0) begin
            errors = errors + 1;
            $display("[F4][FAIL] ★中止したはずのラインが復活した (valid[0]=1)★");
            $display("           → KY-B9: fill_abort_r が効いていない");
        end else begin
            $display("[F4][PASS] ★フィル中止: ラインは登録されなかった★");
        end

        // --- C-8 の先取り確認: 応答は返り、正しいバイトが返ること ---
        if (rd !== expv(A0)) begin
            errors = errors + 1;
            $display("[F4][FAIL] ★中止時に返ったバイトが誤り %02h != %02h★", rd, expv(A0));
        end else begin
            $display("[F4][ OK ] 中止時も正しいバイトが返った (C-8 先取り)");
        end

        // --- 外部から見てミスになること（主判定器） ---
        rq0 = req_count;
        do_read(A0, rd);
        rq1 = req_count;
        if ((rq1 - rq0) !== 1) begin
            errors = errors + 1;
            $display("[F4][FAIL] 中止後の再読出でミスしない req +%0d (期待 1)", rq1-rq0);
        end else begin
            $display("[F4][PASS] 中止後の再読出はミス (req +1)");
        end

        // ==========================================================
        //  ★F7 : 中止後、通常のフィルが再び成立すること★
        //    K-3（fill_abort_r のクリア漏れ）の検出
        //    ★N-1：F4 の後段に埋めず独立試験とする★
        //      （F4 が FAIL すると K-3 の確認まで到達しないため）
        //    症状: 以後すべてのフィルが登録されない
        //          ＝キャッシュが恒久的に無効化されるのと同じ
        // ==========================================================
        // 直前の do_read(A0) でフィルが走っている。登録されていれば
        // 次の読出はヒットするはず。
        rq0 = req_count;
        do_read(A0, rd);
        if (rd !== expv(A0)) begin errors=errors+1; $display("[F7][FAIL] A0 data"); end
        rq1 = req_count;

        if ((rq1 - rq0) !== 0) begin
            errors = errors + 1;
            $display("[F7][FAIL] ★中止後に通常フィルが成立していない req +%0d (期待 0)★",
                     rq1-rq0);
            $display("           → fill_abort_r のクリア漏れ (K-3)");
        end else begin
            $display("[F7][PASS] ★中止後も通常のフィルが成立する (再読出ヒット)★");
        end

        // ==========================================================
        //  ★F5 : 中止時も mem_ready が返り、正しいバイトが返ること★
        //    設計書 §7.6 C-8 / 実装計画 v0.2 §3・§4.2
        //
        //    ★「キャッシュへの登録中止」と「CPU への応答中止」は別である★
        //      ここで応答まで止めると mem_ready が返らず CPU がハングする。
        //      S_SUBOP のハング事例（cpu L858-865）と同型。
        //
        //    ★判定を「タイムアウトしなかったこと」に依存させない（§4.2）★
        //      do_read は 2000 サイクルで $finish するため、ハングすると
        //      ★判定結果が出力される前にシミュレーションが死ぬ★。
        //      よって独自のウォッチドッグで「返ったこと」を能動的に検査する。
        //      （これはバスプロトコルの再実装ではないため規律1 の対象外）
        // ==========================================================
        do_flush();
        repeat (2) @(posedge cpu_clk);

        f5_done = 1'b0;
        f5_rd   = 8'hXX;

        fork
            // スレッド1: A1 を読む（ミス→フィル）
            begin
                do_read(A1, f5_rd);
                f5_done = 1'b1;
            end
            // スレッド2: フィル中に FLUSH（＝中止させる）
            begin
                wait (u_cache.fill_active_r === 1'b1);
                @(negedge cpu_clk);
                ccr_flush = 1'b1;
                @(negedge cpu_clk);
                ccr_flush = 1'b0;
            end
            // スレッド3: ★ウォッチドッグ★
            begin
                repeat (F5_WD) @(posedge cpu_clk);
                if (!f5_done) begin
                    f5_hang = 1'b1;
                end
            end
        join_none
        // ★join_any は使わない★
        //   (2026-09-03) join_any だと最初に終わるスレッド（FLUSH 発行）で
        //   即座に抜け、disable fork が★読出スレッドを殺してしまう★。
        //   実測: f5_done が立たず偽のハング判定になった。
        //   決着条件を明示的に待つ。
        wait (f5_done || f5_hang);
        repeat (2) @(posedge cpu_clk);
        disable fork;

        if (f5_hang || !f5_done) begin
            errors = errors + 1;
            $display("[F5][FAIL] ★mem_ready が返らない＝CPU ハング★ (%0d cyc 待機)", F5_WD);
            $display("           → 登録の中止と応答の中止を混同していないか (C-8)");
        end else begin
            $display("[F5][PASS] ★中止時も mem_ready が返った★");
            if (f5_rd !== expv(A1)) begin
                errors = errors + 1;
                $display("[F5][FAIL] ★返却バイトが誤り %02h != %02h★", f5_rd, expv(A1));
            end else begin
                $display("[F5][PASS] ★中止時も正しいバイトが返った (%02h)★", f5_rd);
            end
        end

        // ==========================================================
        //  結果
        // ==========================================================
        $display("---------------------------------------------");
        if (errors == 0)
            $display("=== tb_cache_flush_poc (段5-a) : ALL PASS ===");
        else
            $display("=== tb_cache_flush_poc (段5-a) : %0d FAIL ===", errors);
        $display("  total psram req count = %0d", req_count);
        $finish;
    end

    // セーフティ・タイムアウト
    initial begin
        #200_000_000;
        $display("[TIMEOUT] tb_cache_flush_poc");
        $finish;
    end

endmodule
// ============ 以上 tb_cache_flush_poc.sv v0.1 ============
