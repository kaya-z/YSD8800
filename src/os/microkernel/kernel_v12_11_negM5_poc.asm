; ============================================================
; YSD8800 マイクロカーネル kernel.asm  v0.12.9
; 純粋アセンブラ版 Track A
;
; v0.12.9: IRQ0スケジューラ アイドル処理欠落の修正（2026-08-04）
;   設計書: yuios_irq0_idle_design_v0_2.md
;   欠陥: _sched_chk に1周検出が無く、READYタスクが0個になると
;         DI状態のまま _sched ループを無限に回りハングする。
;         シェルがGETCで入力待ちに入った状態がまさにこの条件のため、
;         「キーボード入力を受け付けない」現象として顕在化していた。
;   修正: _sched_chk に1周検出を追加し、READYタスクが0個なら
;         IRQ_WK_* を復元して IRET し割込元へ戻す（_irq_noready）。
;         IRQ0_HANDLER は run-to-completion を守り、待機は
;         カーネルコンテキストの _sc_idle が担当する。追加のみ・既存行不変。
;
; v0.12.8: V5 TCR-ACK方式対応（2026-07-13）
;   設計書: v5_design_memo_v0_2.md §5.3
;   背景: emu23 v1.10 でタイマーの再武装契機が「IRET命令」から
;         「TCR bit5(IRQ_ACK)書込」へ変更された。IRET自動再武装は
;         FPGA実装不能な設計負債であった（kaizen原則73）。
;         → ハンドラがACKを書かないとタイマーが永久停止する。
;   修正: (1) MMIO定数 TCR($FC90)/TCR_IRQ_ACK($0020) 追加
;         (2) IRQ0_HANDLER 入口(B退避直後)に ACK 3命令を挿入
;   ★挿入位置は「入口・B退避直後」の1点に固定（設計メモ§5.3で唯一安全と確定）★
;     復元部(_sched_found)への挿入 → 他経路と共有のため誤再武装
;     保存部への挿入 → state==RUNNING時のみ実行のためアイドル中にACKが飛び、
;                      タイマーが永久停止する（致命的）
;   ★本改修は v0.12.7 が修正した FILE-WRITE LBA6 バグの隣接箇所である。
;     ACKはA/Bを破壊するが、直上のL413-415で退避済みのため安全。
;     回帰として FILE-WRITE LBA6 完全性テストを必須とする。★
;
; v0.12.7: コンテキストスイッチ A/Bレジスタ復元漏れ修正（2026-06-01）
;   設計書: yuios_ctxsw_abreg_design_v1_1.md / レビュー: REV-CTXSW-ABREG-001
;   真因: IRQ0_HANDLER 復元部(_sched_found)が SAVED_A(TCB+8)を復元せず、
;         Bは退避も復元もしていなかった。プリエンプティブIRQが任意命令境界で
;         発火するため、MEMCPY-B の 0>判定値(remain)をAに載せた瞬間に中断されると
;         復帰後A=SAVED_X(負値)となり 0> 偽脱出→FILE-WRITE LBA6 byte434-511欠落。
;   修正(IRQ0_HANDLERのみ・協調切替_sc_found/IRQ1は非対象):
;     (1) 入口に STW B,[IRQ_WK_B] 追加（中断時B退避）
;     (2) 保存部に SAVED_B(TCB+10)保存追加
;     (3) 復元部_sched_found に A/B復元追加（IRET直前。IRETはA/B不変）
;     (4) IRQ_WK_B EQU $47B6 新設（memory_contract v1.2要改版・Force占有$47B0-$47B5外）
;
; v0.12.5: Ph.3.5 実装フェーズ Step 6 — IPC4 Pool 方式の実装
; v0.12.6: Ph.3.5 Step 6 デバッグ完了（2026-05-17）
;   - IPC4_RECV msgコピーループ後のDSP→X復元欠落修正（RET前LDW X,[L1_WK_TMP]追加）
;   - IPC4_RECVスロット超過解消（13B削減：X退避撤廃8B+CMPI削除4B+resume統合9B→計21B）
;   - _ipc4recv_resume を IPC4_RECV 冒頭に統合（独立ブロック廃止）
;   - IPC4_RECV/IPC4_CALL の saved_sp 計算修正（+2廃止、saved_pcが戻り先でないため）
;   - _ipc4_enqueue のmsgインデックス修正（IPC4_WK_XはmsgOを指す）
;   - IRQ0_HANDLER のコンテキスト保存を state==RUNNING 時のみに制限
;     （アイドルループ中IRQで寝タスクのsaved_pcが破壊されるバグを修正）
;   設計書: yuios_ipc4_pool_design_v1_2.md §3〜§6
;   方針:
;   - EQU追加: MSG_POOL_BASE, POOL_SIZE, IDX_NIL, ERR_IPC_NOSLOT
;              TCB_IPC_QUEUE_TAIL(+14), TCB_IPC_QUEUE_HEAD(+30)
;              TCB_RSVD1→TCB_IPC_QUEUE_TAIL に rename
;              TCB_RSVD2→TCB_IPC_QUEUE_HEAD に rename
;   - init_msg_pool: MsgPool全エントリ初期化 + フリーリスト構築
;   - _ipc4_enqueue: O(1) enqueue (フリーリスト alloc + キュー末尾挿入)
;   - IPC4_SEND: _ipc4_enqueue を呼ぶ形に全面書き換え
;   - IPC4_RECV: プール dequeue 方式に全面書き換え
;   - IPC4_CALL: _ipc4_enqueue + WAIT_REPLY 方式に全面書き換え
;   - IPC4_REPLY: reply バッファ直接書込方式（変更小・プール不使用）
;   - TASK_CREATE: TCB+14/+30 に IDX_NIL を初期化（§6.2）
;   - _kstart TCB0 初期化: 同上
;   - _kstart: init_msg_pool 呼出追加
;   工程: Ph.3.5-I-1 Step 6（HANDOVER_CHAT23.docx §4.3）
;
; v0.12.4: Ph.3.5 実装フェーズ Step 5 — stack guard 領域の初期化
;   設計書: yuios_memmap_design_v1_1.md §4.1・§7.1・§7.4
;   方針:
;   - _kstart に $FC00-$FC3F（64B = 32ワード）を $A55A で埋めるループ追加
;   - 目的: データスタックオーバーフロー時の MMIO 即突入を防止
;           CHK-GUARD ワード（Step 8以降）で破壊検出に使用
;   - GUARD_BASE=$FC00 は Step 1 で EQU 定義済み
;   工程: Ph.3.5-I-1 Step 5（HANDOVER_CHAT23.docx §4.3）
;
; v0.12.3: Ph.3.5 実装フェーズ Step 4 — KERN_SP 専用化
;   設計書: yuios_memmap_design_v1_1.md §4.1・§6.3・§7.1
;   方針:
;   - SP切替先変更: $FBCE → $477E (KERN_SP専用領域 $4700-$477F の頂上)
;   - 変更箇所: _kstart / TASK_SLEEP / TASK_EXIT / IPC4_CALL / IPC4_RECV 等
;     SPをカーネルスタックに切り替える全箇所（LDW A/SP,#$FBCE）
;   - canary設置: _kstart で $4700 に $A55A を書き込む
;   - KERN_SP領域($4700-$477F)の0クリア（canaryの前に実施）
;   - stack guard初期化($FC00-$FC3Fを$A55A埋め)はStep 5で対応
;   工程: Ph.3.5-I-1 Step 4（HANDOVER_CHAT23.docx §4.3）
;
; v0.12.2: Ph.3.5 実装フェーズ Step 3 — タスクスタック完全分離
;   設計書: yuios_memmap_design_v1_1.md §6.4（スタック完全分離設計）
;   方針:
;   - CALLSTK_BASE: $FBCE → $F07F（tid=0 コールスタック頂上）
;   - DATASTK_BASE: $FB4E → $F87F（tid=0 データスタック頂上）
;   - TASK_STK_GAP: $0100 → $0080（1タスクあたり128B）
;   - 計算式変更:
;       旧: BASE - tid×$100 (SHL 8, 引き算)
;       新: BASE + tid×$80  (SHL 7, 足し算)
;       コール: $F07F + (tid SHL 7)
;       データ: $F87F + (tid SHL 7)
;   - LDW SP, #$FBCE（_kstart）は Step 4 で変更
;   工程: Ph.3.5-I-1 Step 3（HANDOVER_CHAT23.docx §4.3）
;
; v0.12.1: Ph.3.5 実装フェーズ Step 2 — TCB 16タスク化
;   設計書: yuios_tcb_design_v1_2.md §4（MAX_TASKS=16拡張）
;   方針:
;   - MAX_TASKS 8→16（EQU新設、タスク数比較即値4箇所変更）
;   - TCBプール末尾コメント $427F→$44FF（1280B）
;   - タスク数比較: CMPI A/B, #8 → #16（342・453・631・1169行）
;   - [X + #8]（TCBオフセット）・SHL #8（スタック計算）は変更しない
;   - CALLSTK_BASE/DATASTK_BASE/SHL #8によるスタック計算はStep 3で対応
;   工程: Ph.3.5-I-1 Step 2（HANDOVER_CHAT23.docx §4.3）
;
; v0.12.0: Ph.3.5 実装フェーズ Step 1 — メモリマップアドレス定数の更新
;   設計書: yuios_memmap_design_v1_1.md（FIX 版）
;   方針:
;   - カーネルワーク領域: $4280-$42AA → $4780-$47AA に集約移動
;     (KERN_SP $4700-$477F と物理分離。frequently used 領域内)
;   - OS共有変数: $F0xx → $FCxx (OS共有変数領域 $FC40-$FC7F へ)
;     (タスクスタック領域 $F000-$FBFF の完全独立化)
;   - テストバッファ: $E800/$EA00 → $EC00/$EE00
;     (テスト領域 $EC00-$EFFF へ)
;   - 新設定数: GUARD_BASE=$FC00, KERN_SP_TOP=$477E, MSG_POOL_FREE=$47AC
;   - KERN_SP 定数値変更: $FBCE → $477E (専用領域への切替、コードは Step 4 で対応)
;   - CALLSTK_BASE/DATASTK_BASE/TASK_STK_GAP は本Stepでは変更せず（Step 3 で対応）
;   - MAX_TASKS は本Stepでは変更せず（Step 2 で 8→16 化）
;   工程: Ph.3.5-I-1 Step 1（HANDOVER_CHAT23.docx §4.3 / §9.1）
;
; v0.11.3: タスクスタック衝突修正 (HANDOVER_CHAT22 / Ph.3 暫定版)
; v0.3: TASK-SLEEP / TASK-WAKEUP 追加
; v0.4: TASK-ID / TASK-EXIT / TASK-CREATE 追加
; v0.5: MSG-SEND / MSG-RECV 追加
; v0.6: 全タスクDEAD時 HALT
; v0.7: ISA2.3 v2.2.1メモリマップ対応
; v0.8: YUI OS v2.0 Ph.1 IPC拡張対応
;   - TCBサイズ 64B→80B (16タスク×80B=1280B: $4000-$44FF) v0.12.1: 8→16タスク化
;   - TCBアドレス計算: tid*80=(tid<<6)+(tid<<4)
;     パターン: STW A,[L1_WK_TMP]; LDW B,#6; SHL A,B;
;               STW A,[L1_WK_C]; LDW A,[L1_WK_TMP];
;               LDW B,#4; SHL A,B; LDW B,[L1_WK_C];
;               ADD A,B; LDW B,#$4000; ADD A,B
;   - ワーク変数 $4780〜 (TCBプール $4000-$44FF, MsgPool $4500-$46FF の後方)
;   - 新タスク状態: TASK_WAIT_IPC(5), TASK_WAIT_REPLY(6)
;   - TCB+16〜+30: IPC4フィールド
;   - 旧MSG_SEND/MSG_RECV廃止
;   - _sched_common 共通スケジューラ導入(org衝突解消)
;     TASK_SLEEP/TASK_EXIT から JMP で呼び出し
;   - IPC4_SEND/IPC4_RECV/IPC4_CALL/IPC4_REPLY 追加
; v0.10: YUI OS v2.0 Ph.3-A5 UARTドライバ対応
;   - IRQ1ベクタを IRQ1_HANDLER に差替
;   - IRQ1_HANDLER 新設 (yuios_ph3_uart_design_v1_2.docx §5.3)
;   - rx_push サブルーチン追加 (§5.4)
;   - wake_uart_waiter サブルーチン追加 (§5.5, IPC4_REPLY コピペベース)
;   - IRQ1ワーク変数追加: IRQ1_WK_A/B/X/BYTE ($42A2-$42A8)
;   - 新規MMIO定数: UART_RX($FC82), IRQ_STAT($FCB2), IRQ_MASK($FCB4)
;   - UARTリングバッファ定数: UART_RX_RING_BUF($E210)他
; v0.11: YUI OS v2.0 Ph.3-B ストレージドライバ対応
;   設計書: yuios_ph3_storage_design_v1_2.md
;   - IRQ1_HANDLER 拡張: bit1 (STOR) 分岐追加 (§5.2-§5.3)
;   - _handle_stor サブルーチン新設 (§5.3, 順序固守IR4)
;   - wake_stor_waiter サブルーチン新設 (§5.4, state遷移のみ・UART版とは非対称)
;   - YSD8003 MMIO 定数追加: SD_STAT/SD_IRQ_CTRL/STOR_LAST_STAT 等
;   - ストレージ専用変数追加: STOR_DRV_TID/STOR_WAIT_TID/STOR_LAST_STAT ($E230-)
;   - BC_STR を $E230 → $E260 へ移動 (§2.1, KY8 防止)
;   - _kstart にストレージ変数初期化 + テストバッファ領域確保 ($E300/$E500)
; v0.11.1: 解釈A適用 (soudan3.txt) - 設計書 v1.2 §5.4 の論理矛盾修正
;   - wake_stor_waiter の state判定を WAIT_REPLY(6) → WAIT_IPC(5) に修正
;   - STOR_WAIT_TID には【ドライバ自身のtid】が入る前提に変更
;   - TASK_WAIT_IPC_ENTRY サブルーチン新設 ($1100)
;     ドライバ自身を WAIT_IPC で寝かすエントリ (Forth から CODE で呼ぶ)
;   - 設計書 v1.3 へ改版予定（実装後）
; v0.11.2: A/B案適用 - 変数領域 Forthコード衝突回避（B案全面移動）
;   問題: v0.7 で Forthコード末尾が $D817 → $E795 に肥大化し、
;        $E200-$E795 のカーネル変数を Forthコードが上書きする問題発生
;        _kstart の0クリアでForthコードが破壊される、PAGE-BMP操作で破壊される等
;   対処（B案全面移動）:
;   - MEM_TID_ADDR を $E204 → $F014 へ移動
;   - UART_RX_RING_BUF/HEAD/TAIL/COUNT/DRV_TID/WAIT_TID を $F020-$F038 へ移動
;   - BC_STR を $E260 → $F040 へ移動
;   - STOR_DRV_TID/WAIT_TID/LAST_STAT を $F050/$F052/$F054 へ移動
;   - TEST_SRC_BUF/DST_BUF を $E800/$EA00 へ移動
;     (Forthコード末尾$E795とスタック最低$F3CEの間)
;   - PAGE-BMP-LO/HI も $F010/$F012 (Forth側で対応)
;   - wake_uart_waiter / rx_pop を $1200 領域へ移動
;     (IRQ1_HANDLER 拡張により $0DXX 領域内に収まらないため)
;
; v0.11.3: タスクスタック衝突修正 (HANDOVER_CHAT22 / Ph.3 暫定版)
;   問題: tid=N+2 のコールスタック範囲と tid=N のデータスタック範囲が完全重なり
;        UART-DRV(tid=2) のデータ push が UART-TEST(tid=4) のコール戻り値を破壊
;        症状: STOR-DRV 追加時に Unknown opcode 0e at 0001 で死亡
;   原因: CALLSTK_BASE=$FBCE / DATASTK_BASE=$F9CE / TASK_STK_GAP=$100 で
;        コール256B + データ256B = 512B > GAP$100 のため
;   対処:
;   - DATASTK_BASE を $F9CE → $FB4E へ変更（コール頂上から128B下）
;   - 各スタック容量を実質128B制限（コール+データ=256B = GAP$100 に収まる）
;   - tid=0 用初期DSP・TASK_CREATE のデータSP頂上算出を更新
;   注意: 本修正は8タスク維持の暫定版。Ph.3.5 で16タスク化メモリマップ
;        再設計と同時に正式化する予定。
;
; メモリマップ (ROM):
;   $0000-$000F  ベクタテーブル
;   $0020        _dummy_irq
;   $0030-$01BF  IRQ0_HANDLER (~276B)
;   $01C0-$02BF  TASK_SLEEP   (~104B)
;   $02C0-$036F  _sched_common (~168B)
;   $0380-$03CF  TASK_WAKEUP  (~72B)
;   $03D0-$040F  TASK_PRINT_ID
;   $0440        TASK_ID
;   $0460-$051F  TASK_EXIT
;   $0520-$073F  TASK_CREATE
;   $0700-$073F  TASK0/1 デモエントリ
;   $0740        IPC4_SEND
;   $07E0        IPC4_RECV
;   $0880        IPC4_CALL
;   $0B00        IPC4_REPLY
;   $0D00        IRQ1_HANDLER (v0.10新設・v0.11 STOR分岐追加)
;   $0E00        _kstart
; ============================================================

; ================================================================
; 定数定義
; ================================================================
TCB_POOL            EQU $4000
TCB_SIZE            EQU 80
MAX_TASKS           EQU 16          ; v0.12.1新設: Ph.3.5-c (8→16) yuios_tcb_design_v1_2.md §4
                                    ; 注: hasm23はCMPI即値にEQU展開不可→直書き+コメントで対応
                                    ; TCBプール: $4000-$44FF (16×80=1280B), MsgPool: $4500-$46FF

TASK_DEAD           EQU 0
TASK_READY          EQU 1
TASK_RUNNING        EQU 2
TASK_SLEEPING       EQU 3
TASK_WAIT_MSG       EQU 4
TASK_WAIT_IPC       EQU 5
TASK_WAIT_REPLY     EQU 6

; TCBオフセット
TCB_STATE           EQU 0
TCB_SAVED_PC        EQU 2
TCB_SAVED_SP        EQU 4
TCB_SAVED_X         EQU 6
TCB_SAVED_A         EQU 8
TCB_SAVED_B         EQU 10
TCB_SAVED_FLAGS     EQU 12
TCB_RSVD1           EQU 14          ; v0.12.5: TCB_IPC_QUEUE_TAIL に rename
TCB_IPC_QUEUE_TAIL  EQU 14          ; v0.12.5新設: キュー末尾 index (設計書 §3.2.2)
TCB_IPC_MSG0        EQU 16
TCB_IPC_MSG1        EQU 18
TCB_IPC_MSG2        EQU 20
TCB_IPC_MSG3        EQU 22
TCB_IPC_VALID       EQU 24
TCB_IPC_SENDER      EQU 26
TCB_LAST_SENDER     EQU 26          ; v0.12.5: last_sender_tid alias
TCB_PRIORITY        EQU 28
TCB_RSVD2           EQU 30          ; v0.12.5: TCB_IPC_QUEUE_HEAD に rename
TCB_IPC_QUEUE_HEAD  EQU 30          ; v0.12.5新設: キュー先頭 index (設計書 §3.2.2)

; ================================================================
; MsgPool 関連定数 v0.12.5新設
; 設計書: yuios_ipc4_pool_design_v1_2.md §3.1-3.3
; ================================================================
MSG_POOL_BASE       EQU $4500       ; プール先頭（memmap v1.1 §4.3）
POOL_SIZE           EQU 32          ; エントリ数（32x16B=512B=$4500-$46FF）
IDX_NIL             EQU $FFFF       ; キュー末尾・空を示す番兵値
ERR_IPC_NOSLOT      EQU $FFFE       ; プール枯渇エラーコード
MSG_ENTRY_SIZE      EQU 16          ; MsgEntry サイズ（SHL #4=x16）
MSG_SENDER          EQU 0           ; sender tid
MSG_MSG0            EQU 2           ; msg[0] (opcode)
MSG_MSG1            EQU 4           ; msg[1] (arg0)
MSG_MSG2            EQU 6           ; msg[2] (arg1)
MSG_MSG3            EQU 8           ; msg[3] (arg2/result)
MSG_NEXT            EQU 10          ; next index (IDX_NIL=末尾)
IPC4_WK_IDX         EQU $47AE       ; v0.12.5新設: index退避

; ================================================================
; カーネルワーク変数 ($4780〜) v0.12.0: $4280→$4780 へ移動
;   memmap v1.1 §5.1 に従い、frequently used 領域 $4780-$47BF 内に配置。
;   KERN_SP 領域 $4700-$477F とは物理分離。
;
; tid*80計算パターン (A=tid入力, A=TCBアドレス出力, B破壊):
;   STW A,[L1_WK_TMP]      ; tid退避
;   LDW B,#6; SHL A,B      ; A=tid*64
;   STW A,[L1_WK_C]        ; tid*64退避
;   LDW A,[L1_WK_TMP]      ; tid復元
;   LDW B,#4; SHL A,B      ; A=tid*16
;   LDW B,[L1_WK_C]        ; B=tid*64
;   ADD A,B                 ; A=tid*80
;   LDW B,#$4000; ADD A,B  ; A=TCBアドレス
;
; L1_WK_A  = ループ変数(現スキャンtid)
; L1_WK_B  = 1周検出用開始tid (ループ中読むだけ)
; L1_WK_C  = tid*64中間値
; L1_WK_TMP= tid一時退避
; ================================================================
L1_WK_A             EQU $4780       ; v0.12.0: $4280→$4780
L1_WK_B             EQU $4782       ; v0.12.0: $4282→$4782
L1_WK_C             EQU $4784       ; v0.12.0: $4284→$4784
L1_WK_TMP           EQU $4786       ; v0.12.0: $4286→$4786
IRQ_WK_X            EQU $4788       ; v0.12.0: $4288→$4788
IRQ_WK_A            EQU $478A       ; v0.12.0: $428A→$478A
IRQ_WK_B            EQU $47B6       ; v0.12.6新設: IRQ0用B退避(A/Bレジスタ完全保護) memory_contract v1.2/$47B6
SLP_WK_DSP          EQU $478C       ; v0.12.0: $428C→$478C
SLP_WK_PC           EQU $478E       ; v0.12.0: $428E→$478E
MISC_WK_X           EQU $4790       ; v0.12.0: $4290→$4790
CUR_TASK            EQU $4792       ; v0.12.0: $4292→$4792
NEXT_TASK           EQU $4794       ; v0.12.0: $4294→$4794
TASK_COUNT          EQU $4796       ; v0.12.0: $4296→$4796
TC_WK_ENTRY         EQU $4798       ; v0.12.0: $4298→$4798
TC_WK_TID           EQU $479A       ; v0.12.0: $429A→$479A
IPC4_WK_X           EQU $479C       ; v0.12.0: $429C→$479C
IPC4_WK_DST         EQU $479E       ; v0.12.0: $429E→$479E
IPC4_WK_SRCTCB      EQU $47A0       ; v0.12.0: $42A0→$47A0

; v0.10追加: IRQ1専用ワーク変数 v0.12.0: $42A2-$42AA → $47A2-$47AA
; IRQ0のIRQ_WK_X/IRQ_WK_Aとは別領域 (混用禁止)
; yuios_ph3_uart_design_v1_2.docx §5.6
; v0.11追加: IRQ1_WK_STAT (IRQ_STAT保存用、複数bit同時処理対応)
IRQ1_WK_A           EQU $47A2       ; IRQ1用 A退避    v0.12.0: $42A2→$47A2
IRQ1_WK_B           EQU $47A4       ; IRQ1用 B退避    v0.12.0: $42A4→$47A4
IRQ1_WK_X           EQU $47A6       ; IRQ1用 X退避    v0.12.0: $42A6→$47A6
IRQ1_WK_BYTE        EQU $47A8       ; 受信バイト一時保管 (UART) v0.12.0: $42A8→$47A8
IRQ1_WK_STAT        EQU $47AA       ; IRQ_STAT保存            v0.12.0: $42AA→$47AA

; v0.12.0 新設定数
MSG_POOL_FREE       EQU $47AC       ; ★Ph.3.5 新設: MsgPool free list head
GUARD_BASE          EQU $FC00       ; ★Ph.3.5 新設: stack guard 領域基底 ($FC00-$FC3F)
KERN_SP_TOP         EQU $477E       ; ★Ph.3.5 新設: カーネルスタック頂上(canary $4700)

MEM_TID_ADDR        EQU $FC44        ; v0.12.0: $F014→$FC44 (OS共有変数領域)

; ================================================================
; UART / IRQ MMIO (v0.10追加)
; YSD8001 UART ($FC80-$FC8F)
; YSD8004 IRQC ($FCB2-$FCB4)
; ================================================================
UART_RX             EQU $FC82
IRQ_STAT            EQU $FCB2
IRQ_MASK            EQU $FCB4

; ================================================================
; YSD8002 タイマー MMIO (v0.12.8 / V5追加)
;
; TCR($FC90) は「状態ビット」と「イベントストローブ」の混在レジスタ:
;   bit0 TIMER_EN  : 状態（値を保持・readで返る）
;   bit1 IRQ_EN    : 状態（値を保持・readで返る）
;   bit2 SW_START  : ストローブ（1回限りのトリガ・readで常に0）
;   bit3 SW_STOP   : ストローブ（同上）
;   bit5 IRQ_ACK   : ストローブ（タイマー割込ACK＋再武装）★V5新設★
;
; ★重要★ TCR write は【状態ビットも常に上書きする】。
;   これはメモリマップドI/Oの原則であり、FPGA(RTL)でも同じである:
;     always_ff @(posedge clk) if (tcr_we) {irq_en,timer_en} <= wdata[1:0];
;   したがって ACK を書く際は【状態ビットも含めた完全な値】を書かねばならない。
;   ACK単独($0020)を書くと TIMER_EN/IRQ_EN が 0 に落ち、タイマーが恒久停止する。
;   （MC6840 PTM も同様。ハンドラは制御レジスタの全ビットを決めて書く）
;
; emu23 v1.10 以降、タイマーは発火後に自己武装解除するため、
; IRQ0_HANDLER が ACK を書かない限り二度と発火しない。
; ★ACKは1割込につき1回だけ★（複数回書くと周期がずれる）
; ================================================================
TCR                 EQU $FC90
; ACK書込値 = TIMER_EN(bit0) + IRQ_EN(bit1) + IRQ_ACK(bit5) = $0023
; ★$0020(ACK単独)を書いてはならない（状態ビットが落ちる）★
TCR_ACK_REARM       EQU $0023

; ================================================================
; YSD8003 ストレージ MMIO (v0.11追加)
; emu23_device_design_v1_2.docx §6
; emu23_v103_design_v1_4.md §3
; ================================================================
SD_CMD              EQU $FCA0       ; 0=READ_SETUP 1=WRITE_SETUP 2=EXEC
SD_STAT             EQU $FCA2       ; bit0=BUSY bit1=ERROR bit2=READY
SD_LBA_LO           EQU $FCA4       ; LBA下位16bit
SD_LBA_HI           EQU $FCA6       ; LBA上位16bit
SD_BUF_PTR          EQU $FCA8       ; バッファポインタ(0-511)
SD_DATA             EQU $FCAA       ; PIOデータ(8bit)・自動BUF_PTR++
SD_IRQ_CTRL         EQU $FCAC       ; bit0=IRQ_EN bit1=ERR_EN
SD_DISK_LO          EQU $FCAE       ; 総セクタ数下位
SD_DISK_HI          EQU $FCB0       ; 総セクタ数上位

; ================================================================
; UART受信リングバッファ変数 v0.12.0: $F020-$F038 → $FC46-$FC5E へ移動
;   v0.10: $E210-$E228 → v0.11.2: $F020-$F038 → v0.12.0: $FC46-$FC5E
;   理由: タスクスタック領域 $F000-$FBFF を完全独立化するため
;        OS共有変数領域 $FC40-$FC7F に集約 (memmap v1.1 §5.2)
; yuios_ph3_uart_design_v1_2.docx §2.2 (要 v1.3 改版・Ph.3.5完了時に一括対応)
; ================================================================
UART_RX_RING_BUF    EQU $FC46       ; 16B リングバッファ本体 ($FC46-$FC55) v0.12.0
UART_RX_HEAD        EQU $FC56       ; 書き込み位置 (0-15)              v0.12.0: $F030→$FC56
UART_RX_TAIL        EQU $FC58       ; 読み出し位置 (0-15)              v0.12.0: $F032→$FC58
UART_RX_COUNT       EQU $FC5A       ; バッファ内バイト数 (0-16)        v0.12.0: $F034→$FC5A
UART_DRV_TID        EQU $FC5C       ; UARTドライバタスクID             v0.12.0: $F036→$FC5C
UART_WAIT_TID       EQU $FC5E       ; UART_GETC待ちクライアントtid     v0.12.0: $F038→$FC5E

; ================================================================
; ストレージ専用変数 v0.12.0: $F050-$F054 → $FC64-$FC68 へ移動
;   v0.11: $E230 → v0.11.2: $F050 → v0.12.0: $FC64 (OS共有変数領域)
; yuios_ph3_storage_design_v1_2.md §2.2 (要 v1.3 改版・Ph.3.5完了時に一括対応)
; ================================================================
STOR_DRV_TID        EQU $FC64       ; ストレージドライバタスクID v0.12.0: $F050→$FC64
STOR_WAIT_TID       EQU $FC66       ; EXEC完了待ちtid           v0.12.0: $F052→$FC66
                                    ; ★ 解釈A: ドライバ自身のtidが入る
STOR_LAST_STAT      EQU $FC68       ; 最終SD_STAT値             v0.12.0: $F054→$FC68
                                    ; (EXEC前に0クリア、IRQ後に必ず非0値)

; BC_STR (UARTテスト文字列) v0.11→v0.11.2→v0.12.0
; v0.12.0: $F040 → $FC60 (OS共有変数領域)
BC_STR              EQU $FC60       ; "BC\0" テスト文字列配置先 v0.12.0: $F040→$FC60

; テストバッファ v0.12.0: $E800/$EA00 → $EC00/$EE00
;   v0.11.2: $E800/$EA00 → v0.12.0: $EC00/$EE00 (テスト領域 $EC00-$EFFF)
;   memmap v1.1 §5.4
TEST_SRC_BUF        EQU $EC00       ; 512B 書き込み元 v0.12.0: $E800→$EC00
TEST_DST_BUF        EQU $EE00       ; 512B 読み出し先 v0.12.0: $EA00→$EE00

; v0.11.3: タスクスタック衝突回避のため、データSP頂上をコール下端と一致させる
;          旧: DATASTK_BASE=$F9CE → tid=N+2 のコール領域と tid=N のデータ領域が重なる
;          新: DATASTK_BASE=$FB4E → コール128B + データ128B = ギャップ$100に収まる
;          各スタック容量は128Bを上限とする（hasm23/force生成コードで超えないこと）
; v0.12.2: タスクスタック完全分離（memmap v1.1 §6.4）
;          コール $F000-$F7FF（16タスク×128B）/ データ $F800-$FBFF（16タスク×128B）
;          計算: CALLSTK_TOP(tid) = $F07E + tid×$80  (偶数アドレス保証)
;                DATASTK_TOP(tid) = $F87E + tid×$80  (偶数アドレス保証)
;          ★案1: $F07F/$F87F(奇数)→$F07E/$F87E(偶数) アライメント修正
;            実効容量126B/タスク（末尾2Bは未使用）。動作確認後にmemmap設計書改版。
;          コール領域とデータ領域が物理的に分離→衝突不可能な構造
CALLSTK_BASE        EQU $F07E       ; v0.12.2: $FBCE→$F07E (tid=0 コールスタック頂上、偶数)
DATASTK_BASE        EQU $F87E       ; v0.12.2: $FB4E→$F87E (tid=0 データスタック頂上、偶数)
TASK_STK_GAP        EQU $0080       ; v0.12.2: $0100→$0080 (1タスクあたり128B)
KERN_SP             EQU $477E       ; v0.12.0: $FBCE→$477E (KERN_SP専用領域、定数のみ)
                                    ;          SP切替コードは Step 4 で対応
UART_STAT           EQU $FC84
UART_TX             EQU $FC80

; ================================================================
; ベクタ
; ================================================================
    .vector reset   _kstart
    .vector irq0    IRQ0_HANDLER
    .vector irq1    IRQ1_HANDLER    ; v0.10: UARTドライバ対応 (_dummy_irqから差替)
    .vector align   _dummy_irq
    .vector syscall _dummy_irq

    .org $0020
_dummy_irq:
    DI
    IRET

; ================================================================
; IRQ0ハンドラ ($0030)
; スケジューラはここに展開（JSR不可のため）
; ================================================================
    .org $0030
IRQ0_HANDLER:
    DI
    STW  A, [IRQ_WK_A]
    STW  X, [IRQ_WK_X]
    STW  B, [IRQ_WK_B]          ; v0.12.6: 中断時のBを退避(A/Bレジスタ完全保護)

    ;--- ★v0.12.8 (V5): タイマーACK＋再武装（TCR bit5）★ --------------
    ; 挿入位置は「割込入口・B退避直後」に固定する（v5_design_memo_v0_2.md §5.3）。
    ;   ・A/B/X は直上で退避済み → 破壊してよい
    ;   ・分岐前（state==RUNNING 判定の前）→ アイドル中の割込でもACKされる
    ;   ・IRQ0_HANDLER 入口は他経路と非共有 → 誤再武装しない
    ;   ・1割込につき1回だけ通る → ACK重複なし
    ; ★復元部(_sched_found)・保存部への移動は不可（前者=誤再武装/後者=タイマー永久停止）★
    ; 記法は IRQ1_HANDLER の [IRQ_STAT] 参照（L1189/L1210）と同作法。
    ; EQU定数を直接メモリオペランドに書けるためAは不要（破壊するのはBのみ）。
    LDW  B, #$TCR_ACK_REARM     ; $0023 = TIMER_EN|IRQ_EN|IRQ_ACK
    STW  B, [TCR]               ; TCR($FC90) ← ACK＋再武装（状態ビット込みの完全値）
    ;-------------------------------------------------------------------

    ; 現TCBアドレス計算
    LDW  A, [CUR_TASK]
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
    MOV  X, A

    ; v0.12.6 修正: コンテキスト保存は state==RUNNING(2) の時のみ。
    ; _sc_idle(アイドルループ)中のIRQでは CUR_TASK が直前に寝たタスクのまま
    ; のため、保存するとアイドルループPC($031F)を寝たタスクのsaved_pcに
    ; 誤って上書きしてしまう（STORドライバ起床不能バグの原因）。
    LDW  A, [X]
    CMPI A, #2                  ; RUNNING?
    BNE  _irq_sched             ; 非RUNNING（アイドル/WAIT中）→保存スキップ

    ; コンテキスト保存（RUNNINGタスクのみ）
    LDW  A, [IRQ_WK_X]
    STW  A, [X + #6]
    MOV  A, SP
    ADDI A, #4
    STW  A, [X + #4]
    STW  X, [MISC_WK_X]
    MOV  X, SP
    ADDI X, #2
    LDW  A, [X]
    LDW  X, [MISC_WK_X]
    STW  A, [X + #2]
    STW  X, [MISC_WK_X]
    MOV  X, SP
    LDW  A, [X]
    LDW  X, [MISC_WK_X]
    STW  A, [X + #12]
    LDW  A, [IRQ_WK_A]
    STW  A, [X + #8]
    LDW  A, [IRQ_WK_B]          ; v0.12.6: SAVED_B保存
    STW  A, [X + #10]           ; v0.12.6: TCB_SAVED_B

    ; RUNNING→READY
    LDW  A, #1
    STW  A, [X]

_irq_sched:
    LDW  A, [CUR_TASK]
    STW  A, [L1_WK_B]
    ADDI A, #1
_sched:
    CMPI A, #16                 ; MAX_TASKS=16 v0.12.1: #8→#16
    BLT  _sched_chk
    LDW  A, #0
_sched_chk:
    STW  A, [L1_WK_A]
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
    MOV  X, A
    LDW  B, [X]
    CMPI B, #1
    BEQ  _sched_found
    ; --- v0.12.9: 1周検出（★状態チェックの「後」に置くこと★）---
    ; 検出を状態チェックの前に置くと、走査が CUR_TASK+1〜CUR_TASK-1 で
    ; 打ち切られ CUR_TASK 自身が一度も検査されない。IRQ0は割込時の
    ; RUNNINGタスクを RUNNING→READY に落とすがCUR_TASKは据え置くため、
    ; 「唯一の実行可能タスクが直前まで走っていた自分自身」のとき
    ; 永久にスケジュールされなくなる（実測: st3=READY のまま放置）。
    LDW  A, [L1_WK_A]
    LDW  B, [L1_WK_B]           ; B = 開始tid(=CUR_TASK)
    CMP  A, B
    BEQ  _irq_noready           ; 16個すべて検査済でREADY無し→IRETで割込元へ
    ADDI A, #1
    JMP  _sched

; --- v0.12.9: READY不在時の出口（到達は _sched_chk の BEQ _irq_noready のみ）---
; 設計書: yuios_irq0_idle_design_v0_4.md §3.1(2)
;
; ★ここで EI してはならない★
;   v0.2試作では EI/NOP/DI ループでアイドルしたが、EI で受理した IRQ0 が
;   IRQ0_HANDLER に再入し、再入先でもREADY不在のため再び EI …と無限に入れ子化。
;   IRETの実行機会が永久に来ずSPが単調減少しスタックを破壊した（実測 $3FCA→$01C2）。
;   割込ハンドラは run-to-completion を守り、待機は割込ハンドラの外側
;   （カーネルコンテキストの _sc_idle）が担当する。
;
; 直前が JMP _sched（無条件）、末尾が IRET のため、通常フローが本ラベルへ
; 落ち込むこと・本ラベルから _sched_found へ落ち込むことはいずれも無い。
;
; 本経路ではTCBへのコンテキスト保存を行っていない（非RUNNINGのため
; BNE _irq_sched でスキップ済）ので、入口退避の IRQ_WK_* 3本を戻せば
; 中断点が完全復元される。FLAGSはIRETが復元する。
_irq_noready:
    LDW  A, [IRQ_WK_A]          ; 中断時 A を復元
    LDW  B, [IRQ_WK_B]          ; 中断時 B を復元
    LDW  X, [IRQ_WK_X]          ; 中断時 X を復元
    IRET                        ; 割込元へ復帰（アイドルは _sc_idle が担当）

_sched_found:
    LDW  A, [L1_WK_A]
    STW  A, [CUR_TASK]
    LDW  A, #2
    STW  A, [X]
    LDW  A, [X + #6]
    LDW  B, [X + #4]
    SUBI B, #4
    MOV  SP, B
    LDW  B, [X + #2]
    STW  X, [MISC_WK_X]
    MOV  X, SP
    ADDI X, #2
    STW  B, [X]
    LDW  X, [MISC_WK_X]
    LDW  B, [X + #12]
    ORI  B, #$80
    STW  X, [MISC_WK_X]
    MOV  X, SP
    STW  B, [X]
    LDW  X, [MISC_WK_X]
    LDW  B, [X + #8]            ; v0.12.6: B=SAVED_A
    STW  B, [IRQ_WK_A]          ; v0.12.6: 一時退避(保存完了済IRQ_WK_A再利用)
    LDW  B, [X + #10]           ; v0.12.6: B=SAVED_B
    STW  B, [IRQ_WK_B]          ; v0.12.6: 一時退避
    MOV  X, A
    LDW  A, [IRQ_WK_A]          ; v0.12.6: A=SAVED_A復元
    LDW  B, [IRQ_WK_B]          ; v0.12.6: B=SAVED_B復元
    IRET

; ================================================================
; TASK-SLEEP ($01C0)
; コンテキスト保存のみ実施、_sched_common へ JMP
; ================================================================
    .org $01C0
TASK_SLEEP:
    DI

    ; DSPと戻りPCを退避
    STW  X, [SLP_WK_DSP]
    STW  X, [MISC_WK_X]
    MOV  X, SP
    LDW  A, [X]
    STW  A, [SLP_WK_PC]
    LDW  X, [MISC_WK_X]

    ; 現TCBアドレス計算
    LDW  A, [CUR_TASK]
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
    MOV  X, A

    ; コンテキスト保存
    LDW  A, [SLP_WK_PC]
    STW  A, [X + #2]
    MOV  A, SP
    ADDI A, #2
    STW  A, [X + #4]
    LDW  A, [SLP_WK_DSP]
    STW  A, [X + #6]
    LDW  A, #$80
    STW  A, [X + #12]
    ; ★v0.12.11 TKT-04(M-1..M-4): saved_a/saved_b に定義済み値(0)を書く
    ;   SYSCALL では A/B は caller-saved（値は保持されない）だが、
    ;   復元経路は中断理由を判別できないため、フィールドは必ず定義済みにする。
    ;   設計書: yuios_ctxsw_abreg_restore_design_v0_2.md §4.3/§5.2
    XOR  A, A                   ; A = 0（LDW A,#0 は 4B、XOR は 2B）
    STW  A, [X + #8]            ; saved_a = 0
    STW  A, [X + #10]           ; saved_b = 0
    LDW  A, #3
    STW  A, [X]                 ; SLEEPING

    ; SPをカーネルスタックに切り替え
    LDW  A, #$477E              ; v0.12.3: $FBCE→$477E (KERN_SP_TOP)
    MOV  SP, A

    ; 共通スケジューラへ
    JMP  _sched_common

; ================================================================
; _sched_common ($02C0)
; TASK_SLEEP / TASK_EXIT から JMP で呼び出される共通スケジューラ
; 入力: SP=カーネルSP($FBCE), CUR_TASK=現タスク
; 動作: READYタスクを探してコンテキスト復元+IRET
; ================================================================
    .org $02C0
_sched_common:
    LDW  A, [CUR_TASK]
    STW  A, [L1_WK_B]          ; 開始tid（1周検出用）
    ADDI A, #1
_sc_sched:
    CMPI A, #16                 ; MAX_TASKS=16 v0.12.1: #8→#16
    BLT  _sc_chk
    LDW  A, #0
_sc_chk:
    LDW  B, [L1_WK_B]          ; 開始tidと比較（読むだけ）
    CMP  A, B
    BEQ  _sc_idle
    STW  A, [L1_WK_A]
    ; TCBアドレス計算（L1_WK_Bは上書きしない）
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
    MOV  X, A
    LDW  B, [X]
    CMPI B, #1
    BEQ  _sc_found
    LDW  A, [L1_WK_A]
    ADDI A, #1
    JMP  _sc_sched
_sc_idle:
    EI
    NOP
    DI
    JMP  _sched_common

_sc_found:
    DI
    LDW  A, [L1_WK_A]
    STW  A, [CUR_TASK]
    LDW  A, #2
    STW  A, [X]                 ; RUNNING
    LDW  A, [X + #6]            ; 次DSP
    LDW  B, [X + #4]
    SUBI B, #4
    MOV  SP, B
    LDW  B, [X + #2]
    STW  X, [MISC_WK_X]
    MOV  X, SP
    ADDI X, #2
    STW  B, [X]
    LDW  X, [MISC_WK_X]
    LDW  B, [X + #12]
    ORI  B, #$80
    STW  X, [MISC_WK_X]
    MOV  X, SP
    STW  B, [X]
    LDW  X, [MISC_WK_X]
    ; ★v0.12.11 TKT-04(M-5): saved_a/saved_b を復元
    ;   _sched_found(L603-609) は saved_b も IRQ_WK_B へ退避するが、
    ;   MOV X,A / LDW A,[abs] は B を破壊しないため往復は不要（8B冗長）。
    ;   一時退避が要るのは X を潰す前に読む saved_a のみ。
    ;   B の上書きは安全: フラグは L728 STW B,[X] で格納済み。
    ;   設計書: yuios_ctxsw_abreg_restore_design_v0_2.md §5.3
    ; ★陰性対照(_negM5_poc): TKT-04 M-5 のみ無効化（設計書 v0.3 §4.5）
    ;   LDW  B, [X + #8]            ; B = saved_a
    ;   STW  B, [IRQ_WK_A]          ; 一時退避（X を潰す前に逃がす）
    ;   LDW  B, [X + #10]           ; B = saved_b ← そのまま最終値
    MOV  X, A
    ;   LDW  A, [IRQ_WK_A]          ; A = saved_a
    IRET

; ================================================================
; TASK-WAKEUP ($0380)
; SLEEPING(3) or WAIT_IPC(5) → READY
; ================================================================
    .org $0380
TASK_WAKEUP:
    LDW  A, [X]                 ; A = tid (TOS)
    ADDI X, #2
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
    MOV  X, A                   ; X = TCBアドレス
    LDW  A, [X]
    CMPI A, #3
    BEQ  _wakeup_do             ; SLEEPING
    CMPI A, #5
    BEQ  _wakeup_do             ; WAIT_IPC
    JMP  _wakeup_done
_wakeup_do:
    LDW  A, #1
    STW  A, [X]                 ; READY
_wakeup_done:
    RET

; ================================================================
; TASK-PRINT-ID ($03D0)
; デバッグ用 "TN\n" をUART出力
; ================================================================
    .org $03D0
TASK_PRINT_ID:
    STW  X, [MISC_WK_X]
    LDW  X, #$FC80
_tp1:
    LDW  A, [UART_STAT]
    CMPI A, #0
    BEQ  _tp1
    LDW  A, #$54                ; 'T'
    STB  A, [X]
_tp2:
    LDW  A, [UART_STAT]
    CMPI A, #0
    BEQ  _tp2
    LDW  A, [CUR_TASK]
    LDW  B, #$30
    ADD  A, B
    STB  A, [X]
_tp3:
    LDW  A, [UART_STAT]
    CMPI A, #0
    BEQ  _tp3
    LDW  A, #$0A                ; LF
    STB  A, [X]
    LDW  X, [MISC_WK_X]
    RET

; ================================================================
; TASK-ID ($0440)
; ================================================================
    .org $0440
TASK_ID:
    SUBI X, #2
    LDW  A, [CUR_TASK]
    STW  A, [X]
    RET

; ================================================================
; TASK-EXIT ($0460)
; 自タスクをDEAD状態にして _sched_common へ JMP
; ================================================================
    .org $0460
TASK_EXIT:
    DI

    ; 現TCBアドレス計算
    LDW  A, [CUR_TASK]
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
    MOV  X, A

    LDW  A, #0
    STW  A, [X]                 ; DEAD

    LDW  A, #$477E              ; v0.12.3: $FBCE→$477E (KERN_SP_TOP)
    MOV  SP, A
    JMP  _sched_common          ; 共通スケジューラへ
    ; 注: TASK_EXIT は全タスクDEADのとき _sc_idle でEI+NOP+DI ループになる
    ;     完全にDEADな場合はHALTが望ましいが _sched_common 内では
    ;     全DEADと全SLEEPを区別しない。将来版で対応予定。

; ================================================================
; TASK-CREATE ($0520)
; v0.8: TCBサイズ80B, IPC4フィールド初期化
; ================================================================
    .org $0520
TASK_CREATE:
    LDW  A, [X]
    ADDI X, #2
    STW  A, [TC_WK_ENTRY]
    STW  X, [TC_WK_TID]
    DI

    LDW  A, #0
_tc_scan:
    CMPI A, #16                 ; MAX_TASKS=16 v0.12.1: #8→#16
    BEQ  _tc_noslot
    STW  A, [L1_WK_A]
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
    MOV  X, A
    LDW  B, [X]
    CMPI B, #0
    BEQ  _tc_found
    LDW  A, [L1_WK_A]
    ADDI A, #1
    JMP  _tc_scan

_tc_noslot:
    LDW  X, [TC_WK_TID]
    EI
    LDW  A, #$FFFF
    SUBI X, #2
    STW  A, [X]
    RET

_tc_found:
    ; X=空きTCBアドレス, L1_WK_A=tid
    ; コールスタック頂上: $F07E + tid×$80 (tid SHL 7)
    ; 設計書: yuios_memmap_design_v1_1.md §6.4.3（案1: $F07F→$F07E 偶数化）
    LDW  A, [L1_WK_A]
    LDW  B, #7
    SHL  A, B                   ; A = tid × $80
    LDW  B, #$F07E              ; CALLSTK_BASE (tid=0 頂上、偶数)
    ADD  A, B                   ; A = $F07E + tid×$80 = CALLSTK_TOP(tid)
    STW  A, [MISC_WK_X]

    ; TCB初期化
    LDW  A, #1
    STW  A, [X]                 ; READY
    LDW  A, [TC_WK_ENTRY]
    STW  A, [X + #2]
    LDW  A, [MISC_WK_X]
    STW  A, [X + #4]            ; saved_sp

    ; データスタック頂上: $F87E + tid×$80 (tid SHL 7)
    ; 設計書: yuios_memmap_design_v1_1.md §6.4.3（案1: $F87F→$F87E 偶数化）
    LDW  A, [L1_WK_A]
    LDW  B, #7
    SHL  A, B                   ; A = tid × $80
    LDW  B, #$F87E              ; DATASTK_BASE (tid=0 頂上、偶数)
    ADD  A, B                   ; A = $F87E + tid×$80 = DATASTK_TOP(tid)
    STW  A, [X + #6]            ; saved_x (Forth DSP初期値)

    LDW  A, #0
    STW  A, [X + #8]
    STW  A, [X + #10]
    LDW  A, #$80
    STW  A, [X + #12]           ; saved_flags = IE=1
    LDW  A, #$FFFF              ; IDX_NIL v0.12.5
    STW  A, [X + #14]           ; ipc_queue_tail = IDX_NIL (v0.12.5: $6.2)
    LDW  A, #0
    STW  A, [X + #16]
    STW  A, [X + #18]
    STW  A, [X + #20]
    STW  A, [X + #22]
    STW  A, [X + #24]           ; ipc_valid = 0
    STW  A, [X + #26]
    STW  A, [X + #28]
    LDW  A, #$FFFF              ; IDX_NIL v0.12.5
    STW  A, [X + #30]           ; ipc_queue_head = IDX_NIL (v0.12.5: §6.2)

    ; ★v0.12.9(別チケット): EI後に L1_WK_A を読むと、その窓で入った
    ;   IRQ0のスケジューラ走査が L1_WK_A を上書きし、誤ったtidを返す。
    ;   L1_WK_A の読出を EI より前に移動する。
    LDW  A, [L1_WK_A]           ; ★EIより前にtidを確保
    LDW  X, [TC_WK_TID]
    EI
    SUBI X, #2
    STW  A, [X]
    RET

; ================================================================
; TASK0_ENTRY ($0700)
; v0.9: MEM-TEST-TASK Forth ワードの呼び出し
; WORD_MEM_TEST_TASK = $CED4 (kernel_forth_v05.asm.sym より)
; ================================================================
    .org $0700
TASK0_ENTRY:
    JSR $CED4
    JMP TASK0_ENTRY

; ================================================================
; IPC4-SEND ($0740)  ( msg3 msg2 msg1 msg0 tid -- )
; v0.12.5: プール方式に書き換え（設計書 §5.1 _ipc4_enqueue 使用）
; 非ブロッキング送信。プール枯渇時は無視して返る。
; ================================================================
    .org $0740
IPC4_SEND:
    DI
    ; tid を DSP から取り出す
    LDW  A, [X]
    ADDI X, #2
    STW  A, [IPC4_WK_DST]      ; 宛先 tid 保存
    STW  X, [IPC4_WK_X]        ; msg3 先頭 DSP ポインタ保存（_ipc4_enqueue で使用）

    ; _ipc4_enqueue を呼ぶ（DI 済み）
    JSR  _ipc4_enqueue
    ; A=0: OK, A=$FFFE: プール枯渇（SEND は枯渇を無視して返る）

    ; DSP を msg0 の次に進める（msg3/msg2/msg1/msg0 の 4ワード消費）
    LDW  X, [IPC4_WK_X]
    ADDI X, #8                  ; 4ワード × 2B = 8B
    EI
    RET

; ================================================================
; IPC4-RECV ($07E0)  ( -- msg3 msg2 msg1 msg0 )
; v0.12.5: プール dequeue 方式に書き換え（設計書 §5.3）
; キュー空なら WAIT_IPC で寝る。
; ================================================================
    .org $07E0
IPC4_RECV:
    ; v0.12.6: resume合流点を冒頭に統合（独立ブロック削除で9B削減）
    ; WAIT_IPC起床時のsaved_pcは IPC4_RECV 冒頭を指す
    DI
    STW  X, [MISC_WK_X]        ; DSP退避

_ipc4recv_calc_self:
    ; v0.12.5 案A: self_tcb 計算は別アドレスサブルーチン化（サイズ削減）
    JSR  _calc_self_tcb         ; A=self_tcb, X=self_tcb, IPC4_WK_SRCTCB=self_tcb

    ; --- ステップ1: キューが空なら WAIT_IPC で寝る ---
    LDW  A, [X + #30]           ; ipc_queue_head
    CMPI A, #$FFFF              ; == IDX_NIL?
    BNE  _ipc4recv_dequeue
    ; キュー空 → WAIT_IPC でブロック
    LDW  A, #$IPC4_RECV
    STW  A, [X + #2]            ; saved_pc = IPC4_RECV冒頭（v0.12.6統合）
    MOV  A, SP
    ; v0.12.6: saved_pcが自ルーチン冒頭(戻り先でない)のためADDI#2しない
    ;          起床後 $07E0 を再実行し最後にRETするにはSP=寝た時のSPが必要
    STW  A, [X + #4]            ; saved_sp = SP
    LDW  A, [MISC_WK_X]
    STW  A, [X + #6]            ; saved_x = DSP
    LDW  A, #$80
    STW  A, [X + #12]           ; saved_flags = IE=1
    ; ★v0.12.11 TKT-04(M-1..M-4): saved_a/saved_b に定義済み値(0)を書く
    ;   SYSCALL では A/B は caller-saved（値は保持されない）だが、
    ;   復元経路は中断理由を判別できないため、フィールドは必ず定義済みにする。
    ;   設計書: yuios_ctxsw_abreg_restore_design_v0_2.md §4.3/§5.2
    XOR  A, A                   ; A = 0（LDW A,#0 は 4B、XOR は 2B）
    STW  A, [X + #8]            ; saved_a = 0
    STW  A, [X + #10]           ; saved_b = 0
    LDW  A, #5
    STW  A, [X]                 ; state = WAIT_IPC
    LDW  A, #$477E
    MOV  SP, A
    JMP  _sched_common


_ipc4recv_dequeue:
    ; --- ステップ2: キュー先頭エントリ取得 ---
    LDW  A, [X + #30]           ; idx = ipc_queue_head
    STW  A, [IPC4_WK_IDX]

    ; entry_addr = MSG_POOL_BASE + idx × 16
    LDW  B, #4
    SHL  A, B
    LDW  B, #$4500
    ADD  A, B
    STW  A, [L1_WK_A]          ; entry_addr

    ; --- ステップ3: キュー先頭を次に進める ---
    MOV  X, A                   ; X = entry_addr
    LDW  A, [X + #10]           ; nxt = entry.next
    LDW  X, [IPC4_WK_SRCTCB]
    STW  A, [X + #30]           ; ipc_queue_head = nxt
    CMPI A, #$FFFF              ; nxt == IDX_NIL?
    BNE  _ipc4recv_notempty
    STW  A, [X + #14]           ; キュー空になった → tail も NIL
_ipc4recv_notempty:

    ; --- ステップ4: sender を TCB に保存（IPC4-SENDER用）---
    LDW  X, [L1_WK_A]          ; X = entry_addr
    LDW  A, [X + #0]            ; entry.sender
    LDW  X, [IPC4_WK_SRCTCB]
    STW  A, [X + #26]           ; last_sender_tid = entry.sender

    ; --- ステップ5: msg を DSP に push（msg0 先頭、スタックは逆順）---
    ; v0.12.5 案A最適化: ループ化でサイズ削減
    ; v0.12.6: entryポインタを L1_WK_C 常駐化し X退避/復元を撤廃（8B削減）
    ;          → IPC4_RECV スロット超過を解消
    LDW  A, [MISC_WK_X]        ; A = DSP
    STW  A, [L1_WK_TMP]        ; L1_WK_TMP = DSP（カウンタ兼用をやめDSP保持）
    LDW  A, [L1_WK_A]
    ADDI A, #10                 ; A = &entry.msg[3]+2
    STW  A, [L1_WK_C]          ; L1_WK_C = entryポインタ
    LDW  B, #4                  ; B = ループカウンタ
_msg_copy_loop:
    LDW  X, [L1_WK_C]          ; X = entryポインタ
    SUBI X, #2
    STW  X, [L1_WK_C]          ; entryポインタ更新
    LDW  A, [X]                 ; A = msg[i]
    LDW  X, [L1_WK_TMP]        ; X = DSP
    SUBI X, #2
    STW  X, [L1_WK_TMP]        ; DSP更新
    STW  A, [X]                 ; DSP に push
    SUBI B, #1                  ; v0.12.6: SUBIがZフラグを更新するためCMPI不要（4B削減）
    BNE  _msg_copy_loop
    ; L1_WK_TMP = 最終DSP

    ; --- ステップ6: エントリをフリーリストに返却 (O(1) free) ---
    LDW  B, [MSG_POOL_FREE]     ; B = old free_head
    LDW  X, [L1_WK_A]          ; X = entry_addr
    STW  B, [X + #10]           ; entry.next = old MSG_POOL_FREE
    LDW  A, [IPC4_WK_IDX]
    STW  A, [MSG_POOL_FREE]     ; MSG_POOL_FREE = idx

    ; v0.12.6: 最終DSPをXに復元（CODEワード規約: XでDSPを返す）
    LDW  X, [L1_WK_TMP]
    EI
    RET

; ================================================================
; IPC4-CALL ($08C0)  ( msg3 msg2 msg1 msg0 tid -- r3 r2 r1 r0 )
; v0.12.5: プール方式に書き換え（設計書 §5.2）
; _ipc4_enqueue → WAIT_REPLY で寝る → RESUME で reply バッファから取得
; ================================================================
    .org $08C0
IPC4_CALL:
    DI
    ; tid を取り出す
    LDW  A, [X]
    ADDI X, #2
    STW  A, [IPC4_WK_DST]
    STW  X, [IPC4_WK_X]        ; msg3 先頭 DSP ポインタ保存

    ; --- ステップ1: _ipc4_enqueue ---
    JSR  _ipc4_enqueue
    CMPI A, #$FFFE              ; ERR_IPC_NOSLOT?
    BNE  _ipc4call_enq_ok

    ; プール枯渇 → (ERR_IPC_NOSLOT, 0, 0, 0) をDSPに積んで即返却（§5.5）
    LDW  X, [IPC4_WK_X]
    ADDI X, #8                  ; msg3/2/1/0 の4ワード消費
    LDW  A, #0
    SUBI X, #2
    STW  A, [X]                 ; r0 = 0
    SUBI X, #2
    STW  A, [X]                 ; r1 = 0
    SUBI X, #2
    STW  A, [X]                 ; r2 = 0
    LDW  A, #$FFFE              ; ERR_IPC_NOSLOT
    SUBI X, #2
    STW  A, [X]                 ; r3 = ERR_IPC_NOSLOT
    EI
    RET

_ipc4call_enq_ok:
    ; DSP を msg0 の次に進める
    LDW  X, [IPC4_WK_X]
    ADDI X, #8
    STW  X, [IPC4_WK_X]        ; 消費後DSP保存（RESUME で使用）

    ; --- ステップ2: 自分の reply フィールドをクリア ---
    LDW  A, [CUR_TASK]
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
    ADD  A, B                   ; A = &self_tcb
    STW  A, [IPC4_WK_SRCTCB]
    MOV  X, A
    LDW  A, #0
    STW  A, [X + #24]           ; ipc_valid = 0

    ; --- ステップ3: WAIT_REPLY に遷移してスケジューラへ ---
    LDW  A, #$IPC4_CALL_RESUME
    STW  A, [X + #2]            ; saved_pc = IPC4_CALL_RESUME
    MOV  A, SP
    ; v0.12.6: saved_pcが別ルーチン(戻り先でない)のためADDI#2しない
    STW  A, [X + #4]            ; saved_sp = SP
    LDW  A, [IPC4_WK_X]
    STW  A, [X + #6]            ; saved_x = 消費後DSP
    LDW  A, #$80
    STW  A, [X + #12]           ; saved_flags = IE=1
    ; ★v0.12.11 TKT-04(M-1..M-4): saved_a/saved_b に定義済み値(0)を書く
    ;   SYSCALL では A/B は caller-saved（値は保持されない）だが、
    ;   復元経路は中断理由を判別できないため、フィールドは必ず定義済みにする。
    ;   設計書: yuios_ctxsw_abreg_restore_design_v0_2.md §4.3/§5.2
    XOR  A, A                   ; A = 0（LDW A,#0 は 4B、XOR は 2B）
    STW  A, [X + #8]            ; saved_a = 0
    STW  A, [X + #10]           ; saved_b = 0
    LDW  A, #6
    STW  A, [X]                 ; state = WAIT_REPLY
    LDW  A, #$477E
    MOV  SP, A
    JMP  _sched_common

IPC4_CALL_RESUME:
    ; --- ステップ4: TCBの reply バッファ → DSP に転記 ---
    DI
    LDW  A, [CUR_TASK]
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
    ; X はスケジューラ復元で DSP になっている
    STW  X, [IPC4_WK_X]
    LDW  X, [IPC4_WK_SRCTCB]

    LDW  A, [X + #22]           ; ipc_msg[3]
    LDW  X, [IPC4_WK_X]
    SUBI X, #2
    STW  A, [X]
    STW  X, [IPC4_WK_X]

    LDW  X, [IPC4_WK_SRCTCB]
    LDW  A, [X + #20]           ; ipc_msg[2]
    LDW  X, [IPC4_WK_X]
    SUBI X, #2
    STW  A, [X]
    STW  X, [IPC4_WK_X]

    LDW  X, [IPC4_WK_SRCTCB]
    LDW  A, [X + #18]           ; ipc_msg[1]
    LDW  X, [IPC4_WK_X]
    SUBI X, #2
    STW  A, [X]
    STW  X, [IPC4_WK_X]

    LDW  X, [IPC4_WK_SRCTCB]
    LDW  A, [X + #16]           ; ipc_msg[0]
    LDW  B, #0
    STW  B, [X + #24]           ; ipc_valid = 0（消費完了）
    LDW  X, [IPC4_WK_X]
    SUBI X, #2
    STW  A, [X]
    EI
    RET

; ================================================================
; IPC4-REPLY ($0B00)  ( r3 r2 r1 r0 tid -- )
; v0.12.5: 内部実装維持（プール不使用・TCB reply バッファ直書込）
;   設計書 §5.4 との整合: reply 経路はプールを使わない（変更小）
;   注: +26(last_sender_tid) へのCUR_TASK書込は既存コード互換のため維持
; ================================================================
    .org $0B00
IPC4_REPLY:
    DI
    LDW  A, [X]
    ADDI X, #2
    STW  X, [MISC_WK_X]
    STW  A, [IPC4_WK_DST]
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
    LDW  X, [MISC_WK_X]
    LDW  A, [X]
    ADDI X, #2
    STW  X, [MISC_WK_X]
    LDW  X, [IPC4_WK_SRCTCB]
    STW  A, [X + #16]
    LDW  X, [MISC_WK_X]
    LDW  A, [X]
    ADDI X, #2
    STW  X, [MISC_WK_X]
    LDW  X, [IPC4_WK_SRCTCB]
    STW  A, [X + #18]
    LDW  X, [MISC_WK_X]
    LDW  A, [X]
    ADDI X, #2
    STW  X, [MISC_WK_X]
    LDW  X, [IPC4_WK_SRCTCB]
    STW  A, [X + #20]
    LDW  X, [MISC_WK_X]
    LDW  A, [X]
    ADDI X, #2
    STW  X, [MISC_WK_X]
    LDW  X, [IPC4_WK_SRCTCB]
    STW  A, [X + #22]
    LDW  A, #1
    STW  A, [X + #24]
    LDW  A, [CUR_TASK]
    STW  A, [X + #26]
    LDW  A, [X]
    CMPI A, #6
    BNE  _ipc4reply_done
    LDW  A, #1
    STW  A, [X]
_ipc4reply_done:
    LDW  X, [MISC_WK_X]
    EI
    RET


; ================================================================
; IRQ1ハンドラ ($0D00)  v0.10新設
; UART RX割り込み処理 (YSD8001 RX → YSD8004 IRQ_STAT bit0)
; yuios_ph3_uart_design_v1_2.docx §5.3
;
; 処理順序 (必須 - 順序変更禁止):
;   S0: A/B/X退避
;   S1/S2: IRQ_STAT bit0確認 (UART RX由来判定)
;   S3: UART_RX読出 (副作用なし - RX_READYはクリアされない)
;   S4: rx_push(byte) → リングバッファ格納
;   S5: UART_STAT WTC ($0002書込) → RX_READYクリア [最重要: S6より先]
;   S6: IRQ_STAT WTC (bit0クリア) [S5より後である必要あり]
;   S7: UART_WAIT_TIDが非0なら wake_uart_waiter
;   S8: A/B/X復帰, IRET
;
; 警告: S5を欠くとRX_READY=1継続→IRQ1無限ループ
; 警告: S5/S6順序逆転でも多重発火する (§5.2参照)
; ================================================================
    .org $0D00
IRQ1_HANDLER:
    ; --- S0: レジスタ退避 ---
    STW  A, [IRQ1_WK_A]
    STW  B, [IRQ1_WK_B]
    STW  X, [IRQ1_WK_X]

    ; --- v0.11: IRQ_STAT を読み出して保存（bit0/bit1 順次評価のため）---
    LDW  A, [IRQ_STAT]
    STW  A, [IRQ1_WK_STAT]

    ; --- S1/S2: bit0 (UART RX) 確認 ---
    ANDI A, #$0001
    BEQ  _irq1_skip_uart        ; UART RXでなければスキップ

    ; --- S3: UART_RX読出 (RX_READYはクリアされない) ---
    LDW  A, [UART_RX]
    ANDI A, #$00FF              ; 下位8bitのみが受信値

    ; --- S4: リングバッファ書込 ---
    JSR  rx_push                ; A=byte を push (COUNT>=16なら破棄)

    ; --- S5: UART_STAT WTC (RX_READYクリア) ---
    ; 【最重要】S6より前に実行すること。逆順で多重発火する。
    LDW  B, #$0002
    STW  B, [UART_STAT]

    ; --- S6: IRQ_STAT WTC (bit0クリア) ---
    LDW  B, #$0001
    STW  B, [IRQ_STAT]

    ; --- S7: 待機中クライアントを起こす ---
    JSR  wake_uart_waiter

_irq1_skip_uart:
    ; --- v0.11: bit1 (STOR) 分岐 ---
    ; yuios_ph3_storage_design_v1_2.md §5.2 / §5.3
    LDW  A, [IRQ1_WK_STAT]
    ANDI A, #$0002
    BEQ  _irq1_done             ; STORでなければ終了
    JSR  _handle_stor

_irq1_done:
    ; --- S8: レジスタ復帰, IRET ---
    LDW  A, [IRQ1_WK_A]
    LDW  B, [IRQ1_WK_B]
    LDW  X, [IRQ1_WK_X]
    IRET

; ================================================================
; rx_push  (IRQ1_HANDLERから呼ばれる)
; 入力: A = 受信バイト (下位8bit有効)
; 破壊: A, B, X (退避なし - 呼び出し元IRQ1_HANDLERが全退避済)
; yuios_ph3_uart_design_v1_2.docx §5.4
;
; 更新順序: HEAD先 → COUNT後 (逆順禁止)
; COUNT>=16の場合は破棄 (オーバーラン)
; ================================================================
rx_push:
    STW  A, [IRQ1_WK_BYTE]     ; byte退避

    LDW  A, [UART_RX_COUNT]
    LDW  B, #16
    CMP  A, B
    BGE  _rx_push_overrun       ; COUNT >= 16 → 破棄

    ; --- (1) データ書込 ---
    LDW  B, [UART_RX_HEAD]     ; B = HEAD (インデックス 0-15)
    LDW  A, #$FC46              ; UART_RX_RING_BUF v0.12.0: $F020→$FC46
    ADD  A, B                   ; A = &buf[HEAD]
    MOV  X, A                   ; X = &buf[HEAD]
    LDW  A, [IRQ1_WK_BYTE]
    STB  A, [X]                 ; buf[HEAD] = byte (STB A,[X])

    ; --- (2) HEAD更新 (先) ---
    LDW  A, [UART_RX_HEAD]     ; A = 現HEAD
    ADDI A, #1
    ANDI A, #$000F              ; HEAD = (HEAD + 1) mod 16
    STW  A, [UART_RX_HEAD]

    ; --- (3) COUNT更新 (後) ---
    LDW  A, [UART_RX_COUNT]
    ADDI A, #1
    STW  A, [UART_RX_COUNT]

_rx_push_overrun:
    RET

; (wake_uart_waiter / rx_pop は本ファイル末尾の .org $1200 領域に配置)
; v0.11では IRQ1_HANDLER 拡張により $0DXX 領域に収まらなくなったため移動

; ================================================================
; カーネル初期化 ($0E00)
; ================================================================
    .org $0E00
_kstart:
    LDW  SP, #$477E              ; v0.12.3: $FBCE→$477E (KERN_SP_TOP)
    LDW  X, #$F800
    DI

    ; ================================================================
    ; KERN_SP 専用領域ゼロクリア + canary設置 v0.12.3新設
    ; 設計書: yuios_memmap_design_v1_1.md §6.3・§7.1
    ;   領域: $4700-$477F (128B = 64ワード)
    ;   1. 全領域を0クリア
    ;   2. $4700 (先頭) に canary $A55A を設置
    ;      → CHK-GUARD でスタックオーバーラン検出に使用（Step 8以降）
    ; ================================================================
    LDW  A, #0
    LDW  X, #$4700
_init_kernsp:
    CMPI X, #$4780               ; v0.12.3修正: CMP→CMPI（即値比較には CMPI を使用）
    BGE  _init_kernsp_done
    STW  A, [X]
    ADDI X, #2
    JMP  _init_kernsp
_init_kernsp_done:
    LDW  A, #$A55A
    LDW  X, #$4700
    STW  A, [X]                  ; canary $A55A at $4700

    ; ================================================================
    ; stack guard 領域初期化 v0.12.4新設
    ; 設計書: yuios_memmap_design_v1_1.md §4.1・§7.1
    ;   領域: $FC00-$FC3F (64B = 32ワード)
    ;   $A55A 埋め: データスタックオーバーフロー時の MMIO 即突入防止
    ;   CHK-GUARD ワード（Step 8以降）で全32ワード $A55A 確認により破壊検出
    ; ================================================================
    LDW  A, #$A55A
    LDW  X, #$FC00               ; GUARD_BASE
_init_guard:
    CMPI X, #$FC40               ; GUARD_BASE + $40 (64B), 即値比較にはCMPI使用
    BGE  _init_guard_done
    STW  A, [X]
    ADDI X, #2
    JMP  _init_guard
_init_guard_done:

    ; 全TCBゼロクリア (16タスク×80B) v0.12.1: 8→16タスク
    LDW  B, #0
_init_tcb:
    CMPI B, #16                 ; MAX_TASKS=16 v0.12.1: #8→#16
    BEQ  _init_done
    STW  B, [L1_WK_A]
    MOV  A, B
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
    MOV  X, A
    LDW  A, #0
    STW  A, [X + #0]
    STW  A, [X + #2]
    STW  A, [X + #4]
    STW  A, [X + #6]
    STW  A, [X + #8]
    STW  A, [X + #10]
    STW  A, [X + #12]
    STW  A, [X + #14]
    STW  A, [X + #16]
    STW  A, [X + #18]
    STW  A, [X + #20]
    STW  A, [X + #22]
    STW  A, [X + #24]
    STW  A, [X + #26]
    STW  A, [X + #28]
    STW  A, [X + #30]
    STW  A, [X + #32]
    STW  A, [X + #34]
    STW  A, [X + #36]
    STW  A, [X + #38]
    STW  A, [X + #40]
    STW  A, [X + #42]
    STW  A, [X + #44]
    STW  A, [X + #46]
    STW  A, [X + #48]
    STW  A, [X + #50]
    STW  A, [X + #52]
    STW  A, [X + #54]
    STW  A, [X + #56]
    STW  A, [X + #58]
    STW  A, [X + #60]
    STW  A, [X + #62]
    STW  A, [X + #64]
    STW  A, [X + #66]
    STW  A, [X + #68]
    STW  A, [X + #70]
    STW  A, [X + #72]
    STW  A, [X + #74]
    STW  A, [X + #76]
    STW  A, [X + #78]
    LDW  B, [L1_WK_A]
    ADDI B, #1
    JMP  _init_tcb
_init_done:

    ; UART変数初期化 v0.12.0: $F030-$F038 → $FC56-$FC5E（OS共有変数領域）
    ; yuios_ph3_uart_design_v1_2.docx §4.2 (要 v1.3 改版・Ph.3.5完了時に一括対応)
    LDW  A, #0
    LDW  X, #$FC56
    STW  A, [X]              ; UART_RX_HEAD($FC56) = 0
    LDW  X, #$FC58
    STW  A, [X]              ; UART_RX_TAIL($FC58) = 0
    LDW  X, #$FC5A
    STW  A, [X]              ; UART_RX_COUNT($FC5A) = 0
    LDW  X, #$FC5C
    STW  A, [X]              ; UART_DRV_TID($FC5C) = 0
    LDW  X, #$FC5E
    STW  A, [X]              ; UART_WAIT_TID($FC5E) = 0

    ; ストレージ専用変数初期化 v0.12.0: $F050-$F054 → $FC64-$FC68
    ; yuios_ph3_storage_design_v1_2.md §2.2 (要 v1.3 改版・Ph.3.5完了時に一括対応)
    LDW  X, #$FC64
    STW  A, [X]              ; STOR_DRV_TID($FC64) = 0
    LDW  X, #$FC66
    STW  A, [X]              ; STOR_WAIT_TID($FC66) = 0
    LDW  X, #$FC68
    STW  A, [X]              ; STOR_LAST_STAT($FC68) = 0

    ; テスト文字列 "BC\0" を BC_STR($FC60) に配置 v0.12.0: $F040→$FC60
    LDW  X, #$FC60
    LDW  A, #$42             ; 'B'
    STB  A, [X]
    LDW  X, #$FC61
    LDW  A, #$43             ; 'C'
    STB  A, [X]
    LDW  X, #$FC62
    LDW  A, #0               ; NUL
    STB  A, [X]

    ; TCB0 = OS-START（tid=0）
    ; v0.10: Ph.3対応 OS-START から起動（MEMMGR→UART→UART-TEST の順で起動）
    ; v0.12.0: WORD_OS_START = $e988
    ; v0.12.2: スタック頂上を新方式に更新（案1: 偶数化）
    ; v0.12.5: +14(ipc_queue_tail)=IDX_NIL, +30(ipc_queue_head)=IDX_NIL 追加
    LDW  X, #$4000
    LDW  A, #1
    STW  A, [X]              ; READY（後でRUNNINGに変更）
    LDW  A, #$e96e
    STW  A, [X + #2]         ; PC = WORD_OS_START
    LDW  A, #$F07E
    STW  A, [X + #4]         ; saved_sp（コールスタック top）
    LDW  A, #$F87E
    STW  A, [X + #6]         ; saved_x（データスタック top）
    LDW  A, #$80
    STW  A, [X + #12]        ; FLAGS
    LDW  A, #$FFFF           ; IDX_NIL
    STW  A, [X + #14]        ; ipc_queue_tail = IDX_NIL  v0.12.5
    STW  A, [X + #30]        ; ipc_queue_head = IDX_NIL  v0.12.5

    ; TCB1以降: DEAD状態のまま（OS-STARTがTASK-CREATEで動的に生成）

    ; MsgPool 初期化 v0.12.5 (§6.1: フリーリスト構築)
    JSR init_msg_pool

    ; MEM-TID-ADDR ($FC44) = 0（MemMgr は tid=0 → OS-STARTが再設定）
    LDW  A, #0
    STW  A, [MEM_TID_ADDR]

    LDW  A, #1
    STW  A, [TASK_COUNT]     ; 起動タスク数 = 1（tid=0のみ）
    LDW  A, #0
    STW  A, [CUR_TASK]

    ; tid=0（OS-START）を RUNNING で直接起動
    ; v0.12.2: SP=$F07A (=$F07E - 4) に変更（偶数アドレス）
    ;          IRETで [SP+2]にPC, [SP]にFLAGS を書く → 頂上=$F07E
    ;          X=$F87E (DATASTK_TOP tid=0, 偶数)
    LDW  X, #$4000
    LDW  A, #2
    STW  A, [X]              ; RUNNING
    LDW  A, #$F07A           ; v0.12.2: $FBCA→$F07A (CALLSTK_TOP-4, 偶数)
    MOV  SP, A
    MOV  X, SP
    ADDI X, #2
    LDW  A, #$e96e           ; WORD_OS_START
    STW  A, [X]
    MOV  X, SP
    LDW  A, #$80
    STW  A, [X]
    LDW  X, #$F87E           ; v0.12.2: $FB4E→$F87E (DATASTK_TOP tid=0, 偶数)
    IRET

; ================================================================
; v0.11追加: STORハンドラ群 ($1000-)
; _kstart領域($0E00-)の安全な後方に配置
; ================================================================
    .org $1000

; ================================================================
; _handle_stor  (IRQ1_HANDLERから呼ばれる) v0.11追加
; YSD8003 EXEC 完了処理（軽量版・順序固守）
; yuios_ph3_storage_design_v1_2.md §5.3
;
; 責務: STAT保存（必ず非0値）・後始末・state遷移のみ
;       (ipc_msg書込・IPC4_REPLYはドライバ側に移行)
;
; 【★ 順序固守: ST1→ST2→ST3→ST4→ST5 - レビュー指摘IR4】
;   ST1: SD_STAT 読出（必ず非0値が返る）
;   ST2: STOR_LAST_STAT に保存（ドライバの完了通知シグナル）
;   ST3: SD_IRQ_CTRL ← 0（§4.7 冪等性ルール）
;   ST4: IRQ_STAT WTC bit1
;   ST5: wake_stor_waiter（state遷移のみ）
;
; emu23 v1.03 仕様: SD_STATは必ず非0値(READY=0x04 or ERROR=0x02)を返す
;
; 入力: なし (レジスタはIRQ1_HANDLERが全退避済)
; 破壊: A, B, X
; ================================================================
_handle_stor:
    ; --- ST1: SD_STAT 読出（BUSYラッチクリア: 1回目でBUSYが出る可能性があるため2回読み）---
    ; emu23 v1.03 仕様: 1回目はBUSY(0x01)が返る場合あり、2回目で実値(READY=0x04 or ERROR=0x02)
    LDW  A, [SD_STAT]       ; 1回目（BUSYラッチクリア）
    LDW  A, [SD_STAT]       ; 2回目（実際の値）

    ; --- ST2: STOR_LAST_STAT に保存（ドライバの完了通知シグナル）---
    STW  A, [STOR_LAST_STAT]

    ; --- ST3: SD_IRQ_CTRL ← 0（§4.7 冪等性ルール）---
    LDW  A, #0
    STW  A, [SD_IRQ_CTRL]

    ; --- ST4: IRQ_STAT WTC（bit1のみクリア）---
    LDW  A, #$0002
    STW  A, [IRQ_STAT]

    ; --- ST5: STOR_WAIT_TID が非0なら state遷移のみ実行 ---
    JSR  wake_stor_waiter

    RET

; ================================================================
; wake_stor_waiter  (IRQ1_HANDLERから呼ばれる) v0.11追加
; yuios_ph3_storage_design_v1_2.md §5.4
; ★ v0.11.1: 解釈A適用 (soudan3.txt) - state==5(WAIT_IPC)対象に修正
;
; state遷移のみ実施（軽量版）
; ipc_msg/ipc_valid/ipc_sender はドライバが自身でREPLY時に設定
;
; UART版 wake_uart_waiter とは非対称。
; 「IRQ完了通知」=「ドライバ自身を WAIT_IPC → READY に遷移」のみ。
; （UART版はクライアントを WAIT_REPLY → READY に遷移、
;   STOR版はドライバ自身を起こす点で本質的に異なる）
;
; STOR_WAIT_TID には【ドライバ自身のtid】が入る (※soudan3.txt 解釈A)
; STOR_WAIT_TIDのクリアは行わない（ドライバ側のR4で行う）
; ※ 理由: ドライバが起床直後にWAIT-TIDを見て「自分が起こされた」を確認できるようにするため
; ※ ドライバのERROR経路でもクリアされる（§12 IR3で実装担当が確認）
;
; 入力: なし (レジスタはIRQ1_HANDLERが全退避済)
; 破壊: A, B, X
; ================================================================
wake_stor_waiter:
    LDW  A, [STOR_WAIT_TID]
    BEQ  _wake_stor_done        ; tid==0 ならスキップ

    ; tid → TCBアドレス計算 (UART版と同一の5命令ブロック)
    STW  A, [L1_WK_TMP]         ; tid退避
    LDW  B, #6
    SHL  A, B                   ; A = tid*64
    STW  A, [L1_WK_C]
    LDW  A, [L1_WK_TMP]
    LDW  B, #4
    SHL  A, B                   ; A = tid*16
    LDW  B, [L1_WK_C]
    ADD  A, B                   ; A = tid*80
    LDW  B, #$4000
    ADD  A, B                   ; A = TCBアドレス
    MOV  X, A

    ; ★ 削除: ipc_msg[0..3] 書込なし
    ; ★ 削除: ipc_valid = 1 なし
    ; ★ 削除: ipc_sender = CUR_TASK なし

    ; ★ v0.11.1: state==5(WAIT_IPC)なら1(READY)へ遷移
    ; (旧設計書 v1.2 §5.4 の WAIT_REPLY=6 は誤りで soudan3.txt 解釈A 適用)
    LDW  A, [X]                 ; state取得
    CMPI A, #5                  ; TASK_WAIT_IPC?
    BNE  _wake_stor_no_state_change
    LDW  A, #1
    STW  A, [X]                 ; TASK_READY

_wake_stor_no_state_change:
    ; ★ 削除: STOR_WAIT_TID クリアなし（ドライバ側R4で行う）

_wake_stor_done:
    RET

; ================================================================
; TASK_WAIT_IPC_ENTRY ($1100) v0.11.1追加
; ドライバ自身を WAIT_IPC(5) 状態にして寝かす
;
; 注: 定数名 TASK_WAIT_IPC=5 と衝突するためラベル名は _ENTRY 付きに
;
; TASK_SLEEP との違い:
;   - TASK_SLEEP は state=3 (SLEEPING) にする (TASK_WAKEUPで起こす)
;   - TASK_WAIT_IPC_ENTRY は state=5 (WAIT_IPC) にする
;     (IRQ1 の wake_stor_waiter 経由で起こす)
;
; 用途: ストレージドライバが EXEC 後に IRQ 待ちで寝る (§4.4 G9)
; soudan3.txt 解釈A適用
;
; 入力: なし (Forth から JSR で呼ぶ)
; 動作: 自TCBに state=5 と context を保存 → _sched_common へ
;       (起床時はTASK_SLEEP同様、復元してJMP→IRET風に再開)
;
; TASK_SLEEP のコピーベースで実装、state定数のみ 3→5 に変更
; ================================================================
    .org $1100
TASK_WAIT_IPC_ENTRY:
    DI

    ; DSPと戻りPCを退避 (TASK_SLEEPと同じ)
    STW  X, [SLP_WK_DSP]
    STW  X, [MISC_WK_X]
    MOV  X, SP
    LDW  A, [X]
    STW  A, [SLP_WK_PC]
    LDW  X, [MISC_WK_X]

    ; 現TCBアドレス計算
    LDW  A, [CUR_TASK]
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
    MOV  X, A

    ; コンテキスト保存 (TASK_SLEEPと同じ)
    LDW  A, [SLP_WK_PC]
    STW  A, [X + #2]
    MOV  A, SP
    ADDI A, #2
    STW  A, [X + #4]
    LDW  A, [SLP_WK_DSP]
    STW  A, [X + #6]
    LDW  A, #$80
    STW  A, [X + #12]
    ; ★v0.12.11 TKT-04(M-1..M-4): saved_a/saved_b に定義済み値(0)を書く
    ;   SYSCALL では A/B は caller-saved（値は保持されない）だが、
    ;   復元経路は中断理由を判別できないため、フィールドは必ず定義済みにする。
    ;   設計書: yuios_ctxsw_abreg_restore_design_v0_2.md §4.3/§5.2
    XOR  A, A                   ; A = 0（LDW A,#0 は 4B、XOR は 2B）
    STW  A, [X + #8]            ; saved_a = 0
    STW  A, [X + #10]           ; saved_b = 0
    LDW  A, #5                  ; ★ 5=TASK_WAIT_IPC (TASK_SLEEPの3=SLEEPINGとの差分)
    STW  A, [X]

    ; SPをカーネルスタックに切り替え
    LDW  A, #$477E              ; v0.12.3: $FBCE→$477E (KERN_SP_TOP)
    MOV  SP, A

    ; 共通スケジューラへ
    JMP  _sched_common

; ================================================================
; v0.11.1: wake_uart_waiter / rx_pop 移動配置 ($1200)
; v0.11で IRQ1_HANDLER 拡張(STAT保存+bit1分岐)により $0DXX 領域内に
; 収まらなくなったため、_kstart領域($0E00-)の安全な後方に移動。
; IRQ1_HANDLER からは JSR で呼べる距離(16bitアドレス空間内)。
; ================================================================
    .org $1200

; ================================================================
; wake_uart_waiter  (IRQ1_HANDLERから呼ばれる)
; UART_GETC待ちクライアントへ直接REPLY相当処理を実施する
;
; 【必須ルール】本サブルーチンはIPC4_REPLY をコピーベースに
; 実装している。将来IPC4_REPLYが拡張された場合は本関数も追従すること。
; (yuios_ph3_uart_design_v1_2.docx §5.5.1 / §10.4 規約3)
;
; 入力: UART_WAIT_TID = 待ちクライアントtid (0=なし)
;       UART_RX_COUNT > 0（★v0.12.10 TKT-02 I-03(a): 必須。
;         rx_pop が COUNT>0 を要求する（rx_pop ヘッダ「入力: COUNT>0」参照）。
;         現状は呼出元 IRQ1_HANDLER S4 の JSR rx_push 直後であることで保証される。
;         別経路から呼ぶ場合は呼出側で COUNT>0 を保証すること。
;         設計書: yuios_uart_rxring_fix_design_v0_3.md §6.1/§6.5）
; 出力: クライアントTCBに ipc_msg[0]=byte, ipc_valid=1, state=READY
;       UART_WAIT_TID = 0 (クリア)
; 破壊: A, B, X (呼び出し元IRQ1_HANDLERが全退避済)
; IRQコンテキスト内なのでDI/EIは不要
; yuios_ph3_uart_design_v1_2.docx §5.5
; ================================================================
wake_uart_waiter:
    ; A2': UART_WAIT_TIDからtid取得 (DSP不使用)
    LDW  A, [UART_WAIT_TID]
    BEQ  _wake_done             ; 0なら待機者なし

    ; A3: tid → TCBアドレス計算
    STW  A, [L1_WK_TMP]        ; tid退避
    LDW  B, #6
    SHL  A, B                   ; A = tid*64
    STW  A, [L1_WK_C]          ; tid*64退避
    LDW  A, [L1_WK_TMP]        ; tid復元
    LDW  B, #4
    SHL  A, B                   ; A = tid*16
    LDW  B, [L1_WK_C]          ; B = tid*64
    ADD  A, B                   ; A = tid*80
    LDW  B, #$4000
    ADD  A, B                   ; A = TCBアドレス
    STW  A, [IPC4_WK_SRCTCB]   ; IPC4_REPLYと同じワーク変数を流用
    MOV  X, A                   ; X = TCBアドレス

    ; A4': ipc_msg[0]=byte (rx_pop結果), msg[1..3]=0
    JSR  rx_pop                 ; A = byte (下位8bit)
    ; ★v0.12.9: rx_pop は X を破壊する（X=&buf[TAIL] のまま復帰）ため
    ;   TCBポインタを復元する。欠落していると以降の [X+#nn] 書込が
    ;   リングバッファ領域に着弾し、特に TAIL=0 のとき [X+#24](ipc_valid)
    ;   が UART_WAIT_TID($FC5E) を破壊して待機者が永久に起床しない。
    LDW  X, [IPC4_WK_SRCTCB]    ; ★X = TCBアドレス を復元（A は保持）
    STW  A, [X + #16]           ; TCB+16 = ipc_msg[0] = byte
    LDW  A, #0
    STW  A, [X + #18]           ; TCB+18 = ipc_msg[1] = 0
    STW  A, [X + #20]           ; TCB+20 = ipc_msg[2] = 0
    STW  A, [X + #22]           ; TCB+22 = ipc_msg[3] = 0

    ; A5: ipc_valid = 1
    LDW  A, #1
    STW  A, [X + #24]           ; TCB+24 = ipc_valid

    ; A6: ipc_sender = CUR_TASK
    LDW  A, [CUR_TASK]
    STW  A, [X + #26]           ; TCB+26 = ipc_sender

    ; A7: state==6(WAIT_REPLY)なら1(READY)へ遷移
    LDW  A, [X]                 ; state取得
    CMPI A, #6                  ; TASK_WAIT_REPLY?
    BNE  _wake_no_state_change
    LDW  A, #1
    STW  A, [X]                 ; TASK_READY

_wake_no_state_change:
    ; UART_WAIT_TID = 0 (待機解除 - 最後に行うこと)
    LDW  A, #0
    STW  A, [UART_WAIT_TID]

_wake_done:
    RET

; ================================================================
; rx_pop  (wake_uart_waiterから呼ばれる)
; リングバッファから1バイト取得
; 入力: COUNT>0であること (呼び出し側が保証)
; 出力: A = byte (下位8bit)
;       ★v0.12.10 TKT-02 I-03(b): COUNT==0 のとき A = $FFFF（異常センチネル）
;         正常戻り値は ANDI A,#$00FF により $0000-$00FF に限定されるため
;         $FFFF は正常値と衝突しない。A=0 は受信NULと非区別のため不採用。
; 破壊: A, B, X
; 更新順序: TAIL先 → COUNT後 (逆順禁止)
; ================================================================
rx_pop:
    ; ★v0.12.10 TKT-02 I-03(b): COUNT==0 防御ガード
    ;   COUNT==0 で呼ばれると後段の SUBI B,#1 が $FFFF にアンダーフローし、
    ;   同時に TAIL も進むためリングバッファ状態が回復不能に壊れる。
    ;   異常検知可能なセンチネル $FFFF を返して即復帰する。
    ;   設計書: yuios_uart_rxring_fix_design_v0_3.md §6.4
    LDW  A, [UART_RX_COUNT]
    BNE  _rx_pop_go
    LDW  A, #$FFFF              ; ★センチネル（正常戻り値と非衝突）
    RET
_rx_pop_go:
    LDW  X, [UART_RX_TAIL]     ; X = TAIL (インデックス)
    LDW  A, #$FC46              ; UART_RX_RING_BUF v0.12.0: $F020→$FC46
    ADD  A, X                   ; A = &buf[TAIL]
    MOV  X, A                   ; X = &buf[TAIL]
    LDB  A, [X]                 ; A = buf[TAIL]
    ANDI A, #$00FF              ; 下位8bitのみ

    ; TAIL更新 (先)
    ; ★v0.12.9: MOV B,X は誤り。X は &buf[TAIL]（アドレス）であり
    ;   インデックスではない。$FC46 の下位4bitが6のため
    ;   ANDI B,#$000F の結果 TAIL が 1 でなく 7 進み、次回 pop が
    ;   未書込スロットを読んで NUL を返していた。
    LDW  B, [UART_RX_TAIL]      ; ★B = TAIL（インデックス）を再取得
    ADDI B, #1
    ANDI B, #$000F              ; TAIL = (TAIL+1) mod 16
    STW  B, [UART_RX_TAIL]

    ; COUNT更新 (後)
    LDW  B, [UART_RX_COUNT]
    SUBI B, #1
    STW  B, [UART_RX_COUNT]

    RET

; ================================================================
; _calc_self_tcb  ($12C0)  v0.12.5新設
; 現在のタスクの TCB アドレスを計算
;   tid×80 = (tid<<6) + (tid<<4)
;   入力: なし（CUR_TASK を参照）
;   出力: A = self_tcb addr, X = self_tcb addr
;         IPC4_WK_SRCTCB = self_tcb addr
;   破壊: A, B, X, L1_WK_TMP, L1_WK_C
; ================================================================
    .org $12C0
_calc_self_tcb:
    LDW  A, [CUR_TASK]
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
    RET

; ================================================================
; init_msg_pool  ($1300)  v0.12.5新設
; MsgPool全エントリ初期化 + フリーリスト構築
; 設計書: yuios_ipc4_pool_design_v1_2.md §6.1
;
; 処理:
;   1. 全32エントリをゼロクリア
;   2. entry[i].next = i+1 で連結（entry[31].next = IDX_NIL）
;   3. MSG_POOL_FREE = 0（フリーリスト先頭）
;
; 破壊: A, B, X, L1_WK_A, L1_WK_TMP
; ================================================================
    .org $1300
init_msg_pool:
    ; --- (1) 全エントリ連結フリーリスト構築 ---
    LDW  A, #0                  ; i = 0
_init_pool_loop:
    CMPI A, #32                 ; i < POOL_SIZE?
    BGE  _init_pool_done
    STW  A, [L1_WK_TMP]        ; i 退避

    ; entry_addr = MSG_POOL_BASE + i × 16
    LDW  B, #4
    SHL  A, B                   ; A = i × 16
    LDW  B, #$4500              ; MSG_POOL_BASE
    ADD  A, B                   ; A = &MsgPool[i]
    STW  A, [L1_WK_A]          ; entry_addr 退避
    MOV  X, A

    ; sender=0, msg[0..3]=0, _pad=0
    LDW  A, #0
    STW  A, [X + #0]            ; sender = 0
    STW  A, [X + #2]            ; msg[0] = 0
    STW  A, [X + #4]            ; msg[1] = 0
    STW  A, [X + #6]            ; msg[2] = 0
    STW  A, [X + #8]            ; msg[3] = 0
    STW  A, [X + #12]           ; _pad[0] = 0
    STW  A, [X + #14]           ; _pad[1] = 0

    ; next = (i < POOL_SIZE-1) ? i+1 : IDX_NIL
    LDW  A, [L1_WK_TMP]        ; A = i
    ADDI A, #1                  ; A = i+1
    CMPI A, #32                 ; i+1 == POOL_SIZE?
    BNE  _init_pool_setnext
    LDW  A, #$FFFF              ; IDX_NIL（最終エントリ）
_init_pool_setnext:
    LDW  X, [L1_WK_A]          ; X = entry_addr
    STW  A, [X + #10]           ; entry.next = i+1 or IDX_NIL

    LDW  A, [L1_WK_TMP]        ; A = i
    ADDI A, #1                  ; i++
    JMP  _init_pool_loop

_init_pool_done:
    ; MSG_POOL_FREE = 0（フリーリスト先頭はindex 0）
    LDW  A, #0
    STW  A, [MSG_POOL_FREE]
    RET

; ================================================================
; _ipc4_enqueue  (IPC4_SEND/IPC4_CALLから JSR で呼ばれる)
; O(1) enqueue: フリーリストからエントリ確保 → 宛先TCBキュー末尾に挿入
; 設計書: yuios_ipc4_pool_design_v1_2.md §5.1
;
; 入力（ワーク変数経由）:
;   IPC4_WK_DST    = 宛先 tid
;   IPC4_WK_X      = メッセージ先頭アドレス（DSP上のmsg3..msg0）
;   CUR_TASK       = 送信者 tid
;
; 出力（ワーク変数経由）:
;   IPC4_WK_IDX    = 確保したエントリのindex（エラー時=$FFFF=IDX_NIL）
;
; 戻り値: A=0 (OK) / A=$FFFE (ERR_IPC_NOSLOT)
; 破壊: A, B, X, L1_WK_A, L1_WK_TMP, L1_WK_C
; 呼び出し時は DI 済みであること（_ipc4_enqueue 内では EI しない）
; ================================================================
_ipc4_enqueue:
    ; --- (1) フリーリストから空エントリ確保 (O(1) alloc) ---
    LDW  A, [MSG_POOL_FREE]     ; idx = MSG_POOL_FREE
    CMPI A, #$FFFF              ; idx == IDX_NIL?
    BNE  _enq_got_slot
    ; プール枯渇
    LDW  A, #$FFFE              ; ERR_IPC_NOSLOT
    RET

_enq_got_slot:
    STW  A, [IPC4_WK_IDX]      ; idx 退避

    ; entry_addr = MSG_POOL_BASE + idx × 16
    LDW  B, #4
    SHL  A, B                   ; A = idx × 16
    LDW  B, #$4500              ; MSG_POOL_BASE
    ADD  A, B                   ; A = &MsgPool[idx]
    STW  A, [L1_WK_A]          ; entry_addr 退避
    MOV  X, A

    ; MSG_POOL_FREE = entry.next（フリーリストから外す）
    LDW  A, [X + #10]           ; A = entry.next
    STW  A, [MSG_POOL_FREE]

    ; --- (2) エントリにデータ書込 ---
    LDW  A, [CUR_TASK]
    STW  A, [X + #0]            ; sender = CUR_TASK

    ; DSPからmsg[0..3]をコピー
    ; v0.12.6 修正: IPC4_WK_X は msg0 を指す（IPC4_CALL冒頭で tid pop 後の DSP）
    ;   DSPレイアウト（TOS側=低位）: [WK_X+0]=msg0(op) [+2]=msg1 [+4]=msg2 [+6]=msg3
    ;   entry.msg[i] レイアウト: msg[0]@+2 msg[1]@+4 msg[2]@+6 msg[3]@+8
    LDW  X, [IPC4_WK_X]        ; X = DSP（msg0 先頭）
    LDW  A, [X]                 ; msg0
    LDW  X, [L1_WK_A]
    STW  A, [X + #2]            ; entry.msg[0] = msg0

    LDW  X, [IPC4_WK_X]
    LDW  A, [X + #2]            ; msg1
    LDW  X, [L1_WK_A]
    STW  A, [X + #4]            ; entry.msg[1] = msg1

    LDW  X, [IPC4_WK_X]
    LDW  A, [X + #4]            ; msg2
    LDW  X, [L1_WK_A]
    STW  A, [X + #6]            ; entry.msg[2] = msg2

    LDW  X, [IPC4_WK_X]
    LDW  A, [X + #6]            ; msg3
    LDW  X, [L1_WK_A]
    STW  A, [X + #8]            ; entry.msg[3] = msg3

    LDW  A, #$FFFF              ; IDX_NIL
    STW  A, [X + #10]           ; entry.next = IDX_NIL（末尾になる）

    ; --- (3) 宛先TCBキュー末尾に挿入 (O(1)) ---
    ; dst_tcb = TCB_POOL + dst_tid × 80
    LDW  A, [IPC4_WK_DST]      ; A = dst_tid
    STW  A, [L1_WK_TMP]
    LDW  B, #6
    SHL  A, B                   ; A = tid*64
    STW  A, [L1_WK_C]
    LDW  A, [L1_WK_TMP]
    LDW  B, #4
    SHL  A, B                   ; A = tid*16
    LDW  B, [L1_WK_C]
    ADD  A, B                   ; A = tid*80
    LDW  B, #$4000
    ADD  A, B                   ; A = &TCB[dst_tid]
    STW  A, [IPC4_WK_SRCTCB]  ; ここではdst_tcbを保管（変数名は使い回し）
    MOV  X, A                   ; X = dst_tcb

    LDW  A, [X + #30]           ; A = dst_tcb.ipc_queue_head
    CMPI A, #$FFFF              ; head == IDX_NIL（キュー空）?
    BNE  _enq_notempty

    ; キュー空 → head も tail も新エントリに
    LDW  A, [IPC4_WK_IDX]
    STW  A, [X + #30]           ; ipc_queue_head = idx
    STW  A, [X + #14]           ; ipc_queue_tail = idx
    JMP  _enq_queued

_enq_notempty:
    ; キュー非空 → 旧tailのnextを更新し、tailを新エントリに変更
    LDW  A, [X + #14]           ; A = old_tail_idx
    STW  A, [L1_WK_TMP]        ; old_tail_idx 退避

    ; MsgPool[old_tail].next = idx
    LDW  B, #4
    SHL  A, B                   ; A = old_tail_idx × 16
    LDW  B, #$4500
    ADD  A, B                   ; A = &MsgPool[old_tail]
    MOV  X, A
    LDW  A, [IPC4_WK_IDX]
    STW  A, [X + #10]           ; MsgPool[old_tail].next = idx

    ; dst_tcb.ipc_queue_tail = idx
    LDW  X, [IPC4_WK_SRCTCB]
    LDW  A, [IPC4_WK_IDX]
    STW  A, [X + #14]           ; ipc_queue_tail = idx

_enq_queued:
    ; --- (4) 宛先が WAIT_IPC なら起こす ---
    LDW  X, [IPC4_WK_SRCTCB]
    LDW  A, [X]                 ; dst_tcb.state
    CMPI A, #5                  ; TASK_WAIT_IPC?
    BNE  _enq_done
    LDW  A, #1
    STW  A, [X]                 ; dst_tcb.state = READY

_enq_done:
    LDW  A, #0                  ; OK
    RET

