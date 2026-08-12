# emu23 stack-watermark 拡張 設計書

**Version:** 1.1
**作成日:** 2026-06-05
**改版:** 2026-06-05（v1.1: 常駐OS非HALT問題への対応・ステップ上限到達時の出力追加）
**対象工程:** Ph.3.5-I-3-T（I-3 負荷試験の前段：emu23 計測機能拡張）
**対象ツール:** emu23 v1.04 → 実験ビルド `emu23_wm_v104w.c`（KY38：本番 emu23_v104.c は無改変）
**前提文書:** yuios_tcb_design_v1_3.md §9（スタック領域配置）／yuios_memmap_design_v1_6.md
**ステータス:** ドラフト（実装検証中）

---

## 改版履歴

| 版 | 日付 | 内容 |
|---|---|---|
| v1.0 | 2026-06-05 | 初版。動的最小値追跡＋guard検査。設計中に guard 検査方式を OS 設置 $A55A 維持検査へ訂正。 |
| v1.1 | 2026-06-05 | **常駐 OS は HALT しない**ため `-q` の HALT 後出力では watermark が出ないことが実装検証で判明（exit=124 timeout）。`-w` 時にステップ上限を設け、HALT 到達 or 上限到達のいずれでも wm_report を呼ぶ方式に訂正（§4.1 追加）。Dhrystone 単体は startup_harness が独自 SP を使い $F000-$F7FF に偶発侵入するため誤検出が出る点を §7 WM-K1 に明記。 |

---

## 1. 目的

Ph.3.5-I-3 負荷試験（16タスク同時 CALL・最悪 in-flight=16）において、
コールスタック／データスタックの**実消費量（high-water mark）**を定量測定し、
TCB 設計書 §9 が確保した 1タスク=128B（コール）/128B（データ）に対して
オーバーフローが起きないことを実測で裏取りする。

現行 emu23 は SP を逐次更新するが、「各タスクのスタックが**最も深く**侵食された
アドレス」を保持していない。本拡張で watermark 追跡を追加する。

## 2. 測定対象アドレス（TCB設計書 §9 確定値）

| 領域 | 範囲 | 1タスク | 成長方向 |
|---|---|---|---|
| コールスタック | $F000–$F7FF（2KB） | 128B（tid×$80） | 高位→低位（SP減算） |
| データスタック | $F800–$FBFF（2KB） | 128B | 高位→低位（X減算） |
| stack guard | $FC00–$FC3F（64B） | — | $A55A 埋め |

タスク tid のコールスタック頂上 = `$F07E + tid×$80`（偶数化済・memmap §6.4.3）。
底（最深許容） = 頂上 − 127。これを割ると隣タスク領域へ侵食＝オーバーフロー。

## 3. 測定方式（fill-and-scan 方式）

**SP/X の動的最小値追跡方式**を主方式とする。fill-scan は本 OS が起動時に
領域をゼロクリア／パターン埋めするため不採用。

**guard 検査の方式（訂正）**: emu23 側で guard 領域を埋めることはしない。
OS（kernel K-mem3）が `_kstart` で stack guard $FC00-$FC3F を **`$A55A`** で
埋めるため、emu23 はこの OS 設置パターンが実行後も維持されているかを
終了時に走査する。1ワードでも $A55A 以外に化けていればスタック突き抜けと
判定し VIOLATED とする（emu23 の事前埋めは OS 初期化と競合するため廃止）。

### 3.1 動的最小値追跡（主方式）

`exec_one()` 実行後に毎回：
```c
if (cpu.sp >= CALLSTK_LO && cpu.sp <= CALLSTK_HI && cpu.sp < callsp_min)
    callsp_min = cpu.sp;
if (cpu.x  >= DATASTK_LO && cpu.x  <= DATASTK_HI && cpu.x  < datax_min)
    datax_min  = cpu.x;
```
- `CALLSTK_LO=0xF000, CALLSTK_HI=0xF7FF`
- `DATASTK_LO=0xF800, DATASTK_HI=0xFBFF`
- X はデータスタックポインタとしてのみ意味を持つため、上記範囲にある時だけ
  追跡する（X は汎用にも使われるが、範囲ガードで誤検出を排除）。
- SP は範囲外（$FC7E 初期値・カーネルスタック $4700-$477F）の間は無視。

### 3.2 タスク別 watermark（オプション）

CUR_TASK（カーネル変数）が判れば tid 別に分離測定できるが、アドレスは
memmap 依存。本フェーズでは**領域全体の最深値**のみ測定し、tid 別は
「最深 SP が属する 128B スロット」から逆算して報告する（tid = (HI−sp)/$80）。

## 4. 出力仕様

`-q` モード（負荷試験で使用）終了時、HALT 後に stderr へ1ブロック出力（§4.1 の
上限到達時も同様）：
```
[WATERMARK] callstk: min_sp=$F4xx depth=NN B (slot tid=t, F000-F7FF)
[WATERMARK] datastk: min_x =$FAxx depth=NN B (slot tid=t, F800-FBFF)
[WATERMARK] guard $FC00-$FC3F: intact / VIOLATED
```
- `-q` の stdout は UART 出力のみ（非回帰維持）。watermark は **stderr** へ。
- guard 領域は OS が起動時に `$A55A` で埋める。emu23 は終了時にこの維持を
  走査し、1ワードでも化けていれば VIOLATED（スタック突き抜け検出）。

### 4.1 常駐 OS（非 HALT）への対応（v1.1 新設）

YUI OS はスケジューラが恒常的に回り続ける**常駐型**で HALT しない。よって
`-q` の `while(!cpu.halted)` ループは抜けず、HALT 後の `wm_report()` に到達しない
（v1.0 実装で exit=124 timeout を実測）。

対策：`-w` 指定時に限り `-q` ループへ**ステップ上限** `WM_MAX_STEPS`（既定
2,000,000 命令）を設け、`HALT 到達` または `上限到達` のいずれでもループを抜けて
`wm_report()` を呼ぶ。負荷試験の UART 出力（総合試験なら `…Y` まで）は上限到達
前に完了するため、watermark は確定済みの値が得られる。

```c
if (quiet_mode) {
    uint64_t steps = 0;
    while (!cpu.halted) {
        exec_one();
        if (wm_enable && ++steps >= WM_MAX_STEPS) break;  /* 常駐OSの打切り */
    }
    fflush(stdout);
    wm_report();
    return 0;
}
```
- `-w` 無指定時は従来通り上限なし（完全非回帰）。
- 上限値は `--wm-steps N` で上書き可能とする（負荷試験で長時間回す場合に対応）。

## 5. 起動オプション

`--watermark`（または `-w`）指定時のみ測定・出力。無指定時は完全に従来動作
（性能・出力とも非回帰）。

## 6. 実装差分（最小侵襲）

| 箇所 | 変更 |
|---|---|
| グローバル | `static int wm_enable=0; static uint16_t callsp_min=0xFFFF, datax_min=0xFFFF;` |
| 定数 | CALLSTK_LO/HI・DATASTK_LO/HI・GUARD_LO/HI |
| main 引数解析 | `--watermark`/`-w` で `wm_enable=1`（guard は OS が埋めるため emu23 は埋めない） |
| exec_one 直後 | wm_enable 時に §3.1 の最小値追跡（-q ループ・REPLループ両方） |
| 終了処理 | §4 の出力（-q の HALT 後、repl の q 後）。guard は OS 設置 $A55A の維持を検査 |
| バナー | `emu23 v1.04+wm` と表示しバージョン識別 |

合計：約 +40 行。命令デコード部は無改変。

## 7. KY（本拡張固有）

- **WM-K1**: X の範囲ガードを誤ると汎用 X 使用を誤検出。$F800-$FBFF 限定で誤検出排除。
  なお **Dhrystone 等の OS 非搭載単体プログラムは startup_harness が独自 SP を設定し
  $F000-$F7FF 領域に偶発侵入するため、watermark は誤検出（OVER 128B/guard VIOLATED）を
  出す。watermark 機能は YUI OS 搭載前提であり、単体プログラムへの適用は意味を持たない**
  （Dhrystone 回帰は `-w` 無指定で行うこと）。
- **WM-K2**: 本番 emu23_v104.c を改変しない（KY28/38）。実験ビルド名 `emu23_wm_v104w.c`。
- **WM-K3**: `-q` stdout を汚さない。watermark は stderr 限定（Python照合・UART判定の非回帰維持）。
- **WM-K4**: emu23 改修につき Dhrystone 回帰が必要（toolchain改修規則）。ただし
  本拡張は `--watermark` 無指定時に従来パスと完全一致するため、無指定での
  Dhrystone PASS で回帰確認とする。

## 8. レビュー観点

- [ ] §3.1 の範囲ガードで X 誤検出が排除できるか（汎用 X が $F800-$FBFF を指す瞬間はないか）
- [x] guard 検査は emu23 で埋めず OS 設置 $A55A の維持を見る方式に訂正済み（§3冒頭）
- [ ] tid 逆算式 (HI−sp)/$80 の妥当性
- [ ] `-q` 非回帰（stdout 不変）

---
*--- 以上（ドラフト v1.0・レビュー前）---*
