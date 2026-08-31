// ============================================================
//  ysd8800_v5_membus_v0_6.sv   v0.6  (2026-08-28 psram_ctrl v0.3 追従)
//
//    ★v0.6 変更点(工程②-A 段3)★: u_psram_ctrl の参照を v0_2 → ★v0_3★
//      へ追従し、burst_len(常に1) と beat_valid(未接続) を接続した。
//      ★ロジック変更は一切無い(ポート接続の追加のみ)★
//      モジュール名 ysd8800_v5_membus_v0_1 は据置(Case X-1)のため
//      TB群は無改修で通る。
//      期待される効果: ★システムレベルで効果ゼロ(G-0 バイト完全一致)★
//      設計根拠: v10_psram_burst_design_v0_3.md §4
//  ★正式版★
//    v0.5 変更点: u_cdc_bridge の参照を v0_3 → ★v0_4★ へ追従。
//                 (ack_sync_d 除去版。論理変更なし)
//                 ★モジュール名 ysd8800_v5_membus_v0_1 は据え置き(Case X-1)★
//    ------------------------------------------------------------
//    以下 v0.4 までの記録(欠落させない)
//  ysd8800_v5_membus_v0_4.sv   v0.4  (2026-08-25 cdc_bridge v0.3 追従)
//  ★正式版★
//    v0.4 変更点(工程①.5 A-2q):
//      (1) u_cdc_bridge の参照を ysd8800_cdc_bridge_v0_2 → ★v0_3★ へ追従。
//      (2) ★本モジュール名 ysd8800_v5_membus_v0_1 は据え置き(Case X-1)★
//          → TB群(tb_cpu_v8b_prod_v0_2 等)は【無改修】。
//      (3) ロジック変更なし。参照追従のみ。
//    ------------------------------------------------------------
//    以下 v0.3 までの記録(欠落させない)
//  ysd8800_v5_membus_v0_3.sv   v0.3  (2026-08-24 mmio_stub v0.8 追従)
//  ★正式版★
//    v0.3 変更点(①.5 冒頭タスク):
//      (1) u_mmio_stub の参照を ysd8800_mmio_stub_v0_5 → ★v0_8★ へ追従。
//          (未接続MMIO応答 8'h00→8'hFF 是正に伴うモジュール名昇格・案X)
//      (2) ★本モジュール名 ysd8800_v5_membus_v0_1 は据え置き(案X-1)★。
//          これにより TB 群(tb_cpu_v8b_prod_v0_2 等)は【無改修】で済む。
//      (3) ロジック変更なし。参照追従のみ。
//    ------------------------------------------------------------
//    以下 v0.2 までの記録(欠落させない)
//  ysd8800_v5_membus_v0_2.sv   v0.2  (2026-07-19 V6-A YSD8003透過)
//  ★正式版★ (V6-A上位結合・原則43承認済 2026-07-19/CHAT108)
//    v0.2 変更点(CHAT109/Step3):
//      (1) u_mmio_stub の参照実体を v0.6→v0.7 に更新(YSD8003結線版)。
//          モジュール名は ysd8800_mmio_stub_v0_5 のまま据え置き。
//      (2) irq_src_stor 外部入力ポートを【削除】。YSD8003はstub内部で
//          irq_stor_o→irq_src_stor直結され、外部から与える必要が消滅。
//          → CPU/membus irq1_ack透過は不要(そもそも存在せず)。
//      (3) YSD8003 SPI物理層(spi_cs_n_o/spi_sck_o/spi_mosi_o/spi_miso_i)と
//          disk_sectors_i を外部ポートへ透過(TB/上位がSDモデルへ接続)。
//    ★モジュール名は ysd8800_v5_membus_v0_1 のまま据え置き(統合TB無改修)★
//  ~~ysd8800_v5_membus_v0_1.sv   v0.1  (2026-07-17 正式版昇格)~~ ←v0.2で改版
//    昇格記録: poc → 正式版。下位 u_mmio_stub は正式版
//    ysd8800_mmio_stub_v0_5 を参照(poc除去に追従)。
//    OR実装のまま昇格・TCR EN是正はV6以降(v5_design_memo §3.5.2)。
//  YSD8800 FPGA V5 : メモリサブシステム統合ラッパー
//                    （MMU + YSD8004割込 + YSD8001 UART + ★YSD8002 タイマー★）
//
//  ※ V4 (ysd8800_v4_membus_v0_1.sv, 2026-07-12):
//       MMU + YSD8004割込 + ★YSD8001 UART★
//
//  設計根拠: v3_5_design_memo_v0_2.md §3.1 / §3.2（V3.5・継承）
//            v3_7_design_memo_v0_2.md §4.2（YSD8004・案B・継承）
//            v4_design_memo_v0_2.md   §4.1（YSD8001・案B・継承）
//            v5_design_memo_v0_3.md   §4  （YSD8002・案B・★D8/D9承認済★）
//  黄金参照: emu23 v1.10（emu23_v110.c、--mmu）  ★V4 は v1.09★
//
//  ------------------------------------------------------------
//  【V4(ysd8800_v4_membus_v0_1)からの変更点】★V5★
//    (A) MMIOスタブを v0.4 → ★v0.5_poc★ に差し替え
//        （YSD8002 タイマーが内部にインスタンス化される）
//
//    (B) ★irq_timer_o を外部へ貫通させる★
//        ★YSD8004 は経由しない★
//          YSD8004 は IRQ1（UART/ストレージ）の集約器。
//          タイマーは【IRQ0】として CPU に直接入る別系統である。
//        CPU側の結線（TB/トップで行う）:
//          assign irq_in = irq_timer_o ? 3'd1
//                        : (irq1_o     ? 3'd2 : 3'd0);   ★タイマー優先★
//        根拠(emu23_v110.c):
//          L1591: if (irq_pending<0 && YSD8002_tick(..)) irq_pending=1; ←先
//          L1611: if (irq_pending<0 && irq_stat!=0)      irq_pending=2; ←後
//
//    (C) ★★cycle_r: CPUクロックカウンタを新設★★【D8・案A・承認済】
//
//        ★★★【最重要・実機での留意事項】★★★
//          emu23 : cpu.cycle++ は L1230 の1箇所のみ = 【命令数】(CPI=1固定)
//          FPGA  : 本カウンタ                       = 【クロック数】(実CPI≒18)
//          → 両者は【定義上一致しない】。
//
//          案A(実機=クロック数)を採用した理由:
//            案B(命令完了カウンタ)は実機に命令数を数える回路が要り非現実的。
//            案C(TB側でPERIOD調整)はTBが実機を検証しなくなり本末転倒。
//            実機が真実である。
//
//          ★これにより実機で以下が起こる（v5_design_memo §3.6 に詳述）★
//            1. PERIOD=40000 は emu23 では 40000【命令】後に発火するが、
//               実機では 40000【クロック】後 = 4MHz で 10ms 後に発火する。
//               実時間としては妥当だが「命令数」としては約1/18になる。
//            2. YUI OS のプリエンプション間隔（＝コンテキストスイッチ回数）
//               は emu23 と一致しない。回数一致を判定基準にしてはならない。
//            3. ★Dhrystone の SW_SCORE はクロック数を返す。★
//               黄金値 826/48405 のうち【48405（サイクル値）は emu23 専用】。
//               実機では別値になる。実機判定は「完走＋Dhrystone結果値(826)」のみ。
//            4. CYCLE_LO/HI もクロック数。時間換算は clk数 / 4MHz。
//
//          → 判定基準は「完走＋論理結果一致」。絶対サイクル一致は求めない。
//  ------------------------------------------------------------
//
//  【V3.7(ysd8800_v37_membus_v0_1)からの変更点】★V4★
//    (1) MMIOスタブを v0.3 → ★v0.4★ に差し替え
//        （YSD8001 UART が内部にインスタンス化される）
//
//    (2) ★UART割込源ポートを削除★
//        v3.7: irq_src_uart_rx / irq_src_uart_tx を外部から受けていた
//              （V4で接続する、というプレースホルダ）
//        v4  : YSD8001 が MMIOスタブ内部に来たため【内部結線】になった。
//              外部ポートとしては不要になったので削除する。
//        irq_src_stor は V6 まで外部ポートのまま残す。
//
//    (3) ★UART物理層ポートを新規追加★（論点C=案C-1・承認済）
//        uart_rx_valid_i / uart_rx_data_i / uart_tx_valid_o / uart_tx_data_o
//        V4 ではTBが直接叩く疑似ポート。V9 で実シリアライザを接続する。
//
//    ★アドレスデコーダ・MMU・CDCブリッジ・PSRAMは V3.7 から一切不変★
//  ------------------------------------------------------------
//
//  【★アドレスデコーダは無改修でよい★】(V4で確認・KY34)
//    ysd8800_addr_decoder_v0_1 L43: is_mmio = (cpu_mem_addr >= 16'hFC80)
//    → $FC80 以降を【丸ごと】MMIO側へ振っている。
//    → したがって $FC81(UART上位バイト)が PSRAM へ抜けることは
//      構造的に起こりえない。論点A=案A-3 は既に成立している。
//    （emu23 は == 点デコードのため PSRAM に抜けるが、それは
//      yuios_memmap「$FC80- 絶対RAM禁止」規約に違反したアクセスに
//      対する未定義動作であり、仕様として写像しない。→ KY47）
//
//  【V3(ysd8800_v3_membus_v0_1)との関係】
//    V3/V3.5/V3.7 の各ラッパーは【残す】(削除しない)。旧構成での
//    回帰実行を可能にし、デグレ検出の退路を確保するため。
// ============================================================
//          （内部で ysd8800_ysd8004_v0_1 をインスタンス化）
//    (2) 割込源入力(irq_src_uart_rx / irq_src_stor / irq_src_uart_tx)を
//        外部ポートとして追加（V4/V6でデバイスから接続）
//    (3) CPUへの割込出力 irq1_o を外部ポートとして追加
//        ★レベル信号★（IRQ_STAT != 0 の間アサート継続）
//        上位で irq_in = (irq1_o ? 3'd2 : 3'd0) として CPU へ接続する
//
//    ★デコーダ・MMU・CDCブリッジ・PSRAMコントローラは V3.5 から一切不変★
//    ★CPUコア(v0.5.7)も無改修★
//  ------------------------------------------------------------

//  ------------------------------------------------------------
//  【構成】★MMUはデコーダの【後段】・RAM側パスにのみ挿入する★
//
//     CPUコア ysd8800_cpu v0.5.7（★無改修★／論理アドレス16bit）
//           │ mem_addr[15:0] / mem_rd / mem_wr / mem_ready
//     ┌─────┴──────────────┐
//     │ ysd8800_addr_decoder │  ← 【論理アドレス】$FC80判定（V3のまま・無改修）
//     └──┬───────────────┬──┘
//  MMIO側 │               │ RAM側（論理アドレス16bit）
//         │               │
//  ┌──────┴────────┐ ┌────┴──────────┐
//  │ mmio_stub v0.2│ │ ysd8800_mmu   │ ← ★新規（純組合せ）★
//  │  +MMUレジスタ │ │  16page/4KB   │
//  │ PTR[16]/MCR   │─▶│ phys = en     │
//  │ ($FF00-$FF10) │ptr│  ? {ptr[p],o} │
//  │ ★変換外★     │mcr│  : {4'b0,la}  │
//  └───────────────┘ └────┬──────────┘
//   （常時可視・自己救済性）  │ phys_addr[19:0]
//                    ┌───────┴────────┐
//                    │ cdc_bridge v0.2 │ ← ★PHYS_AW=20★
//                    └───────┬────────┘
//                    ┌───────┴────────┐
//                    │ psram_ctrl v0.2 │ ← ★MEM_AW=20（1MB）★
//                    └────────────────┘
//
//  【★なぜMMIOを変換外にするのか★】(設計メモ §2.3・レビュー承認)
//    MMIOを変換対象にすると:
//      (1) MMUの自己ロックアウト … MCR($FF10)自身が変換対象だと、
//          ページテーブル設定次第でMCRに到達できなくなり切り戻し不能
//      (2) 割り込みコントローラの喪失 … コンテキストスイッチ中に
//          割り込みをマスク解除できなくなる
//      (3) カーネルの足元崩壊 … YUI OSはコンテキストスイッチのたびに
//          PTR[0..15]をMMIO経由で書き換える。ここが変換対象だと
//          プロセス切替コードが自分の実行基盤を壊す
//    FM-11/CoCo3(GIME)/Dragon等のMC6809+SAM/DAT系でもI/Oは変換の
//    外側に固定される。「I/Oは常に見えていなければならない」が鉄則。
//    根拠: emu23 rd8()/rd16()/wr8()/wr16() はMMIO判定でreturnし、
//          mmu_translate()に到達しない(L152/638-639/771-772/793/820)。
//
//  【V3(ysd8800_v3_membus_v0_1)との関係】
//    V3ラッパーは【残す】(削除しない)。V3構成での回帰実行を可能にし、
//    デグレ検出の退路を確保するため(設計メモ §8 Q3・レビュー承認)。
//
//  【MMU無効時(MCR.EN=0)の等価性】
//    MMUは恒等写像 phys={4'b0,logical} を出力する。
//    => V3構成とbit-exact等価。V3の全26ベクタが再現するはず(S5で確認)。
// ============================================================
`timescale 1ns/1ps

module ysd8800_v5_membus_v0_1 #(
    parameter int PHYS_AW = 20,       // 物理アドレス幅(20bit=1MB)
    parameter int MEM_AW  = 20        // PSRAMモデルの確保幅(TBで縮小可)
) (
    input  logic        cpu_clk,
    input  logic        cpu_rst_n,

    // ---- CPU抽象バスI/F(V3と完全同一・CPUコアは無改修) ----
    input  logic [15:0] mem_addr,     // 【論理アドレス】
    input  logic [7:0]  mem_wdata,
    output logic [7:0]  mem_rdata,
    input  logic        mem_rd,
    input  logic        mem_wr,
    output logic        mem_ready,

    // PSRAM用の高速クロック(案A CDC同期方式)
    input  logic        psram_clk,
    input  logic        psram_rst_n,

    // ---- YSD8004 割込I/F(V3.7) ----
    //   ★V4変更: irq_src_uart_rx / irq_src_uart_tx を【削除】した。
    //     YSD8001 が MMIOスタブ内部にインスタンス化されたため、
    //     UART の割込源は内部結線となり、外部から与えるものではなくなった。
    //   ★V6-A変更(v0.2): irq_src_stor も【削除】した。
    //     YSD8003 が MMIOスタブ内部にインスタンス化され、irq_stor_o が
    //     stub内で irq_src_stor へ直結された。外部から与える必要が消滅。
    //   CPUへの割込出力 ★レベル信号★（IRQ_STAT != 0）
    output logic        irq1_o,

    // ---- ★V6-A新規: YSD8003 SPI物理層I/F★ (上位結合・CHAT108確定) ----
    //   V6-A ではTB/上位が直接SDモデルへ接続する疑似ポート。
    output logic        spi_cs_n_o,
    output logic        spi_sck_o,
    output logic        spi_mosi_o,
    input  logic        spi_miso_i,
    input  logic [31:0] disk_sectors_i,   // SD容量(セクタ数)

    // ---- ★V4新規: YSD8001 物理層I/F★ (論点C=案C-1・承認済) ----
    //   V4 ではTBが直接叩く疑似ポート。V9 で実シリアライザを接続する。
    input  logic        uart_rx_valid_i,   // 1クロックパルス
    input  logic [7:0]  uart_rx_data_i,
    output logic        uart_tx_valid_o,   // 1クロックパルス(送信開始)
    output logic [7:0]  uart_tx_data_o,

    // ---- ★V5新規: YSD8002 タイマー割込★ ----
    //   ★YSD8004 は経由しない（IRQ0 の別系統）★
    //   CPU側: assign irq_in = irq_timer_o ? 3'd1 : (irq1_o ? 3'd2 : 3'd0);
    output logic        irq_timer_o,       // ★1クロックパルス★

    // ---- ★V5新規: 割込アクノリッジ irq0_ack【案0-a'】★ ----
    //   TB側の CPU が出す IRQ0(timer)受理確定パルスを受け、
    //   mmio_stub 経由で YSD8002 の irq_req_r を下ろす。YSD8004非経由。
    input  logic        irq0_ack,

    // ---- 診断用(TB観測専用) ----
    output logic [15:0]        dbg_mmio_last_addr,
    output logic [31:0]        dbg_mmio_access_count,
    output logic               dbg_mmu_en,        // 現在のMCR.EN
    output logic [PHYS_AW-1:0] dbg_phys_addr,     // MMU変換後の物理アドレス
    output logic [127:0]       dbg_ptr_flat,      // PTR[15..0]（packed）
    // ★V5新規: クロックカウンタ観測（TB診断専用・機能には無関係）★
    output logic [31:0]        dbg_cycle
);

    // ---- デコーダ ⇔ 各パス ----
    logic [15:0] ram_addr, mmio_addr;
    logic [7:0]  ram_wdata, ram_rdata, mmio_wdata, mmio_rdata;
    logic        ram_rd, ram_wr, ram_ready, mmio_rd, mmio_wr, mmio_ready;

    // ---- MMIOスタブ ⇒ MMU への供給線 ----
    logic [127:0] ptr_flat;    // {PTR[15],...,PTR[0]}（Icarus unpacked port制約回避）
    logic         mmu_en;      // MCR bit0

    // ---- MMU出力(物理アドレス) ----
    logic [PHYS_AW-1:0] phys_addr;

    // ============================================================
    // (1) アドレスデコーダ … 【論理アドレス】$FC80判定・V3から無改修
    // ============================================================
    ysd8800_addr_decoder_v0_1 u_decoder (
        .cpu_mem_addr(mem_addr), .cpu_mem_wdata(mem_wdata),
        .cpu_mem_rdata(mem_rdata), .cpu_mem_rd(mem_rd),
        .cpu_mem_wr(mem_wr), .cpu_mem_ready(mem_ready),
        .ram_addr(ram_addr), .ram_wdata(ram_wdata), .ram_rdata(ram_rdata),
        .ram_rd(ram_rd), .ram_wr(ram_wr), .ram_ready(ram_ready),
        .mmio_addr(mmio_addr), .mmio_wdata(mmio_wdata), .mmio_rdata(mmio_rdata),
        .mmio_rd(mmio_rd), .mmio_wr(mmio_wr), .mmio_ready(mmio_ready)
    );

    // ============================================================
    // ★★(1.5) V5新規: CPUクロックカウンタ★★【D8・案A・承認済】
    //
    //   YSD8002 の cycle_i を駆動する。emu23 の cpu.cycle に相当する位置。
    //
    //   ★★【単位が emu23 と違う】★★
    //     emu23_v110.c L1230 : cpu.cycle++  ← 命令実行1回につき+1（CPI=1固定）
    //     本カウンタ          : cpu_clk 1周期につき+1（＝クロック数）
    //     実CPI ≒ 18 のため、同じ PERIOD 値でも発火する「命令数」は約1/18。
    //
    //   ★これは不具合ではなく【案A の設計判断】である★
    //     実機のタイマーはクロックで動く（MC6840 PTM も同様）。
    //     emu23 との一致は「発火する/しない」「ACKで再武装する」という
    //     【論理】で取り、【絶対サイクル】では取らない。
    //
    //   ★実機で YUI OS / Dhrystone を動かす際の留意事項★
    //     → 本ファイル冒頭ヘッダ (C) および v5_design_memo §3.6 を必読。
    //     特に Dhrystone の黄金値 826/48405 のうち
    //     【48405（サイクル値）は emu23 専用であり実機では別値になる】。
    //
    //   32bit幅: 4MHz で約 1073秒(約18分) でラップする。
    //     ラップしても YSD8002 側の比較は (cycle_i >= cnt_r) であり、
    //     ACK 時に cnt_r <= cycle_i + period で再設定されるため、
    //     ラップ跨ぎの1回だけ発火が早まる可能性がある（既知・許容）。
    //     ※ emu23 は uint64_t のため事実上ラップしない。ここは非等価。
    //       V5 のスコープ外（実機長時間運用時の課題として §3.6 に記録）。
    // ============================================================
    logic [31:0] cycle_r;
    always_ff @(posedge cpu_clk or negedge cpu_rst_n) begin
        if (!cpu_rst_n) cycle_r <= 32'd0;
        else            cycle_r <= cycle_r + 32'd1;
    end
    assign dbg_cycle = cycle_r;

    // ============================================================
    // (2) MMIOスタブ ★v0.5(正式)★ … MMUレジスタ(PTR/MCR) + YSD8004
    //                              + YSD8001 + ★YSD8002★
    //     ★MMUの【前段】に位置し、アドレス変換を受けない★
    //     YSD8004($FCB2-$FCB5) / YSD8001($FC80-$FC87) / ★YSD8002($FC90-$FC9F)★
    //     は内部でインスタンス化される（案B）。UART の割込源は内部結線。
    //     ★タイマー割込(irq_timer_o)は YSD8004 を経由せず外部へ直接出る★
    // ============================================================
    ysd8800_mmio_stub_v0_8 u_mmio_stub (   // ★v0.3: v0_5→v0_8 追従(未接続=$FF是正)★
        .clk(cpu_clk), .rst_n(cpu_rst_n),
        .mmio_addr(mmio_addr), .mmio_wdata(mmio_wdata), .mmio_rdata(mmio_rdata),
        .mmio_rd(mmio_rd), .mmio_wr(mmio_wr), .mmio_ready(mmio_ready),
        .ptr_flat_o(ptr_flat), .mmu_en_o(mmu_en),
        // ★V6-A変更: irq_src_stor 結線を削除(stub内部で直結)★
        .irq1_o         (irq1_o),
        // ★V6-A: YSD8003 SPI物理層を外部ポートへ素通し★
        .spi_cs_n_o     (spi_cs_n_o),
        .spi_sck_o      (spi_sck_o),
        .spi_mosi_o     (spi_mosi_o),
        .spi_miso_i     (spi_miso_i),
        .disk_sectors_i (disk_sectors_i),
        // ★V4: YSD8001 物理層（外部ポートへ素通し）★
        .uart_rx_valid_i(uart_rx_valid_i),
        .uart_rx_data_i (uart_rx_data_i),
        .uart_tx_valid_o(uart_tx_valid_o),
        .uart_tx_data_o (uart_tx_data_o),
        // ★V5: YSD8002 タイマー★
        .irq_timer_o    (irq_timer_o),    // IRQ0（YSD8004 非経由）
        .cycle_i        (cycle_r),        // ★D8: クロックカウンタ★
        .irq0_ack       (irq0_ack),       // ★案0-a': 受理確定パルス中継★
        .dbg_last_addr(dbg_mmio_last_addr), .dbg_access_count(dbg_mmio_access_count)
    );

    // ============================================================
    // (3) MMU … ★RAM側パスにのみ挿入（純組合せ）★
    //     packed(128bit) → unpacked(ptr[0:15]) へ展開してMMUへ渡す
    // ============================================================
    logic [7:0] ptr_arr [0:15];
    genvar gp;
    generate
        for (gp = 0; gp < 16; gp = gp + 1) begin : g_ptr_unpack
            assign ptr_arr[gp] = ptr_flat[8*gp +: 8];
        end
    endgenerate

    ysd8800_mmu_v0_1 #(.PHYS_AW(PHYS_AW)) u_mmu (
        .logical_addr (ram_addr),      // ★デコーダ後段のRAM側論理アドレス★
        .mmu_en       (mmu_en),
        .ptr          (ptr_arr),
        .physical_addr(phys_addr)
    );

    // ============================================================
    // (4) CDCブリッジ v0.2 … 物理アドレス(20bit)を受ける
    // ============================================================
    logic [PHYS_AW-1:0] psram_addr_w;
    logic [7:0]         psram_wdata_w, psram_rdata_w;
    logic               psram_we_w, psram_req_w, psram_ack_w;

    ysd8800_cdc_bridge_v0_4 #(.PHYS_AW(PHYS_AW)) u_cdc_bridge (   // ★v0.5: v0_4追従★
        .cpu_clk(cpu_clk), .cpu_rst_n(cpu_rst_n),
        .cpu_phys_addr(phys_addr),          // ★MMU出力(物理)★
        .cpu_mem_wdata(ram_wdata),
        .cpu_mem_rdata(ram_rdata), .cpu_mem_rd(ram_rd),
        .cpu_mem_wr(ram_wr), .cpu_mem_ready(ram_ready),
        .psram_clk(psram_clk), .psram_rst_n(psram_rst_n),
        .psram_addr(psram_addr_w), .psram_wdata(psram_wdata_w), .psram_we(psram_we_w),
        .psram_req(psram_req_w), .psram_ack(psram_ack_w), .psram_rdata(psram_rdata_w)
    );

    // ============================================================
    // (5) PSRAMコントローラ v0.3 … ★1MB(MEM_AW=20)・②-Aバースト対応★
    //     ★v0.6: v0_2 → v0_3 追従。ポート接続2本を追加(ロジック変更なし)★
    //
    //     burst_len は常に 1 に固定する(②-A: 休眠状態)。
    //     キャッシュが無い以上2バイト目以降の置き場所が無く、
    //     バースト経路は誰も叩かない。②-Bでキャッシュが駆動する。
    //     → ★システムレベルで効果が構造的にゼロ★であり、
    //        これがG-0(バイト完全一致)を保証する。
    //
    //     ★幅を明示するのは 'x 混入を防ぐため(R-1)。既定値に頼らない。★
    // ============================================================
    localparam int PS_BLEN_W = $clog2(32) + 1;   // ★v0.6追加: =6★

    ysd8800_psram_ctrl_v0_3 #(
        .LATENCY_NORMAL(12), .LATENCY_REFRESH(15), .REFRESH_PPM(500),
        .PHYS_AW(PHYS_AW), .MEM_AW(MEM_AW), .BURST_MAX(32)
    ) u_psram_ctrl (
        .clk(psram_clk), .rst_n(psram_rst_n),
        .addr(psram_addr_w), .wdata(psram_wdata_w), .we(psram_we_w),
        .req(psram_req_w), .ack(psram_ack_w), .rdata(psram_rdata_w),
        .burst_len (PS_BLEN_W'(1)),   // ★②-A: 常に1(休眠)★
        .beat_valid(),                // ★②-A: 未接続(②-Bでキャッシュへ)★
        .dbg_refresh_hit()            // TB階層参照で観測(設計書 §3.5 案a)
    );

    // ---- 診断出力 ----
    assign dbg_mmu_en    = mmu_en;
    assign dbg_phys_addr = phys_addr;
    assign dbg_ptr_flat  = ptr_flat;

endmodule
