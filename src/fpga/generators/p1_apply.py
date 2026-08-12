#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# p1_apply.py v1.0 (2026-07-02)
# 基準asmの「4命令連続空往復窓」をMOV B,Aに置換する。
# emu23実行等価検証のための置換版asm生成が目的。
#
# 置換規則(設計書v1.1 §3.1):
#   SUBI SP, #2 / STW A,[SP] / LDW B,[SP] / ADDI SP,#2  (完全隣接4命令)
#   → MOV B, A
#
# KY防止策1: 置換前後でSP純移動(SUBI SP -2 / ADDI SP +2)が不変であることを検証。
# w/r前詰め(設計書v1.1 §3.4)。命令行のみ対象、コメント/空行/ラベルは温存。

import re, sys

def norm(s):
    # コメント除去+空白正規化した比較用キー
    return re.sub(r'\s+', ' ', s.split(';')[0].strip())

L1 = 'SUBI SP, #2'
L2 = 'STW A, [SP]'
L3 = 'LDW B, [SP]'
L4 = 'ADDI SP, #2'

def sp_move(lines):
    # 純SP移動(命令行のみ): SUBI SP,#2 => -2, ADDI SP,#2 => +2
    mv = 0
    for ln in lines:
        k = norm(ln)
        if k == L1: mv -= 2
        elif k == L4: mv += 2
    return mv

def main(src, dst):
    raw = open(src, encoding='utf-8').read().splitlines()
    # 命令行のインデックスと正規化キーを用意（コメント/空行/ラベルは非命令）
    def is_insn(ln):
        s = ln.split(';')[0].strip()
        if not s: return False
        if s.endswith(':'): return False
        return True

    out = []
    r = 0
    n = len(raw)
    folded = 0
    while r < n:
        # 現在行から連続する「命令行4つ」がL1..L4に一致するか
        # ただしコメント/空行が間に挟まったら不一致（完全隣接=命令行が連続）
        if is_insn(raw[r]) and norm(raw[r]) == L1:
            # 次の3命令行を、間に非命令(コメント等)を許さず取得
            seq = [r]
            k = r + 1
            ok = True
            while len(seq) < 4 and k < n:
                if is_insn(raw[k]):
                    seq.append(k)
                    k += 1
                else:
                    # コメント/空行/ラベルが挟まる → 完全隣接でない → 非置換
                    ok = False
                    break
            if ok and len(seq) == 4:
                keys = [norm(raw[i]) for i in seq]
                if keys == [L1, L2, L3, L4]:
                    # 置換: 4命令窓をMOV B,Aへ
                    indent = re.match(r'\s*', raw[seq[0]]).group(0)
                    out.append(indent + 'MOV  B, A')
                    r = seq[3] + 1
                    folded += 1
                    continue
        out.append(raw[r])
        r += 1

    # SP収支検証
    mv_before = sp_move(raw)
    mv_after  = sp_move(out)
    print(f"置換件数: {folded}")
    print(f"SP純移動 置換前: {mv_before}")
    print(f"SP純移動 置換後: {mv_after}")
    print(f"SP収支不変: {mv_before == mv_after}")
    if mv_before != mv_after:
        print("!!! SP収支が変化。置換が境界を壊した可能性。中断すべき。")
        sys.exit(2)

    open(dst, 'w', encoding='utf-8').write('\n'.join(out) + '\n')
    print(f"出力: {dst} ({len(out)}行)")

if __name__ == '__main__':
    src = sys.argv[1] if len(sys.argv) > 1 else 'dhry_base.asm'
    dst = sys.argv[2] if len(sys.argv) > 2 else 'dhry_p1.asm'
    main(src, dst)
