#!/usr/bin/env python3
"""merge_simple.py - userコード + ハーネスをマージ"""
import sys

user_f, harness_f, out_f = sys.argv[1], sys.argv[2], sys.argv[3]
with open(user_f,    'rb') as f: user    = bytearray(f.read())
with open(harness_f, 'rb') as f: harness = bytearray(f.read())

m = bytearray(65536)
m[:len(user)]    = user
m[:len(harness)] = harness   # ハーネスで先頭を上書き（ベクタ+_cstart）

last = max(i for i in range(len(m)) if m[i])
with open(out_f, 'wb') as f:
    f.write(bytes(m[:last + 1]))
print(f"  Merged: {last+1} bytes -> {out_f}")
