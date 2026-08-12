// ============================================================
//  ysd8800_mmio_stub_v0_3.sv   v0.3  (2026-07-12)
//  YSD8800 FPGA V3.7 : MMIOスタブ + MMUレジスタ + ★YSD8004接続★
//
//  設計根拠: v3_design_memo_v0_2.md   §4.2 (V3スタブ部・継承)
//            v3_5_design_memo_v0_2.md §4.3 (MMUレジスタ部・継承)
//            v3_7_design_memo_v0_2.md §4.2 (YSD8004接続・案B・承認済)
//  黄金参照: emu23 v1.09 (emu23_v109.c)
//              MMU_PTR_BASE=0xFF00 / MMU_MCR_ADDR=0xFF10 / MCR_EN=bit0
//              IRQ_STAT_ADDR=0xFCB2 / IRQ_MASK_ADDR=0xFCB4  (L294-295)
//
//  ------------------------------------------------------------
//  【V3.5(v0.2)からの変更点】★V3.7で追加★
//    (1) YSD8004割込コントローラ(ysd8800_ysd8004_v0_1)をインスタンス化
//    (2) $FCB2-$FCB5 を YSD8004 へルーティング
//          $FCB2 : IRQ_STAT (下位)  R / Write-to-Clear
//          $FCB3 : IRQ_STAT (上位)  R  常時0x00   ★KY-B★
//          $FCB4 : IRQ_MASK (下位)  R/W
//          $FCB5 : IRQ_MASK (上位)  R  常時0x00   ★KY-B★
//    (3) 割込源入力(irq_src_*)を外部ポートとして追加(V4/V6で接続)
//    (4) irq1_o を外部ポートとして追加(CPUのirq_inへ。★レベル信号★)
//    (5) リード多重化に YSD8004 を追加
//
//    ★MMUレジスタ部・スタブ挙動・診断出力は v0.2 から一切不変★
//  ------------------------------------------------------------
//
//  【★案B: スタブはルーティングに徹する★】(設計メモ v0.2 §4.2・承認)
//    YSD8004 の機能実体(レジスタ・W2C・マスク・集約・レベル出力)は
//    すべて ysd8800_ysd8004_v0_1.sv 側にある。本モジュールは
//    「アドレスをデコードして sel/we/wdata を渡し、rdata を選ぶ」だけ。
//    → V4以降(UART/Timer/Storage)も同じ流儀で並べる。
//
//  【★IRQ_MASK リセット値は 0x04★】(KY-A・emu23 L307)
//    リセット値の実体は YSD8004 モジュール側にある。本モジュールでは
//    値を持たない(責務分離)。単体TB(tb_ysd8004_v0_1)で検証済み。
//
//  【原則59】always_comb/always_ff内の定数ビット選択はIcarus 12.0で
//            制約があるため、MCR bit0 の抽出は assign で外出しする。
// ============================================================
`timescale 1ns/1ps

module ysd8800_mmio_stub_v0_3 (
    input  logic        clk,
    input  logic        rst_n,

    input  logic [15:0] mmio_addr,
    input  logic [7:0]  mmio_wdata,
    output logic [7:0]  mmio_rdata,
    input  logic        mmio_rd,
    input  logic        mmio_wr,
    output logic        mmio_ready,

    // ---- MMUへの供給(V3.5・不変) ----
    //   Icarus 12.0 の unpacked array port 制約回避のため packed 128bit
    //   ptr_flat_o[8*n +: 8] が PTR[n] に対応する。
    output logic [127:0] ptr_flat_o,   // {PTR[15],...,PTR[1],PTR[0]}
    output logic         mmu_en_o,     // MCR bit0

    // ---- ★V3.7新規: YSD8004 割込I/F★ ----
    //   割込源入力(1クロックパルス規約・設計メモ §4.3)
    input  logic        irq_src_uart_rx,   // V4で YSD8001 から接続
    input  logic        irq_src_stor,      // V6で YSD8003 から接続
    input  logic        irq_src_uart_tx,   // V4で YSD8001 から接続
    //   CPUへの割込出力 ★レベル信号★ (IRQ_STAT != 0)
    //   CPU側で irq_in = (irq1_o ? 3'd2 : 3'd0) として接続する
    output logic        irq1_o,

    // 診断用出力(TB観測専用・機能には無関係)
    output logic [15:0] dbg_last_addr,
    output logic [31:0] dbg_access_count
);

    // ------------------------------------------------------------
    // アドレス定数 (emu23 v1.09 と一致)
    // ------------------------------------------------------------
    localparam logic [15:0] MMU_PTR_BASE = 16'hFF00;   // PTR[0]
    localparam logic [15:0] MMU_PTR_LAST = 16'hFF0F;   // PTR[15]
    localparam logic [15:0] MMU_MCR_ADDR = 16'hFF10;   // MCR

    // ★V3.7新規: YSD8004 (emu23 L294-295)
    localparam logic [15:0] YS4_BASE     = 16'hFCB2;   // IRQ_STAT (下位)
    localparam logic [15:0] YS4_LAST     = 16'hFCB5;   // IRQ_MASK (上位)

    logic access;
    assign access = mmio_rd | mmio_wr;

    // ------------------------------------------------------------
    // アドレスヒット判定 (すべて【論理アドレス】で判定・変換を受けない)
    // ------------------------------------------------------------
    logic hit_ptr, hit_mcr, hit_ys4;
    assign hit_ptr = (mmio_addr >= MMU_PTR_BASE) && (mmio_addr <= MMU_PTR_LAST);
    assign hit_mcr = (mmio_addr == MMU_MCR_ADDR);
    assign hit_ys4 = (mmio_addr >= YS4_BASE) && (mmio_addr <= YS4_LAST);  // ★V3.7★

    // PTRインデックス(下位4bit) ... 原則59: assignで外出し
    logic [3:0] ptr_idx;
    assign ptr_idx = mmio_addr[3:0];

    // ★V3.7: YSD8004内オフセット(★下位3bit★) ... 原則59: assignで外出し
    //   $FCB2 -> 3'b010 / $FCB3 -> 3'b011 / $FCB4 -> 3'b100 / $FCB5 -> 3'b101
    //
    //   ★【S5 BUG-1 修正】当初2bit(mmio_addr[1:0])としたが、
    //     $FCB2[1:0]=2'b10 / $FCB4[1:0]=2'b00 であり、STAT と MASK が
    //     入れ替わっていた（mmio_addr[2]でしか区別できない）。
    //     3bitにして一意にデコードする。
    logic [2:0] ys4_off;
    assign ys4_off = mmio_addr[2:0];

    // ------------------------------------------------------------
    // MMUレジスタ本体 (V3.5から不変)
    // ------------------------------------------------------------
    logic [7:0] ptr_r [0:15];
    logic [7:0] mcr_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 恒等写像リセット (emu23 mmu_reset())
            for (int i = 0; i < 16; i++) ptr_r[i] <= i[7:0];
            mcr_r <= 8'h00;                  // MMU無効
        end else if (mmio_wr) begin
            // 常時アクセス可(MCR.EN に依存しない)
            if (hit_ptr) ptr_r[ptr_idx] <= mmio_wdata;
            if (hit_mcr) mcr_r          <= mmio_wdata;
        end
    end

    // ---- MMUへの供給 (V3.5から不変) ----
    genvar gi;
    generate
        for (gi = 0; gi < 16; gi = gi + 1) begin : g_ptr_flat
            assign ptr_flat_o[8*gi +: 8] = ptr_r[gi];
        end
    endgenerate

    // 原則59: MCR bit0 抽出は assign で外出し
    assign mmu_en_o = mcr_r[0];

    // ------------------------------------------------------------
    // ★V3.7新規: YSD8004 割込コントローラ (案B: 独立モジュールを接続)
    //   本モジュールはルーティングに徹する。機能実体はYSD8004側。
    // ------------------------------------------------------------
    logic [7:0] ys4_rdata;

    ysd8800_ysd8004_v0_1 u_ysd8004 (
        .clk             (clk),
        .rst_n           (rst_n),
        // MMIOルーティング: 本デバイスがヒットした時のみ sel を上げる
        .sel_i           (hit_ys4 & access),
        .addr_i          (ys4_off),
        .we_i            (mmio_wr),
        .wdata_i         (mmio_wdata),
        .rdata_o         (ys4_rdata),
        // 割込源(外部ポートから素通し。V4/V6で接続)
        .irq_src_uart_rx (irq_src_uart_rx),
        .irq_src_stor    (irq_src_stor),
        .irq_src_uart_tx (irq_src_uart_tx),
        // CPUへの割込出力(レベル)
        .irq1_o          (irq1_o)
    );

    // ------------------------------------------------------------
    // リードデータ多重化 (組合せ)
    //   MMUレジスタ / YSD8004 以外は従来スタブ挙動 = 固定0x00
    // ------------------------------------------------------------
    always_comb begin
        if (hit_ptr)      mmio_rdata = ptr_r[ptr_idx];
        else if (hit_mcr) mmio_rdata = mcr_r;
        else if (hit_ys4) mmio_rdata = ys4_rdata;      // ★V3.7新規★
        else              mmio_rdata = 8'h00;          // V3スタブ挙動
    end

    // 即時ready(組合せ)。V3から不変。
    //   YSD8004 も組合せリード/1クロックライトのためウェイト不要。
    assign mmio_ready = access;

    // ------------------------------------------------------------
    // 診断ラッチ・カウンタ (V3から不変)
    // ------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dbg_last_addr    <= 16'h0000;
            dbg_access_count <= 32'h0000_0000;
        end else if (access) begin
            dbg_last_addr    <= mmio_addr;
            dbg_access_count <= dbg_access_count + 32'd1;
        end
    end

endmodule
