// ============================================================
//  ysd8800_psram_ctrl_v0_1.sv   v0.1  (2026-07-11)
//  YSD8800 FPGA V3 : PSRAMコントローラ ビヘイビアモデル
//
//  設計根拠: v3_design_memo_v0_2.md §3/§3.1/§5
//   - 通常時レイテンシ: 12サイクル(Gowin公式PSRAM HS IP 1:2ギア比・
//     80MHz級を第一候補とする見積り、§4.1.4)
//   - リフレッシュ由来の可変レイテンシ: 約0.05%の頻度で2xレイテンシ
//     (12→15サイクル)。HyperRAM系メモリの自動DRAMリフレッシュに
//     起因(§3.1)。固定レイテンシ前提のTBのみで通すと実機で
//     初めて遭遇する、という指示No.5の教訓を反映し、本モデル自体に
//     可変レイテンシ発生機構を組み込む。
//
//  ★本モデルは「Gowin公式PSRAM HS IPを模したビヘイビア記述」であり、
//    実IPそのものではない(Icarus Verilogでは合成専用ハードマクロ
//    IPをシミュレートできないための代替・v3_design_memo_v0_2.md
//    §3参照)。実FPGA合成時はGowin IPコアジェネレータの生成物に
//    置き換える(将来工程・本モデルはシミュレータ専用)。
//
//  I/F: ysd8800_cdc_bridge_v0_1 の psram_* 信号にそのまま接続できる
//       req/ackレベル4相ハンドシェイク(§4.1.2/§4.1.3と同一契約)。
//
//  容量: 64Mbit(=8MB=23bit)のうち、V3ではCPU論理アドレス16bit分
//        (下位64KB)のみを実装する。指示No.7(§4.3)の「インタフェース
//        は将来幅・実装は現在幅」に従い、addr入力自体は20bit以上を
//        受けられる形にしつつ、内部配列は64KB分のみ確保する。
//        上位ビット([PHYS_AW-1:16])はV3では未使用(0固定運用)。
// ============================================================
`timescale 1ns/1ps

module ysd8800_psram_ctrl_v0_1 #(
    parameter int LATENCY_NORMAL  = 12,   // 通常時レイテンシ(サイクル)
    parameter int LATENCY_REFRESH = 15,   // リフレッシュ重畳時レイテンシ
    parameter int REFRESH_PPM     = 500,  // 発生頻度(百万分率。500=0.05%)
    parameter int PHYS_AW         = 20    // 将来拡張用アドレス幅(指示No.7・V3.5 MMU=20bit)
)(
    input  logic                  clk,      // PSRAM側高速クロック(コントローラ動作クロック)
    input  logic                  rst_n,

    // req/ackレベル4相ハンドシェイク(ysd8800_cdc_bridge_v0_1と同一契約)
    input  logic [PHYS_AW-1:0]    addr,     // 上位ビットはV3では0固定(§4.3)
    input  logic [7:0]            wdata,
    input  logic                  we,
    input  logic                  req,
    output logic                  ack,
    output logic [7:0]            rdata,

    // 診断用(TB観測専用): 今回のアクセスがリフレッシュ重畳だったか
    output logic                  dbg_refresh_hit
);

    // V3実装範囲: 論理64KB相当のみ(指示No.7: 実装は現在幅)
    logic [7:0] mem [0:65535];

    typedef enum logic [1:0] {PS_IDLE, PS_BUSY, PS_WAIT_REQ_LOW} ps_state_t;
    ps_state_t ps_state;
    integer    busy_cnt;
    logic [15:0] addr_lo;       // PHYS_AWのうち下位16bitのみV3では使用
    assign addr_lo = addr[15:0];

    // 疑似リフレッシュ発生器(LFSR的な簡易乱数。実機の非決定性を模擬)
    logic [31:0] lfsr;
    logic        refresh_this_access;

    // 閾値は64bit(longint)で計算してから下位20bitへ切り出す。
    // 32bit演算のままだと 1048576×REFRESH_PPM がREFRESH_PPM大で
    // オーバーフローする(自己レビューPoCで発見・KY39系是正)。
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
        end else begin
            case (ps_state)
                PS_IDLE: begin
                    ack <= 1'b0;
                    if (req) begin
                        // このアクセスがリフレッシュ重畳になるかをreq受理時点で確定
                        refresh_this_access <= (lfsr[19:0] < REFRESH_THRESH);
                        // IDLE→BUSY遷移自体で1サイクル消費するため-2で開始
                        // (req受理サイクルからack成立サイクルまでを丁度LATENCYに
                        //  揃えるための補正。単体TBの実測でLATENCY一致を確認済)
                        busy_cnt <= ((lfsr[19:0] < REFRESH_THRESH)
                                     ? LATENCY_REFRESH : LATENCY_NORMAL) - 2;
                        ps_state <= PS_BUSY;
                    end
                end
                PS_BUSY: begin
                    if (busy_cnt == 0) begin
                        if (we) mem[addr_lo] <= wdata;
                        rdata           <= mem[addr_lo];
                        dbg_refresh_hit <= refresh_this_access;
                        ack             <= 1'b1;
                        ps_state        <= PS_WAIT_REQ_LOW;
                    end else begin
                        busy_cnt <= busy_cnt - 1;
                    end
                end
                PS_WAIT_REQ_LOW: begin
                    // 4相: reqが下がるまでackを維持(ysd8800_cdc_bridge_v0_1契約)
                    if (!req) begin
                        ack      <= 1'b0;
                        ps_state <= PS_IDLE;
                    end
                end
            endcase
        end
    end

endmodule
