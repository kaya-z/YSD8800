YSD8800 開発プロジェクト

**emu23 デバッグ・ユーザマニュアル**

emu23 v1.13 / ISA 2.3 対応

対応エミュレータバージョン: emu23 v1.13 (2026-08-14)

| 文書番号 | EMU23-DEBUG-MANUAL-001 |
| --- | --- |
| 文書バージョン | **v1.4**（2026-08-14） |
| 作成日 | 2026-05-17 |
| 改版日 | 2026-06-27 |
| 作成者 | YSD8800開発チーム |
| 対象エミュレータ | **emu23 v1.12** (ISA2.3対応) ~~v1.09~~ |
| ファイル名 | ~~emu23_debug_manual_v1_2.docx~~ → **emu23_debug_manual_v1_3.md**（★v1.3 で拡張子を実体に合わせ `.md` へ是正★ v1.2 までは `.docx` でありながら実体は UTF-8 プレーンテキストだった＝KY41 4点整合） |
| 関連設計書 | **emu23_device_design_v1_11.md** / **emu23_interactive_mode_design_v1_6.md** / ~~emu23_interactive_mode_design_v1_2.md~~ / emu23_v108_mmu_port_design_v1_1.md / emu23_v105_design_v1_0.md / emu23_v103_design_v1_4.md / emu23_device_design_v1_3.docx |
| ステータス | 確定 |

# **改版履歴**

| **版数** | **日付** | **担当** | **変更内容** |
| --- | --- | --- | --- |
| v1.0 | 2026-05-17 | 開発チーム | 初版作成（emu23 v1.03対応、kaizen.txt 原則24に基づき独立文書として整備） |
| v1.1 | 2026-06-06 | 開発チーム | emu23 v1.05 対応。スタック watermark 計測オプション（-w / --wm-steps / --wm-warmup）を §2.2・§2.3・§5 に追記。ビルド方法・バージョン確認のバージョン表記を v1.03→v1.05 に更新。 |
| **v1.2** | **2026-06-27** | **開発チーム** | **emu23 v1.09 対応。①§2.2 オプション一覧に `--mmu`（v1.08 で復活した FM-11方式16ページMMU の有効化）と `-it`（v1.09 新規・インタラクティブモード）を追記。②§2.3 にオプション組み合わせ例（MMU有効起動・対話起動）を追記。③§3.2 REPLコマンド一覧に MMUデバッガコマンド（`mmu` / `mmu en` / `mmu dis` / `mmu ptr N V` / `physmem`。いずれも `--mmu` モード時のみ有効）を追記。④ビルド方法・バージョン確認のバージョン表記を v1.05→v1.09 に更新。v1.1 までの記述は欠落させず保持。** |
| **v1.3** | **2026-08-12** | **【emu23 v1.09→v1.12 追従：Phase B' 完了（B-1 TKT-03 + B-C 改良2）】**①**ファイル名の拡張子を `.docx`→`.md` に是正**（v1.2 までは実体が UTF-8 プレーンテキストだった＝KY41 4点整合）。対象エミュレータを v1.09→**v1.12** に更新。②**§2.2 オプション表に 3 件追加**：`--bus-pullup`（v1.12 以降は既定有効のため no-op・互換受理）／**`--no-bus-pullup`**（v1.11 挙動へ切り戻し・障害切り分け用）／**`--strict-mmio`**（未接続 MMIO アクセス検出時点で停止・`--bus-pullup` と独立）。③**§2.4 として新節「MMIO 誤アクセスの検知」を新設。**壊れたポインタが MMIO 空間を指すバグは v1.11 まで検知不能だった（`mem[]` にフォールスルーして RAM のように読み書きできた）が、v1.12 のデコード層新設により検知可能になった。出力タグ `[MMIO-UNMAPPED]`（未接続）／`[MMIO-UNSUP]`（実装済だがアクセス幅未対応＝現状 `UART_BAUD` の 8bit のみ）／`[MMIO-SUMMARY]`（総件数・0件でも出力）と、抑制ルール（同一PC初回のみ・上限16件・打切り後も計数継続）を記載。④**★§2.4.3 に `--strict-mmio` が必要な理由を明記★**：未接続読出値 `$FFFF` は YUI OS の `IDX_NIL`（IPCキュー終端番兵・`kernel_v12_11.asm` L292）と一致するため、**誤アクセスが「キューは空」という正常系として受理され、例外も出ずタスクが静かに寝る**。症状が発生地点から遠く離れて現れるこの構造を実コード付きで解説し、`--strict-mmio` で発生地点を押さえる手順を示した。同種の衝突（`$FFFE`=`ERR_IPC_NOSLOT`・`$FE01`-`$FE0B`=FileMgr エラーコード）も併記。⑤**§2.4.5／§2.4.6 に運用上の注意**：サマリは `atexit` 出力のため **`HALT` 到達時のみ**取得可能（YUI OS は待機ループで HALT しないため取得不可・Dhrystone 等を使う）／警告とサマリは **stderr** に出るため `-q` の byte-exact 比較は **stdout のみ**を対象とすること。関連：`emu23_device_design_v1_11.md` §4.3 / §12.10。v1.2 までの記述は削除せず保持。 | Claude |
| **v1.4** | **2026-08-14** | **開発チーム** | **【emu23 v1.12→v1.13 追従：Phase B'' B-2/B-3（EMU-A 引数解析 + EMU-B シンボル容量）】**①対象エミュレータを v1.12→**v1.13** に更新（表紙・バージョン確認例）。②**§2.1 基本書式に「v1.13 での引数解析の変更（EMU-A 解消）」を追記**。v1.12 までは `argv[2]`/`argv[3]` を無条件に `.dbg`/`.sym` と位置解釈していたため `emu23 prog.bin -i uart.bin --disk d.img` で `-i` が `.dbg`・`uart.bin` が `.sym` と誤認され `Loaded 0 label symbols` になっていた。v1.13 ではオプションとその引数が**消費済み**とマークされ位置解釈の対象外となるため、自動導出が正しく機能する（実測 0→1164）。形式別の動作表（従来形／非推奨形／自動導出形）を掲載。③**§2.2 オプション表に `--dbg FILE` / `--sym FILE` を追加**（位置引数より優先・失敗時は `[DBG-NOTFOUND]`/`[SYM-NOTFOUND]`・値省略は `exit(1)`）。④**§2.5 として新節「シンボル読込の診断」を新設**：v1.12 までは `fopen` 失敗を黙殺していたため「読めていない」ことに気付けなかった経緯、警告タグ3種（`[SYM-NOTFOUND]`/`[DBG-NOTFOUND]`/`[SYM-TRUNCATED]`）、**自動導出の失敗は仕様として黙殺される**（＝「警告が出ない＝読めている」ではない）点、読込件数の確認手順（`-q` を外して `Loaded N label symbols` を見る）を記載。⑤**★§9 制限事項表の `MAX_SYM=128` を 2048 に是正★**（`yuios_road2.sym` は 1,164 シンボルあり v1.12 まで**先頭128本しか読めず警告も出なかった**＝EMU-B）。旧記述は取り消し線で保持＝KY41。⑥**同表に「シンボル名の最大長: 31文字」を新規追加**（★既知の制約 EMU-D★：31文字超は黙って切り詰められ、検索キー側は切り詰められないため `strcmp` が一致せず**そのラベルで BP を張れない**。現行最大26文字ゆえ未発現。別チケット `emu23_ticket_EMU_D_symname_v1_0.md` 起票済）。⑦**★§2.5.4 に実測事実を明記★**：Dhrystone の測定値（`Dhrystones/sec`・`cycles`）は **stderr** 出力であり stdout に出るのは `P:20` のみ。回帰ゲートが `2>&1` 合流後に grep しているのはこのためで、**emu23 が stderr に出す警告文言に `Dhrystones/sec`/`cycles`/`P:` を含めてはならない**。⑧引数総数 64 個超は `exit(1)`。関連：`emu23_argsym_design_v1_0.md` / `yuios_build_procedure_v1_14.md` / `tool_version_ledger_v1_15.md`。v1.3 までの記述は削除せず保持。 | Claude |

# **§1  概要**

## **1.1  このマニュアルについて**

本書はYSD8800エミュレータ emu23（ISA 2.3対応）のユーザ向けデバッグマニュアルです。

チャットをまたぐたびにソースコードを読み直す非効率を解消するため、コマンドラインオプション・インタラクティブREPLコマンド・デバッグ手順を一元化しています。

本書は kaizen.txt 原則24「emu23デバッグマニュアルを独立文書として整備する」に基づき作成されました。

## **1.2  emu23の位置づけ**

emu23はYSD8800 ISA 2.3仕様に準拠したソフトウェアエミュレータです。以下の仮想デバイスをシミュレートします。

| **デバイス名** | **チップ型番** | **機能概要** |
| --- | --- | --- |
| UART | YSD8001 | シリアル通信・RX/TX割り込み（IRQ1経由） |
| タイマー | YSD8002 | 周期割り込み（IRQ0）・Dhrystone計測ストップウォッチ |
| ストレージ | YSD8003 | 512Bセクタ読み書き・完了IRQ（IRQ1経由） |
| 割り込みコントローラ | YSD8004 | IRQ_STAT/IRQ_MASK・優先制御 |

## **1.3  ビルド方法**

gcc -std=c99 -O2 -Wall -Wno-unused-function emu23_v109.c -o emu23

*※ emu23のソースファイル名にはバージョン番号が含まれます。使用前にバージョンを確認してください。*

## **1.4  バージョン確認**

引数なしで起動するとバージョンと使用方法が表示されます。

$ emu23

emu23 v1.13 (2026-08-14) for YSD8800 ISA2.3

usage: emu23 prog.bin [prog.dbg [prog.sym]] [options]
  --dbg <file>          specify .dbg explicitly (overrides argv[2])
  --sym <file>          specify .sym explicitly (overrides argv[3])

  ...

# **§2  コマンドラインオプション一覧**

## **2.1  基本書式**

emu23 prog.bin [prog.dbg [prog.sym]] [options]
emu23 prog.bin [options] [--dbg <file>] [--sym <file>]      ← v1.13 以降の推奨形

prog.dbgとprog.symはprog.binのパスから自動導出されます（拡張子を .dbg / .sym に置換）。

明示的に指定しない場合、同名の .dbg / .sym ファイルが自動的にロードされます。

### **【v1.4 追記】v1.13 での引数解析の変更（EMU-A 解消）**

**v1.12 まで**は `argv[2]` を `.dbg`、`argv[3]` を `.sym` として**無条件に位置解釈**していた。
このためオプションを併用すると誤認が起きていた。

```
【v1.12 まで】
emu23 prog.bin -i uart.bin --disk d.img
               ^^^^^^^^^^  ^^^^^^^^^
               → -i が .dbg、uart.bin が .sym と誤認され
                 fopen 失敗を黙殺 → "Loaded 0 label symbols" のまま継続

【v1.13 以降】
オプションとその引数は「消費済み」とマークされ、位置解釈の対象外になる
               → .dbg / .sym は自動導出され正しく読まれる（実測 Loaded 1164）
```

**明示指定したい場合は位置引数ではなく `--dbg` / `--sym` を使う（推奨）。**

```
emu23 yuios_road2.bin --sym yuios_road2.sym --disk disk.img -q
```

| 形式 | v1.13 での動作 |
|---|---|
| `prog.bin prog.dbg prog.sym [opts]` | **従来どおり動作**（`.dbg`/`.sym` はオプションに消費されないため） |
| `prog.bin prog.sym [opts]` | **非推奨**。`.sym` が `load_dbg()` に渡る（v1.12 と同じ）。`--sym` を使うこと |
| `prog.bin [opts]` | `.dbg`/`.sym` を自動導出（**v1.13 で正しく読まれるようになった**） |

> **★注意★** `argv[1]` は必ずプログラム（`.bin`）である。
> オプションをプログラム名より**前**に置くことはできない（v1.13 でも不変）。

**関連する新規オプション・警告は §2.5 を参照。**

## **2.2  オプション詳細**

| **オプション** | **形式** | **説明** |
| --- | --- | --- |
| -n N | -n <整数> | N命令実行してトレースを出力し終了（バッチモード） |
| -b ADDR | -b <16進アドレス> | ADDRに最初に到達した時点からトレース開始（-nと併用） |
| -q | -q | 静粛モード：HALT まで実行、UART出力のみ stdout に表示 |
| -it | -it | インタラクティブモード（v1.09〜）：ターミナルを raw mode 化し、キーボード入力を1文字ずつ UART RX へ流し込む。YUI OS Shell 等の対話操作に使用。エコーは行わない（YUI OS 側 UART ドライバの責務）。終了は Ctrl+D（0x04）。`-q` とは排他（同時指定はエラー）。※内部的に診断ログ抑制（`-q` 相当）が有効化される |
| -i FILE | -i <ファイルパス> | UART受信データをファイルから供給（未指定時はstdin非ブロッキング） |
| --disk FILE | --disk <イメージパス> | YSD8003ストレージに接続するディスクイメージファイル |
| --mmu | --mmu | FM-11方式16ページMMU を有効化（v1.08〜復活）。4KB/ページ・16論理ページ→256物理ページ、PTR[16]@\$FF00 / MCR@\$FF10。無効時（既定）は恒等写像で MMU 無効版と byte-exact 非干渉。本オプション指定時のみ REPL の MMUデバッガコマンド（mmu / physmem・§3.2）が有効化される |
| -m ADDR N | -m <16進アドレス> <整数> | 実行終了後にADDRから Nワードをダンプ（-nと併用） |
| -w / --watermark | -w | スタック watermark 計測：各タスク（tid 0〜15）のコール／データスタック最深値と guard 破壊を測定し、終了後に stderr へ出力（v1.05〜） |
| --wm-steps N | --wm-steps <整数> | -w 使用時、常駐OS（HALTしない）向けの実行打切り上限命令数（既定 2000000）。-w 無指定時は無効（v1.05〜） |
| --wm-warmup N | --wm-warmup <整数> | -w 使用時、起動初期 N サイクルを測定対象外とする（既定 2000）。_kstart の一過性 SP/X 値の誤検出を除外（v1.05〜） |
| **--bus-pullup** | **--bus-pullup** | **未接続 MMIO 領域の読出を `$FF`/`$FFFF`（プルアップ模倣）にし、書込を破棄する（v1.12〜）。★v1.12 以降は既定で有効のため本オプションは no-op★**（互換のため受理する） |
| **--no-bus-pullup** | **--no-bus-pullup** | **v1.11 までの挙動（未接続 MMIO は `mem[]` へフォールスルー＝RAM として振る舞う）に切り戻す（v1.12〜）。**プルアップ起因が疑われる障害の切り分け手段 |
| **--strict-mmio** | **--strict-mmio** | **未接続 MMIO アクセスを検出した時点で実行を停止し、アドレス・PC・アクセス種別を報告する（v1.12〜）。`--bus-pullup` の有無とは独立に機能する。**誤アクセスの発生地点そのものを押さえるために使う（§2.4 参照） |
| **--dbg FILE** | **--dbg <ファイルパス>** | **`.dbg` を明示指定する（v1.13〜）。位置引数 `argv[2]` より優先される。**ファイルが開けない場合は **stderr** に `[DBG-NOTFOUND]` を出力（自動導出時の失敗は従来どおり黙殺）。値を省略すると `emu23: option --dbg requires a filename` を出して `exit(1)` |
| **--sym FILE** | **--sym <ファイルパス>** | **`.sym` を明示指定する（v1.13〜）。位置引数 `argv[3]` より優先される。**オプション併用時に確実にシンボルを読ませたい場合の推奨形（§2.1・§2.5 参照）。失敗時の挙動は `--dbg` と同型（`[SYM-NOTFOUND]`） |

## **2.3  オプション組み合わせ例**

### **2.3.1  静粛実行（Dhrystoneベンチマーク等）**

$ emu23 dhry.bin -q

*※ UART出力のみ表示。**'**-q**'** は Dhrystone等の自動実行に使用。*

### **2.3.2  バッチトレース（最初の200命令を表示）**

$ emu23 yuios.bin -n 200

### **2.3.3  特定アドレス到達後に100命令トレース**

$ emu23 yuios.bin yuios.dbg yuios.sym -b 1A00 -n 100

*※ yuios.symから先にアドレスをgrepして調べると便利です（§3.2参照）。*

### **2.3.4  UARTコマンド入力をファイルから供給**

$ echo -n 'ls\r\n' > cmd.txt

$ emu23 yuios.bin -i cmd.txt -q

### **2.3.5  ストレージ付き起動**

$ emu23 yuios.bin --disk disk.img -q

*※ disk.imgが存在しない場合は新規作成されます。*

### **2.3.6  アドレス到達後トレース＋終了後メモリダンプ**

$ emu23 yuios.bin yuios.dbg yuios.sym -b FC00 -n 50 -m FC20 8

*※ FC00到達後50命令トレース、終了後 $FC20から8ワードをダンプ。*

### **2.3.7  スタック watermark 計測（v1.05〜）**

常駐型OS（HALTしない）のスタック消費を測る場合は -q -w と --wm-steps を併用します。

$ emu23 yuios.bin --disk disk.img -i /dev/null -q -w --wm-steps 10000000

*※ 各タスクのコール／データスタック使用バイト数（/128B）と stack guard（$FC00-$FC3F の $A55A 維持）の検査結果が stderr に出力されます。stdout（UART出力）は汚染しません。*

*※ 起動初期の一過性 SP/X 値が誤検出される場合は --wm-warmup で除外サイクル数を調整します（既定2000）。*

$ emu23 yuios.bin --disk disk.img -i /dev/null -q -w --wm-warmup 2000

### **2.3.8  インタラクティブモードで YUI OS Shell を対話操作（v1.09〜）**

YUI OS（Ph.6 常駐 Shell）を起動し、ターミナルからリアルタイムにコマンドを打ち込む場合は -it を使用します。

$ emu23 yuios.bin --disk disk.img -it

*※ ブート後、Shell プロンプト（YUI> 等）にキー入力したコマンドが1文字ずつ UART RX へ渡り、ver / help / ps / run / mem / kill / ls / cat 等が実行できます。入力文字のエコー表示は YUI OS 側 UART ドライバ／Shell が行います（emu23 はエコーしません）。終了は Ctrl+D。*

*※ -it は -q と排他です（同時指定はエラー）。-it 指定時は診断ログが自動抑制され、UART 出力のみが画面に出ます。*

*※ パイプ／リダイレクトで入力を供給する場合、終端の Ctrl+D（0x04）検出は RX バッファ滞留により不安定になることがあります。Ctrl+D 終了の確実な確認は実端末（または PTY）での1文字ずつの操作で行ってください。*

### **2.3.9  MMU を有効化して起動（v1.08〜復活）**

FM-11方式16ページMMU を有効化する場合は --mmu を付けます。REPL の MMUデバッガコマンド（§3.2）も本指定時のみ有効になります。

$ emu23 yuios.bin --disk disk.img --mmu

*※ --mmu 無指定時（既定）は MMU 無効で、MMU 有効版とメモリアクセス結果は byte-exact 非干渉です。*

## **2.4  【v1.3 新設】MMIO 誤アクセスの検知（v1.12〜）**

### **2.4.1  何が検知できるか**

emu23 v1.12 で MMIO アドレスデコード層が新設され、**MMIO 空間（`$FC80`-`$FFFF`）のうちデバイスが実装されていないアドレスへのアクセスを検知できる**ようになった。壊れたポインタが MMIO 空間を指すバグは、従来 emu23 では検知できなかった（`mem[]` にフォールスルーして RAM のように読み書きできてしまうため）。

出力は **stderr** に出る。

```
[MMIO-UNMAPPED] rd16 addr=FCB8 pc=0A3C
[MMIO-UNMAPPED] wr16 addr=FF20 pc=0B14 val=1234
[MMIO-UNMAPPED] suppressed after 16 reports
[MMIO-UNSUP] rd8 addr=FC86 pc=0C20
[MMIO-SUMMARY] unmapped=39 unsup=0
```

| タグ | 意味 |
| --- | --- |
| `[MMIO-UNMAPPED]` | **未接続アドレス**へのアクセス（デバイスが存在しない） |
| `[MMIO-UNSUP]` | **実装済レジスタだが、そのアクセス幅では未対応**（現状 `UART_BAUD`＝`$FC86` への 8bit アクセスのみ。16bit 専用のため） |
| `[MMIO-SUMMARY]` | 終了時の総件数。**0 件でも必ず出力される** |

### **2.4.2  警告の抑制ルール**

未接続アクセスがループ内で起きるとログが埋まるため、抑制が入っている。

- **同一 PC からの警告は初回のみ**出力
- **上限 16 件で打切り**（`suppressed after 16 reports` を出力）
- **打切り後も計数は継続**するため、`[MMIO-SUMMARY]` の件数は常に正確

上の例では実アクセス 39 件に対し警告 8 行、サマリは 39 件を報告している。

### **2.4.3  ★`$FFFF` は正常値に化ける — なぜ `--strict-mmio` が要るか★**

未接続読出は実機のバスがプルアップされているため `$FFFF` を返す。ところが **YUI OS では `$FFFF` が `IDX_NIL`（IPC キューの終端番兵）と一致する**（`kernel_v12_11.asm` L292）。

```asm
    LDW  A, [X + #30]           ; ipc_queue_head を読む
    CMPI A, #$FFFF              ; == IDX_NIL?
    BNE  _ipc4recv_dequeue      ; 違えば → メッセージあり
    ; 一致 → キューは空 → WAIT_IPC で寝る
```

壊れた `X` が未接続領域を指した場合、読み出した `$FFFF` は **「キューは空」という完全に正常な状態として受理される。** 例外も出ず、タスクは設計どおり寝る。症状は「なぜかタスクが起きてこない」という形で、**バグの発生地点から遠く離れた場所・時刻に現れる**。

**このとき `--strict-mmio` を付けると、誤アクセスした瞬間に停止して PC を教えてくれる。**

```
./emu23 yuios.bin -q --disk disk.img --strict-mmio
  [MMIO-UNMAPPED] rd16 addr=FC88 pc=0204
  [MMIO-STRICT] unmapped access addr=FC88 pc=0204 rd16 -> abort
```

同種の衝突は `$FFFE`（`ERR_IPC_NOSLOT`）、`$FE01`-`$FE0B`（FileMgr エラーコード）にもある。**`$FF` 系の値はこのプロジェクトで「意味を持つ値」として多用されているため、未接続読出値と紛れやすい。**

### **2.4.4  使い方の指針**

| 状況 | 推奨 |
| --- | --- |
| 通常のデバッグ | 既定のまま（警告は出るが停止しない） |
| **原因不明のハング・タスクが起きない** | **`--strict-mmio` を付けて再実行**。誤アクセスがあれば発生地点で止まる |
| v1.12 で挙動が変わった疑い | `--no-bus-pullup` で v1.11 相当に戻して比較 |
| 正常性の確認 | `[MMIO-SUMMARY]` が `unmapped=0 unsup=0` であること |

### **2.4.5  ★注意：サマリは HALT 到達時のみ出る★**

サマリは `atexit` で出力されるため、**`timeout` で強制終了した場合は出力されない**。YUI OS は待機ループ（`BEGIN TASK-SLEEP AGAIN`）で HALT しないため、**YUI OS 実行ではサマリを取得できない**。サマリで確認したい場合は Dhrystone 等の HALT で終了するプログラムを使う。

```
./emu23 dhry.asm.bin -q 2>&1 >/dev/null | grep MMIO
  → [MMIO-SUMMARY] unmapped=0 unsup=0
```

### **2.4.6  ★注意：警告は stderr に出る★**

`-q` の出力を期待値と byte-exact 比較する場合、**stdout のみを比較対象**とすること。`2>&1` で混ぜると MMIO サマリが差分として現れる。

## **2.5  【v1.4 新設】シンボル読込の診断（v1.13〜 / EMU-A・EMU-B）**

### **2.5.1  なぜ「シンボルが読めていない」ことに気付けなかったか**

v1.12 までの `load_dbg()` / `load_sym()` は **`fopen()` 失敗時に黙って return** していた。
このため誤ったファイルを渡しても**エラーにならず実行が継続**し、
ラベル指定の BP だけが使えないという分かりにくい症状になっていた。

```
(emu) b _kernel_irq_dispatch
(emu) Unknown label: _kernel_irq_dispatch     ← ここで初めて気付く
```

**v1.13 では、明示的に指定したファイルが読めない場合に必ず警告を出す。**

### **2.5.2  警告タグ一覧（すべて stderr・`-q` でも出力）**

| タグ | 意味 | 出る条件 |
|---|---|---|
| `[SYM-NOTFOUND]` | `.sym` が開けない | **明示指定時のみ**（`--sym` / 位置引数） |
| `[DBG-NOTFOUND]` | `.dbg` が開けない | **明示指定時のみ**（`--dbg` / 位置引数） |
| `[SYM-TRUNCATED]` | シンボル数が `MAX_SYM`(2048) を超えた | 打切り発生時に**常に** |

```
[SYM-TRUNCATED] loaded=2048 skipped=317 last=_kernel_irq_dispatch (MAX_SYM=2048) - label BP may be incomplete
```

`last=` は**最後に読めたラベル名**である。目的のラベルが
「読めた側」か「落ちた側」かを判断する手がかりになる。

> **★自動導出の失敗は黙殺される（仕様）★**
> `.dbg` を持たないビルドは普通にあるため、`change_ext()` による自動導出の
> 失敗は警告しない。**「警告が出ない＝読めている」ではない**点に注意。
> 読めた件数は非 `-q` 実行時の `Loaded N label symbols` で確認する。

### **2.5.3  シンボルが読めているかの確認手順**

```
$ ./emu23 yuios_road2.bin --disk disk.img        ← -q を付けない
Loaded 56416 bytes from yuios_road2.bin
Loaded 1164 label symbols                        ← ★ここを見る★
```

`Loaded 0 label symbols` なら読めていない。`--sym` で明示指定する。

> **★`-q` では表示されない★**
> 件数表示は `!quiet_mode` 配下にあるため、`-q` / `-it` 実行時は出ない
> （`-it` は内部的に `-q` 相当になる）。確認は `-q` を外して行うこと。

### **2.5.4  回帰比較時の注意（§2.4.6 と同じ原則）**

**本節の警告はすべて stderr に出力される。**
`-q` の byte-exact 比較は **stdout のみ**を対象とすること。

> **★実測で判明した重要事項（v1.4 追記）★**
> Dhrystone の測定値 `--- Dhrystones/sec = 819 ---` と `cycles=48785` は
> **stderr** に出力される（stdout に出るのは `P:20` のみ）。
> `Makefile` の回帰ゲートが `-q 2>&1 | grep -iE 'Dhrystones/sec|cycles|P:'` と
> **合流させているのはこのため**である。
> したがって emu23 が stderr に出す警告文言には
> **`Dhrystones/sec` / `cycles` / `P:` を含めてはならない**（ゲートに混入する）。

### **2.5.5  その他の制限**

- 引数の総数が **64個**を超えると `emu23: too many arguments (max 64)` で `exit(1)`。
- **シンボル名 31 文字超は切り詰められ BP を張れない（EMU-D・未解決）**。
  現行の最大は 26 文字のため未発現。`emu23_ticket_EMU_D_symname_v1_0.md` 参照。

---

# **§3  インタラクティブREPLコマンド**

## **3.1  REPLの起動**

$ emu23 yuios.bin

YSD8800 ISA2.3 Emulator (emu23 v1.09) — reset vector = 0100

Type 'help' for commands.

*※ --mmu 指定時はバナーが「(emu23 v1.09 +MMU)」と表示され、MMUデバッガコマンド（§3.2）が利用可能になります。*

PC=0100 A=0000 B=0000 X=0000 SP=FC7E F=00 | _start

(emu) _

*※ 各プロンプトにPC・レジスタ状態が表示されます。.symファイルが読まれている場合はPCのシンボル名も表示されます。*

## **3.2  コマンド一覧**

| **コマンド** | **書式** | **説明** |
| --- | --- | --- |
| s | s [N] | N命令ステップ実行（N省略時=1）。ブレークポイント到達で停止 |
| c | c | HALTまたはブレークポイントまで連続実行 |
| t | t | HALTまたはブレークポイントまで連続実行。各命令実行後にレジスタダンプ |
| b | b <addr│label> | ブレークポイントを設定。アドレス（16進）またはシンボル名で指定 |
| b | b | 引数なし：設定済みブレークポイント一覧表示 |
| bd | bd <N> | ブレークポイントN番を削除 |
| regs | regs | 全レジスタ値を表示 |
| disas | disas [addr [n]] | addrからn命令逆アセンブル（デフォルト: 現在PC、10命令） |
| mem | mem [addr [n]] | addrからnバイトをHEXダンプ（デフォルト: 現在PC、64バイト） |
| memw | memw [addr [n]] | addrからnワードをHEXダンプ（デフォルト: 現在PC、8ワード） |
| irq | irq <id> | IRQをソフトウェア注入（id: IRQ番号+1） |
| reset | reset | CPU初期化（メモリは保持。リセットベクタから再起動） |
| mmu | mmu | 【--mmu モード時のみ】MMU状態（MCR・PTR[0..15] の論理→物理対応）をダンプ |
| mmu en | mmu en | 【--mmu モード時のみ】MMU を有効化（MCR bit0=1） |
| mmu dis | mmu dis | 【--mmu モード時のみ】MMU を無効化（MCR bit0=0） |
| mmu ptr | mmu ptr <N> <V> | 【--mmu モード時のみ】PTR[N]（N=0〜15）に物理ページ番号 V（16進・0〜FF）を設定 |
| physmem | physmem <A> [n] | 【--mmu モード時のみ】物理アドレス A（16進・20bit空間）から n バイトを HEXダンプ（n省略時=16） |
| q | q | エミュレータ終了 |
| help / ? | help | コマンド一覧を表示（--mmu モード時は MMUコマンドも併記） |

## **3.3  ブレークポイントの使い方**

### **3.3.1  アドレス指定**

(emu) b 1A00

Breakpoint 0 set at 1a00

### **3.3.2  シンボル名指定（.symファイルが必要）**

(emu) b WORD_UART_DRV_TASK

Breakpoint 0 set at 1a00

*※ .symファイルは hasm23 が生成します。prog.bin と同名で同ディレクトリに置くと自動ロードされます。*

### **3.3.3  コマンドラインでシンボルアドレスを調べる**

$ grep WORD_UART_DRV_TASK yuios.sym

WORD_UART_DRV_TASK 1A00

$ emu23 yuios.bin yuios.dbg yuios.sym -b 1A00 -n 50

### **3.3.4  ブレークポイントの一覧・削除**

(emu) b

Num  Addr

0    1a00

1    2000

(emu) bd 0

Breakpoint 0 deleted

## **3.4  メモリダンプの使い方**

### **3.4.1  バイトダンプ**

(emu) mem FC00 32

*※ $FC00 から 32バイトをダンプ。*

### **3.4.2  ワードダンプ（16ビット）**

(emu) memw FC00 8

*※ $FC00 から 8ワード（16バイト）をダンプ。アドレス・値ともに偶数前提。*

### **3.4.3  逆アセンブル**

(emu) disas 1A00 20

*※ $1A00 から 20命令を逆アセンブル表示。*

## **3.5  IRQ注入の使い方**

irq コマンドはソフトウェアからIRQを注入できます。IRQ番号と irq_pending の対応については §5.1 を参照してください。

(emu) irq 1

** IRQ 1 injected **

**⚠ IRQ注入は irq_pending を直接書き換えます。現在 pending 中のIRQが上書きされる点に注意。**

# **§4  クラッシュ解析の定石手順**

## **4.1  全体フロー**

emu23のクラッシュ・ハング解析は以下の順序で実施します。

| **手順** | **作業** | **コマンド例** |
| --- | --- | --- |
| Step 1 | 異常発生タイミング（サイクル数）を特定 | コンソール出力・HALT時のサイクル番号を確認 |
| Step 2 | 直前命令群をトレースで取得 | emu23 prog.bin -n <サイクル数> 2>&1 │ tail -30 |
| Step 3 | PC・SP・レジスタ値で原因箇所を絞り込む | regsコマンド、disasコマンドで確認 |
| Step 4 | 必要なら特定アドレスのブレークポイントで精査 | emu23 prog.bin -b <ADDR> -n 20 |
| Step 5 | メモリ・スタック領域をダンプして実測値確認 | memw / mem コマンド |

## **4.2  典型的な異常パターンと対処**

### **4.2.1  $0000ジャンプ（ゼロへの暴走）**

スタック破壊またはNULLポインタコールが原因。

PC=0000 A=xxxx B=xxxx ...

対処手順：

- 暴走直前のSP値を確認（スタック下限アドレスを下回っていないか）

- 暴走直前のPCの命令を逆アセンブルして JSR/JMP 先を確認

- -n オプションでトレースを遡りスタック破壊のタイミングを特定

### **4.2.2  ALIGNMENT EXCEPTION**

奇数アドレスへの16ビットアクセス。IRQ3が発火します。

!! ALIGNMENT EXCEPTION (READ) @F801

対処手順：

- スタックポインタが奇数アドレスにずれていないか確認（memw FC コマンド等）

- SPを変更する命令（PUSH/POP等）の前後でSP値をトレース

### **4.2.3  HALT後の状態確認**

HALTが発生しても[HALTED]プロンプトでREPLは継続します。

[HALTED] PC=xxxx ...

[HALTED] (emu) regs

[HALTED] (emu) memw FC00 16

*※ HALT後でも regs / mem / memw / disas / q は使用可能です。*

## **4.3  スタック使用量の計測**

スタック破壊デバッグには実測SP最小値の確認が有効です。

$ emu23 prog.bin -b <タスク開始アドレス> -n 10000 2>&1 | grep SP= | awk -F= '{print $2}' | cut -d' ' -f1 | sort | head -1

*※ SPの最小値が設計上のスタック下限（設計書 §スタックマップ参照）を下回っていないか確認します。*

## **4.4  バグ種別ごとのデバッグ初手**

kaizen.txt 原則28に基づき、バグ種別によってアプローチを変えます。

| **バグ種別** | **推奨デバッグ初手** |
| --- | --- |
| IRQタイミング依存 | emu23トレース初手。-n でタイミングを狭める |
| スケジューラ状態遷移 | emu23トレース初手。CUR_TASKとstateをmemwで確認 |
| スタック破壊・PC異常 | emu23トレース初手。SP最小値計測 |
| 特定実行順序のみ発生 | emu23トレース初手。ブレークポイントで状態を段階確認 |
| 特定命令のロジックエラー | 論理分析 + disasコマンドで確認 |
| 設計書との実装ミス（オフセット違い等） | 論理分析 + memwコマンドでフィールド確認 |

# **§5  IRQ・割り込み関連**

## **5.1  IRQ番号と irq_pending の対応表**

emu23内部の irq_pending 値はISA仕様のIRQ番号から +1 オフセットとなっています。

| **IRQ名称（ISA仕様）** | **ISA IRQ番号** | **irq_pending値** | **割り込みベクタアドレス** |
| --- | --- | --- | --- |
| タイマー（YSD8002） | IRQ0 | 1 | $0002 |
| デバイス（YSD8004経由） | IRQ1 | 2 | $0004 |
| 予約 | IRQ2 | 3（予約） | $0006（予約） |
| アラインメント例外 | IRQ3 | 3 | $0006 |
| SYSCALLトラップ | IRQ4 | 4 | $0008 |

**⚠ irq_pending値とISA IRQ番号はズレています。混同しないよう注意してください。**

計算式：

ベクタアドレス = irq_pending × 2

## **5.2  YSD8004 IRQ_STAT ビット定義**

| **ビット名** | **ビット位置** | **ビット値** | **内容** |
| --- | --- | --- | --- |
| IRQ_STAT_BIT_UART_RX | bit0 | 0x0001 | YSD8001 UART受信完了 |
| IRQ_STAT_BIT_STOR | bit1 | 0x0002 | YSD8003 ストレージ完了/エラー |
| IRQ_STAT_BIT_UART_TX | bit2 | 0x0004 | YSD8001 UART送信レジスタ空き（TDRE） |

## **5.3  IRQ優先制御（v1.03の動作）**

v1.03では ysd8004_raise() に IRQ pending 上書き保護機構が実装されています。

| **既存irq_pending** | **新規IRQ1要求** | **動作** |
| --- | --- | --- |
| -1（何もなし） | IRQ1（=2） | 正常にpending化 |
| 2（IRQ1） | IRQ1（=2） | 上書き無害（同一） |
| 4（SYSCALL） | IRQ1（=2） | IRQ1で上書き（優先度正当） |
| 1（IRQ0タイマー） | IRQ1（=2） | 保護：irq_statに保持、IRET後に再評価機構で復活 |
| 3（IRQ3アラインメント） | IRQ1（=2） | 保護：同上 |

*※ IRQ_STAT再評価機構：irq_pending **<** 0 かつ irq_stat != 0 の場合、毎命令実行後にIRQ1が自動復活します。*

## **5.4  割り込みハンドラデバッグの注意**

**⚠ CUR_TASK が指すタスクは「現在実行中のタスク」とは限りません（アイドル中も前回のtidが残る）。**

IRQ0_HANDLERのデバッグでは、CUR_TASKのstateフィールドを必ず確認してください。

(emu) memw <CUR_TASKアドレス> 8

*※ kaizen.txt 原則25「IRQハンドラの全状態×全イベント表」参照。*

# **§6  MMIOアドレスマップ**

## **6.1  全体マップ**

| **アドレス範囲** | **デバイス** | **用途** |
| --- | --- | --- |
| $FC80 - $FC86 | YSD8001 UART | UART_TX / RX / STAT / BAUD |
| $FC90 - $FC9E | YSD8002 タイマー | TCR / PERIOD / CYCLE / SW_RUNS / SCORE |
| $FCA0 - $FCB0 | YSD8003 ストレージ | SD_CMD / STAT / LBA / BUF_PTR / DATA / IRQ_CTRL / DISK |
| $FCB2 - $FCB4 | YSD8004 割り込みコントローラ | IRQ_STAT / IRQ_MASK |

## **6.2  YSD8001 UARTレジスタ**

| **アドレス** | **レジスタ名** | **説明** |
| --- | --- | --- |
| $FC80 | UART_TX | 送信バッファ（書き込み専用）。書き込みで即時putchar出力 |
| $FC82 | UART_RX | 受信バッファ（読み出し専用）。RX_READY=1の時に有効 |
| $FC84 | UART_STAT | bit0=TX_READY  bit1=RX_READY（WTC: bit1書き込みでクリア） |
| $FC86 | UART_BAUD | ボーレート分周値（予約定義・動作影響なし） |

*※ UART_STAT は Write-to-Clear 方式。bit1(RX_READY)に1を書くとクリアされます。*

## **6.3  YSD8002 タイマーレジスタ**

| **アドレス** | **レジスタ名** | **説明** |
| --- | --- | --- |
| $FC90 | TCR | bit0=TIMER_EN  bit1=IRQ_EN  bit2=SW_START  bit3=SW_STOP  bit4=SW_BUSY(R) |
| $FC92 | PERIOD_HI | IRQ周期 上位16bit（単位: CPUクロック数） |
| $FC94 | PERIOD_LO | IRQ周期 下位16bit |
| $FC96 | CYCLE_LO | 現在サイクルカウンタ 下位16bit（読み出し時HI側をラッチ） |
| $FC98 | CYCLE_HI | 現在サイクルカウンタ 上位16bit（CYCLE_LOラッチ値） |
| $FC9A | SW_RUNS | Dhrystoneストップウォッチ：Number_Of_Runs設定値 |
| $FC9C | SCORE_LO | ストップウォッチ計測サイクル数 下位16bit（読み出し時HI側ラッチ） |
| $FC9E | SCORE_HI | ストップウォッチ計測サイクル数 上位16bit（SCORE_LOラッチ値） |

*※ CYCLE / SCORE は 32bit値を 2回読みで取得します。必ず LO を先に読んでください（HIラッチのタイミングが LO読み出し時です）。*

## **6.4  YSD8003 ストレージレジスタ**

| **アドレス** | **レジスタ名** | **説明** |
| --- | --- | --- |
| $FCA0 | SD_CMD | 0=READ_SETUP  1=WRITE_SETUP  2=EXEC |
| $FCA2 | SD_STAT | bit0=BUSY  bit1=ERROR  bit2=READY |
| $FCA4 | SD_LBA_LO | LBAアドレス 下位16bit |
| $FCA6 | SD_LBA_HI | LBAアドレス 上位16bit |
| $FCA8 | SD_BUF_PTR | セクタバッファポインタ（0-511） |
| $FCAA | SD_DATA | PIOデータ転送（読み書きで BUF_PTR が自動インクリメント） |
| $FCAC | SD_IRQ_CTRL | bit0=IRQ_EN  bit1=ERR_EN |
| $FCAE | SD_DISK_LO | 総セクタ数 下位16bit（読み出し専用） |
| $FCB0 | SD_DISK_HI | 総セクタ数 上位16bit（読み出し専用） |

*※ EXEC(SD_CMD=2)受理から IRQ発火まで 512サイクルの遅延があります（v1.03実装）。BUSY状態は SD_STAT の1回目の読み出しでクリアされます（BUSYラッチ方式）。*

## **6.5  YSD8004 割り込みコントローラレジスタ**

| **アドレス** | **レジスタ名** | **説明** |
| --- | --- | --- |
| $FCB2 | IRQ_STAT | 発生済みIRQステータス（Write-to-Clear）。1を書くとそのビットがクリア |
| $FCB4 | IRQ_MASK | IRQマスク（1=マスク 0=許可）。リセット値: 0x0004（UART TX IRQマスク） |

# **§7  補助ファイルフォーマット**

## **7.1  .binファイル（バイナリ）**

.binファイルはそのままメモリにロードされる生バイナリです。ロード先アドレスは $0000 固定です。

リセットベクタ（$0000-$0001）にエントリポイントアドレスが格納されています。

## **7.2  .dbgファイル（デバッグ情報）**

.dbgファイルはアドレスと行情報のマッピングです。REPLのプロンプト表示に使用されます。

AAAA NN some_source_text

*※ AAAAはアドレス（16進）、NNは行番号。hasm23が.binと同時に生成します。*

## **7.3  .symファイル（シンボルテーブル）**

.symファイルはシンボル名とアドレスのマッピングです。ブレークポイント名前指定に使用されます。

SYMBOL_NAME AAAA

*※ AAAAはアドレス（16進）。hasm23が生成します。*

### **シンボルアドレスの調べ方**

$ grep -i uart yuios.sym

WORD_UART_DRV_TASK 1A00

UART_SEND 1A20

$ emu23 yuios.bin yuios.dbg yuios.sym -b 1A00 -n 50

## **7.4  ディスクイメージ（--disk）**

YSD8003ストレージに接続するディスクイメージは 512バイト×Nセクタのフラットバイナリです。

# 4MB (8192セクタ) のディスクイメージ作成例

$ dd if=/dev/zero of=disk.img bs=512 count=8192

*※ emu23起動時に総セクタ数が自動計算されます。ファイルが存在しない場合は空ファイルが新規作成されます。*

# **§8  実践的デバッグレシピ**

## **8.1  UARTドライバのデバッグ**

### **8.1.1  UART出力が出ない場合**

- UART_TX への書き込みがあるか確認

(emu) b FC80

→ $FC80書き込み時（UART_TX）に停止

- IRQ_MASKでUART TX IRQ（bit2）がマスクされていないか確認

(emu) memw FCB2 2

*※ IRQ_MASKのリセット値は 0x0004（UART TX IRQマスク）。ドライバがマスクを外しているか確認。*

### **8.1.2  UART受信が取れない場合**

- -i FILEオプションで入力ファイルを確認

- UART_STAT (bit1=RX_READY) をポーリングしているか逆アセンブルで確認

(emu) disas <poll_addr> 10

## **8.2  ストレージドライバのデバッグ**

### **8.2.1  読み書きが完了しない場合**

- --diskオプションでディスクイメージが接続されているか確認

$ emu23 prog.bin --disk disk.img -q

- SD_STAT (bit2=READY) が 1 になっているか確認

(emu) memw FCA2 1   // SD_STAT確認

- EXEC後に IRQ1（YSD8004経由）が発火するか確認（512サイクル遅延あり）

(emu) b <IRQ1ハンドラアドレス>

(emu) c

## **8.3  タイマー・スケジューラのデバッグ**

### **8.3.1  タイマーIRQが発火しない場合**

- TCR ($FC90) bit0=TIMER_EN / bit1=IRQ_EN が 1 になっているか確認

(emu) memw FC90 1

- FLAGSレジスタのIE bit (bit7) が 1 になっているか確認

(emu) regs

*※ FLAGS=00 の場合は割り込み全体が禁止されています（IE=0）。*

### **8.3.2  スケジューラが期待タスクを選ばない場合**

- CUR_TASKのstateフィールドを確認（kaizen.txt 原則25）

(emu) memw <CUR_TASKアドレス> 4   // TCB先頭4ワード確認

**⚠ CUR_TASKはアイドル中も変化しません。stateがRUNNING(2)であることを確認してからコンテキスト保存を行うこと。**

## **8.4  Dhrystoneベンチマークの実行**

$ emu23 dhry.bin -q

実行終了（HALT）時に以下が表示されます。

[YSD8002] cpu_freq=4000000 Hz  irq_hz=100

[YSD8002] total_cycles=XXXXXX  elapsed=YYYY ms

--- Dhrystones/sec = ZZZZ ---

*※ ストップウォッチ機能（TCR SW_START/SW_STOP）を使用したコードでは SCORE レジスタから経過サイクルを読み取ります。*

# **§9  既知制約・注意事項**

## **9.1  emu23の既知制約**

| **制約事項** | **説明と対処** |
| --- | --- |
| ブレークポイントの最大数: 128個 | MAX_BP=128。通常使用では問題なし |
| **シンボルテーブルの最大数: 2048個**（v1.13 で 128→2048） | **MAX_SYM=2048。**~~MAX_SYM=128。大規模プロジェクトでは .symをgrepで検索~~（v1.12 まで。`yuios_road2.sym` は 1,164 シンボルあり **先頭 128 本しか読めず、しかも警告も出なかった**＝EMU-B）。v1.13 では全数読める。超過時は **stderr** に `[SYM-TRUNCATED] loaded=… skipped=… last=…` を出力（`-q` でも出る） |
| **シンボル名の最大長: 31文字**（★既知の制約 EMU-D★） | `sym_t.name` は `char[32]`。**31文字を超えるラベル名は黙って切り詰められ、そのラベルでは BP を張れない**（`Unknown label`）。検索キー側は切り詰められないため `strcmp` が一致しないことによる。現行 `yuios_road2.sym` の最大は **26文字**のため未発現。`emu23_ticket_EMU_D_symname_v1_0.md` 参照 |
| デバッグ情報の最大行数: 8192行 | MAX_DBG=8192。超過分は無視される |
| stdin非ブロッキング使用時の注意 | REPLモードでは stdin を NONBLOCK設定するため、インタラクティブ入力と -i FILE は併用不可 |
| -b は到達後即停止ではなくトレース開始 | -b ADDR は ADDR到達後に run_steps 命令をトレースするもの。REPLの b コマンドとは動作が異なる |
| irq_pending オフセット | emu23内部のirq_pending値はISA IRQ番号+1。§5.1参照 |
| SD_STAT の BUSYラッチ | EXEC後に SD_STAT を読むと1回目はBUSY=1、2回目以降は実際のSTATを返す |
| watermark の起動初期誤検出（v1.05） | -w 計測で _kstart の暫定 X=$F800 が data tid=0 の満杯(128B)として誤検出される。--wm-warmup（既定2000）で除外する |
| watermark は YUI OS 前提（v1.05） | -w はタスクスタック配置(コール$F000-$F7FF/データ$F800-$FBFF/各128B)を前提とする。Dhrystone等の単体プログラムでは誤検出が出るため -w を付けない |

## **9.2  hasm23との連携上の注意**

**⚠ hasm23は .org でコードが重なっても警告しません（kaizen.txt 原則22）。Step 8-Fで対処予定。**

**⚠ hasm23はシンボル二重定義を検出しません（kaizen.txt 原則21）。Step 8-Fで対処予定。**

emu23で解析する前に、hasm23のリンクマップでコードサイズを必ず確認してください。

## **9.3  関連設計書一覧**

| **設計書ファイル名** | **内容** |
| --- | --- |
| emu23_v105_design_v1_0.md | emu23 v1.05 設計書（スタック watermark 計測機能） |
| emu23_v103_design_v1_4.md | emu23 v1.03 設計書（メインループ・デバイス実装） |
| emu23_device_design_v1_2.docx | YSD8001/8002/8003/8004 デバイス設計書 |
| ysd8001_uart_design_v1_2.docx | YSD8001 UART 詳細設計書 |
| ysd8002_timer_design_v1_0.docx | YSD8002 タイマー詳細設計書 |
| toolchain23_design_v1_2.docx | ツールチェーン全体設計書 |
| ISA2_3_v231.docx | YSD8800 ISA 2.3 仕様書 |
| kaizen.txt | 開発・デバッグ改善事項（デバッグ原則集） |
| debug_style_guide.txt | デバッグ報告スタイルガイド |

# **§10  クイックリファレンスカード**

## **コマンドラインオプション（早見表）**

| **オプション** | **用途** |
| --- | --- |
| emu23 prog.bin -q | 静粛実行（HALTまで無停止・UART出力のみ） |
| emu23 prog.bin -n N | 最初のN命令をトレース |
| emu23 prog.bin -b ADDR -n N | ADDR到達後N命令をトレース |
| emu23 prog.bin -i input.txt -q | UARTへのキー入力をファイルから供給 |
| emu23 prog.bin --disk disk.img | ストレージ接続 |
| emu23 prog.bin -n N -m ADDR W | N命令後にADDRからWワードダンプ |

## **REPLコマンド（早見表）**

| **コマンド** | **書式** | **用途** |
| --- | --- | --- |
| s / s N | s [N] | N命令ステップ |
| c | c | ブレーク/HALTまで実行 |
| t | t | ブレーク/HALTまでトレース実行 |
| b addr | b <hex│label> | ブレークポイント設定 |
| bd N | bd <N> | ブレークポイント削除 |
| b | b | ブレークポイント一覧 |
| regs | regs | 全レジスタ表示 |
| disas a n | disas [addr [n]] | 逆アセンブル |
| mem a n | mem [addr [n]] | バイトダンプ |
| memw a n | memw [addr [n]] | ワードダンプ |
| irq N | irq <id> | IRQ注入 |
| reset | reset | CPU再起動 |
| q | q | 終了 |

## **IRQクイックリファレンス**

| **IRQ名** | **irq_pending値** | **ベクタアドレス** | **発生源** |
| --- | --- | --- | --- |
| タイマー（IRQ0） | 1 | $0002 | YSD8002 PERIOD到達 |
| デバイス（IRQ1） | 2 | $0004 | YSD8004 irq_stat!=0 |
| アラインメント（IRQ3） | 3 | $0006 | 奇数アドレスアクセス |
| SYSCALL（IRQ4） | 4 | $0008 | SYSCALL命令実行 |

## **MMIOクイックリファレンス**

| **アドレス** | **レジスタ** | **用途** |
| --- | --- | --- |
| $FC80 | UART_TX | UART送信 |
| $FC82 | UART_RX | UART受信 |
| $FC84 | UART_STAT | bit0=TX_READY  bit1=RX_READY（WTC） |
| $FC90 | TCR | タイマー制御 |
| $FC96/$FC98 | CYCLE_LO/HI | 現在サイクルカウンタ（LOを先読み） |
| $FCA0 | SD_CMD | ストレージコマンド（0=RD 1=WR 2=EXEC） |
| $FCA2 | SD_STAT | ストレージ状態（bit0=BUSY bit2=READY） |
| $FCB2 | IRQ_STAT | 割り込みステータス（WTC） |
| $FCB4 | IRQ_MASK | 割り込みマスク（1=マスク） |

emu23 デバッグ・ユーザマニュアル v1.1  |  YSD8800開発プロジェクト  |  p.