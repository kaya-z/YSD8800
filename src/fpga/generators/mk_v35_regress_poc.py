#!/usr/bin/env python3
# =====================================================================
# mk_v35_regress_poc.py  v0.1  (2026-07-11)
#   V3の実CPU統合TBを、V3.5構成(MMU挿入済み・MCR=0)へ差し替える。
#
# 【狙い】S5: MMU無効時のV3等価性(デグレ無)を証明する。
#   MCR=0(リセット値)ならMMUは恒等写像なので、V3構成と
#   bit-exact等価になるはず。V3でALL PASSした全26ベクタが
#   V3.5構成でも再現することを確認する。
#
# 【KY38】本番TBは変更せず、_poc サフィックスで出力する。
# =====================================================================
import re, sys, os

# (入力TB, 出力TB)
TARGETS = [
    ("tb_cpu_v3_v0_1.sv",    "tb_cpu_v35regress_poc.sv"),
    ("tb_cpu_v3mem_v0_1.sv", "tb_cpu_v35mem_poc.sv"),
]

def convert(src, dst):
    with open(src) as f:
        s = f.read()

    orig = s

    # (1) メモリサブシステムをV3.5ラッパーへ差し替え
    #     CPU側I/Fは完全同一なので、モジュール名+パラメータのみ変更。
    s = s.replace(
        "ysd8800_v3_membus_v0_1 u_membus (",
        "ysd8800_v35_membus_v0_1 #(.PHYS_AW(20), .MEM_AW(20)) u_membus ("
    )

    # (2) TBモジュール名を _poc 化(重複定義回避)
    m = re.search(r"module\s+(tb_\w+)\s*;", s)
    if not m:
        print(f"ERROR: module decl not found in {src}", file=sys.stderr)
        sys.exit(1)
    old_mod = m.group(1)
    new_mod = os.path.splitext(dst)[0]
    s = s.replace(f"module {old_mod};", f"module {new_mod};")

    if s == orig:
        print(f"ERROR: no substitution happened in {src}", file=sys.stderr)
        sys.exit(1)

    # ヘッダに注記を追加
    hdr = (
        "// ============================================================\n"
        f"//  {dst}   (V3.5 regression PoC / KY38)\n"
        f"//  元TB: {src}\n"
        "//  変更: ysd8800_v3_membus_v0_1 -> ysd8800_v35_membus_v0_1\n"
        "//                                  (PHYS_AW=20, MEM_AW=20)\n"
        "//  狙い: MCR=0(リセット値)でMMUは恒等写像 => V3とbit-exact等価。\n"
        "//        V3でALL PASSしたベクタがV3.5構成でも再現することを確認\n"
        "//        する(デグレ無の証明・v3_5_design_memo_v0_2.md §4.4/S5)。\n"
        "// ============================================================\n"
    )
    s = hdr + s

    with open(dst, "w") as f:
        f.write(s)
    print(f"OK: {src} -> {dst}  (module {old_mod} -> {new_mod})")

def main():
    for src, dst in TARGETS:
        if not os.path.exists(src):
            print(f"ERROR: {src} not found", file=sys.stderr)
            sys.exit(1)
        convert(src, dst)

if __name__ == "__main__":
    main()
