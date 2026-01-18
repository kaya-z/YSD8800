module cpu_core (
    input  logic        clk,
    input  logic        reset,
    output logic [15:0] pc
);

    /* ========= memories ========= */

    logic [7:0]  imem [0:65535];
    logic [15:0] dmem [0:65535];

    /* ========= registers ========= */

    logic [7:0]  ir;
    logic [15:0] regA;
    logic        ZF, NF;
    logic        halted;

    /* ========= instruction fetch / execute ========= */

    always_ff @(posedge clk) begin
        if (reset) begin
            pc     <= 16'h0000;
            regA  <= 16'h0000;
            ZF    <= 1'b0;
            NF    <= 1'b0;
            halted <= 1'b0;
        end
        else if (!halted) begin
            ir <= imem[pc];

            case (ir)

            8'h10: begin // LDW #imm
                regA <= {imem[pc+1], imem[pc+2]};
                pc   <= pc + 3;
            end

            8'h20: begin // ADDW #imm
                regA <= regA + {imem[pc+1], imem[pc+2]};
                pc   <= pc + 3;
            end

            8'h30: begin // STW addr
                dmem[{imem[pc+1], imem[pc+2]}] <= regA;
                pc <= pc + 3;
            end

            8'h42: begin // JMP addr
                pc <= {imem[pc+1], imem[pc+2]};
            end

            8'hFF: begin // HALT
                halted <= 1'b1;
                pc <= pc;
            end

            default: begin
                pc <= pc + 1;
            end
            endcase

            /* flags */
            ZF <= (regA == 16'h0000);
            NF <= regA[15];
        end
    end

endmodule
