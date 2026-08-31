# YSD8800 プロジェクト アーカイブ目録 v1.0

| 項目 | 内容 |
|---|---|
| ファイル名 | `ARCHIVE_INDEX_v1_0.md` |
| Version | **v1.0** |
| 作成日 | **2026-08-27** |
| 起票者 | Claude |
| ステータス | v1.0 初版（`knowledge_relocation_plan_v1_0.md` 承認に基づく S-2 成果物） |
| 上位文書 | `knowledge_relocation_plan_v1_0.md` v1.0 |
| 保管先 | **Google Drive: `YSD8800/ARCHIVE/`** |
| 登録先 | **本目録のみプロジェクトナレッジにも登録する**（本体50本は登録解除） |

## 変更履歴

| 版 | 日付 | 内容 | 起票者 |
|---|---|---|---|
| v1.0 | 2026-08-27 | 初版。Drive移設50本の目録を作成。未消化TODO・復帰トリガを全数記録。 | Claude |

---

## 0. 本目録の使い方

### 0.1 目的

プロジェクトナレッジ容量逼迫（97%）解消のため、確定済み設計文書50本を Google Drive へ移設した。**Driveは自動検索されないため、本目録がないとClaudeは「そこに何があるか」を知ることができない。** 本目録はナレッジ側に残す唯一の索引である。

### 0.2 ★最重要★ 未消化TODOはここにしかない

移設50本のうち**多数に未消化の改版TODOが残存**していた。本体が手元から消えるとTODOごと失われるため、**「未消化TODO」列が本目録の存在意義の中核**である。工程完了時には必ず本目録の該当行を確認すること。

### 0.3 復旧手順

1. **ローカル環境**に全生成物の原本が保管されている（かやぬまさん確認済・2026-08-27）
2. 必要になったら**ローカルからプロジェクトナレッジへ再登録**する
3. **Driveから復元しようとしないこと**（§0.4 参照）

### 0.4 ★Driveのファイルはコピー＆ペースト不可★

Google Drive コネクタの `read_file_content` は「自然言語表現」を返すため、**Markdownエスケープにより内容が変質する**（実証済：`knowledge_relocation_plan_v1_0.md` §3）。

- **散文の設計文書**：意味は取れる。Claudeが内容を参照する用途では実用可
- **ソースコード**：識別子の `_` がエスケープされ、`<` がUnicode化し、インデントが消失する。**コンパイル不能**
- したがって本アーカイブには**ソースコードを一切置かない**（`.md` / `.docx` のみ・全50本確認済）

### 0.5 改版が必要になったら

**必ずナレッジ側へ復帰させてから改版すること。** Drive上で直接改版すると版数分裂を起こす（既存 `YSD8800/DOCS/` が実例）。`ARCHIVE/` は**確定・不変**の領域である。

---

## 1. `ARCHIVE/YUIOS/` — YUI OS 設計文書・完了チケット（22本 / 985,214 B ≒ 962 KB）

### 1.1 設計文書（15本）

| # | 文書 | 確定版 | 内容 | 未消化TODO | 復帰トリガ |
|---|---|---|---|---|---|
| Y-01 | `yuios_ph4_filemgr_design_v1_9_6.md` | v1.9.6 | Ph.4 フラットFS + FileMgr 設計書。全API（LIST/OPEN/CLOSE/READ/WRITE/SEEK/STAT/DELETE）実装完了。**単独294 KB＝旧最大文書** | — | **Ph.7（FAT12移行）** |
| Y-02 | `yuios_memmap_design_v2_4.md` | v2.4 | メモリマップ再設計書（Ph.3.5-b〜Ph.5/Ph.6 高位再配置） | ★**Step 3完了後に `CALLSTK_TOP`/`DATASTK_TOP` を `$F07F`/`$F87F` → `$F07E`/`$F87E` へ改版**★<br>O-4：`yuios_design` v2.6 §9 の Level 区分導入と同期改版 | **Step 3完了時** |
| Y-03 | `yuios_design_v2_7.md` | v2.7 | YUI OS 全体設計書。Level 1=Forth／Level 2=C の区分 | §8.4「メモリ再配置（案C・memmap v1.7 改版要件）」が未消化 | ④ YUI OS改善 |
| Y-04 | `yuios_ph3_uart_design_v1_6.md` | v1.6 | Ph.3 UART ドライバ設計書 | ★**Ph.3.5完了時（Step 7-C）に一括改版 → v1.7**★<br>§10「次工程（Ph.3-A5 実装）への引継ぎ」 | **Step 7-C** |
| Y-05 | `yuios_ph3_storage_design_v1_6.md` | v1.6 | Ph.3 ストレージドライバ設計書 | ★**Ph.3.5完了時（Step 7-C）に一括改版 → v1.7**★ | **Step 7-C** |
| Y-06 | `yuios_ctxsw_abreg_restore_design_v0_3.md` | v0.3 | コンテキストスイッチ A/Bレジスタ復元 設計書 | v0.3＝未確定版数。完了判定要確認 | ④ YUI OS改善 |
| Y-07 | `yuios_ipc4_pool_design_v1_3.md` | v1.3 | IPC4 共通メッセージプール方式 詳細設計書 | §10.2「Ph.5 以降」節あり。timeout/cancel/task kill は §6.3 で将来課題 | Ph.5 |
| Y-08 | `yuios_tcb_design_v1_3.md` | v1.3 | TCB レイアウト改版設計書（16タスク化） | §12 将来課題：`IPC4-CALL-TIMEOUT`／cancel API／`task_cleanup_queue`／独立 `WAIT_DRIVER` 状態（値4予約） | Ph.5 |
| Y-09 | `yuios_ph6_shell_design_v1_2.md` | v1.2 | Ph.6 Forth 常駐 Shell 設計書 | ★**MW-5（シェル完全一致化・KY60横展開）で改版**★<br>§8「ビルド手順への影響（手順書改版要否）」未決 | **MW-5** |
| Y-10 | `yuios_ph3_5_i3_load_design_v1_3.md` | v1.3 | Ph.3.5-I-3 負荷試験（16タスク同時CALL）設計書 | — | Ph.3.5 追加試験時 |
| Y-11 | `yuios_makefile_design_v0_2.md` | v0.2 | Makefile 設計書（Step 8-B ビルドシステム改善）。**Step 8-B は完了済** | FileMgr 各テストビルド（`build_v0_10_*.sh` 系）統合は将来課題に残置<br>E-1：ビルド手順書 §10 将来課題 No.2 は Step 8-F/8-I へ | ビルドシステム改修時 |
| Y-12 | `yuios_ctxsw_abreg_design_v1_1.md` | v1.1 | コンテキストスイッチ A/Bレジスタ復元漏れ 修正設計書 | 「**要改版（実装GO後）**」の記述あり。実装完了済か要確認 | ④ YUI OS改善 |
| Y-13 | `mkfs_yuifs_design_memo_v1_2.md` | v1.2<br>(2026-05-29) | `mkfs_yuifs.py` v1.1 設計メモ。**Step 5-2 FILE-LIST-IMPL 試験のため `--add-file NAME` を追加**（内容は固定 "Hello, YUI OS!\n" 15B。★任意バイナリ格納＝`--add-binary` ではない★）。作成チャット：[YUI OS Ph.4 ファイルマネージャ開発の準備](https://claude.ai/chat/8235446d-aecc-4eb7-aa7a-bbf508495927) | §6.2「上位設計書（FileMgr v1.2）への改版要請」の消化状況要確認 | Ph.7（FAT12移行） |
| Y-14 | `YUI_OS_Level1_Functional_Spec_v1_0.docx` | v1.0 | YUI OS Level 1 機能仕様書 | （docx・未抽出） | ④ YUI OS改善 |
| Y-15 | `YUI_OS_Specification_v1_0.docx` | v1.0 | YUI OS 仕様書（初版） | （docx・未抽出）v2.x系 `.md` に実質置換済 | ④ YUI OS改善 |

### 1.2 完了チケット・検証記録（7本）

| # | 文書 | 確定版 | 内容 | 未消化TODO | 復帰トリガ |
|---|---|---|---|---|---|
| Y-16 | `kernel_v12_8_migration_design_v1_3.md` | v1.3 | kernel v12.8 移行・yuios 絶対ゲート再設定 設計書 | 候補原則A：サブシステム間の追随状況を Makefile に明示リスト化し「追随未完タグ」を残す運用 → **kaizen未登録の可能性** | — |
| Y-17 | `yuios_tkt04_w5_verify_design_v0_3.md` | v0.3 | TKT-04 検証項目 W-5 再現手順 設計書 | M-8：`_w5_pc` 実測 `$0613`。プレースホルダ規約（`$FFFF`＋TODO）明記済 | — |
| Y-18 | `startup_harness23_v17_irq1_regsave_fix_design_v1_1.md` | v1.1 | `startup_harness23 v1.7` `_irq1_handler` レジスタ退避改修 設計書 | §7 将来課題（申し送り・KY41）あり<br>ビルド手順書改版要否の提示が未決 | — |
| Y-19 | `step8i_irqfix_design_v0_2.md` | v0.2 | Step 8-I IRQ優先制御 修正方針 設計書 | IRQ2優先選択ロジックを将来課題化（現状IRQ2未使用）<br>※`v3_7_design_memo` §2 で **N/Aクローズ済** | ②.5（GPIO拡張でIRQ2使用時） |
| Y-20 | `yuios_paired_impl_ledger_v1_0.md` | v1.0 | YUI OS 対実装台帳 | — | ④ YUI OS改善 |
| Y-21 | `yuios_ref_freeze_ticket_I4_v1_0.md` | v1.0 | `yuios_road2` リファレンス凍結票 | — | — |
| Y-22 | `irqtest_design_v0_2.md` | v0.2 | Step 8-I 実害再現テスト 設計書。emu23 IRQ pending 保護の定量実証 | — | — |

---

## 2. `ARCHIVE/FPGA_DESIGN/` — 旧フェーズ FPGA 設計メモ（10本 / 202,347 B ≒ 198 KB）

⚠️ **これらはCPUコアが9フェーズ連続 v0.5.8 無改修である期間の設計判断記録。** バグの詳細（特に F-03 の BUG-1）は `fpga_source_version_ledger` に要約されているが、**原因分析の全文は本メモ側にのみ存在する可能性**がある。

| # | 文書 | 確定版 | 内容 | 未消化TODO | 復帰トリガ |
|---|---|---|---|---|---|
| F-01 | `v3_design_memo_v0_3.md` | v0.3 | V3 設計メモ（メモリ・バス・MMIOデコード／PSRAM統合） | `fpga_impl_roadmap_v1_0` の「64KBメモリをBRAM実装」記述とPSRAM前提の齟齬 → v1.1 で改版予定（**現行 v1.3 で解消済と推定・要確認**） | ② キャッシュRTL |
| F-02 | `v3_5_design_memo_v0_3.md` | v0.3 | V3.5（MMU統合）設計メモ | 主設計書 `YSD8800_MMU_Design_v1_1_0.docx` → **v1.2.0 へ改版要**（§2.4/§9）※現行 v1_2_0 で**消化済** | ③ FPGA物理実装 |
| F-03 | `v3_7_design_memo_v0_3.md` | v0.3 | V3.7 YSD8004 割込コントローラ設計メモ。★**BUG-1（`addr_i` 2bit化により IRQ_STAT と IRQ_MASK が入替。S3単体TB 21/21 PASS の偽合格）**★ | §2 で旧§3.5「IRQ2優先選択」を N/A クローズ済 | ②.5 / ③ |
| F-04 | `v4_design_memo_v0_2.md` | v0.2 | V4 YSD8001 UART FPGA実装 設計メモ | — | ③ FPGA物理実装 |
| F-05 | `v5_design_memo_v0_5.md` | v0.5 | V5 YSD8002 タイマー設計メモ。S1〜S10＋EN是正（案B）完了 | ★**案A（`TIMER_EN=0` でカウンタ歩進停止）は将来課題・V6以降へ先送り**★ | ②.5 RTL追加機能 |
| F-06 | `v6_en_fix_design_memo_v0_1.md` | v0.1 | EN是正工程（TCR発火EN OR→AND）設計メモ | ★**案A（カウンタ停止）は案Bでは表現不能＝将来課題**★<br>`ysd8002_timer_design` へ「§X 将来課題」節の新設要請<br>RTL冒頭コメント L86-92 の表現改訂要請 | ②.5 RTL追加機能 |
| F-07 | `v6a_storage_design_memo_v0_2.md` | v0.2 | V6-A ストレージコントローラ（YSD8003）RTL設計メモ。案D wait-state制御（`SD_STAT` $FCA2 読み時にSPI未完なら `mem_ready` 抑止） | — | ③ FPGA物理実装 |
| F-08 | `v6a_integration_design_memo_v0_3.md` | v0.3 | V6-A 上位結合 設計メモ | 既存 `mmio_ready` ロジックと AND 合流する箇所の特定（§次ステップで実測）＝**実測完了か要確認** | ③ FPGA物理実装 |
| F-09 | `v8_catls_integ_design_memo_v0_2.md` | v0.2 | V8 YUI OS統合 選択肢A（cat/ls フル統合）設計メモ | — | — |
| F-10 | `v8_catls_local_reproduce_procedure_v1_0.md` | v1.0 | V8 cat/ls INTEGRATION ローカル再現手順書 | — | — |

---

## 3. `ARCHIVE/EMU23/` — emu23 大規模改修チケット（7本 / 259,868 B ≒ 254 KB）

⚠️ emu23 は **v2.00〜v2.15 の全13セッションで改修完了**。現行の契約書 `emu23_device_design_v1_12.md` と `emu23_debug_manual_v1_10.md` は**ナレッジに据置**しており、本群は改修過程の記録である。

| # | 文書 | 確定版 | 内容 | 未消化TODO | 復帰トリガ |
|---|---|---|---|---|---|
| E-01 | `emu23_mc_design_v0_7.md` | v0.7 | マシンサイクル対応（`-mc` オプション）設計書。Phase C | — | ② キャッシュRTL（CPI検討時） |
| E-02 | `emu23_memwrite_design_v0_4.md` | v0.4 | 任意アドレス書き込み機能 設計書 | — | — |
| E-03 | `emu23_argsym_design_v1_0.md` | v1.0 | 起動引数解析・シンボル容量 改修設計書 | — | — |
| E-04 | `emu23_bp_continue_design_v1_0.md` | v1.0 | B-4（EMU-C）BP停止位置からの `c` 再開 修正設計書 | 「★ビルド手順書の改版要否★」の記述あり → **`yuios_build_procedure_v1_14` で消化済か要確認** | — |
| E-05 | `emu23_interactive_mode_design_v1_2.md` | v1.2 | 対話モード設計書 | — | — |
| E-06 | `emu23_ticket_EMU_D_symname_v1_0.md` | v1.0 | チケット EMU-D：シンボル名31文字超の切詰めによるラベルBP不能 | ★**チケット自体が未解決**★ 深刻度=中（現状は発現せず・将来発現しうる）。起票元 `emu23_argsym_design_v0_3.md` §6.5 はナレッジ未登録 | **emu23 次期改修時** |
| E-07 | `sim_impl_policy_v0_2.md` | v0.2 | シミュレータ実装指針（ハードウェア写像可能性規範） | 「V5 が未完了（S5以降残存）のため、本付録は V5 完了後に追記・改版する余地を残す」→ **V5は完了済。改版が未実施** | ② キャッシュRTL |

---

## 4. `ARCHIVE/TOOLCHAIN/` — 確定ツールの設計文書（8本 / 154,997 B ≒ 151 KB）

⚠️ hasm23 v1.04 / lnk23 v2.01 / Force v1.5 はいずれも確定版。**scc23 は Phase 2〜6 が並走予定のため本群に含めない。**

| # | 文書 | 確定版 | 内容 | 未消化TODO | 復帰トリガ |
|---|---|---|---|---|---|
| T-01 | `hasm23_xref_yof_design_v2_3.md` | v2.3<br>(2026-06-21) | hasm23＋lnk23 クロスファイルシンボル参照対応＋YOF固定アドレス配置ビルド 設計書。Step 8-F-2「道2」統合テストI1-I3完了後に確定。作成チャット：[Step 8-F ツール不具合改修の続行](https://claude.ai/chat/4c7748ca-daea-45b0-ab24-1082e6cea54c) | ビルド手順書 §10 将来課題 **No.2/3/6** の恒久対処が対象工程。**消化状況要確認** | hasm23/lnk23 改修時 |
| T-02 | `review_insights_v1_0.docx` | v1.0 | レビュー知見集 | （docx・未抽出）「将来課題」の語あり | — |
| T-03 | `toolchain23_design_v1_2.docx` | v1.2 | ツールチェーン23 全体設計書 | （docx・未抽出） | ISA3.0/YSD8810 設計時 |
| T-04 | `forth_compiler_design.docx` | — | Force Forth クロスコンパイラ設計書 | （docx・未抽出） | Force改修時 |
| T-05 | `lnk23_design_v1_4.docx` | v1.4<br>(2026-06-21) | lnk23 リンカ設計書。hasm23_xref_yof_design v2.3 と同一の道2実装で同時改版。作成チャット：[Step 8-F ツール不具合改修の続行](https://claude.ai/chat/4c7748ca-daea-45b0-ab24-1082e6cea54c) | （docx・未抽出） | lnk23改修時 |
| T-06 | `force_memory_contract_v1_2.md` | v1.2 | Force コンパイラ メモリ使用契約書 | §6「既知の懸念事項（将来の TODO）」あり | Force改修時 |
| T-07 | `force_ir_spec.docx` | — | Force IR 仕様書 | （docx・未抽出） | Force改修時 |
| T-08 | `force_lnk23_build_report_v1_0.docx` | v1.0 | Force/lnk23 ビルドレポート | （docx・未抽出） | — |

---

## 5. `ARCHIVE/DEVICE/` — 周辺デバイス設計文書（3本 / 75,495 B ≒ 74 KB）

| # | 文書 | 確定版 | 内容 | 未消化TODO | 復帰トリガ |
|---|---|---|---|---|---|
| D-01 | `ysd8001_uart_design_v1_2.docx` | v1.2 | YSD8001 UART デバイス設計書 | （docx・未抽出） | ②.5 GPIO拡張バス / ③ |
| D-02 | `ysd8002_timer_design_v1_2.docx` | v1.2 | YSD8002 タイマー デバイス設計書。§11.1 に EN是正（案B）の正式記録 | ★**§11 将来課題：案A（`TIMER_EN=0` でカウンタ歩進停止）は未実装**★（F-05/F-06 と対応） | **②.5 RTL追加機能** |
| D-03 | `YSD8800_MMU_Design_v1_2_0.docx` | v1.2.0 | YSD8800 MMU 設計書（FM-11方式16ページMMU） | （docx・未抽出） | ③ FPGA物理実装 |

---

## 6. 工程別 復帰チェックリスト

各工程の着手前に、本表の該当行を確認すること。

| 工程 | 復帰・確認すべき文書 |
|---|---|
| **② キャッシュRTL** | F-01, E-01, E-07 |
| **②.5 RTL追加機能**（GPIO拡張バス・デバッグDIO） | ★**D-02（案A＝TIMER_EN カウンタ停止）**★, F-05, F-06, Y-19（IRQ2優先制御） |
| **③ FPGA物理実装** | F-02, F-03, F-04, F-07, F-08, D-01, D-03 |
| **④ YUI OS改善** | Y-03, Y-06, Y-12, Y-14, Y-15, Y-20 |
| **Step 3 完了時** | ★**Y-02（memmap: `$F07F`/`$F87F` → `$F07E`/`$F87E`）**★ |
| **Step 7-C（Ph.3.5完了）** | ★**Y-04, Y-05（一括改版 → v1.7）**★ |
| **MW-5（シェル完全一致化）** | ★**Y-09**★ |
| **Ph.5** | Y-07, Y-08 |
| **Ph.7（FAT12移行）** | Y-01, Y-13 |
| **ツール改修時** | T-01（hasm23/lnk23）, T-04/T-06/T-07（Force）, T-03（ISA3.0） |
| **emu23 次期改修時** | ★**E-06（未解決チケット EMU-D）**★, E-02, E-03, E-04, E-05 |
| **新規デバイス／シミュレータ設計時** | ★**E-07 `sim_impl_policy_v0_2`（上位規範・全ツール設計に適用と自称）**★ |
| **メモリマップ変更時（T-3/Y-02 と連動）** | ★**T-06 `force_memory_contract_v1_2`**★（`ysd8800_kern.tgt` の依存設計書・KY19 同期改版必須） |

---

## 7. 要確認事項（本目録作成時に検出）

以下は「TODOとして記録されているが、既に消化済の可能性がある」項目。次回の台帳更新時に確認されたい。

| # | 項目 | 記録元 | 確認方法 |
|---|---|---|---|
| C-1 | `fpga_impl_roadmap` の「64KBをBRAM実装」記述の是正 | F-01 | 現行 v1.3 の本文を確認 |
| C-2 | `YSD8800_MMU_Design` の v1.2.0 改版 | F-02 | **消化済**（現行 D-03 が v1.2.0） |
| C-3 | ビルド手順書 §10 将来課題 No.2/3/6 の恒久対処 | T-01, Y-11 | `yuios_build_procedure_v1_14` §10 を確認 |
| C-4 | `sim_impl_policy` の V5完了後の追記・改版 | E-07 | **未実施**。V5は完了済 |
| C-5 | `emu23_bp_continue` のビルド手順書改版要否 | E-04 | `yuios_build_procedure_v1_14` 改版履歴を確認 |
| C-6 | `v6a_integration` の `mmio_ready` AND合流箇所の実測 | F-08 | ①.5 の CDC 作業で実測済か確認 |
| C-7 | `kernel_v12_8_migration` の「候補原則A」（追随未完タグ運用） | Y-16 | `kaizen.txt` への登録有無を確認 |
| C-8 | ~~docx 11本の未消化TODO未抽出~~ → ★**クローズ（2026-08-27 実査済・下記 §7.1 参照）**★ | §1.1, §4, §5 | 発行前にローカル実査で抽出完了 |
| C-9 | ★**`yuios_ph3_uart_design_v1_6.md` の KY41 4点整合違反**★ | Y-04 | 復帰時に本文ヘッダを是正（下記 §7.1 F-1） |
| C-10 | ★**`.docx` 拡張子11本の実体がプレーンテキスト**★ | §1.1, §4, §5 | 拡張子と実体の不一致（下記 §7.1 F-2） |

---

## 7.1 ★docx 実査結果（C-8 クローズ）と副次的発見★

本目録の発行直前に、`.docx` 11本をローカル実査した。その結果、**目録の記述精度に関わる2件の不整合**を検出した。

### F-1：`yuios_ph3_uart_design_v1_6.md` の KY41 4点整合違反

| 整合点 | 実測値 | 判定 |
|---|---|---|
| ファイル名 | `yuios_ph3_uart_design_v1_6.md` | v1.6 |
| 本文ヘッダのファイル名表記 | `yuios_ph3_uart_design_v1_5.md` | ★**v1.5 のまま**★ |
| Version 文字列 | `Version 1.5 / 2026-05-01（最終改版: 2026-08-06）` | ★**v1.5 のまま**★ |
| 改版履歴 | 2026-08-06 の追記あり | v1.6 相当 |

**「最終改版」日付だけを追記し、版数文字列とファイル名表記を追従させていない。** `fpga_source_version_ledger` v1.9 で「KY41 4点整合」を運用ルール化した後も、YUI OS 側の文書には適用が行き渡っていなかったことになる。

→ **T-1（Step 7-C での v1.7 改版）の際に必ず同時是正すること。**

### F-2：`.docx` 拡張子11本の実体がプレーンテキスト

`file` コマンドで全数確認した結果、移設対象の `.docx` 11本は **OOXML（ZIP）ではなく UTF-8 プレーンテキスト**であった。

```
lnk23_design_v1_4.docx:         Unicode text, UTF-8 text
ysd8002_timer_design_v1_2.docx: C source, Unicode text, UTF-8 text
```

内容は Markdown 相当（`**太字**`・表記法）。**Word では正しく開けない可能性が高い。**

- **実害**：現時点ではなし（Claude・テキストエディタからは読める）
- **リスク**：Google Drive にアップロードすると、Drive が拡張子から MIME を推定して Word 文書として扱おうとし、プレビュー不能または文字化けする可能性がある
- **推奨**：Drive へのアップロード時に **`.md` へリネームする**か、そのまま上げてプレビュー可否を確認する

### F-3：消化済みの確認

`v3_5_design_memo_v0_3.md` の「`YSD8800_MMU_Design` v1.1.0 → v1.2.0 へ改版要」は、現行 `YSD8800_MMU_Design_v1_2_0.docx` の存在により**消化済み**（C-2 と同一事項）。

### docx 群の内容（抽出結果・「未抽出」欄の補完）

| 文書 | 版数 / 日付 | 内容（実査） |
|---|---|---|
| `review_insights_v1_0.docx` | v1.0 | **設計レビュー知見集**。V2 CPUコア単体検証〜V8 cat/ls フル統合の全レビューから抽出した恒久原則。「iverilog 上で YUI OS 稼働達成 記念」 |
| `toolchain23_design_v1_2.docx` | v1.2 / 2026-04-16 | ISA2.3 ツールチェーン設計書（hasm23 / disasm23 / emu23 / scc23） |
| `forth_compiler_design.docx` | v1.0 | Force（Forth Cross Compiler）設計方針書 |
| `lnk23_design_v1_4.docx` | v1.4 / 2026-06-21 | lnk23 リンカ設計書（YSD8800 ISA2.3 汎用リンカ） |
| `force_ir_spec.docx` | v1.0 | Force IR 仕様書（Intermediate Representation Specification） |
| `force_lnk23_build_report_v1_0.docx` | v1.0 / 2026-04-23 | Force / lnk23 カーネル結合ビルド動作確認報告書。Step 8-L |
| `ysd8001_uart_design_v1_2.docx` | v1.2 / 2026-04-29 | YSD8001 UART チップ設計書。文書番号 YSD8001-UART-001 |
| `ysd8002_timer_design_v1_2.docx` | v1.2 / 2026-07-18 | YSD8002 タイマーチップ抽象化（旧 v1.1 / 2026-04-16 から改版） |
| `YSD8800_MMU_Design_v1_2_0.docx` | v1.2.0 | MMU拡張設計書。FM-11方式ページング。⚠️**「ISA2.2準拠」表記**（現行 ISA2.3 との差異は要確認） |
| `YUI_OS_Specification_v1_0.docx` | v1.0 | YUI OS Microkernel Specification（英文）。⚠️**「YSD8800 ISA2.2」表記** |
| `YUI_OS_Level1_Functional_Spec_v1_0.docx` | v1.0 | YUI OS Level 1 機能仕様書 |

⚠️ **ISA2.2 表記の2本**（`YSD8800_MMU_Design_v1_2_0.docx` / `YUI_OS_Specification_v1_0.docx`）は、③FPGA物理実装や④YUI OS改善で参照する際に**現行 ISA2.3 との差異確認が必要**。

---

## 8. 移設ファイル全数リスト（検算用・50本）

| 保管先 | 本数 | 容量 |
|---|---:|---:|
| `ARCHIVE/YUIOS/` | 22 | 985,214 B |
| `ARCHIVE/FPGA_DESIGN/` | 10 | 202,347 B |
| `ARCHIVE/EMU23/` | 7 | 259,868 B |
| `ARCHIVE/TOOLCHAIN/` | 8 | 154,997 B |
| `ARCHIVE/DEVICE/` | 3 | 75,495 B |
| **合計** | **50** | **1,677,921 B** |

**検算（KY41 第6点）**：985,214 + 202,347 + 259,868 + 154,997 + 75,495 = **1,677,921 B**。`knowledge_relocation_plan_v1_0.md` §4 の移設容量と**完全一致**（差分 0 B）。本数も 22+10+7+8+3 = **50本**で一致。移設リストとの集合差分も**なし**（2026-08-27 実測）。

⚠️ **起票時の自己検出**：本§8の初稿では YUIOS を 943,875 B、TOOLCHAIN を 146,336 B と誤記しており、合計が 1,627,921 B（−50,000 B）となっていた。KY41 第6点「内訳数値の再検算」により発行前に自己検出・是正。`fpga_source_version_ledger` v1.9／v1.10 に続く**3例目の自己検出**である。

---

*以上*
