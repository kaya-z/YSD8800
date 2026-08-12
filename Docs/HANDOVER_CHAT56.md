# HANDOVER_CHAT56.md

YSD8800 / YUI OS プロジェクト チャット間引継ぎ文書
**作成日: 2026-06-18 (CHAT56)**
**工程: Step 8-Y YUI OS 本格実装 / Ph.5 ProcMgr / Step4 実装フェーズ**

---

## §0. 本チャット(CHAT56)サマリ

CHAT55 で確定した memmap v2.4（案D-ε・承認済）に基づき、$C000→$D400 移設の**実装フェーズ前半**を完遂した。
依存順 1〜3（scc23・crt0・kernel_forth）のうち、**1〜3 すべて完了**。
残りは Forth 常駐 Shell（Ph.6）と Step4 本体（$D400 へ fib ロード→暴走解消実証）。

本チャットは**ログ容量懸念により Step4 本体着手前で区切り**、次チャット(CHAT57)へ引き継ぐ。

---

## §1. 本チャットで完了した作業

### (A) scc23 v1.04 ソース成果物出力（前チャット完成分の正式出力）
- 前チャット(CHAT55)で実装完了していた scc23 v1.04 のソースを正式に成果物出力。
- 内容（再掲）: ワーク変数 $C7E8系→$DBE8系（+$1400・12定義）、CLI 既定値 CODE $D440/RUNTIME $D780/DATA $DA80、後方互換維持（--code-org 等で旧値指定可）。
- 検証再確認: $C7E8系残存ゼロ、バナー `scc23 v1.04 (2026-06-17)`、既定 .org=$D440/$D780/$DA80。

### (B) crt0 新版: startup_proc v1.1（$D400化）★本日主成果1
- **`.org $C000`→`$D400`**（エントリ番地・実コード変更1点）。
- ヘッダ v1.0→v1.1、KY41 旧記述保持。TASK_EXIT=$0460 はカーネル固定番地として保持（移設対象外）。
- 論理（main復帰→TASK-EXIT）は v1.0 から不変。
- **結合方式＝方式B 確定**（かやぬま承認）: crt0(.org $D400) と scc23 v1.04 出力(.org $D440・CODE-ORG) を lnk23 で2セクション結合。crt0 の `JSR _main` は scc23 出力の `_main` 実体アドレスを .sym から取得して直書き。
- **二段構成を正式採用**（crt0使用・かやぬまと合意）。理由: ①main復帰の正常処理（TASK-EXIT）は必須、②OS/コンパイラの責務分離（scc23 を OS非依存に保ち移植性確保）、③MMU対応(Level 2)で crt0 が初期化コード(BSS/引数/TLS等)の正規の置き場所になる。OS-9 の cstart→F$Exit と同じ定石。

### (C) crt0+fib 結合検証（方式B実証）
- fib.c を scc23 v1.04 でコンパイル（既定 $D440/$D780/$DA80）。
- `_main` 実体アドレス = **$D5E3**。
- crt0 の `JSR _main`→`JSR $D5E3` 直書き → アセンブル成功。
- lnk23 で crt0($D400)→fib($D440) 結合（SECTION順: crt0先・fib後）成功（43 symbols）。
- 配置実測: `_proc_entry=$D400` / `_fib=$D443` / `_main=$D5E3`。crt0のJSR先 = _main実体 一致。

### (D) kernel_forth v0.10.15 フルビルド（$D400化）★本日主成果2
- **PROC-LOAD-ADDR `$C000`→`$D400`**（CONSTANT・1点集約。参照箇所FILE-READ宛先/TASK-CREATEエントリは定数経由で自動追従）。
- ヘッダ v0.10.14→v0.10.15、KY41 記録。MemMgr 5定数（PAGE-POOL-BASE=$DD00等）は v0.10.14で移設済・本版変更なし。
- フルビルド6ステップ全PASS（Force v1.5→hasm23 2pass→kernel.asm WORD_OS_START更新→lnk23）。
  - yuios_v0_10_15.bin（56404B）/ yuios_v0_10_15.sym（1023sym）生成。
- ビルド実測: WORD_PROCMGR_TASK=$c0a7、WORD_OS_START=$c150。

### (E) 検証結果
- PROC-LOAD-ADDR反映: `EQU $D400`、FILE-READ/TASK-CREATE が `LDW A, #$D400`×2 で追従 ✅
- 辞書終端 vs ロード領域: 辞書系$c150 / load$D400 → **分離（余裕4784B）＝$C000衝突解消** ✅
- **OS起動 stdout = `0123MD`**（ベースラインv0.10.14と完全一致＝5サーバ正常起動の証拠）✅
- 起動 exit=0（暴走/HALTなし）、disk.img非破壊（非ゼロ16B＝mkfs由来のみ）✅
- Dhrystone回帰: 対象外（kernelソース定数変更でコンパイラ改修ではない・前回v2.2と同判断）。OS起動非回帰で代替。

---

## §2. 成果物（本チャット出力）

| ファイル | 版 | 内容 |
|---|---|---|
| scc23_v1_04.c | v1.04 | C コンパイラ（前チャット完成分・正式出力） |
| startup_proc_v1_1.asm | v1.1 | crt0（.org $D400・方式B結合対応）★本日 |
| kernel_forth_v0_10_15.fs | v0.10.15 | カーネルForth層（PROC-LOAD-ADDR $D400）★本日 |
| build_v0_10_15.sh | — | フルビルドスクリプト（v0.10.15用）★本日 |

※yuios_v0_10_15.bin/.sym はビルド生成物（再現可能のため未出力）。次チャットで build_v0_10_15.sh により再生成可。

---

## §3. 次チャット(CHAT57)でやること【Step4 実装フェーズ後半】

memmap v2.4 §15.7 の依存順 4〜5：

4. **Forth 常駐 Shell 実装（Ph.6）**
   - 辞書約1.4KB（楽観値・+30%=1.85KB／残余裕2.9KB）。
   - **.sym 早期補正**（O-2 前提）: 最初の2〜3コマンド実装時点で辞書終端を実測補正（memmap v2.4 §15.10）。
   - Level 1 では Shell を Forth 常駐とし、C プロセス領域($D400-$DBFF)を子プロセス専用1スロットにすることで `run` を成立させる。

5. **Step4 本体再開**（最終実証）
   - $D400 リンク版 fib をディスクへ格納（**lnk23出力は$0000基点絶対イメージ。$D400-$DA20の実体部 約$620≒1568B を切り出してFILE格納**＝本チャットの発見事項・申し送り）。
   - ProcMgr 経由（PROC_EXEC/PROC_WAIT）で $D400 へ FILE_READ→TASK-CREATE→実行。
   - **`Unknown opcode ff at c191` 暴走が解消することを確認**（=$C000衝突解消の最終実証・memmap v2.4 §15.9）。

---

## §4. 申し送り事項（重要）

### (申1) ディスク格納時の切り出し（Step4本体の要点）
lnk23 出力(proc_fib.bin等)は **$0000 基点の絶対イメージ**（先頭$0000-$D3FFはパディング）。
ProcMgr は PROC-LOAD-ADDR($D400) へ FILE_READ するため、**ディスク格納すべきは $D400 以降の実体部のみ**（fib例で $D400-$DA20＝約1568B）。
全イメージ(55841B)をそのまま格納するのは誤り。Step4本体で切り出し処理（Python等）が必要。
※fib実測サイズ1569B（memmap v2.4 §15.10記載値とほぼ一致）。C プロセス領域2KB枠の約8割使用＝1KB縮小不可。

### (申2) crt0先頭($D400)とmain($D440)のギャップ
crt0実コードは12バイト（$D400-$D40B）。$D440まで$34(52B)空き。
scc23出力先頭の `JMP _main`($D440) は crt0使用時デッドコード（crt0が直接_main実体$D5E3を呼ぶため制御が来ない・無害）。

### (申3) tid8以降データスタック$FC00超問題
HANDOVER_CHAT54 §6 の既知事項。本作業のスタック域不変につき本工程対象外だが、別KYとして継続管理（memmap v2.4 §15.8）。

### (申4) ビルド時の注意
- Force は frontend/(ir,lexer,parser)+backend/(codegen) のディレクトリ構成でビルド: `gcc -O2 -I. -o force force.c frontend/ir.c frontend/lexer.c frontend/parser.c backend/codegen.c`（codegen_v1_5.c→backend/codegen.c、codegen_v1_4.h→backend/codegen.h）。
- kernel_v12_7.asm の WORD_OS_START 参照はハードコード `$e96e`（プレースホルダ）。build script の Step5 が Force 出力 .sym の実値へ動的置換する。

---

## §5. ツールバージョン台帳（2026-06-18時点）

| ツール/ファイル | 版 | 備考 |
|---|---|---|
| scc23 | **v1.04** | ワーク変数$DBE8系・既定$D440/$D780/$DA80 |
| startup_proc (crt0) | **v1.1** | .org $D400（★本日更新）|
| kernel_forth | **v0.10.15** | PROC-LOAD-ADDR $D400（★本日更新）|
| Force | v1.5 | 変更なし |
| hasm23 | v1.02 | 変更なし |
| lnk23 | v2.00 | 変更なし |
| emu23 | v1.05 | 変更なし |
| ysd8800_kern.tgt | v0.6 | 変更なし（DATA-START $DC00）|
| ysd8800.prim | v1.1 | 変更なし |
| kernel (ASM) | v12_7 | 変更なし |
| mkfs_yuifs | v1.1 | 変更なし |
| yuios_design | v2.7 | Level 1/2区分 |
| yuios_memmap_design | v2.4 | 案D-ε（承認済）|

---

## §6. 本日のKY活動（2026-06-18）

**危険**: crt0の.orgを$D400に変えるだけと早合点し、crt0内の絶対番地（SP初期値・ワーク番地・TASK_EXIT戻り先・エントリ）を$C000系のまま取り残し、ビルドは通るが実行時サイレント・コラプション。
**防止策**: ①着手前に全絶対番地をgrep棚卸し・対応表化、②memmap v2.4対応表を一次情報に1変更1検証、③改修後.sym実測で$C000系残存ゼロを機械確認。
**結果**: crt0はSP/X初期化を持たない（TCB復元前提）設計のため、実コード変更点は`.org`1点に集約と判明。kernel_forthもMemMgr既移設済でPROC-LOAD-ADDR 1点のみ。取り残しなく完遂。

---

## §7. セッション規律メモ
- 設計→レビュー→承認→実装の順守（方式B・二段構成はかやぬま承認後に着手）。
- KY41 4点整合（ファイル名・Version・ヘッダ・改版履歴）を全成果物で遵守。
- 見えた異常（Forthコメント記号誤り `\\\\`、sed行番号ズレ）は都度即潰した。
