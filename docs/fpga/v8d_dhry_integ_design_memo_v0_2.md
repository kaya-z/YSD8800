# V8-D Dhrystone iverilog動作確認 設計メモ v0.2

- **作成日**: 2026-07-23
- **作成者**: Claude (CHAT115)
- **対象工程**: V8-D（V8-a と V8-b の間の回帰チェック工程）
- **状態**: 再レビュー依頼中（v0.1 レビュー指摘反映済）
- **KY準拠**: 原則41（設計メモ形式）・原則43（実装前レビュー必須）・原則75（弁別能力のある負例）
- **前版**: v0.1（2026-07-23・条件付き差戻し）

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

### 2.3 UART 出力仕様（v0.2 修正: 実源乖離修正）

**★v0.1 からの重要修正**: `dhry_timer.c` は `#define my_printf` （空マクロ・L430）だが、L625 に **`putchar('N'); putchar('='); print_num(Number_Of_Runs); putchar('\n');`** が直書きで存在する。これは `my_printf` に依存せず必ず出力される。

`dhry_timer.c` の出力フロー:

```c
// main() L547-556
r = dhrystone(10);
// ↓ dhrystone() 内部 L625 で先行出力される
//   putchar('N'); putchar('='); print_num(10); putchar('\n');
//   → "N=10\n" (5B)
//   その後 timer_start → 10反復ループ → timer_stop → return result
// ↑ main() 続き L551-554
if (r) putchar('P'); else putchar('F');   // "P" (1B)
putchar(':');                              // ":" (1B)
print_num(result);   // result==20 が期待値・"20" (2B)
// 総合出力: "N=10\nP:20" (9B)
```

**UART 期待出力: `"N=10\nP:20"` の9バイト（順序込み）**

### 2.4 `result` 変数の意義（v0.2 補足）

`result` は Dhrystone の内部検証カウンタ。L690〜L801 で **20項目**のチェック（`Int_Glob == 5` 等）を積み上げ、L834 で `return result == 20`。

- **20 は反復回数（Number_Of_Runs=10）とは無関係**
- 「全項目パスの意」であり、Number_Of_Runs を変えても 20 のまま
- 完走かつ全項目パス → `result==20` → `dhrystone()` は非0 return → main で `putchar('P')`

### 2.5 emu23 の副次出力（RTLでは出ない）

emu23 は SCORE レジスタ確定時に **stderr へ Dhrystones/sec / cycles / cpu_freq を出力**（`--- Dhrystones/sec = 826 ---` 等）。しかしこれは emu23 ホスト側の副次処理であり、**RTL 上には該当機構が存在しない**。従って UART 判定の対象外。

---

## 3. 合格判定（Q7準拠・v0.2 強化）

### 3.1 主判定（v0.2 修正）

- **UART 出力に `"N=10\n"` と `"P:20"` の両方をこの順序で含む**（9バイト全体一致）
- **HALT 到達**

**弁別能力**（原則75の応用）:
- 「N=10\n だけ出て P:20 が出ない」→ Dhrystoneに入ったが完走しない ケースを FAIL 検出可能
- 「P:20 だけで N=10\n が無い」→ 期待値マッチ位置ずれ・偽PASS 検出可能
- 順序込み検査により、TB の照合ロジックが両方の出現を確認する

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

### 4.2 案S1: SD経路削除（本設計メモで確定・確認2）

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
- 期待文字列: `"N=10\nP:20"` (9B)
- キャプチャバッファ長は余裕を持って 32B 程度
- **照合方式**: `"N=10\n"` の出現位置を検出後、それ以降に `"P:20"` の出現を確認（順序照合）

### 4.5 サイクル上限（v0.2 修正: 根拠を明確化）

**根拠（v0.2 で書換）**:

Dhrystone 10 反復の emu23 実測（Makefile regress 期待値）:
- emu23: **48,405 cyc**

RTL（iverilog）上での膨張要因:
- **PSRAM wait-state**（原則71・アクセス毎に数〜十数cyc追加）
- 命令フェッチ・データアクセスの両方で PSRAM 経由 → 実行時間膨張
- 想定膨張率: **5〜20倍**
- 想定 RTL cycle数: **約24万〜97万 cyc**

**TB サイクル上限**: **1,000万cyc**（想定最大の約10倍余裕・原則71対応の安全設定）

タイムアウト時は明示FAIL。後続の V8-b・V8-c で上限値を再検討する際、この根拠ロジック（emu23基準×PSRAM係数×余裕）を踏襲すること。

### 4.6 負例枠（v0.2 修正: 案X採用）

**案X採用**（原則75・弁別能力のある負例）:

**負例内容**: TB 側で **期待文字列を意図的に `"N=10\nP:21"` に設定**（本来の `"P:20"` を `"P:21"` に変えた版）を追加し、以下を確認:

- 期待文字列 `"P:21"` に対して、実際の出力は `"P:20"` が来る
- **FAIL が返ることを積極確認** → TB の文字列照合ロジックが「意図した通りに不一致検出できる」ことを証明

これにより「常に PASS を返してしまうバグった TB」を回帰的に排除できる。実装工数は正例TBのコピー＋期待文字列1バイト変更のみで軽量。

**負例ファイル名**: `tb_cpu_v8d_dhry_poc_neg.sv`（または正例TB内でパラメータ化）

---

## 5. Dhrystone hex ビルド手順

### 5.1 参照ドキュメント

- `yuios_build_procedure_v1_9.docx` §5（Cプログラムビルド）
- `Makefile` の dhrystone ターゲット（自動化スクリプト参考）
- `yuios_makefile_design_v0_2.md` §1.2 dhrystone道2 D1〜D8

### 5.2 emu23 での UART 出力実測確認（v0.2 修正: 位置づけ整理）

**主目的**: 期待文字列 `"N=10\nP:20"` (9B) が emu23 上で本当に出ることの**一次確認**。設計メモの記述と実源の照合最終確認。

```
# D1〜D7: hex（=dhry_final.bin）まで生成
# D8: emu23 で実行し UART 出力を照合
timeout 30 ./emu23 dhry_final.bin -q
# 期待 UART: "N=10\nP:20" (9B)
# 期待 stderr: Dhrystones/sec=826 cycles=48405（参考記録）
```

**判定に用いる情報**:
- **UART 全出力**（9B照合の一次確認）→ TB 期待文字列の根拠

**参考記録のみ（V8-D 判定には無関係）**:
- emu23 停止時 PC 値
- emu23 上のサイクル数（48,405 想定）
- Dhrystones/sec 値

### 5.3 iverilog 向け hex 変換

`dhry_final.bin` → `dhry_final.hex` 変換:
- `bin2hex.py` （プロジェクトナレッジに実在）を使用
- V8-a 時の `v6t_sdread` / `v8t_catls` と同じ手法で $readmemh 形式に変換

---

## 6. 実施段階（1変更1検証）

1. **本設計メモ v0.2 の再レビュー承認** ★現在ここ
2. **emu23 で Dhrystone 実行 → UART出力実測確認**
   - dhry_timer.c → scc23 → hasm23 → lnk23 → emu23 走行
   - UART出力 `"N=10\nP:20"` 実測（PC・cycle は参考記録）
3. **`dhry_final.hex` 準備**（bin2hex.py 使用）
4. **`tb_cpu_v8d_dhry_poc.sv` 派生作成**（正例）
   - V8-a TB から SD経路削除
   - hex差替え・期待文字列差替え（9B順序込み）
   - grep で SD残存ゼロ確認
5. **`tb_cpu_v8d_dhry_poc_neg.sv` 作成**（負例・案X）
   - 期待文字列を `"N=10\nP:21"` に変更したもの
6. **iverilog ビルド** → **正例PASS・負例FAIL 確認**
7. **設計メモ v0.3 改版**（実測結果反映）
8. **V8-D 完了報告** → V8-b 着手判断

---

## 7. KY（V8-D特有）

### 7.1 危険予知一覧（v0.2 修正: KY-G 追加）

| # | 危険 | 防止策 |
|---|---|---|
| KY-A | V8-a TB の SD経路残存で PSRAM 競合 | 派生直後にgrep確認・案S1準拠 |
| KY-B | サイクル数無限化で iverilog 実行停止 | サイクル上限1000万で強制FAIL |
| KY-C | dhry_final.hex と v8t_catls.hex の混同 | ファイル名に必ず`dhry`を含む |
| KY-D | emu23 基準値と RTL 値の一致を求めてしまう | Q7準拠・UART一致のみ判定 |
| KY-E | dhry_timer.c を勝手に改変 | 無改修で使用（RTL互換確認済） |
| KY-F | Makefile の dhrystone ターゲットが emu23前提 | iverilog向けhex変換ステップを明示化 |
| **KY-G** | **L625 の "N=10\n" 出力を見落として "P:20" のみを期待し、TB バッファの位置ずれで偽 FAIL または偽 PASS を招く** | **期待文字列は "N=10\nP:20" の順序込みで検証。TB は先頭からの部分文字列探索でなく、両方の出現順を確認する** |

### 7.2 特に強調

**KY-A**: 派生元のV8-aは規模が大きい。SD経路の削除漏れが1行でもあると初期化未完了で stuck → 「Dhrystone未完のバグ」と誤診する。派生後の grep確認は必須（原則43準拠）。

**KY-G（v0.2 追加）**: v0.1 レビューで発覚した実源乖離の再発防止。**Dhrystone の UART 出力は "N=10\n"（dhrystone()内・L625）＋ "P:20"（main()内・L551-554）の順序合成**。片方を見落とすと弁別能力が落ちる。原則5.1（実源照合）の実践。

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
| `v8d_dhry_integ_design_memo_v0_1_review_v1_0.docx` | v0.1 レビュー指摘書（v0.2 反映元） |
| `yuios_build_procedure_v1_9.docx` | Dhrystone ビルド手順（§5） |
| `yuios_makefile_design_v0_2.md` | dhrystone道2の詳細フロー |
| `Makefile` | dhrystone ターゲット定義・regress期待値 |
| `dhry_timer.c` | Dhrystoneソース本体（現行版・MMIO対応済・L430/L484/L547-556/L625/L690-801/L834 実源根拠） |
| `ysd8800_ysd8002_v0_3.sv` | RTL YSD8002 実装確認元（L332-341） |
| `tb_cpu_v8catls_poc.sv` | 派生元TB |
| `v8_catls_integ_design_memo_v0_2.md` | V8-a 完了報告（縮小解釈の議論含む） |
| `emu23_debug_manual_v1_2.docx` | emu23 使用方法（基準値取得時） |
| `kaizen.txt` | 原則41（設計メモ形式）・原則43（実装前レビュー）・原則71（PSRAM wait）・原則75（弁別負例）・原則81（縮小解釈）|
| `review_insights_v1_0.docx` | 原則5.1（実源照合）・原則73（外部観測判定）・原則75（弁別負例） |

---

## 10. v0.1 レビュー指摘への対応対応表

| # | 区分 | 指摘 | v0.2 対応 |
|---|---|---|---|
| 1 | 必修正 | §2.3・§3.1 UART 期待出力 "P:20" → "N=10\nP:20" | **§2.3・§2.4・§3.1・§4.4・§5.2 に反映** |
| 2 | 必修正 | §7.1 に KY-G 追加 | **§7.1・§7.2 に反映** |
| 3 | 推奨 | §4.5 サイクル上限根拠を PSRAM wait 係数ベースに書換 | **§4.5 に反映（emu23基準×5〜20倍×余裕）** |
| 4 | 推奨 | §4.6 負例枠を案X（"P:21"期待でFAIL確認）に変更 | **§4.6 案X 採用で反映** |
| 5 | 推奨 | §5.2 基準値取得を UART 実測に主眼を絞る | **§5.2 に反映（cycle/PC は参考記録扱いに整理）** |
| 6 | 補足 | SW_STOP 挙動確認・V8-D スコープでは問題無し | 補足のためv0.2 で変更なし（レビュア結論通り） |

---

## 改版履歴

| 版 | 日付 | 内容 |
|---|---|---|
| v0.1 | 2026-07-23 | 初版。RTL調査結果・段階計画・KY含む。レビュー結果: 条件付き差戻し。|
| v0.2 | 2026-07-23 | v0.1 レビュー指摘全反映（必修正2件・推奨修正3件）。主変更: §2.3/§3.1 期待UART出力を "N=10\nP:20" に修正・§4.5 サイクル上限根拠明確化・§4.6 負例枠を案X（P:21期待FAIL）採用・§5.2 基準値位置づけ整理・§7.1 KY-G 追加。§2.4/§2.5 追記。§10 対応表新設。前版情報は §10 に集約保持（原則: 前版情報欠落禁止）。|
