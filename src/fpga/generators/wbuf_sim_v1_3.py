#!/usr/bin/env python3
# wbuf_sim_v1_3.py  v1.3 (2026-09-08)
#   段7-B 手順7「案ε」— ライトバッファ効果の単一サーバ待ち行列模擬
#   設計: v19_stage7b_emu23_nocache_plan_v0_7.md §4.3.2 / §4.3.3.1
#         ★改修根拠: answer_v21_stage7b_alpha_fragility_v1_0.md §2★
#
#   入力: emu23 --trace-addr のトレース "cyc,pa,kind,hit"（ストリーム処理・全量保持しない）
#   モデル（§4.3.2 単一サーバ）:
#     - 読みヒット (R/F, hit=1) : サーバを占有しない（投入しない）
#     - 読みミス   (R/F, hit=0) : cache_line * lat[FILL] の間サーバを占有
#     - 書込       (W)          : 深さ D のバッファに投入。サーバが空いたら排出
#
# ============================================================================
# ★[v1.3 修正] 16bit 書込ペアの結合（本版の本質）★
# ----------------------------------------------------------------------------
#   v1.2 までは、トレース上の書込到着時刻をそのまま独立な到着とみなしていた。
#   これは誤りである（回答書 §1）。
#
#   emu23 の書込課金は lat[WR]-1 = 4 であり cpu.cycle に加算される。
#   16bit 書込は呼出側がバイト単位で 2 回 mem_charge() を呼ぶため、
#   2 発目の cyc は「1 発目の課金 4 サイクルを経過した後」になる。
#   したがってトレース上の delta=4（全書込の 50.1%）は
#     ×「2 発目が 4 サイクル後に到着した」
#     ○「1 発目が 4 サイクル待たされたから 2 発目が 4 サイクルずれた」
#   であり、★因果が逆★である。
#
#   いま模擬したいのは「その待ちを取り除いた世界」であるから、
#   待ちを取り除けば 2 発目はほぼ直後に来る。トレースの時刻はもう使えない。
#   v1.2 の S=4 で alpha≈1.0 は、★待ち時間を余裕として二重に数えた artifact★。
#
#   最小改修（回答書 §2）:
#     1. ★アドレスが連続する書込 2 件★ を「同一時刻に到着する 2 バイト要求」に結合
#     2. 結合要求はバッファのスロットを 2 つ要求する
#     3. D=1 では 1 バイトしか入らず 2 バイト目で CPU が待つ → alpha(1) ~= 0.5
#     4. D=2 では丸ごと入る                                  → alpha(2)  = 1.0
#
#   ★結合判定は delta 値ではなくアドレス連続性で行う（回答書 §2 末尾）。★
#   delta は S が変われば変わる量＝いま取り除こうとしている待ち時間そのもの
#   から生成された値であり、これで判定すると因果の取り違えが形を変えて残る。
#
#   ★検算（本版の合否）★: S=4 と S=5 で alpha(1) がどちらも 0.5 近傍になること。
#                          S で alpha が跳ぶなら、まだ因果が残っている。
# ============================================================================
#
#   出力: D と S ごとに
#     alpha(D)        = 待ちゼロで吸収できた書込の割合
#     実効削減率(D)   = 削減サイクル / C_eff （主判定量・直接積算）
#     upper * alpha   = 下限（併記）
import sys

FILL_LAT   = 5        # lat[FILL]（校正値。★フィル側は実測に置換できない＝案εの限界・§4.3.3.1★）
CACHE_LINE = 32       # emu23 既定（L580）／RTL と同諸元

# ★[v1.2] 基準待ちはビンごとに RTL 実測から自己校正する（v1.3 でも踏襲）★
#   base_wait = stall_wr / n_writes とすれば、
#   ★alpha=1（全吸収）のとき実効削減率がちょうど上限に一致する★ことが保証される。
#   （v1.0 はサービス時間 S を、v1.1 は全ビン共通の 3.000442 を用いて、いずれも上限超過）


def _drain(queue, cyc):
    """到着時刻 cyc の時点で排出済みの要求をキューから外す。"""
    while queue and queue[0] <= cyc:
        queue.pop(0)


def _admit(cyc, nbyte, D, S, base_wait, st):
    """★[v1.3] 1 つの書込到着（nbyte スロット要求）を処理する★

    nbyte=2 は 16bit 書込のペア。2 バイトは ★同一時刻 cyc に到着する★ ものとして
    扱う（回答書 §1.3：ライトバッファがあれば CPU は待たされないので、
    2 発目はほぼ直後に来る。トレース上の delta=4 は使わない）。
    """
    for _ in range(nbyte):
        st['n_w'] += 1
        if len(st['queue']) < D:
            # バッファに空きがある → CPU は待たずに済む
            st['n_absorb'] += 1
            start = max(cyc, st['busy_until'])
            st['busy_until'] = start + S
            st['queue'].append(st['busy_until'])
            st['saved'] += base_wait
        else:
            # 満杯 → 先頭が排出されるまで待つ（部分吸収）
            start = max(cyc, st['busy_until'])
            wait = start - cyc
            if wait > base_wait:
                wait = base_wait      # 元より悪くはならない
            st['busy_until'] = start + S
            st['queue'].append(st['busy_until'])
            st['saved'] += (base_wait - wait)


def simulate(path, D, S, base_wait):
    """単一サーバ + 深さ D のライトバッファ。戻り値は各種積算値。"""
    fill_service = CACHE_LINE * FILL_LAT   # 読みミス1件のサーバ占有時間

    st = {'busy_until': 0, 'queue': [], 'n_w': 0, 'n_absorb': 0, 'saved': 0.0}
    last_cyc = 0
    pend = None            # ★[v1.3] 直前の書込 (cyc, pa)。1件先読みでペア判定する★
    n_pair = 0             # ★[v1.3] 結合できたペア数（診断出力用）★

    with open(path, 'r') as f:
        for line in f:
            if not line or line[0] == '#':
                continue
            p = line.rstrip('\n').split(',')
            if len(p) != 4:
                continue
            try:
                cyc = int(p[0])
                pa  = int(p[1], 16) if p[1].lower().startswith('0x') else int(p[1], 16)
            except ValueError:
                continue
            kind, hit = p[2], p[3]
            last_cyc = cyc

            if kind == 'W':
                if pend is not None and abs(pa - pend[1]) == 1:
                    # ★アドレス連続の書込 2 件 = 16bit 書込のペア★
                    # 1 発目の到着時刻に、2 スロットまとめて投入する
                    _drain(st['queue'], pend[0])
                    _admit(pend[0], 2, D, S, base_wait, st)
                    n_pair += 1
                    pend = None
                else:
                    # 先に保留中の単独書込があれば先に流す（時系列順を保つ）
                    if pend is not None:
                        _drain(st['queue'], pend[0])
                        _admit(pend[0], 1, D, S, base_wait, st)
                    pend = (cyc, pa)
            else:
                # 読みが来たら、保留中の書込を先に流してから読みを処理する
                if pend is not None:
                    _drain(st['queue'], pend[0])
                    _admit(pend[0], 1, D, S, base_wait, st)
                    pend = None
                _drain(st['queue'], cyc)
                if hit == '0':
                    # 読みミス = ラインフィル。サーバを占有する（この間は排出できない）
                    start = max(cyc, st['busy_until'])
                    st['busy_until'] = start + fill_service

    if pend is not None:
        _drain(st['queue'], pend[0])
        _admit(pend[0], 1, D, S, base_wait, st)

    return st['n_w'], st['n_absorb'], st['saved'], last_cyc, n_pair


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
        print("usage: wbuf_sim_v1_3.py <trace> <C_eff> <stall_wr> [D...]", file=sys.stderr)
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

    print("wbuf_sim v1.3 (2026-09-08)  trace=%s" % path)
    print("  C_eff=%d  stall_wr=%d  writes=%d" % (c_eff, stall_w, n_w0))
    print("  base_wait = stall_wr/writes = %.4f cyc   upper bound = %.2f%%"
          % (base_wait, upper))
    print("  model: single-server (v19 v0.7 4.3.2), FILL=%d*%d, line=%dB"
          % (CACHE_LINE, FILL_LAT, CACHE_LINE))
    print("  [v1.3] 16bit write pairs bound by ADDRESS CONTIGUITY (not delta)")
    print("%-3s %-3s %10s %10s %10s %8s %12s %10s" %
          ("D", "S", "writes", "pairs", "absorbed", "alpha", "eff_reduc", "upper*a"))
    for D in depths:
        for S in (4, 5):          # ★実測4.000 と校正値5 の併記（M-3）★
            n_w, n_a, saved, last, n_pair = simulate(path, D, S, base_wait)
            alpha = (n_a / n_w) if n_w else 0.0
            eff   = saved / c_eff if c_eff else 0.0
            print("%-3d %-3d %10d %10d %10d %8.4f %11.2f%% %9.2f%%" %
                  (D, S, n_w, n_pair, n_a, alpha, eff * 100.0, upper * alpha))
    return 0


if __name__ == "__main__":
    sys.exit(main())
