module tb;

    logic clk;
    logic reset;

    cpu_top dut (
        .clk   (clk),
        .reset (reset)
    );

    // クロック生成
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // リセットと実行
    initial begin
        reset = 1;
        #20;
        reset = 0;

        // 10命令分実行
        #200;
        $finish;
    end

endmodule
