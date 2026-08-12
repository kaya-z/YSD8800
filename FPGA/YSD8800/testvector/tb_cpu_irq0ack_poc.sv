// ============================================================
//  tb_cpu_irq0ack_poc.sv   v0.1  (2026-07-17)
//  YSD8800 FPGA V5/S4 : irq0_ack 出力ピン直接観測TB
//
//  目的(設計メモ tb_cpu_irq0ack_poc_design_v0_1.md):
//   「IE=0 のとき irq0_ack が立たない / IE=1 の割込受理時に irq0_ack が
//    1クロックだけ立つ」を CPU の irq0_ack 出力ピンの直接観測で実証する。
//   (HANDOVER 繰返し指示「見込みで省略せず実証」への対応。S4デグレの補完)
//
//  ベース: tb_cpu_irq_v0_1.sv (V1・ALL PASS実績)
//  差分3点:
//    (1) DUT に .irq0_ack(irq0_ack) を追加接続 (既存TBは未接続=観測不可)
//    (2) irq0_ack アサート回数カウンタ ack_cnt
//    (3) 2フェーズ連続実行 (Case-EI → 再reset → Case-DI)
//
//  irq0_ack 生成条件(実源 cpu_v0_1_FIXED L919-920):
//    (state==S_MEMR_HI)&&mem_ready&&(stack_ctx==CTX_IRQVEC)&&(irq_latch==3'd1)
//   → IE=0 では S_IRQ_ACCEPT に入らず stack_ctx が CTX_IRQVEC にならない
//     ⇒ 構造上 irq0_ack は立たない。本TBはこれを実証する。
//
//  golden:
//   ベクタ mem[0002:0003]=0300 → IRQ1(timer)ハンドラ=0x0300
//   Case-EI: 0104=EI(02)  → 受理あり: ack_cnt==1, B=00AA, A=0011
//   Case-DI: 0104=DI(03)  → 受理なし: ack_cnt==0, B!=00AA, A=0022, HALT@010D
//     (DI: ie_clr IE←0 明示。ISA2.3実在命令 decoder L111 8'h03=ID_DI)
// ============================================================
`timescale 1ns/1ps

import ysd8800_idec_pkg::*;

module tb_cpu_irq0ack_poc;
    logic        clk, rst_n;
    logic [15:0] mem_addr;
    logic [7:0]  mem_wdata, mem_rdata;
    logic        mem_rd, mem_wr, mem_ready;
    logic [2:0]  irq_in;
    logic [15:0] dbg_pc, dbg_a, dbg_b, dbg_x, dbg_sp, dbg_flags;
    logic        dbg_halt;
    logic [2:0]  dbg_irq_pending;
    logic        irq0_ack;              // ★差分(1): 観測対象ピン★

    integer errors = 0;
    integer ack_cnt;                    // ★差分(2): irq0_ack アサート回数★

    ysd8800_cpu_v0_1 dut (
        .clk(clk), .rst_n(rst_n),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata),
        .mem_rd(mem_rd), .mem_wr(mem_wr), .mem_ready(mem_ready),
        .irq_in(irq_in),
        .dbg_pc(dbg_pc), .dbg_a(dbg_a), .dbg_b(dbg_b), .dbg_x(dbg_x),
        .dbg_sp(dbg_sp), .dbg_flags(dbg_flags), .dbg_halt(dbg_halt),
        .dbg_irq_pending(dbg_irq_pending),
        .irq0_ack(irq0_ack)             // ★差分(1)★
    );

    logic [7:0] mem [0:65535];
    assign mem_ready = 1'b1;
    always_comb mem_rdata = mem[mem_addr];
    always_ff @(posedge clk) begin
        if (mem_wr) mem[mem_addr] <= mem_wdata;
    end

    // ★差分(2): irq0_ack を毎クロック監視してカウント★
    always_ff @(posedge clk) begin
        if (irq0_ack) ack_cnt <= ack_cnt + 1;
    end

    initial clk = 0;
    always #5 clk = ~clk;

    // 共通プログラムロード (op0104 で EI(02)/DI(03) を切替)
    task load_program(input [7:0] op0104);
        begin
            for (int i=0;i<65536;i=i+1) mem[i]=8'h00;
            mem[16'h0000]=8'h00; mem[16'h0001]=8'h01; // reset →0x0100
            // IRQ1(timer) ベクタ: mem[2]=0x0300 (LE)
            mem[16'h0002]=8'h00; mem[16'h0003]=8'h03;
            // 0100 LDWI SP,#4000
            mem[16'h0100]=8'h21; mem[16'h0101]=8'h30; mem[16'h0102]=8'h00; mem[16'h0103]=8'h40;
            // 0104 EI(02) or DI(03)  ← ケース切替点
            mem[16'h0104]=op0104;
            // 0105 LDWI A,#0011
            mem[16'h0105]=8'h21; mem[16'h0106]=8'h00; mem[16'h0107]=8'h11; mem[16'h0108]=8'h00;
            // 0109 LDWI A,#0022 (受理されれば実行されない / 非受理なら実行される)
            mem[16'h0109]=8'h21; mem[16'h010A]=8'h00; mem[16'h010B]=8'h22; mem[16'h010C]=8'h00;
            // 010D HALT (非受理時のフォールバック停止)
            mem[16'h010D]=8'h01;
            // IRQ1ハンドラ @0300 : 0300 LDWI B,#00AA / 0304 HALT
            mem[16'h0300]=8'h21; mem[16'h0301]=8'h10; mem[16'h0302]=8'hAA; mem[16'h0303]=8'h00;
            mem[16'h0304]=8'h01;
        end
    endtask

    task chk_i(input [127:0] tag, input integer got, input integer exp);
        begin
            if (got !== exp) begin
                $display("FAIL[%0s] got=%0d exp=%0d", tag, got, exp); errors=errors+1;
            end else $display("PASS[%0s] =%0d", tag, got);
        end
    endtask

    task chk16(input [127:0] tag, input [15:0] got, input [15:0] exp);
        begin
            if (got !== exp) begin
                $display("FAIL[%0s] got=%04x exp=%04x", tag, got, exp); errors=errors+1;
            end else $display("PASS[%0s] =%04x", tag, got);
        end
    endtask

    // 1フェーズ実行: リセット→irq_driver→完走待ち
    task run_phase(input [7:0] op0104);
        integer g;
        begin
            load_program(op0104);
            ack_cnt = 0;
            irq_in  = 3'd0;
            rst_n   = 0;
            repeat(2) @(negedge clk);
            rst_n   = 1;

            fork
                begin : irq_driver
                    // PC>=0105(EI/DI実行後)で irq_in=1。維持して次S_IRQCHKで判定させる。
                    wait (dbg_pc == 16'h0105);
                    @(posedge clk); #1;
                    irq_in = 3'd1;   // timer IRQ
                    // 受理されハンドラ域に入るか、フォールバックHALTに達したら落とす
                    wait ((dbg_pc >= 16'h0300 && dbg_pc <= 16'h0305) || dbg_halt);
                    irq_in = 3'd0;
                end
            join_none

            begin : runloop
                g=0;
                while (!dbg_halt && g<600) begin @(posedge clk); #1; g=g+1; end
            end
            // irq_driver が残っていれば回収
            irq_in = 3'd0;
            #1;
        end
    endtask

    initial begin
        // ============ Phase 1: Case-EI (受理あり) ============
        $display("--- Phase1: Case-EI (0104=EI, 受理あり) ---");
        run_phase(8'h02);
        if (!dbg_halt) begin $display("FAIL[EI]: not halted @PC=%04x", dbg_pc); errors=errors+1; end
        // ★主眼: irq0_ack が【ちょうど1回】立つ★
        chk_i ("EI: ack_cnt==1", ack_cnt, 1);
        // ハンドラ到達の証拠 B=00AA / 受理は0109前(A=0011)
        chk16 ("EI: B(handler ran)=00AA", dbg_b, 16'h00AA);
        chk16 ("EI: A(irq before 0109)=0011", dbg_a, 16'h0011);
        // 受理後 IE=0
        if (dbg_flags[7] !== 1'b0) begin
            $display("FAIL[EI]: IE=%0d exp0", dbg_flags[7]); errors=errors+1;
        end else $display("PASS[EI]: IE=0 (受理後クリア)");

        // ============ Phase 2: Case-DI (受理なし) ============
        $display("--- Phase2: Case-DI (0104=DI, IE=0, 受理なし) ---");
        run_phase(8'h03);
        if (!dbg_halt) begin $display("FAIL[DI]: not halted @PC=%04x", dbg_pc); errors=errors+1; end
        // ★主眼: irq0_ack が【1回も立たない】★
        chk_i ("DI: ack_cnt==0", ack_cnt, 0);
        // 二重裏付け(設計メモ§5): ハンドラ未到達 B!=00AA
        if (dbg_b === 16'h00AA) begin
            $display("FAIL[DI]: B=00AA (ハンドラに入ってしまった=受理された)"); errors=errors+1;
        end else $display("PASS[DI]: B!=00AA (ハンドラ未到達=%04x)", dbg_b);
        // 0109 が実行され A=0022 になる(非受理で命令列が素通り)
        chk16 ("DI: A(0109 executed)=0022", dbg_a, 16'h0022);

        // ============ 総合判定 ============
        if (errors==0) $display("CPU_IRQ0ACK_TB: ALL PASS");
        else           $display("CPU_IRQ0ACK_TB: %0d FAIL", errors);
        $finish;
    end
endmodule
