YUI OS Ph.3 UART ドライバ詳細設計書 v1.5

**YUI OS Ph.3 UART ドライバ詳細設計書**

yuios_ph3_uart_design_v1_5.md

Version 1.5  /  2026-05-01（最終改版: 2026-08-06）

| **項目** | **内容** |
| --- | --- |
| 文書種別 | 詳細設計書 |
| 対象工程 | Step 8-Y Ph.3-A4: UART ドライバ詳細設計 |
| 対象 OS | YUI OS Ph.3 |
| 対象 ISA | ISA2.3 (YSD8800) |
| 対象周辺 | YSD8001 UART (v1.2) / YSD8004 IRQC |
| 対象エミュレータ | emu23 v1.11 |
| 関連設計書 | yuios_design_v2_4.md / ysd8001_uart_design_v1_2.docx |
| 前提引継ぎ | HANDOVER_CHAT19.docx |
| 作成日 | 2026-05-01 |
| 作成者 | Claude (Anthropic) |
| 対象実装 | kernel_v12_10.asm (v0.12.10) / md5 d5c18dd3aa1d4d4a4bc042fb5d6af893 |
| ステータス | v1.5（TKT-02 反映・検証 V-1〜V-7 全項目PASS） |

# **改版履歴**

| **版数** | **日付** | **変更内容** | **作成者** |
| --- | --- | --- | --- |
| v1.0 | 2026-05-01 | 初版作成。Chat #18 で確定した設計方針（HANDOVER_CHAT19 §3.2）に基づく Ph.3-A4 詳細設計 | Claude |
| v1.1 | 2026-05-01 | review7.txt 指摘反映: ①RX_READYクリア責務明文化 ②WAIT-TID単一制約明記 ③WAIT/IRQレース対策(再チェックループ) ④TX_READYポーリング整合 ⑤PUTSブロック時間試算 ⑥バッファ拡張余地 ⑦初期化原則明文化 ⑧COUNT更新順序固定 | Claude |
| v1.2 | 2026-05-01 | review8.txt の GO 判定および実装フェーズ向け必須ルールを正式記載。§5.5.1 wake_uart_waiter 実装規約（IPC4-REPLY コピペ規則）追加、§5.5.2 IPC4-REPLY 実装解析（kernel_v09.asm 由来）追加、§10 実装フェーズ規約追加、§9.1 KY9 追加 | Claude |
| v1.3 | 2026-05-18 | Ph.3.5 実装完了に伴うアドレス更新：①UART ワーク変数アドレスを $E210〜$E22F → $FC46〜$FC5E に更新（§2.2）、②TCB レイアウトを v0.12.6 の 80B 構成に更新（§5.5.2）、③wake_uart_waiter 擬似コードを v0.12.6 実装に整合（TCB+14/+30 フィールド追加対応、IPC4 Pool 方式対応注記） | Claude |
| v1.4 | 2026-06-06 | 上位設計書・関連ツール版数の整合更新：①関連設計書参照を yuios_design_v2_4.md（Ph.4 完了・Ph.3.5 補完完了版）に更新、②対象エミュレータを emu23 v1.02 → v1.05 に更新（watermark 機能統合版）。本文内容（UART ドライバ設計・実装規約）に変更なし | Claude |
| **v1.5** | **2026-08-06** | **TKT-02（UART 受信リングバッファ／起床経路 欠陥修正）反映。設計書 yuios_uart_rxring_fix_design_v0_4.md §7.1 に基づく5箇所改版：**①**§5.5.3 擬似コードに `LDW X,[IPC4_WK_SRCTCB]` を挿入**（★欠陥①の設計書側是正。v1.4 までの擬似コードには X 復元が無く、実装は設計書どおりに正しく実装された結果として誤っていた）②§5.5.2 A4 行に `rx_pop` の破壊レジスタと X 復元要件を明記③**§5.5.1 に「コピペ規約の適用範囲には限界がある」を新設**（★差替コメント必須化・挿入 JSR の独立レビュー必須化。最上位の構造的原因への対処）④**§3.4 に `rx_pop` の呼出規約（`$FFFF` センチネル・破壊レジスタ・空時の副作用なし）を明文化し、実装乖離の記録を追加**（★v1.1 で規定済の `return -1` ガードが実装に存在しなかった事例）⑤§5.5 に `wake_uart_waiter` の呼出規約（`UART_RX_COUNT > 0` の継承宣言を含む）を明記。**対象実装は kernel_v12_10.asm（v0.12.10）／黄金値 md5 `d5c18dd3aa1d4d4a4bc042fb5d6af893`。検証 V-1〜V-7 全項目PASS（28判定）** | Claude |

## **v1.1 → v1.2 変更概要**

review8.txt は v1.1 を「実装 GO」と判定（評価 8.5〜9/10）したが、別チャットで実装する都合上、レビュアが提示した「実装時の唯一の注意事項」が口頭注意のまま埋もれる懸念がある。本 v1.2 ではこれを設計書本体に正式条項として刻み込み、実装担当が見落とせない形にする。

| **項目** | **内容** | **反映箇所** |
| --- | --- | --- |
| IR1 | wake_uart_waiter は IPC4-REPLY のコードをコピーベースに実装すること（必須ルール） | §5.5.1（新設） |
| IR2 | IPC4-REPLY 現行実装（kernel_v09.asm L841-）の解析と参照すべき具体的処理リスト | §5.5.2（新設） |
| IR3 | 実装フェーズ規約（順序・チェックリスト） | §10.4（新設） |
| IR4 | wake_uart_waiter 実装ズレリスクを KY9 として正式登録 | §9.1 KY9 |
| IR5 | TCB アドレス計算式の正規化（v2.0 では tid*80+$4000） | §5.5.2 注記 |

# **1. 概要**

## **1.1 目的**

本書は、YUI OS Ph.3 において UART (YSD8001) を独立ドライバタスクとして実装するための詳細設計書である。

Ph.2 では UART は kernel.asm 内部のサブルーチン（_kputs / _kputc）として実装されていたが、Ph.3 ではマイクロカーネル方針に従い独立タスク化する。クライアントタスクは IPC4-CALL 経由で UART サービスを利用する。

## **1.2 適用範囲**

| **レイヤ** | **実装** | **本書の扱い** |
| --- | --- | --- |
| UART チップ（YSD8001） | MMIO レジスタ・割込発火 | 対象外（ysd8001_uart_design_v1_2.docx を参照） |
| IRQ1 ハンドラ | kernel.asm 内に新設 | 本書 §5 で詳細設計 |
| UART ドライバタスク | Forth ワード（kernel_forth.fs に追加） | 本書 §4 で詳細設計 |
| 受信リングバッファ | RAM 上の固定領域 | 本書 §3 で詳細設計 |
| IPC4 メッセージ仕様 | SVC_UART (0x04) 系 | 本書 §6 で詳細設計 |
| UART テストタスク | Forth ワード（起動時自動実行） | 本書 §7 で詳細設計 |
| wake_uart_waiter 実装規約 | IPC4-REPLY コピペベース実装 | 本書 §5.5.1 / §10.4 で必須化 |

## **1.3 設計方針（Chat #18 で確定済）**

HANDOVER_CHAT19 §3.2 で確定した設計事項を以下に再掲する。本書はこれを前提とする。

**【v1.1 補足】** 「UART_PUTC 動作: MMIO TX 直接書込」は TX_READY が立った状態を前提とする旨を明示する（§6.3 参照）。HANDOVER の「フロー制御なし」とはハードウェア RTS/CTS 制御がない意であり、TX_READY によるソフトウェア同期は必須。

| **項目** | **確定内容** |
| --- | --- |
| タスク登録方法 | Forth ワード UART-DRV-TASK として実装、UART-START で TASK-CREATE 起動 |
| UART_PUTC 動作 | TX_READY ポーリング待ち → MMIO TX 書込 → 即 IPC4-REPLY（HW フロー制御なし） |
| UART_PUTS 動作 | 全文字送信完了まで待機後 IPC4-REPLY（将来 FIFO 化を想定） |
| 受信リングバッファサイズ | 16 バイト固定（v1.1: 将来 32/64B 拡張可能性を §3.1 注記） |
| バッファあふれ時 | 新規受信を破棄 |
| バッファ配置 | 案 C ハイブリッド（カーネルワーク内 UART 専用サブ領域 / $E2xx 系） |
| IRQ1 (UART RX) 取扱 | 既存 IRQ1 ベクタを差し替え、UART RX 用ハンドラを新設 |
| RX 処理経路 | IRQ コンテキストでリングバッファ格納 → UART_GETC 待ちタスクを起こす |
| UART_GETC WAIT 動作 | UART ドライバ自身も TASK-WAIT-IPC で次リクエスト待機 |
| テスト方針 | UART-TEST-TASK として Forth 側にテストタスク追加、起動時自動実行 |

# **2. メモリ配置**

## **2.1 配置領域の決定**

HANDOVER_CHAT19 §3.3 の仮アドレス案を本書で正式採用する。配置領域は Ph.2 で MemMgr が使用する $E200 系の続き領域とする。

Ph.2 既存使用：$E200 (PAGE-BMP-LO) / $E202 (PAGE-BMP-HI) / $E204 (MEM-TID-ADDR) — kernel_forth_v05.fs L67-69 で確認済み。

UART 専用領域は $E210 から開始し、$E206-$E20F は将来用に予約する。

## **2.2 UART 専用変数アドレス一覧**

| **アドレス** | **サイズ** | **シンボル名（Forth）** | **シンボル名（ASM）** | **用途** |
| --- | --- | --- | --- | --- |
| $FC46 | 16 B | UART-RX-RING-BUF | UART_RX_RING_BUF | 受信リングバッファ本体 **【v1.3】$E210→$FC46** |
| $FC56 | 2 B | UART-RX-HEAD | UART_RX_HEAD | 書き込み位置（IRQ ハンドラが進める） **【v1.3】$E220→$FC56** |
| $FC58 | 2 B | UART-RX-TAIL | UART_RX_TAIL | 読み出し位置（ドライバタスクが進める） **【v1.3】$E222→$FC58** |
| $FC5A | 2 B | UART-RX-COUNT | UART_RX_COUNT | バッファ内バイト数（0〜16） **【v1.3】$E224→$FC5A** |
| $FC5C | 2 B | UART-DRV-TID | UART_DRV_TID | UART ドライバタスク ID **【v1.3】$E226→$FC5C** |
| $FC5E | 2 B | UART-WAIT-TID | UART_WAIT_TID | UART_GETC 応答待ちクライアント tid（0=なし、単一スロット） **【v1.3】$E228→$FC5E** |

### **2.2.1 設計判断: UART-WAIT-TID の追加**

HANDOVER_CHAT19 では UART-DRV-TID までの 6 アドレスのみ列挙されていたが、本設計で UART-WAIT-TID（$E228）を追加する。

理由：UART_GETC でリングバッファ空時にクライアント tid を保存し、IRQ ハンドラから「リングバッファに 1 バイト到着 → 待機中クライアントへ即 REPLY」する経路を簡潔に実装するため。これがないと、ドライバタスクが BEGIN…AGAIN ループ内で COUNT を polling する必要があり、CPU 効率が悪化する（CPU が空回りする）。

**【v1.1 制約明記】** UART-WAIT-TID は単一スロットのため、同時に UART_GETC を発行できるクライアントは 1 タスクのみとする。複数同時発行時は後勝ちで上書きされ、先行クライアントは永久ブロックする。詳細は §6.5 / §9.1 KY6 / §9.2 を参照。

## **2.3 メモリマップ整合性確認**

| **参照文書** | **結果** | **備考** |
| --- | --- | --- |
| yuios_memmap_design_v1_2.md | OK | **【v1.3 更新】$FC46-$FC5E は OS 共有変数領域（$FC40-$FCFF）内。Ph.3.5 Step 1 で $E210〜 から移動済み（v0.12.0）** |
| kernel_forth_v05.fs (Ph.2) | OK | $E200/$E202/$E204 のみ使用。$E206 以降は空き |
| kernel_v09.asm (Ph.2) | OK | MEM_TID_ADDR=$E204 のみ参照。$E206 以降は未使用 |

**【KY】【v1.3 更新】** 将来 ストレージドライバ等の他デバイス用変数領域を割り当てる際は、本表を参照して衝突を回避すること。本書の確定により **$FC46-$FC5E** は UART 専用となる（Ph.3.5 Step 1 でアドレス移動済み）。

# **3. 受信リングバッファ**

## **3.1 構造**

受信リングバッファは 16 バイトの固定長 FIFO とする。書き込みは IRQ1 ハンドラ、読み出しは UART ドライバタスクが行う。

  $E210 +0  +1  +2  +3  +4  +5  +6  +7  +8  +9  +A  +B  +C  +D  +E  +F

         ┌────────────── 16 バイト リングバッファ ──────────────┐

         │   data[0]   ...   data[15]                             │

         └────────────────────────────────────────────────────────┘

  $FC56  HEAD  : 次の書き込み位置（0〜15）

  $FC58  TAIL  : 次の読み出し位置（0〜15）

  $FC5A  COUNT : 現在のバッファ内バイト数（0〜16）

**【v1.1 拡張余地】** 9600 bps では 16 B ≒ 16 ms 相当。スケジューラ遅延次第で容易にあふれる可能性がある。将来 32 B / 64 B 化する場合は HEAD/TAIL のマスク値（現 $000F）と確保アドレス範囲のみ変更すれば対応可能。**【v1.3 更新】** Ph.3.5 で $FC46-$FC5E に移動済み。拡張時は OS 共有変数領域（$FC40-$FCFF）内の空きを利用する。

## **3.2 不変条件**

| **条件** | **意味** |
| --- | --- |
| 0 ≤ HEAD ≤ 15 | 書き込み位置は常にバッファ内（mod 16） |
| 0 ≤ TAIL ≤ 15 | 読み出し位置は常にバッファ内（mod 16） |
| 0 ≤ COUNT ≤ 16 | バッファ内バイト数は 0 以上 16 以下 |
| COUNT = 0  → 空 | 読み出し不可 |
| COUNT = 16 → 満杯 | 書き込み不可（オーバーラン破棄） |

## **3.3 書き込み手順（IRQ1 ハンドラから呼ばれる）**

**【v1.1 規定】** 更新順序は HEAD → COUNT の順を必須とする。逆順にすると、COUNT 更新と HEAD 更新の間にドライバタスク側で COUNT を読まれた場合、TAIL が既に進んでいない領域から無効データを取得する可能性がある。

rx_push(byte):

  if COUNT == 16:

    return  /* オーバーラン → 破棄（HANDOVER §3.2 確定方針） */

  RING_BUF[HEAD] = byte         /* (1) データ書込 */

  HEAD = (HEAD + 1) mod 16      /* (2) HEAD 更新（先） */

  COUNT = COUNT + 1             /* (3) COUNT 更新（後） */

## **3.4 読み出し手順（UART_GETC 処理から呼ばれる）**

**【v1.1 規定】** 更新順序は TAIL → COUNT の順を必須とする。

rx_pop() -> byte:

  if COUNT == 0:

    return -1  /* 空（呼出側は IRQ ハンドラからの起こしを待機） */

  byte = RING_BUF[TAIL]         /* (1) データ読出 */

  TAIL = (TAIL + 1) mod 16      /* (2) TAIL 更新（先） */

  COUNT = COUNT - 1             /* (3) COUNT 更新（後） */

  return byte

**■【v1.5 追加・TKT-02】呼出規約の明文化**

| 項目 | 内容 |
|---|---|
| 入力 | `UART_RX_COUNT`（呼出側は §3.2 の不変条件を維持すること） |
| 出力（正常） | A = byte。`ANDI A,#$00FF` により **`$0000`–`$00FF` に限定**される |
| 出力（空） | **A = `$FFFF`**（= 上記 `return -1` の16bit2の補数表現）。正常戻り値と衝突しない一意なセンチネル |
| **破壊** | **A, B, X**（★呼出側は必ず退避・復元すること。特に X は `&RING_BUF[TAIL]` になって復帰する） |
| 空のときの副作用 | **なし。TAIL・COUNT はいずれも変化しない**（即時 return） |

> **`return -1` を `A = 0` として実装してはならない。**
> 正常戻り値に `0x00`（NUL）が含まれるため区別がつかなくなり、
> 呼出側が異常を検知できない。`$FFFF` は正常戻り値域外であり一意である。

**■【v1.5 追加・TKT-02】★実装乖離の記録（設計は正しく実装が欠落していた事例）★**

v0.12.9 までの `kernel_v12_*.asm` の `rx_pop` 実装には、
**本項が v1.1 の時点で規定していた `if COUNT == 0: return -1` のガードが存在しなかった。**
実装側ヘッダは代わりに `; 入力: COUNT>0であること (呼び出し側が保証)` と宣言しており、
**設計書の規定を「呼出側の責務」へすり替えていた。**

| | 欠陥① (§5.5.3) | 本件 (§3.4) |
|---|---|---|
| 設計書 | **誤**（X 復元が欠落） | **正**（ガードを規定済） |
| 実装 | 設計書どおり（＝誤） | **誤**（ガードを省略） |
| 検出手段 | 実装照合レビューでは**不可能** | 実装照合レビューで**可能だった** |

安全性は「呼出元 IRQ1_HANDLER S4 の `JSR rx_push` 直後である」という
**暗黙の呼出順序**にのみ依存していた。別経路から呼べば `COUNT` が
`$FFFF` にアンダーフローし、`rx_push` の `CMP A,#16 / BGE` が符号付き比較で
負値と評価してオーバーラン判定まで破綻する。

**v0.12.10 でガードを実装し、設計書との乖離を解消した**（検証 V-7 PASS）。

## **3.5 同時アクセス保護**

リングバッファは IRQ1 ハンドラ（書き込み）とドライバタスク（読み出し）の双方からアクセスされる。COUNT への加減算は単一命令で完結しないため、ドライバタスク側のクリティカルセクションでは DI/EI で保護する。

IRQ1 ハンドラは元々 IE=0 で動作するため追加の保護は不要。

# **4. UART ドライバタスク仕様**

## **4.1 タスク基本情報**

| **項目** | **値** |
| --- | --- |
| タスク名（Forth） | UART-DRV-TASK |
| 登録方法 | UART-START : MAKE-TASK 起動 → tid を UART-DRV-TID に格納 |
| 登録順序 | MEMMGR-START の後、ユーザタスク作成より前 |
| 想定 tid | 2（tid=0=Forth ルート、tid=1=MemMgr に続く） |
| スタックサイズ | コールスタック 256B / データスタック 256B（標準） |
| 主ループ | BEGIN IPC4-RECV → DISPATCH AGAIN（MemMgr と同パターン） |

## **4.2 起動時初期化**

UART-DRV-TASK は起動直後に以下を実行する。

**【v1.1 原則明文化】** IRQ 有効化（IRQ_MASK の更新および後続の EI）を行う前に、必ず関連デバイスのステータスフラグと割込コントローラのステータスをクリアすること。残留フラグがあると IRQ 有効化直後に意図しない割込が発火する。

1. UART-RX-HEAD = 0

2. UART-RX-TAIL = 0

3. UART-RX-COUNT = 0

4. UART-WAIT-TID = 0

   --- ↑ 内部状態を先に確定 ---

5. UART_STAT へ $0002 書込（残留 RX_READY を念のためクリア）

6. YSD8004 IRQ_STAT へ $0001 書込（bit0 RX 残留割込クリア）

   --- ↑ ステータスを先にクリア ---

7. YSD8004 IRQ_MASK の bit0 = 0 を保証（RX 許可）

   ※ TX IRQ (bit2) は本ドライバでは未使用のためマスク維持

   --- ↑ IRQ 有効化はステータスクリア後 ---

8. メインループへ進入

【根拠】§7 (ysd8001_uart_design_v1_2.docx §3.6) のリセット値で IRQ_MASK=0x0004 → bit0 は既に 0（RX 許可）であるため、step 7 は冪等動作だが明示する。

## **4.3 メインループ**

: UART-DRV-TASK  ( -- )

    UART-INIT                    \ §4.2

    BEGIN

        IPC4-RECV                \ ( -- msg3 msg2 msg1 msg0 )

        IPC4-SENDER-DIRECT >R    \ R: client_tid

        REORDER-MSG-3            \ ( -- arg1 arg0 op )

        R>                       \ ( -- arg1 arg0 op tid )

        UART-DISPATCH

    AGAIN ;

MEMMGR-TASK と同じスタック整列パターンを採用する（kernel_forth_v05.fs L483-491 と整合）。

## **4.4 ディスパッチ**

UART-DISPATCH は op 番号により処理を分岐する。

: UART-DISPATCH  ( arg1 arg0 op tid -- )

    >R                          \ R: tid

 

    DUP UART-PUTC-OP = IF       \ op == $0401

        DROP                    \ op を捨てる

        SWAP DROP               \ arg1 を捨てる、TOS=arg0(char)

        UART-PUTC-IMPL          \ ( char -- )

        0 0 0 0 R> IPC4-REPLY

        EXIT

    THEN

 

    DUP UART-PUTS-OP = IF       \ op == $0403

        DROP

        SWAP DROP               \ TOS=arg0(addr)

        UART-PUTS-IMPL          \ ( addr -- )

        0 0 0 0 R> IPC4-REPLY

        EXIT

    THEN

 

    UART-GETC-OP = IF           \ op == $0402

        DROP DROP               \ arg0 / arg1 不使用

        R> UART-GETC-IMPL       \ ( tid -- ) — REPLY 内部で行う

        EXIT

    THEN

 

    \ 未知 op

    DROP DROP

    0 0 0 0 R> IPC4-REPLY ;

# **5. IRQ1 ハンドラ詳細設計**

## **5.1 配置**

IRQ1 ハンドラは kernel.asm に新設する。Ph.2 では _dummy_irq に向いていたベクタを差し替える。

  ; Ph.2 (kernel_v09.asm L126):

      .vector irq1    _dummy_irq

  ; Ph.3 (kernel.asm 改版後):

      .vector irq1    IRQ1_HANDLER

配置アドレスは IRQ0_HANDLER より下、$0080 付近を想定。最終アドレスは kernel.asm 改版時に決定する。

## **5.2 IRQ1 ハンドラ統合手順（v1.1 で再構成）**

IRQ1 は本書 v1.0 では UART RX 専用とする（YSD8001 RX 割り込みのみが bit0 を立てる）。将来ストレージ完了割込（bit1）等を追加する場合は本ハンドラ内で IRQ_STAT を読んで分岐する。

以下の手順は ysd8001_uart_design_v1_2.docx §5.4 と完全整合する。順序は厳守。

| **手順** | **操作** | **責務担当** | **順序根拠** |
| --- | --- | --- | --- |
| S0 | レジスタ A/B/X を IRQ1 専用ワークへ退避 | IRQ1_HANDLER | ハンドラ規約 |
| S1 | YSD8004 IRQ_STAT を読出、bit0 を確認 | IRQ1_HANDLER | UART RX 由来か判定 |
| S2 | (bit0=0 なら) S8 へジャンプ（割込未要因） | IRQ1_HANDLER | — |
| S3 | UART_RX を読出（副作用なし、A=byte） | IRQ1_HANDLER | 受信値取得（読み出しでは RX_READY はクリアされない） |
| S4 | rx_push(byte)（COUNT==16 なら破棄） | IRQ1_HANDLER → rx_push | リングバッファ格納 |
| S5 | UART_STAT に $0002 書込（RX_READY を WTC でクリア） | IRQ1_HANDLER | 【必須】これを忘れると IRQ 多重発火（review R1 指摘） |
| S6 | YSD8004 IRQ_STAT bit0 に 1 書込（割込要求クリア） | IRQ1_HANDLER | S5 より後である必要あり（ysd8001 §5.4 注） |
| S7 | UART-WAIT-TID が非0なら待機クライアントを起こす | IRQ1_HANDLER → wake_uart_waiter | GETC 即時応答経路 |
| S8 | レジスタ A/B/X を復帰、IRET | IRQ1_HANDLER | ハンドラ規約 |

**【最重要・review R1 反映】** S5（UART_STAT WTC で RX_READY クリア）を欠落させると、UART_STAT.RX_READY=1 が継続し、YSD8004 IRQ_STAT bit0 も再セットされて IRET 直後に再度 IRQ1 が発火、無限ハンドラループに陥る。S5 と S6 の順序を逆にすると、S5 完了前に S6 で IRQ_STAT がクリアされるが、UART 側の RX_READY=1 によって直後に再アサートされ多重発火する。

## **5.3 IRQ1 ハンドラ擬似コード**

IRQ1_HANDLER:

    ; --- S0: レジスタ退避 ---

    STW  A, [IRQ1_WK_A]

    STW  B, [IRQ1_WK_B]

    STW  X, [IRQ1_WK_X]

 

    ; --- S1/S2: IRQ_STAT 確認 ---

    LDW  A, [IRQ_STAT]          ; YSD8004 IRQ_STAT

    ANDI A, #$0001

    BEQ  irq1_done              ; UART RX でなければ S8 へ

 

    ; --- S3: UART_RX 読出（副作用なし） ---

    LDW  A, [UART_RX]

    ANDI A, #$00FF              ; 下位 8bit のみが受信値

 

    ; --- S4: リングバッファ書込 ---

    JSR  rx_push                ; A=byte を push

 

    ; --- S5: UART_STAT WTC（RX_READY クリア） ---

    LDW  B, #$0002

    STW  B, [UART_STAT]

 

    ; --- S6: IRQ_STAT WTC（bit0 クリア） ---

    LDW  B, #$0001

    STW  B, [IRQ_STAT]

 

    ; --- S7: 待機中クライアントを起こす ---

    JSR  wake_uart_waiter

 

irq1_done:

    ; --- S8: レジスタ復帰、IRET ---

    LDW  A, [IRQ1_WK_A]

    LDW  B, [IRQ1_WK_B]

    LDW  X, [IRQ1_WK_X]

    IRET

## **5.4 rx_push サブルーチン**

rx_push:                        ; A=byte（下位8bit有効）

    STW  A, [IRQ1_WK_BYTE]      ; byte 退避

    LDW  A, [UART_RX_COUNT]

    LDW  B, #16

    CMP  A, B

    BGE  rx_push_overrun        ; COUNT >= 16 → 破棄

 

    ; --- (1) データ書込 ---

    LDW  X, [UART_RX_HEAD]      ; X = HEAD（インデックス）

    LDW  B, #UART_RX_RING_BUF

    ADD  B, X                   ; B = &buf[HEAD]

    LDW  A, [IRQ1_WK_BYTE]

    STB  A, [B]                 ; buf[HEAD] = byte

 

    ; --- (2) HEAD 更新（先） ---

    LDW  A, X

    INCW A

    ANDI A, #$000F              ; HEAD = (HEAD + 1) mod 16

    STW  A, [UART_RX_HEAD]

 

    ; --- (3) COUNT 更新（後） ---

    LDW  A, [UART_RX_COUNT]

    INCW A

    STW  A, [UART_RX_COUNT]

rx_push_overrun:

    RTS

【注】上記擬似アセンブリは設計説明用。INCW / ANDI の正確なニーモニック・オペランド形式は ISA2.3 / hasm23 の実際の構文に合わせて kernel.asm 実装フェーズで再確認する。

## **5.5 wake_uart_waiter サブルーチン**

UART_GETC 待ちクライアントが居る場合、IRQ ハンドラ内で UART ドライバタスクを介さず直接 REPLY 相当の処理を実施する。これにより GETC のレイテンシを最小化する。

**■【v1.5 追加・TKT-02】呼出規約**

| 項目 | 内容 |
|---|---|
| 入力 | `UART_WAIT_TID`（0 = 待機者なし。0 なら即 return） |
| 入力 | **`UART_RX_COUNT > 0`**（★内部で `rx_pop` を呼ぶため必須。現状は呼出元 IRQ1_HANDLER S4 の `JSR rx_push` 直後であることで保証される。**別経路から呼ぶ場合は呼出側で `COUNT > 0` を保証すること**） |
| 出力 | クライアント TCB に `ipc_msg[0]=byte` / `ipc_valid=1` / `state=READY`、`UART_WAIT_TID=0` |
| 破壊 | A, B, X（呼出元 IRQ1_HANDLER が全退避済） |
| 使用ワーク変数 | `L1_WK_TMP` / `L1_WK_C` / `IPC4_WK_SRCTCB` |

> 呼出先の入力契約は**呼出側が継承宣言する**こと。`rx_pop` が
> 「入力: COUNT>0」を明記していても、`wake_uart_waiter` が黙っていれば
> さらにその呼出側は前提を知り得ない（原則6 の連鎖）。

### **5.5.1 【実装必須ルール】wake_uart_waiter は IPC4-REPLY をコピーベースに実装すること**

**■ 必須実装ルール（review8 由来・違反時は実装事故確定）**

wake_uart_waiter は、kernel.asm の現行 IPC4_REPLY 実装（**【v1.3 更新】v0.12.6 kernel_v12_5.asm** 由来）

を「コピペベース」で実装し、引数展開部分のみを差し替えること。

禁止事項：

 ✗ 「TCB を最小限書き換えればよい」と判断して独自実装する

 ✗ 「ipc_msg と state と valid だけ書けば動くだろう」とフィールドを省略する

 ✗ IPC4_REPLY のソースを参照せずに本設計書 §5.5 擬似コードだけで実装する

理由：

  IPC4_REPLY は将来、キュー管理・スケジューラフラグ・優先度調整・

  ready list 操作などが追加される可能性がある。wake 側が独自実装だと、

  **【v1.3 注記】IPC4 Pool 方式（v0.12.5〜）の導入後も、IPC4_REPLY の REPLY 経路は TCB 直接書込（プール非経由）のまま変わっていないため、wake_uart_waiter の構造は継続有効。**
  IPC4_REPLY が拡張された時に wake_uart_waiter だけが古い実装のまま残り、

  「IPC4_REPLY 経由の REPLY は動くが UART RX 経由の REPLY だけ壊れる」

  という、極めて発見が困難なバグ（ドライバ起因に見えない）が発生する。

正しい実装手順：

  1. kernel_v09.asm の IPC4_REPLY: ラベル以降のコードをコピーする

  2. 「DSP からの 4 ワード pop」「tid の pop」を「UART_WAIT_TID 取得 + 

     rx_pop で取得した byte 1 個」に差し替える

  3. それ以外の TCB 書き込み・state 遷移ロジックは原則そのまま流用する

  4. EI / DI の取り扱いは IRQ ハンドラ内である点を考慮（既に IE=0、

     IRET で IE 復帰のため明示的 EI 不要）

**■【v1.5 追加・TKT-02 最重要】コピペ規約の適用範囲には限界がある**

**本規約が保証するのは「コピー元と同じ部分の正しさ」だけである。**
差し替え・新規挿入した命令は、規約の**保証範囲外**である。

TKT-02 欠陥①（2026-08-04 発覚）はこの盲点そのものであった。

| 項目 | 内容 |
|---|---|
| 誤った箇所 | `JSR rx_pop`（**コピー元 IPC4_REPLY に存在しない挿入命令**）の直後 |
| 正しかった箇所 | TCB 書込・state 遷移・A7 条件判定など**コピーした部分はすべて正しかった** |
| 発見が遅れた理由 | 本設計書 v1.4 §5.5.3 の擬似コードにも同じ誤りがあり、**実装は設計書どおりに正しく実装されていた**。「実装が設計書と一致するか」を見る通常のレビューでは**原理的に検出できなかった** |
| 被害 | シェルが1文字受信しても永久に起床せず、READY タスク 0 個からスケジューラ無限ループ（TKT-00）を誘発 |

**したがって以下を必須とする。**

  5. **差し替え・挿入した命令には `★差替` コメントを付け、コピー元との差分を明示する**

  6. **挿入した `JSR` については、呼出先の「破壊レジスタ」「入力契約」を
     ヘッダで確認し、必要なレジスタ退避・復元を明示的に行う。
     この箇所だけは規約に頼らず独立にレビューすること**

  7. **レビュー時は、擬似コードと実装の一致確認だけでなく、
     `★差替` 箇所について呼出先の副作用一覧との突き合わせを行うこと**

> ※ 本項は kaizen 原則102 系3 に対応する。原則6（副作用スコープの明記）は
> 「呼ばれる側」の規律であり、`rx_pop` は「破壊: A,B,X」を正しく明記していた。
> **明記だけでは防げない**ことの実例である。

### **5.5.2 IPC4-REPLY 現行実装の解析（コピー元の参照点）**

**【v1.3 更新】** v0.12.6 kernel_v12_5.asm の IPC4_REPLY（$0B00）実装を解析した結果、wake_uart_waiter で必ず再現すべき処理は以下のとおり。実装時はこの一覧と現行 IPC4_REPLY のソースを並べて照合すること。

| **No.** | **IPC4_REPLY での処理** | **wake での扱い** |
| --- | --- | --- |
| A1 | DI（IRQ 抑止） | IRQ ハンドラ内なので不要（既に IE=0） |
| A2 | DSP から tid を pop し IPC4_WK_DST に格納 | tid は UART_WAIT_TID から取得（DSP 不使用） |
| A3 | tid から TCB アドレスを計算: tid*80 /* v1.3更新 */ + tid*16 + $4000 = tid*80 + $4000、IPC4_WK_SRCTCB に格納 | 同じ計算式を流用（v2.0 TCBサイズ80B規約） |
| A4 | DSP から r0/r1/r2/r3 を順に pop し、TCB+16/+18/+20/+22 へ書込 | r0=byte（rx_pop 結果）、r1/r2/r3=0 を直接書込（DSP 経由しない）<br>**【v1.5 追加・TKT-02】★ここはコピー元 IPC4_REPLY に存在しない `JSR rx_pop` を挿入する箇所である。`rx_pop` は A・B・X を破壊するため、呼出直後に `LDW X,[IPC4_WK_SRCTCB]` で X（TCB ポインタ）を復元すること。**コピペ規約はこの挿入命令を保証しない**（§5.5.1 の【v1.5 追加】参照）** |
| A5 | TCB+24 = 1 (ipc_valid) | 同じ書込を流用 |
| A6 | TCB+26 = CUR_TASK (ipc_sender) | IRQ コンテキストでは送信者は「IRQ そのもの」だが、互換性のため CUR_TASK を流用してよい（クライアントは sender を見ない設計） |
| A7 | TCB+0 (state) を読み、6 (TASK-WAIT-REPLY) なら 1 (TASK-READY) へ遷移、それ以外はそのまま | 【極めて重要】この条件判定を必ず流用すること。クライアントが既に READY なのに上書きする等、状態破壊を防ぐ |
| A8 | EI（IRQ 復帰） | IRQ ハンドラ内なので不要（IRET で復帰） |

**【TCB アドレス計算式】** kernel_v09.asm L823-832 の式は、見た目は SHL+ADD だが結果として tid*80+$4000 になる。これは v2.0 設計書 §3.1 の TCB サイズ 80B（64B + 16B 拡張）と整合する。実装時はこの 5 命令ブロックを丸ごとコピーすればよい。

### **5.5.3 wake_uart_waiter 擬似コード（v1.2 で更新）**

以下は §5.5.1 のルールに従って IPC4_REPLY をベースに展開した擬似コード。実装時は現行 IPC4_REPLY を直接参照し、本擬似コードは方向性確認用とすること。

wake_uart_waiter:

    ; A2': UART_WAIT_TID から tid 取得（DSP 不使用）

    LDW  A, [UART_WAIT_TID]

    BEQ  wake_done              ; 0 なら待機者なし

 

    ; A3: tid → TCB アドレス（IPC4_REPLY と同一の計算式をコピー）

    STW  A, [L1_WK_TMP]

    LDW  B, #6

    SHL  A, B

    STW  A, [L1_WK_C]

    LDW  A, [L1_WK_TMP]

    LDW  B, #4

    SHL  A, B

    LDW  B, [L1_WK_C]

    ADD  A, B

    LDW  B, #$4000

    ADD  A, B

    STW  A, [IPC4_WK_SRCTCB]

    MOV  X, A

 

    ; A4': r0=byte (rx_pop), r1=0, r2=0, r3=0 を TCB+16/+18/+20/+22 へ

    JSR  rx_pop                 ; A=byte（下位8bit）★差替: コピー元に無い挿入命令

    ; ★★★【v1.5 追加・TKT-02 欠陥①是正】★★★
    ; rx_pop は「破壊: A, B, X」である（§3.4／kernel rx_pop ヘッダ参照）。
    ; 内部の MOV X,A により X = &buf[TAIL] のまま復帰するため、
    ; TCB ポインタを必ず復元すること。欠落すると以降の [X + #nn] 書込が
    ; リングバッファ領域（$FC46〜）に着弾し、特に TAIL=0 のとき
    ; [X + #24](ipc_valid) が UART_WAIT_TID($FC5E) を破壊して
    ; 待機者が永久に起床しない。
    ; LDW X,[addr] は A を破壊しないため rx_pop の戻り値は保持される。
    LDW  X, [IPC4_WK_SRCTCB]    ; ★X = TCB アドレスを復元（A は保持）

    STW  A, [X + #16]           ; ipc_msg[0] = byte（※注: r0 を msg0 に置く）

    LDW  A, #0

    STW  A, [X + #18]           ; ipc_msg[1] = 0

    STW  A, [X + #20]           ; ipc_msg[2] = 0

    STW  A, [X + #22]           ; ipc_msg[3] = 0

 

    ; A5: ipc_valid = 1

    LDW  A, #1

    STW  A, [X + #24]

 

    ; A6: ipc_sender = CUR_TASK（互換性のためそのまま）

    LDW  A, [CUR_TASK]

    STW  A, [X + #26]

 

    ; A7: state==6 (WAIT-REPLY) なら 1 (READY) へ — IPC4_REPLY と同一処理

    LDW  A, [X]                 ; state

    CMPI A, #6

    BNE  wake_no_state_change

    LDW  A, #1

    STW  A, [X]

wake_no_state_change:

 

    ; UART_WAIT_TID = 0（待機解除）

    LDW  A, #0

    STW  A, [UART_WAIT_TID]

 

wake_done:

    RTS

**【擬似コード上の注意】** 上記 A4' で「r0 を msg0 (TCB+16) に置く」点について：IPC4_REPLY は DSP から ( r3 r2 r1 r0 tid -- ) の順で pop し、結果として TCB+16=msg0=r0 となる。クライアント側 IPC4-CALL は ( -- r3 r2 r1 r0 ) で受け取り、Forth の規約上 TOS=r0 が「最後に push された＝最初に DROP される」値となる。テストタスク §7.4 では「SWAP DROP SWAP DROP SWAP DROP」で r0 のみ残しており整合する。実装時はクライアント側の受け取り方を kernel_v09.asm IPC4_CALL_RESUME と並べて確認のこと。

### **5.5.4 実装時セルフチェック**

wake_uart_waiter 実装後、kernel.asm 上で以下を確認する。

| **No.** | **確認項目** | **確認方法** |
| --- | --- | --- |
| C1 | TCB アドレス計算ブロックが IPC4_REPLY と同一 | diff で 5 命令ブロックを比較（コピペで違いがないこと） |
| C2 | TCB+16/+18/+20/+22 への 4 ワード書込が漏れていない | コードレビューで全フィールドが書かれているか確認 |
| C3 | TCB+24 (ipc_valid) = 1 が書かれている | コードレビュー |
| C4 | TCB+26 (ipc_sender) が書かれている | コードレビュー |
| C5 | state==6 → 1 の条件分岐が IPC4_REPLY と同一 | diff で _ipc4reply_done ラベル相当部分を比較 |
| C6 | DI/EI が混入していない（IRQ ハンドラ内のため不要） | grep DI / EI で確認 |
| C7 | UART_WAIT_TID = 0 のクリアが最後に行われる | コードレビュー |

## **5.6 IRQ1 用ワーク変数**

IRQ1 ハンドラ専用ワーク変数を kernel.asm に追加する。既存の IRQ_WK_X / IRQ_WK_A は IRQ0 が使用しているため流用しない。

| **シンボル** | **アドレス** | **用途** |
| --- | --- | --- |
| IRQ1_WK_A | $4232 | IRQ1 用 A 退避 |
| IRQ1_WK_B | $4234 | IRQ1 用 B 退避 |
| IRQ1_WK_X | $4236 | IRQ1 用 X 退避 |
| IRQ1_WK_BYTE | $4238 | 受信バイト一時保管 |

配置先 $4232-$4239 は yuios_memmap_design_v1_2.md **【v1.3 更新】** §3 の「カーネルワーク変数 ($4200-$423F)」内の空き領域。MemMgr が $422C-$4230 まで使用しているため、その直後を採用する。

**【v1.2 補足】** wake_uart_waiter は IPC4_REPLY と同じ IPC4_WK_SRCTCB / L1_WK_TMP / L1_WK_C を流用するため、新規ワークは IRQ1 用 4 個のみで足りる。L1_WK_* は IRQ0 と共有するが、wake_uart_waiter は DI 不要（IRQ1 内で IE=0）かつ IRQ0 とは時間的に重ならない（同時発火しない構造）ため衝突しない。

# **6. IPC4 メッセージ仕様**

## **6.1 op 番号**

yuios_design_v2_0.docx §6.2 と整合する。

| **op 名** | **値** | **Forth 定数名** |
| --- | --- | --- |
| UART-PUTC-OP | $0401 | UART-PUTC-OP |
| UART-GETC-OP | $0402 | UART-GETC-OP |
| UART-PUTS-OP | $0403 | UART-PUTS-OP |

## **6.2 リクエスト/レスポンス対応表**

| **op** | **リクエスト引数** | **応答 (r0/r1/r2/r3)** | **ブロック条件** |
| --- | --- | --- | --- |
| UART_PUTC | arg0 = 文字コード | 0 / 0 / 0 / 0 | TX_READY 成立まで（短時間ポーリング） |
| UART_PUTS | arg0 = 文字列先頭アドレス（NUL終端） | 0 / 0 / 0 / 0 | 全文字送信完了まで（ドライバ内ポーリング、§6.4 試算参照） |
| UART_GETC | なし | r0 = 受信文字（下位8bit有効） | リングバッファ空 → クライアントが TASK-WAIT-REPLY、IRQ ハンドラから起床 |

## **6.3 PUTC 内部実装**

**【v1.1 整合】** review R4 反映。TX_READY ポーリング待ちは必須。「直接書込」は HW フロー制御がない意のみで、ソフトウェア同期は必要。

: UART-PUTC-IMPL  ( char -- )

    BEGIN UART-STAT @ 1 AND UNTIL  \ TX_READY=1 待ち（必須）

    UART-TX ! ;                    \ 1バイト送信

【設計判断】TX TDRE 割込（IRQ_MASK bit2）はリセット時にマスク状態（HANDOVER_CHAT19 K4）。本書 v1.1 では TX 側はポーリングのままとし、TX TDRE 割込は使用しない。これにより UART-PUTC-IMPL の実装が単純化される。将来 PUTS の高速化が必要になった段階で TX 割込方式に拡張する。

## **6.4 PUTS 内部実装**

: UART-PUTS-IMPL  ( addr -- )

    BEGIN

        DUP C@                     \ 1バイト読出

        DUP 0= IF                  \ NUL 検出

            DROP DROP EXIT

        THEN

        UART-PUTC-IMPL

        1+

    AGAIN ;

**【v1.1 ブロック時間試算 (review R5)】** ysd8001 設計書 §6.3 より、emu23 では 1 バイト送信に約 4167 サイクル要する。N バイトの PUTS は最大で約 4167 × N サイクルブロックする。例: 16 バイト送信 ≒ 66,672 サイクル ≒ 16.7 ms (4 MHz 換算)。この間 UART ドライバタスクは他のリクエスト（PUTC/GETC）を受け付けられない。長文出力時のレイテンシ要件がある場合は将来 TX TDRE 割込化（FIFO + 非同期 REPLY）で対応する。

## **6.5 GETC 内部実装（v1.1 全面改訂・review R3 反映）**

GETC は UART ドライバの中で最も慎重な実装が必要な部分である。バッファ非空時は即時 REPLY し、空時は IRQ ハンドラからの起床経路に委ねる。WAIT-TID 設定と COUNT 確認の間に IRQ が割り込むレース条件への対策として、再チェックループパターンを採用する。

### **6.5.1 レース条件の本質**

【危険シナリオ（v1.0 設計のまま実装した場合）】

 

  T0: ドライバ: UART-GETC-IMPL に進入、COUNT==0 を確認

  T1: ドライバ: WAIT-TID = client_tid をセット

  T2: ←←← この瞬間 IRQ1 発火、wake_uart_waiter 動作

       ・rx_pop で byte 取得

       ・クライアント TCB に書込、state=READY

       ・WAIT-TID = 0

  T3: ドライバ: EI して EXIT、ループへ戻る

  T4: クライアント: WAIT-REPLY でブロック ← 既に READY なのに待機状態に

      → 永久ブロック（次の RX 来るまで）

### **6.5.2 解決策: 再チェックループ**

DI 中に WAIT-TID をセットした直後、COUNT を再確認する。DI 区間中は IRQ が抑止されているため、再確認時点で COUNT が変化していれば「DI 直前または再確認直前に IRQ 経路が動いた」のいずれでもないため、自タスクで pop して REPLY すれば良い。

: UART-GETC-IMPL  ( tid -- )

    DI                              \ §3.5 同時アクセス保護

 

    UART-RX-COUNT @ 0= IF

        \ --- バッファ空: 待機登録 ---

        DUP UART-WAIT-TID !         \ tid 保存

 

        \ --- 再チェック（review R3 対策） ---

        UART-RX-COUNT @ 0= IF

            \ DI 中なので IRQ は来ていない。安全に WAIT 状態へ

            EI

            DROP                    \ tid 消費（REPLY しない）

            EXIT                    \ クライアントは WAIT-REPLY 継続

        ELSE

            \ DI 直前に IRQ が走り COUNT が増えた稀なケース

            \ ※実際には WAIT-TID をセットしたタイミング上

            \   この else 節に入ることはない（DI 後は IRQ 不発）

            \   が、コードの完全性のため残す

            0 UART-WAIT-TID !       \ 待機キャンセル

            \ 下に流れて pop & REPLY

        THEN

    THEN

 

    \ --- バッファ非空: 即 REPLY ---

    UART-RX-POP                     \ ( -- byte )

    EI

    >R                              \ R: byte

    0 0 0 R>                        \ r3=0 r2=0 r1=0 r0=byte

    \ ※ 実際のスタック整理は IPC4-REPLY のスタック効果

    \    ( r3 r2 r1 r0 tid -- ) に合わせて実装時に正規化

    IPC4-REPLY ;

### **6.5.3 レース対策の正当性**

| **時点** | **イベント** | **結果** |
| --- | --- | --- |
| T0 直前 | クライアントが IPC4-CALL を発行、ドライバへメッセージ転送 | クライアントは TASK-WAIT-REPLY 状態にカーネルが遷移済 |
| T1 | ドライバが UART-GETC-IMPL に入り DI | 以降 IRQ 抑止 |
| T2 | COUNT==0 確認 | 確認時点で空 |
| T3 | WAIT-TID = tid | DI 中なので IRQ ハンドラは動かない |
| T4 | COUNT 再確認 = 0 | DI 中に COUNT は増えない（DI 直前の確認と同値） |
| T5 | EI、EXIT | EI 直後 IRQ が来ても、wake_uart_waiter が WAIT-TID を見て即時起床 |
| T6 以降 | RX 到着 → IRQ 発火 | クライアントは既に WAIT-REPLY 中（T0 直前で確定）→ 確実に起床 |

クライアントが TASK-WAIT-REPLY 状態に入るのは IPC4-CALL の完了時点（ドライバが IPC4-RECV する前）であり、ドライバが GETC-IMPL を実行している時点では既に WAIT-REPLY が確定している。したがって IRQ ハンドラは安全に「ipc_valid=1, state=READY」を書ける。

## **6.6 待機解除経路（IRQ → クライアント直接 REPLY）**

§5.5 wake_uart_waiter で説明したとおり、IRQ ハンドラは UART_WAIT_TID が非0の場合、UART ドライバタスクを起こさず直接クライアントへ「ipc_msg[0] = byte / ipc_valid = 1 / state = READY」を書き込む。

【根拠】UART ドライバタスクが GETC 応答のためだけに走るのは無駄であり、また UART ドライバが他のリクエスト（PUTC/PUTS）処理中だと GETC 応答が遅延する。IRQ コンテキストで直接 REPLY 相当の処理を行うことで一貫したレイテンシを保証できる。

【トレードオフ】IRQ ハンドラの責務が増えるが、操作は TCB への 5 ワード書込（msg0..msg3、ipc_valid、ipc_sender）と state 条件遷移、UART_WAIT_TID クリアのみで完結し、複雑度は許容範囲内。実装の正しさは §5.5.1 のコピペルールで担保する。

# **7. UART テストタスク仕様**

## **7.1 目的**

UART ドライバの動作を起動時自動検証するためのテストタスクを Forth 側に組み込む。HANDOVER_CHAT19 §3.2 で確定済の方針。

## **7.2 テストシーケンス**

| **No.** | **操作** | **期待動作** |
| --- | --- | --- |
| T1 | UART_PUTC で 'A' を送信 | ホスト stdout に 'A' が即時出力される |
| T2 | UART_PUTS で "BC\0" を送信 | ホスト stdout に "BC" が即時出力される |
| T3 | UART_GETC を発行（バッファ空） | クライアントは TASK-WAIT-REPLY でブロック |
| T4 | emu23 -i ファイルから 'X' を注入 | IRQ1 発火 → リングバッファに格納 → ハンドラから起床 → クライアントへ 'X' 応答 |
| T5 | 受信した 'X' を UART_PUTC でエコーバック | ホスト stdout に 'X' が出力される |
| T6 | 完了マーカー 'D' を UART_PUTC で送信 | ホスト stdout に 'D' が出力される（テスト完走確認） |

## **7.3 期待出力**

  ABCXD

マーカー 'D' は "Done" の意。emu23 の自動テストでは終了時にこの文字列を grep で確認する。

## **7.4 テストタスク Forth 擬似コード**

: UART-TEST-TASK  ( -- )

    \ T1: PUTC

    $41 0 0 0  UART-PUTC-OP  UART-DRV-TID @  IPC4-CALL

    DROP DROP DROP DROP

    \ T2: PUTS

    BC-STR  0 0 0  UART-PUTS-OP  UART-DRV-TID @  IPC4-CALL

    DROP DROP DROP DROP

    \ T3-T4: GETC（IRQ で起床）

    0 0 0 0  UART-GETC-OP  UART-DRV-TID @  IPC4-CALL

    \ ( -- r3 r2 r1 r0 ) r0 に受信文字

    SWAP DROP SWAP DROP SWAP DROP   \ r0 のみ残す

    \ T5: エコーバック

    0 0 0  UART-PUTC-OP  UART-DRV-TID @  IPC4-CALL

    DROP DROP DROP DROP

    \ T6: 完了マーカー

    $44 0 0 0  UART-PUTC-OP  UART-DRV-TID @  IPC4-CALL

    DROP DROP DROP DROP

    \ 終了

    BEGIN AGAIN ;                   \ 完了後は無限ループで停止待ち

## **7.5 起動シーケンス（kernel_forth.fs main 部に追加）**

: OS-START  ( -- )

    MEMMGR-START                    \ Ph.2 既存

    UART-START                      \ Ph.3 新規

    UART-TEST-START                 \ テストタスク起動

    BEGIN PAUSE AGAIN ;             \ ルートタスクは待機ループ

# **8. 影響範囲（既存ファイル変更点）**

| **ファイル** | **変更内容** | **改版見込み** |
| --- | --- | --- |
| kernel.asm (現 v0.9) | IRQ1 ベクタを IRQ1_HANDLER に差替、IRQ1_HANDLER / rx_push / wake_uart_waiter / IRQ1_WK_* 追加 | v0.9 → v0.10 |
| kernel_forth.fs (現 v0.5) | UART-DRV-TASK / UART-DISPATCH / UART-START / UART-TEST-TASK / UART-TEST-START / UART-* 定数追加 | v0.5 → v0.6 |
| ysd8800_kern.tgt | 変更なし | — |
| yuios_kernel_memmap (現 v1.1) | $E210-$E22F 追記、$4232-$4239 追記 | v1.1 → v1.2（実装後） |
| yuios_design_v2_0.docx | Ph.3 UART 詳細を本書から参照 | v2.0 → v2.1（実装後・必要に応じ） |
| emu23_v102.c | 変更なし（既に IRQ1/UART 対応済み） | — |

# **9. KY（危険予知）と既知リスク**

## **9.1 設計レベルの危険予知（v1.2 で増補）**

| **No.** | **危険** | **防止策** |
| --- | --- | --- |
| KY1 | IRQ1 ハンドラの RX クリア順序を誤ると割込多重発火（ハンドラ無限ループ） | §5.2 統合手順表で順序を厳格定義、コードコメントにも順序を強制記載 |
| KY2 | リングバッファインデックスの mod 16 を誤実装するとオーバーフロー（メモリ破壊） | §3.3/3.4 の擬似コードに ANDI #$000F を明記、実装時は単体テストで境界確認 |
| KY3 | UART_WAIT_TID の更新中に IRQ が割り込むと TID が破損する | §6.5 で DI/EI ガードを明示。EI は REPLY 直前で行う |
| KY4 | wake_uart_waiter で TCB を直接書き換えるため、IPC4-REPLY との実装ズレが発生しうる | 【v1.2 強化】§5.5.1 で「IPC4-REPLY をコピペベース」を必須ルール化、§5.5.4 でセルフチェック項目を規定 |
| KY5 | tid 衝突: UART-DRV-TID を初期化前 (=0) に他タスクが UART を呼ぶと tid=0 (Forth ルート) に IPC が飛ぶ | OS-START 順序で UART-START 完了後にテストタスクを起こす。UART-DRV-TID==0 の場合は IPC4-CALL を行わない防御コードをクライアント側に推奨 |
| KY6 | [v1.1 追加] UART_GETC を 2 タスク以上が同時発行すると、後発の WAIT-TID が先発を上書きし、先発クライアントが永久ブロックする | §9.2 で v1.1 範囲では「同時 1 タスクのみ」を仕様として明文化。複数タスク要件発生時は WAIT キュー化（v2.0 候補） |
| KY7 | [v1.1 追加] WAIT-TID 設定後、クライアントが WAIT-REPLY 状態に入る前に IRQ が来て REPLY ロスト | §6.5.2 再チェックループ採用、および IPC4-CALL の意味論（呼出時点で WAIT-REPLY 確定）に依拠 |
| KY8 | [v1.1 追加] 起動時 IRQ_MASK 解除前に UART_STAT/IRQ_STAT に残留フラグがあると、IRQ 解除直後に意図しない発火 | §4.2 初期化手順でステータスクリア → IRQ 解除の順序を必須とする |
| KY9 | [v1.2 追加] 将来 IPC4_REPLY が拡張された時、wake_uart_waiter が独自実装だと取り残されて UART 経由 REPLY のみ壊れる（極めて発見困難） | §5.5.1 IPC4-REPLY コピペルールを必須化。kernel.asm 改版時に IPC4_REPLY と wake_uart_waiter を必ずペアでレビューする規約を §10.4 に追加 |

## **9.2 既知の制約（v1.2 範囲外）**

| **項目** | **内容** | **対応工程** |
| --- | --- | --- |
| TX 高速化 | PUTS が 1 バイトずつポーリング送信のため遅い（§6.4 試算: 16B で 16.7 ms） | Ph.3 完了後の最適化工程で TX TDRE 割込方式へ拡張 |
| IRQ 優先制御 | ysd8004_raise() の cpu.irq_pending 無条件上書き（HANDOVER §1.2 K1） | Ph.3 完了後の独立工程 |
| WAIT キュー化 | [v1.1 追加] UART_GETC 同時 1 タスクのみ。複数同時要求はキュー化が必要 | v2.0 候補。$E22A-$E22F 予約領域を WAIT キュー（最大3エントリ）に転用 |
| バッファサイズ可変化 | 現在 16B 固定。9600 bps 連続入力で 16 ms 分 | v2.0 以降で検討（32/64B 化） |

# **10. 次工程（Ph.3-A5 実装）への引継ぎ**

## **10.1 実装順序（review8 推奨を反映）**

| **順** | **作業** | **成果物** |
| --- | --- | --- |
| 1 | kernel.asm v0.10 改版 — IRQ1_HANDLER（§5.3）を最優先で実装 | kernel.asm v0.10 中間 |
| 2 | kernel.asm — rx_push（§5.4） / wake_uart_waiter（§5.5）を実装。wake は §5.5.1 ルール厳守 | kernel.asm v0.10 中間 |
| 3 | kernel.asm — IRQ1_WK_* 領域追加（§5.6）、ベクタ差替確認、kernel.asm v0.10 確定 | kernel.asm v0.10 |
| 4 | kernel_forth.fs v0.6 改版 — UART-GETC-IMPL（§6.5、レース絡み）を最優先で実装 | kernel_forth.fs v0.6 中間 |
| 5 | kernel_forth.fs — UART-PUTC-IMPL / UART-PUTS-IMPL を実装（§6.3 / §6.4） | kernel_forth.fs v0.6 中間 |
| 6 | kernel_forth.fs — UART-DRV-TASK / UART-DISPATCH / UART-START / 定数群を追加 | kernel_forth.fs v0.6 中間 |
| 7 | kernel_forth.fs — UART-TEST-TASK / UART-TEST-START / OS-START 改修 | kernel_forth.fs v0.6 |
| 8 | yuios_build_procedure_v1_0.docx に従ってビルド | yuios_v10.bin / yuios_v10.sym |
| 9 | emu23 v1.02 で起動、期待出力 "ABCXD" を確認 | テストログ |
| 10 | Ph.2 の M28AR 出力が回帰していないことを確認 | 回帰テストログ |
| 11 | yuios_kernel_memmap v1.2 へ改版（$E210/$4232 領域追記） | memmap v1.2 |

## **10.2 入力ファイル（emu23 -i）**

UART_GETC テスト用に 1 バイトの入力ファイルを準備する。

  $ printf 'X' > uart_test_input.bin

  $ ./emu23 yuios_v10.bin yuios_v10.sym -i uart_test_input.bin -q

  期待出力: ABCXD

## **10.3 デバッグ観点**

emu23 のデバッグログ出力（§6.5 のレポート時）に以下を加えると問題切り分けが容易：UART_STAT の値、IRQ_STAT の値、UART_RX_COUNT の値、UART_WAIT_TID の値。

## **10.4 【v1.2 新設】実装フェーズ規約（必読）**

本設計書を別チャットで実装する際、以下の規約を厳守すること。

**■ 実装フェーズ必読規約**

規約 1. 実装着手前に本設計書の §5.5.1 / §5.5.2 / §5.5.4 を必ず通読する。

        wake_uart_waiter の実装方針を頭に入れた状態で kernel.asm を

        触り始めること。

規約 2. wake_uart_waiter を実装する時は、必ず先に kernel_v09.asm の

        IPC4_REPLY: ラベル（v0.9 では L841 付近）を view ツールで開き、

        画面の左半分に表示すること。右半分で wake_uart_waiter を書く。

        「IPC4_REPLY を見ずに wake を書く」は本設計書違反である。

規約 3. kernel.asm を改版（v0.9→v0.10）した際は、IPC4_REPLY と

        wake_uart_waiter を必ずペアでレビューする。IPC4_REPLY が改修

        された場合は wake_uart_waiter の追従が必要かを必ず判定する。

規約 4. §5.5.4 セルフチェック項目 C1〜C7 を実装完了報告に含めること。

        全項目 PASS でなければ Ph.3-A5 完了とは認めない。

規約 5. 期待出力 "ABCXD" の確認に加え、Ph.2 回帰テスト（M28AR 出力）

        が PASS することを必ず確認する。Ph.3 改修で Ph.2 が壊れていない

        ことの保証は実装担当の責務。

規約 6. 本設計書 v1.2 で確定したアドレス（§2.2 / §5.6）を勝手に変更

        しない。変更が必要な場合は本設計書を v1.3 に改版してから実装

        を進めること（kaizen.txt 「設計→実装の分離」原則）。

規約 7. 実装中に本設計書の不備に気付いた場合は、実装を一旦停止し、

        進捗管理チャットで設計書改版の要否を相談すること。設計書を

        無視した独自実装は禁止。

# **11. レビュー履歴**

本書 v1.2 までのレビュー経緯を以下に示す。

| **版** | **レビュー文書** | **レビュー結果** | **対応** |
| --- | --- | --- | --- |
| v1.0 | review7.txt | 修正必須 4 件 + 改善 4 件の指摘 | v1.1 で全件反映 |
| v1.1 | review8.txt | 実装 GO（評価 8.5〜9/10）。設計として閉じている。実装時の注意 1 件（IPC4-REPLY コピペ）を提示 | v1.2 で実装ルールとして正式記載（§5.5.1 / §10.4） |
| v1.2 | (本書) | — | FIX 候補。実装フェーズ着手可 |

## **11.1 v1.2 レビュー観点（再レビュー時）**

v1.2 は v1.1 に対し実装ルールの追記のみであり、設計内容自体に変更はない。再レビューが必要な場合は以下のみ確認願いたい。

| **No.** | **観点** |
| --- | --- |
| RV1 | §5.5.1 のコピペルールが実装担当に伝わる文体・配置になっているか |
| RV2 | §5.5.2 の IPC4_REPLY 解析（A1〜A8）が kernel_v09.asm L841 以降の現実装と一致しているか |
| RV3 | §5.5.3 擬似コードの A4'（ipc_msg[0] = byte）が IPC4_REPLY の引数順と整合しているか |
| RV4 | §5.5.4 セルフチェック C1〜C7 が実装漏れを十分カバーしているか |
| RV5 | §10.4 実装フェーズ規約 1〜7 が現実的か（過剰でも不足でもないか） |
| RV6 | KY9 の表現が運用上有効か |

# **12. 関連文書**

| **文書** | **版数** | **参照箇所** |
| --- | --- | --- |
| yuios_design_v2_0.docx | v2.0 | §3.1 TCB / §4 IPC / §6.2 UARTドライバ |
| ysd8001_uart_design_v1_2.docx | v1.2 | §3 レジスタ / §4 動作 / §5 割込 / §6 emu23 実装 |
| yuios_memmap_design_v1_2.md **【v1.3 更新】** | v1.1 | §3 メモリマップ全体 |
| HANDOVER_CHAT19.docx | v1.0 | §3 確定設計事項 / §6 KY |
| yuios_build_procedure_v1_0.docx | v1.0 | §4 Ph.2 ビルド手順（実装時に踏襲） |
| emu23_v102_design_v1_3.docx | v1.3 | §6.2 RX ポーリング周期 / §6.3 TX タイミング |
| ISA2_3_v231.docx | v2.3.1 | 命令セット全般（実装時に参照） |
| YSD8800_ABI_spec.docx | — | ABI 全般 |
| kernel_v09.asm | v0.9 | §5.5.2 IPC4_REPLY コピー元（L841 以降） |
| review7.txt | — | v1.0 レビューフィードバック（v1.1 改版根拠） |
| review8.txt | — | v1.1 レビュー判定および実装ルール提示（v1.2 改版根拠） |

# **以上**

本書 v1.2 は v1.1 を実装ルール明文化により補強した版である。設計内容自体は v1.1 から変更なし、すべて追記による補強。

実装担当（別チャット作業者を含む）は §5.5.1 / §5.5.2 / §10.4 を必読のこと。

Page  /