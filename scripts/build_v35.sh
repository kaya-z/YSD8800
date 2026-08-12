#!/bin/bash
# =====================================================================
#  build_v35.sh  v0.1  (2026-07-11)
#   V3.5 統合TBのビルドスクリプト
#
#  使い方: ./build_v35.sh <tb_file.sv> <out.vvp>
#
#  コンパイル順序(依存順・HANDOVER §7):
#    decoder -> regfile -> alu -> cpu -> V3.5周辺 -> 統合ラッパー -> tb
#
#  CPUコアは v0.5.7 (ysd8800_cpu_v0_1_FIXED.sv) を使用する。
#    ※S_SUBOP mem_rd欠落バグ修正版。V3で発見・修正(原則63)。
# =====================================================================
set -e

TB=$1
OUT=$2

if [ -z "$TB" ] || [ -z "$OUT" ]; then
  echo "usage: $0 <tb_file.sv> <out.vvp>"
  exit 1
fi

iverilog -g2012 -o "$OUT" \
  ysd8800_decoder_v0_1.sv \
  ysd8800_regfile_v0_1.sv \
  ysd8800_alu_v0_1.sv \
  ysd8800_cpu_v0_1_FIXED.sv \
  ysd8800_addr_decoder_v0_1.sv \
  ysd8800_mmio_stub_v0_2.sv \
  ysd8800_mmu_v0_1.sv \
  ysd8800_cdc_bridge_v0_2.sv \
  ysd8800_psram_ctrl_v0_2.sv \
  ysd8800_v35_membus_v0_1.sv \
  "$TB"

echo "build OK: $OUT"
