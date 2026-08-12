//==============================================================
// sd_spi_model_v0_1_poc.sv
//   SDカード SPIモード ビヘイビアモデル（V6-A 黄金リファレンス）
//   - 設計メモ: v6a_storage_design_memo_v0_2.md §4.2
//   - KY38: _poc サフィックス（検証用モデル・本番RTLではない）
//   - 権威付け方針: SD Physical Layer Simplified Spec の SPIモード
//     コマンド/レスポンス順に忠実。R1/R7/トークン0xFE/CRC16 を模擬。
//   Version: v0.1 (2026-07-18)
//
// 【責務範囲（設計メモ§4.2）】
//   模擬する: CMD0→R1(0x01) / CMD8→R7 / CMD55+ACMD41→R1(0x00) /
//             CMD17→R1(0x00)→データトークン0xFE→512B→CRC16(ダミー)
//   模擬しない: 実CRC7検証（受理のみ）・電気的タイミング・複数枚
//
// 【SPIモード基礎（MC6809的に言えば同期シリアルのシフトレジスタ授受）】
//   - CS_n=0 でカード選択。SCK立上りでMOSIサンプル・MISOはSCK立下りで更新（mode0想定）
//   - ホストは8bit単位でコマンド送出（6バイト: 0x40|cmd, arg[31:0], crc7|1）
//   - カードはR1(1バイト)等で応答。CMD17後はデータトークン0xFE + 512B + CRC16
//
// 【既知パターン】セクタ内容 = (lba*512 + i) の下位8bit  … RTL/TB照合用
//==============================================================
`timescale 1ns/1ps

module sd_spi_model_v0_1_poc (
    input  logic cs_n,     // チップセレクト（0=選択）
    input  logic sck,      // SPIクロック（ホスト生成）
    input  logic mosi,     // Master Out Slave In（ホスト→カード）
    output logic miso      // Master In Slave Out（カード→ホスト）
);

    //--------------------------------------------------------------
    // 内部状態
    //--------------------------------------------------------------
    // 受信シフタ（MOSIをSCK立上りで取り込む）
    logic [7:0] rx_shift;
    logic [3:0] rx_bitcnt;      // 0-7
    logic       rx_byte_valid;  // 1バイト受信完了パルス
    logic [7:0] rx_byte;

    // 送信シフタ（MISOをSCK立下りで更新）
    logic [7:0] tx_shift;
    logic [3:0] tx_bitcnt;

    // コマンド受信バッファ（6バイト）
    logic [7:0] cmd_buf [0:5];
    integer     cmd_idx;

    // カード状態機械
    typedef enum logic [3:0] {
        ST_IDLE_UNINIT,   // 電源投入直後（CMD0待ち）
        ST_IDLE,          // CMD0受理後アイドル（未初期化・R1=0x01返す）
        ST_READY,         // ACMD41完了後（初期化済・R1=0x00）
        ST_SEND_R1,       // R1レスポンス送出中
        ST_SEND_R7,       // R7(R1+4バイト)送出中
        ST_READ_WAIT,     // CMD17後、データトークン準備
        ST_READ_TOKEN,    // 0xFE送出
        ST_READ_DATA,     // 512バイト送出
        ST_READ_CRC       // CRC16 2バイト送出
    } state_t;
    state_t st;

    // レスポンス送出FIFO（簡易: バイト列を順に吐く）
    logic [7:0] resp_queue [0:7];
    integer     resp_len;
    integer     resp_ptr;

    // CMD17 データ転送用
    logic [31:0] cur_lba;
    integer      data_idx;      // 0-511
    logic [7:0]  crc16_lo, crc16_hi;  // ダミーCRC（模擬）

    // MISOアイドルレベル = 1（SPIラインのプルアップ相当）
    logic miso_r;
    assign miso = cs_n ? 1'b1 : miso_r;

    //--------------------------------------------------------------
    // 初期化
    //--------------------------------------------------------------
    initial begin
        rx_shift   = 8'h00;
        rx_bitcnt  = 0;
        rx_byte    = 8'h00;
        rx_byte_valid = 0;
        tx_shift   = 8'hFF;
        tx_bitcnt  = 0;
        cmd_idx    = 0;
        st         = ST_IDLE_UNINIT;
        resp_len   = 0;
        resp_ptr   = 0;
        cur_lba    = 0;
        data_idx   = 0;
        miso_r     = 1'b1;
        crc16_lo   = 8'h00;
        crc16_hi   = 8'h00;
    end

    //--------------------------------------------------------------
    // 受信: SCK立上りでMOSIを取り込む（mode0）
    //--------------------------------------------------------------
    always @(posedge sck) begin
        if (!cs_n) begin
            rx_shift <= {rx_shift[6:0], mosi};
            if (rx_bitcnt == 4'd7) begin
                rx_bitcnt     <= 0;
                rx_byte       <= {rx_shift[6:0], mosi};
                rx_byte_valid <= 1'b1;
            end else begin
                rx_bitcnt     <= rx_bitcnt + 1;
                rx_byte_valid <= 1'b0;
            end
        end
    end

    //--------------------------------------------------------------
    // 送信: SCK立下りでMISOを更新（mode0）
    //--------------------------------------------------------------
    always @(negedge sck) begin
        if (!cs_n) begin
            miso_r <= tx_shift[7];
            tx_shift <= {tx_shift[6:0], 1'b1};  // 送出後はFF埋め
            if (tx_bitcnt == 4'd7) begin
                tx_bitcnt <= 0;
                // 次バイトのロードは処理FSM側で行う
                load_next_tx();
            end else begin
                tx_bitcnt <= tx_bitcnt + 1;
            end
        end
    end

    //--------------------------------------------------------------
    // 次送信バイトのロード（レスポンスキュー/データ列から）
    //--------------------------------------------------------------
    task load_next_tx;
        begin
            case (st)
                ST_SEND_R1, ST_SEND_R7: begin
                    if (resp_ptr < resp_len) begin
                        tx_shift = resp_queue[resp_ptr];
                        resp_ptr = resp_ptr + 1;
                    end else begin
                        tx_shift = 8'hFF;
                        // R7送出完了で状態遷移
                        finish_response();
                    end
                end
                ST_READ_TOKEN: begin
                    tx_shift = 8'hFE;         // データトークン
                    st = ST_READ_DATA;
                    data_idx = 0;
                end
                ST_READ_DATA: begin
                    tx_shift = (cur_lba*512 + data_idx) & 8'hFF;  // 既知パターン
                    if (data_idx == 511) begin
                        st = ST_READ_CRC;
                        crc16_lo = 8'h00;  // ダミーCRC16（模擬・値照合対象外）
                        crc16_hi = 8'h00;
                        data_idx = 0;
                    end else begin
                        data_idx = data_idx + 1;
                    end
                end
                ST_READ_CRC: begin
                    if (data_idx == 0) begin
                        tx_shift = crc16_hi;
                        data_idx = 1;
                    end else begin
                        tx_shift = crc16_lo;
                        st = ST_READY;   // 読出完了→READYへ戻る
                        data_idx = 0;
                    end
                end
                default: tx_shift = 8'hFF;
            endcase
        end
    endtask

    //--------------------------------------------------------------
    // R1/R7送出完了後の遷移
    //--------------------------------------------------------------
    task finish_response;
        begin
            // CMD17のR1(0x00)送出完了なら読出トークンフェーズへ
            if (last_cmd == 6'd17 && st == ST_SEND_R1) begin
                st = ST_READ_TOKEN;
            end else begin
                // 通常はアイドル/レディへ復帰（初期化進行はコマンド受理側で更新）
                st = post_resp_state;
            end
        end
    endtask

    // 直近コマンド番号・応答後遷移先を保持
    logic [5:0] last_cmd;
    state_t     post_resp_state;
    logic       acmd_pending;   // CMD55直後（次のCMD41をACMD41と解釈）

    //--------------------------------------------------------------
    // コマンド解析: 6バイト受信完了で応答を組む
    //--------------------------------------------------------------
    always @(posedge sck) begin
        if (!cs_n && rx_byte_valid) begin
            // コマンドフレーム収集（先頭バイトのbit7:6=01でコマンド開始）
            if (cmd_idx == 0) begin
                if (rx_byte[7:6] == 2'b01) begin
                    cmd_buf[0] = rx_byte;
                    cmd_idx    = 1;
                end
                // それ以外(0xFF等ダミークロック)は無視
            end else begin
                cmd_buf[cmd_idx] = rx_byte;
                if (cmd_idx == 5) begin
                    cmd_idx = 0;
                    decode_command();
                end else begin
                    cmd_idx = cmd_idx + 1;
                end
            end
        end
    end

    //--------------------------------------------------------------
    // コマンドデコード＆レスポンス構築
    //--------------------------------------------------------------
    task decode_command;
        logic [5:0]  cmd;
        logic [31:0] arg;
        begin
            cmd = cmd_buf[0][5:0];
            arg = {cmd_buf[1], cmd_buf[2], cmd_buf[3], cmd_buf[4]};
            last_cmd = cmd;
            resp_ptr = 0;

            case (cmd)
                6'd0: begin  // CMD0 GO_IDLE_STATE
                    resp_queue[0] = 8'h01;  // R1: アイドル
                    resp_len = 1;
                    st = ST_SEND_R1;
                    post_resp_state = ST_IDLE;
                    acmd_pending = 0;
                end
                6'd8: begin  // CMD8 SEND_IF_COND → R7
                    resp_queue[0] = 8'h01;      // R1
                    resp_queue[1] = 8'h00;
                    resp_queue[2] = 8'h00;
                    resp_queue[3] = 8'h01;       // 電圧範囲エコー
                    resp_queue[4] = cmd_buf[4];  // チェックパターンエコー
                    resp_len = 5;
                    st = ST_SEND_R7;
                    post_resp_state = ST_IDLE;
                end
                6'd55: begin // CMD55 APP_CMD（次はACMD）
                    resp_queue[0] = 8'h01;
                    resp_len = 1;
                    st = ST_SEND_R1;
                    post_resp_state = ST_IDLE;
                    acmd_pending = 1;
                end
                6'd41: begin // ACMD41 SD_SEND_OP_COND → 初期化完了でR1=0x00
                    if (acmd_pending) begin
                        resp_queue[0] = 8'h00;  // 初期化完了
                        resp_len = 1;
                        st = ST_SEND_R1;
                        post_resp_state = ST_READY;  // 以後READY
                        acmd_pending = 0;
                    end else begin
                        resp_queue[0] = 8'h05;  // illegal（ACMD前置なし）
                        resp_len = 1;
                        st = ST_SEND_R1;
                        post_resp_state = ST_IDLE;
                    end
                end
                6'd17: begin // CMD17 READ_SINGLE_BLOCK
                    cur_lba = arg;
                    resp_queue[0] = 8'h00;  // R1 OK
                    resp_len = 1;
                    st = ST_SEND_R1;
                    post_resp_state = ST_READY;
                    // R1送出完了後 finish_response でトークンフェーズへ
                end
                default: begin
                    resp_queue[0] = 8'h04;  // illegal command
                    resp_len = 1;
                    st = ST_SEND_R1;
                    post_resp_state = ST_READY;
                end
            endcase
            // 最初のレスポンスバイトを即ロード
            tx_shift = 8'hFF;  // コマンド後1バイトはNCR相当のFF、次から実レスポンス
        end
    endtask

endmodule
