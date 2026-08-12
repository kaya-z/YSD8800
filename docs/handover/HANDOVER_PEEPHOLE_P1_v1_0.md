# HANDOVER: scc23 v2.02 確定完了 → P1 着手

- 文書版数: v1.0
- 日付: 2026-06-28（出力実施・確認は 2026-06-29）
- 作成理由: P3 完全完了（v2.02 確定・outputs 出力済み）。次の本題 P1 を別チャットで着手するための引継ぎ。
- 前チャット系譜: 「SCC23のピープホール最適化」→ P3実装 → P3出力（本チャット）→ **次: P1（別チャット）**

---

## 0. このチャットで完了したこと（P3 完全クローズ）

前チャットで表示崩れ（`antml:` プレフィックス脱落）により未完だった **outputs 出力のみ** を本チャットで完遂した。

- **`scc23_v2_02.c`** 確定・出力済み（`/mnt/user-data/outputs/`）。
  - poc ベース。ヘッダを v2.02 化（ファイル名 / `Version: 2.02 (2026-06-28)` / P3変更点ブロック / 改版履歴 v2.02 を append-only 追加）。
  - `SCC_VERSION "2.02"` / `SCC_DATE "2026-06-28"`（180-181行）。
  - 駄目押し: `gcc -O2` コンパイル成功・`./scc23 --version` → `scc23 v2.02 (2026-06-28) for YSD8800 ISA2.3` 表示確認。
- **`tool_version_ledger_v1_9.md`** 確定・出力済み。
  - v1.8 ベース。**4点整合確認済み**（ファイル名 v1_9 / ヘッダ `Version 1.9` / 改版履歴 v1.9行 / §1 scc23 行 v2.02）。
  - あわせて、v1.8 改版時にヘッダ表記が `Version 1.7` のまま追従漏れしていた **KY41 4点整合違反の残骸を是正**（→ v1.9・最終改版日 2026-06-28）。

→ **P3 は設計→レビュー→承認→実装→検証→確定→台帳反映まで全クローズ。原則43 完了。**

### P3 で残る軽微フォロー（P1 とは独立・次回設計書改版時で可）
- 設計書 `scc23_v2_00_design_v2_8.docx` §9.2.5 の P3 行に「v2.02 実装済」注記。
  - ※ §9.2.11（P3本体）は前チャットで append-only 反映済み・4点一致確認済み。残るのは §9.2.5 概要表の1行注記のみ。急がない。

---

## 1. P3 の到達点（確定済み・参照用）

### 1.1 P3 の内容
パターン: `ADD  B, A` / `MOV  A, B`（隣接）→ `ADD  A, B` へ統合。
- 加算可換 `B₀+A₀=A₀+B₀` により A最終値・FLAGS(Z/N/C/V) 同値。差は B の値のみ → **B が dead のときのみ置換**。
- ガード G1〜G4。G4 = 固定窓 W=6 で B dead を積極証明（B再定義を先に発見＝置換／B読み・境界＝非置換／未確定＝非置換）。
- 境界 = ラベル / `JSR`/`RET`/`IRET` / 分岐 `JMP`/`BEQ`/`BNE`/`BLT`/`BGE`（ISA2.3実機。`BMI`/`BPL`は非存在）。

### 1.2 実装位置（v2.02.c 内）
- ヘルパ群: `is_p3_add_BA` / `is_p3_mov_AB` / `p3_redefines_B` / `p3_reads_B` / `p3_is_boundary` / `p3_b_dead_within_window` を `is_flag_neutral_A` の直後に配置。
- ループ: `peephole_pass()` 内、P2a→P2b の**後段**に独立ループ（前詰め方式）。書換は g_insbuf[w-1] を `ADD A,B` へ・g_insbuf[r] 破棄。

### 1.3 検証結果（PASS・確定）
| 検証 | 結果 |
| --- | --- |
| 絶対ゲート | -O0 Dhrystone = 826/48405/P:20（不変維持）✅ |
| byte不変 | -O0 が v2.01 -O0 と byte一致（P3 が -O0 非作動）✅ |
| P3作動 | -O1 で `ADD A,B` 統合発生・cycles 改善 ✅ |
| 機能正当 | -O1: **cycles 48055→47885・835 DPS・P:20不変** ✅ |
| V5回帰(実行) | fib(F55)/test_for(6)/test_local(A)/test_for_call(3)/Dhrystone(P:20) が v2.01 -O1 と全結果一致 ✅ |
| 混入検査 | poc vs v2.01 = 追加112行/削除0行（P3 2ブロックのみ・他改変なし）✅ |

---

## 2. 確立したビルド手順（重要・再現用）

### 2.1 Dhrystone -O0（絶対ゲート / Makefile デフォルト）
```
make regress SCC=./scc23      # 826/48405/P:20・21846B
```
プロジェクト Makefile（/mnt/project/Makefile）をコピーして使用。`make dhrystone` は D1〜D7 を自動実行。

### 2.2 Dhrystone -O1（peephole 検証用・手順の核心）
Makefile に -O1 ターゲットが無いため手順を踏む（**runtime-org は 0x0100**・bin方式・`JSR _main` 実アドレス sed 置換）:
```
scc23 --code-org 0x0400 --data-org 0x4000 --runtime-org 0x0100 -O1 -o dhry.asm dhry_timer.c
hasm23 dhry.asm                        # 単純bin（-c は使わない）→ dhry.asm.bin
MAIN=$(grep -E '^[0-9a-f]+ _main$' dhry.asm.sym | awk '{print $1}')
sed -E "s/JSR[[:space:]]+_main/JSR  \$${MAIN}/" startup_harness23_v15.asm > sh.asm
hasm23 sh.asm
printf 'SECTION code 0x0000 dhry.asm.bin\nSECTION harness 0x0000 sh.asm.bin\n' > dhry.lds
lnk23 -o dhry.bin --sym dhry.sym dhry.lds
emu23 dhry.bin -q                      # P:20不変を確認
```

### 2.3 ハマりどころ（KY34・実証済み）
- hasm23 出力命名は **`<input>.asm.bin`**（`<input>.bin` ではない）。
- emu23 起動オプション順: `./emu23 binary.bin -q`（バイナリ名の後ろにオプション）。
- `--runtime-org 0x3000` は **-c(obj)モード時のみ**。bin方式 Dhrystone では **0x0100 が正**。
- Dhrystone は **bin方式**（`hasm23` -c なし）。obj方式(`-c`)＋lds の SECTION配置は道2(YUI OS)用で Dhrystone には不適。
- harness は `JSR _main` を**実アドレスへ sed 置換**してからアセンブル。

### 2.4 使用ツール（確定バージョン）
- **scc23 v2.02**（本チャットで確定）/ hasm23 v1.04 / lnk23 v2.01 / **emu23 v1.09**
- 台帳: **tool_version_ledger_v1_9.md**（最新）。
- emu23 は手順書 v1.8 記載の v1.07 から更新されているが通常動作同一（記録済み）。

---

## 3. 次の本題: P1（導入順 ③）

### 3.1 P1 とは
- 導入順（設計書 §9.2.9 E-3 / §9.2.5）: ①P2✅ → ②P3✅ → **③P1（次）** → ④P4。
- P1 = **スタックラウンドトリップ除去**（冗長な退避・復帰往復の除去）。
- HANDOVER_PEEPHOLE_v1_0.md §2.5 実測: 現行 scc23 のスタック退避は **SUBI SP/STW 形**（PUSH/POP形でない）。P1往復は実測 **197箇所**。

### 3.2 P1 の注意（設計書記載・高リスク）
- **P1 は高リスク**（設計書明記）。SP相対 `[SP+imm]` の参照・`JSR`/`RET` 介在検出が必要（§9.2.9 M-4 で具体化済み）。
- これまでの P2a/P2b/P3 が「2命令隣接・フラグ/可換の局所証明」で済むのに対し、P1 は **退避〜復帰の区間にまたがる解析**が要る。区間内の SP相対アクセス・関数呼び出し・分岐の有無を見て安全性を判定するため、誤置換のリスクが質的に高い。
- 着手は**原則43 フルサイクル必須**: P1実装設計書 作成 → レビュー（M/C/N/E分類）→ 承認 → 工程確認「工程ヨシ!」→ KY活動 → 「ご安全に！」→ 実装。**承認前の実装着手は厳禁。**

### 3.3 別チャット開始時の手順
1. **claude_tool_operation_guide_v1_0.txt 参照**（規律1〜5）。
   - **今回・前回の教訓**: コンテキスト長が伸びると `antml:` プレフィックス脱落で出力操作が不能になる。**出力操作（cp + present_files）はコンテキストが短いうちに早期実行**。複雑スクリプトは create_file で別ファイル化し、bash_tool には実行コマンドのみ渡す（heredoc 内 `<`/`>` 記号が引き金）。
2. **本 HANDOVER と設計書 `scc23_v2_00_design_v2_8.docx` を確認**（KY34: 実ファイルが真実）。
3. **「進捗と予定の確認(latest)」チャットで最新ロードマップを工程確認** → 「工程ヨシ!」。
4. P1 の既存設計を `project_knowledge_search`（"§9.2.9 M-4" "SP相対" "スタックラウンドトリップ" 等）で確認。
5. P1 実装設計書を作成し、原則43 フルサイクルへ。実験コードは **KY38: `_poc` サフィックス**（本番 scc23_v2_02.c は直接改変厳禁）。

---

## 4. 成果物（/mnt/user-data/outputs/）
- `scc23_v2_02.c` — **v2.02 確定版**（P3実装・検証済み・出力済み）
- `tool_version_ledger_v1_9.md` — **最新台帳**（scc23 v2.02 反映・ヘッダ是正済み・出力済み）
- `scc23_v2_02_peephole_P3_design_v1_1.md` — P3設計書（承認済み・前チャット成果）
- `scc23_v2_00_design_v2_8.docx` — 設計書本体（§9.2.11 反映済み・§9.2.5 注記のみ次回）
- `HANDOVER_PEEPHOLE_P1_v1_0.md` — 本文書

---

## 5. PDCA（本チャット C/A）
- **C（評価）**: 前チャット未完の出力操作のみが残課題だったが、KY活動の防止策どおり「コンテキストが短いうちに出力を最優先実行」を徹底し、表示崩れの再発なく完遂。v2.02 確定・台帳 v1.9 反映まで完了。KY41 ヘッダ追従漏れも発見・是正できた。
- **A（改善）**: 出力操作の早期実行は有効だった。今後も「確定済みの成果物は、検証の駄目押しより先に outputs 出力を済ませる」を標準動作とする。P1 は区間解析を伴う高リスクのため、設計レビュー段階で「誤置換シナリオの列挙」をレビュー必須項目に加えることを推奨。

以上 / HANDOVER_PEEPHOLE_P1_v1_0.md
