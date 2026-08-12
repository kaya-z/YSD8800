//=====================================================================
// ysd8800_ysd8004_v0_1.sv
//
//   YSD8004 割り込みコントローラ（Interrupt Controller）
//
//   Project : YSD8800 / YUI OS  --- Step 8 FPGA / V3.7
//   Version : v0.1
//   Date    : 2026-07-12
//   Design  : v3_7_design_memo_v0_2.md（承認版・Mレベル指摘なし）
//   Golden  : emu23 v1.09 (emu23_v109.c)
//
//---------------------------------------------------------------------
// 【役割】
//   複数デバイス（UART_RX / STOR / UART_TX）の割込要求を集約し、
//   CPU の IRQ1（irq_in = 3'd2）1本へ束ねる。
//   MC6809 + PIA/ACIA のワイヤードOR構成と同型。ハンドラは IRQ_STAT を
//   読んで発生源を判別する。
//
// 【レジスタ】（emu23 v1.09 実照合）
//   $FCB2  IRQ_STAT  R / Write-to-Clear   reset = 0x00   (L294,629,761)
//   $FCB3  (上位)    R  常時 0x00 を返す                 ★KY-B★
//   $FCB4  IRQ_MASK  R/W  1=マスク 0=許可  reset = 0x04   (L295,630,762,307)
//   $FCB5  (上位)    R  常時 0x00 を返す                 ★KY-B★
//
//   ★★ IRQ_MASK のリセット値は 0x04 である（0x00 ではない）★★
//      bit2 = UART_TX がマスクされた状態で起動する。
//      根拠: emu23 L307 / ysd8001_uart_design_v1_2 §3.6
//      ここを 0x00 で実装すると V4 で TX 割込が想定外発火し、
//      emu23 との等価性が破れる。 → KY-A（本フェーズ最大の危険箇所）
//
// 【IRQ_STAT ビット定義】（emu23 L298-300）
//   bit0 = UART_RX (YSD8001 受信)
//   bit1 = STOR    (YSD8003 完了/エラー)
//   bit2 = UART_TX (YSD8001 送信 TDRE)
//   bit3-7 = 予約（将来の集約拡張枠）
//
// 【設計判断】（設計メモ v0.2 §4.1/§4.2/§4.3/§3.4）
//   ・レジスタ幅は 8bit（案A承認）。バスがバイト粒度のため。
//     使用ビットは bit0-2 のみで、16bit完全実装は実利が薄い。
//     ただし上位バイト($FCB3/$FCB5)は必ずデコードし 0x00 を返す。
//   ・独立モジュール（案B承認）。MMIOスタブはルーティングに徹する。
//   ・割込入力は「1クロックパルス」規約。保持は本モジュールの責務。
//     （IRQ_STAT |= allowed は冪等なので、誤ってレベルで来ても破綻しない）
//   ・★irq1_o は「IRQ_STAT != 0」のレベル信号★（パルスではない）→ KY-D
//     これにより emu23 の「IRQ_STAT再評価機構」(L1576-1578) が
//     RTL側では自動的に成立する（設計メモ §4.4b【第2段】）。
//     パルスにすると V5 で割込を取りこぼすため、絶対にレベルとすること。
//
// 【スコープ外】
//   pending保護ロジック（emu23 L320-327）は CPU側 irq_pending の
//   更新条件であり、本モジュールの責務ではない。V5 へ申し送り（§4.4b）。
//=====================================================================

`timescale 1ns / 1ps

module ysd8800_ysd8004_v0_1 (
    input  logic        clk,
    input  logic        rst_n,

    //--- MMIO バスI/F（バイト粒度。MMIOスタブからルーティングされる）---
    input  logic        sel_i,        // 本デバイスが選択された
    input  logic [2:0]  addr_i,       // ★アドレス下位3bit（mmio_addr[2:0]）★
                                      //   $FCB2 -> 3'b010 = 2  IRQ_STAT (下位)
                                      //   $FCB3 -> 3'b011 = 3  IRQ_STAT (上位・常時0)
                                      //   $FCB4 -> 3'b100 = 4  IRQ_MASK (下位)
                                      //   $FCB5 -> 3'b101 = 5  IRQ_MASK (上位・常時0)
                                      //
                                      // ★【V3.7 S5 BUG-1 修正】★
                                      //   当初 addr_i を2bit(mmio_addr[1:0])としたが、
                                      //   $FCB2/$FCB3 と $FCB4/$FCB5 は mmio_addr[2] で
                                      //   しか区別できず、STAT と MASK が入れ替わっていた。
                                      //     $FCB2[1:0]=2'b10  $FCB4[1:0]=2'b00
                                      //   S3単体TBはaddr_iを直接与えていたため露見せず、
                                      //   S5統合で初めて発覚（無限割込ループ）。
                                      //   → 3bit化し、下位3bitで一意にデコードする。
    input  logic        we_i,         // 1=write / 0=read
    input  logic [7:0]  wdata_i,
    output logic [7:0]  rdata_o,

    //--- 割込要求入力（各デバイスから。1クロックパルス規約）---
    input  logic        irq_src_uart_rx,   // → IRQ_STAT bit0  (V4で接続)
    input  logic        irq_src_stor,      // → IRQ_STAT bit1  (V6で接続)
    input  logic        irq_src_uart_tx,   // → IRQ_STAT bit2  (V4で接続)

    //--- CPU への割込出力 ---
    output logic        irq1_o             // ★レベル信号★ (IRQ_STAT != 0)
);

    //-----------------------------------------------------------------
    // アドレスデコード（★実アドレス $FCB2..$FCB5 の下位3bit★）
    //   $FCB2 = ...1011_0010 → [2:0] = 3'b010
    //   $FCB3 = ...1011_0011 → [2:0] = 3'b011
    //   $FCB4 = ...1011_0100 → [2:0] = 3'b100
    //   $FCB5 = ...1011_0101 → [2:0] = 3'b101
    //-----------------------------------------------------------------
    localparam logic [2:0] A_STAT_LO = 3'b010;   // $FCB2
    localparam logic [2:0] A_STAT_HI = 3'b011;   // $FCB3
    localparam logic [2:0] A_MASK_LO = 3'b100;   // $FCB4
    localparam logic [2:0] A_MASK_HI = 3'b101;   // $FCB5

    //-----------------------------------------------------------------
    // レジスタ実体
    //   ★IRQ_MASK のリセット値は 8'h04（KY-A・emu23 L307）★
    //-----------------------------------------------------------------
    logic [7:0] irq_stat_r;
    logic [7:0] irq_mask_r;

    //-----------------------------------------------------------------
    // 割込源の束ね（emu23 L314-317: allowed = bits & ~irq_mask）
    //-----------------------------------------------------------------
    logic [7:0] src_bits;
    logic [7:0] allowed;

    assign src_bits = { 5'b0,
                        irq_src_uart_tx,   // bit2
                        irq_src_stor,      // bit1
                        irq_src_uart_rx }; // bit0

    assign allowed  = src_bits & ~irq_mask_r;

    //-----------------------------------------------------------------
    // レジスタ更新
    //
    //   優先順位: MMIO書込 > 割込セット
    //     同一サイクルで「Write-to-Clear」と「割込セット」が競合した場合、
    //     クリアを先に適用してから新規要求をORする。
    //     （取りこぼし防止。emu23 は逐次実行のため競合は生じないが、
    //       RTL では同時到来しうる。イベントを落とさない側に倒す）
    //-----------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            irq_stat_r <= 8'h00;
            irq_mask_r <= 8'h04;   // ★★KY-A: 0x00 ではない★★
        end
        else begin
            //--- IRQ_MASK 書込 ---
            if (sel_i && we_i && (addr_i == A_MASK_LO))
                irq_mask_r <= wdata_i;
            // $FCB5 (MASK上位) への書込は無視（上位8bitは非実装）

            //--- IRQ_STAT: Write-to-Clear と 割込セット ---
            if (sel_i && we_i && (addr_i == A_STAT_LO))
                // クリア後に新規要求をOR（同時到来を落とさない）
                irq_stat_r <= (irq_stat_r & ~wdata_i) | allowed;
            else
                irq_stat_r <= irq_stat_r | allowed;
            // $FCB3 (STAT上位) への書込は無視（上位8bitは非実装）
        end
    end

    //-----------------------------------------------------------------
    // 読出（★KY-B: 上位バイトは必ず 0x00 を返す★）
    //   ここをデコードし忘れると、CPU が LDW（16bit=2バイトアクセス）で
    //   $FCB2 を読んだ際に上位バイトが不定となり emu23 と食い違う。
    //-----------------------------------------------------------------
    always_comb begin
        unique case (addr_i)
            A_STAT_LO: rdata_o = irq_stat_r;
            A_STAT_HI: rdata_o = 8'h00;      // ★上位バイト★
            A_MASK_LO: rdata_o = irq_mask_r;
            A_MASK_HI: rdata_o = 8'h00;      // ★上位バイト★
            default:   rdata_o = 8'h00;
        endcase
    end

    //-----------------------------------------------------------------
    // CPU への割込出力
    //   ★レベル信号★（IRQ_STAT != 0 の間アサートし続ける）
    //   emu23 L318: if (irq_stat != 0) → IRQ1 pending
    //   ハンドラが IRQ_STAT をクリアするまで下がらない＝取りこぼさない。
    //   （設計メモ §4.4b【第2段】: これにより emu23 の再評価機構が
    //     RTL側で自動成立する。パルスにすると V5 で破綻する）
    //-----------------------------------------------------------------
    assign irq1_o = (irq_stat_r != 8'h00);

endmodule
