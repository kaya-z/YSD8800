; startup_harness23.asm v1.7
; v1.7: _irq1_handlerレジスタ退避追加（scc23 v2.04レビューで発見）
;       - _irq1_handler: A/B無退避 → _timer_handlerと同一パターンでA/B/X退避追加
;         理由: LDW A,#$FCB2でAを、LDW B,[A]でBを破壊するため、
;               呼出元コードのレジスタ保護が必要（従来は非対称で欠陥）。
;               Xは本ハンドラでは未使用だが将来拡張時の退避漏れを防ぐため
;               _timer_handlerと同一パターンに揃える（案A採用）。
;       - 設計書: startup_harness23_v17_irq1_regsave_fix_design_v1_1.md
; v1.6: V5 TCR-ACK方式対応（emu23 v1.10以降）
;       - _timer_handler: IRETのみ → A/B/X退避＋TCR IRQ_ACK(bit5)書込＋復元
;         理由: タイマーの再武装契機がIRET命令からTCR-ACK書込に変更されたため。
;               ACKがA/Bを破壊するので退避・復元が必須となった。
;       - _isr_wk_a/_isr_wk_b/_isr_wk_x: ISR退避ワーク新設（$000C-$0011）
; v1.5: lnk23対応
;       - _startup: JSR $0400 → JSR  $04cc（シンボル参照化）
;         lnk23がR_ABS16リロケーションで_mainのアドレスを解決する
;         Forthカーネルは --alias _main=_forth_main で対応（案Y）
; v1.4: デバイス追加対応
;       - IRQ0ハンドラ: _dummy_irq → _timer_handler（YSD8002タイマー対応）
;       - IRQ1ハンドラ: _dummy_irq → _irq1_handler（YSD8004経由デバイス対応）
;       - IRQ3ハンドラ: NMI扱い明示（_align_handler）
;       - _syscall_handler: ディスパッチテーブル方式に変更
;       - _syscall_disp_ptr: 間接ポインタ変数追加
;         初期値: _harness_dispatch（YUI OS導入前のスタブ）
;         YUI OS導入後: _kernel_dispatchに書き換え（案A→案B移行）
; v1.3: ISA2.3対応
;       - IRQ4(SYSCALL)ハンドラ追加
;       - EI追加（SYSCALL IRQ4受理のため必須）
;       - ベクタテーブルを全エントリ明示
; v1.2: CODE_ORG=$0400に対応
; v1.1: SP=$F7FEに変更
;
; 設計書: emu23_device_design_v1_2.docx
;
; IRQ番号とベクタの対応（emu23内部）
;   irq_pending=1 → ベクタ $0002 → IRQ0: YSD8002タイマー
;   irq_pending=2 → ベクタ $0004 → IRQ1: YSD8004経由（YSD8003等）
;   irq_pending=3 → ベクタ $0006 → IRQ3: アラインメント例外（NMI扱い）
;   irq_pending=4 → ベクタ $0008 → IRQ4: SYSCALL
;
; MMIO定義（参照用）
;   YSD8002: TCR=$FC90 SW_RUNS=$FC9A SCORE_LO=$FC9C SCORE_HI=$FC9E
;   YSD8003: SD_STAT=$FCA2
;   YSD8004: IRQ_STAT=$FCB2（Write-to-Clear）IRQ_MASK=$FCB4
;   SYSCALL ABI: A=番号 / スタック=引数 / B=戻り値

; ================ ベクタテーブル ================
    .org  $0000
    .word _startup          ; reset

    .org  $0002
    .word _timer_handler    ; IRQ0: YSD8002タイマー

    .org  $0004
    .word _irq1_handler     ; IRQ1: YSD8004経由デバイス

    .org  $0006
    .word _align_handler    ; IRQ3: アラインメント例外（NMI扱い）

    .org  $0008
    .word _syscall_handler  ; IRQ4: SYSCALL

; ================ _syscall_disp_ptr（間接ポインタ変数）================
; YUI OS導入前: _harness_dispatch を指す
; YUI OS導入後: _kernel_dispatch に書き換え
    .org  $000A
_syscall_disp_ptr:
    .word _harness_dispatch

; ================ ISR退避ワーク（v1.6 / V5新設）================
; _timer_handler が TCR ACK を発行する際に A/B/X を破壊するため、
; 中断されたコードのレジスタを保護する退避先が必要になった。
; 配置: $000C-$0011（_syscall_disp_ptr $000A-000B と _startup $0018 の間の空き）
    .org  $000C
_isr_wk_a:
    .word $0000
    .org  $000E
_isr_wk_b:
    .word $0000
    .org  $0010
_isr_wk_x:
    .word $0000

; ================ スタートアップ ================
    .org  $0018
_startup:
    LDW  SP, #$F7FE         ; Cスタック初期値
    LDW  X,  #$0000         ; フレームポインタ初期化
    EI                      ; 割り込み許可
    JSR  $04cc              ; v1.5: シンボル参照（lnk23がR_ABS16で解決）
                            ; Forthカーネル時: --alias _main=_forth_main (案Y)
    HALT

; ================ IRQ0: タイマーハンドラ（YSD8002）================
; YSD8002タイマー割り込みを受理してIRETする
; YUI OS導入後はここでタイマースケジューリング処理を行う
; SP到達時条件: [SP]=FLAGS / [SP+2]=戻りPC
;
; v1.6 (V5): ★TCR-ACK 方式への移行★
;   emu23 v1.10 以降、タイマーは発火後に自己武装解除する（next_irq_cycle=UINT64_MAX）。
;   ハンドラが TCR bit5 (IRQ_ACK) を書かない限り二度と発火しない。
;   → ACK 発行が必須。ACK は A/B を破壊するため、A/B/X の退避・復元を追加した。
;   （v1.5 以前は IRET が自動再武装していたため退避不要だった）
;   ★ACK は1割込につき1回だけ書くこと（複数回書くと周期がずれる）★
_timer_handler:
    STW  A, [_isr_wk_a]     ; A/B/X を退避（中断されたコードを保護）
    STW  B, [_isr_wk_b]
    STW  X, [_isr_wk_x]

    LDW  A, #$FC90          ; TCR アドレス
    LDW  B, #$0023          ; TIMER_EN|IRQ_EN|IRQ_ACK ＝ ACK＋再武装
    STW  B, [A]             ; TCR ← 状態ビット込みの完全値
                            ; ★$0020(ACK単独)不可: 状態ビットが落ちタイマー恒久停止★

    LDW  A, [_isr_wk_a]     ; A/B/X を復元
    LDW  B, [_isr_wk_b]
    LDW  X, [_isr_wk_x]
    IRET

; ================ IRQ1: YSD8004経由デバイスハンドラ ================
; YSD8003ストレージ完了等をIRQ_STATで確認し処理する
; SP到達時条件: [SP]=FLAGS / [SP+2]=戻りPC
;
; IRQ_STAT ($FCB2) Write-to-Clear:
;   bit1: YSD8003ストレージ完了/エラー
;
_irq1_handler:
    ; v1.7 修正: A/B/X を退避（_timer_handler と対称化）
    ; 理由: LDW A,#$FCB2 で A を、LDW B,[A] で B を破壊するため
    ;       呼出元レジスタの保護が必要。
    ;       X は本ハンドラでは未使用だが、将来拡張時の退避漏れを防ぐため
    ;       _timer_handler と同一パターンに揃える（案A採用）。
    STW  A, [_isr_wk_a]
    STW  B, [_isr_wk_b]
    STW  X, [_isr_wk_x]

    ; IRQ_STATを読み出してからWrite-to-Clearでクリア
    LDW  A, #$FCB2      ; IRQ_STAT アドレス
    LDW  B, [A]         ; IRQ_STATを読み出し
    STW  B, [A]         ; Write-to-Clear（読み出し値を書き戻す）

    LDW  A, [_isr_wk_a] ; A/B/X を復元
    LDW  B, [_isr_wk_b]
    LDW  X, [_isr_wk_x]
    IRET

; ================ IRQ3: アラインメント例外（NMI扱い）================
; IE=0でも即時発生・マスク不可
; SP到達時条件: [SP]=FLAGS / [SP+2]=例外発生PC（障害アドレス前後）
_align_handler:
    HALT                ; アラインメント例外は致命的エラー → HALT

; ================ IRQ4: SYSCALLハンドラ ================
; ディスパッチテーブル方式（将来拡張）:
;   _syscall_disp_ptr → ハンドラ関数ポインタ
;   YUI OS導入前: _harness_dispatch（即IRET）
;   YUI OS導入後: _kernel_dispatch（本物のカーネルディスパッチ）
;
; SYSCALL ABI:
;   入力: A=SYSCALL番号 / スタック=引数
;   出力: B=戻り値（成功>=0 / 失敗<0）
;   A: caller-saved（ハンドラ内でPUSH/POP）
;   B: caller-saved（戻り値）
;
; SP到達時条件（IRQ4受理後）:
;   SP+0: FLAGS
;   SP+2: 戻りPC
;   SP+4〜: 引数
;
; NOTE: ISA2.3に間接JSR（JSR [X]）が無いため、
;       _syscall_disp_ptrは将来の間接JSR命令追加またはFPGA実装時に使用予定
;       v1.5では_harness_dispatchへ直接ジャンプ
;
_syscall_handler:
    JMP  _harness_dispatch      ; 直接ジャンプ（暫定）
                                ; 将来: JSR [_syscall_disp_ptr] 相当に変更

; ================ _harness_dispatch（SYSCALLスタブ）================
; YUI OS導入前の最小ハンドラ: 即IRET
_harness_dispatch:
    IRET
