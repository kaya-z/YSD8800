; ================================================================
;  v6t_mask.asm   v0.1  (2026-07-18)
;  ★EN是正工程 負例テスト（KY54: 負例先行）★
;  ベース: v5t_ack.asm v0.2 からの派生（TCR書込値のみ変更）
;  YSD8800 FPGA EN是正 / 負例統合TB テストプログラム
;
;  【検証内容 — 是正の生命線】
;    TCR = $0001 (TIMER_EN=1, ★IRQ_EN=0★) を書く。
;    ・旧OR実装 : (tcr&0x03)!=0 → irq_enabled=1 → ★発火する(CNT>0)★
;    ・案B AND化 : (tcr&0x01)&&(tcr&0x02) = 1&&0 = 0 → ★発火しない(CNT=0)★
;    → この負例のみが OR と AND を弁別できる（$03正例は両方発火）。
;
;  【期待（案B・emu23 v1.11 / RTL v0.3）】
;    CNT = 0 （IRQ_EN=0 が割込マスクとして機能＝契約回復の直接証明）
;
;  【もし CNT>0 なら】
;    → AND化が効いていない or 片側乖離。是正失敗として原因究明する。
;
;  ★ISA2.3 に存在する命令のみ使用（v5t_ack.asm と同一命令セット）★
; ================================================================

TCR         EQU $FC90       ; emu23 L596
TCR_MASK    EQU $0001       ; ★TIMER_EN=1 / IRQ_EN=0★（負例の要）

CNT         EQU $0200       ; ハンドラ呼出回数（期待=0）
OUTC        EQU $0202
INC_        EQU $0204
SAVE_A      EQU $0210
SAVE_B      EQU $0212

; ================ ベクタテーブル ================
    .org  $0000
    .word START             ; ★reset★

    .org  $0002
    .word TIMER_ISR         ; ★IRQ0: YSD8002 タイマー★

    .org  $0004
    .word $0000             ; IRQ1 (未使用)

; ================ 本体 ================
    .org  $0100
START:
    DI

    ; ★SP初期化（v5t_ack派生・同一）★
    LDW  SP, #$FC7E         ; $FC80(MMIO境界)未満・下降スタック・emu23初期値一致

    LDW  A, #0
    STW  A, [CNT]
    STW  A, [OUTC]

    ; ★PERIOD は書かない（デフォルト 40000）★
    ; ★TCR = $0001 (TIMER_EN=1, IRQ_EN=0)★ ← 負例の核心
    ;   案BのANDなら irq_enabled=0 で発火しない。
    LDW  A, #1
    STW  A, [TCR]

    EI

    ; ---- 二重ループ: 外200 × 内100 = 2万回（short版・RTLシムMAX_CYC整合）----
    ;   ★内ループ長は #1000→#100 に短縮（CHAT104: RTLシムのMAX_CYC=3M内で完走させるため）。
    ;   短縮後も実サイクル数は PERIOD=40000 を十分に跨ぐことをアセンブル後に実測確認する。
    ;   跨がない場合は PERIOD 側を短縮して負例条件（発火機会がある中でCNT=0）を担保する。
OUTLP:
    LDW  A, #0
    STW  A, [INC_]
INLP:
    LDW  A, [INC_]
    ADDI A, #1
    STW  A, [INC_]
    LDW  B, #100
    CMP  A, B
    BLT  INLP

    LDW  A, [OUTC]
    ADDI A, #1
    STW  A, [OUTC]
    LDW  B, #200
    CMP  A, B
    BLT  OUTLP

    DI
    ; ★判定値: A ← CNT （期待=0）★
    LDW  A, [CNT]
    HALT

; ================ タイマー割込ハンドラ ================
;   ★案Bが正しければ、このハンドラは1度も呼ばれない★
;   （呼ばれたら CNT>0 となり是正失敗が検出される）
TIMER_ISR:
    DI
    STW  A, [SAVE_A]
    STW  B, [SAVE_B]

    ;--- ACK＋再武装（万一発火した場合に周期を維持し、CNTを増やして失敗を顕在化）---
    LDW  B, #$0023          ; TIMER_EN|IRQ_EN|IRQ_ACK
    STW  B, [TCR]

    LDW  A, [CNT]
    ADDI A, #1
    STW  A, [CNT]

    LDW  B, [SAVE_B]
    LDW  A, [SAVE_A]
    IRET
