# HANDOVER_CHAT106

- **作成日**: 2026-07-19
- **前チャット**: CHAT106（V6-A 実装②-b SD初期化シーケンス具体化＋TB作成＋CMD17不具合切り分け）
- **次チャット**: CHAT107（V6-A CMD17読出ERROR原因究明→修正→TB全PASS）
- **テーマ**: FPGA V6-A YSD8003 ストレージコントローラ（SDカードSPIモード読出）

---

## 0. セッション開始時の必須手順（KY49含む）
1. 本HANDOVER確認
2. claude_tool_operation_guide_v1_0.txt 確認（規律1〜5）
3. 工程確認（「進捗と予定の確認(latest)」の最新ロードマップと照合）
4. KY活動（1件）
5. 「ご安全に！」で作業開始

> **重要（乱れ対策）**: 本チャットでツール呼び出し書式崩れが複数回発生。真因＝**ツールコール直前の長文**＋**ログ長大化**。次チャットは「ツールコール前の地の文ゼロ〜1文」「規律4＝1応答1操作」を機械的に徹底し、ログが伸びたら早めに区切ること。

---

## 1. 現在地（V6-A 到達点）

### 1.1 本チャット(CHAT106)の完了事項（2026-07-19）
| 成果物 | 版 | 状態 |
|---|---|---|
| ysd8800_ysd8003_v0_2.sv | v0.2 | ★SD初期化シーケンス実装完了・iverilog警告ゼロ・EXIT=0★ |
| tb_ysd8003_v0_1.sv | v0.1 | 作成・ビルドクリーン。T1/T4/T6一部PASS、T2/T3 FAIL（下記） |

いずれも `/mnt/user-data/outputs/` に出力済。次チャットで /mnt/project/ に見つからない場合は「セッション後登録」を最初に疑う（スナップショットが古い・ユーザー操作は正しい）。

### 1.2 実装②-b（v0.1→v0.2）の実装内容
- **電源投入ダミー**: S_POWERUP でCS=1のまま0xFF×10バイト（80clk≧74clk規格）
- **初期化コマンド列**: S_CMD0（正CRC 0x95）→ S_CMD8（正CRC 0x87・arg=0x000001AA）→ S_CMD55 → S_ACMD41（HCS=1・0x40100000）→ S_INIT_DONE
- **共通R1受信**: 新設 S_INIT_R1 で5コマンド共通にフレーム送出→NCR待ち→init_next遷移
- **★ハング回避KY（成立確認済）★**:
  - `init_active` 新設：EXEC前（初期化中）もSPI_TIMEOUT保護対象に（timeout_cntカウント条件＝`exec_active||init_active`）
  - ACMD41再ループに `ACMD41_RETRY_MAX=512` 上限→超過でS_ERROR
  - S_ERRORで `init_active`もクリア（TO暴走防止）
- Web検証（elm-chan/nodeloop等）でCMD0/CMD8のみ正CRC7、以降ダミーCRC(0x01)を確認済み。

### 1.3 標準準拠の根拠（Web検索・2026-07-19）
- CMD0のCRC7=0x95、CMD8のCRC7=0x87は固定値（複数実装で一致）。以降はダミー0x01でよい。
- CMD8はarg=0x000001AA（電圧範囲＋チェックパターン0xAA）。
- CMD55→ACMD41をR1=0x00になるまで反復（本SDモデルpocは1回で0x00を返す簡略仕様）。

---

## 2. ★次チャット最優先: CMD17読出がS_ERRORで終わる不具合★

### 2.1 症状（debug_style_guide準拠）
- **現象**: TB実行でT2（512Bデータ一致）とT3（STAT READY）がFAIL。
- **切り分け済み事実**:
  - T1（初期化完走 S_IDLE到達）は **PASS** → 初期化のCMD0/8/55/41のR1受信は成立している。
  - EXEC投入後、`dut.reg_stat=010（ERROR）`, `dut.fsm=8（S_IDLE=ERROR処理後の終着）` を確認。
  - **CMD17読出FSMがS_ERROR経由で終了している**のが真因。
  - T4（IRQ）はPASSするが、これは**S_ERRORでもIRQを予約する仕様（emu23互換・549行付近）**のため。成功の証拠ではない。
  - **速度依存ではない**: DIV_FAST=0（高速）をDIV_FAST=9（初期化と同速）にしても同じERROR。SCK速度は無関係と確定。
  - T6（タイムアウト→ERROR→ready返却・ハングしない）は **PASS**。ハング回避KYは成立。

### 2.2 次チャットの調査方針（仮説を1つに絞る）
初期化(同じSPI機構)は成功するのにCMD17だけ失敗する。差分に注目して切り分ける:
1. **最有力仮説**: CMD17送出後の **S_RD_R1** でR1=0x00を受信できず、resp_wait_cnt上限(>8)超過→S_ERROR。
   - あるいは **S_RD_TOKEN** でデータトークン0xFE不達。
   - 確認法: `dut.fsm` の遷移を EXEC直後から数十clk、階層参照で1回だけダンプ（$displayを1箇所）。どの状態でS_ERRORへ落ちるか特定する。
2. SDモデル側 CMD17処理（sd_spi_model_v0_1_poc.sv L273-280, L183-184の finish_response）と、RTLのS_RD_R1/S_RD_TOKEN受信タイミングの噛み合いを照合。
   - モデルは `last_cmd==17 && st==ST_SEND_R1` で読出トークンフェーズへ遷移（L183-184）。CS制御・バイト境界がRTLと合っているか。
3. **初期化との差分で怪しい点**: S_INIT_R1では期待R1一致で `spi_cs_r<=1`（CS解除）してから次コマンドへ。CMD17（S_RD_CMD17）はCS=0のまま連続。この**CS制御の非対称**がモデルのcmd_idx/状態と噛み合っているか要確認。

### 2.3 デバッグの作法（重要）
- 仮説検証は1つに絞ってから実行（トークン節約）。
- $displayは1箇所・1回に絞る（ログ長大化＝乱れ誘発を避ける）。
- iverilog: build/run分離、vvpはtimeout必須、`ls -la`でタイムスタンプ確認。

---

## 3. 残作業（CMD17修正後）

1. **T5（negative）本格化**: SDモデルpocはトークン不正を注入できない。SDモデル拡張（v0.2）でトークン不達/CRCエラー注入を追加してからT5を有効化。現状はT6タイムアウト経路がERROR確定を代表検証。
2. **EXEC受理をS_IDLE時のみに限定（見えているバグ・KY）**: 現状EXEC(A_CMD_L=2)は初期化完了前でも `fsm<=S_RD_CMD17` へ飛ぶ（v0.2 L395付近）。初期化中断の恐れ。`fsm==S_IDLE`ガードを追加すべき（1変更1検証でCMD17修正の後に実施）。
3. **mmio_stub / addr_decoder 改修**（$FCA0-$FCBF を YSD8003 v0.2 へルーティング。V4/V5同型。KY60: mmio_stubのYSD8003旧版参照が無いか確認）。
4. **統合検証**: YUI OS無改修で cat/ls（案Dの2回読み契約保存が最終関門）。

---

## 4. 重要な申し送り・ペンディング

- **latest反映（済）**: 「V6の前にEN是正工程を挿入」は**latest反映済・完了**（かやぬまさん2026-07-19確認）。以後この件の警告・依頼は不要。
- **kaizen候補（原則78）**: 「黄金リファレンスが特定機構（SPI等）を隠蔽する工程では、emu23一致は検証軸にならない。判定軸をOS観測の外部契約に移しcycle等価を放棄。隠蔽層をRTLで起こす際、OS側固定前提（2回読み）が実機タイミングと衝突しうるためwait-stateで吸収」。**未反映**。次チャットでkaizen.txt反映を検討。
- **kaizen候補（新規・本チャット教訓）**: 「S_ERRORでもIRQを予約する仕様のため、IRQ検査のPASSは成功の証拠にならない。完了検証はSTATのREADY(bit2)成立で判定すること」。
- **バージョン台帳**: fpga_source_version_ledger（現v1.6）へ **ysd8003 v0.2**（初期化実装）・**tb_ysd8003 v0.1**・**sd_spi_model_poc v0.1** 追記が必要。tool_version_ledger（現v1.12）は変更なし（ツール改修なし）。

---

## 5. CHAT106の反省（PDCA-A・次チャットで是正）
- **ツール呼び出し書式崩れ複数回発生**。真因＝ツールコール直前の長文＋ログ長大化。→ 次チャット改善策: 「ツールコール前の地の文はゼロ〜1文」「規律4＝1応答1操作」を機械的徹底。ログが伸びたら早めに区切って新チャットへ。
- **成果物の早期出力を怠り、デバッグでログを伸ばしてから出力**した。→ 次チャットは節目ごとに小さく出力する。

---

## 6. 検証・環境メモ
- iverilog 12.0。本作業環境では `apt-get install -y iverilog`（sudoなし）でインストール可。
- build/run分離、`ls -la`でタイムスタンプ確認、vvp実行はtimeout必須。
- shで実行されるため `${PIPESTATUS}` は使えない（Bad substitution）。`cmd 2>err.txt; echo "EXIT=$?"` の形にする。
- FPGA回帰ゲート=完走＋論理結果一致（cycle一致は対象外・CPI=1固定のため）。

---

## 7. TB構成メモ（tb_ysd8003_v0_1.sv）
- DUT: `ysd8800_ysd8003_v0_1`（ファイルは v0_2.sv・内部モジュール名は v0_1 のまま）
- SDモデル: `sd_spi_model_v0_1_poc`（ポート: cs_n/sck/mosi/miso）
- `kill_miso` スイッチでMISOを常時FF固定→T6タイムアウト注入。
- `mmio_read` は ready_o=1 待ち合わせ付き（案D wait-state吸収）。
- `wait_init_done` は `dut.fsm===dut.S_IDLE` を階層参照で監視。
- TBウォッチドッグ（#200000000）でTB自体のハング防止。
- 試験: T1(init完走)/T6(TO→no hang)=PASS, T2(512B)/T3(READY)=FAIL（§2の不具合）, T4(IRQ)=PASS(ただし§4のとおり成功の証拠ではない), T5=SDモデル拡張待ちで記録のみ。

---

## 8. 参照ファイル（互換基準）
- emu23_v111.c（YSD8003: MMIO L295-320 / STAT読 L642-666 / EXEC L761-810）
- sd_sample.c（sd_read/sd_wait_ready 2回読み固定・リトライ無し）
- yuios_ph3_storage_design_v1_5.md
- sd_spi_model_v0_1_poc.sv（黄金リファレンス・SD規格模擬）
- v6a_storage_design_memo_v0_2.md（レビュー承認済・案D確定）
- ysd8800_ysd8002_v0_3.sv（ポート作法・原則59準拠の手本）
