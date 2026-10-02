# v25_rtl_inspection_record_v0_1.md — ②RTL実装総点検 点検記録表

| 項目 | 内容 |
|---|---|
| 文書名 | ②RTL実装総点検 点検記録表 |
| 版数 | v0.1 |
| 作成日 | 2026-09-26 |
| 様式 | 計画書§6.2（ID／観点／対象／事実／探索範囲／反証／根拠設計メモ／判定／重大度） |
| 対応 | `v25_rtl_inspection_report_v0_2.md`（review r1.0 RV-3対応） |

---

## 観点A（仕様⇔RTL：レジスタ・ビット網羅）

| ID | 対象 | 事実 | 探索範囲 | 反証 | 根拠設計メモ | 判定 | 重大度 |
|---|---|---|---|---|---|---|---|
| A-001 | YSD8001 | TX/RX/STAT/BAUD全レジスタ・ビット意味論・reset値が設計書v1.3.2と一致（`ysd8800_ysd8001_v0_3.sv` L138-151, 156-161） | 設計書§2.2/§3全節 vs RTL全文grep（FC8） | 設計書とRTL両方を個別に開いて突合（片方のみに依拠せず） | `ysd8001_uart_design_v1_3_2.md` | 適合 | — |
| A-002 | YSD8002 | `fire_en=timer_en_r&irq_en_r`（AND）、TCRビット構成一致（`ysd8800_ysd8002_v0_3.sv` L210, L74-76） | 設計書§11 vs RTL全文grep（FC9） | 段0でD-02本文抽出済・RTLコメントも同一経緯を記録 | `ysd8002_timer_design_v1_2.md` | 適合 | — |
| A-003 | YSD8003 | レジスタ構成一致。BUSY挙動は実SPIクロック駆動のwait-state（`spi_busy`/`sck_tick`）で`ready_o`制御（`ysd8800_ysd8003_v0_4.sv` L56, 199, 340-357） | emu23_device_design§6.2 vs RTL全文grep（FCA/FCB） | 案(D)の設計メモ記載と実装ロジックを個別に確認 | `v6a_storage_design_memo_v0_2.md` | 適合（優良） | — |
| A-004 | YSD8004 | bit0=UART_RX/bit1=Storage/bit2=UART_TX、IRQ_MASKリセット値0x04（`ysd8800_ysd8004_v0_1.sv` L81-83） | emu23_device_design§7.1 vs RTL全文grep | UART設計書のreset table（§3.6）と二重照合 | `ysd8001_uart_design_v1_3_2.md` §3.6 | 適合 | — |
| A-005 | MMU | 変換式・挿入位置（デコーダ後段RAM側のみ）・純組合せ構成が設計書と一致（`ysd8800_mmu_v0_1.sv` 全61行） | 設計書§7 vs RTL全文 | 段0で本文抽出済の記述とRTL実体を個別突合 | `YSD8800_MMU_Design_v1_2_0.md` | 適合 | — |
| A-006 | デコーダ | `is_mmio=(addr>=$FC80)`のみの単純組合せ回路（`ysd8800_addr_decoder_v0_1.sv` 全61行） | ファイル全文 | — | `v3_design_memo_v0_3.md` §2 | 適合 | — |
| A-007 | 未接続領域応答 | `mmio_stub_v0_11.sv` L619で`8'hFF`応答を確認（v0.8で是正済） | `emu23_device_design`§4.2 vs RTL grep（8'hFF/8'h00） | 台帳v1.12の是正記録と実源を二重確認 | `emu23_device_design_v1_12.md` | 適合 | — |
| A-008 | UART_BAUD 8bit対象外規定 | emu23の`rd8`/`wr8`固有規定と判明。RTLバスは物理的にバイト単位でありRTL側に欠落なし | `emu23_device_design`§4.4.5 | — | 同上 | 適合（規定の所在を確認） | — |
| E-003 | YSD8004 IRQビット表（マスター文書） | `emu23_device_design_v1_12.md`§7.1.1のIRQ_STAT/IRQ_MASKビット表がbit2(UART TX)を欠落し「bit0=UART RX(将来実装)」のまま。実装済み | §7.1.1本文 vs RTL・UART設計書 | RTL実装・UART設計書の2系統で実装済みと確認 | `ysd8001_uart_design_v1_3_2.md` §5.2/§3.6 | 記録・機能影響なし | S-4 |
| E-004 | MMU ptrポート | `ptr[0:15]`が依然unpacked array形式。原則65の懸念経路とは異なりmembus内部でのみ再展開する構成のため実害なし（段0.5′実測でMISMATCH=0） | RTL全文 vs 段0.5′実測ログ | 実行結果で裏付け | kaizen2.txt 原則65 | 記録・機能影響なし | S-4 |

## 観点C（YUI OS実使用⇔RTL）

| ID | 対象 | 事実 | 探索範囲 | 反証 | 根拠設計メモ | 判定 | 重大度 |
|---|---|---|---|---|---|---|---|
| C-001（静的） | kernel_v12_11.asm / kernel_forth_v0_10_18.fs | MMIOシンボル15種（UART_TX/RX/STAT, TCR, SD_CMD/STAT/LBA_LO/HI/BUF_PTR/DATA/IRQ_CTRL/DISK_LO/HI, IRQ_STAT/MASK）を抽出。$FC00-$FC7F帯のOS内部変数・$FExx帯のエラーコードは除外（P-2対応） | 両カーネル全文grep（EQU/CONSTANT定義）＋非MMIO値の個別判定 | startup_proc_v1_1.asm・sd_sample.cも確認（新規デバイス発見なし） | — | 記録 | — |
| C-002（動的） | `mmio_trace.log`（段0.5′） | 22一意アドレス。総アクセス4,876件 | boot+ver+lsシナリオ全体（cycle 0〜3,754,937） | 既存`mmio_acc`統計（4,875）と突合・1件差異を記録 | — | 記録 | — |
| C-003（和集合） | 静的∪動的 | 静的抽出全シンボルが観点A確認済みレジスタの範囲内。**「YUI OSが使うのにRTLに無い」＝0件** | C-001・C-002の和集合をA-001〜A-006の実装確認結果と突合 | UART_RX・SD_BUF_PTR・SD_DISK_LO/HIが動的トレース外である理由を個別に説明（TB側RX入力なし・ls時未使用） | — | **S-1相当なし** | — |
| C-004 | `--strict-mmio`交差確認 | emu23 v2.16でyuios_road2.binを`ver`/`ls`シナリオ・`--strict-mmio`付き実行。`[MMIO-UNMAPPED]`検出なし | boot+ver+lsシナリオ | — | — | 適合 | — |
| rv-5 | SD_DISK_LO/HI・disk_sectors_i | `SD_DISK_LO`/`SD_DISK_HI`は両カーネルとも定義のみで使用箇所なし（grep再確認：定義行以外に出現なし）。RTL側`disk_sectors_i`はysd8003の入力ポート（L110, 164-167）でTBが定数`32'd16`を供給（TB L267）。実機での供給源（CMD9等）はV6-Aスコープ外で未設計 | kernel_v12_11.asm L406-407・kernel_forth_v0_10_18.fs L509-510の全出現をgrep | 定義行1件のみであることを2ファイルで確認 | — | 記録（現状未使用。将来使用時はS-2化の恐れ） | S-3 |

## 観点B（機能網羅・物理層）

| ID | 対象 | 事実 | 探索範囲 | 反証 | 根拠設計メモ | 判定 | 重大度 |
|---|---|---|---|---|---|---|---|
| B-002 | 割込配線 | UART_TX/RX・SD完了→YSD8004(bit2/0/1)→`irq1_o`、Timer→`irq_timer_o`の配線を確認 | membus/8004ソース全文 | A-004と重複確認 | — | 適合 | — |
| B-003 | SD/UART物理I/F | `spi_*`・`uart_txd_o`/`uart_rxd_i`が実信号として存在 | membus/8001/8003ポート宣言 | — | — | 適合 | — |
| **RV-1** | **PSRAM物理I/F** | **`psram_ctrl_v0_4`のポート（L76-96）にPSRAM物理信号が皆無。`mem`配列（L100）のみで記憶を実現** | psram_ctrl全ポート・membus全ポート(L331-392)をgrep | TKT-V12（同型の先例）と突合 | 計画書§5（`mem`配列を承認済簡略化の例として明記） | **記録・要TKT** | **S-1→TKT-V16(c)** |
| B-001 | CPU割込入力配線 | `irq_in`優先順位ロジックがRTL12本のどこにも存在せず、TB（L169）が代替 | 全RTLファイルgrep（irq_in） | membus L377コメントで「上位で接続」と明記されていることを確認 | — | 記録・要TKT | S-1→TKT-V16(b-1) |
| — | CRC無視・案(D) | V6-Aスコープ（CMD17最小セット）として承認済み | 設計メモ全文 | — | `v6a_storage_design_memo_v0_2.md` | 承認済み簡略化 | — |

## 観点D（emu23⇔RTL差分）

| ID | 対象 | 事実 | 探索範囲 | 反証 | 根拠設計メモ | 判定 | 重大度 |
|---|---|---|---|---|---|---|---|
| D-001 | SD BUSY | emu23は即時fread完了、RTLは実SPI遅延をバスストールで表現。契約（2回読みでREADY）は保存 | 設計メモ§2.2-2.3 vs RTL実装 | — | `v6a_storage_design_memo_v0_2.md` | 適合（RTLがより実機的） | — |
| D-002 | 過去の既知差異 | fire_en OR→AND、未接続応答$00→$FFはいずれも是正済み・回帰確認済み | A-002・A-007と重複確認 | — | — | 適合 | — |
| B-001 | irq_in優先順位 | emu23は割込ディスパッチをソフトウェアで暗黙処理。RTL側に合成可能な等価物なし | 上記B-001と同一所見 | — | — | 記録（観点B・D・F共通） | S-1→TKT-V16(b-1) |

## 観点F（シミュレーション専用構造・合成可能性）

| ID | 対象 | 事実 | 探索範囲 | 反証 | 根拠設計メモ | 判定 | 重大度 |
|---|---|---|---|---|---|---|---|
| F-001 | `initial`/`$display`/`$fatal`/`$error`/`#`遅延 | RTL16本を横断grep。`$error`多数（cache/wbuf/cdc_bridge/psram_ctrl/mmio_stub）はいずれも契約違反検知アサーション（正常動作時の機能に無関係）。`#`遅延は0件 | RTL16本全文grep | 各`$error`呼出し箇所を個別に確認し機能ロジックとの独立性を確認 | — | 適合 | — |
| P-3(a) | psram_ctrl挙動モデル | `mem`配列による挙動モデル（既知） | — | — | 計画書§7 | 記録（RV-1として再掲・TKT-V16(c)） | S-1 |
| P-3 | TBバックドア | `$readmemh`による直接ロード（既知） | — | — | 計画書§7 | 記録（TKT-V16(a)） | S-1 |
| rv-5 | disk_sectors_i | 観点C rv-5と同一所見（TB定数供給・実機での供給源未設計） | — | — | — | 記録 | S-3 |

## 観点G（実機成立性）

| ID | 対象 | 事実 | 探索範囲 | 反証 | 根拠設計メモ | 判定 | 重大度 |
|---|---|---|---|---|---|---|---|
| G-001 | 起動経路 | 未設計（段0.5で確定・既報） | — | — | — | 記録 | S-1→TKT-V16(a) |
| G-002 | FPGAトップ | 不存在（段0.5で確定・既報） | — | — | — | 記録 | S-1→TKT-V16(b) |
| G-003 | CDC | `cache_v0_6.sv`が独自にpsram_clkドメインの`always_ff`を持つが、membus L684で「CDC非経由」と明記。同一クロックドメイン内で完結する経路であり真の跨ぎではない | cache全文・membus L684 | psram_ctrl.beat_valid（同一psram_clkドメインの出力）が発生源であることを確認 | — | 適合（意図的設計） | — |
| G-004 | PSRAM IP接続前提 | RV-1と同一所見 | — | — | — | 記録 | S-1→TKT-V16(c) |
| G-005 | CPU外部I/F駆動源 | トップ不存在のため駆動源も未設計（G-002に含まれる） | — | — | — | 記録 | S-1→TKT-V16(b) |
| rv-7 | BAUDとcpu_clk整合 | ボーレートは`baud_r`リセット値と`cpu_clk`実周波数の両方で決まるが、後者が未確定 | ysd8001 L178・G-002の関連 | — | — | 記録 | S-1→TKT-V16(d) |

## 観点H（台帳・版数整合）

| ID | 対象 | 事実 | 探索範囲 | 反証 | 根拠設計メモ | 判定 | 重大度 |
|---|---|---|---|---|---|---|---|
| H-001 | KY60呼称 | 台帳・計画書が「KY60運用」と呼ぶ慣行はkaizen2.txt実KY60（シェルキーワード前方一致の危険）と無関係。呼称の誤用 | kaizen2.txt L2181実文確認、台帳内「KY60」全出現grep | — | — | 記録 | S-4 |
| P-1 | md5未記録 | R-4/R-5/R-10/R-12の台帳md5記録なし（別系統grep -c 0件で再確認） | 台帳全文 | grep -cで0件確認 | — | 記録 | S-4 |
| P-5 | 台帳L212 | V2-e行「作成予定・実装未着手」未更新（再確認） | 台帳L205-215 | — | — | 記録（範囲外） | S-4 |
| T-1 | ③'設計メモ | 計画書のV5設計メモ版数誤記（v0.2→実際v0.5）。計画書v0.5で是正済 | Drive実ファイル確認 | ARCHIVE_INDEX F-05と突合 | — | 是正済 | — |
| E-005 | ARCHIVE_INDEX D-02行 | ファイル拡張子表記`.docx`が実体（`.md`）と不一致。段0で確認済みだったが報告書v0.1に未記載（review r1.0 rv-6指摘で判明） | Drive検索結果のtitle確認 | Google Drive `search_files`で直接確認 | — | 記録 | S-4 |

## 観点E（先送り記載の横断洗い出し）

| ID | 対象 | 事実 | 探索範囲 | 反証 | 根拠設計メモ | 判定 | 重大度 |
|---|---|---|---|---|---|---|---|
| E-001 | cache_v0_6.sv L55 | 廃止済み「D-C4暫定措置」の記述が冒頭コメントに残存。本文L327-328は正しく更新済み | 検索語11種でRTL12本grep | 本文の該当箇所と冒頭要約を突合 | — | 記録 | S-4 |
| E-002 | membus L445 | cycle_rラップアラウンドが引用する「§3.6」が`v5_design_memo_v0_5.md`に存在しない | 同設計メモ全文検索 | 該当節の不在をファイル全文で確認 | — | 記録・要フォロー | S-4 |
| — | その他13件 | 承認済み先送り・reserved bit・到達不能コード等、正常な記述と確認 | 同上 | 各③'設計メモ・TKT記録と個別突合 | 複数（本文参照） | 適合 | — |

---
*— 以上 `v25_rtl_inspection_record_v0_1.md` —*
