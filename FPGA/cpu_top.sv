module cpu_top (
    input logic clk,
    input logic reset
);

    // =========================
    // レジスタ
    // =========================
    logic [15:0] pc;
    logic [7:0]  ir;
    logic [7:0]  op1, op2, op3;
    logic [7:0]  reg_a;
    logic        halted;

    // =========================
    // メモリ
    // =========================
    logic [7:0] rom_data;
    logic [7:0] dmem [0:65535];

    rom u_rom (
        .clk  (clk),
        .addr (pc),
        .data (rom_data)
    );

    // =========================
    // フェッチ（IR + operands）
    // =========================
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            ir  <= 8'h00;
            op1 <= 8'h00;
            op2 <= 8'h00;
            op3 <= 8'h00;
        end else if (!halted) begin
            ir  <= rom_data;
            op1 <= dmem[pc + 16'd1]; // 簡略（後でROMに統一可）
            op2 <= dmem[pc + 16'd2];
            op3 <= dmem[pc + 16'd3];
        end
    end

    // =========================
    // 実行
    // =========================
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            pc     <= 16'h0000;
            reg_a  <= 8'h00;
            halted <= 1'b0;
        end else if (!halted) begin
            case (ir)
                8'h10: begin // LDA imm8
                    reg_a <= op1;
                    pc <= pc + 16'd4;
                end

                8'h20: begin // STA abs16
                    dmem[{op1, op2}] <= reg_a;
                    pc <= pc + 16'd4;
                end

                8'h30: begin // JMP abs16
                    pc <= {op1, op2};
                end

                8'hFF: begin // HALT
                    halted <= 1'b1;
                end

                default: begin
                    halted <= 1'b1;
                end
            endcase
        end
    end

    // =========================
    // デバッグ
    // =========================
    always_ff @(posedge clk) begin
        $display("PC=%04h IR=%02h A=%02h", pc, ir, reg_a);
    end

endmodule
