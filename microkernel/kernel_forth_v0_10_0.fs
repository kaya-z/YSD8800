\ kernel_forth.fs - YUI OS カーネル Forth 層
\ Version: 0.10.0   Ph.4 Step 4: FS-MOUNT 動作確認版
\ YSD8800 YUI OS Microkernel
\
\ ★★★ v0.10.0 追加点 (2026-05-23) ★★★
\ Ph.4 Step 4 (FS-MOUNT 単体動作確認) に必要な以下を v0.9.0 に追加:
\   1. FILEMGR-TASK 実装 (FILEMGR-INIT → 'M'/'m' 出力 → IPC4-RECV AGAIN ループ)
\   2. FILEMGR-START 実装 (TASK-CREATE で tid=4 起動)
\   3. OS-START から FILEMGR-START 呼出 (STOR-START の直後)
\
\ Step 4 期待出力: A BCP M  (M = FS-MOUNTED=1 確認)
\ 異常系 (未フォーマットディスク or ver不一致): A BCP m  (小文字 m)
\
\ 半製品マーカーの取扱い:
\   - 「★REVIEW★」「★TODO★」「★HOLE★」マーカー付き IMPL は Step 5 以降で対応
\   - 本版では FILE-DISPATCH 等の TODO 群は呼び出さず、IPC4-RECV で受信した
\     メッセージは黙って捨てて次の RECV に戻る (Step 5 で FILE-DISPATCH を実装)
\
\ 設計方針:
\   - IRQ0ハンドラ・コンテキストスイッチはアセンブラ（kernel.asm）
\   - 高レベルAPIはここで純粋Forthとして実装（移植性重視）
\   - ハードウェア依存部は CODE...END-CODE に隔離
\
\ v0.9.0-WIP: Ph.4 フラットFS + FileMgr 実装 (中断・半製品) (2026-05-21)
\       設計書: yuios_ph4_filemgr_design_v1_2.md (FIX 済)
\               yuios_memmap_design_v1_3.md     (FIX 済)
\               yuios_design_v2_3.md            (FIX 済)
\       前チャット: HANDOVER_CHAT26 → 本ファイル → HANDOVER_CHAT27
\       追加内容 (現時点で骨格コード化のみ・動作未検証):
\         - FileMgr 専用定数群 ($4800系、エラーコード $FE00台、OP コード $0201..$0208)
\         - 補助ワード: MAGIC-CHECK / NAME-LEN / NAME-EQ? / FID-VALID?
\                       MEMCPY-B / MEMSET-B / SLOT-ADDR / DE-ADDR
\         - STOR I/O ヘルパ: STOR-READ-1 / STOR-WRITE-1
\         - SBブロック操作: SB-LOAD / SB-STORE
\         - ディレクトリ: DIR-LOAD / DIR-STORE / DIR-FIND / DIR-FIND-FREE
\         - FS-MOUNT / FILEMGR-INIT
\         - FILE-REORDER-MSG / REPLY-OK
\         - FILE-OPEN-IMPL / FILE-CLOSE-IMPL (半製品)
\         - FILE-SEEK-IMPL / FILE-STAT-IMPL / FILE-LIST-IMPL (半製品)
\         - FILE-READ-IMPL (複雑・特に要再検証)
\       未着手 (HANDOVER_CHAT27 で対応):
\         - FILE-WRITE-IMPL / FILE-DELETE-IMPL
\         - FILE-DISPATCH / FILEMGR-TASK / FILEMGR-START
\         - FILEMGR-TEST-TASK / FILEMGR-TEST-START
\         - mkfs_yuifs.py
\       OS-START 修正 (HANDOVER_CHAT26 案B採用):
\         - UART-TEST tid: 旧4 → 5  (FileMgr=4 と衝突回避)
\         - STOR-TEST tid: 旧5 → 6  (FileMgr=4, ProcMgr=5 と衝突回避)
\         - FILEMGR-START 追加 (tid=4)
\         - FILEMGR-TEST-START 追加 (tid=7) ※未実装のためコメントアウト中
\       期待最終出力: ABCXD P Q
\
\ v0.8.5: Ph.3.5 実装フェーズ Step 6 — IPC4 Pool 方式の実装
\       2026-05-17 デバッグ完了: STOR-DISPATCH READ分岐SWAP削除（dst/LBA逆転修正）
\       設計書: yuios_ipc4_pool_design_v1_2.md
\       方針:
\       - Forth コード変更なし（API 完全互換 §7.2）
\       - アセンブラ側で IPC4_SEND/RECV/CALL を全面書き換え
\       工程: Ph.3.5-I-1 Step 6（HANDOVER_CHAT23.docx §4.3）
\
\ v0.8.4: Ph.3.5 実装フェーズ Step 5 — stack guard 領域の初期化
\       設計書: yuios_memmap_design_v1_1.md §4.1・§7.1・§7.4
\       方針:
\       - GUARD-BASE=$FC00, GUARD-SIZE=$40 CONSTANT 新設
\         (CHK-GUARD ワード実装（Step 8）で使用)
\       - _kstart での guard 初期化はアセンブラ側で実施（kernel.asm v0.12.4）
\       工程: Ph.3.5-I-1 Step 5（HANDOVER_CHAT23.docx §4.3）
\
\ v0.8.3: Ph.3.5 実装フェーズ Step 4 — KERN_SP 専用化
\       設計書: yuios_memmap_design_v1_1.md §4.1・§6.3・§7.1
\       方針:
\       - Forth 側の CONSTANT 追加: KERN-SP-TOP=$477E, KERN-SP-BASE=$4700
\       - コード変更なし（SP切替はアセンブラ側）
\       工程: Ph.3.5-I-1 Step 4（HANDOVER_CHAT23.docx §4.3）
\
\ v0.8.2: Ph.3.5 実装フェーズ Step 3 — タスクスタック完全分離
\       設計書: yuios_memmap_design_v1_1.md §6.4（スタック完全分離設計）
\       方針:
\       - CALLSTK-BASE: $FBCE → $F07F（tid=0 コールスタック頂上）
\       - DATASTK-BASE: $FB4E → $F87F（tid=0 データスタック頂上）
\       - TASK-STK-GAP: $0100 → $0080（1タスクあたり128B）
\       - コール領域 $F000-$F7FF とデータ領域 $F800-$FBFF が物理完全分離
\       工程: Ph.3.5-I-1 Step 3（HANDOVER_CHAT23.docx §4.3）
\
\ v0.8.1: Ph.3.5 実装フェーズ Step 2 — TCB 16タスク化
\       設計書: yuios_tcb_design_v1_2.md §4（MAX_TASKS=16拡張）
\       方針:
\       - TCB-POOL コメント: $4000-$427F(8×80B) → $4000-$44FF(16×80B=1280B)
\       - MAX-TASKS CONSTANT 新設（16）
\       - Forthコード内「8タスク」記述を更新
\       - TCBオフセット定数 TCB-A(8) 等は変更しない
\       工程: Ph.3.5-I-1 Step 2（HANDOVER_CHAT23.docx §4.3）
\
\ v0.8.0: Ph.3.5 実装フェーズ Step 1 — メモリマップアドレス定数の更新
\       設計書: yuios_memmap_design_v1_1.md（FIX 版）
\       方針:
\       - OS共有変数: $F0xx → $FCxx (OS共有変数領域 $FC40-$FC7F へ)
\         (タスクスタック領域 $F000-$FBFF の完全独立化)
\       - PAGE-BMP-LO/HI: $F010/$F012 → $FC40/$FC42
\       - MEM-TID-ADDR: $F014 → $FC44
\       - UART-RX-RING-BUF/HEAD/TAIL/COUNT/DRV-TID/WAIT-TID: $F020-$F038 → $FC46-$FC5E
\       - BC-STR: $F040 → $FC60
\       - STOR-DRV-TID/WAIT-TID/LAST-STAT: $F050/$F052/$F054 → $FC64/$FC66/$FC68
\       - TEST-SRC-BUF/DST-BUF: $E800/$EA00 → $EC00/$EE00
\       - カーネルワーク領域参照（インラインASM）: $42xx → $47xx
\       注意:
\       - $F000 CONSTANT PAGE-BMP-HI-INIT は実アドレスでなく値（変更しない）
\       - DATASTK-BASE 等スタック関係の変更は Step 3 で対応
\       - MAX-TASKS / TCB プール末尾の変更は Step 2 で対応
\       工程: Ph.3.5-I-1 Step 1（HANDOVER_CHAT23.docx §4.3 / §9.1）
\
\ v0.7.2: スタック衝突修正 + STOR-TEST 暴走防止 (HANDOVER_CHAT22 / Ph.3 暫定版)
\       1. DATASTK-BASE を $F9CE → $FB4E へ変更（kernel_v11.asm v0.11.3 と整合）
\          理由: tid=N+2 のコール範囲と tid=N のデータ範囲が重なるため
\       2. STOR-TEST-TASK 末尾に BEGIN AGAIN 追加（タスク終了時の暴走防止）
\          各 EXIT パスを「失敗マーカ + BEGIN AGAIN」に変更
\          失敗箇所識別: F2 (S2=WRITE), F3 (S3=READ), F4 (S4=比較不一致)
\       注意: 本修正は8タスク維持の暫定版。→ v0.8.1 で16タスク化正式化済み。
\            IPC4 競合バグ: Ph.3.5 Step 6〜7 で根本解決予定。
\

\ 設計方針:
\   - IRQ0ハンドラ・コンテキストスイッチはアセンブラ（kernel.asm）
\   - 高レベルAPIはここで純粋Forthとして実装（移植性重視）
\   - ハードウェア依存部は CODE...END-CODE に隔離
\
\ v0.1: TASK-ID, TASK-PRINT-ID をForth化
\ v0.2: TASK-WAKEUP, TASK-CREATE, MSG-SEND, MSG-RECV をForth化
\ v0.3: ISA2.3 v2.2.1メモリマップ対応
\ v0.4: kernel.asm v0.8対応（YUI OS v2.0 Ph.1 IPC拡張）
\       TCBサイズ 64B→80B / IPC4ワード追加
\ v0.5: YUI OS v2.0 Ph.2 メモリマネージャ実装
\       - ページビットマップ管理（$E200/$E202）
\       - BMP-INIT / BMP-BIT-SET / BMP-BIT-CLR / BMP-BIT@ / BMP-FREE-COUNT
\       - FIT-START / FREE-PGNO VARIABLE（2PICK代替: Force v1.3未対応のため）
\       - ALLOC-FIT? / BMP-MARK-USED / MEM-ALLOC-PAGES / MEM-FREE-PAGES
\       - REORDER-MSG-3 / MEMMGR-DISPATCH / MEMMGR-TASK / MEMMGR-START
\       - デモタスク削除 → MEM-TEST-TASK に置き換え
\ v0.6: YUI OS v2.0 Ph.3-A5 UARTドライバ実装
\       - UART定数追加（UART-RX, IRQ-STAT, IRQ-MASK, RXバッファ変数）
\       - UART-PUTC-IMPL / UART-PUTS-IMPL / UART-GETC-IMPL
\       - UART-DISPATCH / UART-DRV-TASK / UART-START
\       - UART-TEST-TASK / UART-TEST-START
\       - OS-START: MEMMGR-START → UART-START → UART-TEST-START
\ v0.7: YUI OS v2.0 Ph.3-B ストレージドライバ実装
\       設計書: yuios_ph3_storage_design_v1_2.md (+ soudan3.txt 解釈A適用)
\       - YSD8003 MMIO定数 (SD-CMD/SD-STAT/SD-LBA-LO/SD-DATA/SD-IRQ-CTRL等)
\       - ストレージ変数 (STOR-DRV-TID/STOR-WAIT-TID/STOR-LAST-STAT)
\       - BC-STR を $E230 → $E260 へ移動 (kernel_v11.asm と整合)
\       - SELF-IPC-VALID? (STOR-LAST-STAT @ 0<>) - IR1解決
\       - TASK-WAIT-IPC ワード新設 (ドライバ自身を寝かす)
\       - STOR-INIT / STOR-DISPATCH / STOR-DRV-TASK / STOR-START
\       - STOR-READ-IMPL / STOR-WRITE-IMPL / STOR-STAT-IMPL
\       - STOR-TEST-TASK / STOR-TEST-START
\       - OS-START: MEMMGR → UART → STOR → UART-TEST → STOR-TEST
\       - 【★ 解釈A適用】 STOR-WAIT-TID = ドライバ自身のtid (旧設計のclient_tidは誤り)
\         wake_stor_waiter は state=5(WAIT_IPC)→READY 遷移
\         (旧 kernel_v11.asm wake_stor_waiter の state==6 は v0.11.1 で v=5 に修正)
\ v0.7.1: A/B案適用 - 変数領域 Forthコード衝突回避（B案で全面移動）
\       問題: v0.7 で Forthコード末尾が $D817 → $E795 に肥大化し、
\            $E200-$E795 のカーネル変数を Forthコードが上書きする問題発生
\       対処（B案全面移動）:
\       - PAGE-BMP-LO/HI を $E200/$E202 → $F010/$F012 へ移動
\       - MEM-TID-ADDR を $E204 → $F014 へ移動
\       - UART-RX-RING-BUF/HEAD/TAIL/COUNT/DRV-TID/WAIT-TID を $F020-$F038 へ移動
\       - BC-STR を $E260 → $F040 へ移動
\       - STOR-DRV-TID/WAIT-TID/LAST-STAT を $F050/$F052/$F054 へ移動
\       - TEST-SRC-BUF/DST-BUF を $E800/$EA00 へ移動
\         (Forthコード末尾$E795とスタック最低$F3CEの間)
\ v0.7.2: スタック衝突修正 + STOR-TEST 暴走防止 (HANDOVER_CHAT22 / Ph.3 暫定版)
\       1. DATASTK-BASE を $F9CE → $FB4E へ変更（kernel_v11.asm v0.11.3 と整合）
\          理由: tid=N+2 のコール範囲と tid=N のデータ範囲が重なるため
\       2. STOR-TEST-TASK 末尾に BEGIN AGAIN 追加（タスク終了時の暴走防止）
\          各 EXIT パスを「失敗マーカ + BEGIN AGAIN」に変更
\          失敗箇所識別: F2 (S2=WRITE), F3 (S3=READ), F4 (S4=比較不一致)
\       注意: 本修正は8タスク維持の暫定版。→ v0.8.1 で16タスク化正式化済み。
\            IPC4 競合バグ（STOR-TEST F4停止）: Ph.3.5 Step 6〜7 で根本解決予定。

\ ============================================================
\ ハードウェア定数（移植時はここを変更）
\ ============================================================
$FC80 CONSTANT UART-TX
$FC82 CONSTANT UART-RX          \ v0.6: 受信データレジスタ追加
$FC84 CONSTANT UART-STAT
$FCB2 CONSTANT IRQ-STAT         \ v0.6: YSD8004 IRQ_STAT
$FCB4 CONSTANT IRQ-MASK         \ v0.6: YSD8004 IRQ_MASK

\ ============================================================
\ UART受信リングバッファ変数アドレス v0.8.0: $F020-$F038 → $FC46-$FC5E
\   v0.6: 新設 → v0.7.1: $F020-$F038 → v0.8.0: $FC46-$FC5E
\   理由: タスクスタック領域 $F000-$FBFF を完全独立化
\        OS共有変数領域 $FC40-$FC7F に集約 (memmap v1.1 §5.2)
\ yuios_ph3_uart_design_v1_2.docx §2.2 (要 v1.3 改版・Ph.3.5完了時に一括対応)
\ ============================================================
$FC46 CONSTANT UART-RX-RING-BUF \ 16Bリングバッファ本体 v0.8.0: $F020→$FC46
$FC56 CONSTANT UART-RX-HEAD     \ 書き込み位置（IRQハンドラが進める） v0.8.0: $F030→$FC56
$FC58 CONSTANT UART-RX-TAIL     \ 読み出し位置（ドライバが進める）   v0.8.0: $F032→$FC58
$FC5A CONSTANT UART-RX-COUNT    \ バッファ内バイト数（0-16）         v0.8.0: $F034→$FC5A
$FC5C CONSTANT UART-DRV-TID     \ UARTドライバタスクID格納アドレス   v0.8.0: $F036→$FC5C
$FC5E CONSTANT UART-WAIT-TID    \ UART_GETC待ちクライアントtid       v0.8.0: $F038→$FC5E

\ ============================================================
\ YSD8003 ストレージ MMIO（v0.7追加）
\ emu23_device_design_v1_2.docx §6
\ emu23_v103_design_v1_4.md §3
\ ============================================================
$FCA0 CONSTANT SD-CMD           \ 0=READ_SETUP 1=WRITE_SETUP 2=EXEC
$FCA2 CONSTANT SD-STAT          \ bit0=BUSY bit1=ERROR bit2=READY
$FCA4 CONSTANT SD-LBA-LO        \ LBA下位16bit
$FCA6 CONSTANT SD-LBA-HI        \ LBA上位16bit
$FCA8 CONSTANT SD-BUF-PTR       \ バッファポインタ(0-511)
$FCAA CONSTANT SD-DATA          \ PIOデータ(8bit)・自動BUF_PTR++
$FCAC CONSTANT SD-IRQ-CTRL      \ bit0=IRQ_EN bit1=ERR_EN
$FCAE CONSTANT SD-DISK-LO       \ 総セクタ数下位
$FCB0 CONSTANT SD-DISK-HI       \ 総セクタ数上位

\ ============================================================
\ ストレージ専用変数アドレス v0.8.0: $F050-$F054 → $FC64-$FC68
\   v0.7: $E230 → v0.7.1: $F050 → v0.8.0: $FC64 (OS共有変数領域)
\ yuios_ph3_storage_design_v1_2.md §2.2 (要 v1.3 改版・Ph.3.5完了時に一括対応)
\ ============================================================
$FC64 CONSTANT STOR-DRV-TID     \ ストレージドライバtid格納アドレス v0.8.0: $F050→$FC64
$FC66 CONSTANT STOR-WAIT-TID    \ EXEC完了待ちtid                  v0.8.0: $F052→$FC66
                                \ ★ 解釈A: ドライバ自身のtidが入る
$FC68 CONSTANT STOR-LAST-STAT   \ 最終SD_STAT値兼IRQ完了通知シグナル v0.8.0: $F054→$FC68
                                \ EXEC前0クリア・IRQ後に必ず非0(READY/ERROR)

\ ============================================================
\ ストレージ IPC4 op番号（v0.7追加）
\ yuios_ph3_storage_design_v1_2.md §6.1
\ ============================================================
$0501 CONSTANT STOR-READ-OP
$0502 CONSTANT STOR-WRITE-OP
$0503 CONSTANT STOR-STAT-OP

\ ============================================================
\ ストレージテスト用バッファ v0.8.0: $E800/$EA00 → $EC00/$EE00
\   v0.7.1: $E800/$EA00 → v0.8.0: $EC00/$EE00 (テスト領域 $EC00-$EFFF)
\   memmap v1.1 §5.4
\ ============================================================
$EC00 CONSTANT TEST-SRC-BUF     \ 512B 書き込み元 v0.8.0: $E800→$EC00
$EE00 CONSTANT TEST-DST-BUF     \ 512B 読み出し先 v0.8.0: $EA00→$EE00

\ ============================================================
\ UART IPC4 op番号（v0.6追加）
\ yuios_design_v2_0.docx §6.2 と整合
\ ============================================================
$0401 CONSTANT UART-PUTC-OP
$0402 CONSTANT UART-GETC-OP
$0403 CONSTANT UART-PUTS-OP

\ ============================================================
\ FileMgr 定数 (v0.9.0新設)
\ yuios_ph4_filemgr_design_v1_2.md §4.1 / §5.2 / §5.5
\ ★この節は確定済み・机上検証不要
\ ============================================================

\ --- FileMgr 専用変数 ($4800系、memmap v1.3 カーネル成長予約領域) ---
$4800 CONSTANT FILEMGR-TID-ADDR  \ FileMgr タスク ID 格納 (=4)
$4802 CONSTANT FS-MOUNTED        \ FS マウント状態 (0=未, 1=済)
$4804 CONSTANT FS-NEXT-FREE      \ next_free_sec キャッシュ
$4806 CONSTANT FS-FILE-COUNT     \ file_count キャッシュ
$4808 CONSTANT FS-TOTAL-SEC      \ total_sectors キャッシュ
$480A CONSTANT FS-WR-OLD-NEXT    \ FILE_WRITE ロールバック退避 (old_next_free)
$480C CONSTANT FS-WR-OLD-COUNT   \ FILE_WRITE ロールバック退避 (old_file_count)
$480E CONSTANT FS-FSVER          \ FSバージョン (上位=major 下位=minor)
$4820 CONSTANT FS-OPENTAB        \ オープンファイルテーブル (16B × 4スロット = 64B)
$4860 CONSTANT FS-SECBUF         \ 汎用セクタバッファ (512B)
$4A60 CONSTANT FS-DIRBUF         \ ディレクトリキャッシュ (1536B = 3セクタ)

\ --- FS レイアウト定数 (§5.5) ---
1     CONSTANT FS-DIR-START      \ ディレクトリ領域開始 LBA
3     CONSTANT FS-DIR-SECTORS    \ ディレクトリ領域セクタ数
32    CONSTANT FS-DIR-ENTRIES    \ ディレクトリエントリ総数
4     CONSTANT FS-DATA-START     \ データ領域開始 LBA
48    CONSTANT FS-DE-SIZE        \ ディレクトリエントリサイズ (B)
512   CONSTANT FS-SECSIZE        \ セクタサイズ (B)

\ --- ディレクトリエントリ内オフセット (§3.4) ---
0     CONSTANT DE-NAME           \ name (16B)
16    CONSTANT DE-SIZE           \ size (4B, u32, ただし下位16bitのみ運用)
20    CONSTANT DE-START-SEC      \ start_sec (2B)
22    CONSTANT DE-SEC-COUNT      \ sec_count (2B)
24    CONSTANT DE-FLAGS          \ flags (2B)
1     CONSTANT FLG-USED          \ flags bit0: 1=使用中

\ --- FILE_xxx OP コード (§4.1) ---
$0201 CONSTANT FILE-OPEN-OP
$0202 CONSTANT FILE-CLOSE-OP
$0203 CONSTANT FILE-READ-OP
$0204 CONSTANT FILE-WRITE-OP
$0205 CONSTANT FILE-SEEK-OP
$0206 CONSTANT FILE-STAT-OP
$0207 CONSTANT FILE-LIST-OP
$0208 CONSTANT FILE-DELETE-OP

\ --- エラーコード (§4.2、FS系 $FE00台) ---
$0000 CONSTANT E-OK
$FE01 CONSTANT E-NOENT           \ ファイル不存在
$FE02 CONSTANT E-NOSPC           \ ディスク空き容量不足
$FE03 CONSTANT E-MFILE           \ オープン数上限超過
$FE04 CONSTANT E-BADF            \ 不正な fid
$FE05 CONSTANT E-NAMETOOLONG     \ ファイル名 15 文字超
$FE06 CONSTANT E-EXIST           \ 同名ファイル既存
$FE07 CONSTANT E-NODIRSPC        \ ディレクトリエントリ空きなし
$FE08 CONSTANT E-IOERR           \ ストレージ I/O エラー
$FE09 CONSTANT E-INVAL           \ 引数不正
$FE0A CONSTANT E-FSVER           \ FS ver_major 不一致
$FE0B CONSTANT E-BUSY            \ open 中削除不可

\ --- オープンファイルテーブル スロット内オフセット (§5.3) ---
0     CONSTANT OT-USED           \ 1=使用中, 0=空き
2     CONSTANT OT-DIR-INDEX      \ DEインデックス
4     CONSTANT OT-START-SEC      \ ファイル先頭LBA
6     CONSTANT OT-SIZE           \ サイズ (4B、下位2Bを運用)
10    CONSTANT OT-POS            \ 論理オフセット (4B、下位2Bを運用)
16    CONSTANT OT-SLOT-SIZE      \ 1スロット 16B
4     CONSTANT FS-MAX-OPEN       \ 同時オープン上限

\ --- FILE_STAT 戻りバッファのオフセット (§4.3.5) ---
\ stat_buf レイアウト: +0=size(4B) +4=start_sec(2B) +6=sec_count(2B) +8=flags(2B) +10..(予約)

\ --- FileMgr テスト用バッファ (§8.3) ---
\ ★注意: $EC00/$EE00 は STOR-TEST と共有。FileMgr-TEST 実装時は時分割共用とする
$EC00 CONSTANT FT-NAME-BUF       \ テスト用ファイル名 "hello.txt"
$EC10 CONSTANT FT-SRC-BUF        \ 書き込みデータ (1セクタ未満)
$EE00 CONSTANT FT-DST-BUF        \ 読み出し先 (FILE_READ の dst)
$EF00 CONSTANT FT-STAT-BUF       \ FILE_STAT 結果

\ ============================================================
\ TCB定数（v0.4: 80Bレイアウト対応）
\ ============================================================
$4000 CONSTANT TCB-POOL     \ TCBプール先頭（$4000-$44FF: 16×80B=1280B） v0.8.1: 8→16タスク
80    CONSTANT TCB-SIZE
16    CONSTANT MAX-TASKS     \ v0.8.1新設: MAX_TASKS=16 (yuios_tcb_design_v1_2.md §4)
$F07E CONSTANT CALLSTK-BASE \ tid=0 コールスタック頂上 v0.8.2: $FBCE→$F07E (偶数化)
                            \ CALLSTK_TOP(tid) = $F07E + tid×$80 (tid SHL 7)
                            \ コール領域: $F000-$F7FF（16タスク×128B、実効126B）
$F87E CONSTANT DATASTK-BASE \ tid=0 データスタック頂上 v0.8.2: $FB4E→$F87E (偶数化)
                            \ DATASTK_TOP(tid) = $F87E + tid×$80 (tid SHL 7)
                            \ データ領域: $F800-$FBFF（16タスク×128B、実効126B）
$0080 CONSTANT TASK-STK-GAP \ タスク間スタック間隔 v0.8.2: $0100→$0080 (128B)

\ TCBオフセット（バイト）
0  CONSTANT TCB-STATE
2  CONSTANT TCB-PC
4  CONSTANT TCB-SP
6  CONSTANT TCB-DSP
8  CONSTANT TCB-A
12 CONSTANT TCB-FLAGS
16 CONSTANT TCB-IPC-MSG0   \ ipc_msg[0] opcode
18 CONSTANT TCB-IPC-MSG1   \ ipc_msg[1] arg0
20 CONSTANT TCB-IPC-MSG2   \ ipc_msg[2] arg1
22 CONSTANT TCB-IPC-MSG3   \ ipc_msg[3] arg2/result
24 CONSTANT TCB-IPC-VALID
26 CONSTANT TCB-IPC-SENDER

\ タスク状態定数
0 CONSTANT TASK-DEAD
1 CONSTANT TASK-READY
2 CONSTANT TASK-RUNNING
3 CONSTANT TASK-SLEEPING
4 CONSTANT TASK-WAIT-MSG
5 CONSTANT TASK-WAIT-IPC
6 CONSTANT TASK-WAIT-REPLY

\ カーネルワーク変数 v0.8.0: $4292→$4792 (frequently used 領域)
$4792 CONSTANT CUR-TASK-ADDR

\ KERN_SP 専用領域定数 v0.8.3新設 (yuios_memmap_design_v1_1.md §6.3)
$477E CONSTANT KERN-SP-TOP    \ カーネルスタック頂上（偶数）
$4700 CONSTANT KERN-SP-BASE   \ カーネルスタック底（canary $A55A 設置先）

\ stack guard 領域定数 v0.8.4新設 (yuios_memmap_design_v1_1.md §7.1・§7.4)
$FC00 CONSTANT GUARD-BASE     \ stack guard 領域先頭 ($FC00-$FC3F, 64B)
$0040 CONSTANT GUARD-SIZE     \ stack guard サイズ (64B = 32ワード)
$A55A CONSTANT GUARD-PATTERN  \ guard 初期値・検出パターン

\ ============================================================
\ MemMgr 定数 v0.8.0: $F010-$F014 → $FC40-$FC44 (OS共有変数領域)
\   v0.5: $E200/$E202/$E204 → v0.7.1: $F010/$F012/$F014 → v0.8.0: $FC40/$FC42/$FC44
\ ============================================================
$FC40 CONSTANT PAGE-BMP-LO      \ ビットマップ下位ワード（page 0-15）  v0.8.0: $F010→$FC40
$FC42 CONSTANT PAGE-BMP-HI      \ ビットマップ上位ワード（page 16-31） v0.8.0: $F012→$FC42
$FC44 CONSTANT MEM-TID-ADDR     \ MemMgr tid 格納アドレス             v0.8.0: $F014→$FC44
$C000 CONSTANT PAGE-POOL-BASE   \ ページプール先頭
32    CONSTANT PAGE-TOTAL        \ 総ページ数
28    CONSTANT PAGE-USER-MAX     \ ユーザ用ページ数（OS予約4ページ除く）
$F000 CONSTANT PAGE-BMP-HI-INIT \ HI初期値（page28-31=bit12-15=1）
                                \ ★この値はビットマップ値であって実アドレスでない（v0.8.0でも変更しない）
$0101 CONSTANT MEM-ALLOC-OP
$0102 CONSTANT MEM-FREE-OP
$0103 CONSTANT MEM-QUERY-OP

\ ============================================================
\ MemMgr 作業変数（v0.5追加）
\ Force v1.3 が 2PICK に未対応のため VARIABLE で代替
\ Force がカーネル変数領域に自動配置する
\ 注意: v0.8.0以降は OS共有変数領域（$FC40-$FC7F）以降に配置されることを確認
\       (旧 $F016 以降の前提は v0.8.0 で改められた)
\ ============================================================
VARIABLE FIT-START   \ ALLOC-FIT? / BMP-MARK-USED 用: start を退避
VARIABLE FREE-PGNO   \ MEM-FREE-PAGES 用: page_no を退避

\ ============================================================
\ アーキテクチャ層 CODE...END-CODE ブリッジ
\ ============================================================

CODE DI-OP
    DI
END-CODE
CODE EI-OP
    EI
END-CODE

CODE KERN-TASK-SLEEP
    JSR $01C0
END-CODE
CODE KERN-TASK-EXIT
    JSR $0460
END-CODE
CODE KERN-TASK-CREATE
    JSR $0520
END-CODE
CODE KERN-TASK-WAKEUP-ASM
    JSR $0380
END-CODE

\ IPC4 低レベルブリッジ
\ IPC4-SEND-ASM  ( msg3 msg2 msg1 msg0 tid -- )
CODE IPC4-SEND-ASM
    JSR $0740
END-CODE
\ IPC4-RECV-ASM  ( -- msg3 msg2 msg1 msg0 )
CODE IPC4-RECV-ASM
    JSR $07E0
END-CODE
\ IPC4-CALL-ASM  ( msg3 msg2 msg1 msg0 tid -- )
CODE IPC4-CALL-ASM
    JSR $08C0
END-CODE
\ IPC4-REPLY-ASM  ( r3 r2 r1 r0 tid -- )
CODE IPC4-REPLY-ASM
    JSR $0B00
END-CODE

\ ============================================================
\ TCB操作プリミティブ
\ ============================================================

\ TCBアドレス計算: tid → TCBアドレス
\ v0.4: tid*80 = (tid<<6) + (tid<<4)
: TCB-ADDR  ( tid -- addr )
    DUP  6 LSHIFT
    SWAP 4 LSHIFT
    +
    TCB-POOL + ;

: TCB-@  ( tid off -- val )  SWAP TCB-ADDR + @ ;
: TCB-!  ( val tid off -- )  SWAP TCB-ADDR + ! ;

: TCB-STATE@  ( tid -- state )  TCB-STATE TCB-@ ;
: TCB-STATE!  ( state tid -- )  TCB-STATE TCB-! ;

: TCB-IPC-VALID@   ( tid -- valid )   TCB-IPC-VALID  TCB-@ ;
: TCB-IPC-SENDER@  ( tid -- sender )  TCB-IPC-SENDER TCB-@ ;
: TCB-IPC-MSG0@    ( tid -- val )     TCB-IPC-MSG0   TCB-@ ;
: TCB-IPC-MSG1@    ( tid -- val )     TCB-IPC-MSG1   TCB-@ ;
: TCB-IPC-MSG2@    ( tid -- val )     TCB-IPC-MSG2   TCB-@ ;
: TCB-IPC-MSG3@    ( tid -- val )     TCB-IPC-MSG3   TCB-@ ;

\ ============================================================
\ UART出力
\ ============================================================
: emit-char  ( c -- )
    BEGIN UART-STAT @ 0= INVERT UNTIL
    UART-TX ! ;

: emit-nl  ( -- )  10 emit-char ;

\ ============================================================
\ TASK-ID  ( -- tid )
\ ============================================================
: TASK-ID  ( -- tid )
    CUR-TASK-ADDR @ ;

\ ============================================================
\ TASK-PRINT-ID  ( -- )
\ ============================================================
: TASK-PRINT-ID  ( -- )
    84 emit-char
    TASK-ID 48 + emit-char
    emit-nl ;

\ ============================================================
\ TASK-WAKEUP  ( tid -- )
\ v0.4: SLEEPING(3) / WAIT-IPC(5) → READY
\ ============================================================
: TASK-WAKEUP  ( tid -- )
    DUP TCB-STATE@
    DUP TASK-SLEEPING =
    SWAP TASK-WAIT-IPC =
    OR
    IF
        TASK-READY SWAP TCB-STATE!
    ELSE
        DROP
    THEN ;

\ ============================================================
\ TASK-CREATE  ( entry -- tid )
\ ============================================================
: TASK-CREATE  ( entry -- tid )
    KERN-TASK-CREATE ;

\ ============================================================
\ TASK-EXIT  ( -- )
\ ============================================================
: TASK-EXIT  ( -- )
    KERN-TASK-EXIT ;

\ ============================================================
\ TASK-SLEEP  ( -- )
\ ============================================================
: TASK-SLEEP  ( -- )
    KERN-TASK-SLEEP ;

\ ============================================================
\ IPC4ワード（v0.4）
\ ============================================================
: IPC4-SEND  ( msg3 msg2 msg1 msg0 tid -- )
    IPC4-SEND-ASM ;

: IPC4-RECV  ( -- msg3 msg2 msg1 msg0 )
    IPC4-RECV-ASM ;

: IPC4-CALL  ( msg3 msg2 msg1 msg0 tid -- r3 r2 r1 r0 )
    IPC4-CALL-ASM ;

: IPC4-REPLY  ( r3 r2 r1 r0 tid -- )
    IPC4-REPLY-ASM ;

\ IPC4-SENDER-DIRECT: DSPを使わずにsender tidを直接取得
\ CUR_TASK($4792)→tid→TCB[$4000+tid*80+26]を読む  v0.8.0: $4292→$4792 等
\ スタック上のデータを破壊しない
CODE IPC4-SENDER-DIRECT  ( -- tid )
    DI                       ; IRQ競合防止（L1_WK_TMP/L1_WK_C共有）
    STW  X, [$4788]          ; DSP退避（IRQ_WK_X流用）   v0.8.0: $4288→$4788
    LDW  A, [$4792]          ; A = CUR_TASK              v0.8.0: $4292→$4792
    STW  A, [$4786]          ; L1_WK_TMP = tid           v0.8.0: $4286→$4786
    LDW  B, #6
    SHL  A, B                ; A = tid*64
    STW  A, [$4784]          ; L1_WK_C                   v0.8.0: $4284→$4784
    LDW  A, [$4786]          ; A = tid                   v0.8.0: $4286→$4786
    LDW  B, #4
    SHL  A, B                ; A = tid*16
    LDW  B, [$4784]          ; B = tid*64                v0.8.0: $4284→$4784
    ADD  A, B                ; A = tid*80
    LDW  B, #$4000
    ADD  A, B                ; A = TCB addr
    MOV  X, A                ; X = TCB addr
    LDW  A, [X + #26]        ; A = TCB[+26] = ipc_sender
    LDW  X, [$4788]          ; DSP復元                   v0.8.0: $4288→$4788
    SUBI X, #2
    STW  A, [X]              ; push tid
    EI
END-CODE

: IPC4-SENDER  ( -- tid )
    TASK-ID TCB-IPC-SENDER@ ;

\ ============================================================
\ v0.5: メモリマネージャ（MemMgr）実装
\ ============================================================

\ ============================================================
\ ビットマップ操作ワード
\ ============================================================

\ BMP-INIT  ( -- )
\ ページビットマップ初期化
\ page 0-15: 全空き（$0000）
\ page 16-27: 空き、page 28-31: OS予約（$F000）
: BMP-INIT  ( -- )
    0                PAGE-BMP-LO !
    PAGE-BMP-HI-INIT PAGE-BMP-HI ! ;

\ BMP-BIT-SET  ( page_no -- )
\ 指定ページを使用中（bit=1）にセット
: BMP-BIT-SET  ( page_no -- )
    DUP 16 <
    IF
        1 SWAP LSHIFT
        PAGE-BMP-LO @ OR
        PAGE-BMP-LO !
    ELSE
        16 -
        1 SWAP LSHIFT
        PAGE-BMP-HI @ OR
        PAGE-BMP-HI !
    THEN ;

\ BMP-BIT-CLR  ( page_no -- )
\ 指定ページを空き（bit=0）にクリア
: BMP-BIT-CLR  ( page_no -- )
    DUP 16 <
    IF
        1 SWAP LSHIFT INVERT
        PAGE-BMP-LO @ AND
        PAGE-BMP-LO !
    ELSE
        16 -
        1 SWAP LSHIFT INVERT
        PAGE-BMP-HI @ AND
        PAGE-BMP-HI !
    THEN ;

\ BMP-BIT@  ( page_no -- flag )
\ 指定ページのビット状態を返す（0=空き、0以外=使用中）
: BMP-BIT@  ( page_no -- flag )
    DUP 16 <
    IF
        1 SWAP LSHIFT
        PAGE-BMP-LO @ AND
    ELSE
        16 -
        1 SWAP LSHIFT
        PAGE-BMP-HI @ AND
    THEN
    0= INVERT ;

\ BMP-FREE-COUNT  ( -- n )
\ 空きページ数を返す（全32ページスキャン）
\ page_no をRスタックで管理し、データスタックには count のみを置く
\ Force v1.3: BEGIN/WHILE後のA残骸問題を回避。REPEAT後DUP DROPでcount→A確定
: BMP-FREE-COUNT  ( -- n )
    0 >R             \ R=page_no=0
    0                \ count（データスタック上）
    BEGIN R@ PAGE-TOTAL < WHILE
        R@ BMP-BIT@ 0=
        IF 1+ THEN   \ 空きなら count++
        R> 1+ >R     \ page_no++
    REPEAT
    R> DROP          \ page_noをRから捨てる
    DUP DROP ;       \ Force TOS=A残骸対策: count を A に確定してRET

\ ============================================================
\ ページ割り当て補助ワード
\ ============================================================

\ ALLOC-FIT?  ( start n -- flag )
\ start から n ページ全てが空きか確認する
\ -1=全空き（成功）、0=失敗
: ALLOC-FIT?  ( start n -- flag )
    OVER FIT-START !         \ start を変数に退避
    0                        \ start n i=0
    BEGIN DUP OVER < WHILE   \ i < n
        FIT-START @ OVER +   \ start n i (start+i)
        BMP-BIT@             \ start n i bit
        IF                   \ 使用中→失敗
            DROP DROP        \ n i 捨て
            0 EXIT
        THEN
        1+                   \ i++
    REPEAT
    DROP DROP -1 ;           \ n i 捨て、-1（成功）を返す

\ BMP-MARK-USED  ( start n -- )
\ start から n ページを使用中にマーク
: BMP-MARK-USED  ( start n -- )
    OVER FIT-START !         \ start を変数に退避
    0                        \ start n i=0
    BEGIN DUP OVER < WHILE   \ i < n
        FIT-START @ OVER +   \ start n i (start+i)
        BMP-BIT-SET
        1+
    REPEAT
    DROP DROP DROP ;         \ start n i 捨て

\ ============================================================
\ MEM-ALLOC-PAGES  ( n -- addr )
\ n 連続ページを First Fit で割り当て
\ 戻り値: 先頭アドレス（失敗=0）
: MEM-ALLOC-PAGES  ( n -- addr )
    DUP 0=              IF DROP 0 EXIT THEN
    DUP PAGE-USER-MAX > IF DROP 0 EXIT THEN

    DUP >R                        \ R=n
    PAGE-USER-MAX SWAP -          \ max_start = 28-n

    0                             \ max_start start=0
    BEGIN
        DUP OVER > INVERT WHILE   \ start <= max_start
        DUP R@ ALLOC-FIT?
        IF
            DUP R@ BMP-MARK-USED  \ 使用中マーク
            256 * PAGE-POOL-BASE + \ addr = $C000 + start*256
            SWAP DROP             \ max_start 捨て
            R> DROP EXIT          \ addr を返す
        THEN
        1+                        \ start++
    REPEAT
    DROP DROP R> DROP 0 ;         \ 失敗: 0

\ ============================================================
\ MEM-FREE-PAGES  ( addr n -- )
\ addr から n ページを解放
\ ============================================================
: MEM-FREE-PAGES  ( addr n -- )
    DUP 0= IF DROP DROP EXIT THEN

    OVER PAGE-POOL-BASE -         \ n (addr-$C000)
    DUP 0< IF
        DROP DROP EXIT
    THEN
    8 RSHIFT                      \ n page_no
    DUP 255 > IF DROP DROP EXIT THEN

    DUP PAGE-USER-MAX >= IF
        DROP DROP EXIT
    THEN

    OVER FREE-PGNO !              \ n を退避
    OVER                          \ n page_no page_no
    FREE-PGNO @ +                 \ n page_no (page_no+n)
    PAGE-USER-MAX > IF
        DROP DROP EXIT
    THEN

    FREE-PGNO !                   \ n → FREE-PGNO
    FREE-PGNO @ SWAP              \ page_no n
    FREE-PGNO !                   \ page_no を確定退避、n はスタック

    0                             \ n i=0
    BEGIN DUP OVER < WHILE        \ i < n
        FREE-PGNO @ OVER +        \ n i (page_no+i)
        BMP-BIT-CLR
        1+
    REPEAT
    DROP DROP ;

\ ============================================================
\ IPC4 メッセージ整列ワード
\ ============================================================

\ REORDER-MSG-3  ( msg3 msg2 msg1 msg0 -- op arg0 arg1 )
: REORDER-MSG-3  ( msg3 msg2 msg1 msg0 -- arg1 arg0 op )
    \ msg0=op, msg1=arg0, msg2=arg1, msg3=不使用
    \ msg3 を捨てるため >R して NIP的処理
    >R >R >R     \ R: msg2 msg1 msg0 退避
    DROP         \ msg3を捨てる
    R> R> R> ;   \ msg2(arg1) msg1(arg0) msg0(op) を順に戻す → TOS=op

\ ============================================================
\ MemMgr サーバタスク
\ ============================================================

\ MEMMGR-DISPATCH  ( op arg0 arg1 client_tid -- )
: MEMMGR-DISPATCH  ( arg1 arg0 op client_tid -- )
    \ REORDER-MSG-3 出力 arg1 arg0 op(TOS)
    \ + IPC4-SENDER で client_tid push: arg1 arg0 op client_tid(TOS)
    \ ※実際の呼び出しでは MEMMGR-TASK 側で処理
    >R                            \ R=client_tid → arg1 arg0 op(TOS)

    \ --- MEM_ALLOC ($0101) ---
    DUP MEM-ALLOC-OP = IF
        DROP                      \ op を捨てる → arg1 arg0(TOS=pages)
        SWAP DROP                 \ arg1 を捨てる → arg0=pages(TOS)
        MEM-ALLOC-PAGES           \ addr
        >R
        0 0 0
        R>                        \ r0=addr
        R> IPC4-REPLY
        EXIT
    THEN

    \ --- MEM_FREE ($0102) ---
    DUP MEM-FREE-OP = IF
        DROP                      \ op を捨てる → arg1(n) arg0(addr)(TOS)
        SWAP                      \ arg0(addr) arg1(n)(TOS) ← MEM-FREE-PAGES の引数順
        MEM-FREE-PAGES
        0 0 0 0 R> IPC4-REPLY
        EXIT
    THEN

    \ --- MEM_QUERY ($0103) ---
    MEM-QUERY-OP = IF
        DROP DROP                 \ arg1 arg0 を捨てる
        BMP-FREE-COUNT            \ count
        >R
        0 0 0
        R>                        \ r0=count
        R> IPC4-REPLY
        EXIT
    THEN

    DROP DROP
    0 0 0 0 R> IPC4-REPLY ;

\ MEMMGR-TASK  ( -- )
: MEMMGR-TASK  ( -- )
    BMP-INIT
    BEGIN
        IPC4-RECV                 \ ( -- msg3 msg2 msg1 msg0 )
        IPC4-SENDER-DIRECT >R     \ R=tid（DSP不使用で安全取得）
        REORDER-MSG-3             \ ( -- op arg0 arg1 )
        R>                        \ ( -- op arg0 arg1 tid )
        MEMMGR-DISPATCH
    AGAIN ;

\ MEMMGR-START  ( -- )
CODE MEMMGR-TASK-ADDR  ( -- addr )
    SUBI X, #2
    LDW  A, #WORD_MEMMGR_TASK
    STW  A, [X]
END-CODE

: MEMMGR-START  ( -- )
    MEMMGR-TASK-ADDR TASK-CREATE
    MEM-TID-ADDR ! ;

\ ============================================================
\ MEM-TEST-TASK  ( -- )
\ 期待出力: M → 8（空き28の下1桁） → A → R
\ ============================================================
: MEM-TEST-TASK  ( -- )
    BEGIN
        0 TCB-ADDR TCB-STATE + @
        TASK-WAIT-IPC =
    UNTIL

    77 emit-char emit-nl          \ 'M'

    \ (1) MEM_QUERY
    0 0 0 MEM-QUERY-OP
    MEM-TID-ADDR @ IPC4-CALL
    >R DROP DROP DROP R>          \ r0(count)を残しr3 r2 r1をDROP
    \ 10進2桁表示 (count < 100 を前提)
    0 SWAP                        \ tens=0 count
    BEGIN DUP 10 >= WHILE
        10 - SWAP 1+ SWAP
    REPEAT                        \ tens ones
    SWAP 48 + emit-char           \ 十の位
    48 + emit-char emit-nl        \ 一の位

    \ (2) MEM_ALLOC
    0 0 2 MEM-ALLOC-OP
    MEM-TID-ADDR @ IPC4-CALL
    >R DROP DROP DROP R>          \ r0(addr)を残しr3 r2 r1をDROP
    DUP 0= IF
        DROP 70 emit-char
    ELSE
        65 emit-char
    THEN
    emit-nl

    \ (3) MEM_FREE
    >R
    0 2 R> MEM-FREE-OP
    MEM-TID-ADDR @ IPC4-CALL
    DROP DROP DROP DROP
    82 emit-char emit-nl          \ 'R'

    TASK-EXIT ;

\ ============================================================
\ v0.6: UARTドライバ実装
\ yuios_ph3_uart_design_v1_2.docx §4-§7
\ ============================================================

\ ------------------------------------------------------------
\ UART-INIT  ( -- )
\ UARTドライバ起動時初期化（§4.2）
\ バッファ変数は_kstartで初期化済み。ここではデバイスフラグのみクリア。
\ 順序: デバイスフラグクリア（IRQ有効化の前に必ず実行）
\ ------------------------------------------------------------
: UART-INIT  ( -- )
    0 UART-WAIT-TID !       \ 待機tid=0（なし）— 念のためリセット
    \ デバイス残留フラグクリア（IRQ有効化の前に必ず実行）
    2 UART-STAT !           \ UART_STAT WTC: RX_READYクリア
    1 IRQ-STAT  !           \ IRQ_STAT WTC: bit0(UART RX)クリア
    \ IRQ_MASKはリセット値 bit0=0(RX許可) なので変更不要
    ;

\ ------------------------------------------------------------
\ UART-PUTC-IMPL  ( char -- )
\ 1バイト送信（TX_READYポーリング待ち → MMIO書込）
\ yuios_ph3_uart_design_v1_2.docx §6.3
\ 注意: TX_READYポーリングは必須（HWフロー制御なし≠同期不要）
\ ------------------------------------------------------------
: UART-PUTC-IMPL  ( char -- )
    BEGIN UART-STAT @ 1 AND UNTIL   \ TX_READY=1 待ち
    UART-TX ! ;                     \ 1バイト送信

\ ------------------------------------------------------------
\ UART-PUTS-IMPL  ( addr -- )
\ NUL終端文字列送信
\ yuios_ph3_uart_design_v1_2.docx §6.4
\ ------------------------------------------------------------
: UART-PUTS-IMPL  ( addr -- )
    BEGIN
        DUP C@                      \ 1バイト読出
        DUP 0= IF                   \ NUL検出
            DROP DROP EXIT
        THEN
        UART-PUTC-IMPL
        1+
    AGAIN ;

\ ------------------------------------------------------------
\ UART-RX-POP  ( -- byte )
\ リングバッファから1バイト取得（COUNT>0が前提）
\ DI/EI保護は呼び出し元(UART-GETC-IMPL)が担う
\ 更新順序: TAIL先 → COUNT後（逆順禁止）
\ yuios_ph3_uart_design_v1_2.docx §3.4
\ ------------------------------------------------------------
: UART-RX-POP  ( -- byte )
    UART-RX-TAIL @              \ tail_idx
    UART-RX-RING-BUF +          \ &buf[tail]
    C@                          \ byte
    UART-RX-TAIL @ 1+ 15 AND    \ (tail+1) mod 16
    UART-RX-TAIL !              \ TAIL更新（先）
    UART-RX-COUNT @ 1-
    UART-RX-COUNT ! ;           \ COUNT更新（後）

\ ------------------------------------------------------------
\ UART-GETC-IMPL  ( tid -- )
\ 1バイト受信。バッファ空なら待機、非空なら即REPLY
\ レース対策: DI中にWAIT-TID設定→COUNT再チェック
\ yuios_ph3_uart_design_v1_2.docx §6.5
\ ------------------------------------------------------------
: UART-GETC-IMPL  ( tid -- )
    DI-OP                           \ クリティカルセクション開始

    UART-RX-COUNT @ 0= IF
        \ --- バッファ空: 待機登録 ---
        DUP UART-WAIT-TID !         \ tid保存

        \ --- 再チェック（レース対策 §6.5.2）---
        UART-RX-COUNT @ 0= IF
            \ DI中なのでIRQは来ていない。安全にWAIT状態へ
            EI-OP
            DROP                    \ tid消費（REPLYしない）
            EXIT                    \ クライアントはWAIT-REPLY継続
        ELSE
            \ DI直前にIRQが走ってCOUNTが増えた（理論上は到達しない）
            0 UART-WAIT-TID !       \ 待機キャンセル
            \ 下に流れてpop & REPLY
        THEN
    THEN

    \ --- バッファ非空: 即REPLY ---
    \ スタック: tid (TOS)
    UART-RX-POP                     \ ( tid -- tid byte ) TOS=byte
    EI-OP
    \ IPC4-REPLY ( r3 r2 r1 r0 tid -- ): 底→TOS = r3 r2 r1 r0 tid
    \ byte→r0(TOS直下), tid→TOS
    \ RS(LIFO): 後積み→先出し。byteを後に積む→先に出る→r0位置へ
    SWAP                             \ ( tid byte -- byte tid ) TOS=tid
    >R                               \ R:tid (先積み),  stack: byte
    >R                               \ R:tid byte (後積み),  stack: (empty)
    0 0 0                            \ stack: 0(r3) 0(r2) 0(r1), TOS=0
    R>                               \ R:tid → pop byte(後積み先出し): 0 0 0 byte(r0)
    R>                               \ pop tid: 0 0 0 byte tid(TOS) ✓
    IPC4-REPLY ;

\ ------------------------------------------------------------
\ UART-DISPATCH  ( arg1 arg0 op tid -- )
\ op番号によりPUTC/PUTS/GETCに分岐
\ yuios_ph3_uart_design_v1_2.docx §4.4
\ ------------------------------------------------------------
: UART-DISPATCH  ( arg1 arg0 op tid -- )
    >R                              \ R: tid

    DUP UART-PUTC-OP = IF           \ op == $0401
        DROP                        \ op捨て
        SWAP DROP                   \ arg1捨て（TOS=arg0=char）
        UART-PUTC-IMPL              \ ( char -- )
        0 0 0 0 R> IPC4-REPLY
        EXIT
    THEN

    DUP UART-PUTS-OP = IF           \ op == $0403
        DROP
        SWAP DROP                   \ TOS=arg0=addr
        UART-PUTS-IMPL              \ ( addr -- )
        0 0 0 0 R> IPC4-REPLY
        EXIT
    THEN

    UART-GETC-OP = IF               \ op == $0402
        DROP DROP                   \ arg0/arg1不使用
        R> UART-GETC-IMPL           \ ( tid -- ) REPLY内部で実施
        EXIT
    THEN

    \ 未知op
    DROP DROP
    0 0 0 0 R> IPC4-REPLY ;

\ ------------------------------------------------------------
\ UART-DRV-TASK  ( -- )
\ UARTドライバメインタスク（§4.3パターン）
\ ------------------------------------------------------------
: UART-DRV-TASK  ( -- )
    UART-INIT
    BEGIN
        IPC4-RECV                   \ ( -- msg3 msg2 msg1 msg0 )
        DI-OP                       \ v0.7.3: race対策 - sender確定まで割込み禁止
        IPC4-SENDER-DIRECT >R       \ R: client_tid
        EI-OP                       \ v0.7.3: 割込み再許可
        REORDER-MSG-3               \ ( -- arg1 arg0 op )
        R>                          \ ( -- arg1 arg0 op tid )
        UART-DISPATCH
    AGAIN ;

\ ------------------------------------------------------------
\ UART-START  ( -- )
\ UARTドライバタスクを生成し、tidをUART-DRV-TIDに格納
\ MEMMGR-STARTの後、ユーザタスク作成より前に呼ぶこと
\ ------------------------------------------------------------
CODE UART-DRV-TASK-ADDR  ( -- addr )
    SUBI X, #2
    LDW  A, #WORD_UART_DRV_TASK
    STW  A, [X]
END-CODE

: UART-START  ( -- )
    UART-DRV-TASK-ADDR TASK-CREATE  \ ( -- tid )
    UART-DRV-TID ! ;                \ tidをUART-DRV-TIDに格納

\ ============================================================
\ v0.6: UARTテストタスク
\ 期待出力: ABCXD
\ yuios_ph3_uart_design_v1_2.docx §7
\ ============================================================

\ テスト用文字列 "BC\0" は kernel.asm v0.12.0 の $FC60 に配置
\ v0.7: $E230→$E260 → v0.7.1: $F040 → v0.8.0: $FC60（OS共有変数領域）
\ yuios_ph3_storage_design_v1_2.md §2.1
$FC60 CONSTANT BC-STR

: UART-TEST-TASK  ( -- )
    \ T1: PUTC 'A'($41)
    \ IPC4-CALL ( msg3 msg2 msg1 msg0 tid -- r3 r2 r1 r0 )
    \ msg0=op, msg1=arg0(char), msg2=arg1(unused), msg3=unused
    0 0 $41 UART-PUTC-OP  UART-DRV-TID @  IPC4-CALL
    DROP DROP DROP DROP

    \ T2: PUTS "BC"
    \ msg0=op, msg1=arg0(addr), msg2=arg1(unused), msg3=unused
    0 0 BC-STR UART-PUTS-OP  UART-DRV-TID @  IPC4-CALL
    DROP DROP DROP DROP

    \ T3-T4: GETC（バッファ空→ブロック、IRQで起床）
    0 0 0 UART-GETC-OP  UART-DRV-TID @  IPC4-CALL
    \ ( -- r3 r2 r1 r0 ) r0=受信文字
    SWAP DROP SWAP DROP SWAP DROP   \ r0のみ残す

    \ T5: 受信文字をエコーバック
    \ スタック: char (TOS) — GETCで受け取った文字
    \ msg0=op, msg1=arg0(char), msg2=0, msg3=0 の順に積む
    >R                               \ R:char, stack: empty
    0 0                              \ msg3=0, msg2=0
    R>                               \ msg3=0, msg2=0, msg1=char (TOS=char)
    UART-PUTC-OP                     \ msg0=UART-PUTC-OP
    UART-DRV-TID @                   \ tid
    IPC4-CALL
    DROP DROP DROP DROP

    \ T6: 完了マーカー 'D'($44)
    0 0 $44 UART-PUTC-OP  UART-DRV-TID @  IPC4-CALL
    DROP DROP DROP DROP

    BEGIN AGAIN ;                   \ 完了後は無限ループで停止待ち

CODE UART-TEST-TASK-ADDR  ( -- addr )
    SUBI X, #2
    LDW  A, #WORD_UART_TEST_TASK
    STW  A, [X]
END-CODE

: UART-TEST-START  ( -- )
    UART-TEST-TASK-ADDR TASK-CREATE
    DROP ;                          \ tidは不要なのでDROP

\ ============================================================
\ v0.7: ストレージドライバ実装
\ yuios_ph3_storage_design_v1_2.md (+ soudan3.txt 解釈A適用)
\ ============================================================

\ ------------------------------------------------------------
\ TASK-WAIT-IPC ワード（ドライバ自身を寝かす）v0.7新規
\ kernel_v11.asm $1100 の TASK_WAIT_IPC_ENTRY を呼び出す
\
\ ★ 解釈A: ドライバ自身が WAIT_IPC で寝る
\   IRQ1 の wake_stor_waiter から WAIT_IPC→READY で起こされる
\
\ ※ "TASK-WAIT-IPC" という名前は CONSTANT 5 と区別される
\   (CONSTANTはタスク状態定数、こちらはエントリワード)
\ ------------------------------------------------------------
CODE TASK-WAIT-IPC-ENTRY  ( -- )
    JSR $1100                       \ TASK_WAIT_IPC_ENTRY
END-CODE

\ ------------------------------------------------------------
\ SELF-IPC-VALID?  ( -- flag )  v0.7新規
\ STOR-LAST-STAT @ 0<> なら IRQ完了済（true）
\ yuios_ph3_storage_design_v1_2.md §5.5.2 / IR1解決
\ ------------------------------------------------------------
: SELF-IPC-VALID?  ( -- flag )
    STOR-LAST-STAT @ 0<> ;

\ ------------------------------------------------------------
\ STOR-INIT  ( -- )  v0.7新規
\ ドライバ初期化（STOR-DRV-TASK起動時に1回実施）
\ yuios_ph3_storage_design_v1_2.md §4.2
\ ------------------------------------------------------------
: STOR-INIT  ( -- )
    0 STOR-WAIT-TID !               \ 待機tid=0
    0 STOR-LAST-STAT !              \ ステータス初期化（シグナル兼用）
    0 SD-IRQ-CTRL !                 \ IRQ_CTRL 初期は無効
    \ YSD8004 IRQ_MASK の bit1 (STOR) を許可（=0）
    IRQ-MASK @ $FFFD AND IRQ-MASK ! ;

\ ------------------------------------------------------------
\ STOR-READ-IMPL  ( dst LBA tid -- )  v0.7新規
\ レビュー指摘 重大1/2/3/4 + review10 IR1/IR2 全反映版
\ ★ 解釈A適用: STOR-WAIT-TID にはドライバ自身のtid を入れる
\ yuios_ph3_storage_design_v1_2.md §4.4
\ ------------------------------------------------------------
: STOR-READ-IMPL  ( dst LBA tid -- )
    >R                              \ R: tid（client_tid）

    \ ★ G1: WAIT-TID ガード（重大1: BUSY返却）
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

    \ ★ G3': STOR-LAST-STAT クリア（IR2）
    \ IRQ完了通知シグナルとして使うため、EXEC前に必ず0クリア
    0 STOR-LAST-STAT !

    \ ★ G4: WAIT-TID 設定（IRQ より前に必ず）
    \ ★ 解釈A: ドライバ自身のtid を入れる（旧設計のR@=client_tidは誤り）
    TASK-ID STOR-WAIT-TID !

    \ G5: IRQ_CTRL 有効化（§4.7 冪等性ルール準拠）
    1 SD-IRQ-CTRL !

    \ G6: EXEC 発行（emu23 v1.03: 512cycle後にIRQ1発火予約）
    2 SD-CMD !

    \ ★★★ G7-G9: IRQレース対策（重大2）
    \ パターン: DI → STAT再チェック → 既に非0なら起床済→WAITスキップ → EI+WAIT
    DI-OP                           \ 割込禁止（短時間）

    \ ★ G8: 自TCBの完了状態を再チェック（STAT非0で判定）
    SELF-IPC-VALID? IF
        \ 既にIRQ完了済（STAT非0） → WAITしない
        EI-OP
    ELSE
        \ まだIRQ来ていない → WAIT-IPCで寝る
        \ TASK-WAIT-IPC内部でEIされる前提（_sched_common経由）
        TASK-WAIT-IPC-ENTRY               \ ドライバ自身が寝る → IRQから起こされる
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
    \ stack: dst
    \ BUF_PTR は EXEC 時に 0 にリセット済
    \ Force v1.2 は DO/LOOP 未対応のため BEGIN/WHILE/REPEAT で実装
    \
    \ ループ内で dst を pointer のように1ずつ進める方式:
    \   dst を残し、書込ごとに dst ← dst+1
    \   終了条件は count==0
    \ stack使用: TOS=count, 下=ptr
    \
    512                             \ stack: dst count=512
    BEGIN
        DUP 0 >
    WHILE
        \ stack: dst count
        SWAP                        \ stack: count dst
        SD-DATA @                   \ stack: count dst byte
        OVER C!                     \ dst[0] = byte (stack: count dst)
        1 +                         \ stack: count dst+1
        SWAP                        \ stack: dst+1 count
        1 -                         \ stack: dst+1 count-1
    REPEAT
    DROP                            \ count捨て
    DROP                            \ dst捨て (stack: empty)

    \ ★ R4: WAIT-TID 解放（最後）
    0 STOR-WAIT-TID !

    \ 成功応答 r0=0
    0 0 0 0 R> IPC4-REPLY ;

\ ------------------------------------------------------------
\ STOR-WRITE-IMPL  ( src LBA tid -- )  v0.7新規
\ ★ 解釈A適用: STOR-WAIT-TID にはドライバ自身のtid を入れる
\ yuios_ph3_storage_design_v1_2.md §4.5
\ ------------------------------------------------------------
: STOR-WRITE-IMPL  ( src LBA tid -- )
    >R                              \ R: tid（client_tid）

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

    \ ★ G3': STOR-LAST-STAT クリア（IR2）
    0 STOR-LAST-STAT !

    \ ★ W3-pre: src → SD_DATA 512B 転送（EXEC前）
    \ BUF_PTR は WRITE_SETUP では自動リセットされないため明示
    \ ★【KY5/IR4】 0 SD-BUF-PTR ! は絶対に忘れないこと
    \ Force v1.2 は DO/LOOP 未対応のため BEGIN/WHILE/REPEAT で実装
    0 SD-BUF-PTR !
    \ stack: src
    512                             \ stack: src count=512
    BEGIN
        DUP 0 >
    WHILE
        \ stack: src count
        SWAP                        \ stack: count src
        DUP C@                      \ stack: count src byte (下位8bit)
        SD-DATA !                   \ BUF_PTR自動++ (stack: count src)
        1 +                         \ stack: count src+1
        SWAP                        \ stack: src+1 count
        1 -                         \ stack: src+1 count-1
    REPEAT
    DROP                            \ count捨て
    \ stack: src+512 (進めたsrcポインタ、後でDROP)

    \ ★ G4: WAIT-TID 設定
    \ ★ 解釈A: ドライバ自身のtid を入れる
    TASK-ID STOR-WAIT-TID !

    \ G5: IRQ_CTRL 有効化
    1 SD-IRQ-CTRL !

    \ G6: EXEC 発行
    2 SD-CMD !

    \ ★ G7-G9: IRQレース対策（READと同じ）
    DI-OP
    SELF-IPC-VALID? IF
        EI-OP
    ELSE
        TASK-WAIT-IPC-ENTRY               \ ドライバ自身が寝る
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

\ ------------------------------------------------------------
\ STOR-STAT-IMPL  ( tid -- )  v0.7新規
\ IRQ待ちなしで即座に SD_STAT を返す
\ yuios_ph3_storage_design_v1_2.md §4.6
\ ------------------------------------------------------------
\ IPC4-REPLY ( r3 r2 r1 r0 tid -- )
\ msg0(r0)=stat, msg1=msg2=msg3=0 として REPLY する
: STOR-STAT-IMPL  ( tid -- )
    \ スタック: tid
    >R                              \ R: tid, stack: empty
    SD-STAT @                       \ stack: stat
    >R                              \ R: tid stat, stack: empty
    0 0 0                           \ stack: 0(r3) 0(r2) 0(r1)
    R>                              \ stack: 0 0 0 stat (TOS=stat=r0)
    R>                              \ stack: 0 0 0 stat tid (TOS=tid)
    IPC4-REPLY ;

\ ------------------------------------------------------------
\ STOR-DISPATCH  ( arg1 arg0 op tid -- )  v0.7新規
\ op番号によりREAD/WRITE/STATに分岐
\ yuios_ph3_storage_design_v1_2.md §4.3
\ ------------------------------------------------------------
: STOR-DISPATCH  ( arg1 arg0 op tid -- )
    >R                              \ R: tid

    DUP STOR-READ-OP = IF
        DROP                        \ op捨て
        \ v0.12.6: 余計なSWAPを削除（chatlog修正の再適用）
        \ DROP後 stack: arg1(dst) arg0(LBA), 底→TOS = dst LBA
        \ STOR-READ-IMPL ( dst LBA tid -- ) は底→TOS = dst LBA tid を要求
        \ R> で tid を戻せば dst LBA tid ✓（SWAP不要）
        R>                          \ stack: dst LBA tid
        STOR-READ-IMPL              \ 内部でIPC4-REPLY
        EXIT
    THEN

    DUP STOR-WRITE-OP = IF
        DROP
        \ stack: arg1(src) arg0(LBA), TOS=LBA
        R>                          \ stack: src LBA tid
        STOR-WRITE-IMPL
        EXIT
    THEN

    STOR-STAT-OP = IF
        DROP DROP                   \ arg0 arg1 捨て
        R> STOR-STAT-IMPL           \ ( tid -- ) でREPLY
        EXIT
    THEN

    \ 未知op
    DROP DROP                       \ arg0 arg1 捨て
    -1 0 0 0 R> IPC4-REPLY ;

\ ------------------------------------------------------------
\ STOR-DRV-TASK  ( -- )  v0.7新規
\ ストレージドライバメインタスク（§4.1パターン）
\ yuios_ph3_storage_design_v1_2.md §4.1
\ ------------------------------------------------------------
: STOR-DRV-TASK  ( -- )
    STOR-INIT
    BEGIN
        IPC4-RECV                   \ ( -- msg3 msg2 msg1 msg0 )
        DI-OP                       \ v0.7.3: race対策 - sender確定まで割込み禁止
        IPC4-SENDER-DIRECT >R       \ R: client_tid
        EI-OP                       \ v0.7.3: 割込み再許可
        REORDER-MSG-3               \ ( -- arg1 arg0 op )
        R>                          \ ( -- arg1 arg0 op tid )
        STOR-DISPATCH
    AGAIN ;

\ ------------------------------------------------------------
\ STOR-START  ( -- )  v0.7新規
\ ストレージドライバタスクを生成し、tidをSTOR-DRV-TIDに格納
\ UART-STARTの後、ユーザタスク作成より前に呼ぶこと
\ ------------------------------------------------------------
CODE STOR-DRV-TASK-ADDR  ( -- addr )
    SUBI X, #2
    LDW  A, #WORD_STOR_DRV_TASK
    STW  A, [X]
END-CODE

: STOR-START  ( -- )
    STOR-DRV-TASK-ADDR TASK-CREATE  \ ( -- tid )
    STOR-DRV-TID ! ;                \ tidをSTOR-DRV-TIDに格納

\ ============================================================
\ v0.7: ストレージテストタスク
\ 期待出力: ABCXD の後にスペース+'P'
\ yuios_ph3_storage_design_v1_2.md §7
\ ============================================================
: STOR-TEST-TASK  ( -- )
    \ S0: スペース出力（区切り）
    0 0 $20 UART-PUTC-OP UART-DRV-TID @ IPC4-CALL
    DROP DROP DROP DROP

    \ S1: src_buf にパターン書き込み（最初の8B: "STOR_TST"）
    $53 TEST-SRC-BUF       C!       \ 'S'
    $54 TEST-SRC-BUF 1 +   C!       \ 'T'
    $4F TEST-SRC-BUF 2 +   C!       \ 'O'
    $52 TEST-SRC-BUF 3 +   C!       \ 'R'
    $5F TEST-SRC-BUF 4 +   C!       \ '_'
    $54 TEST-SRC-BUF 5 +   C!       \ 'T'
    $53 TEST-SRC-BUF 6 +   C!       \ 'S'
    $54 TEST-SRC-BUF 7 +   C!       \ 'T'

    \ S2: STOR_WRITE LBA=0
    \ IPC4-CALL ( msg3 msg2 msg1 msg0 tid -- r3 r2 r1 r0 )
    \ msg2=arg1(src), msg1=arg0(LBA), msg0=op
    0 TEST-SRC-BUF 0 STOR-WRITE-OP STOR-DRV-TID @ IPC4-CALL
    >R DROP DROP DROP R>            \ r0のみ残す
    0= INVERT IF
        0 0 $46 UART-PUTC-OP UART-DRV-TID @ IPC4-CALL  \ 'F'
        DROP DROP DROP DROP
        $32 UART-PUTC-IMPL          \ v0.7.2: '2' = S2失敗
        BEGIN AGAIN                 \ v0.7.2: EXIT→暴走を回避
    THEN

    \ S3: STOR_READ LBA=0 → dst_buf
    0 TEST-DST-BUF 0 STOR-READ-OP STOR-DRV-TID @ IPC4-CALL
    >R DROP DROP DROP R>
    0= INVERT IF
        0 0 $46 UART-PUTC-OP UART-DRV-TID @ IPC4-CALL
        DROP DROP DROP DROP
        $33 UART-PUTC-IMPL          \ v0.7.2: '3' = S3失敗
        BEGIN AGAIN
    THEN

    \ S4: src と dst の最初の8B を比較
    \ Force v1.2 は DO/LOOP 未対応のため BEGIN/WHILE/REPEAT で実装
    \ stack使用: i (0..7)
    0
    BEGIN
        DUP 8 <
    WHILE
        \ stack: i
        DUP TEST-SRC-BUF + C@       \ stack: i src[i]
        OVER TEST-DST-BUF + C@      \ stack: i src[i] dst[i]
        <> IF
            DROP                    \ i捨て
            0 0 $46 UART-PUTC-OP UART-DRV-TID @ IPC4-CALL  \ 'F'
            DROP DROP DROP DROP
            $34 UART-PUTC-IMPL      \ v0.7.2: '4' = S4不一致
            BEGIN AGAIN
        THEN
        1 +
    REPEAT
    DROP                            \ i捨て

    \ S5: 全致 → 'P' 出力
    0 0 $50 UART-PUTC-OP UART-DRV-TID @ IPC4-CALL  \ 'P'
    DROP DROP DROP DROP
    BEGIN AGAIN ;                   \ v0.7.2: タスク終了暴走防止

CODE STOR-TEST-TASK-ADDR  ( -- addr )
    SUBI X, #2
    LDW  A, #WORD_STOR_TEST_TASK
    STW  A, [X]
END-CODE

: STOR-TEST-START  ( -- )
    STOR-TEST-TASK-ADDR TASK-CREATE
    DROP ;                          \ tidは不要なのでDROP

\ ============================================================
\ OS-START  ( -- )  v0.7: Ph.3-B対応メインエントリ
\ 起動順序: MEMMGR-START → UART-START → STOR-START → UART-TEST-START → STOR-TEST-START
\ その後ルートタスクは待機ループ
\ yuios_ph3_storage_design_v1_2.md §7.3
\ ============================================================
\ ------------------------------------------------------------
\ [HYP5-DIAG] PUTC-HEX1  ( nibble -- )  下位4bitをhex1桁で出力
\ ------------------------------------------------------------
: PUTC-HEX1  ( n -- )
    $0F AND
    DUP 10 < IF $30 + ELSE $37 + THEN
    UART-PUTC-IMPL ;

\ [HYP5-DIAG] PUTC-HEX4  ( w -- )  16bitをhex4桁で出力
: PUTC-HEX4  ( w -- )
    DUP 12 RSHIFT PUTC-HEX1
    DUP  8 RSHIFT PUTC-HEX1
    DUP  4 RSHIFT PUTC-HEX1
                  PUTC-HEX1 ;

\ [HYP5-DIAG] DIAG-STR-TID  ( -- )  STOR-DRV-TID を [STR=XXXX] 形式で出力
: DIAG-STR-TID  ( -- )
    $5B UART-PUTC-IMPL              \ '['
    $53 UART-PUTC-IMPL              \ 'S'
    $54 UART-PUTC-IMPL              \ 'T'
    $52 UART-PUTC-IMPL              \ 'R'
    $3D UART-PUTC-IMPL              \ '='
    STOR-DRV-TID @ PUTC-HEX4
    $5D UART-PUTC-IMPL              \ ']'
    ;

\ [HYP8-DIAG] DIAG-ALL-TIDS  ( -- )  全タスクtidを出力
: DIAG-ALL-TIDS  ( -- )
    $5B UART-PUTC-IMPL              \ '['
    $55 UART-PUTC-IMPL              \ 'U'
    $3D UART-PUTC-IMPL              \ '='
    UART-DRV-TID @ PUTC-HEX4
    $2C UART-PUTC-IMPL              \ ','
    $53 UART-PUTC-IMPL              \ 'S'
    $3D UART-PUTC-IMPL              \ '='
    STOR-DRV-TID @ PUTC-HEX4
    $5D UART-PUTC-IMPL              \ ']'
    ;

\ ====================================================================
\ ★★★ v0.9.0-WIP: Ph.4 FileMgr (半製品・机上検証必須) ★★★
\ ====================================================================
\ 設計書: yuios_ph4_filemgr_design_v1_2.md
\
\ 重要警告:
\   - 本ブロックは未検証コードを含みます。HANDOVER_CHAT27.md §4「再検証必須
\     ワード一覧」を必ず確認してください。
\   - 現状はビルドが通らない可能性があります (FILE-DISPATCH / FILEMGR-TASK
\     / FILEMGR-START / FILEMGR-TEST-TASK が未実装プレースホルダのため、
\     OS-START からの参照が解決しません)。
\   - 次回作業では:
\       1. ★REVIEW★ マーカー付きの半製品ワードを机上検証 → 必要に応じ再実装
\       2. ★TODO★ マーカー付きのワードを実装
\       3. ダミー FILEMGR-TASK でビルド可能性を先に確認 (案δ思想)
\       4. その後 IMPL を1つずつ追加
\
\ Force v1.2 制約 (HANDOVER_CHAT27 §5 で詳述):
\   - DO/LOOP 不使用 → BEGIN/WHILE/REPEAT のみ
\   - LOCALS 不使用、2PICK / ROLL 不使用
\   - R スタック多段重ね (3段以上) は事故りやすい → VARIABLE 代替推奨
\   - IPC4 スタック効果: ( msg3 msg2 msg1 msg0 tid -- r3 r2 r1 r0 )
\                       msg0/r0 が TOS
\
\ ====================================================================

\ --------------------------------------------------------------------
\ FileMgr ワーク変数 (Force が自動配置)
\ Force v1.2: 2PICK 未対応のため、ループ変数は VARIABLE で代替する
\ (MemMgr の FIT-START / FREE-PGNO と同じ流儀)
\ --------------------------------------------------------------------
VARIABLE FM-WK-DST          \ MEMCPY-B / MEMSET-B 用: dst 退避
VARIABLE FM-WK-SRC          \ MEMCPY-B 用: src 退避
VARIABLE FM-WK-LEN          \ MEMCPY-B / MEMSET-B 用: len 退避
VARIABLE FM-WK-VAL          \ MEMSET-B 用: 充填値退避
VARIABLE FM-WK-A            \ 汎用ワーク A
VARIABLE FM-WK-B            \ 汎用ワーク B
VARIABLE FM-WK-C            \ 汎用ワーク C

\ --------------------------------------------------------------------
\ 補助ワード群 (§6.6)
\ --------------------------------------------------------------------

\ MEMCPY-B  ( dst src len -- )                                ★REVIEW★
\ 副作用: dst[0..len-1] 書き換え、FM-WK-DST/SRC/LEN を破壊
\ 前提  : dst/src 領域が len バイト確保、重複なし
\ 検証点: R スタックでループカウンタを保持できているか
: MEMCPY-B  ( dst src len -- )
    FM-WK-LEN !
    FM-WK-SRC !
    FM-WK-DST !
    0 >R                                    \ R: i = 0
    BEGIN  R@ FM-WK-LEN @ <  WHILE
        FM-WK-SRC @ R@ + C@                 \ src[i]
        FM-WK-DST @ R@ + C!                 \ dst[i] = src[i]
        R> 1 + >R                           \ i++
    REPEAT
    R> DROP ;

\ MEMSET-B  ( dst val len -- )                                ★REVIEW★
\ 副作用: dst[0..len-1] 書き換え、FM-WK-DST/LEN/VAL を破壊
: MEMSET-B  ( dst val len -- )
    FM-WK-LEN !
    FM-WK-VAL !
    FM-WK-DST !
    0 >R                                    \ R: i = 0
    BEGIN  R@ FM-WK-LEN @ <  WHILE
        FM-WK-DST @ R@ +                    \ &dst[i]
        FM-WK-VAL @ SWAP C!                 \ dst[i] = val (下位1B)
        R> 1 + >R
    REPEAT
    R> DROP ;

\ NAME-LEN  ( name-addr -- len )                              ★REVIEW★
\ NULL終端文字列の長さ。最大16で打ち切り (15文字超なら 16 を返す)
\ 副作用: なし
: NAME-LEN  ( name-addr -- len )
    0 >R                                    \ R: i = 0
    BEGIN
        R@ 16 <                             \ i < 16
        OVER R@ + C@ 0= INVERT               \ かつ name[i] != 0
        AND
    WHILE
        R> 1 + >R
    REPEAT
    DROP                                    \ name-addr 捨てる
    R> ;                                    \ i を返す

\ NAME-EQ?  ( addr1 addr2 -- flag )                           ★REVIEW★
\ 16B 以内 NULL 終端文字列の一致判定 (両方が同位置で NULL なら eq)
\ 副作用: FM-WK-A/B/C/DST 破壊
\ 検証点: ループの「早期脱出」を done フラグで実現しているが、Force v1.2
\         で意図通り動くか確認。代替案として「最初の不一致で flag=0、
\         以降の比較もスキップ」する単純実装も検討
: NAME-EQ?  ( addr1 addr2 -- flag )
    FM-WK-A !                               \ FM-WK-A = addr2
    FM-WK-B !                               \ FM-WK-B = addr1
    1 FM-WK-C !                             \ FM-WK-C = 1 (eq候補)
    0 FM-WK-DST !                           \ FM-WK-DST = done flag
    0 >R                                    \ R: i = 0
    BEGIN  R@ 16 <  WHILE
        FM-WK-DST @ 0= IF                   \ 未確定の間だけ比較
            FM-WK-B @ R@ + C@                \ name1[i]
            FM-WK-A @ R@ + C@                \ name2[i]
            OVER OVER = IF
                DROP                         \ name2[i] 捨てる
                0= IF                        \ name1[i] == 0 ?
                    1 FM-WK-DST !            \ done (eq確定)
                THEN
            ELSE
                DROP DROP
                0 FM-WK-C !
                1 FM-WK-DST !                \ done (ne確定)
            THEN
        THEN
        R> 1 + >R
    REPEAT
    R> DROP
    FM-WK-C @ ;

\ MAGIC-CHECK  ( buf-addr -- flag )                           ★REVIEW★
\ buf 先頭 8B が "YUIFS\0\0\0" か照合
\ 副作用: なし
\ 検証点: 連続 IF...THEN の入れ子が Force v1.2 で正しくコンパイルされるか
\         (EXIT がネスト深い IF 内で正しく動くかは特に要確認)
: MAGIC-CHECK  ( buf-addr -- flag )
    DUP    C@ $59 = IF                      \ 'Y'
    DUP 1+ C@ $55 = IF                      \ 'U'
    DUP 2 + C@ $49 = IF                      \ 'I'
    DUP 3 + C@ $46 = IF                      \ 'F'
    DUP 4 + C@ $53 = IF                      \ 'S'
    DUP 5 + C@ 0  = IF
    DUP 6 + C@ 0  = IF
    DUP 7 + C@ 0  = IF
        DROP 1 EXIT                          \ 全一致
    THEN THEN THEN THEN THEN THEN THEN THEN
    DROP 0 ;                                 \ 不一致

\ FID-VALID?  ( fid -- flag )                                 ★REVIEW★
\ fid が 0〜3 (FS-MAX-OPEN-1) かつ used==1 か
\ 検証点: 0< / >= が Force v1.2 で使えるか確認。代替: 0 < / DUP < 等
: FID-VALID?  ( fid -- flag )
    DUP 0< IF DROP 0 EXIT THEN
    DUP FS-MAX-OPEN >= IF DROP 0 EXIT THEN
    OT-SLOT-SIZE *                           \ fid * 16
    FS-OPENTAB +                              \ slot addr
    OT-USED + @
    0= INVERT ;

\ SLOT-ADDR  ( fid -- slot-addr )
: SLOT-ADDR  ( fid -- addr )
    OT-SLOT-SIZE *  FS-OPENTAB + ;

\ DE-ADDR  ( index -- de-addr )
: DE-ADDR  ( index -- addr )
    FS-DE-SIZE *  FS-DIRBUF + ;

\ --------------------------------------------------------------------
\ STOR I/O ヘルパ
\ --------------------------------------------------------------------

\ STOR-READ-1  ( lba buf -- r0 )                              ★REVIEW★
\ 1セクタを STOR_READ。戻り値 r0 (0=OK, 非0=エラー) を返す。
\ 副作用: buf に 512B 書き込み。r1〜r3 は捨てる。
\ 検証点: IPC4-CALL スタック並び (msg3 msg2 msg1 msg0 tid) の組み立てが
\         正しいか。特に >R >R >R 0 R> R> R> の R スタック操作。
\         STOR-TEST-TASK の実装 (kernel_forth_v0_8_5.fs L1298 等) と
\         パターン比較すること:
\           0 TEST-SRC-BUF 0 STOR-WRITE-OP STOR-DRV-TID @ IPC4-CALL
\         これは ( msg3=0  msg2=buf  msg1=lba  msg0=op  tid ) で TOS=tid
\         そのまま並べれば良い → 本実装の R スタック退避は過剰の可能性
: STOR-READ-1  ( lba buf -- r0 )
    SWAP                                     \ ( buf lba )
    STOR-READ-OP                             \ ( buf lba op )
    >R >R >R 0 R> R> R>                       \ ( 0 buf lba op )
    STOR-DRV-TID @                            \ ( 0 buf lba op tid )
    IPC4-CALL                                 \ ( r3 r2 r1 r0 )
    >R DROP DROP DROP R> ;                    \ r0 のみ残す

\ STOR-WRITE-1  ( lba buf -- r0 )                             ★REVIEW★
: STOR-WRITE-1  ( lba buf -- r0 )
    SWAP                                     \ ( buf lba )
    STOR-WRITE-OP                            \ ( buf lba op )
    >R >R >R 0 R> R> R>                       \ ( 0 buf lba op )
    STOR-DRV-TID @
    IPC4-CALL
    >R DROP DROP DROP R> ;

\ --------------------------------------------------------------------
\ スーパーブロック操作
\ --------------------------------------------------------------------

\ SB-LOAD  ( -- r0 )  LBA=0 を FS-SECBUF に読み込む
: SB-LOAD  ( -- r0 )
    0 FS-SECBUF STOR-READ-1 ;

\ SB-STORE  ( -- r0 )  FS-SECBUF を LBA=0 へ書き戻し
: SB-STORE  ( -- r0 )
    0 FS-SECBUF STOR-WRITE-1 ;

\ --------------------------------------------------------------------
\ ディレクトリ操作 (§5.6)
\ --------------------------------------------------------------------

\ DIR-LOAD  ( -- r0 )                                         ★REVIEW★
\ LBA 1,2,3 を FS-DIRBUF へ一括読み込み (3セクタ=1536B)
\ r0=0 成功、非0=どこかで STOR エラー
\ 検証点: 「最初のエラーコードだけ保持する」ロジックが正しいか
: DIR-LOAD  ( -- r0 )
    0 >R                                    \ R: i = 0
    0 FM-WK-C !                             \ FM-WK-C = 累計エラー = 0
    BEGIN  R@ FS-DIR-SECTORS <  WHILE
        FS-DIR-START R@ +                   \ LBA = 1 + i
        FS-DIRBUF R@ FS-SECSIZE * +         \ dst = FS-DIRBUF + i*512
        STOR-READ-1                         \ ( -- r0 )
        FM-WK-C @ 0= IF
            FM-WK-C !
        ELSE
            DROP
        THEN
        R> 1 + >R
    REPEAT
    R> DROP
    FM-WK-C @ ;

\ DIR-STORE  ( -- r0 )                                        ★REVIEW★
: DIR-STORE  ( -- r0 )
    0 >R
    0 FM-WK-C !
    BEGIN  R@ FS-DIR-SECTORS <  WHILE
        FS-DIR-START R@ +
        FS-DIRBUF R@ FS-SECSIZE * +
        STOR-WRITE-1
        FM-WK-C @ 0= IF
            FM-WK-C !
        ELSE
            DROP
        THEN
        R> 1 + >R
    REPEAT
    R> DROP
    FM-WK-C @ ;

\ DIR-FIND  ( name-addr -- index )                            ★REVIEW★
\ FS-DIRBUF から name 一致 & FLG_USED のエントリを探す。なければ -1
\ 前提  : DIR-LOAD 済み
\ 副作用: FM-WK-SRC/LEN/A/B/C/DST 破壊 (NAME-EQ? 経由)
: DIR-FIND  ( name-addr -- index )
    FM-WK-SRC !                              \ FM-WK-SRC = name-addr
    -1 FM-WK-LEN !                            \ 結果index, 初期 -1
    0 >R                                     \ R: i = 0
    BEGIN  R@ FS-DIR-ENTRIES <
           FM-WK-LEN @ -1 = AND               \ 未発見の間
    WHILE
        R@ DE-ADDR                           \ ( ent-addr )
        DUP DE-FLAGS + @ FLG-USED AND IF
            DUP                              \ ( ent ent )
            FM-WK-SRC @ SWAP NAME-EQ? IF
                R@ FM-WK-LEN !               \ index 確定
            THEN
        THEN
        DROP                                 \ ent 捨てる
        R> 1 + >R
    REPEAT
    R> DROP
    FM-WK-LEN @ ;

\ DIR-FIND-FREE  ( -- index )                                 ★REVIEW★
: DIR-FIND-FREE  ( -- index )
    -1 FM-WK-LEN !
    0 >R
    BEGIN  R@ FS-DIR-ENTRIES <
           FM-WK-LEN @ -1 = AND
    WHILE
        R@ DE-ADDR DE-FLAGS + @ FLG-USED AND 0= IF
            R@ FM-WK-LEN !                   \ 空きエントリ発見
        THEN
        R> 1 + >R
    REPEAT
    R> DROP
    FM-WK-LEN @ ;

\ --------------------------------------------------------------------
\ FS-MOUNT と FILEMGR-INIT (§5.4)
\ Forth は先方参照不可 → FS-MOUNT を先に定義
\ --------------------------------------------------------------------

\ FS-MOUNT  ( -- )                                            ★REVIEW★
\ LBA=0 を読み magic 検証 → 動的フィールドをキャッシュ
\ ver_major 不一致なら FS-MOUNTED=0 維持 (マウント拒否)
\ 副作用: FS-MOUNTED / FS-NEXT-FREE / FS-FILE-COUNT / FS-TOTAL-SEC / FS-FSVER 設定
\ 検証点: SB レイアウト (magic 8B, ver_major +8, ver_minor +9, total_sec +12,
\         next_free +24, file_count +26) が mkfs_yuifs.py の出力と一致するか
: FS-MOUNT  ( -- )
    SB-LOAD                                  \ FS-SECBUF に LBA=0 を読み込む
    0= INVERT IF
        EXIT                                 \ I/O エラー → 未マウント
    THEN
    FS-SECBUF MAGIC-CHECK 0= IF
        EXIT                                 \ magic 不一致 → 未マウント
    THEN
    \ version 読み出し (C@ 2回で明示 pack: major<<8 | minor、v1.2 review19)
    FS-SECBUF 8 + C@ 8 LSHIFT                \ major << 8
    FS-SECBUF 9 + C@ OR                       \ | minor
    FS-FSVER !
    \ ver_major 検査 (上位バイトが 1 でなければ拒否)
    FS-FSVER @ 8 RSHIFT $FF AND  1 = 0= IF
        EXIT                                 \ ver_major 不一致 → 未マウント
    THEN
    \ 動的フィールドをキャッシュ
    FS-SECBUF 12 + @ FS-TOTAL-SEC !          \ total_sectors
    FS-SECBUF 24 + @ FS-NEXT-FREE !          \ next_free_sec
    FS-SECBUF 26 + @ FS-FILE-COUNT !         \ file_count
    1 FS-MOUNTED ! ;

\ FILEMGR-INIT  ( -- )                                        ★REVIEW★
: FILEMGR-INIT  ( -- )
    FS-OPENTAB 0 64 MEMSET-B                 \ オープンテーブル 64B クリア
    0 FS-MOUNTED !
    0 FS-NEXT-FREE !
    0 FS-FILE-COUNT !
    0 FS-TOTAL-SEC !
    0 FS-WR-OLD-NEXT !
    0 FS-WR-OLD-COUNT !
    0 FS-FSVER !
    FS-MOUNT ;

\ --------------------------------------------------------------------
\ FILE-REORDER-MSG  ( msg3 msg2 msg1 msg0 -- arg2 arg1 arg0 op )
\ §5.7。msg と arg の対応が既に一致するため恒等。確定済み。
\ --------------------------------------------------------------------
: FILE-REORDER-MSG  ( msg3 msg2 msg1 msg0 -- arg2 arg1 arg0 op )
    ;                                         \ 恒等

\ --------------------------------------------------------------------
\ REPLY-OK  ( r0 tid -- )                                     ★REVIEW★
\ r0=値、r1=r2=r3=0 で IPC4-REPLY
\ 副作用: FM-WK-A/B 破壊
\ 検証点: VARIABLE 退避方式でスタック並びを確実に組み立てる
\ --------------------------------------------------------------------
: REPLY-OK  ( r0 tid -- )
    FM-WK-A !                                \ tid 退避
    FM-WK-B !                                \ r0 退避
    0 0 0 FM-WK-B @                          \ ( 0 0 0 r0 )
    FM-WK-A @ IPC4-REPLY ;

\ ====================================================================
\ ★★★ 以下、半製品 IMPL 群 (前チャットで未完成のまま中断) ★★★
\ ====================================================================
\ 注意: 以下の IMPL ワードは前チャットで初稿を書いたが、机上検証未了。
\       特に R スタック操作 (>R >R / R> R>) の depth と順序、VARIABLE の
\       使い回しに混乱の可能性あり。HANDOVER_CHAT27 §4 を確認し、必要に
\       応じて完全に書き直すこと。
\
\ 次回作業の推奨方針 (kaizen 原則1: 段階的進行):
\   Step A: ダミー FILEMGR-TASK で FILEMGR-START のビルド可能性を確認
\           (op を受信して E-OK を返すだけのスケルトン)
\   Step B: FS-MOUNT 単体動作確認 (mkfs_yuifs.py で SB を書いてから起動)
\   Step C: FILE-OPEN-IMPL → FILE-LIST-IMPL 等の読み取り系
\   Step D: FILE-WRITE-IMPL (ロールバック含む)
\   Step E: FILE-DELETE-IMPL
\   Step F: FILEMGR-TEST-TASK で ABCXD P Q 出力確認
\ ====================================================================

\ ★TODO★ FILE-OPEN-IMPL  ( arg2 arg1 arg0 tid -- )
\         §4.3.1。arg0 = name-addr
\         前チャットでの初稿があるが、机上検証必要。次回再実装または検証。
\         半製品コードは HANDOVER_CHAT27 §6「半製品コード断片」を参照

\ ★TODO★ FILE-CLOSE-IMPL  ( arg2 arg1 arg0 tid -- )  §4.3.2

\ ★TODO★ FILE-READ-IMPL  ( arg2 arg1 arg0 tid -- )  §4.3.3 / §6.3
\         セクタを跨ぐループ処理あり。最も複雑。要再設計。

\ ★TODO★ FILE-WRITE-IMPL  ( arg2 arg1 arg0 tid -- )  §4.3.4 / §6.4
\         書き込み順序: データ→ディレクトリ→SB (失敗時ロールバック必須)
\         地雷💣5。前チャットで未着手。

\ ★TODO★ FILE-SEEK-IMPL  ( arg2 arg1 arg0 tid -- )  §4.3.4

\ ★TODO★ FILE-STAT-IMPL  ( arg2 arg1 arg0 tid -- )  §4.3.5

\ ★TODO★ FILE-LIST-IMPL  ( arg2 arg1 arg0 tid -- )  §4.3.6

\ ★TODO★ FILE-DELETE-IMPL  ( arg2 arg1 arg0 tid -- )  §4.3.7

\ ★TODO★ FILE-DISPATCH  ( msg3 msg2 msg1 msg0 client_tid -- )
\         REORDER して op で IMPL に分岐。MEMMGR-DISPATCH を雛形にする。

\ ====================================================================
\ v0.10.0 (Step 4): FILEMGR-TASK / FILEMGR-START 最小実装
\ ====================================================================
\ Step 4 の目的は FS-MOUNT 単体動作確認のみ。FILE-DISPATCH は Step 5 で実装。
\ 本版では IPC4-RECV で受信したメッセージは黙って捨てて次の RECV に戻る。
\ 将来の追加実装に備えて IPC4-RECV → IPC4-SENDER-DIRECT → AGAIN のループは
\ STOR-DRV-TASK と同形にしておく (Step 5 で FILE-DISPATCH を挿入する位置を
\ 明確化)。

\ --------------------------------------------------------------------
\ FILEMGR-PUTC  ( char -- )                                  v0.10.0
\ char を UART へ 1文字出力 (デバッグ用ヘルパ)
\ 副作用: IPC4-CALL の戻り値 4ワード DROP
\ --------------------------------------------------------------------
: FILEMGR-PUTC  ( char -- )
    \ ( char ) → ( 0 0 char op tid ) [底→TOS]
    >R                                  \ R:(char) DSP:()
    0 0                                 \ DSP:(0 0) = (msg3 msg2)
    R>                                  \ DSP:(0 0 char) = (msg3 msg2 msg1)
    UART-PUTC-OP                        \ DSP:(0 0 char op) = (msg3 msg2 msg1 msg0)
    UART-DRV-TID @                      \ DSP:(0 0 char op tid)
    IPC4-CALL
    DROP DROP DROP DROP ;

\ --------------------------------------------------------------------
\ FS-MOUNT-DBG  ( -- )                                       v0.10.0
\ FS-MOUNT のデバッグ版。各段階で識別文字を出力する。
\   '0' : SB-LOAD 開始前
\   'i' : SB-LOAD I/O エラー (r0 != 0)
\   '1' : SB-LOAD 成功、MAGIC-CHECK 開始前
\   'g' : MAGIC-CHECK 不一致
\   '2' : MAGIC 一致、version 読出開始
\   'v' : ver_major 不一致
\   '3' : ver_major OK、キャッシュ書込開始
\   'M' : FS-MOUNTED=1 で完了
\ --------------------------------------------------------------------
: FS-MOUNT-DBG  ( -- )
    $30 FILEMGR-PUTC                    \ '0' SB-LOAD 開始
    SB-LOAD
    DUP 0= INVERT IF
        DROP $69 FILEMGR-PUTC           \ 'i' I/O エラー
        EXIT
    THEN
    DROP                                \ r0 (=0) 捨て
    $31 FILEMGR-PUTC                    \ '1' SB-LOAD 成功
    FS-SECBUF MAGIC-CHECK 0= IF
        $67 FILEMGR-PUTC                \ 'g' magic 不一致
        EXIT
    THEN
    $32 FILEMGR-PUTC                    \ '2' magic OK
    FS-SECBUF 8 + C@ 8 LSHIFT
    FS-SECBUF 9 + C@ OR
    FS-FSVER !
    FS-FSVER @ 8 RSHIFT $FF AND 1 = 0= IF
        $76 FILEMGR-PUTC                \ 'v' ver_major 不一致
        EXIT
    THEN
    $33 FILEMGR-PUTC                    \ '3' ver_major OK
    FS-SECBUF 12 + @ FS-TOTAL-SEC !
    FS-SECBUF 24 + @ FS-NEXT-FREE !
    FS-SECBUF 26 + @ FS-FILE-COUNT !
    1 FS-MOUNTED !
    $4D FILEMGR-PUTC ;                  \ 'M' 完了

\ --------------------------------------------------------------------
\ FILEMGR-INIT-DBG  ( -- )                                   v0.10.0
\ FILEMGR-INIT のデバッグ版。FS-MOUNT-DBG を呼ぶ。
\ --------------------------------------------------------------------
: FILEMGR-INIT-DBG  ( -- )
    FS-OPENTAB 0 64 MEMSET-B
    0 FS-MOUNTED !
    0 FS-NEXT-FREE !
    0 FS-FILE-COUNT !
    0 FS-TOTAL-SEC !
    0 FS-WR-OLD-NEXT !
    0 FS-WR-OLD-COUNT !
    0 FS-FSVER !
    FS-MOUNT-DBG ;

\ --------------------------------------------------------------------
\ FILEMGR-PUTC-M  ( -- )                                     v0.10.0
\ FS-MOUNTED の値に応じて 'M' (成功) または 'm' (失敗) を UART 出力
\ 副作用: DSP 上に IPC4-CALL の戻り値が残らないよう DROP DROP DROP DROP で清掃
\ --------------------------------------------------------------------
: FILEMGR-PUTC-M  ( -- )
    FS-MOUNTED @ IF
        0 0 $4D UART-PUTC-OP UART-DRV-TID @ IPC4-CALL    \ 'M' (=$4D)
    ELSE
        0 0 $6D UART-PUTC-OP UART-DRV-TID @ IPC4-CALL    \ 'm' (=$6D)
    THEN
    DROP DROP DROP DROP ;

\ --------------------------------------------------------------------
\ FILEMGR-TASK  ( -- )                                       v0.10.0
\ FileMgr メインタスク (tid=4)。STOR-DRV-TASK と同形のサーバループ。
\ Step 4: FILEMGR-INIT-DBG → IPC4-RECV AGAIN
\ Step 5 以降: IPC4-RECV → FILE-DISPATCH を挿入予定
\ --------------------------------------------------------------------
: FILEMGR-TASK  ( -- )
    FILEMGR-INIT-DBG                    \ デバッグ版 (段階ごとに文字出力)
    BEGIN
        IPC4-RECV                       \ ( -- msg3 msg2 msg1 msg0 )
        DROP DROP DROP DROP             \ Step 4: メッセージは捨てるだけ
        \ ★Step5★ ここに FILE-DISPATCH を挿入する
    AGAIN ;

\ --------------------------------------------------------------------
\ FILEMGR-TASK-ADDR  ( -- addr )                             v0.10.0
\ FILEMGR-TASK の Forth ワード先頭アドレスを DSP に積む
\ TASK-CREATE に渡すために必要 (STOR-DRV-TASK-ADDR と同形)
\ --------------------------------------------------------------------
CODE FILEMGR-TASK-ADDR  ( -- addr )
    SUBI X, #2
    LDW  A, #WORD_FILEMGR_TASK
    STW  A, [X]
END-CODE

\ --------------------------------------------------------------------
\ FILEMGR-START  ( -- )                                      v0.10.0
\ FileMgr タスクを生成し、tid を FILEMGR-TID-ADDR に格納
\ STOR-START の後・テストタスク起動の前に呼ぶこと
\ --------------------------------------------------------------------
: FILEMGR-START  ( -- )
    FILEMGR-TASK-ADDR TASK-CREATE       \ ( -- tid )
    FILEMGR-TID-ADDR ! ;                \ tid を $4800 へ格納

\ ★TODO★ FILEMGR-TEST-TASK  ( -- )
\         §8.3 テストシナリオ実装。期待出力: ABCXD P Q

\ ★TODO★ FILEMGR-TEST-START  ( -- )

: OS-START  ( -- )
    MEMMGR-START                    \ Ph.2 既存 (tid=1)
    UART-START                      \ Ph.3-A5 UARTドライバ起動 (tid=2)
    STOR-START                      \ v0.7: Ph.3-B ストレージドライバ起動 (tid=3)
    FILEMGR-START                   \ v0.10.0: Ph.4 FileMgr 起動 (tid=4)
    UART-TEST-START                 \ UARTテストタスク起動 (tid=5)
    STOR-TEST-START                 \ v0.7: STORテストタスク起動 (tid=6)
    \ ★HOLE★ FILEMGR-TEST-START は未実装プレースホルダ。Step 6 で対応
    \ FILEMGR-TEST-START            \ v0.10.0: FileMgrテストタスク起動 (tid=7)
    BEGIN TASK-SLEEP AGAIN ;        \ ルートタスクは待機ループ
