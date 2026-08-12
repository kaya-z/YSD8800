# HANDOVER_CHAT102.md

- **作成日**: 2026-07-18
- **前チャット**: HANDOVER_CHAT101.md（V5 完了・大きな節目）
- **本チャットの担当**: ①emu23 v1.10 FPGA不適切実装 再点検 → ②ナレッジ整理
- **結論**: 担当2工程とも **完了**。実削除はユーザ操作待ち。次工程は③EN是正工程（要レビュー承認）。

---

## 0. 最優先: セッション開始時にやること

1. 本HANDOVERを確認
2. `claude_tool_operation_guide_v1_0.txt` を1回参照（規律1〜5）
3. **「進捗と予定の確認(latest)」チャットの最新ロードマップ**を参照し工程確認（古い情報に注意・最新か判断）
4. KY活動を1つ挙げ防止策を実行
5. 「ご安全に！」で作業開始

---

## 1. 工程位置

| 工程 | 状態 |
|---|---|
| FPGA V5（YSD8002タイマー）S1〜S10 | ✅完了（2026-07-18・CHAT101） |
| ①emu23 v1.10 再点検 | ✅**完了（本チャット）** |
| ②ナレッジ整理（削除候補確定） | ✅**完了（本チャット）**・実削除はユーザ操作待ち |
| ③EN是正工程（TCR EN=OR→AND） | ⬜**次工程**・レビュー承認待ち |
| V6以降 | ⬜ EN是正の後 |

> **latest反映依頼（CHAT101から継続・未確認）**: 「V6の前にEN是正工程を挿入」が
> latestロードマップに反映済みか要確認。未反映ならユーザ更新が必要。

---

## 2. 本チャットの成果物

本チャットは **read-only 徹底**（KY防止策：再点検・棚卸しで実源を改変しない）。
新規ソース生成なし。成果は「判定・申し送り」であり本HANDOVERに集約。

- 実源（emu23_v110.c / RTL / 設計文書）への改変: **一切なし**
- 生成物: 本HANDOVER_CHAT102.md のみ

---

## 3. ①emu23 v1.10 再点検 結果（重要）

**総括: 原則73（emu都合を仕様と誤認）の観点での重大な乖離は発見されず。**
RTL(`ysd8800_ysd8002_v0_2.sv`)はemu23の行番号まで参照して意図的に整合させており契約は健全。

| # | 論点 | 判定 | 根拠 |
|---|---|---|---|
| 1 | SW_START/STOP/SCORE がemu固有か | ✅シロ（契約実装） | RTL L315-324 実装。`score=cycle-sw_start`(L322)がemu L713と一致。sim_impl_policy違反なし |
| 2 | Dhrystones/sec表示(fprintf) | ⚠ホスト固有（正しい境界） | スコア確定=ハード責務、dps算出/stderr表示=ホスト固有。RTL非実装は正しい |
| 3 | TCRマスク0x37のemu/RTL一致 | ✅一致 | emu L695 / RTL bit0/1+2/3/5で等価 |
| 4 | IRQ_ACK(bit5)挙動 | ✅一致 | emu L701-704 / RTL L305-314（rearm+自動クリア） |
| 5 | iret_pulse_o廃止の徹底 | ✅廃止済 | 計測はMMIO SW機構に一本化 |
| 6 | **fire_en の OR/AND** | 🔧既知負債 | emu L696/RTL L193 とも**一致してOR**。EN是正で両側AND化 |

### ③EN是正工程への申し送り
1. AND化は **emu L696 と RTL L193 の両方**を修正（片側だと乖離）。
2. Dhrystones/sec表示のホスト固有性を `ysd8002_timer_design` 改版時に「FPGA契約外」と明記推奨。
3. SW機構自体はハード実装済み。EN是正では**fire_enゲートのみ**触る（SW_START/STOPには触れない）。

---

## 4. ②ナレッジ整理 削除候補 最終確定（★実削除はユーザ操作★）

全件 grep / 版数台帳照合済み。**削除可 計19件**。

### 前半：ドキュメント・ソース系（12件）

**【A】旧HANDOVER・履歴（8件）**
- HANDOVER_CHAT92 / 93 / 94 / 95 / 96 / 97 / 98
- HANDOVER_PEEPHOLE_P1_IMPL_v1_0.md
- ※CHAT95/96/97はユーザ判断で削除確定。参照は履歴言及のみ・実依存なし。

**【B】旧版・poc（4件）**
- ysd8800_ysd8002_v0_1.sv … どのビルドもコンパイル対象にせず
- ysd8800_mmio_stub_v0_5_poc.sv … 正式版v0_5へ昇格済
- v5_design_memo_v0_3.md … v0_4現存
- emu23_v109.c … ★下記注記参照。ユーザ判断で削除確定★

### 後半：TB系（7件）

- tb_cpi_probe_poc.sv / tb_cpi_probe2_poc.sv（CPI測定・役割終了）
- tb_cpu_irq_diag_poc.sv（IRQ診断・役割終了）
- tb_cpu_v35regress_poc.sv / tb_cpu_v35mem_poc.sv / tb_cpu_v35boundary_poc.sv
  （V3.5段階検証PoC・正式は tb_cpu_v35mmu_v0_1.sv に集約済）
- tb_cpu_v5timer.sv（full版TB。**TBのみ削除**）

### ★保持確定（削除禁止・機械削除の罠）★

- **kernel_v12_7.asm** … 現行v0.10.18 道2ビルドの実ソース（build_road2.sh L53等）。**削除厳禁**
- **kernel_v12_8.asm** … Track A・V5-ACK対応。ビルド未統合だが将来必須
- **tb_ysd8002_v0_2_poc.sv** / tb_cpu_irq0ack_poc.sv / tb_cdc_bridge_v02_poc.sv … poc名だが現役
- **gen_*.py 9本すべて保持**（v2c/v2dはユーザ判断で保持確定。黄金値は都度生成方式のためTBとペア必須）
- **v5t_ack.hex / v5t_noack.hex**（full用・ユーザ判断で保持）
- **v5t_ack.asm / v5t_noack.asm**（V5設計の一次記録・SP初期化意図。ユーザ判断で保持）
- **golden_v2a.txt / v5t_ack_short.hex / v5t_noack_short.hex**（現役データ）
- HANDOVER_CHAT99（S9回帰基準md5出典）/ 100 / 101

### emu23_v109.c 削除に関する注記
- 現行回帰実行は `emu23_v110.c`。v109を実行バイナリ名で直接呼ぶ箇所なし（コメント照合のみ）。
- V3.5/V3.7黄金値は永続保存されず、生成器が `./emu23`（=現行v110）を都度subprocess実行して生成。
- よってv109削除でも回帰は回る。**ただし台帳は「v109 --mmu生成」と記録**しており、
  実運用(v110生成)との乖離あり。→ EN是正/V6着手時に「黄金はv110基準へ一本化」を台帳追記推奨。

---

## 5. 申し送り事項（本チャットでは実源改変せず記録のみ）

1. `gen_v2_vectors_v2e_poc.py` 冒頭コメントがコピペ由来で「v2d」表記のまま（KY41の4点整合の軽微な瑕疵）。改版機会に是正。
2. short版hex（現役S8ゲート入力）を asm 2本からどう生成したか手順が追えず、再現方法が未文書化の可能性。V5工程で手順文書化を検討。
3. emu23_v109.c 削除に伴い「V3.5/V3.7黄金値は v110 基準へ一本化」を版数台帳に追記（EN是正工程で v109/v110 のMMU黄金一致検証を併せて実施推奨）。
4. kernel_v12_8（V5-ACK対応・Track A）がビルド未統合のまま。V6以降「実カーネルにV5タイマー割込を載せる」工程で v12_7→v12_8 切替（またはForth側ACK挿入）を検討。

---

## 6. 常駐管理項目（失念厳禁）

- 版数台帳: fpga_source_version_ledger_v1_5 / tool_version_ledger_v1_11
- 設計負債（管理済み）: TCR EN=OR→AND（③EN是正工程で両側同時修正）
- sim_impl_policy v0.2 を上位規範として維持
- KY60: mmio_stub が旧版YSD8002を参照していないか毎回確認（本チャットで v0_5→v0_2 健全と確認済）

---

## 7. 本チャットの教訓（PDCA-A）

- **KY34（実ファイルが真実）が複数回効いた**: 「v12_7は不要では」の直感に反し、実ビルドスクリプト照合で v12_7 が現役ソースと判明。版数・サイズだけで新旧判断しない。
- **poc名の罠**: tb_ysd8002_v0_2_poc / gen_v2_vectors_v2e_poc は poc名だが現役。名前で機械的に切らず、版数台帳・ビルド再現との紐づきで判定する。
- **黄金値は都度生成方式**: 多くのTBが黄金値を永続保存せず生成器で都度生成。TBと生成器はペアで存続要否を判断する。
- **read-only徹底が有効**: 再点検・棚卸しで実源を触らない方針により、未承認改修の混入を防げた。

---

## 8. 参照すべき主要ファイル（次チャット＝③EN是正工程）

- emu23_v110.c（L696: fire_en の OR ロジック）
- ysd8800_ysd8002_v0_2.sv（L193: `timer_en_r | irq_en_r` の OR）
- ysd8002_timer_design_v1_0.docx（EN是正で改版対象・KY41準拠）
- fpga_source_version_ledger_v1_5.md / tool_version_ledger_v1_11.md
- kaizen.txt（原則43=実装前レビュー、原則73）

---

## 9. ビルド再現メモ（次チャット用・CHAT101から継承）

```
# iverilog 12.0（apt-get install -y iverilog）
# emu: gcc -O2 -o emu23 emu23_v110.c

# S8 short版統合TB（正式）:
#   build_v4.sh 系ドライバに tb_cpu_v5timer_short.sv を渡す
#   $readmemh は v5timer/v5t_ack_short.hex / v5t_noack_short.hex を読む

# S9 V2e 82ベクタ回帰:
#   gen_v2_vectors_v2e_poc.py で expected_v2e.hex 生成 → tb_cpu_v2e_v0_1.sv
#   expected_v2e.hex md5 = 09de96788c67b1e795d38277375eafcf（CHAT99値と一致）
```

---

## 10. ③EN是正工程の着手手順（次チャット冒頭の指針）

1. **原則43**: 実装前に設計レビュー承認を得る（EN=OR→AND の設計メモ作成→レビュー）。
2. AND化は emu(L696) と RTL(L193) の**両側同時**（片側だと emu/RTL 乖離）。
3. KY41準拠で ysd8002_timer_design を改版（追記のみ・取り消し線保持・4点整合）。
4. 回帰: Dhrystone（826/48405/P:20）＋V1/V2全82ベクタ デグレゼロ確認。
5. 併せて v109/v110 MMU黄金一致検証（申し送り3）。
