module rom (
    input  logic        clk,
    input  logic [15:0] addr,
    output logic [7:0]  data
);

    // 64KB ROM
    logic [7:0] mem [0:65535];

    // 起動時にプログラムをロード
    initial begin
        $readmemh("prog.hex", mem);
    end

    // 同期ROM（1クロック遅延）
    always_ff @(posedge clk) begin
        data <= mem[addr];
    end

endmodule
