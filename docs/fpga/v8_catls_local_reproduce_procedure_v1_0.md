# V8 cat/ls INTEGRATION ローカル再現手順書 v1.0

- **作成日**: 2026-07-22
- **対象**: かやぬまさんローカル環境
- **目的**: プロジェクトナレッジのファイルからV8 cat/ls INTEGRATION（YUI OS on iverilog）ALL PASSをローカルで再現する
- **参照元実行環境**: Ubuntu 24 / Icarus Verilog 12.0 (stable)
- **想定所要時間**: ビルド1分・実行1〜2分（正例+負例で計3〜5分）

---

## 0. サマリ（先に全体像）

```
[1] 前提環境確認  →  [2] 作業ディレクトリ作成  →  [3] ファイル配置
                                                          ↓
[6] ALL PASS確認  ←  [5] 実行（負例→正例）  ←  [4] ビルド
```

**最終期待出力**:
```
RESULT: PASS=4 FAIL=0
>>> V8 cat/ls INTEGRATION ALL PASS <<<
```

---

## 1. 前提環境

### 1.1 必須ツール
| ツール | 版数 | 確認コマンド |
|---|---|---|
| Icarus Verilog | 11.0以上（12.0推奨） | `iverilog -V` |
| bash / md5sum / cp | 標準 | (通常インストール済) |

### 1.2 iverilog のインストール（未インストールの場合）

**Ubuntu / Debian系**:
```
sudo apt-get update
sudo apt-get install -y iverilog
```

**Fedora / RHEL系**:
```
sudo dnf install iverilog
```

**macOS (Homebrew)**:
```
brew install icarus-verilog
```

### 1.3 バージョン確認
```
iverilog -V
```
→ `Icarus Verilog version 11.0` 以上であること。11.0未満は `-g2012` 未対応の可能性あり。

---

## 2. 作業ディレクトリ作成

```
mkdir -p ~/yui_v8_check
cd ~/yui_v8_check
```

以後の作業は `~/yui_v8_check` で行う。

---

## 3. ファイル配置

プロジェクトナレッジから **合計21ファイル** を `~/yui_v8_check/` に配置する。全て**プロジェクトナレッジからダウンロード**するだけでよい（生成不要）。

### 3.1 RTL本体（14ファイル）

| # | ファイル | 役割 |
|---|---|---|
| 1 | `ysd8800_decoder_v0_1.sv` | 命令デコーダ + idec_pkg |
| 2 | `ysd8800_regfile_v0_1.sv` | レジスタファイル |
| 3 | `ysd8800_alu_v0_1.sv` | ALU |
| 4 | `ysd8800_cpu_v0_1_FIXED.sv` | CPUコア v0.5.8 |
| 5 | `ysd8800_v5_membus_v0_2.sv` | メモリバス統合ラッパー |
| 6 | `ysd8800_mmio_stub_v0_7.sv` | MMIOデコード（YSD8001-8004ルーティング） |
| 7 | `ysd8800_ysd8003_v0_4.sv` | ストレージコントローラ（SPI CMD17） |
| 8 | `ysd8800_ysd8002_v0_3.sv` | タイマー（EN是正版 AND化） |
| 9 | `ysd8800_ysd8004_v0_1.sv` | 割込コントローラ |
| 10 | `ysd8800_ysd8001_v0_1.sv` | UART |
| 11 | `ysd8800_addr_decoder_v0_1.sv` | アドレスデコーダ |
| 12 | `ysd8800_cdc_bridge_v0_2.sv` | CDCブリッジ |
| 13 | `ysd8800_mmu_v0_1.sv` | MMU |
| 14 | `ysd8800_psram_ctrl_v0_2.sv` | PSRAMコントローラ |

### 3.2 TB・モデル・デモC（3ファイル）

| # | ファイル | 役割 |
|---|---|---|
| 15 | `tb_cpu_v8catls_poc.sv` | 統合TB（UART照合・KY54負例枠付） |
| 16 | `sd_spi_model_v0_3_poc.sv` | SD SPIモデル（$readmemh実イメージ返し） |
| 17 | `v8_catls_demo_poc.c` | cat/lsデモC（**参考用**・ビルドには不要） |

### 3.3 生成物（4ファイル）

| # | ファイル | 役割 |
|---|---|---|
| 18 | `v8t_catls.hex` | デモC最終ビルド hex（17408行） |
| 19 | `sd_image.hex` | mkfs正例イメージ 8KB |
| 20 | `sd_image_neg.hex` | 内容差替負例イメージ |
| 21 | `sd_image_pos.hex` | 正例退避用（`sd_image.hex`と同一・KY防止策用） |

**注**: `sd_image_pos.hex` はプロジェクトナレッジにあれば取得、無ければ`sd_image.hex`をコピーして作成（4節参照）。

### 3.4 配置後の確認
```
ls -la ~/yui_v8_check/ | wc -l
```
→ ヘッダ2行 + ファイル21個 = **23行** になっていること。

---

## 4. 正例イメージの退避（KY防止策）

**★重要★** V8統合TBは`sd_image.hex`という固定ファイル名を`$readmemh`で読む。負例ランで上書きすると正例が消える。**必ず先に退避する**。

```
cd ~/yui_v8_check
cp sd_image.hex sd_image_pos.hex
md5sum sd_image.hex sd_image_pos.hex sd_image_neg.hex
```

**期待md5**:
```
2dc006b4b605b805fa95e2c4246ca5e1  sd_image.hex
2dc006b4b605b805fa95e2c4246ca5e1  sd_image_pos.hex
52426123fa3eeab68683b792ceed416f  sd_image_neg.hex
```

正例2つのmd5が一致し、負例が異なることを確認。

---

## 5. ビルド

### 5.1 ★依存順の重要注意★

**`ysd8800_decoder_v0_1.sv` `ysd8800_regfile_v0_1.sv` `ysd8800_alu_v0_1.sv` を必ず先頭に置く**。これらは`idec_pkg`パッケージを定義しており、TB内で`import ysd8800_idec_pkg::*;`する。SystemVerilogパッケージは前方参照不可のため、順序を間違えると`syntax error`になる。

### 5.2 ビルドコマンド（コピペ用ワンライナー）

```
cd ~/yui_v8_check

iverilog -g2012 -o v8tb.vvp \
  ysd8800_decoder_v0_1.sv \
  ysd8800_regfile_v0_1.sv \
  ysd8800_alu_v0_1.sv \
  tb_cpu_v8catls_poc.sv \
  ysd8800_cpu_v0_1_FIXED.sv \
  ysd8800_v5_membus_v0_2.sv \
  ysd8800_mmio_stub_v0_7.sv \
  ysd8800_ysd8003_v0_4.sv \
  ysd8800_ysd8002_v0_3.sv \
  ysd8800_ysd8004_v0_1.sv \
  ysd8800_ysd8001_v0_1.sv \
  ysd8800_addr_decoder_v0_1.sv \
  ysd8800_cdc_bridge_v0_2.sv \
  ysd8800_mmu_v0_1.sv \
  ysd8800_psram_ctrl_v0_2.sv \
  sd_spi_model_v0_3_poc.sv
```

### 5.3 期待出力（警告のみ・エラー無し）
```
ysd8800_ysd8001_v0_1.sv:285: vvp.tgt sorry: Case unique/unique0 qualities are ignored.
ysd8800_ysd8004_v0_1.sv:157: vvp.tgt sorry: Case unique/unique0 qualities are ignored.
```
→ この2件の`sorry`警告は**無害**（unique/unique0はシミュレーション上のヒントで、iverilogは無視する仕様）。

### 5.4 生成物確認
```
ls -la v8tb.vvp
```
→ `v8tb.vvp`（約290KB）が生成されていること。

---

## 6. 実行

**KY54（TB健全性証明）順序として、負例を先に実行してからの正例実行を推奨**。

### 6.1 【推奨】負例ラン（内容差替でTBがFAILを出せることの確認）

```
cd ~/yui_v8_check
cp sd_image_neg.hex sd_image.hex
md5sum sd_image.hex
# → 52426123fa3eeab68683b792ceed416f であること

vvp v8tb.vvp
```

**期待出力（末尾）**:
```
[UART out] "ls:\nHELLO.TXT\ncat HELLO.TXT:\nByebye, YUIOS!\n"  (cnt=44)
[read] UART mism_bytes=11
--- T0: negative run (KY54: TBがFAILを出せる健全性) ---
  PASS T0_negative                  (TB detects mismatch: got=11 != wrong=-1)
--- S1: プログラム完走(HALT到達) ---
  PASS S1_halt                      got=1 exp=1
--- S2: UART出力バイト数==EXP_LEN ---
  PASS S2_uart_len                  got=44 exp=44
--- S3: UART出力==期待文字列(mism==0) ---
  FAIL S3_uart_match                got=11 exp=0
============================================================
 RESULT: PASS=3 FAIL=1
 >>> SOME FAILED <<<
============================================================
```

**この結果の意味**:
- S3が`FAIL(mism=11)`になるのは**期待通り**（負例イメージなので11バイト不一致）
- S3がPASSしてしまったら**TBが壊れている**（内容差替を検出できない＝ハードコード疑惑）
- T0_negative がPASS＝「TBはFAILを検出できる健全性がある」を確認できた

### 6.2 正例ラン

```
cd ~/yui_v8_check
cp sd_image_pos.hex sd_image.hex
md5sum sd_image.hex
# → 2dc006b4b605b805fa95e2c4246ca5e1 であること

vvp v8tb.vvp
```

**期待出力（末尾）**:
```
[info] HALT reached at cyc=3750467 (PC=0025)
[UART out] "ls:\nHELLO.TXT\ncat HELLO.TXT:\nHello, YUI OS!\n"  (cnt=44)
[read] UART mism_bytes=0
--- T0: negative run (KY54: TBがFAILを出せる健全性) ---
  PASS T0_negative                  (TB detects mismatch: got=0 != wrong=-1)
--- S1: プログラム完走(HALT到達) ---
  PASS S1_halt                      got=1 exp=1
--- S2: UART出力バイト数==EXP_LEN ---
  PASS S2_uart_len                  got=44 exp=44
--- S3: UART出力==期待文字列(mism==0) ---
  PASS S3_uart_match                got=0 exp=0
============================================================
 RESULT: PASS=4 FAIL=0
 >>> V8 cat/ls INTEGRATION ALL PASS <<<
============================================================
```

### 6.3 実行時間の目安

- 実行時間: 実マシン性能により **30秒〜3分程度**
- サイクル数: 3,750,467 cyc（HALT到達）
- 途中 `WARNING: $readmemh(v8t_catls.hex): Not enough words in the file for the requested range [0:1048575].` が出るが**無害**（TBが1MBメモリ全域を確保するが、hexは17KB程度で埋めなくてよい）

---

## 7. トラブルシューティング

### 7.1 症状: `syntax error` が出る（idec_pkg関連）
**原因**: RTLファイルの順序ミス。decoder/regfile/alu が先頭にない。
**対処**: §5.2 のビルドコマンドをそのままコピペする。順序を変えない。

### 7.2 症状: `Cannot find sd_image.hex` エラー
**原因**: 実行時に `sd_image.hex` が無い、またはカレントディレクトリが違う。
**対処**: `vvp` 実行時のカレントディレクトリが `~/yui_v8_check` になっているか確認。TB内で相対パスで`$readmemh("sd_image.hex")`しているため。

### 7.3 症状: S3_uart_match が正例でもFAIL
**原因の可能性**:
- (a) 正例と負例のファイルを取り違えている → §4のmd5で二重確認
- (b) 正例ラン前に`sd_image.hex`が負例のまま → `cp sd_image_pos.hex sd_image.hex` を実行してmd5確認
- (c) `sd_image_pos.hex` を作り忘れて `sd_image.hex` が負例で上書きされた → プロジェクトナレッジから`sd_image.hex`を再取得

### 7.4 症状: HALTに到達せずタイムアウト
**原因**: TBのMAX_CYC制限に達した。RTL挙動が想定外。
**対処**: 
- `iverilog -V` で 11.0 以上か確認
- ファイル取り違えがないか md5 で再確認
- それでも駄目なら実行ログを添えて相談

### 7.5 症状: warnings `Not enough words in the file`
**原因**: TB側で1MB分確保しているが、hexは17KB程度。
**対処**: **無害・無視でOK**（未使用領域はゼロ初期化される仕様）。

---

## 8. 検証項目チェックリスト

再現成功時に以下すべてが確認できること：

- [ ] iverilog 11.0以上がインストールされている
- [ ] 21ファイルが作業ディレクトリに揃った
- [ ] `sd_image_pos.hex` を退避した（md5一致確認）
- [ ] ビルドがエラー無しで完了（sorry警告2件のみ）
- [ ] 負例ラン: S3_uart_match=FAIL(mism=11) / 他PASS＝TB健全
- [ ] 正例ラン: **PASS=4 FAIL=0** かつ `>>> V8 cat/ls INTEGRATION ALL PASS <<<`
- [ ] 正例UART出力に `"Hello, YUI OS!"` が含まれる

---

## 9. 参考: ファイルの取得方法（プロジェクトナレッジから）

プロジェクトナレッジ画面から各ファイルを個別にダウンロードするか、Claude Web/Desktop で以下のように依頼して個別に受け取る：

```
「プロジェクトナレッジの ysd8800_decoder_v0_1.sv を出力してください」
```

**まとめてzipで欲しい場合**: Claudeに依頼して一括tarballを作成してもらう手も可能（別セッションで対応可）。

---

## 10. 関連文書

- 設計メモ: `v8_catls_integ_design_memo_v0_2.md`
- ソース版数台帳: `fpga_source_version_ledger_v1_7.md`
- 実行ログ: `log_v8tb_pos.txt` / `log_v8tb_neg.txt`（プロジェクトナレッジ）

---

## 改版履歴
| 版 | 日付 | 内容 |
|---|---|---|
| v1.0 | 2026-07-22 | 初版。CHAT113 ALL PASS達成後のローカル再現手順として作成。 |
