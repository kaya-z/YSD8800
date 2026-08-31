# YSD8800 / YUI OS ツールバージョン管理台帳

Version 1.13  /  2026-08-02

| 項目 | 内容 |
| --- | --- |
| 文書番号 | TOOL-VERSION-LEDGER-001 |
| 目的 | YSD8800 ツールチェーン各ツールの現行バージョンを一元管理する（kaizen 原則：ツール類はバージョンを常にリスト管理） |
| 対象 ISA | YSD8800 ISA2.3 |
| 作成日 | 2026-06-06 |
| 最終改版日 | 2026-08-02 |
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
| **v1.8** | **2026-06-27** | **emu23 v1.08→v1.09（インタラクティブモード -it 追加）成果を反映。** ①§1 現行ツール一覧の emu23 行を v1.08→**v1.09** に更新。②§2 emu23 系譜に v1.09 行を追加。③v1.09 実装内容: 新規 `-it` オプション（termios raw mode 化・ECHO/ICANON/ISIG 無効・キー入力を UART RX へ流し込み・エコーは YUI OS UART ドライバ責務・Ctrl+D(0x04) で終了）。診断ログ抑制（`-it` 時 quiet_mode 内部セット＝A方針）・終了は 0x04 検出に一本化し真EOF即終了は撤去（あ方針）。既存破壊変更は `ysd8001_tick()` 内の poll_rx 呼び出しを関数ポインタ経由化した 1 行のみで `-q`/`-i`/REPL は非回帰。④検証: yuios_road2.bin（道2・**56416 byte / md5 a1f1001f… 黄金リファレンス一致**）で `-q` 非回帰 PASS、`-it` で YUI OS 実起動し `ver`→`YUIOS V0.10.18`／`help`／`ps` 応答到達、Ctrl+D 終了を PTY で exit 0 実証、排他チェック PASS。⑤関連設計書: emu23_interactive_mode_design **v1.1→v1.2**（§2.4 診断ログ抑制・§3.2 0x04一本化・§5 実証結果・§8 教訓を追記）。| Claude |
| **v1.9** | **2026-06-28** | **scc23 v2.01→v2.02（peephole P3 追加）成果を反映＋文書ヘッダ版数の追従漏れ是正。** ①§1 現行ツール一覧の scc23 行を v2.01→**v2.02** に更新。②v2.02 実装内容: asm peephole に **P3**（可換加算の冗長MOV吸収：`ADD B,A` / `MOV A,B` → `ADD A,B`）を追加。ADD可換性 + dead proof（中間Bは隣接ホワイトリスト条件で再使用なしを担保）により結果A・最終フラグを保存。ガード=完全隣接のみ／直後にsource B出現で非置換／P2系の後段で評価。-O0/-O0-strict は非適用＝byte不変。③検証: --version=scc23 v2.02、絶対ゲート -O0 Dhrystone **826/48405/P:20 完全一致**（不変維持）、-O1 で **835 DPS / cycles 47885 / P:20**（v2.01 -O1 比 48055→47885）、V5実行回帰（fib F55/test_for 6/test_local A/test_for_call 3/Dhrystone P:20）が v2.01 -O1 と全結果一致、混入検査 poc vs v2.01=追加112行/削除0行（P3 2ブロックのみ）。④**文書ヘッダ是正**: 本台帳ヘッダ「Version」表記が v1.8 改版時に v1.7 のまま追従漏れしていた（改版履歴には v1.7/v1.8 行が存在）KY41 4点整合違反の残骸を、本 v1.9 改版で v1.9 へ是正（最終改版日も 2026-06-25→2026-06-28）。⑤関連設計書: scc23_v2_02_peephole_P3_design v1.1（実装済反映は次回設計書改版時に §9.2.5 へ注記）。過去版系譜は欠落させず保持。 | Claude |
| **v1.10** | **2026-07-03** | **scc23 v2.02→v2.03（peephole P1 追加）成果を反映。** ①§1 現行ツール一覧の scc23 行を v2.02→**v2.03** に更新。②v2.03 実装内容: asm peephole に **P1**（スタックラウンドトリップ除去）を追加＝第4パターン（P2a/P2b/P3 の後段で評価）。4命令固定窓 `SUBI SP,#2`/`STW A,[SP]`/`LDW B,[SP]`/`ADDI SP,#2` を `MOV B,A` 1命令へ畳込む。生成起源は「境界偶然マッチ」（異なるSIRノード境界の pop_b 後半 ADDI SP,#2 と別ノードの push_a 前半 SUBI SP,#2 が命令ストリーム上で偶然隣接）。安全性は起源非依存で、4命令ローカル正味効果が B=A（+デッドストア+SP収支ゼロ）＝MOV B,A（0x20・FLAGS不変）と外部観測等価。ガード G1（完全隣接）/G2（SUBI・ADDI同量）/G3（STW A・LDW B）/G4（[SP]オフセット無し）/**G5（窓直後がZ/Nを読む条件分岐 BEQ/BNE/BLT/BGE なら非置換＝フラグ意味論保護）**の全真時のみ置換。③検証専用 `--no-peep` フラグ追加（peephole_pass 全無効化・既定OFF・最適化レベル独立）。④検証(2026-07-03 全PASS): V1（-O0/-O0-strict で base(v2.02)と asm byte不変）／V2（-O1 dhry_timer.c で差分は MOV B,A×24追加・4命令窓×24削除のみ）／V2c（連続窓×2 両畳込み・SP収支不変）／V3=CONT-1（G5がP2/P3書換え後のストリーム位置r+4で正しく効く・単体T9実証）／**V4（-O1 Dhrystone実機 P:20不変・cycles 47885→47795〈−90〉・836 DPS）**／V5=CONT-2（fib/test_for/test_local/test_for_call が base と asm完全一致）／**絶対ゲート -O0-strict 826/48405/P:20・21846B 完全一致**／ガード単体検証 p1_g5_test_poc.c G1〜G5網羅 全12テストPASS。⑤base/p1 の obj は共に 20822B code・bin 21846B とサイズ同一に見えるが `cmp` で相違あり（P1反映確認・偽の一致排除済）。⑥KY41 4点整合済（ファイル名 scc23_v2_03.c・SCC_VERSION "2.03"・ヘッダ日付 2026-07-03・改版履歴）。⑦関連設計書: scc23_v2_03_peephole_P1_design v1.3（実装完了反映）／HANDOVER_PEEPHOLE_P1_IMPL_v1_0.md。過去版系譜は欠落させず保持。 | Claude |
| **v1.11** | **2026-07-18** | **emu23 v1.09→v1.10（V5 タイマー黄金リファレンス改修）の登録漏れを是正。** ①§1 現行ツール一覧の emu23 行を v1.09→**v1.10** に更新。②§2 emu23 系譜に v1.10 行を追加。③v1.10 実装内容（実体 emu23_v110.c ヘッダより）: タイマー(YSD8002)の再武装契機を「IRET命令フック」から「**TCR bit5 IRQ_ACK 書込**」へ変更。(1)timer_in_service 削除 (2)IRQ受理部の同フラグセット削除 (3)IRET命令内 YSD8002_iret() 呼出削除（v1.07 Step8-I 修正が丸ごと不要化）(4)TCR($FC90) write マスク 0x17→**0x37**・bit5=IRQ_ACK 新設で書込時 YSD8002_rearm() 自動クリア (5)YSD8002_iret()→**YSD8002_rearm()** 改名。★変更理由★: IRETフック方式は**FPGA実装不能**（MC6809はRTIを外部にブロードキャストせず iret_pulse_o 専用線が引けない）→ **kaizen原則73「エミュレータの実装都合を仕様と誤認するな」**。★互換性注意★: タイマー割込ハンドラは TCR に IRQ_ACK(bit5)=`$0023` を書く義務（書かないと発火後自己武装解除で二度と発火しない）。両ソース kernel_v12_7/8・startup_harness23_v15/16 は ACK 先行で契約充足済。④本改修は Step 8 V5 の S1 で実施済だったが tool_version_ledger への反映が漏れていた（V5昇格の整合確認〈2026-07-18〉で検出・是正）。⑤設計書 v5_design_memo・レビュー v5_design_review_reply_v1_0 承認済。過去版系譜は欠落させず保持。 | Claude |

| **v1.12** | **2026-07-18** | **emu23 v1.10→v1.11（EN是正工程・案B）を反映。** ①§1 現行ツール一覧の emu23 行を v1.10→**v1.11** に更新。②§2 emu23 系譜に v1.11 行を追加。③v1.11 実装内容（実体 emu23_v111.c ヘッダより）: タイマー(YSD8002)の**発火許可条件を OR→AND へ是正**（`(tcr&0x03)?1:0` → `((tcr&0x01)&&(tcr&0x02))?1:0`）。bit0(TIMER_EN) と bit1(IRQ_EN) の両方が 1 のときのみ発火＝**IRQ_EN=0 が割込マスクとして機能**（契約回復）。★目的★: 旧OR実装では IRQ_EN=0 でも TIMER_EN=1 で発火してしまい IRQ_EN が名前どおり機能しない契約違反状態だった。★FPGA-RTL 側も対称改修★: ysd8800_ysd8002 v0.2→**v0.3**（`fire_en = timer_en_r & irq_en_r`）。④検証: 負例 v6t_mask（TCR=$0001）→ **emu CNT=0 / RTL CNT=0**（is正の直接証明）、正例 v5t_ack（TCR=$0003）→ CNT=30（V5黄金一致）、**Dhrystone 826/48405/P:20 完全一致（二重不変を実証）**、V1/V2 全ベクタ回帰 ALL PASS（V2a20/V2c64/V2d75/V2e82・CPUコア無改修デグレゼロ）、MMU黄金 v111基準で決定性一致（md5=0b7c941e…）。⑤★残る「案A（TIMER_EN=0 でカウンタ歩進停止）」は将来課題として V6以降へ先送り**（ユーザー承認 2026-07-17/18）。⑥関連設計書: ysd8002_timer_design **v1.0→v1.2**（TCR AND是正・§11.1将来課題）／v5_design_memo **v0.4→v0.5**（§3.5.2 改訂）／v6_en_fix_design_memo v0.1。⑦KY41 4点整合済（emu23_v111.c・起動表示 \"emu23 v1.11 (2026-07-18)\"・ヘッダ日付・改版履歴）。過去版系譜は欠落させず保持。 | Claude |

| **v1.13** | **2026-08-02** | **scc23 v2.04→v2.05（Phase 1 / C-3 前方未定義 float 関数呼び出し値破壊阻止）を反映。** ①§1 現行ツール一覧の scc23 行を v2.03→**v2.05** に更新（v2.03 → v2.04 → v2.05 と2段階昇格。台帳 v1.12 までは v2.03 のまま v2.04 記載が漏れていたため併せて是正＝KY41）。②§2 に「scc23 バージョン系譜」を新設（従来 scc23 独立系譜表なし・§1 一行のみで管理していた欠落を是正）。③v2.04 実装内容（欠落是正・実体 scc23_v2_04.c ヘッダより）: char ロード幅不一致バグ修正。emit_expr() SIR_SYM スカラ変数参照の非グローバル分岐で is_char を算出しながら参照しておらず、ローカル/パラメータの char を LDW（2バイト）で読んでいた bug。store 側は STB（1バイト）→「1バイト書込/2バイト読出」の非対称。emu23 は mem[] ゼロ初期化で偶然通過、実 FPGA は PSRAM 電源投入時内容が不定で非決定的動作（CHAT119 FPGA V8-D Dhrystone RTL 完走調査で発見）。修正: char は LDB（1バイト・ゼロ拡張）で読み store と対称化。LDB は [imm16]/[X] の2形式のみで [X+off] 形式が無いため X を一時的にずらして読み直後に戻す（off==0 は LDB A,[X] 1命令、off!=0 は3命令）。④v2.05 実装内容: Phase 1 / C-3（前方未定義 float 関数呼び出しの値破壊阻止）。**バグ機序（2段構造）**: 1段目 parse_primary の call 型伝播で SC_FUNC 未登録の呼び出しを T_INT にフォールバック（int文脈では正当）／2段目 binop_promote の float 経路で wrap_i2f が T_INT ノードに SIR_I2F を挿入→emit で `LDW B,#8 / SHL A,B` が生成され既に Q8.8 の戻り値を 8bit 左シフトして値破壊。**修正（案D＋案C 併用）**: 案D=`is_undecl_call()` ヘルパを新設し binop_promote の float 経路直前で error 停止（ボトムアップ評価により未定義 SIR_CALL が float 演算に最初に触れる binop_promote で必ず捕捉・複合式でも漏れない・fail-safe）／案C=parse_primary の T_INT フォールバック分岐で warning 出力（プロトタイプ宣言追加を促す早期通知）。**不変**: プロトタイプ宣言済み関数呼び出し・int 文脈のみでの未定義関数呼び出しのコード生成は完全に v2.04 と同一。⑤検証: **V1**(PoC case1/case2 で値破壊阻止確認・case1 は v2.04 と byte-exact) **V2**(**Dhrystone -O0-strict 絶対ゲート 826/48405/P:20/21846B 完全一致**・生成 asm は v2.04 とバナー行のみ差分＝byte-exact) **V3**(Dhrystone -O1 生成 asm も v2.04 とバナー行のみ差分＝**cycles 47795 維持**) **V4**(既存 float テストはナレッジ未登録・case1 で代替確認済) **V5**(追加PoC case3〜case6 全PASS＝int 文脈のみ/右辺 float 文脈/プロトタイプあり/再帰呼び出し 全て期待通り) **dhry_all.c**（K&R版）追加検証: v2.04/v2.05 で error 内容 167件完全一致＝C-3 修正による回帰なし。K&R パーサ未対応は Phase 3 課題（プリプロセッサ移植と併せて対応）。⑥KY41 4点整合済（scc23_v2_05.c・SCC_VERSION "2.05"・SCC_DATE "2026-08-02"・ヘッダ改版履歴 v2.05 節新設）。⑦関連設計書: **scc23_v2_05_C3_forward_decl_design v0.3**（承認版・レビュー2回全項目クローズ済：v0.1レビュー C=1/M=1/N=1 → v0.2 で全反映 → v0.2レビュー確認書で全クローズ+CONF-1 反映を v0.3 で実施）／scc23_v2_04_char_load_fix_design v1.1（v2.04 起点として保持）。⑧ビルド手順書 yuios_build_procedure v1.11 の改版要否＝**不要**（v2.05 は使い方が v2.04 と同一・コマンドライン仕様不変）。過去版系譜は欠落させず保持。 | Claude |

| ツール | 現行版 | ソースファイル | 役割 | 直近の変更 |
| --- | --- | --- | --- | --- |
| Force | v1.5 | force_v1_5.c（メイン）＋ frontend/ir.c・lexer.c・parser.c・ir.h（無印）＋ backend/codegen.c **v1.5**（codegen_v1_5.c）＋ backend/codegen.h **v1.4相当（ファイル名codegen_v1_4.h、冒頭コメントは無印v1.0のまま）** ＋ targets/ysd8800.tgt（無印）・ysd8800.prim **v1.1** | Forth クロスコンパイラ | force_v1_5.c: VARIABLE/VALUE/DEFER のデータ部とgetterコード部を分離出力（v1.4）／_FMUL_A/B/R 再配置によるTCB破壊バグ修正（v1.5）。詳細は §2.8 参照 |
| scc23 | **v2.05** | scc23_v2_05.c | Small-C 派生 C コンパイラ | **v1.04（ポインタバグ P1〜P7 修正系列）→ v2.00（float Q8.8/定数畳み込み/最適化レベル -O0/-O0-strict/-O1）→ v2.01（peephole P2a/P2b を -O1 へ新設）→ v2.02（peephole P3 追加）→ v2.03（peephole P1 追加）→ v2.04（char ロード幅不一致修正：LDB [X+off] 未対応のため X 一時退避方式で対称化・CHAT119 FPGA V8-D 調査で発見）→ v2.05（Phase 1/C-3：前方未定義 float 関数呼び出しの値破壊阻止＝案D fail-safe error 化＋案C 早期警告。`is_undecl_call()` を新設し binop_promote の float 経路直前で判定、複合式でも漏れなくボトムアップで捕捉）。-O0/-O0-strict は byte不変、-O1 で Dhrystone cycles 47795・836 DPS・P:20** |
| hasm23 | **v1.04** | hasm23_v1_04.c | アセンブラ | **v1.03: (A).global 追加・(B)UNDEF複数参照／v1.04: 道2（YOFモード .org 配置アドレス尊重・has_org フラグ・.vector 遅延書き込み）** |
| disasm23 | v1.00 | disasm23.c | 逆アセンブラ | ISA2.3 初版 |
| lnk23 | **v2.01** | lnk23_v2_01.c | YOF リンカ | **v2.01: 道2（YOF load_addr+has_org 尊重の固定配置・--machine force・固定/自動混在エラー）** |
| **emu23** | **v1.11** | **emu23_v111.c** | エミュレータ（UART/Timer/SD/IRQ統合 + stack watermark計測 + FM-11方式16ページMMU〈--mmu〉 + インタラクティブモード〈-it〉 + TCR-ACK方式タイマー再武装 + **発火EN=AND〈EN是正/案B〉**） | **v1.11: [EN是正/案B]タイマー発火許可条件をOR→ANDへ是正（`(tcr&0x03)` → `(tcr&0x01)&&(tcr&0x02)`）。IRQ_EN(bit1)=0が割込マスクとして機能（契約回復）。FPGA-RTL側もysd8002 v0.3で対称AND化。負例v6t_mask（TCR=$01）→CNT=0で実証。Dhrystone826/48405/P:20不変。案A（TIMER_EN=0でカウンタ停止）はV6以降へ先送り。設計書ysd8002_timer_design v1.2/v5_design_memo v0.5。旧v1.10（TCR-ACK）は§2系譜に保持** |
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
| **v1.09** | **2026-06-27** | **Step 8: インタラクティブモード -it 追加。termios raw mode（ECHO/ICANON/ISIG 無効・VMIN=0非ブロッキング）でキー入力を 1 文字ずつ UART RX へ流し込み、YUI OS Shell のリアルタイム対話操作を実現。エコーは YUI OS UART ドライバ責務（emu23 非エコー）。終了は Ctrl+D(0x04) 検出に一本化（真EOF即終了は撤去＝あ方針）。診断ログは quiet_mode 内部セットで抑制（A方針）。atexit/SIGTERM/SIGHUP で raw mode 復帰保証。既存破壊変更は ysd8001_tick() 内 poll_rx 呼び出しの関数ポインタ化 1 行のみ・-q/-i/REPL 非回帰。検証: yuios_road2.bin 56416/md5 a1f1001f… 一致、-q 非回帰 PASS、-it で ver→YUIOS V0.10.18／help／ps 応答到達、Ctrl+D終了 PTY exit 0、排他チェック PASS。Dhrystone 実数値再測定は次回ビルド時（残課題・ビルド健全性は md5一致で確認済）** | emu23_interactive_mode_design_v1_2.md（実装完了反映版） |
| **v1.10** | **2026-07-13** | **[V5] 黄金リファレンス改修。タイマー(YSD8002)再武装契機を「IRET命令フック」→「TCR bit5 IRQ_ACK書込」へ変更。(1)timer_in_service削除 (2)IRQ受理部の同フラグセット削除 (3)IRET命令内YSD8002_iret()呼出削除〈v1.07 Step8-I修正が丸ごと不要化〉(4)TCR($FC90)writeマスク0x17→0x37・bit5=IRQ_ACK新設で書込時YSD8002_rearm()自動クリア (5)YSD8002_iret()→YSD8002_rearm()改名。理由=IRETフックはFPGA実装不能〈MC6809はRTIを外部broadcastせず iret_pulse_o不可〉→kaizen原則73。★互換性★: タイマー割込ハンドラはTCRにIRQ_ACK(bit5)=$0023書込義務〈書かないと発火後自己武装解除で二度と発火せず〉。影響: kernel_v12_7.asm IRQ0_HANDLER/startup_harness23_v15.asm _timer_handler〈両者ACK先行で充足済〉** | v5_design_memo_v0_2.md / v5_design_review_reply_v1_0.docx（承認済） |
| **v1.11** | **2026-07-18** | **[EN是正/案B] タイマー(YSD8002)発火許可条件を OR→AND へ是正。`irq_enabled = (tcr&0x03)?1:0`〈OR〉 → `((tcr&0x01)&&(tcr&0x02))?1:0`〈AND〉。bit0(TIMER_EN)とbit1(IRQ_EN)の両方が1のときのみ発火＝IRQ_EN=0が割込マスクとして機能〈契約回復〉。旧OR実装はIRQ_EN=0でもTIMER_EN=1で発火する契約違反状態だった。★FPGA-RTL対称改修★: ysd8800_ysd8002 v0.2→v0.3〈`fire_en=timer_en_r & irq_en_r`〉。検証: 負例v6t_mask(TCR=$01)→emu/RTL共CNT=0〈是正の直接証明〉、正例v5t_ack(TCR=$03)→CNT=30、Dhrystone826/48405/P:20不変、V1/V2全ベクタ(20/64/75/82)ALL PASS〈CPUコア無改修デグレゼロ〉、MMU黄金v111決定性一致。★案A(TIMER_EN=0でカウンタ停止)はV6以降へ先送り** | ysd8002_timer_design_v1_2.docx / v5_design_memo_v0_5.md / v6_en_fix_design_memo_v0_1.md（承認済） |

## 2.4 scc23 バージョン系譜（新設）

**新設経緯**: 台帳 v1.12 まで scc23 は §1 現行ツール一覧の一行のみで管理されており、他ツール（emu23/hasm23/lnk23）と同等の独立系譜表が存在しなかった。台帳 v1.13 改版時（scc23 v2.05 反映）に、過去版（v1.00〜v2.04）の記録漏れも併せて系譜表として一括整備する（KY41・過去版系譜は欠落させず保持）。

| 版 | 日付 | 主な変更 | 設計書 |
| --- | --- | --- | --- |
| v1.00 | 2026-04-16 | ISA2.3 初版（scc22 v3.05 ベース。asm("...") インラインアセンブラ構文追加。SYSCALL 1バイト化対応） | toolchain23_design_v1_2.docx |
| v1.01 | — | [P1-P7] ポインタバグ修正（ポインタ+整数のスケーリング、ポインタ同士減算のC標準準拠、SIR_POST/PRE_INC/DEC ポインタスケーリング、文字列リテラル2バイトアライメント、`*ptr` 逆参照の型推論、ptr-ptr減算の SHR→SAR、SIR_ASGN_OP のポインタ算術） | scc23_v1_04.c 冒頭コメント |
| v1.02 | — | [A] ベースアドレスのコマンドライン引数化（--code-org/--data-org/--runtime-org）／[B] 演算子系ヘルパのオンデマンド出力（_cc_mul/_cc_div の実使用時のみ出力） | scc23_v1_04.c 冒頭コメント（v1.03 で遡及補完） |
| v1.03 | — | [WK1] ランタイムワーク変数を $FBD0系 → $C7E8系（Cプロセス区画内DATA末尾）へ移設。旧位置が tid7 データスタック領域を破壊するサイレント・コラプション修正／[V1.03-FIX] 冒頭コメント版数是正+v1.02履歴補完（KY41 4点整合是正） | scc23_runtime_wk_relocation_design_v1_1.docx |
| v1.04 | 2026-06-17 | [WK2] memmap v2.4（案D-ε）に伴い Cプロセス区画を $C000-$C7FF → $D400-$DBFF へ +$1400 一律移設。旧ロード先 $C000 が Forth 辞書実コード（実測終端 $C15F）と物理衝突する問題を修正 | memmap v2.4 §15.6/§15.7 |
| v2.00 | 2026-06-22 | [S1-S6] float(Q8.8) サポート・定数畳み込み・最適化レベル制御 -O0/-O0-strict/-O1 を追加。T_FLOAT/T_BOOL/T_UINT予約、SIR_FMUL/FDIV/I2F/F2I、Q8.8 リテラル、binop_promote/wrap_i2f、fold_binop、_fmul/_fdiv ランタイム | scc23_v2_00_design_v2_2.docx |
| v2.01 | 2026-06-26 | asm peephole を -O1 へ新設（P2a 完全同一連続MOV削除・P2b dead store除去）。命令ストリームバッファ基盤（方式B）。-O0/-O0-strict は非適用＝byte不変。dead store 63命令削除で Dhrystone cycles 48405→48055 | scc23_v2_00_design_v2_6.docx §9.2 |
| v2.02 | 2026-06-28 | peephole P3 追加（`ADD B,A`/`MOV A,B` → `ADD A,B` 可換吸収）。-O1 で cycles 48055→47885 | scc23_v2_02_peephole_P3_design_v1_1.md |
| v2.03 | 2026-07-03 | peephole P1 追加（スタックラウンドトリップ除去 4命令窓 `SUBI SP,#2`/`STW A,[SP]`/`LDW B,[SP]`/`ADDI SP,#2` → `MOV B,A`）。G5=窓直後 Z/N 分岐で非置換のフラグ意味論保護。--no-peep 検証フラグ追加。-O1 で cycles 47885→47795 | scc23_v2_03_peephole_P1_design_v1_3.md |
| **v2.04** | **2026-07-26** | **char ロード幅不一致バグ修正**。emit_expr() SIR_SYM スカラ変数参照の非グローバル分岐で is_char を算出しながら未参照→ローカル/パラメータ char を LDW（2バイト）で読んでいた。store 側 STB（1バイト）と非対称。emu23 は mem[] ゼロ初期化で偶然通過、実 FPGA は PSRAM 初期値不定で非決定的（CHAT119 FPGA V8-D Dhrystone RTL 完走調査で発見）。修正: char は LDB（1バイト・ゼロ拡張）で読み対称化。LDB は [X+off] 形式無しのため X 一時退避方式（off==0 は LDB A,[X] 1命令、off!=0 は3命令）。 | scc23_v2_04_char_load_fix_design_v1_1.md |
| **v2.05** | **2026-08-02** | **Phase 1 / C-3：前方未定義 float 関数呼び出しの値破壊阻止**。**バグ機序（2段）**: 1段目 parse_primary の call 型伝播で SC_FUNC 未登録の呼び出しを T_INT にフォールバック／2段目 binop_promote の float 経路で wrap_i2f が T_INT ノードに SIR_I2F を挿入→emit で `LDW B,#8 / SHL A,B` が生成され既に Q8.8 の戻り値を 8bit 左シフトして値破壊。**修正（案D＋案C 併用）**: 案D=`is_undecl_call()` ヘルパを新設し binop_promote の float 経路直前で error 停止（ボトムアップ評価で複合式でも漏れなく捕捉・fail-safe）／案C=parse_primary の T_INT フォールバック分岐で warning 出力（早期通知）。**不変**: プロトタイプ宣言済み関数・int 文脈のみでの未定義関数呼び出しのコード生成は v2.04 と同一。**検証**: V1(PoC値破壊阻止確認)/V2(Dhrystone -O0-strict 絶対ゲート 826/48405/P:20/21846B 完全一致・byte-exact)/V3(-O1 cycles 47795 維持)/V4(既存 float テストはナレッジ未登録・case1 で代替確認済)/V5(追加PoC case3〜case6 全PASS)/dhry_all.c 追加検証(v2.04/v2.05 で error 内容 167件完全一致＝C-3 修正による回帰なし・K&R パーサ未対応は Phase 3 課題)。 | scc23_v2_05_C3_forward_decl_design_v0_3.md（承認版・v0.1レビュー C=1/M=1/N=1 → v0.2 で全反映 → v0.2レビュー確認書で全クローズ+CONF-1 → v0.3 反映） |

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
| scc23_v2_03_peephole_P1_design | **v1.3** | scc23 v2.03 peephole P1（スタックラウンドトリップ除去）実装設計書（境界偶然マッチ・ガードG1〜G5・emu23実行等価実証） |
| scc23_v2_00_design | **v2.9** | scc23 v2.00系 peephole 正本設計書（§9.2 に P2a/P2b/P3/P1 を集約。§9.2.12=P1） |
| scc23_v2_04_char_load_fix_design | **v1.1** | scc23 v2.04 char ロード幅不一致修正設計書（LDB [X+off] 未対応のため X 一時退避方式で対称化・CHAT119 FPGA V8-D 調査で発見） |
| scc23_v2_05_C3_forward_decl_design | **v0.3** | scc23 v2.05 Phase 1/C-3 前方未定義 float 関数呼び出し値破壊阻止設計書（案D fail-safe error 化＋案C 早期警告。承認版・レビュー2回全項目クローズ済） |
| scc23_phase_roadmap | **v1.0** | scc23 v2.x 改良フェーズ工程表（Phase 0=P1 peephole 完了／Phase 1=検証負債対応〈C-1/C-2/C-3〉／Phase 2=型システム統合〈T_BOOL+T_UINT〉／Phase 3=OS拡張〈プリプロセッサ移植・static変数〉／Phase 4=関数ポインタ／Phase 5=残る最適化／Phase 6=Q16.16） |

## 4. 運用ルール

- ツールを改修・更新したら、本台帳の §1 現行版と該当ツールの系譜表を更新する。
- ツール改修時は回帰チェック（Dhrystone）を実施（Force 改修時は対象外）。
- ツールのバナー／ソース VERSION 定義と本台帳の版数が一致することを定期確認する（記憶に頼らず grep で実体確認）。
- 現行版の更新時も、過去版の系譜記録は欠落させない。
