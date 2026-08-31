// ============================================================
//  ysd8800_cdc_bridge_v0_4.sv   v0.4  (2026-08-26 死状態変数 ack_sync_d 除去)
//  ★正式版★ 工程①.5
//    v0.4 変更点:
//      (1) ★ack_sync_d を削除★。v0.3のA-2q化で参照がゼロになったが
//          「保持」と称して宣言・リセット・代入の3行が残っていた。
//          未使用の状態変数は kaizen「内部状態変数の変更箇所を
//          一か所に集約」の趣旨に反し、将来の読み手を誤らせる。
//      (2) ★論理変更なし★。N-4検証(NC-1)にて、本削除を行っても
//          V8-b本番ランのログがバイト完全一致することを実測確認済
//          (2026-08-26)。ビルド成果物は 298,467B → 298,250B と
//          実際に縮んでおり「確かに変更された上で結果不変」を実証。
//    ------------------------------------------------------------
//    以下 v0.3 までの記録(欠落させない)
//  ysd8800_cdc_bridge_v0_3.sv   v0.3  (2026-08-25 A-2q: CDC遅延1cyc削減)
//  ★正式版★ 工程①.5 PSRAM性能改善
//    設計根拠: v9_psram_perf_design_memo_v0_3.md (条件1/2/4 充足)
//    v0.3 変更点(A-2q):
//      (1) req_hold(登録・ack検出の次cyc)を廃止し ★suppress_r★ に置換。
//            suppress_r <= ack_sync[0] & ~ack_sync[1];
//          → ack_sync[1]が立つのと【同じ】クロックで1になり、抑止幅は
//            ちょうど1cpu cyc。cpu_mem_ready と完全同位相。
//      (2) cpu_mem_ready を suppress_r の assign 出力へ変更。
//          ★登録済・単一FF出力のため Q はグリッチを持たない★
//      (3) cpu_mem_rdata を psram_rdata の assign 出力へ変更。
//          psram_ctrlはPS_WAIT_REQ_LOWでreq立下りまでrdata/ackを保持する
//          ため論理的に安定(4相ハンドシェイク)。
//          ★FPGAでは非同期パスとなり set_max_delay 等のSTA制約が必須★
//    効果(単体PoC実測・本番同一8:1構成):
//          連続read間隔 5 cpu_clk → ★4 cpu_clk★ (-1cyc/アクセス・持続)
//    ★不採用案の記録★:
//      - A-2  (readyのみ組合せ化): req_holdに吸収され初回1cycのみ。実質0%
//      - A-2' (ack_edge_cでreq抑止): 4cyc出るが ack_edge_c は2FF出力の
//              デコードで、ack立下り時の同時遷移ハザードが psram_clk
//              (31.25ns)でサンプルされる危険。★不採用★
//      - A-2''(~ack_sync[1]でreq抑止): グリッチフリーだが抑止期間が延び
//              5cycに戻り効果消失。★不採用★
//      - A-4  (2FF→1FF): メタステービリティ耐性低下。原則82違反。★却下★
//    ------------------------------------------------------------
//    以下 v0.2 までの記録(欠落させない)
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

module ysd8800_cdc_bridge_v0_4 #(
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
    // ★v0.3(A-2q): req_hold(登録・1cyc遅れ)を廃止し suppress_r に置換★
    logic       suppress_r;    // 登録済・単一FF出力のreq抑止信号(readyと同位相)
    logic       req_level;     // psram_clk側へ渡す要求レベル
    logic [1:0] ack_sync;      // 高速→CPU 2FF同期器
    // ★v0.4: ack_sync_d を削除(v0.3で参照ゼロの死んだ状態変数だった)★

    // ★v0.3(A-2q): 抑止信号を【登録済・単一FF出力】にする。
    //   単一FFのQは定義上グリッチを持たないため、psram_clkでサンプル
    //   されても偽requestを生じない(旧A-2'案のack_edge_c組合せデコードは
    //   ack立下り時に同時遷移ハザードを生じるため不採用)。
    assign req_level   = (cpu_mem_rd | cpu_mem_wr) & ~suppress_r;
    assign psram_addr  = cpu_phys_addr;          // ★幅一致(PHYS_AW)★
    assign psram_wdata = cpu_mem_wdata;
    assign psram_we    = cpu_mem_wr;

    always_ff @(posedge cpu_clk or negedge cpu_rst_n) begin
        if (!cpu_rst_n) begin
            ack_sync      <= 2'b00;
            suppress_r    <= 1'b0;
            // ★v0.3: cpu_mem_ready/cpu_mem_rdata は assign 化のため除去★
        end else begin
            // 2FF同期器: psram_ack(高速ドメイン)をCPUクロックへ
            ack_sync   <= {ack_sync[0], psram_ack};

            // ★★v0.3(A-2q): req抑止信号の生成★★
            //   ack_sync[0]が立った【次】のクロックで1になる。
            //   → cpu_mem_ready と完全同位相で、抑止幅はちょうど1cpu cyc。
            //   D入力の組合せ(ack_sync[0]&~ack_sync[1])に生じるハザードは
            //   クロック端までに確定するため無害(FF入力側のため)。
            //   ack_sync[0]を本FFが叩くので、この経路も2FF相当のMTBFを持つ。
            suppress_r <= ack_sync[0] & ~ack_sync[1];
        end
    end

    // ================= CPU側出力(v0.3: assign化) =================
    //   ★req_holdは廃止。suppress_rが「ready」と「req抑止」を兼ねる。★
    //   旧v0.2: ack立上り検出の【次】クロックでreadyを1にしていたため
    //           1cpu cyc遅く、かつ req_hold がさらに1cyc遅れて効くことで
    //           連続アクセス時に次reqが1cyc余計に待たされていた。
    assign cpu_mem_ready = suppress_r;       // ★登録済・単一FF出力★
    assign cpu_mem_rdata = psram_rdata;      // ★非同期データパス: STA制約必須★

    // ================= 2FF同期器: CPU→高速側へreqを渡す =================
    logic [1:0] req_sync;
    always_ff @(posedge psram_clk or negedge psram_rst_n) begin
        if (!psram_rst_n) req_sync <= 2'b00;
        else              req_sync <= {req_sync[0], req_level};
    end
    assign psram_req = req_sync[1];

endmodule
