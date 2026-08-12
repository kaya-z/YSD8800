# YSD8800 / YUI OS ツールバージョン管理台帳

Version 1.7  /  2026-06-26

| 項目 | 内容 |
| --- | --- |
| 文書番号 | TOOL-VERSION-LEDGER-001 |
| 目的 | YSD8800 ツールチェーン各ツールの現行バージョンを一元管理する（kaizen 原則：ツール類はバージョンを常にリスト管理） |
| 対象 ISA | YSD8800 ISA2.3 |
| 作成日 | 2026-06-06 |
| 最終改版日 | 2026-06-25 |
| ステータス | 確定 |

## 改版履歴

| 版数 | 日付 | 内容 | 担当 |
| --- | --- | --- | --- |
| v1.0 | 2026-06-06 | 初版作成。現行ツール一覧を整備。emu23 を v1.04→**v1.05**（stack watermark 計測統合）に更新したことを契機に、バージョン管理台帳として独立文書化。 | Claude |
| **v1.1** | **2026-06-21** | **v1.0 以降（Step 8-Y/Step 8-F）のツール版数変更を一括反映。** ①scc23 v1.00→**v1.04**（ポインタバグ修正 P1〜P7 等。台帳 v1.0 では旧 v1.00 のまま放置されていたため是正）。②hasm23 v1.02→**v1.03**（(A).global 追加・(B)UNDEF複数参照）→**v1.04**（道2: YOFモード .org 配置尊重・has_org・.vector 遅延書き込み）。③lnk23 v2.00→**v2.01**（道2: load_addr+has_org 尊重の固定配置・--machine force）。④emu23 v1.05→**v1.06**（F-001: `bd` コマンド到達不能バグ修正）。⑤§2 に emu23 v1.06 系譜追記。⑥§3 関連文書を最新版（build_procedure v1.6 / hasm23_xref_yof_design v2.3）に更新。過去版系譜は欠落させず保持。 | Claude |
| **v1.2** | **2026-06-21** | **Step 8-B（ビルドシステム改善）成果物を登録。** ①§1 現行ツール一覧に **Makefile v1.0**・**mk_post1.sh v1.0** をビルドシステム成果物として追加。②§2.7 として「ビルドシステム系譜」を新設。③§3 関連文書の build_procedure を **v1.6→v1.7**（§4.12 Makefile 節新設）に更新。④Makefile/mk_post1.sh は build_road2.sh および既知 Dhrystone 手順の**バイト等価**移植であり、yuios=56416 完全一致・Dhrystone 826/48405/P:20 一致を MK-1〜MK-6 で確認済み。過去版系譜は欠落させず保持。 | Claude |
| **v1.3** | **2026-06-21** | **Force 関連ファイル一式の版数欠落を是正（ユーザ指摘対応）。** ①§1 現行ツール一覧の Force 行を、force_v1_5.c 単体表記から **構成ファイル一覧**（force_v1_5.c / codegen v1.5・ir.c・lexer.c・parser.c・ir.h・ysd8800.tgt・ysd8800.prim v1.1）に拡充。②§2.8 として「Force バージョン系譜」を新設し、v1.0〜v1.5 の変更履歴を実ファイル（force_v1_5.c, codegen_v1_5.c, ysd8800.prim）の記載と照合した上で整理。③ir.c・lexer.c・parser.c・ir.h は実ファイル上にバージョン表記が無いことを確認し、台帳上は「無印（要バージョン表記追加・課題として記録）」と明記。④ysd8800.tgt 内の `ASSEMBLER hasm22` 表記が ISA2.3 現行（hasm23）と不一致である点を §2.8 注記として記録（実装変更ではなく台帳上の指摘事項のみ。対応要否は別途確認）。過去版系譜は欠落させず保持。 | Claude |
| **v1.4** | **2026-06-21** | **codegen.h の版数欠落を是正（ユーザ再指摘対応）。** ①実ファイル確認の結果、`codegen.h` は **ファイル名が `codegen_v1_4.h`** として存在することを確認。しかし v1.3 改版時の §2.8 表は codegen.c（実装側）のみを追跡し、**codegen.h（ヘッダ側）の記載を欠落**させていたため是正。②実ファイル精査の結果、`codegen_v1_4.h` 冒頭コメントは「v1.0」表記のままだが、構造体 `codegen_t` 内部には v1.4 相当のコメント（data_section/code_section 分離。force.c/codegen.c v1.4 の変更に対応）が記載されており、**ファイル名・冒頭コメント・実装内容の三者が不一致**であることを確認・記録。③codegen.c v1.5 の `_FMUL_A/B/R` 再配置は生成アセンブラへのリテラル文字列出力であり、`codegen.h` の構造体・API定義（`target_t`/`prim_table_t`/`codegen_t`/関数プロトタイプ）には影響しないことをソース突合せで確認。よって codegen.h は v1.5 時点でも実体としては v1.4 相当のまま変化なしと判断。④§1 Force 行・§2.8 系譜表に codegen.h の行を追加。⑤所見・課題に「codegen.h 冒頭コメントの v1.0 表記が実体（v1.4相当）と不一致」を追加。過去版系譜は欠落させず保持。 | Claude |
| **v1.5** | **2026-06-22** | **Step 8-I（IRQ優先制御修正）成果を反映。** ①emu23 **v1.06→v1.07**（IRET命令が全IRQで無条件にYSD8002_iret()を呼ぶ設計書§5.3違反を是正。timer_in_serviceフラグでタイマーIRQ復帰時のみ再設定。タイマーとIRQ1衝突時のタイマーIRQ大量欠落を解消）。②§1 現行ツール一覧の emu23 行を v1.07 に更新。③§2 emu23 系譜に v1.07 行を追加。④§3 関連文書に emu23_device_design **v1.2→v1.3**（§3.4/§3.5 新設）を反映。⑤検証: タイマーIRQ欠落テスト v1.06=1→v1.07=983（理論値一致）、絶対ゲート yuios 56416・Dhrystone 826/48405/P:20 一致、v1.06/v1.07 同一バイナリ出力一致で回帰確認。過去版系譜は欠落させず保持。 | Claude |
| **v1.7** | **2026-06-26** | **scc23 v2.00→v2.01（peephole最適化 O1繰り上げ）成果を反映。** ①§1 現行ツール一覧の scc23 行を v1.04→**v2.01** に更新（v2.00=float Q8.8/定数畳み込み/最適化レベル、v2.01=asm peephole を -O1 へ新設）。台帳 v1.6 までは scc23 v1.04 のまま v2.00 記載が漏れていたため併せて是正。②v2.01 実装内容: 命令ストリームバッファ基盤（方式B・関数生成区間のみ emit をバッファ蓄積→関数クローズ時 -O1 で peephole 走査→flush）＋ **P2a**（完全同一連続MOV削除・MOVフラグ不変ゆえ無条件安全）＋ **P2b**（dead store除去・方針Y超保守ホワイトリスト・基本ブロック境界/フラグ意味論ガード付）。③検証: 絶対ゲート -O0-strict Dhrystone **826/48405/P:20 完全一致**（不変維持）、-O0/-O0-strict 命令列 base(v2.00)と byte不変（versionコメントのみ差）、-O1 で dead store 63命令削除（MOV A,B 132→69）・**cycles 48405→48055(-350)・826→832/sec・P:20不変**、float/代数簡約回帰（_fmul/_fdiv/I2F/F2I 命令列不変・emu23実行 全結果一致）。④設計書 scc23_v2_00_design §9.2/§9.2.9 の計画を実装済へ反映（設計書改版は別途）。⑤既知メモ: Dhrystone最終bin MD5 はリンク手順差で HANDOVER記載値と異なるがサイズ21846・実行値一致＝機能等価（要精査）。過去版系譜は欠落させず保持。 | Claude |

## 1. 現行ツールバージョン一覧（2026-06-21 時点）

| ツール | 現行版 | ソースファイル | 役割 | 直近の変更 |
| --- | --- | --- | --- | --- |
| Force | v1.5 | force_v1_5.c（メイン）＋ frontend/ir.c・lexer.c・parser.c・ir.h（無印）＋ backend/codegen.c **v1.5**（codegen_v1_5.c）＋ backend/codegen.h **v1.4相当（ファイル名codegen_v1_4.h、冒頭コメントは無印v1.0のまま）** ＋ targets/ysd8800.tgt（無印）・ysd8800.prim **v1.1** | Forth クロスコンパイラ | force_v1_5.c: VARIABLE/VALUE/DEFER のデータ部とgetterコード部を分離出力（v1.4）／_FMUL_A/B/R 再配置によるTCB破壊バグ修正（v1.5）。詳細は §2.8 参照 |
| scc23 | **v2.01** | scc23_v2_01.c | Small-C 派生 C コンパイラ | **v1.04（ポインタバグ P1〜P7 修正系列）→ v2.00（float Q8.8/定数畳み込み/最適化レベル -O0/-O0-strict/-O1）→ v2.01（asm peephole を -O1 へ新設: P2a 完全同一連続MOV削除・P2b dead store除去。命令ストリームバッファ基盤。-O0/-O0-strict は byte不変、-O1 で Dhrystone cycles 48405→48055）** |
| hasm23 | **v1.04** | hasm23_v1_04.c | アセンブラ | **v1.03: (A).global 追加・(B)UNDEF複数参照／v1.04: 道2（YOFモード .org 配置アドレス尊重・has_org フラグ・.vector 遅延書き込み）** |
| disasm23 | v1.00 | disasm23.c | 逆アセンブラ | ISA2.3 初版 |
| lnk23 | **v2.01** | lnk23_v2_01.c | YOF リンカ | **v2.01: 道2（YOF load_addr+has_org 尊重の固定配置・--machine force・固定/自動混在エラー）** |
| **emu23** | **v1.08** | **emu23_v108.c** | エミュレータ（UART/Timer/SD/IRQ統合 + stack watermark計測 + **FM-11方式16ページMMU〈--mmu〉**） | **v1.08: Step 8 V(-1) MMU復活移植（emu22 v1.10→v1.21で脱落した mmu_translate/phys_mem/PTR[16]@\$FF00/MCR@\$FF10 を復活。--mmu 有効化、無効時は v1.07 と byte-exact 非干渉。命令フェッチ26箇所 fetch8 化）。検証: G1〜G4・非干渉・G2（yuios 56416 一致）全PASS、Dhrystone 826/48405/P:20 一致** |
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
| **v1.07** | **2026-06-22** | **Step 8-I: IRET命令(case 0x04)が全IRQで無条件にYSD8002_iret()を呼ぶ設計書(§5.3)違反を是正。timer_in_serviceフラグ導入によりタイマーIRQ(IRQ0)復帰時のみ再設定。タイマーとIRQ1高頻度衝突時のタイマーIRQ大量欠落を解消（欠落テスト v1.06=1→v1.07=983）。回帰: yuios 56416・Dhrystone 826/48405/P:20 一致** | emu23_device_design_v1_3.docx §3.4 / step8i_irqfix_design_v0_2.md |
| **v1.08** | **2026-06-25** | **Step 8 V(-1): emu22 v1.10→v1.21 改版で脱落した FM-11方式16ページMMU を復活移植（emu22-1_10.c より）。mmu_translate/mmu_reset/phys_mem/PTR[16]@\$FF00/MCR@\$FF10、アクセス層 rd8/wr8/rd16/wr16/fetch16 の末尾フォールバックを変換経由化、命令フェッチ26箇所を fetch8 化。--mmu で有効化、無効時は恒等写像で v1.07 と byte-exact 非干渉。MMUデバッガコマンド mmu/physmem 移植。検証: G1/G3（Dhrystone 826/48405/P:20 一致）/G4（test_mmu1〜4_poc 全PASS）/非干渉（fib_verify_combined MD5一致）/G2（道2フルビルド yuios=56416 一致・配置 forth@\$5100/kernel@\$0000/reloc=2）全PASS** | emu23_v108_mmu_port_design（実装完了反映版）/ HANDOVER_CHAT67.md |

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

## 2.8 Force バージョン系譜（メインドライバ＋構成ファイル）

Force は単一ファイルではなく、メインドライバ（force.c）＋フロントエンド（ir/lexer/parser）＋バックエンド（codegen）＋ターゲット設定（.tgt/.prim）の複合構成。**従来の台帳は force_v1_5.c の版数のみを記載しており、構成ファイル側の版数が欠落していたため、本節で実ファイルの記載内容を確認の上、一括整理する。**

| ファイル | 版 | 日付 | 主な変更 | 出典 |
| --- | --- | --- | --- | --- |
| force.c（メインドライバ） | v1.0 | — | ベースライン（`-v` オプション・使用法・ビルド手順を含む） | force_v1_5.c 冒頭コメント |
| force.c | v1.2 | — | ベースライン表記（詳細差分の記録は確認できず） | force_v1_5.c 冒頭コメント |
| force.c | v1.4 | 2026-05-23 | VARIABLE/VALUE/DEFER のデータ部とコード部を分離出力。hasm23 .org 後退による getter コード上書きバグを回避 | force_v1_5.c 冒頭コメント |
| **force.c** | **v1.5** | **2026-05-24** | **_FMUL_A/B/R を $4232-$4236 から $47B0-$47B4 へ移動。TCB プール拡張（memmap v1.3: 16タスク化）と _FMUL ハードコードが衝突し tid=7 の TCB を破壊する重大バグを修正** | force_v1_5.c 冒頭コメント |
| backend/codegen.c | v1.0 | — | 初版 | codegen_v1_5.c 冒頭コメント |
| backend/codegen.c | v1.3 | — | ISA2.3 v2.2.1 メモリマップ対応 | codegen_v1_5.c 冒頭コメント |
| backend/codegen.c | v1.4 | 2026-05-23 | VARIABLE/VALUE/DEFER データ部をコード部から分離。出力先を cg->code_section に変更 | codegen_v1_5.c 冒頭コメント |
| **backend/codegen.c** | **v1.5** | **2026-05-24** | **_FMUL_A/B/R 再配置（force.c v1.5 と同時改版）** | codegen_v1_5.c 冒頭コメント |
| backend/codegen.h | v1.0（冒頭コメント表記） | — | ファイル名は **codegen_v1_4.h**。冒頭コメントは「Force Forth Cross Compiler v1.0」のまま未更新 | codegen_v1_4.h 冒頭コメント（実体） |
| **backend/codegen.h** | **v1.4相当（実装内容）** | **2026-05-23頃** | **構造体 `codegen_t` 内に v1.4 対応コメント（data_section/code_section 分離バッファの追加）が記載されており、内容としては v1.4 時点の codegen.c と対応。codegen.c v1.5（_FMUL再配置）はリテラル文字列出力のみで構造体・API（target_t/prim_table_t/codegen_t/関数プロトタイプ）に変更なしのため、.h は v1.5 化されず v1.4 相当のまま** | codegen_v1_4.h 構造体コメント／codegen_v1_5.c との突合せ確認 |
| frontend/ir.c | 無印 | — | バージョン表記なし（**課題**：force.c/codegen.c に追従した版数表記の追加が必要） | ir.c 実体確認 |
| frontend/ir.h | 無印 | — | 同上 | ir.h 実体確認 |
| frontend/lexer.c | 無印 | — | 同上 | lexer.c 実体確認 |
| frontend/parser.c | 無印 | — | 同上 | parser.c 実体確認 |
| targets/ysd8800.tgt | 無印 | — | ヘッダに「Force Forth Cross Compiler v1.0」「YSD8800 ISA2.2 ターゲット設定」と記載。**注記：`ASSEMBLER hasm22` 表記が残存しており ISA2.3 現行（hasm23）と不一致。台帳上の指摘事項として記録（対応要否は別途確認）** | ysd8800.tgt 実体確認 |
| targets/ysd8800.prim | v1.0 | — | ベースライン（ISA2.2時代からISA2.3へ移行・バージョン無表記時代の名残） | ysd8800.prim 冒頭コメント |
| targets/ysd8800.prim | **v1.1** | **2026-05-30** | **PRIM PLUS-STORE (+!) のバグ修正。旧版は LDW B,[A]; ADD B,B で val を無視し mem[addr] を2倍化していた。CFETCH の X 退避イディオムを応用し mem[addr]=mem[addr]+val へ修正** | ysd8800.prim 冒頭コメント |

**所見・課題（本節新設に伴う指摘事項）：**
1. frontend/ir.c・ir.h・lexer.c・parser.c は実ファイル上にバージョン表記が無い。force.c/codegen.c は改版時にヘッダコメントへバージョンを明記する運用が徹底されているのに対し、フロントエンド側は徹底されていない。次回フロントエンド改修時にバージョン表記の追加を推奨する。
2. ysd8800.tgt の `ASSEMBLER hasm22` 表記は ISA2.2 時代の記述が残存したものと推定される。実害（Force の動作）は無いと考えられるが、設定ファイルの記述としては現行 ISA2.3／hasm23 と不整合であり、別途修正の要否を確認されたい。
3. **codegen.h はファイル名（codegen_v1_4.h）・冒頭コメント（v1.0表記）・実装内容（v1.4相当の構造体コメントを含む）の三者が不一致。codegen.c の改版（v1.0→v1.5）に対し、codegen.h 側のバージョン更新ルールが徹底されていなかったことが原因と考えられる。次回 codegen.c/.h を同時改修する際は、両ファイルの冒頭コメント表記・ファイル名・実体を必ず一致させること（KY41 の4点整合の考え方を codegen.h にも適用）。**
4. 上記はいずれも本台帳改版の過程で発見した事実の記録であり、本指示の範囲では実装修正は行っていない（記録のみ）。

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
