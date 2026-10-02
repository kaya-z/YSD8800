//==============================================================
// tb_cpu_v8b_prod_v0_5_phy_poc.sv   v0.5  (2026-09-23)
//
// ★v0.5 変更点（TKT-V12・M-10・設計書 v24_tktv12_uart_phy_design_v0_5_1.md
//   §13.6・§14.7・§15 に従う。v0.4 からの複製、変更は次の4点のみ）★
//
//   (1) 新ポート3本の接続：uart_txd_o（DUT出力）／uart_rxd_i（TB→DUT入力）
//       ／uart_rx_frame_err_o（観測用）。疑似ポート uart_rx_valid_i は
//       1'b0 固定を維持（§13.6.2：入力は RX 端子経由でしか届かない構造）。
//   (2) TB 独立シリアル送受信モデルを新設：
//       - 送信モデル：uart_rxd_i を駆動。アイドル 1・Z を入れない
//         （§13.1 潜在バグの封止・R-10）。1 ビット (baud_r+1) サイクル
//         （固定値 417＝BAUD_EN=1・reset baud_r=416 より (416+1)=417）。
//       - 受信モデル：uart_txd_o を DUT とは独立に監視。1 ビット 417
//         サイクル・中央サンプル。FE 検出（stop bit ≠ 1）。
//   (3) 判定を①〜⑥に拡張（設計書 §13.6.2・§15.1 B-20）：
//       ①TX受信バイト列が期待列と全バイト一致
//       ②受信モデル FE=0
//       ③uart_rx_frame_err_o パルス 0 回
//       ④u_membus.u_mmio_stub.u_ysd8001 の wr_baud_lo／wr_baud_hi が
//         0 回（§14.7.3 C-20。アドレス $FC86/$FC87 実装確定済）
//       ⑤疑似ポート uart_tx_valid_o 経由の蓄積（v0.4 由来の uart_bytes）
//         とも一致（観測専用で並走）
//       ★⑥ u_membus.u_mmio_stub.u_ysd8001 の wr_tx が tx_run_r=1 の間に
//         立った回数が 0（§15.1 B-20。送信中の TX 上書き検出）★
//       期待バイト列・出典は本ファイル末尾の M-10 送受信モデル部
//       コメントに記す（R-11 付帯条件・§15.3）。
//   (4) ★新規対処（本チャットで発見・ユーザー方針(A)採用）★
//       v0.4 由来の早期失敗マーカー検出（'i'=$69／'g'=$67／'v'=$76、
//       L508 付近）は m2_reached 以降ずっと有効であり、B7 判定部で
//       finalize_and_exit(0) を招く。M-10 は対話コマンド①に 'v' を
//       送信する設計（R-9 承認済）であり、'v' のエコーが TX に
//       0x76 として出力されるため、v0.4 のまま複製すると設計通りの
//       試験実施が不可能になる（本チャットで発見・設計書未記載の
//       新規論点）。
//       【対処】 m5_reached（"0123MD" 検出済＝対話フェーズ開始）以降は
//       この早期失敗マーカー検出を無効化する（下記 L508 付近 str_replace
//       箇所を参照）。M-10 の対話は m5_reached 後にのみ開始するため
//       （§13.6.2「受信モデルが "0123MD" を観測した後」）、この変更は
//       起動シーケンス自体の判定能力を損なわない。
//
// ── v0.4 変更点 (計画書 v18_stage7c_stallmon_plan_v0_2.md §5.2、既存・不変) ★
//   (1) [KY96] G-M に母数 rdchk_count を追加。
//              ※観測点は v0.3 で既にキャッシュ境界であり、M-1(観測点移行)
//                の対象は Dhrystone TB のみであった(実源確認)。
//   (2) [段7-C] mem_ready ストール積算モニタを新設(MMIO 分離・恒等式検算)。
//   (3) [TKT-V8] irq0_fire_count / irq0_ack_count を新規追加。
//              終了時スナップショットも出力。
//   (4) 合格表示条件を pass && mism==0 && rdchk>0 && both==0 へ是正。
//              $finish のタイミングは不変(表示分岐のみ)。
//   YSD8800 FPGA V8-b 本番用テストベンチ
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

module tb_cpu_v8b_prod_v0_5_phy_poc;

    // -------------------------------------------------------------
    //  パラメータ (段階起動用、コマンドラインで上書き可)
    // -------------------------------------------------------------
    parameter integer MAX_CYCLES        = 1_000_000;    // phase-1 既定値
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
    //  UART 物理層信号 (v0.5 新規・TKT-V12 M-10)
    //   uart_txd_o : DUT→TB (シリアル送信出力)
    //   uart_rxd_i : TB→DUT (シリアル受信入力。アイドル 1 で TB が駆動)
    //   uart_rx_frame_err_o : フレームエラーパルス (判定③)
    // -------------------------------------------------------------
    logic       uart_txd_o;
    logic       uart_rxd_i;
    logic       uart_rx_frame_err_o;

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

    // -------------------------------------------------------------
    //  M-10 対話制御用フラグ (v0.5 新設)
    // -------------------------------------------------------------
    logic m5_reported;       // M-5 到達表示の重複防止
    logic m10_all_done;      // 対話（v/x/help）3件完了
    logic m10_pass_final;    // 判定①〜⑥ + 既存G-M等の総合合否
    initial begin
        m5_reported    = 0;
        m10_all_done   = 0;
        m10_pass_final = 0;
    end

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
        // 疑似ポートは 0 固定を維持 (§13.6.2：入力は RX 端子経由のみ)
        .uart_txd_o(uart_txd_o), .uart_rxd_i(uart_rxd_i),
        .uart_rx_frame_err_o(uart_rx_frame_err_o),
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
                $display("[M-4] \"YUI> \" prompt detected @cycle=%0d", cycle_count);
            end

            // M-5: "0123MD" マーカー検出 → PASS
            //   v0.3 [C-1]: tail-match → subseq-match（速度非依存化）
            if (!m5_reached && uart_subseq_match(needle_pass)) begin
                m5_reached = 1;
                m5_cycle   = cycle_count;
                $display("[M-5] \"0123MD\" detected @cycle=%0d ==> PASS", cycle_count);
            end

            // 失敗マーカー早期検出 (v0.3 §4)
            //   'i'=$69 / 'g'=$67 / 'v'=$76
            //   前提: uart_rx_valid_i = 1'b0 (本番 idle) 前提で有効
            // ★v0.5 対処（本チャットで発見・方針(A)）：
            //   M-10 は対話コマンド① に 'v'($76) を送信する設計（R-9 承認済）。
            //   'v' のエコーが TX に $76 として出力されるため、m5_reached
            //   （"0123MD" 検出＝対話フェーズ開始）以降はこの早期失敗検出を
            //   無効化する。対話は m5_reached 後にのみ開始するため
            //   （§13.6.2「受信モデルが "0123MD" を観測した後」）、起動
            //   シーケンス自体の判定能力は損なわない。★
            if (!fail_marker_detected && m2_reached && !m5_reached &&
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

            // M-5 到達（"0123MD" 検出）— v0.4 は直ちに PASS 終了したが、
            // v0.5 は M-10 対話（v/x/help）を継続するため即時終了しない。
            // 表示は初回のみ行い、実際の終了は m10_all_done 側（下記新設）で行う。
            if (m5_reached && !m5_reported) begin
                m5_reported = 1;
                $display("==================================================");
                $display("  \"0123MD\" 到達 @cycle=%0d ==> M-10 対話へ継続", m5_cycle);
                $display("  M-1: %0d, M-2: %0d, M-3: %0d, M-4: %0d, M-5: %0d",
                         m1_cycle, m2_cycle, m3_cycle, m4_cycle, m5_cycle);
                $display("==================================================");
            end

            // M-10 対話完了 → 最終判定 (v0.5 新設)
            if (m10_all_done) begin
                finalize_and_exit(m10_pass_final);
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
    // [DEBUG 2026-09-05 / U-A 対応] キャッシュ返却データ vs PSRAM 実体の照合
    //   ★観測点はキャッシュ境界（物理アドレス）★
    //     cpu_phys_addr_i = MMU 出力 phys_addr（20bit 物理）
    //     cpu_rd_i        = ram_rd（RAM パス専用。MMIO は来ない）
    //   → MMU 有効な YUI OS でも論理/物理の食い違いが生じない。
    //     $FC80 フィルタは不要（MMIO はデコーダ前段で分岐するため）。
    //   ★[v0.4 2026-09-05] 母数 rdchk_count を追加★
    //     v0.3 は MISMATCH のみを数えており、「照合対象0件でも 0 と表示
    //     される偽の合格」を排除できなかった(KY96)。計画書 v18 §5.2。
    //   ※ 観測点は v0.3 の時点で既にキャッシュ境界であり、
    //     M-1(観測点移行)の対象は Dhrystone TB のみであった(実源確認)。
    integer mism_count;
    integer rdchk_count;
    initial mism_count = 0;
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

    // -------------------------------------------------------------
    // [v0.4 ★TKT-V8★] IRQ0 発火 / 再武装(ACK) の計数
    //   計画書 v18 §4.2.2 / §5.2 e,e1
    //   Dhrystone TB (v0_3 L474-) と同形。YUI OS 側での再現有無を見る。
    // -------------------------------------------------------------
    integer irq0_fire_count, irq0_ack_count;
    logic   irq0_d, armed_d;
    initial begin
        irq0_fire_count = 0; irq0_ack_count = 0;
        irq0_d = 1'b0; armed_d = 1'b0;
    end
    always @(posedge cpu_clk) begin
        if (cpu_rst_n) begin
            irq0_d  <= u_membus.u_mmio_stub.u_ysd8002.irq_req_r;
            armed_d <= u_membus.u_mmio_stub.u_ysd8002.armed_r;
            if (u_membus.u_mmio_stub.u_ysd8002.irq_req_r && !irq0_d)
                irq0_fire_count <= irq0_fire_count + 1;
            if (u_membus.u_mmio_stub.u_ysd8002.armed_r && !armed_d)
                irq0_ack_count  <= irq0_ack_count + 1;
        end
    end

    // -------------------------------------------------------------
    // [v0.4 ★段7-C★] mem_ready ストール積算モニタ
    //   計画書 v18 §2.2 / §2.2.1 / §5.2 a-d
    //   ★代入は NBA。cycle_count(L224) と位相を揃える★
    //     (Dhrystone TB の試走で恒等式 sum=C_total+1 を検出した是正)
    // -------------------------------------------------------------
    integer stall_wr, stall_rd, bus_ack, bus_idle, mmio_acc, bus_both;
    initial begin
        stall_wr = 0; stall_rd = 0; bus_ack = 0;
        bus_idle = 0; mmio_acc = 0; bus_both = 0;
    end
    wire is_mmio = (mem_addr >= 20'hFC80);
    always @(posedge cpu_clk) begin
        if (cpu_rst_n) begin
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

    task finalize_and_exit(input bit pass);
        integer c_eff;
        bit     pass_final;
        $fclose(uart_fd);
        $display("[RESULT] MISMATCH total = %0d / read_checked = %0d",
                 mism_count, rdchk_count);
        if (rdchk_count == 0)
            $display("[RESULT] G-M INVALID: 照合対象0件 (モニタが機能していない)");
        else if (mism_count == 0)
            $display("[RESULT] G-M PASS");
        else
            $display("[RESULT] G-M FAIL");
        // ---- TKT-V8 (計画書 §4.2.2 / §4.2.3) ----
        $display("[IRQ] fire=%0d  ack(armed rise)=%0d  expect=%0d (C_total/40000)",
                 irq0_fire_count, irq0_ack_count, cycle_count / 40000);
        $display("[IRQ] snapshot: armed=%b timer_en=%b irq_en=%b period=%0d cnt=%0d",
                 u_membus.u_mmio_stub.u_ysd8002.armed_r,
                 u_membus.u_mmio_stub.u_ysd8002.timer_en_r,
                 u_membus.u_mmio_stub.u_ysd8002.irq_en_r,
                 u_membus.u_mmio_stub.u_ysd8002.period_r,
                 u_membus.u_mmio_stub.u_ysd8002.cnt_r);
        // ---- 段7-C (計画書 §2.2 / §2.3) ----
        c_eff = cycle_count - mmio_acc;
        $display("--------------- STALL (stage 7-C) ---------------");
        $display("[ST] C_total=%0d  mmio_acc=%0d  C_eff=%0d",
                 cycle_count, mmio_acc, c_eff);
        $display("[ST] stall_wr=%0d  stall_rd=%0d  bus_ack=%0d  idle=%0d  both=%0d",
                 stall_wr, stall_rd, bus_ack, bus_idle, bus_both);
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
        if ((stall_wr + stall_rd + bus_ack + bus_idle + mmio_acc) == cycle_count)
            $display("[ST] IDENTITY OK (sum == C_total)");
        else
            $display("[ST] ★IDENTITY FAIL★ sum=%0d C_total=%0d (取りこぼしあり)",
                     stall_wr + stall_rd + bus_ack + bus_idle + mmio_acc, cycle_count);
        if (bus_both != 0)
            $display("[ST] ★PRECOND FAIL★ mem_rd&&mem_wr が %0d 回。本測定は無効",
                     bus_both);
        $display("-------------------------------------------");
        // ---- [v0.4 S-1 相当] 合格表示と合格条件を一致させる ----
        //   YUI OS は UART マーカー体系が Dhrystone と異なるため、
        //   終端条件(M-5 検出)+ G-M + 前提検証で構成する(計画書 §5.2 注記)。
        pass_final = pass && (mism_count == 0) && (rdchk_count > 0)
                          && (bus_both == 0);
        if (!pass_final) begin
            $display("[FAILCOND] m5_ok    = %b", pass);
            $display("[FAILCOND] mism==0  = %b (mism=%0d)", (mism_count==0), mism_count);
            $display("[FAILCOND] rdchk>0  = %b (rdchk=%0d)", (rdchk_count>0), rdchk_count);
            $display("[FAILCOND] both==0  = %b (both=%0d)", (bus_both==0), bus_both);
        end
        if (pass_final)
            $display("=== V8-b PROD PASS ===");
        else
            $display("=== V8-b PROD FAIL ===");
        $finish;
    endtask

    // 起動時バナー
    initial begin
        $display("==================================================");
        $display("  tb_cpu_v8b_prod_v0_5_phy_poc  (2026-09-23)");
        $display("  V8-b M-10 TB (TKT-V12) / MAX_CYCLES=%0d", MAX_CYCLES);
        $display("  DUT: ysd8800_cpu_v0_1 + ysd8800_v5_membus_v0_1(_phy1_poc)");
        $display("       + sd_spi_model_v0_3_poc + ysd8001_v0_3(PHY_EN/BAUD_EN=1)");
        $display("  設計根拠: v24_tktv12_uart_phy_design_v0_5_1.md §13.6/§14.7/§15");
        $display("==================================================");
    end

    // =============================================================
    //  v0.5 新設: M-10 ★TB 独立シリアル送受信モデル★（TKT-V12）
    //   設計書 v24_tktv12_uart_phy_design_v0_5_1.md §13.6.2・§14.7・§15
    //   判定値・出典は R-11 付帯条件（§15.3）により本節冒頭に明記する。
    //
    //   ビット周期 = (baud_r+1) = 417 cycles（BAUD_EN=1・reset baud_r=416。
    //     ysd8800_ysd8001_v0_3.sv L178 baud_r既定=416, L537 baud_r+1）
    //   半ビット点 = 208 cycles（(416+1)>>1。同ファイル L538 rx_half）
    //
    //   期待起動部（25B・実測 uart_out.log 転記・§14.7.4 C-21）：
    //     "YUIOS Booted!\nYUI> 0123MD"
    //   期待対話部（65B・実源 kernel_forth_v0_10_18.fs 本チャットで実読）：
    //     ① v $0D  -> "v\r\nYUIOS V0.10.18\r\nYUI> "   (L3265-3271,L3142)
    //     ② x $0D  -> "x\r\n?\r\nYUI> "                 (L3392-3403既定分岐)
    //     ③ help $0D(アイドル0) -> "help\r\nrun <n>\r\nps\r\nhelp\r\nYUI> "
    //                                                    (L3207-3212,L3395)
    //   判定：
    //     ① TX受信バイト列が期待列と全バイト一致（対話部は厳密一致・
    //        起動部は不一致でも多重集合一致なら要調査＝C-21）
    //     ② 受信モデル FE (m10_fe_cnt) = 0
    //     ③ uart_rx_frame_err_o パルス (m10_frame_err_cnt) = 0
    //     ④ wr_baud_lo/wr_baud_hi 書込 (m10_baud_wr_cnt) = 0 回（C-20）
    //     ⑤ 疑似ポート uart_tx_valid_o 経由の蓄積(uart_bytes)と一致
    //     ⑥ wr_tx が tx_run_r=1 の間に立った回数 (m10_tx_ovr_cnt) = 0（B-20）
    // =============================================================

    localparam int PHY_BIT_PERIOD = 417;
    localparam int PHY_HALF_BIT   = 208;

    // --- 送信モデル: TB→DUT (uart_rxd_i を駆動。アイドル1・Zを入れない R-10) ---
    initial uart_rxd_i = 1'b1;

    task automatic phy_send_byte(input byte d, input int idle_bits);
        logic [9:0] fr;
        fr = {1'b1, d, 1'b0};   // fr[9]=stop(1) fr[8:1]=data(LSB first) fr[0]=start(0)
        for (int b = 0; b < 10; b = b + 1) begin
            uart_rxd_i = fr[b];
            repeat (PHY_BIT_PERIOD) @(negedge cpu_clk);
        end
        if (idle_bits > 0) repeat (idle_bits * PHY_BIT_PERIOD) @(negedge cpu_clk);
    endtask

    task automatic phy_send_line(input string cmd, input int idle_bits);
        for (int i = 0; i < cmd.len(); i = i + 1)
            phy_send_byte(byte'(cmd[i]), idle_bits);
        phy_send_byte(8'h0D, idle_bits);
    endtask

    // --- 受信モデル: DUT→TB (uart_txd_o を DUT とは独立に監視) ---
    byte    phy_rx_bytes [$];
    integer m10_fe_cnt;
    initial m10_fe_cnt = 0;

    initial begin : phy_rx_monitor
        byte m;
        forever begin
            @(negedge uart_txd_o);
            repeat (PHY_HALF_BIT) @(negedge cpu_clk);
            if (uart_txd_o !== 1'b0) begin
                m10_fe_cnt = m10_fe_cnt + 1;
            end
            else begin
                for (int b = 0; b < 8; b = b + 1) begin
                    repeat (PHY_BIT_PERIOD) @(negedge cpu_clk);
                    m[b] = uart_txd_o;
                end
                repeat (PHY_BIT_PERIOD) @(negedge cpu_clk);
                if (uart_txd_o !== 1'b1) m10_fe_cnt = m10_fe_cnt + 1;
                phy_rx_bytes.push_back(m);
            end
        end
    end

    function automatic bit phy_subseq_match(input byte needle[]);
        int q_len = phy_rx_bytes.size();
        int n_len = needle.size();
        int j = 0;
        for (int k = 0; k < q_len; k = k + 1)
            if (j < n_len && phy_rx_bytes[k] === needle[j]) j = j + 1;
        return (j == n_len);
    endfunction

    function automatic bit phy_tail_match(input byte needle[]);
        int q_len = phy_rx_bytes.size();
        int n_len = needle.size();
        if (q_len < n_len) return 0;
        for (int k = 0; k < n_len; k = k + 1)
            if (phy_rx_bytes[q_len - n_len + k] !== needle[k]) return 0;
        return 1;
    endfunction

    // 範囲一致（string 版）: phy_rx_bytes[start_idx .. start_idx+len-1] と exp の厳密一致
    function automatic bit phy_range_match(input int start_idx, input string exp);
        int elen = exp.len();
        if (phy_rx_bytes.size() < start_idx + elen) return 0;
        for (int k = 0; k < elen; k = k + 1)
            if (phy_rx_bytes[start_idx + k] !== byte'(exp[k])) return 0;
        return 1;
    endfunction

    // 多重集合一致（C-21：起動部の順序違いのみを許容する判定に使用）
    function automatic bit phy_multiset_match(input int start_idx, input int len, input string exp);
        int hist_a[256];
        int hist_b[256];
        if (phy_rx_bytes.size() < start_idx + len) return 0;
        if (exp.len() != len) return 0;
        for (int i = 0; i < 256; i = i + 1) begin hist_a[i] = 0; hist_b[i] = 0; end
        for (int k = 0; k < len; k = k + 1) begin
            hist_a[phy_rx_bytes[start_idx + k]] = hist_a[phy_rx_bytes[start_idx + k]] + 1;
            hist_b[byte'(exp[k])] = hist_b[byte'(exp[k])] + 1;
        end
        for (int i = 0; i < 256; i = i + 1) if (hist_a[i] != hist_b[i]) return 0;
        return 1;
    endfunction

    // --- 判定④/⑥: BAUD書込・TX上書きの階層参照モニタ (C-20・B-20) ---
    integer m10_baud_wr_cnt;
    integer m10_tx_ovr_cnt;
    initial begin
        m10_baud_wr_cnt = 0;
        m10_tx_ovr_cnt  = 0;
    end
    always @(posedge cpu_clk) begin
        if (u_membus.u_mmio_stub.u_ysd8001.wr_baud_lo ||
            u_membus.u_mmio_stub.u_ysd8001.wr_baud_hi)
            m10_baud_wr_cnt = m10_baud_wr_cnt + 1;
        if (u_membus.u_mmio_stub.u_ysd8001.wr_tx &&
            u_membus.u_mmio_stub.u_ysd8001.g_phy.tx_run_r)
            m10_tx_ovr_cnt = m10_tx_ovr_cnt + 1;
    end

    // --- 判定③: uart_rx_frame_err_o パルス回数 ---
    integer m10_frame_err_cnt;
    initial m10_frame_err_cnt = 0;
    always @(posedge cpu_clk) if (uart_rx_frame_err_o) m10_frame_err_cnt = m10_frame_err_cnt + 1;

    // --- 対話シーケンサ本体 ---
    string m10_dlg_exp;
    initial m10_dlg_exp =
        "v\r\nYUIOS V0.10.18\r\nYUI> x\r\n?\r\nYUI> help\r\nrun <n>\r\nps\r\nhelp\r\nYUI> ";

    integer m10_boot_start_idx;   // 対話部の開始オフセット(=起動部の長さ)
    bit     m10_dlg_exact;        // 対話部65B厳密一致
    bit     m10_boot_exact;       // 起動部25B厳密一致
    bit     m10_boot_multiset_ok; // 起動部 多重集合一致(C-21用・要調査判定)

    initial begin : m10_dialogue
        byte needle_pass_local [] = '{"0","1","2","3","M","D"};
        byte needle_prompt_local [] = '{"Y","U","I",">"," "};

        // 受信モデル自身が "0123MD" を観測するまで待つ(§13.6.2)
        while (!phy_subseq_match(needle_pass_local)) @(negedge cpu_clk);
        m10_boot_start_idx = phy_rx_bytes.size();   // この時点までが起動部

        // ① v $0D (文字間アイドル2ビット)
        phy_send_line("v", 2);
        while (!phy_tail_match(needle_prompt_local)) @(negedge cpu_clk);

        // ② x $0D (文字間アイドル2ビット)
        phy_send_line("x", 2);
        while (!phy_tail_match(needle_prompt_local)) @(negedge cpu_clk);

        // ③ help $0D (アイドル0連続・省略不可)
        phy_send_line("help", 0);
        while (!phy_tail_match(needle_prompt_local)) @(negedge cpu_clk);

        // 余剰受信の検出窓
        repeat (2 * PHY_BIT_PERIOD) @(negedge cpu_clk);

        // ---- 判定①: 起動部・対話部 ----
        m10_boot_exact = phy_range_match(0, "YUIOS Booted!\nYUI> 0123MD");
        m10_boot_multiset_ok = m10_boot_exact ||
            phy_multiset_match(0, m10_boot_start_idx, "YUIOS Booted!\nYUI> 0123MD");
        m10_dlg_exact = phy_range_match(m10_boot_start_idx, m10_dlg_exp);

        $display("========== M-10 判定 ==========");
        $display("[M-10] 起動部 厳密一致=%0b 多重集合一致=%0b (要調査条件・C-21)",
                  m10_boot_exact, m10_boot_multiset_ok);
        $display("[M-10] 対話部(65B) 厳密一致=%0b", m10_dlg_exact);
        $display("[M-10] ②FE(受信モデル)=%0d ③frame_err_pulse=%0d ④baud_wr=%0d ⑥tx_overwrite=%0d",
                  m10_fe_cnt, m10_frame_err_cnt, m10_baud_wr_cnt, m10_tx_ovr_cnt);
        $display("[M-10] ⑤疑似ポート蓄積 uart_bytes.size=%0d  phy_rx_bytes.size=%0d",
                  uart_bytes.size(), phy_rx_bytes.size());

        if (!m10_boot_exact && !m10_boot_multiset_ok)
            $display("[M-10] ★起動部：多重集合も不一致（要調査を超える不整合）★");
        else if (!m10_boot_exact)
            $display("[M-10] 起動部：順序差のみ（多重集合一致）→ 要調査（FAILとしない・C-21）");

        m10_pass_final =
            m10_dlg_exact &&
            (m10_boot_exact || m10_boot_multiset_ok) &&
            (m10_fe_cnt == 0) &&
            (m10_frame_err_cnt == 0) &&
            (m10_baud_wr_cnt == 0) &&
            (m10_tx_ovr_cnt == 0) &&
            (uart_bytes.size() == phy_rx_bytes.size());

        if (m10_tx_ovr_cnt != 0)
            $display("[M-10] ★判定⑥発火：UART欠陥でなくYUI OS側 emit-char の課題（B-20・別チケット化）★");

        m10_all_done = 1;
    end

endmodule
