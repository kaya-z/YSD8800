**emu23 インタラクティブモード追加 設計書**

`-it` オプションによる対話的UART入出力サポート

Version 1.1  /  2026-06-26

| **項目** | **内容** |
| --- | --- |
| 文書番号 | EMU23-MOD-004 |
| 対象ツール | emu23 v1.08 → v1.09（予定） |
| ISAバージョン | YSD8800 ISA2.3 |
| 関連設計書 | emu23_v108_mmu_port_design_v1_1.md（MMU復活移植・直近改修） |
| 上位設計書 | yuios_ph6_shell_design（Shell実装・対話入力要件） |
| 作成日 | 2026-06-26 |
| ステータス | v1.1 ドラフト（レビュー前・実装未着手・emu23_v108.c実ソースで非干渉確認済み） |

# **改版履歴**

| **版** | **日付** | **変更内容** | **担当** |
| --- | --- | --- | --- |
| v1.0 | 2026-06-26 | 初版。`-q` モードがキーボード入力を実質受け付けない問題に対し、新規 `-it` オプションでターミナルraw mode化・対話的UART入出力を実現する設計を起案。 | Claude |
| v1.1 | 2026-06-26 | ベースを emu23 ~~v1.05~~ → **v1.08** に更新。emu23_v108.c（MMU復活移植版）の実ソース確認により以下を反映：①対象ツール記載を v1.08→v1.09（予定）に修正。②`ysd8001_tick()`/`ysd8001_poll_rx()`/`-q`ブロックは v1.05→v1.08 間で無変更（byte-exact一致）であることを確認し、本設計の§3全体はそのまま適用可能と確認。③`--mmu`オプションが `-q`/`-i` と同一のオプション解析ループ内で処理されていることを確認し、`-it`との組み合わせ動作を新規スコープ外事項として追記（§6）。 | Claude |

# **1. 目的と背景**

## **1.1 改修の目的**

YUI OS に Shell（Ph.6）が実装されると、emu23 上で YUI OS を起動したままターミナルからコマンドを打ち込みたい場面が生じる。しかし現行 `-q` モードではこれが実質的に機能しない。本設計書は対話的入出力を可能にする新規モード `-it` を追加するための設計を定める。

## **1.2 現状の `-q` モードの動作と問題点**

### 1.2.1 既存実装（v1.08時点・実ソース確認済み）

emu23 は YSD8001（UART）の RX ポーリング機構を `ysd8001_tick()` 内に既に持っており、`exec_one()` から毎サイクル呼ばれている。`-i FILE` 未指定時は stdin を `O_NONBLOCK` 化し、256サイクルに1回 `read(STDIN_FILENO, ...)` で1バイト読み込みを試みる。`-q` モードのメインループも `exec_one()` を呼ぶだけの単純なループであり、この RX ポーリング自体は動作する。

**v1.05→v1.08間の非干渉確認（emu23_v108.c実ソース照合済み）：** `ysd8001_poll_rx()` / `ysd8001_tick()` / `-q` ブロック（main()内）は、Step8-I（IRQ優先制御修正・v1.07）・Step8 V(-1)（MMU復活移植・v1.08）の両改修を経ても一切変更されていない（byte-exactで同一）。v1.08で追加された `--mmu` オプションはメモリアクセス（命令フェッチ含む26箇所の`fetch8()`化・MMIOディスパッチ）に関わる改修であり、UART RXポーリング経路とは独立している。よって本設計書の§3で述べる変更方針はv1.08にもそのまま適用できる。

### 1.2.2 問題の所在

問題は RX ポーリング機構そのものではなく、**Linux ターミナルのデフォルト動作（Cooked Mode）**にある。

- ターミナルドライバが行バッファリングを行うため、Enter キーを押すまで入力がプロセスに渡らない。
- ターミナル側がローカルエコーを行うため、1文字単位のリアルタイム入出力に向かない。
- Ctrl+C 等の制御文字がターミナルにインターセプトされ、SIGINT 等としてプロセスへ送られてしまい、UART RX バイトとして渡らない。

このため `-q` モードでは「キーボード入力を受け付けない」という体感になる。

## **1.3 本設計で実現すること**

- 新規オプション `-it`（interactive）を追加。
- `-it` 指定時、ターミナルを raw mode に切り替え、1文字単位でリアルタイムにUART RXへ流し込む。
- ターミナルのローカルエコーは無効化する（ユーザ確定：エコーはYUI OS側UARTドライバの責務とする。emu23側では簡易エコーを実装しない）。
- 終了方法は Ctrl+D（EOF）固定とする（ユーザ確定）。
- `-q` の既存動作には一切変更を加えない（非回帰）。

# **2. 前提・制約**

## **2.1 エコーバックの扱い（確定事項）**

ユーザ確認結果：**YUI OS 側（UART ドライバ／Shell）でエコーバック実装済みであることを前提とし、emu23 側ではエコーを一切行わない。**

- emu23 は raw mode 設定時に `ECHO` フラグを明示的にOFFにする（ターミナル側の自動エコーも止める）。
- emu23 自身が読み取った文字を画面に再出力する処理は実装しない。
- 結果として、画面に文字が表示されるのは YUI OS の UART ドライバが TX 側に書き戻した場合のみとなる。YUI OS 側でエコーバックが未実装の場合、ユーザの入力は画面上に見えない点に注意（既知の前提条件として明記）。

## **2.2 終了方法（確定事項）**

ユーザ確認結果：**Ctrl+D（EOF）で emu23 を終了する。**

- raw mode 中は Ctrl+C がそのまま UART RX バイト（0x03）として CPU 側に渡る想定とする（SIGINT 抑止）。
- Ctrl+D（0x04, EOF相当）を emu23 側で検出した場合、CPU 動作とは独立してプロセスを終了する。
- `read()` が 0 を返す（EOFシグナル）場合も同様に終了条件として扱う。

## **2.3 既存モードへの影響**

- `-q` モード：変更なし。
- `-i FILE` モード：変更なし（ファイル入力時は raw mode 設定自体を行わない）。
- 通常 REPL モード：変更なし。
- `-it` は `-q` と排他オプションとする（同時指定はエラー、または `-it` を優先しエラーメッセージを表示）。
- `--mmu`（v1.08で追加・MMU拡張）：`-q`/`-i`/`-w`等と同一のオプション解析ループ内で処理されているため、`-it --mmu` の同時指定は構文上可能になる。MMUはメモリアクセス側の機構でUART RX経路とは独立しているため、技術的な相互干渉は想定しにくいが、組み合わせ時の動作確認は実装時に別途実施する（§6参照）。

# **3. 設計詳細**

## **3.1 ターミナル制御（termios）**

`<termios.h>` を使用し、`-it` 指定時のみ以下を実施する。

```c
#include <termios.h>

static struct termios orig_termios;
static int raw_mode_active = 0;

static void enable_raw_mode(void) {
    struct termios raw;
    if (tcgetattr(STDIN_FILENO, &orig_termios) == -1) return;
    raw = orig_termios;
    raw.c_lflag &= ~(ECHO | ICANON | ISIG);
    /* ISIG も無効化: Ctrl+C(SIGINT)・Ctrl+Z(SIGTSTP)等を
     * ターミナルに奪われず、生バイトとしてUART RXへ渡すため */
    raw.c_cc[VMIN]  = 0;
    raw.c_cc[VTIME] = 0;
    tcsetattr(STDIN_FILENO, TCSANOW, &raw);
    raw_mode_active = 1;
}

static void disable_raw_mode(void) {
    if (raw_mode_active) {
        tcsetattr(STDIN_FILENO, TCSANOW, &orig_termios);
        raw_mode_active = 0;
    }
}
```

**KY注記：** `enable_raw_mode()` で `ISIG` を落とすため、emu23 プロセス自体が Ctrl+C で終了できなくなる。異常終了時にターミナルが raw mode のまま残置されるリスクがあるため、`atexit()` および主要 `signal` ハンドラで `disable_raw_mode()` を確実に呼ぶこと（§3.4 参照）。

## **3.2 EOF（Ctrl+D）検出と終了**

`ysd8001_poll_rx()` 相当の読み込み処理を `-it` 専用に分岐させる。既存の `ysd8001_poll_rx()` は変更せず、`-it` モード用の薄いラッパーを新設する方針とする（既存 `-q`/`-i` 経路を汚さないため）。

```c
static int it_mode_should_exit = 0;

/* -it モード専用の RX ポーリング。
 * 既存 ysd8001_poll_rx() をベースに EOF 検出のみ追加。 */
static void ysd8001_poll_rx_interactive(void) {
    if (ysd8001.stat & YSD8001_STAT_RX_READY) return;

    unsigned char buf;
    ssize_t n = read(STDIN_FILENO, &buf, 1);

    if (n == 0) {
        /* EOF（Ctrl+D で読み取りバッファが空になり0が返るケース） */
        it_mode_should_exit = 1;
        return;
    }
    if (n < 0) return;  /* EAGAIN等、非ブロッキングで読めるデータなし */

    if (buf == 0x04) {
        /* Ctrl+D を明示バイトとして検出した場合も終了扱い
         * （raw mode + ICANON無効では0個読み込み終了のEOFとは
         *   別に、0x04そのものが1バイトとして読めてしまう可能性があるため
         *   両方のケースを終了トリガーとして扱う） */
        it_mode_should_exit = 1;
        return;
    }

    ysd8001.rx_buf = buf;
    ysd8001.stat |= YSD8001_STAT_RX_READY;
    ysd8004_raise(IRQ_STAT_BIT_UART_RX);
}
```

**設計判断：** raw mode + `ICANON` 無効の状態では、Ctrl+D は伝統的な「EOF記号」としては機能せず、**0x04 という1バイトの生データ**として読めてしまう可能性が高い（ICANON下でのみ特別扱いされる制御文字のため）。したがって本設計では「0x04を読んだら終了」を主たる検出条件とし、`read()==0`（真のEOF）も保険として終了条件に含める。

**KY注記：** 0x04 を「終了コマンド」として横取りすると、YUI OS 側が本来 0x04 を通常データとして受け取りたいケース（バイナリプロトコル等）と衝突する可能性がある。Shell用途では実害は薄いと想定するが、将来的に別の終了キー（例：Ctrl+]、ASCII 0x1D）への変更余地は残す。

## **3.3 メインループ追加**

既存 `-q` ブロック（main() 内）と並列に新設する。既存コードへの変更は「オプション解析にif分岐を1つ追加」のみとし、`-q` 側のロジックは1行も変更しない。

```c
/* -it モード: 対話的実行。ターミナルraw mode化＋EOF検出 */
if (interactive_mode) {
    enable_raw_mode();
    uint64_t steps = 0;
    while (!cpu.halted && !it_mode_should_exit) {
        exec_one();   /* 内部で ysd8001_tick() が呼ばれるが、
                       * -it モードでは poll_rx を interactive版に
                       * 差し替える必要がある（§3.5参照） */
        if (wm_enable && ++steps >= wm_max_steps) break;
    }
    disable_raw_mode();
    fflush(stdout);
    wm_report();
    return 0;
}
```

## **3.4 異常終了時のraw mode復帰保証**

raw mode 設定中にプロセスが異常終了すると、ターミナルが raw mode のまま残り、以後のシェル操作に支障が出る（既知のtermios利用時の典型的事故）。

```c
#include <stdlib.h>
#include <signal.h>

static void cleanup_on_exit(void) {
    disable_raw_mode();
}

/* main() 冒頭、-it 判定後に登録 */
if (interactive_mode) {
    atexit(cleanup_on_exit);
    /* SIGTERM等の通常終了シグナルにも対応 */
    signal(SIGTERM, exit);
    signal(SIGHUP,  exit);
}
```

**KY注記：** `ISIG` を無効化しているため SIGINT（Ctrl+C）はターミナルから送られてこないが、外部から `kill -TERM` 等で終了させられるケースは残るため、上記の保険を入れる。

## **3.5 既存 `ysd8001_tick()` との関係**

既存の `ysd8001_tick()` は内部で `ysd8001_poll_rx()`（stdin/ファイル共通）を直接呼んでいる。`-it` モード時は §3.2 の `ysd8001_poll_rx_interactive()` を使う必要があるため、関数ポインタまたはフラグ分岐で切り替える。

```c
/* グローバル関数ポインタ方式（既存コードへの侵襲を最小化） */
static void (*poll_rx_fn)(void) = ysd8001_poll_rx;  /* 既定 */

/* main() 内、-it 判定確定後 */
if (interactive_mode) {
    poll_rx_fn = ysd8001_poll_rx_interactive;
}

/* ysd8001_tick() 内の呼び出しを変更 */
static void ysd8001_tick(uint64_t current_cycle) {
    if ((current_cycle & 0xFF) == 0) {
        poll_rx_fn();   /* 直接呼び出しから関数ポインタ経由に変更 */
    }
    ...
}
```

**KY注記：** `ysd8001_tick()` の変更はこの1箇所（直接呼び出し→関数ポインタ経由）のみ。`-q`/`-i`/通常REPL利用時は `poll_rx_fn` が既定の `ysd8001_poll_rx` を指すため、動作は完全に従来通り（非回帰）。

## **3.6 オプション解析への追加**

```c
static int interactive_mode = 0;

/* 既存の -q 解析と同じ箇所に追加 */
if (strcmp(argv[i], "-it") == 0) interactive_mode = 1;

/* -q と -it の排他チェック（オプション解析末尾） */
if (quiet_mode && interactive_mode) {
    fprintf(stderr, "emu23: -q and -it are mutually exclusive\n");
    return 1;
}
```

ヘルプ文字列にも追記する：

```c
"  -it          interactive: raw terminal mode, UART RX from keyboard,\n"
"               Ctrl+D (0x04) to exit. No local echo (UART driver's job)\n"
```

# **4. 変更ファイル一覧**

| **ファイル** | **変更内容** | **変更規模（推定）** |
| --- | --- | --- |
| emu23_v1XX.c | `#include <termios.h>` 追加 | 1行 |
| 同上 | `enable_raw_mode()` / `disable_raw_mode()` 新設 | 約20行 |
| 同上 | `ysd8001_poll_rx_interactive()` 新設 | 約20行 |
| 同上 | `cleanup_on_exit()` 新設・atexit/signal登録 | 約10行 |
| 同上 | `-it` モード用メインループ追加 | 約12行 |
| 同上 | `ysd8001_tick()` 内の呼び出しを関数ポインタ経由に変更 | 1行変更 |
| 同上 | オプション解析に `-it` 分岐・排他チェック追加 | 約6行 |
| 同上 | ヘルプ文字列追記 | 2行 |

**既存コードへの破壊的変更は `ysd8001_tick()` 内の1行（直接呼び出し→関数ポインタ経由）のみ**であり、`-q`・`-i`・通常REPLの動作は完全に保たれる設計である。

# **5. 動作確認方法（実装後）**

| **項目** | **確認手順** | **期待結果** |
| --- | --- | --- |
| 非回帰確認（`-q`） | `emu23 yuios.bin -q` を実行 | v1.05までと完全に同一の出力・終了動作 |
| 非回帰確認（`-i`） | `emu23 yuios.bin -i cmds.txt` を実行 | v1.05までと完全に同一の動作 |
| 対話入力確認 | `emu23 yuios.bin -it` 実行後、Shellプロンプトでキー入力 | 1文字ずつリアルタイムにUART RXへ反映され、YUI OS側のShellが文字を認識する |
| エコー確認 | `-it` 実行中に文字入力 | emu23自身はエコーしない。YUI OS側UARTドライバ・Shellのエコー実装に依存して画面表示が決まる |
| 終了確認 | `-it` 実行中に Ctrl+D | emu23が即時終了し、ターミナルがcooked modeに復帰している（`stty -a` 等で確認） |
| 異常終了時の復帰確認 | `-it` 実行中に `kill -TERM <pid>` | ターミナルがraw modeのまま残らないこと |

# **6. スコープ外事項**

| **項目** | **理由・方針** |
| --- | --- |
| emu23側での簡易エコー実装 | ユーザ確定：エコーはYUI OS側UARTドライバの責務とする |
| Ctrl+C以外の制御文字の特別処理 | 本設計では0x04（EOF/Ctrl+D）のみを特別扱い。他は生バイトとしてUART RXへ素通し |
| カーソル制御・ANSIエスケープシーケンスの解釈 | emu23は素通しのみ。解釈はYUI OS側ターミナルドライバ/アプリの責務 |
| 終了キーのCtrl+D以外への変更（Ctrl+]等） | 将来必要になった場合に別途検討（§3.2 KY注記に余地を残す） |
| `-it` と `-w`（watermark計測）の同時使用時の挙動詳細 | 排他指定はしないが、組み合わせ時の動作確認は実装時に別途実施 |
| `-it` と `--mmu`（v1.08 MMU拡張）の同時使用時の挙動詳細 | 排他指定はしない。両機構は担当領域（UART RX vs メモリアクセス）が独立しており技術的な直接干渉は想定しにくいが、組み合わせ時の動作確認は実装時に別途実施する |

# **7. KY活動（危険予知）**

| **危険予知（KY）** | **防止策** |
| --- | --- |
| raw mode設定中にプロセスがクラッシュし、ターミナルがraw modeのまま残ってシェル操作不能になる | `atexit()`・主要signalハンドラで`disable_raw_mode()`を確実に呼ぶ（§3.4）。実装後、`kill -9`以外の終了経路を全て手動テストすること |
| `ISIG`無効化によりCtrl+Cでemu23自体を止められなくなり、デバッグ時に困る | Ctrl+D（EOF/0x04）を確実な脱出口として用意し、実装直後に脱出経路を最優先でテストする |
| 0x04を「終了コマンド」として横取りすることで、YUI OS側が0x04を通常データとして使うケースと衝突する | 本設計のスコープ外事項として明記し、Shell実装側でも0x04をデータとして使わない運用を徹底する |
| `ysd8001_tick()`の変更（関数ポインタ化）が`-q`/`-i`/REPLの既存動作に影響を与える | 変更は1行のみとし、既定値を`ysd8001_poll_rx`に固定。実装後は§5の非回帰確認を最優先で実施する |

以上 / emu23 インタラクティブモード追加 設計書 v1.0
