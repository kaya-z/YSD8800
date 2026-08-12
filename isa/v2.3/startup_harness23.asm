; startup_harness23.asm v1.3
; v1.3: ISA2.3対応
;       - IRQ4(SYSCALL)ハンドラ追加
;       - EI追加（SYSCALL IRQ4受理のため必須）
;       - ベクタテーブルを全エントリ明示
; v1.2: CODE_ORG=$0400に対応
; v1.1: SP=$F7FEに変更
;
; ベクタテーブル
    .org  $0000
    .word _startup          ; reset
    .org  $0002
    .word _dummy_irq        ; irq0（タイマー等 - 未使用時はダミー）
    .org  $0004
    .word _dummy_irq        ; irq1
    .org  $0006
    .word _dummy_irq        ; align
    .org  $0008
    .word _syscall_handler  ; syscall (IRQ4)

; スタートアップ
    .org  $0018
_startup:
    LDW  SP, #$F7FE         ; Cスタック初期値
    LDW  X,  #$0000         ; フレームポインタ初期化
    EI                      ; 割り込み許可（SYSCALL IRQ4受理に必須）
    JSR  $0400              ; Cコード(_main)へジャンプ
    HALT

; IRQ4ハンドラ（SYSCALL）
; emu23がSYSCALL実行時（IRQ4発火前）にYSD8002フック処理済み
; ハンドラは即IREtするだけ
_syscall_handler:
    IRET

; ダミーIRQハンドラ
_dummy_irq:
    IRET
