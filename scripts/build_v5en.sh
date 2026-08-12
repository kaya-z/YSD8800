#!/bin/bash
# =====================================================================
#  build_v5en.sh  v1.0  (2026-07-18)
#   V5 EN是正版 統合TBのビルドスクリプト
#   使い方: ./build_v5en.sh <tb_file.sv> <top_module> <out.vvp>
#   build_v4.sh からの差分:
#     ・mmio_stub  v0.4 -> ★v0.6★（YSD8002参照を v0_3 へ追従・案X-1）
#     ・membus     v4   -> ★v5★
#     ・ysd8800_ysd8002_v0_3.sv を追加（EN是正: 発火EN OR->AND）
#   ★kaizen原則68: ビルド成否は成果物の実在で判定★
# =====================================================================
TB=$1; TOP=$2; OUT=$3
if [ -z "$TB" ] || [ -z "$TOP" ] || [ -z "$OUT" ]; then
  echo "usage: $0 <tb_file.sv> <top_module> <out.vvp>"; exit 1
fi
rm -f "$OUT"
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
  ysd8800_ysd8002_v0_3.sv \
  ysd8800_mmio_stub_v0_6.sv \
  ysd8800_v5_membus_v0_1.sv \
  "$TB" 2>&1 | grep -v "sorry: Case unique"
if [ -f "$OUT" ]; then echo "BUILD OK: $OUT"; exit 0
else echo "BUILD FAILED: $OUT not created"; exit 1; fi
