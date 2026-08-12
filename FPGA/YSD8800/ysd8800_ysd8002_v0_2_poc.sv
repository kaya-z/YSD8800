// ============================================================
//  ysd8800_ysd8002_v0_2_poc.sv   v0.2_poc  (2026-07-14)
//  ★実験版★ (KY38: 本番昇格は統合TB PASS 後)
//  ベース: ysd8800_ysd8002_v0_1.sv v0.1 (2026-07-14) 単体TB 19 PASS 済
//
//  ★★v0.2 の変更点（1点のみ）★★
//    irq_timer_o : 【1クロックパルス】→【レベル】へ変更
//    ・irq_req_r を新設。fire で set / TCR-ACK(bit5) で clear。
//
//  【変更理由】(D12 = 案B-1a・ユーザー承認 2026-07-14)
//    CPU v0.5.8 は irq_in を S_IRQCHK 状態でしかサンプルしない
//    (実源 L153-157)。S_IRQCHK は命令境界にしか来ない(実CPI≒18)ため、
//    1クロックパルスは★ほぼ確実に取りこぼされる★。
//
//  【却下した代案】パルスストレッチ(N クロック保持)
//    PSRAM ウェイト・キャッシュ・PLL比変更で1命令長が変動すると
//    静かに破綻する【タイミング依存】。間欠故障となり最悪。
//    → ★ユーザー指摘により却下★
//
//  【採用】レベル＋ハンドシェイク = MC6840 PTM の作法。★クロック非依存★
//
//  【既存ソフトへの影響: ゼロ】(実源確認済 2026-07-14)
//    kernel_v12_8.asm        L458-459: ACK($0023) → L568 IRET  ★ACK が先★
//    startup_harness23_v16.asm _timer_handler: ACK → 復元 → IRET ★ACK が先★
//    → 両者とも B-1a の契約を既に充足。★ソース改修不要★
//
//  【契約 / D13-A】IRQ0_HANDLER は必ず TCR に $0023 を書くこと。
//    書かない場合 irq_req_r が落ちず、IRET 後に即再受理されハングする。
//    これはバグではなく【ACK 義務】の機械的強制である。
//    (emu23 は「1回で自己沈黙」= A=1。RTL は「ハング」。★意味論が異なる★)
//
//  YSD8800 FPGA V5 : YSD8002 タイマー (MMIO デバイス)
//
//  設計根拠: v5_design_memo_v0_3.md §3.5 / §3.5.1【D4/D7 承認】
//  黄金リファレンス: emu23_v110.c
//    L257-264 YSD8002_tick()   : 発火＋自己武装解除
//    L269-273 YSD8002_rearm()  : TCR bit5(IRQ_ACK) 書込で再武装
//    L694-704 TCR write        : write マスク 0x37 / IRQ_ACK 自動クリア
//    L616-620 TCR read         : ★bit0/1/4 しか返さない★(bit2/3/5 は常に0)
//
//  ------------------------------------------------------------
//  ★V5 の中核: 再武装契機は「IRET」ではなく「ハンドラの TCR-ACK 書込」★
//  ------------------------------------------------------------
//   旧(emu23 v1.09): IRET 命令をフックして再武装 → ★FPGA 実装不能★
//     CPU から iret_pulse_o を引く必要があるが、MC6809 は RTI を外部に
//     ブロードキャストしない。CPU 内部事情をバスに晒すのは設計原則違反。
//   新(emu23 v1.10 / 本RTL): ハンドラが TCR に $0023 を書いて ACK＋再武装。
//     MC6840 PTM / MC6850 ACIA と同一の、実機として正統な形。
//     ★CPU からの特殊信号は一切不要。通常の MMIO デバイスとして実装できる。★
//
//  ------------------------------------------------------------
//  ★TCR は「状態ビット」と「イベントストローブ」の混在レジスタである★
//  ------------------------------------------------------------
//   状態ビット (R/W・値を保持):   bit0 TIMER_EN / bit1 IRQ_EN
//   ストローブ (W・自動クリア):   bit2 SW_START / bit3 SW_STOP / bit5 IRQ_ACK
//   合成読出   (R):               bit4 SW_BUSY
//
//   ★実源根拠★ emu23 L616-619 の TCR read は bit0/1/4 しか返さない。
//     「読んで返らない」＝「状態を持たない」＝ストローブ、である。
//
//   ★原則74★ レジスタ書込は【そのレジスタの全ビットを決める行為】である。
//     ハンドラが ACK を書くときは $0020(bit5のみ)ではなく
//     ★$0023 (TIMER_EN|IRQ_EN|IRQ_ACK)★ を書かねばならない。
//     $0020 を書くと TIMER_EN/IRQ_EN が 0 に落ち、★ACK が ACK 自身を殺す★。
//     本RTL は「書込値が全ビットを決める」素直な実装であり、これは
//     emu23 と同じ挙動である(emu23 のバグではない)。
//
//  ------------------------------------------------------------
//  ★★【D7・2026-07-14】発火 EN 条件は AND ではなく OR である★★
//  ------------------------------------------------------------
//   emu23 L696 実源:  ysd8002.irq_enabled = (ysd8002.tcr & 0x03) ? 1 : 0;
//                                            ^^^^^^^^^^^^^^^^^^^^^^ ★OR★
//   → bit0(TIMER_EN) か bit1(IRQ_EN) の【どちらか】が立てば発火する。
//   → 設計メモ v0.2 §3.5 の擬似コード「TIMER_EN && IRQ_EN」(AND)は【誤り】。
//      v0.3 §3.5.1 で訂正済み。★RTL は黄金リファレンス(emu23)に合わせる★(原則76)。
//
//   ★★設計負債(申し送り・失念厳禁)★★
//     OR であるため IRQ_EN(bit1) は名前どおり機能していない。
//     TCR=$01 と書いても(IRQ_EN=0 のつもりでも)★割込は出続ける★。
//     正しくは AND であるべき(MC6840 PTM の作法)。
//     → ユーザー指示(2026-07-14)により★近日中に抜本改修★することが決定済み。
//        V5 完了(S10)後に独立工程として実施すること。
//        詳細・改修範囲: v5_design_memo_v0_3.md §3.5.2 / kaizen.txt 原則77
//        ★Dhrystone 黄金値 826/48405 が変わりうる★
//
//  ------------------------------------------------------------
//  バス I/F 規約 (YSD8001 v0_1 と同型)
//  ------------------------------------------------------------
//   ★MMIO はバイト単位アクセス★。16bit レジスタは 2 バイトに分かれる。
//   YSD8002 レジスタは $FC90-$FC9F の 16 バイト → ★アドレス下位 4bit★
//   (YSD8001 は $FC80-$FC87 の 8 バイトで下位 3bit。★ここが違う★)
//
//   | addr_i | レジスタ         | R/W | 備考                              |
//   |--------|------------------|-----|-----------------------------------|
//   |  4'h0  | TCR      (下位)  | R/W | ★本デバイスの中核★               |
//   |  4'h1  | TCR      (上位)  | R   | 常時 0x00 (emu23 は 16bit 値の上位)|
//   |  4'h2  | PERIOD_HI(下位)  | R/W | period[23:16]                     |
//   |  4'h3  | PERIOD_HI(上位)  | R/W | period[31:24]                     |
//   |  4'h4  | PERIOD_LO(下位)  | R/W | period[7:0]                       |
//   |  4'h5  | PERIOD_LO(上位)  | R/W | period[15:8]                      |
//   |  4'h6  | CYCLE_LO (下位)  | R   | cycle[7:0]  ★読出時 HI をラッチ★ |
//   |  4'h7  | CYCLE_LO (上位)  | R   | cycle[15:8]                       |
//   |  4'h8  | CYCLE_HI (下位)  | R   | cycle_hi_latch[7:0]               |
//   |  4'h9  | CYCLE_HI (上位)  | R   | cycle_hi_latch[15:8]              |
//   |  4'hA  | SW_RUNS  (下位)  | R/W | Dhrystone Number_Of_Runs          |
//   |  4'hB  | SW_RUNS  (上位)  | R/W |                                   |
//   |  4'hC  | SCORE_LO (下位)  | R   | ★読出時 SCORE_HI をラッチ★       |
//   |  4'hD  | SCORE_LO (上位)  | R   |                                   |
//   |  4'hE  | SCORE_HI (下位)  | R   | score_hi_latch[7:0]               |
//   |  4'hF  | SCORE_HI (上位)  | R   | score_hi_latch[15:8]              |
//
//   ★16bit レジスタへの書込は下位バイト/上位バイトが別クロックで来る★
//     → 各バイトを独立に受ける(ワード結合のための一時レジスタは持たない)。
//        emu23 は 16bit 一括だが、CPU の STW は membus が 2 バイトに分解して
//        連続で発行するため、最終的なレジスタ値は一致する。
//
//  ------------------------------------------------------------
//  割込出力
//  ------------------------------------------------------------
//   irq_timer_o : ★1クロックパルス★ (レベルではない)
//     根拠: emu23 L260 で next_irq_cycle=UINT64_MAX にして自己武装解除する。
//           = 「時刻が来た」というイベント信号であり、状態信号ではない。
//     対比: YSD8001 の TX(TDRE) は「バッファが空である限り要求し続ける」レベル。
//           ★同じ割込源でも性質が異なる。源ごとにパルス/レベルを使い分ける。★
//
//   上位(membus)での CPU 接続:
//     irq_in = irq_timer_o ? 3'd1 : (irq1_o ? 3'd2 : 3'd0)
//     ★タイマー(IRQ0)優先★ 根拠: emu23 L1591(タイマー) が L1611(IRQ1) より先。
//     CPU v0.5.8 の pending 第1段保護と噛み合って、タイマーが IRQ1 に
//     蹴落とされないことを保証する。
// ============================================================
`timescale 1ns/1ps

module ysd8800_ysd8002_v0_2_poc (
    input  logic        clk,
    input  logic        rst_n,

    // --- MMIO バス I/F ($FC90-$FC9F) ---
    input  logic        sel_i,        // 本デバイスが選択された (hit_ys2 & access)
    input  logic [3:0]  addr_i,       // ★アドレス下位4bit（mmio_addr[3:0]）★
    input  logic        we_i,         // 1=write / 0=read
    input  logic [7:0]  wdata_i,
    output logic [7:0]  rdata_o,

    // --- 割込出力 ---
    output logic        irq_timer_o,  // ★1クロックパルス★ → CPU irq_in=3'd1 (IRQ0)

    // --- サイクルカウンタ (CPU クロックの経過サイクル数) ---
    //   emu23 の cpu.cycle に相当。上位(membus/TB)から供給する。
    //   ★emu23 は CPI=1 固定のため FPGA と cycle 一致は定義上不可★
    //   (kaizen: リグレッションゲートは「完走＋論理結果一致」のみ)
    input  logic [31:0] cycle_i,

    // --- 割込アクノリッジ入力 (案0-a' / v5_irq0_ack_design_v0_1) ---
    //   CPU が IRQ0(timer) 受理を確定した瞬間に 1クロック立つパルス。
    //   emu23 の「発火チケットを受理で消費(irq_pending=-1)」を写像する。
    //   ★これで irq_req_r を下ろす(受理=割込線クリア)。ACK(bit5)は再武装専任に戻る★
    input  logic        irq0_ack
);

    // ------------------------------------------------------------
    // レジスタ
    // ------------------------------------------------------------
    //  ★tcr_r は【状態ビットのみ】を保持する(bit0/bit1)★
    //    ストローブ(bit2/3/5)は保持しない。emu23 も read で返さない。
    logic        timer_en_r;    // TCR bit0
    logic        irq_en_r;      // TCR bit1
    logic [31:0] period_r;      // PERIOD_HI/LO (32bit)
    logic [31:0] cnt_r;         // ★ダウンカウンタではなく「次回発火cycle」を保持★
    logic        armed_r;       // 1=カウント中 / 0=発火済み沈黙中 ★自己武装解除★
    logic [15:0] sw_runs_r;     // SW_RUNS
    logic [31:0] score_r;       // SCORE (SW_STOP で確定)
    logic [31:0] sw_start_cyc_r;// SW_START 時の cycle
    logic        sw_busy_r;     // SW_BUSY (TCR bit4 R)
    logic [15:0] cycle_hi_lat_r;// CYCLE_LO 読出時にラッチ
    logic [15:0] score_hi_lat_r;// SCORE_LO 読出時にラッチ

    // ------------------------------------------------------------
    // ★発火 EN 条件【D7: OR】★
    //   emu23 L696: ysd8002.irq_enabled = (ysd8002.tcr & 0x03) ? 1 : 0;
    //   原則59: always_comb 内の定数ビット選択を避け assign で外出し
    // ------------------------------------------------------------
    logic fire_en;
    assign fire_en = timer_en_r | irq_en_r;    // ★OR★ (AND ではない。§3.5.1)

    // ------------------------------------------------------------
    // ★TCR ストローブ検出 (1クロックパルス・状態を持たない)★
    //   assign で外出し(原則59)。read では常に 0 が返る(emu23 L616-619 と同形)。
    // ------------------------------------------------------------
    logic tcr_we;
    logic irq_ack_stb, sw_start_stb, sw_stop_stb;
    assign tcr_we       = sel_i & we_i & (addr_i == 4'h0);
    assign irq_ack_stb  = tcr_we & wdata_i[5];   // bit5 IRQ_ACK
    assign sw_start_stb = tcr_we & wdata_i[2];   // bit2 SW_START
    assign sw_stop_stb  = tcr_we & wdata_i[3];   // bit3 SW_STOP

    // ------------------------------------------------------------
    // ★発火判定★
    //   emu23 L257-264 YSD8002_tick():
    //     if (!irq_enabled) return 0;
    //     if (current_cycle >= next_irq_cycle) { next=UINT64_MAX; return 1; }
    //   → armed_r が「next != UINT64_MAX」に相当する。
    //   ★>= であって == ではない★ (cycle が跨いでも取りこぼさない)
    // ------------------------------------------------------------
    logic fire;
    assign fire = armed_r & fire_en & (cycle_i >= cnt_r);

    // ------------------------------------------------------------
    //  ★v0.2 (B-1a): 割込要求ラッチ irq_req_r ★
    //    【変更理由】v0.1 は irq_timer_o を「1クロックパルス」で出していたが、
    //      CPU(v0.5.8) は irq_in を【S_IRQCHK 状態でしかサンプルしない】
    //      (実源 L153-157: state==S_IRQCHK && irq_in!=0 && irq_pending==0)。
    //      S_IRQCHK は命令境界にしか来ない(実CPI≒18)ため、1クロックパルスは
    //      ★ほぼ確実に取りこぼされる★。
    //
    //    【却下した代案】パルスストレッチ(N クロック保持)
    //      → PSRAM ウェイト・キャッシュ・PLL比変更で1命令長が変動すると
    //        静かに破綻する【タイミング依存】。間欠故障となり最悪。
    //
    //    【採用】レベル＋ハンドシェイク (MC6840 PTM の作法)
    //      ・fire        で irq_req_r <= 1 （立ちっぱなし）
    //      ・TCR-ACK(bit5) で irq_req_r <= 0 （ソフトが落とす）
    //      受理中は CPU の IE=0 のため多重受理は起きない。
    //      ACK は IRET より前に実行される契約
    //      (kernel_v12_8.asm L458 / startup_harness23_v16.asm _timer_handler)。
    //      ★クロック非依存★
    //
    //    【契約】IRQ0_HANDLER は必ず TCR に $0023 を書くこと。
    //      書かない場合、irq_req_r が落ちず IRET 後に即再受理されハングする。
    //      これはバグではなく【ACK 義務】の機械的強制である。
    // ------------------------------------------------------------
    logic irq_req_r;
    assign irq_timer_o = irq_req_r;   // ★レベル★ (v0.1 のパルスから変更)

    // ------------------------------------------------------------
    // レジスタ更新
    // ------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // emu23 YSD8002_init() 相当 (L240-254)
            //   tcr = 0x03 (TIMER_EN=1 IRQ_EN=1)
            //   period = cpu_freq/irq_hz = 4,000,000/100 = 40000
            //   next_irq_cycle = cycles_per_irq (1周期後に初回発火)
            timer_en_r     <= 1'b1;
            irq_en_r       <= 1'b1;
            period_r       <= 32'd40000;
            cnt_r          <= 32'd40000;
            armed_r        <= 1'b1;
            irq_req_r      <= 1'b0;   // ★v0.2: reset 時は割込要求なし★
            sw_runs_r      <= 16'd0;
            score_r        <= 32'd0;
            sw_start_cyc_r <= 32'd0;
            sw_busy_r      <= 1'b0;
            cycle_hi_lat_r <= 16'd0;
            score_hi_lat_r <= 16'd0;
        end else begin
            // ------------------------------------------------
            // (1) 発火 → ★自己武装解除★
            //     emu23 L260: next_irq_cycle = UINT64_MAX (次を設定するまで停止)
            //     ★ハンドラが TCR-ACK を書かない限り二度と発火しない★
            // ------------------------------------------------
            if (fire) begin
                armed_r   <= 1'b0;
                irq_req_r <= 1'b1;   // ★v0.2: 割込要求を【立てっぱなし】にする★
                                     //   armed_r=0 で fire 自体は次クロックで落ちるが、
                                     //   irq_req_r は 受理(irq0_ack) か TCR-ACK まで下がらない。
            end
            // ------------------------------------------------
            // (1') ★受理による割込線クリア (案0-a' / v5_irq0_ack_design_v0_1)★
            //     emu23: CPU受理で発火チケット消費(irq_pending=-1) を写像。
            //     ★fire優先(回答書§5-1)★: 同一クロックで fire と irq0_ack が
            //       競合したら fire(set)が勝つ。発火取りこぼしは回復不能だが、
            //       クリアの1クロック遅延は次サイクル受理で無害。よって else if。
            //     再武装はしない(=ワンショット)。周期化は ACK(bit5) が担う。
            // ------------------------------------------------
            else if (irq0_ack) begin
                irq_req_r <= 1'b0;   // 受理=割込線を下ろす(再武装せず)
            end

            // ------------------------------------------------
            // (2) MMIO 書込
            // ------------------------------------------------
            if (sel_i && we_i) begin
                case (addr_i)
                    // --- TCR $FC90 (下位バイト) ---
                    //   ★原則74: 書込値が全ビットを決める★
                    //   状態ビットは wdata で丸ごと上書き。RMW ではない。
                    //   emu23 L695-696: tcr = v & 0x37; irq_enabled = (tcr&0x03)?1:0;
                    4'h0: begin
                        timer_en_r <= wdata_i[0];
                        irq_en_r   <= wdata_i[1];
                        // ★IRQ_ACK (bit5): ACK＋再武装★
                        //   emu23 L701-704 / YSD8002_rearm() L269-273:
                        //     next_irq_cycle = current_cycle + period
                        //   ★1割込につき1回だけ書くこと(複数回書くと周期がずれる)★
                        if (wdata_i[5]) begin
                            cnt_r     <= cycle_i + period_r;
                            armed_r   <= 1'b1;
                            irq_req_r <= 1'b0;   // ★v0.2: ACK＝割込要求を下ろす★
                                                 //   ★同一クロックで fire と衝突した場合、
                                                 //     この後方代入が勝つ(ACK 優先)。
                                                 //     ACK は「今の要求を消す」意思表示であり、
                                                 //     直後に cnt_r が新周期へ更新されるため、
                                                 //     次周期で改めて fire する。取りこぼしなし。
                        end
                        // ★SW_START (bit2): 計測開始 (emu23 L705-709)★
                        if (wdata_i[2]) begin
                            sw_start_cyc_r <= cycle_i;
                            sw_busy_r      <= 1'b1;
                        end
                        // ★SW_STOP (bit3): 計測停止・SCORE 確定 (emu23 L710-714)★
                        if (wdata_i[3] && sw_busy_r) begin
                            score_r   <= cycle_i - sw_start_cyc_r;
                            sw_busy_r <= 1'b0;
                        end
                    end
                    // TCR 上位バイト: emu23 は 16bit 値なので上位は無視(0固定)
                    4'h1: ;  // 書込無視

                    // --- PERIOD_HI $FC92 (period[31:16]) ---
                    4'h2: period_r[23:16] <= wdata_i;
                    4'h3: period_r[31:24] <= wdata_i;
                    // --- PERIOD_LO $FC94 (period[15:0]) ---
                    4'h4: period_r[7:0]   <= wdata_i;
                    4'h5: period_r[15:8]  <= wdata_i;

                    // --- CYCLE は読出専用 ---
                    4'h6, 4'h7, 4'h8, 4'h9: ;  // 書込無視

                    // --- SW_RUNS $FC9A ---
                    4'hA: sw_runs_r[7:0]  <= wdata_i;
                    4'hB: sw_runs_r[15:8] <= wdata_i;

                    // --- SCORE は読出専用 ---
                    4'hC, 4'hD, 4'hE, 4'hF: ;  // 書込無視
                    default: ;
                endcase
            end

            // ------------------------------------------------
            // (3) MMIO 読出の副作用 (★HI ラッチ★)
            //     emu23 L623-627: CYCLE_LO 読出時に CYCLE_HI をラッチする
            //     → 32bit 値を 16bit バス 2回で読む際の一貫性を保証する機構。
            //     ★下位を読んだ瞬間の上位が保存される(読出中に cycle が進んでも
            //       整合した 32bit 値が得られる)★
            //     ★addr_i==4'h6 は CYCLE_LO の【下位バイト】である。
            //       ラッチ契機は emu23 の「CYCLE_LO(16bit)読出」＝
            //       バイト単位では最初のバイト(4'h6)アクセス時とする。★
            // ------------------------------------------------
            if (sel_i && !we_i && (addr_i == 4'h6))
                cycle_hi_lat_r <= cycle_i[31:16];
            if (sel_i && !we_i && (addr_i == 4'hC))
                score_hi_lat_r <= score_r[31:16];
        end
    end

    // ------------------------------------------------------------
    // MMIO 読出 (組合せ)
    //   ★TCR read は bit0/1/4 しか返さない★(emu23 L616-619)
    //     bit2/3/5(ストローブ)は状態を持たないので常に 0。
    //
    //   ★原則59 / iverilog 12.0 制約★
    //     always_comb 内で period_r[23:16] のような【定数ビット選択】を書くと
    //     iverilog 12.0 は "sorry: constant selects in always_* processes are
    //     not currently supported (all bits will be included)" を出す。
    //     → ★assign で事前抽出しておき、always_comb では【名前】を参照する。★
    // ------------------------------------------------------------
    logic [7:0] tcr_rd;
    logic [7:0] period_b0, period_b1, period_b2, period_b3;
    logic [7:0] cycle_b0, cycle_b1;
    logic [7:0] cyc_lat_b0, cyc_lat_b1;
    logic [7:0] runs_b0, runs_b1;
    logic [7:0] score_b0, score_b1;
    logic [7:0] scr_lat_b0, scr_lat_b1;

    assign tcr_rd     = {3'b000, sw_busy_r, 2'b00, irq_en_r, timer_en_r};
    assign period_b0  = period_r[7:0];
    assign period_b1  = period_r[15:8];
    assign period_b2  = period_r[23:16];
    assign period_b3  = period_r[31:24];
    assign cycle_b0   = cycle_i[7:0];
    assign cycle_b1   = cycle_i[15:8];
    assign cyc_lat_b0 = cycle_hi_lat_r[7:0];
    assign cyc_lat_b1 = cycle_hi_lat_r[15:8];
    assign runs_b0    = sw_runs_r[7:0];
    assign runs_b1    = sw_runs_r[15:8];
    assign score_b0   = score_r[7:0];
    assign score_b1   = score_r[15:8];
    assign scr_lat_b0 = score_hi_lat_r[7:0];
    assign scr_lat_b1 = score_hi_lat_r[15:8];

    always_comb begin
        rdata_o = 8'h00;
        if (sel_i && !we_i) begin
            case (addr_i)
                // TCR: bit0=TIMER_EN bit1=IRQ_EN bit4=SW_BUSY
                4'h0: rdata_o = tcr_rd;
                4'h1: rdata_o = 8'h00;                   // 上位バイトは常に0
                4'h2: rdata_o = period_b2;
                4'h3: rdata_o = period_b3;
                4'h4: rdata_o = period_b0;
                4'h5: rdata_o = period_b1;
                4'h6: rdata_o = cycle_b0;
                4'h7: rdata_o = cycle_b1;
                4'h8: rdata_o = cyc_lat_b0;
                4'h9: rdata_o = cyc_lat_b1;
                4'hA: rdata_o = runs_b0;
                4'hB: rdata_o = runs_b1;
                4'hC: rdata_o = score_b0;
                4'hD: rdata_o = score_b1;
                4'hE: rdata_o = scr_lat_b0;
                4'hF: rdata_o = scr_lat_b1;
                default: rdata_o = 8'h00;
            endcase
        end
    end

endmodule

// ============================================================
//  改版履歴
// ------------------------------------------------------------
//   v0.1 (2026-07-14): 新規作成【V5/S7】
//     v5_design_memo_v0_3.md §3.5【D4承認】に基づく YSD8002 タイマー RTL。
//     ★再武装契機を IRET → TCR bit5(IRQ_ACK) 書込へ移した★ことにより、
//     CPU からの特殊信号(iret_pulse_o)が一切不要となり、通常の MMIO
//     デバイスとして実装可能になった(V5 の中核目的)。
//     - 発火: armed_r && (cycle_i >= cnt_r) && (TIMER_EN|IRQ_EN) → 1クロックパルス
//             → armed_r <= 0 ★自己武装解除★ (emu23 L260 と同形)
//     - 再武装: TCR書込 && wdata[5] → cnt_r <= cycle_i + period_r; armed_r <= 1
//             (emu23 YSD8002_rearm() L269-273 と同形)
//     ★【D7】発火 EN は AND ではなく ★OR★ (emu23 L696 実源)。設計メモ v0.2 の
//       AND 記述は誤りであり v0.3 §3.5.1 で訂正済み。原則76(黄金リファレンスの
//       実源に対して実装せよ)。
//     ★★申し送り: EN の OR は設計負債である(IRQ_EN が名前どおり機能しない)。
//       ユーザー指示により★近日中に抜本改修(AND化)★が決定済み。V5完了後に
//       独立工程で実施。詳細: v5_design_memo_v0_3.md §3.5.2 / kaizen 原則77。★★
// ============================================================
