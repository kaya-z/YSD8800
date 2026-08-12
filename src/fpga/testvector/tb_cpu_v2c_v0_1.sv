// ============================================================
//  tb_cpu_v2c_v0_1.sv   v0.1  (2026-07-09)
//  YSD8800 FPGA V2-c : C4分岐 / C5メモリ 外部観測等価検証TB
//   (+ V2-a/b を回帰として統合実行 = 計64ベクタ)
//
//  検証観点:
//   - 全ベクタ共通: A/B/X/FLAGS(下位8bit) を emu23 v1.09黄金と突合
//   - ★新観点A(C4分岐): dbg_pc(HALT時PC) も黄金PCと突合。
//       分岐先=次命令アドレス+rel16。taken/not-takenで最終PCが異なる配置。
//       レジスタA(taken=0xAAAA/not-taken=0x5555)との二重確認。
//   - ★新観点B(C5メモリ): STW/STBは gen側で「STW→(クリア)→LDW/LDB読戻し」
//       構造にしてあり、ストア値がレジスタに還元される。よってレジスタ突合で
//       ストア副作用を検証(emu無改修・論点5-b)。LDWはZ/N突合、LDB/STBはFLAGS不変。
//   - M-1(STWデータ下位ニブル)の回帰: STW_absB(データ=B)で下位ニブル実装を検証。
//
//  期待値 expected_v2c.hex : 1ベクタ5word (A, B, X, F, PC)
//  入力 v2c/<id>.hex        : プログラム+データ域preseed($0200〜)を$readmemhで一括ロード
//
//  ★メモリクリア範囲は 0x0000-0x02FF(=データ域まで)。
//    全65536クリアはIcarusで always_comb張り付き下の2巡目ハング(2026-07-08教訓)。
//    データ域$0200を使うため V2-a/bの0x01FFから0x02FFへ拡大。
// ============================================================
`timescale 1ns/1ps

import ysd8800_idec_pkg::*;

module tb_cpu_v2c_v0_1;
    logic        clk, rst_n;
    logic [15:0] mem_addr;
    logic [7:0]  mem_wdata, mem_rdata;
    logic        mem_rd, mem_wr, mem_ready;
    logic [2:0]  irq_in;
    logic [15:0] dbg_pc, dbg_a, dbg_b, dbg_x, dbg_sp, dbg_flags;
    logic        dbg_halt;

    integer errors = 0;

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
    // メモリ書込(STW/STB検証に必須): CPUのwrをメモリへ反映
    always_ff @(posedge clk) begin
        if (mem_wr) mem[mem_addr] <= mem_wdata;
    end

    initial clk = 0;
    always #5 clk = ~clk;

    localparam int NVEC = 64;
    string vname [0:NVEC-1];
    logic [15:0] exp_mem [0:NVEC*5-1];

    integer vi, cyc;
    logic [15:0] exp_a, exp_b, exp_x, exp_pc;
    logic [7:0]  exp_f;

    initial begin
        // ---- ベクタ名(gen veclist順に厳密一致) ----
        vname[0]="ADD_pos";   vname[1]="ADD_zero";  vname[2]="ADD_neg";
        vname[3]="SUB_pos";   vname[4]="SUB_zero";  vname[5]="SUB_neg";
        vname[6]="AND_zero";  vname[7]="AND_neg";
        vname[8]="OR_pos";    vname[9]="OR_neg";
        vname[10]="XOR_zero"; vname[11]="XOR_neg";
        vname[12]="NOT_neg";  vname[13]="NOT_zero";
        vname[14]="SHL_neg";  vname[15]="SHL_zero";
        vname[16]="SHR_pos";  vname[17]="SHR_zero";
        vname[18]="SAR_neg";  vname[19]="SAR_pos";
        vname[20]="ADDI_pos"; vname[21]="ADDI_zero";vname[22]="ADDI_neg";
        vname[23]="SUBI_pos"; vname[24]="SUBI_zero";vname[25]="SUBI_neg";
        vname[26]="ANDI_zero";vname[27]="ANDI_neg"; vname[28]="ANDI_pos";
        vname[29]="ORI_pos";  vname[30]="ORI_neg";
        vname[31]="XORI_zero";vname[32]="XORI_neg";
        vname[33]="CMP_eq";   vname[34]="CMP_lt";   vname[35]="CMP_gt";
        vname[36]="CMP_wrap";
        vname[37]="CMPI_eq";  vname[38]="CMPI_lt";  vname[39]="CMPI_gt";
        vname[40]="CMPI_wrap";
        // C4 分岐
        vname[41]="JMP_fwd";
        vname[42]="BEQ_taken"; vname[43]="BEQ_ntaken";
        vname[44]="BNE_taken"; vname[45]="BNE_ntaken";
        vname[46]="BLT_taken"; vname[47]="BLT_ntaken";
        vname[48]="BGE_taken"; vname[49]="BGE_ntaken";
        vname[50]="JMP_bwd";
        // C5 メモリ
        vname[51]="LDW_abs";  vname[52]="LDW_zero"; vname[53]="LDW_neg";
        vname[54]="LDW_rs";   vname[55]="LDW_xoff";
        vname[56]="STW_abs";  vname[57]="STW_absB"; vname[58]="STW_rd";
        vname[59]="STW_xoff";
        vname[60]="LDB_abs";  vname[61]="LDB_x";
        vname[62]="STB_abs";  vname[63]="STB_x";

        $readmemh("v2c/expected_v2c.hex", exp_mem);
        irq_in = 3'd0;

        for (vi = 0; vi < NVEC; vi = vi + 1) begin
            // データ域まで含めてクリア(0x0000-0x02FF)。全域はハング。
            for (int i=0;i<16'h0300;i=i+1) mem[i]=8'h00;
            load_prog(vi);

            exp_a  = exp_mem[vi*5+0];
            exp_b  = exp_mem[vi*5+1];
            exp_x  = exp_mem[vi*5+2];
            exp_f  = exp_mem[vi*5+3][7:0];
            exp_pc = exp_mem[vi*5+4];

            rst_n = 0;
            repeat(2) @(negedge clk);
            rst_n = 1;

            cyc = 0;
            while (!dbg_halt && cyc < 300) begin
                @(posedge clk); #1;
                cyc = cyc + 1;
            end

            if (!dbg_halt) begin
                $display("FAIL[%0d %s]: not halted (cyc=%0d)", vi, vname[vi], cyc);
                errors = errors + 1;
            end else begin
                if (dbg_a !== exp_a) begin
                    $display("FAIL[%0d %s]: A=%04x exp=%04x",
                             vi,vname[vi],dbg_a,exp_a); errors=errors+1; end
                if (dbg_b !== exp_b) begin
                    $display("FAIL[%0d %s]: B=%04x exp=%04x",
                             vi,vname[vi],dbg_b,exp_b); errors=errors+1; end
                if (dbg_x !== exp_x) begin
                    $display("FAIL[%0d %s]: X=%04x exp=%04x",
                             vi,vname[vi],dbg_x,exp_x); errors=errors+1; end
                if (dbg_flags[7:0] !== exp_f) begin
                    $display("FAIL[%0d %s]: F=%02x exp=%02x",
                             vi,vname[vi],dbg_flags[7:0],exp_f); errors=errors+1; end
                // ★新観点A: PC突合(分岐経路判定の主軸)
                if (dbg_pc !== exp_pc) begin
                    $display("FAIL[%0d %s]: PC=%04x exp=%04x",
                             vi,vname[vi],dbg_pc,exp_pc); errors=errors+1; end
            end
        end

        if (errors==0) $display("CPU_V2C_TB: ALL PASS (%0d vectors)", NVEC);
        else           $display("CPU_V2C_TB: %0d FAIL", errors);
        $finish;
    end

    // プログラム+preseedを $readmemh でロード(ファイル名はcaseで列挙)
    task load_prog(input integer idx);
        case (idx)
            0: $readmemh("v2c/ADD_pos.hex",mem);   1: $readmemh("v2c/ADD_zero.hex",mem);
            2: $readmemh("v2c/ADD_neg.hex",mem);   3: $readmemh("v2c/SUB_pos.hex",mem);
            4: $readmemh("v2c/SUB_zero.hex",mem);  5: $readmemh("v2c/SUB_neg.hex",mem);
            6: $readmemh("v2c/AND_zero.hex",mem);  7: $readmemh("v2c/AND_neg.hex",mem);
            8: $readmemh("v2c/OR_pos.hex",mem);    9: $readmemh("v2c/OR_neg.hex",mem);
            10:$readmemh("v2c/XOR_zero.hex",mem);  11:$readmemh("v2c/XOR_neg.hex",mem);
            12:$readmemh("v2c/NOT_neg.hex",mem);   13:$readmemh("v2c/NOT_zero.hex",mem);
            14:$readmemh("v2c/SHL_neg.hex",mem);   15:$readmemh("v2c/SHL_zero.hex",mem);
            16:$readmemh("v2c/SHR_pos.hex",mem);   17:$readmemh("v2c/SHR_zero.hex",mem);
            18:$readmemh("v2c/SAR_neg.hex",mem);   19:$readmemh("v2c/SAR_pos.hex",mem);
            20:$readmemh("v2c/ADDI_pos.hex",mem);  21:$readmemh("v2c/ADDI_zero.hex",mem);
            22:$readmemh("v2c/ADDI_neg.hex",mem);  23:$readmemh("v2c/SUBI_pos.hex",mem);
            24:$readmemh("v2c/SUBI_zero.hex",mem); 25:$readmemh("v2c/SUBI_neg.hex",mem);
            26:$readmemh("v2c/ANDI_zero.hex",mem); 27:$readmemh("v2c/ANDI_neg.hex",mem);
            28:$readmemh("v2c/ANDI_pos.hex",mem);  29:$readmemh("v2c/ORI_pos.hex",mem);
            30:$readmemh("v2c/ORI_neg.hex",mem);   31:$readmemh("v2c/XORI_zero.hex",mem);
            32:$readmemh("v2c/XORI_neg.hex",mem);
            33:$readmemh("v2c/CMP_eq.hex",mem);    34:$readmemh("v2c/CMP_lt.hex",mem);
            35:$readmemh("v2c/CMP_gt.hex",mem);    36:$readmemh("v2c/CMP_wrap.hex",mem);
            37:$readmemh("v2c/CMPI_eq.hex",mem);   38:$readmemh("v2c/CMPI_lt.hex",mem);
            39:$readmemh("v2c/CMPI_gt.hex",mem);   40:$readmemh("v2c/CMPI_wrap.hex",mem);
            // C4 分岐
            41:$readmemh("v2c/JMP_fwd.hex",mem);
            42:$readmemh("v2c/BEQ_taken.hex",mem); 43:$readmemh("v2c/BEQ_ntaken.hex",mem);
            44:$readmemh("v2c/BNE_taken.hex",mem); 45:$readmemh("v2c/BNE_ntaken.hex",mem);
            46:$readmemh("v2c/BLT_taken.hex",mem); 47:$readmemh("v2c/BLT_ntaken.hex",mem);
            48:$readmemh("v2c/BGE_taken.hex",mem); 49:$readmemh("v2c/BGE_ntaken.hex",mem);
            50:$readmemh("v2c/JMP_bwd.hex",mem);
            // C5 メモリ
            51:$readmemh("v2c/LDW_abs.hex",mem);   52:$readmemh("v2c/LDW_zero.hex",mem);
            53:$readmemh("v2c/LDW_neg.hex",mem);   54:$readmemh("v2c/LDW_rs.hex",mem);
            55:$readmemh("v2c/LDW_xoff.hex",mem);
            56:$readmemh("v2c/STW_abs.hex",mem);   57:$readmemh("v2c/STW_absB.hex",mem);
            58:$readmemh("v2c/STW_rd.hex",mem);    59:$readmemh("v2c/STW_xoff.hex",mem);
            60:$readmemh("v2c/LDB_abs.hex",mem);   61:$readmemh("v2c/LDB_x.hex",mem);
            62:$readmemh("v2c/STB_abs.hex",mem);   63:$readmemh("v2c/STB_x.hex",mem);
        endcase
    endtask
endmodule
