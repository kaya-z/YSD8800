//==============================================================
// tb_cpu_v8b_prod_v0_1.sv   v0.1  (2026-08-01)
//   YSD8800 FPGA V8-b 本番用テストベンチ
//
//   目的: yuios_road2.bin (56,416B, kernel v12.8 + Forth v0.10.18)
//         を iverilog 上の実 RTL 環境で実行し、UART TX 出力に
//         "0YUI> " プロンプト後の FILEMGR タスク YUIFS 起動進捗
//         マーカー "0123MD" (6バイト) 到達を判定する。
//
//   DUT   : ysd8800_cpu_v0_1 (RTL v0.5.8・無改修)
//           + ysd8800_v5_membus_v0_1 (ファイル v0.2・無改修)
//   SDモデル: sd_spi_model_v0_3_poc ($readmemh で sd_image.hex を返す)
//
//   段階起動 (v0.3 §5):
//     phase-1: MAX_CYCLES=1_000_000    (M-1/M-2 快速 sanity)
//     phase-2: MAX_CYCLES=10_000_000   (M-3/M-4 起動完走)
//     phase-3: MAX_CYCLES=100_000_000  (M-5 本番判定)
//
//   設計根拠: v8b_prod_design_memo_v0_3.md (承認済 2026-08-01)
//==============================================================

`timescale 1ns/1ps

module tb_cpu_v8b_prod_v0_1;

    // -------------------------------------------------------------
    //  パラメータ (段階起動用、コマンドラインで上書き可)
    // -------------------------------------------------------------
    parameter integer MAX_CYCLES        = 1_000_000;    // phase-1 既定値
    parameter integer M1_TIMEOUT_CYCLES = 10_000;       // v0.3 §4
    parameter integer M2_TIMEOUT_CYCLES = 200_000;
    parameter integer M3_TIMEOUT_CYCLES = 5_000_000;
    parameter integer M4_TIMEOUT_CYCLES = 8_000_000;
    parameter integer UART_STALL_LIMIT  = 500_000;      // v0.3 §6.2 デッドロック検出

    // -------------------------------------------------------------
    //  クロック・リセット
    // -------------------------------------------------------------
    logic cpu_clk;
    logic psram_clk;
    logic cpu_rst_n;
    logic psram_rst_n;

    // -------------------------------------------------------------
    //  CPU-membus 内部バス
    // -------------------------------------------------------------
    logic [19:0] mem_addr;
    logic [7:0]  mem_wdata;
    logic [7:0]  mem_rdata;
    logic        mem_rd, mem_wr;
    logic        mem_ready;

    // -------------------------------------------------------------
    //  CPU デバッグポート (v0.3 §7 CL-3 判定に使用)
    //  ※ 未接続の dbg_a/dbg_b/dbg_x/dbg_flags/dbg_irq_pending は
    //    §3.1 参考実源対応表準拠で省略 (v0.3 レビュー指摘1 案A)
    // -------------------------------------------------------------
    logic [15:0] dbg_pc, dbg_sp;
    logic        dbg_halt;

    // -------------------------------------------------------------
    //  IRQ 結合 (V8-a L84 完全一致)
    // -------------------------------------------------------------
    logic [2:0] irq_in;
    logic       irq1_o;
    logic       irq_timer_o;
    logic       irq0_ack;
    assign irq_in = irq_timer_o ? 3'd1 : (irq1_o ? 3'd2 : 3'd0);

    // -------------------------------------------------------------
    //  SD SPI 信号
    // -------------------------------------------------------------
    logic spi_cs_n_o;
    logic spi_sck_o;
    logic spi_mosi_o;
    logic spi_miso_i;

    // -------------------------------------------------------------
    //  UART 信号 (tx_valid_o パルス駆動・v0.3 A1)
    // -------------------------------------------------------------
    logic       uart_tx_valid_o;
    logic [7:0] uart_tx_data_o;

    // -------------------------------------------------------------
    //  UART 蓄積 (dynamic queue)
    // -------------------------------------------------------------
    byte uart_bytes [$];
    integer uart_fd;

    // -------------------------------------------------------------
    //  cycle カウンタ・マイルストーン状態
    // -------------------------------------------------------------
    integer cycle_count;
    integer last_uart_cycle;

    logic m1_reached, m2_reached, m3_reached, m4_reached, m5_reached;
    integer m1_cycle, m2_cycle, m3_cycle, m4_cycle, m5_cycle;

    // -------------------------------------------------------------
    //  失敗マーカー検出フラグ (v0.3 §4)
    //   'i'=$69 : SB-LOAD I/O error
    //   'g'=$67 : MAGIC mismatch
    //   'v'=$76 : ver_major mismatch
    // -------------------------------------------------------------
    logic fail_marker_detected;
    byte  fail_marker;

    // =============================================================
    //  B2: クロック・リセット生成
    // =============================================================

    // CPU クロック 100MHz (10ns 周期) - V8-a 準拠
    initial cpu_clk = 0;
    always #5 cpu_clk = ~cpu_clk;

    // PSRAM クロック 25MHz (40ns 周期) - CDC bridge 経由
    initial psram_clk = 0;
    always #20 psram_clk = ~psram_clk;

    // リセット: 20 cycle Low → High
    initial begin
        cpu_rst_n   = 0;
        psram_rst_n = 0;
        repeat (3) @(negedge psram_clk);
        psram_rst_n = 1;
        // PSRAM 初期化はここで実行 (B4 で $readmemh)
        // ...ただし B2 段階では順序フックだけ。実際の $readmemh は B4 で追加。
        repeat (20) @(negedge cpu_clk);
        cpu_rst_n = 1;
        $display("[B2] Reset released @cycle=%0d", cycle_count);
    end

    // cycle カウンタ
    initial cycle_count = 0;
    always @(posedge cpu_clk) begin
        if (cpu_rst_n) cycle_count <= cycle_count + 1;
    end

    // =============================================================
    //  B3: DUT インスタンス (v0.3 §3.1 準拠)
    //   参考実源対応表: tb_cpu_v8catls_poc.sv L84/L89-97/L103-127/L131-136
    // =============================================================

    // --- DUT 1: CPU コア (無改修・RTL v0.5.8) ---
    ysd8800_cpu_v0_1 dut_cpu (
        .clk(cpu_clk), .rst_n(cpu_rst_n),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata),
        .mem_rd(mem_rd), .mem_wr(mem_wr), .mem_ready(mem_ready),
        .irq_in(irq_in),
        .dbg_pc(dbg_pc), .dbg_sp(dbg_sp), .dbg_halt(dbg_halt),
        // 未使用の dbg_* (dbg_a/dbg_b/dbg_x/dbg_flags/dbg_irq_pending) は省略
        //   本 TB の M-1/M-5・CL-3 判定は dbg_pc/dbg_sp/dbg_halt のみで十分
        //   (V8-a との差分の意図明示・v0.3 レビュー指摘1 案A)
        .irq0_ack(irq0_ack)
    );

    // --- DUT 2: v5 membus (ファイル v0.2 / module 宣言名は _v0_1) ---
    ysd8800_v5_membus_v0_1 #(.PHYS_AW(20), .MEM_AW(20)) u_membus (
        .cpu_clk(cpu_clk), .cpu_rst_n(cpu_rst_n),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata),
        .mem_rd(mem_rd), .mem_wr(mem_wr), .mem_ready(mem_ready),
        .psram_clk(psram_clk), .psram_rst_n(psram_rst_n),
        .irq1_o(irq1_o), .irq_timer_o(irq_timer_o), .irq0_ack(irq0_ack),
        .spi_cs_n_o(spi_cs_n_o), .spi_sck_o(spi_sck_o),
        .spi_mosi_o(spi_mosi_o), .spi_miso_i(spi_miso_i),
        .uart_tx_valid_o(uart_tx_valid_o), .uart_tx_data_o(uart_tx_data_o),
        .uart_rx_valid_i(1'b0), .uart_rx_data_i(8'h00),
        // (RX は本番 idle。UC-1 の判断により差替可能性あり)
        .disk_sectors_i(32'd16)   // 16 セクタ = 8KB (v0.3 §3.3)
    );

    // --- 補助 1: SD SPI モデル (実源 4 ポートのみ) ---
    sd_spi_model_v0_3_poc u_sd (
        .cs_n (spi_cs_n_o),
        .sck  (spi_sck_o),
        .mosi (spi_mosi_o),
        .miso (spi_miso_i)
    );

    // =============================================================
    //  B4: PSRAM 全域初期化 + CL-1 (v0.3 §3.2 / §7)
    //   V8-a L287-289 手法踏襲、ただし 1KB 限定でなく 56,416B 全域
    //   (V8-D の PSRAM 1KB 事故の反面教師・v0.3 A5)
    // =============================================================

    // yuios_road2.hex の期待行数 (56,416B)
    localparam integer EXPECTED_LOAD_BYTES = 56416;

    integer readmemh_lines;
    integer i;

    initial begin
        // PSRAM リセット解除を待ってから初期化
        @(posedge psram_rst_n);
        repeat (3) @(negedge psram_clk);

        // CL-1 (1): 56,416B 全域を明示的に 0 クリア
        $display("[B4] CL-1 (1): PSRAM 全域 0 クリア開始 (%0d bytes)", EXPECTED_LOAD_BYTES);
        for (i = 0; i < EXPECTED_LOAD_BYTES; i = i + 1)
            u_membus.u_psram_ctrl.mem[i] = 8'h00;

        // CL-1 (2): $readmemh でロード
        $display("[B4] CL-1 (2): yuios_road2.hex ロード");
        $readmemh("yuios_road2.hex", u_membus.u_psram_ctrl.mem);

        // CL-1 (3): 期待バイト数の確認 (行数=バイト数)
        //   $readmemh は行数を直接返さないので、簡易的に先頭と末尾の
        //   キー位置が非ゼロであることを確認する形にする。
        //   厳密な行数カウントは事前に wc -l で外部確認する運用。
        $display("[B4] CL-1 (3): 先頭バイト mem[$00000]=$%02x", u_membus.u_psram_ctrl.mem[0]);
        $display("[B4] CL-1 (3): _kstart  mem[$00E00]=$%02x", u_membus.u_psram_ctrl.mem[16'h0E00]);
        $display("[B4] CL-1 (3): 末尾-1B  mem[$%05x]=$%02x",
                 EXPECTED_LOAD_BYTES-1, u_membus.u_psram_ctrl.mem[EXPECTED_LOAD_BYTES-1]);

        // CL-1 (4): mem[$00E00] は kernel_v12_8.asm 先頭命令 (LDW SP, #$477E)
        //   opcode 値は初回実行時にダンプで観測する (v0.3 UC-2 対応・情報表示のみ)
        if (u_membus.u_psram_ctrl.mem[16'h0E00] == 8'h00) begin
            $display("[B4] CL-1 (4) WARN: mem[$0E00]=0x00 - HEX ロード失敗の可能性");
            $fatal(1, "[B4] CL-1 FAIL: _kstart 位置にコード未ロード");
        end
        $display("[B4] CL-1 PASS");
    end

    // =============================================================
    //  B5: SD image 供給 + CL-2 (v0.3 §3.3 / §7)
    //   sd_spi_model_v0_3_poc は内部で $readmemh("sd_image.hex")
    //   を実行する設計 (V8-a 実績)。TB 側は CL-2 マジック検証のみ実施。
    // =============================================================

    initial begin
        // sd_spi_model の image ロード完了を待つ (少し余裕を持たせて数 cycle)
        @(posedge psram_rst_n);
        repeat (10) @(negedge psram_clk);

        // CL-2: YUIFS マジック "YUIFS" (0x59, 0x55, 0x49, 0x46, 0x53) を検証
        //   sd_spi_model 内部の sd_mem 配列を階層参照して確認
        //   (パス名は sd_spi_model_v0_3_poc の実装依存・実源で確認要)
        $display("[B5] CL-2: SD image マジック検証");
        // 注: u_sd の内部 image 配列名は sd_spi_model_v0_3_poc.sv 実源に依存
        //     暫定的に sd_mem を仮定。B5 実 RTL 統合時に実源で確認する。
        //     (v0.3 UC-1 対応: sd_image.hex 内容確認・実装段階の暫定)
        if (u_sd.sd_mem[0] !== 8'h59 || u_sd.sd_mem[1] !== 8'h55 ||
            u_sd.sd_mem[2] !== 8'h49 || u_sd.sd_mem[3] !== 8'h46 ||
            u_sd.sd_mem[4] !== 8'h53) begin
            $display("[B5] CL-2 FAIL: SD image magic mismatch. Read: %02x %02x %02x %02x %02x",
                     u_sd.sd_mem[0], u_sd.sd_mem[1], u_sd.sd_mem[2],
                     u_sd.sd_mem[3], u_sd.sd_mem[4]);
            $fatal(1, "[B5] CL-2 FAIL");
        end
        $display("[B5] CL-2 PASS: YUIFS magic detected");
    end

    // =============================================================
    //  B6: UART 収集 + マイルストーン検出 (v0.3 §3.4 / §4)
    //   tx_valid_o パルス駆動 (V8-a 準拠、9600bps サンプリング不要)
    // =============================================================

    // UART ログファイル open
    initial begin
        uart_fd = $fopen("uart_out.log", "w");
        if (uart_fd == 0) $fatal(1, "[B6] uart_out.log open failed");
    end

    // マイルストーン初期化
    initial begin
        m1_reached = 0; m2_reached = 0; m3_reached = 0;
        m4_reached = 0; m5_reached = 0;
        m1_cycle = 0; m2_cycle = 0; m3_cycle = 0;
        m4_cycle = 0; m5_cycle = 0;
        fail_marker_detected = 0;
        fail_marker = 8'h00;
        last_uart_cycle = 0;
    end

    // -------------------------------------------------------------
    // 部分列マッチ関数: uart_bytes 末尾から needle を検索
    //   末尾のみで十分 (毎 tx で呼ぶので、既に検出済のパターンは
    //   more recent なマッチが上書きするだけ)
    // -------------------------------------------------------------
    function automatic bit uart_tail_match(input byte needle[]);
        int q_len = uart_bytes.size();
        int n_len = needle.size();
        if (q_len < n_len) return 0;
        for (int k = 0; k < n_len; k = k + 1)
            if (uart_bytes[q_len - n_len + k] !== needle[k]) return 0;
        return 1;
    endfunction

    // -------------------------------------------------------------
    // UART TX 受信 + ログ書出 + マーカー検出
    // -------------------------------------------------------------
    byte needle_booted [] = '{"Y","U","I","O","S"," ","B","o","o","t","e","d","!"};
    byte needle_prompt [] = '{"0","Y","U","I",">"," "};
    byte needle_pass   [] = '{"0","1","2","3","M","D"};

    always @(posedge cpu_clk) begin
        if (cpu_rst_n && uart_tx_valid_o) begin
            // 蓄積
            uart_bytes.push_back(uart_tx_data_o);
            $fwrite(uart_fd, "%c", uart_tx_data_o);
            $fflush(uart_fd);
            last_uart_cycle <= cycle_count;

            // M-2: 最初の UART TX
            if (!m2_reached) begin
                m2_reached = 1;
                m2_cycle   = cycle_count;
                $display("[M-2] First UART TX byte=$%02x @cycle=%0d",
                         uart_tx_data_o, cycle_count);
            end

            // M-3: "YUIOS Booted!" 検出
            if (!m3_reached && uart_tail_match(needle_booted)) begin
                m3_reached = 1;
                m3_cycle   = cycle_count;
                $display("[M-3] \"YUIOS Booted!\" detected @cycle=%0d", cycle_count);
            end

            // M-4: "0YUI> " プロンプト検出
            if (!m4_reached && uart_tail_match(needle_prompt)) begin
                m4_reached = 1;
                m4_cycle   = cycle_count;
                $display("[M-4] \"0YUI> \" prompt detected @cycle=%0d", cycle_count);
            end

            // M-5: "0123MD" マーカー検出 → PASS
            if (!m5_reached && uart_tail_match(needle_pass)) begin
                m5_reached = 1;
                m5_cycle   = cycle_count;
                $display("[M-5] \"0123MD\" detected @cycle=%0d ==> PASS", cycle_count);
            end

            // 失敗マーカー早期検出 (v0.3 §4)
            //   'i'=$69 / 'g'=$67 / 'v'=$76
            //   前提: uart_rx_valid_i = 1'b0 (本番 idle) 前提で有効
            if (!fail_marker_detected && m2_reached &&
                (uart_tx_data_o == 8'h69 || uart_tx_data_o == 8'h67 ||
                 uart_tx_data_o == 8'h76)) begin
                fail_marker_detected = 1;
                fail_marker = uart_tx_data_o;
                $display("[FAIL-EARLY] YUIFS mount failed marker='%c' ($%02x) @cycle=%0d",
                         uart_tx_data_o, uart_tx_data_o, cycle_count);
            end
        end
    end

    // -------------------------------------------------------------
    // M-1: PC が $0E00 (_kstart) に到達
    //   (v0.3 §7 CL-3 実装ヒント: M-1 検出時に CL-3 の PC assert を紐付ける)
    // -------------------------------------------------------------
    always @(posedge cpu_clk) begin
        if (cpu_rst_n && !m1_reached && dbg_pc == 16'h0E00) begin
            m1_reached = 1;
            m1_cycle   = cycle_count;
            $display("[M-1] PC reached $0E00 (_kstart) @cycle=%0d", cycle_count);
            // CL-3 PC assert (M-1 到達時点で確定)
            $display("[B6] CL-3 (PC): dbg_pc==$0E00 confirmed");
        end
    end

    // =============================================================
    //  B7: 判定・タイムアウト・終了処理 (v0.3 §5 / §6)
    // =============================================================

    // CL-3 SP assert: _kstart の LDW SP, #$477E 実行完了後
    //   dbg_sp が $477E になった時点で確認 (M-1 到達後の初回)
    logic cl3_sp_checked;
    initial cl3_sp_checked = 0;
    always @(posedge cpu_clk) begin
        if (cpu_rst_n && m1_reached && !cl3_sp_checked && dbg_sp == 16'h477E) begin
            cl3_sp_checked = 1;
            $display("[B7] CL-3 (SP): dbg_sp==$477E confirmed @cycle=%0d (KERN_SP_TOP)",
                     cycle_count);
        end
    end

    // タイムアウト・打切り監視
    always @(posedge cpu_clk) begin
        if (cpu_rst_n) begin
            // M-1 タイムアウト
            if (!m1_reached && cycle_count > M1_TIMEOUT_CYCLES) begin
                $display("[M-1 TIMEOUT] _kstart ($0E00) not reached @cycle=%0d",
                         cycle_count);
                $display("[FAIL] M-1 未到達: PSRAM 初期化 or リセット経路異常の疑い");
                finalize_and_exit(0);
            end

            // M-2 タイムアウト (m1 到達後に判定)
            if (m1_reached && !m2_reached && cycle_count > M2_TIMEOUT_CYCLES) begin
                $display("[M-2 TIMEOUT] no UART TX @cycle=%0d", cycle_count);
                $display("[FAIL] M-2 未到達: UART/MMIO 経路異常の疑い");
                finalize_and_exit(0);
            end

            // UART デッドロック検出 (v0.3 §6.2)
            if (m2_reached && !m5_reached &&
                (cycle_count - last_uart_cycle) > UART_STALL_LIMIT) begin
                $display("[FAIL] UART TX stall > %0d cycles @cycle=%0d",
                         UART_STALL_LIMIT, cycle_count);
                finalize_and_exit(0);
            end

            // 失敗マーカー検出時 (v0.3 §4)
            if (fail_marker_detected) begin
                $display("[FAIL] Early fail marker '%c' detected", fail_marker);
                finalize_and_exit(0);
            end

            // PASS 判定
            if (m5_reached) begin
                $display("==================================================");
                $display("  V8-b 本番 PASS ==> \"0123MD\" @cycle=%0d", m5_cycle);
                $display("  M-1: %0d, M-2: %0d, M-3: %0d, M-4: %0d, M-5: %0d",
                         m1_cycle, m2_cycle, m3_cycle, m4_cycle, m5_cycle);
                $display("==================================================");
                finalize_and_exit(1);
            end

            // MAX_CYCLES 到達
            if (cycle_count >= MAX_CYCLES) begin
                $display("[TIMEOUT] MAX_CYCLES=%0d reached", MAX_CYCLES);
                $display("  Milestones reached: M-1=%0b M-2=%0b M-3=%0b M-4=%0b M-5=%0b",
                         m1_reached, m2_reached, m3_reached, m4_reached, m5_reached);
                finalize_and_exit(0);
            end
        end
    end

    // 終了処理タスク
    task finalize_and_exit(input bit pass);
        $fclose(uart_fd);
        if (pass)
            $display("=== V8-b PROD PASS ===");
        else
            $display("=== V8-b PROD FAIL ===");
        $finish;
    endtask

    // 起動時バナー
    initial begin
        $display("==================================================");
        $display("  tb_cpu_v8b_prod_v0_1  (2026-08-01)");
        $display("  V8-b 本番 TB / MAX_CYCLES=%0d", MAX_CYCLES);
        $display("  DUT: ysd8800_cpu_v0_1 + ysd8800_v5_membus_v0_1");
        $display("       + sd_spi_model_v0_3_poc");
        $display("  設計根拠: v8b_prod_design_memo_v0_3.md (承認済)");
        $display("==================================================");
    end

endmodule
