**YUI OS カーネル メモリマップ対応設計書**

YSD8800 YUI OS Microkernel / kernel.asm v0.10 / kernel_forth.fs v0.6

Version 1.2  /  2026-05-03

# **改版履歴**

| **版数** | **日付** | **変更内容** |
| --- | --- | --- |
| v1.0 | 2026-04-23 | 初版作成（kernel.asm v0.7 / kernel_forth.fs v0.3 ISA2.3メモリマップ対応） |
| v1.1 | 2026-04-23 | 9章 動作確認にlnk23経由ビルドフロー・バイナリ一致確認を追記 |
| v1.2 | 2026-05-03 | Ph.3-A5 UARTドライバ実装に伴う領域追記: §3メモリマップに$E210-$E22F（UARTリングバッファ変数）・$E230（テスト文字列）・$42A2-$42A8（IRQ1ワーク変数）を追加。§10 Ph.3-A5動作確認結果追加。対象kernel.asm v0.10 / kernel_forth.fs v0.6 |

# **1. 概要**

本文書は、YSD8800 YUI OS マイクロカーネルの構成ファイルである kernel.asm および kernel_forth.fs を ISA2.3 v2.2.1 メモリマップに対応させた変更内容を記述する。

変更の主目的は以下の2点である。

① TCBプール・ワーク変数・タスクスタックがROM領域($0000–$3FFF)および旧Dictionary領域($E0xx)に配置されていた問題を解消し、RAM領域に正しく移動する。

② FPGA実装時にROM書き込みが発生しない設計に整合させる。

# **2. 対象ファイルとバージョン**

| **ファイル** | **旧バージョン** | **新バージョン** | **備考** |
| --- | --- | --- | --- |
| kernel.asm | v0.6 | v0.7 | アドレス定数・スタック計算全面改定 |
| kernel_forth.fs | v0.2 | v0.3 | CONSTANT定数・TCB-ADDR全面改定 |
| ysd8800_kern.tgt | v0.1(ISA2.2) | v0.2(ISA2.3) | CODE-START/DATA-START/ASSEMBLER変更 |

# **3. ISA2.3 v2.2.1 メモリマップ（Forceマシン）**

kernel.asm v0.7 適用後のアドレス配置を以下に示す。★印が本改版での変更箇所。

| **アドレス** | **用途** | **種別** | **備考** |
| --- | --- | --- | --- |
| $0000–$000F | ベクタテーブル | ROM | ISA2.3共通（変更なし） |
| $0010–$07FF | Forthカーネル本体（kernel.asm） | ROM | kernel.asm v0.10配置 |
| $0800–$3FFF | カーネルコード拡張 | ROM | 将来RAM化候補 |
| $4000–$427F | TCBプール（8タスク×80B=640B） | RAM | v0.8でTCB 64B→80Bに拡張 |
| $4280–$42A1 | カーネルワーク変数・IPC変数 | RAM | L1_WK / IRQ_WK / IPC4_WK |
| $42A2–$42A8 | IRQ1専用ワーク変数（★v1.2追加） | RAM | IRQ1_WK_A/B/X/BYTE (kernel.asm v0.10追加) |
| $42A9–$423F | 予備（カーネルワーク拡張余地） | RAM | |
| $4400–$EFFF | Forth辞書（Dictionary） | RAM | Forceコンパイラ配置先 |
| $E200–$E203 | ページビットマップ（Ph.2追加） | RAM | PAGE-BMP-LO/HI |
| $E204–$E205 | MemMgr TID格納 | RAM | MEM-TID-ADDR |
| $E206–$E20F | 予備 | RAM | |
| $E210–$E21F | UARTリングバッファ本体（★v1.2追加） | RAM | 16B固定 (UART-RX-RING-BUF, kernel_forth.fs v0.6追加) |
| $E220–$E221 | UART_RX_HEAD（★v1.2追加） | RAM | 書き込み位置 (0-15) |
| $E222–$E223 | UART_RX_TAIL（★v1.2追加） | RAM | 読み出し位置 (0-15) |
| $E224–$E225 | UART_RX_COUNT（★v1.2追加） | RAM | バッファ内バイト数 (0-16) |
| $E226–$E227 | UART_DRV_TID（★v1.2追加） | RAM | UARTドライバタスクID |
| $E228–$E229 | UART_WAIT_TID（★v1.2追加） | RAM | UART_GETC待ちクライアントtid |
| $E22A–$E22F | 予備（UART変数拡張余地） | RAM | |
| $E230–$E232 | テスト文字列"BC\0"（★v1.2追加） | RAM | UART-TEST-TASK用、_kstartで初期化 |
| $E233–$EFFF | Forth辞書末尾（予備） | RAM | |
| $F000–$F7FF | Forth Workspace | RAM | HEREポインタ等 |
| $F800–$FBCF | Stacks（データ＋コールスタック） | RAM | 全タスクスタック配置 |
| $FBD0–$FBFF | ランタイムワーク変数 | RAM | scc23予約（変更なし） |
| $FC00–$FC7F | 予備 | RAM | Stacks拡張またはシステム用途 |
| $FC80–$FFFF | I/O（UART等） | I/O | 変更なし |

# **4. アドレス対照表（旧→新）**

| **用途** | **旧アドレス** | **新アドレス** | **変更理由** |
| --- | --- | --- | --- |
| TCBプール (8タスク×64B) | $1000 | $4000 | ROM→RAM (ISA2.3メモリマップ準拠) |
| L1_WK_A/B/C | $E020〜$E024 | $4200〜$4204 | Dictionary領域→RAM先頭付近 |
| L1_WK_TMP | $E028 | $4208 | 同上 |
| IRQ_WK_X / IRQ_WK_A | $E030/$E032 | $4210/$4212 | 同上 |
| SLP_WK_DSP / SLP_WK_PC | $E038/$E03A | $4218/$421A | TASK_SLEEP専用退避 |
| CUR_TASK / NEXT_TASK | $E100/$E102 | $4220/$4222 | 同上 |
| TASK_COUNT | $E104 | $4224 | 同上 |
| TC_WK_ENTRY / TC_WK_TID | $E040/$E042 | $4228/$422A | TASK_CREATE専用退避 |
| IPC_WK_A/B/X | $E044〜$E048 | $422C〜$4230 | IPC専用ワーク |
| tid=0 コールスタック頂上 | $23FE | $FBCE | ROM→Stacks領域($F800-$FBCF) |
| tid=0 データスタック頂上 | $21FE | $F9CE | 同上 |
| tid=1 コールスタック頂上 | $27FE | $FACE | CALLSTK_BASE - $100 |
| tid=1 データスタック頂上 | $25FE | $F8CE | DATASTK_BASE - $100 |
| タスクスタックギャップ | $0400 | $0100 | 8タスク×$100×2=2KB |
| カーネルSP切替先 (KERN_SP) | $FBFE | $FBCE | 予約領域外→Stacks領域上端 |

# **5. タスクスタック配置詳細**

タスクスタックは Stacks 領域（$F800–$FBCF）に収める。タスクあたりのギャップを $0400 から $0100 に縮小し、8タスク×2スタック×$100 = 2048B を確保する。

| **tid** | **CALLSTK_BASE** | **DATASTK_BASE** | **コールスタック範囲** | **データスタック範囲** |
| --- | --- | --- | --- | --- |
| 0 | $FBCE | $F9CE | $FACE–$FBCE (256B) | $F8CE–$F9CE (256B) |
| 1 | $FACE | $F8CE | $EACE–$FACE (256B) | $F7CE–$F8CE (256B) |
| 2 | $FBCE-$200 | $F9CE-$200 | 同様に$100ずつ下方向 | 同左 |
| … | … | … | … | … |
| 7 | $FBCE-7×$100 | $F9CE-7×$100 | 最下位 | 最下位 |

# **6. kernel.asm v0.7 変更詳細**

## **6.1 定数変更**

EQU定数をRAM領域の新アドレスに変更した。hasm23はEQU定数の四則演算式（例: TCB_POOL+64）に非対応のため、演算結果を数値リテラルで展開している。

## **6.2 TASK_CREATE スタック計算ロジック変更**

旧実装: コールスタック頂上 = $23FE + tid × $400 （加算・左シフト10bit）

新実装: コールスタック頂上 = CALLSTK_BASE($FBCE) - tid × $100 （減算・左シフト8bit）

  LDW  B, #8

  SHL  A, B               ; A = tid * 256 ($100)

  LDW  B, #$FBCE          ; CALLSTK_BASE

  SUB  B, A               ; B = CALLSTK_BASE - tid*$100

## **6.3 カーネル初期化（_kstart）変更**

SP初期値を $FBFE（予約領域侵入）から $FBCE（Stacks領域上端）に変更。DSP初期値を $F700（旧）から $F800（Stacks領域先頭）に変更。

## **6.4 カーネルSPスイッチ変更**

TASK_SLEEP・TASK_EXIT・MSG_RECV 内でのカーネルSP切替先を $FBFE から $FBCE（KERN_SP）に変更した。

# **7. kernel_forth.fs v0.3 変更詳細**

Forthレイヤーの定数（CONSTANT）をkernel.asm v0.7と整合する値に更新した。

| **定数名** | **旧値** | **新値** | **変更内容** |
| --- | --- | --- | --- |
| TCB-POOL | $1000 | $4000 | TCBプールをRAM領域に移動 |
| CALLSTK-BASE | $23FE | $FBCE | Stacks領域に移動 |
| DATASTK-BASE | $21FE | $F9CE | 同上 |
| TASK-STK-GAP | $0400 | $0100 | ギャップを縮小（256B/タスク） |
| CUR-TASK-ADDR | $E100 | $4220 | カーネル状態変数をRAMに移動 |
| TCB-ADDR (定義内) | $1000 + | TCB-POOL + | ハードコードを定数参照に変更 |

# **8. ysd8800_kern.tgt v0.2 変更詳細**

| **項目** | **旧値** | **新値** | **変更理由** |
| --- | --- | --- | --- |
| ASSEMBLER | hasm22 | hasm23 | ISA2.3対応アセンブラに変更 |
| CODE-START | $1200 | $4400 | TCBプール・ワーク変数の後に配置 |
| DATA-START | $E200 | $C000 | Dictionary領域中間に配置 |

# **9. 動作確認**

## **9.1 確認環境**

| **項目** | **内容** |
| --- | --- |
| アセンブラ | hasm23 v1.01 (2026-04-21) |
| リンカ | lnk23 v2.00 (2026-04-21) |
| エミュレータ | emu23 v1.01 (2026-04-19) |
| 対象ファイル | kernel.asm v0.7 |

## **9.2 ビルドフロー（lnk23経由）**

lnk23がForceカーネル（kernel.asm）のリンクに対応していることの検証を兼ねて、lnk23スクリプトモードを経由したビルドフローで動作確認を実施した。

# Step 1: アセンブル

./hasm23 kernel.asm

  -> kernel.asm.bin  kernel.asm.sym

# Step 2: リンクスクリプト (kernel.lds)

OUTPUT kernel_final.bin

SYMOUT kernel_final.sym

SECTION code 0x0000 kernel.asm.bin kernel.asm.sym

# Step 3: リンク

./lnk23 kernel.lds

  -> kernel_final.bin (3806 bytes)  kernel_final.sym (76 symbols)

# Step 4: 実行

./emu23 kernel_final.bin -q

## **9.3 確認結果**

| **確認項目** | **結果** | **備考** |
| --- | --- | --- |
| アセンブル（hasm23 v1.01） | ✅ PASS | エラーなし |
| lnk23 v2.00 リンク | ✅ PASS | 3806 bytes / 76 symbols 出力 |
| バイナリ一致確認 | ✅ PASS | 直接アセンブル出力とlnk23経由出力が完全一致 |
| emu23 v1.01 起動 | ✅ PASS | 正常起動 |
| タスク0出力（T0×3） | ✅ PASS | T0 T0 T0  確認 |
| タスク1出力（T1×3） | ✅ PASS | T1 T1 T1  確認 |
| タスクスイッチ（WAKEUP/SLEEP） | ✅ PASS | T0→T1→T0→… 正常交互出力 |

# **10. Ph.3-A5 動作確認（v1.2追加）**

## **10.1 確認環境**

| **項目** | **内容** |
| --- | --- |
| アセンブラ | hasm23 v1.01 (2026-04-22) |
| リンカ | lnk23 v2.00 |
| エミュレータ | emu23 v1.02 (2026-04-29、IRQ_MASK初期値修正版) |
| 対象ファイル | kernel.asm v0.10 / kernel_forth.fs v0.6 |
| 設計書 | yuios_ph3_uart_design_v1_2.docx |

## **10.2 ビルド成果物**

| **ファイル** | **サイズ** |
| --- | --- |
| yuios_v10.bin | 55,335 bytes |
| yuios_v10.sym | 349 symbols |

## **10.3 確認結果**

| **確認項目** | **結果** | **備考** |
| --- | --- | --- |
| 期待出力 "ABCXD" | ✅ PASS | -i uart_test_input.bin (printf 'X') 使用 |
| Ph.2 回帰テスト "M28AR" | ✅ PASS | yuios_v09.bin での無回帰確認 |
| Dhrystone N=10 動作 | ✅ PASS | 826 Dhrystones/sec（emu23修正後も同値） |
| セルフチェック C1〜C7 | ✅ PASS | 全7項目合格（設計書§5.5.4） |

## **10.4 今後の作業**

① 本設計書 v1.2 をプロジェクトナレッジに登録する。

② 手順11完了をもって Ph.3-A5 実装完了とする。

③ 次工程（Step 8-S: emu23ストレージ実装）に進む。