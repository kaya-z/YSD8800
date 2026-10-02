//============================================================================
//  ysd8800_wbuf_v0_2.sv
//
//  YSD8800 ライトバッファ（深さ D=2 相当）
//
//  Version : v0.2   (2026-09-18)
//  設計書  : v23_stage25_wbuf_design_v0_2.md
//  チケット: TKT-V10 (phase4_ticket_ledger_v1_10.md §7.10)
//  工程    : 工程②.5（RTL 追加機能）
//
//----------------------------------------------------------------------------
//  【位置】
//      cache v0.6 → ★本モジュール★ → cdc_bridge v0.5 → psram_ctrl v0.3
//
//      cpu_clk 単一ドメインで閉じる。★CDC 跨ぎ状態を新設しない★
//      （設計書 §6.1 / TKT-V7・KY99 の教訓）。
//
//  【方式A：ドレイン】設計書 §3.2
//      PSRAM 読出の前にバッファを空にする。
//      ★アドレス比較によるフォワーディングは行わない★
//      → up_rd_i が来たら wb_valid_r が下りるまで無条件に待たせる。
//         アドレス一致判定を入れた時点で方式B になる（設計書 §5.1）。
//
//  【バッファの形】設計書 §4.1
//      アドレス1本 ＋ 2バイトのデータ ＋ バイト有効フラグ。
//      ★ペア判定は「偶数境界」ではなく wb_addr_r ± 1 で行う★
//      （設計書 §4.1.1 / M-2。16bit アクセスの整列は保証されていない。
//        下位バイト先行／上位バイト先行のどちらも仮定しない）。
//
//  【up_ready_o は純組合せ】設計書 §4.4.1 / C-2
//      現行 cache の cpu_ready_o = br_ready_i は純組合せ素通しであり、
//      ★バイパス時に W-0（完全一致）を取るにはこの経路を維持する必要がある★
//
//  【MMIO】設計書 §2.3-①
//      MMIO は is_mmio=(addr>=$FC80) により membus 側で別経路
//      （mmio_stub 直行）。★本モジュールは MMIO に一切触れない★
//
//  【契約 C-α'（境界②）】設計書 §6.2.1 / C-1
//      ca_viol は違反条件にアドレス一致を含む（cache_v0_6.sv L572-575）。
//      ドレインの2バイト目はアドレスが ±1 異なるため違反にならない。
//      ★実装上の要件は「2バイト目でアドレスを必ず更新する」ことのみ★
//      → 無駄な1サイクル空きを入れない。
//
//  【FLUSH/CEN 立下り】設計書 §5.4.1 / C-4
//      ★ドレイン先行の保証主体は本モジュール自身★
//      flush_req_i を受けたら wb_valid_r が下りるまで flush_ack_o を返さない。
//      （CCR 受領側にバッファ状態を見せない＝モジュール間依存を作らない）
//
//============================================================================

`default_nettype none

module ysd8800_wbuf_v0_2 #(
    parameter int PHYS_AW = 20
)(
    input  wire                  cpu_clk,
    input  wire                  cpu_rst_n,

    //---- 制御 ---------------------------------------------------------
    //  wbuf_en_i=0 : 全面バイパス（純組合せ素通し）
    //  ★測定は mmio_stub の _poc でリセット値 1'b1 として与える★
    //    CCR ビット割当は TKT-V11 解決後（設計書 §8.1）
    input  wire                  wbuf_en_i,

    //---- 上流（cache の br_* を受ける）---------------------------------
    input  wire [PHYS_AW-1:0]    up_addr_i,
    input  wire [7:0]            up_wdata_i,
    input  wire                  up_rd_i,
    input  wire                  up_wr_i,
    output wire [7:0]            up_rdata_o,
    output wire                  up_ready_o,

    //---- 下流（cdc_bridge の cpu_mem_* へ）-----------------------------
    output wire [PHYS_AW-1:0]    dn_addr_o,
    output wire [7:0]            dn_wdata_o,
    output wire                  dn_rd_o,
    output wire                  dn_wr_o,
    input  wire [7:0]            dn_rdata_i,
    input  wire                  dn_ready_i,

    //---- FLUSH / CEN 立下り（設計書 §5.4.1）-----------------------------
    input  wire                  flush_req_i,
    output wire                  flush_ack_o,

    //---- 観測（TB 用・設計書 §7.2）--------------------------------------
    output wire                  dbg_wb_hit_o,    // 書込をバッファが吸収した
    output wire                  dbg_wb_drain_o,  // ドレイン実行中
    output wire                  dbg_wb_full_o,   // 非連続書込で待たせた
    // ★G-M 拡張（案a）用に内部状態を出す（設計書 §6.3.2）★
    output wire                  dbg_wb_valid_o,
    output wire [PHYS_AW-1:0]    dbg_wb_addr_o,
    output wire [1:0]            dbg_wb_be_o,
    output wire [7:0]            dbg_wb_data0_o,
    output wire [7:0]            dbg_wb_data1_o
);

    //========================================================================
    //  1. 状態
    //========================================================================
    //   S_IDLE  : バッファ空
    //   S_HOLD  : 1バイト以上を保持。まだ下流へ送出していない
    //             （隣接バイトの追記を待つ。これが D=2 相当の吸収を生む）
    //   S_DRAIN : 下流へ送出中
    localparam logic [1:0] S_IDLE  = 2'd0;
    localparam logic [1:0] S_HOLD  = 2'd1;
    localparam logic [1:0] S_DRAIN = 2'd2;

    logic [1:0]          st_r;
    logic [PHYS_AW-1:0]  wb_addr_r;     // 保持している最初のバイトのアドレス
    logic [7:0]          wb_data_r [0:1];
    logic [1:0]          wb_be_r;
    logic                wb_valid_r;
    logic                drain_idx_r;   // ドレイン中に送出しているバイト位置

    //========================================================================
    //  2. 上流要求の分類（組合せ）
    //========================================================================
    wire en = wbuf_en_i;

    // 隣接判定（★±1・偶数境界を問わない★ 設計書 §4.1.1）
    wire hit_same = wb_valid_r && (up_addr_i == wb_addr_r);
    wire hit_up   = wb_valid_r && (up_addr_i == (wb_addr_r + PHYS_AW'(1)));
    wire hit_down = wb_valid_r && (up_addr_i == (wb_addr_r - PHYS_AW'(1)));

    //  受理できる書込か
    //   ・空          → 常に受理（新規登録）
    //   ・上隣で be[1] 未使用 → 受理（追記）
    //   ・下隣        → 受理（先頭を1つ下げて詰め直す。be[1] 未使用が条件）
    //   ・同一アドレスへの再書込 → ★受理しない★
    //       同じバイトを上書きすると、送出順と最終値の関係が
    //       状態に依存する。単純化のためドレインさせる。
    wire can_take_new  = (st_r == S_IDLE);
    wire can_take_up   = (st_r == S_HOLD) && hit_up   && (wb_be_r[1] == 1'b0);
    wire can_take_down = (st_r == S_HOLD) && hit_down && (wb_be_r[1] == 1'b0);
    wire can_take      = can_take_new | can_take_up | can_take_down;

    wire wr_accept = en & up_wr_i & can_take;

    //  待たせる条件
    //   ・読出   : wb_valid_r が立っている間（★アドレスを見ない★ §5.1）
    //   ・書込   : 受理できない（非連続・同一アドレス・ドレイン中）
    wire rd_block = en & up_rd_i & wb_valid_r;
    wire wr_block = en & up_wr_i & ~can_take;

    //  ドレインを開始すべきか
    //   ・両バイト埋まった              → 即開始
    //   ・待たせている要求がある        → 開始
    //   ・FLUSH 要求                    → 開始
    //   ・★上流アイドルが HOLD_GRACE サイクル継続 → 開始★
    //
    //  ★HOLD_GRACE を設ける理由（v0.1 デバッグで判明）★
    //    16bit ペアは 1 バイト目の ready の次サイクルに 2 バイト目が来る
    //    （cache_v0_6.sv L546-548「実CPUは ready の次サイクルに新しい要求を
    //      出す（S_MEMR_LO→S_MEMR_HI 等）」）。
    //    アイドルを見た瞬間にドレインを始めると、要求と要求の間に
    //    1 サイクルでも隙間が空いた時点でペアの吸収機会を失う。
    //    ★猶予を置かない実装は「要求が必ず密着する」という暗黙前提に
    //      依存しており、疎になった途端に効果が消える（KY98 と同型）。★
    localparam int HOLD_GRACE = 3;     // 実CPUのペア到着は1〜2サイクル以内
    logic [1:0] idle_cnt_r;

    wire hold_full     = (st_r == S_HOLD) && (wb_be_r == 2'b11);
    wire upstream_idle = ~up_rd_i & ~up_wr_i;
    wire idle_expired  = (idle_cnt_r >= 2'(HOLD_GRACE - 1));
    wire drain_start   = (st_r == S_HOLD) &&
                         (hold_full | rd_block | wr_block | flush_req_i |
                          (upstream_idle & idle_expired));

    //========================================================================
    //  3. ドレイン制御（組合せ）
    //========================================================================
    //  be=0 のバイトはスキップする（8bit 単発書込の場合）
    wire       drain_active = (st_r == S_DRAIN);
    wire       cur_be       = wb_be_r[drain_idx_r];
    wire       drain_beat   = drain_active & cur_be & dn_ready_i;
    wire       drain_skip   = drain_active & ~cur_be;
    wire       drain_last   = (drain_idx_r == 1'b1);

    //========================================================================
    //  4. 下流ポート（組合せ）
    //========================================================================
    //  ★バイパス時は純組合せ素通し（W-0 の完全一致に必須）★
    assign dn_addr_o  = ~en ? up_addr_i
                      : drain_active ? (wb_addr_r + PHYS_AW'(drain_idx_r))
                      : up_addr_i;

    assign dn_wdata_o = ~en ? up_wdata_i
                      : drain_active ? wb_data_r[drain_idx_r]
                      : up_wdata_i;

    assign dn_wr_o    = ~en ? up_wr_i
                      : drain_active ? cur_be
                      : 1'b0;          // 有効時、書込は必ずバッファ経由

    //  読出はバッファが空のときだけ下流へ通す
    assign dn_rd_o    = ~en ? up_rd_i
                      : (up_rd_i & ~wb_valid_r);

    //========================================================================
    //  5. 上流ポート（組合せ・★登録しない★ 設計書 §4.4.1）
    //========================================================================
    assign up_rdata_o = dn_rdata_i;

    assign up_ready_o = ~en          ? dn_ready_i      // バイパス：現行と同一
                      : wr_accept    ? 1'b1            // 書込を吸収：即 ready
                      : (rd_block | wr_block) ? 1'b0   // ドレイン待ち
                      : up_rd_i      ? dn_ready_i      // 素通しの読出
                      : 1'b0;

    //========================================================================
    //  6. FLUSH（設計書 §5.4.1）
    //========================================================================
    //  ★wb_valid_r が下りるまで ack を返さない★
    assign flush_ack_o = ~en ? 1'b1 : (flush_req_i & ~wb_valid_r);

    //========================================================================
    //  7. 状態機械
    //========================================================================
    always_ff @(posedge cpu_clk or negedge cpu_rst_n) begin
        if (!cpu_rst_n) begin
            st_r         <= S_IDLE;
            wb_addr_r    <= '0;
            wb_data_r[0] <= 8'h00;
            wb_data_r[1] <= 8'h00;
            wb_be_r      <= 2'b00;
            wb_valid_r   <= 1'b0;
            drain_idx_r  <= 1'b0;
            idle_cnt_r   <= 2'd0;
        end
        else if (!en) begin
            // バイパス中は常に空に保つ（有効化直後の残留を防ぐ）
            st_r         <= S_IDLE;
            wb_be_r      <= 2'b00;
            wb_valid_r   <= 1'b0;
            drain_idx_r  <= 1'b0;
            idle_cnt_r   <= 2'd0;
        end
        else begin
            // ★unique は Icarus 12.0 が無視する（vvp.tgt sorry）ため付けない。★
            //   効かない修飾子を残すと「排他性が検査されている」と誤解を招く。
            //   default を必ず置くことで同等の安全性を確保する。
            case (st_r)

            //----------------------------------------------------------------
            S_IDLE: begin
                if (up_wr_i) begin
                    wb_addr_r    <= up_addr_i;
                    wb_data_r[0] <= up_wdata_i;
                    wb_data_r[1] <= 8'h00;
                    wb_be_r      <= 2'b01;
                    wb_valid_r   <= 1'b1;
                    drain_idx_r  <= 1'b0;
                    idle_cnt_r   <= 2'd0;
                    st_r         <= S_HOLD;
                end
            end

            //----------------------------------------------------------------
            S_HOLD: begin
                if (can_take_up & up_wr_i) begin
                    // 上隣へ追記：アドレスは据え置き
                    wb_data_r[1] <= up_wdata_i;
                    wb_be_r[1]   <= 1'b1;
                    st_r         <= S_DRAIN;      // 両バイト揃った → 即ドレイン
                    drain_idx_r  <= 1'b0;
                end
                else if (can_take_down & up_wr_i) begin
                    // 下隣へ追記：★先頭を1つ下げ、既存を上位へ移す★
                    wb_addr_r    <= up_addr_i;
                    wb_data_r[1] <= wb_data_r[0];
                    wb_data_r[0] <= up_wdata_i;
                    wb_be_r      <= 2'b11;
                    st_r         <= S_DRAIN;
                    drain_idx_r  <= 1'b0;
                end
                else if (drain_start) begin
                    st_r        <= S_DRAIN;
                    drain_idx_r <= 1'b0;
                    idle_cnt_r  <= 2'd0;
                end
                else if (upstream_idle) begin
                    if (!idle_expired) idle_cnt_r <= idle_cnt_r + 2'd1;
                end
                else begin
                    idle_cnt_r <= 2'd0;   // 要求が来たら猶予を数え直す
                end
            end

            //----------------------------------------------------------------
            S_DRAIN: begin
                if (drain_skip) begin
                    // 無効バイトは送出せず次へ
                    if (drain_last) begin
                        st_r       <= S_IDLE;
                        wb_valid_r <= 1'b0;
                        wb_be_r    <= 2'b00;
                    end
                    else begin
                        drain_idx_r <= 1'b1;
                    end
                end
                else if (drain_beat) begin
                    if (drain_last) begin
                        st_r       <= S_IDLE;
                        wb_valid_r <= 1'b0;
                        wb_be_r    <= 2'b00;
                    end
                    else begin
                        drain_idx_r <= 1'b1;
                    end
                end
            end

            //----------------------------------------------------------------
            default: st_r <= S_IDLE;
            endcase
        end
    end

    //========================================================================
    //  8. 観測出力
    //========================================================================
    assign dbg_wb_hit_o   = wr_accept;
    assign dbg_wb_drain_o = drain_active;
    assign dbg_wb_full_o  = wr_block;

    //  ★G-M 拡張（案a）用：期待値の重ね合わせに使う（設計書 §6.3.2）★
    assign dbg_wb_valid_o = wb_valid_r;
    assign dbg_wb_addr_o  = wb_addr_r;
    assign dbg_wb_be_o    = wb_be_r;
    assign dbg_wb_data0_o = wb_data_r[0];
    assign dbg_wb_data1_o = wb_data_r[1];

endmodule

`default_nettype wire

//============================================================================
//  改版履歴
//----------------------------------------------------------------------------
//  v0.2  2026-09-18  ★HOLD_GRACE（猶予カウンタ）を追加★。
//                    v0.1 は upstream_idle を見た瞬間にドレインを開始しており、
//                    要求間に1サイクルでも隙間が空くとペア吸収の機会を失った
//                    （単体TB W-1a/W-1b FAIL で発覚）。
//                    ★「要求は必ず密着する」という暗黙前提への依存であった（KY98 同型）。★
//                    なお仮説検証で一時追加した S_GAP 状態は
//                    ★棄却されたため除去した★（残すと必要な状態と誤認される）。
//  v0.1  2026-09-18  新規作成（TKT-V10 / 設計書 v23_stage25_wbuf_design_v0_2.md）
//                    ・方式A（ドレイン）／アドレス比較なし
//                    ・ペア判定は ±1（偶数境界を仮定しない・M-2）
//                    ・up_ready_o は純組合せ（C-2）
//                    ・CDC 跨ぎ状態を新設しない（§6.1）
//                    ・FLUSH ドレイン先行は本モジュールが保証（C-4）
//                    ・G-M 拡張用に内部状態を dbg_* で出す（M-1）
//============================================================================
