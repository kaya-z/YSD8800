// ============================================================
//  ysd8800_decoder_v0_1.sv   v0.1  (2026-06-30)
//  YSD8800 FPGA V1 CPUコア : 命令デコーダ (案A: 0x1Fサブop正規化)
//
//  設計根拠:
//   - fpga_v1_cpucore_design_v1_1.md §4.3(フラグ更新)/§5.3(命令分類)
//   - emu23 v1.09 instr_size() L990-1069 (命令長)
//   - get_reg_ptr() L1104-1112 (rD/rS=4,5 抑止: 本日KY)
//
//  方針(2026-06-30確定):
//   - 外部観測等価(PC/A/B/X/SP/FLAGS/メモリ)は守る。
//   - 内部構造はFPGA簡素化優先。emu23内部実装は模倣しない。
//   - 案A: opcode が 0x1F のときサブopバイトも入力し、
//     内部命令ID(idec)に正規化して一括出力。FSMはサブopを意識しない。
//
//  入力タイミング:
//   - op    : 1バイト目(opcode)。常に有効。
//   - subop : op==0x1F のときのみ意味を持つ(2バイト目)。
//             FSMが 0x1F 検出後にサブopをフェッチして与える。
//   - is_ext_valid : subop が確定しているか(0x1F時にFSMが立てる)。
//
//  出力(制御信号)はすべて組合せ。
// ============================================================
`timescale 1ns/1ps

// ---- 内部命令ID(idec) 定義 ----
package ysd8800_idec_pkg;
    typedef enum logic [5:0] {
        ID_NOP,    ID_HALT,   ID_EI,     ID_DI,     ID_BRK,
        ID_MOV,    ID_ADD,    ID_SUB,    ID_CMP,
        ID_AND,    ID_OR,     ID_XOR,    ID_NOT,
        ID_SHL,    ID_SHR,    ID_SAR,
        ID_LDWI,   ID_ADDI,   ID_SUBI,   ID_CMPI,
        ID_ANDI,   ID_ORI,    ID_XORI,
        ID_JMP,    ID_BEQ,    ID_BNE,    ID_BLT,    ID_BGE,
        ID_LDW_ABS, ID_STW_ABS, ID_LDW_RS, ID_STW_RD,
        ID_LDW_XI,  ID_STW_XI,
        ID_PUSH,   ID_POP,
        ID_LDB_ABS, ID_LDB_X,  ID_STB_ABS, ID_STB_X,
        ID_IRET,   ID_SYSCALL, ID_JSR,    ID_RET,
        ID_ILLEGAL
    } idec_t;
endpackage

import ysd8800_idec_pkg::*;

module ysd8800_decoder_v0_1 (
    input  logic [7:0]  op,          // opcode (1バイト目)
    input  logic [7:0]  subop,       // 0x1F時のサブopcode (2バイト目)
    input  logic        is_ext_valid,// subop確定フラグ(0x1F時にFSMが立てる)

    // --- 正規化命令ID ---
    output idec_t       idec,

    // --- 命令長(後続フェッチ総バイト数: opcode含む) ---
    output logic [2:0]  instr_len,

    // --- 制御信号 ---
    output logic        is_ext,       // op==0x1F
    output logic        need_subop,   // サブopフェッチ要(=op==0x1F)
    output logic        is_imm16,     // imm16フェッチ要
    output logic        flag_we,      // ALU の Z/N フラグ更新(IE操作は別線)
    output logic        reg_we,       // 汎用レジスタ書込(rD)
    output logic        ie_set,       // EI: FLAGS bit7(IE)←1
    output logic        ie_clr,       // DI: FLAGS bit7(IE)←0
    output logic [1:0]  mem_op,       // 00:none 01:rd 10:wr (幅はmem_w16で)
    output logic        mem_w16,      // 1:16bit 0:8bit
    output logic        is_branch,    // 0x60-0x64
    output logic [2:0]  branch_cond,  // 分岐条件(下記localparam)
    output logic        is_ctrl       // クラスD(IRET/SYSCALL/JSR/RET)
);

    // mem_op エンコード
    localparam logic [1:0] MEM_NONE = 2'b00;
    localparam logic [1:0] MEM_RD   = 2'b01;
    localparam logic [1:0] MEM_WR   = 2'b10;

    // branch_cond エンコード (is_branch=1 のとき有効)
    localparam logic [2:0] BR_ALWAYS = 3'd0; // JMP
    localparam logic [2:0] BR_EQ     = 3'd1; // BEQ Z=1
    localparam logic [2:0] BR_NE     = 3'd2; // BNE Z=0
    localparam logic [2:0] BR_LT     = 3'd3; // BLT N=1
    localparam logic [2:0] BR_GE     = 3'd4; // BGE N=0

    assign is_ext     = (op == 8'h1F);
    assign need_subop = (op == 8'h1F);

    // ============================================================
    //  正規化: 内部命令ID(idec)を決める
    // ============================================================
    always_comb begin
        idec = ID_ILLEGAL;
        if (op == 8'h1F) begin
            // EXT: subop確定時のみ正規化。未確定なら ILLEGAL のまま
            if (is_ext_valid) begin
                case (subop)
                    8'h00, 8'h01, 8'h02: idec = ID_PUSH;     // PUSH A/B/X
                    8'h03, 8'h04, 8'h05: idec = ID_POP;      // POP  A/B/X
                    8'h10, 8'h12:        idec = ID_LDB_ABS;  // LDB A/B,[imm16]
                    8'h11, 8'h13:        idec = ID_LDB_X;    // LDB A/B,[X]
                    8'h14, 8'h16:        idec = ID_STB_ABS;  // STB A/B,[imm16]
                    8'h15, 8'h17:        idec = ID_STB_X;    // STB A/B,[X]
                    default:             idec = ID_ILLEGAL;
                endcase
            end
        end else begin
            case (op)
                8'h00: idec = ID_NOP;
                8'h01: idec = ID_HALT;
                8'h02: idec = ID_EI;
                8'h03: idec = ID_DI;
                8'h04: idec = ID_IRET;
                8'h05: idec = ID_SYSCALL;
                8'h06: idec = ID_BRK;
                8'h20: idec = ID_MOV;
                8'h21: idec = ID_LDWI;
                8'h22: idec = ID_LDW_ABS;
                8'h23: idec = ID_STW_ABS;
                8'h24: idec = ID_LDW_RS;
                8'h25: idec = ID_STW_RD;
                8'h26: idec = ID_LDW_XI;
                8'h27: idec = ID_STW_XI;
                8'h40: idec = ID_ADD;
                8'h41: idec = ID_ADDI;
                8'h42: idec = ID_SUB;
                8'h43: idec = ID_SUBI;
                8'h44: idec = ID_CMP;
                8'h45: idec = ID_CMPI;
                8'h50: idec = ID_AND;
                8'h51: idec = ID_ANDI;
                8'h52: idec = ID_OR;
                8'h53: idec = ID_ORI;
                8'h54: idec = ID_XOR;
                8'h55: idec = ID_XORI;
                8'h56: idec = ID_NOT;
                8'h57: idec = ID_SHL;
                8'h58: idec = ID_SHR;
                8'h59: idec = ID_SAR;
                8'h60: idec = ID_JMP;
                8'h61: idec = ID_BEQ;
                8'h62: idec = ID_BNE;
                8'h63: idec = ID_BLT;
                8'h64: idec = ID_BGE;
                8'h68: idec = ID_JSR;
                8'h69: idec = ID_RET;
                default: idec = ID_ILLEGAL;
            endcase
        end
    end

    // ============================================================
    //  命令長 (emu23 instr_size L990-1069 準拠)
    // ============================================================
    always_comb begin
        instr_len = 3'd1; // default: 1バイト(NOP等/未知)
        if (op == 8'h1F) begin
            if (is_ext_valid) begin
                case (subop)
                    // 2バイト: PUSH/POP, LDB/STB [X]
                    8'h00,8'h01,8'h02,8'h03,8'h04,8'h05,
                    8'h11,8'h13,8'h15,8'h17: instr_len = 3'd2;
                    // 4バイト: LDB/STB [imm16]
                    8'h10,8'h12,8'h14,8'h16: instr_len = 3'd4;
                    default:                 instr_len = 3'd2; // unknown EXT
                endcase
            end else begin
                instr_len = 3'd2; // subop未確定時の暫定(最低2)
            end
        end else begin
            case (op)
                // 1バイト
                8'h00,8'h01,8'h02,8'h03,8'h04,8'h05,8'h06,8'h69:
                    instr_len = 3'd1;
                // 2バイト: opcode + rb
                8'h20,8'h24,8'h25,8'h40,8'h42,8'h44,
                8'h50,8'h52,8'h54,8'h56,8'h57,8'h58,8'h59:
                    instr_len = 3'd2;
                // 3バイト: opcode + imm16 (rbなし: 分岐/JSR)
                8'h60,8'h61,8'h62,8'h63,8'h64,8'h68:
                    instr_len = 3'd3;
                // 4バイト: opcode + rb + imm16
                8'h21,8'h22,8'h23,8'h26,8'h27,
                8'h41,8'h43,8'h45,8'h51,8'h53,8'h55:
                    instr_len = 3'd4;
                default: instr_len = 3'd1;
            endcase
        end
    end

    // ============================================================
    //  imm16フェッチ要否
    // ============================================================
    always_comb begin
        is_imm16 = 1'b0;
        if (op == 8'h1F) begin
            if (is_ext_valid) begin
                // LDB/STB [imm16] のみ imm16 を持つ
                case (subop)
                    8'h10,8'h12,8'h14,8'h16: is_imm16 = 1'b1;
                    default:                 is_imm16 = 1'b0;
                endcase
            end
        end else begin
            case (op)
                8'h21,8'h22,8'h23,8'h26,8'h27,
                8'h41,8'h43,8'h45,8'h51,8'h53,8'h55,
                8'h60,8'h61,8'h62,8'h63,8'h64,8'h68:
                    is_imm16 = 1'b1;
                default: is_imm16 = 1'b0;
            endcase
        end
    end

    // ============================================================
    //  フラグ(Z/N)更新イネーブル (§4.3 実照合)
    //   ALU演算/LDW/CMP = 更新, MOV/STW/LDB/STB = 不変
    //   ※ flag_we は ALU の Z/N 更新専用(2026-06-30 案ii で純化)。
    //     EI/DI の IE 操作は ie_set/ie_clr 専用線で別系統に分離。
    // ============================================================
    always_comb begin
        flag_we = 1'b0;
        case (idec)
            ID_ADD, ID_SUB, ID_AND, ID_OR, ID_XOR, ID_NOT,
            ID_SHL, ID_SHR, ID_SAR,
            ID_ADDI, ID_SUBI, ID_ANDI, ID_ORI, ID_XORI,
            ID_CMP, ID_CMPI,
            ID_LDWI, ID_LDW_ABS, ID_LDW_RS, ID_LDW_XI:
                flag_we = 1'b1;
            default:
                flag_we = 1'b0;
        endcase
    end

    // ============================================================
    //  IE(割込許可)操作専用線 (EI/DI)  ※ 2026-06-30 案ii で分離
    //   FSM が FLAGS bit7(IE) を直接 set/clr する。flag_we とは別系統。
    // ============================================================
    always_comb begin
        ie_set = (idec == ID_EI);
        ie_clr = (idec == ID_DI);
    end

    // ============================================================
    //  汎用レジスタ書込 (rD)
    //   CMP/CMPI=結果書かない, STW系/STB系=書かない,
    //   分岐/制御/NOP系=書かない
    // ============================================================
    always_comb begin
        reg_we = 1'b0;
        case (idec)
            ID_MOV, ID_ADD, ID_SUB, ID_AND, ID_OR, ID_XOR, ID_NOT,
            ID_SHL, ID_SHR, ID_SAR,
            ID_LDWI, ID_ADDI, ID_SUBI, ID_ANDI, ID_ORI, ID_XORI,
            ID_LDW_ABS, ID_LDW_RS, ID_LDW_XI,
            ID_LDB_ABS, ID_LDB_X,
            ID_POP:
                reg_we = 1'b1;
            default:
                reg_we = 1'b0; // CMP/CMPI/STW/STB/PUSH/分岐/制御
        endcase
    end

    // ============================================================
    //  メモリアクセス種別
    // ============================================================
    always_comb begin
        mem_op  = MEM_NONE;
        mem_w16 = 1'b0;
        case (idec)
            ID_LDW_ABS, ID_LDW_RS, ID_LDW_XI: begin
                mem_op = MEM_RD; mem_w16 = 1'b1;
            end
            ID_STW_ABS, ID_STW_RD, ID_STW_XI: begin
                mem_op = MEM_WR; mem_w16 = 1'b1;
            end
            ID_LDB_ABS, ID_LDB_X: begin
                mem_op = MEM_RD; mem_w16 = 1'b0;
            end
            ID_STB_ABS, ID_STB_X: begin
                mem_op = MEM_WR; mem_w16 = 1'b0;
            end
            // PUSH/POP/JSR/RET/IRET/SYSCALL のスタックアクセスは
            // FSMの専用シーケンスで扱う(mem_op汎用線では出さない)。
            default: begin
                mem_op = MEM_NONE; mem_w16 = 1'b0;
            end
        endcase
    end

    // ============================================================
    //  分岐
    // ============================================================
    always_comb begin
        is_branch   = 1'b0;
        branch_cond = BR_ALWAYS;
        case (idec)
            ID_JMP: begin is_branch = 1'b1; branch_cond = BR_ALWAYS; end
            ID_BEQ: begin is_branch = 1'b1; branch_cond = BR_EQ;     end
            ID_BNE: begin is_branch = 1'b1; branch_cond = BR_NE;     end
            ID_BLT: begin is_branch = 1'b1; branch_cond = BR_LT;     end
            ID_BGE: begin is_branch = 1'b1; branch_cond = BR_GE;     end
            default: begin is_branch = 1'b0; branch_cond = BR_ALWAYS; end
        endcase
    end

    // ============================================================
    //  クラスD制御フロー
    // ============================================================
    always_comb begin
        is_ctrl = 1'b0;
        case (idec)
            ID_IRET, ID_SYSCALL, ID_JSR, ID_RET: is_ctrl = 1'b1;
            default:                              is_ctrl = 1'b0;
        endcase
    end

endmodule
