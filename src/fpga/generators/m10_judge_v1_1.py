#!/usr/bin/env python3
# m10_judge_v1_1.py  v1.1  (2026-09-25)
#   TKT-V12 review v1.6 B-23 対応：判定①を対話区間（起動部／①v／②x／③help）
#   ごとに分けて併合（interleave）判定する。既存の phy_out.log をそのまま使う
#   （再シミュレーション不要・review v1.6 B-23）。
#   v1.0（全体一括判定）からの変更点：区間分割のみ。判定ロジック（DP併合）は
#   m10_judge_v1_0.py と同一（interleave_ok をそのまま流用）。
import sys

VERSION = "m10_judge v1.1 (2026-09-25)"

# 期待列を区間ごとに分割（出典は tb_cpu_v8b_prod_v0_6_phy_poc.sv ヘッダ・R-11付帯条件）
# 各区間は「直前のプロンプト直後」〜「自分の応答中に出る次のプロンプト末尾」まで
# （先頭の "YUI> " は直前区間側に属するため、ここには含めない）
SEG_BOOT = b"YUIOS Booted!\n" + b"YUI> "
SEG_1    = b"v\r\nYUIOS V0.10.18\r\nYUI> "
SEG_2    = b"x\r\n?\r\nYUI> "
SEG_3    = b"help\r\nrun <n>\r\nps\r\nhelp\r\nYUI> "
SEGMENTS = [("起動部", SEG_BOOT), ("①v", SEG_1), ("②x", SEG_2), ("③help", SEG_3)]

MARKER = b"0123MD"   # FILEMGR マウント完了マーカー。先頭からの部分列(prefix)を許容


def interleave_ok(obs, a, b):
    """obs が a（全体）と b（長さ k の prefix）の併合か。成立する最大 k を返す（不成立は -1）"""
    n, m = len(a), len(b)
    best = -1
    for k in range(m, -1, -1):
        if n + k != len(obs):
            continue
        bb = b[:k]
        dp = [[False] * (k + 1) for _ in range(n + 1)]
        dp[0][0] = True
        for i in range(n + 1):
            for j in range(k + 1):
                if not dp[i][j]:
                    continue
                c = i + j
                if c >= len(obs):
                    continue
                if i < n and obs[c] == a[i]:
                    dp[i + 1][j] = True
                if j < k and obs[c] == bb[j]:
                    dp[i][j + 1] = True
        if dp[n][k]:
            best = k
            break
    return best


def split_by_prompt(obs, prompt=b"YUI> "):
    """obs を prompt の出現位置で4区間（起動部/①/②/③）に切る。
       起動部は先頭〜最初のprompt末尾を含む。以後の区間は
       「直前promptの直後」〜「次promptの末尾」で、重複を持たない。"""
    idx = []
    i = 0
    while True:
        j = obs.find(prompt, i)
        if j < 0:
            break
        idx.append(j)
        i = j + 1
    if len(idx) < 4:
        return None
    segs = []
    segs.append(obs[:idx[0] + len(prompt)])                                   # 起動部
    segs.append(obs[idx[0] + len(prompt):idx[1] + len(prompt)])                # ①
    segs.append(obs[idx[1] + len(prompt):idx[2] + len(prompt)])                # ②
    segs.append(obs[idx[2] + len(prompt):idx[3] + len(prompt)])                # ③
    return segs


def main():
    print(VERSION)
    path = sys.argv[1] if len(sys.argv) > 1 else "phy_out.log"
    with open(path) as f:
        obs = bytes(int(t, 16) for t in f.read().split())
    print(f"[J1.1] 受信 {len(obs)} B（{path}）")

    segs = split_by_prompt(obs)
    if segs is None:
        print("[J1.1] ★区間分割失敗：\"YUI> \" が4回未満しか見つからない★")
        return 1

    all_pass = True
    marker_used_total = 0
    for (name, exp), obs_seg in zip(SEGMENTS, segs):
        remaining_marker = MARKER[marker_used_total:]
        k = interleave_ok(obs_seg, exp, remaining_marker)
        if k >= 0:
            print(f"[J1.1] {name:6s} 併合判定 PASS（受信{len(obs_seg)}B/期待{len(exp)}B、"
                  f"マーカー消費 {remaining_marker[:k]!r}）")
            marker_used_total += k
        else:
            print(f"[J1.1] {name:6s} 併合判定 FAIL（受信{len(obs_seg)}B/期待{len(exp)}B）")
            print(f"[J1.1] {name:6s} 受信列: {obs_seg!r}")
            all_pass = False

    print(f"[J1.1] 総合: {'PASS' if all_pass else 'FAIL（区間別詳細は上記）'}")
    return 0 if all_pass else 1


if __name__ == "__main__":
    sys.exit(main())
