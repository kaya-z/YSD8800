**YUI OS Ph.3-B ストレージドライバ設計書**

YSD8003 ストレージドライバ Forth タスク化詳細設計

Version 1.6  /  2026-05-03（最終改版: 2026-08-14）

| **項目** | **内容** |
| --- | --- |
| 文書番号 | YUIOS-PH3B-001 |
| 対象工程 | Step 8-Y Ph.3-B ストレージドライバ実装 |
| ISAバージョン | YSD8800 ISA2.3 |
| 関連設計書 | emu23_v105_design_v1_0.md (emu23 v1.05 設計)、emu23_device_design_v1_2.docx (YSD8003 仕様)、yuios_ph3_uart_design_v1_4.md (Ph.3-A5 UART 設計)、yuios_ph4_filemgr_design_v1_9_5.md (Ph.4 FileMgr 設計・実装完了) |
| 上位設計書 | yuios_design_v2_4.md §6.3 ストレージドライバ |
| 作成日 | 2026-05-03 |
| ステータス | v1.5（上位設計書・関連設計書・ツール版数を最新化・整合確認済み） |

# **改版履歴**

| **版数** | **日付** | **変更内容** | **作成者** |
| --- | --- | --- | --- |
| v1.0 | 2026-05-03 | 初版作成。Ph.3-A5 UART 設計の構造を踏襲し、IRQ1 駆動の遅延 IRQ 完了通知方式で設計 | Claude |
| v1.1 | 2026-05-03 | review9.txt 指摘全反映: ①WAIT-TID 上書きBUSY返却 ②IRQレース対策・WAIT前再チェックループ移植 ③512B転送中アトミシティ明文化 ④IRQハンドラ軽量化 ⑤STOR-LAST-OP削除 ⑥STAT再読余地明文化 ⑦バッファ戦略明文化 ⑧IRQ_CTRL冪等性ルール ⑨BC-STR移動の手順注記 | Claude |
| v1.2 | 2026-05-03 | review10.txt の GO 判定および「実装前チェックリスト」を正式記載。①SELF-IPC-VALID? の判定ロジックを案A（STOR-LAST-STATベース）に修正 (§5.5.2) ②EXEC直前の `0 STOR-LAST-STAT !` クリアを §4.4/§4.5 に追加 ③§5.3 IRQ ST1 で STOR-LAST-STAT 非0保証を明記 ④WAIT-TID 全EXITパスクリア確認を KY11 強化 + §12 実装前チェックリスト新設 | Claude |
| v1.3 | 2026-05-17 | Ph.3.5 Step 6 実装デバッグで判明した設計誤りの反映：①STOR-DISPATCH READ分岐の SWAP 誤り修正（§4.3）、②`_ipc4_enqueue` msg インデックス誤り（op が 0000 になるバグ）を注記（§4.3 / §5.1 参照）、③IPC4_RECV saved_sp 修正の影響を§5 に注記 | Claude |
| v1.4 | 2026-05-24 | Ph.4 FileMgr 実装時に発覚した LBA=0 共有問題への対処：STOR-TEST-TASK の S2/S3 で使用する LBA を 0 → 10 に変更（§7.1/§7.2 改訂）。Ph.4 ではLBA=0 がスーパーブロック専用となるため、STOR-TEST が "STOR_TST" を LBA=0 に書き込むと FS-MOUNT の MAGIC-CHECK が必ず失敗していた。LBA=10 はデータ領域内（LBA=4 以降）で、最小ディスクサイズ 8KB (16セクタ) でも収まる。FileMgr 設計書 v1.2 §8.4 と整合（FILEMGR-TEST は LBA=10 を使わないこと） | Claude |
| **v1.6** | **2026-08-14** | **【emu23 v1.13（EMU-A 引数解析是正）への追従・記録の注記】**①**§10 の起動例 `./emu23 yuios_v11.bin yuios_v11.sym -i uart_test_input.bin --disk disk.img -q` に注記を追加。**当該コマンドは当時に実際に実行した記録であるため**コマンド自体は書き換えず保持**するが、**この形式では `.sym` が読めていなかった**事実を明記（`argv[2]=.sym` が `load_dbg()` に渡り、`argv[3]="-i"` は `load_sym()` の `fopen` 失敗として**黙殺**＝EMU-A。当時は警告も出なかった）。②**期待出力 `ABCXD P` の検証はシンボル非依存のため結果は有効**である旨を併記。③**emu23 v1.13 以降の推奨形 `--sym` を提示**。v1.13 では `-i` とその引数が消費済みとなるため旧形式でも `.sym` は自動導出で読まれる（`.dbg` 側の誤読は残る）。関連：`emu23_argsym_design_v1_0.md` §5.8.1 ／ `emu23_debug_manual_v1_4.md` §2.1。**本文の設計内容（ストレージドライバ設計・実装規約）に変更はない。**v1.5 までの記述は削除せず保持。 | Claude |
| v1.5 | 2026-06-06 | 上位設計書・関連設計書・ツール版数の整合更新：①上位設計書参照を yuios_design_v2_4.md に更新（Ph.4 完了・Ph.3.5 補完完了版）、②関連設計書を最新版（emu23_v105_design_v1_0.md・yuios_ph3_uart_design_v1_4.md・yuios_ph4_filemgr_design_v1_9_5.md）に更新、③対象エミュレータを emu23 v1.05 に更新（watermark 機能統合版）。本文内容（ストレージドライバ設計・実装規約）に変更なし | Claude |

## **v1.1 → v1.2 変更概要**

review10.txt は v1.1 を「実装に進んで問題ないレベル（実質GO）」と判定したが、「設計として成立しているか微妙な箇所」として2点の指摘を受けた。本 v1.2 ではこれを設計書本体に正式条項として刻み込み、実装担当が見落とせない形にする。

| **項目** | **指摘内容** | **反映箇所** |
| --- | --- | --- |
| IR1 | SELF-IPC-VALID? の判定ロジックが論理的不完全（WAIT前後で常にREADYのため区別できない）。案A（STOR-LAST-STATベース判定）で修正必須 | §5.5.2（書き換え） |
| IR2 | EXEC直前にSTOR-LAST-STATを0クリアする手順を追加（IR1のための前提） | §4.4 G3'（新設）/§4.5 G3'（新設）/§5.3 ST1 注記 |
| IR3 | WAIT-TIDクリアが「全EXITパス」で行われているか実装時にチェック必須 | §12.2（新設）/KY11（強化） |
| IR4 | 実装前チェックリスト（4項目）を設計書に正式記載 | §12（新設） |

# **1. 概要**

## **1.1 目的**

本書は、YUI OS Ph.3-B において YSD8003 ストレージコントローラを独立ドライバタスクとして実装するための詳細設計書である。

Ph.2 まではストレージは未対応で、Cアプリ（sd_sample.c 等）から直接 MMIO アクセスする形で利用していた。Ph.3-B ではマイクロカーネル方針に従い、ストレージを独立タスク化する。クライアントタスクは IPC4-CALL 経由でストレージサービスを利用する。

## **1.2 適用範囲**

| **レイヤ** | **実装** | **本書の扱い** |
| --- | --- | --- |
| YSD8003 ストレージチップ | MMIO レジスタ・遅延 IRQ 完了通知 | 対象外（emu23_device_design_v1_2.docx §6 / emu23_v103_design_v1_4.docx を参照） |
| IRQ1 ハンドラ拡張 | 既存 UART RX 処理に bit1 (STOR) 分岐を追加 | 本書 §5 で詳細設計 |
| ストレージドライバタスク | Forth ワード（kernel_forth.fs に追加） | 本書 §4 で詳細設計 |
| IPC4 メッセージ仕様 | SVC_STORAGE (0x05) 系 | 本書 §6 で詳細設計 |
| ストレージテストタスク | Forth ワード（起動時自動実行） | 本書 §7 で詳細設計 |
| 完了待ち単一スロット | UART_WAIT_TID と同パターン（STOR_WAIT_TID）+ BUSY返却保護 | 本書 §3 / §4.4 で詳細設計 |
| 実装前チェックリスト | 4項目（IR1-IR4） | 本書 §12 で必須化 |

## **1.3 設計方針（前提）**

ユーザ指示および review9.txt / review10.txt 反映により本工程で確定済みの方針：

| **項目** | **確定内容** |
| --- | --- |
| 完了通知方式 | IRQ1 駆動（emu23 v1.03 で 512 サイクル後遅延発火） |
| ポーリング併用 | 不要（マイクロカーネル方針優先） |
| タスク登録方法 | Forth ワード STOR-DRV-TASK として実装、STOR-START で TASK-CREATE 起動 |
| IRQハンドラ責務 | STAT保存 + IRQ_CTRL=0 + IRQ_STAT WTC + state遷移（READY化）のみ。ipc_msg設定なし、IPC4-REPLY発行なし |
| 転送+REPLYの責務 | ドライバタスク本体（STOR-READ-IMPL / STOR-WRITE-IMPL）内で実施 |
| **完了通知シグナル**【v1.2新】 | STOR-LAST-STAT が「IRQ完了の直接シグナル」を兼ねる。EXEC前に0クリア、IRQハンドラが必ず非0値を書き込む |
| STOR_READ 動作 | LBA設定 → STAT=0クリア → READ_SETUP → IRQ_CTRL=1 → EXEC → 再チェック → WAIT-IPC → STAT確認 → 512B転送 → IPC4-REPLY |
| STOR_WRITE 動作 | LBA設定 → STAT=0クリア → WRITE_SETUP → src→SD_DATA転送 → IRQ_CTRL=1 → EXEC → 再チェック → WAIT-IPC → STAT確認 → IPC4-REPLY |
| STOR_STAT 動作 | SD_STAT を読んで返す（即 REPLY、IRQ待ちなし） |
| 完了待ちスロット | STOR_WAIT_TID 単一スロット + BUSY返却ガード |
| アトミシティ保証 | 単一ドライバタスク + 同期RPC + WAIT-TIDガードで多重侵入防止（§3.3） |
| バッファ配置 | カーネルワーク内 STOR 専用サブ領域（$E230〜・UART 領域 $E210-$E22F の続き） |
| バッファ戦略 | 中間バッファなし・直接 SD_DATA → dst_addr 転送（§3.4） |
| IRQ1 (STOR) 取扱 | 既存 IRQ1_HANDLER に bit1 分岐を追加（軽量処理） |
| 完了待ち WAIT 動作 | ドライバ自身が TASK-WAIT-IPC で寝る、IRQで起床（state遷移のみ） |
| テスト方針 | STOR-TEST-TASK として Forth 側にテストタスク追加。LBA0 書込→読出→照合 |

# **2. メモリ配置**

## **2.1 配置領域の決定**

UART 領域 $E210-$E22F の続きとして、$E230 から開始する。yuios_kernel_memmap_v1_2.docx での既存予約領域を確認し、競合回避する。

【既存使用領域】

| **アドレス** | **用途** | **担当** |
| --- | --- | --- |
| $E200-$E204 | MemMgr (Ph.2: PAGE-BMP-LO/HI, MEM-TID-ADDR) | kernel_forth_v05.fs L67-69 |
| $E206-$E20F | MemMgr 予約 | (将来用) |
| $E210-$E22F | UART (Ph.3-A5) | kernel_v10.asm / kernel_forth_v06.fs |
| $E230 〜 | **本書で予約: ストレージ専用** | (本工程) |

【yuios_v06 で BC-STR が $E230 に配置されているため要調整】 kernel_forth_v06.fs L748 で `$E230 CONSTANT BC-STR` がある。これは UART テスト用文字列 "BC\0" の配置先で、kernel.asm v0.10 の $E230 にデータとして配置されている (yuios_ph3_uart_design_v1_2.docx §7.4)。

【判断】 BC-STR を $E230 → $E260 へ移動し、$E230-$E25F (48 B) をストレージ専用領域に充当する。これは UART テストタスクの動作にしか影響せず、kernel_v11.asm / kernel_forth_v07.fs の修正で対応可能。

## **2.2 ストレージ専用変数アドレス一覧**

| **アドレス** | **サイズ** | **シンボル名（Forth）** | **シンボル名（ASM）** | **用途** |
| --- | --- | --- | --- | --- |
| $E230 | 2 B | STOR-DRV-TID | STOR_DRV_TID | ストレージドライバタスク ID |
| $E232 | 2 B | STOR-WAIT-TID | STOR_WAIT_TID | EXEC 完了待ちタスク tid（0=なし、単一スロット） |
| $E234 | 2 B | STOR-LAST-STAT | STOR_LAST_STAT | IRQ1 ハンドラが保存する最終 SD_STAT 値。**【v1.2新】 IRQ完了通知シグナルを兼ねる（EXEC前0クリア、IRQ後必ず非0）** |
| $E236-$E25F | 42 B | (予約) | (予約) | 将来拡張用（複数スロット化・キャッシュ等） |
| $E260 | 3 B | BC-STR (移動) | BC_STR | UART テスト文字列（$E230 から移動） |
| $E263-$E27F | 29 B | (予約) | (予約) | UART 系拡張用 |

【v1.1 削除】 STOR-LAST-OP は v1.0 でデバッグ用に確保していたが、IRQ ハンドラ・ドライバいずれも参照しないため削除。将来ロギング機能を追加する場合は予約領域から再確保する。

【v1.2 役割追加】 STOR-LAST-STAT は元々「IRQ ハンドラが SD_STAT を保存する変数」だったが、v1.2 では**「IRQ完了通知シグナル」も兼ねる**。EXEC前にドライバが 0 にクリアし、IRQハンドラ ST1 で必ず非0値（READY=0x04 or ERROR=0x02）を書く。これにより SELF-IPC-VALID? の判定が論理的に成立する（§5.5.2）。

## **2.3 メモリマップ整合性確認**

| **参照文書** | **結果** | **備考** |
| --- | --- | --- |
| yuios_kernel_memmap_v1_2.docx | OK | $E230-$E25F は I/O 領域 ($FC80-) の外。Forth Workspace ($F000-$F7FF) とも干渉なし |
| kernel_forth_v06.fs (Ph.3-A5) | OK | $E210-$E22F のみ使用 ($E230 BC-STR は移動対応) |
| kernel_v10.asm (Ph.3-A5) | OK | UART 関連は $E210-$E22F 内に収まる |

# **3. アーキテクチャ設計**

## **3.1 全体フロー**

【v1.2 改訂】 STAT クリア手順（G3'）を追加：

```
[クライアント]                    [STOR-DRV-TASK]                   [IRQ1_HANDLER]                  [emu23/YSD8003]
     │                                  │                                 │                              │
     │ IPC4-CALL(STOR_READ, LBA, dst)   │                                 │                              │
     │─────────────────────────────────>│                                 │                              │
     │                                  │ G1: STOR_WAIT_TID チェック       │                              │
     │                                  │     (!= 0 ならBUSY即返却)        │                              │
     │                                  │ G2: LBA設定                       │                              │
     │                                  │ G3: SD_CMD ← READ_SETUP          │                              │
     │                                  │ ★G3': 0 STOR-LAST-STAT ! 【v1.2】│                              │
     │                                  │ G4: STOR_WAIT_TID ← 自分tid      │                              │
     │                                  │ G5: SD_IRQ_CTRL ← 1              │                              │
     │                                  │ G6: SD_CMD ← EXEC                │ ─── IRQ予約 ──────────────>│
     │                                  │ G7: DI（割込禁止）                │                              │
     │                                  │ G8: 再チェック                    │                              │
     │                                  │     (STOR-LAST-STAT @ 0<> なら   │                              │
     │                                  │      既にIRQ完了→WAITスキップ)  │                              │
     │                                  │ G9: TASK-WAIT-IPC で寝る (EI内包)│                              │
     │                                  │                                 │                              │
     │                                  │                                 │ <─── 512cycle後 IRQ1 ─────│
     │                                  │                                 │                              │
     │                                  │                                 │ ★I1: SD_STAT 読出           │
     │                                  │                                 │     必ず非0値              │
     │                                  │                                 │     (READY=0x04 or         │
     │                                  │                                 │      ERROR=0x02)           │
     │                                  │                                 │ I2: STOR_LAST_STAT に保存    │
     │                                  │                                 │ I3: SD_IRQ_CTRL ← 0          │
     │                                  │                                 │ I4: IRQ_STAT WTC bit1        │
     │                                  │                                 │ I5: wake_stor_waiter         │
     │                                  │                                 │     (state遷移のみ)        │
     │                                  │ <─── (state=READY) ────────────│                              │
     │                                  │                                 │                              │
     │                                  │ R2: STOR_LAST_STAT 確認          │                              │
     │                                  │     bit2(READY)?  → 続行         │                              │
     │                                  │     bit1(ERROR)?  → エラー応答  │                              │
     │                                  │ R3: SD_DATA から 512B 読出       │                              │
     │                                  │     dst_addr へ転送              │                              │
     │                                  │ R4: STOR_WAIT_TID ← 0 (解放)    │                              │
     │ <─── IPC4-REPLY (r0=0/−1) ────│                                 │                              │
```

## **3.2 STOR-WAIT-TID 単一スロット制約 + BUSYガード**

【review9 重大1】 単一スロットの「後勝ち上書き」リスクを以下で防止する：

ドライバが新規要求を受信した直後に `STOR_WAIT_TID != 0` をチェックし、非0ならBUSY (r0=-2) で即時返却する。

【BUSY返却の条件】

| **状態** | **STOR_WAIT_TID** | **判定** | **応答** |
| --- | --- | --- | --- |
| 待機なし | 0 | 受付可 | 通常処理 |
| 他タスクが待機中 | 非0 | BUSY | r0=-2 で即返却 |

【ドライバ自身が完了待ち中の場合】 ドライバ自身が TASK-WAIT-IPC で寝ている間は、メインループの IPC4-RECV まで戻らない。よって新規要求はカーネル側でブロックされ、ドライバが起床して IPC4-RECV するまで配送されない。よってBUSY発生はドライバが「直前要求のクリーンアップ前に次要求が来た」極稀なレースケースのみ。

【BUSYの定義】

```
r0 = -2 = BUSY (デバイス・ドライバ多重要求検出)
r0 = -1 = ERROR (デバイス側エラー、SD_STAT bit1=1)
r0 =  0 = 成功
r0 =  正値 = データ（STAT問い合わせ等）
```

## **3.3 アトミシティ保証（多重侵入防止）**【review9 重大3】

ストレージドライバのアトミシティは以下の3層で保証する。

### 3.3.1 第1層: 単一ドライバタスク（マイクロカーネル原則）

STOR-DRV-TASK は1タスクのみ。メインループは：

```forth
BEGIN
  IPC4-RECV       \ 要求待ち（カーネルがブロッキング）
  ...処理...
  IPC4-REPLY     \ 応答
AGAIN
```

メインループが IPC4-RECV に戻らない限り、新規要求は処理されない。512B 転送中・IRQ 待ち中も「ドライバはまだ IPC4-RECV に戻っていない」状態であり、カーネルの IPC4 機構が新規 IPC4-CALL を「待機」として保持する。

### 3.3.2 第2層: STOR_WAIT_TID ガード（§3.2）

IRQ完了通知の単一スロット保護。新規要求受信時に非0なら即BUSY。

### 3.3.3 第3層: 同期RPC性質（IPC4設計）

クライアントは IPC4-CALL 後、IPC4-REPLY を受けるまでブロックする。同一クライアントから多重発行は構造上不可能。複数クライアントからの同時発行は第1層・第2層で順次直列化される。

### 3.3.4 第3層の限界と将来拡張

【現状の限界】 第3層は IPC4 同期RPCに依存している。非同期 IPC が将来導入された場合、第3層保護は失われる。

【将来拡張】 §2.2 で確保した予約領域 $E236-$E25F (42B) を使い、複数スロット化（WAITキュー）への拡張余地を残す。Phase 1 では本設計で十分。

## **3.4 バッファ戦略**【review9 中7】

### 3.4.1 Phase 1: 中間バッファなし（直接転送）

クライアントが指定する dst_addr / src_addr に対し、SD_DATA レジスタとの直接転送を行う：

```
READ:  SD_DATA → dst_addr[0..511]
WRITE: src_addr[0..511] → SD_DATA
```

【設計判断の根拠】

- メモリ消費を最小化（中間バッファ 512B 削減）
- ドライバロジックが単純
- Phase 1 のシェル+簡易FSでは十分

### 3.4.2 中間バッファ非採用のトレードオフ

| **項目** | **採用方式（直接転送）** | **採用しない方式（中間バッファ）** |
| --- | --- | --- |
| メモリ消費 | 0 B | 512 B |
| 転送速度 | 1コピー | 2コピー |
| FS連携 | dst_addr=FSバッファで直送可 | FS層で再コピー必要 |
| キャッシュ | なし | 容易に追加可 |
| マルチクライアント | 1要求ずつ直列 | 並列処理の余地 |

### 3.4.3 将来拡張（Phase 2 以降）

将来「ディスクキャッシュ」「FAT12 FS」「複数並列リクエスト」を実装する際は、ドライバ内に中間バッファ (512B × Nブロック) を導入する。その時点で本書 §3.4 を改版する。

# **4. ストレージドライバタスクの設計**

## **4.1 タスク構成**

メインループ：

```forth
: STOR-DRV-TASK  ( -- )
    STOR-INIT
    BEGIN
        IPC4-RECV                   \ ( -- msg3 msg2 msg1 msg0 )
        IPC4-SENDER-DIRECT >R       \ R: client_tid
        REORDER-MSG-3               \ ( -- arg1 arg0 op )
        R>                          \ ( -- arg1 arg0 op tid )
        STOR-DISPATCH
    AGAIN ;
```

## **4.2 STOR-INIT**

```forth
: STOR-INIT  ( -- )
    0 STOR-WAIT-TID !       \ 待機tid=0
    0 STOR-LAST-STAT !      \ ステータス初期化（v1.2: シグナル兼用）
    0 SD-IRQ-CTRL !         \ IRQ_CTRL 初期は無効
    \ YSD8004 IRQ_MASK の bit1 (STOR) を許可（=0）
    IRQ-MASK @ $FFFD AND IRQ-MASK ! ;
```

## **4.3 STOR-DISPATCH**

```forth
: STOR-DISPATCH  ( arg1 arg0 op tid -- )
    >R                              \ R: tid
    DUP STOR-READ-OP = IF
        DROP                        \ op捨て → stack: arg1(dst) arg0(LBA)
        \  ★ v1.3 修正: SWAP 削除
        \  DROP後 stack は底→TOS = dst LBA。
        \  STOR-READ-IMPL ( dst LBA tid -- ) は底→TOS = dst LBA tid を要求。
        \  R> で tid を戻せば dst LBA tid ✓ （SWAP は不要、誤りだった）
        R>                          \ stack: dst LBA tid
        STOR-READ-IMPL              \ 内部でIPC4-REPLY
        EXIT
    THEN
    DUP STOR-WRITE-OP = IF
        DROP
        R>
        STOR-WRITE-IMPL
        EXIT
    THEN
    STOR-STAT-OP = IF
        DROP DROP
        R> STOR-STAT-IMPL
        EXIT
    THEN
    \ 未知op
    DROP DROP
    -1 0 0 0 R> IPC4-REPLY ;
```

**【v1.3 修正ポイント】READ 分岐の SWAP 削除：**

v1.2 では READ 分岐に `SWAP` が記載されていたが、これは誤りである。

`IPC4-CALL ( msg3 msg2 msg1 msg0 tid -- )` のスタックレイアウトにおいて、`STOR-DISPATCH` が受け取る引数は底→TOS = `arg1(=dst) arg0(=LBA) op tid`。`>R` で tid をリターンスタックに退避後、`DROP` で op を捨てると `arg1(dst) arg0(LBA)` が底→TOS で残る。これは `STOR-READ-IMPL ( dst LBA tid -- )` が要求する順序（底→TOS = dst LBA tid）と **SWAP なしで一致する**。

v1.2 の SWAP が存在すると LBA と dst が逆になり、READ 後に dst バッファがゼロのままになる（実装デバッグで確認）。

## **4.4 STOR-READ-IMPL**【v1.2 改訂: G3' 追加】

```forth
\ STOR-READ-IMPL  ( dst LBA tid -- )
\ レビュー指摘 重大1/2/3/4 + review10 IR1/IR2 全反映版
: STOR-READ-IMPL  ( dst LBA tid -- )
    >R                              \ R: tid

    \ ★ G1: WAIT-TID ガード（review9 重大1: BUSY返却）
    STOR-WAIT-TID @ 0= INVERT IF
        \ 既に他タスクが待機中 → BUSY返却
        DROP DROP                   \ dst, LBA 捨て
        -2 0 0 0 R> IPC4-REPLY      \ r0=-2 (BUSY)
        EXIT
    THEN

    \ stack: dst LBA

    \ G2: LBA設定（Phase1: 16bit）
    DUP SD-LBA-LO !                 \ ( -- dst LBA )
    DROP                            \ ( -- dst )
    0 SD-LBA-HI !

    \ G3: READ_SETUP
    0 SD-CMD !                      \ 0 = READ_SETUP

    \ ★ G3': STOR-LAST-STAT クリア（v1.2新・IR2）
    \ IRQ完了通知シグナルとして使うため、EXEC前に必ず0クリア
    \ これによりG8の SELF-IPC-VALID? が論理的に成立する
    0 STOR-LAST-STAT !

    \ G4: WAIT-TID 設定（IRQ より前に必ず）
    R@ STOR-WAIT-TID !

    \ G5: IRQ_CTRL 有効化（§4.7 冪等性ルール準拠）
    1 SD-IRQ-CTRL !

    \ G6: EXEC 発行（emu23 v1.03: 512cycle後にIRQ1発火予約）
    2 SD-CMD !

    \ ★★★ G7-G9: IRQレース対策（review9 重大2）
    \ パターン: DI → STAT再チェック → 既に非0なら起床済→WAITスキップ → EI+WAIT
    \ UART版 yuios_ph3_uart_design_v1_2.docx §5.5 と同等のロジック移植
    DI-OP                           \ 割込禁止（短時間）

    \ ★ G8: 自TCBの完了状態を再チェック（v1.2: STAT非0で判定）
    SELF-IPC-VALID? IF
        \ 既にIRQ完了済（STAT非0） → WAITしない
        EI-OP
    ELSE
        \ まだIRQ来ていない → WAIT-IPCで寝る
        \ TASK-WAIT-IPC内部でEIされる前提
        TASK-WAIT-IPC               \ 寝る → IRQから起こされる
    THEN

    \ ★ R2: STAT 確認（重大4: ドライバ側で確認）
    \ ここでSTOR-LAST-STATは必ず非0（IRQ完了済保証）
    STOR-LAST-STAT @
    DUP $0004 AND 0= IF             \ bit2 (READY) が 0 ならエラー
        DROP                        \ STAT捨て
        DROP                        \ dst捨て
        \ ★ KY11: 全EXITパスでWAIT-TIDクリア
        0 STOR-WAIT-TID !
        -1 0 0 0 R> IPC4-REPLY      \ r0=-1 (ERROR)
        EXIT
    THEN
    DROP                            \ STAT捨て (READY確認済)

    \ ★ R3: SD_DATA → dst へ 512B 転送
    \   アトミシティ: 単一タスク+WAIT-TIDガードで保証（§3.3）
    \ stack: dst
    \ BUF_PTR は EXEC 時に 0 にリセット済
    DUP                             \ stack: dst dst
    512 0 DO
        SD-DATA @                   \ ( -- byte )  下位8bit、BUF_PTR自動++
        OVER I + C!                 \ dst[I] = byte
    LOOP
    DROP                            \ stack: dst
    DROP                            \ stack: empty

    \ ★ R4: WAIT-TID 解放（最後）
    0 STOR-WAIT-TID !

    \ 成功応答 r0=0
    0 0 0 0 R> IPC4-REPLY ;
```

【§4.4 補足: STAT 再読余地】 review9 指摘6 反映。R2 でエラー検出時はそのまま返却するが、必要なら R2 直前で SD_STAT を再読することも可能（STOR-LAST-STAT は IRQ 時点の値、その後変化する余地あり）。Phase 1 では IRQ 時点のSTATで足りるが、診断目的で `SD_STAT @ STOR_LAST_STAT !` を R2 直前に追加する選択肢を残す。

【§4.4 補足: SELF-IPC-VALID? と DI-OP / EI-OP】 §5.5 で実装方法を後述。

【§4.4 補足: 全EXITパスのWAIT-TIDクリア】 v1.2 では明示的に：
- G1（BUSY経路）: WAIT-TID クリア不要（自分はセットしていない）
- R2（ERROR経路）: WAIT-TID クリア必須
- R4（成功経路）: WAIT-TID クリア必須

これらを実装時に必ず確認すること（§12 実装前チェックリストIR3）。

## **4.5 STOR-WRITE-IMPL**【v1.2 改訂: G3' 追加】

```forth
: STOR-WRITE-IMPL  ( src LBA tid -- )
    >R                              \ R: tid

    \ ★ G1: BUSY ガード
    STOR-WAIT-TID @ 0= INVERT IF
        DROP DROP
        -2 0 0 0 R> IPC4-REPLY
        EXIT
    THEN

    \ stack: src LBA

    \ G2: LBA設定
    DUP SD-LBA-LO !
    DROP                            \ stack: src
    0 SD-LBA-HI !

    \ G3: WRITE_SETUP
    1 SD-CMD !                      \ 1 = WRITE_SETUP

    \ ★ G3': STOR-LAST-STAT クリア（v1.2新・IR2）
    0 STOR-LAST-STAT !

    \ ★ W3-pre: src → SD_DATA 512B 転送（EXEC前）
    \ BUF_PTR は WRITE_SETUP では自動リセットされないため明示
    \ ★【KY5】 0 SD-BUF-PTR ! は絶対に忘れないこと
    0 SD-BUF-PTR !
    DUP                             \ stack: src src
    512 0 DO
        DUP I + C@                  \ ( -- byte )
        SD-DATA !                   \ BUF_PTR自動++
    LOOP
    DROP                            \ stack: src

    \ G4: WAIT-TID 設定
    R@ STOR-WAIT-TID !

    \ G5: IRQ_CTRL 有効化
    1 SD-IRQ-CTRL !

    \ G6: EXEC 発行
    2 SD-CMD !

    \ ★ G7-G9: IRQレース対策（READと同じ）
    DI-OP
    SELF-IPC-VALID? IF
        EI-OP
    ELSE
        TASK-WAIT-IPC
    THEN

    \ ★ R2: STAT 確認
    STOR-LAST-STAT @
    DUP $0004 AND 0= IF
        DROP DROP
        \ ★ KY11: ERRORパスでもWAIT-TIDクリア
        0 STOR-WAIT-TID !
        -1 0 0 0 R> IPC4-REPLY
        EXIT
    THEN
    DROP

    \ ★ R4: WAIT-TID 解放
    DROP                            \ src捨て
    0 STOR-WAIT-TID !

    \ 成功応答
    0 0 0 0 R> IPC4-REPLY ;
```

## **4.6 STOR-STAT-IMPL**

```forth
: STOR-STAT-IMPL  ( tid -- )
    \ IRQ待ちなしで即座に SD_STAT を返す
    \ stack: tid
    SD-STAT @                       \ ( tid -- tid stat )
    SWAP                            \ ( -- stat tid )
    \ IPC4-REPLY 引数順序: msg3 msg2 msg1 msg0 tid → REPLY
    \ msg0=stat, msg1=msg2=msg3=0
    \ 整列: stat tid → 0 0 0 stat tid
    >R                              \ R: tid, stack: stat
    0 0 0 SWAP                      \ stack: 0 0 0 stat (TOS=stat=msg0)
    R>                              \ stack: 0 0 0 stat tid
    IPC4-REPLY ;
```

## **4.7 IRQ_CTRL 冪等性ルール**【review9 軽微8】

IRQ_CTRL レジスタの操作には以下のルールを厳守する：

| **タイミング** | **責務** | **動作** |
| --- | --- | --- |
| STOR-INIT 時 | ドライバ | IRQ_CTRL ← 0（初期化、確実に無効） |
| STOR-READ-IMPL G5 / WRITE G5 | ドライバ | IRQ_CTRL ← 1（EXEC直前） |
| IRQ1_HANDLER I3 | カーネル | IRQ_CTRL ← 0（IRQ受理直後） |

【冪等性原則】

- IRQ_CTRL ← 1 は EXEC 1回毎に必ず行う（多重 EXEC でも問題なし）
- IRQ_CTRL ← 0 は IRQ 1回毎に必ず行う（多重 IRQ は来ないが、安全側に倒す）
- ドライバが IRQ_CTRL ← 1 した状態で WAIT に入ったら、IRQ ハンドラが必ず IRQ_CTRL ← 0 に戻す

【違反時の影響】

- IRQ_CTRL ← 0 忘れ: 次回 EXEC 時に多重 IRQ 発生（無害だが診断困難）
- IRQ_CTRL ← 1 忘れ: IRQ 発火しない → ドライバ永久ブロック

# **5. IRQ1 ハンドラ拡張**

## **5.1 既存 IRQ1_HANDLER の構造**

kernel_v10.asm L954-989 の IRQ1_HANDLER は IRQ_STAT bit0（UART RX）のみを処理する。本工程では bit1（STOR）の処理を追加する。

## **5.2 拡張方針**

【採用】 ビット毎独立処理。

```asm
IRQ1_HANDLER:
    レジスタ退避 (A, B, X)
    LDW A, [IRQ_STAT]
    PUSH A                       ; STAT保存
    \ bit0 (UART RX)
    ANDI A, #$0001
    BEQ skip_uart
    JSR _handle_uart_rx          ; 既存処理
skip_uart:
    POP A
    \ bit1 (STOR)
    ANDI A, #$0002
    BEQ skip_stor
    JSR _handle_stor             ; 本書追加
skip_stor:
    レジスタ復帰
    IRET
```

【複数ビット同時発生時の処理順序】 UART RX → STOR の順。両者独立なので順序は本質的でないが、固定する。

## **5.3 _handle_stor: STOR 完了処理**【v1.2 改訂: ST1で非0保証明記】

【v1.0からの主要変更】 ipc_msg 書込・IPC4-REPLY 発行を削除。state 遷移のみに軽量化。

【v1.2 強化】 ST1 で SD_STAT 読出 → STOR_LAST_STAT 保存。emu23 v1.03 仕様により SD_STAT は必ず非0値（READY=0x04 または ERROR=0x02）を返すことが保証される。これによりドライバ側 §5.5.2 SELF-IPC-VALID? の判定が論理的に成立する。

【★ IR4: 順序固守 - レビュアの「実装前チェックリスト3」より】

```
順序: SD_STAT 読出・保存 → IRQ_CTRL=0 → IRQ_STAT WTC → wake
```

崩すと以下の問題：
- IRQ_STAT WTC を STAT 読出より先 → SD_STAT 値が変化する可能性
- IRQ_CTRL=0 を最後 → 多重 IRQ が来てから無効化、無駄な発火
- wake を STAT 保存より先 → ドライバ起床時に STAT 未確定で判定不能

```asm
; ================================================================
; _handle_stor  (IRQ1_HANDLERから呼ばれる)
; YSD8003 EXEC 完了処理（v1.2 軽量版・順序固守）
;
; v1.2 責務: STAT保存（必ず非0値）・後始末・state遷移のみ
;            (ipc_msg書込・IPC4-REPLYはドライバ側に移行)
;
; 【★ 順序固守: ST1→ST2→ST3→ST4 - レビュー指摘IR4】
;   ST1: SD_STAT 読出（必ず非0値が返る）
;   ST2: STOR_LAST_STAT に保存（ドライバの完了通知シグナル）
;   ST3: SD_IRQ_CTRL ← 0（§4.7 冪等性ルール）
;   ST4: IRQ_STAT WTC bit1
;   ST5: wake_stor_waiter（state遷移のみ）
;
; 入力: なし (レジスタはIRQ1_HANDLERが全退避済)
; 破壊: A, B, X
; ================================================================
_handle_stor:
    ; --- ST1: SD_STAT 読出（BUSYラッチクリアの効果も兼ねる）---
    ; emu23 v1.03 仕様: 必ず非0値を返す（READY=0x04 or ERROR=0x02）
    LDW  A, [SD_STAT]

    ; --- ST2: STOR_LAST_STAT に保存（ドライバの完了通知シグナル）---
    STW  A, [STOR_LAST_STAT]

    ; --- ST3: SD_IRQ_CTRL ← 0（§4.7 冪等性ルール）---
    LDW  A, #0
    STW  A, [SD_IRQ_CTRL]

    ; --- ST4: IRQ_STAT WTC（bit1のみクリア）---
    LDW  A, #$0002
    STW  A, [IRQ_STAT]

    ; --- ST5: STOR-WAIT-TID が非0なら state遷移のみ実行 ---
    JSR  wake_stor_waiter

    RET
```

【ST1 STOR_LAST_STAT 非0保証の根拠】 emu23_device_design_v1_2.docx §6 / emu23_v103_design_v1_4.docx により、SD_STAT は EXEC 完了時に必ず以下のいずれかを返す：

- READY (0x04): 正常完了
- ERROR (0x02): エラー（disk_fp NULL 等）
- BUSY (0x01) は EXEC 完了時には立たない（BUSYラッチは1回目STAT読でクリア済）

よって STOR_LAST_STAT には EXEC 完了時に必ず非0値が入る。これがドライバ側の SELF-IPC-VALID? 判定の前提となる。

## **5.4 wake_stor_waiter: state 遷移専用版**【review9 重大4】

【v1.0からの主要変更】 ipc_msg 書込・ipc_valid設定・ipc_sender 設定を削除。state 遷移のみ。

```asm
; ================================================================
; wake_stor_waiter
;
; v1.1 以降: state遷移のみ実施（軽量版）
;            ipc_msg/ipc_valid/ipc_sender はドライバが自身でREPLY時に設定
;
; UART版 wake_uart_waiter とは非対称。
; 「IRQ完了通知」=「state=WAIT_REPLY → READY」のみ。
;
; STOR-WAIT-TIDのクリアは行わない（ドライバ側のR4で行う）
; ※ 理由: ドライバが起床直後にWAIT-TIDを見て「自分が起こされた」を確認できるようにするため
; ※ ドライバのERROR経路でもクリアされる（§12 IR3で実装担当が確認）
;
; 入力: なし (レジスタはIRQ1_HANDLERが全退避済)
; 破壊: A, B, X
; ================================================================
wake_stor_waiter:
    LDW  A, [STOR_WAIT_TID]
    BEQ  _wake_stor_done            ; tid==0 ならスキップ

    ; tid → TCBアドレス計算 (UART版と同一の5命令ブロックを流用)
    STW  A, [L1_WK_TMP]             ; tid退避
    LDW  B, #6
    SHL  A, B                       ; A = tid*64
    STW  A, [L1_WK_C]
    LDW  A, [L1_WK_TMP]
    LDW  B, #4
    SHL  A, B                       ; A = tid*16
    LDW  B, [L1_WK_C]
    ADD  A, B                       ; A = tid*80
    LDW  B, #$4000
    ADD  A, B                       ; A = TCBアドレス
    MOV  X, A

    ; ★ v1.1 以降 削除: ipc_msg[0..3] 書込なし
    ; ★ v1.1 以降 削除: ipc_valid = 1 なし
    ; ★ v1.1 以降 削除: ipc_sender = CUR_TASK なし

    ; ★ state==6(WAIT_REPLY)なら1(READY)へ遷移
    LDW  A, [X]                     ; state取得
    CMPI A, #6                      ; TASK_WAIT_REPLY?
    BNE  _wake_stor_no_state_change
    LDW  A, #1
    STW  A, [X]                     ; TASK_READY

_wake_stor_no_state_change:
    ; ★ v1.1 以降 削除: STOR_WAIT_TID クリアなし（ドライバ側R4で行う）

_wake_stor_done:
    RET
```

【§5.4 重要事項】

- **wake_uart_waiter とは非対称な設計** であることを実装担当に明示する
- UART版コピペでは動作不正となるため、本ハンドラは**新規実装**として扱う
- STOR_WAIT_TID のクリアタイミングが UART (IRQ内) と STOR (ドライバR4) で異なる

## **5.5 SELF-IPC-VALID? と DI-OP / EI-OP の実装**【v1.2 全面改訂・review10 IR1】

§4.4 G7-G9 の IRQ レース対策で使用するワードの実装方針：

### 5.5.1 DI-OP / EI-OP

既存の kernel_forth.fs に CODE ブロックで定義済の前提（Ph.2 で実装済）。確認後、未定義ならば追加：

```forth
CODE DI-OP  ( -- )
    DI                              \ ISA2.3命令 DI
END-CODE

CODE EI-OP  ( -- )
    EI                              \ ISA2.3命令 EI
END-CODE
```

### 5.5.2 SELF-IPC-VALID?: STOR-LAST-STAT ベース判定【v1.2 全面書き換え】

【v1.1 → v1.2 変更点】 v1.1 では「自TCBの state==READY」で判定していたが、これは論理的不完全（WAIT前後で常にREADYのため区別不可）であった（review10 IR1）。v1.2 では STOR-LAST-STAT が「EXEC前=0、IRQ完了後=非0」となる性質を利用して判定する。

```forth
\ ( -- flag )  IRQ完了済（STAT非0）なら true
\ EXEC前にG3'で0クリア、IRQハンドラST1-ST2で必ず非0値（READY=0x04 or ERROR=0x02）が書かれる
: SELF-IPC-VALID?  ( -- flag )
    STOR-LAST-STAT @ 0<> ;
```

【判定の論理性】

| **タイミング** | **STOR-LAST-STAT** | **SELF-IPC-VALID? 判定** |
| --- | --- | --- |
| EXEC前 G3' でクリア | 0 | false |
| EXEC直後（IRQ未到来） | 0 | false → WAIT実行 |
| IRQ到来後（STAT保存済） | 非0（READY/ERROR） | true → WAITスキップ |

【EXEC前0クリアの責務】 §4.4 G3' / §4.5 G3' で必ず実行する。これがないと前回EXECの残留値が残り、誤判定する。

【非0値保証の責務】 §5.3 ST1-ST2 で IRQハンドラが必ず非0値を書き込む。emu23 v1.03 仕様（§5.3 ST1注記参照）でこの保証が成立する。

【IR1 完全解決】 v1.1 の論理的不完全性を解消。WAIT前後の状態区別が STOR-LAST-STAT の値変化で明確に行われる。

# **6. IPC4 メッセージ仕様**

## **6.1 SVC_STORAGE = 0x05**

| **操作名** | **opcode** | **msg0** | **msg1 (arg0)** | **msg2 (arg1)** | **msg3** | **戻り値 (r0)** |
| --- | --- | --- | --- | --- | --- | --- |
| STOR_READ | 0x0501 | op | LBA (16bit) | dst_addr | 0 | 0=成功, -1=ERROR, **-2=BUSY** |
| STOR_WRITE | 0x0502 | op | LBA (16bit) | src_addr | 0 | 0=成功, -1=ERROR, **-2=BUSY** |
| STOR_STAT | 0x0503 | op | 0 | 0 | 0 | SD_STAT 値 |

【LBA幅】 Phase 1 では 16bit (LBA_LO のみ使用、上位は 0 固定)。これは disk.img 最大サイズ 65536 セクタ × 512B = 32MB に相当。Phase 2 で 32bit 化検討。

## **6.2 メッセージ詳細**

### 6.2.1 STOR_READ (0x0501)

クライアント側：
```forth
0 dst-addr LBA STOR-READ-OP STOR-DRV-TID @ IPC4-CALL
\ r0 = 0(成功) or -1(ERROR) or -2(BUSY)
```

ドライバ動作（§4.4 STOR-READ-IMPL 参照）。

### 6.2.2 STOR_WRITE (0x0502)

クライアント動作：
```forth
0 src-addr LBA STOR-WRITE-OP STOR-DRV-TID @ IPC4-CALL
```

ドライバ動作（§4.5 STOR-WRITE-IMPL 参照）。

### 6.2.3 STOR_STAT (0x0503)

クライアント動作：
```forth
0 0 0 STOR-STAT-OP STOR-DRV-TID @ IPC4-CALL
\ r0 = SD_STAT 値（生値）
```

ドライバ動作（§4.6 STOR-STAT-IMPL 参照、IRQ 待ちなし）。

# **7. ストレージテストタスクの設計**

## **7.1 テスト方針**

UART-TEST-TASK と同様、STOR-TEST-TASK を Forth 側に追加し、起動時自動実行する。

【テスト内容】

T1: **LBA=10** にパターン書込（src_buf に "STOR_TST" を配置 → STOR_WRITE）

T2: **LBA=10** から読み出し（dst_buf へ STOR_READ → src と一致確認）

T3: 結果を UART で出力（成功時 'P', 失敗時 'F'）

【期待出力】 既存 yuios_v10 の `ABCXD` の後にスペース+`P` が追加される。

【v1.4 注記: LBA=10 を使う理由】

v1.3 までは LBA=0 を使用していたが、Ph.4 FileMgr 実装時に **LBA=0 がスーパーブロック専用領域**となったため、STOR-TEST が "STOR_TST" を LBA=0 に書き込むと FILEMGR-TASK の FS-MOUNT 内 MAGIC-CHECK が必ず失敗（magic 不一致）する問題が発生した（HANDOVER_CHAT30 §1.2 参照）。

対策として、テスト用 LBA を **データ領域内** に移すこととし、以下の条件を満たす LBA=10 を選択：

- LBA=4 以降のデータ領域内（mkfs_yuifs の `data_start=4` 以降）
- 最小ディスクサイズ 8KB（=16セクタ）でも範囲内（LBA 0〜15 のうち LBA=10 はデータ領域内）
- ディレクトリ領域（LBA=1〜3）と衝突しない
- 将来の FILEMGR-TEST が使う LBA とも衝突しない（FILEMGR-TEST 側で LBA=10 を回避する約束）

## **7.2 STOR-TEST-TASK 構造**

```forth
\ テスト用バッファ（kernel.asm v0.11 の固定領域 $E300- に配置）
$E300 CONSTANT TEST-SRC-BUF     \ 512B 書き込み元
$E500 CONSTANT TEST-DST-BUF     \ 512B 読み出し先

: STOR-TEST-TASK  ( -- )
    \ S0: スペース出力（区切り）
    0 0 $20 UART-PUTC-OP UART-DRV-TID @ IPC4-CALL
    DROP DROP DROP DROP

    \ S1: src_buf にパターン書き込み（最初の8B: "STOR_TST"）
    $53 TEST-SRC-BUF       C!      \ 'S'
    $54 TEST-SRC-BUF 1 +   C!      \ 'T'
    $4F TEST-SRC-BUF 2 +   C!      \ 'O'
    $52 TEST-SRC-BUF 3 +   C!      \ 'R'
    $5F TEST-SRC-BUF 4 +   C!      \ '_'
    $54 TEST-SRC-BUF 5 +   C!      \ 'T'
    $53 TEST-SRC-BUF 6 +   C!      \ 'S'
    $54 TEST-SRC-BUF 7 +   C!      \ 'T'

    \ S2: STOR_WRITE LBA=10 (v1.4: LBA=0 から変更、案α LBA衝突対処)
    0 TEST-SRC-BUF 10 STOR-WRITE-OP STOR-DRV-TID @ IPC4-CALL
    DROP DROP DROP                  \ r1 r2 r3 捨て、stack: r0
    0= INVERT IF
        0 0 $46 UART-PUTC-OP UART-DRV-TID @ IPC4-CALL  \ 'F'
        DROP DROP DROP DROP
        EXIT
    THEN

    \ S3: STOR_READ LBA=10 → dst_buf (v1.4: LBA=0 から変更)
    0 TEST-DST-BUF 10 STOR-READ-OP STOR-DRV-TID @ IPC4-CALL
    DROP DROP DROP
    0= INVERT IF
        0 0 $46 UART-PUTC-OP UART-DRV-TID @ IPC4-CALL
        DROP DROP DROP DROP
        EXIT
    THEN

    \ S4: src と dst の最初の8B を比較
    8 0 DO
        TEST-SRC-BUF I + C@
        TEST-DST-BUF I + C@
        <> IF
            0 0 $46 UART-PUTC-OP UART-DRV-TID @ IPC4-CALL  \ 'F'
            DROP DROP DROP DROP
            UNLOOP EXIT
        THEN
    LOOP

    \ S5: 全致 → 'P' 出力
    0 0 $50 UART-PUTC-OP UART-DRV-TID @ IPC4-CALL  \ 'P'
    DROP DROP DROP DROP ;
```

## **7.3 起動シーケンス**

```forth
: OS-START  ( -- )
    MEMMGR-START                    \ Ph.2
    UART-START                      \ Ph.3-A5
    STOR-START                      \ Ph.3-B (本工程で追加)
    UART-TEST-START                 \ 既存テスト
    STOR-TEST-START ;               \ 本工程で追加
```

# **8. 期待出力と動作確認**

## **8.1 期待出力**

```
ABCXD P
```

- `ABCXD`: Ph.3-A5 UART テスト出力（既存）
- ` `: スペース（区切り、STOR-TEST-TASK の S0 で出力）
- `P`: ストレージ書込→読出→照合 PASS

## **8.2 動作確認コマンド**

```bash
# ディスクイメージ準備
dd if=/dev/zero of=disk.img bs=512 count=2048

# 既存 RX テスト用入力ファイル
printf 'X' > uart_test_input.bin

# 実行（emu23 v1.03 必須）
./emu23 yuios_v11.bin yuios_v11.sym -i uart_test_input.bin --disk disk.img -q

# 期待出力: ABCXD P
```

> **★【v1.6 注記】上記コマンドは当時に実際に実行した記録である。
> ただしこの形式では `.sym` が読めていなかった。★**
>
> emu23 は `argv[2]` を `.dbg`、`argv[3]` を `.sym` として位置解釈する。
> 上記は `argv[2]=yuios_v11.sym`（→ `load_dbg()` に渡る）、
> `argv[3]="-i"`（→ `load_sym()` が `fopen` 失敗 → **黙殺**）となり、
> **シンボルは一切読まれていなかった**（EMU-A / 当時は警告も出なかった）。
> 期待出力 `ABCXD P` の検証はシンボル非依存のため**結果は有効**である。
>
> **emu23 v1.13 以降は次の形式を使うこと。**
>
> ```
> ./emu23 yuios_v11.bin --sym yuios_v11.sym -i uart_test_input.bin --disk disk.img -q
> ```
>
> v1.13 では `-i` とその引数が「消費済み」となるため、旧形式でも
> `.sym` は**自動導出により読まれる**（`.dbg` 側の誤読は残る）。
> 詳細は `emu23_argsym_design_v1_0.md` §5.8.1 ／ `emu23_debug_manual_v1_4.md` §2.1 参照。

## **8.3 ディスク内容の確認**

```bash
# LBA=10 (オフセット 10*512=5120, 0-7 byte) に "STOR_TST" が書き込まれていることを確認
# v1.4: LBA=0 はスーパーブロック専用のため LBA=10 に変更
hexdump -C -s 5120 -n 16 disk.img
# 期待: 00001400  53 54 4f 52 5f 54 53 54 ...
```

## **8.4 BUSY ガードの単体動作確認**

LBA=10 と LBA=11 を同時要求するテストタスクを2つ起動して、BUSY (-2) が返ることを確認する（Phase 1 では実装オプション）。

# **9. KY (危険予知)**

【KY1】 IRQ_CTRL の有効/無効タイミング誤りで、IRQ1 が常時発火 or 永久に来ない

【防止策】
- ドライバ側: EXEC 直前のみ IRQ_CTRL ← 1、IRQ ハンドラ側で IRQ_CTRL ← 0 に必ず戻す
- §4.2 STOR-INIT で初期値 0 を確実に設定
- §4.7 冪等性ルール厳守

【KY2】 STOR_WAIT_TID 設定タイミングと EXEC 発行のレース

【防止策】
- 順序固守: STAT=0クリア → WAIT-TID 設定 → IRQ_CTRL ← 1 → EXEC ← 2 → DI → 再チェック → WAIT-IPC
- §4.4 のコメントに「順序最重要」と明記

【KY3】 IRQ1_HANDLER 内で UART RX と STOR の両方が同時発生したケースで、片方が取りこぼされる

【防止策】
- §5.2 ビット毎独立処理採用
- IRQ_STAT を最初に PUSH してから両方をテスト
- 試験 T8（同時発生試験）を実施

【KY4】 wake_stor_waiter が wake_uart_waiter と**非対称**であることの実装担当への伝達不足

【防止策】
- §5.4 で「UART版コピペでは動作不正」と明記
- wake_stor_waiter は新規実装扱いで PR / コードレビュー必須
- ipc_msg/ipc_valid/ipc_sender 書込なし、STOR_WAIT_TID クリアなし、の3点を実装後に diff で確認

【KY5】 BUF_PTR が EXEC 後の WRITE で 0 にリセットされず、データが間違った位置に書かれる

【防止策】
- §4.5 STOR-WRITE-IMPL の W3-pre で `0 SD-BUF-PTR !` を明示
- レビュー時に WRITE_SETUP 後の BUF_PTR 状態を再確認
- §12 実装前チェックリスト IR4 で必須化

【KY6】 STOR-LAST-STAT の更新タイミングと、ドライバ側の参照タイミング不整合

【防止策】
- IRQ ハンドラが state 遷移を行う前に必ず STOR_LAST_STAT を更新する（§5.3 ST1→ST2→ST5 の順序固守）
- ドライバ側は TASK-WAIT-IPC 復帰直後に STOR_LAST_STAT を読む（§4.4 R2）

【KY7】 emu23 v1.03 の遅延 IRQ 機構が動かないケース（v1.02 のままで実行）

【防止策】
- 実行前に必ず `./emu23` の起動バナーを確認し、v1.03 表記を確認
- ビルド手順書に「emu23 v1.03 必須」を明記

【KY8】 BC-STR のアドレス変更（$E230 → $E260）忘れによる UART テスト失敗

【防止策】
- kernel_v11.asm では $E260 に "BC\0" を配置
- kernel_forth_v07.fs では `$E260 CONSTANT BC-STR` に変更
- yuios_v10 と yuios_v11 の `ABCXD` 出力を両方確認
- 【手順注記】 sed で grep して残存箇所を確認: `grep -rn "E230" kernel_v11.asm kernel_forth_v07.fs`

【KY9】 IRQレース対策の再チェックループ移植ミス

【防止策】
- §4.4 G7-G9 のパターン（DI → SELF-IPC-VALID? → EI/WAIT）を必ず移植
- §5.5 で SELF-IPC-VALID? の実装を確認
- UART版 yuios_ph3_uart_design_v1_2.docx §5.5 の対応箇所と diff で照合

【KY10】 BUSY 返却忘れによる多重要求受付

【防止策】
- §4.4 / §4.5 の G1 で `STOR-WAIT-TID @ 0= INVERT IF -2 ... THEN` を必ず最初に実行
- 単体テスト §8.4 で BUSY 返却を確認
- 戻り値定義（0/-1/-2）をクライアント側ドキュメントにも明記

【KY11】【v1.2 強化・review10 IR3】 WAIT-TID 全EXITパスでクリア漏れ

【防止策・v1.2強化】

ドライバ側 (§4.4/§4.5) には以下の3つの EXIT パスがあり、各々で WAIT-TID クリアの要否が異なる：

| **EXITパス** | **STOR-WAIT-TID クリア要否** | **理由** |
| --- | --- | --- |
| G1 (BUSY経路) | 不要 | 自分はWAIT-TIDをセットしていない |
| R2 (ERROR経路) | **必須** | G4でセット済、クリアしないと次回 BUSY |
| R4 (成功経路) | **必須** | G4でセット済、クリアしないと次回 BUSY |

将来コード追加時にも上記ルールを守ること。EXIT 追加時の必須チェック項目とする。

【KY12】 STAT 取得タイミングの単一性に伴う診断難化

【防止策】
- §4.4 R2 直前で SD_STAT を再読する選択肢を残す（実装時にコメントで明示）
- Phase 2 で必要なら STAT 履歴ログを追加

【KY13】【v1.2 新設・review10 IR1】 SELF-IPC-VALID? の前回EXEC残留値による誤判定

【防止策】
- §4.4 G3' / §4.5 G3' で `0 STOR-LAST-STAT !` を必ず実行（EXEC前クリア）
- G3' をコメントアウトすると G8 で誤って WAIT スキップ → 永久ブロック
- 単体テスト T5 (連続2回 STOR_READ で正常応答するか) で検証

【KY14】【v1.2 新設・review10 IR4】 IRQハンドラ内処理順序の崩壊

【防止策】
- §5.3 _handle_stor の処理順序を厳守: STAT読出 → STAT保存 → IRQ_CTRL=0 → IRQ_STAT WTC → wake
- 順序を変えるとSTAT再読、多重IRQ、STAT未確定で起床等の各種バグ
- §12 IR4 で実装前チェックリストとして必須化

# **10. レビュー確認事項（v1.2）**

| **No.** | **項目** | **§** | **内容** |
| --- | --- | --- | --- |
| RR1 | メモリ配置 ($E230-) / STOR-LAST-OP 削除 | §2 | BC-STR を $E260 に移動・予約領域 42B 確保 |
| RR2 | 三層アトミシティ保証の妥当性 | §3.3 | マイクロカーネル原則+WAIT-TID+同期RPC で十分か |
| RR3 | バッファ戦略（Phase 1 直接転送） | §3.4 | Phase 1 で十分か。FS連携時の改版条件 |
| RR4 | BUSY (r0=-2) 返却仕様 | §4.4 G1 / §6.1 | 戻り値定義の妥当性。クライアント再試行戦略 |
| RR5 | IRQレース対策（DI/再チェック/WAIT） | §4.4 G7-G9 / §5.5 | UART版パターンの正確な移植が成立しているか |
| RR6 | IRQハンドラ軽量化（state遷移のみ） | §5.3 / §5.4 | UART版 wake_uart_waiter との非対称設計の妥当性 |
| RR7 | SELF-IPC-VALID? 実装【v1.2改訂】 | §5.5.2 | STOR-LAST-STAT ベース判定の妥当性。EXEC前0クリア手順の必要性 |
| RR8 | IRQ_CTRL 冪等性ルール | §4.7 | 3点（init/EXEC/IRQ）でのルール妥当性 |
| RR9 | STOR-WAIT-TID クリア責務分離 | §5.4 / §4.4 R4 | クリアをドライバR4側に移したことの整合性 |
| RR10 | テストパターン "STOR_TST" 8B | §7.2 | テスト十分性。512B フル照合の必要性 |
| RR11 | 起動シーケンス順序 | §7.3 | MEMMGR → UART → STOR の順で良いか |
| RR12 | 期待出力 `ABCXD P` | §8.1 | 形式の妥当性。BUSY試験(§8.4)の実装スコープ |
| RR13 | STAT 再読の余地 | §4.4 末尾 / KY12 | Phase 1 でコメント明示で足りるか |
| RR14 |【v1.2新】 G3' STAT クリア | §4.4 G3' / §4.5 G3' | EXEC前0クリア手順の妥当性。実装漏れリスク |
| RR15 |【v1.2新】 IRQハンドラ順序固守 | §5.3 ST1-ST5 | 処理順序の妥当性。崩壊時の影響範囲 |

# **11. 関連文書**

| **文書** | **版数** | **備考** |
| --- | --- | --- |
| emu23_v103_design_v1_4.docx | v1.4 | emu23 v1.03 改修設計書（本工程で同時作成） |
| emu23_device_design_v1_2.docx | v1.2 | YSD8001/8002/8003/8004 デバイス仕様 |
| yuios_ph3_uart_design_v1_2.docx | v1.2 | Ph.3-A5 UART 設計書（本書のテンプレート） |
| yuios_design_v2_0.docx | v2.0 | YUI OS 全体設計（§6.3 ストレージドライバ） |
| ISA2_3_v231.docx | v2.3.1 | YSD8800 ISA2.3 仕様書 |
| YSD8800_ABI_spec.docx | - | ABI 仕様 |
| storage.txt | - | ストレージ設計議論ログ（方式 A 採用根拠） |
| HANDOVER_CHAT20.md | v1.0 | Chat #19→#20 引継ぎ |
| review9.txt | - | v1.0 レビュー結果（v1.1で全反映） |
| review10.txt | - | v1.1 レビュー結果（GO判定+本書 v1.2 で全反映） |

# **12. 実装前チェックリスト**【v1.2 新設・review10 全指摘正式記載】

## **12.1 概要**

review10.txt は v1.1 を「実装に進んで問題ないレベル（実質GO）」と判定したが、「実装前チェックリスト（これだけやれ）」として4項目を提示した。本 §12 ではこれを設計書本体に正式条項として記載し、実装担当が必ず確認する形にする。

## **12.2 IR1: SELF-IPC-VALID? の限界明記**

【v1.2 解決済】 v1.1 では state==READY 判定で論理的不完全だった。v1.2 では STOR-LAST-STAT ベース判定（§5.5.2）で完全解決。

【実装担当チェック項目】

- [ ] §5.5.2 の SELF-IPC-VALID? 実装が STOR-LAST-STAT @ 0<> となっていること
- [ ] §4.4 G3' / §4.5 G3' で `0 STOR-LAST-STAT !` がEXEC前に実行されること
- [ ] §5.3 _handle_stor の ST1-ST2 で SD_STAT 読出 → STOR_LAST_STAT 保存が必ず実行されること

## **12.3 IR2: WAIT-TID 全EXITパスクリア確認**

【実装担当チェック項目】

§4.4 STOR-READ-IMPL / §4.5 STOR-WRITE-IMPL の各 EXIT パスで以下を確認：

- [ ] G1 BUSY経路: WAIT-TID クリア不要（自分はセットしていない）
- [ ] R2 ERROR経路: `0 STOR-WAIT-TID !` が必ず実行されること
- [ ] R4 成功経路: `0 STOR-WAIT-TID !` が必ず実行されること
- [ ] 将来追加するEXITパスでも上記ルールを守ること

【検証方法】 grep で `EXIT` を全検索し、その直前で WAIT-TID クリアが実行されているか確認：

```bash
grep -B5 'EXIT' kernel_forth_v07.fs | grep -A5 'STOR-READ-IMPL\|STOR-WRITE-IMPL'
```

## **12.4 IR3: IRQハンドラ内処理順序固守**

【実装担当チェック項目】

§5.3 _handle_stor の処理順序を以下の順で実装：

```
ST1: SD_STAT 読出（A レジスタへ）
ST2: STOR_LAST_STAT に保存
ST3: SD_IRQ_CTRL ← 0
ST4: IRQ_STAT WTC bit1 ($0002 を IRQ_STAT へ書込)
ST5: wake_stor_waiter 呼出
```

- [ ] ST1 → ST2 順序維持（STAT読出と保存を分離しない）
- [ ] ST2 → ST3 順序維持（STAT 保存を IRQ_CTRL クリアより先に）
- [ ] ST3 → ST4 順序維持（IRQ_CTRL=0 を WTC より先に）
- [ ] ST4 → ST5 順序維持（WTC を wake より先に）

【順序崩壊時の影響】

| **誤った順序** | **影響** |
| --- | --- |
| ST4 を ST1 より先 | SD_STAT 値が変化する可能性（実機で問題顕在化） |
| ST3 を ST5 の後 | 多重 IRQ が来てから無効化、無駄な発火 |
| ST5 を ST2 より先 | ドライバ起床時に STAT 未確定で判定不能 |

## **12.5 IR4: WRITE BUF_PTR=0 必須**

【実装担当チェック項目】

§4.5 STOR-WRITE-IMPL の W3-pre で `0 SD-BUF-PTR !` が EXEC 前に必ず実行されること：

- [ ] WRITE_SETUP コマンド発行後（G3）、SD_DATA 書込ループ前（W3-pre 内）に `0 SD-BUF-PTR !` がある
- [ ] READ_SETUP の場合は EXEC 時に自動リセットされるので不要

【無視時の影響】 WRITE_SETUP では BUF_PTR が前回値を保持する仕様（emu23_device_design_v1_2.docx §6）。明示的に 0 にしないと、512B書込が間違った位置から始まり、データ破壊が起こる。

## **12.6 実装フロー**

実装担当は以下の順序で本工程を進める：

1. emu23 v1.03 改修着手前: emu23_v103_design_v1_4.docx を確認
2. emu23 v1.03 実装・回帰テスト確認
3. kernel_v11.asm に IRQ1_HANDLER 拡張・wake_stor_waiter 追加（§5.3 / §5.4）
4. **§12.4 IR3 順序確認** ← 必須
5. kernel_forth_v07.fs に SELF-IPC-VALID? / STOR-INIT / STOR-DRV-TASK / STOR-DISPATCH / STOR-READ-IMPL / STOR-WRITE-IMPL / STOR-STAT-IMPL 追加
6. **§12.2 IR1 確認** ← 必須
7. **§12.3 IR2 確認** ← 必須
8. **§12.5 IR4 確認** ← 必須
9. STOR-TEST-TASK 追加
10. ビルド・動作確認（§8）

— 以上 —
