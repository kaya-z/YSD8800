# HANDOVER_CHAT105

- **作成日**: 2026-07-19
- **前チャット**: CHAT105（V6-A ストレージコントローラ 設計〜本体RTL）
- **次チャット**: CHAT106（V6-A 実装②-b以降）
- **テーマ**: FPGA V6-A YSD8003 ストレージコントローラ（SDカードSPIモード読出）

---

## 0. セッション開始時の必須手順（KY49含む）
1. 本HANDOVER確認
2. claude_tool_operation_guide_v1_0.txt 確認（規律1〜5）
3. 工程確認（「進捗と予定の確認(latest)」の最新ロードマップと照合）
4. KY活動（1件）
5. 「ご安全に！」で作業開始

---

## 1. 現在地（V6-A 到達点）

### 1.1 完了済（CHAT105・2026-07-18）
| 成果物 | 版 | 状態 |
|---|---|---|
| v6a_storage_design_memo | v0.2 | ★レビュー承認済★（案D反映） |
| sd_spi_model_v0_1_poc.sv | v0.1 | 作成・iverilog文法クリーン（黄金リファレンス） |
| ysd8800_ysd8003_v0_1.sv | v0.1 | 作成・558行・iverilog警告ゼロ・EXIT=0 |

いずれも `/mnt/user-data/outputs/` に出力済。次チャットで /mnt/project/ に見つからない場合は「セッション後登録」を最初に疑う（スナップショットが古い・ユーザー操作は正しい）。

### 1.2 設計の核（レビュー確定事項）
- **emu23とRTLの非対称**: emu23のYSD8003はfreadで512Bを即時memcpyしSPIを隠蔽。RTLはこの隠蔽層を実SPI状態機械として起こす（本テーマの山場）。emu23協調等価は使えない。判定軸は「OSが観測する外部契約（レジスタ遷移）」、cycle等価は放棄。
- **★案(D): STAT読み($FCA2) wait-state化★**: SPI完了までready_o=0でCPUを待たせ、完了/タイムアウトでready_o=1＋READY/ERROR返却。OSのsd_wait_ready 2回読み（sd_sample.c）が無改修で成立。V3 mem_ready滞留の再利用・MC6809 MRDY相当。
  - 案(A)（SPIをCPU速度に合わせる）は約1000倍のタイミング乖離で物理的に実現不能→却下済。
- **ハング回避KY（最重要）**: SPIタイムアウトカウンタで規定超過→ERROR確定→ready_o返却。ready_oを永久に0にしない。
- 諮問決定: ②512Bバッファ=分散RAM(LUTRAM) ③SCK=2段固定分周（初期化低速/読出高速・OS非依存） ④CDC不要（SPI=4MHz単一ドメイン） ⑤V6-A=読出(CMD17)のみ・書込(CMD24)はV6-B。

### 1.3 本体RTL(v0.1)の実装済/未実装
- **実装済**: MMIO $FCA0-$FCBF（下位5bit・8bitバイトアクセス・emu23互換）、ready_o wait-state論理、SPIマスタ（mode0・8bit転送）、CMD17読出FSM（S_RD_CMD17→R1→TOKEN→512B→CRC）、タイムアウト、割込irq_stor_o（レベル・ack解除）、BUSYラッチ、BUF_PTR自動++。
- **★未実装（骨格素通し）★**: SD初期化シーケンス。S_POWERUP→S_INIT_DONE を素通しにしており、CMD0/CMD8/CMD55/ACMD41の実バイト授受が未実装。次チャット最優先。

---

## 2. 次チャット(CHAT106)の作業（優先順）

1. **実装②-b: SD初期化シーケンス具体化**
   - S_POWERUP: CS=1で74クロック以上のダミーSCK（電源安定・SD規格）
   - S_CMD0(GO_IDLE→R1=0x01) → S_CMD8(SEND_IF_COND→R7) → S_CMD55+S_ACMD41ループ(R1=0x00まで) → S_INIT_DONE
   - cmd_frame + spi_start によるバイト授受は、既存のS_RD_CMD17/S_RD_R1の書き方を踏襲
2. **TB作成 tb_ysd8003_v0_1.sv**（KY54: negative先行）
   - T5(negative): トークン不達/CRCエラー→ERROR(bit1)
   - T6(必須): SPIタイムアウト→ERROR→ready_o返却（ハングしない）
   - T1: 初期化シーケンス完走（CMD0/8/41順・CS/CRC7）
   - T2: CMD17→512B既知パターン(lba*512+i)一致
   - T3: STAT BUSY→READY遷移・SD_DATA 512回読出一致
   - T4: 完了IRQ(IRQ1)レベル立ち・ackで落ち
   - sd_spi_modelの権威付け（SD規格忠実性の1点照合）を忘れず
3. **mmio_stub / addr_decoder 改修**（$FCA0-$FCBF を YSD8003 へルーティング。V4/V5同型作業。KY60: mmio_stubのYSD8003参照追加監視）
4. **統合検証**: YUI OS無改修で cat/ls（案Dの2回読み契約保存が最終関門）

---

## 3. 重要な申し送り・ペンディング

- **★latest反映依頼（失念厳禁・継続）★**: 「V6の前にEN是正工程を挿入」がlatest未反映（2026-07-18承認）。EN是正完了＋V6-A着手（本体RTLまで）を「進捗と予定の確認(latest)」へ日報反映が必要。あわせて「V6は案A＋ストレージV6-A担当」の工程整理も依頼要。
- **kaizen候補（原則78）**: 「黄金リファレンスが特定機構（SPI等）を隠蔽する工程では、emu23一致は検証軸にならない。判定軸をOS観測の外部契約に移しcycle等価を放棄。隠蔽層をRTLで起こす際、OS側固定前提（2回読み）が実機タイミングと衝突しうるためwait-stateで吸収」。次チャットでkaizen.txt反映を検討。
- **バージョン台帳**: fpga_source_version_ledger（現v1.6）へ ysd8003 v0.1・sd_spi_model_poc v0.1 追記が必要。tool_version_ledger（現v1.12）は変更なし（emu23等ツール改修なし）。

---

## 4. CHAT105の反省（PDCA-A・次チャットで是正）

- **ツール呼び出し書式崩れ複数回発生**。真因=ツールコール直前の長文。次チャット改善策: 「ツールコール前の地の文は1〜2文まで」「規律4=1応答1操作」を機械的徹底。ログ長大化の兆候（メモリ既知教訓）。
- **iverilog警告10件**（comb内定数ビット選択）を一時発生→kaizen原則59（comb内定数選択をassign外出し）失念が真因。RTL新規作成時は着手前に原則59を必ず想起。最終的に警告ゼロで是正済。

---

## 5. 検証・環境メモ
- iverilog 12.0。build/run分離、`ls -la`でタイムスタンプ確認、vvp実行はtimeout必須。
- 日本語をechoするとbashが「invalid UTF-8」を返すことがある→python3で確認する回避策が有効。
- FPGA回帰ゲート=完走＋論理結果一致（cycle一致は対象外・CPI=1固定のため）。

---

## 6. 参照ファイル（互換基準）
- emu23_v111.c（YSD8003: MMIO L295-320 / STAT読 L642-666 / EXEC L761-810）
- sd_sample.c（sd_read/sd_wait_ready 2回読み固定・リトライ無し）
- yuios_ph3_storage_design_v1_5.md
- ysd8800_ysd8002_v0_3.sv（ポート作法・原則59準拠の手本）
- v6a_storage_design_review_reply_v1_0.md（レビュー回答・案D確定）
