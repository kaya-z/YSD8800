# HANDOVER: scc23 peephole P3 完了 → P1 着手

- 文書版数: v1.0
- 日付: 2026-06-27
- 作成理由: 画面表示乱れのため別チャットへ引継ぎ。P3 はほぼ完了、次は P1。
- 前チャット: 「SCC23のピープホール最適化」→ 本チャット（P3実装）

---

## 1. P3 の到達点（ほぼ完了・確定待ち）

### 1.1 状態
- P3 実装は **`scc23_v2_02_poc.c`（KY38・本番非改変）に完了**。コンパイル成功。
- 設計書 `scc23_v2_02_peephole_P3_design_v1_1.md`（**承認済み**）に準拠。
- 設計書本体へ §9.2.11 を append-only 反映済み: `scc23_v2_00_design_v2_8.docx`（4点一致確認済み）。
- 原則43クリア済み（設計レビュー承認・設計書反映・工程確認「工程ヨシ!」「ご安全に！」）。

### 1.2 P3 の内容
パターン: `ADD  B, A` / `MOV  A, B`（隣接）→ `ADD  A, B` へ統合。
- 加算可換 `B₀+A₀=A₀+B₀` により A最終値・FLAGS(Z/N) 同値。差は B の値のみ → **B が dead のときのみ置換**。
- ガード G1〜G4。G4 = 固定窓 W=6 で B dead を積極証明（B再定義を先に発見＝置換／B読み・境界＝非置換／未確定＝非置換）。
- 境界 = ラベル / `JSR`/`RET`/`IRET` / 分岐 `JMP`/`BEQ`/`BNE`/`BLT`/`BGE`（ISA2.3実機。`BMI`/`BPL`は非存在）。
- フラグ専用ガード不要（P2bと違い、両者とも最後にADDがZ/N同値確定）。

### 1.3 実装位置（poc内）
- ヘルパ群: `is_p3_add_BA` / `is_p3_mov_AB` / `p3_redefines_B` / `p3_reads_B` / `p3_is_boundary` / `p3_b_dead_within_window` を `is_flag_neutral_A` の直後に追加。
- ループ: `peephole_pass()` 内、P2a→P2b の**後段**に独立ループ（前詰め方式）。書換は g_insbuf[w-1]を`ADD A,B`へ・g_insbuf[r]破棄。窓走査は r+1 以降を読み取り専用・`min(start+W,n)`で終端クランプ。

### 1.4 検証結果（PASS）
| 検証 | 結果 |
| --- | --- |
| V1 絶対ゲート | poc -O0 = 826/48405/P:20・21846B ✅ |
| V2 byte不変 | poc -O0 が v2.01 -O0 と **byte完全一致**（P3が-O0非作動）✅ |
| V3 P3作動 | -O1でペア 35→2、`ADD A,B` +33。残2は JSR境界・窓未確定で正しく非置換 ✅ |
| V4 機能正当 | poc -O1: **cycles 48055→47885(-170)・835 DPS・P:20不変** ✅ |
| V5 回帰(asm) | test_for/test_local/fib/test_for_call の4件、poc vs v2.01 差分は**全てP3統合パターンのみ**（誤拾いゼロ）✅ |

### 1.5 P3 残作業（別チャット冒頭で実施）
1. **V5 実行レベル確認**（駄目押し）: fib.c 等を emu23 実行し poc と v2.01 で出力一致を確認。
   - 中核正当性は V1〜V4＋V5(asm差分)で既に立証済み。これは品質確認。
2. **v2.02 確定**（KY41 4点一致）:
   - `scc23_v2_02_poc.c` → `scc23_v2_02.c` にリネーム
   - `SCC_VERSION "2.01"` → `"2.02"`（150行目付近）
   - ヘッダコメント・改版履歴を更新（P3追加を記載）
   - `--version` 表示が `scc23 v2.02` になることを確認
3. **tool_version_ledger** v1.7→v1.8（scc23 v2.01→v2.02・新cycles 47885 記録）。
4. 設計書 §9.2.5 の P3 行に「v2.02 実装済」注記（次回設計書改版時）。

---

## 2. 確立したビルド手順（重要・再現用）

### 2.1 Dhrystone -O0（絶対ゲート / Makefile デフォルト）
```
make regress SCC=./scc23      # 826/48405/P:20・21846B
```
プロジェクト Makefile（/mnt/project/Makefile）をコピーして使用。`make dhrystone` は D1〜D7 を自動実行。

### 2.2 Dhrystone -O1（P3検証用・手順の核心）
Makefile に -O1 ターゲットが無いため手順を踏む（**runtime-org は 0x0100**・bin方式・`JSR _main`実アドレスsed置換）:
```
scc23 --code-org 0x0400 --data-org 0x4000 --runtime-org 0x0100 -O1 -o dhry.asm dhry_timer.c
hasm23 dhry.asm                        # 単純bin（-c は使わない）
MAIN=$(grep -E '^[0-9a-f]+ _main$' dhry.asm.sym | awk '{print $1}')
sed -E "s/JSR[[:space:]]+_main/JSR  \$${MAIN}/" startup_harness23_v15.asm > sh.asm
hasm23 sh.asm
printf 'SECTION code 0x0000 dhry.asm.bin\nSECTION harness 0x0000 sh.asm.bin\n' > dhry.lds
lnk23 -o dhry.bin --sym dhry.sym dhry.lds
emu23 dhry.bin -q                      # P:20不変を確認
```

### 2.3 ハマりどころ（KY34・実証済み）
- `--runtime-org 0x3000` は **-c(obj)モード時のみ**必要。**bin方式のDhrystoneでは 0x0100 が正**（Makefile準拠）。
- Dhrystone は **bin方式**（`hasm23` -c なし）。obj方式(`-c`)＋ldsのSECTION配置は別系統（道2 YUI OS用）で、Dhrystoneには不適。
- harness は `JSR _main` を**実アドレスへ sed 置換**してからアセンブル（シンボル参照のままだと未定義エラー）。

### 2.4 使用ツール（本チャットでビルド・確認済み）
- scc23 v2.01（起点）/ hasm23 v1.04 / lnk23 v2.01 / **emu23 v1.09**
- emu23 は手順書 v1.8 の v1.07 から更新されているが通常動作同一（記録済み）。

---

## 3. 次の本題: P1（導入順 ③）

### 3.1 P1 とは
- 導入順（設計書 §9.2.9 E-3 / §9.2.5）: ①P2✅ → ②P3✅(本チャット) → **③P1** → ④P4。
- P1 = **スタックラウンドトリップ除去**（`PUSH`/`POP` または `SUBI SP/STW … LDW/ADDI SP` の冗長往復除去）。
- HANDOVER_PEEPHOLE_v1_0.md §2.5 実測: 現行 scc23 のスタック退避は **SUBI SP/STW 形**（PUSH/POP形でない）。P1往復は実測 **197回**。

### 3.2 P1 の注意（設計書記載・高リスク）
- **P1 は高リスク**（設計書明記）。SP相対 `[SP+imm]` の参照・`JSR`/`RET` 介在検出が必要（M-4 で具体化済み）。
- 着手は**原則43**: P1実装設計書作成 → レビュー → 承認 → 工程確認 → KY → 「ご安全に！」。
- まず `recent_chats`/`project_knowledge_search` で P1 関連の既存設計（§9.2.9 M-4・SP判定）を確認すること。

### 3.3 別チャット開始時の手順
1. claude_tool_operation_guide 参照（規律1〜5）。**今回の教訓: heredoc内の `<` `>` 記号でツール書式が崩れた。複雑スクリプトは create_file で別ファイル化を徹底。**
2. 本 HANDOVER と設計書 v2.8 を確認。
3. P3 残作業（V5実行・v2.02確定）を先に片付ける。
4. その後 P1 の実装設計に着手（原則43）。

---

## 4. 成果物（/mnt/user-data/outputs/）
- `scc23_v2_02_poc.c` — P3実装（検証済み・確定待ち）
- `scc23_v2_02_peephole_P3_design_v1_1.md` — P3設計書（承認済み）
- `scc23_v2_00_design_v2_8.docx` — 設計書本体（§9.2.11 反映済み）
- `HANDOVER_PEEPHOLE_P3_v1_0.md` — 本文書

---

## 5. PDCA（本日 C/A）
- **C**: P3 実装・検証は計画通り完遂（V1〜V4＋V5asm PASS）。実測33ペア統合（予想29以上）・cycles -170・P:20不変。
- **A（改善）**: ツール呼び出しで heredoc 内記号（`<` `>` 等）により画面表示が複数回崩れた。**次回以降、複雑スクリプトは必ず create_file で別ファイル化**し、bash_tool には実行コマンドのみ渡す。これを本日の最大の改善点として記録。

以上 / HANDOVER_PEEPHOLE_P3_v1_0.md
