#!/bin/bash
# build_v0_10_7.sh — kernel_forth_v0_10_7.fs をビルドする
# v0.10.7: Step 5-4 FILE-CLOSE-IMPL 実装版
#
# 前提:
#   - ./force, ./hasm23, ./lnk23 が同じディレクトリにビルド済み (Force v1.5 以降)
#   - ysd8800_kern.tgt v0.4 以降, ysd8800.prim が同じディレクトリに存在
#   - kernel_v12_5.asm が同じディレクトリに存在
#   - kernel_forth_v0_10_7.fs が同じディレクトリに存在
#
# 既存の build.sh (v0.10.2 系専用) を v0.10.7 向けに派生したもの。
# build.sh のタグ式 (v0.10.2{tag}) を踏襲せず、明示的に v0.10.7 を扱う。

set -e

SRC="kernel_forth_v0_10_7.fs"
ASM="kernel_forth_v0_10_7.asm"
KASM="kernel_v12_5_for_v0_10_7.asm"
BIN="yuios_v0_10_7.bin"
SYM="yuios_v0_10_7.sym"
LDS="yuios_v0_10_7.lds"

if [ ! -f "$SRC" ]; then
  echo "ERROR: $SRC が見つかりません"
  exit 1
fi

echo "=== Step 1: Force ==="
./force --target ysd8800_kern --tgt-file ysd8800_kern.tgt --prim-file ysd8800.prim \
    "$SRC" -o "$ASM" 2>&1 | tail -3

echo "=== Step 2: hasm23 1パス目 ==="
rm -f "${ASM}.bin" "${ASM}.sym"
./hasm23 "$ASM" 2>&1 | tail -3

echo "=== Step 3: sed でラベル置換 ==="
for sym in WORD_MEMMGR_TASK WORD_UART_DRV_TASK WORD_UART_TEST_TASK \
           WORD_STOR_DRV_TASK WORD_STOR_TEST_TASK WORD_FILEMGR_TASK WORD_FILEMGR_TEST_TASK; do
  addr=$(grep -E "^[0-9a-f]+ ${sym}$" "${ASM}.sym" 2>/dev/null | awk '{print $1}')
  if [ -n "$addr" ]; then
    sed -i "s|LDW  A, #${sym}|LDW  A, #\$${addr}|g" "$ASM"
    echo "  $sym -> \$$addr"
  fi
done

echo "=== Step 4: hasm23 2パス目 ==="
rm -f "${ASM}.bin" "${ASM}.sym"
./hasm23 "$ASM" 2>&1 | tail -3

echo "=== Step 5: kernel.asm の WORD_OS_START 更新 ==="
new_addr=$(grep -E "^[0-9a-f]+ WORD_OS_START$" "${ASM}.sym" | awk '{print $1}')
if [ -z "$new_addr" ]; then
  echo "ERROR: WORD_OS_START が見つかりません"
  exit 1
fi
sed "s|\$e96e|\$${new_addr}|" kernel_v12_5.asm > "$KASM"
echo "  WORD_OS_START -> \$$new_addr"
rm -f "${KASM}.bin" "${KASM}.sym"
./hasm23 "$KASM" 2>&1 | tail -3

echo "=== Step 6: lnk23 ==="
cat > "$LDS" <<LDSEOF
OUTPUT $BIN
SYMOUT $SYM
SECTION forth   0x0000 ${ASM}.bin ${ASM}.sym
SECTION kernel  0x0000 ${KASM}.bin ${KASM}.sym
LDSEOF
./lnk23 "$LDS" 2>&1 | tail -3

echo "=== ビルド完了: $BIN, $SYM ==="
ls -la "$BIN" "$SYM"
