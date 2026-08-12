// ============================================================
//  ysd8800_regfile_v0_1.sv   v0.1  (2026-06-30)
//  YSD8800 FPGA V1 CPUコア : レジスタファイル
//
//  設計根拠: fpga_v1_cpucore_design_v1_1.md §3
//  黄金リファレンス: emu23 v1.09 get_reg_ptr() L1104-1112
//      case 0:A 1:B 2:X 3:SP / default:NULL
//      → rD/rS で指定可能なのは 0-3 の4本のみ。
//        4(PC)/5(FLAGS) は NULL = オペランド指定不可 (no-op)。
//
//  本モジュールの方針:
//   - レジスタは物理的に6本(A/B/X/SP/PC/FLAGS)保持。
//   - 汎用ライトポート(we_gp/waddr_gp/wdata_gp)は rD 指定の書込用。
//     waddr_gp ∈ {4,5} のときは内部で we を無効化(no-op)。
//     [本日KY最重要] デコーダ側でも抑止するが、ここでも二重に担保。
//   - PC/FLAGS は専用ライトポートでのみ更新
//     (分岐/FETCH/割込受理/IRET/set_zn)。
//   - 読出ポートは rD/rS 用の2本。raddr ∈ {4,5} のときは
//     0x0000 を返す(emu23の NULL 相当。読み手側 if(rd&&rs) で
//     破棄されるため値は副作用に影響しないが、定義として0)。
//
//  レジスタ番号(rD/rS フィールド値)とインデックスの対応:
//     0=A 1=B 2=X 3=SP 4=PC 5=FLAGS
// ============================================================
`timescale 1ns/1ps

module ysd8800_regfile_v0_1 (
    input  logic        clk,
    input  logic        rst_n,

    // --- 読出ポート (rD/rS デコード結果) ---
    input  logic [3:0]  raddr_d,    // rD フィールド
    input  logic [3:0]  raddr_s,    // rS フィールド
    output logic [15:0] rdata_d,    // rD の現在値 (4/5指定時は0)
    output logic [15:0] rdata_s,    // rS の現在値 (4/5指定時は0)

    // --- 汎用ライトポート (rD への書込: MOV/ALU/LDW結果) ---
    input  logic        we_gp,      // 汎用ライトイネーブル
    input  logic [3:0]  waddr_gp,   // 書込先 (= rD)。4/5は内部で抑止
    input  logic [15:0] wdata_gp,

    // --- PC 専用ポート ---
    input  logic        we_pc,
    input  logic [15:0] wdata_pc,
    output logic [15:0] pc_out,

    // --- SP 専用ポート (PUSH/POP/割込/JSR/RET のSP増減用) ---
    input  logic        we_sp,
    input  logic [15:0] wdata_sp,
    output logic [15:0] sp_out,

    // --- FLAGS 専用ポート (set_zn / 割込受理(IE=0) / IRET復元) ---
    input  logic        we_flags,
    input  logic [15:0] wdata_flags,
    output logic [15:0] flags_out,

    // --- A/B/X の直接観測 (PUSH/POP・割込・トレース突合用) ---
    output logic [15:0] a_out,
    output logic [15:0] b_out,
    output logic [15:0] x_out
);

    // レジスタ実体
    logic [15:0] reg_a, reg_b, reg_x, reg_sp, reg_pc, reg_flags;

    // ----- 汎用ライトの有効判定 (本日KY最重要) -----
    // waddr_gp が 0-3 のときのみ汎用ライトを通す。
    // 4(PC)/5(FLAGS) は emu23 get_reg_ptr=NULL = no-op に合わせ抑止。
    logic gp_addr_valid;
    always_comb begin
        gp_addr_valid = (waddr_gp == 4'd0) || (waddr_gp == 4'd1) ||
                        (waddr_gp == 4'd2) || (waddr_gp == 4'd3);
    end

    logic gp_we_a, gp_we_b, gp_we_x, gp_we_sp;
    always_comb begin
        gp_we_a  = we_gp && gp_addr_valid && (waddr_gp == 4'd0);
        gp_we_b  = we_gp && gp_addr_valid && (waddr_gp == 4'd1);
        gp_we_x  = we_gp && gp_addr_valid && (waddr_gp == 4'd2);
        gp_we_sp = we_gp && gp_addr_valid && (waddr_gp == 4'd3);
    end

    // ----- 同期書込 -----
    // 優先順位: 専用ポート(PC/SP/FLAGS) と 汎用ポートは
    //   同一レジスタ(SP)へ同時要求されない前提(FSMが排他制御)。
    //   念のため SP は専用ポートを優先する。
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_a     <= 16'h0000;
            reg_b     <= 16'h0000;
            reg_x     <= 16'h0000;
            reg_sp    <= 16'h0000;
            reg_pc    <= 16'h0000;
            reg_flags <= 16'h0000;
        end else begin
            // A
            if (gp_we_a)  reg_a <= wdata_gp;
            // B
            if (gp_we_b)  reg_b <= wdata_gp;
            // X
            if (gp_we_x)  reg_x <= wdata_gp;
            // SP : 専用ポート優先、無ければ汎用
            if (we_sp)        reg_sp <= wdata_sp;
            else if (gp_we_sp) reg_sp <= wdata_gp;
            // PC : 専用ポートのみ
            if (we_pc)        reg_pc <= wdata_pc;
            // FLAGS : 専用ポートのみ
            if (we_flags)     reg_flags <= wdata_flags;
        end
    end

    // ----- 読出 (組合せ) -----
    // raddr が 4/5 のときは 0 を返す (emu23 NULL 相当)。
    function automatic [15:0] read_reg(input [3:0] addr);
        case (addr)
            4'd0: read_reg = reg_a;
            4'd1: read_reg = reg_b;
            4'd2: read_reg = reg_x;
            4'd3: read_reg = reg_sp;
            default: read_reg = 16'h0000; // 4/5 含む全て
        endcase
    endfunction

    always_comb begin
        rdata_d = read_reg(raddr_d);
        rdata_s = read_reg(raddr_s);
    end

    // ----- 専用観測出力 -----
    always_comb begin
        pc_out    = reg_pc;
        sp_out    = reg_sp;
        flags_out = reg_flags;
        a_out     = reg_a;
        b_out     = reg_b;
        x_out     = reg_x;
    end

endmodule
