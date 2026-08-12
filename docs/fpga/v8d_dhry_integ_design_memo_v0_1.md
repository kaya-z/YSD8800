# V8-D Dhrystone iverilog動作確認 設計メモ v0.1

- **作成日**: 2026-07-23
- **作成者**: Claude (CHAT115)
- **対象工程**: V8-D（V8-a と V8-b の間の回帰チェック工程）
- **状態**: レビュー依頼中（未承認）
- **KY準拠**: 原則41（設計メモ形式）・原則43（実装前レビュー必須）

---

## 1. 目的

V8-a（cat/lsデモC実SPI経路実証）完了後、V8-b（yuios.bin本体動作確認）に進む前に、**CPU＋PSRAM＋UART＋YSD8002タイマー の総合動作を Dhrystone（C単体・OS無し）で回帰チェックする**。

### 1.1 挿入意義

- **1変更1検証**（kaizen原則）: V8-a→V8-b の間にステップを挟むことで、V8-b で問題が出た際「YUI OS 起因の問題」に切り分けやすくなる
- **回帰チェック**: V6-A・V8-a で大きく変わった RTL（YSD8003 追加、membus v0.2、mmio_stub v0.7、YSD8002 v0.3）に対する Dhrystone 完走性の確認
- **YSD8002 SW計時 RTL の間接検証**: TCR bit2/3、SW_RUNS、SCORE_LO/HI が波形上で正しく駆動されることの実測

### 1.2 スコープ外（重要・縮小解釈厳守）

- Dhrystone MIPS 値の emu23 との一致（時間計測は成り立たない前提・Q7確定）
- YUI OS 本体動作（V8-b でカバー）
- SD カード経路（案S1で削除）

---

## 2. 前提となる RTL 調査結果

### 2.1 YSD8002 v0.3 SW計時実装状況

`ysd8800_ysd8002_v0_3.sv` に **SW計時レジスタは完全実装済み**。

| レジスタ | アドレス | 実装 | ロジック |
|---|---|---|---|
| TCR | $FC90 | ✅ | bit2=SW_START, bit3=SW_STOP, bit4=SW_BUSY(R) |
| SW_RUNS | $FC9A (16bit) | ✅ | R/W・Number_Of_Runs格納用 |
| SCORE_LO | $FC9C | ✅ | R専用・SW_STOP時に差分cycle確定 |
| SCORE_HI | $FC9E | ✅ | R専用・HIラッチ機構あり |
| CYCLE_LO/HI | $FC96/$FC98 | ✅ | R専用・32bitサイクルカウンタ |

**コアロジック**（v0_3.sv L332-341）:
```
SW_START (bit2): sw_start_cyc_r <- cycle_i; sw_busy_r <- 1
SW_STOP  (bit3): score_r <- cycle_i - sw_start_cyc_r; sw_busy_r <- 0
```

emu23 L705-714 と1対1対応。V5工程（HANDOVER100〜105）で実装完了済み。

### 2.2 dhry_timer.c の RTL 互換性

`dhry_timer.c` (プロジェクトナレッジ・現行版) の timer_start / timer_stop は **既に MMIO 直書き方式に完全移行済み**。SYSCALL 0x0010/0x0011 は使用していない。

- `timer_start()` (L542-): TCR bit2 (SW_START) 直書き
- `timer_stop()` (L686-): TCR bit3 (SW_STOP) 直書き

→ **RTLとの互換性: 完全**。dhry_timer.c は無改修で V8-D TB に投入できる。

### 2.3 UART 出力仕様

`dhry_timer.c` main() の出力:
```c
r = dhrystone(10);
if (r) putchar('P'); else putchar('F');
putchar(':');
print_num(result);   // result は Dhrystone内部検証カウンタ・期待値 20
```

**UART 期待出力: `"P:20"` の4文字**

- SCORE_LO/HI（cycle差分）は書き込まれるが UART には出ない
- emu23 の Dhrystones/sec 出力（stderr）はホスト側処理のため RTL では出ない

---

## 3. 合格判定（Q7準拠）

### 3.1 主判定
- **UART 出力に `"P:20"` を含む**（4バイト完全一致）
- **HALT 到達**

### 3.2 副判定（波形観測・オプション）
- SW_START 書込→SW_STOP 書込 の間に cycle カウンタが進行
- SCORE_LO が非ゼロで確定（SW_BUSY が 1→0 遷移）

### 3.3 判定外（Q7）
- サイクル数の emu23 一致
- Dhrystones/sec 数値

---

## 4. TB 仕様

### 4.1 派生元・命名

- **派生元**: `tb_cpu_v8catls_poc.sv` (V8-a)
- **新規ファイル名**: `tb_cpu_v8d_dhry_poc.sv`
- **KY 対策**: V8-a と混同しないため `v8d_dhry` を必ずファイル名に含む

### 4.2 案S1: SD経路削除（本設計メモで確定・確認2)

派生時に以下を削除:
- `sd_spi_model_v0_3_poc.sv` インスタンス化行
- `$readmemh("sd_image.hex", ...)` 系全行
- SD 関連ワイヤ・接続

削除確認: 派生完了後 `grep -nE "sd_spi|sd_image|sdcard" tb_cpu_v8d_dhry_poc.sv` で残存ゼロ。

### 4.3 hex ロード

- V8-D 用 hex: `dhry_final.hex`（`dhry_final.bin` を `bin2hex.py` で変換）
- $readmemh("dhry_final.hex", psram_mem) 相当

### 4.4 UART キャプチャ

- V8-a の UART キャプチャロジックを踏襲
- 期待文字列: `"P:20"` (4B)
- キャプチャバッファ長は余裕を持って 32B 程度

### 4.5 サイクル上限

Dhrystone 10反復の見積り（暫定・要emu23基準値取得で確定）:
- emu23 実測: 48,405 cyc（Makefile regress 期待値）
- RTL 上は emu23 と cycle 数は一致しない前提だが、**おおよそ 5万〜50万 cyc** と想定
- V8-a が 3,750,467 cyc（cat/lsデモC）で完走したことを考えると、Dhrystone は同程度以下

**TB サイクル上限**: 1,000万cyc（100倍余裕・タイムアウト時は明示FAIL）

### 4.6 KY54 相当の負例枠

- V8-a では sd_image_neg.hex による内容差替負例を実施
- V8-D では Dhrystone に SDカードは無関係のため、**負例は「意図的にhexを1バイト破壊した破壊版」**を作るか検討
- **本設計メモでは負例スコープを別途相談**（着手前に方針確定）

---

## 5. Dhrystone hex ビルド手順

### 5.1 参照ドキュメント
- `yuios_build_procedure_v1_9.docx` §5（Cプログラムビルド）
- `Makefile` の dhrystone ターゲット（自動化スクリプト参考）
- `yuios_makefile_design_v0_2.md` §1.2 dhrystone道2 D1〜D8

### 5.2 emu23 基準値取得手順（本工程の前段階）

```
# D1〜D7: hex（=dhry_final.bin）まで生成
# D8: emu23 で実行
timeout 30 ./emu23 dhry_final.bin -q
# 期待: UART=P:20 / stderr=Dhrystones/sec=826 cycles=48405
```

**取得すべき基準値**:
- UART 全出力（`P:20` の前後に何か出るか確認）
- emu23 停止時 PC 値
- HALT到達までのサイクル数（RTL 側と比較参考にはならないが記録）

### 5.3 iverilog 向け hex 変換

`dhry_final.bin` → `dhry_final.hex` 変換:
- `bin2hex.py` （プロジェクトナレッジに実在）を使用
- V8-a 時の `v6t_sdread` / `v8t_catls` と同じ手法で $readmemh 形式に変換

---

## 6. 実施段階（1変更1検証）

1. **本設計メモ v0.1 のレビュー承認** ★現在ここ
2. **emu23 で Dhrystone 実行 → 基準値取得**
   - dhry_timer.c → scc23 → hasm23 → lnk23 → emu23 走行
   - UART出力・PC・cycle 数を記録
3. **`dhry_final.hex` 準備**（bin2hex.py 使用）
4. **`tb_cpu_v8d_dhry_poc.sv` 派生作成**
   - V8-a TB から SD経路削除
   - hex差替え・期待文字列差替え
   - grep で SD残存ゼロ確認
5. **iverilog ビルド** → **PASS 確認**
6. **設計メモ v0.2 改版**（実測結果反映）
7. **V8-D 完了報告** → V8-b 着手判断

---

## 7. KY（V8-D特有）

### 7.1 危険予知一覧

| # | 危険 | 防止策 |
|---|---|---|
| KY-A | V8-a TB の SD経路残存で PSRAM 競合 | 派生直後にgrep確認・案S1準拠 |
| KY-B | サイクル数無限化で iverilog 実行停止 | サイクル上限1000万で強制FAIL |
| KY-C | dhry_final.hex と v8t_catls.hex の混同 | ファイル名に必ず`dhry`を含む |
| KY-D | emu23 基準値と RTL 値の一致を求めてしまう | Q7準拠・UART一致のみ判定 |
| KY-E | dhry_timer.c を勝手に改変 | 無改修で使用（RTL互換確認済） |
| KY-F | Makefile の dhrystone ターゲットが emu23前提 | iverilog向けhex変換ステップを明示化 |

### 7.2 特に強調

**KY-A**: 派生元のV8-aは規模が大きい。SD経路の削除漏れが1行でもあると初期化未完了で stuck → 「Dhrystone未完のバグ」と誤診する。派生後の grep確認は必須（原則43準拠）。

---

## 8. 実施しない事項（スコープ縮小・原則81準拠）

- ISA3.0 対応
- V8-b（yuios.bin動作）
- Step 8-Impl（実機実装）
- V6-B（CMD24書込）
- Dhrystoneのタイマー計測値の絶対値検証（RTL cycle値の絶対値検証）

これらは V8-D の**次工程以降**で個別に対応する。

---

## 9. 関連文書

| 文書 | 参照理由 |
|---|---|
| `HANDOVER_CHAT113.md` | V8-D 挿入経緯・作業指針§5 |
| `yuios_build_procedure_v1_9.docx` | Dhrystone ビルド手順（§5） |
| `yuios_makefile_design_v0_2.md` | dhrystone道2の詳細フロー |
| `Makefile` | dhrystone ターゲット定義・regress期待値 |
| `dhry_timer.c` | Dhrystoneソース本体（現行版・MMIO対応済） |
| `ysd8800_ysd8002_v0_3.sv` | RTL YSD8002 実装確認元 |
| `tb_cpu_v8catls_poc.sv` | 派生元TB |
| `v8_catls_integ_design_memo_v0_2.md` | V8-a 完了報告（縮小解釈の議論含む） |
| `emu23_debug_manual_v1_2.docx` | emu23 使用方法（基準値取得時） |
| `kaizen.txt` | 原則43（実装前レビュー）・原則76（RTLは黄金ref準拠）・原則81（縮小解釈）|

---

## 10. レビュー観点（推奨・かやぬまさんへ）

- §2 RTL 調査結果に見落としがないか（特に SW_STOP→SCORE_LO のクリア/HIラッチ挙動）
- §3 合格判定「P:20 一致」で回帰チェックとして十分か
- §4.5 サイクル上限 1000万 が妥当か（実走行前なので推定値）
- §4.6 負例枠を V8-D に設けるべきか（V8-a では KY54 として実施）
- §6 段階の順序（基準値取得→TB→ビルド→PASS）の是非

---

## 改版履歴

| 版 | 日付 | 内容 |
|---|---|---|
| v0.1 | 2026-07-23 | 初版。RTL調査結果・段階計画・KY含む。レビュー依頼中。 |
