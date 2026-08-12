YUI OS v2.3 マイクロカーネル設計書	Version 2.3 / 2026-05-20

**YUI OS**

**マイクロカーネル設計書**

Version 2.3

2026-05-20

YSD8800 YUI OS Project

## **改版履歴**

| **版** | **日付** | **変更内容** | **担当** |
| --- | --- | --- | --- |
| v1.0 | 2026-03 | 初版。YSD8800 ISA2.2 / kernel v0.6 / kernel_forth.fs v0.2 | Claude |
| v2.0 | 2026-04-23 | ISA2.3対応・マイクロカーネル全機能設計（メモリ管理・FS・IPC拡張・ドライバタスク化・シェル） | Claude |
| v2.1 | 2026-05-18 | Ph.3.5（カーネル基盤改訂）完了に伴う全面更新：①メモリマップ更新（TCBプール$1000→$4000、MsgPool追加、スタック分離、KERN_SP専用化、stack guard新設）、②TCBレイアウト更新（64B→80B、16タスク化、IPC4 Poolフィールド追加）、③IPC4 Pool方式の採用（単一スロット競合バグ解消）、④ドライバタスク実装状況反映（UART/STOR実装完了・Ph.3.5 Step 7C完了） | Claude |
| v2.2 | 2026-05-18 | TID割り当て正式確定：§4.4にTID列を追加し全サーバタスクのTIDを一元管理。§4.4.1（タスク起動順序）を新設。Ph.4設計（FileMgr）着手に伴い決定。 | Claude |
| v2.3 | 2026-05-20 | Ph.4 FileMgr 設計書（yuios_ph4_filemgr_design_v1_2.md）FIX に伴う改版要請 C1〜C4 を反映：①§7.2 FILE_WRITE の引数を fid → name_addr に変更（C1）、②§7.1 ディスクレイアウトを Ph.4 設計書参照に更新（C2）、③§7.2 エラー戻り値を FS 系 $FE00 台エラーコード体系に更新（C3）、④§4.5 IPC4-CALL/RECV のスタック効果表記を実装実績（STOR 設計書準拠）に訂正（C4）、⑤§2.1 メモリマップを memmap v1.3 と整合（FileMgr 領域追加・Forth ゾーン先頭 $5100 変更） | Claude |

# **1. 概要**

## **1.1 YUI OS とは**

YUI OS は YSD8800 CPU アーキテクチャ向けに設計されたマイクロカーネルです。Forth 言語（Force クロスコンパイラ）でカーネル高レベル層を実装し、C 言語（scc23 コンパイラ）でユーザランドを実装します。最終的には FPGA (SystemVerilog) 上の YSD8800 CPU で動作することを目標としています。

v2.0 では ISA2.3 ベースへの移行と、本格的なマイクロカーネル機能（メモリマネージャ・ファイルシステム・プロセスマネージャ・IPC・ドライバタスク化・シェル）を追加します。

## **1.2 設計方針**

| **方針** | **内容** |
| --- | --- |
| 移植性 | ハードウェア依存部を CODE...END-CODE に隔離。高レベルロジックは純粋 Forth で記述。ISA2.3 ベース、他 CPU への移植は CODE ブリッジ交換のみ。 |
| 最小性 | マイクロカーネル構成。スケジューラ・IPC のみをカーネル空間で実装。メモリ管理・FS・ドライバは別タスク（サーバ）として実装。 |
| メッセージパッシング | 全コンポーネント間通信は固定長メッセージ（4ワード=8バイト）の同期 RPC で統一。ドライバタスクのみ内部リングバッファを持つ。 |
| 段階的発展 | ファイルシステムは独自フラットFS→FAT12 に段階的移行。メモリ管理は固定ページ方式で開始し将来 MMU 連携へ。 |
| ISA2.3 基準 | SYSCALL はAレジスタ渡し（IRQ4発火）方式。MMIO でデバイス制御（YSD8001/8002/8003/8004）。 |

## **1.3 アーキテクチャ構成**

YUI OS v2.0 のソフトウェアスタック：

  ┌─────────────────────────────────────────┐

  │  ユーザランド (C: scc23)                 │  プロセス空間

  │  シェル / アプリケーション               │

  ├─────────────────────────────────────────┤

  │  サーバタスク群（ユーザ空間）             │

  │  MemMgr / FileMgr / ProcMgr / Driver    │

  ├─────────────────────────────────────────┤

  │  kernel_forth.fs  v0.3                  │  $1200+

  │  (高レベルAPI・IPC・スケジューラIF)      │

  ├─────────────────────────────────────────┤

  │  kernel_core.asm  v0.6                  │  $0030-$08E9

  │  (IRQ0ハンドラ・コンテキストスイッチ)   │

  ├─────────────────────────────────────────┤

  │  YSD8800 CPU (ISA2.3)                   │

  │  YSD8001/8002/8003/8004 デバイス        │

  └─────────────────────────────────────────┘

# **2. メモリマップ**

## **2.1 アドレス空間**

YSD8800 は 16bit アドレス空間（64KB）を持ちます。YUI OS v2.0 での割り当ては以下のとおりです。

| **アドレス範囲** | **サイズ** | **用途** | **備考** |
| --- | --- | --- | --- |
| $0000-$0017 | 24 B | リセット・IRQベクタ | ISA2.3固定 |
| $0018-$002F | 24 B | スタートアップコード（_cstart） | ハーネス配置 |
| $0030-$08E9 | 約2.2KB | kernel_core.asm（IRQ0ハンドラ・カーネルAPI） | v0.6 |
| $0900-$0FFF | 約1.7KB | カーネル予約（将来拡張） | - |
| $4000-$44FF | 1280 B | TCBプール（16タスク × 80B） | **【v2.1】$1000→$4000、8→16タスク、64→80B** |
| $1200-$BFFF | 約43KB | kernel_forth.fs + サーバタスク + ユーザコード | コード配置領域 |
| $4500-$46FF | 512 B | MsgPool（IPC4 32エントリ × 16B） | **【v2.1新設】IPC4 Pool方式** |
| $4700-$477F | 128 B | KERN_SP専用スタック | **【v2.1新設】カーネル用スタック** |
| $4780-$47BF | 64 B | カーネルワーク変数 | **【v2.1新設】L1_WK/IPC4_WK/MISC_WK等** |
| **$4800-$505F** | **2144 B** | **FileMgr 専用領域**（FileMgr変数・FS-SECBUF・FS-DIRBUF・FS-OPENTAB等） | **【v2.3新設・memmap v1.3 M2反映】yuios_ph4_filemgr_design_v1_2.md §5.2** |
| **$5060-$50FF** | **160 B** | **カーネル成長予約残余**（将来拡張用） | **【v2.3新設・memmap v1.3 M1反映】** |
| $C000-$DFFF | 8 KB | 固定ページプール（MemMgr管理） | v2.0新規 |
| $E000-$E1FF | 512 B | カーネルワーク変数・グローバル変数 | 既存 |
| **$5100-$EFFF** | — | **Force VARIABLE / Forth辞書 / scc23グローバル変数（Forthゾーン）** | **【v2.3更新: 先頭 $5000→$5100。memmap v1.3反映】** |
| $FC80-$FC8F | 16 B | YSD8001 UART I/O ポート | MMIO |
| $FC90-$FC9F | 16 B | YSD8002 タイマー MMIO | MMIO |
| $FCA0-$FCB1 | 18 B | YSD8003 ストレージ MMIO | MMIO |
| $FCB2-$FCB5 | 4 B | YSD8004 割り込みコントローラ MMIO | MMIO |
| $FF00-$FF10 | 17 B | MMU ページテーブルレジスタ（特権） | 将来 |
| $F000-$F7FF | 2 KB | コールスタック領域（16タスク×128B） | **【v2.1更新】スタック完全分離** |
| $F800-$FBFF | 2 KB | データスタック領域（16タスク×128B） | **【v2.1更新】DSP専用領域** |
| $FC00-$FC3F | 64 B | stack guard領域（$A55A×32W） | **【v2.1新設】スタックオーバーラン検出用** |
| $FC40-$FCFF | 192 B | OS共有変数領域（UART/STOR変数等） | **【v2.1更新】** |

## **2.2 固定ページプール（MemMgr管理）**

$C000-$DFFF（8KB）を固定ページ方式で管理します。1ページ = 256バイト、合計32ページ。

| **項目** | **値** | **説明** |
| --- | --- | --- |
| ページサイズ | 256 B | 固定。MMU ページサイズと将来整合させるため 256B 単位。 |
| 総ページ数 | 32 ページ | $C000-$DFFF = 8KB / 256B = 32 |
| 管理方式 | ビットマップ | 32bit 1変数でページ使用状況を管理（bit=0:空き, 1:使用中） |
| 割り当て単位 | 1ページ以上 | 連続ページも割り当て可（alloc_pages(n)） |
| ユーザ用 | 28ページ | Cアプリのロード・実行用（上位4ページをOS予約に充当） |

# **3. タスク管理**

## **3.1 TCB（タスク制御ブロック）v2.1更新**

**【v2.1確定】** 80B 構成、TCBプールは **$4000** に配置（16タスク × 80B = 1280B、$4000-$44FF）。

| **オフセット** | **サイズ** | **フィールド名** | **説明** |
| --- | --- | --- | --- |
| +0 | 2 B | state | タスク状態（下表参照） |
| +2 | 2 B | saved_pc | 保存済みプログラムカウンタ |
| +4 | 2 B | saved_sp | 保存済みスタックポインタ（コールスタック） |
| +6 | 2 B | saved_x | 保存済みデータスタックポインタ（DSP） |
| +8 | 2 B | msg_data | IPCメッセージデータ（後方互換） |
| +10 | 2 B | (予約) | — |
| +12 | 2 B | saved_flags | 保存済み FLAGS（IE=1 で再開） |
| +14 | 2 B | ipc_queue_tail | **【v2.1更新】IPC4 Poolキュー末尾index（初期値IDX_NIL=$FFFF）** |
| +16 | 2 B | ipc_msg[0] | REPLYバッファ ワード0（r0=result） **【v2.1: IPC4 Pool reply経路専用】** |
| +18 | 2 B | ipc_msg[1] | IPC拡張メッセージ ワード1（arg0） |
| +20 | 2 B | ipc_msg[2] | IPC拡張メッセージ ワード2（arg1） |
| +22 | 2 B | ipc_msg[3] | IPC拡張メッセージ ワード3（arg2/result） |
| +24 | 2 B | ipc_valid | 拡張IPC有効フラグ（0=なし, 1=あり） |
| +26 | 2 B | last_sender_tid | 最後に受信した送信元tid |
| +28 | 2 B | priority       | タスク優先度（将来用） |
| +30 | 2 B | ipc_queue_head | **【v2.1新設】IPC4 Poolキュー先頭index（初期値IDX_NIL=$FFFF）** |
| +32〜+79 | 48 B | (予約) | 将来拡張用 |

**【v2.1確定】** TCBアドレス計算: `tid * 80 + $4000`。16タスク × 80B = 1280B（$4000-$44FF）。MsgPool（IPC4 Pool）は $4500-$46FF（32エントリ × 16B = 512B）に配置。

## **3.2 タスク状態**

| **状態名** | **値** | **説明** |
| --- | --- | --- |
| TASK-DEAD | 0 | 未使用・終了済み |
| TASK-READY | 1 | 実行可能・スケジューラ待ち |
| TASK-RUNNING | 2 | 現在実行中 |
| TASK-SLEEPING | 3 | TASK-SLEEP で自発的待機中 |
| TASK-WAIT-MSG | 4 | MSG-RECV でメッセージ待ち（旧IPC互換） |
| TASK-WAIT-IPC | 5 | IPC4-RECV で拡張メッセージ待ち（v2.0新規） |
| TASK-WAIT-REPLY | 6 | IPC4-CALL で応答待ち（v2.0新規） |

## **3.3 スタック配置**

| **tid** | **コールスタック頂上** | **データスタック頂上** | **コールスタック先頭** | **スタック幅** |
| --- | --- | --- | --- | --- |
| 0 | $23FE | $21FE | $2000-$23FE | 512B×2 |
| 1 | $27FE | $25FE | $2400-$27FE | 512B×2 |
| 2 | $2BFE | $29FE | $2800-$2BFE | 512B×2 |
| n | $23FE + n×$400 | $21FE + n×$400 | コールスタック幅 512B | - |

## **3.4 スケジューリング**

v2.0 でもプリエンプティブ（IRQ0タイマー駆動）＋協調スケジューリング（TASK-SLEEP/EXIT）の組み合わせは変更なし。

# **4. IPC（プロセス間通信）**

## **4.1 設計方針**

v2.0 の IPC は「固定長メッセージ（4ワード=8バイト）同期 RPC」を基本とします。送信側は応答が返るまでブロックします（TASK-WAIT-REPLY 状態）。ドライバタスクのみ内部リングバッファを持ち非同期対応とします。

## **4.2 IPC4 Pool方式【v2.1新設】**

共通メッセージプール（MsgPool）による競合解消：

| 項目 | 値 |
|------|----|  
| MsgPool配置 | $4500-$46FF（32エントリ × 16B = 512B） |
| POOL_SIZE | 32 |
| IDX_NIL | $FFFF（キュー末尾/空の番兵） |
| ERR_IPC_NOSLOT | $FFFE（プール枯渇エラー） |

各エントリ（MsgEntry 16B）: sender(2B) + msg[0..3](8B) + next(2B) + pad(4B)

キューはTCBのipc_queue_head/tailで管理（FIFO O(1)）。詳細は yuios_ipc4_pool_design_v1_3.md 参照。

## **4.3 メッセージ構造（4ワード固定）**

| **ワード** | **名称** | **用途** |
| --- | --- | --- |
| word0 | opcode | 操作コード（サービス種別 + 要求番号）上位8bit=サービスID、下位8bit=操作番号 |
| word1 | arg0 | 引数0（アドレス / サイズ / ファイルID 等） |
| word2 | arg1 | 引数1 |
| word3 | arg2 / result | 引数2（送信時）または戻り値（受信時） |

## **4.4 サービスID・TID定義【v2.2更新】**

TIDはOS-START内でのTASK-CREATE呼び出し順序により決定する。tid=0はForthルートタスク（OS-START自身）に固定される。tid=1以降はMEMMGR-START→UART-START→STOR-STARTの順で確定済み（Ph.3.5実装完了）。FileMgr以降はPh.4〜6で順次確定する。

| **TID** | **サービスID** | **名称** | **担当タスク** | **起動ワード** | **実装状況** |
| --- | --- | --- | --- | --- | --- |
| 0 | — | — | Forthルートタスク（OS-START） | —（起動時固定） | 実装済 |
| 1 | 0x01 | SVC_MEM | メモリマネージャ（MemMgr） | MEMMGR-START | 実装済（Ph.2） |
| 2 | 0x04 | SVC_UART | UARTドライバタスク | UART-START | 実装済（Ph.3-A） |
| 3 | 0x05 | SVC_STORAGE | ストレージドライバタスク | STOR-START | 実装済（Ph.3-B） |
| 4 | 0x02 | SVC_FILE | ファイルマネージャ（FileMgr） | FILEMGR-START | **Ph.4で実装予定** |
| 5 | 0x03 | SVC_PROC | プロセスマネージャ（ProcMgr） | PROCMGR-START | Ph.5で実装予定 |
| 6 | — | — | シェル | SHELL-START | Ph.6で実装予定 |
| 7〜15 | — | — | ユーザタスク（動的割り当て） | TASK-CREATE | 将来 |
| — | 0x10-0xFF | (予約) | 将来拡張 | — | — |

**【注意】** TIDとSVC_IDは別の概念。SVC_IDはIPCメッセージのopcodeで使用するサービス識別子（§4.3）、TIDはTCBの物理スロット番号。クライアントはSVC_IDでサービスを区別し、実際のIPC送信先TIDは各ドライバ変数（UART-DRV-TID、STOR-DRV-TID、FILE-DRV-TID等）から取得する。

## **4.4.1 タスク起動順序【v2.2新設】**

OS-START内でのTASK-CREATE呼び出し順序を以下に確定する。起動順序の変更はTID割り当ての変更を意味するため、設計書改版なしに変更してはならない。

```forth
: OS-START  ( -- )
    MEMMGR-START        \ tid=1: MemMgr（最初に起動。他タスクのメモリ確保の前提）
    UART-START          \ tid=2: UARTドライバ（ログ出力の前提）
    STOR-START          \ tid=3: ストレージドライバ
    FILEMGR-START       \ tid=4: FileMgr（Ph.4実装予定）
    PROCMGR-START       \ tid=5: ProcMgr（Ph.5実装予定）
    SHELL-START         \ tid=6: シェル（Ph.6実装予定）
    BEGIN TASK-SLEEP AGAIN ;  \ ルートタスク（tid=0）は待機ループ
```

**起動順序の設計根拠：**
- MemMgr（tid=1）を最初に起動：他サーバがメモリ確保（MEM_ALLOC）を必要とするため最優先
- UARTドライバ（tid=2）を2番目：デバッグ出力・シェル入出力の基盤
- ストレージドライバ（tid=3）を3番目：FileMgrが依存するため先行起動
- FileMgr（tid=4）を4番目：ProcMgrがファイルロードに依存するため先行起動
- ProcMgr（tid=5）を5番目：シェルがPROC_EXECに依存するため先行起動
- シェル（tid=6）を最後：全サービスが揃った後に起動

## **4.5 IPC APIワード（kernel_forth_v0_8_5.fs v0.8.5 実装済み）【v2.1更新・v2.3 C4訂正】**

| **ワード** | **スタック効果** | **説明** |
| --- | --- | --- |
| IPC4-SEND | ( msg3 msg2 msg1 msg0 tid -- ) | 4ワードメッセージを送信（ノンブロッキング）。**msg0がTOS** |
| IPC4-RECV | ( -- msg3 msg2 msg1 msg0 ) | 4ワードメッセージ受信（なければ WAIT-IPC でブロック）。**受信後msg0がTOS** |
| IPC4-CALL | ( msg3 msg2 msg1 msg0 tid -- r3 r2 r1 r0 ) | 送信→応答待ち（同期RPC・WAIT-REPLY でブロック）。**msg0/r0がTOS** |
| IPC4-REPLY | ( r3 r2 r1 r0 tid -- ) | IPC4-CALL の送信元に応答を返す。**r0がTOS** |

**【v2.3 C4 訂正】** v2.2 では `IPC4-SEND ( msg0 msg1 msg2 msg3 tid -- )` と msg0 を底（最初にpush）とした表記だったが、これは誤りである。実装（kernel_v12_5.asm）および yuios_ph3_storage_design_v1_3.md §4.1 の実績に基づき、**msg3 が底・msg0 が TOS** という正しい順序に訂正した。クライアント側の呼び出し例も同様：`0 dst-addr LBA STOR-READ-OP STOR-DRV-TID @ IPC4-CALL`（LBA=msg1/TOS直前、op=msg0/TOS）が正しい形式。

## **4.6 同期RPC動作シーケンス**

  クライアント            カーネル                  サーバ

  IPC4-CALL               IPC4-SEND処理             IPC4-RECV

  →メッセージをTCBに格納  →サーバをREADYに         →TCBからメッセージ取得

  →WAIT-REPLY状態に       →クライアントをWAIT-REPLY →処理実行

  (ブロック)              スケジューラ切替           IPC4-REPLY

  ←応答をTCBから取得      ←クライアントをREADYに   →TCBに結果格納

  →戻り値4ワードをスタックへ

# **5. メモリマネージャ（MemMgr）**

## **5.1 概要**

MemMgr は独立したサーバタスクとして動作し、$C000-$DFFF の固定ページプールを管理します。クライアントからは IPC4-CALL 経由でページの割り当て・解放を要求します。

## **5.2 サービス要求定義（SVC_MEM = 0x01）**

| **操作名** | **opcode** | **引数** | **説明** |
| --- | --- | --- | --- |
| MEM_ALLOC | 0x0101 | arg0=ページ数 | 連続ページ割り当て。戻り値=先頭アドレス（失敗時0） |
| MEM_FREE | 0x0102 | arg0=先頭アドレス, arg1=ページ数 | ページ解放 |
| MEM_QUERY | 0x0103 | なし | 空きページ数を返す |

## **5.3 ページビットマップ**

32ページを 32bit 変数 1 つで管理します。bit0 = $C000ページ、bit31 = $DF00ページ。

  PAGE_BITMAP: 32bit変数（カーネルワーク変数領域 $E200 に配置）

  0 = 空き, 1 = 使用中

  ページアドレス計算: base_addr = $C000 + page_no * 256

## **5.4 将来のMMU連携**

256B固定ページサイズは YSD8800 MMU（YSD8800_MMU_Design_v1_1_0.docx）のページサイズと整合させています。MMU 実装後はページテーブルレジスタ（$FF00-$FF0F）と連携し、仮想アドレス空間をサポートします。

# **6. ドライバタスク**

## **6.1 設計方針**

デバイスドライバは独立したサーバタスクとして実装します。MMIO で YSD8001/8003 を制御し、IPC4 経由でサービスを提供します。UARTドライバのみ内部リングバッファ（FIFO）を持ち、割り込み（IRQ1 / YSD8004 経由）で非同期受信に対応します。

## **6.2 UARTドライバ（SVC_UART = 0x04）【v2.1: 実装完了】**

| **操作名** | **opcode** | **引数** | **説明** |
| --- | --- | --- | --- |
| UART_PUTC | 0x0401 | arg0=文字コード | 1文字送信 |
| UART_GETC | 0x0402 | なし | 1文字受信（バッファ空なら WAIT-IPC） |
| UART_PUTS | 0x0403 | arg0=文字列アドレス | 文字列送信（NULL終端） |

UARTドライバ内部には受信リングバッファ（16バイト）を持ちます。YSD8004 IRQ1 経由の受信割り込みでバッファに格納し、UART_GETC 要求に応じてバッファから返します。

## **6.3 ストレージドライバ（SVC_STORAGE = 0x05）【v2.1: Ph.3.5 Step 7C 完了】**

| **操作名** | **opcode** | **引数** | **説明** |
| --- | --- | --- | --- |
| STOR_READ | 0x0501 | arg0=LBA, arg1=dst_addr | セクタ読み込み（512B → dst_addr） |
| STOR_WRITE | 0x0502 | arg0=LBA, arg1=src_addr | セクタ書き込み（src_addr → 512B） |
| STOR_STAT | 0x0503 | なし | デバイス状態取得 |

YSD8003 MMIO ($FCA0-$FCAE) を使用。PIO 転送で 512B/セクタ。完了は YSD8004/IRQ1 経由の割り込みまたはポーリングで検出。

# **7. ファイルシステム（FileMgr）**

## **7.1 Phase 1: 独自フラットFS【v2.3 C2 更新】**

Phase 1 では実装の簡易さを優先した独自フラットファイルシステムを使用します。ディレクトリ階層なし、固定エントリ数。詳細設計は **yuios_ph4_filemgr_design_v1_2.md §3** を参照のこと（本節は概要のみ記載）。

### **7.1.1 ディスクレイアウト**

| **セクタ番号** | **用途** | **説明** |
| --- | --- | --- |
| 0 | スーパーブロック | FS識別子（"YUIFS\0\0\0"）・バージョン（ver_major/minor）・諸元（total_sectors/dir_start等）・next_free_sec・file_count |
| 1-3 | ディレクトリエントリ | 最大32エントリ（1エントリ=48B、合計1536B=3セクタ。エントリはセクタ跨ぎあり） |
| 4- | ファイルデータ | セクタ単位で連続配置（連続割り当て方式。next_free_sec で単調増加管理） |

**容量上限：** 16bit LBA × 512B = **32 MB**。スーパーブロック・ディレクトリ定義の詳細は yuios_ph4_filemgr_design_v1_2.md §3 参照。

### **7.1.2 ディレクトリエントリ構造（48B）**

| **オフセット** | **サイズ** | **フィールド** | **説明** |
| --- | --- | --- | --- |
| +0 | 16B | name[16] | ファイル名（NULL終端・拡張子含む。最大15文字） |
| +16 | 4B | size | ファイルサイズ（バイト）32bit |
| +20 | 2B | start_sec | 開始セクタ番号（LBA） |
| +22 | 2B | sec_count | 使用セクタ数 |
| +24 | 2B | flags | 属性（bit0=使用中FLG_USED, bit1=実行可能FLG_EXEC） |
| +26 | 22B | (予約) | 将来拡張（FAT12移行時に活用） |

## **7.2 FileMgr サービス（SVC_FILE = 0x02）【v2.3 C1・C3 更新】**

| **操作名** | **opcode** | **引数** | **説明** |
| --- | --- | --- | --- |
| FILE_OPEN | 0x0201 | arg0=名前アドレス | ファイルオープン。戻り値=ファイルID 0〜3（失敗=FS エラーコード $FE0x） |
| FILE_CLOSE | 0x0202 | arg0=ファイルID | クローズ。戻り値=0（成功）/FS エラー |
| FILE_READ | 0x0203 | arg0=ファイルID, arg1=dst, arg2=サイズ | 読み込み。戻り値=実読み込みバイト数（失敗=FS エラー） |
| FILE_WRITE | 0x0204 | **arg0=名前アドレス**, arg1=src, arg2=サイズ | **【C1訂正】** 新規ファイル作成＋一括書き込み。戻り値=0（成功）/FS エラー |
| FILE_SEEK | 0x0205 | arg0=ファイルID, arg1=オフセット | シーク（絶対位置）。戻り値=新オフセット/FS エラー |
| FILE_STAT | 0x0206 | arg0=名前アドレス, arg1=stat_buf | ファイル情報取得。戻り値=0（成功）/FS エラー |
| FILE_LIST | 0x0207 | arg0=buf_addr, arg1=buf_size | ディレクトリ一覧取得。戻り値=エントリ数/FS エラー |
| FILE_DELETE | 0x0208 | arg0=名前アドレス | ファイル削除（open中はE_BUSY）。戻り値=0（成功）/FS エラー |

**【C1 訂正詳細】** v2.2 §7.2 では FILE_WRITE の arg0 が「ファイルID」だったが、これは誤りである。フラットFS の連続割り当て方式では作成時に最終サイズが必要なため、FILE_WRITE は「名前指定の新規作成＋一括書き込み」セマンティクスを採る。arg0 は**名前アドレス（NULL終端文字列）**が正しい。

**【C3 エラーコード体系】** 戻り値の FS エラーは `$FE00` 台（yuios_ph4_filemgr_design_v1_2.md §4.2 確定）：

| **定数名** | **値** | **意味** |
| --- | --- | --- |
| E_OK | $0000 | 成功 |
| E_NOENT | $FE01 | ファイルが存在しない |
| E_NOSPC | $FE02 | ディスク空き容量不足 |
| E_MFILE | $FE03 | オープンファイル数上限（4）超過 |
| E_BADF | $FE04 | 不正な fid |
| E_NAMETOOLONG | $FE05 | ファイル名が15文字超 |
| E_EXIST | $FE06 | 同名ファイルが既に存在（FILE_WRITE時） |
| E_NODIRSPC | $FE07 | ディレクトリエントリの空きなし |
| E_IOERR | $FE08 | ストレージI/Oエラー |
| E_INVAL | $FE09 | 引数不正 |
| E_FSVER | $FE0A | FSフォーマットのver_major不一致（マウント拒否） |
| E_BUSY | $FE0B | ファイルがopen中のため削除不可 |

エラー値域（$FE00-$FEFF）はIPC系エラー（$FF00-$FFFF）と分離され、クライアントが判別可能。詳細は yuios_ph4_filemgr_design_v1_2.md §4.2 参照。

## **7.3 Phase 2: FAT12移行**

Phase 2 では FAT12 互換フォーマットへ移行します。フラットFS のディスクレイアウトを FAT12 に置き換え、FileMgr の内部実装のみ変更します。IPC インタフェース（SVC_FILE）は変更しません。

| **項目** | **FAT12仕様** |
| --- | --- |
| フォーマット | FAT12（512B/セクタ・PC互換） |
| ディレクトリ | ルートディレクトリ固定（階層なし） |
| ファイル名 | 8.3形式（85文字名+3文字拡張子） |
| 最大ファイル数 | 112エントリ（標準FAT12ルート） |
| メリット | PC上のツールでディスクイメージ編集可能 |

# **8. プロセスマネージャ（ProcMgr）**

## **8.1 概要**

ProcMgr は C バイナリのロードと実行を管理するサーバタスクです。FileMgr からファイルを読み込み、MemMgr からメモリを割り当て、新タスクを起動します。

## **8.2 Cバイナリ実行フロー**

  1. クライアントが PROC_EXEC('filename') を IPC4-CALL

  2. ProcMgr → FileMgr: FILE_OPEN('filename')

  3. ProcMgr → FileMgr: FILE_STAT → ファイルサイズ取得

  4. ProcMgr → MemMgr: MEM_ALLOC(pages) → ロードアドレス取得

  5. ProcMgr → FileMgr: FILE_READ(dst=ロードアドレス)

  6. ProcMgr → カーネル: TASK-CREATE(entry=ロードアドレス) → tid

  7. ProcMgr → クライアント: IPC4-REPLY(tid)

*【注】Cバイナリは位置独立コード（PIC）またはロードアドレス固定バイナリとします。v2.0 Phase 1 ではロードアドレス固定（$C000固定）とします。*

## **8.3 ProcMgr サービス（SVC_PROC = 0x03）**

| **操作名** | **opcode** | **引数** | **説明** |
| --- | --- | --- | --- |
| PROC_EXEC | 0x0301 | arg0=ファイル名アドレス | バイナリをロードして実行。戻り値=tid（失敗-1） |
| PROC_KILL | 0x0302 | arg0=tid | タスク強制終了 |
| PROC_WAIT | 0x0303 | arg0=tid | タスク終了待ち |
| PROC_LIST | 0x0304 | arg0=buf_addr | タスク一覧取得 |

# **9. シェル**

## **9.1 概要**

シェルは C で実装されたユーザランドアプリケーションです。UART ドライバ経由でコマンドを受け付け、FileMgr・ProcMgr を呼び出してコマンドを実行します。

## **9.2 基本コマンド**

| **コマンド** | **説明** |
| --- | --- |
| ls | ファイル一覧表示（FILE_LIST） |
| cat <file> | ファイル内容表示（FILE_OPEN + FILE_READ） |
| run <file> | Cバイナリ実行（PROC_EXEC） |
| ps | タスク一覧表示（PROC_LIST） |
| kill <tid> | タスク終了（PROC_KILL） |
| mem | 空きメモリ表示（MEM_QUERY） |
| ver | OS バージョン表示 |
| help | コマンド一覧表示 |

## **9.3 シェルのビルド**

シェルは scc23 でコンパイルし、lnk23 でリンクして実行バイナリを生成します。startup_harness23 と組み合わせてビルドします。

# **10. 実装順序（ロードマップ）**

## **10.1 フェーズ分割**

| **フェーズ** | **対象** | **主な作業** | **備考** |
| --- | --- | --- | --- |
| Ph.1 | IPC拡張 | TCB拡張（80B化）+ IPC4ワード実装（kernel_forth.fs v0.4） | 全マネージャの基盤 |
| Ph.2 | MemMgr | 固定ページ管理（ビットマップ）サーバタスク実装 | Ph.1完了後 |
| Ph.3 | ドライバタスク化 | UARTドライバ（リングバッファ）+ ストレージドライバ | Ph.1完了後 |
| Ph.4 | フラットFS + FileMgr | ディスクレイアウト設計＋FileMgrサーバタスク実装 | Ph.2/3完了後 |
| Ph.5 | ProcMgr | Cバイナリロード実行（$C000固定） | Ph.2/4完了後 |
| Ph.6 | シェル | コマンド実装・統合テスト | Ph.1-5完了後 |
| Ph.7 | FAT12移行 | FileMgr内部をFAT12に置き換え（IPC IF変更なし） | 将来 |
| Ph.8 | MMU連携 | ページテーブルとMemMgr統合 | 将来 |

## **10.2 各フェーズの設計書作成**

各フェーズ開始前に設計書をサブチャットで作成し、レビュー承認後に実装を開始します。実装完了後に HANDOVER_CHAT を作成し、本チャット（進捗管理）に報告します。

# **11. ビルドシステム**

## **11.1 ツールチェーン（ISA2.3系）**

| **ツール** | **バージョン** | **役割** |
| --- | --- | --- |
| hasm23 | v1.01 | YSD8800 ISA2.3 アセンブラ（-c オプションでYOF出力） |
| emu23 | v1.01 | YSD8800 ISA2.3 エミュレータ（YSD8001/8002/8003/8004 MMIO対応） |
| scc23 | v1.00 | Small-C コンパイラ（ISA2.3対応） |
| disasm23 | v1.00 | 逆アセンブラ |
| lnk23 | v2.00 | YOF対応リンカ（スクリプトモード・YOFモード） |
| Force | v1.2 | Force Forth クロスコンパイラ（.fs → .asm） |
| startup_harness23 | v1.5 | スタートアップハーネス（JSR _main でシンボル参照） |

## **11.2 標準ビルドフロー（Cアプリ）**

# 1. コンパイル

./scc23 -o prog.asm prog.c

# 2. アセンブル

./hasm23 prog.asm

# 3. リンク（スクリプトモード）

./lnk23 prog.lds   # SECTION code→harness順

# 4. 実行

./emu23 prog.bin -q

## **11.3 カーネルビルドフロー**

# 1. Forth カーネルコンパイル（Force）

./force --target ysd8800_kern kernel_forth.fs -o build/kern.asm

# 2. アセンブル（kernel_core.asm + kern.asm）

./hasm23 kernel_core.asm

./hasm23 build/kern.asm

# 3. リンク（lnk23スクリプトモード）

# SECTION: kernel_core → kern → harness の順

./lnk23 kernel.lds

# 4. 実行

./emu23 kernel.bin -q

# **12. 他アーキテクチャへの移植ガイド**

## **12.1 移植に必要な変更点**

| **変更箇所** | **内容** |
| --- | --- |
| kernel_forth.fs の CODE ブリッジ | DI-OP/EI-OP/KERN-* を対象アーキのアセンブリに変更 |
| ハードウェア定数 | UART-TX/UART-STAT/CUR-TASK-ADDR 等のアドレスを変更 |
| kernel_core.asm | IRQ0ハンドラ・コンテキストスイッチをターゲットCPUで全面書き直し |
| Force ターゲットファイル | ARCH/CELL-SIZE/DS-REG/RS-REG/TOS-REG を変更 |
| ドライバタスク | MMIO アドレスを変更（IPC インタフェースは共通） |

## **12.2 移植性確保の原則**

高レベルロジック（スケジューリングアルゴリズム・IPC・FS・MemMgr）は kernel_forth.fs と Forth ワードで記述し、アーキテクチャ非依存を維持します。アーキテクチャ依存部は CODE...END-CODE ブロックに集中させます。

# **付録A: バージョン履歴**

| **版** | **日付** | **変更内容** |
| --- | --- | --- |
| v1.0 | 2026-03 | 初版。ISA2.2 / kernel v0.6 / kernel_forth.fs v0.2 |
| v2.0 | 2026-04-23 | ISA2.3対応・TCB拡張・IPC4ワード・MemMgr・FileMgr(フラットFS/FAT12)・ProcMgr・ドライバタスク化・シェル設計を追加 |
| v2.1 | 2026-05-18 | Ph.3.5完了に伴う全面更新（メモリマップ・TCBレイアウト・IPC4 Pool方式採用） |
| v2.2 | 2026-05-18 | TID割り当て正式確定（§4.4更新・§4.4.1新設） |
| v2.3 | 2026-05-20 | Ph.4 FileMgr FIX に伴う改版：①FILE_WRITE引数訂正（fid→name_addr）、②FS §7.1 詳細更新（スーパーブロック諸元・32MB上限・セクタ跨ぎ規則）、③FS エラーコード体系追加（$FE00台）、④IPC4-CALL/RECV スタック効果表記訂正（msg0がTOS）、⑤§2.1 メモリマップを memmap v1.3 と整合（FileMgr領域$4800-$505F追加・Forthゾーン先頭$5100） |

# **付録B: 関連文書**

| **文書** | **内容** |
| --- | --- |
| ISA2_3_v231.docx | YSD8800 ISA2.3 仕様書 v2.3.1 |
| emu23_device_design_v1_2.docx | emu23 デバイス設計書（YSD8001/8002/8003/8004） |
| lnk23_design_v1_2.docx | lnk23 リンカ設計書 |
| YSD8800_MMU_Design_v1_1_0.docx | YSD8800 MMU 設計書 |
| YSD8800_ABI_spec.docx | YSD8800 ABI 仕様書 |
| yuios_memmap_design_v1_3.md | YUI OS メモリマップ設計書 **v1.3**（v1.2 → v1.3 改版済み）【v2.3更新】 |
| yuios_ph4_filemgr_design_v1_2.md | Ph.4 フラットFS + FileMgr 詳細設計書（FIX 済）【v2.3新規追加】 |
| force_lnk23_build_report_v1_0.docx | Force/lnk23 ビルドレポート v1.0 |
| kernel_forth.fs v0.3 | YUI OS Forthカーネル層（ISA2.3対応版） |

	YSD8800 YUI OS Project