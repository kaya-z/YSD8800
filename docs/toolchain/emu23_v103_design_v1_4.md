**emu23 v1.03 改修設計書**

YSD8003 ストレージ完了 IRQ 遅延化 / YSD8004 IRQ pending 保護

Version 1.4  /  2026-05-03

| **項目** | **内容** |
| --- | --- |
| 文書番号 | EMU23-MOD-002 |
| 対象ツール | emu23 v1.02 → v1.03 |
| ISAバージョン | YSD8800 ISA2.3 |
| 関連設計書 | emu23_device_design_v1_2.docx (デバイス仕様) |
| 上位設計書 | yuios_design_v2_0.docx §6.3 ストレージドライバ |
| 作成日 | 2026-05-03 |
| ステータス | v1.4 ドラフト（レビュー前） |

# **改版履歴**

| **版** | **日付** | **変更内容** | **担当** |
| --- | --- | --- | --- |
| v1.4 | 2026-05-03 | 初版（v1.3 = v1.02改修設計書 を継承し v1.4 として新規作成）。YSD8003 EXEC 完了 IRQ の遅延化機構（512 サイクル後発火）と、YSD8004 ysd8004_raise() の IRQ pending 上書き保護（既知課題K1暫定対処）を追加。 | Claude |

# **1. 目的と背景**

## **1.1 改修の目的**

YUI OS Ph.3-B ストレージドライバ実装にあたり、emu23 v1.02 の YSD8003 完了 IRQ 機構には以下の問題がある。本設計書はこれらを解決するための emu23 v1.03 への改修内容を定める。

## **1.2 v1.02 の問題点**

| **項目** | **v1.02 の状態** | **問題点** |
| --- | --- | --- |
| YSD8003 EXEC 完了 IRQ | EXEC（SD_CMD=2）書き込みと同じ命令サイクル内で IRQ1 を pending 化 | ドライバが SD_CMD 書き込み後に WAIT-IPC で寝る前に IRQ1 が来る恐れがある（タイミング順序が破綻） |
| ysd8004_raise() の cpu.irq_pending 設定 | `cpu.irq_pending = 2;` で無条件上書き | 高優先 IRQ0（タイマー）/IRQ3（アラインメント）を蹴落とす可能性（既知課題 K1） |
| 実 SD カードとの乖離 | 完了が同期的・即時 | FPGA + 実 SD カード移行時に「数百μsec〜msec オーダーの完了遅延」を再現できない |

## **1.3 v1.03 で実現すること**

- YSD8003 EXEC 完了 IRQ を「N サイクル後に発火」する遅延機構を追加（N=512 サイクル）
- ysd8004_raise() に IRQ pending 上書き保護を追加（既知課題 K1 暫定対処）
- 既存機能（UART RX/TX IRQ、タイマー IRQ0、Dhrystone 計測、SD_DATA PIO 転送、BUSY ラッチ）への後方互換性を保つ
- v1.02 で動作確認済みの全テスト（yuios_v10.bin 期待出力 ABCXD、Ph.2 回帰 M28AR、Dhrystone 826 DPS）の回帰維持

# **2. YSD8003 完了 IRQ 遅延機構**

## **2.1 設計方針**

EXEC（SD_CMD=2）書き込み時に即座に IRQ1 を発火するのではなく、512 サイクル後に発火する。これにより、ドライバタスクが「IRQ_CTRL を有効化 → SD_CMD ← 2 → WAIT-IPC」の順序を実行する時間を確保する。

データ自体（fread/fwrite）は EXEC 受理時に同期実行する。これは「データの確定タイミング」と「完了通知（IRQ）タイミング」を分離する意図である。BUSY ラッチも EXEC 受理時に立て、IRQ 発火と同時には変化させず、ドライバが SD_STAT を 1 回読み出した時点でクリアする（v1.02 の仕様を踏襲）。

【設計判断の根拠】

- 実 SD カード（FPGA 実装時）では PIO 転送中に CPU が他のタスクを走らせられる必要がある。完了 IRQ はマイクロ秒〜ミリ秒オーダー後の非同期通知である。
- エミュレータ上では再現性のあるテストのため固定サイクル数とする。
- 512 サイクルは「512B PIO 転送相当（1 byte/cycle）」という直感的な値で、Dhrystone 影響は極小（1 EXEC あたり 512 サイクルの遅延カウンタ更新コストが最大）。

## **2.2 状態変数**

emu23_v103.c に以下の static 変数を追加する。

| **変数名** | **型** | **初期値** | **用途** |
| --- | --- | --- | --- |
| sd_irq_delay | int | 0 | 残りサイクル数。0=非予約、>0=予約中。1 サイクル毎に -1。 |

【KY 防止策反映】 sd_irq_delay は必ず 0 で初期化する（起動直後の偽 IRQ 発火を防止）。

## **2.3 状態遷移**

```
[非予約] sd_irq_delay == 0
    │
    │ EXEC 受理 (SD_CMD ← 2) かつ IRQ_CTRL bit0 == 1
    ▼
[予約中] sd_irq_delay > 0
    │
    │ 命令毎 sd_irq_delay--
    │
    │ sd_irq_delay が 0 に到達
    ▼
[IRQ 発火] ysd8004_raise(IRQ_STAT_BIT_STOR) を呼び出し
    │
    ▼
[非予約] sd_irq_delay == 0
```

## **2.4 EXEC 受理時の動作**

emu23_v102.c L498-525（SD_CMD 書き込みハンドラの EXEC 分岐）を以下に変更する。

| **タイミング** | **v1.02 動作** | **v1.03 動作（新規）** |
| --- | --- | --- |
| EXEC 受理（SD_CMD ← 2） | sd_busy_latch=1 / sd_stat=0x00 / sd_buf_ptr=0 / fread or fwrite 実行 / sd_stat = READY or ERROR / IRQ_CTRL bit0=1 なら ysd8004_raise() 即時発火 | sd_busy_latch=1 / sd_stat=0x00 / sd_buf_ptr=0 / fread or fwrite 実行 / sd_stat = READY or ERROR / **IRQ_CTRL bit0=1 なら sd_irq_delay = 512 を設定（即時発火しない）** |
| sd_irq_delay 既存値 | 該当なし（即時方式） | **EXEC 受理時に sd_irq_delay の既存値を強制クリアしてから新規値を設定（多重予約防止）** |

【KY 防止策反映】 多重予約防止のため、EXEC 受理時は sd_irq_delay = 512 と直接代入する（前値を見ない）。これにより連続 EXEC 時の干渉を防ぐ。

## **2.5 命令ループへの組み込み**

emu23 のメイン命令ループ（DECODE/EXEC ステージ）に、以下の遅延カウンタ更新処理を追加する。

```c
/* メイン命令ループ内、IRQ チェックの直前に追加 */
if (sd_irq_delay > 0) {
    sd_irq_delay--;
    if (sd_irq_delay == 0) {
        ysd8004_raise(IRQ_STAT_BIT_STOR);
    }
}
```

【設計判断】 命令毎に -1 する方式とする。CPU の実サイクル数で減算する方式（命令毎に cycles 分減算）も考慮したが、実装単純性と Dhrystone 影響低減を優先して命令毎 -1 を採用する。

【影響範囲】 全命令ループに 1 つの分岐と 1 つのデクリメントが追加される。Dhrystone 計測時は sd_irq_delay = 0 で保持されるため、追加コストは「分岐 1 回（不成立）」のみ。

## **2.6 ディスク未接続時の動作**

disk_fp == NULL の場合：

| **項目** | **v1.02 動作** | **v1.03 動作** |
| --- | --- | --- |
| sd_stat | 0x02 (ERROR) を設定 | 同左（変更なし） |
| IRQ 発火 | IRQ_CTRL bit0=1 なら即時発火 | **IRQ_CTRL bit0=1 なら sd_irq_delay = 512 で予約**（エラーも遅延 IRQ で通知） |

【設計判断の根拠】 エラーも遅延 IRQ で通知することで、ドライバ側のコード経路を「正常時/エラー時」で統一できる。ドライバは IRQ ハンドラで起こされた後、SD_STAT を読んで bit1 (ERROR) の有無で判定する。

# **3. YSD8004 IRQ pending 保護**

## **3.1 設計方針（既知課題 K1 暫定対処）**

ysd8004_raise() 内で `cpu.irq_pending = 2;` と無条件上書きしている箇所を、既存の高優先 IRQ を保護するロジックに変更する。これは Ph.3 完了後の独立工程「IRQ 優先制御見直し」の本格対応までの暫定対処である。

【保護対象の優先順位（emu23_device_design_v1_2.docx §3.1 より）】

| **優先順位** | **IRQ 番号** | **cpu.irq_pending 値** |
| --- | --- | --- |
| 0（最高） | IRQ3（アラインメント） | 3 |
| 1 | IRQ0（YSD8002 タイマー） | 1 |
| 2 | IRQ1（YSD8004 経由） | 2 |
| 3 | IRQ2（予備） | （未使用） |
| 4（最低） | IRQ4（SYSCALL） | 4 |

## **3.2 保護ロジック**

ysd8004_raise() L194 の `cpu.irq_pending = 2;` を以下に変更する。

```c
/* IRQ pending 保護: 既存の高優先 IRQ（IRQ3=3, IRQ0=1）を蹴落とさない */
/* IRQ1（=2）より低優先または非アサート時のみ pending を更新 */
if (cpu.irq_pending == 0 || cpu.irq_pending > 2) {
    cpu.irq_pending = 2;  /* IRQ1 として pending */
}
/* irq_stat へのビットセットは既に行われているので、
   IRET 後の再評価で IRQ1 が拾われる可能性は残る */
```

【ロジック解説】

- `cpu.irq_pending == 0`: 何も pending していない → IRQ1 に設定 OK
- `cpu.irq_pending > 2`: IRQ4（SYSCALL）が pending → IRQ1 で上書き OK（IRQ1 の方が高優先）
- `cpu.irq_pending == 1`: IRQ0（タイマー）pending → 上書きしない（タイマーを蹴落とさない）
- `cpu.irq_pending == 2`: IRQ1 既に pending → 上書き不要（同じ値）
- `cpu.irq_pending == 3`: IRQ3（NMI）pending → 上書きしない（NMI を蹴落とさない）

## **3.3 irq_stat の扱い**

irq_stat レジスタへのビット OR セット（L192 `irq_stat |= allowed;`）は無条件で実行する。これにより：

- 高優先 IRQ により IRQ1 への遷移が一時的にブロックされても、irq_stat にはビットが残る
- IRQ0/IRQ3 ハンドラ実行中も irq_stat = 0x0002 等は保持される
- IRET 後の再評価で IRQ1 が改めて pending 化される（ISA2.3 ハンドラ仕様 §3.2）

【補足】 ただし、ISA2.3 の IRET 後再評価が irq_stat の非 0 を見て自動的に IRQ1 を再 pending 化する機構を持っているかは別途確認が必要（v1.02 実装での挙動確認）。本対処はあくまで「上書きを防ぐ」ことに主眼を置く。万一 IRET 後再評価が機能しない場合、ドライバが irq_stat をポーリングで補助する設計としても良い（§5 で議論）。

【KY 防止策反映】 既存の UART RX IRQ（IRQ_STAT_BIT_UART_RX = 0x0001）と TX IRQ（0x0004）が IRQ0 / IRQ3 と同時発生したケースで取りこぼされないか、回帰テストで必ず確認する。

# **4. 影響範囲と互換性**

## **4.1 既存機能への影響**

| **機能** | **影響** | **互換性** |
| --- | --- | --- |
| UART RX IRQ (IRQ_STAT_BIT_UART_RX) | ysd8004_raise() の保護ロジック変更のみ | ◎ 後方互換 |
| UART TX IRQ (IRQ_STAT_BIT_UART_TX) | 同上 | ◎ 後方互換 |
| YSD8002 タイマー IRQ0 | 保護対象（タイマー優先） | ◎ 改善（v1.02 では蹴落とされる可能性あり） |
| アラインメント例外 IRQ3 | 保護対象（NMI 優先） | ◎ 改善 |
| SD_DATA PIO 転送 | 変更なし | ◎ 後方互換 |
| BUSY ラッチ | 変更なし | ◎ 後方互換 |
| disk_fp なし時のエラー応答 | エラーも遅延 IRQ で通知に変更 | △ 微変更（ドライバが IRQ 待ち前提なら正常動作） |
| Dhrystone 計測 | sd_irq_delay = 0 で保持されるため、分岐 1 回のオーバーヘッドのみ | ◎ 影響極小 |
| yuios_v10.bin (ABCXD) | UART のみ使用、ストレージ未使用 | ◎ 後方互換 |
| Ph.2 回帰 (M28AR) | ストレージ未使用 | ◎ 後方互換 |

## **4.2 起動バナー表示**

emu23 起動時のバージョン表示を v1.02 → v1.03 に変更する（規約：ツール改修時はバージョン表示）。

```
emu23 v1.03 (2026-05-03) - YSD8800 ISA2.3 Emulator
  - YSD8003 deferred completion IRQ (delay=512 cycles)
  - YSD8004 irq_pending overwrite protection
```

# **5. 設計上の論点（レビュー対象）**

## **5.1 R1: 遅延サイクル数の妥当性**

【提案値】 512 サイクル

【論点】

- 512 = 1 byte/cycle × 512B/sector の直感的計算
- emu23 で IRQ 受理→ハンドラ起動には 20-30 命令程度（経験則）かかるため、512 サイクルあれば十分余裕がある
- Dhrystone への影響は分岐 1 回/命令のみ（実測で 0.1% 程度の劣化想定）

【代替案】

- 256 サイクル：最小、PIO 全体相当（ただし余裕少なめ）
- 1024 サイクル：2 cycle/byte で余裕大

【レビュー確認事項 RR1】 512 サイクルで合意するか。

## **5.2 R2: IRET 後再評価の機能性**

【論点】 §3.3 で言及した「IRET 後再評価で IRQ1 が再 pending 化される機構」が emu23 v1.02 に実装されているか。実装されていない場合、保護ロジックが「タイマー IRQ0 と同時発生時に IRQ1 が永久に来ない」現象を引き起こす可能性がある。

【対応案】

(a) emu23 ソース確認で IRET 後再評価ロジックを追跡し、必要なら v1.03 で追加実装

(b) ドライバ側で「IRQ_CTRL を一旦 0 にして再度 1 に戻す」ことで再エッジを発生させる回避策

(c) ドライバ側にタイムアウトポーリング（例：IRQ 待ちが 10000 サイクル経過したら SD_STAT を直接ポーリング）

【レビュー確認事項 RR2】 (a) を本工程で対処するか、(b)(c) のドライバ側回避で済ませるか。

【設計者見解】 (a) を推奨。IRET 後再評価は他の既知課題（K1 本格対処）でも必要になる機構で、Ph.3-B 設計書側で「ドライバは IRQ_CTRL を再投入する」と仕様化するのは仕様の不自然化を招く。

## **5.3 R3: エラーも遅延 IRQ で通知することの是非**

§2.6 で「disk_fp == NULL でも sd_irq_delay = 512 で予約」としたが、即時エラー応答（sd_stat = ERROR を即時返してドライバがポーリング）の方が単純という考え方もある。

【設計者見解】 ドライバ実装の単純化のため、エラーも遅延 IRQ で通知する。これによりドライバは「EXEC → WAIT-IPC → 起こされる → SD_STAT を読む → 正常/エラー判定」の単一経路で済む。

【レビュー確認事項 RR3】 この方針で合意するか。

## **5.4 R4: irq_stat 保持と IRET 後再評価の整合**

§3.3 で irq_stat へのビットセットは無条件と定義したが、IRET 後再評価機構が実装されていない場合、ビットだけ立って IRQ1 に遷移しないままドライバが永久ブロックする可能性がある。

【対応】 §5.2 R2 と関連。emu23 ソース確認後に実装方針確定。

# **6. 回帰テスト計画**

## **6.1 必須回帰テスト**

| **No.** | **テスト** | **コマンド** | **期待値** | **備考** |
| --- | --- | --- | --- | --- |
| T1 | 起動バナー | `./emu23` | v1.03 表示 | バージョン表示確認 |
| T2 | yuios_v10 (Ph.3-A5 UART) | `./emu23 yuios_v10.bin yuios_v10.sym -i uart_test_input.bin -q` | ABCXD | UART RX/TX IRQ への影響なしを確認 |
| T3 | Ph.2 回帰 (MemMgr) | `./emu23 yuios_v09.bin yuios_v09.sym -q` | M28AR | IPC4 への影響なしを確認 |
| T4 | Dhrystone | `./emu23 dhry_final.bin -q` | 826 DPS（±5%許容） | 性能劣化なしを確認 |

## **6.2 新規追加テスト（v1.03 確認用）**

| **No.** | **テスト** | **方法** | **期待値** |
| --- | --- | --- | --- |
| T5 | sd_irq_delay 単体 | テスト用 .asm で SD_CMD=2 書き込み後 600 サイクル NOP、IRQ1 ハンドラに到達するか | 到達 |
| T6 | sd_irq_delay 早期チェック | T5 と同じだが 400 サイクル時点で irq_stat を読む | bit1 = 0 (まだ未発火) |
| T7 | 多重 EXEC 防止 | EXEC 受理 → 100 サイクル後に再度 EXEC → 残り 412 サイクル後に IRQ1 1 回のみ発火 | IRQ ハンドラ 1 回のみ呼ばれる |
| T8 | IRQ pending 保護 | タイマー IRQ0 と SD 完了 IRQ1 を同時発生させる | タイマー優先で受理、IRET 後 IRQ1 受理（要 §5.2 確認） |

## **6.3 sd_sample.c による既存テスト**

emu23 v1.02 まで動作していた sd_sample.c は IRQ_CTRL を無効（=0）にして使う前提のため、ポーリング方式で動作する。このテストも回帰として実施する：

```bash
./scc23 -o sd_sample.asm sd_sample.c
./hasm23 sd_sample.asm
./lnk23 sd_sample.lds
dd if=/dev/zero of=disk.img bs=512 count=2048
./emu23 sd_sample_final.bin -q --disk disk.img
```

期待出力（v1.02 と同じ） を確認すること。

# **7. 実装手順**

## **7.1 ソース改修順序**

1. `static int sd_irq_delay = 0;` を追加（YSD8003 関連変数の近く）
2. ysd8004_raise() に IRQ pending 保護ロジック追加
3. SD_CMD 書き込みハンドラ EXEC 分岐を改修（即時発火 → sd_irq_delay = 512 設定）
4. メイン命令ループに sd_irq_delay デクリメント+発火処理を追加
5. 起動バナー文字列を v1.02 → v1.03 に変更
6. ファイル冒頭コメントの版数履歴を更新

## **7.2 ビルド・配置**

```bash
gcc -std=c99 -O2 -w emu23_v103.c -o emu23
```

emu23 バイナリを既存 emu23 と置換。

## **7.3 動作確認順序**

1. T1（起動バナー） → T4（Dhrystone） で基本機能を先に確認
2. T2 → T3 で既存 OS 機能の回帰確認
3. T5 → T8 で v1.03 新機能の確認

# **8. KY (危険予知)**

【危険】 命令ループに毎サイクルカウンタ更新処理を追加することで以下のリスクがある：

(a) sd_irq_delay 初期値設定漏れ → 起動直後に偽 IRQ 発火

(b) EXEC 受理時のカウンタ既存値クリア漏れ → 連続 EXEC 時に古い遅延が干渉

(c) disk_fp == NULL 時に IRQ 予約しないと、永久に来ない IRQ で WAIT-IPC 永久ブロック

(d) 保護ロジックの条件式を誤ると、UART IRQ が取りこぼされる

【防止策】

- (a): `static int sd_irq_delay = 0;` で必ず 0 初期化
- (b): EXEC 受理時に `sd_irq_delay = 512;` と直接代入（前値を見ない）
- (c): エラー時も sd_irq_delay = 512 で予約（§2.6 確定）
- (d): 改修前に yuios_v10.bin と dhry_final.bin のベースライン記録、改修後に必ず両方の回帰テストを実施
- 全条件分岐をユニットテスト T5-T8 で網羅確認

# **9. 関連文書**

| **文書** | **版数** | **備考** |
| --- | --- | --- |
| emu23_device_design_v1_2.docx | v1.2 | YSD8001/8002/8003/8004 デバイス仕様 |
| emu23_v102_design_v1_3.docx | v1.3 | v1.02 改修設計書（前版） |
| ISA2_3_v231.docx | v2.3.1 | YSD8800 ISA2.3 仕様書（IRQ 仕様） |
| ysd8001_uart_design_v1_2.docx | v1.2 | YSD8001 UART チップ仕様 |
| ysd8002_timer_design_v1_0.docx | v1.0 | YSD8002 タイマー仕様 |
| yuios_design_v2_0.docx | v2.0 | YUI OS 全体設計（§6.3 ストレージドライバ） |
| HANDOVER_CHAT20.md | v1.0 | Chat #19→#20 引継ぎ |

# **10. レビュー確認事項一覧**

| **No.** | **項目** | **§** | **内容** |
| --- | --- | --- | --- |
| RR1 | 遅延サイクル数 | §5.1 | 512 サイクルで合意するか |
| RR2 | IRET 後再評価の対応 | §5.2 | (a) emu23 で対処 / (b)(c) ドライバ回避 のいずれを採用するか |
| RR3 | エラーも遅延 IRQ 通知 | §5.3 | この方針で合意するか |
| RR4 | irq_stat 保持の整合 | §5.4 | RR2 とセットで決定 |
| RR5 | 起動バナー文言 | §4.2 | 表示文字列の妥当性 |
| RR6 | 回帰テスト範囲 | §6 | T1-T8 で網羅性 OK か |

— 以上 —
