# YUI OS Ph.6 Forth 常駐 Shell 設計書

- **ファイル名**: yuios_ph6_shell_design_v1_2.md
- **Version**: 1.2（CHAT59/60 実装確定反映・実装後追補）
- **Status**: 実装反映済 — v1.1 は条件なし承認済（CHAT57/58）。本 v1.2 は CHAT59/60 の実装結果・設計判断を追補した記録版（KY41: 旧情報は打ち消し線で保持）
- **対象**: Step 8-Y / YUI OS Ph.6 Shell（Level 1・Forth 常駐実装）
- **作成日**: 2026-06-18（CHAT57）
- **前提**: ~~kernel_forth v0.10.16~~ → **kernel_forth v0.10.18**（Ph.6 Shell 全8コマンド＋起動メッセージ実装・実証済）
- **上位設計**: yuios_memmap_design v2.4 §15（案D-ε・Level 1/Level 2 区分）、yuios_design v2.x §9（Shell=C は Level 2 目標）
- **査読対応**: yuios_ph6_shell_design_v1_0_review_v1_0.md（条件付き差し戻し）の M-1／M-2／C/D を反映。M-1（GETC 経路）・M-2（繰り返し run）は実体確認＋実機実証で裏取り済（本書 §12）。

---

## 1. 目的とスコープ

### 1.1 目的

YUI OS Level 1 における対話シェルを **Forth 辞書常駐**として実装する。ユーザが UART から入力したコマンド行を解釈し、組込コマンド（`run` 等）を実行する。`run <name>` は ProcMgr の PROC_EXEC/PROC_WAIT を介して C プロセス（例: fib）を C プロセス領域 $D400 へロード・実行・待機する。

### 1.2 なぜ Forth 常駐か（memmap v2.4 §15.3/15.4 の確定方針）

MMU なし単一物理アドレス空間かつ crt0 非 PIC という Level 1 の制約下では、Shell を C プロセスとして C プロセス領域に置くと、`run` で起動する子プロセスが同じ領域へロードされ **実行中の Shell 自身を上書き破壊**する（§15.2 run 不成立問題）。Shell を辞書常駐とすれば、Shell は辞書（$C160 直上）に居り、子プロセスのみ $D400 へ載るため領域の奪い合いが起きず `run` が成立する。Shell=C 実装は Level 2（Ph.8 MMU 後）の到達目標として保持する。

OS-9 になぞらえれば、Level 1 のこの構成は「常駐シェル＋単一ユーザプロセス＋複数システムプロセス（FileMgr/MemMgr/UART/ProcMgr）が協調する」形であり、OS-9 Level I のフラット 64KB 空間モデルをリスペクトしたものである。

### 1.3 スコープ（本設計の範囲）

- 含む: プロンプト表示、行入力（UART-GETC 経由）、行編集（最小：BS）、トークン分割、コマンドディスパッチ、~~組込コマンド `run` / `ps` / `help`~~ → **【v1.2・CHAT59/60 実装確定】組込コマンド全8種 `help` / `run` / `ps` / `ver` / `mem` / `kill` / `ls` / `cat`**、実行ループ、Shell タスクの起動（OS-START への組込）、**起動メッセージ `YUIOS Booted!`（一括表示・1行版）**。
- 含まない（将来）: パイプ・リダイレクト、環境変数、ヒストリ、外部コマンド検索パス、引数複数化（`run` は引数 1 個＝ファイル名のみ）。

### 1.4 非目標（Level 2 へ送る）

Shell の C 実装、複数同時ユーザプロセス、動的ロードの PIC 化。これらは MMU 統合（Ph.8）後の Level 2 で扱う。

**【v1.2 追記・CHAT60 設計判断】Level 2 送り確定事項**: (a) **`ls` 全件表示（旧 D 案＝PAGE-POOL を MemMgr ALLOC/FREE で借用し全32件表示）**。Level 1 では辞書天井 $D3FF に張り付き実装余地が物理的に無く、Level 2（MMU で Shell が独立論理空間を持つ）では普通にバッファ確保で全件表示できるため D 案という工夫自体が不要となる。よって **D 案は実装しない**（Level 1 で不可・Level 2 で不要）。Level 1 の `ls` は A 案（先頭4件＋`n/N` 表示）を最終仕様とする。(b) **起動メッセージ2行目 `YUKARI Semiconductor Devices.` およびブートログ化（行単位の起動成否ログ）**。辞書天井制約で Level 1 では1行のみ。Level 2 の C 実装 Shell ＋端末サービス経由ブートログで復活・拡張する。

**子プロセスの stdin 非サポート（M-1 対応）**: Level 1 では UART_GETC を発行するのは **Shell ただ 1 タスク**である（§3.1 不変条件）。`run` で起動した C プロセスが getchar（UART_GETC）を呼ぶことは Level 1 では非サポートとする。理由は UART ドライバの GETC 待機機構が単一クライアント（UART-WAIT-TID 1 個）前提のため（§3.1）。子プロセスの stdin が必要になるのは Level 2 で複数プロセスの入出力多重化を導入してからとする。

---

## 2. 配置とサイズ予算（memmap v2.4 §15.5 準拠）

| 項目 | 値 | 根拠 |
|---|---|---|
| Shell 常駐先 | Forth 辞書（$C160 直上から伸長） | v0.10.16 実測 WORD_OS_START=$C160 |
| 辞書天井 | $D3FF（案D-ε） | memmap v2.4 §15.5 |
| 現辞書余裕 | $C160→$D3FF ＝ 約 4767B | 天井 − 実終端 |
| Shell 概算サイズ | 約 1.42KB（楽観）／+30% 見て約 1.85KB | §15.4／§15.10 O-2 |
| 搭載後辞書実終端（概算） | 約 $C6EB〜$C8D0 | 1.42〜1.85KB 加算 |
| 搭載後余裕（概算） | 約 2.9〜3.3KB | 天井 $D3FF まで |

**【v1.2 実測確定・CHAT60】** 全8コマンド＋起動メッセージ実装後の実測値: **真の辞書終端 $D2AA / 天井 $D3FF まで余裕 341B（0.33KB）**。VAR_* 最大 $DC5E（個数48・不変）/ SH-PS-BUF($DC60) 余裕 0B。Shell 実サイズは概算 1.42KB を超え約 3.7KB（review v1.0 E-1 の上振れ予言が的中）。**重要な測定基準の是正**: 辞書終端は `< $D400` で測ると OS-START 実体（$D2xx〜、起動メッセージ追加で $D400 超へ伸びうる）を見落とす。**真の終端は $5100〜$DBFF 全域で VAR_*／PROC-LOAD-ADDR を除いた最大シンボルで測る**こと。実際 BOOT-MSG 即値42文字版で OS-START が $D426 まで伸び天井を 39B 超過、1行版化で $D2AA に収めた（§14.x 参照）。

**KY/監視（§15.10 O-2・§14 K38）**: Shell サイズ見積りは楽観的。**最初の 2〜3 コマンド（`help`+`run` の骨格）実装時点で一旦フルビルドし、.sym で辞書実終端を実測・早期補正**する。実終端 ≦ $D3FF を 1 変更 1 検証で常時確認。DATA(VARIABLE) は $DC00 起点で自動追従するため、Shell が増やす VARIABLE 個数を .sym 実測し $DCFF 超過（PAGE-POOL 侵食）が無いことを確認する（§14 v2.1 C-2）。

---

## 3. 依存する既存資産（v0.10.16・IPC4 サービス）

Shell はすべて既存の IPC4 サービスを 2B トークンのラッパで呼ぶだけで成立する（スレッデッドコード密度効果＝§15.4）。新規カーネル機能は追加しない。

| サービス | op | シグネチャ（IPC4-CALL） | Shell での用途 |
|---|---|---|---|
| UART_PUTC | $0401 | `0 0 ch PUTC-OP uart_tid IPC4-CALL` → r0 | プロンプト・エコー・出力 |
| UART_PUTS | $0403 | `0 0 straddr PUTS-OP uart_tid IPC4-CALL` | 文字列出力（help 等） |
| UART_GETC | $0402 | `0 0 0 GETC-OP uart_tid IPC4-CALL` → r0=byte | 行入力 1 文字 |
| PROC_EXEC | $0301 | `0 0 nameaddr EXEC-OP procmgr_tid IPC4-CALL` → r0=new_tid/err | `run`：子プロセス起動 |
| PROC_WAIT | $0303 | `0 0 tid WAIT-OP procmgr_tid IPC4-CALL` → r0=exit_code | `run`：子の終了待ち |
| PROC_LIST | $0304 | `0 0 bufaddr LIST-OP procmgr_tid IPC4-CALL` → r0=count | `ps`：タスク一覧 |

**TID 取得**: `UART-DRV-TID @`（$FC5C）、`PROC-TID-ADDR @`（$FC6A）。いずれも OS-START でドライバ/ProcMgr 起動時に設定済み。

**IPC4-CALL 戻り**: `( ... -- r3 r2 r1 r0 )` で r0=TOS。不要な r3 r2 r1 は `>R DROP DROP DROP R>` で r0 のみ残す（exectest 実証済の作法）。

### 3.1 不変条件：UART_GETC を発行するのは Shell ただ 1 タスク（M-1 対応）

UART ドライバの GETC 待機機構（UART-GETC-IMPL）は、待機クライアント tid を**単一変数 `UART-WAIT-TID`（$FC5E）に 1 個だけ**保持する（kernel_forth 実体確認済）。バッファ空のとき `DUP UART-WAIT-TID !` で待機 tid を登録し、RX-IRQ 受信時にその 1 タスクを起こす。

したがって **Level 1 では UART_GETC を発行できるのは Shell（tid=6）ただ 1 タスクに限る**ことを不変条件とする。これを破る（複数タスクが GETC する）と UART-WAIT-TID が上書きされ、取りこぼし・デッドロックが起きる。本不変条件の帰結として、子プロセスの stdin は Level 1 で非サポート（§1.4）。

**実証状況（M-1 解消）**: GETC 経路は exectest（PUTC のみ）では未実証だったため、CHAT57 で**最小実証タスク（GETC で 3 文字受信→エコー）を差し込み、emu23 `-i` で入力 "abc" を供給して実機確認**した。出力で `G`→`a`→`b`→`c`→`Z` の順序が保たれ、リングバッファ経由の 1 文字受信・エコーが成立することを確認済（§12.1）。SH-READLINE はこの実証された基盤の上に行編集を載せるだけである。

---

## 4. データ構造（Shell 専用 VARIABLE・DATA 領域）

**【v1.2 重要改版・CHAT58/59/60】データ配置の実装確定**

~~C-2/D-1 で SH-ARG-BUF 等を VARIABLE 化（$DC00 起点自動追従）~~ → **実装の結果、Shell バッファ群は VARIABLE ではなく DATA 域上端の CONSTANT 固定アドレスで確保**した。理由: Force v1.5 で Shell 規模の VARIABLE を増設すると VAR_* 自動配置が急上昇し、**実測で VAR_* 最大が $DC5E（SH-PS-BUF $DC60 の 2B 手前）まで逼迫、余裕 0B** に達したため。以降のコマンド追加では **新規 VARIABLE を一切増やさず**、ワーク領域は R/データスタックで完結させる方針を厳守した（SH-ATOI・SH-CAT-DUMP・SH-EMIT-DEC2・各コマンドとも VARIABLE 不使用）。

**バッファ占有マップ（実測・CONSTANT 固定）**:

| アドレス | サイズ | 用途 |
|---|---|---|
| $DC60-$DC7F | 32B | SH-PS-BUF |
| $DC80-$DC8F | 16B | SH-CMD-BUF |
| $DC90-$DC9F | 16B | SH-ARG-BUF |
| $DCA0-$DCA5 | 6B | SH-PROMPT-BUF |
| $DCA6-$DCA9 | 4B | SH-RUN-KW |
| $DCAA-$DCAE | 5B | SH-HELP-KW |
| $DCB0-$DCF0 | 65B | SH-LINE-BUF（ls/cat の作業バッファに流用） |
| $DCF1-$DCF3 | 3B | SH-PS-KW |
| 空き | $DCAE-$DCAF(2B)・$DCF4-$DCFF(12B) | 計14B のみ |

**DATA 域空きは計14B**しかなく、新コマンドのキーワード文字列を SH-STR= 方式で置く領域は無い（→ §5.5 先頭文字分岐方式の採用根拠）。`ls`/`cat` の作業バッファは **SH-LINE-BUF(65B) を流用**（ls/cat 実行は SH-READLINE 完了後ゆえ入力行と時系列競合なし）。

| 名前 | 型 | サイズ | 用途 |
|---|---|---|---|
| `SH-LINE-BUF` | バッファ | 65B（CONSTANT で領域確保・最大 64 文字＋NUL） | 入力行（NUL 終端） |
| `SH-LINE-LEN` | VARIABLE | 2B | 現在の行長（0〜64） |
| `SH-ARG-BUF` | バッファ | 16B（NUL 終端） | `run` のファイル名引数 |
| `SH-CMD-BUF` | バッファ | 16B（NUL 終端） | 先頭語（コマンド名） |

**配置方針（D-1 確定・査読 C-2 反映）**: バッファ実体は **DATA 域の VARIABLE/領域確保（$DC00 起点・自動追従）** とする。テストバッファ域（$ED00-$EFFF）は流用しない。理由は、ProcMgr が PROC_EXEC 内で STAT バッファに $EF00 系（PE-STATBUF）を流用するため、`run` 実行中にテストバッファ域へ置いた Shell バッファと**時系列競合**する恐れがあるため（査読 C-2）。VARIABLE 化による $DC00 域消費は数十バイト規模で、DATA 枠 256B の余裕内（memmap v2.4 §14 v2.1 C-2 の VARIABLE 増加見積り内）。**フルビルド後 .sym で VAR 個数を実測し $DCFF 超過なきこと（PAGE-POOL $DD00 非侵食）を境界検査（K38）**する。

**SH-ARG-BUF と FT-NAME-BUF の関係（査読 C-2）**: PROC-EXEC-IMPL は内部で FILE-OPEN にファイル名アドレスを渡すだけなので、SH-ARG-BUF は **NUL 終端文字列でありさえすれば任意アドレスで動く**（FT-NAME-BUF 互換である必要はない）。

**バッファ上限のオフバイワン是正（D-4 反映）**: SH-LINE-BUF は 65B 確保（インデックス 0〜63 で最大 64 文字＋index 64 に NUL）。§5.2 の上限チェックは `SH-LINE-LEN @ 64 <`（= 最大 64 文字まで格納可）とする。確定時に `SH-LINE-LEN @`（≤64）の位置へ NUL を置くため 65B 目（index 64）まで使用する。

---

## 5. ワード構成（辞書追加分）

### 5.1 低レベルラッパ

```
: SH-EMIT   ( ch -- )        0 0 ROT UART-PUTC-OP UART-DRV-TID @ IPC4-CALL DROP DROP DROP DROP ;
: SH-TYPE   ( straddr -- )   0 0 ROT UART-PUTS-OP UART-DRV-TID @ IPC4-CALL DROP DROP DROP DROP ;
: SH-KEY    ( -- ch )        0 0 0   UART-GETC-OP UART-DRV-TID @ IPC4-CALL >R DROP DROP DROP R> ;
: SH-CR     ( -- )           $0D SH-EMIT  $0A SH-EMIT ;
```

### 5.2 行入力

```
: SH-READLINE  ( -- )    \ SH-LINE-BUF に 1 行読み込み（NUL 終端）。Enter($0D)で確定。BS($08)で1文字削除。
    0 SH-LINE-LEN !
    BEGIN
        SH-KEY                       ( ch )
        DUP $0D = IF                                 \ Enter→確定
            DROP
            0 SH-LINE-BUF SH-LINE-LEN @ + C!         \ ★D-3: 確定時に NUL 終端を付与
            SH-CR EXIT
        THEN
        DUP $08 = OVER $7F = OR IF                   \ BS or DEL
            DROP
            SH-LINE-LEN @ 0> IF
                $08 SH-EMIT  $20 SH-EMIT  $08 SH-EMIT  \ 画面上 1 文字消去
                SH-LINE-LEN @ 1- SH-LINE-LEN !
            THEN
        ELSE
            DUP SH-EMIT                              \ エコー
            SH-LINE-LEN @ 64 < IF                    \ ★D-4: 最大64文字(buf 65B・0..63格納+NUL)
                DUP SH-LINE-BUF SH-LINE-LEN @ + C!
                SH-LINE-LEN @ 1+ SH-LINE-LEN !
            ELSE DROP THEN
        THEN
    AGAIN ;
```
（NUL 終端は Enter 確定時に `0 SH-LINE-BUF SH-LINE-LEN @ + C!` で本体に付与済み。SH-PARSE が NUL 終端を前提とするため必須＝D-3。）

### 5.3 トークン分割（最小：先頭語＝コマンド、次語＝引数）

```
: SH-SKIP-SP  ( idx -- idx' )   \ 空白スキップ
: SH-WORD     ( idx -- idx' start len )  \ 1 語切り出し
: SH-PARSE    ( -- )            \ SH-LINE-BUF を cmd と arg(SH-ARG-BUF) に分解
```
Phase1 は引数 1 個（ファイル名）のみ対応。区切りは空白（$20）。

### 5.4 組込コマンド

```
: SH-CMD-HELP  ( -- )   \ 使用可能コマンド一覧を SH-TYPE で表示
: SH-CMD-RUN   ( -- )   \ SH-ARG-BUF のファイルを PROC_EXEC→PROC_WAIT（exectest と同経路）
    \ 1. ARG が空なら usage 表示して return
    \ 2. 0 0 SH-ARG-BUF PROC-EXEC-OP PROC-TID-ADDR @ IPC4-CALL → r0=new_tid/err
    \ 3. r0<0 なら "exec failed"（err=-1 が BUSY 由来か OPEN 失敗かは Phase1 では区別せず表示）
    \ 4. 0 0 new_tid PROC-WAIT-OP PROC-TID-ADDR @ IPC4-CALL → r0=exit_code
    \ 5. プロンプトへ戻る
```

**繰り返し run の成立保証（M-2 対応・実体確認済）**: `run` を繰り返すには、子プロセス終了ごとに C プロセス領域占有フラグ LOAD-SLOT-BUSY が解放される必要がある。実体確認の結果、**PROC-WAIT-IMPL が子プロセス DEAD 検出後に `0 LOAD-SLOT-BUSY !` を実行して占有解除する**（kernel_forth v0.10.16 PROC-WAIT-IMPL 内・実体確認済）。すなわち `run`→PROC_EXEC（BUSY=new_tid）→PROC_WAIT（DEAD 待ち→解放）の流れで、WAIT 完了時に必ず解放され、**次の run が成立する**。fib の crt0（startup_proc v1.1）は main return 後 TASK_EXIT で自発 DEAD 化し、ProcMgr 側の WAIT がそれを検出して解放する経路である。

**実証状況（M-2 解消）**: CHAT57 で exectest を **2 回連続 EXEC→WAIT** に拡張し実機確認。出力 `0E123MDF557WF557W`＝1 回目 `F557W`・2 回目 `F557W`（2 回目も new_tid=7＝同一スロット再利用で BUSY 弾きなし）を確認済（§12.2）。繰り返し run は実体・実機ともに成立。
: SH-CMD-PS    ( -- )   \ PROC_LIST で件数取得し SH-PS-BUF を表示
```

**【v1.2 新設・CHAT59/60】組込コマンド ver/mem/kill/ls/cat 実装仕様**

全コマンド **新規 VARIABLE 不使用**・**先頭文字分岐**（§5.5）でディスパッチ。出力は1文字エラーコード方式。

- **`ver`** ( SH-CMD-VER ): OS バージョン `YUIOS V0.10.18` を emit。コード即値 EMIT（DATA 域消費ゼロ）。
- **`mem`** ( SH-CMD-MEM ): MEM_QUERY($0103)→r0=空きページ数 → `MEM: N/16` 表示（1ページ=256B・全16ページ）。実測 `MEM: 12/16`（OS予約4ページ）。
- **`kill <tid>`** ( SH-CMD-KILL ): 引数を **SH-ATOI** で数値化し PROC_KILL($0302) 発行。**保護ガード**: tid 0..6（カーネル/常駐サービス/Shell 自身）は kill 拒否で `P`、範囲外(>15)・非数字・空は `?`、対象が既に DEAD なら `D`、生存タスク(tid 7..15)の kill 成功で `K`。PROC-KILL-IMPL は対象 tid を無検証で DEAD 化するため **保護は Shell 側責務**（§実証で kill 16 のオフバイワン= `16 >`→`15 >` 修正済）。
- **`ls`** ( SH-CMD-LS・**A 案**): FILE_LIST($0207) を SH-LINE-BUF(64B=4件) へ→各16B エントリ名を SH-TYPE 出力→末尾に `表示件数/総数`（総数 N は FS-FILE-COUNT@ $4806）。**構造上最大4件表示**、総数 N は **SH-EMIT-DEC2**（0-99 2桁）で表示。実測 `FIB`→`1/1`、6件→`4/6`、12件→`4/12`、0件→`0/0`。全32件版（D 案）は §1.4 のとおり Level 2 送り。
- **`cat <file>`** ( SH-CMD-CAT ): FILE_OPEN($0201)→FILE_READ($0203) を SH-LINE-BUF(64B) へ逐次（OT-POS 自動前進・actual=0 で EOF）→FILE_CLOSE($0202)。actual バイトを **SH-CAT-DUMP** でそのまま EMIT（ヌル終端非依存）。引数空=`?`、open 失敗=`!`。実測 `cat HELLO`→`Hello, YUI OS!`。複数ブロック逐次読みは FILE-READ-IMPL 仕様＋PROC-EXEC 実績で担保。

**補助ワード（v1.2 新設・VARIABLE 不使用）**:
- **SH-ATOI** ( -- n ): SH-ARG-BUF のヌル終端10進文字列→符号なし数値。非数字/空は -1。R に累積・TOS に走査ptr。
- **SH-EMIT-DEC2** ( n -- ): 0-99 を10進出力（除算不使用・十の位を減算ループ算出）。**SH-EMIT-TID は 0-15 専用で N≧16（実害は≧20）で表示破綻**するため、ls 総数 N には本ワードを使う。
- **SH-CAT-DUMP** ( n addr -- ): addr から n バイトを EMIT。
- **SH-CMD0** ( -- ch ): SH-CMD-BUF 先頭1文字取得（先頭文字分岐用）。

### 5.5 ディスパッチ

```
: SH-DISPATCH  ( -- )
    \ 既存 run/help/ps は SH-STR= 比較を温存（実証済機能の回帰回避）
    \ 新規 ver/mem/kill/ls/cat は SH-CMD0（先頭1文字）で分岐
```

**【v1.2 重要改版・CHAT59/60】先頭文字分岐方式の採用**

~~文字列比較は既存 STRCMP 相当 or 先頭数文字比較~~ → **DATA 域空きが14B しか無く（§4）、5コマンド分のキーワード文字列（計20B）を SH-STR= 方式で置けない**ため、新規5コマンドは **先頭1文字（SH-CMD0）による分岐**を採用（DATA 域消費ゼロ）。全8コマンドの先頭文字 `h/r/p/v/m/k/l/c` が**一意**であることを確認（衝突なし）。

分岐表: `'v'`$76→ver / `'m'`$6D→mem / `'k'`$6B→kill / `'l'`$6C→ls / `'c'`$63→cat。既存 run/help/ps は SH-STR= 比較を温存（実証済のため回帰リスクを負わない）。

**制約（Level 2 で解消）**: 先頭文字分岐は同頭コマンド（例 `cat`/`cd`）を追加すると破綻する。Level 1 の8コマンド固定では問題なし。コマンド拡張時は先頭文字の一意性確認を必須とする。

### 5.6 メインループ・タスク

```
: SH-PROMPT  ( -- )   SH-ARG-BUF? いいえ固定文字列 "YUI> " を SH-TYPE ;
: SHELL-TASK  ( -- )
    SH-BANNER                       \ 起動バナー
    BEGIN
        SH-PROMPT
        SH-READLINE
        SH-LINE-LEN @ 0> IF
            SH-PARSE
            SH-DISPATCH
        THEN
    AGAIN ;
CODE SHELL-TASK-ADDR ( -- addr ) ... END-CODE   \ CODE ブリッジ（exectest と同形）
: SHELL-START ( -- )   SHELL-TASK-ADDR TASK-CREATE DROP ;
```

**CODE ブリッジ注意（CHAT57 教訓）**: `LDW A, #WORD_SHELL_TASK` 形式の `#ラベル` 即値は、ビルドの Step3 sed ラベル置換リストに `WORD_SHELL_TASK` を追加しないと hasm23 が解決できず不正コード化する。ビルド手順書（yuios_build_procedure）への追記が必要（後述 §8）。

---

## 6. OS-START への組込

現 OS-START は tid0=root … tid5=ProcMgr の順で 5 サービスを起動している。Shell は**ユーザ対話タスク**として **PROCMGR-START の後に SHELL-START を追加**し、tid=6 を自然確保する。

```
: OS-START
    ...
    PROCMGR-START                   \ tid=5
    BOOT-MSG                        \ ★v1.2 起動メッセージ "YUIOS Booted!"（SHELL前）
    SHELL-START                     \ tid=6 ★Ph.6 追加
    BEGIN TASK-SLEEP AGAIN ;
```

**【v1.2 新設・CHAT60】起動メッセージ BOOT-MSG**: PROCMGR-START 後・SHELL-START 前に1回出力。`emit-char` 直（カーネル直 UART・ドライバ非依存）で `YUIOS Booted!`＋改行を出す。SHELL 前に置くため Shell プロンプト `YUI> ` より先に表示される。`0123MD` マーカー（各サービス内蔵）は**温存・非改変**（条件付き化は見送り）。**2行目 `YUKARI Semiconductor Devices.` は辞書天井制約で削除**（即値42文字版は OS-START を $D426 まで伸ばし天井 $D3FF を 39B 超過、1行版で $D2AA に収容）。2行目は Level 2 送り（§1.4）。

**TID 監視（申し送り N-4／HANDOVER_CHAT54 §6）**: tid8 以降はデータスタック $FC00 超の別問題があるため、Shell が `run` で起動する子プロセス（tid=7）までは安全圏。tid8 以降を使う構成になる場合は別途 KY 管理。Shell 自身は tid=6 で問題なし。

---

## 7. 動作シナリオ（受入基準）

### 7.1 正常系（run fib）

```
（起動）YUI OS Level 1 banner
YUI> run fib            ← ユーザ入力
F55                     ← fib 本体出力（$D400 で実行）
YUI>                    ← プロンプト復帰（PROC_WAIT 完了）
```
受入: `run fib` で fib が $D400 にロード・実行され `F55` 出力後、Shell にプロンプトが戻る（CHAT57 で実証した `F557W` の `W`＝WAIT 完了がプロンプト復帰に相当）。

### 7.2 ps

```
YUI> ps
（tid 一覧＝PROC_LIST の count と各 tid）
YUI>
```

### 7.3 help / 未知コマンド

```
YUI> help
run <name>  - load and run a C program
ps          - list tasks
help        - this help
YUI> foo
?
YUI>
```

### 7.4 異常系

- `run`（引数なし）→ usage 表示。
- `run nonexist` → PROC_EXEC が err（OPEN 失敗）→ "exec failed" 表示・プロンプト復帰（Shell は落ちない）。
- ロード領域 BUSY 中の二重 run → PROC_EXEC が BUSY で -1 → "busy" 表示。

---

## 8. ビルド手順への影響（手順書改版要否）

- **要改版**: yuios_build_procedure の Step3 sed ラベル置換リストに **`WORD_SHELL_TASK`** を追加（§5.6 CODE ブリッジの `#ラベル` 即値解決のため）。CHAT57 で exectest の `WORD_PROC_EXEC_TEST` 追加が必須だったのと同じ事象。
- 本番 OS には Shell を常設するため、検証用 exectest/probe とは異なり**本番ビルドにも sed リスト追加が恒久的に必要**。

---

## 9. 回帰計画（memmap v2.4 §15.9 準拠・査読 M-1/M-2 反映）

1. **【最優先・M-1】SH-READLINE 単体実証**: 数文字入力→エコー→Enter 確定→SH-LINE-BUF 内容確認。GETC 経路は CHAT57 まで未実証だったため（exectest は PUTC のみ）、run 実証（項6）の**前段**に置く。emu23 `-i` で入力供給。※CHAT57 で GETC 経路の素の実機実証は完了済（§12.1）だが、SH-READLINE としての行編集込みは Ph.6 実装後に再実証。
2. **非回帰**: Shell 搭載後も 5 サービス起動 `0123MD` が不変であること（素ディスク起動）。
3. **辞書天井**: フルビルド後 .sym で辞書実終端 ≦ $D3FF を実測（K38）。SH バッファ VARIABLE による $DC00 域消費が $DCFF 超過なきこと（PAGE-POOL $DD00 非侵食）も実測。
4. **help / 未知コマンド**: `help` で一覧表示、未知語で `?` 表示・プロンプト復帰。
5. **ps**: PROC_LIST で件数・tid 一覧表示。
6. **run 実証**: `run fib` で `F55`→プロンプト復帰（§7.1）。
7. **【M-2】繰り返し run 実証**: `run fib` を **2 回連続実行**し、2 回目も `F55` が出る（BUSY で弾かれない）。これが Shell の「繰り返し実行」の本質検証。※CHAT57 で exectest 2回版により実機実証済（§12.2）。Ph.6 実装後に Shell 経由で再実証。
8. **異常系**: `run`（引数なし）→usage、`run nonexist`→exec failed・Shell 継続。
9. **Dhrystone**: Shell は Force/kernel_forth 改版でツール改修ではないため Dhrystone 回帰は不要（ツール非改修）。OS 全タスク健全性は項2/6/7 で担保。

---

## 10. レビュー論点の決着（v1.0 review v1.0 反映済）

| 論点 | 区分 | 決着 |
|---|---|---|
| M-1 GETC 単一クライアント | 必須 | §3.1 に不変条件明記＋§1.4 子 stdin 非サポート。GETC 経路実機実証済（§12.1）。回帰最優先項目化（§9-1）。 |
| M-2 LOAD-SLOT-BUSY 解放 | 必須 | §5.4 に PROC-WAIT-IMPL の `0 LOAD-SLOT-BUSY !` 解放経路を明記。2 回 run 実機実証済（§12.2）。回帰追加（§9-7）。 |
| C-1 run 経路 = exectest | 確認 | 経路同一（FT-NAME-BUF→SH-ARG-BUF 差分のみ）。繰り返し成立は M-2 で別途保証済。 |
| C-2/D-1 バッファ配置 | 確認/決定 | SH-ARG-BUF は **VARIABLE 化**（テストバッファ域は $EF00 STAT と競合余地）。§4 で確定。 |
| D-2 トークン分割 | 決定 | Phase1 は cmd+arg1 で確定。将来複数化は §1.3 予約のみ。 |
| D-3 NUL 終端 | 査読追加 | §5.2 擬似コード本体に Enter 確定時の NUL 付与を反映。 |
| D-4 バッファ上限 | 査読追加 | SH-LINE-BUF を 65B 確保・上限 `64 <` に是正（§4）。 |
| N-1 行編集範囲 | 情報 | 行編集は BS のみ（カーソル移動・ヒストリなし）で Phase1 確定。査読で妥当性確認。 |
| N-2 STRCMP 不在 | 情報（裏取り済） | 専用 STRCMP 無し（grep 確認済）→ Shell 内に固定長比較 `SH-STR=` ( a b len -- flag ) を実装。バイト操作は既存 `C@`(CFETCH)/`C!`(CSTORE)（kernel_forth 内使用実績：行1203/1512 等）。 |
| N-3/N-4 | 情報 | tid 監視（tid6/7 安全圏）・OS-START 追加位置（PROCMGR-START 直後 tid6）を査読で妥当性確認。 |
| E-1 サイズ楽観性 | 評価 | 概算 1.42KB は楽観。§2 の .sym 早期補正（O-2）を必須工程として明記済。 |

## 11. ビルド手順への影響（手順書改版要否）

- **要改版**: yuios_build_procedure の Step3 sed ラベル置換リストに **`WORD_SHELL_TASK`** を追加（§5.6 CODE ブリッジの `#ラベル` 即値解決のため）。CHAT57 で exectest の `WORD_PROC_EXEC_TEST` 追加が必須だったのと同じ事象。
- 本番 OS には Shell を常設するため、検証用 exectest/probe とは異なり**本番ビルドにも sed リスト追加が恒久的に必要**。

## 12. 実証記録（M-1／M-2 の裏取り・CHAT57）

設計の前提を「机上のまま」にせず、必須修正 2 点を実体確認＋実機実証で裏取りした（KY39: 実体を真とする／「見えているバグは先に潰す」）。

### 12.1 M-1：GETC 経路の実機実証

CHAT57 で v0.10.16 に GETC エコーテスト（GETC で 3 文字受信→即エコー）を tid=6 として差し込み、emu23 `-i` で入力 "abc" を供給。出力で `G`（開始）→`a`→`b`→`c`（受信エコー）→`Z`（完了）の順序が保たれ、UART RX リングバッファ経由の 1 文字受信・エコーが成立することを確認。SH-READLINE はこの実証済基盤に行編集を載せるだけ。

### 12.2 M-2：繰り返し run の実機実証

CHAT57 で exectest を 2 回連続 EXEC→WAIT に拡張し実機確認。出力 `0E123MDF557WF557W`＝1 回目 `F557W`・2 回目 `F557W`（2 回目も new_tid=7＝同一スロット再利用で BUSY 弾きなし）。PROC-WAIT-IMPL が DEAD 検出後 `0 LOAD-SLOT-BUSY !` で解放するため、繰り返し run が成立することを実体・実機で確認。

## 13. 改版履歴

| Version | 日付 | 変更内容 | 担当 |
|---|---|---|---|
| 1.0 | 2026-06-18 | 初版ドラフト（CHAT57）。Level 1 Forth 常駐 Shell。memmap v2.4 §15 準拠。kernel_forth v0.10.16 を前提。レビュー前。 | Claude |
| 1.1 | 2026-06-18 | review v1.0（条件付き差し戻し）反映。M-1（GETC 単一クライアント不変条件・子 stdin 非サポート・実機実証・回帰最優先化）、M-2（LOAD-SLOT-BUSY 解放経路明記・2 回 run 実機実証・回帰追加）を反映し実体裏取り（§12）。C-2/D-1（SH-ARG-BUF VARIABLE 化）、D-3（NUL 終端を擬似コード本体へ）、D-4（バッファ 65B・上限オフバイワン是正）を反映。§10 に論点決着表、§12 に実証記録を新設。再レビュー用。 | Claude |
| 1.2 | 2026-06-20 | **CHAT59/60 実装確定反映**。残5コマンド（ver/mem/kill/ls/cat）＋起動メッセージ実装完了を反映。(a) バッファ CONSTANT 固定化・VAR 域0B 逼迫・新規 VARIABLE 不使用方針（§4）。(b) 先頭文字分岐方式の採用と同頭コマンド制約（§5.5）。(c) ls A 案確定・D 案（全件）は Level 2 送り（§1.4）。(d) 起動メッセージ1行版・2行目 Level 2 送り（§6）。(e) 辞書終端の正しい測定基準（$5100-$DBFF 全域）と実測値 終端$D2AA・余裕341B（§2）。(f) 補助ワード SH-ATOI/SH-EMIT-DEC2/SH-CAT-DUMP/SH-CMD0 新設。kernel_forth v0.10.18。 | Claude |
