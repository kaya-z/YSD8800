YUI OS v2.7 マイクロカーネル設計書	Version 2.7 / 2026-06-17

**YUI OS**

**マイクロカーネル設計書**

Version 2.7

2026-06-17

YSD8800 YUI OS Project

## **改版履歴**

| **版** | **日付** | **変更内容** | **担当** |
| --- | --- | --- | --- |
| v1.0 | 2026-03 | 初版。YSD8800 ISA2.2 / kernel v0.6 / kernel_forth.fs v0.2 | Claude |
| v2.0 | 2026-04-23 | ISA2.3対応・マイクロカーネル全機能設計（メモリ管理・FS・IPC拡張・ドライバタスク化・シェル） | Claude |
| v2.1 | 2026-05-18 | Ph.3.5（カーネル基盤改訂）完了に伴う全面更新：①メモリマップ更新（TCBプール$1000→$4000、MsgPool追加、スタック分離、KERN_SP専用化、stack guard新設）、②TCBレイアウト更新（64B→80B、16タスク化、IPC4 Poolフィールド追加）、③IPC4 Pool方式の採用（単一スロット競合バグ解消）、④ドライバタスク実装状況反映（UART/STOR実装完了・Ph.3.5 Step 7C完了） | Claude |
| v2.2 | 2026-05-18 | TID割り当て正式確定：§4.4にTID列を追加し全サーバタスクのTIDを一元管理。§4.4.1（タスク起動順序）を新設。Ph.4設計（FileMgr）着手に伴い決定。 | Claude |
| v2.3 | 2026-05-20 | Ph.4 FileMgr 設計書（yuios_ph4_filemgr_design_v1_2.md）FIX に伴う改版要請 C1〜C4 を反映：①§7.2 FILE_WRITE の引数を fid → name_addr に変更（C1）、②§7.1 ディスクレイアウトを Ph.4 設計書参照に更新（C2）、③§7.2 エラー戻り値を FS 系 $FE00 台エラーコード体系に更新（C3）、④§4.5 IPC4-CALL/RECV のスタック効果表記を実装実績（STOR 設計書準拠）に訂正（C4）、⑤§2.1 メモリマップを memmap v1.3 と整合（FileMgr 領域追加・Forth ゾーン先頭 $5100 変更） | Claude |
| v2.4 | 2026-06-06 | Ph.4 FileMgr 全 API 実装完了・Ph.3.5 補完工程（I-2/I-3）完了に伴う一括改版：①§4.4 FileMgr（tid=4）の実装状況を「Ph.4で実装予定」→「**実装済（Ph.4）**」に更新、②§4.4.1 OS-START コメントの FILEMGR-START を実装済みに更新、③§10.1 フェーズ表に Ph.1〜Ph.4・Ph.3.5 補完工程の完了を明記、④§11.1 ツールチェーン版数を最新（emu23 v1.05・Force v1.5・hasm23 v1.02）に更新、⑤付録 B 関連文書を最新版（FileMgr 設計書 v1.9.5・memmap v1.6・emu23 v1.05 設計書等）に更新、⑥付録 A 版数履歴に v2.4 を追記 | Claude |
| v2.5 | 2026-06-06 | Ph.5 ProcMgr 詳細化（案C）：§8 全面詳細化・$C000-$DFFF 再分割（ProcMgr ロード $C000-$C7FF＋MemMgr $C800-$DFFF/24ページ）・§2/§5 整合・KY42 衝突解消。レビュー差し戻し（v2.5_review_v1_0） |
| v2.6 | 2026-06-06 | レビュー指摘 D-1〜D-9 反映：①D-1 §2.2 ユーザ20ページに修正、②D-2 ビットマップを実体（PAGE-BMP-LO/HI 2×16bit・初期値 LO=$0000/HI=$FFF0・bit割当）で1箇所集約、③D-3 PAGE_BITMAP 配置を $E200→実体 $FC40/$FC42 に修正、④D-4/R3 ProcMgr ワークを Forth VARIABLE 化に確定、⑤D-5 PROC_LIST に arg1=buf_size 追加、⑥D-6/R4 crt0 実体確認（harness は HALT・ProcMgr 専用 crt0 を §10.3 作業項目化）、⑦D-7 TASK-KILL 不在確認・TCB-STATE! による DEAD 化方式を §8.5.4 に設計、⑧D-8 ヘッダ版数統一、⑨D-9 付録A 追記、⑩R1-R6 全件クローズ（§8.8）。memmap v1.7 同期は本書確定後。**【第2回レビュー（v2_6_review_v1_0）条件付き承認・E-1（改版履歴 v2.5 行重複）を削除し集約・本版確定】** |
| v2.7 | 2026-06-17 | **【Level 1/Level 2 区分の正式導入（OS-9 Level I/II リスペクト）】** memmap v2.4（案D-ε・承認済）および同レビュー D-2/O-4 の確定に同期。Ph.5 Step4 で発覚した $C000 衝突（ProcMgr ロード領域と Forth 辞書実コード $C15F の物理衝突）の根本解消に伴い、YUI OS の動作モデルを **Level 1（MMU なし・単一空間）／Level 2（MMU あり・アドレス変換）** として正式区分。①**§1.4 新設**＝Level 区分の定義（Level 1＝動的 C プロセス同時1個・Shell は Forth 常駐・PAGE-POOL は MMU 見越し温存／Level 2＝複数 C プロセス・Shell は C 実装・論理ページプール昇格）。②**§9 改版**＝Shell を「Level 1：Forth 常駐実装」「Level 2：C 実装（v2.6 §9.1 の到達目標）」の二段構成へ。v2.6 §9.1「Shell=C 実装」は消さず Level 2 到達目標として位置づけ直し（KY41）。③**§8.0.1 Phase 区分を Level 区分へ対応づけ**（Phase 1↔Level 1／Phase 2↔Level 2）。④**§8.2.2 単一プロセス制約**に「単一固定ロード領域＋非PIC＋MMU なしでは run が原理的に不成立」の構造制約（memmap v2.4 §15.2）を明記し、Level 1 では Shell を辞書常駐とすることで C プロセス領域を子プロセス専用1スロットにして run を成立させる旨を追記。⑤**§2.1 メモリマップ**に ProcMgr ロード領域 $C000→$D400-$DBFF（memmap v2.4 案D-ε）を反映。⑥**§5.4 MMU連携**を Level 2 移行の文脈で更新。⑦**§10 ロードマップ**に Level 区分の位置づけ（Ph.8 MMU で Level 1→Level 2）を追記。前提：memmap v2.4 承認済・本書は §9 等の方針記述更新（実装はロードマップ各 Ph で別途）。 | Claude |

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

## **1.4 動作レベル区分（Level 1 / Level 2）【v2.7 新設・OS-9 Level I/II リスペクト】**

YUI OS は、ハードウェアの MMU 有無に応じた **2 段階の動作レベル**を持つ。これは MC6809 系 OS-9 の **Level I（フラット 64KB 空間）／Level II（DAT による動的アドレス変換）** の本質的区分をリスペクトしたものである。Ph.5 Step4 で顕在化した「単一固定ロード領域では、あるプロセスが別プロセスを起動できない（非PIC・MMU なしの構造制約）」という問題を、敗北ではなく**段階的達成**として明示化するために導入する（根拠：memmap v2.4 §15.2/§15.3）。

| 項目 | **YUI OS Level 1**（現状・MMU なし） | **YUI OS Level 2**（Ph.8 MMU 対応後・将来） |
| --- | --- | --- |
| 動的 C プロセス（`run` で起動） | **同時 1 個** | **複数同時実行**（MMU アドレス変換） |
| システムサービス（UART/Mem/File/Proc） | **複数並行常駐**（マイクロカーネルとして動作） | 同左 |
| Shell 実装 | **Forth 常駐**（辞書・C プロセス領域を消費しない） | **C 実装**（ユーザランドへ外出し・§9.1 の到達目標） |
| C プロセス領域 | **1 スロット**（$D400-$DBFF・子プロセス専用） | MMU バンクで複数 |
| PAGE-POOL | $DD00-$ECFF/16pg を温存（MMU 見越し） | 論理ページプールへ昇格（Level 1 の物理プールが土台） |
| IPC インターフェース | FILE_*/PROC_*/MEM_* | **Level 1 から不変**（サービス層無改造で Level 2 へ移行） |
| 対応する Phase 区分（§8.0.1） | Phase 1 | Phase 2 |

**Level 1 の "同時 1 プロセス" の定義**：`run` で起動する**動的 C プロセス**が同時 1 個。Forth 常駐 Shell と各システムサービスタスク（FileMgr/MemMgr/UART/ProcMgr）は**カーネル側常駐としてカウント外**。すなわち YUI OS Level 1 は「ユーザ動的プロセス 1 個＋複数の常駐サービスタスクが IPC4 で並行協調する真のマイクロカーネル」である。

**移行戦略**：Level 1 で IPC インターフェース（FILE_*/PROC_*/MEM_*）とサービス分割を固める。Ph.8 で MMU を載せたとき、ユーザプロセス側のみがアドレス変換の恩恵を受けて複数化し、サービス層は無改造で Level 2 へ移行する。OS-9 が Level I→II でアプリ再コンパイル不要だったのと同じ実装経済性を狙う。**Shell=C 実装という当初目標（§9.1）は捨てず、Level 2 の到達目標として位置づけ直す**（Level 1 では Forth 常駐で先行実装し `run` 競合を回避する）。

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
| $C000-$C7FF | 2 KB | **ProcMgr ロード領域**（Phase 1 単一プロセス固定） | **【v2.5 案C新設】§8.4** ／ ~~$C000-$C7FF~~ → **【v2.7：memmap v2.4 案D-ε で $D400-$DBFF へ移設】** $C000 は Forth 辞書実コード $C15F と衝突したため辞書外へ移設。最新配置は memmap v2.4 §15 を正とする |
| $C800-$DFFF | 6 KB | 固定ページプール（MemMgr管理・24ページ） | **【v2.5 案C：$C000-$DFFF→縮小移設】** ／ ~~$C800-$DFFF/24pg~~ → **【v2.7：memmap v2.2/v2.4 で $DD00-$ECFF/16pg へ確定】** Level 1 で温存（MMU 見越し）。最新は memmap v2.4 §15.8 を正とする |
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

**$C800-$DFFF（6KB）** を固定ページ方式で管理します【**v2.5 案C：$C000-$DFFF 8KB/32ページ→$C800-$DFFF 6KB/24ページ。先頭 2KB は ProcMgr ロード領域へ転用（§8.4）**】。1ページ = 256バイト、合計24ページ。

| **項目** | **値** | **説明** |
| --- | --- | --- |
| ページサイズ | 256 B | 固定。MMU ページサイズと将来整合させるため 256B 単位。 |
| 総ページ数 | **24 ページ** | $C800-$DFFF = 6KB / 256B = 24【v2.5 案C】 |
| 管理方式 | ビットマップ（2×16bit） | 実体は `PAGE-BMP-LO`($FC40)＋`PAGE-BMP-HI`($FC42) の 16bit 2変数で 32bit を構成。**LO=bit0-15、HI=bit16-31**【**v2.6 D-2: 実体反映**】 |
| bit割当 | bit0-19=ユーザ20ページ / bit20-23=OS予約4ページ / bit24-31=無効ページ | **初期値: LO=$0000（page0-15 空き）／HI=$FFF0（bit20-23 OS予約＝使用中・bit24-31 無効＝使用中マーク）**【**v2.6 D-2**】 |
| 割り当て単位 | 1ページ以上 | 連続ページも割り当て可（alloc_pages(n)） |
| ユーザ用 | **20ページ** | Cアプリ等のページ確保用（24ページ中 4ページをOS予約に充当）【**v2.6 D-1: 28→20。案Cの総24ページに整合**】 |

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
| 4 | 0x02 | SVC_FILE | ファイルマネージャ（FileMgr） | FILEMGR-START | **実装済（Ph.4）** |
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
    FILEMGR-START       \ tid=4: FileMgr（**Ph.4実装済**）
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

MemMgr は独立したサーバタスクとして動作し、**$C800-$DFFF（6KB・24ページ）** の固定ページプールを管理します【**v2.5 案C：$C000-$DFFF→$C800-$DFFF に移設・縮小**。先頭 $C000-$C7FF は ProcMgr ロード領域へ転用（§8.4）】。クライアントからは IPC4-CALL 経由でページの割り当て・解放を要求します。

## **5.2 サービス要求定義（SVC_MEM = 0x01）**

| **操作名** | **opcode** | **引数** | **説明** |
| --- | --- | --- | --- |
| MEM_ALLOC | 0x0101 | arg0=ページ数 | 連続ページ割り当て。戻り値=先頭アドレス（失敗時0） |
| MEM_FREE | 0x0102 | arg0=先頭アドレス, arg1=ページ数 | ページ解放 |
| MEM_QUERY | 0x0103 | なし | 空きページ数を返す |

## **5.3 ページビットマップ**

**24ページ**を 16bit 変数 2 つ（PAGE-BMP-LO/HI で 32bit 構成）で管理します【**v2.6 D-2: 実体反映**】。bit0 = $C800ページ、bit23 = $DF00ページ。**LO=bit0-15／HI=bit16-31**。bit20-23 は OS 予約、bit24-31 は無効ページとして恒久使用中マーク。初期値 **LO=$0000 / HI=$FFF0**。

  PAGE_BITMAP: 16bit×2変数 PAGE-BMP-LO($FC40) / PAGE-BMP-HI($FC42)
              【v2.6 D-3: 設計書旧記述「$E200」は v0.5 時代の陳腐化値。
               kernel_forth v0.10.11 実体は OS共有変数域 $FC40/$FC42
               （$E200→$F010→$FC40 と移動済み）。§2.1 $FC40-$FCFF 内に所在】

  0 = 空き, 1 = 使用中

  ページアドレス計算: base_addr = $C800 + page_no * 256  ★v2.5 案C

## **5.4 将来のMMU連携**

256B固定ページサイズは YSD8800 MMU（YSD8800_MMU_Design_v1_1_0.docx）のページサイズと整合させています。MMU 実装後はページテーブルレジスタ（$FF00-$FF0F）と連携し、仮想アドレス空間をサポートします。

> **【v2.7：Level 2 移行の文脈】** 本 MMU 連携は **YUI OS Level 2（§1.4）への移行**そのものである。Level 1 で温存した PAGE-POOL（$DD00-$ECFF/16pg・memmap v2.4 §15.8 で不変宣言）は、MMU 見越しの大プールとして確保されており、Level 2 で論理ページプールへ昇格する土台となる（かやぬま指示：Level 1 で PAGE-POOL を縮小せず温存することで Level 2 移行を円滑化）。Level 2 では各 C プロセスが独立した仮想アドレス空間（仮想 $C000 等の固定エントリ・物理は別ページ）を持ち、§8.2.2 の単一固定ロード領域制約が解消されて複数プロセスの真の同時実行が可能になる。

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

# **8. プロセスマネージャ（ProcMgr）**【v2.5 全面詳細化・案C】

## **8.0 設計方針（案C）と KY42 衝突解消**

ProcMgr（TID=5、SVC_PROC=0x03）は C バイナリのロードと実行を管理するサーバタスクです。本節は v2.4 までの概要記述を、Ph.5 詳細設計（yuios_ph5_procmgr_design_v0_1.md）に基づき全面詳細化したものです。

**【重要・KY42】** v2.4 §8 では Phase 1 ロードアドレスを「$C000 固定」としていましたが、$C000-$DFFF（8KB）は §5 の MemMgr ページプールおよび memmap v1.6 §4.5 の「Forth コード成長予約」と三重に重複していました。この二重使用は Step 5-1 の `_FMUL_A/B/R`×TCB[7] 衝突と同質の致命事故を招くため、**案C により本領域を再分割して恒久解消**します（§8.4・§5.1 と連動）。

### **8.0.1 Phase 区分**

| Phase | 内容 |
| --- | --- |
| **Phase 1** | 単一プロセス・~~ロードアドレス $C000 固定~~ → **ロードアドレス $D400 固定（memmap v2.4 案D-ε）**・非PIC バイナリ（本節で設計）。**＝YUI OS Level 1（§1.4）に対応** |
| Phase 2（将来） | MMU によりプロセスごと独立仮想空間（仮想 $C000 固定・物理は別ページ）。OS-9 メモリモジュール思想に接近。**＝YUI OS Level 2（§1.4）に対応** |

> **【v2.7 注記】** 本 Phase 区分は §1.4 の動作レベル区分（Level 1/Level 2）と一対一対応する。Phase はプロセスローダ（ProcMgr）視点の区分、Level は OS 全体の動作モデル視点の区分であり、同じ段階を指す。ロードアドレスは memmap v2.4 で $C000→$D400 へ移設された（$C000 が Forth 辞書実コード $C15F と衝突したため。詳細 §8.2.2）。

## **8.1 概要**

ProcMgr は、FileMgr（tid=4）に格納された C バイナリ（scc23 v1.00 出力のフラットバイナリ・非PIC）をディスクから読み出し、$C000 固定領域へロードして新タスクとして起動・管理するサーバタスクです。MC6809/OS-9 における exec に相当する役割を、マイクロカーネル構成（カーネルは TASK-CREATE のみ提供し、ロード管理はユーザ空間サーバが担う）で実現します。ProcMgr 自身は IPC4-CALL を受けるサーバであると同時に、内部で FileMgr・カーネル（TASK-CREATE）を呼ぶクライアントでもあります。

## **8.2 Cバイナリ実行フロー（PROC_EXEC）**

```
クライアント            ProcMgr (tid=5)              FileMgr / カーネル
PROC_EXEC(fname)
 IPC4-CALL ───────────> IPC4-RECV
                        1. FILE_OPEN(fname) ────────> FileMgr: fd 取得
                        2. FILE_STAT(fd) ───────────> FileMgr: size 取得
                        3. size ≤ 2KB 検証（NGは-1 REPLY）
                        4. ★Phase1: ロード先=$C000 固定
                           （MEM_ALLOC は使わない）
                        5. FILE_READ(fd, dst=$C000) ─> FileMgr: 本体読込
                        6. FILE_CLOSE(fd) ──────────> FileMgr
                        7. TASK-CREATE($C000) ──────> カーネル: tid 取得
                        8. PROC テーブル登録（tid, busy）
 <── IPC4-REPLY(tid) ── 9. IPC4-REPLY(tid)
```

**【案C 重要差分】** v2.4 §8.2 手順4「MEM_ALLOC でロードアドレス取得」は **Phase 1 では実施しません**。$C000 固定領域を直接使用します。理由：scc23 v1.00 は非PIC のため可変アドレスへロードしても動作せず、PIC 対応は scc23 v1.10 計画にも未収載のためです。Phase 2 で MMU により各プロセスが仮想 $C000 を持つ形へ発展させます。

### **8.2.1 エラーハンドリング**

| 失敗条件 | 戻り値 |
| --- | --- |
| ファイル不存在（FILE_OPEN 失敗） | -1（$FFFF） |
| サイズ > 2KB（Phase 1 制約） | -1 |
| ロード領域使用中（Phase 1 単一プロセス制約） | -1 |
| TASK-CREATE 失敗（TCB 枯渇） | -1 |

### **8.2.2 単一プロセス制約の管理**

Phase 1 はロード領域が1つ（~~$C000-$C7FF~~ → **$D400-$DBFF**・memmap v2.4 案D-ε）のため同時1プロセスのみ。ProcMgr は `LOAD-SLOT-BUSY` フラグで占有状態を管理し、稼働中プロセスの PROC_WAIT/PROC_KILL/TASK-EXIT 完了でクリアします。

> **【v2.7 構造制約の明記（memmap v2.4 §15.2）】** この「同時1プロセス」制約は、単なる実装上の都合ではなく **構造的必然**である。ProcMgr は C バイナリを**固定アドレス（PROC-LOAD-ADDR）へ FILE-READ → TASK-CREATE** する単一ロード領域モデルを採る。このため「あるプロセスが別のプロセスを起動する」（例：Shell の `run fib`）は、子プロセスが同じ固定アドレスへロードされ**実行中の親プロセス自身を上書き破壊**するため、**原理的に不可能**である。これは **MMU なし（単一物理アドレス空間）かつ crt0 が固定エントリ＝非PIC** という 2 制約が重なった限界による（OS-9 Level I が MMU なしで複数プロセスを動かせたのは Microware が PIC を徹底したためで、scc23 の非PIC 出力ではそのまま適用できない）。
>
> **Level 1 での対処**：Shell を **Forth 常駐**（辞書に置く・§9）とすることで Shell は C プロセス領域（$D400）を使わず、`run` で起動する子プロセスのみが $D400 を占有する。これにより親（Forth Shell・辞書常駐）と子（C プロセス・$D400）が領域を奪い合わず、Level 1 でも `run` が成立する。C プロセス領域は「子プロセス専用 1 スロット」となる。複数プロセスの真の同時実行は Level 2（MMU）で実現する。

## **8.3 ProcMgr サービス（SVC_PROC = 0x03）**

IPC4 メッセージ規約（msg3 が底・msg0 が TOS、§4.5 C4 訂正）に従います。

| **操作名** | **opcode** | **引数** | **戻り値** | **説明** |
| --- | --- | --- | --- | --- |
| PROC_EXEC | 0x0301 | arg0=ファイル名アドレス | tid（失敗 -1） | バイナリをロードして実行 |
| PROC_KILL | 0x0302 | arg0=tid | 0/-1 | タスク強制終了 |
| PROC_WAIT | 0x0303 | arg0=tid | 終了コード | タスク終了待ち |
| PROC_LIST | 0x0304 | arg0=buf_addr, arg1=buf_size | エントリ数 | タスク一覧を buf へ書込み【**v2.6 D-5: arg1=buf_size 追加。FILE_LIST と引数形式統一・オーバーラン防止**】 |

**IPC メッセージ形式（msg0=TOS）：** msg0=opcode / msg1=arg0 / **msg2=arg1（PROC_LIST の buf_size 等。他サービスは0）**【v2.6 D-5】 / msg3=予約(0)。
**応答（r0=TOS）：** r0=戻り値 / r1-r3=予約(0)。

## **8.4 メモリ再配置（案C・memmap v1.7 改版要件）**

$C000-$DFFF（8KB）を以下に再分割します（§5.1・memmap v1.7 と連動）：

| アドレス | サイズ | 用途 | v1.6 旧用途 |
| --- | --- | --- | --- |
| **$C000-$C7FF** | 2 KB | **ProcMgr ロード領域**（Phase 1 単一プロセス固定・$C000 固定エントリ） | Forth 成長予約の一部 |
| **$C800-$DFFF** | 6 KB | **MemMgr 固定ページプール（24 ページ×256B）** | MemMgr プール 32 ページ全体 |

Forth 辞書本体は $5100-$BFFF（27KB）で確保済みであり、$C000- の成長予約は現時点で未使用のため、本転用は現行辞書を侵食しません。Forth 成長予約の消失（8KB→0）は将来逼迫時に memmap v2.0 で再配置します。

**MemMgr 移設に伴う定数変更（実装は Ph.5 工程・本節は確定仕様）：** `PAGE-POOL-BASE` $C000→**$C800**、`PAGE-TOTAL` 32→**24**、`PAGE-USER-MAX` 28→**20**、`PAGE-BMP-HI-INIT` $F000→**$FFF0**（bit20-23=OS予約・bit24-31=無効ページを使用中マーク）。アドレス計算式 `base = PAGE-POOL-BASE + page_no*256` は定数追従のためロジック変更不要。

## **8.5 タスク終了連携【v2.6 実体確認反映】**

### **8.5.1 カーネル API 実体（kernel_forth v0.10.11 確認済）**

| 機能 | ワード | 実体有無 |
| --- | --- | --- |
| タスク生成 | `TASK-CREATE ( entry -- tid )` | ✅ 存在 |
| 自タスク終了 | `TASK-EXIT ( -- )` | ✅ 存在 |
| 他タスク強制終了 | TASK-KILL 相当 | ❌ **不在**（D-7） |
| タスク状態 | `TCB-STATE@/!`・状態定数 `TASK-DEAD=0 / READY=1 / RUNNING=2 / SLEEPING=3 / WAIT-MSG=4 / WAIT-IPC=5 / WAIT-REPLY=6` | ✅ 存在 |

### **8.5.2 crt0 の TASK-EXIT（D-6・R4 確定）**

**実体確認結果：** `startup_harness23 v1.5` は `JSR _main` の直後が **`HALT`**（L66）であり、main から戻ると**システム全体が停止**する。これは harness（単一プログラム実行）専用であり、**ProcMgr がロードする C プロセスには使用不可**（main 終了でOS全体が落ちる致命挙動）。

**確定方針：** Ph.5 にて **ProcMgr 専用 crt0（`startup_proc.asm`）を新規作成**し、`JSR _main` 直後を **`HALT` ではなく TASK-EXIT 呼び出し**（KERN-TASK-EXIT 相当の SYSCALL もしくは Forth ワード連携）に置き換える。これを **Ph.5 必須作業項目**とする（§10.3 参照）。

### **8.5.3 PROC_WAIT（R2 確定）**

Phase 1 単一プロセスでは、対象 TCB の `TCB-STATE@` をポーリングし `TASK-DEAD` 到達で REPLY する。**終了コードは Phase 1 では 0 固定**（TCB に終了コードフィールドを新設するのは将来 Phase）。本判断を確定とする（R2 クローズ）。

### **8.5.4 PROC_KILL（D-7 確定）**

TASK-KILL 相当ワードは不在だが状態機構は存在するため、Phase 1 は以下手順で実装する：① 対象 tid の `TCB-STATE!` に `TASK-DEAD` を設定（スケジューラ選択対象から除外。スケジューラは state を見て READY のみ選択）、② ロード領域占有フラグ `LOAD-SLOT-BUSY` をクリア、③ 当該タスクのコール/データスタック領域は固定割当のため明示解放不要（次回ロードで上書き）。**カーネルへの TASK-KILL ワード追加は行わず、ProcMgr 層で TCB-STATE! による DEAD 化で実現する**（マイクロカーネル原則：機構はカーネル・方針はサーバ）。

## **8.6 起動（PROCMGR-START）**

§4.4.1 の起動順序（OS-START 内 5番目・tid=5）に従い、`PROCMGR-START` が ProcMgr 本体（PROCMGR-TASK：IPC4-RECV ループ＋ディスパッチ）を TASK-CREATE で起動します。実装は FileMgr（FILEMGR-START/DISPATCH）構造を踏襲します。

## **8.7 ProcMgr ワーク変数【v2.6 D-4・R3 確定】**

**確定方針：** ProcMgr はユーザ空間サーバであるため、ワーク変数を **カーネルワーク予約域（$47C0系）には置かず、Forth ワークスペース内の `VARIABLE` として定義**する（層的整合・レビュー推奨に従う）。Force/Forth 辞書の通常 VARIABLE 配置（Forth ゾーン $5100-$EFFF・データ部）に置かれ、カーネル予約域・Force ランタイム占有域（$47B0-$47B6）とは物理的に分離されるため、`_FMUL_A/B/R`×TCB[7] と同質の層混在衝突を構造的に回避する。

| 変数（VARIABLE） | 用途 |
| --- | --- |
| `LOAD-SLOT-BUSY` | ロード領域占有フラグ（0=空き/非0=稼働 tid） |
| `PROC-CUR-TID` | 現稼働プロセス tid |
| `PROC-EXIT-CODE` | 直近終了プロセスの終了コード（Phase 1 は常時0・§8.5.3） |

**force_memory_contract v1.2 突合結果：** VARIABLE は Forth ゾーンに配置され、契約書 §4.3「触れてはならない領域」（$47B6 / $FF11-$FFFF 等）に抵触しない。層分離により衝突なし（D-4 クローズ）。

## **8.8 レビュー観点一覧（Ph.5 設計）【v2.6 全件クローズ】**

| # | 観点 | 確定結果（v2.6） | 連動 |
| --- | --- | --- | --- |
| R1 | MemMgr 24ページ化のビットマップが bit0-23 のみ正走査するか | ✅ 初期値を LO=$0000/HI=$FFF0 に確定（§2.2・§5.3）。bit24-31 を恒久使用中マークし ALLOC 対象外化。**実装後に kernel_forth で走査を実検証する**（Ph.5 実装時 KY 項目） | §2.2/§5.3/§8.4 |
| R2 | PROC_WAIT 終了コード保持方式 | ✅ **Phase 1 は終了コード 0 固定**に確定（TCBフィールド新設は将来） | §8.5.3 |
| R3 | ProcMgr ワーク変数配置 | ✅ **Forth ワークスペースの VARIABLE 化**に確定（カーネル予約域不使用）。contract v1.2 と突合済 | §8.7 |
| R4 | scc23 出力 main 後の TASK-EXIT crt0 | ✅ 実体確認：harness は HALT で不適。**ProcMgr 専用 crt0（startup_proc）を Ph.5 で新規作成**と確定 | §8.5.2/§10.3 |
| R5 | Phase 1 C バイナリ 2KB 収容 | ⏳ 実測は Ph.5 実装時に dhry_timer 等で実施・記録（設計上の上限は 2KB と確定。超過時 memmap v2.0 で拡張） | §8.4 |
| R6 | memmap v1.7・本節最終反映 | ⏳ 本書 v2.6 確定後に memmap を v1.7 へ一括同期（$C000 再分割・$C800 起点24ページ・BMP初期値・ProcMgr crt0 依存） | §8.4 |

**注：** R1・R5 の実機検証は「設計確定」と「実装時検証」を分離したもので、設計判断としては全件クローズ済み。実装フェーズで R1（走査）・R5（サイズ）を検証 KY として継続管理する。

# **9. シェル**

## **9.1 概要**

~~シェルは C で実装されたユーザランドアプリケーションです。~~UART ドライバ経由でコマンドを受け付け、FileMgr・ProcMgr を呼び出してコマンドを実行します。

> **【v2.7 改版：Level 区分による Shell 実装の二段構成】** v2.6 §9.1 は「シェルは C 実装のユーザランドアプリ」と記したが、Ph.5 Step4 で判明した構造制約（§8.2.2：単一固定ロード領域では Shell が `run` で子プロセスを起動できない）により、**Level に応じて実装言語を分ける**こととした（memmap v2.4 §15.4・本書 §1.4）。旧 v2.6 の「C 実装」記述は **Level 2 の到達目標**として有効であり、削除しない（KY41）。

| 動作レベル | Shell 実装 | 配置 | 理由 |
| --- | --- | --- | --- |
| **Level 1**（現状・MMU なし） | **Forth 常駐**（kernel_forth 辞書内） | 辞書（$C15F 直上から伸長・約 1.4KB 見込み） | C プロセス領域 $D400 を使わないため `run` 子プロセスと競合しない。8 コマンドの大半は既存サービスワード（FILE_*/PROC_*/MEM_*）への IPC ラッパで、辞書消費が小さい |
| **Level 2**（Ph.8 MMU 後・将来） | **C 実装**（ユーザランドアプリ） | ユーザプロセス空間（MMU 仮想 $C000 等） | MMU により複数プロセス共存が可能になり、Shell を独立 C プロセスとして外出しできる（v2.6 §9.1 の本来の姿・OS-9 のディスク常駐シェル思想） |

**Level 1 Forth Shell の構成**：メイン REPL ループ（`SHELL-TASK`）＋行入力（UART_RX poll）＋トークナイザ＋コマンドディスパッチ＋8 コマンドの IPC ラッパ。重い処理（ファイル I/O・プロセス管理・メモリ管理）はすべて既存サービスタスクへ IPC で委譲するため、Shell 本体は軽量。サイズ見積りは約 1.4KB（fib v1.03 実測基準の外挿・±30%）で、memmap v2.4 案D-ε の辞書余裕（新天井 $D3FF まで約 4.7KB）に収まる。Ph.6 実装時に最初の 2〜3 コマンド実装時点で .sym 実測し外挿を補正する（memmap v2.4 §15.10 O-2）。

## **9.2 基本コマンド**

| **コマンド** | **説明** | **依存サービス（実装済）** |
| --- | --- | --- |
| ls | ファイル一覧表示（FILE_LIST） | FileMgr（Ph.4 実装済） |
| cat <file> | ファイル内容表示（FILE_OPEN + FILE_READ） | FileMgr（Ph.4 実装済） |
| run <file> | Cバイナリ実行（PROC_EXEC） | ProcMgr（Ph.5 実装済） |
| ps | タスク一覧表示（PROC_LIST） | ProcMgr（Ph.5 実装済） |
| kill <tid> | タスク終了（PROC_KILL） | ProcMgr（Ph.5 実装済） |
| mem | 空きメモリ表示（MEM_QUERY） | MemMgr（Ph.2 実装済） |
| ver | OS バージョン表示 | Shell 内蔵 |
| help | コマンド一覧表示 | Shell 内蔵 |

8 コマンド中 6 個は既存サービスタスクへの IPC 呼び出しの薄いラッパであり、Shell 自体のロジックは「行入力→パース→ディスパッチ→IPC 発行→結果出力」の REPL に集約される。OS-9 のシェルが `dir`/`copy`/`procs`/`mfree` 等の多くをシステムコールの薄いラッパとして実装していたのと同じ構造。

## **9.3 シェルのビルド**

**Level 1（Forth 常駐）**：kernel_forth.fs に Shell ワード群を追加し、Force でクロスコンパイルしてカーネルへ組み込む。独立バイナリ生成は不要（辞書常駐）。

~~**Level 2（C 実装）**：~~シェルは scc23 でコンパイルし、lnk23 でリンクして実行バイナリを生成します。startup_harness23（→ Level 2 では startup_proc 系 crt0）と組み合わせてビルドします。（**※この C ビルド手順は Level 2 で適用。Level 1 では上記 Forth 組み込み方式を用いる**）



# **10. 実装順序（ロードマップ）**

## **10.1 フェーズ分割**

> **【v2.7：Level 区分とフェーズの対応】** Ph.1〜Ph.7 は **YUI OS Level 1**（MMU なし・動的 C プロセス同時1個・Shell は Forth 常駐／§1.4）の構築フェーズである。**Ph.8（MMU 連携）をもって Level 1→Level 2 へ移行**し、複数 C プロセス同時実行と C 実装 Shell が解禁される。

| **フェーズ** | **対象** | **主な作業** | **備考** |
| --- | --- | --- | --- |
| Ph.1 | IPC拡張 | TCB拡張（80B化）+ IPC4ワード実装（kernel_forth.fs v0.4） | **✅ 完了** |
| Ph.2 | MemMgr | 固定ページ管理（ビットマップ）サーバタスク実装 | **✅ 完了** |
| Ph.3 | ドライバタスク化 | UARTドライバ（リングバッファ）+ ストレージドライバ | **✅ 完了** |
| Ph.3.5 | カーネル基盤改訂 | メモリマップ再設計・TCB 16タスク化・IPC4 Pool方式・自動検査（I-2）・負荷試験（I-3）・emu23 v1.05 watermark | **✅ 完了（2026-06-06 I-2/I-3 全項目 PASS）** |
| Ph.4 | フラットFS + FileMgr | ディスクレイアウト設計＋FileMgrサーバタスク実装（全 API: LIST/OPEN/CLOSE/READ/WRITE/SEEK/STAT/DELETE） | **✅ 完了（2026-06-05 Ph.4 総合試験 PASS）** |
| Ph.5 | ProcMgr | Cバイナリロード実行（~~案C：$C000-$C7FF 固定ロード／MemMgrプール $C800-$DFFF へ移設~~ → **案D-ε：$D400-$DBFF 固定ロード（memmap v2.4・$C000 衝突解消）／PAGE-POOL $DD00-$ECFF 温存**） | 🔧 **実装中（Level 1）。memmap v2.4 承認済・Step4 本体（ProcMgr 経由ロード）再開待ち** |
| Ph.6 | シェル | コマンド実装・統合テスト（**Level 1：Forth 常駐 Shell・§9**） | Ph.1-5完了後（**Level 1**） |
| Ph.7 | FAT12移行 | FileMgr内部をFAT12に置き換え（IPC IF変更なし） | 将来（**Level 1**） |
| Ph.8 | MMU連携 | ページテーブルとMemMgr統合。**＝Level 1→Level 2 移行（複数 C プロセス・C 実装 Shell 解禁・PAGE-POOL を論理ページプールへ昇格）** | 将来（**Level 2 への移行点**） |

## **10.2 各フェーズの設計書作成**

各フェーズ開始前に設計書をサブチャットで作成し、レビュー承認後に実装を開始します。実装完了後に HANDOVER_CHAT を作成し、本チャット（進捗管理）に報告します。

## **10.3 Ph.5 実装作業項目【v2.6 新設】**

レビュー（yuios_design_v2_5_review_v1_0）の確定結果に基づく Ph.5 実装の作業項目：

1. **MemMgr プール移設**：`PAGE-POOL-BASE`=$C800 / `PAGE-TOTAL`=24 / `PAGE-USER-MAX`=20 / `PAGE-BMP-HI-INIT`=$FFF0（LO=$0000）へ定数変更（1変更1検証）。変更後 ALLOC が bit0-23 のみ正走査することを実検証（R1）。
2. **ProcMgr 専用 crt0（startup_proc.asm）新規作成**：`JSR _main` 直後を HALT ではなく TASK-EXIT 呼び出しに（D-6/R4・§8.5.2）。バージョン表示・コメント版数付与。
3. **ProcMgr 本体実装**：PROCMGR-TASK（IPC4-RECV ループ＋ディスパッチ）・PROC_EXEC/KILL/WAIT/LIST・ワーク VARIABLE（§8.7）。
4. **C バイナリ 2KB 収容実測**（R5）：dhry_timer 等で実測し記録。
5. **memmap v1.7 同期**（R6）。

# **11. ビルドシステム**

## **11.1 ツールチェーン（ISA2.3系）**

| **ツール** | **バージョン** | **役割** |
| --- | --- | --- |
| hasm23 | v1.02 | YSD8800 ISA2.3 アセンブラ（-c オプションでYOF出力・W001 .org重ね書き警告） |
| emu23 | v1.05 | YSD8800 ISA2.3 エミュレータ（YSD8001/8002/8003/8004 MMIO対応・-w watermark計測） |
| scc23 | v1.00 | Small-C コンパイラ（ISA2.3対応） |
| disasm23 | v1.00 | 逆アセンブラ |
| lnk23 | v2.00 | YOF対応リンカ（スクリプトモード・YOFモード） |
| Force | v1.5 | Force Forth クロスコンパイラ（.fs → .asm・VARIABLE/VALUE/DEFER分離出力） |
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
| v2.4 | 2026-06-06 | Ph.4 FileMgr 全 API 実装完了・Ph.3.5 補完工程（I-2/I-3）完了：①§4.4 FileMgr TID=4 を実装済みに更新、②§4.4.1 OS-START 実装済みマーク、③§10.1 Ph.1〜Ph.4・Ph.3.5 補完完了を明記・Ph.5 着手可を示す、④§11.1 ツールチェーン版数更新（emu23 v1.05・Force v1.5・hasm23 v1.02）、⑤付録 B 関連文書最新化（FileMgr 設計書 v1.9.5・memmap v1.6・emu23 v1.05 設計書・ビルド手順書 v1.5・ツール台帳 v1.0・I-3 負荷試験設計書 v1.3 追加） |

# **付録B: 関連文書**

| **文書** | **内容** |
| --- | --- |
| ISA2_3_v231.docx | YSD8800 ISA2.3 仕様書 v2.3.1 |
| emu23_device_design_v1_2.docx | emu23 デバイス設計書（YSD8001/8002/8003/8004） |
| emu23_v105_design_v1_0.md | emu23 v1.05 設計書（watermark 機能・EMU23-MOD-003）【v2.4追加】 |
| emu23_debug_manual_v1_1.docx | emu23 デバッグマニュアル v1.1（v1.05 対応）【v2.4更新】 |
| lnk23_design_v1_3.docx | lnk23 リンカ設計書 |
| YSD8800_MMU_Design_v1_1_0.docx | YSD8800 MMU 設計書 |
| YSD8800_ABI_spec.docx | YSD8800 ABI 仕様書 |
| yuios_memmap_design_v1_6.md | YUI OS メモリマップ設計書 **v1.6**（IRQ_WK_B 新設・Force ランタイム / MMIO 完全記載）【v2.4更新】 |
| yuios_ph4_filemgr_design_v1_9_5.md | Ph.4 フラットFS + FileMgr 詳細設計書 v1.9.5（Ph.4 総合試験 PASS・全 API 実装完了）【v2.4更新】 |
| yuios_ph3_5_i3_load_design_v1_3.md | Ph.3.5 I-3 負荷試験設計書 v1.3（V1〜V4 全項目 PASS 記録）【v2.4追加】 |
| yuios_build_procedure_v1_5.docx | ビルド手順書 v1.5（emu23 v1.05 対応・§4.10 watermark 節新設）【v2.4更新】 |
| tool_version_ledger_v1_0.md | ツールバージョン台帳 v1.0（新規）【v2.4追加】 |
| force_lnk23_build_report_v1_0.docx | Force/lnk23 ビルドレポート v1.0 |
| force_memory_contract_v1_2.md | Force コンパイラ メモリ使用契約書 v1.2（IRQ_WK_B 対応）【v2.4追加】 |
| kernel_forth v0.10.11 | YUI OS Forthカーネル層（Ph.4 FileMgr 全 API 実装済み）【v2.4更新】 |
| kernel_core v0.12.7 | YUI OS ASM カーネル層（A/B レジスタ復元修正済み）【v2.4追加】 |

	YSD8800 YUI OS Project