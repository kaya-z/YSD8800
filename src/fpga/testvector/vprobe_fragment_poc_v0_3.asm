
; ================================================================
; vprobe_fragment_poc  v0.3  (2026-08-08)
; TKT-02/TKT-01/TKT-04 検証用 PoCハーネス断片（kernel_v12_11.asm へ追記）
;
; 設計書: yuios_uart_rxring_fix_design_v0_4.md §5.3（V系）
;         yuios_ctxsw_abreg_restore_design_v0_2.md（W系）
;         yuios_tkt04_w5_verify_design_v0_3.md §4.4（W-5）
;
; 【v0.3 変更】★W-5（TASK_CREATE EI窓中断→_sc_found 再開 end-to-end）を追加★
;   併せて KY41 4点整合を是正（v0.2 はヘッダ版数・日付・追記先が実体と不整合、
;   結果バッファ表に _tc/W-1/W-3/W-4 が未反映だった）。
;   挿入位置: _w4_resume の直後・_w3 の直前（設計書 §4.4）。
;
; 【v0.2 変更】★結果バッファを $4000 → $4600 へ退避★
;   TCBアドレス = $4000 + tid*80（L1786-1787）、MAX_TASKS=16 のため
;   $4000-$44FF はTCB領域。v0.1 の結果バッファ($4000)はTCB[0]と完全衝突。
;   $4500-$46FF は MSG_POOL だが本PoCはOS非起動のため未使用であり安全。
;   V-3 では tid=1（TCB=$4050）を使用する。
;
; 【KY38】本番ソース非改変。_poc サフィックス付きで別ビルド。
; 【原則76】rx_push/rx_pop/wake_uart_waiter は本物の実装を直接呼ぶ。
;
; 【実行順】_poc_start → V-1 → V-2 → V-7 → V-4 → V-3a/b/c → _tc
;           → _wmark → W-1 → W-4 → ★W-5★ → W-3 → (TASK_SLEEP で _sc_idle)
;
; 【結果バッファ $4600〜】
;   $4600 V-1 COUNT   $4602 V-1 HEAD    $4604 V-1 TAIL
;   $4606 V-2 折返し後TAIL
;   $4608 V-7 戻り値A $460A V-7 COUNT   $460C V-7 TAIL
;   $460E 完走マーカ1 $C0DE
;   $4610 V-4 HEAD    $4612 V-4 TAIL    $4620-$462F V-4取得列
;   $4640/$4642/$4644 スクラッチ
;   $4650 V-3a TCB+16  $4652 V-3a TCB+24  $4654 V-3a state  $4656 V-3a WAIT_TID
;   $4658 V-3b STOR_DRV  $465A V-3b STOR_WAIT  $465C V-3b STOR_STAT
;   $465E V-3b TCB+16    $4660 V-3b TCB+24
;   $4662 V-3c TCB+16    $4664 V-3c TCB+24     $4666 V-3c WAIT_TID
;   $4668 完走マーカ2 $BEEF
;   ---- v0.3 追記: 既存 W系/_tc の割付を明記 ----
;   $466A _tc 戻り値（_tc_noslot 経路 = $FFFF）
;   $4670 W-1 A  $4672 W-1 B  $4674 W-1 X   （_sc_found 経由の復元）
;   $4676 W-4 A  $4678 W-4 B  $467A W-4 X   （_sched_found 経由の復元）
;   $467C 完走マーカ3 $CAFE
;   $4680 W-3 TASK_SLEEP saved_a  $4682 W-3 saved_b
;   $4684 完走マーカ4 $F00D（W-3 予約・現状未書込）
;   ---- v0.3 新規: W-5 ----
;   $4686 完走マーカ5 $5A5A（W-5）
;   $46AE ★W-5 判定対象（TASK_CREATE が積んだ戻り値）★
;         症状値=$46B0(saved_x) / 正常値=$0005(saved_a)
;   $46B0 W-5 疑似 Forth DSP 初期値（saved_x）
;   $4690/$4692/$4694 _w_setup 引数域   $4696/$4698 _w_setup/_w3 ループワーク
;   $469A/$469C W-5 専用ループワーク（_w5_fillslp）
;   $46E0 _w3 疑似DSP
;   $46F0 W-5 疑似カーネルSP（saved_sp）。[$46F0] に _w5_land アドレスを格納
; ================================================================
    .org $2000
_poc_start:
    LDW  SP, #$477E
    DI

    LDW  A, #0
    STW  A, [UART_RX_HEAD]
    STW  A, [UART_RX_TAIL]
    STW  A, [UART_RX_COUNT]
    STW  A, [UART_WAIT_TID]

; ---------------- V-1: オーバーラン（17バイト投入） ----------------
_v1_loop_init:
    LDW  A, #0
    STW  A, [$4640]
_v1_loop:
    LDW  X, [$4640]
    CMPI X, #17
    BGE  _v1_done
    MOV  A, X
    ADDI A, #$41
    JSR  rx_push
    LDW  X, [$4640]
    ADDI X, #1
    STW  X, [$4640]
    JMP  _v1_loop
_v1_done:
    LDW  X, #$4600
    LDW  A, [UART_RX_COUNT]
    STW  A, [X]
    LDW  A, [UART_RX_HEAD]
    STW  A, [X + #2]
    LDW  A, [UART_RX_TAIL]
    STW  A, [X + #4]

; ---------------- V-2: TAIL折返し ----------------
_v2:
    LDW  A, #15
    STW  A, [UART_RX_TAIL]
    LDW  A, #1
    STW  A, [UART_RX_COUNT]
    JSR  rx_pop
    LDW  X, #$4600
    LDW  A, [UART_RX_TAIL]
    STW  A, [X + #6]

; ---------------- V-7: COUNT==0 防御ガード ----------------
_v7:
    LDW  A, #0
    STW  A, [UART_RX_COUNT]
    LDW  A, #3
    STW  A, [UART_RX_TAIL]
    JSR  rx_pop
    LDW  X, #$4600
    STW  A, [X + #8]
    LDW  A, [UART_RX_COUNT]
    STW  A, [X + #10]
    LDW  A, [UART_RX_TAIL]
    STW  A, [X + #12]

; ---------------- V-4: 16バイト一周 ----------------
_v4:
    LDW  A, #0
    STW  A, [UART_RX_HEAD]
    STW  A, [UART_RX_TAIL]
    STW  A, [UART_RX_COUNT]
    STW  A, [$4642]
_v4_push:
    LDW  X, [$4642]
    CMPI X, #16
    BGE  _v4_push_done
    MOV  A, X
    ADDI A, #$50
    JSR  rx_push
    LDW  X, [$4642]
    ADDI X, #1
    STW  X, [$4642]
    JMP  _v4_push
_v4_push_done:
    LDW  A, #0
    STW  A, [$4644]
_v4_pop:
    LDW  X, [$4644]
    CMPI X, #16
    BGE  _v4_pop_done
    JSR  rx_pop
    LDW  X, [$4644]
    LDW  B, #$4620
    ADD  B, X
    MOV  X, B
    STB  A, [X]
    LDW  X, [$4644]
    ADDI X, #1
    STW  X, [$4644]
    JMP  _v4_pop
_v4_pop_done:
    LDW  X, #$4600
    LDW  A, [UART_RX_HEAD]
    STW  A, [X + #16]
    LDW  A, [UART_RX_TAIL]
    STW  A, [X + #18]

; ---------------- 完走マーカ1 ----------------
    LDW  X, #$4600
    LDW  A, #$C0DE
    STW  A, [X + #14]
    JMP  _v3a

; ================================================================
; V-3 共通サブルーチン: TCB(tid=1)=$4050 を待機状態に初期化
; ================================================================
_v3_setup:
    LDW  X, #$4050
    LDW  A, #6
    STW  A, [X]                 ; state = TASK_WAIT_REPLY
    LDW  A, #0
    STW  A, [X + #16]
    STW  A, [X + #18]
    STW  A, [X + #20]
    STW  A, [X + #22]
    STW  A, [X + #24]
    STW  A, [X + #26]
    LDW  A, #1
    STW  A, [UART_WAIT_TID]     ; 待機者 tid=1
    RET

; ---------------- V-3a: TAIL=0 で起床 ----------------
_v3a:
    JSR  _v3_setup
    LDW  X, #$FC46
    LDW  A, #$7A
    STB  A, [X]                 ; buf[0] = $7A
    LDW  A, #0
    STW  A, [UART_RX_TAIL]
    LDW  A, #1
    STW  A, [UART_RX_COUNT]
    JSR  wake_uart_waiter
    LDW  X, #$4050
    LDW  A, [X + #16]
    LDW  X, #$4650
    STW  A, [X]                 ; $4650 = TCB+16 (ipc_msg[0])
    LDW  X, #$4050
    LDW  A, [X + #24]
    LDW  X, #$4650
    STW  A, [X + #2]            ; $4652 = TCB+24 (ipc_valid)
    LDW  X, #$4050
    LDW  A, [X]
    LDW  X, #$4650
    STW  A, [X + #4]            ; $4654 = TCB+0 (state)
    LDW  A, [UART_WAIT_TID]
    STW  A, [X + #6]            ; $4656 = WAIT_TID

; ---------------- V-3b: TAIL=4 でストレージ変数の巻添え確認 ----------------
_v3b:
    LDW  A, #$1111
    STW  A, [STOR_DRV_TID]
    LDW  A, #$2222
    STW  A, [STOR_WAIT_TID]
    LDW  A, #$3333
    STW  A, [STOR_LAST_STAT]
    JSR  _v3_setup
    LDW  X, #$FC4A
    LDW  A, #$7B
    STB  A, [X]                 ; buf[4] = $7B
    LDW  A, #4
    STW  A, [UART_RX_TAIL]
    LDW  A, #1
    STW  A, [UART_RX_COUNT]
    JSR  wake_uart_waiter
    LDW  X, #$4650
    LDW  A, [STOR_DRV_TID]
    STW  A, [X + #8]            ; $4658
    LDW  A, [STOR_WAIT_TID]
    STW  A, [X + #10]           ; $465A
    LDW  A, [STOR_LAST_STAT]
    STW  A, [X + #12]           ; $465C
    LDW  X, #$4050
    LDW  A, [X + #16]
    LDW  X, #$4650
    STW  A, [X + #14]           ; $465E = TCB+16
    LDW  X, #$4050
    LDW  A, [X + #24]
    LDW  X, #$4650
    STW  A, [X + #16]           ; $4660 = TCB+24

; ---------------- V-3c: TAIL=1（奇数）でアライメント例外が出ないこと ----------------
_v3c:
    JSR  _v3_setup
    LDW  X, #$FC47
    LDW  A, #$7C
    STB  A, [X]                 ; buf[1] = $7C
    LDW  A, #1
    STW  A, [UART_RX_TAIL]
    LDW  A, #1
    STW  A, [UART_RX_COUNT]
    JSR  wake_uart_waiter
    LDW  X, #$4050
    LDW  A, [X + #16]
    LDW  X, #$4650
    STW  A, [X + #18]           ; $4662 = TCB+16
    LDW  X, #$4050
    LDW  A, [X + #24]
    LDW  X, #$4650
    STW  A, [X + #20]           ; $4664 = TCB+24
    LDW  A, [UART_WAIT_TID]
    STW  A, [X + #22]           ; $4666 = WAIT_TID

; ---------------- T-C: TKT-01 _tc_noslot 経路（16スロット全埋め） ----------------
;   期待: 戻り値 $FFFF が DSP へ書かれる
;   安全対策: 全TCB state=3(SLEEPING) とする。
;     state≠0 → TASK_CREATE から見て「空きなし」
;     state≠1 → EI(L877)後にIRQ0が入っても _irq_noready から安全にIRET
_tc:
    LDW  A, #0
    STW  A, [$4646]             ; ループカウンタ
_tc_fill:
    LDW  X, [$4646]
    CMPI X, #16
    BGE  _tc_fill_done
    ; TCBアドレス = $4000 + tid*80  (tid*64 + tid*16)
    MOV  A, X
    LDW  B, #6
    SHL  A, B                   ; A = tid*64
    STW  A, [$4648]
    LDW  X, [$4646]
    MOV  A, X
    LDW  B, #4
    SHL  A, B                   ; A = tid*16
    LDW  B, [$4648]
    ADD  A, B                   ; A = tid*80
    LDW  B, #$4000
    ADD  A, B
    MOV  X, A
    LDW  A, #3                  ; SLEEPING
    STW  A, [X]
    LDW  X, [$4646]
    ADDI X, #1
    STW  X, [$4646]
    JMP  _tc_fill
_tc_fill_done:
    ; 疑似DSPを $4680 に用意（entry_addr を積む）
    LDW  X, #$4680
    LDW  A, #$1234              ; ダミー entry_addr
    STW  A, [X]
    JSR  TASK_CREATE
    DI                          ; ★EI(L877)で開いた割込を即閉じる
    LDW  X, #$4650
    LDW  A, [$4680]
    STW  A, [X + #26]           ; $466A = TASK_CREATE 戻り値（期待 $FFFF）
    JMP  _wmark                 ; ★W系定義ブロックを飛び越す（落ち込み防止）

; ================================================================
; W-1 / W-4: TKT-04 コンテキストスイッチ A/B 復元検証
;   共通TCB(tid=1)=$4050 を組み、_sc_found / _sched_found へ直接JMPする。
;   両者は入口条件が同一（X=TCBアドレス, L1_WK_A=tid）。
;   復帰後 A/B/X を結果バッファへ記録する。
;
;   結果: $4670 W-1 A  $4672 W-1 B  $4674 W-1 X
;         $4676 W-4 A  $4678 W-4 B  $467A W-4 X
;         $467C 完走マーカ3 $CAFE
; ================================================================

; --- 偽TCB構築サブルーチン: A=saved_a値, B=saved_b値 を $4650 経由で受け取る ---
;   呼出前に [$4690]=saved_a, [$4692]=saved_b, [$4694]=saved_pc を設定すること
_w_setup:
    ; 全TCBを SLEEPING(3) にして IRQ0 が切替先を見つけないようにする
    LDW  A, #0
    STW  A, [$4696]
_w_fill:
    LDW  X, [$4696]
    CMPI X, #16
    BGE  _w_fill_done
    MOV  A, X
    LDW  B, #6
    SHL  A, B
    STW  A, [$4698]
    LDW  X, [$4696]
    MOV  A, X
    LDW  B, #4
    SHL  A, B
    LDW  B, [$4698]
    ADD  A, B
    LDW  B, #$4000
    ADD  A, B
    MOV  X, A
    LDW  A, #3
    STW  A, [X]
    LDW  X, [$4696]
    ADDI X, #1
    STW  X, [$4696]
    JMP  _w_fill
_w_fill_done:
    ; TCB(tid=1)=$4050 を組む
    LDW  X, #$4050
    LDW  A, #1
    STW  A, [X]                 ; state = READY
    LDW  A, [$4694]
    STW  A, [X + #2]            ; saved_pc = 復帰先
    LDW  A, #$46F0
    STW  A, [X + #4]            ; saved_sp = 疑似カーネルスタック
    LDW  A, #$DEAD
    STW  A, [X + #6]            ; saved_x = 目印
    LDW  A, [$4690]
    STW  A, [X + #8]            ; saved_a
    LDW  A, [$4692]
    STW  A, [X + #10]           ; saved_b
    LDW  A, #0
    STW  A, [X + #12]           ; saved_flags
    LDW  A, #1
    STW  A, [L1_WK_A]           ; tid=1
    LDW  X, #$4050              ; X = TCBアドレス（入口条件）
    RET

; ---------------- W-1: _sc_found 経由の復元 ----------------
_w1:
    LDW  A, #$AAAA
    STW  A, [$4690]
    LDW  A, #$BBBB
    STW  A, [$4692]
    LDW  A, #$_w1_resume
    STW  A, [$4694]
    JSR  _w_setup
    JMP  _sc_found              ; ★IRETで _w1_resume へ復帰する
_w1_resume:
    DI                          ; IRETでIE=1になるため即座に閉じる
    STW  A, [$4670]
    STW  B, [$4672]
    STW  X, [$4674]

; ---------------- W-4: _sched_found 経由の復元（非回帰） ----------------
_w4:
    LDW  A, #$CCCC
    STW  A, [$4690]
    LDW  A, #$DDDD
    STW  A, [$4692]
    LDW  A, #$_w4_resume
    STW  A, [$4694]
    JSR  _w_setup
    JMP  _sched_found           ; ★IRETで _w4_resume へ復帰する
_w4_resume:
    DI
    STW  A, [$4676]
    STW  B, [$4678]
    STW  X, [$467A]
    LDW  A, #$CAFE
    STW  A, [$467C]             ; 完走マーカ3
    LDW  SP, #$477E             ; スタック復旧

; ---------------- W-5: TASK_CREATE EI窓中断 → _sc_found 再開 (end-to-end) ----------------
;   設計書: yuios_tkt04_w5_verify_design_v0_3.md §4.4
;   条件1(EI窓での中断)・条件2(_sc_found 経由の再開) が成立した「後」の状態を
;   TCB として直接構築し、実 TASK_CREATE の L952-954 を無改変で通過させる。
;   $46AE 積まれた戻り値（判定対象）   $4686 完走マーカ5 $5A5A
;   症状値 = $46B0 (saved_x) / 正常値 = $0005 (saved_a)
_w5:
    DI                          ; 挿入位置変更に対する堅牢化（設計書 C-4）
    JSR  _w5_fillslp            ; 全TCBを SLEEPING(3) 化（別タスクへ切替させない）
    LDW  A, #$0000
    STW  A, [$46AE]             ; 判定域を既知値でクリア
    LDW  A, #$_w5_land
    STW  A, [$46F0]             ; ★L954 RET の飛び先（[saved_sp]）
    ; --- 疑似TCB(tid=1)=$4050 を構築 ---
    LDW  X, #$4050
    LDW  A, #1
    STW  A, [X]                 ; state = READY
    LDW  A, #$0613              ; ★_w5_pc = L952 SUBI X,#2（.dbg 実測値）
    STW  A, [X + #2]            ; saved_pc = EI窓の途中
    LDW  A, #$46F0
    STW  A, [X + #4]            ; saved_sp
    LDW  A, #$46B0
    STW  A, [X + #6]            ; saved_x = 疑似DSP = ★症状値★
    LDW  A, #$0005
    STW  A, [X + #8]            ; saved_a = 期待tid = ★正常値★
    LDW  A, #$0000
    STW  A, [X + #10]           ; saved_b
    STW  A, [X + #12]           ; saved_flags（L732 ORI で IE=1 が強制される）
    LDW  A, #1
    STW  A, [L1_WK_A]           ; tid=1（_sc_found 入口条件）
    LDW  X, #$4050              ; X=TCBアドレス（_sc_found 入口条件）
    JMP  _sc_found              ; ★IRET で $0613 へ復帰し L952-954 を実行

; ← 実 TASK_CREATE L954 RET の飛び先
_w5_land:
    DI
    LDW  SP, #$477E             ; スタック復旧
    LDW  A, #$5A5A
    STW  A, [$4686]             ; 完走マーカ5
    JMP  _w3                    ; 既存 W-3 へ引き継ぐ（BP はここ = _w3 に置く）

; --- W-5 専用: 全TCBを SLEEPING(3) 化（専用ワーク $469A/$469C）---
_w5_fillslp:
    LDW  A, #0
    STW  A, [$469A]
_w5_fs_loop:
    LDW  X, [$469A]
    CMPI X, #16
    BGE  _w5_fs_done
    MOV  A, X
    LDW  B, #6
    SHL  A, B
    STW  A, [$469C]             ; tid×64
    LDW  X, [$469A]
    MOV  A, X
    LDW  B, #4
    SHL  A, B                   ; tid×16
    LDW  B, [$469C]
    ADD  A, B                   ; tid×80
    LDW  B, #$4000
    ADD  A, B                   ; TCBアドレス
    MOV  X, A
    LDW  A, #3
    STW  A, [X]                 ; SLEEPING
    LDW  X, [$469A]
    ADDI X, #1
    STW  X, [$469A]
    JMP  _w5_fs_loop
_w5_fs_done:
    RET

; ---------------- W-3: 各SYSCALL保存経路で saved_a/saved_b が 0 になること ----------------
;   TCB(tid=1)=$4050 の +8/+10 に非ゼロ値を仕込んでから各SYSCALLを呼び、
;   保存ブロックが 0 で上書きすることを確認する。
;   $4680 W-3 TASK_SLEEP  saved_a   $4682 saved_b
;   $4684 完走マーカ4 $F00D
_w3:
    ; CUR_TASK=1 とし TCB(tid=1) を RUNNING に、+8/+10 に汚染値を置く
    LDW  A, #1
    STW  A, [CUR_TASK]
    LDW  X, #$4050
    LDW  A, #2
    STW  A, [X]                 ; RUNNING
    LDW  A, #$EEEE
    STW  A, [X + #8]            ; saved_a を汚染
    STW  A, [X + #10]           ; saved_b を汚染
    ; 他TCBは DEAD(0) にして _sched_common が READY を見つけないようにする
    ; （TASK_SLEEP は末尾で _sched_common へ JMP するため、
    ;   READY 不在 → _sc_idle で EI/NOP/DI ループに入る。
    ;   そこで停止させず、先に保存結果を採取するためBP方式は使わず、
    ;   TASK_SLEEP 直前に保存ブロックだけを検証する構成とする）
    LDW  A, #0
    STW  A, [$4696]
_w3_clr:
    LDW  X, [$4696]
    CMPI X, #16
    BGE  _w3_go
    CMPI X, #1
    BEQ  _w3_skip
    MOV  A, X
    LDW  B, #6
    SHL  A, B
    STW  A, [$4698]
    LDW  X, [$4696]
    MOV  A, X
    LDW  B, #4
    SHL  A, B
    LDW  B, [$4698]
    ADD  A, B
    LDW  B, #$4000
    ADD  A, B
    MOV  X, A
    LDW  A, #0
    STW  A, [X]                 ; DEAD
_w3_skip:
    LDW  X, [$4696]
    ADDI X, #1
    STW  X, [$4696]
    JMP  _w3_clr
_w3_go:
    ; TASK_SLEEP を呼ぶ（戻ってこないため、保存結果は _sc_idle 到達前に
    ; TCB へ書かれている。BP で停止して採取する運用とする）
    LDW  X, #$46E0              ; 疑似DSP
    JSR  TASK_SLEEP
    HALT

; ---------------- 完走マーカ2（W系へ続く） ----------------
_wmark:
    LDW  X, #$4650
    LDW  A, #$BEEF
    STW  A, [X + #24]           ; $4668
    JMP  _w1                    ; ★TKT-04 W系検証へ
