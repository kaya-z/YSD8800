#!/bin/bash
# =====================================================================
#  build_v4.sh  v1.0  (2026-07-13)
#   V4 統合TBのビルドスクリプト
#
#  使い方: ./build_v4.sh <tb_file.sv> <top_module> <out.vvp>
#
#  build_v35.sh からの差分:
#    ・mmio_stub      v0.2 -> ★v0.4★（YSD8004 + YSD8001 を内包）
#    ・membus         v35  -> ★v4★
#    ・ysd8800_ysd8004_v0_1.sv を追加（V3.7）
#    ・ysd8800_ysd8001_v0_1.sv を追加（V4）
#
#  ★kaizen原則68: ビルド成否は $? ではなく【成果物の実在】で判定する★
#    → 本スクリプトは set -e せず、最後に ls で確認して返す。
# =====================================================================

TB=$1
TOP=$2
OUT=$3

if [ -z "$TB" ] || [ -z "$TOP" ] || [ -z "$OUT" ]; then
  echo "usage: $0 <tb_file.sv> <top_module> <out.vvp>"
  exit 1
fi

rm -f "$OUT"      # ★古いバイナリが残って偽合格するのを防ぐ★

iverilog -g2012 -s "$TOP" -o "$OUT" \
  ysd8800_decoder_v0_1.sv \
  ysd8800_regfile_v0_1.sv \
  ysd8800_alu_v0_1.sv \
  ysd8800_cpu_v0_1_FIXED.sv \
  ysd8800_addr_decoder_v0_1.sv \
  ysd8800_mmu_v0_1.sv \
  ysd8800_cdc_bridge_v0_2.sv \
  ysd8800_psram_ctrl_v0_2.sv \
  ysd8800_ysd8004_v0_1.sv \
  ysd8800_ysd8001_v0_1.sv \
  ysd8800_mmio_stub_v0_4.sv \
  ysd8800_v4_membus_v0_1.sv \
  "$TB" 2>&1 | grep -v "sorry: Case unique"

# ★成果物の実在で判定（原則68）★
if [ -f "$OUT" ]; then
  echo "BUILD OK: $OUT"
  exit 0
else
  echo "BUILD FAILED: $OUT not created"
  exit 1
fi
