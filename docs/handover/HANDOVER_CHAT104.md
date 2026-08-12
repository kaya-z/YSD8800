# HANDOVER_CHAT104.md

- **作成日**: 2026-07-18
- **前チャット**: HANDOVER_CHAT103.md（③EN是正工程 主要実装＋主要回帰 完了）
- **本チャット(CHAT104)の担当**: ③EN是正工程の **残タスク（negTB完全化・全回帰・MMU黄金・文書改版・台帳更新）を全完了**
- **状態**: **★設計負債（EN是正/案B）の改修が全て完了。かやぬまさん「おつかれさまでした」で本テーマ完結★**
- **次チャットの担当**: **★V6-A ストレージコントローラ（YSD8003）RTL実装 — プロジェクト最大のテーマ★**

---

## 0. 最優先: セッション開始時にやること
1. 本HANDOVERを確認
2. `claude_tool_operation_guide_v1_0.txt` を1回参照（規律1〜5）
3. 「進捗と予定の確認(latest)」で工程確認（最新か判断）
4. KY活動を1つ挙げ防止策を実行
5. 「ご安全に！」で作業開始

> **★latest反映依頼（失念厳禁・CHAT101から継続）★**
> 「V6の前にEN是正工程を挿入」がlatest未反映（かやぬまさん 2026-07-18「ここで承認・ロードマップ未反映」）。
> **EN是正は完了したので、日報時に「EN是正工程 完了・latestに反映」を依頼すること。**
> あわせて **「V6は案A（TIMER_EN=0でカウンタ停止）＋ストレージV6-Aを担当」** の工程整理も依頼。

---

## 1. CHAT104で完了した内容（EN是正 残タスク・全5点）

| No | タスク | 結果 |
|---|---|---|
| 1 | negTB完全化 | ✅ `tb_cpu_v6mask` **N0〜N3 ALL PASS(4/4)**。内ループ #1000→#100 短縮でN2/N3のFAIL解消。真因＝ループ長>MAX_CYC（AND化と無関係）を実証 |
| 2 | V1/V2 全ベクタ回帰 | ✅ V2a=20 / V2c=64 / V2d=75 / **V2e=82**（md5=`09de96788c67b1e795d38277375eafcf` 一致）**ALL PASS**。CPUコア無改修＝デグレゼロ |
| 3 | MMU黄金一致検証 | ✅ v111で黄金生成・**決定性一致**（md5=`0b7c941ec6a6a7817dc64fcdd1e06f57`・2回生成同一）。EN是正はMMU非干渉。黄金は **v111基準へ一本化** |
| 4 | 文書改版（KY41） | ✅ ysd8002_timer_design **v1.0→v1.2** ／ v5_design_memo **v0.4→v0.5** |
| 5 | 版数台帳更新 | ✅ tool_version_ledger **v1.11→v1.12** ／ fpga_source_version_ledger **v1.5→v1.6** |

### 是正の核心（実証済み）
負例 `v6t_mask`（TCR=$0001＝TIMER_EN=1/IRQ_EN=0）で **emu23 v1.11・RTL v0.3 の両側とも CNT=0**。
実サイクル121611（発火周期40000を約3回跨ぐ＝発火機会3回）の中で一度も発火せず、
**IRQ_EN=0 が割込マスクとして機能する契約回復**を直接実証。Dhrystone 826/48405/P:20 も不変。

### CHAT104 成果物（/mnt/user-data/outputs 出力済み）
- `ysd8002_timer_design_v1_2.docx`（TCR AND是正・§11.1将来課題・4点整合是正）
- `v5_design_memo_v0_5.md`（§3.5.2「近日中抜本改修」→「案B完了・案Aは将来」改訂）
- `tool_version_ledger_v1_12.md`（emu23 v1.11 反映）
- `fpga_source_version_ledger_v1_6.md`（ysd8002 v0_3 / mmio_stub v0_6・§14新設）
- `v6t_mask.asm`（内ループ#100 short版）
- `v6t_mask_short.hex`

---

## 2. ★次工程 = V6-A ストレージコントローラ（YSD8003）RTL実装★

### 2.1 工程定義（fpga_impl_roadmap_v1_3.docx §V6-A より）
- **ストレージ：最速 SD カード読み出し（最優先・FPGA固有・SPIモード）**
- **範囲**: SPI初期化（CMD0 / CMD8 / ACMD41）＋ 単一ブロック読出（CMD17）の最小セット。
- **OS側I/F**: 現行ストレージドライバ互換に保ち、**OS無改修で cat/ls 動作を目標**。
- **完了条件**: SPIでSDから1ブロック読出成功＋OS無改修でブート。
- **検証**: SDカードSPIモデルに対する単体TB。
  **★重要★ ストレージは emu23 黄金リファレンス枠外**（SDのSPIプロトコルはemu23に対応物がない。§2.4参照）。
- V6-B（後日）: 書込CMD24・マルチブロック・DMA度向上・完了IRQ洗練。

### 2.2 ★最重要の技術的差分（emu23 と FPGA-RTL の非対称）★
- **emu23 側 YSD8003（storage.txt / emu23_v111.c §295-303）は「高レベル抽象」**。
  SPI通信の低レベル詳細（CRC・クロック分周・CIDレジスタ・CMD0/8/41/17シーケンス）は**隠蔽**され、
  ホストファイルを直接 memcpy する（`card->storage + (addr/512)*512`）。
- **FPGA-RTL V6-A では、この隠蔽されていた SPIプロトコルを実RTLで実装せねばならない**。
  ここが本テーマ最大の山場。emu23には無い「SPI状態機械・SDカード初期化シーケンス・
  SCK生成・MISO/MOSIシフト・R1/R7レスポンス解釈」を新規設計する。
- したがって **emu23協調等価検証は使えない**。SDカードSPIビヘイビアモデル（新規作成）に対する
  単体TBが正解リファレンスとなる（roadmap §144 明記）。

### 2.3 ★プログラマI/F（MMIOレジスタ）= emu23 YSD8003 互換基準★
OS無改修が完了条件なので、**RTLは emu23 の YSD8003 MMIOレジスタI/Fを互換実装**する。
（emu23_v111.c L295-303 実照合）:

| アドレス | 名前 | 説明 |
|---|---|---|
| $FCA0 | SD_CMD | 0=READ_SETUP / 1=WRITE_SETUP / 2=EXEC |
| $FCA2 | SD_STAT | bit0=BUSY / bit1=ERROR / bit2=READY |
| $FCA4 | SD_LBA_LO | LBAアドレス 下位16bit |
| $FCA6 | SD_LBA_HI | LBAアドレス 上位16bit |
| $FCA8 | SD_BUF_PTR | バッファポインタ (0-511) |
| $FCAA | SD_DATA | PIOデータ(8bit)・自動 BUF_PTR++ |
| $FCAC | SD_IRQ_CTRL | bit0=IRQ_EN / bit1=ERR_EN |
| $FCAE | SD_DISK_LO | 総セクタ数 下位16bit |
| $FCB0 | SD_DISK_HI | 総セクタ数 上位16bit |

- **EXEC完了IRQ**: emu23 は SD_CMD=2(EXEC) 受理時に `sd_irq_delay=512` で予約、512cycle後に
  **IRQ1（YSD8004経由・IRQ_STAT_BIT_STOR）** で発火（emu23_v111.c §60-62・L1605-1613）。
  RTL側もこの「EXEC→完了IRQ（IRQ1）」の外部観測を互換させる（タイミングはSPI実装依存）。
- ★注意★: この $FCA0-$FCB0 は emu23 の割り当て。**FPGA-RTLの addr_decoder / mmio_stub で
  この帯域を YSD8003 へルーティングする改修が要る**（V4でUART $FC80-$FC87、V5でTimer $FC90系を
  ルーティングしたのと同様の作業）。KY60 の対象がYSD8003にも広がる点に留意。

### 2.4 検証戦略（emu23枠外・単体TB主体）
- **SDカードSPIビヘイビアモデル（新規SV）** を作り、それに対する単体TBで検証。
- モデルは「CMD0→アイドル遷移、CMD8→R7、ACMD41→初期化完了、CMD17→データトークン+512バイト+CRC」を模擬。
- 完了条件の「OS無改修でブート」は、YUI OS の現行ストレージドライバ（PIO方式・SD_DATA読出）が
  RTL YSD8003 に対して cat/ls を通せるか、で判定。

### 2.5 既存資産（次チャットで参照すべきファイル）
| 分類 | ファイル | 用途 |
|---|---|---|
| 工程定義 | `fpga_impl_roadmap_v1_3.docx` §V6-A/V6-B（§100/101/144） | ストレージ工程の正式定義 |
| emu23実装 | `emu23_v111.c` L295-303・§60-62・L1605-1613 | MMIOレジスタI/F・EXEC完了IRQ仕様の互換基準 |
| 抽象仕様 | `storage.txt` | SDブロックデバイス抽象・512バイトセクタ |
| OS側設計 | `yuios_ph3_storage_design_v1_5.md` | YUI OS ストレージドライバI/F（OS無改修の基準） |
| OS側サンプル | `sd_sample.c` | ストレージ利用のCコード例 |
| RTL参考 | `ysd8800_ysd8001_v0_1.sv`（UART）/ `ysd8800_ysd8002_v0_3.sv`（Timer） | MMIOデバイスRTLの実装作法・割込出力の作法 |
| ルーティング参考 | `ysd8800_mmio_stub_v0_6.sv` / `ysd8800_addr_decoder_v0_1.sv` | 新デバイスの$FCxx帯ルーティング改修の手本 |
| 割込接続 | `ysd8800_ysd8004_v0_1.sv`（YSD8004） | YSD8003完了IRQ→IRQ1(STOR)接続先 |

### 2.6 ★V6-A 着手前の手順（原則43厳守）★
1. **設計検討 → 設計メモ作成 → レビュー承認**（原則43。いきなり実RTLを書かない）。
2. 設計メモに最低限含めるべき論点:
   - SPI状態機械の構成（初期化シーケンス CMD0/8/ACMD41 / データ転送 CMD17）
   - SDカードSPIビヘイビアモデルの責務範囲（どこまで模擬するか）
   - MMIOレジスタI/F（emu23互換・$FCA0-$FCB0）とバイト/ワードアクセス粒度
   - EXEC→完了IRQ(IRQ1) の実現方式（SPI転送完了検出→YSD8004へレベル出力）
   - SCK周波数（4MHz CPUクロックに対する分周）／CDCの要否
   - sim_impl_policy v0.2 の G1〜G4 実現可能性ゲート適用（ハードで実現不能な実装を持ち込まない）
3. レビュー承認後に実装着手。KY38（実験は_pocサフィックス）厳守。

---

## 3. 常駐管理項目（失念厳禁）

### 3.1 版数台帳（最新）
- `tool_version_ledger_v1_12.md`（emu23 v1.11 現行）
- `fpga_source_version_ledger_v1_6.md`（ysd8002 v0_3 / mmio_stub v0_6 現行・§14がEN是正記録）

### 3.2 ツールチェーン現行版
- emu23 **v1.11**（emu23_v111.c・発火EN=AND・起動表示 `emu23 v1.11 (2026-07-18)`）
- hasm23 v1.04 / lnk23 v2.01 / scc23 v2.03 / Force v1.5 / disasm23 v1.00 / mkfs_yuifs v1.1
- iverilog 12.0（RTLシム・要 `apt-get install -y iverilog`）

### 3.3 FPGA-RTL 現行版
- CPUコア: `ysd8800_cpu_v0_1_FIXED.sv`（v0.5.8・**EN是正でも無改修＝5フェーズ連続論理不変**）
- 下位: decoder/regfile/alu v0_1・addr_decoder v0_1・mmu v0_1・cdc_bridge v0_2・psram_ctrl v0_2
- デバイス: ysd8001(UART) v0_1・**ysd8002(Timer) v0_3**・ysd8004(IRQ) v0_1
- スタブ/バス: **mmio_stub v0_6**（module名 v0_5据置）・v5_membus v0_1
- ビルド: `build_v5en.sh`（EN是正版）。V6では storage 追加でビルドスクリプト改版が要る。

### 3.4 設計負債・将来課題
- **★案A（TIMER_EN=0 でカウンタ歩進停止）＝ V6以降の将来課題**（正式記録: ysd8002_timer_design v1.2 §11.1・
  fpga_source_version_ledger v1.6 §14.5）。EN是正/案Bで割込マスク契約は回復済のため優先度は低い。
- sim_impl_policy v0.2 を上位規範として維持（ストレージ設計で特に重要＝SPIはハード実装可能性の検証必須）。
- KY60: mmio_stub の YSD8002 参照は v0_3 で健全確認済（CHAT104）。**V6でYSD8003追加時、
  KY60の対象にYSD8003参照も加える**。

### 3.5 停滞工程の警告
- scc23 Phase 1〜6: FPGA優先で意図的保留（技術的停滞に非ず・Step 8完了後に着手・失念厳禁）
- Ph.7（FAT12）/ Ph.8（MMU連携・Level2）: 将来計画として保持

---

## 4. CHAT104の教訓（PDCA-A）
- **ログ長大化の予防警告は改善**した（約35回で予告・約60回で再警告）。CHAT103の反省（antmlタグ崩れ2回後に
  遅れて警告）を踏まえ、今回はタグ崩れゼロで完走。次回も同方針（30回超で予防警告・早め成果物出力）。
- **文書の版数不整合を実体確認で発見**（ysd8002_timer_design：ファイル名v1_0だが本文Version1.1・
  履歴v1.0という3者不整合。KY34「実ファイルが真実」で検出）。**勝手に判断せずユーザ確認**し、
  「YSD8002は論理デバイスゆえ設計書に記載・最新シミュレータemu23も記録」という方針を得てv1.2改版。
  → 教訓: 改版前に必ず本文Version・ファイル名・変更履歴の3点を実体照合する。
- **negTBの真因究明**: N2/N3 FAILを「AND化不全」と誤認せず、ループ長>MAX_CYCと正しく切り分け、
  AND化ロジックに触れずループ長のみ修正で解決。KYの防止策（真因取り違えでの是正破壊回避）が機能した。

---

## 5. 引継ぎのまとめ（次チャット冒頭で読む3行）
1. **EN是正（設計負債）は全完了**。次は **V6-A ストレージコントローラ（YSD8003）RTL実装** ＝プロジェクト最大テーマ。
2. **emu23はSPIを隠蔽している**ため協調等価は使えない。**SDカードSPIモデル＋単体TB**が正解リファレンス。
   MMIOレジスタI/F（$FCA0-$FCB0）は emu23 互換で OS無改修を目指す。
3. **原則43厳守**: まず設計検討→設計メモ→レビュー承認。いきなりRTLを書かない。latest反映依頼も忘れず。
