; ================================================================
;  v6t_sdread.asm   v0.1  (2026-07-19)
;  YSD8800 FPGA V6-A / CHAT109 Step4 統合TB テストプログラム
;
;  【検証内容】
;    CPU が実バス経由で YSD8003(ストレージ)へ CMD17 読出を発行し、
;    512B のデータを PIO 読出して既知パターンと照合する。
;    ★実 wait-state(ready合流)・実 MMIO デコード・CPUストールを通す★
;    単体TB(tb_ysd8003) の T2/T3 を CPU経由で再現する。
;
;  【SD レジスタマップ (sd_sample.c L47-54 / $FCA0 基点)】
;    $FCA0 SD_CMD  : 0=READ_SETUP / 1=WRITE_SETUP / 2=EXEC
;    $FCA2 SD_STAT : bit0=BUSY / bit1=ERROR / bit2=READY
;    $FCA4 LBA_LO  : LBA 下位16bit
;    $FCA6 LBA_HI  : LBA 上位16bit
;    $FCAA SD_DATA : PIO 8bit (読出で BUF_PTR 自動++)
;
;  【期待パターン (sd_spi_model / 単体TB T2 と同一)】
;    LBA=1 の 512B は data[i] = (1*512 + i) & 0xFF。
;    i=0..255 で 0x00..0xFF、i=256..511 で再び 0x00..0xFF。
;    → 期待値は下位8bitのみ。i を 8bit で回して (i & 0xFF) と一致すればよい。
;      (512+i)&0xFF == i&0xFF （512 は 0x200 で下位8bit=0）。
;
;  【STAT 待ち (案D wait-state 環境)】
;    実バスでは STAT 読み時に SPI 未完なら ready_o=0 で CPU がストールする。
;    安全側に STAT を READY(bit2) が立つまでループ読みする(単体TB T3 と同型)。
;    ERROR(bit1) 検出時は即座に失敗として HALT。
;
;  【判定】
;    最後に A ← MISM(不一致数)。0 なら全512B一致=成功。
;    RESULT アドレスにも保存し、TB が階層参照で確認できるようにする。
;
;  ★ISA2.3 に存在する命令のみ使用★ (hasm23_v1_04 命令表で確認済)
; ================================================================

SD_CMD      EQU $FCA0
SD_STAT     EQU $FCA2
SD_LBA_LO   EQU $FCA4
SD_LBA_HI   EQU $FCA6
SD_DATA     EQU $FCAA

CMD_READ    EQU $0000       ; READ_SETUP
CMD_EXEC    EQU $0002       ; EXEC
STAT_ERR    EQU $0002       ; bit1
STAT_RDY    EQU $0004       ; bit2

; ---- 作業/結果領域 (PSRAM 低位・プログラムと非重複) ----
MISM        EQU $0300       ; 不一致カウント(16bit)
IDX         EQU $0302       ; ループインデックス(0..511, 16bit)
SAVE_X      EQU $0304
RESULT      EQU $0306       ; 最終結果(0=成功)

; ================ ベクタテーブル ================
    .org  $0000
    .word START             ; ★reset★

    .org  $0002
    .word $0000             ; IRQ0 (未使用)

    .org  $0004
    .word $0000             ; IRQ1 (未使用・本テストはポーリング)

; ================ 本体 ================
    .org  $0100
START:
    DI                      ; 割込は使わずポーリング

    ; --- MISM=0, IDX=0 初期化 ---
    LDW  A, #0
    STW  A, [MISM]
    STW  A, [IDX]

    ; --- LBA=1 設定 ---
    LDW  A, #1
    STW  A, [SD_LBA_LO]
    LDW  A, #0
    STW  A, [SD_LBA_HI]

    ; --- READ_SETUP → EXEC ---
    LDW  A, #$CMD_READ
    STW  A, [SD_CMD]
    LDW  A, #$CMD_EXEC
    STW  A, [SD_CMD]

    ; --- STAT を READY(bit2) まで待つ（ERRORなら失敗）---
WAIT_RDY:
    LDW  A, [SD_STAT]
    LDW  B, #$STAT_ERR
    AND  A, B               ; A = STAT & ERROR
    BNE  RD_ERROR           ; ERROR ビット立ち → 失敗
    LDW  A, [SD_STAT]
    LDW  B, #$STAT_RDY
    AND  A, B               ; A = STAT & READY
    BEQ  WAIT_RDY           ; READY 未立ち → 継続待ち

    ; --- 512B 読出・照合ループ ---
    ;   i(IDX) を 0..511 で回し、SD_DATA を LDB で読む。
    ;   期待値 = i & 0xFF。不一致なら MISM++。
RD_LOOP:
    LDB  A, [SD_DATA]       ; A(下位8bit) ← 実データ 1バイト
    LDW  B, [IDX]
    ANDI B, #$00FF          ; B = i & 0xFF = 期待値
    CMP  A, B
    BEQ  RD_MATCH
    ; --- 不一致: MISM++ ---
    LDW  A, [MISM]
    ADDI A, #1
    STW  A, [MISM]
RD_MATCH:
    ; --- IDX++ ---
    LDW  A, [IDX]
    ADDI A, #1
    STW  A, [IDX]
    ; --- i < 512 なら継続 ---
    LDW  B, #512
    CMP  A, B
    BLT  RD_LOOP

    ; --- 判定: A ← MISM, RESULT へ保存, HALT ---
    LDW  A, [MISM]
    STW  A, [RESULT]
    HALT

; ---- エラー経路: RESULT = $FFFF (異常) ----
RD_ERROR:
    LDW  A, #$FFFF
    STW  A, [RESULT]
    HALT
