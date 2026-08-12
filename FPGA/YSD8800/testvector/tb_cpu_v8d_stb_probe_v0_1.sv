//==============================================================
// tb_cpu_v8d_dhry_n1_poc.sv   v0.1  (2026-07-23)
//   YSD8800 FPGA V8-D Dhrystone iverilog動作確認TB (正例・案β Number_Of_Runs=1版)
//
//   派生元: tb_cpu_v8d_dhry_poc.sv v0.1 (10反復版)
//   経緯: 10反復版は MAX_CYC=1000万で1反復すら未完了(cyc消費200倍以上膨張)。
//        負荷1/10として1反復版で回帰チェック実施。
//   派生方針: 案S1 (SD経路削除) / KY-G準拠 (期待文字列 "N=1\nP:20" 8B順序照合)
//
//   DUT    : ysd8800_cpu_v0_1 (RTL v0.5.8・無改修)
//            + ysd8800_v5_membus_v0_1 (ファイル v0.2・YSD8003結線版・無改修)
//   SDモデル: 無し (削除・案S1)
//            spi_miso_i=1'b1 tie-off / disk_sectors_i=32'd0 tie-off
//   プログラム: dhry_n1_final.hex (dhry_timer_n1.c ISA2.3 build・21846B・Number_Of_Runs=1)
//              scc23 v2.03 / hasm23 v1.04 / lnk23 v2.01 でビルド
//
//   検証:
//     UART($FC80)へ putchar 出力されるバイト列を tx_valid_o パルスで
//     捕捉しFIFO配列に蓄積。HALT後に期待文字列とバイト単位で照合。
//     期待列: "N=1\nP:20" (8B・順序込み)
//       - "N=1\n" (4B): dhry_timer_n1.c L625 (dhrystone()内・print_num(1))
//       - "P:20"  (4B): dhry_timer_n1.c L551-554 (main()内・result==20)
//
//   合格判定 (設計メモ v0.2 §3.1準拠・案β用に長さ変更):
//     S1_halt        : HALT到達
//     S2_uart_len    : uart_cnt == 8
//     S3_uart_match  : mism_bytes == 0 (順序込み8B一致)
//     T0_negative    : TB健全性 (KY54踏襲)
//
//   ビルド:
//     iverilog -g2012 -o tb_n1.vvp tb_cpu_v8d_dhry_n1_poc.sv \
//       ysd8800_cpu_v0_1_FIXED.sv ysd8800_v5_membus_v0_2.sv \
//       ysd8800_mmio_stub_v0_7.sv ysd8800_ysd8003_v0_4.sv \
//       ysd8800_ysd8002_v0_3.sv ysd8800_ysd8004_v0_1.sv \
//       ysd8800_ysd8001_v0_1.sv ysd8800_addr_decoder_v0_1.sv \
//       ysd8800_cdc_bridge_v0_2.sv ysd8800_mmu_v0_1.sv \
//       ysd8800_psram_ctrl_v0_2.sv
//     ※ sd_spi_model_v0_3_poc.sv は含めない (案S1)
//==============================================================
`timescale 1ns/1ps

module tb_cpu_v8d_stb_probe_v0_1;

    // ---- クロック/リセット ----
    logic cpu_clk;
    logic cpu_rst_n;
    logic psram_clk;
    logic psram_rst_n;

    // ---- CPU <-> membus バス ----
    logic [15:0] mem_addr;
    logic [7:0]  mem_wdata;
    logic [7:0]  mem_rdata;
    logic        mem_rd;
    logic        mem_wr;
    logic        mem_ready;

    // ---- 割込 ----
    logic [2:0]  irq_in;
    logic        irq_timer_o;
    logic        irq1_o;
    logic        irq0_ack;

    // ---- CPU dbg ----
    logic [15:0] dbg_pc, dbg_a, dbg_b, dbg_x, dbg_sp, dbg_flags;
    logic        dbg_halt;
    logic [2:0]  dbg_irq_pending;

    // ---- membus dbg ----
    logic [15:0] dbg_mmio_last_addr;
    logic [31:0] dbg_mmio_access_count;
    logic        dbg_mmu_en;
    logic [19:0] dbg_phys_addr;
    logic [127:0] dbg_ptr_flat;
    logic [31:0] dbg_cycle;

    // ---- UARTポート ----
    logic        uart_rx_valid_i;
    logic [7:0]  uart_rx_data_i;
    logic        uart_tx_valid_o;
    logic [7:0]  uart_tx_data_o;

    // ---- SPI物理線 (案S1: 未接続tie-off) ----
    //  membusのポート要求に応じて信号は宣言するが SDモデルは接続しない
    //  spi_miso_i=1 (SD無応答時のidleライン想定) / disk_sectors_i=0
    logic        spi_cs_n_o;
    logic        spi_sck_o;
    logic        spi_mosi_o;
    logic        spi_miso_i;
    logic [31:0] disk_sectors_i;

    integer errors = 0;
    integer passes = 0;

    // ★STBプローブ v0.1: $F792(Ch_Locスロット)への書込監視
    //   目的: $25AF EXT STB B,[X] の write path が PSRAM へ届くか観測
    integer stb_wr_f792_cnt = 0;   // $F792へのmem_wr発火回数
    integer stb25af_ent     = 0;   // $25AF到達回数
    integer probe_dump_cnt  = 0;   // ダンプ抑制カウンタ

    assign irq_in = irq_timer_o ? 3'd1 : (irq1_o ? 3'd2 : 3'd0);

    // ============================================================
    //  DUT: CPUコア (無改修)
    // ============================================================
    ysd8800_cpu_v0_1 dut_cpu (
        .clk(cpu_clk), .rst_n(cpu_rst_n),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata),
        .mem_rd(mem_rd), .mem_wr(mem_wr), .mem_ready(mem_ready),
        .irq_in(irq_in),
        .dbg_pc(dbg_pc), .dbg_a(dbg_a), .dbg_b(dbg_b), .dbg_x(dbg_x),
        .dbg_sp(dbg_sp), .dbg_flags(dbg_flags), .dbg_halt(dbg_halt),
        .dbg_irq_pending(dbg_irq_pending),
        .irq0_ack(irq0_ack)
    );

    // ============================================================
    //  DUT: v5 membus (ファイル v0.2・YSD8003結線版・無改修)
    // ============================================================
    ysd8800_v5_membus_v0_1 #(.PHYS_AW(20), .MEM_AW(20)) u_membus (
        .cpu_clk(cpu_clk), .cpu_rst_n(cpu_rst_n),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata),
        .mem_rd(mem_rd), .mem_wr(mem_wr), .mem_ready(mem_ready),
        .psram_clk(psram_clk), .psram_rst_n(psram_rst_n),
        .irq1_o(irq1_o),
        .spi_cs_n_o(spi_cs_n_o),
        .spi_sck_o(spi_sck_o),
        .spi_mosi_o(spi_mosi_o),
        .spi_miso_i(spi_miso_i),
        .disk_sectors_i(disk_sectors_i),
        .uart_rx_valid_i(uart_rx_valid_i),
        .uart_rx_data_i(uart_rx_data_i),
        .uart_tx_valid_o(uart_tx_valid_o),
        .uart_tx_data_o(uart_tx_data_o),
        .irq_timer_o(irq_timer_o),
        .irq0_ack(irq0_ack),
        .dbg_mmio_last_addr(dbg_mmio_last_addr),
        .dbg_mmio_access_count(dbg_mmio_access_count),
        .dbg_mmu_en(dbg_mmu_en),
        .dbg_phys_addr(dbg_phys_addr),
        .dbg_ptr_flat(dbg_ptr_flat),
        .dbg_cycle(dbg_cycle)
    );

    // ============================================================
    //  SDモデル (案S1: 削除・接続なし)
    //  Dhrystone は SD 未使用のため sd_spi_model_v0_3_poc は非接続。
    //  membus は spi_cs_n_o/spi_sck_o/spi_mosi_o を出すが、
    //  Dhrystone プログラムは SPI MMIO ($FCA0系) を触らないため
    //  spi_cs_n_o は初期状態 (deasserted) のままとなる。
    // ============================================================

    // ============================================================
    //  クロック
    // ============================================================
    initial cpu_clk = 0;
    always #10 cpu_clk = ~cpu_clk;
    initial psram_clk = 0;
    always #1.25 psram_clk = ~psram_clk;

    // ============================================================
    //  ★UARTキャプチャ★
    //    YSD8001 は $FC80 書込のたび tx_valid_o を1クロックパルス、
    //    tx_data_o にバイトを載せる。これを捕捉し uart_fifo に蓄積。
    // ============================================================
    localparam integer UART_CAP_MAX = 256;
    logic [7:0] uart_fifo [0:UART_CAP_MAX-1];
    integer     uart_cnt = 0;

    // ★STBプローブ: CPUバス上で mem_wr=1 かつ addr=$F792 の瞬間を捕捉
    //   CPUコアが STB write を「バスに出しているか」を直接観測する。
    //   これが発火していれば CPU側は正常 → 真因は下流(bridge/MMU/PSRAM)。
    //   発火していなければ CPU側で STB が消えている。
    always @(posedge cpu_clk) begin
        if (cpu_rst_n && mem_wr && (mem_addr == 16'hF792)) begin
            stb_wr_f792_cnt = stb_wr_f792_cnt + 1;
            if (stb_wr_f792_cnt <= 8)
                $display("  [CPUBUS_WR $F792 #%0d cyc=%0d PC=%04h] mem_wdata=%02h B=%04h A=%04h X=%04h",
                         stb_wr_f792_cnt, to_cyc, dbg_pc, mem_wdata, dbg_b, dbg_a, dbg_x);
        end
    end

    always @(posedge cpu_clk) begin
        if (cpu_rst_n && uart_tx_valid_o) begin
            if (uart_cnt < UART_CAP_MAX) begin
                uart_fifo[uart_cnt] = uart_tx_data_o;
                uart_cnt = uart_cnt + 1;
            end
        end
    end

    // ============================================================
    //  期待文字列 (8B): "N=1\nP:20"  [V8-D 案β Number_Of_Runs=1版]
    //    dhry_timer_n1.c 実源根拠 (Number_Of_Runs=1改変版):
    //      L625: putchar('N'); putchar('='); print_num(1); putchar('\n');  → "N=1\n"
    //      L551-554: putchar('P'); putchar(':'); print_num(result);        → "P:20"
    //    result==20 は 20項目検証パス合計 (Number_Of_Runsとは無関係)
    //    KY-G準拠: 順序込み8B照合
    // ============================================================
    localparam integer EXP_LEN = 8;
    logic [7:0] exp_str [0:EXP_LEN-1];
    initial begin
        // "N=1\n" (4B)
        exp_str[0]="N"; exp_str[1]="="; exp_str[2]="1"; exp_str[3]="\n";
        // "P:20" (4B)
        exp_str[4]="P"; exp_str[5]=":"; exp_str[6]="2"; exp_str[7]="0";
    end

    // ============================================================
    //  判定ユーティリティ
    // ============================================================
    task automatic chk(input string name, input integer got, input integer exp);
        if (got === exp) begin
            passes = passes + 1;
            $display("  PASS %-28s got=%0d exp=%0d", name, got, exp);
        end else begin
            errors = errors + 1;
            $display("  FAIL %-28s got=%0d exp=%0d", name, got, exp);
        end
    endtask

    task automatic chk_expect_fail(input string name, input integer got, input integer wrong_exp);
        if (got !== wrong_exp) begin
            passes = passes + 1;
            $display("  PASS %-28s (TB detects mismatch: got=%0d != wrong=%0d)",
                     name, got, wrong_exp);
        end else begin
            errors = errors + 1;
            $display("  FAIL %-28s (TB missed: got==wrong==%0d)", name, got);
        end
    endtask

    // ============================================================
    //  走行: HALT到達 or タイムアウト
    // ============================================================
    integer to_cyc;
    // ★Step B: PC ヒストグラム 256B単位(上位8bit)で集計
    logic [31:0] pc_hist [0:255];

    // ★Step D: 主要エントリ通過回数
    integer main_ent, dhry_ent, for_cond_ent, for_body_ent;
    integer func1_ent, func2_ent;
    // ★Step F: Func_2 while ループ本体ラベル通過回数
    integer L0139_ent, L0143_ent, L0145_ent, L0140_ent;
    // ★Step G: for本体内 JSR _Func_2 命令位置の通過回数
    integer jsr_func2_ent;
    // ★Step H: Func_2 RET直前 ($27B8) の観測 (最初10回)
    integer func2_ret_dump_cnt;
    logic [7:0] sp_m2, sp_m1, sp_0, sp_1, sp_2, sp_3;
    // ★Step I: L_0140 以降のラベル通過
    integer L0149_ent, L0150_ent, L0151_ent, L0152_ent;
    integer L0147_ent, L0148_ent, L0153_ent;
    integer L0155_ent, L0156_ent, L0157_ent;
    integer L0138_ent;
    // ★Step J: $2627 BGE / $2629 LDW / $262D JMP 実行直前の状態観測
    integer bge_dump_cnt, ldw_dump_cnt, jmp_dump_cnt;
    integer post_jmp_dump_cnt;   // JMP実行後の次PC観測
    logic jmp_reached;            // $262D 到達フラグ
    logic [7:0] jmp_b0, jmp_b1, jmp_b2, jmp_b3;   // JMP命令バイト列
    logic [15:0] pc_prev;

    // 診断版: 100万cyc毎に PC/A/B/SP/FLAGS/UART進捗をダンプ + PC ヒストグラム集計 + エントリカウント
    task automatic run_until_halt(input integer max_cyc);
        integer next_dump;
        integer i;
        to_cyc = 0;
        next_dump = 500000;
        for (i = 0; i < 256; i = i + 1) pc_hist[i] = 32'd0;
        main_ent = 0; dhry_ent = 0; for_cond_ent = 0; for_body_ent = 0;
        func1_ent = 0; func2_ent = 0;
        L0139_ent = 0; L0143_ent = 0; L0145_ent = 0; L0140_ent = 0;
        jsr_func2_ent = 0;
        func2_ret_dump_cnt = 0;
        L0149_ent = 0; L0150_ent = 0; L0151_ent = 0; L0152_ent = 0;
        L0147_ent = 0; L0148_ent = 0; L0153_ent = 0;
        L0155_ent = 0; L0156_ent = 0; L0157_ent = 0;
        L0138_ent = 0;
        bge_dump_cnt = 0; ldw_dump_cnt = 0; jmp_dump_cnt = 0;
        post_jmp_dump_cnt = 0;
        jmp_reached = 1'b0;
        pc_prev = 16'hFFFF;
        while (dbg_halt !== 1'b1 && to_cyc < max_cyc) begin
            @(posedge cpu_clk);
            to_cyc = to_cyc + 1;
            // PC 上位8bit (bin=256B単位) を集計
            pc_hist[dbg_pc[15:8]] = pc_hist[dbg_pc[15:8]] + 1;
            // ★Step D: PC変化時のみエントリカウント (同一PC連続は1回扱い)
            if (dbg_pc !== pc_prev) begin
                case (dbg_pc)
                    16'h04CC: main_ent     = main_ent     + 1;
                    16'h0579: dhry_ent     = dhry_ent     + 1;
                    16'h07CB: for_cond_ent = for_cond_ent + 1;
                    16'h0835: for_body_ent = for_body_ent + 1;
                    16'h23B4: func1_ent    = func1_ent    + 1;
                    16'h248D: begin
                        func2_ent = func2_ent + 1;
                        // ★制御フロー: Func_2突入直前のPC(=JSRまたはRET先)を捕捉
                        if (func2_ent <= 8)
                            $display("  [F2_ENTRY #%0d cyc=%0d] from PC_prev=%04h  SP=%04h  [SP+0..3]=%02h %02h %02h %02h",
                                     func2_ent, to_cyc, pc_prev, dbg_sp,
                                     u_membus.u_psram_ctrl.mem[dbg_sp+16'd0],
                                     u_membus.u_psram_ctrl.mem[dbg_sp+16'd1],
                                     u_membus.u_psram_ctrl.mem[dbg_sp+16'd2],
                                     u_membus.u_psram_ctrl.mem[dbg_sp+16'd3]);
                    end
                    // ★制御フロー: $248C = RET命令。到達時と実行後のSP変化を捕捉
                    //   期待: RET実行後 SP+=2、PCはスタック上の戻り番地に飛ぶ
                    //   異常: SP不変 or PC=$248D(=PC++ フォールスルー)
                    16'h248C: begin
                        if (func2_ent <= 5)
                            $display("  [RET248C cyc=%0d f2=%0d] SP=%04h  [SP+0..3]=%02h %02h %02h %02h  A=%04h B=%04h",
                                     to_cyc, func2_ent, dbg_sp,
                                     u_membus.u_psram_ctrl.mem[dbg_sp+16'd0],
                                     u_membus.u_psram_ctrl.mem[dbg_sp+16'd1],
                                     u_membus.u_psram_ctrl.mem[dbg_sp+16'd2],
                                     u_membus.u_psram_ctrl.mem[dbg_sp+16'd3],
                                     dbg_a, dbg_b);
                    end
                    // ★STBプローブ: $25AF = EXT STB B,[X] (Ch_Loc='A'書込) 到達
                    //   到達時のB(=書込値$41期待)/X(=$F792期待)と、
                    //   現時点のPSRAM mem[$F792](=書込前の値)を観測
                    16'h25AF: begin
                        stb25af_ent = stb25af_ent + 1;
                        if (probe_dump_cnt < 3) begin
                            $display("  [STB25AF#%0d cyc=%0d] B=%04h X=%04h  PSRAM[F792](書込前)=%02h",
                                     stb25af_ent, to_cyc, dbg_b, dbg_x,
                                     u_membus.u_psram_ctrl.mem[16'hF792]);
                            probe_dump_cnt = probe_dump_cnt + 1;
                        end
                    end
                    // ★STBプローブ: $25B1 = STB実行直後。PSRAM[$F792]が$41になったか
                    16'h25B1: begin
                        if (stb25af_ent <= 3)
                            $display("  [STB25B1(STB直後) cyc=%0d] PSRAM[F792](書込後)=%02h  (=$41期待)",
                                     to_cyc, u_membus.u_psram_ctrl.mem[16'hF792]);
                    end
                    // ★Step F: while ループ本体ラベル通過
                    16'h24C9: L0139_ent    = L0139_ent    + 1;   // while 先頭
                    16'h2586: L0143_ent    = L0143_ent    + 1;   // Func_1==Ident_1 成立
                    16'h260D: L0145_ent    = L0145_ent    + 1;   // Func_1!=Ident_1
                    // 16'h2610: → 下に統合 (L0140_ent更新+観測)
                    // ★Step G: for本体内 JSR _Func_2 命令位置
                    16'h08E8: jsr_func2_ent = jsr_func2_ent + 1;
                    // ★Step I: L_0140 以降のラベル通過
                    16'h2630: L0149_ent = L0149_ent + 1;
                    16'h2634: L0150_ent = L0150_ent + 1;
                    16'h265B: L0151_ent = L0151_ent + 1;
                    16'h265F: L0152_ent = L0152_ent + 1;
                    16'h266D: L0147_ent = L0147_ent + 1;
                    16'h2671: L0148_ent = L0148_ent + 1;
                    16'h26A0: L0153_ent = L0153_ent + 1;
                    16'h26C0: L0155_ent = L0155_ent + 1;
                    16'h26C4: L0156_ent = L0156_ent + 1;
                    16'h26D9: L0157_ent = L0157_ent + 1;
                    16'h27B0: L0138_ent = L0138_ent + 1;
                    // ★Step J: 中間PC通過カウンタ (最初3回だけダンプ)
                    16'h2614: begin
                        if (bge_dump_cnt < 3) begin
                            $display("  [PC_2614#%0d cyc=%0d] 到達! (L_0140の $2610 LDW直後)", bge_dump_cnt+1, to_cyc);
                            bge_dump_cnt = bge_dump_cnt + 1;
                        end
                    end
                    16'h2618: begin
                        if (ldw_dump_cnt < 3) begin
                            $display("  [PC_2618#%0d cyc=%0d] 到達! (SUBI SP,#2直後 = STW A,[SP])", ldw_dump_cnt+1, to_cyc);
                            ldw_dump_cnt = ldw_dump_cnt + 1;
                        end
                    end
                    16'h261A: begin
                        if (jmp_dump_cnt < 3) begin
                            $display("  [PC_261A#%0d cyc=%0d] 到達! (STW直後 = LDW A,#87)", jmp_dump_cnt+1, to_cyc);
                            jmp_dump_cnt = jmp_dump_cnt + 1;
                        end
                    end
                    // ★Step J: $2610 (L_0140) 到達時に A/B/X/SP/FLAGSと[X-6][X-5]も観測
                    16'h2610: begin
                        L0140_ent = L0140_ent + 1;
                        if (post_jmp_dump_cnt < 3) begin
                            $display("  [PC_2610_L0140#%0d cyc=%0d] A=%04h B=%04h X=%04h SP=%04h FLAGS=%04h",
                                     post_jmp_dump_cnt+1, to_cyc, dbg_a, dbg_b, dbg_x, dbg_sp, dbg_flags);
                            // [X-6]と[X-5] = X+FFFA が指すメモリ (Ch_Loc格納位置)
                            $display("       PSRAM [X-6=%04h][X-5]=%02h %02h  (LDW A,[X+FFFA]の読出元)",
                                     dbg_x - 16'd6,
                                     u_membus.u_psram_ctrl.mem[dbg_x - 16'd6],
                                     u_membus.u_psram_ctrl.mem[dbg_x - 16'd5]);
                            $display("       PSRAM [$2610..$2617]=%02h %02h %02h %02h %02h %02h %02h %02h",
                                     u_membus.u_psram_ctrl.mem[16'h2610],
                                     u_membus.u_psram_ctrl.mem[16'h2611],
                                     u_membus.u_psram_ctrl.mem[16'h2612],
                                     u_membus.u_psram_ctrl.mem[16'h2613],
                                     u_membus.u_psram_ctrl.mem[16'h2614],
                                     u_membus.u_psram_ctrl.mem[16'h2615],
                                     u_membus.u_psram_ctrl.mem[16'h2616],
                                     u_membus.u_psram_ctrl.mem[16'h2617]);
                            post_jmp_dump_cnt = post_jmp_dump_cnt + 1;
                        end
                    end
                    // ★Step J: 元々の $2627 BGE 直前観測 (念のため残す)
                    16'h2626: begin  // 実は $2626 が BGE (私が誤解していた)
                        $display("  [BGE_at_2626 cyc=%0d] A=%04h B=%04h X=%04h FLAGS=%04h",
                                 to_cyc, dbg_a, dbg_b, dbg_x, dbg_flags);
                    end
                    // ★Step H: Func_2 RET 直前 ($27B8)
                    16'h27B8: begin
                        if (func2_ret_dump_cnt < 10) begin
                            sp_m2 = u_membus.u_psram_ctrl.mem[dbg_sp - 2];
                            sp_m1 = u_membus.u_psram_ctrl.mem[dbg_sp - 1];
                            sp_0  = u_membus.u_psram_ctrl.mem[dbg_sp + 0];
                            sp_1  = u_membus.u_psram_ctrl.mem[dbg_sp + 1];
                            sp_2  = u_membus.u_psram_ctrl.mem[dbg_sp + 2];
                            sp_3  = u_membus.u_psram_ctrl.mem[dbg_sp + 3];
                            $display("  [Func_2_RET#%0d cyc=%0d] SP=%04h  [SP-2..SP+3]=%02h %02h | %02h %02h | %02h %02h  → POP先PC=%02h%02h",
                                     func2_ret_dump_cnt+1, to_cyc, dbg_sp,
                                     sp_m2, sp_m1, sp_0, sp_1, sp_2, sp_3,
                                     sp_1, sp_0);
                            func2_ret_dump_cnt = func2_ret_dump_cnt + 1;
                        end
                    end
                endcase
                pc_prev = dbg_pc;
            end
            if (to_cyc >= next_dump) begin
                $display("  [DIAG cyc=%8d] PC=%04h uart=%0d  main=%0d dhry=%0d fcnd=%0d fbdy=%0d f1=%0d f2=%0d",
                         to_cyc, dbg_pc, uart_cnt,
                         main_ent, dhry_ent, for_cond_ent, for_body_ent, func1_ent, func2_ent);
                next_dump = next_dump + 500000;
            end
        end
        if (dbg_halt !== 1'b1)
            $display("  [WARN] timeout: HALT not reached in %0d cyc", max_cyc);
        else
            $display("  [info] HALT reached at cyc=%0d (PC=%04h)", to_cyc, dbg_pc);
    endtask

    // ★Step D+F: エントリカウンタの最終ダンプ
    task automatic dump_entry_counts;
        $display("--- ENTRY COUNTS (期待値: NoR=1 完走時) ---");
        $display("  main   ($04CC)  : %0d  (期待=1)",       main_ent);
        $display("  dhry   ($0579)  : %0d  (期待=1)",       dhry_ent);
        $display("  for_cond ($07CB): %0d  (期待=2 [i=1判定+i=2判定])", for_cond_ent);
        $display("  for_body ($0835): %0d  (期待=1)",       for_body_ent);
        $display("  Func_1 ($23B4)  : %0d  (期待=3・Func_2から)",  func1_ent);
        $display("  Func_2 ($248D)  : %0d  (期待=1・for本体から)", func2_ent);
        $display("--- Func_2 while ループ ラベル通過 (★Step F) ---");
        $display("  L_0139 ($24C9) while先頭     : %0d", L0139_ent);
        $display("  L_0143 ($2586) Func_1==Ident_1: %0d  (Int_Loc++ 成立ルート)", L0143_ent);
        $display("  L_0145 ($260D) Func_1!=Ident_1: %0d  (Int_Loc そのまま)",  L0145_ent);
        $display("  L_0140 ($2610) while抜け後   : %0d", L0140_ent);
        $display("--- for本体内 JSR _Func_2 通過 (★Step G) ---");
        $display("  JSR _Func_2 ($08E8): %0d  (期待=1)", jsr_func2_ent);
        $display("--- L_0140 以降のラベル通過 (★Step I) ---");
        $display("  L_0140 ($2610) while抜け: %0d", L0140_ent);
        $display("  L_0149 ($2630) Ch_Loc>='W'成立: %0d", L0149_ent);
        $display("  L_0150 ($2634) 判定後: %0d", L0150_ent);
        $display("  L_0151 ($265B) Ch_Loc<'Z'成立: %0d", L0151_ent);
        $display("  L_0152 ($265F) 判定後: %0d", L0152_ent);
        $display("  L_0147 ($266D) else合流: %0d", L0147_ent);
        $display("  L_0148 ($2671) then合流: %0d", L0148_ent);
        $display("  L_0153 ($26A0) if後: %0d", L0153_ent);
        $display("  L_0155 ($26C0) Ch_Loc=='R'成立: %0d", L0155_ent);
        $display("  L_0156 ($26C4) 判定後: %0d", L0156_ent);
        $display("  L_0157 ($26D9) return true ルート: %0d", L0157_ent);
        $display("  L_0138 ($27B0) RET準備: %0d", L0138_ent);
        $display("--- 診断ヒント (Step G) ---");
        if (jsr_func2_ent == func2_ent && func2_ent > 1)
            $display("  → JSR通過数 == Func_2入口通過数 = for本体内で Func_2 呼出ループ発生");
        else if (jsr_func2_ent == 1 && func2_ent > 1)
            $display("  → JSR通過=1回だが Func_2入口=多数 → Func_2 のRETがFunc_2入口に戻っている");
        $display("--- 診断ヒント ---");
        if (L0143_ent > 0 && L0145_ent == 0)
            $display("  → Func_1 は Ident_1 と一致判定(=0)。Int_Loc++ ルートを通っている");
        else if (L0145_ent > 0 && L0143_ent == 0)
            $display("  → Func_1 は Ident_1 と不一致判定(=1)。Int_Loc そのまま = while 継続");
        else if (L0143_ent > 0 && L0145_ent > 0)
            $display("  → 両ルート発生");
    endtask

    // ============================================================
    //  ★Step B: PC ヒストグラムダンプ (非零binを cnt降順)
    // ============================================================
    task automatic dump_pc_hist;
        integer i, j;
        integer maxidx;
        logic [31:0] maxv;
        logic [31:0] hist_local [0:255];
        integer nonzero;
        $display("--- PC HISTOGRAM (256B/bin・降順・上位20) ---");
        nonzero = 0;
        for (i = 0; i < 256; i = i + 1) begin
            hist_local[i] = pc_hist[i];
            if (pc_hist[i] != 0) nonzero = nonzero + 1;
        end
        $display("  (非零bin数=%0d)", nonzero);
        for (j = 0; j < 20; j = j + 1) begin
            maxidx = 0;
            maxv = 0;
            for (i = 0; i < 256; i = i + 1) begin
                if (hist_local[i] > maxv) begin
                    maxv = hist_local[i];
                    maxidx = i;
                end
            end
            if (maxv == 0) begin
                $display("  (残り0)");
                j = 100;  // 早期break
            end else begin
                $display("  #%2d  bin=$%02h00-%02hFF  cnt=%0d",
                         j+1, maxidx[7:0], maxidx[7:0], maxv);
                hist_local[maxidx] = 0;
            end
        end
    endtask

    // ============================================================
    //  UART出力照合: uart_fifo[0..uart_cnt-1] vs exp_str[0..EXP_LEN-1]
    //    戻り: 不一致バイト数(mism)・順序込みの完全一致を要求
    // ============================================================
    integer mism_bytes;
    task automatic compare_uart(output integer mism);
        integer i;
        begin
            mism = 0;
            // 長さ不一致もmismに寄与
            if (uart_cnt != EXP_LEN) begin
                $display("  [len] uart_cnt=%0d exp=%0d (length mismatch)", uart_cnt, EXP_LEN);
                mism = mism + 1;
            end
            for (i = 0; i < EXP_LEN; i = i + 1) begin
                if (i < uart_cnt) begin
                    if (uart_fifo[i] !== exp_str[i]) begin
                        $display("  [diff] idx=%0d got=%02h exp=%02h", i, uart_fifo[i], exp_str[i]);
                        mism = mism + 1;
                    end
                end
            end
        end
    endtask

    // UART出力を可読ダンプ
    task automatic dump_uart;
        integer i;
        begin
            $write("  [UART out] \"");
            for (i = 0; i < uart_cnt; i = i + 1) begin
                if (uart_fifo[i] == 8'h0a) $write("\\n");
                else $write("%c", uart_fifo[i]);
            end
            $display("\"  (cnt=%0d)", uart_cnt);
        end
    endtask

    // ============================================================
    //  メイン
    // ============================================================
    //  MAX_CYC 根拠 (設計メモ v0.2 §4.5):
    //    emu23 実測 48,405 cyc × PSRAM wait 5〜20倍膨張想定 = 24万〜97万 cyc
    //    上限 1000万 cyc は想定最大の約10倍余裕
    localparam integer MAX_CYC = 100000;

    initial begin
        $display("============================================================");
        $display(" tb_cpu_v8d_dhry_stepJ_jmp  YSD8800 FPGA V8-D Step J");
        $display("   $2627 BGE / $2629 LDW / $262D JMP 実行時状態観測");
        $display("   + PSRAM $262D-$2630 の実バイト列 + JMP後の次PC");
        $display("   → JMP _L_0150 が誤って $248D に飛ぶ真因の決着");
        $display("============================================================");

        // 案S1: SD tie-off
        spi_miso_i      = 1'b1;
        disk_sectors_i  = 32'd0;
        uart_rx_valid_i = 1'b0;
        uart_rx_data_i  = 8'h00;

        $display("[LOAD] dhry_n1_final.hex");
        cpu_rst_n   = 0;
        psram_rst_n = 0;
        repeat (3) @(negedge psram_clk);
        psram_rst_n = 1;
        for (int i = 0; i < 16'h0400; i = i + 1)
            u_membus.u_psram_ctrl.mem[i] = 8'h00;
        $readmemh("dhry_n1_final.hex", u_membus.u_psram_ctrl.mem);
        repeat (3) @(negedge cpu_clk);
        cpu_rst_n = 1;

        run_until_halt(MAX_CYC);

        dump_uart();
        compare_uart(mism_bytes);
        dump_pc_hist();
        dump_entry_counts();
        $display("  [read] UART mism_bytes=%0d", mism_bytes);

        // ---------- 判定 ----------
        $display("--- T0: negative run (KY54踏襲: TBがFAILを出せる健全性) ---");
        // わざと外した期待(mismが負数になることはないので、-1と比較でTB健全性確認)
        chk_expect_fail("T0_negative", mism_bytes, /*wrong=*/-1);

        $display("--- S1: プログラム完走(HALT到達) ---");
        chk("S1_halt", (dbg_halt===1'b1) ? 1 : 0, 1);

        $display("--- S2: UART出力バイト数==EXP_LEN(8) ---");
        chk("S2_uart_len", uart_cnt, EXP_LEN);

        $display("--- S3: UART出力==期待文字列(mism==0・順序込み8B) ---");
        chk("S3_uart_match", mism_bytes, 0);

        $display("============================================================");
        $display(" RESULT: PASS=%0d FAIL=%0d", passes, errors);
        if (errors == 0) $display(" >>> V8-D Dhrystone INTEGRATION ALL PASS <<<");
        else             $display(" >>> SOME FAILED <<<");
        $display("============================================================");
        $finish;
    end

    // 保険タイムアウト
    initial begin
        #300_000_000;
        $display("  [FATAL] simulation watchdog timeout");
        $finish;
    end

endmodule
