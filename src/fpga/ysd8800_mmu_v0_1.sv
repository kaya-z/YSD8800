// ============================================================
//  ysd8800_mmu_v0_1.sv   v0.1  (2026-07-11)
//  YSD8800 FPGA V3.5 : MMU（FM-11方式 16ページ・ページング）
//
//  設計根拠: YSD8800_MMU_Design_v1_1_0.docx §2-3 / §7
//            v3_5_design_memo_v0_2.md §4.1（レビュー承認済 v1.0）
//  黄金参照: emu23 v1.09 (emu23_v109.c) mmu_translate() L124-132
//
//  【変換式】(設計書 §2-3・emu23 L124-131 と一致)
//      logical_page = logical_addr[15:12]        (4bit / 16論理ページ)
//      page_offset  = logical_addr[11:0]         (12bit / 4KBページ)
//      phys_page    = PTR[logical_page]          (8bit / 256物理ページ)
//      phys_addr    = {phys_page, page_offset}   (20bit / 1MB物理空間)
//
//  【MMU無効時(MCR.EN=0)】恒等写像 phys_addr = {4'b0, logical_addr}
//      → V3のRTLとbit-exact等価（回帰デグレ無の担保・設計メモ §4.4）
//
//  【★挿入位置★】(設計メモ §2・レビュー承認)
//      アドレスデコーダ($FC80論理判定)の【後段】・RAM側パスにのみ挿入する。
//      MMIO(MMUレジスタ自身を含む)はアドレス変換を受けない。
//      根拠: emu23 rd8()/rd16()/wr8()/wr16() はMMIO判定でreturnし、
//            mmu_translate()に到達しない(L152/638-639/771-772/793/820)。
//      理由: MMIOを変換対象にするとMCR自身が消えてMMUを切り戻せなくなる
//            (自己ロックアウト)。MC6809+SAM/DAT系(FM-11/CoCo3/Dragon)でも
//            I/Oは変換の外側に固定される鉄則。
//
//  【★純組合せである必然性★】(設計メモ §4.1 要点1)
//      CPUコアは16bitアクセスを S_MEMR_LO → S_MEMR_HI (addr+1) の
//      2バイトアクセスに分解するFSMである。MMUを純組合せに置けば、
//      各バイトアクセスのアドレスがそれぞれ独立に変換される。
//      → emu23 が mmu_translate(a) と mmu_translate(a+1) を別々に呼ぶ
//        のと自動的に一致する。境界またぎの特別な細工は不要。
//
//      なお 4KBページ境界($1000/$2000/.../$5000等)はすべて偶数アドレスの
//      ため、境界を跨ぐ16bitアクセスは必ず奇数アドレス始まりとなり
//      アライメント例外で弾かれる。=> 跨ぎ16bitアクセスは【原理上発生しない】
//      (v3_5設計レビュー回答書 v1.0 §4)。
//
//  【原則59】always_comb内の定数ビット選択はIcarus 12.0で制約があるため
//            page抽出をassign文で外出しする。
//  【原則63】本モジュールは新規stateを一切追加しない(純組合せ)ため、
//            CPUコアのバス出力always_combへの影響は無い。
//            => 原則63の突き合わせ(state追加時のcase欠落チェック)対象外。
// ============================================================
`timescale 1ns/1ps

module ysd8800_mmu_v0_1 #(
    parameter int PHYS_AW = 20            // 物理アドレス幅(20bit=1MB・設計書§2-2)
) (
    input  logic [15:0]        logical_addr,   // CPU論理アドレス(16bit)
    input  logic               mmu_en,         // MCR bit0 (1=変換有効/0=恒等写像)
    input  logic [7:0]         ptr [0:15],     // PTRレジスタ(MMIO側から供給)
    output logic [PHYS_AW-1:0] physical_addr   // 物理アドレス
);

    // ---- 原則59: always_comb内のビット選択を避け、assignで外出し ----
    logic [3:0]  page;
    logic [11:0] offset;
    assign page   = logical_addr[15:12];   // 論理ページ番号(0-15)
    assign offset = logical_addr[11:0];    // ページ内オフセット(0-4095)

    // ---- 選択された物理ページ番号(8bit) ----
    logic [7:0] phys_page;
    assign phys_page = ptr[page];

    // ---- アドレス変換 ----
    always_comb begin
        if (mmu_en) begin
            // MMU有効: {PTR[page], offset} = 8+12 = 20bit
            physical_addr = {phys_page, offset};
        end else begin
            // MMU無効: 恒等写像(上位ビットは0埋め) => V3とbit-exact等価
            physical_addr = {{(PHYS_AW-16){1'b0}}, logical_addr};
        end
    end

endmodule
