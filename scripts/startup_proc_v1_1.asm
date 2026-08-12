; startup_proc.asm v1.1
; YUI OS Ph.5 ProcMgr 専用 C プロセス crt0
; YSD8800 / ISA2.3
;
; 作成: 2026-06-07 (CHAT47 / Ph.5 Step 2)
; 改版: 2026-06-18 (CHAT56 / Ph.5 Step 4)
;
; ────────────────────────────────────────────────────────────
; v1.1 変更点 (2026-06-18):
;   memmap v2.4（案D-ε・承認済）に伴い C プロセス区画を $C000-$C7FF →
;   $D400-$DBFF へ移設したため、crt0 ロード先頭 .org を $C000 → $D400 へ変更。
;   理由: 旧 $C000 が Forth 辞書実コード（実測終端 $C15F）と物理衝突し、
;   ProcMgr 経由ロード時に走行中カーネルを上書き破壊するため（HANDOVER_CHAT54/55）。
;   結合方式（方式B）: 本 crt0(.org $D400) と scc23 v1.04 出力(.org $D440・CODE-ORG)
;   を lnk23 で 2 セクション結合（crt0 先・scc23 出力後）。crt0 の JSR _main は
;   scc23 出力の _main 実体アドレスを .sym から取得して解決する。
;   論理（main 復帰 → TASK-EXIT）は v1.0 から不変。旧 $C000 記述は履歴として下記に保持。
; ────────────────────────────────────────────────────────────
; 設計書: yuios_design_v2_6.md §8.5.2 (D-6/R4), §8.2, §10.3 Step2
;
; ────────────────────────────────────────────────────────────
; 目的:
;   ProcMgr が $D400 固定ロード領域に読み込む C プロセス（scc23 v1.04
;   出力・非PIC）のエントリ crt0。main から戻ったときに HALT で OS 全体を
;   止めるのではなく、TASK-EXIT($0460) を呼んで自タスクのみを終了させる。
;
; ★本日 KY（2026-06-07）: startup_harness23 v1.5 の HALT 流用禁止。
;   harness は単一プログラム実行用で JSR _main 直後が HALT（OS全停止）。
;   本 crt0 は harness を一切流用せず新規記述する。
;
; ────────────────────────────────────────────────────────────
; harness との決定的な差異（流用してはならない理由）:
;   (1) ベクタテーブル/IRQハンドラを持たない。
;       → それらは OS カーネル側が保持済み。C プロセスには不要。
;   (2) SP/X(フレームポインタ/Forth DSP) を初期化しない。
;       → TASK-CREATE($0520) が起動時に当該 tid 固有スタックを設定済み:
;           saved_sp = CALLSTK_TOP(tid) = $F07E + tid×$80   (HW コールスタック=SP)
;           saved_x  = DATASTK_TOP(tid) = $F87E + tid×$80
;         crt0 で SP を上書きすると tid 固有スタックを破壊する（harness の
;         LDW SP,#$F7FE は本用途では有害）。
;   (3) main 復帰後は HALT ではなく TASK-EXIT。
;
; ────────────────────────────────────────────────────────────
; ロード/起動シーケンス（§8.2・v2.4 で $D400 へ移設）:
;   ProcMgr → FILE_READ で本バイナリを $D400 へ展開
;          → TASK-CREATE($D400) でエントリ=$D400 のタスク生成
;          → スケジューラが当該タスクに切替（SP/X は TCB から復元）
;          → 本 crt0 の _proc_entry($D400) から実行開始
;
; カーネル固定エントリ（kernel_v12_7.asm .org 固定配置）:
;   TASK_EXIT = $0460   ( -- )  自タスクを TASK-DEAD 化しスケジューラへ
;
; 配置: 本 crt0 は C プロセスバイナリの先頭に位置し、ロード先頭 $D400 が
;       _proc_entry になるようリンクする（ProcMgr ロード領域の固定エントリ）。
; ────────────────────────────────────────────────────────────

TASK_EXIT_ADDR  EQU $0460       ; カーネル TASK-EXIT 固定エントリ

    .org $D400                  ; ★v1.1: ProcMgr ロード領域固定先頭（memmap v2.4・案D-ε / 旧 $C000）
_proc_entry:
    ; SP/X は初期化しない（TASK-CREATE が tid 固有スタックを設定済み）。
    JSR  _main                  ; C プロセス本体へ。lnk23 が R_ABS16 で _main 解決
                                ; （scc23 出力の main 実体。harness の
                                ;  --alias _main=_forth_main とは無関係）
_proc_exit:
    ; main から戻った（return / 関数末尾）→ 自タスクのみ終了。
    ; HALT は使わない（OS 全停止になるため・本日 KY）。
    JSR  TASK_EXIT_ADDR         ; TASK-EXIT($0460): 自 tid を DEAD 化しスケジューラへ
    ; TASK-EXIT は通常戻らない（スケジューラが別タスクへ切替）。
    ; 万一戻った場合の保険として再度 TASK-EXIT を試みる無限ループ。
    ; ※HALT は置かない（OS 全停止回避）。
_proc_exit_guard:
    JSR  TASK_EXIT_ADDR
    JMP  _proc_exit_guard
