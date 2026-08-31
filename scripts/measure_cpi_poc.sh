#!/bin/bash
# =====================================================================
#  measure_cpi_poc.sh  v0.1  (2026-08-20)
#   emu23 改良4 段9: サイクル表 v1.0 の再測定（差分法）
#
#  【方式】ysd8800_cycle_count_table_v1_0.md §1.4 に準拠
#     CPI = raw(命令) - raw(NOP) + 2
#   ただし本スクリプトは 1 命令を N=100 回ループで実行し、
#     CPI = (raw(命令) - raw(NOP)) / 100 + 2
#   とする（1命令あたりの差を取るため精度が上がる）。
#
#  【KY54】既知の正しい命令（MOV=4/ADDI=6 等）で方式を検証してから
#          疑義のある命令を測る。
#  【KY38】_poc 接尾辞。本番ファイルは変更しない。
# =====================================================================
set -e

mk() {   # $1=タグ  $2=命令行
  cat > cpi_$1.asm <<EOF
    .org  \$0000
    .word START
    .org  \$0100
START:
    DI
    LDW  SP, #\$FC7E
    LDW  X, #\$0200
    LDW  A, #0
    LDW  B, #100
LOOP:
    $2
    SUBI B, #1
    BNE  LOOP
    HALT
EOF
  ./hasm23 -c cpi_$1.asm >/dev/null 2>&1
  ./lnk23 -o cpi_$1.bin cpi_$1.asm.obj >/dev/null 2>&1
  python3 bin2hex.py cpi_$1.bin cpi_$1.hex >/dev/null 2>&1
}

raw() {  # $1=タグ  → RTL raw クロック数
  timeout 300 vvp sim_v9_idealmem.vvp +IMG=cpi_$1.hex 2>&1 \
    | grep -o "reset..HALT) = [0-9]*" | grep -o "[0-9]*$"
}

mk nop "NOP"
BASE=$(raw nop)
echo "raw(NOP loop) = $BASE"
echo "---------------------------------------------"
printf "%-18s %8s %8s %6s %6s\n" "命令" "raw" "delta" "CPI" "表v1.0"

chk() {  # $1=タグ $2=命令 $3=表の値
  mk "$1" "$2"
  R=$(raw "$1")
  D=$((R - BASE))
  CPI=$(python3 -c "print(($D)/100.0 + 2)")
  printf "%-18s %8s %8s %6s %6s\n" "$2" "$R" "$D" "$CPI" "$3"
}

echo "=== [KY54] 方式検証: 表が正しいと考えられる命令 ==="
chk mov  "MOV  A, B"      4
chk addi "ADDI A, #1"     6
chk ldwi "LDW  A, #1"     6
chk ldwm "LDW  A, [\$0200]" 8
chk stwm "STW  A, [\$0200]" 7

echo "=== 疑義のある命令 ==="
chk ldwr "LDW  A, [X]"    7
chk stwr "STW  A, [X]"    6

# --- JSR/RET は複合命令のため専用測定（表§1.4 の「セットアップ命令を差し引く」方式）---
cat > cpi_jsrret.asm <<'AEOF'
    .org  $0000
    .word START
    .org  $0100
START:
    DI
    LDW  SP, #$FC7E
    LDW  B, #100
LOOP:
    JSR  SUB
    SUBI B, #1
    BNE  LOOP
    HALT
SUB:
    RET
AEOF
./hasm23 -c cpi_jsrret.asm >/dev/null 2>&1
./lnk23 -o cpi_jsrret.bin cpi_jsrret.asm.obj >/dev/null 2>&1
python3 bin2hex.py cpi_jsrret.bin cpi_jsrret.hex >/dev/null 2>&1
RJ=$(timeout 300 vvp sim_v9_idealmem.vvp +IMG=cpi_jsrret.hex 2>&1 | grep -o "reset..HALT) = [0-9]*" | grep -o "[0-9]*$")
echo "=== JSR+RET 対 ==="
echo "raw(JSR+RET loop) = $RJ   raw(NOP loop) = $BASE"
python3 -c "print('JSR+RET 合計CPI =', ($RJ-$BASE)/100.0 + 2, ' (表v1.0: 7+7=14)')"
