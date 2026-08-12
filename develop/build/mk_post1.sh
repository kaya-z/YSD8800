#!/bin/bash
# mk_post1.sh v1.0 — YUI OS Makefile 後処理1（S2: #WORD_xxx 混入行除去）
#   Step 8-B / yuios_makefile_design v0.2 §2.7 準拠
#   build_road2.sh Step 2 からのバイト等価移植（新規ロジックなし・M-2 条件）
#   役割: Force 出力 asm 中の #WORD_xxx 混入行を、1パス目アセンブルで得た
#         絶対アドレスを用いて #$addr に全自動置換する（固定リスト不使用）。
#   引数: $1 = forth asm ファイル（例 kf_r2.asm） / $2 = hasm23 パス（例 ./hasm23）
set -e
FASM="$1"
HASM="$2"

# まず .org $5100 基準の1パス目で各 WORD_xxx の絶対アドレスを得る。
# 混入行を一旦 "#$0000" に潰した一時asmで1パス目を回し .sym を得る。
sed -E 's/#WORD_[A-Z0-9_]+/#$0000/g' "$FASM" > "${FASM}.p1"
rm -f "${FASM}.p1.bin" "${FASM}.p1.sym"
"$HASM" "${FASM}.p1" 2>&1 | tail -1
# 全自動抽出した #WORD_xxx を、1パス目 .sym のアドレスで本物の #$addr に置換（固定リスト不使用）
cp "$FASM" "${FASM}.work"
for sym in $(grep -oE '#WORD_[A-Z0-9_]+' "$FASM" | sed 's/^#//' | sort -u); do
  addr=$(grep -E "^[0-9a-f]+ ${sym}$" "${FASM}.p1.sym" 2>/dev/null | awk '{print $1}')
  if [ -z "$addr" ]; then echo "  ERROR: $sym のアドレス不在（1パス目）"; exit 1; fi
  sed -i "s|#${sym}\b|#\$${addr}|g" "${FASM}.work"
  echo "  (後処理1) $sym -> \$$addr"
done
mv "${FASM}.work" "$FASM"
