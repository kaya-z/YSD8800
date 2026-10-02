//=====================================================================
// ysd8800_ysd8001_v0_2.sv
//
//   YSD8001 UART（調歩同期式シリアル通信インタフェース）
//
//   Project : YSD8800 / YUI OS  --- Step 8 FPGA / V4 → ★工程②.5 TKT-V12★
//   Version : v0.2（v0.1: 2026-07-12）
//   Date    : 2026-09-21
//   Design  : v4_design_memo_v0_2.md（承認版・v4_design_review_reply_v1_0）
//             ★v24_tktv12_uart_phy_design_v0_3_1.md（TKT-V12・条件付承認）★
//   Golden  : emu23 v1.09 (emu23_v109.c)
//   Spec    : ysd8001_uart_design_v1_2.docx
//             ★→ v1.3（md）へ改版予定（設計書 v0.3.1 §8 #7）。分周式は
//               v1.2 §3.4「分周値 = CLK/baud − 1」＝ 1ビット周期 baud_r+1★
//
// 【v0.2 変更点（TKT-V12）】
//   ・parameter bit PHY_EN / BAUD_EN を追加（既定 0/0 = 構成 C-0 = v0.1 等価）
//   ・TXD/RXD 実シリアライザ／デシリアライザ（PHY_EN=1 時のみ generate）
//   ・UART_BAUD 実分周（BAUD_EN=1 時。1ビット = baud_r+1 サイクル）
//   ・ポート追加: txd_o / rxd_i / rx_frame_err_o
//   ・C-3（PHY_EN=0 かつ BAUD_EN=1）は時刻0で $fatal
//
//---------------------------------------------------------------------
// 【役割】
//   1バイトの送受信レジスタと状態フラグを提供し、YSD8004 経由で
//   IRQ1 を発生させる。MC6850 ACIA と同型の思想（TDRE 方式）。
//
// 【レジスタ】（emu23 v1.09 L561-564 実照合）
//   $FC80  UART_TX    W    送信データ（書込で送信開始）
//   $FC81  (上位)     R    常時 0x00                     ★KY-B★
//   $FC82  UART_RX    R    受信データ（★読出に副作用なし★）
//   $FC83  (上位)     R    常時 0x00                     ★KY-B★
//   $FC84  UART_STAT  R/W  状態（W = Write-to-Clear）
//   $FC85  (上位)     R    常時 0x00                     ★KY-B★
//   $FC86  UART_BAUD  R/W  ボーレート分周値（下位）
//   $FC87  UART_BAUD  R/W  ボーレート分周値（上位）
//
// 【★KY45: UART_STAT のリセット値は 0x01 である（0x00 ではない）★】
//   TX_READY=1 で起動する。根拠: emu23 L380 (ysd8001_reset)
//     ysd8001.stat = YSD8001_STAT_TX_READY;
//   ここを 0x00 にすると、リセット直後に送信不能となる。
//   （V3.7 の IRQ_MASK=0x04 と同種の「0でない初期値」の罠）
//
// 【UART_STAT ビット定義】（emu23 L336-337）
//   bit0 = TX_READY  1=送信レジスタ書込可  ★W2C不可（HW自動管理）★
//   bit1 = RX_READY  1=受信バッファにデータあり  ★W2C可★
//   bit2-7 = 予約（0を返す）
//
// 【設計判断】（設計メモ v0.2）
//  ・★KY44/原則67: addr_i は必ず3bit★
//      $FC80[1:0]=2'b00 と $FC84[1:0]=2'b00 が衝突する（TX と STAT）。
//      $FC82[1:0]=2'b10 と $FC86[1:0]=2'b10 が衝突する（RX と BAUD）。
//      2bitでは原理的にデコード不能。V3.7 BUG-1 と全く同じ構造の罠。
//      さらに localparam は実アドレスから機械導出し、手書きしない。
//
//  ・★論点A=案A-3（承認済）: 上位バイトは 0x00 を返す★
//      $FC80-$FC8F を範囲デコードする（V3.7 と統一）。
//      emu23 は == 点デコードのため $FC81 等で PSRAM に抜けるが、
//      yuios_memmap は「$FC80- 絶対RAM禁止」と規約で固定しており、
//      emu23 の当該挙動は【規約違反時の未定義動作】に過ぎない。
//      未定義動作を仕様として写像しない。→ KY47
//
//  ・★論点B=案B-1（承認済）: irq_tx_o はレベル信号★
//      確定設計#1 を「RX/STOR=1クロックパルス、TX=レベル」に改訂。
//      emu23 L496-499: TX_READY=1 の間、毎サイクル ysd8004_raise()。
//      = MC6850 ACIA の TDRE と同一思想。送信バッファが空である限り
//        割込を要求し続け、ドライバは送るデータが尽きたら
//        IRQ_MASK bit2 を立てて黙らせる。
//      YSD8004 は無改修でよい（irq_stat_r |= allowed は冪等）。
//
//  ・★論点C=案C-1（承認済）: 物理シリアライザは V9 へ★
//      TXD/RXD のシリアライザ／デシリアライザは本モジュールに含めない。
//      emu23 に物理層は存在せず（stdin/stdout 仮想化）、外部観測等価の
//      対象外であるため、V4 のゲート判定に寄与しない。
//      ただし将来の接続点ポートは本 v0.1 で確保する（レビュー §5 必須）。
//
// 【スコープ外】
//   ・TXD/RXD 物理シリアライザ（V9）
//   ・UART_BAUD による実分周（V9。本版は保持のみ・動作影響なし）
//     emu23 L148 相当:「読み書きしてもボーレートに影響なし」
//   ★→ v0.2: 上記2項目は TKT-V12 にて工程②.5（旧呼称 V9）で実装済。
//      ただし既定（PHY_EN=0/BAUD_EN=0）では v0.1 と同じくスコープ外動作。
//      詳細は v24_tktv12_uart_phy_design_v0_3_1.md。★
//=====================================================================

`timescale 1ns / 1ps

module ysd8800_ysd8001_v0_2 #(
    //--- ★TKT-V12 構成切替（設計書 §6・C-12: WBUF_EN と同じ parameter bit）★
    //   C-0: 0/0 既定・v0.1等価 / C-1: 1/0 / C-2: 1/1 FPGA実機 / C-3: 0/1 禁止
    parameter bit PHY_EN  = 1'b0,
    parameter bit BAUD_EN = 1'b0
) (
    input  logic        clk,
    input  logic        rst_n,

    //--- MMIO バスI/F（バイト粒度。MMIOスタブからルーティングされる）---
    input  logic        sel_i,        // 本デバイスが選択された (hit_ys1 & access)
    input  logic [2:0]  addr_i,       // ★アドレス下位3bit（mmio_addr[2:0]）★
                                      //   ★KY44: 2bitでは TX/STAT・RX/BAUD が衝突★
    input  logic        we_i,         // 1=write / 0=read
    input  logic [7:0]  wdata_i,
    output logic [7:0]  rdata_o,

    //--- YSD8004 への割込源 ---
    output logic        irq_rx_o,     // ★1クロックパルス★ → IRQ_STAT bit0
    output logic        irq_tx_o,     // ★レベル★（TX_READY=1の間）→ IRQ_STAT bit2

    //--- 物理層 I/F（V4では疑似ポート。V9で実シリアライザを接続）---
    input  logic        rx_valid_i,   // 1クロックパルス（受信1バイト確定）
    input  logic [7:0]  rx_data_i,
    output logic        tx_valid_o,   // 1クロックパルス（送信開始）
    output logic [7:0]  tx_data_o,
                                      // ★C-2 では上4本はデバッグ観測専用（§6.2）★
                                      // ★PHY_EN=1 時 rx_valid_i/rx_data_i は無視（§5.2）★

    //--- ★v0.2 追加: 実シリアル物理層（TKT-V12）★ ---
    output logic        txd_o,          // ★アイドル/リセット/PHY_EN=0 時は常に 1★
    input  logic        rxd_i,          // ★非同期入力。PHY_EN=0 では参照しない（§8.3）★
    output logic        rx_frame_err_o  // ★1クロックパルス・デバッグ専用（§5.1.1）★
);

    //-----------------------------------------------------------------
    // アドレスデコード
    //   ★原則67 / KY44: 実アドレスから【機械導出】する★
    //     V3.7 BUG-1 は localparam を手書きしたことが遠因であった。
    //     ここで数値を手書きすると、TBが同じ思い込みを共有した場合に
    //     偽合格（false-pass）する。
    //-----------------------------------------------------------------
    localparam logic [15:0] ADDR_TX      = 16'hFC80;
    localparam logic [15:0] ADDR_RX      = 16'hFC82;
    localparam logic [15:0] ADDR_STAT    = 16'hFC84;
    localparam logic [15:0] ADDR_BAUD    = 16'hFC86;

    // 下位3bitを実アドレスから抽出（手書き禁止）
    localparam logic [2:0] A_TX_LO   = ADDR_TX[2:0];         // $FC80 -> 3'b000
    localparam logic [2:0] A_TX_HI   = ADDR_TX[2:0]   + 3'd1; // $FC81 -> 3'b001
    localparam logic [2:0] A_RX_LO   = ADDR_RX[2:0];         // $FC82 -> 3'b010
    localparam logic [2:0] A_RX_HI   = ADDR_RX[2:0]   + 3'd1; // $FC83 -> 3'b011
    localparam logic [2:0] A_STAT_LO = ADDR_STAT[2:0];       // $FC84 -> 3'b100
    localparam logic [2:0] A_STAT_HI = ADDR_STAT[2:0] + 3'd1; // $FC85 -> 3'b101
    localparam logic [2:0] A_BAUD_LO = ADDR_BAUD[2:0];       // $FC86 -> 3'b110
    localparam logic [2:0] A_BAUD_HI = ADDR_BAUD[2:0] + 3'd1; // $FC87 -> 3'b111

    //-----------------------------------------------------------------
    // UART_STAT ビット定義（emu23 L336-337）
    //-----------------------------------------------------------------
    localparam int BIT_TX_READY = 0;
    localparam int BIT_RX_READY = 1;

    // ★Write-to-Clear の対象は bit1 (RX_READY) のみ★
    //   emu23 L340: #define YSD8001_STAT_WTC_MASK 0x0002
    //   bit0 (TX_READY) への書込は【完全に無視】する（HW自動管理）
    localparam logic [7:0] STAT_WTC_MASK = 8'h02;

    //-----------------------------------------------------------------
    // TX タイミングモデル（emu23 L344）
    //   #define YSD8001_TX_CYCLES 4167
    //     = 10bit x (4MHz / 9600bps) = 4166.67 -> 4167
    //   FPGA の CPU クロックも 4MHz（ロードマップ確定）のため同一定数。
    //   4167 < 8192 = 2^13 なので 13bit カウンタで足りる。
    //-----------------------------------------------------------------
    localparam int TX_CYCLES = 4167;

    //-----------------------------------------------------------------
    // レジスタ実体
    //-----------------------------------------------------------------
    logic [7:0]  stat_r;       // UART_STAT   ★reset = 8'h01（KY45）★
    logic [7:0]  rx_buf_r;     // UART_RX 内部バッファ
    logic [15:0] baud_r;       // UART_BAUD   reset = 16'd416
    logic [12:0] tx_cnt_r;     // TX ダウンカウンタ（0 = 送信中でない）

    //-----------------------------------------------------------------
    // MMIO アクセス条件（原則59: assign で外出し）
    //-----------------------------------------------------------------
    logic wr_tx;      // $FC80 への書込 = 送信開始
    logic wr_stat;    // $FC84 への書込 = Write-to-Clear
    logic wr_baud_lo; // $FC86 への書込
    logic wr_baud_hi; // $FC87 への書込

    assign wr_tx      = sel_i & we_i & (addr_i == A_TX_LO);
    assign wr_stat    = sel_i & we_i & (addr_i == A_STAT_LO);
    assign wr_baud_lo = sel_i & we_i & (addr_i == A_BAUD_LO);
    assign wr_baud_hi = sel_i & we_i & (addr_i == A_BAUD_HI);

    //-----------------------------------------------------------------
    // TX 送信中判定
    //   emu23 は tx_complete_cycle（絶対サイクル）で管理するが、
    //   RTL では実カウンタ（ダウンカウント）で等価な挙動を作る。
    //-----------------------------------------------------------------
    logic tx_busy;
    logic tx_done;

    logic tx_done_phy;   // ★v0.2: シリアライザのストップビット最終サイクル★

    assign tx_busy = (tx_cnt_r != 13'd0);
    // 最終サイクル（1 -> 0 に落ちる瞬間）で TX_READY を復帰させる
    //   ★v0.2: PHY_EN=1 ではシリアライザ側に置換。位相は同じ
    //     （最終サイクルで 1 → 次エッジで TX_READY=1。設計書 §7.1）★
    assign tx_done = PHY_EN ? tx_done_phy : (tx_cnt_r == 13'd1);

    //-----------------------------------------------------------------
    // RX 受け入れ判定
    //   ★オーバーラン: 先着優先・後着破棄★
    //   emu23 L390: if (stat & RX_READY) return;   ← 既に未読データが
    //   あれば新データを【捨てる】。上書きしない。
    //-----------------------------------------------------------------
    logic rx_accept;
    //   ★v0.2: 疑似ポートと実PHY を【択一 MUX】（OR にしない・設計書 §5.2）★
    logic       rx_valid_phy;
    logic [7:0] rx_data_phy;
    logic       rx_valid_int;
    logic [7:0] rx_data_int;
    assign rx_valid_int = PHY_EN ? rx_valid_phy : rx_valid_i;
    assign rx_data_int  = PHY_EN ? rx_data_phy  : rx_data_i;
    assign rx_accept = rx_valid_int & ~stat_r[BIT_RX_READY];

    //-----------------------------------------------------------------
    // ★kaizen 原則65 対応★
    //   Icarus Verilog 12.0 は always_* 内の【定数ビット選択】を
    //   正しく扱えない（"constant selects in always_* processes are
    //   not currently supported (all bits will be included)" と警告し、
    //   全ビットを含めてしまう＝意図しない値になる）。
    //   → assign で事前に外出しする。
    //-----------------------------------------------------------------
    logic [7:0] baud_lo;
    logic [7:0] baud_hi;
    assign baud_lo = baud_r[7:0];
    assign baud_hi = baud_r[15:8];

    //=================================================================
    // レジスタ更新
    //=================================================================

    //--- UART_STAT ---------------------------------------------------
    //   複数の更新要因が同一サイクルに競合しうる:
    //     (a) TX 書込        -> TX_READY = 0
    //     (b) TX 完了        -> TX_READY = 1
    //     (c) RX 受理        -> RX_READY = 1
    //     (d) Write-to-Clear -> RX_READY = 0（bit1 に 1 を書いた場合）
    //
    //   ★競合の解決方針★
    //     ・bit0 (TX_READY) は (a)/(b) のみが動かす。W2C は【無視】。
    //       (a) と (b) は同時に起こりえない（送信中でなければ (b) は無い）。
    //     ・bit1 (RX_READY) は (c)/(d) が動かす。
    //       同時到来時は【セット優先】とする＝イベントを落とさない。
    //       （emu23 は逐次実行のため競合しないが、RTLでは同時到来しうる。
    //         V3.7 の YSD8004 と同じく「落とさない側に倒す」方針）
    //-----------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // ★★KY45: 0x00 ではない。TX_READY=1 で起動する★★
            //   emu23 L380: ysd8001.stat = YSD8001_STAT_TX_READY;
            stat_r <= 8'h01;
        end
        else begin
            //--- bit0: TX_READY（HW自動管理・W2C対象外）---
            if (wr_tx)
                stat_r[BIT_TX_READY] <= 1'b0;   // (a) 送信開始 -> ビジー
            else if (tx_done)
                stat_r[BIT_TX_READY] <= 1'b1;   // (b) 送信完了 -> 復帰

            //--- bit1: RX_READY（セット優先・W2C対象）---
            if (rx_accept)
                stat_r[BIT_RX_READY] <= 1'b1;                   // (c)
            else if (wr_stat && wdata_i[BIT_RX_READY])
                stat_r[BIT_RX_READY] <= 1'b0;                   // (d) W2C

            //--- bit2-7: 予約（常に 0 を保つ）---
            stat_r[7:2] <= 6'b0;
        end
    end

    //--- UART_RX 内部バッファ ----------------------------------------
    //   ★読出に副作用なし★（emu23 L510-513: RX_READY をクリアしない）
    //   設計判断（UART設計書 §3.2 / レビュー R7）:
    //     読出での自動クリアは「データの取りこぼし」「割り込みの
    //     取りこぼし」のリスクがあるため採用しない。
    //-----------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rx_buf_r <= 8'h00;             // emu23 L381
        else if (rx_accept)
            rx_buf_r <= rx_data_int;       // 受理時のみ更新（後着は破棄）
                                           // ★v0.2: PHY_EN で択一（§5.2）★
    end

    //--- TX ダウンカウンタ -------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            tx_cnt_r <= 13'd0;                       // 送信中でない
        else if (wr_tx)
            tx_cnt_r <= TX_CYCLES[12:0];             // 送信開始
        else if (tx_busy)
            tx_cnt_r <= tx_cnt_r - 13'd1;            // カウントダウン
    end

    //--- UART_BAUD ---------------------------------------------------
    //   ★byte-enable バスのため 2 バイトに分けて保持する★
    //   $FC86 = baud_r[7:0] / $FC87 = baud_r[15:8]
    //   CPU が LDW/STW で叩けば 2 バイトアクセスとなり emu23 と一致。
    //   （LDB 単独アクセスは確定設計#8 により規約で禁止）
    //   本版では保持のみ。実分周は V9（emu23 も動作影響なし）。
    //-----------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            baud_r <= 16'd416;                       // emu23 L382: 9600bps@4MHz
        else begin
            if (wr_baud_lo) baud_r[7:0]  <= wdata_i;
            if (wr_baud_hi) baud_r[15:8] <= wdata_i;
        end
    end

    //=================================================================
    // 読出（組合せ）
    //   ★KY-B / 論点A=案A-3: 上位バイトは必ず 0x00 を返す★
    //     $FC80-$FC8F を範囲デコードする（V3.7 と統一）。
    //     デコードし忘れると、CPU が LDW（16bit=2バイトアクセス）で
    //     $FC84 を読んだ際に上位バイトが不定となる。
    //=================================================================
    always_comb begin
        unique case (addr_i)
            A_TX_LO  : rdata_o = 8'h00;        // UART_TX は Write only
                                               //   emu23: 読出値はダミー(0)
            A_TX_HI  : rdata_o = 8'h00;        // ★上位バイト★
            A_RX_LO  : rdata_o = rx_buf_r;     // ★副作用なし★
            A_RX_HI  : rdata_o = 8'h00;        // ★上位バイト★
            A_STAT_LO: rdata_o = stat_r;
            A_STAT_HI: rdata_o = 8'h00;        // ★上位バイト★
            A_BAUD_LO: rdata_o = baud_lo;      // 原則65: assignで事前抽出
            A_BAUD_HI: rdata_o = baud_hi;      // 原則65: assignで事前抽出
            default  : rdata_o = 8'h00;
        endcase
    end

    //=================================================================
    // YSD8004 への割込出力
    //=================================================================

    //--- RX 割込: ★1クロックパルス★（確定設計#1'）------------------
    //   受理した瞬間のみ 1 クロック発火。保持は YSD8004 の責務。
    //   emu23 L407: ysd8004_raise(IRQ_STAT_BIT_UART_RX);
    //     （poll_rx 内で、新データを受理したときだけ呼ばれる）
    //   ★オーバーランで破棄された後着データでは発火しない★
    //     （rx_accept は RX_READY=0 のときのみ真）
    //-----------------------------------------------------------------
    logic irq_rx_pulse_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            irq_rx_pulse_r <= 1'b0;
        else
            irq_rx_pulse_r <= rx_accept;    // 受理の1クロック後に1パルス
    end

    assign irq_rx_o = irq_rx_pulse_r;

    //--- TX 割込: ★レベル★（TDRE 方式・確定設計#1' / 案B-1）--------
    //   ★★パルスではない。TX_READY=1 の間アサートし続ける★★
    //
    //   emu23 L496-499（実源）:
    //     if (ysd8001.stat & YSD8001_STAT_TX_READY) {
    //         ysd8004_raise(IRQ_STAT_BIT_UART_TX);   // 毎サイクル
    //     }
    //
    //   MC6850 ACIA の TDRE と同一思想:
    //     送信バッファが空である限り割込を要求し続け、ドライバは
    //     送るデータが尽きたら IRQ_MASK bit2 を立てて黙らせる。
    //     MC6809 + ACIA の割込駆動シリアル出力そのもの。
    //
    //   ★エッジパルス化してはならない（案B-2 は却下済）★
    //     W2C 後に再セットされず、ドライバが TDRE を取りこぼし、
    //     emu23（黄金参照）と発散する。
    //
    //   ★YSD8004 は無改修でよい★
    //     irq_stat_r <= irq_stat_r | allowed;  は冪等であり、
    //     レベル入力を受けても IRQ_STAT[2] が立ち続けるだけ。
    //     リセット時 IRQ_MASK=0x04（bit2 マスク）のため、
    //     ドライバが明示的にマスクを外すまで IRQ_STAT[2] は立たない。
    //-----------------------------------------------------------------
    assign irq_tx_o = stat_r[BIT_TX_READY];

    //=================================================================
    // 物理層 I/F（V4 では疑似ポート。V9 で実シリアライザを接続）
    //   ★論点C=案C-1（承認済）★
    //   emu23 L503-505 は putchar() で即時に文字を吐き、TX_READY を
    //   4167 サイクル後に戻す「タイミングだけモデル化」方式である。
    //   RTL も同じく、書込の瞬間に tx_valid_o を1クロック上げる。
    //   V9 ではここに実シリアライザを接続し、tx_valid_o を送信開始
    //   トリガとして使う。
    //   ★→ 撤回（v0.2 / TKT-V12・設計書 v0.3 §4.1・B-11）★
    //     tx_valid_r は wr_tx の 1 クロック遅れであり、トリガにすると
    //     C-1 の TX_READY が N=4169 となり C-0（N=4168）と一致しない。
    //     実シリアライザは wr_tx（組合せ）で起動する（本ファイル末尾）。
    //=================================================================
    logic       tx_valid_r;
    logic [7:0] tx_data_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_valid_r <= 1'b0;
            tx_data_r  <= 8'h00;
        end
        else begin
            tx_valid_r <= wr_tx;               // 書込の1クロック後に1パルス
            if (wr_tx) tx_data_r <= wdata_i;   // 送信データを保持
        end
    end

    assign tx_valid_o = tx_valid_r;
    assign tx_data_o  = tx_data_r;

    //=================================================================
    // ★v0.2 TKT-V12: 実シリアル物理層（設計書 v0.3.1 §3〜§6）★
    //=================================================================

    //--- C-3 禁止（§6.3）: 時刻 0 で発火。合成では無視されうる -----
    generate
        if (!PHY_EN && BAUD_EN) begin : g_bad_cfg
            initial $fatal(1, "YSD8001: BAUD_EN=1 requires PHY_EN=1 (C-3 prohibited)");
        end
    endgenerate

    generate
    if (PHY_EN) begin : g_phy

        //=============================================================
        // TX シリアライザ（§4）
        //   8N1・LSB first。起動は wr_tx（★tx_valid_r ではない・B-11★）
        //   ロード値 = ビット周期 − 1
        //     BAUD_EN=1 : 全ビット baud_r（周期 baud_r+1・A-3 N+1 分周）
        //     BAUD_EN=0 : start/D0-D7 = 415（周期416）、stop = 422（周期423）
        //                 合計 416×9+423 = 4167 = C-0 と同一（§4.3 案1）
        //   baud_r は送信開始時にラッチ（原則143・§3.3）
        //=============================================================
        logic        tx_run_r;
        logic [3:0]  tx_idx_r;      // 0=start / 1..8=D0..D7 / 9=stop
        logic [15:0] tx_bcnt_r;     // ビット内ダウンカウンタ
        logic [15:0] tx_lat_r;      // baud_r ラッチ（BAUD_EN=1 のみ使用）
        logic [9:0]  tx_sh_r;       // {stop, D7..D0, start}
        logic [3:0]  tx_idx_nx;
        logic [15:0] tx_reload;

        assign tx_idx_nx   = tx_idx_r + 4'd1;
        assign tx_reload   = BAUD_EN ? tx_lat_r
                           : ((tx_idx_nx == 4'd9) ? 16'd422 : 16'd415);
        // ★ストップビット最終サイクル＝C-0 の tx_cnt_r==1 と同位相（§7.1）★
        assign tx_done_phy = tx_run_r & (tx_idx_r == 4'd9) & (tx_bcnt_r == 16'd0);
        assign txd_o       = tx_run_r ? tx_sh_r[tx_idx_r] : 1'b1;

        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                tx_run_r  <= 1'b0;
                tx_idx_r  <= 4'd0;
                tx_bcnt_r <= 16'd0;
                tx_lat_r  <= 16'd416;
                tx_sh_r   <= 10'h3FF;
            end
            else if (wr_tx) begin
                // ★単段（R-3）。送信中の再書込は C-0 と同じく再起動★
                tx_run_r  <= 1'b1;
                tx_idx_r  <= 4'd0;
                tx_sh_r   <= {1'b1, wdata_i, 1'b0};
                tx_lat_r  <= baud_r;
                tx_bcnt_r <= BAUD_EN ? baud_r : 16'd415;
            end
            else if (tx_run_r) begin
                if (tx_bcnt_r == 16'd0) begin
                    if (tx_idx_r == 4'd9)
                        tx_run_r <= 1'b0;                // 送信完了
                    else begin
                        tx_idx_r  <= tx_idx_nx;
                        tx_bcnt_r <= tx_reload;
                    end
                end
                else
                    tx_bcnt_r <= tx_bcnt_r - 16'd1;
            end
        end

        //=============================================================
        // RX デシリアライザ（§5）
        //   2段同期 → 立下り検出 → 半ビット点で start 再確認 → 中央サンプル
        //   半ビット点 = (baud_r+1)>>1（C-13）。0 のとき（baud_r=0）は
        //   スタート検出を抑止し受信しない（§3.2）。
        //   FE 後は立下り検出のため rxd=1 を経由しない限り再起動しない（C-8）。
        //=============================================================
        localparam logic [1:0] RS_IDLE  = 2'd0;
        localparam logic [1:0] RS_START = 2'd1;
        localparam logic [1:0] RS_DATA  = 2'd2;
        localparam logic [1:0] RS_STOP  = 2'd3;

        logic        rxd_s1_r, rxd_s2_r, rxd_s3_r;
        logic [1:0]  rs_r;
        logic [15:0] rx_bcnt_r;
        logic [15:0] rx_lat_r;      // 周期−1 のラッチ
        logic [2:0]  rx_idx_r;
        logic [7:0]  rx_sh_r;
        logic        rx_valid_r;
        logic [7:0]  rx_data_r;
        logic        rx_ferr_r;

        logic        rx_fall;
        logic [7:0]  rx_sh_nx;      // ★原則65: 定数部分選択は assign で外出し★
        logic [15:0] rx_per_m1;
        logic [16:0] rx_baud_p1;
        logic [15:0] rx_half;

        assign rx_fall    = rxd_s3_r & ~rxd_s2_r;
        assign rx_sh_nx   = {rxd_s2_r, rx_sh_r[7:1]};           // LSB first
        assign rx_per_m1  = BAUD_EN ? baud_r : 16'd415;
        assign rx_baud_p1 = {1'b0, baud_r} + 17'd1;
        assign rx_half    = BAUD_EN ? rx_baud_p1[16:1] : 16'd208;

        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                rxd_s1_r <= 1'b1;
                rxd_s2_r <= 1'b1;
                rxd_s3_r <= 1'b1;
            end
            else begin
                rxd_s1_r <= rxd_i;
                rxd_s2_r <= rxd_s1_r;
                rxd_s3_r <= rxd_s2_r;
            end
        end

        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                rs_r       <= RS_IDLE;
                rx_bcnt_r  <= 16'd0;
                rx_lat_r   <= 16'd415;
                rx_idx_r   <= 3'd0;
                rx_sh_r    <= 8'h00;
                rx_valid_r <= 1'b0;
                rx_data_r  <= 8'h00;
                rx_ferr_r  <= 1'b0;
            end
            else begin
                rx_valid_r <= 1'b0;                      // パルス既定
                rx_ferr_r  <= 1'b0;
                case (rs_r)
                    RS_IDLE: begin
                        if (rx_fall && (rx_half != 16'd0)) begin
                            rs_r      <= RS_START;
                            rx_bcnt_r <= rx_half - 16'd1;
                            rx_lat_r  <= rx_per_m1;      // 原則143: 受信要求と一緒にラッチ
                        end
                    end
                    RS_START: begin
                        if (rx_bcnt_r == 16'd0) begin
                            if (!rxd_s2_r) begin         // まだ 0 → start 確定
                                rs_r      <= RS_DATA;
                                rx_idx_r  <= 3'd0;
                                rx_bcnt_r <= rx_lat_r;
                            end
                            else
                                rs_r <= RS_IDLE;         // グリッチとして破棄（M-7）
                        end
                        else
                            rx_bcnt_r <= rx_bcnt_r - 16'd1;
                    end
                    RS_DATA: begin
                        if (rx_bcnt_r == 16'd0) begin
                            rx_sh_r   <= rx_sh_nx;
                            rx_bcnt_r <= rx_lat_r;
                            if (rx_idx_r == 3'd7)
                                rs_r <= RS_STOP;
                            else
                                rx_idx_r <= rx_idx_r + 3'd1;
                        end
                        else
                            rx_bcnt_r <= rx_bcnt_r - 16'd1;
                    end
                    default: begin                       // RS_STOP
                        if (rx_bcnt_r == 16'd0) begin
                            if (rxd_s2_r) begin
                                rx_valid_r <= 1'b1;      // 受理 → rx_accept 経路へ
                                rx_data_r  <= rx_sh_r;
                            end
                            else
                                rx_ferr_r  <= 1'b1;      // FE: 破棄・STAT 不変
                            rs_r <= RS_IDLE;
                        end
                        else
                            rx_bcnt_r <= rx_bcnt_r - 16'd1;
                    end
                endcase
            end
        end

        assign rx_valid_phy   = rx_valid_r;
        assign rx_data_phy    = rx_data_r;
        assign rx_frame_err_o = rx_ferr_r;

    end
    else begin : g_nophy
        //--- C-0: v0.1 等価。rxd_i を参照する論理は存在しない（§8.3 契約）---
        assign txd_o          = 1'b1;      // ★B-6: ブレークを送らない★
        assign tx_done_phy    = 1'b0;
        assign rx_valid_phy   = 1'b0;
        assign rx_data_phy    = 8'h00;
        assign rx_frame_err_o = 1'b0;
    end
    endgenerate

endmodule
