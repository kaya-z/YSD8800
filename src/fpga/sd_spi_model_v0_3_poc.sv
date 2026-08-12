//==============================================================
// sd_spi_model_v0_3_poc.sv
//   SDカード SPIモード ビヘイビアモデル（V6-A/V8 黄金リファレンス）
//   - 設計メモ: v6a_storage_design_memo_v0_2.md §4.2 /
//               v8_catls_integ_design_memo_v0_1.md §3.1
//   - KY38: _poc サフィックス（検証用モデル・本番RTLではない）
//   - 権威付け方針: SD Physical Layer Simplified Spec の SPIモード
//     コマンド/レスポンス順に忠実。R1/R7/トークン0xFE/CRC16 を模擬。
//   Version: v0.3 (2026-07-20)
//
// 【変更履歴】
//   v0.1 (2026-07-18) 新規。初期化/CMD17の応答順を模擬。
//   v0.2 (2026-07-19) CS deassert(立上り)でSPI位相をバイト境界へ
//     リセットする実SD準拠挙動を追加。コマンド間のビット位相ズレで
//     CMD17先頭0x51を取りこぼしR1不達→S_ERRORに陥る不具合を根絶。
//     具体: (1)posedge cs_nでrx_bitcnt/tx_bitcntを0クリア
//           (2)収集always内でCS再アサート初回にcmd_idx=0
//     根拠: 実SDはCS deassertで次トランザクションを先頭バイト境界
//     から開始する（SD物理層一般則）。RTL側は無修正で整合。
//   v0.3 (2026-07-20) V8 cat/lsフル統合向け。データ送出を計算式返し
//     (cur_lba*512+i)&0xFF から、$readmemhで読込んだmkfs実イメージ
//     img_mem[]返しへ置換。mkfsが書いた実FSイメージをSD経由で読ませる
//     ことで「SD→FS→出力」の往復突合を可能にする。範囲外LBAは8'hFF
//     を返す保護付き。RTL側は無修正で整合（TB環境の差し替えのみ）。
//     設計レビュー承認: v8_catls_integ_design_review_reply_v1_0.md 依頼1。
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

module sd_spi_model_v0_3_poc (
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
    logic       cs_prev;    // v0.2: CS前値（再アサート検出でcmd_idxリセット）

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

    // v0.3: SDカード実イメージ（$readmemhでmkfs生成イメージを流し込む）
    //   従来の計算式返し (cur_lba*512+i)&0xFF を実バイト返しへ置換。
    //   IMG_SECTORS=16(8KB)。範囲外LBAアクセスは 8'hFF を返す(保護)。
    parameter        IMG_SECTORS = 16;
    parameter        IMG_BYTES   = IMG_SECTORS * 512;   // 8192
    parameter string IMG_HEX     = "sd_image.hex";      // TB投入前にcpで差し替え
    logic [7:0] img_mem [0:IMG_BYTES-1];
    integer     img_addr;   // cur_lba*512+data_idx（範囲チェック用）

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
        cs_prev    = 1'b1;
        st         = ST_IDLE_UNINIT;
        resp_len   = 0;
        resp_ptr   = 0;
        cur_lba    = 0;
        data_idx   = 0;
        miso_r     = 1'b1;
        crc16_lo   = 8'h00;
        crc16_hi   = 8'h00;
        // v0.3: mkfs生成イメージを読込（1バイト1行hex）。
        $readmemh(IMG_HEX, img_mem);
    end

    //--------------------------------------------------------------
    // v0.2: CS解除(立上り)でビット境界カウンタをリセット。
    //   実SDはCS deassertでSPI位相を初期化し次トランザクションを
    //   先頭バイト境界から開始する（SD物理層一般則）。cmd_idxは
    //   ブロッキング代入の収集always専有のため、そちら側でクリアする
    //   （多重ドライブ回避）。
    //--------------------------------------------------------------
    always @(posedge cs_n) begin
        rx_bitcnt <= 0;
        tx_bitcnt <= 0;
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
    //   v0.2修正: tx_shiftの二重ドライブ（NBA shift と task内ブロッキング
    //   ロードの競合）を解消。バイト途中はシフト、バイト境界では
    //   load_next_tx()に新バイトロードを一任し、シフトしない。
    //--------------------------------------------------------------
    always @(negedge sck) begin
        if (!cs_n) begin
            if (tx_bitcnt == 4'd7) begin
                // バイト境界: 新バイトをロードし、そのMSBを出力。
                // 同時にシフトを1つ進め、次negedgeでbit6が出るようにする。
                load_next_tx();                       // tx_shift = 新バイト（ブロッキング）
                miso_r    <= tx_shift[7];             // 新バイトMSB出力
                tx_shift  <= {tx_shift[6:0], 1'b1};   // 次ビットへシフト
                tx_bitcnt <= 0;                        // 新バイトのbit0を出した→次はbit1..7で7回
            end else begin
                miso_r    <= tx_shift[7];
                tx_shift  <= {tx_shift[6:0], 1'b1};
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
                    // v0.3: 実イメージ返し。範囲外は 8'hFF（保護・レビュー推奨）
                    img_addr = cur_lba*512 + data_idx;
                    if (img_addr < IMG_BYTES)
                        tx_shift = img_mem[img_addr];
                    else
                        tx_shift = 8'hFF;
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
        // v0.2: CS再アサート(1→0)の初回でコマンド収集位相をリセット
        if (cs_prev && !cs_n) cmd_idx = 0;
        cs_prev <= cs_n;
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
                    // v0.2: Ncr(コマンド-R1間ギャップ)としてFFを1バイト前置。
                    //   送出は1バイト遅延パイプのため、これでR1(0x00)が
                    //   確実にMISOへ乗り、RTLのNCR待ちが0x00を捕捉できる。
                    resp_queue[0] = 8'hFF;  // Ncrギャップ
                    resp_queue[1] = 8'h00;  // R1 OK
                    resp_len = 2;
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
