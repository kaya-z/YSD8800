// ============================================================
//  ysd8800_mmio_stub_v0_4.sv   v0.4  (2026-07-12)
//  YSD8800 FPGA V4 : MMIOスタブ + MMUレジスタ + YSD8004 + ★YSD8001★
//
//  設計根拠: v3_design_memo_v0_2.md   §4.2 (V3スタブ部・継承)
//            v3_5_design_memo_v0_2.md §4.3 (MMUレジスタ部・継承)
//            v3_7_design_memo_v0_2.md §4.2 (YSD8004接続・案B・継承)
//            v4_design_memo_v0_2.md   §4.1 (YSD8001接続・案B・承認済)
//  黄金参照: emu23 v1.09 (emu23_v109.c)
//              MMU_PTR_BASE=0xFF00 / MMU_MCR_ADDR=0xFF10 / MCR_EN=bit0
//              IRQ_STAT_ADDR=0xFCB2 / IRQ_MASK_ADDR=0xFCB4  (L294-295)
//              UART_TX=0xFC80 / RX=0xFC82 / STAT=0xFC84 / BAUD=0xFC86 (L561-564)
//
//  ------------------------------------------------------------
//  【V3.7(v0.3)からの変更点】★V4で追加★
//    (1) YSD8001 UART(ysd8800_ysd8001_v0_1)をインスタンス化
//    (2) $FC80-$FC87 を YSD8001 へルーティング
//          $FC80 : UART_TX   (下位)  W
//          $FC81 : (上位)            R  常時0x00   ★KY-B/論点A★
//          $FC82 : UART_RX   (下位)  R  ★読出に副作用なし★
//          $FC83 : (上位)            R  常時0x00   ★KY-B/論点A★
//          $FC84 : UART_STAT (下位)  R / Write-to-Clear(bit1のみ)
//          $FC85 : (上位)            R  常時0x00   ★KY-B/論点A★
//          $FC86 : UART_BAUD (下位)  R/W
//          $FC87 : UART_BAUD (上位)  R/W
//
//    (3) ★割込源の結線が変わった★
//        v0.3: irq_src_uart_rx / irq_src_uart_tx は【外部ポート】
//              （V4で接続する、というプレースホルダ）
//        v0.4: YSD8001 が内部にあるため【内部結線】になった。
//              → 外部ポートから削除し、YSD8001 の出力を直結する。
//        irq_src_stor は V6 まで外部ポートのまま残す。
//
//    (4) ★物理層ポートを新規に外部へ出す★（論点C=案C-1・承認済）
//        rx_valid_i / rx_data_i / tx_valid_o / tx_data_o
//        V4 ではTBが直接叩く疑似ポート。V9 で実シリアライザを接続する。
//
//    (5) リード多重化に YSD8001 を追加
//
//    ★MMUレジスタ部・YSD8004部・診断出力は v0.3 から一切不変★
//  ------------------------------------------------------------
//
//  【★案B: スタブはルーティングに徹する★】(承認済・V3.7から継承)
//    YSD8001 の機能実体(TX/RX/STAT/BAUD・W2C・TDRE・オーバーラン)は
//    すべて ysd8800_ysd8001_v0_1.sv 側にある。本モジュールは
//    「アドレスをデコードして sel/we/wdata を渡し、rdata を選ぶ」だけ。
//
//  【★KY44 / 原則67: デバイス内オフセットは3bit★】
//    $FC80[1:0] = $FC84[1:0] = 2'b00 （TX と STAT が衝突）
//    $FC82[1:0] = $FC86[1:0] = 2'b10 （RX と BAUD が衝突）
//    → 2bitでは原理的にデコード不能。V3.7 BUG-1 と全く同じ構造の罠。
//    → mmio_addr[2:0] を渡す。
//
//  【★論点A=案A-3（承認済）★】
//    上位バイト($FC81/$FC83/$FC85)は範囲デコードで拾い、0x00 を返す。
//    emu23 は == 点デコードのため PSRAM に抜けるが、yuios_memmap は
//    「$FC80- 絶対RAM禁止」と規約で固定しており、emu23 の当該挙動は
//    【規約違反時の未定義動作】に過ぎない。仕様として写像しない。→KY47
//    ※ なお ysd8800_addr_decoder_v0_1 が $FC80 以降を丸ごと MMIO 側へ
//      振っている(L43: is_mmio = addr >= 16'hFC80)ため、$FC81 が PSRAM
//      へ抜けることは構造的に起こりえない。案A-3 は既に成立している。
//
//  【原則59】always_comb/always_ff内の定数ビット選択はIcarus 12.0で
//            制約があるため、MCR bit0 の抽出は assign で外出しする。
// ============================================================
`timescale 1ns/1ps

module ysd8800_mmio_stub_v0_4 (
    input  logic        clk,
    input  logic        rst_n,

    input  logic [15:0] mmio_addr,
    input  logic [7:0]  mmio_wdata,
    output logic [7:0]  mmio_rdata,
    input  logic        mmio_rd,
    input  logic        mmio_wr,
    output logic        mmio_ready,

    // ---- MMUへの供給(V3.5・不変) ----
    //   Icarus 12.0 の unpacked array port 制約回避のため packed 128bit
    //   ptr_flat_o[8*n +: 8] が PTR[n] に対応する。
    output logic [127:0] ptr_flat_o,   // {PTR[15],...,PTR[1],PTR[0]}
    output logic         mmu_en_o,     // MCR bit0

    // ---- YSD8004 割込I/F(V3.7) ----
    //   ★V4変更: irq_src_uart_rx / irq_src_uart_tx は【削除】した。
    //     YSD8001 が本モジュール内部にインスタンス化されたため、
    //     割込源は内部結線になった（外部から与えるものではなくなった）。
    input  logic        irq_src_stor,      // V6で YSD8003 から接続(据置)
    //   CPUへの割込出力 ★レベル信号★ (IRQ_STAT != 0)
    //   CPU側で irq_in = (irq1_o ? 3'd2 : 3'd0) として接続する
    output logic        irq1_o,

    // ---- ★V4新規: YSD8001 物理層I/F★ (論点C=案C-1・承認済) ----
    //   V4 ではTBが直接叩く疑似ポート。V9 で実シリアライザを接続する。
    input  logic        uart_rx_valid_i,   // 1クロックパルス
    input  logic [7:0]  uart_rx_data_i,
    output logic        uart_tx_valid_o,   // 1クロックパルス(送信開始)
    output logic [7:0]  uart_tx_data_o,

    // 診断用出力(TB観測専用・機能には無関係)
    output logic [15:0] dbg_last_addr,
    output logic [31:0] dbg_access_count
);

    // ------------------------------------------------------------
    // アドレス定数 (emu23 v1.09 と一致)
    // ------------------------------------------------------------
    localparam logic [15:0] MMU_PTR_BASE = 16'hFF00;   // PTR[0]
    localparam logic [15:0] MMU_PTR_LAST = 16'hFF0F;   // PTR[15]
    localparam logic [15:0] MMU_MCR_ADDR = 16'hFF10;   // MCR

    // ★V3.7: YSD8004 (emu23 L294-295)
    localparam logic [15:0] YS4_BASE     = 16'hFCB2;   // IRQ_STAT (下位)
    localparam logic [15:0] YS4_LAST     = 16'hFCB5;   // IRQ_MASK (上位)

    // ★V4新規: YSD8001 UART (emu23 L561-564)
    //   $FC80 TX / $FC82 RX / $FC84 STAT / $FC86 BAUD (+各上位バイト)
    localparam logic [15:0] YS1_BASE     = 16'hFC80;   // UART_TX (下位)
    localparam logic [15:0] YS1_LAST     = 16'hFC87;   // UART_BAUD (上位)

    logic access;
    assign access = mmio_rd | mmio_wr;

    // ------------------------------------------------------------
    // アドレスヒット判定 (すべて【論理アドレス】で判定・変換を受けない)
    // ------------------------------------------------------------
    logic hit_ptr, hit_mcr, hit_ys4, hit_ys1;
    assign hit_ptr = (mmio_addr >= MMU_PTR_BASE) && (mmio_addr <= MMU_PTR_LAST);
    assign hit_mcr = (mmio_addr == MMU_MCR_ADDR);
    assign hit_ys4 = (mmio_addr >= YS4_BASE) && (mmio_addr <= YS4_LAST);  // ★V3.7★
    assign hit_ys1 = (mmio_addr >= YS1_BASE) && (mmio_addr <= YS1_LAST);  // ★V4★

    // PTRインデックス(下位4bit) ... 原則59: assignで外出し
    logic [3:0] ptr_idx;
    assign ptr_idx = mmio_addr[3:0];

    // ★V3.7: YSD8004内オフセット(★下位3bit★) ... 原則59: assignで外出し
    //   $FCB2 -> 3'b010 / $FCB3 -> 3'b011 / $FCB4 -> 3'b100 / $FCB5 -> 3'b101
    //
    //   ★【S5 BUG-1 修正】当初2bit(mmio_addr[1:0])としたが、
    //     $FCB2[1:0]=2'b10 / $FCB4[1:0]=2'b00 であり、STAT と MASK が
    //     入れ替わっていた（mmio_addr[2]でしか区別できない）。
    //     3bitにして一意にデコードする。
    logic [2:0] ys4_off;
    assign ys4_off = mmio_addr[2:0];

    // ★V4新規: YSD8001内オフセット(★下位3bit★) ... 原則59/KY44
    //   $FC80 -> 3'b000  $FC81 -> 3'b001
    //   $FC82 -> 3'b010  $FC83 -> 3'b011
    //   $FC84 -> 3'b100  $FC85 -> 3'b101
    //   $FC86 -> 3'b110  $FC87 -> 3'b111
    //
    //   ★★KY44: ここを2bitにすると V3.7 BUG-1 の完全な再演になる★★
    //     $FC80[1:0]=2'b00 と $FC84[1:0]=2'b00 → TX と STAT が衝突
    //     $FC82[1:0]=2'b10 と $FC86[1:0]=2'b10 → RX と BAUD が衝突
    //     単体TBがaddr_iを直接与えると露見しないため、必ず3bitとする。
    logic [2:0] ys1_off;
    assign ys1_off = mmio_addr[2:0];

    // ------------------------------------------------------------
    // MMUレジスタ本体 (V3.5から不変)
    // ------------------------------------------------------------
    logic [7:0] ptr_r [0:15];
    logic [7:0] mcr_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 恒等写像リセット (emu23 mmu_reset())
            for (int i = 0; i < 16; i++) ptr_r[i] <= i[7:0];
            mcr_r <= 8'h00;                  // MMU無効
        end else if (mmio_wr) begin
            // 常時アクセス可(MCR.EN に依存しない)
            if (hit_ptr) ptr_r[ptr_idx] <= mmio_wdata;
            if (hit_mcr) mcr_r          <= mmio_wdata;
        end
    end

    // ---- MMUへの供給 (V3.5から不変) ----
    genvar gi;
    generate
        for (gi = 0; gi < 16; gi = gi + 1) begin : g_ptr_flat
            assign ptr_flat_o[8*gi +: 8] = ptr_r[gi];
        end
    endgenerate

    // 原則59: MCR bit0 抽出は assign で外出し
    assign mmu_en_o = mcr_r[0];

    // ------------------------------------------------------------
    // ★V4新規: YSD8001 UART (案B: 独立モジュールを接続)
    //   本モジュールはルーティングに徹する。機能実体はYSD8001側。
    // ------------------------------------------------------------
    logic [7:0] ys1_rdata;

    // ★YSD8001 → YSD8004 への割込源（内部結線）★
    //   v0.3 では外部ポートだったが、YSD8001 が内部に来たので内部信号化。
    logic irq_uart_rx;   // ★1クロックパルス★
    logic irq_uart_tx;   // ★レベル★（TDRE・論点B=案B-1承認済）

    ysd8800_ysd8001_v0_1 u_ysd8001 (
        .clk        (clk),
        .rst_n      (rst_n),
        // MMIOルーティング: 本デバイスがヒットした時のみ sel を上げる
        .sel_i      (hit_ys1 & access),
        .addr_i     (ys1_off),          // ★3bit(KY44)★
        .we_i       (mmio_wr),
        .wdata_i    (mmio_wdata),
        .rdata_o    (ys1_rdata),
        // YSD8004 への割込源
        .irq_rx_o   (irq_uart_rx),
        .irq_tx_o   (irq_uart_tx),
        // 物理層(V4は疑似ポート・外部へ素通し。V9で実シリアライザ接続)
        .rx_valid_i (uart_rx_valid_i),
        .rx_data_i  (uart_rx_data_i),
        .tx_valid_o (uart_tx_valid_o),
        .tx_data_o  (uart_tx_data_o)
    );

    // ------------------------------------------------------------
    // ★V3.7: YSD8004 割込コントローラ (案B: 独立モジュールを接続)
    //   本モジュールはルーティングに徹する。機能実体はYSD8004側。
    //   ★V4変更: 割込源を YSD8001 から【内部結線】で受ける★
    // ------------------------------------------------------------
    logic [7:0] ys4_rdata;

    ysd8800_ysd8004_v0_1 u_ysd8004 (
        .clk             (clk),
        .rst_n           (rst_n),
        // MMIOルーティング: 本デバイスがヒットした時のみ sel を上げる
        .sel_i           (hit_ys4 & access),
        .addr_i          (ys4_off),
        .we_i            (mmio_wr),
        .wdata_i         (mmio_wdata),
        .rdata_o         (ys4_rdata),
        // ★割込源: V4 で YSD8001 から内部結線された★
        .irq_src_uart_rx (irq_uart_rx),    // ★V4接続★ 1クロックパルス
        .irq_src_stor    (irq_src_stor),   // V6で接続(外部ポートのまま)
        .irq_src_uart_tx (irq_uart_tx),    // ★V4接続★ レベル(TDRE)
        // CPUへの割込出力(レベル)
        .irq1_o          (irq1_o)
    );

    // ------------------------------------------------------------
    // リードデータ多重化 (組合せ)
    //   MMUレジスタ / YSD8004 / YSD8001 以外は従来スタブ挙動 = 固定0x00
    //
    //   ★各hitの範囲は互いに重ならない（排他）★
    //     YS1: $FC80-$FC87 / YS4: $FCB2-$FCB5 / PTR: $FF00-$FF0F / MCR: $FF10
    //   したがって優先順位に意味はないが、明示的にelse ifで並べる。
    // ------------------------------------------------------------
    always_comb begin
        if (hit_ptr)      mmio_rdata = ptr_r[ptr_idx];
        else if (hit_mcr) mmio_rdata = mcr_r;
        else if (hit_ys4) mmio_rdata = ys4_rdata;      // V3.7
        else if (hit_ys1) mmio_rdata = ys1_rdata;      // ★V4新規★
        else              mmio_rdata = 8'h00;          // V3スタブ挙動
    end

    // 即時ready(組合せ)。V3から不変。
    //   YSD8004 / YSD8001 も組合せリード/1クロックライトのためウェイト不要。
    assign mmio_ready = access;

    // ------------------------------------------------------------
    // 診断ラッチ・カウンタ (V3から不変)
    // ------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dbg_last_addr    <= 16'h0000;
            dbg_access_count <= 32'h0000_0000;
        end else if (access) begin
            dbg_last_addr    <= mmio_addr;
            dbg_access_count <= dbg_access_count + 32'd1;
        end
    end

endmodule
