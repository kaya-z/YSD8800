// ============================================================
//  ysd8800_psram_ctrl_v0_2.sv   v0.2  (2026-07-11)
//  YSD8800 FPGA V3.5 : PSRAMコントローラ(ビヘイビアモデル)
//                      ★物理1MB化・アドレス全幅使用★
//
//  設計根拠: v3_design_memo_v0_2.md §3        (V3・可変レイテンシモデル)
//            v3_5_design_memo_v0_2.md §8 Q2   (V3.5・1MB化/レビュー承認済)
//
//  ------------------------------------------------------------
//  【V3(v0.1)からの変更点】★V3.5の必須改修(2件目)★
//    (1) MEM_AW パラメータを追加（メモリ配列の実確保幅）
//    (2) mem 配列を [0:65535] 固定 → [0:(1<<MEM_AW)-1] に変更
//    (3) addr_lo(16bit固定・上位を捨てていた) を廃止し、
//        addr[MEM_AW-1:0] を直接使用 → ★上位ビットが効くようになる★
//
//  【★なぜこの改修が必須か★】(KY34で検出・本チャット)
//    V3実装の実態:
//        logic [15:0] addr_lo;
//        assign addr_lo = addr[15:0];      // ← 上位4bitを捨てていた
//        if (we) mem[addr_lo] <= wdata;    // ← 64KBしか見ない
//        logic [7:0] mem [0:65535];        // ← 64KB固定
//    すなわち PHYS_AW=20 でポートを20bitにしても、【内部で下位16bitしか
//    使っていない】ため、MMUがリマップした物理$14000は$4000に化けていた。
//    CDCブリッジの20bit化(v0.2)だけでは不十分であり、本モジュールの
//    1MB化まで行って初めてリマップが機能する。
//    emu23(黄金)は phys_mem[pa & 0xFFFFF] = 20bit/1MB空間である
//    (レビュー回答書 §2 実照合・Q2根拠)。
//
//  【シミュレーション速度への配慮】(レビュー回答書 §3 Q2 注意)
//    MEM_AW をパラメータ化し、TBが必要な分だけ確保できるようにした。
//      MEM_AW=16 → 64KB (V3等価・回帰TB用・高速)
//      MEM_AW=20 → 1MB  (V3.5 MMUリマップ検証用)
//    デフォルトは PHYS_AW と同じ20bit(1MB)。
//  ------------------------------------------------------------
//
//  【リフレッシュ模擬(V3から不変)】
//    HyperRAMは約0.05%の頻度でレイテンシが2x(12→15サイクル)になる。
//    実機の非決定性を模擬するため簡易LFSRで確率的に重畳させる。
// ============================================================
`timescale 1ns/1ps

module ysd8800_psram_ctrl_v0_2 #(
    parameter int LATENCY_NORMAL  = 12,   // 通常時レイテンシ(サイクル)
    parameter int LATENCY_REFRESH = 15,   // リフレッシュ重畳時レイテンシ
    parameter int REFRESH_PPM     = 500,  // 発生頻度(百万分率。500=0.05%)
    parameter int PHYS_AW         = 20,   // 物理アドレス幅(V3.5 MMU=20bit)
    parameter int MEM_AW          = 20    // ★V3.5追加: メモリ配列の実確保幅★
) (
    input  logic                  clk,      // PSRAM側高速クロック
    input  logic                  rst_n,

    input  logic [PHYS_AW-1:0]    addr,     // ★物理アドレス(全幅を使用する)★
    input  logic [7:0]            wdata,
    input  logic                  we,
    input  logic                  req,
    output logic                  ack,
    output logic [7:0]            rdata,

    // 診断用(TB観測専用)
    output logic                  dbg_refresh_hit
);

    // ★V3.5: メモリ配列をMEM_AWで確保(V3の[0:65535]固定を廃止)★
    logic [7:0] mem [0:(1<<MEM_AW)-1];

    typedef enum logic [1:0] {PS_IDLE, PS_BUSY, PS_WAIT_REQ_LOW} ps_state_t;
    ps_state_t ps_state;
    integer    busy_cnt;

    // ★V3.5: addr_lo(16bit固定)を廃止し、MEM_AW幅で使用する★
    //   これによりMMUがリマップした上位ビットが実際に効くようになる。
    logic [MEM_AW-1:0] mem_idx;
    assign mem_idx = addr[MEM_AW-1:0];

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
                        if (we) mem[mem_idx] <= wdata;   // ★全幅アドレスで参照★
                        rdata           <= mem[mem_idx];
                        dbg_refresh_hit <= refresh_this_access;
                        ack             <= 1'b1;
                        ps_state        <= PS_WAIT_REQ_LOW;
                    end else begin
                        busy_cnt <= busy_cnt - 1;
                    end
                end
                PS_WAIT_REQ_LOW: begin
                    // 4相: reqが下がるまでackを維持(cdc_bridge契約)
                    if (!req) begin
                        ack      <= 1'b0;
                        ps_state <= PS_IDLE;
                    end
                end
            endcase
        end
    end

endmodule
