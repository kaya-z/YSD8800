// ============================================================
//  tb_cdc_bridge_v0_1.sv   v0.1  (2026-07-11)
//  YSD8800 FPGA V3 : CDCブリッジ 単体TB
//
//  検証観点(v3_design_memo_v0_2.md §4.1.2/§4.1.3・fixorder v1.0 §4):
//   - 単発リード/ライトが正しくCDCを越えて完了するか
//   - 背中合わせの連続要求(mem_rdが下がらずアドレスだけ変わる。
//     S_MEMR_LO→S_MEMR_HI相当)で、req/ackが正しく1回ずつ
//     独立してハンドシェイクされ、データ取り違え・多重発行・
//     取りこぼしが起きないか
//   - CPU 4MHz相当 : PSRAM 80MHz相当(20倍)のクロック比で検証
//
//  高速側(psram_clk)の応答はTB内蔵の簡易4相応答モデルで代替
//  (実PSRAMコントローラはStep3で別途実装・本TB限定KY38準拠)。
// ============================================================
`timescale 1ns/1ps

module tb_cdc_bridge_v0_1;
    logic        cpu_clk, cpu_rst_n;
    logic [15:0] cpu_mem_addr;
    logic [7:0]  cpu_mem_wdata, cpu_mem_rdata;
    logic        cpu_mem_rd, cpu_mem_wr, cpu_mem_ready;

    logic        psram_clk, psram_rst_n;
    logic [15:0] psram_addr;
    logic [7:0]  psram_wdata, psram_rdata;
    logic        psram_we, psram_req, psram_ack;

    integer errors = 0;

    ysd8800_cdc_bridge_v0_2 #(.PHYS_AW(16)) dut (
        .cpu_clk(cpu_clk), .cpu_rst_n(cpu_rst_n),
        .cpu_phys_addr(cpu_mem_addr), .cpu_mem_wdata(cpu_mem_wdata),
        .cpu_mem_rdata(cpu_mem_rdata), .cpu_mem_rd(cpu_mem_rd),
        .cpu_mem_wr(cpu_mem_wr), .cpu_mem_ready(cpu_mem_ready),
        .psram_clk(psram_clk), .psram_rst_n(psram_rst_n),
        .psram_addr(psram_addr), .psram_wdata(psram_wdata), .psram_we(psram_we),
        .psram_req(psram_req), .psram_ack(psram_ack), .psram_rdata(psram_rdata)
    );

    // クロック: CPU 4MHz相当(period=20) : PSRAM 80MHz相当(period=1) = 20:1
    initial cpu_clk = 0;
    always #10 cpu_clk = ~cpu_clk;
    initial psram_clk = 0;
    always #0.5 psram_clk = ~psram_clk;

    // ---- 高速側 簡易4相応答モデル(Step3で実コントローラへ置換予定) ----
    localparam int LATENCY = 12; // §4.1.4見積り相当(通常時12サイクル)
    logic [7:0] psram_mem [0:65535];
    typedef enum logic [1:0] {PS_IDLE, PS_BUSY, PS_WAIT_REQ_LOW} ps_state_t;
    ps_state_t ps_state;
    integer    busy_cnt;
    integer    access_log_count; // TB観測用: 高速側が実際にアクセスを受理した回数

    always_ff @(posedge psram_clk or negedge psram_rst_n) begin
        if (!psram_rst_n) begin
            ps_state <= PS_IDLE;
            psram_ack <= 1'b0;
            busy_cnt <= 0;
            psram_rdata <= 8'h00;
            access_log_count <= 0;
        end else begin
            case (ps_state)
                PS_IDLE: begin
                    psram_ack <= 1'b0;
                    if (psram_req) begin
                        ps_state <= PS_BUSY;
                        busy_cnt <= LATENCY - 1;
                        access_log_count <= access_log_count + 1;
                    end
                end
                PS_BUSY: begin
                    if (busy_cnt == 0) begin
                        if (psram_we) psram_mem[psram_addr] <= psram_wdata;
                        psram_rdata <= psram_mem[psram_addr];
                        psram_ack   <= 1'b1;
                        ps_state    <= PS_WAIT_REQ_LOW;
                    end else begin
                        busy_cnt <= busy_cnt - 1;
                    end
                end
                PS_WAIT_REQ_LOW: begin
                    // 4相: reqが下がるまでackを維持
                    if (!psram_req) begin
                        psram_ack <= 1'b0;
                        ps_state  <= PS_IDLE;
                    end
                end
            endcase
        end
    end

    task automatic do_read(input [15:0] addr, output [7:0] rdata);
        @(negedge cpu_clk);
        cpu_mem_addr = addr; cpu_mem_rd = 1'b1; cpu_mem_wr = 1'b0;
        @(posedge cpu_mem_ready);
        rdata = cpu_mem_rdata;
        @(negedge cpu_clk);
        cpu_mem_rd = 1'b0;
    endtask

    // 背中合わせ連続アクセス: mem_rdを一度も下げずにアドレスだけ変える
    // (S_MEMR_LO→S_MEMR_HI相当。ブリッジのreq_holdが正しく機能するかの核心テスト)
    task automatic do_back_to_back_read(input [15:0] addr1, input [15:0] addr2,
                                          output [7:0] rdata1, output [7:0] rdata2);
        @(negedge cpu_clk);
        cpu_mem_addr = addr1; cpu_mem_rd = 1'b1; cpu_mem_wr = 1'b0;
        @(posedge cpu_mem_ready);
        rdata1 = cpu_mem_rdata;
        @(negedge cpu_clk);
        cpu_mem_addr = addr2;      // rdは1のまま、アドレスだけ切替
        @(posedge cpu_mem_ready);
        rdata2 = cpu_mem_rdata;
        @(negedge cpu_clk);
        cpu_mem_rd = 1'b0;
    endtask

    task automatic do_write(input [15:0] addr, input [7:0] wdata);
        @(negedge cpu_clk);
        cpu_mem_addr = addr; cpu_mem_wdata = wdata;
        cpu_mem_wr = 1'b1; cpu_mem_rd = 1'b0;
        @(posedge cpu_mem_ready);
        @(negedge cpu_clk);
        cpu_mem_wr = 1'b0;
    endtask

    logic [7:0] rd1, rd2;
    integer count_before;

    initial begin
        cpu_rst_n = 0; psram_rst_n = 0;
        cpu_mem_addr = 16'h0000; cpu_mem_wdata = 8'h00;
        cpu_mem_rd = 0; cpu_mem_wr = 0;
        psram_mem[16'h1000] = 8'h11;
        psram_mem[16'h1001] = 8'h22;
        repeat (3) @(negedge cpu_clk);
        cpu_rst_n = 1; psram_rst_n = 1;
        repeat (3) @(negedge cpu_clk);

        // T1: 単発リード
        do_read(16'h1000, rd1);
        if (rd1 !== 8'h11) begin
            $display("[T1] FAIL: expected 11 got %02h", rd1); errors++;
        end else if (access_log_count !== 1) begin
            $display("[T1] FAIL: access_log_count=%0d expected 1", access_log_count); errors++;
        end else $display("[T1] PASS: single read $1000 -> %02h (access#%0d)", rd1, access_log_count);

        // T2: 背中合わせ連続リード(rdを下げずにアドレスだけ切替。核心テスト)
        count_before = access_log_count;
        do_back_to_back_read(16'h1000, 16'h1001, rd1, rd2);
        if (rd1 !== 8'h11 || rd2 !== 8'h22) begin
            $display("[T2] FAIL: rd1=%02h rd2=%02h expected 11/22", rd1, rd2); errors++;
        end else if (access_log_count !== count_before + 2) begin
            $display("[T2] FAIL: access_log_count=%0d expected %0d (2件の独立要求のはず)",
                       access_log_count, count_before + 2); errors++;
        end else $display("[T2] PASS: back-to-back $1000->%02h, $1001->%02h (独立要求2件・access#%0d)",
                            rd1, rd2, access_log_count);

        // T3: ライト後、同アドレスをリードして反映確認
        do_write(16'h2000, 8'h7E);
        do_read(16'h2000, rd1);
        if (rd1 !== 8'h7E) begin
            $display("[T3] FAIL: write/read-back mismatch got %02h expected 7E", rd1); errors++;
        end else $display("[T3] PASS: write $2000=7E -> read-back %02h", rd1);

        // T4: 4連続の背中合わせリード(ずれ・取りこぼし累積がないか)
        count_before = access_log_count;
        for (int i = 0; i < 4; i++) begin
            psram_mem[16'h3000 + i] = 8'h30 + i;
        end
        begin
            logic [7:0] seq [0:3];
            @(negedge cpu_clk);
            cpu_mem_rd = 1'b1; cpu_mem_wr = 1'b0;
            for (int i = 0; i < 4; i++) begin
                cpu_mem_addr = 16'h3000 + i;
                @(posedge cpu_mem_ready);
                seq[i] = cpu_mem_rdata;
                @(negedge cpu_clk);
            end
            cpu_mem_rd = 1'b0;
            if (seq[0] !== 8'h30 || seq[1] !== 8'h31 || seq[2] !== 8'h32 || seq[3] !== 8'h33) begin
                $display("[T4] FAIL: seq=%02h,%02h,%02h,%02h expected 30,31,32,33",
                          seq[0], seq[1], seq[2], seq[3]); errors++;
            end else if (access_log_count !== count_before + 4) begin
                $display("[T4] FAIL: access_log_count=%0d expected %0d",
                          access_log_count, count_before + 4); errors++;
            end else $display("[T4] PASS: 4連続背中合わせ read 全一致 (access#%0d)", access_log_count);
        end

        if (errors == 0) $display("ALL PASS (4/4)");
        else $display("FAIL: %0d error(s)", errors);
        $finish;
    end
endmodule
