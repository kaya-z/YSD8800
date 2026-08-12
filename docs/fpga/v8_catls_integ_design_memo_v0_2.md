# V8 YUI OS統合 選択肢A（cat/ls フル統合）設計メモ v0.2

- **作成日**: 2026-07-20（v0.1）／**改版日**: 2026-07-21（v0.2）
- **チャット**: CHAT112（設計・実装Step1〜Step4前半）／CHAT113（Step4後半〜Step5＝**ALL PASS達成**）
- **前提**: CHAT111で選択肢B（read専用テストC・案D 2回読み契約保存）ALL PASS(4/0)達成済
- **方針確定**: A-1（read専用cat/lsデモC・CMD24書込回避）＝かやぬまさん承認済（2026-07-20）
- **上位規範**: 原則43（実装前レビュー）、KY34（実ファイルが真実）、KY38（実験は_poc）、sim_impl_policy v0.2（HW実現不可な実装をシミュレータに持ち込まない）

## 改版履歴（KY41準拠・追記のみ）
| 版 | 日付 | 内容 |
|---|---|---|
| v0.1 | 2026-07-20 | 初版。方針確定〜Step1〜Step4前半TB作成完了。レビュー依頼5項目提示。 |
| **v0.2** | **2026-07-21** | **Step4後半（TB実行）・Step5（結果確定）完了追記。ALL PASS達成報告。** |

---

## 1. ゴール

mkfs_yuifs でYUIFSイメージ生成 → SD SPIモデルへ供給 → **read専用cat/lsデモC** が実SPI経由で
sd_read し、YUIFSを解釈して **ls（ファイル名一覧）** と **cat（ファイル内容）** を UART出力 →
TBがUART出力をキャプチャして期待文字列と照合し ALL PASS を確認する。

**書込は一切行わない**（CMD24不要。mkfsが事前に書いたイメージを読むだけ）。

---

## 2. 実ファイル確認結果（KY34・2026-07-20確認済）
（v0.1本文と同一・以下略。詳細はv0.1参照）

## 3. デモC仕様（v0.1確定）
（v0.1本文と同一・以下略。詳細はv0.1参照）

## 4. TB仕様（v0.1確定）
（v0.1本文と同一・以下略。詳細はv0.1参照）

## 5. KY54強化（内容差替負例）（v0.1確定）
（v0.1本文と同一・以下略。詳細はv0.1参照）

## 6. 改修/新規ファイル一覧（全て_poc・KY38）
| ファイル | 種別 | 内容 |
|---|---|---|
| v8_catls_demo_poc.c | 新規 | read専用cat/lsデモC |
| sd_spi_model_v0_3_poc.sv | 改修(v0.2→v0.3) | 計算式返し→$readmemhイメージ返し |
| tb_cpu_v8catls_poc.sv | 新規 | UARTキャプチャ＋期待文字列照合TB |
| sd_image.img/.hex | 生成物 | mkfs最小イメージ |
| **sd_image_neg.hex** | **生成物(v0.2追記)** | **内容差替負例イメージ（"Byebye, YUIOS!\n"）** |

**無改修死守**: sd_sample.c / mkfs_yuifs_v1_1.py / RTL(CPU・YSD8003 v0.4等) は一切触らない。
→ **v0.2確認**: 全ラン通じて無改修死守を継続達成。

## 7. 段階（1変更1検証）
- Step1: mkfsイメージ生成＋hex化（規模確認）。 ✅完了(CHAT112)
- Step2: SDモデル改修（v0.3）＋モデル単体で $readmemh 読込→LBA返却をミニTBで確認。 ✅完了(CHAT112)
- Step3: デモC作成＋ビルドチェーン通し（scc23→hasm23→lnk23→hex）＋ISA健全性確認。 ✅完了(CHAT112)
- Step4: 統合TB作成（UARTキャプチャ＋照合）。KY54負例→正例。 ✅完了(CHAT112:TB作成 / **CHAT113:TB実行**)
- Step5: ALL PASS確認→成果物出力。 ✅完了(**CHAT113**)

---

## 8. レビュー依頼事項（原則43）→ **全項目承認済（2026-07-20）**
1. ~~論点2の解~~ → **承認済**
2. ~~論点3の解~~ → **承認済**
3. ~~最小イメージサイズ 8KB(16セクタ)~~ → **承認済**
4. ~~デモCの期待出力フォーマット~~ → **承認済**
5. ~~ファイル名 HELLO.TXT~~ → **承認済**

追加推奨（レビュー中に採用）: KY54強化（内容差替負例） → **v0.2で実行・PASS達成**

---

## 9. 【v0.2追記】実行結果（2026-07-21・CHAT113）

### 9.1 KY54 負例ラン（内容差替）
- **配置**: sd_image_neg.hex → sd_image.hex（md5=52426123fa3eeab68683b792ceed416f）
- **UART出力**: `"ls:\nHELLO.TXT\ncat HELLO.TXT:\nByebye, YUIOS!\n"` (44バイト)
- **mismatch**: 11バイト（期待"Hello, YUI OS!"に対し"Byebye, YUIOS!"）
- **結果**:

| ケース | 結果 | got | exp | 意味 |
|---|---|---|---|---|
| T0_negative | PASS | 11 | ≠-1 | TBがFAIL検出できる健全性 |
| S1_halt | PASS | 1 | 1 | プログラム完走 |
| S2_uart_len | PASS | 44 | 44 | 出力長一致 |
| S3_uart_match | FAIL | 11 | 0 | 期待通り不一致検出 |

→ **KY54目的達成**: 「デモCがSD実内容を読む（ハードコード無し）」を直接証明。
FSパス（superblock→dir走査→data読）が実データを追従することを因果的に確認。

### 9.2 正例ラン
- **配置**: sd_image_pos.hex → sd_image.hex（md5=2dc006b4b605b805fa95e2c4246ca5e1）
- **UART出力**: `"ls:\nHELLO.TXT\ncat HELLO.TXT:\nHello, YUI OS!\n"` (44バイト・完全一致)
- **サイクル**: HALT到達 cyc=3,750,467 (PC=0x0025)
- **結果**:

| ケース | 結果 | got | exp |
|---|---|---|---|
| T0_negative | PASS | 0 | ≠-1 |
| S1_halt | PASS | 1 | 1 |
| S2_uart_len | PASS | 44 | 44 |
| S3_uart_match | PASS | 0 | 0 |

**RESULT: PASS=4 FAIL=0 >>> V8 cat/ls INTEGRATION ALL PASS <<<**

### 9.3 到達点の意味
YSD8003(ストレージ) + YUIFS + YUI OS が実SPI経由で結合し、**OS無改修**で cat/ls が動作。
V6-A から続くストレージ工程の到達点であり、YUI OSがFPGA実装上で実ファイルシステムを
読み出せることの初の実証。

### 9.4 kaizen候補（本チャット学び）
- **KY-新1**: 統合TBビルドは decoder/regfile/alu 先頭必須（idec_pkgパッケージ前方参照）
- **KY-新2**: 期待文字列はPython実バイト列挙で確定させる（欠落自己検出に有効）
- **KY-新3**: 正例hexは負例ラン前に必ず退避（`sd_image_pos.hex`）＋md5で二重確認
  → 本チャットで実効を確認、kaizen反映推奨
