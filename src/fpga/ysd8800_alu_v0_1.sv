// ============================================================
//  ysd8800_alu_v0_1.sv   v0.1  (2026-06-30)
//  YSD8800 FPGA V1 CPUコア : ALU (純組合せ)
//
//  設計根拠 (emu23 v1.09 実照合):
//   - set_zn() L1098-1101:
//       Z = (result == 0)         -> flag_z
//       N = (result & 0x8000)     -> flag_n (最上位bit)
//   - SHL L1467-1476: result = a << (b & 0x0F)   論理左・こぼれ破棄
//   - SHR L1478-1487: result = a >> (b & 0x0F)   論理右・0埋め
//   - SAR L1489-1499: result = $signed(a) >>> (b & 0x0F) 算術右・符号保持
//   - NOT L1461-1465: result = ~a (b不使用)
//   - ADD/SUB/AND/OR/XOR: 通常演算
//   - CMP/CMPI: SUB と同じ演算結果で Z/N のみ生成(書込は上位reg_weで抑止)
//
//  方針(2026-06-30): 外部観測等価を守る。result と Z/N を常に出し、
//   書く/書かないは上位(reg_we)で制御。フラグ反映は flag_we で制御。
//   即値版(ADDI等)は operand_b に imm16 を入れるだけ(本モジュール共通)。
//
//  alu_op エンコード(FSM/デコーダ側 idec から変換して与える):
// ============================================================
`timescale 1ns/1ps

module ysd8800_alu_v0_1 (
    input  logic [3:0]  alu_op,
    input  logic [15:0] operand_a,   // rD 現在値
    input  logic [15:0] operand_b,   // rS 値 or imm16
    output logic [15:0] result,
    output logic        flag_z,
    output logic        flag_n
);
    // alu_op エンコード
    localparam logic [3:0] ALU_ADD  = 4'd0;
    localparam logic [3:0] ALU_SUB  = 4'd1; // CMP/CMPI もこれ
    localparam logic [3:0] ALU_AND  = 4'd2;
    localparam logic [3:0] ALU_OR   = 4'd3;
    localparam logic [3:0] ALU_XOR  = 4'd4;
    localparam logic [3:0] ALU_NOT  = 4'd5; // operand_b 不使用
    localparam logic [3:0] ALU_SHL  = 4'd6;
    localparam logic [3:0] ALU_SHR  = 4'd7;
    localparam logic [3:0] ALU_SAR  = 4'd8;
    localparam logic [3:0] ALU_PASSB= 4'd9; // operand_b 通過(MOV/LDW用: Z/Nは結果に対し生成)

    logic [3:0] shamt; // シフト量 = operand_b[3:0]
    assign shamt = operand_b[3:0]; // assign文でビット選択(Icarus always_comb制約回避)

    always_comb begin
        case (alu_op)
            ALU_ADD:   result = operand_a + operand_b;
            ALU_SUB:   result = operand_a - operand_b;
            ALU_AND:   result = operand_a & operand_b;
            ALU_OR:    result = operand_a | operand_b;
            ALU_XOR:   result = operand_a ^ operand_b;
            ALU_NOT:   result = ~operand_a;
            ALU_SHL:   result = operand_a << shamt;
            ALU_SHR:   result = operand_a >> shamt;
            ALU_SAR:   result = $signed(operand_a) >>> shamt;
            ALU_PASSB: result = operand_b;
            default:   result = 16'h0000;
        endcase
    end

    // set_zn と同一定義 (L1098-1101)。assign文でビット選択(Icarus制約回避)
    assign flag_z = (result == 16'h0000);
    assign flag_n = result[15];

endmodule
