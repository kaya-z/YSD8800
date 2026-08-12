**emu23 v1.05 改修設計書**

スタック watermark 計測機能の統合

Version 1.0  /  2026-06-06

| **項目** | **内容** |
| --- | --- |
| 文書番号 | EMU23-MOD-003 |
| 対象ツール | emu23 v1.04 → v1.05 |
| ISAバージョン | YSD8800 ISA2.3 |
| 関連設計書 | emu23_v103_design_v1_4.md (EMU23-MOD-002) / emu23_watermark_design v1.1 |
| 上位設計書 | yuios_tcb_design_v1_3.md §9 / yuios_memmap_design_v1_6.md |
| 作成日 | 2026-06-06 |
| ステータス | v1.0 ドラフト（レビュー前） |

# **改版履歴**

| **版** | **日付** | **変更内容** | **担当** |
| --- | --- | --- | --- |
| v1.0 | 2026-06-06 | 初版。emu23 v1.04 に各タスクのスタック high-water mark 計測機能（-w / --wm-steps / --wm-warmup）を統合し v1.05 とする。Ph.3.5-I-3-T で実験ビルド emu23_wm_v104w.c として実装・検証した watermark 機能のうち汎用部分のみを本流へ取り込む。試験専用機能（I-3 プール占有 HWM の $50A2 直読 = I3-POOL）は含めない。 | Claude |

# **1. 目的と背景**

## **1.1 改修の目的**

YUI OS は各タスクにコールスタック 128B・データスタック 128B（TCB 設計書 §9）を割り当てる。タスク数が増える Ph.5 ProcMgr 以降や Step 8 FPGA 移行前の品質確認において、各タスクのスタックが 128B 枠を超えていないか、stack guard が破壊されていないかを定量的に実測する手段が必要となる。本設計書はその計測機能を emu23 v1.05 へ統合する内容を定める。

## **1.2 v1.04 までの状態と課題**

emu23 v1.04 は SP を逐次更新するが、各タスクのスタックが最も深く侵食されたアドレス（high-water mark）を保持しない。スタック消費量を知るには手動トレースが必要で、タスク数が増えると非現実的。

## **1.3 v1.05 で実現すること**

- `-w` / `--watermark` 指定時、各タスク（tid 0〜15）のコール／データスタック最深値を測定し 128B 枠超過を検出。
- stack guard 領域（$FC00-$FC3F、OS が $A55A で設置）の破壊を検出。
- 常駐 OS（HALT しない）対応のため `--wm-steps N` で実行打切り上限を設ける。
- 起動初期の一過性 SP/X 値（§3.1 の誤検出）を除外する `--wm-warmup N` を設ける。
- `-w` 無指定時は v1.04 と完全に同一動作（非回帰）を保つ。
- 試験専用機能（I-3 プール占有 HWM 直読）は含めない（責務分離）。

# **2. watermark 計測機構**

## **2.1 測定対象（TCB 設計書 §9）**

| 領域 | 範囲 | 1タスク | 頂上(tid) |
| --- | --- | --- | --- |
| コールスタック | $F000-$F7FF | 128B | $F07E + tid×$80 |
| データスタック | $F800-$FBFF | 128B | $F87E + tid×$80 |
| stack guard | $FC00-$FC3F | 64B | $A55A 埋め |

## **2.2 測定方式（スロット別動的最小値追跡）**

exec_one() 実行ごとに、SP/X が各スタック領域内にあれば、所属する 128B スロット（= tid）別に最小値（最深点）を更新する。全体最深 1 個ではどのタスクが何バイト使ったか区別できないため、スロット別に記録する（Ph.3.5-I-3 実装中に判明した教訓）。X の範囲ガード（$F800-$FBFF 限定）で汎用 X 使用の誤検出を排除する。

## **2.3 使用バイト数の算出**

スタックは「空時 X=頂上+2、最初の push で X=頂上」規約のため、使用バイト = (頂上 − 最深値) + 2。スロット頂上 = 領域基底 + tid×$80 + $7E。

## **2.4 出力仕様**

`-w` 指定時、実行終了（HALT / 打切り / repl 終了）後に stderr へ出力する。stdout（UART 出力）は汚さない（非回帰維持）。call/data の各 tid 行、PEAK 行、guard 検査結果を出す。

## **2.5 常駐 OS への対応（--wm-steps）**

YUI OS はスケジューラが恒常的に回る常駐型で HALT しない。`-w` 指定時のみステップ上限 wm_max_steps（既定 2,000,000、--wm-steps N で変更）を設け、HALT 到達または上限到達でループを抜けて報告する。`-w` 無指定時は従来通り無制限（非回帰）。

# **3. 設計上の論点と実装中の知見**

## **3.1 ウォームアップ（--wm-warmup）の必要性**

カーネル起動 _kstart は、KERN_SP 領域初期化のための暫定値として一瞬 X=$F800 を設定する（データスタックポインタとしての使用ではない）。この一過性の X=$F800 が data tid=0 の最深値（128B 満杯）として誤検出される。対策として追跡を「cpu.cycle >= wm_warmup_cycles（既定 2000 cycle）」の後から開始する。warmup=0 で data tid=0=128B（誤検出）、warmup=500 以上で 8B（真値）に収束することを Ph.3.5-I-3 で実測確認済み。

## **3.2 guard 検査方式**

emu23 側で guard を埋めない。OS が _kstart で $FC00-$FC3F を $A55A で設置するため、emu23 は終了時にこのパターンの維持を走査し、1 ワードでも化けていれば VIOLATED とする。

## **3.3 試験専用機能（I3-POOL）を含めない理由**

I-3 実験ビルドの I3-POOL 出力は試験版カーネルの ASM フックが $50A2 に書く前提で、本番カーネルには無意味。汎用ツールに混ぜると紛らわしいため v1.05 には含めない（責務分離）。

# **4. 影響範囲と互換性**

| **機能** | **影響** | **互換性** |
| --- | --- | --- |
| 全命令デコード/実行 | 変更なし | ◎ 後方互換 |
| -w 無指定時の全動作 | wm_enable 判定で skip | ◎ 完全非回帰（実測一致） |
| stdout(UART) 出力 | watermark は stderr のみ | ◎ 非汚染 |
| -q モード | -w 指定時のみ上限。無指定は無制限 | ◎ 後方互換 |
| Dhrystone 計測 | -w 無指定で従来一致 | ◎ 影響なし（回帰 PASS） |

## **4.1 起動バナー表示**

```
emu23 v1.05 (2026-06-06) for YSD8800 ISA2.3
  - v1.05: stack watermark 計測機能統合 (-w)
  - YSD8003 deferred completion IRQ (delay=512 cycles)
  - v1.04: DBG printf removed
  - YSD8004 irq_pending overwrite protection + IRQ_STAT re-evaluation
```

usage 追加：
```
  -w,--watermark    measure per-task stack high-water mark (stderr)
  --wm-steps N      step limit for -w on resident OS (default 2000000)
  --wm-warmup N     skip first N cycles for -w (default 2000)
```

# **5. 回帰テスト計画と結果（2026-06-06 実施）**

| **No.** | **テスト** | **期待値** | **結果** |
| --- | --- | --- | --- |
| T1 | 起動バナー | v1.05 表示 | PASS |
| T2 | 非回帰（-w 無指定で v1.04 と stdout/disk 比較） | 完全一致 | PASS（stdout=0A BC123MPDQLORSCWVXY・disk 一致） |
| T3 | Dhrystone 回帰 | v1.04 と一致 | PASS |
| T4 | watermark 機能（本番 OS を -w） | PEAK 出力・guard intact | PASS（callstk 24B/datastk 16B/guard intact） |
| T5 | I3-POOL 非搭載 | -w 出力に I3-POOL 行が無い | PASS |

# **6. 実装手順**

1. watermark グローバル変数群を mem[] 宣言直後に追加。
2. wm_report() を exec_one() 定義の直前に追加。
3. exec_one() 末尾にスロット別追跡（ウォームアップ判定付き）を追加。
4. main 冒頭でスロット配列を 0xFFFF 初期化。
5. 引数解析に -w / --watermark / --wm-steps / --wm-warmup を追加。
6. -q ループにステップ上限と wm_report() を追加。repl() 後にも wm_report()。
7. 起動バナー・usage を v1.05 に更新。ファイル冒頭に版数コメント。

ビルド：`gcc -O2 -o emu23 emu23_v105.c`

# **7. KY (危険予知)**

(a) X の範囲ガード誤りで汎用 X を誤検出 → $F800-$FBFF 限定で排除済み。
(b) 起動初期の一過性 SP/X 値の誤検出 → ウォームアップ（§3.1）で対処。閾値過大だと実ピークを取り逃すため既定 2000 cycle。
(c) -w が stdout を汚すと UART 判定・Dhrystone 回帰が壊れる → stderr 限定（T2/T3 で確認）。
(d) 試験専用機能の混入 → 責務分離のため非搭載（§3.3）。
