YUI OS ビルド手順書 v1.15 / 2026-08-28

**YUI OS ビルド手順書**

~~yuios_build_procedure_v1_12.docx~~ → ~~yuios_build_procedure_v1_13.md~~ → ~~yuios_build_procedure_v1_14.md~~ → **yuios_build_procedure_v1_15.md**（★v1.13で拡張子を実体に合わせ `.md` へ是正。v1.12までは `.docx` でありながら実体はUTF-8プレーンテキストだった＝KY41 4点整合）

~~Version 1.6 / 2026-06-21~~ ~~Version 1.7 / 2026-06-21~~ ~~Version 1.8 / 2026-06-22~~ ~~Version 1.9 / 2026-07-04~~ ~~Version 1.11 / 2026-07-27~~ ~~Version 1.10 / 2026-07-26~~ → Version 1.11 / 2026-07-27

| **項目** | **内容** |
| --- | --- |
| 文書種別 | YUI OS ビルド手順書 |
| バージョン | ~~v1.4~~ → ~~v1.6~~ → ~~v1.7~~ → ~~v1.8~~ → ~~v1.9~~ → ~~v1.10~~ → ~~v1.11~~ → ~~v1.12~~ → ~~v1.14~~ → **v1.15**（★v1.15 で §4.14「RTL シミュレーション環境の構築」を新設＝工程②-A で判明した環境起因の躓き6件を恒久化★）（KY41是正: 旧項目表は v1.4 のまま放置されていたため v1.6 に更新。v1.7 で Step 8-B Makefile 化を反映。v1.9 で §4.13 ツール実体検証・環境同期を新設。v1.10 で scc23 v2.04 char ロード幅是正対応・絶対ゲート更新 819/48785/P:20。v1.11 で startup_harness23 v1.6→v1.7 `_irq1_handler` レジスタ退避追加対応） |
| 作成日 | 2026-04-29 |
| 最終改版日 | ~~2026-06-02~~ → ~~2026-06-21~~ → ~~2026-07-04~~ → ~~2026-07-26~~ → ~~2026-07-27~~ → ~~2026-08-09~~ → ~~2026-08-14~~ → **2026-08-28** |
| 対象 ISA | ISA2.3 (YSD8800) |
| ビルドシステム | **【v1.7】Makefile v1.0 + mk_post1.sh v1.0（Step 8-B）** — yuios（道2）/ dhrystone / disk / run / regress / verify / clean を単一 Makefile に集約 |
| 対象ツール | ★**scc23 v2.07** / **hasm23 v1.04** / **lnk23 v2.01** / **emu23 v2.15** / **Force v1.5** / disasm23 v1.00 / mkfs_yuifs.py v1.1★ ／★**【v1.15】RTL 検証系に **Icarus Verilog 12.0 (stable)**（`-g2012` 必須・§4.14）を追加**★ ~~(旧: scc23 v2.05 / emu23 v1.13)~~ ~~(旧: scc23 v1.04 / hasm23 v1.02 / lnk23 v2.00 / emu23 v1.05 / emu23 v1.06 / emu23 v1.07 / emu23 v1.08)~~ ／**【v1.9】ツール実体は§4.13の機能マーカーで検証すること（バージョン文字列のみに依存しない）**／**【v1.10】scc23 版数を v1.04 → v2.04 に一気に追従（本手順書では途中版 v2.00〜v2.03 の追記が漏れていた）。scc23 v2.04 は char ロード幅是正版（設計書 scc23_v2_04_char_load_fix_design_v1_0.md）。emu23 も v1.09/v1.10/v1.11 の追記漏れを本改版で追従（v1.11 = TCR fire-EN OR→AND / plan-B EN fix）**／**【v1.11】Cプログラムビルド用スタートアップ startup_harness23 を ~~v1.5~~→**v1.7** に追従（v1.6=V5 TCR-ACK方式対応・`_timer_handler` A/B/X 退避、v1.7=`_irq1_handler` A/B/X 退避追加・`_timer_handler`と対称化）**／**【v1.14】emu23 を v1.12→**v1.13** に追従（EMU-A 引数解析＝argv 消費マーク方式・`--dbg`/`--sym` 新設／EMU-B `MAX_SYM` 128→2048。詳細は §4.7.3）** |
| 対象 OS | YUI OS Ph.2〜Ph.6 (**kernel_v12_11** + kernel_forth_v0_10_18。Ph.6 常駐 Shell 含む) |
| 作成者 | Claude (Anthropic) |

# **改版履歴**

| **版数** | **日付** | **内容** | **作成者** |
| --- | --- | --- | --- |
| v1.0 | 2026-04-29 | 初版作成: Chat #18 で確立したビルド手順を集約 | Claude |
| v1.1 | 2026-05-18 | §4.5 をシンボルアドレスハードコード禁止原則として強化 (kaizen 原則31 対応)。§6.6 に全件抽出コマンド追記。§10 将来課題 No.3 を更新。 | Claude |
| v1.2 | 2026-05-23 | Force v1.4 / hasm23 v1.02 / emu23 v1.04 にバージョン更新。§4.4.5 新設 (hasm23 W001 警告ゼロ確認)、§4.7 emu23 実行に --disk 必須化、§6.7 新設 (VARIABLE 追加・変更時の必須確認手順)、§6.8 新設 (ディスクマウント未指定でのSTOR-TEST失敗)。Ph.4 ファイルマネージャ実装で発生した VARIABLE レイアウト破壊問題の再発防止策を盛り込む。 | Claude |
| v1.3 | 2026-05-29 | **Step 5-2 FILE-LIST-IMPL 実装に伴うビルド手順変更を反映：**①対象ツール表に **Force v1.5**（_FMUL を $47B0-$47B5 に移動した版）と **mkfs_yuifs.py v1.1**（--add-file オプション追加版）を追加。②対象 OS を **kernel_forth_v0_10_3** に更新。③§4.8 として新節「kernel_forth_v0_10_3.fs のビルド」を新設し、build_v0_10_3.sh の使用方法を記載。従来の build.sh (v0.10.2{tag} 形式) との切り分けを明確化。④§4.7 emu23 実行手順に mkfs_yuifs.py v1.1 の --add-file オプション使用例（hello.txt 作成）を追記。⑤§6.9 として新節「FILE-LIST-IMPL のビルド前確認」を新設し、RSHIFT 利用可能性確認・FM-WK-COUNT/REMAIN/PTR 追加位置・試験 buf アドレス（TEST-DST-BUF+$100=$EF00）の確認手順を記載。Step 5-2 動作実証（2026-05-29、`0A BC123MPDQL` 出力）の根拠手順として位置付け。 | Claude |
| v1.4 | 2026-06-02 | **Step 5-6c FILE-WRITE-IMPL ロールバック実装に伴うビルド手順変更を反映：**①対象 OS を **kernel_v12_7 + kernel_forth_v0_10_9**（FILE-WRITE-IMPL 5-6c ロールバック含む）に更新。②§4.9 として新節「kernel_forth_v0_10_9.fs のビルド（Step 5-6c）」を新設し、build_v0_10_9_k127.sh の使用方法・期待出力 `0A BC123MPDQLORCWVX`（5-6c 非回帰）を記載。③【★今回判明した重要な手順注意】§4.7 emu23 実行手順に「**引数順序の注意**」を追記：emu23 は argv[1] を必ずプログラム名として解釈するため、`-q` 等のオプションは**プログラム名の後ろに置く**こと（`./emu23 -q prog.bin` のように -q を先頭に置くとプログラム名と誤解釈され即 exit する）。正：`./emu23 yuios.bin -q --disk disk.img`。④§6.10 として新節「テスト時のディスクイメージ汚染による誤デグレード」を新設：FileMgr テストは WRITE 系で同名ファイルを作るため、2 回目以降は同一 disk.img を使い回すと E-EXIST 等で WRITE 失敗し `wVx`/`l` 等の小文字デグレードに見える。**テストごとに mkfs_yuifs で disk.img を作り直す**こと（§8.4.6.5 デバッグ手順 #2 と整合）。⑤§8.6 として新節「emu23 が即 exit／-q で出力ゼロ」を新設（引数順序の誤りの切り分け）。Step 5-6c 動作実証（2026-06-02、kernel_forth v0.10.9 で `0A BC123MPDQLORCWVX` 出力・v0.10.8 と完全一致＝非回帰確認）の根拠手順として位置付け。なお 5-6c はツールチェーン無改修（kernel_forth のみ変更）のため Dhrystone 回帰チェックは対象外。 | Claude |
| v1.5 | 2026-06-06 | **emu23 v1.05（スタック watermark 計測機能統合）へのバージョン更新を反映：**①対象ツール表・§2.1・§2.2・§3.5・§3.6・§8 のツール一覧の emu23 を v1.04→**v1.05**（ソース emu23_v105.c）に更新。②§4.10 として新節「スタック watermark によるタスクスタック使用量計測（任意）」を新設し、`-w`/`--wm-steps`/`--wm-warmup` の使用法・常駐OSでの打切り・起動初期誤検出のウォームアップ対処を記載。③emu23 v1.05 は `-w` 無指定時 v1.04 と完全同一動作（非回帰確認済み）かつ Dhrystone 回帰 PASS のため、既存のビルド・実行手順（§3.5・§4.7 等）は変更不要。watermark は任意の追加計測手順として位置付ける。 関連：emu23_v105_design_v1_0.md / emu23_debug_manual_v1_1.docx。 | Claude |
| **v1.6** | **2026-06-21** | **【Step 8-F-2 道2：sed系統②廃止・YOF 固定アドレス配置ビルドを反映】**①対象ツール表を hasm23 **v1.04**（YOFモードの `.org` 配置アドレス尊重・has_org/.vector 遅延書き込み）・lnk23 **v2.01**（load_addr+has_org 尊重の固定配置）・emu23 **v1.06**（bd コマンド修正）・対象 OS を kernel_forth **v0_10_18**（Ph.6 常駐 Shell）に更新。②**§4.11 として新節「道2ビルド（YOF 固定アドレス配置・sed系統②廃止）」を新設**。従来の sed系統②（§7.1・kernel.asm の `$e96e`→WORD_OS_START 直書き＝§10 No.6）を廃止し、kernel_v12_7.asm の `#$e96e`2箇所を `#$WORD_OS_START`（UNDEF 参照）に置換、forth 側は WORD_OS_START 定義直前に `.global` を挿入、hasm23 -c で forth.obj(load_addr=$5100)/kernel.obj(load_addr=$0000) を生成、**lnk23 を `--machine force` モードで**固定配置リンクする手順を記載（**L-8: `--machine force` は必須**。落とすと forth@$5100 が baremetal ROM境界 $3FFF チェックに掛かりエラー）。③**§4.11 の後処理1（No.1 混入行 #WORD_xxx 修正）は固定リストではなく `#WORD_xxx` 全自動抽出方式**に改善（kernel_forth v0.10.18 実態は6個。固定リスト流用だと取りこぼす）。④結合テスト I3 で道2版 yuios.bin が従来 .bin リンク版と**全56416バイト完全一致**を確認（非回帰）。⑤§10 将来課題：No.2/3/6 を「道2（v1.04/v2.01）で解決済み」に更新、No.1/4/5 を独立 Step 8-B（ビルドシステム改善）として工程化済みと注記。 関連：hasm23_xref_yof_design_v2_3.md（実装・検証済み）/ lnk23_design・toolchain23_design（改版予定）。v1.5 までの記述は削除せず保持（旧 sed系統② 手順は §7.1 に取り消し線で残置）。 | Claude |
| **v1.8** | **2026-06-22** | **【Step 8-I：emu23 v1.07 へのバージョン追従】**①対象ツール表の emu23 を v1.06→**v1.07**（IRET時のタイマー再設定をタイマーIRQ復帰時のみに限定＝§5.3準拠の修正）に更新。②emu23 v1.07 は通常動作（yuiosビルド・Dhrystone・ストレージ）で v1.06 と完全同一動作（同一バイナリ出力一致で確認済み）であり、**ビルド・実行手順は一切変更不要**。修正はタイマーとIRQ1が高頻度衝突する場合のタイマーIRQ欠落のみに影響する。③絶対ゲート yuios 56416・Dhrystone 826/48405/P:20 を emu23 v1.07 で再確認・PASS。 関連：emu23_device_design_v1_3.docx §3.4 / step8i_irqfix_design_v0_2.md。v1.7 までの記述は削除せず保持。 | Claude |
| **v1.7** | **2026-06-21** | **【Step 8-B ビルドシステム改善：Makefile 化を反映】**①メタ情報に「ビルドシステム」行を新設し **Makefile v1.0 + mk_post1.sh v1.0** を登録。②**§4.12 として新節「Makefile によるビルド（Step 8-B・No.4/No.5 解決）」を新設**。`make yuios`（道2 S1〜S7・build_road2.sh とバイト等価）・`make dhrystone`（D1〜D7・lds は Makefile が自動生成＝No.4 解決）・`make disk`（disk.img 既定名生成＝No.5 解決）・`make run/regress/verify/clean` を記載。M-A 必須プリアンブル（`SHELL`/`.SHELLFLAGS := -ec`/`.ONESHELL:`）と `bash ./mk_post1.sh`（実行権限非依存）を明記。③**§10 将来課題：No.1/No.4/No.5 を「Makefile で解決済（Step 8-B）」に更新**。No.1 は後処理1を mk_post1.sh（build_road2.sh Step2 のバイト等価移植）として規則化、No.4 は手書き lds を Makefile 規則の自動生成に置換、No.5 は `make disk` の既定名 disk.img 化。④**E-1**：No.2（Dhrystone harness の `JSR _main` sed）は Makefile でも当面残置（lnk23 クロスセクション参照の Dhrystone 適用は Step 8-F残/8-I 関連の将来課題）と §10 に明記。⑤検証：MK-1〜MK-6 全 PASS（yuios=56416 完全一致・Dhrystone 826/48405/P:20 一致・本番ソース非改変 diff ゼロ）。前段ゲート D-2（`make -n` 展開後文字列が build_road2.sh/Dhrystone 手順と一致）・D-3（`.ONESHELL` で MAIN 行またぎ保持）通過。 関連：yuios_makefile_design_v0_2.md（APPROVED）/ Makefile v1.0 / mk_post1.sh v1.0。v1.6 までの記述は削除せず保持（§4.11 道2手動ビルドは Makefile の等価基準として残置）。 | Claude |
| **v1.9** | **2026-07-04** | **【ツール実体検証・環境同期の追加：ローカル hasm23 バージョン詐称バイナリ事故の再発防止】**①冒頭メタ情報の版数表記を KY41 4点整合で是正（旧 v1.8 改版時にファイル名表記が v1_7.docx のまま放置されていた是正漏れも修正）。対象ツール emu23 を ~~v1.07~~→**v1.08**（V(-1) MMU 復元版）に追従。②**§4.13 として新節「ツール実体検証と環境同期」を新設**。ローカルの hasm23 がバージョン文字列「v1.04」を表示しつつ実体は道2改修（has_vector 判定）を含まない旧版だったため、make yuios 生成バイナリのリセットベクタ（$0000-$0008）が全ゼロになり CPU が起動アドレスを取得できず起動不能になった事故（2026-07-04）の再発防止。**ルールC**：Makefile に `verify-tools` ターゲットを設け、`strings ./hasm23 | grep -q has_vector` 等の機能マーカーとバージョン文字列の両方をビルド入口で検証する（`yuios`/`dhrystone` ターゲットの依存に前置）。**ルールD**：ローカル／チャット環境併用時、ビルド前に使用ファイル一式（.c/.fs/.asm/.tgt/.prim＋ツール元ソース）を md5sum で、ツールバイナリ実体を機能マーカーで照合する。前回の dhry_timer.c が古かった件（2026-06-22）と同一の「ファイル一式の同期管理の甘さ」に対する恒久対策。 関連：kaizen.txt 原則56/57/58 / claude_tool_operation_guide。v1.8 までの記述は削除せず保持。 | Claude |
| **v1.10** | **2026-07-26** | **【scc23 v2.04 対応・char ロード幅是正・絶対ゲート更新・emu23 追従】**①**冒頭メタ情報の対象ツール scc23 を ~~v1.04~~→**v2.04** に一気に追従**。本手順書では途中版 v2.00〜v2.03 の追記が漏れており、v1.10 で最新版まで一括追従する（KY41前版情報保持：v1.04 は取消線で残存）。scc23 v2.04 は char 型ローカル/パラメータ変数の読出が LDW=2バイトから **LDB=1バイト** に是正された版（設計書 scc23_v2_04_char_load_fix_design_v1_0.md）。②**絶対ゲートを ~~826/48405/P:20~~→**819/48785/P:20** に更新**（cycles +380=+0.79%増は char 読出が各+2命令になった論理的結果・機能的正当性 P:20 は完全維持）。§4.12 Makefile 表の regress 期待値・§XX 回帰説明・`regress` の判定説明・実行コマンド説明の絶対ゲート数値をすべて更新。Makefile 本体も v1.0→**v1.1**（本手順書と同時改版）。③**V3 RTL 4初期化パターン検証**：`tb_cpu_v8d_char_fix_v0_1.sv`（新規TB・パラメータ化1本4回走行）で PSRAM 初期値 $00/$FF/$AA/$55 の4パターン全 PASS を確認。cycles 完全一致（1,317,412）で **PSRAM 初期値非依存を実証**（CHAT119 の真因＝TB PSRAM 未初期化領域の 'x 混入が上位バイトを読む scc23 v2.03 の LDW で顕在化していた問題が、scc23 v2.04 の LDB 化で根絶されたことを確定）。V3 期待UART列は `"N=10\nP:20"` 9B（emu23 v1.11 でフル dhry_timer.c を実行し stdout 分離採取）。④**emu23 の追記漏れ追従**：~~v1.08~~→**v1.11** に更新（v1.09=interactive mode、v1.10=timer re-arm via TCR bit5 IRQ_ACK、v1.11=TCR fire-EN OR→AND / plan-B EN fix）。⑤startup_harness23 の版数追従（v1.6→v1.7 で `_irq1_handler` A/B/X 退避欠落バグ修正）は工程2 として別チャットで実施予定のため、本改版では触れない（原則77：判定基準を動かす変更は工程を分ける）。 関連：scc23_v2_04_char_load_fix_design_v1_0.md / HANDOVER_CHAT120.md / tb_cpu_v8d_char_fix_v0_1.sv / Makefile v1.1 / kaizen.txt 原則76/77/87。v1.9 までの記述は削除せず保持。 | Claude |
| **v1.11** | **2026-07-27** | **【startup_harness23 v1.7 対応・`_irq1_handler` レジスタ退避追加】**①**冒頭メタ情報の対象ツール startup_harness23 を ~~v1.5~~→**v1.7** に一気に追従**（本手順書は Makefile HARNESS 変数を通じてスタートアップ .asm を参照する構造のため、v1.6/v1.7 の追記漏れがあった）。v1.6=V5 TCR-ACK方式対応・`_timer_handler` A/B/X 退避追加、v1.7=`_irq1_handler` A/B/X 退避追加・`_timer_handler`と対称化。②**バグ修正内容**（設計書 startup_harness23_v17_irq1_regsave_fix_design_v1_1.md 承認済）：v1.6 の `_irq1_handler` は `LDW A,#$FCB2` / `LDW B,[A]` で A/B を無退避のまま破壊しており、YSD8003 ストレージ完了 IRQ 受理時に呼出元コードの A/B レジスタを破壊する潜在バグがあった。v1.7 で `_timer_handler` と同一パターン（A/B/X 全退避、案A採用）に対称化。命令サイズ +24B（STW×3 + LDW×3 = 6命令 × 4B）は設計書 §4.4 の予測と実測完全一致。③**Makefile HARNESS 変数を v15→v17 に更新**（Makefile 本体は v1.1 のまま維持。HARNESS 変数の追従は絶対ゲート数値と独立のため、Makefile 版数繰上げなし）。④**V1（emu23 単体テスト）**：make regress で 819/48785/P:20 完全一致 → 黄金値不変を確認（IRQ1 非発火経路のため想定通り）。⑤**V3（RTL 回帰）**：`tb_cpu_v8d_char_fix_v0_1.sv` で PSRAM_INIT_VAL=$00 走行、HALT到達 at cyc=1,317,401、UART `"N=10\nP:20"` 9B 一致で 4/4 PASS。cycles -11 の差は harness の +58B（v15→v17）増によるコード配置の些細な差異と解釈（機能に影響なし）。⑥**V4（V8-a cat/ls 回帰）**：本チャット実験環境の制約により**スキップ**（SD ディスク経由の実挙動テストで、実行環境が別途必要）。修正効果の直接確認は次回 V8-a テスト実施時に確認する（申し送り）。 関連：startup_harness23_v17_irq1_regsave_fix_design_v1_1.md / startup_harness23_v16_irq1_regsave_bug_report_v1_0.md / kaizen.txt「見えているバグは先に潰す」原則。v1.10 までの記述は削除せず保持。 | Claude |
| **v1.12** | **2026-08-09** | **【TKT-04/TKT-00 検証で判明した未文書化制約の反映】**①**§4.7.1 を新設**——シェル操作によるベースライン確認手順（`ver`/`ls`）。**★UART 入力の行終端は CR（`\r`）でなければならない★**（LF ではシェルがコマンドを確定せずエコーのみ返す）。②同節に **`-q` オプションが実質必須**である旨を明記（`-q` なしでは IRQ トレースが 30 秒で約 1.9 MB 出力され UART 出力が埋もれる）。③同節に **emu23 デバッガの制約 EMU-A/B/C** を記載——A: `argv[2]/argv[3]` を無条件に `.dbg`/`.sym` と解釈するためオプション併用時に `Loaded 0 label symbols` になる／B: `MAX_SYM=128` によりシンボル数の多いビルドではラベル指定 BP が使えない（→16進アドレス指定）／C: BP 停止位置から `c` で再開できない（→1ラン1BP）。いずれも emu23 改修フェーズ B に登録済。④**§6.4 hasm23 構文制限に 2 件追加**——**ラベル行への同一行コメントは不可**（`Unknown instruction '_LABEL:'`。ラベルは単独行にする）、**`.equ` ディレクティブは不在**（定数定義は大文字 `EQU` のみ）。⑤**冒頭メタ情報を KY41 4点整合で是正**——L1 の版数表記が **v1.4 のまま放置**されており（v1.11 改版時にも見落とし）、文書名も `v1_10.docx` のままであった。対象ツール scc23 を v2.04→**v2.05**、対象 OS を kernel_v12_7→**kernel_v12_11** に更新。 | Claude |
| **v1.14** | **2026-08-14** | **【emu23 v1.12→v1.13（Phase B'' B-2/B-3：EMU-A 引数解析 + EMU-B シンボル容量）への追従】**①対象ツール表の emu23 を v1.12→**v1.13** に更新。②**§4.7.3 として新節「emu23 v1.13 の引数解析と `--dbg`/`--sym`」を新設**。③**★L248 の「argv[2]/argv[3] は .dbg/.sym として load される位置引数だが、該当ファイルが無くても load 失敗は無害でそのまま継続する」という記述は v1.13 で実態が変わった★**：オプションとその引数は**消費済み**となり位置解釈の対象外になったため、`./emu23 prog.bin -q --disk d.img` のような形でも `.dbg`/`.sym` が**自動導出で正しく読まれる**（従来は `-q` が `.dbg`、`--disk` が `.sym` と誤認され読めていなかった）。**なお「オプションをプログラム名より前に置いてはならない」（argv[1] は必ず `.bin`）という制約は v1.13 でも不変**。④**★L274 の EMU-A/EMU-B 警告ボックスを「解消済み」に更新★**：`.sym` 自動導出のオプション併用時破綻（EMU-A）と `MAX_SYM=128`（EMU-B）はいずれも v1.13 で解消したため、**「BP は `.sym` から引いた 16 進アドレスで指定すること」という回避策は不要**になった（ラベル名で BP を張れる）。⑤**群β形式の起動例を是正**（L245／L256／L374）：`./emu23 yuios.bin yuios.sym ...` は `.sym` が `load_dbg()` に渡る誤形式だったため `--sym` 形式へ書き換え。⑥**新規警告タグ**：`[SYM-TRUNCATED]`（`MAX_SYM=2048` 超過時・`-q` でも出力）／`[SYM-NOTFOUND]`・`[DBG-NOTFOUND]`（**明示指定**の読込失敗時のみ。自動導出の失敗は従来どおり黙殺）。いずれも **stderr** 出力のため §4.7.2 ⑤の「`-q` の byte-exact 比較は stdout のみを対象とする」原則がそのまま適用される。⑦**ビルド手順・回帰手順そのものに変更はない**（絶対ゲート Dhrystone 819/48785/P:20・`yuios_road2.bin` 56416B/md5 `599a7f9d…` は v1.13 でも全 PASS・`-q` stdout は v1.12 と byte-exact 一致）。関連：`emu23_argsym_design_v1_0.md` / `tool_version_ledger_v1_15.md`。v1.13 までの記述は削除せず保持。 | Claude |
| **v1.15** | **2026-08-28** | **【工程②-A で判明した RTL シミュレーション環境の躓き6件を恒久化】**①**§4.14 として新節「RTL シミュレーション環境の構築（FPGA 検証系）」を新設**。★コンテナはセッションをまたぐとリセットされるため、チャットが変わるたびにゼロから再構築が必要★という前提を明記し、段0〜段6 の定石コマンド列を収録。②**躓き R-1〜R-6 を表形式で恒久化**：R-1 `iverilog` 初期不在（`apt-get install -y iverilog`／12.0 stable）／R-2 Force の `frontend/`＋★`backend/`★分離と **codegen の改名必須**（`codegen_v1_4.h`→`backend/codegen.h`）／R-3 ★`ysd8800_kern_v0_6.tgt`→`ysd8800_kern.tgt` 改名★（Makefile は版数なし名を要求するがナレッジは版数付き保管）／R-4 ★`iverilog -P` は `-s <top>` なしでは**黙って無視**される★／R-5 ★Icarus 12.0 は `break` 文未サポート★／R-6 size cast は `-g2012` で通る（代替不要・実測確認）。③**§4.14.4 で R-4 を単独節として詳述**：★エラーも警告も出ず既定値で完走するため最も危険★。②-A では `sh` が `time (` を解釈できずコマンド列全体が実行されなかった結果、**前ターンでビルドした既定値のままの `.vvp` が走り** phase-1 のまま M-5 未到達→`PROD FAIL` を **RTL 不具合と誤認しかけた**実例を記載。★**なお当初これを「`iverilog -P` が `-s` なしでは無視される」と分析していたが、v1.15 起草時の実測により誤りと確定（`-s` の有無・`-P` と引数の間の空白の有無にかかわらず `-P` は正しく効く）。誤った知見を手順書に載せる寸前であった＝KY34 の実践例として自己訂正の経緯ごと §4.14.4 に明記**★。対処5ルール（`.vvp` を `rm -f`／ビルドと実行を分離／`ls` で生成確認／`MAX_CYCLES=` 目視／★ビルドコマンドにパイプを繋がない（SIGPIPE で中断され成果物が生成されない・同じく実測で判明）★）と phase-1/2/3 の定義表を収録。④**§4.14.6 でサイクル計数規約の注意を新設**：`negedge` 基準と `posedge` 基準で 1 ずれる（②-A で 11 と 13）。★TB 間で絶対値を比較せず**増分**を見る★。⑤**§4.14.7 に RTL 16 本のファイルリストと既知の無害警告3種**を収録（decoder/regfile/alu 先頭必須）。⑥**§4.14.8 に RTL 側絶対ゲート**（G-0/G-5/M-1〜M-5）を明記。★AC-1 は RTL 指標ではなくビルド成果物の性質（TB 未実装・Python で走査）★である旨を注記。⑦**§4.14.9 に★原則135「改修層とゲートの対応」★を新設**：RTL のみの改修工程では ★G-1(Dhrystone)/G-2/AC-1 は対象外★。②-A で機械的に実行し「絶対ゲート全通過」と報告したが、通過した事実は正しいものの★証拠能力のない項目を成果として数えた★。ユーザ指摘（2026-08-28「ツールチェーンを変更しないのに Dhrystone 回帰検証は正直無駄」）に基づく。⑧**§4.14.10 にチェックリスト10項目**を収録。⑨**対象ツール表を現行版へ追従**：scc23 v2.05→**v2.07**／emu23 v1.13→**v2.15**／★Icarus Verilog 12.0 を RTL 検証系として追加★。⑩ヘッダのファイル名・バージョン・最終改版日・改版履歴を KY41 4点整合で更新。v1.14 までの記述は削除せず保持。 | Claude |
| **v1.13** | **2026-08-12** | **【emu23 v1.11→v1.12（Phase B' 完了：B-1 TKT-03 + B-C 改良2）への追従】**①**ファイル名の拡張子を `.docx`→`.md` に是正**（v1.12 までは `.docx` でありながら実体は UTF-8 プレーンテキストだった＝KY41 4点整合違反。過去版は版数がファイル名に含まれるため参照解決に支障なし）。②対象ツール表の emu23 を v1.11→**v1.12** に更新。③**§4.7.2 として新節「emu23 v1.12 の MMIO 関連オプション」を新設。****★既定動作が変更された★**：未接続 MMIO 領域（`$FC80`-`$FFFF` のうち実装済レジスタ以外）の読出が `mem[]` フォールスルー（RAM 化）から **`$FF`/`$FFFF`**（実機のバスはプルアップされるため）へ、書込は**破棄**へ変わった。MMIO 空間を RAM として使わない規約（`yuios_memmap_design` L225）を守るコードは影響を受けない（YUI OS・Dhrystone とも警告0件を実測確認済）。④追加オプション **`--no-bus-pullup`**（v1.11 挙動へ切り戻し・障害切り分け用）／**`--strict-mmio`**（未接続アクセス検出時点で停止・プルアップの有無と独立）／`--bus-pullup`（既定有効のため no-op・互換受理）を記載。⑤**★注意事項として stderr の扱いを明記★**：MMIO 警告 `[MMIO-UNMAPPED]` とサマリ `[MMIO-SUMMARY]` は **stderr** に出力されるため、`-q` の byte-exact 比較は **stdout のみ**を対象とすること（`2>&1` で混ぜると差分が出る）。⑥**サマリは `atexit` 出力のため `HALT` 到達時のみ**取得可能。YUI OS は待機ループで HALT しないためサマリを取得できず、検証は Dhrystone 等で行う旨を明記。⑦**8bit アクセス経路の被覆漏れ解消**（YSD8002 全8本・YSD8003 7本・YSD8004 2本＝計17本が v1.11 まで `mem[]` に落ちていた）を記載。`UART_BAUD`（`$FC86`）のみ 16bit 専用（`ysd8001_uart_design` L166）で 8bit アクセス時は `$00`＋`[MMIO-UNSUP]` 警告＝仕様どおりである旨も併記。⑧**ビルド手順・回帰手順そのものに変更はない**（絶対ゲート Dhrystone 819/48785/P:20・`yuios_road2.bin` 56416B/md5 `599a7f9d…` は v1.12 でも全 PASS・既定動作は v1.11 と stdout byte-exact 一致）。関連：`emu23_device_design_v1_11.md` / `emu23_interactive_mode_design_v1_6.md` / `tool_version_ledger_v1_14.md`。v1.12 までの記述は削除せず保持。 | Claude |

# **1. 概要**

## **1.1 目的**

本書は YUI OS および関連 C プログラム (Dhrystone 等) を YSD8800 ツールチェーンを使用してビルドするための手順を記述する。

従来、ビルド手順は複数の引継ぎ文書 (HANDOVER_CHAT15/17/18/28 等) に散在し、暗黙知に依存していた。本書はそれらを一元化し、再現性のある手順を提供することを目的とする。

## **1.2 対象範囲**

本書が対象とするビルドは以下のとおり:

  - YUI OS Ph.2 〜 Ph.4 (Forth カーネル + ASM カーネル + FileMgr)

  - C プログラム (Dhrystone タイマー版を例として使用)

  - ツールチェーン自体のビルド (scc23 / hasm23 / lnk23 / emu23 / Force)

## **1.3 前提環境**

| **項目** | **要件** |
| --- | --- |
| OS | Linux (Ubuntu 20.04 以降推奨) |
| コンパイラ | gcc 9.0 以上 (-std=c99 対応) |
| シェル | bash 4.0 以上 |
| ツール | sed, awk, grep, od, dd, python3 |

# **2. ツールチェーン要件**

## **2.1 必須ツール一覧 (バージョン込み)**

【v1.2 更新】Force v1.4 / hasm23 v1.02 / emu23 v1.04 へバージョン更新。

| **ツール名** | **バージョン** | **役割** | **ソースファイル** |
| --- | --- | --- | --- |
| scc23 | v1.00 | C コンパイラ (ISA2.3対応) | scc23_v1_00.c |
| hasm23 | v1.02 | アセンブラ (W001/E001 検出機能あり) | hasm23.c |
| lnk23 | v2.00 | リンカ (lds スクリプト対応) | lnk23.c |
| emu23 | v1.05 | エミュレータ (UART/Timer/SD/IRQ統合 + stack watermark計測) | emu23_v105.c |
| Force | v1.4 | Forth クロスコンパイラ (VARIABLE分離出力) | force.c 他 |
| disasm23 | v1.00 | 逆アセンブラ (デバッグ用) | disasm23.c |

| **ℹ Force v1.4 / hasm23 v1.02 の新機能** Force v1.4: VARIABLE/VALUE/DEFER のデータ部と getter コード部を分離出力する。これにより hasm23 の .org 後退による getter コード上書きバグが回避される。 hasm23 v1.02: W001 警告 (.org 重ね書き検出) と E001 エラー (ラベル二重定義) を追加。 起動時バナーを常時表示するように変更。詳細は §6.7 / §6.8 / §8.4 参照。 |
| --- |

## **2.2 ビルド環境**

以下のファイルがビルドディレクトリに揃っていること:

| **ファイル** | **用途** |
| --- | --- |
| scc23_v1_00.c | C コンパイラソース |
| hasm23.c | アセンブラソース (v1.02) |
| lnk23.c | リンカソース |
| emu23_v105.c | エミュレータソース (v1.05) |
| force.c | Force メインソース (v1.4) |
| ir.c / ir.h | Force IR モジュール |
| lexer.c / lexer.h | Force レキサモジュール |
| parser.c / parser.h | Force パーサモジュール |
| codegen.c / codegen.h | Force コードジェネレータ (v1.4) |
| ysd8800.prim | Force プリミティブ定義 |
| ysd8800.tgt | Force ターゲット定義 (ユーザプログラム用) |
| ysd8800_kern.tgt | Force ターゲット定義 (OS カーネル用) |

## **2.3 ファイル配置構成**

Force コンパイラは frontend/ / backend/ / targets/ サブディレクトリ構成を要求する。プロジェクトナレッジからビルドする場合は以下の構造を作成する:

| build/ ├── force/ │   ├── force.c │   ├── frontend/ │   │   ├── ir.c / ir.h │   │   ├── lexer.c / lexer.h │   │   └── parser.c / parser.h │   ├── backend/ │   │   └── codegen.c / codegen.h │   └── targets/ │       ├── ysd8800.prim │       ├── ysd8800.tgt │       └── ysd8800_kern.tgt ├── scc23 ├── hasm23 ├── lnk23 └── emu23 |
| --- |

# **3. ツールビルド手順**

## **3.1 Force コンパイラビルド**

プロジェクトナレッジからソースを収集し、ビルドツリーを構築する:

| # ビルドツリー作成 mkdir -p build/force/frontend build/force/backend build/force/targets cd build/force # ソースコピー (プロジェクトナレッジからのパス例) cp /mnt/project/ir.{c,h} /mnt/project/lexer.{c,h} /mnt/project/parser.{c,h} frontend/ cp /mnt/project/codegen.{c,h} backend/ cp /mnt/project/force.c . cp /mnt/project/ysd8800.prim /mnt/project/ysd8800.tgt /mnt/project/ysd8800_kern.tgt targets/ # コンパイル (注: -D_GNU_SOURCE が strcasecmp に必要) gcc -std=c99 -D_GNU_SOURCE -O2 -Wall -Wno-unused-function -Wno-format-truncation \     frontend/ir.c frontend/lexer.c frontend/parser.c \     backend/codegen.c force.c -o force # バージョン確認 ./force -v   # → Force v1.4 |
| --- |

## **3.2 scc23 ビルド**

| gcc -std=c99 -O2 -Wall scc23_v1_00.c -o scc23 ./scc23 -v   # → scc23 v1.00 (2026-04-16) for YSD8800 ISA2.3 |
| --- |

## **3.3 hasm23 ビルド**

| gcc -std=c99 -D_GNU_SOURCE -O2 -Wall hasm23.c -o hasm23 ./hasm23 2>&1 │ head -1   # → hasm23 v1.02 (2026-05-23) for YSD8800 ISA2.3 |
| --- |

| **ℹ hasm23 v1.02 の起動時バナー** v1.02 から hasm23 はファイル指定時にも常に起動バナーをstderrに出力する。 ログを保存する際にバージョン特定が容易になる。 |
| --- |

## **3.4 lnk23 ビルド**

| gcc -std=c99 -D_GNU_SOURCE -O2 -Wall lnk23.c -o lnk23 ./lnk23 -v  # → lnk23 v2.00 |
| --- |

## **3.5 emu23 ビルド**

| gcc -std=c99 -D_GNU_SOURCE -O2 -Wall -Wno-unused-function emu23_v105.c -o emu23 -lm ./emu23 2>&1 │ head -1   # → emu23 v1.05 (2026-06-06) for YSD8800 ISA2.3 |
| --- |

## **3.6 ビルド成功確認**

全ツールのバージョン表示を確認する:

| for tool in ./force/force ./scc23 ./hasm23 ./lnk23 ./emu23; do     echo -n "$tool: "; $tool 2>&1 │ head -1 done |
| --- |

期待される出力 (v1.2 以降):

| ./force/force: Force v1.4 ./scc23: scc23 v1.00 (2026-04-16) for YSD8800 ISA2.3 ./hasm23: hasm23 v1.02 (2026-05-23) for YSD8800 ISA2.3 ./lnk23: lnk23 - YSD8800 ISA2.3 Linker v2.00 ./emu23: emu23 v1.05 (2026-06-06) for YSD8800 ISA2.3 |
| --- |

# **4. YUI OS ビルド手順**

## **4.1 ビルド全体フロー**

YUI OS のビルドは以下の流れで行う:

| [kernel_forth_v0_9_0.fs]       │       │ Force v1.4 コンパイル (--target ysd8800_kern)       v [kernel_forth_v0_9_0.asm]  ← 混入行あり (#WORD_xxx 形式)       │       │ 1パス目アセンブル → .sym 取得       │ sed による混入行修正       │ 2パス目アセンブル       v [kernel_forth_v0_9_0.asm.bin] + [kernel_forth_v0_9_0.asm.sym]   ★ ここで hasm23 v1.02 の W001 警告ゼロを確認 (§4.4.5) [kernel_v12_5.asm]       │       │ WORD_OS_START アドレスを .sym から取得・sed 置換       │ hasm23 アセンブル       v [kernel_v12_5.asm.bin] + [kernel_v12_5.asm.sym]       │ lnk23 (yuios.lds スクリプト)       │   SECTION forth 先 → SECTION kernel 後 (後勝ちルール)       v [yuios.bin] + [yuios.sym]       │ ddで32KB ダミーディスクイメージ作成       v [disk.img]       │ emu23 --disk disk.img -q で実行       v 期待出力: A BCP |
| --- |

## **4.2 Step 1: Force による Forth カーネルコンパイル**

| ./force/force --target ysd8800_kern \               --tgt-file force/targets/ysd8800_kern.tgt \               --prim-file force/targets/ysd8800.prim \               kernel_forth_v0_9_0.fs \               -o kernel_forth_v0_9_0.asm |
| --- |

| **ℹ --tgt-file の指定** --tgt-file には必ず targets/ysd8800_kern.tgt を指定すること。 デフォルトの targets/ysd8800.tgt を使用すると配置設定が変わり、kernel_v12_5.asm との整合が取れなくなる。 |
| --- |

## **4.3 Step 2: 混入行修正 (必須)**

Force が出力する ASM には、hasm23 が正しく解釈できない行が含まれる:

| # 問題のある行 (例) LDW  A, #WORD_MEMMGR_TASK |
| --- |

hasm23 はこれを「# で始まるラベル参照」として扱い、エラーで停止する。1パス目で .sym を取得した後、sed で該当アドレスを直書きに変換する:

| # 1パス目: シンボル取得 ./hasm23 kernel_forth_v0_9_0.asm  # (混入行エラーで停止するが .sym は生成される) # 混入行を一括修正 (kernel_forth で参照される代表的なシンボル群) for sym in WORD_MEMMGR_TASK WORD_UART_DRV_TASK WORD_UART_TEST_TASK \            WORD_STOR_DRV_TASK WORD_STOR_TEST_TASK; do   addr=$(grep -E "^[0-9a-f]+ ${sym}$" kernel_forth_v0_9_0.asm.sym │ awk '{print $1}')   [ -n "$addr" ] && sed -i "s│LDW  A, #${sym}│LDW  A, #\$${addr}│g" kernel_forth_v0_9_0.asm done |
| --- |

| **ℹ 混入行の確認** 混入行のパターンは Forth ソースの変更で増える可能性がある。以下のコマンドで全混入箇所を事前に確認すること:   grep -E 'LDW\s+\w+,\s+#WORD_' kernel_forth_v0_9_0.asm |
| --- |

## **4.4 Step 3: hasm23 によるアセンブル**

| # 2パス目: 修正後の再アセンブル rm -f kernel_forth_v0_9_0.asm.bin kernel_forth_v0_9_0.asm.sym ./hasm23 kernel_forth_v0_9_0.asm |
| --- |

### **4.4.5 【v1.2 新設】hasm23 W001 警告ゼロ確認 — VARIABLE 系設計変更時の必須確認**

| **⚠ ★ 必須チェック: アセンブル後に hasm23 の出力を確認すること ★** Forth ソースに VARIABLE / VALUE / DEFER を追加・変更した場合、Force v1.4 で正しく データ部とコード部が分離されているかを必ず確認する。 アセンブル時に W001 警告がゼロ件であることを確認しなければならない。 W001 警告がゼロでない場合、以下のいずれかの問題が発生している可能性が高い:   1. Force のバージョンが v1.4 未満 (古い VARIABLE 生成方式)   2. Forth ソースまたは kernel.asm 側で意図しない .org 後退記述が混入   3. kernel.asm と Forth ASM で同一アドレス領域に書き込みが発生 いずれの場合も、警告を無視して実行すると getter コードが上書きされ、 実行時に予測不可能なクラッシュ (PC 不定 HALT 等) を引き起こす。 |
| --- |

確認手順:

| ./hasm23 kernel_forth_v0_9_0.asm 2>&1 │ tee hasm23_out.log # 出力例 (正常時): #   hasm23 v1.02 (2026-05-23) for YSD8800 ISA2.3 #   hasm23: assembled 'kernel_forth_v0_9_0.asm' -> kernel_forth_v0_9_0.asm.bin  (...) # 出力例 (異常時): #   hasm23: W001 line 197: .org overlap — byte at $C00C already written, ... #   ... #   hasm23: W001 summary: 11 byte(s) were overwritten by .org backward jump(s) # W001 件数を機械的に確認 warns=$(grep -c "^hasm23: W001" hasm23_out.log ││ true) if [ "$warns" -gt 0 ]; then   echo "ERROR: hasm23 W001 重ね書き警告が $warns 件あります。設計を見直してください"   exit 1 fi |
| --- |

| **ℹ W001 警告の背景 (HANDOVER_CHAT28/29 由来の再発防止策)** 2026-05-23、Ph.4 ファイルマネージャ実装中に「VARIABLE FM-WK-* を追加すると UART 出力なし PC 不定 HALT」というレイアウト破壊問題が発生した。原因は Force v1.2 の VARIABLE 生成方式 (データとコードを直書き連続) と hasm23 v1.01 の .org 重ね書き無警告仕様の組み合わせ。 Force v1.4 (データ部とコード部分離) と hasm23 v1.02 (W001 警告) で恒久対策済み。 本確認手順は同種問題を将来検出可能にするためのもの。VARIABLE 追加・変更を伴うコミット の前には必ず本確認を実施すること。 |
| --- |

kernel.asm 側も同様に W001 をチェック:

| ./hasm23 kernel_v12_5.asm 2>&1 │ grep "W001" ││ echo "kernel.asm: W001 ゼロ OK" |
| --- |

## **4.5 Step 4: シンボルアドレス整合確認**

| **⚠ 【原則】カーネル側コード (kernel_core.asm 等) への Forth シンボルアドレスのハードコードは禁止する。 (kaizen 原則31)** Forth ソースのリネーム・ワード追加・削除でアドレスが変化した場合、ハードコードされた 即値はエラーなく静かに腐る。必ずビルドごとに sym ファイルから動的に取得して検証すること。 |
| --- |

【禁止パターン】

| ; BAD: アドレスを数値で直書き LDW  A, #$CE7F      ← Forthソース変更で即座に腐る |
| --- |

【許容パターン】ビルドスクリプトで sym から動的取得して sed 置換 (§7.1 参照):

| # WORD_OS_START アドレスを取得して kernel.asm を更新 new_addr=$(grep -E "^[0-9a-f]+ WORD_OS_START$" kernel_forth_v0_9_0.asm.sym │ awk '{print $1}') cp kernel_v12_5.asm kernel_v12_5_built.asm sed -i "s│\$e96e│\$${new_addr}│g" kernel_v12_5_built.asm ./hasm23 kernel_v12_5_built.asm |
| --- |

## **4.6 Step 5: lnk23 によるリンク**

| cat > yuios.lds <<EOF OUTPUT yuios.bin SYMOUT yuios.sym SECTION forth   0x0000 kernel_forth_v0_9_0.asm.bin kernel_forth_v0_9_0.asm.sym SECTION kernel  0x0000 kernel_v12_5_built.asm.bin kernel_v12_5_built.asm.sym EOF ./lnk23 yuios.lds |
| --- |

| **ℹ 後勝ちルール (SECTION 順序)** lnk23 は後に記述された SECTION が先の SECTION を上書きする (後勝ち)。 kernel_forth は CODE-START=$5100 から始まり、0x0000〜$50FF が 0x00 padding される。 kernel を先に書くと Forth の padding がカーネルを上書きしてしまうため、 必ず「forth 先 → kernel 後」の順序とする。 |
| --- |

## **4.7 Step 6: 動作確認 — 【v1.2 重要更新】ディスクマウント必須**

| **⚠ ★ emu23 実行時は必ず --disk オプションを指定すること ★** YUI OS は STOR-DRV / STOR-TEST タスクを起動するため、ディスクイメージなしで実行すると STOR-TEST S4 (read/write 結果比較) で必ず失敗し、F4 を出力して停止する。 必ずダミーディスクイメージを用意して --disk で渡すこと。 |
| --- |

ダミーディスクイメージ作成 (32KB = 64 セクタ):

| dd if=/dev/zero of=disk.img bs=512 count=64 |
| --- |

実行:

| ./emu23 yuios.bin --sym yuios.sym --disk disk.img -q # 正常動作時の出力例: A BCP<br>★v1.14 是正★: 旧記載 `./emu23 yuios.bin yuios.sym --disk ...` は **argv[2] の `.sym` が `load_dbg()` に渡る**誤形式だった（emu23 v1.12 まではシンボルが一切読めず `Loaded 0 label symbols`）。emu23 v1.13 の `--sym` を使う形へ是正。 |
| --- |

| **⚠ ★ emu23 の引数順序に注意（v1.4 追記）★** emu23 は **argv[1] を必ずプログラム (.bin) 名として解釈**する (位置引数)。 そのため `-q` 等のオプションを**プログラム名より前に置いてはならない**。 誤: `./emu23 -q yuios.bin --disk disk.img` → `-q` が argv[1] となり、load_bin(\"-q\") が失敗して即 exit (出力ゼロ)。 正: `./emu23 yuios.bin -q --disk disk.img` (プログラムを第1引数、オプションは後置)。 なお argv[2]/argv[3] は .dbg/.sym として load される位置引数だが、 該当ファイルが無くても (例: argv[2]=\"-q\") load 失敗は無害でそのまま継続する。 **★v1.14 追記（emu23 v1.13 以降）★: オプションとその引数は消費済みとなるため、`-q` 等が `.dbg`/`.sym` と誤認されることは無くなった。上記の「load 失敗は無害」という説明は v1.12 までの挙動である。ただし argv[1] を必ず `.bin` とする制約（オプションを前に置かない）は不変。** -q を付けると診断メッセージ (IRQ accepted 等) が抑制され UART 出力のみ stdout に出る。 -q モードは HALT まで実行するが、YUI OS は待機ループ (BEGIN TASK-SLEEP AGAIN) で HALT しないため、テスト出力が出揃った後は timeout で止めてよい (UART 出力は timeout 前に取得済み)。 |
| --- |

| **ℹ 正常出力の意味** A: MEMMGR 起動完了 B: UART-DRV 起動完了 C: STOR-DRV 起動完了 P: STOR-TEST 全パス (S2 WRITE / S3 READ / S4 比較すべて成功) Ph.4 FILEMGR-TEST 実装後は出力末尾に X D Q が追加される (期待最終出力: A BCXD P Q)。 |
| --- |

ディスクマウントなしで実行した場合の動作 (参考):

| ./emu23 yuios.bin --sym yuios.sym -q # ★v1.14 是正（旧: `yuios.bin yuios.sym -q`）★ # 出力: A BCF4 # F4 = STOR-TEST S4 失敗 (ディスク未マウントによる比較不一致) # これは正常な失敗動作なので、ビルドが壊れているわけではない |
| --- |

### **4.7.1 【v1.12 新設】シェル操作によるベースライン確認（ver / ls）**

`YUIOS Booted!` の到達だけでなく、シェルコマンドの応答まで確認する場合の手順。

| **★UART 入力の行終端は CR（`\r`）でなければならない★** LF（`\n`）ではシェルがコマンドを確定せず、**エコーだけ返して応答しない**。`printf 'ver\rls\r' > uart_in.bin` のように CR で作成すること。 |
| --- |

実行と期待出力:

| printf 'ver\rls\r' > uart_in.bin<br>timeout 60 ./emu23 yuios_road2.bin -q -i uart_in.bin --disk disk.img<br># 期待出力:<br>#   YUIOS Booted!<br>#   YUI> ver → YUIOS V0.10.18<br>#   YUI> ls  → 0/0（空 FS の場合） |
| --- |

| **⚠ ★`-q` オプションは実質必須★** `-q` を付けないと IRQ トレース（`** IRQ 2 accepted, vec=0d00 **`）が大量に出力され、**30 秒で約 1.9 MB** に達する。UART 出力がトレースに埋もれて判読できない。 |
| --- |

| **✅ ★EMU-A / EMU-B は emu23 v1.13 で解消済（2026-08-14）★**<br>**【v1.13 以降の挙動】** オプションとその引数は前置パスで**消費済み**とマークされ、位置解釈の対象外になる。したがって `./emu23 prog.bin -i uart.bin --disk disk.img` でも `.dbg`/`.sym` は**自動導出で正しく読まれる**（実測 `Loaded 0` → `Loaded 1164`）。`MAX_SYM` も **128→2048** に拡張され、シンボル数の多いビルドでも全数読める。→ **ラベル名でブレークポイントを張ってよい**（16 進アドレス指定への回避は不要）。明示指定したい場合は **`--sym <file>` / `--dbg <file>`** を使う。<br>**【打切り時】** 2048 を超えると `[SYM-TRUNCATED] loaded=… skipped=… last=…` が **stderr** に出る（`-q` でも出力）。<br>**【残課題 EMU-D】** シンボル名が **31 文字を超える**と切り詰められ、その**ラベルでは BP を張れない**（`Unknown label`）。現行 `yuios_road2.sym` の最大は 26 文字のため未発現。`emu23_ticket_EMU_D_symname_v1_0.md` 参照。<br><br>~~**⚠ ★`.sym` の自動導出はオプション併用時に破綻する（EMU-A）★** emu23 は argv[2] を `.dbg`、argv[3] を `.sym` として無条件に解釈する。`./emu23 prog.bin -i uart.bin --disk disk.img` と書くと `-i` が `.dbg`、`uart.bin` が `.sym` と誤認され `Loaded 0 label symbols` になる。さらに位置引数を明示しても `MAX_SYM=128` の制限があり、シンボル数の多いビルド（PoC 等で 1199 個）ではラベル指定のブレークポイントが使えない。→ BP は `.sym` から引いた 16 進アドレスで指定すること。※ EMU-A / EMU-B として emu23 改修フェーズ B に登録済。~~（v1.13 で解消。KY41 により旧記述を取り消し線で保持） |
| --- |

| **⚠ ★ブレークポイント停止位置から `c` で再開できない（EMU-C）★** `c` は `exec_one()` の前に `is_break(pc)` を評価するため、**同じ BP で即停止する**。BP を複数張って連続 `c` で採取する手順は機能しない。→ **1 ラン 1 BP** とし、採取ポイントごとに実行を分けること。 |
| --- |

## **4.7.2 【v1.13 新設】emu23 v1.12 の MMIO 関連オプション（改良2・バス プルアップ）**

emu23 **v1.12**（2026-08-11・Phase B' 完了）で MMIO アドレスデコード層が新設され、**未接続 MMIO 領域の応答が既定で変更された**。ビルド・回帰手順そのものは変更されないが、**既定動作が変わったため本節に記録する。**

### 4.7.2.1 既定動作の変更点

| 項目 | emu23 v1.11 まで | **emu23 v1.12 以降（既定）** |
| --- | --- | --- |
| 未接続 MMIO 読出 | `mem[]` の値（＝RAM として振る舞う） | **`$FF` / `$FFFF`**（実機のバスはプルアップされるため） |
| 未接続 MMIO 書込 | `mem[]` に格納され読み返せた | **破棄される** |
| 未接続アクセス検知 | 不可 | **警告 `[MMIO-UNMAPPED]` を出力**（stderr） |
| 終了時 | — | **`[MMIO-SUMMARY] unmapped=N unsup=N`** を出力（0 件でも出力） |

**MMIO 空間は `$FC80`-`$FFFF`。**`yuios_memmap_design` L225 が「$FC80 以降は MMIO 専用領域。RAM として使用してはならない」と規定しており、**正しく書かれたコードは影響を受けない**（YUI OS・Dhrystone とも警告 0 件を実測確認済み）。

### 4.7.2.2 追加オプション

| オプション | 用途 |
| --- | --- |
| `--bus-pullup` | v1.12 以降は**既定で有効**のため no-op（互換のため受理する） |
| **`--no-bus-pullup`** | **v1.11 までの挙動（`mem[]` フォールスルー）へ切り戻す。**プルアップ起因の疑いがある障害の切り分けに使う |
| **`--strict-mmio`** | **未接続 MMIO アクセスを検出した時点で実行を停止**し、アドレスと PC を報告する。`--bus-pullup` の有無とは独立に機能する |

```
# 通常の実行（v1.11 までと同じ。既定でプルアップ）
./emu23 yuios.bin -q --disk disk.img

# 未接続アクセスの発生地点を特定したい場合
./emu23 yuios.bin -q --disk disk.img --strict-mmio

# プルアップ起因を疑う場合の切り戻し
./emu23 yuios.bin -q --disk disk.img --no-bus-pullup
```

### 4.7.2.3 ★注意：警告・サマリは stderr に出る★

**MMIO 警告とサマリは `stdout` ではなく `stderr` に出力される。**`-q` の出力比較（byte-exact 判定）を行う際は **stdout のみを比較対象**とすること。stderr を混ぜると差分が出る。

```
# 正: stdout のみ比較
./emu23 yuios.bin -q --disk disk.img > out.txt 2>/dev/null
diff out_expected.txt out.txt

# 誤: 2>&1 で混ぜると MMIO サマリが差分として現れる
```

### 4.7.2.4 サマリが出ない場合（常駐 OS の制約）

サマリは `atexit` で出力されるため、**`HALT` に到達せず `timeout` で強制終了した場合は出力されない**。YUI OS は待機ループ（`BEGIN TASK-SLEEP AGAIN`）で HALT しないため、**YUI OS 実行ではサマリを取得できない**。サマリによる検証は Dhrystone 等の HALT で正常終了するプログラムで行うこと。

```
# サマリ取得の例（Dhrystone は HALT で終了する）
./emu23 dhry.asm.bin -q 2>&1 >/dev/null | grep MMIO
  → [MMIO-SUMMARY] unmapped=0 unsup=0
```

### 4.7.2.5 8bit アクセスの被覆について

v1.12 では **8bit アクセス経路（`LDB`/`STB`）の被覆漏れが解消**された。v1.11 までは YSD8002 タイマー全 8 本・YSD8003 の 7 本・YSD8004 の 2 本（計 17 本）が 8bit アクセスでデバイスに届かず `mem[]` に落ちていた。**v1.12 以降は 8bit でも正しくデバイスへ届く。**

**なお `UART_BAUD`（`$FC86`）のみ 16bit 専用**（`ysd8001_uart_design` L166）であり、8bit アクセスすると `$00` を返し `[MMIO-UNSUP]` 警告が出る。これは仕様どおりの動作である。

## **4.7.3 【v1.14 新設】emu23 v1.13 の引数解析と `--dbg` / `--sym`（EMU-A / EMU-B）**

### (1) 何が変わったか

emu23 v1.12 までは、`argv[2]` を `.dbg`、`argv[3]` を `.sym` として
**無条件に位置解釈**していた。このためオプションを併用すると誤認が起きていた。

```
【v1.12 まで】
./emu23 prog.bin -i uart.bin --disk d.img
                  ^^^^^^^^^^  ^^^^^^^^^
                  → -i が .dbg、uart.bin が .sym と誤認
                  → fopen 失敗を黙殺 → Loaded 0 label symbols のまま継続

【v1.13 以降】
オプションとその引数は前置パスで「消費済み」とマークされ、位置解釈の対象外。
→ .dbg / .sym は自動導出され正しく読まれる（実測 Loaded 1164）
```

**この変更により、従来「読めていなかった」ものが読まれるようになる。**
`-q` を付けない実行では `Loaded N dbg entries` / `Loaded N label symbols` が
**新たに表示される**が、これは**回帰ではなく改善**である。

### (2) 新設オプション

| オプション | 意味 |
|---|---|
| `--dbg <file>` | `.dbg` を明示指定（位置引数より優先） |
| `--sym <file>` | `.sym` を明示指定（位置引数より優先） |

**推奨形**：シンボルを明示したいときは位置引数ではなく `--sym` を使う。

```
./emu23 yuios_road2.bin --sym yuios_road2.sym --disk disk.img -q
```

> **★従来の位置引数形式も動作する★**
> `./emu23 prog.bin prog.dbg prog.sym -b 1A00 -n 100` は**従来どおり**動く
> （`.dbg`/`.sym` はどのオプションにも消費されないため）。
> 一方 `./emu23 prog.bin prog.sym ...`（`.dbg` を飛ばして `.sym` を置く形）は
> **v1.12 と同じく `.sym` が `load_dbg()` に渡る**ので使わないこと。

### (3) シンボル容量（EMU-B）

`MAX_SYM` が **128 → 2048** に拡張された。
`yuios_road2.sym` は **1,164 シンボル**あり、v1.12 では先頭 128 本しか
読めていなかった（かつ**警告も出なかった**）。

超過時は **stderr** に次を出力する（`-q` でも出る）。

```
[SYM-TRUNCATED] loaded=2048 skipped=317 last=_kernel_irq_dispatch (MAX_SYM=2048) - label BP may be incomplete
```

### (4) 読込失敗の通知

| 経路 | 失敗時 |
|---|---|
| **明示指定**（`--dbg`/`--sym`/位置引数） | **stderr** に `[DBG-NOTFOUND]` / `[SYM-NOTFOUND]` |
| **自動導出** | **従来どおり黙殺**（`.dbg` を持たないビルドは正常なため） |

`--dbg`/`--sym` の値を書き忘れた場合は
`emu23: option --sym requires a filename` を出して **`exit(1)`** する。

### (5) 回帰比較時の注意（§4.7.2 ⑤と同じ原則）

**本節の警告はすべて stderr に出力される。**
`-q` の byte-exact 比較は **stdout のみ**を対象とすること
（`2>&1` で混ぜると差分が出る）。

> **★実測で判明した重要事項★**
> Dhrystone の測定値 `--- Dhrystones/sec = 819 ---` および `cycles=48785` は
> **stderr** に出力される（stdout に出るのは `P:20` のみ）。
> `Makefile` の `regress` が `-q 2>&1 | grep -iE 'Dhrystones/sec|cycles|P:'` と
> **合流させているのはこのため**である。
> したがって emu23 が stderr に出す警告文言には
> **`Dhrystones/sec` / `cycles` / `P:` を含めてはならない**（ゲートに混入するため）。

### (6) その他

- 引数の総数が **64 個**を超えると
  `emu23: too many arguments (max 64)` を出して `exit(1)` する。
- **既知の残課題（EMU-D）**：シンボル名が **31 文字**を超えると切り詰められ、
  そのラベルでは BP を張れない（`Unknown label`）。
  現行の最大は 26 文字のため未発現。`emu23_ticket_EMU_D_symname_v1_0.md` 参照。

---

## **4.8 【v1.3 新設】kernel_forth_v0_10_3.fs のビルド (Step 5-2 FILE-LIST-IMPL)**

v0.10.3 系は既存 build.sh (v0.10.2{tag} 形式) と命名規則が異なるため、専用スクリプト **build_v0_10_3.sh** を使用すること。

### 4.8.1 前提

  - Force v1.5 以降がビルド済み（_FMUL を $47B0-$47B5 に配置）

  - hasm23 v1.02 以降

  - lnk23 v2.00 以降

  - ysd8800_kern.tgt v0.4 以降（依存設計書: memmap v1.5, force_memory_contract v1.1）

  - kernel_forth_v0_10_3.fs（FILE-LIST-IMPL 実装版）

  - kernel_v12_5.asm

### 4.8.2 ビルド手順

| ./build_v0_10_3.sh # 出力: yuios_v0_10_3.bin, yuios_v0_10_3.sym |
| --- |

### 4.8.3 動作確認用ディスクイメージの準備

Step 5-2 では FILE-LIST-IMPL が USED エントリ 1 個を見つけて r0=1 を返す動作を確認するため、mkfs_yuifs.py v1.1 の --add-file オプションを使用する。

| # hello.txt 1 個を含む 32KB ディスクイメージを作成 python3 mkfs_yuifs.py disk.img --size-kb 32 --add-file hello.txt -v |
| --- |

### 4.8.4 動作確認

| ./emu23 yuios_v0_10_3.bin yuios_v0_10_3.sym --disk disk.img -q # 期待出力: 0A BC123MPDQL # L = FILE-LIST-IMPL 完了 (r0=1) |
| --- |

| **ℹ Step 5-2 出力の意味** 0A BC: カーネル起動 / 123: FILEMGR-INIT 段階 / M: FS-MOUNT 成功 / P: FILEMGR-INIT-DBG 完了 / D: DIR-LOAD 完了 / Q: FILE-STAT (no.txt → E-NOENT) / **L: FILE-LIST-IMPL 完了 (r0=1)** **l (小文字)**: FILE-LIST 失敗（r0≠1）。空ディスクで mkfs した場合は l が出る（正常な境界動作）。 |
| --- |

### 4.8.5 build.sh と build_v0_10_3.sh の使い分け

| **対象 Forth ソース** | **使用スクリプト** |
| --- | --- |
| kernel_forth_v0_10_2{a,b,...,i}.fs | build.sh (v1.2 から存在) |
| kernel_forth_v0_10_3.fs (v1.3 新規) | build_v0_10_3.sh |

将来 v0.10.4 以降を作る場合は同様の派生スクリプトを作成するか、build.sh を汎用化することを検討する（v1.3 ではスコープ外）。

## **4.9 【v1.4 新設】kernel_forth_v0_10_9.fs のビルド (Step 5-6c FILE-WRITE-IMPL ロールバック)**

v0.10.9 系は build_v0_10_8_k127.sh から派生した **build_v0_10_9_k127.sh** を使用する。kernel 本体は **kernel_v12_7.asm**（IRQ0_HANDLER A/B 完全保護版・5-6b LBA6 欠落の真因修正済み）を使用する。

### 4.9.1 前提

  - Force v1.5 以降がビルド済み（frontend/backend サブディレクトリ構成。§3.1・§2.3 参照）

  - hasm23 v1.02 以降 / lnk23 v2.00 以降 / emu23 v1.05

  - ysd8800_kern.tgt v0.5 以降（依存設計書: memmap v1.6 / force_memory_contract v1.2。$47B6=IRQ_WK_B 占有反映済み）

  - kernel_v12_7.asm（v0.12.7・IRQ0_HANDLER の A/B 完全保護）

  - kernel_forth_v0_10_9.fs（FILE-WRITE-IMPL 5-6c ロールバック実装版）

### 4.9.2 ビルド手順

| ./build_v0_10_9_k127.sh # 出力: yuios_v0_10_9.bin, yuios_v0_10_9.sym |
| --- |

ビルドスクリプトは build_v0_10_8_k127.sh と同一構造で、SRC/ASM/KASM/BIN/SYM の各変数を v0_10_9 に置換したもの。Step 1 Force → Step 2 hasm23 1パス目 → Step 3 sed ラベル置換 (WORD_MEMMGR_TASK 〜 WORD_FILEMGR_TEST_TASK) → Step 4 hasm23 2パス目 → Step 5 kernel_v12_7.asm の WORD_OS_START sed 更新 → Step 6 lnk23 (forth 先 → kernel 後) の流れ。

### 4.9.3 動作確認用ディスクイメージの準備

5-6c の検証 (FILE-WRITE-IMPL の単一/複数セクタ WRITE と往復検証) では hello.txt 入りディスクを使う。**テストごとに必ず作り直す**こと (§6.10 参照)。

| python3 mkfs_yuifs.py disk.img --size-kb 32 --add-file hello.txt |
| --- |

### 4.9.4 動作確認

| ./emu23 yuios_v0_10_9.bin -q --disk disk.img # 期待出力: 0A BC123MPDQLORCWVX |
| --- |

| **ℹ Step 5-6c 出力の意味** 0A BC123MPDQ: カーネル起動〜FileMgr 初期化・FILE-STAT。 L: FILE-LIST 成功 / O: OPEN 成功 / R: READ 成功 / C: CLOSE 成功。 W: 単一セクタ WRITE 成功 (5-6a 相当)。 V: 書込ファイルの読み返し検証成功。 **X: 複数セクタ (1024B) 往復検証 全サンプル点一致 (5-6b/5-6c 完全成功)**。 大文字 WVX が揃えば成功。小文字 wVx/l 等が出たらディスク汚染 (§6.10) を疑い disk.img を作り直す。 5-6c のロールバック追加後も本出力が v0.10.8 と完全一致することが非回帰の合格基準 (D-2 検証)。 |
| --- |

### 4.9.5 5-6c ロールバックの検証範囲 (D-2)

5-6c の巻戻し経路 ([M] SB-LOAD/SB-STORE 失敗時のメモリ巻戻し) は、emu23 v1.04 にピンポイントのエラー注入機構がない (ディスク未接続による全 I/O 失敗のみ可能) ため、**机上検証 (巻戻しロジックの等価性・R スタック整合・ディスク非接触) ＋ 正常系 `…WVX` の非回帰実機**で検証する (設計書 yuios_ph4_filemgr_design_v1_9_1.md §6.4.1.5・§8.4.6.6)。emu23 は無改修。

## **4.10 【v1.5 新設】スタック watermark によるタスクスタック使用量計測（任意）**

emu23 v1.05 は、各タスク（tid 0〜15）のコールスタック（$F000-$F7FF）・データスタック（$F800-$FBFF）の最深使用量と、stack guard（$FC00-$FC3F の $A55A）の破壊有無を計測する `-w` オプションを備える。タスク数が増える Ph.5 以降や FPGA 移行前の品質確認で、各タスクが 128B 枠に収まるかを実測できる。

本機能は**任意の追加計測**であり、`-w` を付けない通常のビルド・実行手順（§3.5・§4.7）は一切変わらない（v1.04 と完全同一動作・非回帰確認済み）。

### **4.10.1 基本的な使い方**

| # 常駐OS(HALTしない)のため -q -w に加え --wm-steps で打切り上限を指定 ./emu23 yuios.bin --disk disk.img -i /dev/null -q -w --wm-steps 10000000 |

計測結果は **stderr** に出力される（stdout の UART 出力は汚染しない）。各 tid のスタック使用バイト数（/128B）、最大使用タスク（PEAK）、guard 検査結果が表示される。

### **4.10.2 起動初期の誤検出対処（--wm-warmup）**

カーネル起動 _kstart は KERN_SP 初期化のため一瞬 X=$F800 を設定する。これが data tid=0 の満杯（128B）として誤検出される場合は `--wm-warmup`（既定 2000 サイクル）で起動初期を測定対象外にする。

| ./emu23 yuios.bin --disk disk.img -i /dev/null -q -w --wm-warmup 2000 |

### **4.10.3 注意（KY）**

- `-w` は YUI OS のタスクスタック配置（各 128B）を前提とする。Dhrystone 等の単体プログラム（startup_harness が独自 SP を使う）では誤検出が出るため `-w` を付けない。
- guard が VIOLATED と出た場合はスタック突き抜け（オーバーラン）。当該タスクのスタック設計を見直す。
- 詳細は emu23_debug_manual_v1_1.docx §2.3.7・§9.1、設計は emu23_v105_design_v1_0.md を参照。

# **5. C プログラムビルド手順 (Dhrystone 等)**

scc23 + hasm23 + lnk23 + startup_harness23 のフローはv1.1から変更なし。詳細手順は §5.1〜§5.6 を参照のこと。

(v1.1 と同一のため、本v1.2ではダイジェスト記載のみ。詳細手順は v1.1 文書を参照。)

## **5.1 全体フロー**

| [dhry_timer.c]       │ scc23 コンパイル       v [dhry.asm]       │ hasm23 アセンブル → _main アドレス取得       v [dhry.asm.bin] + [dhry.asm.sym] [startup_harness23_v15.asm]       │ sed で JSR _main → JSR $XXXX (直書き化)       │ hasm23 アセンブル       v [startup_harness23.asm.bin] + [startup_harness23.asm.sym]       │ lnk23 (dhry.lds スクリプト)       v [dhry_final.bin] + [dhry_final.sym]       │ emu23 実行 (ディスク不要)       v Dhrystone ベンチ結果出力 |
| --- |

# **6. ビルド時の既知の落とし穴と対処**

## **6.1 Force 出力の混入行 (#WORD_xxx)**

| **項目** | **内容** |
| --- | --- |
| 現象 | Force が #WORD_xxx 形式のシンボル参照を出力する |
| 影響 | hasm23 v1.02 は当該行でエラー停止 ("Label cannot start with #") |
| 対処 | sed でシンボルアドレスを直書きに変換 (§4.3 参照) |
| 将来 | Force 側の修正で不要になる予定 |

## **6.2 .bin ファイルの先頭パディング問題 (後勝ちルール)**

| **項目** | **内容** |
| --- | --- |
| 現象 | hasm23 は .org 指定アドレスまでを 0x00 で padding する |
| 具体例 | kernel_forth (.org $5100 始まり) → 0x0000〜$50FF が 0x00 |
| 影響 | SECTION 順序を誤ると kernel.bin が Forth の 0x00 padding で上書きされる |
| 対処 | lds スクリプトは必ず「forth 先 → kernel 後」とする |

## **6.3 startup_harness の JSR _main 問題**

| **項目** | **内容** |
| --- | --- |
| 現象 | startup_harness23_v15.asm が JSR _main のシンボル参照を使用 |
| 影響 | lnk23 lds モードでも _main が解決されずリンクエラー |
| 対処 | sed で JSR $XXXX に直書き変換 (§5.x 参照) |
| 将来 | lnk23 のクロスセクション参照対応で解決可能 |

## **6.4 hasm23 の構文制限まとめ**

| **パターン** | **可否** | **代替手段** |
| --- | --- | --- |
| LDW A, #'H' | ❌ 不可 | LDW A, #$48 (16進直書き) |
| LDW A, #UART_TX (EQU値) | ❌ 警告 (bin は 0) | LDW A, #$FC80 (直書き) |
| STW A, [#$5000] | ❌ # でエラー | STW A, [$5000] (# を除去) |
| STW A, [UART_STAT] (EQU) | ✅ OK | — |
| STW A, [SYMBOL] | ✅ OK (bin モード) | — |
| JSR _symbol | ❌ bin モードで未解決 | JSR $XXXX か YOF -c モード |
| YOF (-c) モードで .org backward | ❌ サポート外 | bin モードを使用 |
| 同名ラベルの2回定義 | ❌ E001 エラー停止 | v1.02 で新規追加された検出機能 |
| .org による既存バイト上書き | ⚠ W001 警告 (停止せず) | v1.02 で新規追加 § 4.4.5 / § 6.7 参照 |
| **ラベル行への同一行コメント**<br>`_label:  ; コメント` | **❌ 不可**<br>`Unknown instruction '_LABEL:'` | **ラベルは単独行にし、コメントは前行に置く**<br>【v1.12 新設】既存ソースのラベルはすべて単独行であり、この制約は従来未文書化であった |
| **`.equ` ディレクティブ** | **❌ 不在** | **定数定義は大文字 `EQU` のみ**。中間シンボルを使わず直値で書く<br>実装ディレクティブは `.byte/.db/.dw/.global/.org/.vector/.word`【v1.12 新設】 |

## **6.5 lnk23 の machine モード使い分け**

| **モード** | **TEXT 領域制約** | **用途** |
| --- | --- | --- |
| baremetal (デフォルト) | $3FFF まで | 小規模プログラム |
| none | 制約なし | Dhrystone 等大規模 C プログラム |
| force | Force カーネル前提 | Forth プログラム |

## **6.6 シンボルアドレスの食い違い検出**

kernel.asm と kernel_forth.asm.sym のシンボルアドレスが合っているか、ビルド毎に確認する。Forth シンボルアドレスのハードコードは禁止 (kaizen 原則31)。以下の手順で全件を機械的に抽出すること:

| # Step 1: kernel.asm 内の即値アドレスを全件抽出 (ハードコード検出) grep -En '\$[0-9A-Fa-f]{4}' kernel_v12_5.asm │ grep -v 'EQU\│;' grep -En 'WORD_' kernel_v12_5.asm # Step 2: 実際の Forth シンボルアドレスを .sym から確認 grep -E 'WORD_MEMMGR_TASK│WORD_OS_START' kernel_forth_v0_9_0.asm.sym # Step 3: 不一致があれば sed で置換 (§4.5 参照) |
| --- |

## **6.7 【v1.2 新設】VARIABLE 追加・変更時の必須確認手順**

| **⚠ ★ VARIABLE / VALUE / DEFER を Forth ソースに追加・変更したら必ず確認 ★** 本確認はPh.4 で発生した「ワード追加によるレイアウト破壊問題」(HANDOVER_CHAT28/29) の 再発防止策として、すべてのコミット前に必須となる手順である。 |
| --- |

確認手順:

### **Step 1: Force v1.4 で生成**

| ./force/force --target ysd8800_kern \               --tgt-file force/targets/ysd8800_kern.tgt \               --prim-file force/targets/ysd8800.prim \               kernel_forth_v0_9_0.fs \               -o kernel_forth_v0_9_0.asm |
| --- |

### **Step 2: .asm ファイルでデータ部とコード部の分離を目視確認**

| # Data section 区切りコメントが必ず存在するはず grep -n 'Data section' kernel_forth_v0_9_0.asm # 期待出力例: #   4491:; ==== Data section (VARIABLE/VALUE/DEFER) ==== # その区切りより前に WORD_xxx (getter) が、その後に VAR_xxx (DW) があるか確認 sep_line=$(grep -n 'Data section' kernel_forth_v0_9_0.asm │ head -1 │ cut -d: -f1) head -n $sep_line kernel_forth_v0_9_0.asm │ grep -c '^WORD_'  # > 0 なら OK tail -n +$sep_line kernel_forth_v0_9_0.asm │ grep -c '^VAR_'  # > 0 なら OK |
| --- |

### **Step 3: hasm23 アセンブル + W001 件数チェック**

| ./hasm23 kernel_forth_v0_9_0.asm 2>&1 │ tee hasm23_out.log warns=$(grep -c '^hasm23: W001' hasm23_out.log ││ true) if [ "$warns" -gt 0 ]; then   echo "★★★ ERROR: W001 重ね書き警告が $warns 件 ★★★"   echo "Force のバージョン / Forth ソースの .org 後退記述を確認してください"   exit 1 fi echo "VARIABLE 配置 OK (W001 ゼロ)" |
| --- |

### **Step 4: シンボルアドレスが想定範囲内か確認**

| # WORD_OS_START は MMIO 境界 ($FC80) より十分手前にあるべき os_addr=$(grep -E '^[0-9a-f]+ WORD_OS_START$' kernel_forth_v0_9_0.asm.sym │ awk '{print $1}') os_dec=$(printf '%d' "0x$os_addr") mmio_dec=$(printf '%d' '0xFC80') if [ "$os_dec" -ge "$mmio_dec" ]; then   echo "★ WARNING: WORD_OS_START = \$$os_addr が MMIO 境界 \$FC80 を超えている"   echo "  辞書サイズが MMIO 領域に侵食しています。Force の出力が肥大化していないか確認してください" fi |
| --- |

これら4ステップをすべて通過した場合のみ、リンク・実行へ進めること。

## **6.8 【v1.2 新設】--disk マウントなしによる STOR-TEST 失敗**

| **項目** | **内容** |
| --- | --- |
| 現象 | emu23 実行で `A BCF4` が出力される |
| 原因 | ディスクイメージ未マウントで STOR-TEST S4 (read/write 結果比較) が必ず失敗 |
| 確認 | F4 の F は "Fail"、4 は S4 段階を示す |
| 対処 | dd で 32KB 空イメージを作成し --disk disk.img オプションで渡す (§4.7 参照) |
| 備考 | kernel_forth が STOR-TEST を起動しないバージョンでは関係ない |

## **6.9 【v1.3 新設】FILE-LIST-IMPL のビルド前確認**

Step 5-2 で FILE-LIST-IMPL を実装する際、ビルド前に以下の前提条件をすべて満たしているか確認すること（KY21: 実装着手時に設計書記載の前提条件確認を怠る危険の防止策）。

### 6.9.1 RSHIFT 利用可能性の確認

FILE-LIST-IMPL は `4 RSHIFT` で 16 分割するため、RSHIFT が利用可能である必要がある。

| grep -n "RSHIFT" ysd8800.prim # PRIM RSHIFT があれば OK grep -n "RSHIFT" parser.c # 認識されていれば OK |
| --- |

Force v1.5 + ysd8800.prim では PRIM 定義済み（kernel_forth で複数箇所の使用実績あり）。

### 6.9.2 専用 VARIABLE の追加

FILE-LIST-IMPL は MEMCPY-B との変数衝突を避けるため、専用 VARIABLE 3 個を追加する必要がある（設計書 force_memory_contract v1.1 §6 / FileMgr 設計書 v1.5.2 §5.8）。

| VARIABLE FM-WK-COUNT \\ FILE-LIST 書き込み済み件数 (戻り値) VARIABLE FM-WK-REMAIN \\ FILE-LIST 残り書込可能枠 VARIABLE FM-WK-PTR \\ FILE-LIST 次の書き込み先ポインタ |
| --- |

追加位置: kernel_forth の既存 FM-WK-DST/SRC/LEN/VAL/A/B/C の末尾。追加メモリは +6B で、データ領域 $C000 系に配置されるため FileMgr 専用領域は圧迫しない。

### 6.9.3 試験 buf アドレスの確認

FILEMGR-TEST-TASK での FILE-LIST-TEST 用バッファは **TEST-DST-BUF + $100 (=$EF00)** を使用する（設計書 v1.5.2 §8.4.3.1）。

旧 v1.5/v1.5.1 では $F900 と記載されていたが、実際にはタスクスタック領域（tid=2 のデータスタック）と衝突するため誤り。v1.5.2 で TEST-DST-BUF+$100 に訂正された。

### 6.9.4 ビルド後の Force ASM 検査

ビルド完了後、force_asm_audit.py v1.1 で出力 ASM のメモリ違反検査を行うことを推奨する（KY19 防止策）。

| python3 force_asm_audit.py kernel_forth_v0_10_3.asm |
| --- |

| **⚠ 注意** force_asm_audit.py v1.1 は `CODE...END-CODE` 内のカーネル内部アクセスを Force ランタイムと誤判定する既知の問題があり、現状で約 7 件の誤検出が出る（line 579 等の IRQ_WK_X / CUR_TASK アクセス）。FILE-LIST-IMPL 関連の違反かどうかは検出行のシンボル名で判別すること。本ツールの改修は将来課題（§10）。 |
| --- |

## **6.10 【v1.4 新設】テスト時のディスクイメージ汚染による誤デグレード**

| **項目** | **内容** |
| --- | --- |
| 現象 | FileMgr テスト出力が `…WVX`（全大文字＝成功）でなく `…wVx` や `…lORC…` のように一部が小文字になる。あたかも実装がデグレードしたように見える |
| 原因 | FILEMGR-TEST は WRITE 系で wtest.txt / w1k.txt 等を**実際に disk.img へ書き込む**。同じ disk.img を 2 回目以降のテストで使い回すと、既に同名ファイルが存在するため WRITE が E-EXIST で失敗し `w`/`x`（小文字）、FILE-LIST も既存ファイル増で期待件数とずれて `l`（小文字）になる |
| 確認 | クリーンな disk.img（mkfs 直後）で再実行して `…WVX` が出れば、実装ではなくディスク汚染が原因と確定 |
| 対処 | **テストごとに必ず mkfs_yuifs で disk.img を作り直す**こと。`python3 mkfs_yuifs.py disk.img --size-kb 32 --add-file hello.txt`。FileMgr 設計書 §8.4.6.5 デバッグ手順 #2「前回実行のディスクが残存（毎回 mkfs し直す）」と整合 |
| 教訓 | 2026-06-02 の 5-6c 実装検証で、改修後初回 `wVx`→デグレードを疑ったが、kaizen 原則「動作する参照成果物と直接比較」「計測された状態から始める」に従い v0.10.8 を同一環境でビルド比較し、クリーン disk で両版とも `WVX` 一致＝実装は正常・ディスク汚染が原因と切り分けた。回帰試験は必ず初期状態を揃えて行うこと |

# **7. ビルドスクリプト例 (自動化用シェル)**

## **7.1 build_yuios.sh — YUI OS 統合ビルド (v1.2)**

以下のスクリプトは Force v1.4 / hasm23 v1.02 / emu23 v1.04 を前提とする。要修正箇所は # [要修正] コメントで示す。

| #!/bin/bash # build_yuios.sh - YUI OS 統合ビルドスクリプト # Version: 1.2 / 2026-05-23 set -e # [要修正] ツールのパス FORCE=./force/force HASM=./hasm23 LNK=./lnk23 EMU=./emu23 # [要修正] ソースファイルのパス FORTH_SRC=kernel_forth_v0_9_0.fs KERN_ASM_SRC=kernel_v12_5.asm TGT_DIR=force/targets FORTH_ASM=${FORTH_SRC%.fs}.asm KERN_ASM=${KERN_ASM_SRC%.asm}_built.asm echo "=== Step 1: Force コンパイル ===" $FORCE --target ysd8800_kern \        --tgt-file $TGT_DIR/ysd8800_kern.tgt \        --prim-file $TGT_DIR/ysd8800.prim \        $FORTH_SRC -o $FORTH_ASM echo "=== Step 2: 混入行修正 (1パス目シンボル取得後) ===" ./hasm23 $FORTH_ASM 2>/dev/null ││ true   # 1パス目は混入行エラーで停止するが .sym は生成 for sym in WORD_MEMMGR_TASK WORD_UART_DRV_TASK WORD_UART_TEST_TASK \            WORD_STOR_DRV_TASK WORD_STOR_TEST_TASK; do   addr=$(grep -E "^[0-9a-f]+ ${sym}$" ${FORTH_ASM}.sym │ awk '{print $1}')   [ -n "$addr" ] && sed -i "s│LDW  A, #${sym}│LDW  A, #\$${addr}│g" $FORTH_ASM done echo "=== Step 3: hasm23 アセンブル + W001 ゼロ確認 ===" rm -f ${FORTH_ASM}.bin ${FORTH_ASM}.sym $HASM $FORTH_ASM 2>&1 │ tee hasm23_out.log warns=$(grep -c '^hasm23: W001' hasm23_out.log ││ true) if [ "$warns" -gt 0 ]; then   echo "★★★ ERROR: W001 重ね書き警告 $warns 件。設計を見直してください ★★★"   exit 1 fi echo "=== Step 4: kernel.asm の WORD_OS_START 更新 ===" new_addr=$(grep -E "^[0-9a-f]+ WORD_OS_START$" ${FORTH_ASM}.sym │ awk '{print $1}') if [ -z "$new_addr" ]; then   echo "ERROR: WORD_OS_START が .sym にありません"; exit 1 fi echo "WORD_OS_START = \$$new_addr" cp $KERN_ASM_SRC $KERN_ASM sed -i "s│\$e96e│\$${new_addr}│g" $KERN_ASM $HASM $KERN_ASM echo "=== Step 5: lnk23 リンク ===" cat > yuios.lds <<EOF OUTPUT yuios.bin SYMOUT yuios.sym SECTION forth   0x0000 ${FORTH_ASM}.bin ${FORTH_ASM}.sym SECTION kernel  0x0000 ${KERN_ASM}.bin ${KERN_ASM}.sym EOF $LNK yuios.lds echo "=== Step 6: ダミーディスクイメージ作成 ===" if [ ! -f disk.img ]; then   dd if=/dev/zero of=disk.img bs=512 count=64 status=none   echo "disk.img (32KB) 作成完了" fi echo "=== Step 7: emu23 動作確認 ===" $EMU yuios.bin yuios.sym --disk disk.img -q echo "\n=== ビルド完了 ===" ls -la yuios.bin |
| --- |

# **8. トラブルシューティング**

## **8.1 PC=$E000 ループ**

| **項目** | **内容** |
| --- | --- |
| 症状 | [DBG] Jumping into workspace! PC=E000 が連続出力される |
| 原因 | Forth カーネル領域 ($C000 以降) が 0x00 で埋まっている。kernel が初期化後に NOP を実行し続けて PC が $E000 まで進む。 |
| 確認 | od -An -tx1 -j 0xC000 -N 16 yuios.bin → 全部 00 ならこの症状 |
| 対処 | lds の SECTION 順序を「forth 先 → kernel 後」に変更 (§4.6 参照) |

## **8.2 PC=$0400 で Unknown opcode 18**

| **項目** | **内容** |
| --- | --- |
| 症状 | リセット後即座に「Unknown opcode 18 at 0400」でエラー終了 |
| 原因 | リセットベクタ ($0000-$0001) が 0x00 のまま |
| 対処 | startup_harness を必ず含める。lnk23 -T 0x0400 は使わず lds スクリプトを使用 |

## **8.3 putchar で無限ループ (出力なしでタイムアウト)**

| **項目** | **内容** |
| --- | --- |
| 症状 | 出力なしでタイムアウト、または UART_STAT 待ちでハング |
| 原因 | _putchar 実装が UART_STAT 待ちループ。emu23 v1.02 以上では正常動作 |
| 対処 | emu23 v1.02 以上 (本書はv1.04を推奨) を使用 |

## **8.4 【v1.2 新設】UART 出力なしで PC 不定 HALT (VARIABLE 由来)**

| **項目** | **内容** |
| --- | --- |
| 症状 | emu23 実行で UART 出力が一切なく、$C000 領域近辺で HALT する |
| 原因 | Force v1.2 以前 + hasm23 v1.01 以前の組み合わせで、複数の VARIABLE 定義時に getter コードが上書きされる重大バグ |
| 確認 | hasm23 v1.02 で再ビルドし W001 警告が大量に出るか確認 |
| 対処 | Force v1.4 + hasm23 v1.02 にアップグレードする。本書v1.2が前提とするバージョン構成にすれば自動的に解消 |
| 参考 | HANDOVER_CHAT28/29 progress_report_2026_05_23_part2.md |

## **8.5 【v1.2 新設】出力が ****"****A BCF4****"**** で停止する**

| **項目** | **内容** |
| --- | --- |
| 症状 | 正常動作の "A BCP" ではなく "A BCF4" で停止する |
| 原因 | emu23 を --disk オプションなしで起動した |
| 対処 | dd で disk.img 作成 → --disk disk.img を付けて再実行 (§4.7 参照) |

## **8.6 【v1.4 新設】emu23 が即 exit する／-q で出力がゼロになる**

| **項目** | **内容** |
| --- | --- |
| 症状 | emu23 を起動するとほぼ瞬時に exit し、UART 出力が一切得られない（特に -q を付けたとき） |
| 原因 | `-q` 等のオプションをプログラム名より**前**に置いた。emu23 は argv[1] を必ず .bin 名として load_bin するため、`./emu23 -q yuios.bin` だと load_bin("-q") が失敗して即 exit する |
| 確認 | `./emu23 yuios.bin` のようにプログラムを第1引数にして起動できるか確認 |
| 対処 | オプションはプログラム名の後ろに置く。正：`./emu23 yuios.bin -q --disk disk.img`（§4.7 の引数順序注意を参照） |
| 備考 | -q なしで起動すると `** IRQ N accepted **` 等の診断が大量に stdout に出て UART 文字が埋もれる。UART 出力だけ見たいときは -q を（プログラム名の後ろに）付ける |

# **9. 関連ファイル一覧**

| **ファイル名** | **バージョン** | **用途** |
| --- | --- | --- |
| kernel_v12_7.asm | v12.7 | Ph.2〜Ph.4 OS ASM カーネル (IRQ0_HANDLER A/B 完全保護・5-6b 真因修正済み) |
| kernel_forth_v0_10_9.fs | v0.10.9 | Ph.4 OS Forth カーネル (FileMgr・FILE-WRITE-IMPL 5-6c ロールバック含む) |
| build_v0_10_9_k127.sh | — | v0.10.9 + kernel_v12_7 統合ビルドスクリプト (§4.9) |
| dhry_timer.c | — | Dhrystone (タイマー MMIO 版) |
| startup_harness23_v15.asm | v1.5 | C プログラム用スタートアップ |
| ysd8800_kern.tgt | v0.5 | Force ターゲット定義 (OS カーネル用・$47B6 占有反映) |
| ysd8800.prim | — | Force プリミティブ定義 |
| force.c + ir/lexer/parser/codegen | v1.4 | Force コンパイラ本体 |
| scc23_v1_00.c | v1.00 | C コンパイラ |
| hasm23.c | v1.02 | アセンブラ (W001/E001 検出) |
| lnk23.c | v2.00 | リンカ |
| emu23_v105.c | v1.05 | エミュレータ |
| lnk23_design_v1_3.docx | v1.3 | lnk23 設計書 (lds スクリプト仕様) |
| HANDOVER_CHAT28.md | — | Ph.4 レイアウト破壊問題発生時の引継ぎ |
| HANDOVER_CHAT29.md | — | Force v1.4 / hasm23 v1.02 根本対策完了時の引継ぎ |
| progress_report_2026_05_23_part2.md | — | VARIABLE 分離対策の進捗報告 |

# **§4.11 道2ビルド（YOF 固定アドレス配置・sed系統② 廃止）【v1.6 新設・文書末尾に追補】**

> 本節は章番号上は §4 系列だが、KY41 整合のため文書末尾に追補する。道2（Step 8-F-2）
> による新ビルド経路であり、従来の §4.8/§4.9/§7.1（sed系統②）を置き換える。
> 関連設計書: hasm23_xref_yof_design_v2_3.md（§3.5・§3.7）。

## 4.11.1 道2 の要旨

従来ビルドは kernel.asm 内の Forth シンボル（WORD_OS_START）を **sed で実アドレス直書き**
（sed系統②＝§10 No.6）していた。道2 はこれを廃止し、**YOF オブジェクトのクロスファイル
UNDEF 参照を lnk23 が解決**する。hasm23 v1.04 が `.org` を配置アドレスとして尊重して
YOF を出力（forth=load_addr $5100 / kernel=load_addr $0000・has_org フラグ付き）、
lnk23 v2.01 が load_addr を尊重して固定配置する。

## 4.11.2 必要ツール版数

| ツール | 版数 | 道2 での役割 |
| --- | --- | --- |
| Force | v1.5 | forth カーネルコンパイル（従来同） |
| hasm23 | **v1.04** | YOFモードの `.org` 尊重・has_org 出力・.vector 遅延書き込み |
| lnk23 | **v2.01** | load_addr+has_org 尊重の固定配置・`--machine force` |
| emu23 | v1.06 | 実行確認（従来同・引数はバイナリ名の後） |

## 4.11.3 ビルド手順（build_road2.sh）

```bash
# Step 1: Force（forth カーネルコンパイル）
./force --target ysd8800_kern --tgt-file ysd8800_kern.tgt \
        --prim-file ysd8800.prim kernel_forth_v0_10_18.fs -o kf_r2.asm

# Step 2: 後処理1（混入行 #WORD_xxx を全自動抽出して 1パス目アドレスで #$addr 直書き）
#   ★固定リストを使わない（kernel_forth v0.10.18 実態は6個。固定リスト流用は取りこぼす）
sed -E 's/#WORD_[A-Z0-9_]+/#$0000/g' kf_r2.asm > kf_r2.asm.p1
./hasm23 kf_r2.asm.p1                     # 1パス目で .sym 取得
cp kf_r2.asm kf_r2.asm.work
for sym in $(grep -oE '#WORD_[A-Z0-9_]+' kf_r2.asm | sed 's/^#//' | sort -u); do
  addr=$(grep -E "^[0-9a-f]+ ${sym}$" kf_r2.asm.p1.sym | awk '{print $1}')
  [ -z "$addr" ] && { echo "ERROR: $sym addr不在"; exit 1; }
  sed -i "s|#${sym}\b|#\$${addr}|g" kf_r2.asm.work
done
mv kf_r2.asm.work kf_r2.asm

# Step 3: 後処理2（WORD_OS_START 定義直前に .global を挿入）
awk '/^WORD_OS_START:/ && !d { print ".global WORD_OS_START"; d=1 } { print }' \
    kf_r2.asm > kf_r2.asm.g && mv kf_r2.asm.g kf_r2.asm

# Step 4: hasm23 -c で forth.obj（load_addr=$5100・has_org・WORD_OS_START=GLOBAL）
./hasm23 -c kf_r2.asm

# Step 5: kernel.asm の #$e96e を #$WORD_OS_START へ（sed系統② = No.6 廃止・UNDEF 参照化）
#   ★本番ソース非改変：実験ファイル名 kf_r2_kern.asm に出力（KY38）
sed 's|#\$e96e|#$WORD_OS_START|g' kernel_v12_7.asm > kf_r2_kern.asm

# Step 6: hasm23 -c で kernel.obj（load_addr=$0000・has_org・WORD_OS_START=UNDEF・reloc=2）
./hasm23 -c kf_r2_kern.asm

# Step 7: lnk23 道2リンク（★--machine force 必須・load_addr 尊重の固定配置）
./lnk23 -o yuios.bin --sym yuios.sym --machine force kf_r2.asm.obj kf_r2_kern.asm.obj
```

## 4.11.4 ★最重要注意：`--machine force` は必須（L-8）

道2 リンクでは **`--machine force` を必ず付ける**。forth セクションは load_addr=$5100 に
固定配置されるが、lnk23 の既定（baremetal）モードは ROM 境界 $3FFF を超えるセクションを
エラーにするため、これを付けないと forth@$5100 が弾かれてリンク失敗する。
forth は RAM 上の正当配置であり、`--machine force` は ROM 境界チェックを正しく回避する手段。

## 4.11.5 検証（結合テスト I1-I3 実績）

| 項目 | 期待 / 実績 |
| --- | --- |
| I1 配置 | forth@$5100・kernel@$0000・WORD_OS_START 解決・**reloc=2** |
| I2 起動 | `YUIOS Booted!` `0YUI> 1X23MD`（従来版と一致） |
| I3 バイト比較 | 道2版 yuios.bin と従来 .bin リンク版が**全56416バイト完全一致** |
| 回帰 | 非YOF Dhrystone 819/48785/P:20（hasm23 v1.04 は .bin 出力を1バイトも変えない・scc23 v2.04 で新絶対ゲート） |



# **§4.12 Makefile によるビルド（Step 8-B・No.4/No.5 解決）【v1.7 新設・文書末尾に追補】**

> 本節は Step 8-B（ビルドシステム改善）で導入した **Makefile v1.0** によるビルドを記す。
> §4.11 の道2手動ビルド（build_road2.sh）および既知 Dhrystone 手順を **バイト等価**で
> Makefile 規則化したもので、ツールへの入力バイト列・順序・オプションは一切変えない。
> 関連設計書: yuios_makefile_design_v0_2.md（APPROVED）。成果物: Makefile / mk_post1.sh。

## 4.12.1 ターゲット一覧

| ターゲット | 動作 | 生成物 |
| --- | --- | --- |
| `all`（既定） | = `yuios` | yuios_road2.bin / yuios_road2.sym |
| `yuios` | 道2ビルド（S1〜S7・§4.11 とバイト等価） | yuios_road2.bin / yuios_road2.sym |
| `dhrystone` | Dhrystone ビルド（D1〜D7・lds は Makefile が自動生成＝**No.4 解決**） | dhry_final.bin / dhry_final.sym |
| `disk` | ディスクイメージ生成（既定名 disk.img＝**No.5 解決**） | disk.img |
| `run` | `yuios` + `disk` 後に emu23 起動（対話 OS。timeout 終了＝正常） | （実行のみ） |
| `regress` | `dhrystone` 後に emu23 で 819/48785/P:20 を判定 | （判定のみ） |
| `verify` | `yuios` 後に基準 .bin と `cmp`（56416一致判定） | （判定のみ） |
| `clean` | 中間・成果物の削除（disk.img は対象外＝誤消去防止） | — |

## 4.12.2 必須プリアンブル（M-A）

GNU Make はレシピ各行を独立サブシェルで実行するため、Dhrystone D4 のシェル変数 `MAIN` を
行またぎで保持するには以下を冒頭に必須記述する。

```make
SHELL       := /bin/bash
.SHELLFLAGS := -ec        # -e: 途中失敗で即停止 / -c: コマンド実行
.ONESHELL:                # レシピ全体を単一シェルで実行（変数を行またぎ保持）
```

## 4.12.3 主要な使い方

```bash
make yuios       # 道2 OS ビルド → yuios_road2.bin
make verify      # 基準 yuios_ref_road2_I3.bin と cmp（56416 完全一致を判定）
make dhrystone   # Dhrystone ビルド
make regress     # Dhrystone 実行 → 819/48785/P:20 判定
make disk        # disk.img 生成（既定名・mkfs_yuifs v1.1）
make run         # yuios + disk 後 emu23 起動（YUIOS Booted! 確認。対話のため timeout 終了は正常）
make clean       # 中間・成果物削除（disk.img は残す）
```

## 4.12.4 ★注意事項（KY・J-7）

- **後処理1（S2）は `bash ./mk_post1.sh $(FORTH_ASM) $(HASM)` で呼ぶ**（実行権限非依存）。
  mk_post1.sh の中身は build_road2.sh Step2 の**バイト等価移植**（新規ロジックなし）。
- **ツール（force/hasm23/lnk23/emu23/scc23）を差し替えたら必ず `make clean` を実行**してから
  再ビルドする（J-7）。Make はツールバイナリ更新を検知しないため、古い中間物が残ると
  56416 不一致・誤回帰の温床になる。
- **基準 `REF_BIN := yuios_ref_road2_I3.bin`** は道2 I3 で 56416 完全一致を確認した既知良品を
  凍結退避したもの（E-A）。yuios.bin 自身を基準にしない（自己比較は検証無効）。
- **`make run` は対話 OS** のため emu23 が入力待ちになり `timeout` で終了する。これは正常で
  あり判定対象外（合否判定は verify/regress で行う）。
- **`make clean` のワイルドカード**（`$(FORTH_ASM)*` 等）は意図内だが、不安なら `make -n clean`
  で対象を確認してから実行する（E-B）。

## 4.12.5 検証実績（MK-1〜MK-6・2026-06-21）

| ID | 内容 | 結果 |
| --- | --- | --- |
| D-2 | `make -n` 展開後文字列が build_road2.sh / Dhrystone 手順とバイト等価 | PASS |
| D-3 | `.ONESHELL` で MAIN が行またぎ保持 | PASS（dhrystone 実ビルドで実証） |
| MK-1 | `make yuios`→`make verify` で 56416 一致 | PASS（VERIFY OK） |
| MK-2 | `make dhrystone`→`make regress` で 826/48405/P:20 | PASS（完全一致） |
| MK-3 | `make disk` で disk.img 生成 | PASS（32KB） |
| MK-4 | `make run` で `YUIOS Booted!` | PASS（Booted!→`0YUI>`・rc124=対話 timeout で正常） |
| MK-5 | `make clean` 後 再 make で MK-1 再現 | PASS |
| MK-6 | 本番ソース（fs/asm/c/prim/tgt）非改変 diff ゼロ | PASS（KY38） |



# **§4.13 ツール実体検証と環境同期（バージョン詐称バイナリの再発防止）【v1.9 新設・文書末尾に追補】**

> 本節は 2026-07-04 に発生した「ローカル hasm23 のバージョン詐称バイナリによる YUI OS 起動不能」事故の再発防止策を記す。関連：kaizen.txt 原則56/57/58。

## 4.13.1 背景（事故の要約）

ローカルの `make yuios` 生成バイナリが起動しなかった。REF（`yuios_ref_road2_I3.bin`）との相違は先頭9バイト（$0000-$0008 のベクタテーブル）のみで、残り56407バイトは完全一致。**リセットベクタ $0000 が全ゼロのため CPU が起動アドレスを取得できず暴走**していた（MC6809 でリセットベクタ $FFFE が空だと起動しないのと同一構図）。

- **直接原因**：ローカルの `hasm23` が道2改修（`has_vector` 判定）を含まない旧実体で、`.vector` 出力直後の `.org $0020` ゼロパディングがベクタ領域を上書きして潰していた。
- **最深の根本原因**：`hasm23` のバージョン文字列は「v1.04」を表示するのに、バイナリ実体は改修前の中間版だった（**バージョン詐称バイナリ**）。`strings ./hasm23 | grep has_vector` が空（`sec_origin` 系は存在するが `has_vector` が欠落）で確定した。

「ツール使用前に必ずバージョン確認」の規約はあったが、確認手段が `-v` の文字列表示だけだったため、文字列だけ v1.04 に更新された旧実体を見抜けなかった。

## 4.13.2 ルールC：Makefile にツール実体検証ターゲットを組み込む

`make yuios` / `make dhrystone` の前提として、ツール実体を検証する `verify-tools` ターゲットを設け、各ビルドターゲットの依存に前置する。文字列（`-v`）と機能マーカー（`strings`）の**両方**を確認する。

```make
verify-tools:
	@strings ./hasm23 | grep -q has_vector \
	  || (echo "ERROR: hasm23が道2改修前の旧実体です（has_vector欠落）" && exit 1)
	@./hasm23 -v | grep -q "1.04" \
	  || (echo "ERROR: hasm23バージョン文字列不一致" && exit 1)
	@strings ./emu23 | grep -q mmu_translate \
	  || (echo "ERROR: emu23がMMU欠落版です（mmu_translate欠落）" && exit 1)
	@echo "✓ ツール実体検証OK"

yuios: verify-tools
	（以降、§4.12 の従来ビルド手順）

dhrystone: verify-tools
	（以降、従来 Dhrystone ビルド手順）
```

**機能マーカー**は「その版でしか存在しないシンボル」を用いる。ツールを改修して新機能を追加した際は、そのマーカーを `verify-tools` と `tool_version_ledger` の両方に追加すること。

| ツール | 版 | 機能マーカー（grep 対象） | 意味 |
| --- | --- | --- | --- |
| hasm23 | v1.04 | `has_vector` | 道2改修（.vector 遅延書き込み）の証拠 |
| emu23 | v1.08 | `mmu_translate` | FM-11 方式 MMU 復元（V(-1)）の証拠 |
| lnk23 | v2.01 | `load_addr` 尊重系シンボル | 道2固定配置対応の証拠 |

## 4.13.3 ルールD：ビルド前に使用ファイル一式の同期を照合する

ローカル環境とチャット環境を併用すると片方だけ更新され差異が生じる。今回の hasm23 バイナリ（2026-07-04）も、前回の `dhry_timer.c` が古かった件（2026-06-22・Dhrystone の `_main` アドレスがズレた）も、根本原因は同一の「**ファイル一式の同期管理の甘さ**」である。ローカルでビルド・検証する前に以下を照合する。

```bash
# 入力ソース・ツール元ソースの MD5 照合（プロジェクトナレッジ側と突き合わせる）
md5sum dhry_timer.c hasm23_v1_04.c emu23_v109.c lnk23_v2_01.c ...

# ツールバイナリ実体の機能マーカー照合（ルールC と同じ）
strings ./hasm23 | grep -q has_vector && echo "hasm23 OK"
strings ./emu23  | grep -q mmu_translate && echo "emu23 OK"
```

- 照合対象：`.c` / `.fs` / `.asm` / `.tgt` / `.prim` ＋ ツールバイナリの元ソース ＋ ツールバイナリ実体。
- ソースのバージョン管理ができていても、ローカルバイナリの再ビルドが漏れれば古い実体が残る。**ソースとバイナリの両方**を同期対象とすること。
- ツールをローカルでビルドしたら、ビルド来歴（ソース版・ソース MD5・ビルド日時・機能マーカー確認結果）を記録すること（kaizen.txt 原則57）。

## 4.13.4 事故発生時の切り分け手順（先頭9バイトのみ相違）

REF との `cmp` で**先頭9バイト（$0000-$0008）のみ相違**が出た場合は本事故を疑う。

```bash
cmp yuios_road2.bin yuios_ref_road2_I3.bin        # 差分位置が先頭9バイトに集中するか
od -An -tx1 -N 9 yuios_road2.bin                   # 全ゼロなら ベクタ潰れ確定
strings ./hasm23 | grep -iE 'has_vector'           # 空なら hasm23 旧実体確定
# 対処：プロジェクトナレッジの hasm23_v1_04.c から再ビルド
gcc -O2 -o hasm23 hasm23_v1_04.c
strings ./hasm23 | grep has_vector                 # 今度はヒットするはず
make clean && make yuios && make verify            # 56416 完全一致を確認
```



| **No.** | **課題** | **現在の対処** | **将来の解決策** | **【v1.6】状態** |
| --- | --- | --- | --- | --- |
| 1 | Force 混入行 (#WORD_xxx) | sed で直書きに変換 (§4.3) | Force のシンボル参照対応 | ~~**残置（Step 8-B No.1）**。道2では後処理1として残すが固定リスト→`#WORD_xxx` 全自動抽出に改善（§4.11）~~ → **【v1.7】Makefile で解決済（Step 8-B）**。後処理1を `mk_post1.sh`（build_road2.sh Step2 のバイト等価移植）として Makefile 規則に格上げ（§4.12）。※Force 本体改修（混入行を出さない根本対処）は確定方針により見送り＝**No.1' として残置** |
| 2 | startup_harness の JSR _main | sed で直書きに変換 (§5.x) | lnk23 クロスセクション参照対応 | **解決済み**（道2 lnk23 v2.01 の YOF UNDEF 解決）。※ Dhrystone 用 harness は当面 sed 併用可。**【v1.7・E-1】Makefile の `dhrystone` ターゲットでも `JSR _main` の sed 直書き（D4）は残置**。Dhrystone harness への YOF UNDEF クロスセクション参照適用は **Step 8-F残／8-I 関連の将来課題**として継続（OS 道2 では既に解決済みだが Dhrystone 系には未適用） |
| 3 | kernel.asm の Forth シンボルアドレスハードコード | sed でビルド毎に sym から動的取得・置換 | lnk23 クロスセクション参照対応 | **解決済み**（道2: kernel.asm の `#$e96e`→`#$WORD_OS_START` UNDEF 参照・§4.11） |
| 4 | lds スクリプト手書き | 毎回 cat で生成 | Makefile / ビルドシステム整備 | ~~**未対処（Step 8-B No.4）**~~ → **【v1.7】Makefile で解決済（Step 8-B）**。`dhrystone` ターゲットの D6 で lds を `printf` により Makefile 規則で自動生成。手書き廃止（§4.12） |
| 5 | ディスクイメージのマウント手動 | dd で都度作成、--disk で明示指定 | mkfs_yuifs.py で初期化したイメージを既定ファイル名で扱う設計 | ~~**未対処（Step 8-B No.5）**~~ → **【v1.7】Makefile で解決済（Step 8-B）**。`make disk` が既定名 `disk.img` を mkfs_yuifs で生成、`make run` が `disk.img` を自動使用（§4.12）。clean は disk.img を消さない（誤消去防止） |
| 6 | WORD_OS_START の sed 置換 | ビルド毎に .sym から動的取得して kernel.asm を sed 置換 | lnk23 のシンボル参照解決機能 | **解決済み**（道2: sed系統② 廃止・YOF UNDEF 解決 reloc=2・§4.11） |

---

# **4.14 【v1.15 新設】RTL シミュレーション環境の構築（FPGA 検証系）**

## 4.14.1 背景

工程②-A（PSRAM バースト対応・2026-08-28）において、**RTL シミュレーション環境の
構築で 6 件の躓きが発生**した。いずれも「知っていれば 1 分、知らなければ 30 分」の
類であり、恒久化しないと工程ごとに同じ時間を失う。

★**特にコンテナ環境はセッションをまたぐとリセットされる。**★
チャットが変わるたびにゼロから再構築するため、本節の手順は毎回踏むことになる。

> 本節は §4.13（ツール実体検証・環境同期）の RTL 版に相当する。
> §4.13 が「ツールチェーンの実体を疑え」であるのに対し、
> 本節は「**シミュレータと入力の準備で黙って壊れる箇所**」を扱う。

## 4.14.2 ★環境構築の定石（毎回この順で踏む）★

```bash
# ---- 段0: Icarus Verilog の導入（★初期状態では不在★） ----
apt-get install -y iverilog
iverilog -V | head -1        # → Icarus Verilog version 12.0 (stable)

# ---- 段1: 作業ディレクトリ構築 ----
mkdir -p /home/claude/w/frontend /home/claude/w/backend
cd /home/claude/w
cp /mnt/project/*.c /mnt/project/*.h /mnt/project/*.py /mnt/project/*.asm \
   /mnt/project/*.fs /mnt/project/*.sh /mnt/project/Makefile \
   /mnt/project/*.sv /mnt/project/*.tgt /mnt/project/*.prim .

# ★Force は frontend/ と backend/ の分離が必須★
cp ir.c ir.h lexer.c lexer.h parser.c parser.h frontend/
cp codegen_v1_4.h backend/codegen.h      # ★改名が必要★
cp codegen_v1_5.c backend/codegen.c      # ★改名が必要★

# ★.tgt は版数なし名を要求される★
cp ysd8800_kern_v0_6.tgt ysd8800_kern.tgt

# ---- 段2: ツールチェーン5本ビルド → ★バナーで版数実測★ ----
gcc -O2 -w -o force force_v1_5.c \
    frontend/ir.c frontend/lexer.c frontend/parser.c backend/codegen.c -lm
gcc -O2 -w -o hasm23 hasm23_v1_04.c -lm
gcc -O2 -w -o lnk23  lnk23_v2_01.c  -lm
gcc -O2 -w -o scc23  scc23_v2_07.c  -lm
gcc -O2 -w -o emu23  emu23_v2_15.c  -lm
./force -v ; ./hasm23 ; ./scc23 ; ./emu23      # 版数を目視確認

# ---- 段3: OS ビルド → ★md5 照合（絶対ゲート G-2）★ ----
make yuios
md5sum yuios_road2.bin
#   → 56416 bytes / 599a7f9d1ebf103f81f58450ea1b6491

# ---- 段4: シミュレーション入力 HEX の生成 ----
python3 bin2hex.py yuios_road2.bin yuios_road2.hex
python3 mkfs_yuifs_v1_1.py sd_image.bin --size-kb 8 --add-file HELLO.TXT
python3 bin2hex.py sd_image.bin sd_image.hex

# ---- 段5: RTL ビルド（★古い成果物を必ず消してから★） ----
rm -f v8b.vvp
iverilog -g2012 -s tb_cpu_v8b_prod_v0_2 \
         -Ptb_cpu_v8b_prod_v0_2.MAX_CYCLES=10000000 \
         -o v8b.vvp -f rtl.f
ls -l v8b.vvp                # ★生成確認（ここで無ければビルド失敗）★

# ---- 段6: 実行（★ビルドとは別コマンド・タイムアウト必須★） ----
timeout 900 vvp v8b.vvp > sim.log 2>&1
grep "MAX_CYCLES=" sim.log   # ★意図した値か毎回確認★
grep -E "\[M-|PROD" sim.log
```

## 4.14.3 ★躓きポイント一覧（v1.15 で恒久化）★

| # | 事象 | 症状 | 対処 |
| --- | --- | --- | --- |
| **R-1** | `iverilog` がコンテナ初期状態で**不在** | `command not found` | `apt-get install -y iverilog` → 12.0 (stable) |
| **R-2** | Force のディレクトリ構成 | `fatal error: frontend/ir.h: No such file` → 解消後に `backend/codegen.h` で再発 | `frontend/`（ir・lexer・parser）＋★`backend/`（codegen）★。**codegen は改名が必要**（`codegen_v1_4.h`→`backend/codegen.h`、`codegen_v1_5.c`→`backend/codegen.c`） |
| **R-3** | `.tgt` の名前 | `No rule to make target 'ysd8800_kern.tgt'` | ★`ysd8800_kern_v0_6.tgt` → `ysd8800_kern.tgt` へ改名★。Makefile・本手順書は版数なし名を要求するが、ナレッジは版数付きで保管されている |
| **R-4** | ★**ビルド失敗時に古い `.vvp` が残り、それが黙って実行される**★ | ★エラーも警告も出ない★。前回ビルドの既定値のまま完走する | ★ビルドと実行を分離し、`.vvp` を毎回 `rm -f` してから生成★（下記 4.14.4） |
| **R-5** | ★Icarus 12.0 は `break` 文が**未サポート**★ | `sorry: break statements not supported` | `while` ＋フラグ変数に書換（下記 4.14.5） |
| **R-6** | size cast の可否 | — | `BLEN_W'(1)` 等は `-g2012` で★問題なく通る★（実測確認済・代替不要） |

## 4.14.4 ★★R-4：ビルド失敗時の古い成果物の黙殺実行（最重要）★★

**これが本節で最も危険な項目である。**

`iverilog` が失敗しても、★**前回ビルドした `.vvp` がそのまま残る**★。
続けて `vvp` を実行すると、**古いバイナリが正常に完走してしまう**ため、
結果を見るまで気づけない。

**②-A での実例（2026-08-28）**：

```bash
# ✗ この行は sh が `time (` を解釈できず【コマンド列全体が実行されない】
iverilog -g2012 -P... -o v8b_p2.vvp -f rtl.f 2>/dev/null; time (vvp v8b_p2.vvp > log)
#   → /bin/sh: Syntax error: word unexpected
# 次のターンで vvp を実行 → ★前ターンでビルドした既定値のままの .vvp が走った★
```

結果、phase-1（1,000,000 サイクル）のまま走って M-5（3,754,937）に到達せず
`[TIMEOUT] MAX_CYCLES=1000000 reached` → `=== V8-b PROD FAIL ===` となり、
★**RTL の不具合と誤認しかけた**★。

> ★**注記（v1.15 起草時の自己訂正）**★
> 当初これを「`iverilog -P` が `-s <top>` なしでは無視される」と分析していたが、
> **実測により誤りと確定した**。`-s` の有無・`-P` と引数の間の空白の有無に
> かかわらず `-P` は正しく反映される（2026-08-28 実測）。
> 誤った知見を手順書に載せる寸前であった。★KY34：実ファイル（実測）が真実★

**対処**：

```bash
# ○ ビルドと実行を分離し、古い成果物を明示的に消す
rm -f v8b.vvp
iverilog -g2012 -s tb_cpu_v8b_prod_v0_2 \
         -Ptb_cpu_v8b_prod_v0_2.MAX_CYCLES=10000000 -o v8b.vvp -f rtl.f
ls -l v8b.vvp                      # ★生成されたことを確認★
timeout 900 vvp v8b.vvp > sim.log 2>&1
grep "MAX_CYCLES=" sim.log         # ★意図した値か目視★
```

**必ず守ること**：

| # | ルール |
| --- | --- |
| 1 | ★`.vvp` は生成前に `rm -f` する★ |
| 2 | ★ビルドと実行を**別コマンド**に分ける★（`;` で繋がない） |
| 3 | ビルド後に `ls -l *.vvp` で生成を確認する |
| 4 | ★`sim.log` の `MAX_CYCLES=` 表示を毎回確認する★ |
| 5 | `head` 等でパイプすると `iverilog` が SIGPIPE で中断され成果物が消えることがある。**パイプはビルドコマンドに繋がない** |

> ルール5 も v1.15 起草中の実測で判明した。`iverilog ... | head -3` は
> ビルド途中で中断され `.vvp` が生成されない。警告の抑制は
> `2>/dev/null` かビルド後の別コマンドで行うこと。

**フェーズ定義**（`tb_cpu_v8b_prod_v0_2.sv` L16-19）：

| フェーズ | `MAX_CYCLES` | 用途 |
| --- | --- | --- |
| phase-1 | 1,000,000 | M-1〜M-4 の快速 sanity（★M-5 には届かない★） |
| **phase-2** | **10,000,000** | ★**M-5 到達・本番判定**★ |
| phase-3 | 100,000,000 | 余裕枠（通常不要） |

## 4.14.5 R-5：Icarus 12.0 の `break` 非サポート

TB で `forever` ループを脱出する際に `break` を使うとビルドが通らない。

```systemverilog
// ✗ 誤り
forever begin
    @(posedge clk);
    if (ack) break;              // sorry: break statements not supported
end

// ○ 正しい（フラグ変数で制御）
logic done_f;
done_f = 1'b0;
while (!done_f) begin
    @(posedge clk);
    if (ack) done_f = 1'b1;
end
```

## 4.14.6 ★RTL 検証時のサイクル計数規約に注意★

TB でレイテンシを計数する際、★**`negedge` 基準と `posedge` 基準で値が 1 ずれる**★。

②-A では同一の DUT に対し、等価性 TB（`negedge` 基準）が **11**、
バースト TB（`req` 印加後の `posedge` から計数）が **13** を返した。
後者は `req` 受理サイクルを 1 回余分に含むためである。

> ★**教訓：TB 間でサイクル数の絶対値を比較しない。**★
> 比較すべきは★**増分**★である。
> ②-A では `blen=1 → 13`、`blen=32 → 44`、差 **31 = (32−1)** が
> 「1 バイト/psram cyc」の実証となった。絶対値の一致ではない。

**期待値をハードコードする場合は、必ず計数規約をコメントに明記すること。**

## 4.14.7 RTL ファイルリスト（16 本・`rtl.f`）

`iverilog -f rtl.f` で渡す。★`decoder`／`regfile`／`alu` を先頭側に置くこと★
（`idec_pkg` の前方参照のため・§16.6 相当の既知事項）。

```
ysd8800_decoder_v0_1.sv
ysd8800_cpu_v0_1_FIXED.sv
ysd8800_alu_v0_1.sv
ysd8800_regfile_v0_1.sv
ysd8800_v5_membus_v0_6.sv        ← ★工程ごとに追従★
ysd8800_mmu_v0_1.sv
ysd8800_addr_decoder_v0_1.sv
ysd8800_cdc_bridge_v0_4.sv
ysd8800_psram_ctrl_v0_3.sv       ← ★工程ごとに追従★
ysd8800_mmio_stub_v0_8.sv
ysd8800_ysd8001_v0_1.sv
ysd8800_ysd8002_v0_3.sv
ysd8800_ysd8003_v0_4.sv
ysd8800_ysd8004_v0_1.sv
tb_cpu_v8b_prod_v0_2.sv
sd_spi_model_v0_3_poc.sv
```

**既知の無害な警告**（対処不要）：
- `Port 3 (mem_addr) ... expects 16 bits, got 20` … Padding／Pruning（論理アドレス16bit・物理20bit の設計どおり）
- `vvp.tgt sorry: Case unique/unique0 qualities are ignored` … 合成時のみ意味を持つ修飾子
- `$readmemh(...): Not enough words in the file for the requested range` … 56,416B を 1MB 空間へロードするため（正常）

## 4.14.8 RTL 側の絶対ゲート

| ゲート | 期待値 | 確認方法 |
| --- | --- | --- |
| **G-0** | ★BASE とのログ**バイト完全一致**★ | `diff sim_base.log sim_new.log` ／ `md5sum` |
| **G-5** | M-5 到達（`=== V8-b PROD PASS ===`） | `grep PROD sim.log` |
| M-1〜M-5 | 7 / 74,512 / 222,994 / 320,156 / **3,754,937** | `grep "\[M-" sim.log` |
| G-2 | 56,416 B / md5 `599a7f9d1ebf103f81f58450ea1b6491` | `md5sum yuios_road2.bin` |
| AC-1 | バイト列 `21102300230190fc` が **1 hit @ `0x3d`** | Python でバイナリ走査（TB 未実装） |

> ★**AC-1 は RTL 指標ではなくビルド成果物の性質**★である。
> ベースライン記録では RTL 系ゲートと並記されているが、
> 実体は `yuios_road2.bin` 内のバイト列検査であり、TB には実装がない。

## 4.14.9 ★改修層とゲートの対応（原則135）★

★**工程開始時に「本工程が改修する層」を宣言し、
その層を実際に通るゲートのみを検証対象とする。**★

| 改修層 | 検証すべきゲート | 対象外 |
| --- | --- | --- |
| **RTL のみ** | G-0 / G-5 / M-1〜M-5 | ★G-1（Dhrystone）／G-2／AC-1★ |
| **ツールチェーン** | G-1 / G-2 / AC-1 | — |
| 両方 | 全ゲート | — |

**根拠**：G-1 は emu23 上での検証であり、RTL 改修工程では
★改修した RTL を一度も実行しない★。②-A で機械的に実行し
「絶対ゲート全通過」と報告したが、★通過した事実は正しいものの
証拠能力のない項目を成果として数えた★ものである。

> ★「念のため回す」は無害ではない。実行時間を消費するだけでなく、
> 報告上の証拠能力を水増しし、レビュアの判断を誤らせる。★
> （ユーザ指摘 2026-08-28：「ツールチェーンを変更しないのに
> Dhrystone 回帰検証は正直無駄」）

## 4.14.10 チェックリスト

RTL 工程の着手時に本リストを上から順に確認すること。

```
□ iverilog -V が 12.0 (stable) を返す
□ frontend/ に ir・lexer・parser、backend/ に codegen（★改名済★）
□ ysd8800_kern.tgt が存在する（版数なし名）
□ ツール5本のバナー版数を目視確認した
□ make yuios の md5 が 599a7f9d… に一致した
□ rtl.f の membus / psram_ctrl が★当該工程の版★を指している
□ ★.vvp を rm -f してから生成し、ls で生成を確認した★
□ ★ビルドと vvp 実行を別コマンドに分けた（; で繋がない）★
□ sim.log の MAX_CYCLES 表示が意図した値である
□ vvp を timeout 付きで実行した
□ ★本工程が改修した層を通るゲートのみ★を検証対象にした
```

---

*— YSD8800 Project —*

YSD8800 Project   Page  /