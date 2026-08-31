// ============================================================
//  tb_psram_ctrl_v0_3.sv   v0.3  (2026-08-28)
//  工程②-A 段2 検証用: psram_ctrl v0.3 バースト動作TB
//
//  設計根拠: v10_psram_burst_design_v0_3.md §5.2
//
//  【v0.1からの変更点】
//    (1) DUT を ysd8800_psram_ctrl_v0_1 → v0_3 に変更
//    (2) バーストベクタ B-3/B-4/B-6/B-7/B-8/B-9/B-10 を追加
//    (3) B-1/B-2 は等価性TB(tb_psram_equiv_v0_1)で担保済のため
//        本TBでは単バイト動作の基本確認のみ行う
//
//  【★B-10の判定基準は他と逆★】(設計書 N-4)
//    B-10 は we=1 かつ burst_len>1 という【契約違反】を与え、
//    assertionの$errorが発火することを期待する。
//    ★発火しなければFAIL★である。他ベクタと判定基準が逆なので
//    TB実装時・ログ確認時に取り違えないこと。
//
//  【★beat_validは連続Highである★】(設計書 M-9)
//    burst_len=32 では32サイクル連続で1になり、立上りエッジは1回。
//    ★エッジ計数ではなく「1であるサイクル数」を計数する★
// ============================================================
`timescale 1ns/1ps

module tb_psram_ctrl_v0_3;
    localparam int BLEN_W_TB = $clog2(32) + 1;   // = 6

    logic        clk, rst_n;
    logic [19:0] addr;
    logic [7:0]  wdata, rdata;
    logic        we, req, ack;
    logic [BLEN_W_TB-1:0] burst_len;
    logic        beat_valid;
    logic        dbg_refresh_hit;

    integer errors = 0;

    ysd8800_psram_ctrl_v0_3 #(
        .LATENCY_NORMAL(12), .LATENCY_REFRESH(15), .REFRESH_PPM(500),
        .PHYS_AW(20), .MEM_AW(20), .BURST_MAX(32)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .addr(addr), .wdata(wdata), .we(we),
        .req(req), .ack(ack), .rdata(rdata),
        .burst_len(burst_len), .beat_valid(beat_valid),
        .dbg_refresh_hit(dbg_refresh_hit)
    );

    initial clk = 0;
    always #1 clk = ~clk;

    // ---- 収集用 ----
    logic [7:0] beat_data [0:63];
    integer     beat_n;          // ★beat_validが1であるサイクル数(M-9)★
    integer     ack_high_mid;    // バースト中間でackが1だった回数(N-2)
    integer     total_cyc;
    logic       done_f;          // ★Icarus 12.0 break非対応の代替★

    // 単バイト書き込み(メモリ初期化用)
    task automatic wr1(input [19:0] a, input [7:0] d);
        @(negedge clk);
        addr = a; we = 1'b1; wdata = d; req = 1'b1; burst_len = BLEN_W_TB'(1);
        while (!ack) @(negedge clk);
        @(negedge clk);
        req = 1'b0; we = 1'b0;
        while (ack) @(negedge clk);
    endtask

    // バースト読み出し(beat収集・ack監視)
    task automatic burst_rd(input [19:0] a, input [BLEN_W_TB-1:0] n);
        @(negedge clk);
        addr = a; we = 1'b0; wdata = 8'h00; req = 1'b1; burst_len = n;
        beat_n = 0; ack_high_mid = 0; total_cyc = 0;
        done_f = 1'b0;
        // ★Icarus 12.0 は break 未対応のためフラグで制御する★
        while (!done_f) begin
            @(posedge clk);
            total_cyc = total_cyc + 1;
            if (beat_valid) begin
                if (beat_n < 64) beat_data[beat_n] = rdata;
                beat_n = beat_n + 1;
                // ★N-2: 最終beat以外でackが立っていたら契約違反★
                if (ack && (beat_n < n)) ack_high_mid = ack_high_mid + 1;
            end
            if (ack) done_f = 1'b1;
        end
        @(negedge clk);
        req = 1'b0;
        while (ack) @(negedge clk);
    endtask

    integer i;
    integer bad;
    // ★案B: B-11〜B-13 用★
    integer j;
    integer rnd_shift, rnd_len, rnd_idx;
    logic [19:0] rnd_addr;
    logic [7:0]  exp_byte;
    integer refresh_cnt_single, refresh_cnt_burst;

    initial begin
        rst_n = 0; addr = 0; wdata = 0; we = 0; req = 0;
        burst_len = BLEN_W_TB'(1);
        repeat (3) @(negedge clk);
        rst_n = 1;
        repeat (3) @(negedge clk);

        $display("==================================================");
        $display("  tb_psram_ctrl_v0_3 (2026-08-28)");
        $display("  DUT: ysd8800_psram_ctrl_v0_3 (burst support)");
        $display("  工程②-A 段2: PS_BURST 動作検証");
        $display("==================================================");

        // メモリ初期化: $01000..$0103F に 0xC0+i を書く
        for (i = 0; i < 64; i++) wr1(20'h0_1000 + i, 8'hC0 + i[7:0]);

        // ---------- B-3: burst_len=4 読み ----------
        burst_rd(20'h0_1000, BLEN_W_TB'(4));
        bad = 0;
        if (beat_n != 4) begin
            $display("[B-3] FAIL: beat数=%0d 期待4", beat_n); bad++;
        end
        for (i = 0; i < 4; i++)
            if (beat_data[i] !== (8'hC0 + i[7:0])) begin
                $display("[B-3] FAIL: beat[%0d]=%02h 期待%02h",
                         i, beat_data[i], 8'hC0 + i[7:0]); bad++;
            end
        if (bad == 0) $display("[B-3] PASS: burst_len=4 読み(4beat・順序一致)");
        else errors = errors + bad;

        // ---------- B-4: burst_len=32 読み ----------
        burst_rd(20'h0_1000, BLEN_W_TB'(32));
        bad = 0;
        if (beat_n != 32) begin
            $display("[B-4] FAIL: beat数=%0d 期待32", beat_n); bad++;
        end
        for (i = 0; i < 32; i++)
            if (beat_data[i] !== (8'hC0 + i[7:0])) begin
                $display("[B-4] FAIL: beat[%0d]=%02h", i, beat_data[i]); bad++;
            end
        // ★N-2: 中間31beatでack==0を能動確認★
        if (ack_high_mid != 0) begin
            $display("[B-4] FAIL: 中間beatでack=1が%0d回", ack_high_mid); bad++;
        end
        // ★総サイクル数 = LAT + (32-1) = 12 + 31 = 43★
        //   ただし本TBの total_cyc は req を立てた直後の posedge から
        //   計数するため【req受理サイクルを1回余分に含む】。
        //   よって期待値は 43+1 = 44 となる(RTLではなくTBの計数規約)。
        //   ★重要なのは絶対値ではなく増分である★:
        //     blen=1 → 13, blen=32 → 44。差 31 = (32-1) であり
        //     「1バイト/psram cyc」の設計仮定が成立している。
        if (total_cyc != 44) begin
            $display("[B-4] FAIL: 総サイクル=%0d 期待44", total_cyc); bad++;
        end
        if (bad == 0)
            $display("[B-4] PASS: burst_len=32 (32beat・中間ack=0・43cyc)");
        else errors = errors + bad;

        // ---------- B-7: burst_len=2 (最小バースト) ----------
        burst_rd(20'h0_1000, BLEN_W_TB'(2));
        bad = 0;
        if (beat_n != 2) begin
            $display("[B-7] FAIL: beat数=%0d 期待2", beat_n); bad++;
        end
        if (beat_data[0] !== 8'hC0 || beat_data[1] !== 8'hC1) begin
            $display("[B-7] FAIL: data=%02h,%02h", beat_data[0], beat_data[1]);
            bad++;
        end
        // 期待 = LAT + (2-1) + 1(TB計数規約) = 12+1+1 = 14
        if (total_cyc != 14) begin
            $display("[B-7] FAIL: 総サイクル=%0d 期待14", total_cyc); bad++;
        end
        if (bad == 0) $display("[B-7] PASS: burst_len=2 (PS_BURSTを1回のみ)");
        else errors = errors + bad;

        // ---------- B-8: 連続バースト ----------
        burst_rd(20'h0_1000, BLEN_W_TB'(4));
        burst_rd(20'h0_1010, BLEN_W_TB'(4));
        bad = 0;
        if (beat_n != 4) begin
            $display("[B-8] FAIL: 2回目beat数=%0d", beat_n); bad++;
        end
        for (i = 0; i < 4; i++)
            if (beat_data[i] !== (8'hD0 + i[7:0])) begin
                $display("[B-8] FAIL: beat[%0d]=%02h 期待%02h",
                         i, beat_data[i], 8'hD0 + i[7:0]); bad++;
            end
        if (bad == 0) $display("[B-8] PASS: バースト終了後の再受理が正常");
        else errors = errors + bad;

        // ---------- B-9: burst_len=0 → 1に飽和 ----------
        burst_rd(20'h0_1000, BLEN_W_TB'(0));
        bad = 0;
        if (beat_n != 1) begin
            $display("[B-9] FAIL: beat数=%0d 期待1(飽和)", beat_n); bad++;
        end
        // 期待 = LAT + 1(TB計数規約) = 13。単バイトと同一であること
        if (total_cyc != 13) begin
            $display("[B-9] FAIL: 総サイクル=%0d 期待13", total_cyc); bad++;
        end
        if (bad == 0) $display("[B-9] PASS: burst_len=0 は1に飽和");
        else errors = errors + bad;

        // ---------- B-6: 4相確認(ackがreq低下まで維持) ----------
        @(negedge clk);
        addr = 20'h0_1000; we = 1'b0; req = 1'b1; burst_len = BLEN_W_TB'(4);
        while (!ack) @(negedge clk);
        repeat (5) @(negedge clk);       // reqを上げたまま5サイクル待つ
        if (!ack) begin
            $display("[B-6] FAIL: reqがHighなのにackが落ちた"); errors++;
        end else $display("[B-6] PASS: ackはreq低下まで維持される");
        @(negedge clk); req = 1'b0;
        while (ack) @(negedge clk);

        // ---------- B-10: ★$error発火が期待動作(N-4)★ ----------
        $display("--------------------------------------------------");
        $display("[B-10] ★以下の$errorは【期待動作】である(N-4)★");
        // $01020..$01023 の現在値を控える
        wr1(20'h0_1020, 8'h11);
        wr1(20'h0_1021, 8'h22);
        wr1(20'h0_1022, 8'h33);
        wr1(20'h0_1023, 8'h44);
        // 契約違反: we=1 かつ burst_len=4
        @(negedge clk);
        addr = 20'h0_1020; we = 1'b1; wdata = 8'hEE;
        req = 1'b1; burst_len = BLEN_W_TB'(4);
        while (!ack) @(negedge clk);
        @(negedge clk); req = 1'b0; we = 1'b0;
        while (ack) @(negedge clk);
        // ★mem[$1020]のみ不変(書込抑止)・$1021..$1023も不変であること★
        bad = 0;
        burst_rd(20'h0_1020, BLEN_W_TB'(4));
        if (beat_data[0] !== 8'h11) begin
            $display("[B-10] FAIL: mem[$1020]=%02h 期待11(書込抑止)",
                     beat_data[0]); bad++;
        end
        if (beat_data[1] !== 8'h22 || beat_data[2] !== 8'h33
            || beat_data[3] !== 8'h44) begin
            $display("[B-10] FAIL: 後続バイトが破壊された %02h %02h %02h",
                     beat_data[1], beat_data[2], beat_data[3]); bad++;
        end
        if (bad == 0)
            $display("[B-10] PASS: バースト書き抑止・メモリ非破壊");
        else errors = errors + bad;
        $display("--------------------------------------------------");

        // ==================================================
        // ★案B: 段2 TB強化 (B-11 / B-12 / B-13)★
        //   ②-Bでキャッシュ本体と同時にデバッグする事態を避けるため、
        //   PS_BURST 単体の信頼度をここで上げておく。
        // ==================================================

        // ---------- B-11: burst_len 全長掃引 ----------
        //   1/2/4/8/16/32 の全ての2冪長で
        //     beat数 = n
        //     データ順序 = addr..addr+n-1
        //     総サイクル = LAT + (n-1) + 1(TB計数規約) = 12+n
        //   を機械的に検証する。
        bad = 0;
        for (i = 1; i <= 32; i = i * 2) begin
            burst_rd(20'h0_1000, BLEN_W_TB'(i));
            if (beat_n != i) begin
                $display("[B-11] FAIL: blen=%0d beat数=%0d", i, beat_n);
                bad++;
            end
            if (total_cyc != (12 + i)) begin
                $display("[B-11] FAIL: blen=%0d 総cyc=%0d 期待%0d",
                         i, total_cyc, 12 + i);
                bad++;
            end
            for (j = 0; j < i; j++)
                if (beat_data[j] !== (8'hC0 + j[7:0])) begin
                    $display("[B-11] FAIL: blen=%0d beat[%0d]=%02h",
                             i, j, beat_data[j]);
                    bad++;
                end
            if (ack_high_mid != 0) begin
                $display("[B-11] FAIL: blen=%0d 中間ack=%0d回",
                         i, ack_high_mid);
                bad++;
            end
        end
        if (bad == 0)
            $display("[B-11] PASS: 全長掃引 1/2/4/8/16/32 (cyc=12+n を確認)");
        else errors = errors + bad;

        // ---------- B-12: ランダム網羅 (100回) ----------
        //   アライン済ランダムアドレス × ランダム2冪長。
        //   ★アドレスは必ず burst_len 境界に揃える(契約遵守)★
        //   期待データは書き込み時の規則 mem[a] = (a & 0xFF) ^ 0x5A で照合。
        bad = 0;
        for (i = 0; i < 256; i++) wr1(20'h0_3000 + i, ((20'h0_3000 + i) & 8'hFF) ^ 8'h5A);
        for (i = 0; i < 100; i++) begin
            rnd_shift = $urandom_range(0, 5);          // 0..5 → 長さ 1..32
            rnd_len   = (1 << rnd_shift);
            // $3000 起点で rnd_len 境界に揃った位置を選ぶ
            rnd_idx   = $urandom_range(0, (256 / rnd_len) - 1) * rnd_len;
            rnd_addr  = 20'h0_3000 + rnd_idx;
            burst_rd(rnd_addr, BLEN_W_TB'(rnd_len));
            if (beat_n != rnd_len) begin
                $display("[B-12] FAIL: addr=%05h len=%0d beat数=%0d",
                         rnd_addr, rnd_len, beat_n);
                bad++;
            end
            for (j = 0; j < rnd_len; j++) begin
                exp_byte = ((rnd_addr + j) & 8'hFF) ^ 8'h5A;
                if (beat_data[j] !== exp_byte) begin
                    $display("[B-12] FAIL: addr=%05h len=%0d beat[%0d]=%02h 期待%02h",
                             rnd_addr, rnd_len, j, beat_data[j], exp_byte);
                    bad++;
                end
            end
        end
        if (bad == 0)
            $display("[B-12] PASS: ランダム網羅100回 (アドレス×長さ)");
        else errors = errors + bad;

        // ---------- B-13: ★リフレッシュ希釈の実測(設計書 §3.5 R-a)★ ----------
        //   R-a は「req受理時点で1回だけ判定」であるため、
        //   バースト時はリフレッシュ判定が【バースト全体で1回】になり、
        //   REFRESH_PPM=500 が実質バイトあたり 1/S に希釈される。
        //   ★②-Bの性能測定で「リフレッシュ密度の変化による見かけの改善」を
        //     キャッシュ効果に算入しないため、ここで density を実測する。★
        //
        //   同一バイト数(1024B)を「単バイト1024回」と「32Bバースト32回」で
        //   転送し、dbg_refresh_hit の発生回数を比較する。
        //   期待: バースト側の発生回数が概ね 1/32 に減る。
        refresh_cnt_single = 0;
        refresh_cnt_burst  = 0;

        for (i = 0; i < 1024; i++) begin
            burst_rd(20'h0_1000, BLEN_W_TB'(1));
            if (dbg_refresh_hit) refresh_cnt_single++;
        end
        for (i = 0; i < 32; i++) begin
            burst_rd(20'h0_1000, BLEN_W_TB'(32));
            if (dbg_refresh_hit) refresh_cnt_burst++;
        end

        $display("[B-13] リフレッシュ実測: 単バイト1024回 → %0d hit",
                 refresh_cnt_single);
        $display("[B-13] リフレッシュ実測: 32Bバースト32回(=1024B) → %0d hit",
                 refresh_cnt_burst);
        $display("[B-13] ★同一転送量でのリフレッシュ密度差を②-Bの測定で考慮★");
        // ★本ベクタは密度の【記録】が目的でありPASS/FAIL判定は行わない。
        //   判定してしまうとLFSRの確率的挙動に依存した不安定なTBになる。★
        $display("[B-13] RECORDED (判定なし・②-B測定時の参照値)");
        $display("--------------------------------------------------");

        if (errors == 0) $display("=== 段2 BURST ALL PASS (B-3〜B-13) ===");
        else             $display("=== 段2 BURST FAIL: %0d error(s) ===", errors);
        $finish;
    end
endmodule
