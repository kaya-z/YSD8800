# YSD8800 / YUI OS ツールバージョン管理台帳

Version 1.2  /  2026-06-21

| 項目 | 内容 |
| --- | --- |
| 文書番号 | TOOL-VERSION-LEDGER-001 |
| 目的 | YSD8800 ツールチェーン各ツールの現行バージョンを一元管理する（kaizen 原則：ツール類はバージョンを常にリスト管理） |
| 対象 ISA | YSD8800 ISA2.3 |
| 作成日 | 2026-06-06 |
| 最終改版日 | 2026-06-21 |
| ステータス | 確定 |

## 改版履歴

| 版数 | 日付 | 内容 | 担当 |
| --- | --- | --- | --- |
| v1.0 | 2026-06-06 | 初版作成。現行ツール一覧を整備。emu23 を v1.04→**v1.05**（stack watermark 計測統合）に更新したことを契機に、バージョン管理台帳として独立文書化。 | Claude |
| **v1.1** | **2026-06-21** | **v1.0 以降（Step 8-Y/Step 8-F）のツール版数変更を一括反映。** ①scc23 v1.00→**v1.04**（ポインタバグ修正 P1〜P7 等。台帳 v1.0 では旧 v1.00 のまま放置されていたため是正）。②hasm23 v1.02→**v1.03**（(A).global 追加・(B)UNDEF複数参照）→**v1.04**（道2: YOFモード .org 配置尊重・has_org・.vector 遅延書き込み）。③lnk23 v2.00→**v2.01**（道2: load_addr+has_org 尊重の固定配置・--machine force）。④emu23 v1.05→**v1.06**（F-001: `bd` コマンド到達不能バグ修正）。⑤§2 に emu23 v1.06 系譜追記。⑥§3 関連文書を最新版（build_procedure v1.6 / hasm23_xref_yof_design v2.3）に更新。過去版系譜は欠落させず保持。 | Claude |
| **v1.2** | **2026-06-21** | **Step 8-B（ビルドシステム改善）成果物を登録。** ①§1 現行ツール一覧に **Makefile v1.0**・**mk_post1.sh v1.0** をビルドシステム成果物として追加。②§2.7 として「ビルドシステム系譜」を新設。③§3 関連文書の build_procedure を **v1.6→v1.7**（§4.12 Makefile 節新設）に更新。④Makefile/mk_post1.sh は build_road2.sh および既知 Dhrystone 手順の**バイト等価**移植であり、yuios=56416 完全一致・Dhrystone 826/48405/P:20 一致を MK-1〜MK-6 で確認済み。過去版系譜は欠落させず保持。 | Claude |

## 1. 現行ツールバージョン一覧（2026-06-21 時点）

| ツール | 現行版 | ソースファイル | 役割 | 直近の変更 |
| --- | --- | --- | --- | --- |
| Force | v1.5 | force_v1_5.c | Forth クロスコンパイラ | VARIABLE/VALUE/DEFER のデータ部とgetterコード部を分離出力 |
| scc23 | **v1.04** | scc23_v1_04.c | Small-C 派生 C コンパイラ | v1.01 ポインタバグ P1〜P7 修正以降の系列。v2.00（float/定数畳み込み）は Step 8-I 後に予定 |
| hasm23 | **v1.04** | hasm23_v1_04.c | アセンブラ | **v1.03: (A).global 追加・(B)UNDEF複数参照／v1.04: 道2（YOFモード .org 配置アドレス尊重・has_org フラグ・.vector 遅延書き込み）** |
| disasm23 | v1.00 | disasm23.c | 逆アセンブラ | ISA2.3 初版 |
| lnk23 | **v2.01** | lnk23_v2_01.c | YOF リンカ | **v2.01: 道2（YOF load_addr+has_org 尊重の固定配置・--machine force・固定/自動混在エラー）** |
| **emu23** | **v1.06** | **emu23_v106.c** | エミュレータ（UART/Timer/SD/IRQ統合 + stack watermark計測） | **v1.06: F-001（`bd` コマンド分岐順序バグ＝`b` 分岐が `bd` を先取りし到達不能）修正。Dhrystone 回帰 826/48405/P:20 PASS** |
| mkfs_yuifs.py | v1.1 | mkfs_yuifs_v1_1.py | YUI FS ディスクイメージ作成 | --add-file オプション追加 |
| force_asm_audit.py | v1.2 | force_asm_audit_v1_2.py | Force 生成 asm の禁止領域検査 | yuios_memmap_design v1.4 禁止領域対応 |
| **Makefile** | **v1.0** | **Makefile** | **YUI OS/Dhrystone ビルドシステム（Step 8-B）** | **yuios（道2 S1〜S7）/dhrystone（D1〜D7・lds 自動生成）/disk/run/regress/verify/clean を単一 Makefile に集約。build_road2.sh とバイト等価。`.ONESHELL:`/`SHELL:=/bin/bash`/`.SHELLFLAGS:=-ec` 必須** |
| **mk_post1.sh** | **v1.0** | **mk_post1.sh** | **Makefile 後処理1（S2: #WORD_xxx 混入行除去）** | **build_road2.sh Step2 のバイト等価移植（新規ロジックなし）。引数 $1=forth asm / $2=hasm パス。Makefile から `bash ./mk_post1.sh` で呼ぶ（実行権限非依存）** |

## 2. emu23 バージョン系譜

| 版 | 日付 | 主な変更 | 設計書 |
| --- | --- | --- | --- |
| v1.00 | 2026-04-16 | ISA2.3 初版（emu22 v1.23 ベース。SYSCALL 1バイト化・YSD8002・Dhrystone計測） | toolchain23_design_v1_2.docx |
| v1.02 | — | デバイス実装拡張 | emu23_v102_design_v1_3.docx |
| v1.03 | 2026-05-03 | メインループ・デバイス実装（YSD8003 deferred completion IRQ 等） | emu23_v103_design_v1_4.md |
| v1.04 | 2026-05-18 | YSD8004 irq_pending 上書き保護 + IRQ_STAT 再評価、DBG printf 除去 | （v1.03設計書に内包） |
| **v1.05** | **2026-06-06** | **stack watermark 計測機能統合（-w/--wm-steps/--wm-warmup）。試験専用 I3-POOL は非搭載** | **emu23_v105_design_v1_0.md** |
| **v1.06** | **2026-06-20** | **F-001 修正：`bd N` コマンドの分岐順序バグ（`cmd[0]=='b'` 分岐が `strncmp(cmd,"bd",2)` を先取りし到達不能）を、`bd` 分岐を `b` 分岐の前へ移動して解消。Dhrystone 回帰 826/48405/P:20 一致** | emu23_v105_design_v1_0.md（v1.06 差分は HANDOVER_CHAT61.md に記録） |

## 2.5 hasm23 バージョン系譜

| 版 | 日付 | 主な変更 | 設計書 |
| --- | --- | --- | --- |
| v1.01 | — | -c（YOF オブジェクト出力）追加・lnk23 Phase1 対応 | toolchain23_design_v1_2.docx |
| v1.02 | — | W001 .org 重ね書き警告・E001 ラベル二重定義エラー・常時バナー | （v1.02 内コメント） |
| v1.03 | 2026-06-20 | (A) `.global` 疑似命令追加（export 専用・未定義エラー）／(B) UNDEF 複数参照対応 | hasm23_xref_yof_design_v1_1.md |
| **v1.04** | **2026-06-21** | **道2：YOFモードの `.org` を配置アドレスとして尊重（空白除去・sec_origin 記録・load_addr 出力・offset 相対化・has_org フラグ）。`.vector` を持つセクションは sec_origin=$0000 強制＋ベクタ遅延書き込み** | **hasm23_xref_yof_design_v2_3.md** |

## 2.6 lnk23 バージョン系譜

| 版 | 日付 | 主な変更 | 設計書 |
| --- | --- | --- | --- |
| v2.00 | — | lnk22 から全面再設計。YOF 対応・2パスシンボル解決・リロケーション・lds スクリプト | lnk23_design_v1_3.docx |
| **v2.01** | **2026-06-21** | **道2：YOF セクションの load_addr＋has_org を読み、has_org=1 なら（$0000 でも）固定配置・has_org=0 は自動配置。`--machine force` で ROM 境界回避・固定/自動混在エラー** | **hasm23_xref_yof_design_v2_3.md §3.5.3** |

## 2.7 ビルドシステム系譜（Makefile / mk_post1.sh）

| 成果物 | 版 | 日付 | 主な内容 | 設計書 |
| --- | --- | --- | --- | --- |
| Makefile | **v1.0** | 2026-06-21 | Step 8-B。道2 OS（S1〜S7）と Dhrystone（D1〜D7）を単一 Makefile に並置。Dhrystone の lds は Makefile 規則で自動生成（No.4 解決）、disk.img は既定名生成（No.5 解決）。build_road2.sh/既知 Dhrystone 手順とバイト等価。M-A プリアンブル必須 | yuios_makefile_design_v0_2.md |
| mk_post1.sh | **v1.0** | 2026-06-21 | Step 8-B。S2 混入行除去（#WORD_xxx 全自動抽出→1パス目アドレス直書き）を build_road2.sh Step2 からバイト等価移植（No.1 を Makefile 規則化） | yuios_makefile_design_v0_2.md §2.7 |

## 3. 関連文書

| 文書 | 版 | 用途 |
| --- | --- | --- |
| yuios_build_procedure | **v1.7** | ビルド手順書（対象ツール表が実運用上のバージョン参照点。§4.11 道2ビルド・§4.12 Makefile ビルド） |
| yuios_makefile_design | **v0.2** | Makefile/mk_post1.sh 設計書（Step 8-B・APPROVED） |
| hasm23_xref_yof_design | **v2.3** | 道2（hasm23 v1.04＋lnk23 v2.01）設計書 |
| emu23_v105_design | v1.0 | emu23 v1.05 改修設計書 |
| emu23_debug_manual | v1.1 | emu23 デバッグ・ユーザマニュアル（v1.05 対応） |
| toolchain23_design | v1.2 | ツールチェーン設計起点（各ツール v1.00 時点の設計。起点記録として保持） |

## 4. 運用ルール

- ツールを改修・更新したら、本台帳の §1 現行版と該当ツールの系譜表を更新する。
- ツール改修時は回帰チェック（Dhrystone）を実施（Force 改修時は対象外）。
- ツールのバナー／ソース VERSION 定義と本台帳の版数が一致することを定期確認する（記憶に頼らず grep で実体確認）。
- 現行版の更新時も、過去版の系譜記録は欠落させない。
