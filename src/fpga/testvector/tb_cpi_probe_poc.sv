// tb_cpi_probe_poc.sv  v0.1 (2026-07-11)  ★_poc(KY38: 実験用・本番TBと別名)
//  目的: 各命令の「実RTLサイクル数(CPI)」を理想メモリ前提で機械実測する。
//    emu23はCPI=1固定ゆえサイクル源にできない(KY: サイクル出典はRTL FSM)。
//    測定法: リセット完了(最初のS_FETCH到達)から、対象命令の実行完了
//            (S_IRQCHK 再到達 = 次命令フェッチ直前)までのクロック数を数える。
//    各プログラムは「対象命令1個 + HALT」。ただしCPIは
//      「S_FETCH開始 → 次S_IRQCHK」までの状態数で定義。
//    dbg_stateを観測できないため、ここでは
//      「リセット後の総サイクル数 - 固定オーバーヘッド」で個別CPIを逆算せず、
//      代わりに『命令1個だけ』を置き、HALTに到達するまでのサイクルから
//      HALT自身の1と、共通のS_IRQCHK往復を補正して求める。
//
//  ★簡明化のため本_pocでは「対象命令+HALT」の2命令をロードし、
//    リセット完了〜HALT到達までの実サイクル総数(raw)を出力する。
//    CPI(対象命令) = raw - CPI(HALT) - RESET分。
//    RESET分(S_RESET_LO/HI=2) と HALT到達コスト は基準命令(NOPのみ)で較正する。
//    → NOP+HALT の raw と、対象+HALT の raw の差分で対象命令の純CPIを出す。
module tb_cpi_probe_poc;
    logic        clk, rst_n;
    logic [15:0] mem_addr;
    logic [7:0]  mem_wdata, mem_rdata;
    logic        mem_rd, mem_wr, mem_ready;
    logic [2:0]  irq_in;
    logic [15:0] dbg_pc, dbg_a, dbg_b, dbg_x, dbg_sp, dbg_flags;
    logic        dbg_halt;

    ysd8800_cpu_v0_1 dut (
        .clk(clk), .rst_n(rst_n),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata),
        .mem_rd(mem_rd), .mem_wr(mem_wr), .mem_ready(mem_ready),
        .irq_in(irq_in),
        .dbg_pc(dbg_pc), .dbg_a(dbg_a), .dbg_b(dbg_b), .dbg_x(dbg_x),
        .dbg_sp(dbg_sp), .dbg_flags(dbg_flags), .dbg_halt(dbg_halt)
    );

    logic [7:0] mem [0:65535];
    assign mem_ready = 1'b1;                 // ★理想メモリ(待ちゼロ)
    always_comb mem_rdata = mem[mem_addr];
    always_ff @(posedge clk) begin
        if (mem_wr) mem[mem_addr] <= mem_wdata;
    end

    initial clk = 0;
    always #5 clk = ~clk;

    localparam int NP = 20;
    string pname [0:NP-1];
    integer praw [0:NP-1];
    integer vi, cyc;

    // 1プログラムを実行しHALT到達までの総サイクルを返す
    task run_one(input integer idx, output integer raw);
        integer c;
        begin
            for (int i=0;i<16'h0400;i=i+1) mem[i]=8'h00;
            load_prog(idx);
            rst_n = 0; repeat(2) @(negedge clk); rst_n = 1;
            c = 0;
            while (!dbg_halt && c < 300) begin
                @(posedge clk); #1; c = c + 1;
            end
            raw = c;
        end
    endtask

    initial begin
        irq_in = 3'd0;
        // プログラム定義: 各々「対象命令 + HALT」。entry=$0100。
        //  ★較正基準: idx0 = NOP+HALT。他命令のCPI = raw(対象) - raw(NOP).
        //    (NOPはS_OPFETCHで即S_IRQCHK。対象命令もNOPを置換した差分が純CPI差)
        pname[0]="NOP_base";     // NOP; HALT
        pname[1]="LDWI";         // LDW A,#imm; HALT
        pname[2]="ALU_rr";       // ADD A,B; HALT (要 A,B事前無, 単純加算)
        pname[3]="ALU_imm";      // ADDI A,#imm; HALT
        pname[4]="CMP_rr";       // CMP A,B; HALT
        pname[5]="MOV_rr";       // MOV A,B; HALT
        pname[6]="JMP";          // JMP +0; HALT (分岐成立)
        pname[7]="LDW_abs";      // LDW A,[imm]; HALT
        pname[8]="STW_abs";      // STW A,[imm]; HALT
        pname[9]="LDB_abs";      // LDB A,[imm]; HALT
        pname[10]="STB_abs";     // STB A,[imm]; HALT
        pname[11]="PUSH";        // PUSH A; HALT
        pname[12]="POP";         // POP A; HALT
        pname[13]="EI";          // EI; HALT
        pname[14]="DI";          // DI; HALT
        pname[15]="JSR";         // JSR next; (next=HALT)
        pname[16]="RET_manual";  // (SP init; A=halt; PUSH A; RET) → HALT
        pname[17]="LDB_x";       // LDW X,#imm; LDB A,[X]; HALT
        pname[18]="STB_x";       // LDW X,#imm; STB A,[X]; HALT
        pname[19]="LDW_rs";      // LDW X,#imm; LDW A,[X]; HALT

        $display("# CPI probe (ideal mem). idx name raw_cycles");
        for (vi=0; vi<NP; vi=vi+1) begin
            run_one(vi, praw[vi]);
            $display("%0d %s raw=%0d", vi, pname[vi], praw[vi]);
        end
        $display("# ---- 純CPI = raw - raw(NOP_base) + CPI(NOP) ----");
        $display("# 較正: NOP_base raw=%0d を基準に各命令の純サイクルを算出", praw[0]);
        $finish;
    end

    // 各プログラム: entry=$0100固定。リセットベクタ$0000→$0100。
    task load_prog(input integer idx);
        begin
            // 共通: リセットベクタ $0000 -> $0100
            mem[0]=8'h00; mem[1]=8'h01;
            case (idx)
                0: begin mem['h100]=8'h00; mem['h101]=8'h01; end // NOP;HALT
                1: begin // LDW A,#0x1234 = 21 00 34 12 ; HALT
                   mem['h100]=8'h21; mem['h101]=8'h00; mem['h102]=8'h34; mem['h103]=8'h12;
                   mem['h104]=8'h01; end
                2: begin // ADD A,B = 40 01 ; HALT  (rd=A上位0, rs=B下位1)
                   mem['h100]=8'h40; mem['h101]=8'h01; mem['h102]=8'h01; end
                3: begin // ADDI A,#0x0005 = 41 00 05 00 ; HALT
                   mem['h100]=8'h41; mem['h101]=8'h00; mem['h102]=8'h05; mem['h103]=8'h00;
                   mem['h104]=8'h01; end
                4: begin // CMP A,B = 44 01 ; HALT
                   mem['h100]=8'h44; mem['h101]=8'h01; mem['h102]=8'h01; end
                5: begin // MOV A,B = 20 01 ; HALT  (rd=A上位0,rs=B下位1)
                   mem['h100]=8'h20; mem['h101]=8'h01; mem['h102]=8'h01; end
                6: begin // JMP +0 = 60 00 00 ; HALT  (分岐先=次命令=HALT)
                   mem['h100]=8'h60; mem['h101]=8'h00; mem['h102]=8'h00; mem['h103]=8'h01; end
                7: begin // LDW A,[0x0200] = 22 00 00 02 ; HALT
                   mem['h100]=8'h22; mem['h101]=8'h00; mem['h102]=8'h00; mem['h103]=8'h02;
                   mem['h104]=8'h01; mem['h200]=8'h78; mem['h201]=8'h56; end
                8: begin // STW A,[0x0200] = 23 00 00 02 ; HALT
                   mem['h100]=8'h23; mem['h101]=8'h00; mem['h102]=8'h00; mem['h103]=8'h02;
                   mem['h104]=8'h01; end
                9: begin // LDB A,[0x0200] = 1F 10 00 02 ; HALT
                   mem['h100]=8'h1F; mem['h101]=8'h10; mem['h102]=8'h00; mem['h103]=8'h02;
                   mem['h104]=8'h01; mem['h200]=8'hA5; end
                10: begin // STB A,[0x0200] = 1F 14 00 02 ; HALT
                   mem['h100]=8'h1F; mem['h101]=8'h14; mem['h102]=8'h00; mem['h103]=8'h02;
                   mem['h104]=8'h01; end
                11: begin // PUSH A = 1F 00 ; HALT
                   mem['h100]=8'h1F; mem['h101]=8'h00; mem['h102]=8'h01; end
                12: begin // POP A = 1F 03 ; HALT
                   mem['h100]=8'h1F; mem['h101]=8'h03; mem['h102]=8'h01; end
                13: begin // EI = 02 ; HALT
                   mem['h100]=8'h02; mem['h101]=8'h01; end
                14: begin // DI = 03 ; HALT
                   mem['h100]=8'h03; mem['h101]=8'h01; end
                15: begin // JSR 0x0104 = 68 04 01 ; (0x0103 fallback HALT) 0x0104:HALT
                   mem['h100]=8'h68; mem['h101]=8'h04; mem['h102]=8'h01; mem['h103]=8'h01;
                   mem['h104]=8'h01; end
                16: begin // SP init; A=halt(0x010D); PUSH A; RET ; halt@0x010D:HALT
                   // LDW SP,#0xFC7E = 21 30 7E FC (4B) @0x100
                   mem['h100]=8'h21; mem['h101]=8'h30; mem['h102]=8'h7E; mem['h103]=8'hFC;
                   // LDW A,#0x010D = 21 00 0D 01 (4B) @0x104
                   mem['h104]=8'h21; mem['h105]=8'h00; mem['h106]=8'h0D; mem['h107]=8'h01;
                   // PUSH A = 1F 00 (2B) @0x108
                   mem['h108]=8'h1F; mem['h109]=8'h00;
                   // RET = 69 (1B) @0x10A
                   mem['h10A]=8'h69;
                   // fallback @0x10B,0x10C
                   mem['h10B]=8'h01; mem['h10C]=8'h01;
                   // halt target @0x10D
                   mem['h10D]=8'h01; end
                17: begin // LDW X,#0x0200; LDB A,[X]; HALT
                   mem['h100]=8'h21; mem['h101]=8'h20; mem['h102]=8'h00; mem['h103]=8'h02;
                   mem['h104]=8'h1F; mem['h105]=8'h11; // LDB A,[X] = 1F 11
                   mem['h106]=8'h01; mem['h200]=8'h5A; end
                18: begin // LDW X,#0x0200; STB A,[X]; HALT
                   mem['h100]=8'h21; mem['h101]=8'h20; mem['h102]=8'h00; mem['h103]=8'h02;
                   mem['h104]=8'h1F; mem['h105]=8'h15; // STB A,[X] = 1F 15
                   mem['h106]=8'h01; end
                19: begin // LDW X,#0x0200; LDW A,[X]; HALT  (0x24 mem_rr rd=A hi/rs=X lo)
                   mem['h100]=8'h21; mem['h101]=8'h20; mem['h102]=8'h00; mem['h103]=8'h02;
                   mem['h104]=8'h24; mem['h105]=8'h02; // LDW A,[X] = 24 02
                   mem['h106]=8'h01; mem['h200]=8'h78; mem['h201]=8'h56; end
            endcase
        end
    endtask
endmodule
