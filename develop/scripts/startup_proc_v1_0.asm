; startup_proc.asm v1.0
; YUI OS Ph.5 ProcMgr 専用 C プロセス crt0
; YSD8800 / ISA2.3
;
; 作成: 2026-06-07 (CHAT47 / Ph.5 Step 2)
; 設計書: yuios_design_v2_6.md §8.5.2 (D-6/R4), §8.2, §10.3 Step2
;
; ────────────────────────────────────────────────────────────
; 目的:
;   ProcMgr が $C000 固定ロード領域に読み込む C プロセス（scc23 v1.00
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
; ロード/起動シーケンス（§8.2）:
;   ProcMgr → FILE_READ で本バイナリを $C000 へ展開
;          → TASK-CREATE($C000) でエントリ=$C000 のタスク生成
;          → スケジューラが当該タスクに切替（SP/X は TCB から復元）
;          → 本 crt0 の _proc_entry($C000) から実行開始
;
; カーネル固定エントリ（kernel_v12_7.asm .org 固定配置）:
;   TASK_EXIT = $0460   ( -- )  自タスクを TASK-DEAD 化しスケジューラへ
;
; 配置: 本 crt0 は C プロセスバイナリの先頭に位置し、ロード先頭 $C000 が
;       _proc_entry になるようリンクする（ProcMgr ロード領域の固定エントリ）。
; ────────────────────────────────────────────────────────────

TASK_EXIT_ADDR  EQU $0460       ; カーネル TASK-EXIT 固定エントリ

    .org $C000                  ; ★Phase1: ProcMgr ロード領域固定先頭（§8.4）
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
