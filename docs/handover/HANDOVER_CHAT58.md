# HANDOVER_CHAT58.md — YUI OS Ph.6 Shell 実装（途中）引継ぎ

| 項目 | 内容 |
|---|---|
| 作成日 | 2026-06-19（CHAT58） |
| 現工程 | Step 8-Y / YUI OS Ph.6 Forth常駐Shell 実装フェーズ |
| 前提版 | kernel_forth v0.10.16（Ph.5 Step4完成・CHAT57） |
| 本チャット成果版 | **kernel_forth v0.10.17**（テスト分離 + Shell phase1/2） |
| ツール | scc23 v1.04 / hasm23 v1.02 / lnk23 v2.00 / emu23 v1.05 / Force v1.5 / mkfs_yuifs v1.1 / tgt v0.6 |

---

## 1. 本チャットで完了したこと

### 1.1 Ph.6 Shell設計レビュー完了（承認）
- `yuios_ph6_shell_design_v1_1.md` が **再レビューで条件なし承認**（review v1.1）。
- M-1（GETC単一クライアント）・M-2（LOAD-SLOT-BUSY解放）は CHAT57 で実機実証済。

### 1.2 テストワード分離（辞書3093B回収）
- 未起動デッドコード（OS-START起動列外）を本番ソースから分離：
  MEM-TEST-TASK / UART-TEST群 / STOR-TEST群 / DIAG群 / PUTC-HEX1・HEX4 / BC-STR(CONSTANT)。
- 退避先: **`kernel_forth_tests_v0_10_16.fs`**（検証時はここから本体へ戻す）。
- 効果: 辞書実終端 素版 $C16F→$B55A（**3093B=3.02KB 回収**）。
- ⚠️ **教訓（重要）**: Forthワードの削除範囲は「次の定義(`:`/`CODE`)まで」で取ると、間にある VARIABLE宣言や本番コメントを巻き込む。**必ず本体終端の `;` / `END-CODE` で範囲を取ること**。本チャットで2回誤削除（FM-WK変数群・MEMCPY-B巻き込み）→都度破棄して仕切り直した（本番への実害なし）。

### 1.3 Ph.6 Shell phase1+2 実装
- **実装コマンド: `help` / `run <name>` / `ps`**（設計§9.2の8コマンド中3つ）。
- ワード構成: SHELL-TASK(tid=6) / SH-READLINE(行入力・BS対応・NUL終端) / SH-PARSE(cmd+arg1分解) / SH-STR=(NUL終端比較) / SH-DISPATCH / SH-CMD-HELP/RUN/PS / SH-EMIT-TID(tid 0-15の10進出力・除算不使用)。
- バッファ配置（設計のVARIABLE化方針に対する**実装注記**）: 65B等の可変長バッファは Force VARIABLE では確保困難なため、**DATA域上端 $DC60-$DCF3 に CONSTANT固定アドレスで確保**。VARIABLE自動配置(下から上昇)と非衝突。
  - SH-PS-BUF=$DC60(32B) / SH-CMD-BUF=$DC80(16B) / SH-ARG-BUF=$DC90(16B) / SH-PROMPT-BUF=$DCA0 / SH-RUN-KW=$DCA6 / SH-HELP-KW=$DCAA / SH-LINE-BUF=$DCB0(65B,→$DCF0) / SH-PS-KW=$DCF1(3B)。
- OS-START に `SHELL-START`（PROCMGR-START直後・tid=6）を追加。

### 1.4 実証結果（emu23）
| 項目 | 結果 |
|---|---|
| 非回帰 | `0123MD`（FileMgrマウントマーカー）不変 |
| プロンプト | `YUI> ` |
| help | `run <n>` / `ps` / `help` 表示 |
| ps | `0 1 2 3 4 5 6`（稼働tid一覧） |
| run FIB | `F55`→プロンプト復帰 |
| run FIB 2回連続 | 2回とも `F55`（繰り返し成立） |
| 異常系（不一致名"fib"） | `!`表示・Shell継続 |

- 最終ビルド: yuios_v0_10_17.bin = 56416B / 1080 symbols / WORD_OS_START=$C62E。
- **辞書実終端 $C640・天井$D3FF まで余裕 3519B（3.44KB）**（分離前+Shellは455Bだった→約7.7倍）。

---

## 2. 次チャットでやること（順序）

1. **残りShellコマンド実装**（設計§9.2の未実装5個）:
   - `ls`（FILE_LIST → FileMgr）
   - `cat <file>`（FILE_OPEN+READ → FileMgr）
   - `kill <tid>`（PROC_KILL → ProcMgr）
   - `mem`（MEM_QUERY → MemMgr）
   - `ver`（OSバージョン表示・Shell内蔵）
   - 各コマンド追加ごとに **.sym辞書実終端≦$D3FF・VAR境界≦$DCFF を機械実測（KY/O-2早期補正）**。1変更1検証。
2. **起動メッセージ実装**（全コマンド実装後）:
   - 1行目 `YUIOS Booted!` を各サービス起動で分割表示。**文字片配分（区切り重視案・当初提案で確定）**:
     | 起動点 | 文字片 | 累積 |
     |---|---|---|
     | カーネル | `YUI` | YUI |
     | MemMgr | `OS ` | YUIOS |
     | UART | `Boo` | YUIOS Boo |
     | Storage | `ted` | YUIOS Booted |
     | FileMgr | `!`+改行 | YUIOS Booted! |
     | ProcMgr | `YUKARI Semiconductor Devices.`+改行 | （2行目） |
   - 出力手段は **`emit-char`**（カーネル直UART・ドライバ起動前後問わず使用可）。各STARTワードは改変せず **OS-START内で各START呼び出し直後に文字片をemit**（影響範囲最小）。
   - **`0123MD`（FileMgrマウントマーカー）は条件付き化**: 通常抑制・デバッグ時のみ出力（デバッグフラグ判定を追加）。
   - メモリ見積り: 約150〜250B（辞書余裕3.5KB内で問題なし）。

---

## 3. 重要な申し送り

- **(申1) ビルド手順**: exectest/probe/Shell いずれも、build スクリプトの Step3 sedラベル置換リストに対応ラベル追加が必須。Shellは **`WORD_SHELL_TASK`**（本番ビルド恒久）。手順書 yuios_build_procedure の改版要。
- **(申2) ファイル名大小文字**: FileMgr/FS は**大小文字を区別**。disk格納名 "FIB" に対し `run FIB`（大文字）でないとOPEN失敗（`!`表示）。将来 Shell側で大文字化 or FS側 case-insensitive 化は別途判断（設計書注記候補）。
- **(申3) サイズ見積りの実態**: 設計§9の楽観値1.42KBに対し、Shell phase1+2（help/run/ps）で**約3.7KB**消費（review E-1の懸念が的中）。残り5コマンド実装にはテスト分離(本チャット完了)が前提だった。
- **(申4) VAR域逼迫**: VARIABLE自動配置(VAR_*)が phase2時点で $DC5E まで上昇、SH-PS-BUF($DC60)の **2B手前**。**今後 VARIABLE を増やす場合は DATA域再配置が必要**（ls/cat等で新VARが要るなら要注意）。SHバッファはCONSTANT固定なのでVAR増加と独立だが、新規VARIABLEは$DC60に到達しないか毎回実測。
- **(申5) 退避テストの復活手順**: 検証で MEM/UART/STOR-TEST が必要になったら `kernel_forth_tests_v0_10_16.fs` の該当ブロックを本体へ戻し、OS-STARTに該当 -TEST-START を追加、sedリストに該当ラベル追加。
- **(申6) tid監視**: Shell=tid6・run子プロセス=tid7 まで安全圏。tid8以降データスタック$FC00超は別KY継続（HANDOVER_CHAT54 §6）。

---

## 4. 成果物一覧（/mnt/user-data/outputs/）

| ファイル | 内容 |
|---|---|
| `kernel_forth_v0_10_17.fs` | **本番ソース**（テスト分離済 + Shell phase1/2）|
| `kernel_forth_tests_v0_10_16.fs` | 分離したテストワード退避ファイル |
| `shell_block_v0_10_17.fs` | Shellブロック単体（参考・差し込み元）|
| `HANDOVER_CHAT58.md` | 本文書 |

※ design_inventory・進捗チャット(latest)日報・プロジェクトナレッジ登録（v0.10.16/v0.10.17・CHAT57/58 HANDOVER・Shell設計書v1.0/v1.1・review群）が**未反映の停滞警告継続**。次チャット開始時に確認推奨。

---

## 5. 未解決・保留

- 設計書 yuios_ph6_shell_design への「実装注記」反映待ち: バッファCONSTANT固定化（VARIABLE化からの実装上の変更）、サイズ実測3.7KB、ファイル名大小文字、VAR域逼迫。次チャットで設計書改版（v1.2）として追記推奨（KY41）。
- yuios_design v2.7 §9.2 の8コマンド完全実装はまだ（3/8）。
