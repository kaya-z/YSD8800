// ============================================================
//  ysd8800_cache_v0_6.sv   v0.6  (2026-09-05 工程②-B ★TKT-V7★)
//  ★連続ミス時の fill_hit_byte_r 未更新欠陥の修正（案 B'）★
//
//    ★v0.6 変更点(TKT-V7)★:
//      (1) psram_clk 側で ★beat_valid_i の立上り(burst_start)★ を
//          バースト開始とみなし、beat_cnt_r を 0 相当にすると同時に
//          req_offset / fill_index を ★psram 側へラッチ★する。
//          → 比較の両辺が psram_clk ドメイン内で閉じる。
//      (2) ★beat_no を現ビート番号の単一定義★とし、捕捉比較と
//          ポートA書込アドレスで共用する（1ビートずれを構造で排除）。
//      (3) ★fill_armed_r★ と RTL 内 $error アサーションを追加し、
//          前提 P-A/P-B が破れた場合に無音のデータ破壊ではなく
//          即時失敗させる。
//      (4) 段4 コメント(L373〜)を実態に合わせて整理（I-5・KY100）。
//          ★旧記述は削除せず経緯として保持★（KY41）。
//      (5) それ以外の論理は v0.5 から変更していない。
//      設計書: `v17_tkt_v7_fix_design_v0_4.md` §3.5
//
//    ---- 以下は v0.5 の記述 ----
//
//    ★v0.5 変更点(TKT-V6)★:
//      (1) §契約アサーション部に ★ca_viol / ca_reported★ を追加し、
//          ★1事象につき1回だけ★ $error を出す（再アーム＝違反条件が偽）。
//      (2) ★違反条件そのもの・メッセージ書式は一切変更していない★。
//          変えたのは★報告の粒度のみ★であり、検出能力は保存される。
//      (3) 相互注記に「両境界は同一の再アーム方式を採る」を追記。
//      (4) ★それ以外の論理は v0.4 から一切変更していない★。
//      (5) 版数を上げた理由: ★ファイルが変わったから★（KY84）。
//    設計根拠: v14_tkt_v6_fix_design_v0_2.md §3.2 / §3.5A
//    ------------------------------------------------------------
//    以下 v0.4 までの記録(欠落させない)
//  ysd8800_cache_v0_4.sv   v0.4  (2026-09-03 工程②-B ★段5-a★)
//  ★機能 A：FLUSH による全ライン無効化★
//
//    ★v0.4 変更点(工程②-B 段5-a)★:
//      (1) §4 の tag/valid 更新ブロックに ★ccr_flush_pulse_i による
//          valid_r 全ライン一括クリア★ を追加。fill_done より優先。
//      (2) ★それ以外の論理は v0.3 から一切変更していない★。
//      (3) 版数を上げた理由: ★ファイルが変わったから★（KY84）。
//    設計根拠: v13_stage5_impl_plan_v0_2.md §2.2 A / §4.1.1
//    ------------------------------------------------------------
//    以下 v0.3 までの記録(欠落させない)
//  ysd8800_cache_v0_3.sv   v0.3  (2026-09-01 工程②-B 段4)
//  ★ライトスルー／ノーライトアロケート★
//
//  設計根拠:
//    v11_cache_core_design_v0_4.md
//       §1.3 (ドメイン分割)  §1.5 (DPB RDW)  §3 (アドレス分解)
//       §4   (記憶構造)      §6.5 (投機読出) §7.1 (バイパス/M-11/M-9)
//       §7.2 (読み出し)      §7.5 (フィル中の CPU 要求)
//    v11_cache_stage3_design_memo_v0_2.md
//       D-C1 (ライン先頭丸め＋burst_len 切替・M-1)
//       D-C2 (req_offset_r の CDC・2FF を掛けない)
//       D-C4 (書込ライン無効化・M-3 暫定措置)
//
//  ------------------------------------------------------------
//  ★段3 のスコープ★
//  ------------------------------------------------------------
//    実装する:
//      (1) CEN=0 の純組合せバイパス（段2 と同一・G-0 の成立条件）
//      (2) tag_ram / valid_r / data_ram(DPB) とヒット判定
//      (3) 投機読出 + data_q_valid（M-11）
//      (4) ミス時のラインフィル（丸め・burst_len=32・beat 書込）
//      (5) fill_hit_byte_r による要求バイト返却（M-9）
//      (6) ★ライトスルー：書込ヒット時に該当バイトを更新（段4・§7.3）★
//          ノーライトアロケート（ミス時はキャッシュに触らない）
//    ★実装しない（段5 以降）★:
//      - FLUSH / CEN 立上り無効化 / fill_abort_r       … 段5
//        ※ ccr_flush_pulse_i は段4 でも意図的に未使用
//
//  ------------------------------------------------------------
//  ★G-0 成立の構造的根拠（最重要・KY-B8）★
//  ------------------------------------------------------------
//    CEN=0 のとき、下記の全出力は cpu 入力／ブリッジ入力の
//    ★純組合せ関数★であり、レジスタを一切経由しない。
//      br_phys_addr_o / br_wdata_o / br_rd_o / br_wr_o
//      cpu_rdata_o    / cpu_ready_o / burst_len_o
//    段3 で追加した always_ff は全て「CEN=1 でしか結果が使われない」
//    経路に閉じている。★1段でもバイパス経路に入れば G-0 は落ちる。★
//
//  ------------------------------------------------------------
//  ★CDC 余裕（設計メモ v0.2 §2.2 / §6.1 N-2）★
//  ------------------------------------------------------------
//    req_offset_r  → psram_clk 比較器 : LATENCY_NORMAL - 8 psram cyc
//                                       = 4 cyc (125ns) @LAT=12
//      ⚠ LATENCY_NORMAL <= 8 では本前提が崩れる
//    fill_index_r  → psram_clk 書込アドレス : 同上（同時ラッチ・同一余裕）
//    fill_hit_byte_r → cpu_clk 読出    : 16 psram cyc (500ns)
//    STA: set_false_path ではなく ★set_max_delay★ を使うこと
//
//  ------------------------------------------------------------
//  ★段3 実装時に判明した決定事項（設計メモに明文が無い・要文書追記）★
//  ------------------------------------------------------------
//    I-1: psram_ctrl_v0_3 の beat_cnt は【内部レジスタ】(L92) で
//         ポート出力されていない。よって beat 番号は本モジュール内で
//         生成する。beat_valid は「バースト中 blen_r サイクル★連続★で1」
//         (psram_ctrl_v0_3.sv L72-73) であるため、単純加算で足りる。
//    I-2: beat_valid は★単バイト読出でも書込でも立つ★(同 L165-169)。
//         フィル以外のビートで data_ram を汚さないため、psram_clk 側に
//         フィルゲート(fill_gate_ps)が必須である。
//         ★fill_active_r(cycle N+1) を同期すると余裕が 2 psram cyc しか
//           残らないため、組合せの fill_sel を 2FF 同期する（余裕 8 cyc）。★
//         fill_sel は1ビットのため 2FF 同期が正当（req_offset_r とは扱いが違う）。
//    I-3: フィル先 index も psram_clk 側で必要。req_offset_r と同時に
//         fill_index_r としてラッチし、同じ CDC 余裕論法を適用する。
// ============================================================


module ysd8800_cache_v0_6 #(
    parameter int PHYS_AW   = 20,          // 物理アドレス幅
    parameter int BLEN_W    = 6,           // burst_len 幅 ($clog2(32)+1)
    parameter int LINE_SIZE = 32,          // ラインサイズ(バイト)
    parameter int IDX_W     = 8,           // index 幅  (256 ライン = 8KB)
    parameter int OFF_W     = 5,           // offset 幅 (32 バイト)
    parameter int TAG_W     = PHYS_AW - IDX_W - OFF_W   // = 7
)(
    input  logic                 cpu_clk,
    input  logic                 cpu_rst_n,

    // ---- CCR（mmio_stub より）----
    input  logic                 ccr_cen_i,
    input  logic                 ccr_flush_pulse_i,   // ★段5 で使用・段3 は未使用★

    // ---- CPU 側（MMU 出力・上流）----
    input  logic [PHYS_AW-1:0]   cpu_phys_addr_i,
    input  logic [7:0]           cpu_wdata_i,
    output logic [7:0]           cpu_rdata_o,
    input  logic                 cpu_rd_i,
    input  logic                 cpu_wr_i,
    output logic                 cpu_ready_o,

    // ---- ブリッジ側（下流・cpu_clk ドメイン）----
    output logic [PHYS_AW-1:0]   br_phys_addr_o,
    output logic [7:0]           br_wdata_o,
    input  logic [7:0]           br_rdata_i,
    output logic                 br_rd_o,
    output logic                 br_wr_o,
    input  logic                 br_ready_i,

    // ---- psram_ctrl 直結（M-10 ①②③）----
    output logic [BLEN_W-1:0]    burst_len_o,      // ① cpu_clk 側
    input  logic                 psram_clk,        // ② ③ のドメイン
    input  logic                 psram_rst_n,
    input  logic                 beat_valid_i,     // ② ★cdc_bridge を経由しない★
    input  logic [7:0]           psram_rdata_i     // ③ 同上
);

    localparam int RAM_AW = IDX_W + OFF_W;          // = 13 (8192 バイト)

    // ============================================================
    //  1. アドレス分解（設計書 §3・純組合せ）
    // ============================================================
    wire [TAG_W-1:0] cur_tag = cpu_phys_addr_i[PHYS_AW-1 -: TAG_W];
    wire [IDX_W-1:0] cur_idx = cpu_phys_addr_i[OFF_W +: IDX_W];
    wire [OFF_W-1:0] cur_off = cpu_phys_addr_i[OFF_W-1:0];

    wire [RAM_AW-1:0] ram_raddr = {cur_idx, cur_off};   // 投機読出アドレス

    // ============================================================
    //  2. タグ／有効ビット（cpu_clk・FF アレイ：設計書 §4.1）
    // ============================================================
    logic [TAG_W-1:0] tag_ram [0:(1<<IDX_W)-1];
    logic [(1<<IDX_W)-1:0] valid_r;

    // ヒット判定（純組合せ：設計書 §7.2）
    wire hit  = ccr_cen_i & valid_r[cur_idx] & (tag_ram[cur_idx] == cur_tag);
    wire miss = ~hit;

    // ============================================================
    //  3. フィル制御（cpu_clk）
    // ============================================================
    //  ★D-C1（M-1）★
    //    fill_req      … 組合せ・フィル「開始」の検出（★登録しない★）
    //    fill_active_r … 登録・フィル「継続」の保持
    //  片方だけでは成立しない：
    //    fill_req だけ      → 2サイクル目以降に丸めが外れる
    //    fill_active_r だけ → cdc_bridge L119(組合せ) に初回が間に合わない
    // ------------------------------------------------------------
    logic                  fill_active_r;
    logic [OFF_W-1:0]      req_offset_r;    // 要求バイトのライン内位置
    logic [IDX_W-1:0]      fill_index_r;    // フィル先ライン (I-3)
    logic [TAG_W-1:0]      fill_tag_r;      // フィル完了時に書くタグ

    wire fill_req = ccr_cen_i & miss & cpu_rd_i;
    wire fill_sel = ccr_cen_i & (fill_req | fill_active_r);

    // ★★段4 デバッグの記録（2026-09-01・RTL は無改修で決着）★★
    //   ------------------------------------------------------------
    //   現象: CEN=1 で「書込 → 密着して別ラインを読出」すると、
    //         cpu_rdata_o が fill_hit_byte_r の【前回値】になる。
    //   ★真因は DUT ではなく TB であった（原則136 の実例）。★
    //     tb_cache_*_poc の do_write/do_read が、ready を検出した
    //     【さらに次のサイクル】で wr/rd を下げていた。
    //     cdc_bridge の suppress_r は ★1 cpu cyc しか要求を抑止しない★
    //     (ysd8800_cdc_bridge_v0_4.sv L139/L148) ため、要求が2 cyc
    //     立ち続けると ★同一要求が再送★され、その最中に we が
    //     書込→読出へ変化して blen_r=1 のまま走った。
    //     観測(tb_wt_probe4_poc): fill_sel=0 の時点で psram に req が
    //     届き blen_r=1 が確定、キャッシュがフィル要求を出す頃には手遅れ。
    //   ------------------------------------------------------------
    //   ★試したが誤りだった案（再発防止のため記録する）★
    //     案1: fill_done を br_ready_i の立上りエッジ判定にする
    //          → 的外れ。br_rdy は正当に 0→1 と遷移していた。
    //     案2(A案): ready が落ちて更に 1cyc 経つまで要求を出さない
    //          → 効果なし。bus_idle は元々成立していた。
    //     案3: フィルゲートを beat_valid 静穏後に武装する
    //          → 効果なし。残留ビートではなかった。
    //     ★いずれも「DUT が悪い」という前提から出た案であり、
    //       TB を疑うのが遅れた。判定器を容疑者から外さないこと。★
    //     3案とも ★不要と確認のうえ撤去済み★（cache_min_poc で ALL PASS）。
    //   ------------------------------------------------------------

    // ★C-1：deassert は br_ready_i 成立と同位相★
    //   早すぎる → バースト途中で転送先が飛ぶ
    //               (psram_ctrl は addr をラッチしない：L101-102)
    //   遅すぎる → 次アクセスまで丸めが残り誤アドレスで要求
    wire fill_done = fill_active_r & br_ready_i;

    always_ff @(posedge cpu_clk or negedge cpu_rst_n) begin
        if (!cpu_rst_n) begin
            fill_active_r <= 1'b0;
            req_offset_r  <= '0;
            fill_index_r  <= '0;
            fill_tag_r    <= '0;
        end else begin
            if (fill_done)      fill_active_r <= 1'b0;   // ★clear 優先★
            else if (fill_req)  fill_active_r <= 1'b1;   // set は cycle N+1

            // フィル中は CPU が ready=0 で待たされるためアドレスは不変。
            // 同値の上書きになるので毎サイクル取り込んで差し支えない。
            if (fill_req) begin
                req_offset_r <= cur_off;
                fill_index_r <= cur_idx;
                fill_tag_r   <= cur_tag;
            end
        end
    end

    // ============================================================
    //  ★段5-b：機能 B — CEN 立上りの暗黙フラッシュ（D-B6）★
    //    設計書 §5 D-B6 / KY-B4:
    //      CEN 無効期間中に書かれたメモリとキャッシュの不整合を防ぐため、
    //      ★CEN を 0→1 にした瞬間に全ラインを無効化する★。
    //    ※ 立上り「エッジ」で1サイクルだけ真になること。
    //      ★ccr_cen_i のレベルで駆動してはならない★
    //      （CEN=1 の間ずっとフラッシュし続け、キャッシュが
    //        一度もヒットしなくなる。F3' がこれを検出する）
    //    実装計画 v0.2 §2.2 B / §4.1.4
    // ============================================================
    logic ccr_cen_d;
    always_ff @(posedge cpu_clk or negedge cpu_rst_n) begin
        if (!cpu_rst_n) ccr_cen_d <= 1'b0;
        else            ccr_cen_d <= ccr_cen_i;
    end
    wire cen_rise    = ccr_cen_i & ~ccr_cen_d;
    wire flush_req   = ccr_flush_pulse_i | cen_rise;

    // ============================================================
    //  ★段5-c：機能 C — fill_abort_r（フィル中止）★
    //    設計書 §7.6 / C-4 / KY-B9
    //      flush 発行 → fill_abort_r <= 1
    //      ack 到達時 : if (fill_abort_r) valid/tag を更新しない
    //      fill_abort_r は ack 受領（fill_done）でクリア
    //
    //    ★PSRAM 側のバースト転送は中断しない★（§7.6）。
    //      途中で req を落とすと req/ack 4相契約に違反する。
    //      読み捨てるだけなので副作用は無い（読出に副作用が無い＝§6.5）。
    //      → 本ブロックは br_* に一切触れていない。C-β-1/C-β-2 が監視する。
    //
    //    ★C-8：応答は止めない★（§7.6 C-8）
    //      cpu_ready_o / cpu_rdata_o は fill_done / fill_hit_byte_r を
    //      そのまま使い続ける（§8 は無改修）。
    //      ★「キャッシュへの登録中止」と「CPU への応答中止」は別である★
    //
    //    ★★到達性について（実装計画 v0.2 §3.2）★★
    //      現行システムでは fill_abort_r は原理的に立たない。
    //      フィル中は cpu_ready_o=0（L393付近）で CPU が滞留し
    //      （cpu_v0_1_FIXED.sv L649）、CPU が唯一のバスマスタである以上
    //      CCR へ書き込めないためである。
    //      ★本論理は「単体 TB でのみ検証される防御論理」である。★
    //      第2のバスマスタ（DMA / 外部 GPIO 拡張バス）が入ると到達可能になる。
    // ============================================================
    logic fill_abort_r;
    always_ff @(posedge cpu_clk or negedge cpu_rst_n) begin
        if (!cpu_rst_n)                        fill_abort_r <= 1'b0;
        else if (fill_done)                    fill_abort_r <= 1'b0;  // ★clear 優先★
        else if (flush_req & fill_active_r)    fill_abort_r <= 1'b1;
    end

    // ============================================================
    //  4. tag / valid の更新（cpu_clk）
    // ============================================================
    integer vi;
    always_ff @(posedge cpu_clk or negedge cpu_rst_n) begin
        if (!cpu_rst_n) begin
            valid_r <= '0;
            for (vi = 0; vi < (1<<IDX_W); vi = vi + 1)
                tag_ram[vi] <= '0;
        end else begin
            // ============================================================
            //  ★段5-a：機能 A — FLUSH による全ライン無効化★
            //    設計書 §7.1 / 実装計画 v0.2 §2.2 A
            //    ccr_flush_pulse_i は CCR bit1 の W1T 1clk パルス。
            //    ★全 (1<<IDX_W) ライン を一括クリアする★
            //    （実装計画 §4.1.1：valid_r[cur_idx] だけ、あるいは
            //      valid_r[7:0] だけをクリアするのは誤りである。
            //      F1 が index=0/中間/255 の3本で検出する）
            //
            //    ★fill_done より優先★：同一サイクルで衝突した場合、
            //    フィル結果を登録しない（＝中止扱い）。これは §7.6 C-4 の
            //    fill_abort_r（段5-c）と同じ向きの振る舞いであり、
            //    ★フラッシュしたラインが復活しないこと★を保証する。
            //    ※ tag_ram はクリアしない。valid_r=0 の間 tag は参照されず
            //      （hit = valid_r & tag一致）、次のフィルで上書きされる。
            // ============================================================
            if (flush_req) begin
                valid_r <= '0;
            end
            // ★set はフィル完了時のみ★（§1.5：DPB 競合の回避策そのもの）
            //   ★段5-c：中止扱い（fill_abort_r）なら登録しない（§7.6 C-4）★
            //   これにより「フラッシュしたはずのラインが復活する」ことを防ぐ。
            else if (fill_done && !fill_abort_r) begin
                tag_ram[fill_index_r]  <= fill_tag_r;
                valid_r[fill_index_r]  <= 1'b1;
            end
            // ★段4：D-C4（書込ライン無効化）は撤去した★
            //   段3 の暫定措置「書込は常にラインを無効化」を、
            //   設計書 §7.3 の ★ライトスルー（該当バイトを更新）★ へ置換。
            //   更新の実体は §5 のポートB 側にある（valid_r は触らない）。
            //   ノーライトアロケート：★ミス時はキャッシュに触らない★ため、
            //   ここに書込ミスの処理は存在しない（PSRAM へ抜けるのみ）。
        end
    end

    // ============================================================
    //  5. data_ram（DPB・設計書 §1.3）
    //     ポートA : psram_clk / 書込（ラインフィル）
    //     ポートB : cpu_clk   / 読出（投機読出）※段4 で書込も使う
    // ============================================================
    logic [7:0] data_ram [0:(1<<RAM_AW)-1];
    logic [7:0] data_q;
    logic [RAM_AW-1:0] spec_addr_r;
    logic              spec_valid_r;    // ★段4 追加★

    // ★段4：書込ヒット（ライトスルーのキャッシュ側更新）★
    //   設計書 §7.3：ヒット時のみ該当バイトを更新する。
    //   ミス時は触らない（ノーライトアロケート）。
    wire wr_hit = ccr_cen_i & cpu_wr_i & hit;

    // ---- ポートB：投機読出（§6.5）＋ 書込ヒット更新（§7.3）----
    //   hit を待たずに常時読み出す。hit しなければ捨てるだけ（副作用なし）。
    //   ★段4：同一サイクルで読出と書込は起こらない★
    //     cpu_rd_i と cpu_wr_i は排他であり、調停は不要。
    //     ただし ★書込サイクルは data_q を更新できない★ ため、
    //     spec_valid_r を落として ★古い data_q を有効と誤認させない★。
    //     （これが無いと、書込直後の読出で古い値を返す。段3 では
    //       ライン無効化により hit=0 となり露見しなかった経路である）
    always_ff @(posedge cpu_clk or negedge cpu_rst_n) begin
        if (!cpu_rst_n) begin
            spec_addr_r  <= '0;
            spec_valid_r <= 1'b0;
        end else if (wr_hit) begin
            data_ram[ram_raddr] <= cpu_wdata_i;   // ★ライトスルー更新★
            spec_valid_r        <= 1'b0;          // 投機読出は成立していない
        end else begin
            data_q       <= data_ram[ram_raddr];
            spec_addr_r  <= ram_raddr;
            spec_valid_r <= 1'b1;
        end
    end

    // ★M-11：hit だけで ready を返してはならない★
    //   data_q が「今の要求」に対応しているときだけ有効。
    //   フェッチ=1cyc / データアクセス=2cyc の非対称性が
    //   ★定数を書かずに自動発現する★（N-5）。
    wire data_q_valid = spec_valid_r & (spec_addr_r == ram_raddr);

    // ============================================================
    //  6. psram_clk ドメイン（★このブロックだけ psram_clk★）
    // ============================================================
    //  I-2: フィルゲート。beat_valid は単バイト読出／書込でも立つため、
    //       これが無いと data_ram が汚染される。
    //       fill_sel(組合せ) を 2FF 同期 → req 受理から約4 psram cyc で確定。
    //       最初のビートは LATENCY_NORMAL(=12) cyc 後 → 余裕 8 cyc。
    logic fill_gate_meta, fill_gate_ps;
    logic [BLEN_W-1:0] beat_cnt_r;      // 現サイクルのビート番号（0起点）
    logic [7:0]        fill_hit_byte_r; // ★M-9：要求バイトのキャプチャ★

    // ★★v0.6 / TKT-V7（2026-09-05）★★
    //   連続ミス（背中合わせ）で fill_sel が途切れず beat_cnt_r が
    //   リセットされない欠陥への対処（設計書 v17 §3.5・案 B'）。
    //   psram_clk 側で beat_valid_i の立上りをバースト開始とみなし、
    //   req_offset / fill_index を同時にラッチする。
    //   ★比較の両辺が psram_clk ドメイン内で閉じる★のが要点。
    logic              beat_valid_d;
    logic              fill_armed_r;    // ★N-1：バースト捕捉中フラグ★
    logic [OFF_W-1:0]  req_off_ps_r;    // psram 側にラッチした要求 offset
    logic [IDX_W-1:0]  fill_index_ps_r; // 同・フィル先 index（M-2）

    wire burst_start = fill_gate_ps & beat_valid_i & ~beat_valid_d;

    // ★現ビート番号の単一定義（M-3）★——捕捉比較とポートAで共用する
    wire [BLEN_W-1:0] beat_no = burst_start ? BLEN_W'(0)     : beat_cnt_r;
    wire [OFF_W-1:0]  off_use = burst_start ? req_offset_r   : req_off_ps_r;
    wire [IDX_W-1:0]  idx_use = burst_start ? fill_index_r   : fill_index_ps_r;

    // ★N-1：ビート消費は「捕捉中」のバーストに限る★
    wire beat_take = fill_gate_ps & beat_valid_i & (burst_start | fill_armed_r);

    // ★★段4-fix（2026-09-01・I-2 の不備是正）★★
    //   I-2 のフィルゲートは「フィル以外のビートを弾く」目的だったが、
    //   ★ゲートが開いた瞬間に前アクセスの残留ビートを拾っていた。★
    //     観測(tb_wt_probe3_poc): 書込→密着読出で、fill_req と同じ
    //     サイクルに既に gate=1 かつ bcnt=1。読出要求から 8 psram cyc
    //     しか経っておらず、LATENCY=12 のフィル由来ではあり得ない。
    //     結果、ビート番号が 1 ずれ、req_offset のバイトを捕らえられず
    //     fill_hit_byte_r が前回値のまま返る。
    //   ★CEN=0 では再現しない（tb_wt_negctl2_poc で確認）＝キャッシュ側の欠陥。★
    //
    //   ★★I-5 是正（2026-09-05 / TKT-V7・KY100）★★
    //     ▼上の段落は当時の観測記録として残す（KY41：情報を削らない）。
    //     ただし ★段4 の最終結論は「真因は TB 側」であり、
    //     この観測に対する RTL 側の是正は行われなかった。★
    //     旧版 v0.3〜v0.5 には
    //       「是正: beat_valid の静穏を確認してから武装する」
    //     と書かれていたが ★その実装は存在しなかった★（同案は §上部の
    //     「案3・効果なし・撤去済み」と同一物である）。
    //     実装のないコメントを「是正済」と読ませていた点が KY100 であり、
    //     この記述が TKT-V7 の発見を遅らせた。
    //
    //     ★段4 の結論（真因は TB 側）自体は誤りではない。★
    //     誤りは「同じ症状を生む経路が他にもあり得る」ことを
    //     確認しなかった点である（KY101）。実際 v0.6 で修正した
    //     連続ミス経路が、同一症状をもう一つ生んでいた。
    //     経緯の詳細は `v17_tkt_v7_fix_design_v0_4.md` §2.5 を参照。
    //
    //   ⚠ LATENCY_NORMAL を短縮する改造時は、前提 P-C（バースト開始まで
    //     req_offset_r / fill_index_r が確定している＝余裕 10 psram cyc）を
    //     真っ先に見直すこと（設計書 v17 §3.4）。
    always_ff @(posedge psram_clk or negedge psram_rst_n) begin
        if (!psram_rst_n) begin
            fill_gate_meta  <= 1'b0;
            fill_gate_ps    <= 1'b0;
            beat_valid_d    <= 1'b0;
            fill_armed_r    <= 1'b0;
            beat_cnt_r      <= '0;
            req_off_ps_r    <= '0;
            fill_index_ps_r <= '0;
            fill_hit_byte_r <= 8'h00;
        end else begin
            fill_gate_meta <= fill_sel;
            fill_gate_ps   <= fill_gate_meta;
            beat_valid_d   <= beat_valid_i;

            if (!fill_gate_ps) begin
                // ★N-1：旧コードの規律を捨てない。★
                //   機能上は burst_start で足りるが、波形の可読性が上がり、
                //   前提 P-A が崩れた場合の被害を「先頭からのずれ」に限定できる。
                beat_cnt_r   <= '0;
                fill_armed_r <= 1'b0;
            end else begin
                if (burst_start) begin
                    req_off_ps_r    <= req_offset_r;   // ★開始時に1回だけラッチ★
                    fill_index_ps_r <= fill_index_r;   // ★M-2★
                    fill_armed_r    <= 1'b1;
                end
                if (beat_take) begin
                    // beat_no が現ビート番号の単一定義（I-2：1ビートずれを構造で排除）
                    beat_cnt_r <= beat_no + BLEN_W'(1);

                    // ★M-9：要求 offset のビートを1回だけ捕らえる★
                    if (beat_no == BLEN_W'(off_use))
                        fill_hit_byte_r <= psram_rdata_i;
                end
            end
        end
    end

    // ---- ポートA：ラインフィル書込（psram_clk・CDC 不要）----
    //   ★I-1/M-3：比較側と同じ beat_no / idx_use を使う。★
    //   裸の beat_cnt_r / fill_index_r を使うとカウンタのずれが
    //   そのまま格納位置のずれになる。
    always_ff @(posedge psram_clk) begin
        if (beat_take)
            data_ram[{idx_use, beat_no[OFF_W-1:0]}] <= psram_rdata_i;
    end

    // ---- ★N-1：無音の失敗経路を残さない（RTL 内アサーション）----
    //   前提 P-A（バースト間に beat_valid=0 の期間が存在する）または
    //   P-B（fill_gate_ps 中に非フィルのバーストが出ない）が破れたとき、
    //   ★無音のデータ破壊ではなく即時失敗させる。★
    //   本アサーションが全ワークロードで発火しないことをもって
    //   P-A/P-B の実測検証とする（設計書 v17 §5 T-2）。
`ifndef SYNTHESIS
    always_ff @(posedge psram_clk) begin
        if (psram_rst_n && fill_gate_ps && beat_valid_i
            && !fill_armed_r && !burst_start)
            $error("[CACHE] unarmed beat consumed: P-A/P-B broken @%0t", $time);
    end
`endif

    // ============================================================
    //  7. 下流（ブリッジ／psram_ctrl）への出力
    // ============================================================
    //  ★D-C1：アドレス丸めと burst_len は【同一条件】で切り替える★
    //    CEN=0        → 素通し・burst_len=1（★G-0 の成立条件★）
    //    CEN=1 ヒット → 要求を出さない
    //    CEN=1 ミス   → 丸め・burst_len=32
    assign br_phys_addr_o = fill_sel
                          ? {cpu_phys_addr_i[PHYS_AW-1:OFF_W], {OFF_W{1'b0}}}
                          : cpu_phys_addr_i;
    assign burst_len_o    = fill_sel ? BLEN_W'(LINE_SIZE) : BLEN_W'(1);

    assign br_wdata_o     = cpu_wdata_i;
    // ヒット時は下流へ読出要求を出さない（＝PSRAM アクセスを消す）
    assign br_rd_o        = ccr_cen_i ? (fill_req | fill_active_r) : cpu_rd_i;
    // 書込は常に PSRAM へ抜ける（ライトスルー／ノーライトアロケート・§7.3）
    assign br_wr_o        = cpu_wr_i;

    // ============================================================
    //  8. 上流（CPU）への出力
    // ============================================================
    //  ★CEN=0、および CEN=1 でも「読出以外」は br_* を純組合せ素通し★
    //  §7.5：フィル中は ready=0 で CPU を待たせる（調停ロジック不要）
    assign cpu_ready_o = (ccr_cen_i & cpu_rd_i)
                       ? ((hit & data_q_valid) | fill_done)
                       : br_ready_i;

    //  ★M-9：ミス完了時に br_rdata_i を返してはならない★
    //    バースト完了時点の psram_rdata はライン末尾(offset 31)のバイトである。
    assign cpu_rdata_o = (ccr_cen_i & cpu_rd_i)
                       ? (hit ? data_q : fill_hit_byte_r)
                       : br_rdata_i;

    // ============================================================
    //  9. ★バス契約アサーション（TKT-V1 / T-B・2026-09-02 追加）★
    //     設計書: v12_tb_contract_design_v0_3.md §3.3.1（境界①）
    // ============================================================
    //  ★契約 C-α'★
    //    ready の次サイクルで要求を継続する場合、それは
    //    ★新しい要求（アドレスまたは種別が変化）★でなければならない。
    //    ★同一アドレス・同一種別の保持は契約違反★。
    //
    //  ★注意: 実CPUは ready の次サイクルに新しい要求を出す
    //          （S_MEMR_LO→S_MEMR_HI 等）。
    //          「要求が継続していること」自体は契約違反ではない。★
    //
    //  経緯: 段4 で TB が ready 後も同一要求を保持し、再送が発生した。
    //        DUT は正しいのに落ち、切り分けに数時間を要した（TKT-V1）。
    //
    //  ★対の検査器が cdc_bridge 側（境界②）にもある。片方だけ直さないこと。★
    //  ★TKT-V6 以降、両者は同一の再アーム方式（違反条件が偽になったとき）を
    //    採る。★ 方式が片側だけ変わると★回数の帰属が非対称になり、
    //    段6 の回数判定が狂う。★（2026-09-04）
    //
    //  実装: Icarus 12.0 は assert property 未サポートのため手続き版。
    //        always_ff は $error に合成不可警告が出るため always を使う。
    //  合成: `ifndef SYNTHESIS で囲む（工程③へ持ち込まない）
    // ============================================================
`ifndef SYNTHESIS
    logic                ca_ready_d, ca_rd_d, ca_wr_d;
    logic [PHYS_AW-1:0]  ca_addr_d;
    logic                ca_viol;
    logic                ca_reported;
    // ★方式A試打ち: 報告済の要求を記憶し、同一要求の再送を抑止する★
    logic                ca_rep_rd, ca_rep_wr;
    logic [PHYS_AW-1:0]  ca_rep_addr;
    logic                ca_same_as_reported;

    assign ca_viol = ca_ready_d && (cpu_rd_i || cpu_wr_i)
                                && (cpu_rd_i == ca_rd_d)
                                && (cpu_wr_i == ca_wr_d)
                                && (cpu_phys_addr_i == ca_addr_d);

    assign ca_same_as_reported = ca_reported
                              && (cpu_rd_i        == ca_rep_rd)
                              && (cpu_wr_i        == ca_rep_wr)
                              && (cpu_phys_addr_i == ca_rep_addr);

    always @(posedge cpu_clk or negedge cpu_rst_n) begin
        if (!cpu_rst_n) begin
            ca_ready_d  <= 1'b0;
            ca_rd_d     <= 1'b0;
            ca_wr_d     <= 1'b0;
            ca_addr_d   <= '0;
            ca_reported <= 1'b0;
            ca_rep_rd   <= 1'b0;
            ca_rep_wr   <= 1'b0;
            ca_rep_addr <= '0;
        end else begin
            if (ca_viol && !ca_same_as_reported) begin
                $error("[CONTRACT C-a'] same req held after ready: addr=%h rd=%b wr=%b t=%0t",
                       cpu_phys_addr_i, cpu_rd_i, cpu_wr_i, $time);
                ca_reported <= 1'b1;
                ca_rep_rd   <= cpu_rd_i;
                ca_rep_wr   <= cpu_wr_i;
                ca_rep_addr <= cpu_phys_addr_i;
            end
            else if (!cpu_rd_i && !cpu_wr_i) begin
                ca_reported <= 1'b0;    // ★バスアイドルで再アーム★
            end

            ca_ready_d <= cpu_ready_o;
            ca_rd_d    <= cpu_rd_i;
            ca_wr_d    <= cpu_wr_i;
            ca_addr_d  <= cpu_phys_addr_i;
        end
    end
`endif

endmodule


// ============================================================
//  改版履歴
//    v0.1 (2026-08-30) 初版。工程②-B 段2。
//         純組合せバイパス＋burst_len 駆動＋psram 直結ポートの確定。
//    v0.2 (2026-08-31) 工程②-B 段3。
//         tag_ram/valid_r/data_ram(DPB)・ヒット判定・投機読出(M-11)・
//         ラインフィル(D-C1)・fill_hit_byte_r(M-9)・
//         書込ライン無効化(D-C4) を追加。
//         ★実装決定 I-1/I-2/I-3 を新設（設計メモへ追記要）★
//    v0.3 (2026-09-01) 工程②-B 段4。
//         ★ライトスルー実装★。D-C4(書込ライン無効化)を撤去し、
//         ポートB を「投機読出＋書込ヒット更新」の両用に変更(§4.2/§7.3)。
//         ★spec_valid_r を新設★：書込サイクルは data_q を更新できないため、
//         古い data_q を有効と誤認しないよう投機読出の成立を明示的に落とす。
//         ノーライトアロケート（書込ミス時はキャッシュ非更新）。
//    v0.4 (2026-09-03) 工程②-B 段5。★本行は v0.5 時点で欠落していたため
//         v0.6 で補完した（KY41）。内容は段5 の実装記録に基づく。★
//         機能A: FLUSH による全ライン無効化。
//         機能B: CEN 立上りの暗黙フラッシュ（エッジ検出）。
//         機能C: fill_abort_r（現構成では到達不能・将来の多マスタ用）。
//    v0.5 (2026-09-04) 工程②-B 段6 / TKT-V6。★本行も v0.5 時点で
//         履歴表へ未記載であったため v0.6 で補完した（KY41）。★
//         境界① 契約 C-α' に ca_viol / ca_reported を追加し
//         1事象1回の報告に是正（違反条件・書式は不変）。
//    v0.6 (2026-09-05) 工程②-B / ★TKT-V7★。
//         ★連続ミス時に fill_hit_byte_r が前回値のまま返る欠陥を修正★。
//         psram_clk 側で beat_valid_i の立上りをバースト開始とみなし
//         (burst_start)、beat_cnt_r を 0 相当にすると同時に
//         req_offset / fill_index を psram 側へラッチする（案 B'）。
//         beat_no を現ビート番号の単一定義とし、捕捉比較とポートA で共用。
//         fill_armed_r と RTL 内 $error アサーションを追加（N-1）。
//         段4 コメントを実態に合わせて整理（I-5・KY100／旧記述は保持）。
//         設計書: v17_tkt_v7_fix_design_v0_4.md §3.5
// ============================================================
