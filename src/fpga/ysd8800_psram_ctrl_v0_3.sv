// ============================================================
//  ysd8800_psram_ctrl_v0_3.sv   v0.3  (2026-08-28)
//  YSD8800 FPGA V3.5 : PSRAMコントローラ(ビヘイビアモデル)
//                      ★工程②-A: バースト転送対応★
//
//  設計根拠: v10_psram_burst_design_v0_3.md (承認済 2026-08-27)
//            v3_design_memo_v0_2.md §3        (V3・可変レイテンシモデル)
//            v3_5_design_memo_v0_2.md §8 Q2   (V3.5・1MB化/レビュー承認済)
//
//  ------------------------------------------------------------
//  【v0.2からの変更点】★工程②-A(段1: 骨格のみ)★
//    (1) パラメータ BURST_MAX / BLEN_W を追加
//    (2) 入力ポート  burst_len  を追加 (1 = 従来動作)
//    (3) 出力ポート  beat_valid を追加 (rdata有効表示)
//    (4) 内部レジスタ beat_cnt / blen_r を追加
//    (5) mem_idx を addr + beat_cnt に変更
//    (6) 書込条件を (we && blen_r==1) に限定          ★M-3★
//    (7) rst_n リセット節に追加3信号の初期化を追加     ★M-7★
//
//    (8) PS_BURST 状態を追加(4状態化)                 ★段2★
//    (9) PS_BUSY に blen_r>1 の分岐を追加             ★段2★
//
//    段1(骨格): (1)〜(7) …… 等価性TBで7,563サイクル完全一致を確認済
//    段2(本体): (8)(9)   …… 本版
//
//  【★なぜバーストが必要か★】(設計書 §1.2)
//    v0.2 は req/ack 1バイト1トランザクションであり LAT_FILL = LAT。
//    キャッシュのライン充填がバイト毎にフルレイテンシを払うため、
//    損益分岐ヒット率が S=32 で 97.4% となり実現不能。
//    バースト化によりCDC越えがライン当り1回に減り、
//    2バイト目以降がpsramドメインの1サイクルで流れる。
//
//  【★burst_len=1 の完全等価性★】(設計書 §3.4 / G-0の根拠)
//    beat_cnt が 0 のまま PS_BURST を踏まないため
//      mem_idx = addr[MEM_AW-1:0]  に縮退し v0.2 とビット単位で同一。
//    書込条件 (we && blen_r==1) も blen_r==1 のとき we と等価。
//    → 測定で偶然一致したのではなく【経路が実行されない】ことによる
//       構造的保証である。
//
//  【リフレッシュ模擬(V3から不変・R-a採用)】
//    HyperRAMは約0.05%の頻度でレイテンシが2x(12→15サイクル)になる。
//    ★バースト時はreq受理時点で1回だけ判定する(設計書 §3.5 R-a)。
//      実PSRAMでも行アクティベート時に1回であるため。
//      ただしリフレッシュ密度が実質1/Sに希釈される点に注意し、
//      ②-Bの性能測定では dbg_refresh_hit の発生回数を記録すること。★
// ============================================================
`timescale 1ns/1ps

module ysd8800_psram_ctrl_v0_3 #(
    parameter int LATENCY_NORMAL  = 12,   // 通常時レイテンシ(サイクル)
    parameter int LATENCY_REFRESH = 15,   // リフレッシュ重畳時レイテンシ
    parameter int REFRESH_PPM     = 500,  // 発生頻度(百万分率。500=0.05%)
    parameter int PHYS_AW         = 20,   // 物理アドレス幅(V3.5 MMU=20bit)
    parameter int MEM_AW          = 20,   // ★V3.5追加: メモリ配列の実確保幅★
    parameter int BURST_MAX       = 32,   // ★v0.3追加: 最大バースト長★
    parameter int BLEN_W          = $clog2(BURST_MAX) + 1  // ★v0.3追加: =6★
) (
    input  logic                  clk,      // PSRAM側高速クロック
    input  logic                  rst_n,

    input  logic [PHYS_AW-1:0]    addr,     // ★物理アドレス(全幅を使用する)★
    input  logic [7:0]            wdata,
    input  logic                  we,
    input  logic                  req,
    output logic                  ack,
    output logic [7:0]            rdata,

    // ★v0.3追加: バースト制御★
    //   burst_len : 転送バイト数。1=従来動作。req受理サイクルでのみ参照し
    //               blen_r にラッチする(以後の変化は無視)。
    //               1以上BURST_MAX以下の2の冪であること(assertion検査)。
    //   beat_valid: そのサイクルの rdata が有効な新規バイトであることを示す。
    //               ★バースト中は blen_r サイクル連続で1(パルス列ではない)★
    input  logic [BLEN_W-1:0]     burst_len,
    output logic                  beat_valid,

    // 診断用(TB観測専用)
    output logic                  dbg_refresh_hit
);

    // ★V3.5: メモリ配列をMEM_AWで確保(V3の[0:65535]固定を廃止)★
    logic [7:0] mem [0:(1<<MEM_AW)-1];

    // ★段2: PS_BURST を追加(4状態)。2bitのまま収まる。★
    //   PS_BURST は blen_r>1 のときのみ踏まれる。burst_len=1 では
    //   一度も踏まれないため v0.2 との等価性は段1のまま保たれる。
    typedef enum logic [1:0] {PS_IDLE, PS_BUSY, PS_BURST, PS_WAIT_REQ_LOW} ps_state_t;
    ps_state_t ps_state;
    integer    busy_cnt;

    // ★v0.3追加: バースト状態レジスタ★
    logic [BLEN_W-1:0] beat_cnt;   // 現在のビート番号(0起点)
    logic [BLEN_W-1:0] blen_r;     // 確定バースト長(req受理時にラッチ)

    // ★V3.5: addr_lo(16bit固定)を廃止し、MEM_AW幅で使用する★
    //   これによりMMUがリマップした上位ビットが実際に効くようになる。
    // ★v0.3: beat_cnt を加算。burst_len=1 では beat_cnt=0 のため
    //         v0.2 の assign mem_idx = addr[MEM_AW-1:0] に縮退する。★
    //   幅整合: 暗黙拡張に頼らず両辺を明示的に MEM_AW 幅へ揃える。
    //   桁上げ: MEM_AW 幅でラップする(ライン境界跨ぎは呼出側責務)。
    logic [MEM_AW-1:0] mem_idx;
    assign mem_idx = addr[MEM_AW-1:0]
                   + {{(MEM_AW-BLEN_W){1'b0}}, beat_cnt};

    // 疑似リフレッシュ発生器(LFSR的な簡易乱数。実機の非決定性を模擬)
    logic [31:0] lfsr;
    logic        refresh_this_access;

    // 閾値は64bit(longint)で計算してから下位20bitへ切り出す。
    // 32bit演算のままだと 1048576×REFRESH_PPM がREFRESH_PPM大で
    // オーバーフローする(V3自己レビューPoCで発見・KY39系是正)。
    localparam longint unsigned REFRESH_THRESH_FULL =
        (longint'(1_048_576) * longint'(REFRESH_PPM)) / longint'(1_000_000);
    localparam logic [19:0] REFRESH_THRESH = REFRESH_THRESH_FULL[19:0];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) lfsr <= 32'hACE1_2345;
        else        lfsr <= {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ps_state         <= PS_IDLE;
            ack              <= 1'b0;
            busy_cnt         <= 0;
            rdata            <= 8'h00;
            dbg_refresh_hit  <= 1'b0;
            refresh_this_access <= 1'b0;
            // ★v0.3追加(M-7): 追加3信号の初期化★
            //   beat_valid は【出力ポート】であり、未初期化だと 1'bx となって
            //   ②-Bのキャッシュが誤ってビートを取り込む。②-Aでは未接続のため
            //   顕在化せず、②-Bで「リセット直後の1ビートだけ誤る」という
            //   最も追いにくい形で出るため必ず初期化する。
            beat_valid       <= 1'b0;
            beat_cnt         <= '0;
            blen_r           <= BLEN_W'(1);   // 暴走時も単バイト動作へ縮退
        end else begin
            case (ps_state)
                PS_IDLE: begin
                    ack <= 1'b0;
                    beat_valid <= 1'b0;              // ★v0.3追加(N-5): 明示クリア★
                    if (req) begin
                        // このアクセスがリフレッシュ重畳になるかをreq受理時点で確定
                        refresh_this_access <= (lfsr[19:0] < REFRESH_THRESH);
                        // IDLE→BUSY遷移自体で1サイクル消費するため-2で開始
                        // (req受理サイクルからack成立サイクルまでを丁度LATENCYに
                        //  揃えるための補正。単体TBの実測でLATENCY一致を確認済)
                        busy_cnt <= ((lfsr[19:0] < REFRESH_THRESH)
                                     ? LATENCY_REFRESH : LATENCY_NORMAL) - 2;
                        ps_state <= PS_BUSY;
                        // ★v0.3追加: バースト状態のラッチ★
                        //   burst_len=0 は 1 に飽和させる(C-1)。
                        //   飽和しないとアンダーフローで全域転送する事故になる。
                        beat_cnt <= '0;
                        blen_r   <= (burst_len == '0) ? BLEN_W'(1) : burst_len;
                    end
                end
                PS_BUSY: begin
                    if (busy_cnt == 0) begin
                        // ★v0.3(M-3): バースト書きは未サポート。
                        //   wdataが1本しかないため素直に実装すると同一値を
                        //   Sバイト書き込みメモリを不可逆破壊する(R-5)。
                        //   blen_r==1 に限定して無害化する。
                        //   blen_r==1 のとき本条件は v0.2 の (we) と等価。★
                        if (we && (blen_r == BLEN_W'(1)))
                            mem[mem_idx] <= wdata;   // ★全幅アドレスで参照★
                        rdata           <= mem[mem_idx];
                        dbg_refresh_hit <= refresh_this_access;
                        beat_valid      <= 1'b1;     // ★v0.3追加: beat 0 確定★
                        // ★段2: バースト長による分岐★
                        //   blen_r==1 の経路は v0.2 と完全に同一
                        //   (ack即時・PS_WAIT_REQ_LOWへ)。
                        if (blen_r == BLEN_W'(1)) begin
                            ack      <= 1'b1;
                            ps_state <= PS_WAIT_REQ_LOW;
                        end else begin
                            // beat 0 を出し終えたので次は beat 1
                            // ★ackはまだ立てない(最終バイトまで0を維持)★
                            beat_cnt <= BLEN_W'(1);
                            ps_state <= PS_BURST;
                        end
                    end else begin
                        busy_cnt <= busy_cnt - 1;
                    end
                end
                // ------------------------------------------------
                // ★段2新設: PS_BURST★
                //   1 psram cyc につき 1 バイトを出す。
                //   mem_idx は beat_cnt を含むため自動的に addr+n を指す。
                //   総サイクル数 = LAT + (blen_r - 1)
                //   例: blen=32, LAT=12 → 12 + 31 = 43 psram cyc
                // ------------------------------------------------
                PS_BURST: begin
                    rdata      <= mem[mem_idx];
                    beat_valid <= 1'b1;
                    // ★ackはここでは触らない(0のまま維持)★
                    //   cdc_bridgeはackの【立上りエッジ】を見るため
                    //   各beatでackを立てると挙動が変わる(禁止)。
                    if (beat_cnt == (blen_r - BLEN_W'(1))) begin
                        ack      <= 1'b1;            // 最終バイトで初めて立てる
                        ps_state <= PS_WAIT_REQ_LOW;
                    end else begin
                        beat_cnt <= beat_cnt + BLEN_W'(1);
                    end
                end
                PS_WAIT_REQ_LOW: begin
                    // 4相: reqが下がるまでackを維持(cdc_bridge契約)
                    //   ※cdc_bridge_v0_4 はackのレベルではなく
                    //     ack_sync[0] & ~ack_sync[1] で【立上りエッジ】を
                    //     検出し1 cpu cycパルス化している(L139/L148)。
                    //     各beatでackを立てる変更は挙動を変えるため禁止。
                    beat_valid <= 1'b0;              // ★v0.3追加★
                    if (!req) begin
                        ack      <= 1'b0;
                        ps_state <= PS_IDLE;
                    end
                end
            endcase
        end
    end

    // ------------------------------------------------------------
    // ★v0.3追加: 呼出側契約の検査(設計書 §5.4)★
    //   Gowin EDA は合成時に SYNTHESIS を定義するため合成対象から外れる。
    //   translate_off 系のコメントプラグマはツール依存で挙動が割れるため
    //   `ifndef を採用する。
    //   RTL側の無害化(we && blen_r==1)と合わせた二段防御であり、
    //   シミュレーションでは顕在化し実機では破壊しない。
    // ------------------------------------------------------------
`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (rst_n && (ps_state == PS_IDLE) && req) begin
            if ((burst_len > BLEN_W'(1)) && we)
                $error("PSRAM: burst write not supported (blen=%0d)", burst_len);
            // ★M-8: 境界条件は BURST_MAX ではなく burst_len に依存する。
            //   $clog2(BURST_MAX)固定にすると burst_len=4/addr=$0004 という
            //   正常ケースで誤発火し、正常系ベクタを汚染する。★
            if ((burst_len > BLEN_W'(1)) &&
                ((addr & (PHYS_AW'(burst_len) - PHYS_AW'(1))) != '0))
                $error("PSRAM: burst must be %0d-byte aligned (addr=%h)",
                       burst_len, addr);
            if (burst_len > BLEN_W'(BURST_MAX))
                $error("PSRAM: blen exceeds BURST_MAX (%0d)", burst_len);
            // ★M-8: 非2冪はアラインメント判定が意味を持たないため別途検出★
            if ((burst_len > BLEN_W'(1)) &&
                ((burst_len & (burst_len - BLEN_W'(1))) != '0))
                $error("PSRAM: blen must be a power of 2 (%0d)", burst_len);
        end
    end
`endif

endmodule
