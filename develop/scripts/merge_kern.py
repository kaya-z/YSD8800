#!/usr/bin/env python3
"""merge_kern.py - カーネル + ユーザコード + パッチをマージ
usage: merge_kern.py <kernel.bin> <user.bin> <patch.bin> <output.bin>
"""
import sys

kern_f, user_f, patch_f, out_f = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

with open(kern_f,  'rb') as f: kern  = bytearray(f.read())
with open(user_f,  'rb') as f: user  = bytearray(f.read())
with open(patch_f, 'rb') as f: patch = bytearray(f.read())

m = bytearray(65536)

# 1. カーネルを展開
m[:len(kern)] = kern

# 2. ユーザコード（非ゼロバイトのみ上書き）
for i in range(len(user)):
    if user[i]: m[i] = user[i]

# 3. パッチを適用（非ゼロバイトのみ上書き）
for i in range(len(patch)):
    if patch[i]: m[i] = patch[i]

last = max(i for i in range(len(m)) if m[i])
with open(out_f, 'wb') as f:
    f.write(bytes(m[:last + 1]))
print(f"  Merged: {last+1} bytes -> {out_f}")
