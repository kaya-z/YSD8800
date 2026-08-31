# プロジェクトナレッジ整理計画書 v1.0

| 項目 | 内容 |
|---|---|
| ファイル名 | `knowledge_relocation_plan_v1_0.md` |
| Version | **v1.0** |
| 作成日 | **2026-08-27** |
| 起票者 | Claude（かやぬまさん指示による） |
| ステータス | v1.0 初版（**要レビュー・承認前**） |
| 目的 | プロジェクトナレッジ容量逼迫（97%）の解消。全179ファイルを実測判定し、廃棄／Google Drive移設／据置に分類する。 |
| 適用原則 | 原則43（設計→レビュー→承認→実装）／KY34（実ファイルが真実）／KY38（実験ファイルの隔離）／KY41（改版時の情報欠落防止）／KY57（証拠の不在≠不在の証拠） |

## 変更履歴

| 版 | 日付 | 内容 | 起票者 |
|---|---|---|---|
| v1.0 | 2026-08-27 | 初版。179ファイル全数を実測判定。廃棄10本／Drive移設50本／据置119本に分類。 | Claude |

---

## 1. 背景

プロジェクトナレッジ容量が **97%** に達し、新規成果物の登録が困難になった。
かやぬまさんより「不要と思われるものは無いか／特にテストベクタはこんなに必要か」との問題提起を受け、全数実査を実施した。

### 1.1 実査結果（2026-08-27時点）

| 項目 | 値 |
|---|---|
| ファイル総数 | **179本** |
| 総容量 | **4,635,748 B（約4.64 MB）** |

⚠️ **本作業開始時（同日）の実査では187本 / 4,718,186 B であった。** 会話中に8本（`gen_v2_vectors_v2e_poc.py` `vprobe_fragment_poc.asm` `golden_v2a.txt` `log_v8tb_pos.txt` `log_v8tb_neg.txt` `scc22_v3_x_spec_review.txt` `startup_harness.asm` `build_vprobe_poc.sh` ＝計82,438 B）が登録解除された。かやぬまさんによる先行廃棄と推測するが、Claudeによる直接確認は行っていない（KY57）。

### 1.2 容量偏在の構造

上位10ファイルで全体の約36%を占める。これはKY41「追記のみ・取り消し線で旧情報保持」運用の副作用であり、**文書サイズが単調増加する構造的欠陥**である。本計画はその緩和策でもある。

---

## 2. 判定ルール（承認済み）

各ファイルに以下4問を順に適用し、1つでもYesなら**据置**。全てNoなら**移設または廃棄**。

1. 毎セッション／高頻度で参照するか？（→ L0）
2. ビルド対象・md5ゲート対象の実ソースか？（→ L1）
3. 現工程（①.5 → ② → ②.5 → ③）で触る／根拠になるか？（→ L2）
4. 改版予定が記録に残っているか？（→ 保留＝据置）

### 2.1 方針決定事項（かやぬまさん判断・2026-08-27）

| # | 決定内容 | 根拠 |
|---|---|---|
| D-1 | **削除可と判断したものは廃棄する**（Drive退避せず） | 生成物は全てローカルに保管済であり、いつでも復旧可能 |
| D-2 | **YUI OS関連文書は移設可** | YUI OSには当面手を入れない |
| D-3 | **ソース類（`.sv` `.c` `.asm` `.py` `.fs` 等）はナレッジに据置** | 個々のサイズが小さく、逼迫の主因ではない |
| D-4 | **Google Driveには設計文書のみ保管する** | 下記 §3 の技術的制約による |
| D-5 | `dhry_all.c` / `dhry_all_ansi2.c` は据置 | かやぬまさん判断 |
| D-6 | `ysd8800.tgt` は据置 | 下記 §6.1 参照 |

---

## 3. ★重要★ Google Drive上のソースコードは復元できない（実証済）

### 3.1 検証内容

`YSD8800/FPGA/fpga_verification/tb_cpu_v8catls_poc.sv`（13,107 B）を Google Drive コネクタの `read_file_content` で取得し、原文と比較した。

### 3.2 結果：**読めるが、コンパイル不能な状態に変質する**

| 原文（あるべき姿） | Driveから返却された内容 |
|---|---|
| `tb_cpu_v8catls_poc` | `tb\_cpu\_v8catls\_poc`（アンダースコアが全てエスケープ） |
| `always #10 cpu_clk = ~cpu_clk;` | `always \#10 cpu\_clk = \~cpu\_clk;` |
| `while (dbg_halt !== 1'b1 && to_cyc < max_cyc)` | `... \!== 1'b1 && to\_cyc \u003c max\_cyc`（`<` がUnicodeエスケープ） |
| `` `timescale 1ns/1ps `` | `` \`timescale 1ns/1ps ``（バッククォートもエスケープ） |
| インデント | **全消失**（先頭空白が落ちる） |
| 行末 | Markdownの強制改行（半角空白2個）が全行に混入 |

**原因**：`read_file_content` は仕様上「自然言語表現」を返すため、Markdownとしてエスケープ処理される。ツール仕様にも「テキスト表現は将来変わりうるので形式を前提にするな」と明記されている。

### 3.3 `download_file_content`（base64）が代替にならない理由

バイト完全ではあるが容量が実用に耐えない。

| 対象 | 元サイズ | base64サイズ | 概算トークン |
|---|---:|---:|---:|
| `tb_cpu_v8catls_poc.sv` | 13 KB | 約17 KB | 約5K |
| `yuios_ph4_filemgr_design_v1_9_6.md` | 301 KB | 約401 KB | **約110K** |

1本読むだけでコンテキストを圧迫し、「ログが長大化するとツール呼び出しが不安定になる」という既知のリスクに抵触する。

### 3.4 結論

- **Driveは「バックアップ」ではなく「Claudeが内容を参照できる書庫」と位置づける**
- 保管対象は**散文の設計文書のみ**（書式が崩れても意味は取れる）
- **ソースコードはDriveに置かない**（置いても復元経路として機能しない）
- 復旧経路は一本化する：**ローカル → ナレッジへ再登録**

---

## 4. 判定結果サマリ

| 区分 | 本数 | 容量 | 比率 | 行き先 |
|---|---:|---:|---:|---|
| **据置** | **119** | **2,868,276 B（2,801 KB）** | 61.9% | プロジェクトナレッジ |
| **廃棄** | **10** | **89,551 B（87 KB）** | 1.9% | — |
| **Drive移設** | **50** | **1,677,921 B（1,639 KB）** | 36.2% | `YSD8800/ARCHIVE/` |
| 合計 | 179 | 4,635,748 B | 100% | （検算一致） |

### 4.1 期待効果

**4,636 KB → 2,868 KB。占有率 97% → 約 60%**

---

## 5. 廃棄リスト（10本 / 89,551 B）

| ファイル | 容量 | 廃棄理由 |
|---|---:|---|
| `HANDOVER_CHAT141.md` | 17,419 B | CHAT144に集約済 |
| `HANDOVER_CHAT142.md` | 15,415 B | 同上 |
| `HANDOVER_CHAT143.md` | 13,002 B | 同上 |
| `ysd8800_v4_membus_v0_1.sv` | 13,506 B | 歴代top-levelラッパー。系譜は `fpga_source_version_ledger` §12 に記録済 |
| `ysd8800_v35_membus_v0_1.sv` | 9,058 B | 同上（§10） |
| `ysd8800_v3_membus_v0_1.sv` | 3,322 B | 同上（§9） |
| `knowledge_registration_recommend_v1_1.md` | 8,629 B | 本計画書で上書きされる |
| `storage.txt` | 6,890 B | emu22世代のメモ。現行 `emu23_device_design_v1_12.md` で代替済 |
| `emu23_kairyo.txt` | 1,439 B | 改良要望メモ。emu23 v2.15 で全項目消化済 |
| `combine_simple.py` | 871 B | 参照なし・用途不明 |

⚠️ 廃棄はローカルに原本が存在することを前提とする（D-1）。

### 5.1 実施結果（2026-08-28）

S-5（ナレッジからの削除）実施済み。実測にて検証：

| 項目 | 実施前 | 実施後 | 差分 |
|---|---:|---:|---:|
| 本数 | 174 | 124 | −50 |
| 容量 | 4,637,653 B | 2,959,732 B | **−1,677,921 B**（移設50本と1バイト完全一致） |

**移設50本は完全に削除された。** 一方、廃棄10本のうち7本（`ysd8800_v3/35/4_membus` 3本・`knowledge_registration_recommend_v1_1.md`・`storage.txt`・`emu23_kairyo.txt`・`combine_simple.py`）は本計画書レビュー段階で既に登録解除されていたことが判明（実測確認済）。

**残る `HANDOVER_CHAT141/142/143.md`（計45,836 B）は、かやぬまさんの判断により意図的に据置とする。** 理由：CHAT144（現行引継ぎ文書）作成から日が浅く、しばらく並行して残し、安定を見てから順次削除する方針（2026-08-28決定）。よって現時点の廃棄実施本数は7本（廃棄予定10本中）。この3本は次回棚卸し時の削除第一候補として記録する。

---

## 6. 据置リスト（119本 / 2,868,276 B）— 分類根拠

### 6.1 L0 常時参照（13本）

`kaizen.txt` / `claude_tool_operation_guide_v1_0.txt` / `debug_style_guide.txt` / `tool_version_ledger_v1_26.md` / `fpga_source_version_ledger_v1_12.md` / `yuios_build_procedure_v1_14.md` / `HANDOVER_CHAT144.md` / `emu23_debug_manual_v1_10.md` / `emu23_device_design_v1_12.md` / `Makefile` / `ISA2_3_v231.docx` / `YSD8800_ABI_spec.docx` / `asm_spec_v22.docx`

**★据置判断の特記：`ysd8800.tgt`（1,453 B）**

実測により、現行ビルド3経路すべてで**未使用**であることを確認した。

| 確認先 | 実測結果 |
|---|---|
| `Makefile:88` | `TGT := ysd8800_kern.tgt` |
| `build_road2.sh:20` | `--tgt-file ysd8800_kern.tgt` |
| `build_v0_10_18.sh:13` | `--tgt-file ysd8800_kern.tgt` |
| ファイル冒頭 | `# YSD8800 ISA2.2 ターゲット設定 / Force v1.0`（ISA2.2世代） |
| `yuios_build_procedure_v1_14.md:170` | 「デフォルトの `targets/ysd8800.tgt` を使用すると配置設定が変わり整合が取れなくなる」＝**使用禁止と明記** |

しかし同手順書 L109 / L118 のビルドツリー構築手順に `cp /mnt/project/ysd8800.tgt targets/` が組み込まれているため、廃棄には手順書の改版が必要。得られる容量は全体の 0.03% であり、改版コストが上回る。

→ **据置とする。ただし §8 の改善提案 K-1 として起票する。**

### 6.2 L1 現行ソース（据置・主要なもの）

- **ツールチェーン**：`scc23_v2_07.c` / `emu23_v2_15.c` / `hasm23_v1_04.c` / `lnk23_v2_01.c` / `disasm23.c` / Force一式（`force_v1_5.c` `codegen_v1_5.c` `codegen_v1_4.h` `ir.c/h` `lexer.c/h` `parser.c/h`）/ `ysd8800.prim` / `ysd8800_kern_v0_6.tgt` / `ysd8800.tgt` / `mkfs_yuifs_v1_1.py` / `force_asm_audit_v1_2.py`
- **YUI OS ソース**：`kernel_forth_v0_10_18.fs` / `kernel_v12_11.asm` / `startup_harness23_v17.asm` / `startup_proc_v1_1.asm` / `kernel_forth_tests_filemgr.fs` / ビルドスクリプト3本
- **現行RTL 14本＋SDモデル1本**（V8-b でリンクした構成と一致）
- **回帰資産**：`tb_cpu_v8b_prod_v0_2.sv` / `dhry_timer.c` / `dhry_all.c` / `dhry_all_ansi2.c`

### 6.3 L2 現工程資産（15本）

②キャッシュRTL工程で直接触る／根拠となるもの。

- **PSRAM/CDC系TB 4本**：`tb_cdc_bridge_v0_1.sv` / `tb_psram_ctrl_v0_1.sv` / `tb_bridge_psram_integ_v0_1.sv` / `tb_bridge_psram_20bit_v0_1.sv`
- `cache_study_handover_v1_0.md` / `v9_psram_perf_baseline_v1_2.md` / `v9_psram_perf_design_memo_v0_4.md` / `emu23_cache_base_design_v1_0.md` / `ysd8800_cycle_count_table_v1_1.md`
- `v8b_prod_design_memo_v0_4.md`（BASE-01凍結の根拠）/ `yuios_rtl_boot_reproduce_procedure_v1_1.md`
- `fpga_impl_roadmap_v1_3.docx` / `fpga_v0_impl_spec_skeleton_v1_2.md` / `fpga_v1_cpucore_design_v1_2.md` / `measure_cpi_poc.sh`

### 6.4 旧フェーズ検証資産（D-3により据置・約324 KB）

V1/V2 CPU単体TB 12本＋`gen_v2_vectors.py` ／ V3・V3.5系 8本＋生成器3本 ／ V4系 TB2本＋生成器3本＋テストasm2本 ／ V5・V6系 TB4本＋テストasm4本 ／ ビルドスクリプト3本

⚠️ **将来の再逼迫時における第一削減候補**。根拠：`fpga_source_version_ledger` の記録により、CPUコアは V3.5 / V3.7 / V4 / V5 / EN是正 / V6-A / V8 / V8-b / ①.5 の**9フェーズ連続で v0.5.8 のまま論理不変**であり、これらのTBは9工程にわたり回帰で必要とならなかった実績がある。

---

## 7. Drive移設リスト（50本 / 1,677,921 B）

移設先：**`Google Drive: YSD8800/ARCHIVE/`**（新設。既存 `DOCS/` は試験用のため触らない）

### 7.1 `ARCHIVE/YUIOS/` — 22本

| ファイル | 容量 |
|---|---:|
| `yuios_ph4_filemgr_design_v1_9_6.md` | 294 KB |
| `yuios_memmap_design_v2_4.md` | 105 KB |
| `yuios_design_v2_7.md` | 59 KB |
| `yuios_ph3_uart_design_v1_6.md` | 57 KB |
| `yuios_ph3_storage_design_v1_6.md` | 56 KB |
| `yuios_ctxsw_abreg_restore_design_v0_3.md` | 48 KB |
| `yuios_ipc4_pool_design_v1_3.md` | 44 KB |
| `yuios_tcb_design_v1_3.md` | 42 KB |
| `yuios_ph6_shell_design_v1_2.md` | 30 KB |
| `kernel_v12_8_migration_design_v1_3.md` | 29 KB |
| `yuios_tkt04_w5_verify_design_v0_3.md` | 25 KB |
| `startup_harness23_v17_irq1_regsave_fix_design_v1_1.md` | 25 KB |
| `mkfs_yuifs_design_memo_v1_2.md` | 22 KB |
| `yuios_ph3_5_i3_load_design_v1_3.md` | 20 KB |
| `yuios_makefile_design_v0_2.md` | 20 KB |
| `YUI_OS_Level1_Functional_Spec_v1_0.docx` | 17 KB |
| `YUI_OS_Specification_v1_0.docx` | 13 KB |
| `yuios_ctxsw_abreg_design_v1_1.md` | 13 KB |
| `step8i_irqfix_design_v0_2.md` | 11 KB |
| `yuios_paired_impl_ledger_v1_0.md` | 10 KB |
| `yuios_ref_freeze_ticket_I4_v1_0.md` | 6 KB |
| `irqtest_design_v0_2.md` | 5 KB |

### 7.2 `ARCHIVE/FPGA_DESIGN/` — 10本

| ファイル | 容量 |
|---|---:|
| `v3_7_design_memo_v0_3.md` | 37 KB |
| `v3_5_design_memo_v0_3.md` | 34 KB |
| `v5_design_memo_v0_5.md` | 34 KB |
| `v4_design_memo_v0_2.md` | 30 KB |
| `v6a_storage_design_memo_v0_2.md` | 17 KB |
| `v8_catls_local_reproduce_procedure_v1_0.md` | 11 KB |
| `v6a_integration_design_memo_v0_3.md` | 9 KB |
| `v3_design_memo_v0_3.md` | 8 KB |
| `v6_en_fix_design_memo_v0_1.md` | 8 KB |
| `v8_catls_integ_design_memo_v0_2.md` | 5 KB |

### 7.3 `ARCHIVE/EMU23/` — 7本

| ファイル | 容量 |
|---|---:|
| `emu23_mc_design_v0_7.md` | 62 KB |
| `emu23_memwrite_design_v0_4.md` | 56 KB |
| `emu23_argsym_design_v1_0.md` | 47 KB |
| `emu23_bp_continue_design_v1_0.md` | 30 KB |
| `sim_impl_policy_v0_2.md` | 28 KB |
| `emu23_interactive_mode_design_v1_2.md` | 25 KB |
| `emu23_ticket_EMU_D_symname_v1_0.md` | 4 KB |

※ 現行契約書 `emu23_device_design_v1_12.md` と `emu23_debug_manual_v1_10.md` は L0 据置。

### 7.4 `ARCHIVE/TOOLCHAIN/` — 8本

| ファイル | 容量 |
|---|---:|
| `hasm23_xref_yof_design_v2_3.md` | 46 KB |
| `review_insights_v1_0.docx` | 28 KB |
| `toolchain23_design_v1_2.docx` | 19 KB |
| `forth_compiler_design.docx` | 14 KB |
| `lnk23_design_v1_4.docx` | 13 KB |
| `force_memory_contract_v1_2.md` | 11 KB |
| `force_ir_spec.docx` | 9 KB |
| `force_lnk23_build_report_v1_0.docx` | 6 KB |

※ hasm23 v1.04 / lnk23 v2.01 / Force v1.5 はいずれも確定版。**scc23 は Phase 2〜6 が並走予定のため対象外**（該当設計文書はナレッジ未登録）。

### 7.5 `ARCHIVE/DEVICE/` — 3本

| ファイル | 容量 |
|---|---:|
| `ysd8001_uart_design_v1_2.docx` | 28 KB |
| `YSD8800_MMU_Design_v1_2_0.docx` | 25 KB |
| `ysd8002_timer_design_v1_2.docx` | 19 KB |

---

## 8. ★リスクと防止策★

### R-1（最重要）未消化TODOの喪失

移設対象50本のうち **29本に「改版要／要改版／改版予定／将来課題／未完／保留／TODO／次工程」の記述が残存**することを実測で確認した。文書が手元から消えるとTODOごと失われる。

判明している主要TODO：

| 文書 | 未消化TODO |
|---|---|
| `yuios_ph3_uart_design_v1_6.md` | Ph.3.5完了時（Step 7-C）に一括改版 → v1.7 |
| `yuios_ph3_storage_design_v1_6.md` | 同上 → v1.7 |
| `yuios_memmap_design_v2_4.md` | Step 3完了後に `CALLSTK_TOP` / `DATASTK_TOP` を `$F07F`/`$F87F` → `$F07E`/`$F87E` |
| `yuios_ph6_shell_design_v1_2.md` | MW-5（シェル完全一致化）で改版 |
| `ysd8002_timer_design_v1_2.docx` | 案A（`TIMER_EN=0` でカウンタ歩進停止）は将来課題 |

**防止策**：`ARCHIVE_INDEX.md` に **「凍結時点の未消化TODO」欄を必須項目**として設ける。目録本体はプロジェクトナレッジに残すため、TODOだけは手元に保持される。

### R-2 復帰トリガの見落とし

**防止策**：`ARCHIVE_INDEX.md` に **「復帰トリガ工程」欄**を設ける（例：`yuios_ph6_shell_design_v1_2.md` → トリガ = MW-5、`yuios_ph3_uart_design_v1_6.md` → トリガ = Step 7-C）。

### R-3 Driveからのソース復元不能

§3で実証済。**防止策**：D-3/D-4により、ソース類は一切移設しない。本計画では移設50本すべてが `.md` / `.docx` の散文文書である（確認済）。

### R-4 二重管理による版数分裂

既存の `YSD8800/DOCS/` には試験用に置かれた旧版（`YSD8800_MMU_Design_v1.0.0` `lnk23_design_v1_2/v1_3` `emu23_device_design_v1_2` `ISA2_3_v230` `ysd8802_timer_design_v1_0`〈型番タイポ〉等）が存在する。**防止策**：`ARCHIVE/` を新設し `DOCS/` とは分離。`ARCHIVE/` は「確定・不変」のみを置き、改版が発生した文書は必ずナレッジ側へ復帰させてから改版する。

---

## 9. 実施手順

| # | 作業 | 実施者 | 状態 |
|---|---|---|---|
| S-1 | 本計画書のレビュー・承認 | かやぬまさん | **未** |
| S-2 | `ARCHIVE_INDEX.md` v1.0 生成（TODO欄・復帰トリガ欄付き） | Claude | 未 |
| S-3 | Drive に `YSD8800/ARCHIVE/{YUIOS,FPGA_DESIGN,EMU23,TOOLCHAIN,DEVICE}/` を新設し50本をアップロード | かやぬまさん | 未 |
| S-4 | `ARCHIVE_INDEX.md` をナレッジ＋Driveの両方に登録 | かやぬまさん | 未 |
| S-5 | ナレッジから移設50本＋廃棄10本を登録解除 | かやぬまさん | 未 |
| S-6 | `tool_version_ledger` / `fpga_source_version_ledger` に本作業の記録を追記 | Claude | 未 |
| S-7 | 容量再実測・効果確認 | Claude | 未 |

⚠️ **S-5 は S-4 完了後に行うこと。** 目録の登録前に本体を消すとTODOが失われる（R-1）。

---

## 10. 改善提案（kaizen候補）

| # | 提案 | 根拠 |
|---|---|---|
| **K-1** | `yuios_build_procedure` 改版時に、ビルドツリー構築手順から `ysd8800.tgt` の `cp` 行を削除し、同ファイルを廃棄する | 同手順書 L170 が「使用禁止」と明記しているファイルを L118 でコピーし続けている不整合。単独改版はコスト超過のため、他の改版機会に同時実施する |
| **K-2** | **KY41 にアーカイブ分離ルールを追加**：文書サイズが 80 KB を超えたら、クローズ済みの過去版記述を `*_archive_vX_X.md` に分離し、本体には参照1行のみ残す。アーカイブ本体はナレッジに登録しない | KY41「追記のみ・旧情報保持」は情報欠落を防ぐが**容量が単調増加する**構造的欠陥を持つ。上位10ファイルで全体の36%を占める現状がその実証 |
| **K-3** | **Google Drive上のソースコードは復元経路として機能しない**ことを原則として登録 | §3 の実証結果。`read_file_content` はMarkdownエスケープにより識別子・インデント・比較演算子を破壊する |
| **K-4** | 定期的なナレッジ棚卸しを工程に組み込む（例：各大工程の完了時） | 今回は97%到達まで放置された。逼迫してからの棚卸しは判断を急がせ、誤廃棄リスクを生む |

---

## 11. 承認欄

| 項目 | 状態 |
|---|---|
| レビュー実施 | 未 |
| 承認 | 未 |
| 承認日 | — |

**承認前の実施は禁止（原則43）。**

---

*以上*
