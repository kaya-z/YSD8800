#!/bin/bash
# build_v0_10_15.sh — Ph.5 Step4 PROC-LOAD-ADDR $D400化版
# ベース: build_v0_10_13.sh（ファイル名のみv0.10.15へ）
set -e
SRC="kernel_forth_v0_10_15.fs"
ASM="kernel_forth_v0_10_15.asm"
KASM="kernel_v12_7_for_v0_10_15.asm"
BIN="yuios_v0_10_15.bin"
SYM="yuios_v0_10_15.sym"
LDS="yuios_v0_10_15.lds"

echo "=== Step 1: Force ==="
./force --target ysd8800_kern --tgt-file ysd8800_kern.tgt --prim-file ysd8800.prim "$SRC" -o "$ASM" 2>&1 | tail -3

echo "=== Step 2: hasm23 1パス目 ==="
rm -f "${ASM}.bin" "${ASM}.sym"
./hasm23 "$ASM" 2>&1 | tail -3

echo "=== Step 3: sed ラベル置換 ==="
for sym in WORD_MEMMGR_TASK WORD_UART_DRV_TASK WORD_UART_TEST_TASK \
           WORD_STOR_DRV_TASK WORD_STOR_TEST_TASK WORD_FILEMGR_TASK \
           WORD_FILEMGR_TEST_TASK WORD_PROCMGR_TASK; do
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
if [ -z "$new_addr" ]; then echo "ERROR: WORD_OS_START 不在"; exit 1; fi
# kernel_v12_7.asm 内の WORD_OS_START 参照を実アドレスへ。元ハードコード $e96e を置換。
sed "s|\$e96e|\$${new_addr}|" kernel_v12_7.asm > "$KASM"
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
echo "=== 完了: $BIN ==="
ls -la "$BIN" "$SYM"
