// ============================================================
//  ysd8800_mmio_stub_v0_8.sv   v0.8  (2026-08-24 未接続MMIO応答是正)
//  ★正式版★
//    v0.8 変更点(①.5 冒頭タスク・台帳v1.11 §18.5 案Q):
//      (1) 未接続MMIO読み出し応答を 8'h00 → ★8'hFF★ に是正(L458)。
//          実機は未接続時プルアップで全ビット1。GNDに落ちる回路が
//          無いのに0を返すのは値の捏造であった(V3スタブ時代の残置)。
//          emu23 v1.12以降の $FF 既定と乖離していたのを解消。
//      (2) ロジック変更を伴うため案Xに従いモジュール名も
//          ysd8800_mmio_stub_v0_5 → ★ysd8800_mmio_stub_v0_8★ へ昇格。
//          → 参照元 membus はファイル名のみ繰上げ(案X-1)。
//      ★事前実測(2026-08-24): V8-b本番ランで未接続MMIO読み出しは
//        【0件】(陽性対照=全MMIO読み出し4,490件)。よって本是正は
//        挙動不変であることが実測で保証済(KY57準拠)。
//    ------------------------------------------------------------
//    以下 v0.7 までの記録(欠落させない)
//  ysd8800_mmio_stub_v0_7.sv   v0.7  (2026-07-19 V6-A YSD8003結線)
//  ★正式版★ (V6-A上位結合・原則43承認済 2026-07-19/CHAT108)
//    v0.7 変更点(CHAT109/Step2): YSD8003(ストレージ)を結線。
//      (1) hit_ys3 = $FCA0-$FCB1 を追加(YS3_BASE/YS3_LAST)。$FCB1|$FCB2=YS4で無衝突。
//      (2) u_ysd8003 (ysd8800_ysd8003_v0_1, ファイルv0.3) をインスタンス化。
//          SPI4線(cs_n/sck/mosi/miso)・disk_sectors を外部ポートへ透過。
//      (3) rdata mux に hit_ys3 → ys3_rdata を追加。
//      (4) mmio_ready 合流を hit_ys3?(access&ys3_ready):access へ変更(wait-state)。
//          他ペリフェラルの即応答は不変。状態変更一元化(kaizen準拠)。
//      (5) YSD8003.irq_stor_o(完了1clkパルス) を YSD8004.irq_src_stor へ【内部直結】。
//          → irq_src_stor 外部入力ポートは廃止(V6で内部化)。CPU/membus irq1_ack不要。
//      ★モジュール名は ysd8800_mmio_stub_v0_5 のまま据え置き(上位membus無改修)★
//    v0.6 変更点(1点のみ・案X-1): u_ysd8002 の参照先を
//      ysd8800_ysd8002_v0_2 → ysd8800_ysd8002_v0_3 に更新(L330)。
//      ★本モジュールのロジックは無変更★。ゆえにモジュール名は
//      ysd8800_mmio_stub_v0_5 のまま据え置き(上位membus/TB無改修)。
//      YSD8002本体は発火EN OR→AND化(案B)。詳細 v6_en_fix_design_memo_v0_1.md。
//  ~~ysd8800_mmio_stub_v0_5.sv   v0.5  (2026-07-17 正式版昇格)~~ ←v0.6で改版
//  ★正式版★ (S5昇格・原則43承認済 2026-07-17)
//    昇格記録: v0.5_poc(是正版 md5 d2bef39c…) → v0.5 正式版。
//    OR実装のまま昇格・TCR EN是正はV6以降(v5_design_memo §3.5.2)。
//    u_ysd8002 は正式版 ysd8800_ysd8002_v0_2 を参照(poc除去に追従)。
//  YSD8800 FPGA V5 : MMIOスタブ + MMUレジスタ + YSD8004 + YSD8001 + ★YSD8002★
//
//  ※ v0.4 (2026-07-12): V4 = MMUレジスタ + YSD8004 + ★YSD8001★
//
//  【改版履歴】
//   - 2026-07-14 v0.5    : YSD8002タイマー追加(初版・CHAT94, sedリネームベース)
//   - 2026-07-17 (再適用) : 割込受理クリア irq0_ack 経路3点を適用(案0-a')。
//       (a) irq0_ack 入力ポート追加  (b) u_ysd8002 を v0_1→v0_2_poc 差替
//       (c) u_ysd8002 へ irq0_ack 中継結線。
//       ※CHAT94のsedリネーム版(md5 3058ffbb…)には本3点が欠落していた為、
//         現ナレッジ旧版に対し実源(ysd8002_v0_2_poc/CHAT97記録)から再適用。
//
//  設計根拠: v3_design_memo_v0_2.md   §4.2 (V3スタブ部・継承)
//            v3_5_design_memo_v0_2.md §4.3 (MMUレジスタ部・継承)
//            v3_7_design_memo_v0_2.md §4.2 (YSD8004接続・案B・継承)
//            v4_design_memo_v0_2.md   §4.1 (YSD8001接続・案B・継承)
//            v5_design_memo_v0_3.md   §4  (YSD8002接続・案B・D8承認済)
//  黄金参照: emu23 v1.10 (emu23_v110.c)   ★v0.4 は v1.09 参照★
//              MMU_PTR_BASE=0xFF00 / MMU_MCR_ADDR=0xFF10 / MCR_EN=bit0
//              IRQ_STAT_ADDR=0xFCB2 / IRQ_MASK_ADDR=0xFCB4  (L294-295)
//              UART_TX=0xFC80 / RX=0xFC82 / STAT=0xFC84 / BAUD=0xFC86 (L561-564)
//              ★YSD8002: TCR=0xFC90 ... $FC90-$FC9F (16バイト)★
//
//  ------------------------------------------------------------
//  【V4(v0.4)からの変更点】★V5で追加★
//    (6) YSD8002 タイマーをインスタンス化
//        ★旧(CHAT94): ysd8800_ysd8002_v0_1 → 現: ysd8800_ysd8002_v0_2_poc★
//          (割込受理クリア irq0_ack 対応版へ差替。KY60解消・案0-a')
//    (7) $FC90-$FC9F を YSD8002 へルーティング
//
//        ★★KY44 / 原則67: YSD8002 のオフセットは【4bit】★★
//        ★★YSD8001/YSD8004 は 3bit。【ビット幅が違う】★★
//          YSD8002 は $FC90-$FC9F の【16バイト】を占める。
//          3bit で渡すと $FC90 と $FC98 が区別できず、V3.7 BUG-1
//          （IRQ_STAT/IRQ_MASK 入れ替わり）と全く同じ罠に落ちる。
//          → mmio_addr[3:0] を渡す。
//
//    (8) ★irq_timer_o を新規に外部ポートへ出す★
//        ★YSD8004 は経由しない★
//          YSD8004 は IRQ1(UART/ストレージ)の集約器。
//          タイマーは【IRQ0】で CPU に直接入る別系統である。
//          (emu23 L1591: irq_pending=1 / L1611: irq_pending=2)
//
//    (9) ★cycle_i を新規に外部ポートから受ける★【D8・承認済】
//        ★★【重要】cycle の単位が emu23 と FPGA で異なる★★
//          emu23   : cpu.cycle++ は L1230 の1箇所のみ = 【命令数】(CPI=1固定)
//          FPGA    : membus のクロックカウンタ         = 【クロック数】(実CPI≒18)
//        → 両者は【定義上一致しない】。案A(実機=クロック)を採用。
//        → 判定基準は「完走＋論理結果一致」であり、絶対サイクル一致は求めない。
//        → ★実機で YUI OS/Dhrystone を動かす際の留意事項は
//           v5_design_memo §3.6 を必ず参照すること★
//
//    ★MMUレジスタ部・YSD8004部・YSD8001部・診断出力は v0.4 から一切不変★
//  ------------------------------------------------------------
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

module ysd8800_mmio_stub_v0_8 (
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
    //   ★V6-A変更(v0.7): irq_src_stor も【削除】した。
    //     YSD8003 が本モジュール内部にインスタンス化されたため、
    //     irq_stor_o → irq_src_stor を内部直結する（外部から与えない）。
    //   CPUへの割込出力 ★レベル信号★ (IRQ_STAT != 0)
    //   CPU側で irq_in = (irq1_o ? 3'd2 : 3'd0) として接続する
    output logic        irq1_o,

    // ---- ★V6-A新規: YSD8003 SPI物理層I/F★ (上位結合・CHAT108確定) ----
    //   V6-A ではTB/上位が直接SDモデルへ接続する疑似ポート。
    output logic        spi_cs_n_o,
    output logic        spi_sck_o,
    output logic        spi_mosi_o,
    input  logic        spi_miso_i,
    input  logic [31:0] disk_sectors_i,   // SD容量(セクタ数)

    // ---- ★V4新規: YSD8001 物理層I/F★ (論点C=案C-1・承認済) ----
    //   V4 ではTBが直接叩く疑似ポート。V9 で実シリアライザを接続する。
    input  logic        uart_rx_valid_i,   // 1クロックパルス
    input  logic [7:0]  uart_rx_data_i,
    output logic        uart_tx_valid_o,   // 1クロックパルス(送信開始)
    output logic [7:0]  uart_tx_data_o,

    // ---- ★V5新規: YSD8002 タイマー★ ----
    //   ★YSD8004 は経由しない★
    //     YSD8004 は IRQ1(UART/ストレージ)の集約器。
    //     タイマーは【IRQ0】として CPU に直接入る別系統。
    //     CPU側で irq_in = irq_timer_o ? 3'd1 : (irq1_o ? 3'd2 : 3'd0)
    //     ★タイマー優先★ (emu23 L1591 が L1611 より先に評価される)
    output logic        irq_timer_o,       // ★1クロックパルス★

    //   ★cycle_i【D8・案A承認済】★
    //     membus のクロックカウンタを受ける（＝実機と同一）。
    //     ★emu23 の cpu.cycle は【命令数】(CPI=1固定)、
    //       本ポートは【クロック数】(実CPI≒18)。定義上一致しない。★
    //     判定基準は「完走＋論理結果一致」。絶対サイクル一致は求めない。
    input  logic [31:0] cycle_i,

    // --- 割込アクノリッジ入力 (案0-a' / v5_irq0_ack_design_v0_1) ---
    //   CPU が割込ベクタ読取完了(β点)で 1clk アサート。u_ysd8002 へ中継し、
    //   受理でのみ割込線を下ろす(ACKなし再武装を止める)。fire優先(回答書§5-1)。
    input  logic        irq0_ack,

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

    // ★V5新規: YSD8002 タイマー (emu23_v110.c L596-603 実源照合済)
    //     $FC90 TCR      $FC92 PERIOD_HI  $FC94 PERIOD_LO  $FC96 CYCLE_LO
    //     $FC98 CYCLE_HI $FC9A SW_RUNS    $FC9C SCORE_LO   $FC9E SCORE_HI
    //   (+ 各上位バイト $FC91/$FC93/.../$FC9F) = 【16バイト】
    localparam logic [15:0] YS2_BASE     = 16'hFC90;   // TCR (下位)
    localparam logic [15:0] YS2_LAST     = 16'hFC9F;   // SCORE_HI (上位)

    // ★V6-A新規: YSD8003 ストレージ (emu23 YSD8003 / sd_sample.c)
    //   $FCAE DISK_LO / $FCB0 DISK_HI 等を含む $FCA0-$FCB1(=addr[4:0] 5'h00-5'h11)。
    //   最上位$FCB1 と YS4_BASE=$FCB2 は隣接・無衝突(emu23意図配置)。
    localparam logic [15:0] YS3_BASE     = 16'hFCA0;
    localparam logic [15:0] YS3_LAST     = 16'hFCB1;

    logic access;
    assign access = mmio_rd | mmio_wr;

    // ------------------------------------------------------------
    // アドレスヒット判定 (すべて【論理アドレス】で判定・変換を受けない)
    // ------------------------------------------------------------
    logic hit_ptr, hit_mcr, hit_ys4, hit_ys1, hit_ys2, hit_ys3;
    assign hit_ptr = (mmio_addr >= MMU_PTR_BASE) && (mmio_addr <= MMU_PTR_LAST);
    assign hit_mcr = (mmio_addr == MMU_MCR_ADDR);
    assign hit_ys4 = (mmio_addr >= YS4_BASE) && (mmio_addr <= YS4_LAST);  // ★V3.7★
    assign hit_ys1 = (mmio_addr >= YS1_BASE) && (mmio_addr <= YS1_LAST);  // ★V4★
    assign hit_ys2 = (mmio_addr >= YS2_BASE) && (mmio_addr <= YS2_LAST);  // ★V5★
    assign hit_ys3 = (mmio_addr >= YS3_BASE) && (mmio_addr <= YS3_LAST);  // ★V6-A★

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

    // ★V5新規: YSD8002内オフセット(★★下位4bit★★) ... 原則59/KY44
    //
    //   ★★★【最重要】YSD8001/YSD8004 は3bit。YSD8002 は【4bit】★★★
    //   ★★★ビット幅が違う。ここを3bitにすると必ず壊れる。★★★
    //
    //   YSD8002 は $FC90-$FC9F の【16バイト】を占めるため。
    //   emu23_v110.c L596-603 から機械導出した衝突表:
    //
    //     reg        addr    [3:0]      [2:0](3bitだったら)
    //     TCR        $FC90   4'b0000    3'b000
    //     PERIOD_HI  $FC92   4'b0010    3'b010
    //     PERIOD_LO  $FC94   4'b0100    3'b100
    //     CYCLE_LO   $FC96   4'b0110    3'b110
    //     CYCLE_HI   $FC98   4'b1000    3'b000  ← ★TCR と衝突★
    //     SW_RUNS    $FC9A   4'b1010    3'b010  ← ★PERIOD_HI と衝突★
    //     SCORE_LO   $FC9C   4'b1100    3'b100  ← ★PERIOD_LO と衝突★
    //     SCORE_HI   $FC9E   4'b1110    3'b110  ← ★CYCLE_LO と衝突★
    //
    //   → 3bit では TCR 書込が CYCLE_HI 読出と同一デコードになり、
    //     V3.7 BUG-1（IRQ_STAT/IRQ_MASK 入れ替わり）の完全な再演になる。
    //   → mmio_addr[3:0] を渡す。
    logic [3:0] ys2_off;
    assign ys2_off = mmio_addr[3:0];

    // ★V6-A: YSD8003内オフセット(★下位5bit★ $FCA0-$FCBF) ... 原則59: assignで外出し
    logic [4:0] ys3_off;
    assign ys3_off = mmio_addr[4:0];

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
    // ★V5新規: YSD8002 タイマー (案B: 独立モジュールを接続)
    //   本モジュールはルーティングに徹する。機能実体はYSD8002側。
    //
    //   ★★irq_timer_o は YSD8004 を経由せず外部へ直接出す★★
    //     YSD8004 は IRQ1 の集約器であり、タイマーは IRQ0 の別系統。
    //     (emu23 L1591 timer→irq_pending=1 / L1611 irq_stat→irq_pending=2)
    // ------------------------------------------------------------
    logic [7:0] ys2_rdata;

    ysd8800_ysd8002_v0_3 u_ysd8002 (    // [v0.6] EN是正: v0_2→v0_3 参照追従
        .clk         (clk),
        .rst_n       (rst_n),
        // MMIOルーティング: 本デバイスがヒットした時のみ sel を上げる
        .sel_i       (hit_ys2 & access),
        .addr_i      (ys2_off),          // ★★4bit(KY44)★★ YSD8001は3bit
        .we_i        (mmio_wr),
        .wdata_i     (mmio_wdata),
        .rdata_o     (ys2_rdata),
        // ★IRQ0: CPU へ直接（YSD8004 経由しない）★
        .irq_timer_o (irq_timer_o),
        // ★cycle_i: membus のクロックカウンタ【D8・案A】★
        .cycle_i     (cycle_i),
        // ★irq0_ack: 受理による割込線クリア(案0-a')★
        .irq0_ack    (irq0_ack)
    );

    // ------------------------------------------------------------
    // ★V6-A新規: YSD8003 ストレージ (CHAT108確定・(B-2)パルス方式)
    //   本モジュールはルーティングに徹する。機能実体はYSD8003側。
    //   irq_stor_o(完了1clkパルス) → YSD8004.irq_src_stor へ内部直結。
    //   irq_stor_ack は未使用(YSD8004 W1Cが保持/クリア)。
    // ------------------------------------------------------------
    logic [7:0] ys3_rdata;
    logic       ys3_ready;
    logic       irq_stor_int;   // YSD8003 → YSD8004 内部直結線

    ysd8800_ysd8003_v0_1 u_ysd8003 (
        .clk          (clk),
        .rst_n        (rst_n),
        // MMIOルーティング: 本デバイスがヒットした時のみ sel を上げる
        .sel_i        (hit_ys3 & access),
        .addr_i       (ys3_off),          // ★5bit★ ($FCA0-$FCBF)
        .we_i         (mmio_wr),
        .wdata_i      (mmio_wdata),
        .rdata_o      (ys3_rdata),
        // 案(D) wait-state
        .ready_o      (ys3_ready),
        // 割込: 完了1clkパルス → YSD8004へ内部直結
        .irq_stor_o   (irq_stor_int),
        .irq_stor_ack (1'b0),             // v0.3で未使用（0固定）
        // SPI物理線を外部ポートへ透過
        .spi_cs_n     (spi_cs_n_o),
        .spi_sck      (spi_sck_o),
        .spi_mosi     (spi_mosi_o),
        .spi_miso     (spi_miso_i),
        // SD容量
        .disk_sectors_i (disk_sectors_i)
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
        .irq_src_stor    (irq_stor_int),   // ★V6-A: YSD8003から内部直結(1clkパルス)★
        .irq_src_uart_tx (irq_uart_tx),    // ★V4接続★ レベル(TDRE)
        // CPUへの割込出力(レベル)
        .irq1_o          (irq1_o)
    );

    // ------------------------------------------------------------
    // リードデータ多重化 (組合せ)
    //   MMUレジスタ / YSD8004 / YSD8001 以外は従来スタブ挙動 = 固定0x00
    //
    //   ★各hitの範囲は互いに重ならない（排他）★
    //     YS1: $FC80-$FC87 / ★YS2: $FC90-$FC9F★ / YS4: $FCB2-$FCB5
    //     PTR: $FF00-$FF0F / MCR: $FF10
    //   したがって優先順位に意味はないが、明示的にelse ifで並べる。
    // ------------------------------------------------------------
    always_comb begin
        if (hit_ptr)      mmio_rdata = ptr_r[ptr_idx];
        else if (hit_mcr) mmio_rdata = mcr_r;
        else if (hit_ys4) mmio_rdata = ys4_rdata;      // V3.7
        else if (hit_ys1) mmio_rdata = ys1_rdata;      // V4
        else if (hit_ys2) mmio_rdata = ys2_rdata;      // ★V5新規★
        else if (hit_ys3) mmio_rdata = ys3_rdata;      // ★V6-A新規★
        else              mmio_rdata = 8'hFF;          // ★v0.8: 未接続=プルアップ★
    end

    // ready合流(組合せ)。
    //   ★V6-A変更(v0.7): hit_ys3(ストレージ)時のみ YSD8003.ready_o を反映。
    //     SPI読出中はys3_ready=0でCPUをストールさせる(案D wait-state)。
    //     他ペリフェラルは組合せリード/1クロックライトのため即応答(不変)。
    //     状態変更一元化(kaizen準拠)。永久ストール回避はYSD8003側で
    //     ERROR/READY確定時にready_o=1復帰する論理を実装済(HANDOVER§2.2)。
    assign mmio_ready = hit_ys3 ? (access & ys3_ready) : access;

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
