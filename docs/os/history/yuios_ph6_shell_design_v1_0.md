# YUI OS Ph.6 Forth 常駐 Shell 設計書

- **ファイル名**: yuios_ph6_shell_design_v1_0.md
- **Version**: 1.0（ドラフト・レビュー前）
- **Status**: ドラフト — 有識者レビュー・承認前。承認まで実装着手しない（原則43）
- **対象**: Step 8-Y / YUI OS Ph.6 Shell（Level 1・Forth 常駐実装）
- **作成日**: 2026-06-18（CHAT57）
- **前提**: kernel_forth v0.10.16（Ph.5 Step4 完成・PROC_EXEC/PROC_WAIT 経路実証済 `0E123MDF557W`）
- **上位設計**: yuios_memmap_design v2.4 §15（案D-ε・Level 1/Level 2 区分）、yuios_design v2.x §9（Shell=C は Level 2 目標）

---

## 1. 目的とスコープ

### 1.1 目的

YUI OS Level 1 における対話シェルを **Forth 辞書常駐**として実装する。ユーザが UART から入力したコマンド行を解釈し、組込コマンド（`run` 等）を実行する。`run <name>` は ProcMgr の PROC_EXEC/PROC_WAIT を介して C プロセス（例: fib）を C プロセス領域 $D400 へロード・実行・待機する。

### 1.2 なぜ Forth 常駐か（memmap v2.4 §15.3/15.4 の確定方針）

MMU なし単一物理アドレス空間かつ crt0 非 PIC という Level 1 の制約下では、Shell を C プロセスとして C プロセス領域に置くと、`run` で起動する子プロセスが同じ領域へロードされ **実行中の Shell 自身を上書き破壊**する（§15.2 run 不成立問題）。Shell を辞書常駐とすれば、Shell は辞書（$C160 直上）に居り、子プロセスのみ $D400 へ載るため領域の奪い合いが起きず `run` が成立する。Shell=C 実装は Level 2（Ph.8 MMU 後）の到達目標として保持する。

OS-9 になぞらえれば、Level 1 のこの構成は「常駐シェル＋単一ユーザプロセス＋複数システムプロセス（FileMgr/MemMgr/UART/ProcMgr）が協調する」形であり、OS-9 Level I のフラット 64KB 空間モデルをリスペクトしたものである。

### 1.3 スコープ（本設計の範囲）

- 含む: プロンプト表示、行入力（UART-GETC 経由）、行編集（最小：BS）、トークン分割、コマンドディスパッチ、組込コマンド `run` / `ps` / `help`、実行ループ、Shell タスクの起動（OS-START への組込）。
- 含まない（将来）: パイプ・リダイレクト、環境変数、ヒストリ、外部コマンド検索パス、引数複数化（`run` は引数 1 個＝ファイル名のみ）。

### 1.4 非目標（Level 2 へ送る）

Shell の C 実装、複数同時ユーザプロセス、動的ロードの PIC 化。これらは MMU 統合（Ph.8）後の Level 2 で扱う。

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

---

## 4. データ構造（Shell 専用 VARIABLE・DATA 領域）

| 名前 | 型 | サイズ | 用途 |
|---|---|---|---|
| `SH-LINE-BUF` | バッファ | 64B（CONSTANT で領域確保） | 入力行（NUL 終端） |
| `SH-LINE-LEN` | VARIABLE | 2B | 現在の行長 |
| `SH-ARG-BUF` | バッファ | 16B | `run` のファイル名引数（NUL 終端・FT-NAME-BUF 互換） |
| `SH-PS-BUF` | バッファ | 既存 PL バッファ流用可 | `ps` の PROC_LIST 結果格納 |

**配置方針**: バッファ実体は memmap のテストバッファ域（$ED00-$EFFF・768B）の未使用部、または DATA 域の VARIABLE として確保する。**どちらにするかはレビュー論点（D-1）**。VARIABLE 化すると $DC00 域を消費（自動追従）、テストバッファ流用だと FileMgr 縮小版試験と競合の可能性。初版は **行バッファ等は専用 CONSTANT アドレスでテストバッファ域上端を割当**（VARIABLE は SH-LINE-LEN のみ）を提案。

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
        DUP $0D = IF DROP SH-CR EXIT THEN           \ Enter→確定
        DUP $08 = OVER $7F = OR IF                  \ BS or DEL
            DROP
            SH-LINE-LEN @ 0> IF
                $08 SH-EMIT  $20 SH-EMIT  $08 SH-EMIT  \ 画面上 1 文字消去
                SH-LINE-LEN @ 1- SH-LINE-LEN !
            THEN
        ELSE
            DUP SH-EMIT                              \ エコー
            SH-LINE-LEN @ 64 < IF                    \ オーバーフロー防止
                DUP SH-LINE-BUF SH-LINE-LEN @ + C!
                SH-LINE-LEN @ 1+ SH-LINE-LEN !
            ELSE DROP THEN
        THEN
    AGAIN ;
```
（行末に NUL を置く処理は確定時に追加：`0 SH-LINE-BUF SH-LINE-LEN @ + C!`）

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
    \ 3. r0<0 なら "exec failed" 表示
    \ 4. 0 0 new_tid PROC-WAIT-OP PROC-TID-ADDR @ IPC4-CALL → r0=exit_code
    \ 5. プロンプトへ戻る
: SH-CMD-PS    ( -- )   \ PROC_LIST で件数取得し SH-PS-BUF を表示
```

### 5.5 ディスパッチ

```
: SH-DISPATCH  ( -- )   \ cmd 文字列を既知コマンドと比較し対応ワードを呼ぶ。未知なら "?" 表示
    \ 文字列比較は既存 STRCMP 相当 or 先頭数文字比較。コマンド数が少ないため線形比較で可。
```

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
    SHELL-START                     \ tid=6 ★Ph.6 追加
    BEGIN TASK-SLEEP AGAIN ;
```

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

## 9. 回帰計画（memmap v2.4 §15.9 準拠）

1. **非回帰**: Shell 搭載後も 5 サービス起動 `0123MD` が不変であること（素ディスク起動）。
2. **辞書天井**: フルビルド後 .sym で辞書実終端 ≦ $D3FF を実測（K38）。
3. **run 実証**: `run fib` で `F55`→プロンプト復帰（§7.1）。CHAT57 の exectest 経路を Shell からの実行に置換した形。
4. **Dhrystone**: Shell は Force/kernel_forth の変更でツール改修ではないため、Dhrystone 回帰は不要（ツール非改修）。ただし kernel_forth 改版のため OS 全タスク健全性は (1)(3) で担保。

---

## 10. レビュー論点（M/C/D/N/E 分類用・たたき台）

- **D-1（要決定）**: §4 Shell バッファの配置（テストバッファ域流用 vs VARIABLE 化）。FileMgr 縮小版試験との競合可否。
- **D-2（要決定）**: §5.3 トークン分割を最小（cmd+arg1）で確定してよいか。将来の引数複数化の予約だけ取るか。
- **C-1（確認）**: §5.4 SH-CMD-RUN の PROC_EXEC→PROC_WAIT 経路は exectest（CHAT57 実証）と同一でよいか。FT-NAME-BUF ではなく SH-ARG-BUF を使う差分のみ。
- **C-2（確認）**: §6 OS-START への SHELL-START 追加位置（PROCMGR-START 直後・tid=6）。
- **N-1（注意）**: §5.2 行編集は BS のみ（カーソル移動・ヒストリなし）でよいか。
- **N-2（注意・裏取り済）**: 文字列比較ワード（STRCMP 相当）は kernel_forth v0.10.16 に**専用ワード無し**（grep 確認済）。よって Shell 内で最小の固定長比較ワード（例: `SH-STR=` ( a b len -- flag )）を実装する。バイト操作は既存 `C@`(CFETCH)/`C!`(CSTORE) を使用（kernel_forth 内に使用実績あり：行1203/1512 等）。コマンド数が少ないため、先頭文字での分岐＋短語比較で足りる見込み。
- **E-1（誤記候補）**: サイズ概算（1.42KB）は楽観。§2 の早期補正（O-2）を必須工程として設計に明記済。

---

## 11. 改版履歴

| Version | 日付 | 変更内容 | 担当 |
|---|---|---|---|
| 1.0 | 2026-06-18 | 初版ドラフト（CHAT57）。Level 1 Forth 常駐 Shell。memmap v2.4 §15 準拠。kernel_forth v0.10.16 を前提。レビュー前。 | Claude |
