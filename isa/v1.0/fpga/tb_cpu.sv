module tb_cpu;

    logic clk = 0;
    logic reset = 1;
    logic [15:0] pc;

    cpu_core dut (
        .clk(clk),
        .reset(reset),
        .pc(pc)
    );

    always #5 clk = ~clk;

    initial begin
        #20 reset = 0;
        #500 $finish;
    end

    initial begin
        $dumpfile("cpu.vcd");
        $dumpvars(0, dut);
    end

endmodule
