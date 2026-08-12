// ============================================================
//  tb_cpu_v2d_v0_1.sv   v0.1  (2026-07-10)
//  YSD8800 FPGA V2-d : C6スタック / C7サブルーチン 外部観測等価検証TB
//   (+ V2-a/b/c を回帰として統合実行 = 既存64 + 新規11 = 計75ベクタ)
//
//  検証観点:
//   - 全ベクタ共通: A/B/X/FLAGS(下位8bit) を emu23 v1.09黄金と突合
//   - PC突合(C4以降): dbg_pc(HALT時PC) も黄金PCと突合
//   - ★V2-d新観点(C6/C7): SP突合を追加。ただし stk/sub グループのみ。
//       既存64(leg/br/mem)は SP除外継続(HANDOVER_CHAT77 §2 Q4方針)。
//       C6: PUSH/POP対称でSP復帰、SP_DECRでSP-=2 を dbg_sp と黄金SP突合。
//       C7: JSR/RET対称でSP復帰、JSR_SPmoveでJSRのSP-=2(戻りPC push)を突合。
//   - スタック整合はgen側で PUSH→POP読み戻し+レジスタ突合に還元(emu無改修)。
//   - ★SP初期値対策: 各V2-dベクタ先頭に LDW SP,#0xFC7E を gen が挿入済。
//       RTLリセットSP(0x0000)との差を無効化し、SP突合を成立させる。
//
//  期待値 expected_v2d.hex : 1ベクタ6word (A, B, X, F, PC, SP)  ★6word化
//  グループ veclist_v2d.txt : "id grp" 形式。grp∈{leg,br,mem,stk,sub}。
//    SP突合対象= stk/sub。TBは grp を読み SP突合可否を判定。
//  入力 v2d/<id>.hex        : プログラム+データ域preseed($0200〜)を$readmemhで一括ロード
//
//  ★メモリクリア範囲は 0x0000-0x02FF(=データ域まで)。
//    全65536クリアはIcarusで always_comb張り付き下の2巡目ハング(2026-07-08教訓)。
//    ★スタック域は $FC7E 近傍(高位)。preseed不要・PUSHが書くのみ。
//      クリア範囲外だが、各ベクタがSPを明示初期化し自分でPUSHするため
//      初期化残渣の影響なし(POPは自分がPUSHした値のみ読む)。
// ============================================================
`timescale 1ns/1ps

import ysd8800_idec_pkg::*;

module tb_cpu_v2d_v0_1;
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

    localparam int NVEC = 75;
    string vname [0:NVEC-1];
    string vgrp  [0:NVEC-1];              // ★grp(SP突合判定用): stk/subのみSP突合
    logic [15:0] exp_mem [0:NVEC*6-1];    // ★6word化 (A,B,X,F,PC,SP)

    integer vi, cyc;
    logic [15:0] exp_a, exp_b, exp_x, exp_pc, exp_sp;
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
        // ★V2-d C6 スタック (index 64-70)
        vname[64]="PUSH_POP_A"; vname[65]="PUSH_POP_B"; vname[66]="PUSH_POP_X";
        vname[67]="CROSS_AB";   vname[68]="SP_DECR";    vname[69]="SP_INCR";
        vname[70]="MULTI_PUSH";
        // ★V2-d C7 サブルーチン (index 71-74)
        vname[71]="JSR_RET";    vname[72]="JSR_SPmove";
        vname[73]="NEST_JSR";   vname[74]="RET_only_chk";

        // ★grp設定: 既存64=SP除外, 新規11(stk/sub)=SP突合対象
        for (int i=0;i<64;i=i+1) vgrp[i]="old";   // leg/br/mem(SP除外)を一括old扱い
        for (int i=64;i<71;i=i+1) vgrp[i]="stk";  // C6スタック
        for (int i=71;i<75;i=i+1) vgrp[i]="sub";  // C7サブルーチン

        $readmemh("v2d/expected_v2d.hex", exp_mem);
        irq_in = 3'd0;

        for (vi = 0; vi < NVEC; vi = vi + 1) begin
            // データ域まで含めてクリア(0x0000-0x02FF)。全域はハング。
            for (int i=0;i<16'h0300;i=i+1) mem[i]=8'h00;
            load_prog(vi);

            exp_a  = exp_mem[vi*6+0];
            exp_b  = exp_mem[vi*6+1];
            exp_x  = exp_mem[vi*6+2];
            exp_f  = exp_mem[vi*6+3][7:0];
            exp_pc = exp_mem[vi*6+4];
            exp_sp = exp_mem[vi*6+5];

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
                // ★V2-d新観点: SP突合(stk/subグループのみ・既存64はSP除外)
                if (vgrp[vi]=="stk" || vgrp[vi]=="sub") begin
                    if (dbg_sp !== exp_sp) begin
                        $display("FAIL[%0d %s]: SP=%04x exp=%04x",
                                 vi,vname[vi],dbg_sp,exp_sp); errors=errors+1; end
                end
            end
        end

        if (errors==0) $display("CPU_V2D_TB: ALL PASS (%0d vectors)", NVEC);
        else           $display("CPU_V2D_TB: %0d FAIL", errors);
        $finish;
    end

    // プログラム+preseedを $readmemh でロード(ファイル名はcaseで列挙)
    task load_prog(input integer idx);
        case (idx)
            0: $readmemh("v2d/ADD_pos.hex",mem);   1: $readmemh("v2d/ADD_zero.hex",mem);
            2: $readmemh("v2d/ADD_neg.hex",mem);   3: $readmemh("v2d/SUB_pos.hex",mem);
            4: $readmemh("v2d/SUB_zero.hex",mem);  5: $readmemh("v2d/SUB_neg.hex",mem);
            6: $readmemh("v2d/AND_zero.hex",mem);  7: $readmemh("v2d/AND_neg.hex",mem);
            8: $readmemh("v2d/OR_pos.hex",mem);    9: $readmemh("v2d/OR_neg.hex",mem);
            10:$readmemh("v2d/XOR_zero.hex",mem);  11:$readmemh("v2d/XOR_neg.hex",mem);
            12:$readmemh("v2d/NOT_neg.hex",mem);   13:$readmemh("v2d/NOT_zero.hex",mem);
            14:$readmemh("v2d/SHL_neg.hex",mem);   15:$readmemh("v2d/SHL_zero.hex",mem);
            16:$readmemh("v2d/SHR_pos.hex",mem);   17:$readmemh("v2d/SHR_zero.hex",mem);
            18:$readmemh("v2d/SAR_neg.hex",mem);   19:$readmemh("v2d/SAR_pos.hex",mem);
            20:$readmemh("v2d/ADDI_pos.hex",mem);  21:$readmemh("v2d/ADDI_zero.hex",mem);
            22:$readmemh("v2d/ADDI_neg.hex",mem);  23:$readmemh("v2d/SUBI_pos.hex",mem);
            24:$readmemh("v2d/SUBI_zero.hex",mem); 25:$readmemh("v2d/SUBI_neg.hex",mem);
            26:$readmemh("v2d/ANDI_zero.hex",mem); 27:$readmemh("v2d/ANDI_neg.hex",mem);
            28:$readmemh("v2d/ANDI_pos.hex",mem);  29:$readmemh("v2d/ORI_pos.hex",mem);
            30:$readmemh("v2d/ORI_neg.hex",mem);   31:$readmemh("v2d/XORI_zero.hex",mem);
            32:$readmemh("v2d/XORI_neg.hex",mem);
            33:$readmemh("v2d/CMP_eq.hex",mem);    34:$readmemh("v2d/CMP_lt.hex",mem);
            35:$readmemh("v2d/CMP_gt.hex",mem);    36:$readmemh("v2d/CMP_wrap.hex",mem);
            37:$readmemh("v2d/CMPI_eq.hex",mem);   38:$readmemh("v2d/CMPI_lt.hex",mem);
            39:$readmemh("v2d/CMPI_gt.hex",mem);   40:$readmemh("v2d/CMPI_wrap.hex",mem);
            // C4 分岐
            41:$readmemh("v2d/JMP_fwd.hex",mem);
            42:$readmemh("v2d/BEQ_taken.hex",mem); 43:$readmemh("v2d/BEQ_ntaken.hex",mem);
            44:$readmemh("v2d/BNE_taken.hex",mem); 45:$readmemh("v2d/BNE_ntaken.hex",mem);
            46:$readmemh("v2d/BLT_taken.hex",mem); 47:$readmemh("v2d/BLT_ntaken.hex",mem);
            48:$readmemh("v2d/BGE_taken.hex",mem); 49:$readmemh("v2d/BGE_ntaken.hex",mem);
            50:$readmemh("v2d/JMP_bwd.hex",mem);
            // C5 メモリ
            51:$readmemh("v2d/LDW_abs.hex",mem);   52:$readmemh("v2d/LDW_zero.hex",mem);
            53:$readmemh("v2d/LDW_neg.hex",mem);   54:$readmemh("v2d/LDW_rs.hex",mem);
            55:$readmemh("v2d/LDW_xoff.hex",mem);
            56:$readmemh("v2d/STW_abs.hex",mem);   57:$readmemh("v2d/STW_absB.hex",mem);
            58:$readmemh("v2d/STW_rd.hex",mem);    59:$readmemh("v2d/STW_xoff.hex",mem);
            60:$readmemh("v2d/LDB_abs.hex",mem);   61:$readmemh("v2d/LDB_x.hex",mem);
            62:$readmemh("v2d/STB_abs.hex",mem);   63:$readmemh("v2d/STB_x.hex",mem);
            // ★V2-d C6 スタック
            64:$readmemh("v2d/PUSH_POP_A.hex",mem); 65:$readmemh("v2d/PUSH_POP_B.hex",mem);
            66:$readmemh("v2d/PUSH_POP_X.hex",mem); 67:$readmemh("v2d/CROSS_AB.hex",mem);
            68:$readmemh("v2d/SP_DECR.hex",mem);    69:$readmemh("v2d/SP_INCR.hex",mem);
            70:$readmemh("v2d/MULTI_PUSH.hex",mem);
            // ★V2-d C7 サブルーチン
            71:$readmemh("v2d/JSR_RET.hex",mem);    72:$readmemh("v2d/JSR_SPmove.hex",mem);
            73:$readmemh("v2d/NEST_JSR.hex",mem);   74:$readmemh("v2d/RET_only_chk.hex",mem);
        endcase
    endtask
endmodule
