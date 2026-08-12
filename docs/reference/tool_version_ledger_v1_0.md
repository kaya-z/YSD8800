# YSD8800 / YUI OS ツールバージョン管理台帳

Version 1.0  /  2026-06-06

| 項目 | 内容 |
| --- | --- |
| 文書番号 | TOOL-VERSION-LEDGER-001 |
| 目的 | YSD8800 ツールチェーン各ツールの現行バージョンを一元管理する（kaizen 原則：ツール類はバージョンを常にリスト管理） |
| 対象 ISA | YSD8800 ISA2.3 |
| 作成日 | 2026-06-06 |
| ステータス | 確定 |

## 改版履歴

| 版数 | 日付 | 内容 | 担当 |
| --- | --- | --- | --- |
| v1.0 | 2026-06-06 | 初版作成。現行ツール一覧を整備。emu23 を v1.04→**v1.05**（stack watermark 計測統合）に更新したことを契機に、バージョン管理台帳として独立文書化。 | Claude |

## 1. 現行ツールバージョン一覧（2026-06-06 時点）

| ツール | 現行版 | ソースファイル | 役割 | 直近の変更 |
| --- | --- | --- | --- | --- |
| Force | v1.5 | force_v1_5.c | Forth クロスコンパイラ | VARIABLE/VALUE/DEFER のデータ部とgetterコード部を分離出力 |
| scc23 | v1.00 | scc23_v1_00.c | Small-C 派生 C コンパイラ | ISA2.3 初版（Dhrystone 対応） |
| hasm23 | v1.02 | hasm23_v1_02.c | アセンブラ | W001 .org 重ね書き警告、E001 ラベル二重定義エラー |
| disasm23 | v1.00 | disasm23.c | 逆アセンブラ | ISA2.3 初版 |
| lnk23 | v2.00 | lnk23.c | YOF リンカ | スクリプトモード |
| **emu23** | **v1.05** | **emu23_v105.c** | エミュレータ（UART/Timer/SD/IRQ統合 + stack watermark計測） | **v1.05: stack watermark 計測機能（-w/--wm-steps/--wm-warmup）統合。-w 無指定時 v1.04 と完全同一動作（非回帰確認済み）・Dhrystone 回帰 PASS** |
| mkfs_yuifs.py | v1.1 | mkfs_yuifs_v1_1.py | YUI FS ディスクイメージ作成 | --add-file オプション追加 |
| force_asm_audit.py | v1.2 | force_asm_audit_v1_2.py | Force 生成 asm の禁止領域検査 | yuios_memmap_design v1.4 禁止領域対応 |

## 2. emu23 バージョン系譜

| 版 | 日付 | 主な変更 | 設計書 |
| --- | --- | --- | --- |
| v1.00 | 2026-04-16 | ISA2.3 初版（emu22 v1.23 ベース。SYSCALL 1バイト化・YSD8002・Dhrystone計測） | toolchain23_design_v1_2.docx |
| v1.02 | — | デバイス実装拡張 | emu23_v102_design_v1_3.docx |
| v1.03 | 2026-05-03 | メインループ・デバイス実装（YSD8003 deferred completion IRQ 等） | emu23_v103_design_v1_4.md |
| v1.04 | 2026-05-18 | YSD8004 irq_pending 上書き保護 + IRQ_STAT 再評価、DBG printf 除去 | （v1.03設計書に内包） |
| **v1.05** | **2026-06-06** | **stack watermark 計測機能統合（-w/--wm-steps/--wm-warmup）。試験専用 I3-POOL は非搭載** | **emu23_v105_design_v1_0.md** |

## 3. 関連文書

| 文書 | 版 | 用途 |
| --- | --- | --- |
| yuios_build_procedure | v1.5 | ビルド手順書（対象ツール表が実運用上のバージョン参照点） |
| emu23_v105_design | v1.0 | emu23 v1.05 改修設計書 |
| emu23_debug_manual | v1.1 | emu23 デバッグ・ユーザマニュアル（v1.05 対応） |
| toolchain23_design | v1.2 | ツールチェーン設計起点（各ツール v1.00 時点の設計。起点記録として保持） |

## 4. 運用ルール

- ツールを改修・更新したら、本台帳の §1 現行版と該当ツールの系譜表を更新する。
- ツール改修時は回帰チェック（Dhrystone）を実施（Force 改修時は対象外）。
- ツールのバナー／ソース VERSION 定義と本台帳の版数が一致することを定期確認する（記憶に頼らず grep で実体確認）。
- 現行版の更新時も、過去版の系譜記録は欠落させない。
