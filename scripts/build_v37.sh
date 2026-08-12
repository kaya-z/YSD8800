#!/bin/bash
# build_v37.sh  v1.0  (2026-07-12)  V3.7 S4 回帰

RTL="ysd8800_decoder_v0_1.sv ysd8800_regfile_v0_1.sv ysd8800_alu_v0_1.sv \
ysd8800_cpu_v0_1_FIXED.sv ysd8800_ysd8004_v0_1.sv ysd8800_mmio_stub_v0_3.sv \
ysd8800_addr_decoder_v0_1.sv ysd8800_mmu_v0_1.sv ysd8800_cdc_bridge_v0_2.sv \
ysd8800_psram_ctrl_v0_2.sv ysd8800_v37_membus_v0_1.sv"

run() {
    TB=$1
    OUT=$2
    echo "############ $TB ############"
    iverilog -g2012 -o ${OUT}.vvp $RTL $TB 2>&1 | grep -v "sorry:"
    if [ ! -f ${OUT}.vvp ]; then echo "BUILD FAILED"; return 1; fi
    ls -la ${OUT}.vvp
    timeout 90 vvp ${OUT}.vvp > ${OUT}.log 2>&1
    echo "rc=$?"
    echo "-- FAIL lines --"
    grep -c "^FAIL" ${OUT}.log
    echo "-- tail --"
    tail -3 ${OUT}.log
    echo
}

run tb_cpu_v37mem_poc.sv      m37
run tb_cpu_v37boundary_poc.sv b37
run tb_cpu_v37mmu_v0_1.sv     u37
