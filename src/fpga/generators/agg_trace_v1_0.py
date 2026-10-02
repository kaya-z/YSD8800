#!/usr/bin/env python3
# agg_trace_v1_0.py  v1.0  (2026-09-04 工程②-B 段6 T-1)
#   emu23 --trace-addr の出力を stderr からストリーム集計する。
#   ★ファイルに落とすと 20 秒で 1.46GB になるため、必ずストリームで処理する。★
#   停止条件: stdout(UART) に M-5 マーカー "0123MD" が現れた時点。
#   出力: 種別(F/R/W) x hit(0/1) の件数と、h_f / h_d / f / 書き比率。
import subprocess, sys, threading, os

MARK = b"0123MD"
cmd = sys.argv[1:]

p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

uart = bytearray()
stop = threading.Event()

def watch_stdout():
    while True:
        b = p.stdout.read(1)
        if not b:
            break
        uart.extend(b)
        if MARK in uart:
            stop.set()
            break

t = threading.Thread(target=watch_stdout, daemon=True)
t.start()

cnt = {}          # (kind, hit) -> count
header = []
last_cyc = 0
nline = 0
for raw in p.stderr:
    if stop.is_set():
        break
    line = raw.decode("utf-8", "replace").strip()
    if not line:
        continue
    if line.startswith("#") or line.startswith("cyc,"):
        header.append(line)
        continue
    f = line.split(",")
    if len(f) != 4:
        continue
    try:
        cyc = int(f[0]); kind = f[2]; hit = int(f[3])
    except ValueError:
        continue
    last_cyc = cyc
    cnt[(kind, hit)] = cnt.get((kind, hit), 0) + 1
    nline += 1

try:
    p.kill()
except Exception:
    pass

g = lambda k, h: cnt.get((k, h), 0)
F1, F0 = g("F", 1), g("F", 0)
R1, R0 = g("R", 1), g("R", 0)
W1, W0 = g("W", 1), g("W", 0)
F, R, W = F1 + F0, R1 + R0, W1 + W0
tot = F + R + W

print("=== emu23 trace aggregation (agg_trace_v1_0.py) ===")
for h in header:
    print("  " + h)
print("  UART = %r" % bytes(uart))
print("  marker reached = %s / last_cyc = %d / lines = %d" %
      (stop.is_set(), last_cyc, nline))
print("---- counts ----")
print("  FETCH  F: hit=%-10d miss=%-10d total=%d" % (F1, F0, F))
print("  READ   R: hit=%-10d miss=%-10d total=%d" % (R1, R0, R))
print("  WRITE  W: hit=%-10d miss=%-10d total=%d" % (W1, W0, W))
print("  ALL     : total=%d" % tot)
print("---- derived ----")
if F:
    print("  h_f (fetch hit rate)     = %.4f" % (F1 / F))
if R:
    print("  h_d (data read hit rate) = %.4f" % (R1 / R))
if F + R:
    print("  h   (read hit rate)      = %.4f" % ((F1 + R1) / (F + R)))
    print("  f   = F/(F+R)            = %.4f" % (F / (F + R)))
if tot:
    print("  write ratio W/(F+R+W)    = %.4f" % (W / tot))
