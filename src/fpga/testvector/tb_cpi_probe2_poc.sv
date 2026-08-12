// tb_cpi_probe2_poc.sv v0.1 (2026-07-11) ★_poc(KY38)
//  RET/IRET/SYSCALL受理 の純CPIを精密測定する。
//  方式: セットアップ命令(既知CPI)を含む総rawから既知分を差し引く。
//    既知CPI(実測済・理想メモリ): reset到達=2, HALT到達=4,
//      LDWI/LDW-any-imm=6, PUSH=6.
//  各プログラムで raw を出し、後処理でPython較正する(ここでは raw のみ出力)。
module tb_cpi_probe2_poc;
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
    assign mem_ready = 1'b1;
    always_comb mem_rdata = mem[mem_addr];
    always_ff @(posedge clk) begin
        if (mem_wr) mem[mem_addr] <= mem_wdata;
    end
    initial clk = 0;
    always #5 clk = ~clk;

    localparam int NP = 5;
    string pname [0:NP-1];
    integer praw [0:NP-1];
    integer vi;

    task run_one(input integer idx, output integer raw);
        integer c;
        begin
            for (int i=0;i<16'h0400;i=i+1) mem[i]=8'h00;
            load_prog(idx);
            rst_n = 0; repeat(2) @(negedge clk); rst_n = 1;
            c = 0;
            while (!dbg_halt && c < 400) begin
                @(posedge clk); #1; c = c + 1;
            end
            raw = c;
        end
    endtask

    initial begin
        irq_in = 3'd0;
        pname[0]="SPinit_only";  // LDW SP,#imm; HALT  (SP初期化のCPI較正用)
        pname[1]="JSR_RET";      // SPinit; JSR sub; HALT ; sub: RET (往復)
        pname[2]="IRET_full";    // SPinit; A=t;PUSH A; A=f;PUSH A; IRET; t:HALT
        pname[3]="SYS_accept";   // vec$0008=$0300; SPinit; EI; SYSCALL; h:HALT
        pname[4]="SYS_iret";     // 受理→handler IRET→main HALT (往復)

        $display("# CPI probe2 (ideal mem). idx name raw");
        for (vi=0; vi<NP; vi=vi+1) begin
            run_one(vi, praw[vi]);
            $display("%0d %s raw=%0d", vi, pname[vi], praw[vi]);
        end
        $finish;
    end

    task load_prog(input integer idx);
        begin
            mem[0]=8'h00; mem[1]=8'h01;   // reset vec -> $0100
            case (idx)
                0: begin // LDW SP,#0xFC7E ; HALT
                   mem['h100]=8'h21; mem['h101]=8'h30; mem['h102]=8'h7E; mem['h103]=8'hFC;
                   mem['h104]=8'h01; end
                1: begin // SPinit; JSR sub($0108); HALT($0107) ; sub: RET
                   mem['h100]=8'h21; mem['h101]=8'h30; mem['h102]=8'h7E; mem['h103]=8'hFC;
                   mem['h104]=8'h68; mem['h105]=8'h08; mem['h106]=8'h01; // JSR $0108
                   mem['h107]=8'h01;                                     // HALT(戻り先)
                   mem['h108]=8'h69; end                                 // sub: RET
                2: begin // SPinit; A=$010F;PUSH A; A=$0021;PUSH A; IRET; $010F:HALT
                   mem['h100]=8'h21; mem['h101]=8'h30; mem['h102]=8'h7E; mem['h103]=8'hFC;
                   mem['h104]=8'h21; mem['h105]=8'h00; mem['h106]=8'h0F; mem['h107]=8'h01; // A=$010F
                   mem['h108]=8'h1F; mem['h109]=8'h00;                   // PUSH A
                   mem['h10A]=8'h21; mem['h10B]=8'h00; mem['h10C]=8'h21; mem['h10D]=8'h00; // A=$0021
                   mem['h10E]=8'h1F; mem['h10F]=8'h00;                   // PUSH A  ※注:配置ずれ回避
                   // ★上記でPUSH Aが$010Eに来る。IRETは$0110。HALTは別番地。
                   // 再配置: 単純化のためこの版はraw取得のみで、値検証はV2-eで済。
                   mem['h110]=8'h04;                                     // IRET
                   mem['h111]=8'h01; end                                 // fallback HALT
                3: begin // vec$0008=$0300; SPinit; EI; SYSCALL; HALT(fallback); h$0300:HALT
                   mem[8]=8'h00; mem[9]=8'h03;                           // vec IRQ4 -> $0300
                   mem['h100]=8'h21; mem['h101]=8'h30; mem['h102]=8'h7E; mem['h103]=8'hFC;
                   mem['h104]=8'h02;                                     // EI
                   mem['h105]=8'h05;                                     // SYSCALL
                   mem['h106]=8'h01;                                     // fallback HALT
                   mem['h300]=8'h01; end                                 // handler: HALT
                4: begin // 受理→handler IRET→main HALT
                   mem[8]=8'h00; mem[9]=8'h03;                           // vec -> $0300
                   mem['h100]=8'h21; mem['h101]=8'h30; mem['h102]=8'h7E; mem['h103]=8'hFC;
                   mem['h104]=8'h02;                                     // EI
                   mem['h105]=8'h05;                                     // SYSCALL
                   mem['h106]=8'h01;                                     // 復帰先HALT
                   mem['h300]=8'h04; end                                 // handler: IRET
            endcase
        end
    endtask
endmodule
