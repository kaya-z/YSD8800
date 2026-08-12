#!/usr/bin/env python3
# ============================================================
#  bin2hex.py  v1.0  (2026-07-14)
#  YSD8800 FPGA V5 / S8
#  .bin -> $readmemh 用 .hex (1バイト1行・16進2桁)
# ============================================================
import sys

if len(sys.argv) != 3:
    print("usage: bin2hex.py in.bin out.hex", file=sys.stderr)
    sys.exit(1)

with open(sys.argv[1], 'rb') as f:
    data = f.read()

with open(sys.argv[2], 'w') as f:
    for b in data:
        f.write("%02x\n" % b)

print("bin2hex: %s -> %s (%d bytes)" % (sys.argv[1], sys.argv[2], len(data)))
