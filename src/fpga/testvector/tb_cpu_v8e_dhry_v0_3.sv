//==============================================================
// tb_cpu_v8e_dhry_v0_3.sv   v0.3  (2026-09-05)
//
// ★v0.3 変更点 (計画書 v18_stage7c_stallmon_plan_v0_2.md)★
//   (1) [M-1] G-M MISMATCH モニタの観測点を CPU 側(論理)+$FC80 フィルタ
//             から ★キャッシュ境界 (u_membus.u_cache のポート・物理20bit)★
//             へ移行。TKT-V7 v0.3 §4.2 の正式仕様に追従。
//   (2) [段7-C] mem_ready ストール積算モニタを新設
//             (stall_wr / stall_rd / bus_ack / idle / mmio_acc / bus_both)。
//             ★M-3: MMIO($FC80以上)を分離し母数 C_eff を新設★
//   (3) [TKT-V8] irq0_ack_count (armed_r 立上り) を追加し fire×ACK の
//             2軸で判定可能にした。終了時スナップショットも出力。
//   (4) [S-1 是正] PASS 表示条件を dbg_halt 単独から
//             ★halt && tx_count==9 && mism==0 && rdchk>0 && both==0★ へ。
//             $finish のタイミングは不変(表示分岐のみ)。
//   (5) TKT-V7 用の固定サイクルデバッグ出力($01A20前後)を撤去。
//   YSD8800 段7-A / TKT-V7 用 Dhrystone テストベンチ
//
//   改版履歴:
//     v0.1 (2026-09-05) tb_cpu_v8b_prod_v0_3.sv v0.3 (2026-08-30) から
//                       段7-A 用に派生。Dhrystone 判定・C-TX 配列・
//                       MISMATCH モニタを追加。
//                       ※ヘッダは派生元 v0.3 の記述のままであった(是正)
//     v0.2 (2026-09-05) TKT-V7 検証用。MISMATCH モニタに★母数★
//                       (read_checked) を追加し G-M 判定行を出力。
//                       照合0件による偽の合格を排除する(KY96)。
//
//   ---- 以下は派生元 tb_cpu_v8b_prod_v0_3.sv の記述 ----
//
//   目的: yuios_road2.bin (56,416B, kernel v12.8 + Forth v0.10.18)
//         を iverilog 上の実 RTL 環境で実行し、UART TX 出力に
//         "YUI> " プロンプト後の FILEMGR タスク YUIFS 起動進捗
//         マーカー "0123MD" (6バイト) 到達を判定する。
//
//   DUT   : ysd8800_cpu_v0_1 (RTL v0.5.8・無改修)
//           + ysd8800_v5_membus_v0_1 (ファイル v0.2・無改修)
//   SDモデル: sd_spi_model_v0_3_poc (内部 initial で
//             $readmemh(IMG_HEX, img_mem) 実行・IMG_HEX 既定 "sd_image.hex")
//
//   段階起動 (v0.4 §5・v0.2 実測反映):
//     phase-1: MAX_CYCLES=1_000_000    (M-1〜M-4 快速 sanity)
//     phase-2: MAX_CYCLES=10_000_000   (M-5 到達・本番判定)
//              ※ UART_STALL_LIMIT=5_000_000 必須 (M-4→M-5 間隔 426万cyc)
//     phase-3: MAX_CYCLES=100_000_000  (余裕枠・通常不要)
//
//   ★2026-08-01 V8-b 本番 ALL PASS 実測★
//     M-1=9 / M-2=89,807 / M-3=239,874 / M-4=356,663 / M-5=4,616,900
//     UART 実出力(25B): "YUIOS Booted!\nYUI> 0123MD"
//     CL-1/CL-2/CL-3(PC/SP) 全 PASS・失敗マーカー i/g/v 不出現
//
//   設計根拠: v8b_prod_design_memo_v0_4.md (v0.3 の実測反映改版)
//
//   改版履歴:
//     v0.1 (2026-08-01) 初版。設計書 v0.3 に基づく 7 ブロック実装。
//                       stub 版 syntax PASS まで確認。実 RTL 未結合。
//     v0.2 (2026-08-01) 実 RTL 15 コンポーネント結合・phase-1/2 実走。
//                       確定バグ 3 件を修正し V8-b 本番 ALL PASS 達成。
//       [B-1] B5 CL-2 の階層参照 sd_mem → img_mem 是正。
//             sd_spi_model_v0_3_poc.sv L96 が実源。L124 で
//             $readmemh(IMG_HEX, img_mem) を内部実行するため TB 側の
//             $readmemh は不要。KY 活動により build 前に事前検出。
//       [B-2] ★真因★ B2 クロック生成是正。
//             v0.1: cpu_clk=100MHz(#5) / psram_clk=25MHz(#20)
//                   → psram:cpu = 1:4 (PSRAM が低速)
//             v0.2: cpu_clk=4MHz(#125)  / psram_clk=32MHz(#15.625)
//                   → psram:cpu = 8:1 (V8-a 比率を保持)
//             v0.1 の 100MHz は実源に存在しない創作値(原則76 違反)。
//             実源は 4MHz: ysd8002_timer_design_v1_2.docx
//             cpu_freq_hz=4,000,000 / ysd8001_uart_design_v1_2.docx
//             「計算例(CLK=4MHz)」UART_BAUD=416=4M/9600-1 /
//             toolchain23_design_v1_2.docx 同値。
//             比率 8:1 は V8-a (tb_cpu_v8catls_poc.sv L142/L144) の
//             実績値。比率逆転により CDC ハンドシェイクが CPU 1 cycle
//             内に完了せず、mem_ready が永久に返らなかった
//             (実測: mem_ready=0/5000cyc・mem_rd=5000/5000・PC=$0000 固定)。
//             是正後: mem_ready=865/5000cyc・PC 進行を確認。
//       [B-3] M-4 判定文字列 "0YUI> "(6文字) → "YUI> "(5文字) 是正。
//             実測 UART 出力は "YUIOS Booted!\nYUI> 0" であり、'0' は
//             プロンプトの前ではなく後に出る。'0' は M-5 マーカー列
//             "0123MD" の 1 文字目(FILEMGR SB-LOAD 開始・
//             kernel_forth_v0_10_18.fs L2785)であり、プロンプトの一部
//             ではない。設計書 v0.3 §4 は '0' を M-4/M-5 で二重計上。
//       [追] UART_STALL_LIMIT の既定値を 500_000 → 5_000_000 に変更。
//            M-4(356,663) → M-5(4,616,900) の間隔は約 426 万 cycle で
//            あり、旧既定値では実 SPI 転送中に誤って stall 判定が発火
//            した。kaizen 原則83「実 SPI 転送は fread 前提の OS ドライバ
//            と約1000倍の乖離がある」の実証。
//
//  ── v0.3 改版 (2026-08-30) ────────────────────────────────────
//       [C-1] ★M-5 判定を「末尾一致」→「順序保存の部分列一致」に是正。
//             uart_tail_match() は残置(M-3/M-4 が継続使用)し、
//             M-5 専用に uart_subseq_match() を新設して切替える。
//
//             【是正理由】
//             PSRAM レイテンシ LAT=5 では '0'(FILEMGR SB-LOAD 開始)が
//             プロンプト "YUI> " より前に出力される。出力バイト集合と
//             0→1→2→3→M→D の順序は LAT=12 と同一だが、末尾6バイトが
//             " 123MD" となり tail-match が成立しない。その結果、OS が
//             全処理を完了して正常アイドルに入った後、UART_STALL_LIMIT
//             で誤って FAIL 判定されていた。
//
//             【実測（本是正の根拠）】
//               LAT=12: "YUIOS Booted!\nYUI> 0123M"  ('0' はプロンプト後)
//               LAT= 5: "YUIOS Booted!\n0YUI> 123MD" ('0' はプロンプト前)
//               → 部分列一致に是正後、LAT=5 で
//                 [M-5] detected @cycle=2,810,474 ==> PASS
//                 (RTL・OS・ツールチェーンは一切無変更)
//
//             【重要】v0.2 までの判定は「速度依存」であった。
//             工程②-A' で追跡した「速度依存デッドロック」は実在せず、
//             本判定器の脆弱性が真因である。②-B(キャッシュ本体)では
//             ヒット時の実効レイテンシがさらに短くなるため、本是正なしに
//             等価性ゲートを判定してはならない。
//             → 原則137「PASS/FAIL 判定ロジック自体を被疑対象から
//               外さない。RTL を疑う前に判定器が速度非依存かを確認する」
//
//             【残課題】'0' とプロンプトの出力順序が速度依存で入れ替わる
//             こと自体はレースであり、機能上は無害だが起動シーケンスの
//             同期が甘い。TKT-U1 として起票し工程④で対処する。
//==============================================================

`timescale 1ns/1ps

module tb_cpu_v8e_dhry_v0_3;

    // -------------------------------------------------------------
    //  パラメータ (段階起動用、コマンドラインで上書き可)
    // -------------------------------------------------------------
    parameter integer MAX_CYCLES        = 10_000_000;   // [M-4] 段7-A 既定 (phase-2相当)
    parameter integer M1_TIMEOUT_CYCLES = 10_000;       // v0.4 §4 (実測 9)
    parameter integer M2_TIMEOUT_CYCLES = 200_000;      // 実測 89,807
    parameter integer M3_TIMEOUT_CYCLES = 5_000_000;    // 実測 239,874
    parameter integer M4_TIMEOUT_CYCLES = 8_000_000;    // 実測 356,663
    // ★v0.2 是正★ 500_000 → 5_000_000
    //   M-4(356,663) → M-5(4,616,900) の実 SPI 転送間隔は約 426 万 cycle。
    //   旧値では転送中に誤って stall 判定が発火し FAIL となった。
    //   kaizen 原則83 (実 SPI は fread 前提 OS ドライバと約1000倍乖離) の実証。
    parameter integer UART_STALL_LIMIT  = 5_000_000;    // v0.4 §6.2

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

    // CPU クロック 4MHz (250ns 周期)
    //   実源根拠: ysd8002_timer_design_v1_2.docx cpu_freq_hz=4,000,000
    //             ysd8001_uart_design_v1_2.docx  「計算例(CLK=4MHz)」
    //                                             UART_BAUD リセット値 416
    //                                             = 4MHz/9600 - 1
    //             toolchain23_design_v1_2.docx   cpu_freq_hz 4,000,000
    initial cpu_clk = 0;
    always #125 cpu_clk = ~cpu_clk;

    // PSRAM クロック 32MHz (31.25ns 周期) - CDC bridge 経由
    //   V8-a (tb_cpu_v8catls_poc.sv L142/L144) の psram:cpu = 8:1 比率を保持。
    //   この比率は CDC ハンドシェイクが CPU 1 cycle 内で完了する条件であり、
    //   V8-a ALL PASS の実績構成。比率を崩すと mem_ready が返らない
    //   (2026-08-01 実測: psram:cpu = 1:4 で mem_ready=0/5000cyc)。
    initial psram_clk = 0;
    always #15.625 psram_clk = ~psram_clk;

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

    // [D-1] dhry_final.hex の期待行数 (21,846B)
    localparam integer EXPECTED_LOAD_BYTES = 21846;

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
        $display("[B4] CL-1 (2): dhry_final.hex ロード");   // [D-1]
        $readmemh("dhry_final.hex", u_membus.u_psram_ctrl.mem);

        // CL-1 (3): 期待バイト数の確認 (行数=バイト数)
        //   $readmemh は行数を直接返さないので、簡易的に先頭と末尾の
        //   キー位置が非ゼロであることを確認する形にする。
        //   厳密な行数カウントは事前に wc -l で外部確認する運用。
        $display("[B4] CL-1 (3): 先頭バイト mem[$00000]=$%02x", u_membus.u_psram_ctrl.mem[0]);
        $display("[B4] CL-1 (3): rstvec   mem[$00001]=$%02x", u_membus.u_psram_ctrl.mem[1]);
        $display("[B4] CL-1 (3): 末尾-1B  mem[$%05x]=$%02x",
                 EXPECTED_LOAD_BYTES-1, u_membus.u_psram_ctrl.mem[EXPECTED_LOAD_BYTES-1]);

        // [D-6] CL-1 (4): リセットベクタ mem[$0000]/[$0001] が _startup ($0018) を指すこと
        //   startup_harness23_v17.asm: .org $0000 のベクタ / _startup は .org $0018
        //   実測: dhry_final.hex 先頭 2 バイト = 18 00 (リトルエンディアン)
        if (!(u_membus.u_psram_ctrl.mem[0] == 8'h18 &&
              u_membus.u_psram_ctrl.mem[1] == 8'h00)) begin
            $display("[B4] CL-1 (4) WARN: rstvec=$%02x%02x (expect $0018)",
                     u_membus.u_psram_ctrl.mem[1], u_membus.u_psram_ctrl.mem[0]);
            $fatal(1, "[B4] CL-1 FAIL: リセットベクタ不正 = HEX ロード失敗");
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
        //   sd_spi_model 内部の img_mem 配列を階層参照して確認
        //   (実源照合済: sd_spi_model_v0_3_poc.sv L96 で img_mem 宣言、
        //    L124 で $readmemh(IMG_HEX, img_mem) 実行。IMG_HEX デフォルト
        //    値 "sd_image.hex"・IMG_BYTES=8192B=16 セクタ)
        $display("[B5] CL-2: SD image マジック検証");
        if (u_sd.img_mem[0] !== 8'h59 || u_sd.img_mem[1] !== 8'h55 ||
            u_sd.img_mem[2] !== 8'h49 || u_sd.img_mem[3] !== 8'h46 ||
            u_sd.img_mem[4] !== 8'h53) begin
            $display("[B5] CL-2 FAIL: SD image magic mismatch. Read: %02x %02x %02x %02x %02x",
                     u_sd.img_mem[0], u_sd.img_mem[1], u_sd.img_mem[2],
                     u_sd.img_mem[3], u_sd.img_mem[4]);
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
        tx_count = 0;              // [C-7/N-3]
        irq0_fire_count = 0;       // [U-8]
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

    // === C-1 (v0.3) M-5 専用: 順序保存の部分列一致 =======================
    //  末尾一致は速度依存で成立しない場合がある(ヘッダ v0.3 [C-1] 参照)。
    //  needle の各バイトが uart_bytes 中に「順序を保って」出現すれば真。
    // ====================================================================
    function automatic bit uart_subseq_match(input byte needle[]);
        int q_len = uart_bytes.size();
        int n_len = needle.size();
        int j = 0;
        for (int k = 0; k < q_len; k = k + 1) begin
            if (j < n_len && uart_bytes[k] === needle[j]) j = j + 1;
        end
        return (j == n_len);
    endfunction

    // -------------------------------------------------------------
    // UART TX 受信 + ログ書出 + マーカー検出
    // -------------------------------------------------------------
    byte needle_booted [] = '{"Y","U","I","O","S"," ","B","o","o","t","e","d","!"};
    // M-4 判定: SHELL-START プロンプト "YUI> " (5文字)
    //   ★2026-08-01 実測是正★ 設計書 v0.3 §4 は "0YUI> " (6文字) としたが、
    //   実測 UART 出力は "YUIOS Booted!\nYUI> 0" であり、'0' はプロンプトの
    //   前ではなく後に出る。'0' は M-5 マーカー列 "0123MD" の 1 文字目
    //   (FILEMGR SB-LOAD 開始・Forth kernel_forth_v0_10_18.fs L2785) であり、
    //   プロンプトの一部ではない。設計書 v0.3 は '0' を M-4/M-5 で二重計上
    //   していた。
    byte needle_prompt [] = '{"Y","U","I",">"," "};
    byte needle_pass   [] = '{"0","1","2","3","M","D"};

    // [C-7/N-3] UART TX の発生 cycle 記録 (計画書 v0.3 §5.2)
    integer tx_cycle [0:31];
    integer tx_data  [0:31];
    integer tx_count;
    // [U-8] IRQ0 発火回数 (40,000cyc 周期で入る。計画書 v0.3 T-0 の発見)
    integer irq0_fire_count;

    always @(posedge cpu_clk) begin
        if (cpu_rst_n && uart_tx_valid_o) begin
            // 蓄積
            uart_bytes.push_back(uart_tx_data_o);
            $fwrite(uart_fd, "%c", uart_tx_data_o);
            $fflush(uart_fd);
            last_uart_cycle <= cycle_count;

            // ================================================================
            // [D-2] YUI OS 固有の判定器を撤去
            //   撤去内訳: M-2(初回TX) / M-3("YUIOS Booted!") / M-4(プロンプト)
            //             M-5("0123MD" 部分列一致) / 失敗マーカー検出('i'/'g'/'v')
            //   理由: いずれも YUI OS ワークロード固有。Dhrystone の出力は
            //         "N=10\nP:20" の 9 バイトのみ (計画書 v0.3 P-10)
            // ----------------------------------------------------------------
            // [C-7/N-3] 9 バイト全ての TX 発生 cycle を記録する。
            //   これにより任意区間を事後に切り出せる:
            //     C-total = reset -> dbg_halt
            //     C-body  = tx_cycle[0]('N') -> C-total
            //     C-core  = tx_cycle[4]('P') - tx_cycle[3]('\n')
            // ================================================================
            if (tx_count < 32) begin
                tx_cycle[tx_count] = cycle_count;
                tx_data [tx_count] = uart_tx_data_o;
                $display("[TX] #%0d '%c' ($%02x) @cycle=%0d",
                         tx_count, uart_tx_data_o, uart_tx_data_o, cycle_count);
            end
            tx_count = tx_count + 1;
        end
    end

    // =============================================================
    // [D-4] YUI OS 固有の PC/SP プローブを撤去
    //   撤去内訳:
    //     - M-1 PC プローブ (dbg_pc == $0E00 = _kstart)
    //         Dhrystone は $0E00 を実行しない -> 永久に m1_reached=0
    //     - CL-3 SP assert (dbg_sp == $477E = KERN_SP_TOP)
    //         Dhrystone の SP は $F7FE (startup_harness23_v17.asm L87)
    // =============================================================

    // -------------------------------------------------------------
    // [U-8] IRQ0 発火回数の計測 (計画書 v0.3 T-0 の発見)
    //   YSD8002 はリセット既定で timer_en=1/irq_en=1/period=40000。
    //   ハーネス _timer_handler は TCR<=$0023 (ACK+再武装) を書くため、
    //   測定中 40,000cyc 周期で IRQ0 が入り続ける。
    //   影響は小さいが CEN=0/1 で回数が異なるため実測して記録する。
    // -------------------------------------------------------------
    logic irq0_d;
    initial irq0_d = 1'b0;
    always @(posedge cpu_clk) begin
        if (cpu_rst_n) begin
            irq0_d <= u_membus.u_mmio_stub.u_ysd8002.irq_req_r;
            if (u_membus.u_mmio_stub.u_ysd8002.irq_req_r && !irq0_d)
                irq0_fire_count = irq0_fire_count + 1;
        end
    end

    // -------------------------------------------------------------
    // [v0.3 ★TKT-V8★] IRQ0 再武装(ACK)の計数  計画書 v18 §4.2.2 / §5.1 e1
    //   YSD8002 v0.3 は「ワンショット+ソフト再武装」モデルであり
    //   (L288-290 発火で armed_r<=0 / L323-325 TCR bit5 書込で再武装)、
    //   fire 回数単独では RTL 起因と software 起因を分離できない。
    //   armed_r の立上りを ACK 成立の指標として同時計数する。
    // -------------------------------------------------------------
    integer irq0_ack_count;
    logic   armed_d;
    initial irq0_ack_count = 0;
    initial armed_d = 1'b0;
    always @(posedge cpu_clk) begin
        if (cpu_rst_n) begin
            armed_d <= u_membus.u_mmio_stub.u_ysd8002.armed_r;
            if (u_membus.u_mmio_stub.u_ysd8002.armed_r && !armed_d)
                irq0_ack_count = irq0_ack_count + 1;
        end
    end

    // -------------------------------------------------------------
    // [v0.3 ★段7-C★] mem_ready ストール積算モニタ
    //   計画書 v18 §2.2 / §2.2.1 / §5.1 a-c3
    //   観測点は CPU 側バス(mem_rd/mem_wr/mem_ready)。
    //   ★M-3: MMIO ($FC80 以上) を分離する★
    //     CPU 側バスは MMIO も通過するため、分離しないと Dhrystone の
    //     UART ビジーウェイト(約 37,500cyc)が母数を膨らませ、
    //     書込ストール率が過小に出る。
    // -------------------------------------------------------------
    integer stall_wr, stall_rd, bus_ack, bus_idle, mmio_acc, bus_both;
    initial begin
        stall_wr = 0; stall_rd = 0; bus_ack = 0;
        bus_idle = 0; mmio_acc = 0; bus_both = 0;
    end
    wire is_mmio = (mem_addr >= 20'hFC80);
    // ★[v0.3 是正 2026-09-05] 代入方式を cycle_count(L249, NBA) に揃える★
    //   当初ブロッキング(=)で書いたところ、試走で恒等式が sum=C_total+1 と
    //   なった。cycle_count は NBA のため finalize 実行時点では終端サイクル
    //   分が未反映であるのに対し、ブロッキング側は反映済で1回分先行していた。
    //   ★N-1 の恒等式検算がこの位相ずれを検出した(計画書 §2.2.1 V-b)★
    always @(posedge cpu_clk) begin
        if (cpu_rst_n) begin
            // V-a: 排他前提の検証 (計画書 §2.2.1)
            if (mem_rd && mem_wr) bus_both <= bus_both + 1;
            if (is_mmio && (mem_rd || mem_wr))
                mmio_acc <= mmio_acc + 1;
            else if (!is_mmio && mem_wr && !mem_ready)
                stall_wr <= stall_wr + 1;
            else if (!is_mmio && mem_rd && !mem_ready)
                stall_rd <= stall_rd + 1;
            else if (!is_mmio && (mem_rd || mem_wr) && mem_ready)
                bus_ack  <= bus_ack + 1;
            else
                bus_idle <= bus_idle + 1;
        end
    end


    // タイムアウト・打切り監視
    always @(posedge cpu_clk) begin
        if (cpu_rst_n) begin
            // ============================================================
            // [D-5] YUI OS 固有のタイムアウト監視を撤去
            //   撤去内訳:
            //     - M-1 TIMEOUT (M1_TIMEOUT_CYCLES=10,000)
            //         ★これを残すと 10,000cyc で強制終了し測定不能★
            //     - M-2 TIMEOUT (M2_TIMEOUT_CYCLES=200,000)
            //     - UART 停滞監視 (UART_STALL_LIMIT=5,000,000)
            //         Dhrystone は測定中 UART を出さないため誤発火する
            //   異常終端は MAX_CYCLES 到達のみとする (計画書 v0.3 D-5)
            // ============================================================
            if (1'b0) begin
                finalize_and_exit(0);
            end

            // ============================================================
            // [D-2] 終端判定: dbg_halt (計画書 v0.3 §1.2)
            //   startup_harness23_v17.asm L90-92: JSR _main -> HALT
            //   dbg_halt = (state == S_HALT) であり速度依存が原理的に無い
            // ============================================================
            if (dbg_halt) begin
                $display("==================================================");
                $display("  [HALT] Dhrystone 完了 @cycle=%0d", cycle_count);
                $display("==================================================");
                finalize_and_exit(1);
            end

            // MAX_CYCLES 到達 (唯一の異常終端)
            if (cycle_count >= MAX_CYCLES) begin
                $display("[TIMEOUT] MAX_CYCLES=%0d reached (dbg_halt 未到達)", MAX_CYCLES);
                finalize_and_exit(0);
            end
        end
    end

    // [DEBUG 2026-09-05] 暴走追跡用 PC 履歴リングバッファ
    logic [15:0] pc_hist [0:63];
    logic [15:0] pc_prev;
    integer      pc_wp;
    initial begin pc_wp = 0; pc_prev = 16'hFFFF; end
    always @(posedge cpu_clk) begin
        if (cpu_rst_n && dbg_pc !== pc_prev) begin
            pc_hist[pc_wp] = dbg_pc;
            pc_wp = (pc_wp + 1) % 64;
            pc_prev <= dbg_pc;
        end
    end

    // [DEBUG 2026-09-05] キャッシュ返却データ vs PSRAM 実体の照合
    //   CEN=1 でのみ発生する暴走の原因切分け。
    //   読出完了サイクルで mem_rdata と psram の実体を比較する。
    //   ※ MMIO 領域 ($FC80 以上) は対象外 (キャッシュ非対象)
    //   [v0.2 2026-09-05] TKT-V7 T-1/T-3 用に★母数★を追加。
    //     MISMATCH=0 が「照合した上で 0」であることを示すため
    //     (照合対象0件でも 0 と表示される偽の合格を排除する・KY96)。
    //   [v0.3 2026-09-05 ★M-1 観測点移行★] 計画書 v18 §5.1 項目g
    //     TKT-V7 v0.3 §4.2 で G-M の正式仕様は「キャッシュ境界(物理20bit)」
    //     に確定していたが、v0.2 までは CPU 側(論理)+$FC80 フィルタという
    //     旧観測点のままだった。本版で正式仕様へ移行する。
    //     ★キャッシュポートは RAM パス専用のため $FC80 フィルタは不要★
    //     (MMIO はそもそもキャッシュ段に来ない)。
    integer mism_count;
    integer rdchk_count;
    initial mism_count  = 0;
    initial rdchk_count = 0;
    always @(posedge cpu_clk) begin
        if (cpu_rst_n && u_membus.u_cache.cpu_rd_i && u_membus.u_cache.cpu_ready_o) begin
            rdchk_count = rdchk_count + 1;
            if (u_membus.u_cache.cpu_rdata_o !==
                u_membus.u_psram_ctrl.mem[u_membus.u_cache.cpu_phys_addr_i]) begin
                if (mism_count < 20)
                    $display("[MISMATCH] pa=$%05x cache=$%02x psram=$%02x @cycle=%0d",
                             u_membus.u_cache.cpu_phys_addr_i,
                             u_membus.u_cache.cpu_rdata_o,
                             u_membus.u_psram_ctrl.mem[u_membus.u_cache.cpu_phys_addr_i],
                             cycle_count);
                mism_count = mism_count + 1;
            end
        end
    end

    // [v0.3] TKT-V7 デバッグ用の固定サイクル観測ブロック($01A20 前後)は撤去。
    //        当該バグは修正済であり、常時出力はログを汚すため。


    // 終了処理タスク
    task finalize_and_exit(input bit pass);
        integer k;
        integer c_eff;
        bit     pass_final;
        $fclose(uart_fd);
        // ============================================================
        // [計画書 v0.3 §5.2] 測定結果の出力
        // ============================================================
        $display("--------------- MEASUREMENT ---------------");
        $display("[RESULT] C-total  = %0d", cycle_count);
        $display("[RESULT] tx_count = %0d (expect 9)", tx_count);
        $write  ("[RESULT] UART     = \"");
        for (k = 0; k < tx_count && k < 32; k = k + 1) $write("%c", tx_data[k]);
        $display("\"");
        for (k = 0; k < tx_count && k < 32; k = k + 1)
            $display("[RESULT] tx_cycle[%0d] '%c' = %0d", k, tx_data[k], tx_cycle[k]);
        if (tx_count >= 9) begin
            $display("[RESULT] C-body   = %0d  (tx[0]'N' -> halt)",
                     cycle_count - tx_cycle[0]);
            // [是正 2026-09-05] 実測の並びは N(0) =(1) 1(2) 0(3) \n(4) P(5) :(6) 2(7) 0(8)
            //   計画書 v0.3 §5.2 は tx[4]='P' / tx[3]='\n' としたがインデックス誤り。
            //   正しくは 'P'=tx[5] / '\n'=tx[4]。
            $display("[RESULT] C-core   = %0d  (tx[5]'P' - tx[4]'\\n')",
                     tx_cycle[5] - tx_cycle[4]);
        end
        $display("[RESULT] IRQ0 fire = %0d", irq0_fire_count);
        // ============================================================
        // [v0.3 ★TKT-V8★] 計画書 v18 §4.2.2 / §4.2.3
        // ============================================================
        $display("[IRQ] fire=%0d  ack(armed rise)=%0d  expect=%0d (C_total/40000)",
                 irq0_fire_count, irq0_ack_count, cycle_count / 40000);
        $display("[IRQ] snapshot: armed=%b timer_en=%b irq_en=%b period=%0d cnt=%0d",
                 u_membus.u_mmio_stub.u_ysd8002.armed_r,
                 u_membus.u_mmio_stub.u_ysd8002.timer_en_r,
                 u_membus.u_mmio_stub.u_ysd8002.irq_en_r,
                 u_membus.u_mmio_stub.u_ysd8002.period_r,
                 u_membus.u_mmio_stub.u_ysd8002.cnt_r);
        // ============================================================
        // [v0.3 ★段7-C★] ストール積算  計画書 v18 §2.2 / §2.3
        // ============================================================
        c_eff = cycle_count - mmio_acc;
        $display("--------------- STALL (stage 7-C) ---------------");
        $display("[ST] C_total=%0d  mmio_acc=%0d  C_eff=%0d",
                 cycle_count, mmio_acc, c_eff);
        $display("[ST] stall_wr=%0d  stall_rd=%0d  bus_ack=%0d  idle=%0d  both=%0d",
                 stall_wr, stall_rd, bus_ack, bus_idle, bus_both);
        // 比率は千分率(‰)整数で出す (iverilog の実数表示を避ける)
        if (c_eff > 0) begin
            $display("[ST] wr_stall/C_eff   = %0d.%0d %%",
                     (stall_wr*1000)/c_eff/10, (stall_wr*1000)/c_eff%10);
            $display("[ST] rd_stall/C_eff   = %0d.%0d %%",
                     (stall_rd*1000)/c_eff/10, (stall_rd*1000)/c_eff%10);
        end
        if (cycle_count > 0)
            $display("[ST] wr_stall/C_total = %0d.%0d %%",
                     (stall_wr*1000)/cycle_count/10, (stall_wr*1000)/cycle_count%10);
        if ((stall_wr + stall_rd + bus_ack) > 0)
            $display("[ST] wr_stall/bus_busy = %0d.%0d %%",
                     (stall_wr*1000)/(stall_wr+stall_rd+bus_ack)/10,
                     (stall_wr*1000)/(stall_wr+stall_rd+bus_ack)%10);
        // V-b: 恒等式による取りこぼし検算 (計画書 §2.2.1)
        if ((stall_wr + stall_rd + bus_ack + bus_idle + mmio_acc) == cycle_count)
            $display("[ST] IDENTITY OK (sum == C_total)");
        else
            $display("[ST] ★IDENTITY FAIL★ sum=%0d C_total=%0d (取りこぼしあり)",
                     stall_wr + stall_rd + bus_ack + bus_idle + mmio_acc, cycle_count);
        if (bus_both != 0)
            $display("[ST] ★PRECOND FAIL★ mem_rd&&mem_wr が %0d 回。本測定は無効",
                     bus_both);
        $display("-------------------------------------------");
        // [v0.2] 新ゲート G-M (設計書 v17 §4.3)
        $display("[RESULT] G-M MISMATCH = %0d / read_checked = %0d",
                 mism_count, rdchk_count);
        if (rdchk_count == 0)
            $display("[RESULT] G-M INVALID: 照合対象0件 (モニタが機能していない)");
        else if (mism_count == 0)
            $display("[RESULT] G-M PASS");
        else
            $display("[RESULT] G-M FAIL");
        $display("[RESULT] dbg_pc   = $%04x  dbg_sp = $%04x", dbg_pc, dbg_sp);
        $write("[PCHIST]");
        for (k = 0; k < 64; k = k + 1)
            $write(" %04x", pc_hist[(pc_wp + k) % 64]);
        $display("");
        $display("-------------------------------------------");
        // ============================================================
        // [v0.3 ★S-1 是正★] 計画書 v18 §5.3
        //   v0.2 までは PASS 表示が dbg_halt 到達のみに依存しており、
        //   UART 5B の暴走実行でも PASS と表示された(TKT-V7 T-1 で実測)。
        //   ★合格表示と合格条件を一致させる★
        //   ※ $finish のタイミングは変えない(表示分岐のみの変更)。
        //     実行長が変わると C-total が絶対ゲートと比較できなくなる。
        // ============================================================
        pass_final = pass && (tx_count == 9) && (mism_count == 0)
                          && (rdchk_count > 0) && (bus_both == 0);
        if (!pass_final) begin
            $display("[FAILCOND] halt_ok    = %b", pass);
            $display("[FAILCOND] tx_count==9= %b (tx_count=%0d)", (tx_count==9), tx_count);
            $display("[FAILCOND] mism==0    = %b (mism=%0d)", (mism_count==0), mism_count);
            $display("[FAILCOND] rdchk>0    = %b (rdchk=%0d)", (rdchk_count>0), rdchk_count);
            $display("[FAILCOND] both==0    = %b (both=%0d)", (bus_both==0), bus_both);
        end
        if (pass_final)
            $display("=== V8-e DHRY PASS ===");
        else
            $display("=== V8-e DHRY FAIL ===");
        $finish;
    endtask

    // 起動時バナー
    initial begin
        $display("==================================================");
        $display("  tb_cpu_v8b_prod_v0_3  (2026-08-01)");
        $display("  V8-b 本番 TB / MAX_CYCLES=%0d", MAX_CYCLES);
        $display("  DUT: ysd8800_cpu_v0_1 + ysd8800_v5_membus_v0_1");
        $display("       + sd_spi_model_v0_3_poc");
        $display("  設計根拠: v8b_prod_design_memo_v0_3.md (承認済)");
        $display("==================================================");
    end

endmodule
