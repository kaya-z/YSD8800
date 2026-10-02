#!/usr/bin/env python3
# wbuf_sim_v1_2.py  v1.2 (2026-09-07)
#   段7-B 手順7「案ε」— ライトバッファ効果の単一サーバ待ち行列模擬
#   設計: v19_stage7b_emu23_nocache_plan_v0_7.md §4.3.2 / §4.3.3.1
#
#   入力: emu23 --trace-addr のトレース "cyc,pa,kind,hit"（ストリーム処理・全量保持しない）
#   モデル（§4.3.2 単一サーバ）:
#     - 読みヒット (R/F, hit=1) : サーバを占有しない（投入しない）
#     - 読みミス   (R/F, hit=0) : cache_line * lat[FILL] の間サーバを占有
#     - 書込       (W)          : 深さ D のバッファに投入。サーバが空いたら排出
#   サービス時間 S は ★校正値5 と RTL実測4.000 の両方で算出し併記する（§4.3.3.1 / M-3）★
#
#   出力: D と S ごとに
#     alpha(D)        = 待ちゼロで吸収できた書込の割合（閾値を引く無次元量）
#     実効削減率(D)   = 削減サイクル / C_eff （主判定量・直接積算）
#     13.2% * alpha   = 下限（併記）
import sys

FILL_LAT   = 5        # lat[FILL]（校正値。★フィル側は実測に置換できない＝案εの限界・§4.3.3.1★）
CACHE_LINE = 32       # emu23 既定（L580）／RTL と同諸元

# ★[v1.1 修正] ライトバッファ無しの基準待ち時間★
#   v1.0 はここにサービス時間 S を用いていたが誤り。CPU が書込で実際に待つのは
#   メモリ占有時間ではなく ★b_measured = 3.000442（RTL実測・v19 v0.7 §5.1.6.7）★ である。
#   v1.0 は 21,508 * 4 = 86,032 を削減上限として積算し、
#   ★真の stall_wr = 63,580 を超える 14.09%（上限 10.4% 超過）を出していた★。
#   検算: 21,508 * 3.000442 = 64,533 ≒ stall_wr 63,580（差 1.5%）
B_WAIT = 3.000442

# ★[v1.2 修正] 基準待ちはビンごとに RTL 実測から自己校正する★
#   v1.1 は全ビン共通の B_WAIT=3.000442 を用いたが、emu23 の書込回数との積が
#   RTL の stall_wr と 1.5% ずれ、★Dhry CEN=1 で上限 10.4% を 0.17pt 超える★結果を出した。
#   base_wait = stall_wr / n_writes とすれば、
#   ★α=1（全吸収）のとき実効削減率がちょうど上限に一致する★ことが保証される。
#   これは「実測できる量は実測から取る」という案(f) と同じ方針である。

def simulate(path, D, S, base_wait):
    """単一サーバ + 深さ D のライトバッファ。戻り値は各種積算値。"""
    fill_service = CACHE_LINE * FILL_LAT   # 読みミス1件のサーバ占有時間

    busy_until = 0        # サーバが空く時刻
    queue      = []       # バッファ内の書込の「排出開始可能時刻」列（長さ <= D）
    n_w = 0               # 書込総数
    n_absorb = 0          # 待ちゼロで吸収できた書込数
    saved = 0             # 削減サイクル（部分吸収を含む・§4.3.1）
    last_cyc = 0

    with open(path, 'r') as f:
        for line in f:
            if not line or line[0] == '#':
                continue
            p = line.rstrip('\n').split(',')
            if len(p) != 4:
                continue
            try:
                cyc = int(p[0])
            except ValueError:
                continue
            kind, hit = p[2], p[3]
            last_cyc = cyc

            # 既に排出が済んだ分をキューから外す
            while queue and queue[0] <= cyc:
                queue.pop(0)

            if kind == 'W':
                n_w += 1
                # ★[v1.2] 基準待ちはビンの RTL 実測から自己校正した値★
                pass  # base_wait は引数で受け取る
                if len(queue) < D:
                    # バッファに空きがある → CPU は待たずに済む
                    n_absorb += 1
                    start = max(cyc, busy_until)
                    busy_until = start + S
                    queue.append(busy_until)
                    saved += base_wait
                else:
                    # 満杯 → 先頭が排出されるまで待つ（部分吸収）
                    start = max(cyc, busy_until)
                    wait = start - cyc
                    if wait > base_wait:
                        wait = base_wait      # 元より悪くはならない
                    busy_until = start + S
                    queue.append(busy_until)
                    saved += (base_wait - wait)
            else:
                if hit == '0':
                    # 読みミス = ラインフィル。サーバを占有する（この間は排出できない）
                    start = max(cyc, busy_until)
                    busy_until = start + fill_service
    return n_w, n_absorb, saved, last_cyc

def count_writes(path):
    n = 0
    with open(path, 'r') as f:
        for line in f:
            p = line.rstrip('\n').split(',')
            if len(p) == 4 and p[2] == 'W' and p[0].isdigit():
                n += 1
    return n

def main():
    if len(sys.argv) < 4:
        print("usage: wbuf_sim_v1_2.py <trace> <C_eff> <stall_wr> [D...]", file=sys.stderr)
        return 1
    path    = sys.argv[1]
    c_eff   = int(sys.argv[2])
    stall_w = int(sys.argv[3])
    depths  = [int(x) for x in sys.argv[4:]] or [1, 2]

    n_w0 = count_writes(path)
    if n_w0 == 0:
        print("wbuf_sim: no write records in trace", file=sys.stderr)
        return 1
    base_wait = stall_w / n_w0          # ★ビンごとの自己校正（v1.2）★
    upper = stall_w / c_eff * 100.0     # このビンの上限（％）

    print("wbuf_sim v1.2 (2026-09-07)  trace=%s" % path)
    print("  C_eff=%d  stall_wr=%d  writes=%d" % (c_eff, stall_w, n_w0))
    print("  base_wait = stall_wr/writes = %.4f cyc   upper bound = %.2f%%"
          % (base_wait, upper))
    print("  model: single-server (v19 v0.7 4.3.2), FILL=%d*%d, line=%dB"
          % (CACHE_LINE, FILL_LAT, CACHE_LINE))
    print("%-3s %-3s %10s %10s %8s %12s %10s" %
          ("D", "S", "writes", "absorbed", "alpha", "eff_reduc", "upper*a"))
    for D in depths:
        for S in (4, 5):          # ★実測4.000 と校正値5 の併記（M-3）★
            n_w, n_a, saved, last = simulate(path, D, S, base_wait)
            alpha = (n_a / n_w) if n_w else 0.0
            eff   = saved / c_eff if c_eff else 0.0
            print("%-3d %-3d %10d %10d %8.4f %11.2f%% %9.2f%%" %
                  (D, S, n_w, n_a, alpha, eff * 100.0, upper * alpha))
    return 0

if __name__ == "__main__":
    sys.exit(main())
