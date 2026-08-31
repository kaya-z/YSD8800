#!/bin/bash
# build_v10_psram_poc.sh v0.1 (2026-08-21)
#  PSRAM実装版(V8-b相当)でのCPI測定 — 段10 分子の再測定用
#  ★decoder を必ず先頭に指定★
set -e
iverilog -g2012 -o sim_v10_psram_poc \
    ysd8800_decoder_v0_1.sv ysd8800_regfile_v0_1.sv ysd8800_alu_v0_1.sv \
    ysd8800_cpu_v0_1_FIXED.sv ysd8800_addr_decoder_v0_1.sv ysd8800_mmu_v0_1.sv \
    ysd8800_cdc_bridge_v0_2.sv ysd8800_psram_ctrl_v0_2.sv \
    ysd8800_mmio_stub_v0_7.sv ysd8800_ysd8001_v0_1.sv ysd8800_ysd8002_v0_3.sv \
    ysd8800_ysd8003_v0_4.sv ysd8800_ysd8004_v0_1.sv \
    ysd8800_v5_membus_v0_2.sv tb_cpu_v10_psram_poc_v0_1.sv
echo "[build_v10] OK -> sim_v10_psram_poc"
