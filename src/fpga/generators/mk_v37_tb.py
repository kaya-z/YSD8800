#!/usr/bin/env python3
# mk_v37_tb.py  v1.0  (2026-07-12)
#   V3.5回帰TB4本を V3.7版へ複製する。
#   変更は membus インスタンス行のみ（KY38: 本番資産を壊さない）
#     - module名  : ysd8800_v35_membus_v0_1 -> ysd8800_v37_membus_v0_1
#     - 割込ポート: irq_src_* = 0 固定, irq1_o は観測用ネットへ
#   TB module名も _v37_ 化して衝突を避ける。

import re, sys, os

SRC = "/mnt/project"
DST = "/home/claude/v37"

FILES = [
    ("tb_cpu_v35regress_poc.sv",  "tb_cpu_v37regress_poc.sv"),
    ("tb_cpu_v35mem_poc.sv",      "tb_cpu_v37mem_poc.sv"),
    ("tb_cpu_v35boundary_poc.sv", "tb_cpu_v37boundary_poc.sv"),
    ("tb_cpu_v35mmu_v0_1.sv",     "tb_cpu_v37mmu_v0_1.sv"),
]

# membus インスタンス行に追記する割込ポート接続
IRQ_PORTS = (
    "        // ★V3.7: 割込I/F（本TBでは未使用。割込源は0固定）★\n"
    "        .irq_src_uart_rx(1'b0),\n"
    "        .irq_src_stor   (1'b0),\n"
    "        .irq_src_uart_tx(1'b0),\n"
    "        .irq1_o         (v37_irq1),\n"
)

# TB内に宣言を足す（irq1観測用）
IRQ_DECL = "    logic v37_irq1;   // ★V3.7: YSD8004 IRQ1観測（本TBでは0のはず）★\n"

for src, dst in FILES:
    with open(os.path.join(SRC, src), encoding="utf-8") as f:
        t = f.read()

    orig = t

    # (1) TB module 名を v37 化
    m = re.search(r"^module\s+(\w+)\s*;", t, re.M)
    if not m:
        print("ERR: module not found in %s" % src); sys.exit(1)
    old_tb = m.group(1)
    new_tb = old_tb.replace("v35", "v37")
    if new_tb == old_tb:
        print("ERR: tb name has no v35: %s" % old_tb); sys.exit(1)
    t = t.replace("module %s;" % old_tb, "module %s;" % new_tb)

    # (2) irq1 観測ネットの宣言を module 直後に挿入
    t = t.replace("module %s;\n" % new_tb,
                  "module %s;\n\n%s" % (new_tb, IRQ_DECL), 1)

    # (3) membus インスタンス: module名を差し替え、割込ポートを追記
    old_inst = "ysd8800_v35_membus_v0_1 #(.PHYS_AW(20), .MEM_AW(20)) u_membus (\n"
    new_inst = "ysd8800_v37_membus_v0_1 #(.PHYS_AW(20), .MEM_AW(20)) u_membus (\n" + IRQ_PORTS
    if old_inst not in t:
        print("ERR: membus inst not found in %s" % src); sys.exit(1)
    t = t.replace(old_inst, new_inst)

    # (4) ヘッダに V3.7 由来であることを追記
    t = ("// [V3.7 S4] %s より自動複製 (mk_v37_tb.py v1.0 / 2026-07-12)\n"
         "//   変更点: membus を ysd8800_v37_membus_v0_1 に差し替え、\n"
         "//           YSD8004割込ポートを接続(割込源は0固定)。判定内容は同一。\n"
         "//   目的  : V3.7統合による V3.5相当機能のデグレ検出（回帰）\n" % src) + t

    with open(os.path.join(DST, dst), "w", encoding="utf-8") as f:
        f.write(t)

    print("OK: %s -> %s  (tb: %s -> %s, %d -> %d bytes)"
          % (src, dst, old_tb, new_tb, len(orig), len(t)))

print("done.")
