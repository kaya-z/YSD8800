# 設計レビュー指摘書

## YUI OS Ph.6 Forth 常駐 Shell 設計書 v1.0

| 項目 | 内容 |
|---|---|
| **指摘書ファイル名** | yuios_ph6_shell_design_v1_0_review_v1_0.md |
| **Version** | v1.0 |
| **査読対象** | yuios_ph6_shell_design_v1_0.md（v1.0 / ドラフト・レビュー前） |
| **査読日** | 2026-06-18 |
| **査読方法** | プロジェクトナレッジ一次確認（kernel_forth v0.10.15/16・UART-PUTS-IMPL・PROC-EXEC-IMPL・inject_exectest・yuios_tcb_design v1.3・yuios_design v2.7）＋ IPC4 経路の机上検証 |
| **判定** | **条件付き差し戻し**（M-1／M-2 の解消を承認の前提とする） |
| **分類凡例** | M=必須修正 / C=確認推奨 / D=査読確認 / N=情報 / E=評価 |

---

## 1. 総評

Forth 常駐 Shell という方向性（memmap v2.4 §15.4 の run 成立条件）と、既存 IPC4 サービスを 2B
トークンのラッパで呼ぶだけで成立させる設計思想（§3）は妥当で、実体（op 定数・IPC4-CALL 作法・
UART-PUTS-IMPL の NUL 終端・PROC-EXEC-IMPL の経路）もおおむね正確に把握されている（E-1）。

ただし、本設計が下敷きにした exectest は **「一度 PROC_EXEC→PROC_WAIT して TASK-EXIT する使い捨て
タスク」**であり、Shell は **「UART 入力を待ち続ける無限対話ループ」**である。この**動作モデルの差**
から来る構造的問題が 2 点あり、いずれも承認前に解消すべき（M-1：Shell の UART-GETC 入力待ちと
ドライバの待機機構の単一性、M-2：run 中の Shell ブロックと子プロセス実行の協調）。

---

## 2. 実体照合（プロジェクトナレッジ一次情報）

| 設計書の前提 | ナレッジ実体 | 判定 |
|---|---|---|
| UART-PUTC-OP=$0401／GETC=$0402／PUTS=$0403 | kernel_forth_v0_10_15.fs 該当 CONSTANT 一致 | OK |
| PROC-EXEC-OP=$0301／WAIT=$0303／LIST=$0304 | yuios_design v2.7 §8.3 一致 | OK |
| UART-PUTS-IMPL は NUL 終端文字列送信 | kernel_forth_v0_10_15.fs UART-PUTS-IMPL（`DUP C@ DUP 0= IF...EXIT`）＝NUL 終端 | OK |
| IPC4-CALL 戻り `>R DROP DROP DROP R>` で r0 のみ | inject_exectest 実証作法と一致 | OK |
| run 経路（EXEC→WAIT）は exectest と同一 | inject_exectest.py の PROC-EXEC-TEST と一致 | OK |
| TID 取得 UART-DRV-TID=$FC5C／PROC-TID-ADDR=$FC6A | kernel_forth 一致（PROC-TID-ADDR=$FC6A 確認） | OK |
| STRCMP 専用ワード無し | grep 確認済（設計書 N-2）→ Shell 内で固定長比較を実装する方針は妥当 | OK |

実体把握は正確。問題は実体の有無でなく、Shell の動作モデルに起因する協調設計（下記 M）。

---

## 3. 指摘事項

### M（必須修正）

#### M-1：Shell の UART-GETC 入力待ちと UART ドライバの単一待機機構（UART-WAIT-TID）の競合

| 項目 | 内容 |
|---|---|
| **該当** | §5.1 SH-KEY / §5.2 SH-READLINE / §3 UART_GETC |
| **区分** | M |

**事実（実体）**：UART ドライバの GETC 待機機構（UART-GETC-IMPL）は、待機クライアント tid を
**単一の変数 `UART-WAIT-TID` に 1 つだけ**保持する（kernel_forth_v0_10_15.fs）。バッファ空のとき
`DUP UART-WAIT-TID !` で待機 tid を登録し、IRQ 受信時にその 1 タスクを起こす設計。

**問題**：Shell（tid=6）が `SH-READLINE` で `SH-KEY`＝UART-GETC を呼び continuous に入力待ちする。
これは「UART-WAIT-TID に常時 Shell の tid が入った状態で対話が回る」ことを意味する。これ自体は
単一クライアント（Shell のみが GETC する）なら成立するが、**設計書はこの前提（GETC するのは
Shell ただ 1 タスクに限る）を明示していない**。将来 run した C プロセスが getchar（UART_GETC）を
呼ぶと、UART-WAIT-TID が上書きされ、Shell と子プロセスのどちらか一方しか入力を受け取れない
（取りこぼし・デッドロック）。

**さらに確認すべき点**：exectest は GETC を一切使わず PUTC のみだったため、この経路は **CHAT57 で
未実証**である。Shell の SH-READLINE が UART-GETC を介して実際に行入力できることは、本 Ph.6 で
**初めて通る経路**。設計書 §9 回帰計画にも GETC 経路の単体実証項目がない。

**推奨対応**：
- §3 または §5.2 に「Level 1 では UART_GETC を発行するのは Shell ただ 1 タスクである」ことを
  **不変条件として明記**。run した C プロセスが getchar を使う場合の扱い（Level 1 では子プロセスの
  stdin は非サポート、等）を §1.4 非目標に追記。
- §9 回帰計画に「SH-READLINE 単体実証（数文字入力→エコー→Enter 確定→SH-LINE-BUF 内容確認）」を
  **最優先項目**として追加。run 実証（§7.1）の前段に置く。GETC 経路が未実証である事実を §2 に明記。

#### M-2：run 中の Shell（tid=6）ブロックと UART ドライバの協調——'F55' 出力経路の確認

| 項目 | 内容 |
|---|---|
| **該当** | §5.4 SH-CMD-RUN / §7.1 正常系 |
| **区分** | M |

**事実**：`run fib` 時、Shell は PROC_WAIT（IPC4-CALL）で **WAIT_REPLY 状態**に入り、fib（tid=7）の
DEAD 化まで自発的に抜けられない（yuios_tcb_design v1.3 §5.3.8：WAIT_REPLY は REPLY まで永久ブロック）。
fib は $D400 で実行され 'F''5''5' を UART_TX 直書きで出力する。

**確認が必要な点**：exectest（tid=6）では「EXEC→WAIT 中に fib が走り F55 出力→WAIT 脱出→W 出力」が
`0E123MDF557W` として実証された。Shell でも同じ tid=6 が WAIT する構図だが、**exectest は WAIT 後に
TASK-EXIT して終わるのに対し、Shell は WAIT 後にプロンプトを再表示して SH-READLINE へ戻る**。すなわち：

1. fib（tid=7）が `run` で起動するが、**fib の crt0 は TASK_EXIT で DEAD 化**する（startup_proc）。
   このとき LOAD-SLOT-BUSY がクリアされるのは PROC_KILL 経路（yuios_design v2.7 §8.5.4）。**fib が
   自発 TASK_EXIT した場合に LOAD-SLOT-BUSY が落ちるか**が未確認。落ちないと 2 回目の `run` が
   BUSY で弾かれる（§7.4 の「busy 表示」が常態化＝1 回しか run できない）。
2. これは exectest が **1 回 run して終了**だったため顕在化しなかった。Shell は**繰り返し run する**
   ため、**LOAD-SLOT-BUSY の解放経路が必須**。

**推奨対応**：
- PROC_WAIT 完了時（子プロセス DEAD 化検出時）に ProcMgr が LOAD-SLOT-BUSY をクリアするか、実体
  （PROC-WAIT-IMPL / PROC-EXEC-IMPL）を確認し、**繰り返し run が成立すること**を設計書で保証する。
  落ちないなら SH-CMD-RUN 側または ProcMgr 側でクリアする設計を §5.4 に追記。
- §9 回帰計画に「**run fib を 2 回連続実行**し、2 回目も F55 が出る（BUSY で弾かれない）」ことを
  受入項目として追加。これが Shell の「繰り返し実行」の本質的検証になる。

---

### C（確認推奨）

#### C-1：SH-CMD-RUN の経路は exectest と同一でよい（実体確認済）

§10 C-1 の「PROC_EXEC→PROC_WAIT は exectest と同一・FT-NAME-BUF を SH-ARG-BUF に替える差分のみ」は
正しい。inject_exectest の経路（`0 0 name EXEC-OP PROC-TID-ADDR @ IPC4-CALL` → `>R DROP DROP DROP R>`
→ 負値判定 → WAIT）がそのまま使える。**ただし M-2 の LOAD-SLOT-BUSY 解放だけは exectest では
検証されていない**点に注意（C-1 は経路の同一性のみ保証、繰り返し実行は別途 M-2）。

#### C-2：SH-ARG-BUF と FT-NAME-BUF の関係（D-1 関連）

§4 は SH-ARG-BUF を「FT-NAME-BUF 互換」とするが、PROC-EXEC-IMPL は内部で FILE-OPEN にファイル名
アドレスを渡すだけなので、**SH-ARG-BUF の実体アドレスが何であれ NUL 終端文字列であれば動く**
（FT-NAME-BUF 互換である必要はない）。§4 D-1 の配置論点（テストバッファ流用 vs VARIABLE）は、
FileMgr 縮小版試験が使う $ED00/$EE00/$EF00（memmap v2.1 §14.4(3) 確定）と**重ならない**ことだけ
確認すればよい。SH-ARG-BUF をテストバッファ域に置くなら $EF00 系 STAT バッファとの時系列競合
（run 中に STAT を使う ProcMgr の PE-STATBUF=$EF00 流用）に注意。**SH-ARG-BUF は VARIABLE 化が安全**
（D-1 への査読意見：初版は VARIABLE 推奨。$DC00 域消費は数十バイトで C-2 の VARIABLE 増加見積り内）。

---

### N（情報・確認事項）

- **N-1（§5.6 CODE ブリッジ）**：`WORD_SHELL_TASK` を sed ラベル置換リストに追加する必要（§8）は、
  exectest の `WORD_PROC_EXEC_TEST` 追加が必須だった実績（inject_exectest）と同一事象で正しい。
  **本番ビルドに恒久追加**という指摘（§8）も妥当。ビルド手順書改版要。
- **N-2（STRCMP 不在）**：grep 確認済との記載どおり、専用 STRCMP は無い。Shell 内に固定長比較
  （`SH-STR=`）を実装する方針は妥当。C@（CFETCH）の使用実績も裏取り済（kernel_forth 内）。
- **N-3（tid 監視）**：§6 で Shell=tid6・子プロセス=tid7 まで安全圏、tid8 以降は別 KY（HANDOVER_CHAT54
  §6 のデータスタック $FC00 超問題）という整理は正しい。Level 1（動的プロセス 1 個）なら tid7 までで
  収まる。
- **N-4（OS-START 追加位置）**：§6 の PROCMGR-START 直後に SHELL-START（tid=6）は、inject_exectest の
  PROC-EXEC-TEST-START 追加位置と同じで妥当（C-2 査読確認）。

---

### D（査読確認項目）

- **D-1（C-2 で回答）**：SH-ARG-BUF は VARIABLE 化推奨（テストバッファ域は $EF00 STAT と競合余地）。
- **D-2（§5.3 トークン分割）**：Phase1 は cmd+arg1 のみで確定してよい。将来の引数複数化は §1.3 で
  「予約のみ」と明記済。SH-PARSE の実装は最小で妥当。
- **D-3（追加）**：§5.2 SH-READLINE の NUL 終端付与が「確定時に追加」と注記だけで本体に書かれて
  いない。Enter 確定時（`$0D = IF ... EXIT` の直前）に `0 SH-LINE-BUF SH-LINE-LEN @ + C!` を入れる
  ことを擬似コードに反映。SH-PARSE が NUL 終端を前提にするため、抜けるとバッファオーバーラン読み。
- **D-4（追加）**：§5.2 のバッファ上限チェックが `SH-LINE-LEN @ 64 <` だが、SH-LINE-BUF は 64B
  （§4）。インデックス 0-63 で 64 文字格納＋NUL 終端で 65B 必要。**オフバイワン**の可能性。上限を
  `63 <`（最大 63 文字＋NUL=64B）にするか、バッファを 65B 確保するか確認。

---

## 4. 評価（E）

- **E-1**：既存 IPC4 サービスを 2B トークンのラッパで呼ぶだけで Shell を成立させる設計思想は、
  スレッデッドコードの密度効果（§15.4）を正しく活かしており、新規カーネル機能ゼロで run/ps/help を
  実現する見通しは妥当。実体把握（op 定数・PUTS の NUL 終端・IPC4-CALL 作法）も正確。
- **E-2**：§7 の動作シナリオ（受入基準）が正常系・ps・help・異常系（引数なし／存在しない／BUSY）まで
  網羅されており、テスト設計として良い。特に異常系で「Shell は落ちない」を明示した点が堅実。
- **E-3**：§10 で D-1〜D-2・C-1〜C-2・N-1〜N-2 をレビュー論点として自己整理し、サイズ概算の楽観性
  （O-2 早期補正）を設計に組み込んだ姿勢は誠実。

---

## 5. 判定と次アクション

**条件付き差し戻し。**

- **M-1**：UART_GETC を発行するのは Shell ただ 1 タスクという不変条件を明記し、SH-READLINE の GETC
  経路単体実証（CHAT57 未実証）を §9 回帰の最優先項目に追加。
- **M-2**：LOAD-SLOT-BUSY の解放経路（子プロセス自発 TASK_EXIT 時）を実体確認し、**繰り返し run の
  成立**を保証。§9 に「run fib 2 回連続」受入項目を追加。
- **C-1/C-2/D-1**：SH-ARG-BUF は VARIABLE 化。D-3（NUL 終端付与）・D-4（バッファ上限オフバイワン）を
  擬似コードに反映。

M-1/M-2 はいずれも **exectest（一回実行）と Shell（対話ループ・繰り返し実行）の動作モデル差**から
来る本質的な見落としで、実装前に潰すべき（「見えているバグは先に潰す」）。設計の骨格（Forth 常駐・
IPC4 ラッパ・OS-START 組込）は妥当で作り直し不要。M-1/M-2 反映＋ C/D 整理の v1.1 で再レビューとする。

> ※ 本指摘はプロジェクトナレッジ（kernel_forth v0.10.15/16・yuios_tcb_design v1.3・yuios_design v2.7・
> inject_exectest）の実体に基づく（KY34/KY39：実体を真とする。ナレッジを一次情報として先に確認）。

---

以上。
ご安全に！
