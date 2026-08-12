// ============================================================
//  ysd8800_v37_membus_v0_1.sv   v0.1  (2026-07-12)
//  YSD8800 FPGA V3.7 : メモリサブシステム統合ラッパー
//                      （MMU統合版 + ★YSD8004割込コントローラ★）
//
//  設計根拠: v3_5_design_memo_v0_2.md §3.1 / §3.2（V3.5・継承）
//            v3_7_design_memo_v0_2.md §4.2（YSD8004・案B・承認済 v1.0）
//  黄金参照: emu23 v1.09（emu23_v109.c、--mmu）
//
//  ------------------------------------------------------------
//  【V3.5(ysd8800_v35_membus_v0_1)からの変更点】★V3.7★
//    (1) MMIOスタブを v0.2 → ★v0.3★ に差し替え
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

module ysd8800_v37_membus_v0_1 #(
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

    // ---- ★V3.7新規: YSD8004 割込I/F★ ----
    //   割込源入力（1クロックパルス規約・設計メモ v0.2 §4.3）
    input  logic        irq_src_uart_rx,   // V4で YSD8001 から接続
    input  logic        irq_src_stor,      // V6で YSD8003 から接続
    input  logic        irq_src_uart_tx,   // V4で YSD8001 から接続
    //   CPUへの割込出力 ★レベル信号★（IRQ_STAT != 0）
    output logic        irq1_o,

    // ---- 診断用(TB観測専用) ----
    output logic [15:0]        dbg_mmio_last_addr,
    output logic [31:0]        dbg_mmio_access_count,
    output logic               dbg_mmu_en,        // 現在のMCR.EN
    output logic [PHYS_AW-1:0] dbg_phys_addr,     // MMU変換後の物理アドレス
    output logic [127:0]       dbg_ptr_flat       // PTR[15..0]（packed）
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
    // (2) MMIOスタブ ★v0.3★ … MMUレジスタ(PTR/MCR) + ★YSD8004★
    //     ★MMUの【前段】に位置し、アドレス変換を受けない★
    //     YSD8004($FCB2-$FCB5)は内部でインスタンス化される（案B）
    // ============================================================
    ysd8800_mmio_stub_v0_3 u_mmio_stub (
        .clk(cpu_clk), .rst_n(cpu_rst_n),
        .mmio_addr(mmio_addr), .mmio_wdata(mmio_wdata), .mmio_rdata(mmio_rdata),
        .mmio_rd(mmio_rd), .mmio_wr(mmio_wr), .mmio_ready(mmio_ready),
        .ptr_flat_o(ptr_flat), .mmu_en_o(mmu_en),
        // ★V3.7: 割込I/F（外部ポートへ素通し）★
        .irq_src_uart_rx(irq_src_uart_rx),
        .irq_src_stor   (irq_src_stor),
        .irq_src_uart_tx(irq_src_uart_tx),
        .irq1_o         (irq1_o),
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

    ysd8800_cdc_bridge_v0_2 #(.PHYS_AW(PHYS_AW)) u_cdc_bridge (
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
    // (5) PSRAMコントローラ v0.2 … ★1MB(MEM_AW=20)★
    // ============================================================
    ysd8800_psram_ctrl_v0_2 #(
        .LATENCY_NORMAL(12), .LATENCY_REFRESH(15), .REFRESH_PPM(500),
        .PHYS_AW(PHYS_AW), .MEM_AW(MEM_AW)
    ) u_psram_ctrl (
        .clk(psram_clk), .rst_n(psram_rst_n),
        .addr(psram_addr_w), .wdata(psram_wdata_w), .we(psram_we_w),
        .req(psram_req_w), .ack(psram_ack_w), .rdata(psram_rdata_w),
        .dbg_refresh_hit()
    );

    // ---- 診断出力 ----
    assign dbg_mmu_en    = mmu_en;
    assign dbg_phys_addr = phys_addr;
    assign dbg_ptr_flat  = ptr_flat;

endmodule
