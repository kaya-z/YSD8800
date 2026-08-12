; irqtest_harness.asm v1.0
; Step 8-I 実害再現テスト用 最小ハーネス
; 設計書: irqtest_design_v0_2.md
;
; 目的: タイマーIRQ(IRQ0)と合成注入IRQ1を衝突させ、
;       タイマーIRQ受理回数を計測版emu23(emu23_irqtest)で観測する。
;
; ベース: startup_harness23_v15.asm（ベクタ・ハンドラ流用）
; 変更点: _main を「長いカウントダウンループ後HALT」に置換。
;         タイマーはYSD8002_initで起動済み(TCR=0x03)のためEIのみで発火。
;         IRQ1は計測版の合成注入(IRQ_COLLIDE)で発火。
;
; 使用命令: LDW/STW/SUBI/CMPI/BNE/JMP/EI/IRET/HALT のみ（ISA2.3内・KY遵守）
; CODE_ORG=$0400 / SP=$F7FE

; ================ ベクタテーブル ================
    .org  $0000
    .word _startup          ; reset

    .org  $0002
    .word _timer_handler    ; IRQ0: YSD8002タイマー

    .org  $0004
    .word _irq1_handler     ; IRQ1: YSD8004経由（合成注入）

    .org  $0006
    .word _align_handler    ; IRQ3: アラインメント例外（NMI扱い）

    .org  $0008
    .word _syscall_handler  ; IRQ4: SYSCALL

; ================ スタートアップ ================
    .org  $0018
_startup:
    LDW  SP, #$F7FE         ; Cスタック初期値
    LDW  X,  #$0000         ; フレームポインタ初期化
    EI                      ; 割り込み許可（タイマーIRQ受理開始）
    JSR  _main
    HALT

; ================ IRQ0: タイマーハンドラ ================
; IRETでYSD8002_iretが次回発火を再設定する（emu23内部）
_timer_handler:
    IRET

; ================ IRQ1: YSD8004経由ハンドラ ================
; IRQ_STAT($FCB2)をWrite-to-ClearしてIRET
_irq1_handler:
    PUSH A                  ; A退避（ABI: caller-saved保護・外側ループA破壊防止）
    PUSH B                  ; B退避
    LDW  A, #$FCB2          ; IRQ_STAT アドレス
    LDW  B, [A]             ; 読み出し
    STW  B, [A]             ; Write-to-Clear
    POP  B                  ; B復帰
    POP  A                  ; A復帰
    IRET

; ================ IRQ3: アラインメント例外（NMI）================
_align_handler:
    HALT

; ================ IRQ4: SYSCALLハンドラ ================
_syscall_handler:
    IRET

; ================ _main: 長いカウントダウンループ ================
; 2重ループで十分なサイクル数を稼ぎ、タイマーtickを多数発生させる。
; 外側 OUTER 回 × 内側 $FFFF 回。
; 目標: 総サイクル数が timer period(40000) の数百倍 = 数千万サイクル規模。
    .org  $0400
_main:
    LDW  A, #200            ; 外側カウンタ OUTER=200
_outer:
    LDW  B, #$FFFF          ; 内側カウンタ=65535
_inner:
    SUBI B, #1
    CMPI B, #0
    BNE  _inner
    SUBI A, #1
    CMPI A, #0
    BNE  _outer
    RET
