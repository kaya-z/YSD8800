// ============================================================
//  tb_ysd8002_v0_1.sv   v0.1  (2026-07-14)   ★KY38: _poc 実験版★
//  YSD8800 FPGA V5 : YSD8002 タイマー 単体TB
//
//  検証根拠: v5_design_memo_v0_3.md §3.5 / §3.5.1【D4/D7】
//  黄金リファレンス: emu23_v110.c (L257-264 tick / L269-273 rearm / L694-704 TCRwr)
//
//  ------------------------------------------------------------
//  ★KY54: ネガティブラン先行★
//  ------------------------------------------------------------
//   本TBは `+define+NEGATIVE_RUN` を付けてビルドすると、
//   ★意図的に誤った期待値★で判定する(＝正しいRTLに対して FAIL を出す)。
//   これにより「TBが本当にFAILを検出できるか」を先に実証する。
//
//   ★TBが常にPASSするだけの「置物」でないことを証明してから本番判定に入る。★
//   (正しいRTLをPASSさせるTBは簡単に書けるが、
//    壊れたRTLをFAILさせられないTBは【無価値】である)
//
//  ------------------------------------------------------------
//  検証項目 (T1-T12)
//  ------------------------------------------------------------
//   T1  リセット初期値      : TCR=$03 / PERIOD=40000 / armed=1
//   T2  ★初回発火★        : cycle>=40000 で irq_timer_o が【1クロックパルス】
//   T3  ★自己武装解除★    : 発火後、ACKなしでは【二度と発火しない】
//                             ★V5の中核。旧IRET方式との決別点★
//   T4  ★TCR-ACK 再武装★  : TCR<=$23 で cnt<=cycle+period, armed<=1
//   T5  ★周期発火★        : ACK後、さらに period 経過で再発火
//   T6  ★$20単独はACKを殺す★: TCR<=$20 だと TIMER_EN/IRQ_EN が0に落ち
//                             再武装しても fire_en=0 で発火しない (原則74)
//   T7  TCR read           : bit0/1/4 のみ返る (bit2/3/5 は常に0)
//   T8  ★D7: EN は OR★    : TCR=$01 でも TCR=$02 でも発火する (ANDではない)
//   T9  TCR=$00 で停止      : fire_en=0 → 発火しない
//   T10 PERIOD 書換         : 32bit 4バイト書込 → ACK後の周期に反映
//   T11 SW_START/STOP       : SCORE = stop_cycle - start_cycle / SW_BUSY
//   T12 CYCLE_HI ラッチ      : CYCLE_LO読出時に上位がラッチされる
// ============================================================
`timescale 1ns/1ps

module tb_ysd8002_v0_1;

    logic        clk, rst_n;
    logic        sel, we;
    logic [3:0]  addr;
    logic [7:0]  wdata, rdata;
    logic        irq_timer;
    logic [31:0] cyc;

    integer errors = 0;
    integer fire_count = 0;

    ysd8800_ysd8002_v0_1 dut (
        .clk(clk), .rst_n(rst_n),
        .sel_i(sel), .addr_i(addr), .we_i(we),
        .wdata_i(wdata), .rdata_o(rdata),
        .irq_timer_o(irq_timer),
        .cycle_i(cyc)
    );

    // クロック
    initial clk = 0;
    always #5 clk = ~clk;

    // ★cycle_i は CPU の経過サイクル。TB では clk と同期して進める★
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) cyc <= 32'd0;
        else        cyc <= cyc + 32'd1;
    end

    // 発火回数カウント (パルス検出)
    always_ff @(posedge clk) begin
        if (rst_n && irq_timer) fire_count <= fire_count + 1;
    end

    // ------------------------------------------------------------
    // バスタスク
    // ------------------------------------------------------------
    task bus_write(input [3:0] a, input [7:0] d);
        begin
            @(negedge clk);
            sel = 1; we = 1; addr = a; wdata = d;
            @(negedge clk);
            sel = 0; we = 0; wdata = 8'h00;
        end
    endtask

    task bus_read(input [3:0] a, output [7:0] d);
        begin
            @(negedge clk);
            sel = 1; we = 0; addr = a;
            #1;              // 組合せ確定待ち
            d = rdata;
            @(negedge clk);
            sel = 0;
        end
    endtask

    task chk(input string name, input [31:0] got, input [31:0] exp);
        begin
            if (got !== exp) begin
                $display("FAIL: %-28s got=%0d exp=%0d", name, got, exp);
                errors = errors + 1;
            end else begin
                $display("PASS: %-28s = %0d", name, got);
            end
        end
    endtask

    // ★KY54: ネガティブラン用の期待値歪め★
    //   NEGATIVE_RUN 定義時、T2の期待値をわざと誤らせる。
    //   正しいRTLに対して FAIL が出れば「TBは判定能力を持つ」と実証できる。
`ifdef NEGATIVE_RUN
    localparam int T2_EXP_FIRE = 99;   // ★誤った期待値(本来は1)★
`else
    localparam int T2_EXP_FIRE = 1;
`endif

    logic [7:0] rd;

    initial begin
        sel = 0; we = 0; addr = 4'h0; wdata = 8'h00;
        rst_n = 0;
        repeat (3) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        $display("=== YSD8002 TB start ===");
`ifdef NEGATIVE_RUN
        $display("*** KY54 NEGATIVE RUN: T2 expects WRONG value(99) on purpose ***");
`endif

        // ---------- T1: リセット初期値 ----------
        bus_read(4'h0, rd);
        chk("T1 TCR reset(=0x03)", rd, 8'h03);
        bus_read(4'h4, rd);
        chk("T1 PERIOD_LO b0(40000&FF)", rd, 32'd40000 & 8'hFF);   // 40000=0x9C40 -> 0x40
        bus_read(4'h5, rd);
        chk("T1 PERIOD_LO b1", rd, (32'd40000 >> 8) & 8'hFF);      // -> 0x9C

        // ---------- T2: 初回発火 (cycle>=40000) ----------
        //   リセット後 cnt_r=40000。cyc が 40000 に達したら発火する。
        wait (cyc >= 32'd40005);
        @(posedge clk);
        chk("T2 first fire count", fire_count, T2_EXP_FIRE);

        // ---------- T3: ★自己武装解除★ ACKなしでは二度と発火しない ----------
        //   ★V5の中核。ここが落ちたら設計が破綻している。★
        repeat (200) @(posedge clk);
        chk("T3 no refire w/o ACK", fire_count, 1);

        // ---------- T4/T5: ★TCR-ACK 再武装 → 周期発火★ ----------
        bus_write(4'h0, 8'h23);          // ★$23 = TIMER_EN|IRQ_EN|IRQ_ACK★
        // ACK 直後は armed=1, cnt=cycle+40000。まだ発火しない。
        repeat (50) @(posedge clk);
        chk("T4 no fire right after ACK", fire_count, 1);
        // period 経過 → 2回目の発火
        wait (fire_count >= 2);
        chk("T5 periodic fire (2nd)", fire_count, 2);

        // ---------- T6: ★$20単独は ACK が ACK 自身を殺す★(原則74) ----------
        //   TCR<=$20 → bit5(ACK)で再武装するが、bit0/1 が 0 に落ちるため
        //   fire_en=0 となり【発火しない】。
        bus_write(4'h0, 8'h20);
        bus_read(4'h0, rd);
        chk("T6 TCR after $20 (EN dead)", rd, 8'h00);   // TIMER_EN/IRQ_EN が 0
        repeat (300) @(posedge clk);
        chk("T6 no fire (ACK killed itself)", fire_count, 2);

        // ---------- T7: TCR read は bit0/1/4 のみ ----------
        bus_write(4'h0, 8'h2F);          // bit0,1,2,3,5 を立てて書く
        bus_read(4'h0, rd);
        //   期待: bit0=1,bit1=1 が残る。bit2/3(ストローブ)は返らない。
        //   bit4=SW_BUSY は bit2(SW_START)を書いたので 1 になる。
        chk("T7 TCR read masks strobes", rd, 8'h13);   // 0001_0011 = EN|EN|SW_BUSY

        // ---------- T9: TCR=$00 で停止 ----------
        bus_write(4'h0, 8'h08);          // SW_STOP を先に(BUSY落とす)
        bus_write(4'h0, 8'h00);          // EN 全部落とす
        bus_read(4'h0, rd);
        chk("T9 TCR=0 (all EN off)", rd, 8'h00);

        // ---------- T8: ★D7: EN は OR★ ----------
        //   TCR=$21 (TIMER_EN only + ACK) → ★OR なので発火する★
        //   もし AND だったら irq_en=0 で発火しない。
        fire_count = 0;
        bus_write(4'h0, 8'h21);          // TIMER_EN=1, IRQ_EN=0, ACK
        wait (cyc >= 32'd0);             // 進行
        repeat (40100) @(posedge clk);
        chk("T8 OR: fire w/ TIMER_EN only", (fire_count >= 1) ? 1 : 0, 1);

        //   TCR=$22 (IRQ_EN only + ACK) → ★OR なので発火する★
        fire_count = 0;
        bus_write(4'h0, 8'h22);          // TIMER_EN=0, IRQ_EN=1, ACK
        repeat (40100) @(posedge clk);
        chk("T8 OR: fire w/ IRQ_EN only", (fire_count >= 1) ? 1 : 0, 1);

        // ---------- T10: PERIOD 書換 ----------
        bus_write(4'h4, 8'hE8);          // PERIOD_LO b0 = 0xE8
        bus_write(4'h5, 8'h03);          // PERIOD_LO b1 = 0x03  → 0x03E8 = 1000
        bus_write(4'h2, 8'h00);
        bus_write(4'h3, 8'h00);          // 上位 = 0
        bus_read(4'h4, rd);
        chk("T10 PERIOD_LO b0 readback", rd, 8'hE8);
        bus_read(4'h5, rd);
        chk("T10 PERIOD_LO b1 readback", rd, 8'h03);
        //   ACK して period=1000 で発火するか
        fire_count = 0;
        bus_write(4'h0, 8'h23);
        repeat (1100) @(posedge clk);
        chk("T10 fire w/ period=1000", (fire_count >= 1) ? 1 : 0, 1);

        // ---------- T11: SW_START / SW_STOP / SCORE ----------
        bus_write(4'h0, 8'h07);          // TIMER_EN|IRQ_EN|SW_START
        bus_read(4'h0, rd);
        chk("T11 SW_BUSY=1 after START", (rd & 8'h10) ? 1 : 0, 1);
        repeat (100) @(posedge clk);
        bus_write(4'h0, 8'h0B);          // TIMER_EN|IRQ_EN|SW_STOP
        bus_read(4'h0, rd);
        chk("T11 SW_BUSY=0 after STOP", (rd & 8'h10) ? 1 : 0, 0);
        //   SCORE は 0 より大きいはず(経過サイクル)
        bus_read(4'hC, rd);
        chk("T11 SCORE_LO nonzero", (rd != 8'h00) ? 1 : 0, 1);

        // ---------- T12: CYCLE_HI ラッチ ----------
        bus_read(4'h6, rd);              // CYCLE_LO 読出 → HI がラッチされる
        bus_read(4'h8, rd);              // CYCLE_HI 下位バイト
        //   cyc は 40000 を超えているので上位16bit は 0 でない可能性がある
        //   (0x9C40 * 数回 → 上位が 1 以上)。存在確認のみ。
        $display("INFO: CYCLE_HI latch b0 = %02x (cyc=%0d)", rd, cyc);

        // ---------- 判定 ----------
        $display("----------------------------------------");
        if (errors == 0) $display("YSD8002_TB: ALL PASS");
        else             $display("YSD8002_TB: %0d FAIL", errors);
        $finish;
    end

    // タイムアウト保護
    initial begin
        #20000000;   // 20ms
        $display("FAIL: TB TIMEOUT");
        $display("YSD8002_TB: TIMEOUT FAIL");
        $finish;
    end

endmodule
