#!/bin/bash
# build_road2.sh — 道2版 YUI OS ビルド（Step 8-F-2 結合テスト I1-I3 用）
#   設計書 hasm23_xref_yof_design_v2_2.md §3.7.1 準拠
#   - sed系統②（No.6 WORD_OS_START の kernel.asm 直書き）を廃止し YOF UNDEF 解決へ
#   - 後処理1（No.1 混入行 #WORD_xxx）は残置するが、固定リスト→全自動抽出に改善（KY-本日）
#   - 後処理2（案F2）：WORD_OS_START 定義直前に .global を挿入
#   - hasm23 -c で forth/kernel を YOF 化（道2: load_addr=$5100/$0000・has_org）
#   - lnk23 --machine force で load_addr 尊重の固定配置
#   ※本番ソース（kernel_forth_*.fs / kernel_v12_7.asm）は非改変。実験ファイル名で処理（KY38）
set -e
SRC="${1:-kernel_forth_v0_10_18.fs}"
FASM="kf_r2.asm"          # forth 実験asm
KASM="kf_r2_kern.asm"     # kernel 実験asm
FOBJ="kf_r2.asm.obj"
KOBJ="kf_r2_kern.asm.obj"
BIN="yuios_road2.bin"
SYM="yuios_road2.sym"

echo "=== Step 1: Force（forthカーネルコンパイル）==="
./force --target ysd8800_kern --tgt-file ysd8800_kern.tgt --prim-file ysd8800.prim "$SRC" -o "$FASM" 2>&1 | tail -1

echo "=== Step 2: 後処理1（#WORD_xxx 混入行を全自動抽出して 1パス目アドレスで #\$addr 直書き）==="
# まず .org $5100 基準の1パス目で各 WORD_xxx の絶対アドレスを得る（混入行は # 付きで未解決のままだが
# ラベル定義自体は解決されるので .sym が得られる）。混入行を一時的に NOP 化せず、
# hasm23 はエラーを出すが .sym は生成されるため、それを使う。
# → より安全に: 混入行を一旦 "LDW A, #$0000" に潰した一時asmで1パス目を回し .sym を得る。
sed -E 's/#WORD_[A-Z0-9_]+/#$0000/g' "$FASM" > "${FASM}.p1"
rm -f "${FASM}.p1.bin" "${FASM}.p1.sym"
./hasm23 "${FASM}.p1" 2>&1 | tail -1
# 全自動抽出した #WORD_xxx を、1パス目 .sym のアドレスで本物の #$addr に置換（固定リスト不使用）
cp "$FASM" "${FASM}.work"
for sym in $(grep -oE '#WORD_[A-Z0-9_]+' "$FASM" | sed 's/^#//' | sort -u); do
  addr=$(grep -E "^[0-9a-f]+ ${sym}$" "${FASM}.p1.sym" 2>/dev/null | awk '{print $1}')
  if [ -z "$addr" ]; then echo "  ERROR: $sym のアドレス不在（1パス目）"; exit 1; fi
  sed -i "s|#${sym}\b|#\$${addr}|g" "${FASM}.work"
  echo "  (後処理1) $sym -> \$$addr"
done
mv "${FASM}.work" "$FASM"

echo "=== Step 3: 後処理2（WORD_OS_START 定義直前に .global を挿入・案F2）==="
# WORD_OS_START: の定義行直前に .global WORD_OS_START を1行挿入
awk '/^WORD_OS_START:/ && !done { print ".global WORD_OS_START"; done=1 } { print }' "$FASM" > "${FASM}.g"
mv "${FASM}.g" "$FASM"
echo "  .global WORD_OS_START 挿入済み（$(grep -c '^.global WORD_OS_START' "$FASM") 行）"

echo "=== Step 4: hasm23 -c で forth.obj 生成（道2: load_addr=\$5100・has_org・WORD_OS_START GLOBAL）==="
rm -f "$FOBJ"
./hasm23 -c "$FASM" 2>&1 | tail -1

echo "=== Step 5: kernel_v12_7.asm の \$e96e を #WORD_OS_START へ（sed系統②=No.6 廃止・UNDEF参照化）==="
# 本番ソース非改変: 実験ファイル名 $KASM に出力。#$e96e（2箇所）を UNDEF 参照 #$WORD_OS_START に置換
# hasm23 構文: シンボルアドレス即値参照は #$LABEL 形式（# の後に $ + シンボル名）
sed 's|#\$e96e|#$WORD_OS_START|g' kernel_v12_7.asm > "$KASM"
echo "  #\$e96e -> #\$WORD_OS_START 置換数: $(grep -c '#\$WORD_OS_START' "$KASM")"

echo "=== Step 6: hasm23 -c で kernel.obj 生成（道2: load_addr=\$0000・has_org・WORD_OS_START UNDEF reloc=2）==="
rm -f "$KOBJ"
./hasm23 -c "$KASM" 2>&1 | tail -1

echo "=== Step 7: lnk23 道2リンク（--machine force・load_addr 尊重の固定配置）==="
./lnk23 -o "$BIN" --sym "$SYM" --machine force "$FOBJ" "$KOBJ" 2>&1 | tail -8

echo "=== 完了: $BIN ==="
ls -la "$BIN" "$SYM"
