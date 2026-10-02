//==============================================================
//  bus_tasks.svh   v0.1   (2026-09-02)
//--------------------------------------------------------------
//  ★TKT-V1 / T-A：バスアクセスタスクの共有インクルード★
//  設計書: v12_tb_contract_design_v0_4.md §4
//
//  ★各 TB は本ファイルを `include し、do_read / do_write を
//    独自に実装しないこと。★
//
//  【なぜ共有するのか】
//    段4 で TB 独自実装が ready 検出の 1cyc 後に要求を下げ、
//    ★cdc_bridge の suppress_r(抑止幅ちょうど 1 cpu cyc)を抜けて
//      同一要求が再送され、blen_r / we が混線した。★
//    DUT は正しいのに落ち、切り分けに数時間を要した（KY78）。
//    ★契約の実装が2箇所あると、片方が間違う。★
//
//  【契約 C-α'】
//    ready の次サイクルで要求を継続する場合、それは
//    ★新しい要求（アドレスまたは種別が変化）★でなければならない。
//    ★同一アドレス・同一種別の保持は契約違反★。
//    → ★ready を検出した「その」サイクルで要求を下げる。★
//       1cyc 遅らせてはならない。
//
//  【契約 C-β（書込側）】
//    psram_ctrl は we も wdata も★ポート直接参照★する
//    （受理時にラッチしない）。よって do_write は
//    ★wr / wdata を ready 成立まで保持し続けなければならない。★
//    ★wdata は wr を下げた「後」に変更する。★
//
//  【本ファイルだけでは不十分】
//    T-A は「実装を1箇所にする」だけであり、★その1箇所が誤れば
//    全 TB が誤る。★ DUT 側に常設した契約アサーション（T-B）が
//    受け止める。★T-A と T-B は相互補完であり、片方では不十分。★
//
//  【要求される TB 側の宣言】
//    cpu_clk / cpu_addr / cpu_wdata / cpu_rdata /
//    cpu_rd / cpu_wr / cpu_ready / timeout_cnt
//    および localparam PHYS_AW
//==============================================================

    // ----------------------------------------------------------
    //  do_read : 1 バイト読出
    // ----------------------------------------------------------
    task automatic do_read(input [PHYS_AW-1:0] a, output [7:0] d);
        begin
            @(negedge cpu_clk);
            cpu_addr = a; cpu_rd = 1'b1; cpu_wr = 1'b0;
            timeout_cnt = 0;
            // ready を見てから同サイクルのデータを取り込む
            while (cpu_ready !== 1'b1) begin
                @(negedge cpu_clk);
                timeout_cnt = timeout_cnt + 1;
                if (timeout_cnt > 2000) begin
                    $display("[FATAL] read timeout @addr=$%05x", a);
                    $finish;
                end
            end
            d = cpu_rdata;
            // ★ready と同一サイクルで下げる（実CPU と同じ）★
            //   1cyc 遅れると suppress_r(1cyc) を抜けて再送される。
            cpu_rd = 1'b0;
        end
    endtask

    // ----------------------------------------------------------
    //  do_write : 1 バイト書込
    // ----------------------------------------------------------
    task automatic do_write(input [PHYS_AW-1:0] a, input [7:0] d);
        begin
            @(negedge cpu_clk);
            // ★addr / wdata / wr を同時に立てる★
            cpu_addr = a; cpu_wdata = d; cpu_wr = 1'b1; cpu_rd = 1'b0;
            timeout_cnt = 0;
            // ★ready 成立まで 3 つとも保持する★
            while (cpu_ready !== 1'b1) begin
                @(negedge cpu_clk);
                timeout_cnt = timeout_cnt + 1;
                if (timeout_cnt > 2000) begin
                    $display("[FATAL] write timeout @addr=$%05x", a);
                    $finish;
                end
            end
            // ★ready と同一サイクルで下げる★
            cpu_wr = 1'b0;
            // ★wdata は wr を下げた「後」でなければ変更しない★
            //   (本タスクでは変更しないが、呼出側も同様に扱うこと)
        end
    endtask

//============ 以上 bus_tasks.svh v0.1 ============
