// ============================================================
//  tb_cpu_v35mmu_v0_1.sv   v0.1  (2026-07-11)
//  YSD8800 FPGA V3.5 : 実CPUコア + V3.5メモリサブシステム(MMU統合)
//                      ★MMU有効時★ emu23 v1.09(--mmu) 協調等価検証
//
//  【S7の位置づけ】
//    S5(tb_cpu_v35regress/v35mem/v35boundary)は MCR=0(MMU無効)での
//    V3デグレ無を証明した。本TBは MCR=1(MMU有効)状態での外部観測等価
//    を証明する。すなわちV3.5の本来の検証対象である。
//
//  【対象ベクタ】gen_v35_mmu_vectors.py v0.2 が生成する6本
//    #1 MMU_IDENT_ON     : PTR恒等のままMMU ON → 挙動不変
//    #2 MMU_REMAP_P4     : PTR[4]=$14 論理$4000 → 物理$14000
//    #3 MMU_ISOLATION    : MMU ON書込が物理$4000に漏れない
//    #4 MMU_BOUNDARY     : PTR[4]/PTR[5] 4KB境界の個別変換
//    #5 MMU_PTR_RW       : PTR/MCRリードバック (X=$0055 / B=$0001)
//    #6 MMU_MMIO_BYPASS  : ★MMIO非変換の実証★ (X=$0055 / B=$3C3C)
//
//  【★偽合格防止(原則63)★】
//   (1) MMIOアクセスカウント判定を「>0」とする。
//       V3memTBは「MMIO非タッチ(count==0)」を確認したが、本TBでは
//       MMUレジスタ($FF00-$FF10)へ必ずアクセスするためcount>0が正。
//       count==0ならMMUレジスタに一度も届いていない = デコード破綻。
//   (2) 物理メモリを $00 で広くクリアする。
//       emu23 --mmu は phys_mem を $FF 初期化(L1851)するが、RTLの
//       $readmemh 後の未初期化領域は X。Xのまま読むとFAILするため、
//       MMU設計書 §9-2 に従いベクタ側でクリアするか、write→readの
//       round-tripにする設計としてある。TB側でも $00 クリアし、
//       X伝播による偽FAILを排除する。
//       ★対象は物理$00000-$15FFF(page0-page5 + remap先$14/$15)★
//   (3) X(dbg_x)を突合対象に含める。
//       #5/#6 の PTRリードバック値はXに退避される(生成器v0.2)。
//       Xを突合しなければMMIO非変換の証明が成立しない。
//
//  【DUT構成】S5と同一(ysd8800_v35_membus_v0_1, PHYS_AW=20/MEM_AW=20)
//            CPUコアは無改修(v0.5.7)。
// ============================================================
`timescale 1ns/1ps

import ysd8800_idec_pkg::*;

module tb_cpu_v35mmu_v0_1;
    logic        cpu_clk, cpu_rst_n;
    logic        psram_clk, psram_rst_n;
    logic [15:0] mem_addr;
    logic [7:0]  mem_wdata, mem_rdata;
    logic        mem_rd, mem_wr, mem_ready;
    logic [2:0]  irq_in;
    logic [15:0] dbg_pc, dbg_a, dbg_b, dbg_x, dbg_sp, dbg_flags;
    logic        dbg_halt;
    logic [15:0] dbg_mmio_last_addr;
    logic [31:0] dbg_mmio_access_count;

    integer errors = 0;

    ysd8800_cpu_v0_1 dut_cpu (
        .clk(cpu_clk), .rst_n(cpu_rst_n),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata),
        .mem_rd(mem_rd), .mem_wr(mem_wr), .mem_ready(mem_ready),
        .irq_in(irq_in),
        .dbg_pc(dbg_pc), .dbg_a(dbg_a), .dbg_b(dbg_b), .dbg_x(dbg_x),
        .dbg_sp(dbg_sp), .dbg_flags(dbg_flags), .dbg_halt(dbg_halt)
    );

    ysd8800_v35_membus_v0_1 #(.PHYS_AW(20), .MEM_AW(20)) u_membus (
        .cpu_clk(cpu_clk), .cpu_rst_n(cpu_rst_n),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata),
        .mem_rd(mem_rd), .mem_wr(mem_wr), .mem_ready(mem_ready),
        .psram_clk(psram_clk), .psram_rst_n(psram_rst_n),
        .dbg_mmio_last_addr(dbg_mmio_last_addr),
        .dbg_mmio_access_count(dbg_mmio_access_count)
    );

    initial cpu_clk = 0;
    always #10 cpu_clk = ~cpu_clk;
    initial psram_clk = 0;
    always #0.5 psram_clk = ~psram_clk;

    localparam int NVEC = 6;
    // 物理クリア範囲: page0-5($00000-$05FFF) + remap先 $14000-$15FFF
    localparam int CLR_LO_END = 20'h06000;
    localparam int CLR_HI_BEG = 20'h14000;
    localparam int CLR_HI_END = 20'h16000;

    string vname [0:NVEC-1];
    logic [15:0] exp_mem [0:NVEC*5-1];
    logic [15:0] exp_a, exp_b, exp_x, exp_sp;
    logic [7:0]  exp_f;
    integer vi, cyc;

    initial begin
        vname[0]="MMU_IDENT_ON";
        vname[1]="MMU_REMAP_P4";
        vname[2]="MMU_ISOLATION";
        vname[3]="MMU_BOUNDARY";
        vname[4]="MMU_PTR_RW";
        vname[5]="MMU_MMIO_BYPASS";

        $readmemh("v35mmu/expected_v35mmu.hex", exp_mem);

        irq_in = 3'd0;
        psram_rst_n = 0;
        repeat (3) @(negedge psram_clk);
        psram_rst_n = 1;

        for (vi = 0; vi < NVEC; vi = vi + 1) begin
            // ---- 物理メモリ $00 クリア(偽合格防止(2)) ----
            for (int i = 0; i < CLR_LO_END; i = i + 1)
                u_membus.u_psram_ctrl.mem[i] = 8'h00;
            for (int i = CLR_HI_BEG; i < CLR_HI_END; i = i + 1)
                u_membus.u_psram_ctrl.mem[i] = 8'h00;

            case (vi)
                0: $readmemh("v35mmu/MMU_IDENT_ON.hex",    u_membus.u_psram_ctrl.mem);
                1: $readmemh("v35mmu/MMU_REMAP_P4.hex",    u_membus.u_psram_ctrl.mem);
                2: $readmemh("v35mmu/MMU_ISOLATION.hex",   u_membus.u_psram_ctrl.mem);
                3: $readmemh("v35mmu/MMU_BOUNDARY.hex",    u_membus.u_psram_ctrl.mem);
                4: $readmemh("v35mmu/MMU_PTR_RW.hex",      u_membus.u_psram_ctrl.mem);
                5: $readmemh("v35mmu/MMU_MMIO_BYPASS.hex", u_membus.u_psram_ctrl.mem);
            endcase

            exp_a  = exp_mem[vi*5+0];
            exp_b  = exp_mem[vi*5+1];
            exp_x  = exp_mem[vi*5+2];
            exp_sp = exp_mem[vi*5+3];
            exp_f  = exp_mem[vi*5+4][7:0];

            cpu_rst_n = 0;
            repeat (3) @(negedge cpu_clk);
            cpu_rst_n = 1;

            cyc = 0;
            while (!dbg_halt && cyc < 5000) begin
                @(posedge cpu_clk); #1;
                cyc = cyc + 1;
            end

            if (!dbg_halt) begin
                $display("FAIL[%0d %s]: not halted (cyc=%0d)", vi, vname[vi], cyc);
                errors = errors + 1;
            end else begin
                if (dbg_a !== exp_a) begin
                    $display("FAIL[%0d %s]: A=%04h exp=%04h", vi, vname[vi], dbg_a, exp_a); errors++;
                end
                if (dbg_b !== exp_b) begin
                    $display("FAIL[%0d %s]: B=%04h exp=%04h", vi, vname[vi], dbg_b, exp_b); errors++;
                end
                if (dbg_x !== exp_x) begin
                    $display("FAIL[%0d %s]: X=%04h exp=%04h", vi, vname[vi], dbg_x, exp_x); errors++;
                end
                if (dbg_sp !== exp_sp) begin
                    $display("FAIL[%0d %s]: SP=%04h exp=%04h", vi, vname[vi], dbg_sp, exp_sp); errors++;
                end
                if (dbg_flags[7:0] !== exp_f) begin
                    $display("FAIL[%0d %s]: F=%02h exp=%02h", vi, vname[vi], dbg_flags[7:0], exp_f); errors++;
                end

                // ---- 偽合格防止(1): MMUレジスタに実際に届いたか ----
                // ★v0.1修正(2026-07-11)★
                //   dbg_mmio_access_count は cpu_rst_n でクリアされる
                //   (ysd8800_mmio_stub_v0_2.sv L134-141 実照合)。
                //   ベクタ毎にリセットされるため「絶対値」で判定する。
                //   当初は前ベクタとの差分で判定したが、#3が前ベクタと
                //   同カウント値になり差分0で偽FAILした。
                if (dbg_mmio_access_count == 32'd0) begin
                    $display("FAIL[%0d %s]: MMIOアクセス無し。MMUレジスタに届いていない(デコード破綻)",
                              vi, vname[vi]);
                    errors++;
                end

                $display("[%0d %-16s] A=%04h B=%04h X=%04h SP=%04h F=%02h  mmio=%0d last=%04h",
                          vi, vname[vi], dbg_a, dbg_b, dbg_x, dbg_sp, dbg_flags[7:0],
                          dbg_mmio_access_count, dbg_mmio_last_addr);
            end
        end

        if (errors == 0)
            $display("ALL PASS (%0d/%0d vectors, MMU有効時 外部観測等価・MMIO非変換実証済)",
                       NVEC, NVEC);
        else
            $display("FAIL: %0d error(s)", errors);
        $finish;
    end
endmodule
