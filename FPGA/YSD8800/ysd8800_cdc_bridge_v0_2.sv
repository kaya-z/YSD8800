// ============================================================
//  ysd8800_cdc_bridge_v0_2.sv   v0.2  (2026-07-11)
//  YSD8800 FPGA V3.5 : CPU(4MHz)⇔PSRAM(高速)間 CDCブリッジ
//                      ★物理アドレス20bit対応(PHYS_AWパラメタライズ)★
//
//  設計根拠: v3_design_memo_v0_2.md §4.1.1〜§4.1.3 (V3・CDC方式)
//            v3_5_design_memo_v0_2.md §4.2         (V3.5・20bit化/レビュー承認済)
//
//  ------------------------------------------------------------
//  【V3(v0.1)からの変更点】★これがV3.5の必須改修★
//    (1) parameter int PHYS_AW = 20 を追加
//    (2) 入力を cpu_mem_addr[15:0] → cpu_phys_addr[PHYS_AW-1:0] に変更
//        （MMUが出力する【物理アドレス】を受ける）
//    (3) 出力 psram_addr を [15:0] → [PHYS_AW-1:0] に拡幅
//    それ以外(req/ack 4相・2FF同期器・req_holdワンショット)はV3から不変。
//
//  【★なぜこの改修が必須か★】(v3_5_design_memo §4.2・KY34で検出)
//    V3実装の実態:
//      - ysd8800_psram_ctrl_v0_1 : parameter PHYS_AW = 20 (デフォルト20bit)
//                                  → 単体では既に20bit対応済
//      - ysd8800_cdc_bridge_v0_1 : output logic [15:0] psram_addr;  ← 16bit固定
//      - ysd8800_v3_membus_v0_1  : PSRAMを .PHYS_AW(16) でオーバーライド
//                                  ← 意図的に16bitへ絞っていた
//    HANDOVER_CHAT80 §4 の「物理アドレス線は既に20bit幅で引いてある」は
//    PSRAMコントローラのみに当てはまり、CDCブリッジには当てはまらなかった。
//    これを鵜呑みにすると、MMUを繋いでも【上位4bitが物理的に捨てられ、
//    リマップが全く効かない】という致命的バグになる。
//    => kaizen新原則候補: 「引継文書の『引いてある』は幅まで実ソース確認する」
//  ------------------------------------------------------------
//
//  【設計上の要点(V3から継承・自己レビューで検出した落とし穴)】
//   ysd8800_cpu_v0_1.sv 実照合の結果、S_MEMR_LO→S_MEMR_HI や
//   S_IMML→S_IMMHのように、mem_rd/mem_wrが「アドレスだけ変えて
//   連続で1のまま」次のバスサイクルへ続くケースが多数ある
//   (mem_rdの立下りを新規要求の区切りに使えない)。
//   このためブリッジ自身が「ack後1サイクルだけreq_levelを強制的に
//   下げるワンショット・ホールド」を持ち、CPU側のrd/wrが継続して
//   いても新規要求ごとに req に立下り→立上りの1サイクル分の
//   ギャップを作る。これを高速側で立上りエッジ検出することで、
//   同一要求の多重発行を防止しつつ背中合わせの連続要求も正しく
//   区別できる(案A最大の落とし穴・fixorder v1.0 §4)。
// ============================================================
`timescale 1ns/1ps

module ysd8800_cdc_bridge_v0_2 #(
    parameter int PHYS_AW = 20        // ★V3.5追加: 物理アドレス幅(20bit=1MB)★
) (
    // ---- CPU側(4MHzドメイン): 抽象バスI/F ----
    input  logic               cpu_clk,
    input  logic               cpu_rst_n,
    input  logic [PHYS_AW-1:0] cpu_phys_addr,   // ★MMU出力(物理アドレス)を受ける★
    input  logic [7:0]         cpu_mem_wdata,
    output logic [7:0]         cpu_mem_rdata,
    input  logic               cpu_mem_rd,
    input  logic               cpu_mem_wr,
    output logic               cpu_mem_ready,

    // ---- PSRAM側(高速ドメイン): req/ackレベル4相ハンドシェイク ----
    input  logic               psram_clk,
    input  logic               psram_rst_n,
    output logic [PHYS_AW-1:0] psram_addr,      // ★16 → PHYS_AW に拡幅★
    output logic [7:0]         psram_wdata,
    output logic               psram_we,        // 1=write, 0=read
    output logic               psram_req,       // レベル信号(要求中1・ackを見て自ら下げる)
    input  logic               psram_ack,       // レベル信号(受理完了中1・reqが下がるまで維持)
    input  logic [7:0]         psram_rdata
);

    // ================= CPU側(4MHzドメイン) =================
    logic       req_hold;      // ack直後の1サイクルだけreq_levelを強制0にする
    logic       req_level;     // psram_clk側へ渡す要求レベル
    logic [1:0] ack_sync;      // 高速→CPU 2FF同期器
    logic       ack_sync_d;    // エッジ検出用(1サイクル遅延)

    assign req_level   = (cpu_mem_rd | cpu_mem_wr) & !req_hold;
    assign psram_addr  = cpu_phys_addr;          // ★幅一致(PHYS_AW)★
    assign psram_wdata = cpu_mem_wdata;
    assign psram_we    = cpu_mem_wr;

    always_ff @(posedge cpu_clk or negedge cpu_rst_n) begin
        if (!cpu_rst_n) begin
            ack_sync      <= 2'b00;
            ack_sync_d    <= 1'b0;
            req_hold      <= 1'b0;
            cpu_mem_ready <= 1'b0;
            cpu_mem_rdata <= 8'h00;
        end else begin
            // 2FF同期器: psram_ack(高速ドメイン)をCPUクロックへ
            ack_sync   <= {ack_sync[0], psram_ack};
            ack_sync_d <= ack_sync[1];

            cpu_mem_ready <= 1'b0; // デフォルト(1クロックパルス)

            if (ack_sync[1] & !ack_sync_d) begin
                // ack(同期後)立上りエッジ検出 = このアクセス完了
                cpu_mem_ready <= 1'b1;
                cpu_mem_rdata <= psram_rdata;   // ack確定後は安定(§4.1.3)
                req_hold      <= 1'b1;          // 次サイクルだけreqを強制的に下げる
            end else begin
                req_hold <= 1'b0;               // ホールドは1サイクルのみ
            end
        end
    end

    // ================= 2FF同期器: CPU→高速側へreqを渡す =================
    logic [1:0] req_sync;
    always_ff @(posedge psram_clk or negedge psram_rst_n) begin
        if (!psram_rst_n) req_sync <= 2'b00;
        else              req_sync <= {req_sync[0], req_level};
    end
    assign psram_req = req_sync[1];

endmodule
