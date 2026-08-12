// ============================================================
//  ysd8800_mmio_stub_v0_2.sv   v0.2  (2026-07-11)
//  YSD8800 FPGA V3.5 : MMIOスタブ + MMUレジスタ
//
//  設計根拠: v3_design_memo_v0_2.md §4.2  (V3スタブ部・継承)
//            v3_5_design_memo_v0_2.md §4.3 (MMUレジスタ部・新規/レビュー承認済)
//  黄金参照: emu23 v1.09 (emu23_v109.c)
//              MMU_PTR_BASE=0xFF00 / MMU_MCR_ADDR=0xFF10 / MCR_EN=bit0
//              mmu_reset(): for(i<16) ptr[i]=i;  mcr=0;   (L134-137)
//              レジスタ判定: L633/765/787/813 (論理アドレスで直接判定)
//
//  ------------------------------------------------------------
//  【V3(v0.1)からの変更点】
//    (1) MMUレジスタを実装
//          $FF00-$FF0F : PTR[0..15]  R/W 8bit  リセット値 = n (恒等写像)
//          $FF10       : MCR         R/W 8bit  リセット値 = 0x00 (MMU無効)
//          $FF11-$FF1F : 予約(リード0x00・ライト無視)
//    (2) MMUへの供給出力を追加 (ptr_o[0:15] / mmu_en_o)
//    (3) 上記以外の$FC80-$FFFFは従来スタブ挙動(固定0x00・ライト無視)を維持
//  ------------------------------------------------------------
//
//  【★MMUレジスタは常時アクセス可★】(設計メモ §8 Q1・レビュー承認)
//    MCR.EN=0 のときも PTR/MCR は読み書きできる。
//    根拠: emu23のレジスタ判定(L633/765/787/813)は mmu_mode(--mmu起動フラグ)
//          のみを見ており MCR_EN を見ていない。RTLには起動フラグの概念が
//          無いため「常時アクセス可」が正しい。
//    理由: MCRに書けなければMMUを有効化できない(鶏と卵)。
//
//  【★MMUレジスタは変換を受けない★】(設計メモ §2・レビュー承認)
//    本モジュールはアドレスデコーダの MMIO 側に接続され、
//    【論理アドレス】で判定される。MMU(RAM側パス)を通らない。
//    => MMU ON でどうPTRを書き換えてもMMUレジスタは常に見える
//       (自己ロックアウト回避)。
//
//  【原則59】always_comb/always_ff内の定数ビット選択はIcarus 12.0で
//            制約があるため、MCR bit0 の抽出は assign で外出しする。
//            (EI/DI の FLAGS bit7 で踏んだ轍を繰り返さない)
// ============================================================
`timescale 1ns/1ps

module ysd8800_mmio_stub_v0_2 (
    input  logic        clk,
    input  logic        rst_n,

    input  logic [15:0] mmio_addr,
    input  logic [7:0]  mmio_wdata,
    output logic [7:0]  mmio_rdata,
    input  logic        mmio_rd,
    input  logic        mmio_wr,
    output logic        mmio_ready,

    // ---- MMUへの供給(V3.5新規) ----
    // 【Icarus制約回避・原則59系】
    //   unpacked array port (logic [7:0] ptr_o [0:15]) は Icarus 12.0 で
    //   上位モジュール/TBへの伝搬が効かずX固着する事象を実測（本チャット）。
    //   packed vector (128bit) にフラット化して確実に伝搬させる。
    //   ptr_flat_o[8*n +: 8] が PTR[n] に対応する。
    output logic [127:0] ptr_flat_o,   // {PTR[15],...,PTR[1],PTR[0]}
    output logic         mmu_en_o,     // MCR bit0

    // 診断用出力(TB観測専用・機能には無関係)
    output logic [15:0] dbg_last_addr,
    output logic [31:0] dbg_access_count
);

    // ------------------------------------------------------------
    // MMUレジスタアドレス定数 (emu23 v1.09 と一致)
    // ------------------------------------------------------------
    localparam logic [15:0] MMU_PTR_BASE = 16'hFF00;   // PTR[0]
    localparam logic [15:0] MMU_PTR_LAST = 16'hFF0F;   // PTR[15]
    localparam logic [15:0] MMU_MCR_ADDR = 16'hFF10;   // MCR

    logic access;
    assign access = mmio_rd | mmio_wr;

    // ------------------------------------------------------------
    // アドレスヒット判定 (すべて【論理アドレス】で判定・変換を受けない)
    // ------------------------------------------------------------
    logic hit_ptr, hit_mcr;
    assign hit_ptr = (mmio_addr >= MMU_PTR_BASE) && (mmio_addr <= MMU_PTR_LAST);
    assign hit_mcr = (mmio_addr == MMU_MCR_ADDR);

    // PTRインデックス(下位4bit) ... 原則59: assignで外出し
    logic [3:0] ptr_idx;
    assign ptr_idx = mmio_addr[3:0];

    // ------------------------------------------------------------
    // MMUレジスタ本体
    // ------------------------------------------------------------
    logic [7:0] ptr_r [0:15];
    logic [7:0] mcr_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 恒等写像リセット (設計書§4・emu23 mmu_reset())
            //   PTR[n] = n  → MCR=1 にしても変換が恒等になる(安全側)
            for (int i = 0; i < 16; i++) ptr_r[i] <= i[7:0];
            mcr_r <= 8'h00;                  // MMU無効
        end else if (mmio_wr) begin
            // 常時アクセス可(MCR.EN に依存しない)
            if (hit_ptr) ptr_r[ptr_idx] <= mmio_wdata;
            if (hit_mcr) mcr_r          <= mmio_wdata;
        end
    end

    // ---- MMUへの供給 ----
    // packed 128bit へフラット化（Icarus の unpacked array port 制約回避）
    genvar gi;
    generate
        for (gi = 0; gi < 16; gi = gi + 1) begin : g_ptr_flat
            assign ptr_flat_o[8*gi +: 8] = ptr_r[gi];
        end
    endgenerate

    // 原則59: MCR bit0 抽出は assign で外出し
    assign mmu_en_o = mcr_r[0];

    // ------------------------------------------------------------
    // リードデータ多重化 (組合せ)
    //   MMUレジスタ以外は従来スタブ挙動 = 固定0x00
    // ------------------------------------------------------------
    always_comb begin
        if (hit_ptr)      mmio_rdata = ptr_r[ptr_idx];
        else if (hit_mcr) mmio_rdata = mcr_r;
        else              mmio_rdata = 8'h00;   // V3スタブ挙動(予約領域含む)
    end

    // 即時ready(組合せ)。V3から不変。
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
