/* scc23_v2_03.c - Small C Compiler for YSD8800 ISA2.3
 * Version: 2.03 (2026-07-03)
 *
 * v2.03変更点（設計書 scc23_v2_03_peephole_P1_design_v1_3.md §2/§3
 *               ・HANDOVER_PEEPHOLE_P1_IMPL_v1_0.md ・ベース=scc23_v2_02.c）:
 *   asm peephole 最適化に P1（スタックラウンドトリップ除去）を追加し -O1 へ組み込み
 *   （P2a/P2b/P3 に続く第4パターン。既存P3の後段で評価）。
 *   [P1] 4命令固定窓を1命令へ畳込む:
 *        SUBI SP,#2 / STW A,[SP] / LDW B,[SP] / ADDI SP,#2  →  MOV  B, A
 *        生成起源は「境界偶然マッチ」（異なるSIRノード境界の pop_b 後半 ADDI SP,#2 と
 *        別ノードの push_a 前半 SUBI SP,#2 が命令ストリーム上で偶然隣接して窓を成す）。
 *        安全性は起源非依存: 4命令ローカル正味効果が B=A（+デッドストア+SP収支ゼロ）＝
 *        MOV B,A（0x20・FLAGS不変）と外部観測等価（設計書§1.3/§4）。
 *        ガード G1〜G5（設計書§2・全真時のみ置換）:
 *          G1: 4命令が完全隣接（g_insbuf連続4要素・p1_is_line完全一致で担保）。
 *          G2: 行1=SUBI SP,#2 / 行4=ADDI SP,#2（同量対応）。
 *          G3: 行2=STW A,[SP] / 行3=LDW B,[SP]。
 *          G4: [SP]オフセット無し（完全一致比較が[SP+imm]を別綴りとして排除）。
 *          G5【最重要・フラグ意味論保護】: 窓直後 g_insbuf[r+4] がZ/Nを読む条件分岐
 *              (BEQ/BNE/BLT/BGE)なら非置換。元列末尾 ADDI SP,#2 はZ/Nを更新するが
 *              MOV B,A はFLAGS不変のため。JMP/JSR/RET は無条件でZ/Nを読まず置換可。
 *        peepholeは -O1 のみ作動。-O0/-O0-strict は非適用＝asm byte不変。
 *   [検証専用] --no-peep フラグを追加。peephole_pass() を丸ごと無効化（既定OFF・
 *              最適化レベルと独立）。peephole ON/OFF差分の観測・回帰切り分け用。
 *
 *   【検証結果(2026-07-03・全PASS)】
 *     - V1: -O0/-O0-strict で base(v2.02)と asm 完全一致（byte不変）。
 *     - V2: -O1 dhry_timer.c で差分は MOV B,A×24追加・4命令窓×24削除のみ（他不変）。
 *     - V2c: 連続窓×2→両方畳込み・SP収支不変（単体ハーネスT7）。
 *     - V3(CONT-1): G5がP2/P3書換え後のストリーム位置r+4に対し正しく効く（T9実証）。
 *     - V4: -O1 Dhrystone実機 P:20不変・cycles 47885→47795（−90）。
 *     - V5(CONT-2): fib/test_for/test_local/test_for_call が base と asm完全一致。
 *     - 絶対ゲート: -O0-strict 826/48405/P:20・21846B 完全一致（不変維持）。
 *     - ガード単体検証(p1_g5_test_poc.c): G1〜G5網羅 全12テストPASS。
 *
 *   改版履歴:
 *     v2.03 2026-07-03 peephole P1（スタックラウンドトリップ除去 4命令窓→MOV B,A）を
 *                      -O1へ追加。--no-peep 検証フラグ追加。KY41 4点整合済。
 *
 * --- 以下、v2.02の変更点（保持）---
 *
 * v2.02変更点（設計書 scc23_v2_02_peephole_P3_design_v1_1.md §2/HANDOVER_PEEPHOLE_P3_v1_0.md
 *               ・ベース=scc23_v2_01.c）:
 *   asm peephole 最適化に P3 を追加し -O1 へ組み込み（P2a/P2b に続く第3パターン）。
 *   [P3] 可換加算の冗長MOV吸収（ADD B,A / MOV A,B → ADD A,B）。
 *        ADDは可換(A+B==B+A)。連続2命令が「ADD B,A」（B←B+A、A保存）の直後に
 *        「MOV A,B」（A←B、結果をAへ転記）である場合、両者を「ADD A,B」（A←A+B）
 *        1命令へ畳み込む。結果Aの値・最終フラグ(Z/N/C/V)は ADD A,B が等価に設定するため
 *        意味論を保存（可換性 + dead proof: 中間のBはMOV A,B後に当該経路で再使用されない
 *        ことをホワイトリスト隣接条件で担保）。
 *        ガード:(i)完全隣接のみ(ラベル/他命令が挟まれば非置換＝基本ブロック境界 OBS-1)
 *              (ii)2命令の直後でBが読まれる場合（後続にsource Bが出現）は非置換
 *              (iii)P2a/P2b と同一の insbuf 走査内で順序適用（P3はP2系の後段で評価）。
 *        peepholeは -O1 のみ作動。-O0/-O0-strict は非適用＝asm byte不変。
 *
 *   【検証結果(2026-06-28・再現済)】
 *     - --version: scc23 v2.02 表示。
 *     - 絶対ゲート: -O0 Dhrystone 826/48405/P:20 完全一致（不変維持）。
 *     - -O1: Dhrystone 835 DPS / cycles 47885 / P:20（v2.01 -O1 比 cycles 48055→47885）。
 *     - V5実行回帰: fib(F55)/test_for(6)/test_local(A)/test_for_call(3)/Dhrystone(P:20)が
 *                   v2.01 -O1 と全結果一致。
 *     - 混入検査: poc vs v2.01 = 追加112行/削除0行（P3 2ブロックのみ・他改変なし）。
 *
 *   改版履歴:
 *     v2.02 2026-06-28 peephole P3（ADD B,A / MOV A,B → ADD A,B 可換吸収）を-O1へ追加。
 *
 * --- 以下、v2.01の変更点（保持）---
 *
 * (v2.01) scc23_v2_01.c - Small C Compiler for YSD8800 ISA2.3
 * (v2.01) Version: 2.01 (2026-06-26)
 *
 * v2.01変更点（設計書 scc23_v2_00_design_v2_6.docx §9.2/§9.2.9・ベース=scc23_v2_00.c）:
 *   asmレベル peephole 最適化を新設し -O1 に組み込み（GCC等の慣行に整合）。
 *   実装方式は「命令ストリームバッファ化」（§9.2.4・方式B：関数生成区間のみ
 *   emit/emit_labelをバッファ蓄積→関数クローズ時に-O1ならpeephole走査→flush。
 *   data_section等の関数外出力はバッファOFFで従来通り即時＝byte不変を構造的に保証）。
 *   [PH-基盤] g_insbuf[]/insbuf_put/insbuf_flush/peephole_pass を新設（emit周辺）。
 *            関数生成入口で g_insbuf_on=1、RET後にpeephole_pass()→insbuf_flush()→on=0。
 *   [P2a] 完全同一連続MOV削除（MOV X,Y / MOV X,Y → 後者削除）。
 *         MOVはフラグ不変(ISA2.3 0x20: flags=—)ゆえ2個目削除は無条件安全。
 *   [P2b] dead store除去（方針Y・超保守ホワイトリスト）。Aを書く命令(MOV A,reg/
 *         LDW A,..)直後に、Aを読まずAを上書きする命令(LDW A,#imm/LDW A,[..]/MOV A,reg≠A)が
 *         隣接する場合、前者を削除。ガード:(i)完全隣接のみ(ラベル/他命令が挟まれば非置換＝
 *         OBS-1基本ブロック境界)(ii)行2 sourceにA出現で非置換(iii)フラグ意味論ガード:
 *         行1=LDW(Z/N設定)かつ行2=MOV(フラグ不変)の組は行1のZ/Nが素通りするため非置換。
 *   peepholeは -O1 のみ作動。-O0/-O0-strict は非適用＝asm byte不変（§9.2.9(2)）。
 *
 *   【検証結果(2026-06-26)】
 *     - 絶対ゲート: -O0-strict Dhrystone 826/48405/P:20 完全一致（不変維持）。
 *     - 回帰: fib/test_for/test_for_call/test_local/dhry_timer × {-O0,-O0-strict} byte不変。
 *     - -O1効果: Dhrystone dead store 63命令削除(MOV A,B 132→69)。
 *                cycles 48405→48055(-350)・Dhrystones/sec 826→832。P:20不変(計算正当)。
 *     - float/代数簡約回帰: _fmul/_fdiv/I2F(SHL A,B)/F2I(SAR A,B)命令列 不変。
 *                emu23実行で float乗除算・代数簡約(x*0/x*1/x-x)・混合演算 全結果一致。
 *   【既知メモ】Dhrystone最終binのMD5はリンク手順(--machine force)差によりHANDOVER記載値
 *     (c9ed1e78…)と異なるが、サイズ21846・実行値826/48405/P:20は一致＝機能等価。要精査。
 *
 *   改版履歴:
 *     v2.01 2026-06-26 peephole(P2a/P2b)を-O1へ新設。命令ストリームバッファ基盤追加。
 *     v2.00 2026-06-22 float(Q8.8)/定数畳み込み/最適化レベル制御（下記）。
 *
 * --- 以下、v2.00の変更点（保持）---
 *
 * (v2.00) scc23_v2_00.c - Small C Compiler for YSD8800 ISA2.3
 * (v2.00) Version: 2.00 (2026-06-22)
 *
 * v2.00変更点（設計書 scc23_v2_00_design_v2_2.docx・ベース=scc23_v1_04.c）:
 *   float(Q8.8固定小数点)サポート・定数畳み込み・最適化レベル制御を追加。
 *   [S1] 型システム: T_FLOAT追加(sizeof=2)・floatキーワード・T_BOOL/T_UINT予約(§3.1/3.2)
 *   [S2] IR: SIR_FMUL/FDIV/I2F/F2I追加・g_use_fmul/fdivフラグ。比較命令リネームは
 *        見送り(§2.5.4: v1.04実体は既にA=0/1返し済・float不要・退行リスク)
 *   [S3] 字句: floatリテラル(1.5等)→Q8.8定数(to_fixed: x*256)。TOK_FNUM/cur_fval(§4.3)
 *   [S4] parse: 型昇格(binop_promote/wrap_i2f)。*→FMUL /→FDIV、int↔float混在でI2F挿入。
 *        キャスト(float)/(int)でI2F/F2Iノード挿入(§5.1)
 *   [S5] 定数畳み込み fold_binop(§7.2): float/int定数のコンパイル時計算・0除算error・
 *        FMULオーバーフローwarning。
 *   [S6] emit: SIR_FMUL/FDIV/I2F/F2IをISA2.3適合形で生成(§2.5.1)。即値シフト不使用、
 *        I2F=`LDW B,#8; SHL A,B` / F2I=`LDW B,#8; SAR A,B`。FMUL/FDIVはcc_mul評価規約踏襲
 *   [OPT] 最適化レベル -O0/-O0-strict/-O1(§2.3)。-O0-strict(§2.5.7・v2.2)は定数畳み込みを
 *        含む「コードを変える最適化」を全OFF→Dhrystone等の絶対ゲートをv1.04相当=ゲート値
 *        不変でビルド可能(実証: -O0-strictでDhrystone asmがv1.04と完全一致)。
 *        型変換正規化(I2F/F2I)はfloat必須意味論のため維持。
 *   ※ _fmul/_fdivランタイム本体のオンデマンド出力(§6.3〜6.5)は次工程(Step7)で実装予定。
 *
 * --- 以下、v1.04までの履歴（ベース由来・保持）---
 *
 * (旧ヘッダ) scc23_v1_04.c - Small C Compiler for YSD8800 ISA2.3
 * (旧)Version: 1.04 (2026-06-17)
 *
 * v1.04変更点:
 *   [WK2] memmap v2.4（案D-ε・承認済）に伴い Cプロセス区画を $C000-$C7FF → $D400-$DBFF へ
 *         +$1400 一律移設。理由: 旧ロード先 $C000 が Forth 辞書実コード（実測終端 $C15F）と
 *         物理衝突し、ProcMgr 経由ロード時に走行中カーネルを上書き破壊するため
 *         （HANDOVER_CHAT54/55・`Unknown opcode ff at c191` 暴走）。辞書外 $D400 へ退避。
 *         - ランタイムワーク変数 12個: $C7E8-$C7FF → $DBE8-$DBFF（24B・区画末尾$DBFF詰め）
 *         - CLI 既定値: CODE $0400→$D440 / RUNTIME $0100→$D780 / DATA $4000→$DA80
 *         論理コード不変・アドレス値のみ付け替え（+$1400）。
 *         実装根拠: memmap v2.4 §15.6/§15.7（新規設計書不要・レビュー C-1）。
 *         後方互換: --code-org/--data-org/--runtime-org で任意値へ上書き可能（維持）。
 *
 * ※版数整合是正(v1.03): 本ファイルは v1.01→v1.02→v1.03 と改版されてきたが、
 *   v1.02 では冒頭コメントのファイル名/Version 表記が v1.01 のまま残存し、
 *   かつ v1.02 変更点履歴が欠落していた（SCC_VERSION 定義のみ "1.02"）。
 *   KY41（4点整合: ファイル名・SCC_VERSION・ヘッダ・改版履歴）違反の残骸であったため、
 *   v1.03 改版時に冒頭コメントを是正し、欠落していた v1.02 履歴を実体に基づき補完した。
 *
 * v1.03変更点:
 *   [WK1] ランタイムワーク変数を $FBD0系 → $C7E8系（Cプロセス区画内DATA末尾$C7E8-$C7FF/24B）へ移設。
 *         旧 $FBD0-$FBE7 が kernel タスクスタック領域 $F000-$FBFF（tid7 データスタック
 *         $FB80-$FBFE）に侵入し、ProcMgr 経由ロード時に tid7 のデータスタックを破壊する
 *         サイレント・コラプションを起こすため。論理コード不変・#define 値の付け替えのみ。
 *         設計書: scc23_runtime_wk_relocation_design_v1_1.docx（有識者レビュー承認済・条件なし）。
 *   [V1.03-FIX] 冒頭コメントの版数表記是正＋v1.02履歴補完（上記・KY41 4点整合）。
 *
 * v1.02変更点（※実体に基づき v1.03 で遡及補完）:
 *   [A] ベースアドレスのコマンドライン引数化: --code-org / --data-org / --runtime-org を追加。
 *       parse_org_arg() で $XXXX / 0xXXXX 両形式を解釈（内部 base16）、16bit空間外を弾く。
 *       g_code_org / g_data_org / g_runtime_org（既定 $0400/$4000/$0100）と
 *       エイリアス #define CODE_ORG/DATA_ORG/RUNTIME_ORG で全箇所が追従。オプション省略時は
 *       v1.01 と同一動作（後方互換）。ProcMgr の Cプロセス区画配置($C040/$C380/$C680)に対応。
 *   [B] 演算子系ヘルパのオンデマンド出力: g_use_mul/g_use_div/g_use_mod フラグを導入し、
 *       乗除算ランタイム(_cc_mul/_cc_div 等)を実使用時のみ出力。RUNTIME 出力を parse loop の
 *       後（フラグ確定後）へ移動。未使用ランタイムの無駄出力を抑止。
 *
 * v1.01変更点:
 *   [P1] parse_add(): ポインタ+整数のスケーリング追加（int*→×2、char*→×1）
 *   [P2] parse_add(): ポインタ同士の減算をC標準準拠の要素数返しに修正
 *   [P3] SIR_POST_INC/POST_DEC/PRE_INC/PRE_DEC: ポインタ型のスケーリング追加
 *   [P4] emit_data_section(): 文字列リテラルの2バイトアライメントパディング追加
 *   [P5] parse_unary(): *ptr逆参照の型推論修正（char*→T_CHAR/is_byte=1）
 *   [P6] ptr-ptr減算の右シフトをSIR_SHR→SIR_SAR（符号保存）に修正
 *   [P7] SIR_ASGN_OP: ptr+=n/ptr-=nのスケーリング追加・char*バイトロード修正
 *
 * ISA2.3対応変更点 (scc22 v3.05からの差分):
 *   [ASM] asm("...") インラインアセンブラ構文追加
 *         - 複数命令はセミコロン区切り
 *         - レジスタ保護なし（呼び出し側責務）
 *         - strsep() 使用（Linux+gcc環境）
 *
 * v1.00からの継承:
 * scc22 v3.05からの継承:
 *   v3.05: [B9] switch break スタック不均衡修正
 *   v3.04: [B7] node_vkind() T_PTR VK_RVALUE修正
 *   v3.03: [A7] block stack廃止・frame_size方式回帰
 *   v3.02: [F1-F5] value_kind/SIR_CALL/DW統一/ワーク変数/$FBD0系
 *   v3.00: IR（中間表現）導入
 *   v2.11: 修正A〜K適用
 *
 * 呼び出し規約:
 *   A  = 式評価主レジスタ / 戻り値
 *   B  = 補助演算レジスタ（emit_expr内で破壊される可能性あり）
 *   X  = フレームポインタ（emit_expr内で不変）
 *   SP = Cスタック（PUSH/POPは必ず対応）
 *
 * スタックフレーム（X = フレームポインタ）:
 *   [X+0]  = 旧X
 *   [X+2]  = 戻りアドレス（JSR自動push）
 *   [X+4]  = 第1引数（最後にpush）
 *   [X+6]  = 第2引数
 *   [X-2]  = ローカル変数1
 *   [X-4]  = ローカル変数2
 *
 * build: gcc -std=c99 -O2 -Wall scc23_v1_03.c -o scc23
 * usage: scc23 [-o output.asm] [--code-org N] [--data-org N] [--runtime-org N] input.c
 */
#define _GNU_SOURCE  /* strsep() を有効化（POSIX拡張・Linux+gcc） */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <stdarg.h>
#include <stdint.h>

/* ============================================================
 * バージョン
 * ============================================================ */
#define SCC_VERSION   "2.03"
#define SCC_DATE      "2026-07-03"

/* ============================================================
 * 定数
 * ============================================================ */
#define MAX_SYM         1024
#define MAX_LOCAL       64
#define MAX_PARAM       16
#define MAX_BREAK       32
#define MAX_STR         512
#define IDENT_LEN       64
#define MAX_STRUCT_MEM  64
#define MAX_STRUCTS     64
#define MAX_TYPEDEF     128

/* --- ベースアドレス（v1.02: コマンドライン引数で上書き可能） --- */
/* [v1.04] 既定値を memmap v2.4（案D-ε）の Cプロセス区画 $D400-$DBFF へ変更。
 *   引数省略時に $D400 区画へ向く。crt0=$D400 / CODE=$D440 / RUNTIME=$D780 / DATA=$DA80。
 *   旧既定値（v1.01〜v1.03）: DATA=$4000 / RUNTIME=$0100 / CODE=$0400（汎用・後方互換用）
 *   ※必要なら --data-org/--runtime-org/--code-org で従来値を含む任意値へ上書き可能（後方互換維持）。 */
#define DATA_ORG_DEFAULT     0xDA80   /* [v1.04] $4000 → $DA80 */
#define RUNTIME_ORG_DEFAULT  0xD780   /* [v1.04] $0100 → $D780 */
#define CODE_ORG_DEFAULT     0xD440   /* [v1.04] $0400 → $D440 */
static unsigned g_data_org    = DATA_ORG_DEFAULT;
static unsigned g_runtime_org = RUNTIME_ORG_DEFAULT;
static unsigned g_code_org    = CODE_ORG_DEFAULT;
/* 旧マクロ名を変数へエイリアス（既存参照箇所を一括追従させる） */
#define DATA_ORG     g_data_org
#define RUNTIME_ORG  g_runtime_org
#define CODE_ORG     g_code_org

/* --- (B) 演算子系ヘルパ オンデマンド出力フラグ（v1.02） --- */
/* SIR_MUL/DIV/MOD の JSR 発行時に立て、emit_runtime で使用ヘルパのみ出力する */
static int g_use_mul = 0;
static int g_use_div = 0;
static int g_use_mod = 0;
/* [v2.00] float用。SIR_FMUL/FDIVのJSR発行時に立て、emit_runtimeで_fmul/_fdivをオンデマンド出力（§6.3/§2.5.6）。
 * floatを使わないプログラム(Dhrystone等)では0のまま→ランタイム未出力→bin完全一致（§6.3の狙い）。 */
static int g_use_fmul = 0;
static int g_use_fdiv = 0;

/* [v2.00] 最適化レベル（§2.3）。
 *   OPT_O0(既定): 定数畳み込み・型変換正規化・不要ノード削除・F2I(I2F)安全範囲除去 有効
 *   OPT_O0_STRICT: ノード削除/同型CAST除去/F2I(I2F)除去を無効化（定数畳み込みは§5/§7.1で常時有効）
 *   OPT_O1: O0に加え代数簡約(x*0,x+0,x/1.0,x*2.0等) */
enum { OPT_O0=0, OPT_O0_STRICT=1, OPT_O1=2 };
static int g_opt_level = OPT_O0;

/* [P1/C-1検証] --no-peep: peephole_pass() を丸ごと無効化する検証専用フラグ。
 * 1=peephole全パス(P2a/P2b/P3/P1)を素通し。-O1でも peephole適用前の生出力を得る。
 * 用途: peephole ON/OFF差分の観測（P1発生起源の切り分け・回帰の切り分け）。
 * 既定0。最適化レベル(-O0/-O0-strict/-O1)とは独立。 */
static int g_no_peep = 0;

/* [v1.03] ランタイムワーク領域を $FBD0系 → $C7E8系 へ移設。
 *   旧 $FBD0-$FBE7 は kernel タスクスタック領域 $F000-$FBFF（tid7 データスタック
 *   $FB80-$FBFE）に侵入し、ProcMgr 経由ロード時に tid7 のデータスタックを破壊する
 *   サイレント・コラプションを起こす（設計書 scc23_runtime_wk_relocation_design_v1_1）。
 *   Cプロセス承認区画 $C000-$C7FF（2KB）の DATA 区画末尾 $C7E8-$C7FF（24B）へ移設し、
 *   プロセス全状態を区画内に自己完結させる。グローバル変数（$C680から上方成長）とは
 *   反対端（$C7FF詰め）で離す配置。論理コードは不変・アドレス値のみ付け替え。 */
/* [v1.04] memmap v2.4（案D-ε・承認済）に伴い Cプロセス区画を $C000-$C7FF → $D400-$DBFF
 *   へ +$1400 一律移設（$C000 が Forth 辞書実コード $C15F と物理衝突するため辞書外へ）。
 *   本ワーク領域も $C7E8-$C7FF → $DBE8-$DBFF（24B・区画末尾$DBFF詰め）へ +$1400。
 *   論理コード不変・アドレス値のみ付け替え（memmap v2.4 §15.6/§15.7 を実装根拠）。 */
#define C_XSAVE_ADDR    0xDBE8   /* inc/dec addr退避  ※v1.04 $C7E8→$DBE8 */
#define C_TMP_ADDR      0xDBEA   /* inc/dec旧値/strcpy/strcmp ワーク */
#define C_TMP_ADDR1     0xDBEC   /* [F4] 追加ワーク（設計書v1.5 D9） */
/* [v1.04] ランタイムワーク領域 $DBE8〜$DBFF（24B・Cプロセス区画内DATA末尾） */
#define C_MEMCPY_DEST   0xDBEE   /* memcpy dest ptr */
#define C_MEMCPY_SRC    0xDBF0   /* memcpy src ptr  */
#define C_MEMCPY_CNT    0xDBF2   /* memcpy count    */
#define C_MUL_BASE      0xDBF4   /* _cc_mul A */
#define C_MUL_B         0xDBF6   /* _cc_mul B */
#define C_MUL_R         0xDBF8   /* _cc_mul R */
#define C_DIV_BASE      0xDBFA   /* _cc_div A */
#define C_DIV_B         0xDBFC   /* _cc_div B */
#define C_DIV_Q         0xDBFE   /* _cc_div Q（占有 $DBFE-$DBFF・区画末尾$DBFF詰め） */

/* SirNode 専用定数 */
#define SIR_MAX_ARGS    16
#define SIR_MAX_STMTS   256  /* parse_block内最大文数（動的割当のため参考値）*/

/* ============================================================
 * 型定義（v2.11から流用）
 * ============================================================ */
typedef enum {
    T_INT = 0, T_CHAR, T_PTR, T_ARRAY, T_VOID, T_STRUCT, T_UNION,
    /* [v2.00] 設計書§3.1: float型追加・bool/uintは予約のみ（今回未実装）。
     * 末尾追加につき既存値(T_INT=0等)は不変・後方互換維持。 */
    T_FLOAT, T_BOOL, T_UINT
} ctype_t;

typedef enum {
    SC_GLOBAL, SC_LOCAL, SC_PARAM, SC_FUNC, SC_DEFINE,
    SC_TYPEDEF, SC_ENUM_VAL, SC_STRUCT_TAG, SC_UNION_TAG
} sclass_t;

typedef struct member {
    char     name[IDENT_LEN];
    ctype_t  type;
    ctype_t  base;
    int      offset;
    int      size;
    int      is_array;
    int      arr_size;
    int      is_ptr;
    int      struct_idx;
    int      dim2;
} member_t;

typedef struct structdef {
    char      tag[IDENT_LEN];
    int       is_union;
    member_t  members[MAX_STRUCT_MEM];
    int       nmembers;
    int       total_size;
} structdef_t;

typedef struct sym {
    char     name[IDENT_LEN];
    ctype_t  type;
    ctype_t  base;
    sclass_t sclass;
    int      offset;
    int      size;
    int      is_array;
    int      defined;
    char     defval[MAX_STR];
    int      ival;
    int      struct_idx;
    int      dim2;
    struct sym *next;
} sym_t;

typedef struct {
    char    name[IDENT_LEN];
    ctype_t type;
    ctype_t base;
    int     is_ptr;
    int     is_array;
    int     arr_size;
    int     struct_idx;
    int     dim2;
} typedef_t;

/* ============================================================
 * P1: 式IR（SirNode）型定義
 * ============================================================ */
typedef enum {
    /* リテラル・変数 */
    SIR_CONST,      /* 整数定数 */
    SIR_SYM,        /* シンボル参照（値ロード） */
    SIR_ADDR,       /* アドレス取得 &var */
    SIR_STRLIT,     /* 文字列リテラル（idはstrlitのid） */
    /* メモリ */
    SIR_LOAD,       /* メモリロード */
    SIR_STORE,      /* メモリストア */
    /* 2項算術 */
    SIR_ADD, SIR_SUB, SIR_MUL, SIR_DIV, SIR_MOD,
    /* 2項ビット */
    SIR_AND, SIR_OR, SIR_XOR, SIR_SHL, SIR_SHR,
    SIR_SAR,      /* [P6] v1.01: 算術右シフト（符号保存）ptr-ptr除算用 */
    /* 比較 */
    SIR_EQ, SIR_NE, SIR_LT, SIR_LE, SIR_GT, SIR_GE,
    /* 論理（short-circuit） */
    SIR_LAND, SIR_LOR,
    /* 単項 */
    SIR_NEG, SIR_NOT, SIR_COMPL, SIR_DEREF,
    /* 配列・構造体 */
    SIR_INDEX,      /* 1D配列 base[idx] */
    SIR_INDEX2D,    /* 2D配列 base[i][j] */
    SIR_MEMBER,     /* struct.member / struct->member */
    /* 関数呼び出し */
    SIR_CALL,
    /* 代入 */
    SIR_ASSIGN,     /* 単純代入 */
    SIR_ASGN_OP,    /* 複合代入 (+=等) */
    /* その他 */
    SIR_CAST,
    SIR_COND,       /* 三項 a?b:c */
    SIR_COMMA,
    SIR_POST_INC, SIR_POST_DEC,
    SIR_PRE_INC,  SIR_PRE_DEC,
    SIR_SIZEOF,     /* sizeof（定数畳み込み済み） */
    SIR_NOP,        /* 空式 */
    /* ===== [v2.00] float(Q8.8)関連 新規オペコード（設計書§4.1）===== */
    SIR_FMUL,       /* A = (A * B) >> 8   _fmul呼び出し。call前spill必須。g_use_fmul=1 */
    SIR_FDIV,       /* A = (A << 8) / B   _fdiv呼び出し。call前spill必須。g_use_fdiv=1。負数除算未定義 */
    SIR_I2F,        /* A = A << 8 (LDW B,#8; SHL A,B)  int->float。定数なら畳み込み */
    SIR_F2I,        /* A = A >> 8 算術 (LDW B,#8; SAR A,B)  float->int */
    /* ----- 将来予約（本v2.00未実装。§2.5.4でリネーム見送り）-----
     * 符号なし比較 SIR_CMP_*_U / 8->16拡張 SIR_SEXT8_16 / SIR_ZEXT8_16 等は
     * bool/unsigned型実装時に追加する。既存比較(SIR_LT等)は名称変更しない。 */
} sir_op_t;

typedef struct sir_node {
    sir_op_t    op;
    int         lineno;
    /* SIR_CONST / SIR_SIZEOF */
    int         ival;
    /* SIR_SYM / SIR_ADDR */
    sym_t      *sym;
    /* SIR_STRLIT */
    int         str_id;
    /* 汎用オペランド */
    struct sir_node *left;   /* 第1オペランド */
    struct sir_node *right;  /* 第2オペランド */
    struct sir_node *extra;  /* SIR_COND: elseブランチ */
    /* SIR_INDEX2D 専用 */
    struct sir_node *r2;     /* 列インデックス */
    int         dim2;        /* 列数 */
    int         esz;         /* 要素サイズ（バイト） */
    /* SIR_MEMBER 専用 */
    int         offset;      /* メンバオフセット */
    int         is_ptr;      /* ->演算子か */
    int         struct_idx;  /* メンバが属するstruct index */
    /* SIR_CALL 専用 */
    char        fname[IDENT_LEN];
    struct sir_node *args[SIR_MAX_ARGS];
    int         nargs;
    /* SIR_ASGN_OP 専用 */
    sir_op_t    aop;         /* 基底演算 (SIR_ADD等) */
    /* 型情報 */
    ctype_t     type;
    ctype_t     base;
    int         is_byte;     /* SIR_LOAD/STORE: 1=byte */
    int         is_array;    /* [F1] 配列フラグ（node_vkind判定用） */
} sir_node_t;

/* ============================================================
 * グローバル状態（v2.11から流用）
 * ============================================================ */
static FILE   *src_fp;
static FILE   *out_fp;
static char   *src_name;

static int     cur_char;
static int     cur_line;
static char    cur_tok[MAX_STR];
static int     cur_ival;
static double  cur_fval;   /* [v2.00] floatリテラルの値（TOK_FNUM時に有効） */
static char    cur_str[MAX_STR];

#define PUSHBACK_DEPTH 8
static int     pb_count;
static char    pb_str[PUSHBACK_DEPTH][MAX_STR];
static int     pb_ival[PUSHBACK_DEPTH];
static char    pb_sval[PUSHBACK_DEPTH][MAX_STR];

static sym_t  *sym_table;
static int     sym_count;

static structdef_t structs[MAX_STRUCTS];
static int         nstructs;

static typedef_t   typedefs[MAX_TYPEDEF];
static int         ntypedefs;

static int     label_seq;

static sym_t  *cur_func;
static int     local_count;
static int     param_count;
static int     frame_size;       /* [A7] SPトラッカー: 未解放ローカル変数累積バイト数 */
static int     func_end_label;
static int     func_has_return;  /* [A7fix3] return文が発行されたか（末尾ADDI SP抑制用） */

static int     break_stack[MAX_BREAK];
static int     cont_stack[MAX_BREAK];
static int     break_is_switch[MAX_BREAK];
static int     loop_depth;

#define MAX_SWITCH 8
static int     switch_end[MAX_SWITCH];
static int     switch_depth;

typedef struct strlit {
    int id;
    char text[MAX_STR];
    int  len;
    struct strlit *next;
} strlit_t;
static strlit_t *strlit_list;
static int       strlit_count;

static int     data_offset;
static int     error_count;

/* #ifdef/#if 処理用 */
static int g_stopped_at_else = 0;

/* ============================================================
 * エラー・警告
 * ============================================================ */
static void error(const char *fmt, ...) {
    va_list ap;
    fprintf(stderr, "%s:%d: error: ", src_name, cur_line);
    va_start(ap, fmt); vfprintf(stderr, fmt, ap); va_end(ap);
    fprintf(stderr, "\n");
    error_count++;
}
static void warning(const char *fmt, ...) {
    va_list ap;
    fprintf(stderr, "%s:%d: warning: ", src_name, cur_line);
    va_start(ap, fmt); vfprintf(stderr, fmt, ap); va_end(ap);
    fprintf(stderr, "\n");
}

/* ============================================================
 * アセンブリ出力（バックエンド専用 - フロントエンドから直接使用禁止）
 * ============================================================ */
/* ============================================================
 * [v2.01 peephole] 命令ストリームバッファ基盤（設計書§9.2.4・方式B）
 *   - emit/emit_label の出力を関数生成区間のみバッファへ蓄積し、
 *     関数クローズ時に -O1ならpeephole走査→flush、それ以外は無加工flush。
 *   - 関数外(emit_runtime/data_section等)の出力はバッファOFFで従来通り即時。
 *   - KY: -O0/-O0-strict はpeephole非適用＝asm byte不変（§9.2.9(2)）。
 * ============================================================ */
#define INSBUF_MAX 8192            /* 1関数あたり最大命令(行)数。Dhrystone最大関数でも十分 */
static char *g_insbuf[INSBUF_MAX]; /* 各行の文字列(strdup) */
static int   g_insbuf_n;           /* 蓄積行数 */
static int   g_insbuf_on;          /* 1=バッファ蓄積中(関数生成区間), 0=即時出力 */
static int   g_insbuf_ovf;         /* オーバーフロー検知 */

/* バッファへ1行追加。OFF時は直接out_fpへ。 */
static void insbuf_put(const char *line) {
    if (!g_insbuf_on) { fprintf(out_fp, "%s\n", line); return; }
    if (g_insbuf_n >= INSBUF_MAX) {
        if (!g_insbuf_ovf) { g_insbuf_ovf = 1;
            fprintf(stderr, "scc23: warning: insbuf overflow (>%d lines), peephole skipped for this func\n", INSBUF_MAX); }
        fprintf(out_fp, "%s\n", line);  /* 退避: 直接出力（最適化対象外になるが正しさは維持） */
        return;
    }
    g_insbuf[g_insbuf_n++] = strdup(line);
}

static void emit(const char *fmt, ...) {
    char line[512];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(line, sizeof(line), fmt, ap);
    va_end(ap);
    insbuf_put(line);
}
static void emit_label(int n) { char line[64]; snprintf(line,sizeof(line),"_L_%04d:",n); insbuf_put(line); }
static int  new_label(void)   { return label_seq++; }

/* 行がMOV命令か判定（コメント/ラベル/他命令を除外） */
static int is_mov_line(const char *s) {
    /* emit書式は "    MOV  rD, rS"。先頭空白スキップ後 "MOV " で始まるか。 */
    while (*s == ' ' || *s == '\t') s++;
    return (strncmp(s, "MOV ", 4) == 0);
}

/* 先頭空白を飛ばしたポインタを返す */
static const char *ph_skipws(const char *s){ while(*s==' '||*s=='\t')s++; return s; }

/* ラベル行か（_L_xxxx: / _name: 等、行末や途中に ':' を持ちMOV等命令でない）。
 * emit書式では命令行は "    OP ..."、ラベルは "_..." で始まる。 */
static int is_label_line(const char *s){
    const char *p = ph_skipws(s);
    if (*p == '_' ) return 1;           /* _L_xxxx: / _func: */
    /* コメント行/空行も境界扱い（隣接性を断つ） */
    if (*p == ';' || *p == '\0') return 1;
    return 0;
}

/* [P2b] 行が「Aを書く命令」か（dead store候補=行1の条件）。
 * 対象: MOV A,<reg> / LDW A,#imm / LDW A,[...]。
 * これらはAに新値を書き、書込み自体はA自身の旧値に依存しない。 */
static int writes_A_indep(const char *s){
    const char *p = ph_skipws(s);
    if (strncmp(p,"MOV  A,",7)==0) return 1;   /* MOV  A, B / MOV  A, X */
    if (strncmp(p,"LDW  A,",7)==0) return 1;   /* LDW  A, #imm / [..] */
    return 0;
}

/* [P2b] 行がフラグ(Z/N)を設定する命令か（ISA2.3命令表ベース）。
 * MOV(0x20)=フラグ不変(—)、LDW(0x21/22/24/26)=Z/N設定。 */
static int sets_flags_Ald(const char *s){
    const char *p = ph_skipws(s);
    if (strncmp(p,"LDW ",4)==0) return 1;      /* LDWはZ/N更新 */
    if (strncmp(p,"MOV ",4)==0) return 0;      /* MOVはフラグ不変 */
    return 1;  /* 不明命令は安全側=フラグ設定扱い（このヘルパは行1判定専用） */
}

/* [P2b] 行が「行1のAを読まずにAを上書きする命令」か（行2の条件）。
 * 対象: LDW A,#imm / LDW A,[...] / MOV A,<reg>。
 * ただし source に A が現れる場合（[A]/[A+..]/MOV A,A）は A を読むので除外（保守的）。 */
static int overwrites_A_no_read(const char *s){
    const char *p = ph_skipws(s);
    const char *src = NULL;
    if (strncmp(p,"LDW  A,",7)==0) src = p+7;
    else if (strncmp(p,"MOV  A,",7)==0) src = p+7;
    else return 0;
    src = ph_skipws(src);
    if (src[0]=='A' || strstr(src,"[A")!=NULL || strstr(src,"+ A")!=NULL) return 0;
    return 1;
}

/* [P2b] 行2がフラグ不変命令(MOV)か。フラグ意味論ガード用。 */
static int is_flag_neutral_A(const char *s){
    const char *p = ph_skipws(s);
    return (strncmp(p,"MOV ",4)==0);
}

/* ===== [P3] ADD B,A / MOV A,B → ADD A,B 統合（§9.2.11）===== */

/* 行が厳密に "ADD  B, A" か（先頭空白スキップ後の正規形一致）。*/
static int is_p3_add_BA(const char *s){
    const char *p = ph_skipws(s);
    return (strcmp(p, "ADD  B, A") == 0);
}
/* 行が厳密に "MOV  A, B" か。*/
static int is_p3_mov_AB(const char *s){
    const char *p = ph_skipws(s);
    return (strcmp(p, "MOV  A, B") == 0);
}

/* [P3] 行が「Bを再定義する命令」か（Bをdestに書き、sourceにBを含まない）。
 * 窓内でこれを先に発見できれば B は dead 確定。
 * 対象: LDW  B, #imm / LDW  B, [..] / MOV  B, <reg≠B>。
 * sourceにB（[B]/[B+..]/+ B/先頭B）が現れる場合はBを読むので再定義扱いにしない。*/
static int p3_redefines_B(const char *s){
    const char *p = ph_skipws(s);
    const char *src = NULL;
    if (strncmp(p,"LDW  B,",7)==0) src = p+7;
    else if (strncmp(p,"MOV  B,",7)==0) src = p+7;
    else return 0;
    src = ph_skipws(src);
    if (src[0]=='B' || strstr(src,"[B")!=NULL || strstr(src,"+ B")!=NULL) return 0;
    return 1;
}

/* [P3] 行が「Bを読む可能性がある」か（dead証明を打ち切る）。
 * 保守的: source位置（destカンマの後ろ）にBが字句で現れる、または
 *   STW B,.. のようにBをsourceに持つ命令。
 * p3_redefines_B が真の行はBを読まない再定義なので、呼び出し側で先に再定義判定する。*/
static int p3_reads_B(const char *s){
    const char *p = ph_skipws(s);
    /* オペコード(英大文字)をスキップ */
    const char *q = p;
    while (*q && *q!=' ' && *q!='\t') q++;   /* OP終端 */
    const char *rest = ph_skipws(q);          /* オペランド先頭 */
    /* destを取得（最初のカンマまで）。カンマが無ければ単項/オペランド全体をsource扱い。*/
    const char *comma = strchr(rest, ',');
    const char *src = comma ? ph_skipws(comma+1) : rest;
    /* source側にBが字句で現れるか（[B]/[B+..]/+ B/先頭B/単独B）。*/
    if (src[0]=='B' && (src[1]==',' || src[1]==' ' || src[1]=='\0' || src[1]==']' || src[1]=='+'))
        return 1;
    if (strstr(src,"[B")!=NULL) return 1;
    if (strstr(src,"+ B")!=NULL) return 1;
    /* STW B,.. はBをsourceとして読む（destがメモリ、Bが第1オペランド=rest先頭）*/
    if (strncmp(p,"STW  B",6)==0) return 1;
    return 0;
}

/* [P3] 行が制御フロー境界か（dead証明を打ち切る）。
 * ISA2.3実機(0x60-0x64,0x68,0x69,0x04): JMP/BEQ/BNE/BLT/BGE/JSR/RET/IRET。
 * BMI/BPLはISA2.3に非存在。BRK(0x06)は分岐でなくBを再定義しないため、
 * ここで境界としなくても窓内未確定→非置換に自然に倒れる（安全側）。*/
static int p3_is_boundary(const char *s){
    const char *p = ph_skipws(s);
    if (is_label_line(s)) return 1;                 /* _label: / ; / 空行 */
    if (strncmp(p,"JMP",3)==0) return 1;
    if (strncmp(p,"JSR",3)==0) return 1;
    if (strncmp(p,"RET",3)==0) return 1;
    if (strncmp(p,"IRET",4)==0) return 1;
    /* 条件分岐 B{EQ,NE,LT,GE} のみ境界。BRK等の他のB*は除外（=非境界）。*/
    if (p[0]=='B' && (strncmp(p+1,"EQ",2)==0 || strncmp(p+1,"NE",2)==0
                   || strncmp(p+1,"LT",2)==0 || strncmp(p+1,"GE",2)==0)) return 1;
    return 0;
}

/* [P3] G4: g_insbuf[start..] を固定窓W=6で走査し、Bがdeadか積極証明する。
 *   ・B再定義を先に発見            → 真（dead確定・置換可）
 *   ・B読み出し/境界を先に発見      → 偽（live可能性・非置換）
 *   ・窓を尽くす/終端到達で未確定    → 偽（保守・非置換）  ★本日KY: 終端は安全側false
 * 走査は読み取り専用（配列を変更しない）。*/
static int p3_b_dead_within_window(int start, int n){
    const int W = 6;
    int end = start + W;
    if (end > n) end = n;                  /* ★終端クランプ（KY: 越境読み防止）*/
    for (int i = start; i < end; i++){
        const char *ln = g_insbuf[i];
        if (p3_redefines_B(ln)) return 1;  /* B再定義を先に発見＝dead確定 */
        if (p3_reads_B(ln))     return 0;  /* Bを読む＝live可能性 */
        if (p3_is_boundary(ln)) return 0;  /* 分岐/JSR/RET/IRET/ラベル＝打ち切り */
    }
    return 0;                              /* 窓内/終端で未確定＝保守的に非置換 */
}

/* ================= P1: スタックラウンドトリップ除去 判定ヘルパ =================
 * 設計: scc23_v2_03_peephole_P1_design_v1_3.md §2（ガードG1〜G5）。
 * 対象4命令窓（完全隣接・SP収支ゼロ・[SP]自己完結）:
 *     SUBI SP, #2 / STW A,[SP] / LDW B,[SP] / ADDI SP, #2   →   MOV  B, A
 * 生成起源は「境界偶然マッチ」（異SIRノード境界の偶然一致）。安全性は起源非依存で、
 * 4命令ローカル正味効果が B=A（+デッドストア+SP収支ゼロ）= MOV B,A（0x20・FLAGS不変）
 * と外部観測等価であることに基づく（設計書 §1.3/§4）。 */

/* [P1] G2/G3: 窓の各行が期待綴りと完全一致か（ph_skipwsで行頭空白正規化）。
 * emit実綴り（KY34実確認済 L2147-2152）:
 *   "    SUBI SP, #2" / "    STW  A, [SP]" / "    LDW  B, [SP]" / "    ADDI SP, #2"
 * G4（[SP]オフセット無し）は完全一致比較により [SP+imm] を自動排除（別綴りゆえ不一致）。*/
static int p1_is_line(const char *s, const char *want){
    return strcmp(ph_skipws(s), want) == 0;
}

/* [P1] G5【フラグ意味論保護・最重要】: 窓直後の命令がZ/Nを読む条件分岐か。
 * 元列末尾 ADDI SP,#2 はZ/Nを更新するが MOV B,A はFLAGS不変。直後がそのZ/Nを読む
 * 分岐だと置換で挙動が変わるため非置換とする。
 * ISA2.3実仕様（ISA2_3_v231.docx L228-231/L254）でZ/Nを読むのは
 *   BEQ(0x61)/BNE(0x62)/BLT(0x63)/BGE(0x64) の4種のみ。
 * JMP/JSR/RET は無条件でフラグを読まない → 置換可（P3のboundaryとは意味が異なる。
 * P1はフラグ可視性のみが論点で、制御フロー境界一般ではない）。*/
static int p1_next_reads_ZN(const char *s){
    const char *p = ph_skipws(s);
    if (p[0]=='B' && (strncmp(p+1,"EQ",2)==0 || strncmp(p+1,"NE",2)==0
                   || strncmp(p+1,"LT",2)==0 || strncmp(p+1,"GE",2)==0)) return 1;
    return 0;
}

/* peephole走査本体（-O1時のみ）。基盤の g_insbuf[0..g_insbuf_n) を書き換える。 */
static void peephole_pass(void) {
    if (g_no_peep) return;               /* [P1/C-1検証] --no-peep 指定時は全パス無効 */
    if (g_opt_level != OPT_O1) return;   /* peepholeは-O1のみ（§9.2.2/§9.2.9(2)） */

    /* ---- P2a: 完全同一連続MOV削除（§9.2.9(1)）----
     * `MOV X,Y` の直後に完全同一の `MOV X,Y` が隣接する場合、後者を削除。
     * MOVはフラグ不変(ISA2.3 0x20: flags=—)のため2個目削除は無条件安全。 */
    {
        int w = 0;
        for (int r = 0; r < g_insbuf_n; r++) {
            if (w > 0 && is_mov_line(g_insbuf[w-1]) && is_mov_line(g_insbuf[r])
                      && strcmp(g_insbuf[w-1], g_insbuf[r]) == 0) {
                free(g_insbuf[r]); continue;
            }
            g_insbuf[w++] = g_insbuf[r];
        }
        g_insbuf_n = w;
    }

    /* ---- P2b: dead store除去（§9.2.9(1)・方針Y 超保守ホワイトリスト）----
     * 行1=Aを書く命令(MOV A,<reg>/LDW A,..) の直後、隣接する行2が
     * 「Aを読まずにAを上書きする命令」(LDW A,#imm/LDW A,[..]/MOV A,<reg≠A>) の場合、
     * 行1のA書込みは誰にも読まれず dead → 行1を削除。
     * ガード(OBS-1): 行1・行2が完全隣接（間に命令/ラベル/コメント無し）であること。
     *   前詰め走査で「直前に確定した行(w-1)」と「現在行(r)」の隣接のみ見るため、
     *   ラベル/他命令が挟まれば writes_A_indep/overwrites_A_no_read のどちらかが偽になり非置換。
     * MOV/LDWはA書込み後フラグを汚さない順序関係に影響しない（行2が最終的にAとフラグを決める）。*/
    {
        int w = 0;
        for (int r = 0; r < g_insbuf_n; r++) {
            if (w > 0
                && writes_A_indep(g_insbuf[w-1])          /* 直前=Aを書く命令(行1) */
                && overwrites_A_no_read(g_insbuf[r])       /* 現在=Aを読まずA上書き(行2) */
                /* フラグ意味論ガード: 行1がフラグ設定(LDW)かつ行2がフラグ不変(MOV)なら、
                 * 行1のZ/Nが行2を素通りして後続に残る可能性 → 削除すると意味論変化。除外。 */
                && !(sets_flags_Ald(g_insbuf[w-1]) && is_flag_neutral_A(g_insbuf[r]))) {
                free(g_insbuf[w-1]);
                g_insbuf[w-1] = g_insbuf[r];               /* 行2を行1位置へ前詰め */
                continue;
            }
            g_insbuf[w++] = g_insbuf[r];
        }
        g_insbuf_n = w;
    }

    /* ---- P3: ADD B,A / MOV A,B → ADD A,B 統合（§9.2.11）----
     * 隣接する "ADD  B, A"(行1=w-1) と "MOV  A, B"(行2=r) を、後続でBがdeadなら
     * "ADD  A, B" 1命令へ統合。加算可換ゆえA最終値・FLAGS(Z/N)は同値（§9.2.11.1）。
     * 唯一のリスクはBの値変化 → G4: p3_b_dead_within_window で B dead を積極証明できた時のみ置換。
     * 窓走査は r+1 以降（未処理側）を読み取り専用で参照（本日KY: 書換と先読みを混ぜない）。*/
    {
        int w = 0;
        for (int r = 0; r < g_insbuf_n; r++) {
            if (w > 0
                && is_p3_add_BA(g_insbuf[w-1])             /* 行1=直前確定 "ADD  B, A" */
                && is_p3_mov_AB(g_insbuf[r])               /* 行2=現在 "MOV  A, B"（隣接はw-1とrで担保）*/
                && p3_b_dead_within_window(r+1, g_insbuf_n)) {  /* G4: Bがdead */
                /* 行1を "ADD  A, B" へ書換、行2(r)は破棄。w据え置き（行数-1）。*/
                char *rep = strdup("    ADD  A, B");
                if (rep) {                                  /* strdup失敗時は安全側で非置換 */
                    free(g_insbuf[w-1]);
                    g_insbuf[w-1] = rep;
                    free(g_insbuf[r]);
                    continue;
                }
            }
            g_insbuf[w++] = g_insbuf[r];
        }
        g_insbuf_n = w;
    }

    /* ---- P1: スタックラウンドトリップ除去（§9.2.12）----
     * 4命令固定窓 [SUBI SP,#2 / STW A,[SP] / LDW B,[SP] / ADDI SP,#2] を
     * "MOV  B, A" 1命令へ畳込む。全ガードG1〜G5成立時のみ置換。
     *  G1: 4命令が完全隣接（g_insbuf連続4要素で担保。間にラベル/コメント実体があれば
     *      p1_is_line完全一致が偽になり不成立＝自然に非置換）。
     *  G2: 行r=SUBI SP,#2 / 行r+3=ADDI SP,#2（同量対応）。
     *  G3: 行r+1=STW A,[SP] / 行r+2=LDW B,[SP]。
     *  G4: [SP]オフセット無し（p1_is_line完全一致が [SP+imm] を別綴りとして排除）。
     *  G5: 窓直後 g_insbuf[r+4] がZ/Nを読む条件分岐(BEQ/BNE/BLT/BGE)なら非置換。
     *      ★CONT-1: この判定はP2a/P2b/P3が前段で既に g_insbuf を書換え終えた後の
     *        ストリームに対して行われる（P1は後段配置ゆえパス順序上担保）。
     * 走査は既存P2/P3と同一のw/r前詰め方式（設計書§3）。*/
    {
        int w = 0;
        int r = 0;
        while (r < g_insbuf_n) {
            /* 4命令窓が配列末尾を越えないことを先に確認（KY: 越境読み防止）。*/
            if (r + 3 < g_insbuf_n
                && p1_is_line(g_insbuf[r],   "SUBI SP, #2")   /* G2 行1 */
                && p1_is_line(g_insbuf[r+1], "STW  A, [SP]")  /* G3 行2 */
                && p1_is_line(g_insbuf[r+2], "LDW  B, [SP]")  /* G3 行3 */
                && p1_is_line(g_insbuf[r+3], "ADDI SP, #2")   /* G2 行4 */
                /* G5: 窓直後がZ/Nを読む条件分岐なら非置換。r+4が存在する時のみ判定。*/
                && !(r + 4 < g_insbuf_n && p1_next_reads_ZN(g_insbuf[r+4]))) {
                char *rep = strdup("    MOV  B, A");
                if (rep) {                     /* strdup失敗時は元4命令を温存（安全側非置換）*/
                    free(g_insbuf[r]);
                    free(g_insbuf[r+1]);
                    free(g_insbuf[r+2]);
                    free(g_insbuf[r+3]);
                    g_insbuf[w++] = rep;
                    r += 4;
                    continue;
                }
            }
            g_insbuf[w++] = g_insbuf[r];
            r += 1;
        }
        g_insbuf_n = w;
    }
}

/* バッファをflush（必要ならpeephole後）して空にする。関数クローズ時に呼ぶ。 */
static void insbuf_flush(void) {
    /* peepholeは-O1のみ。opt_levelは後段で参照（基盤段階は常に素通し）。 */
    for (int i = 0; i < g_insbuf_n; i++) {
        fprintf(out_fp, "%s\n", g_insbuf[i]);
        free(g_insbuf[i]); g_insbuf[i] = NULL;
    }
    g_insbuf_n = 0; g_insbuf_ovf = 0;
}

/* [ISA2.3] インラインアセンブラ出力
 * asm("命令1 ; 命令2") のセミコロン区切りを各行に展開して emit する
 * strsep は POSIX拡張（Linux+gcc環境で問題なし）*/
static void emit_asm_inline(const char *asmstr) {
    char buf[256];
    strncpy(buf, asmstr, sizeof(buf) - 1);
    buf[sizeof(buf) - 1] = '\0';
    char *p = buf;
    char *tok;
    while ((tok = strsep(&p, ";")) != NULL) {
        /* 前後の空白トリム */
        while (*tok == ' ' || *tok == '\t') tok++;
        char *end = tok + strlen(tok) - 1;
        while (end > tok && (*end == ' ' || *end == '\t')) *end-- = '\0';
        if (*tok != '\0')
            emit("    %s", tok);
    }
}

/* ============================================================
 * struct/union テーブル（v2.11から流用）
 * ============================================================ */
static int struct_find(const char *tag, int is_union) {
    for (int i = 0; i < nstructs; i++)
        if (structs[i].is_union == is_union && strcmp(structs[i].tag, tag) == 0)
            return i;
    return -1;
}
static int struct_find_any(const char *tag) {
    for (int i = 0; i < nstructs; i++)
        if (strcmp(structs[i].tag, tag) == 0)
            return i;
    return -1;
}
static int struct_new(const char *tag, int is_union) {
    if (nstructs >= MAX_STRUCTS) { error("too many struct/union types"); return 0; }
    memset(&structs[nstructs], 0, sizeof(structdef_t));
    strncpy(structs[nstructs].tag, tag, IDENT_LEN-1);
    structs[nstructs].is_union = is_union;
    return nstructs++;
}

/* ============================================================
 * typedef テーブル（v2.11から流用）
 * ============================================================ */
static typedef_t *typedef_find(const char *name) {
    for (int i = 0; i < ntypedefs; i++)
        if (strcmp(typedefs[i].name, name) == 0)
            return &typedefs[i];
    return NULL;
}
static void typedef_add(const char *name, ctype_t type, ctype_t base,
                         int is_ptr, int is_array, int arr_size,
                         int struct_idx, int dim2) {
    if (ntypedefs >= MAX_TYPEDEF) { error("too many typedefs"); return; }
    typedef_t *td = &typedefs[ntypedefs++];
    strncpy(td->name, name, IDENT_LEN-1);
    td->type=type; td->base=base; td->is_ptr=is_ptr;
    td->is_array=is_array; td->arr_size=arr_size;
    td->struct_idx=struct_idx; td->dim2=dim2;
}

/* ============================================================
 * シンボルテーブル（v2.11から流用）
 * ============================================================ */
static sym_t *sym_alloc(void) {
    sym_t *s = calloc(1, sizeof(sym_t));
    if (!s) { perror("sym_alloc"); exit(1); }
    s->dim2=-1; s->struct_idx=-1;
    s->next=sym_table; sym_table=s; sym_count++;
    return s;
}
static sym_t *sym_find(const char *name) {
    for (sym_t *s=sym_table; s; s=s->next)
        if (strcmp(s->name, name)==0) return s;
    return NULL;
}
static void sym_pop_locals(void) {
    sym_t *prev=NULL, *s=sym_table;
    while (s) {
        sym_t *next=s->next;
        if (s->sclass==SC_LOCAL||s->sclass==SC_PARAM) {
            if (prev) prev->next=next; else sym_table=next;
            free(s); sym_count--;
        } else { prev=s; }
        s=next;
    }
}

/* ============================================================
 * 文字列リテラルプール（v2.11から流用）
 * ============================================================ */
static int strlit_add(const char *text, int len) {
    strlit_t *sl=calloc(1,sizeof(strlit_t));
    sl->id=strlit_count++;
    strncpy(sl->text, text, MAX_STR-1);
    sl->len=len;
    sl->next=strlit_list;
    strlit_list=sl;
    return sl->id;
}

/* ============================================================
 * P1: SirNode alloc/free
 * ============================================================ */
static sir_node_t *sir_new(sir_op_t op) {
    sir_node_t *n = calloc(1, sizeof(sir_node_t));
    if (!n) { perror("sir_new"); exit(1); }
    n->op      = op;
    n->lineno  = cur_line;
    n->str_id  = -1;
    n->dim2    = -1;
    n->esz     = 2;
    n->struct_idx = -1;
    n->type    = T_INT;
    n->base    = T_INT;
    return n;
}

static void sir_free(sir_node_t *n) {
    if (!n) return;
    sir_free(n->left);
    sir_free(n->right);
    sir_free(n->extra);
    sir_free(n->r2);
    for (int i=0; i<n->nargs; i++) sir_free(n->args[i]);
    free(n);
}

/* SirNodeのコンストラクタヘルパー */
static sir_node_t *sir_const(int v) {
    sir_node_t *n=sir_new(SIR_CONST); n->ival=v; return n;
}
/* [v2.00] §4.3: float定数。double->Q8.8(int16)変換。type=T_FLOATで識別（is_floatフィールドは設けない）。*/
static int16_t to_fixed(double x) { return (int16_t)(x * 256.0); }
static sir_node_t *sir_fconst(double x) {
    sir_node_t *n=sir_new(SIR_CONST);
    n->ival=(int)to_fixed(x);
    n->type=T_FLOAT; n->base=T_FLOAT;
    return n;
}
static sir_node_t *sir_sym(sym_t *s) {
    sir_node_t *n=sir_new(SIR_SYM); n->sym=s;
    n->type=s->type; n->base=s->base;
    n->is_array=s->is_array;       /* [F1] lvalue判定用 */
    n->struct_idx=s->struct_idx;   /* [F1] struct/union判定用 */
    return n;
}
static sir_node_t *sir_addr(sym_t *s) {
    sir_node_t *n=sir_new(SIR_ADDR); n->sym=s;
    n->type=T_PTR; n->base=s->type; return n;
}
static sir_node_t *sir_binop(sir_op_t op, sir_node_t *l, sir_node_t *r) {
    sir_node_t *n=sir_new(op); n->left=l; n->right=r;
    n->type=l?l->type:T_INT; return n;
}
static sir_node_t *sir_unop(sir_op_t op, sir_node_t *operand) {
    sir_node_t *n=sir_new(op); n->left=operand;
    n->type=operand?operand->type:T_INT; return n;
}
static sir_node_t *sir_nop(void) {
    return sir_new(SIR_NOP);
}

/* [v2.00] §5.1: int->float 変換ノード(I2F)を挿入。既にfloatならそのまま返す。
 * 定数(SIR_CONST/T_INT)の場合はコンパイル時にQ8.8へ畳み込む(<<8)。§5.3のwarningはfold側で。*/
static sir_node_t *wrap_i2f(sir_node_t *n) {
    if (!n) return n;
    if (n->type==T_FLOAT) return n;
    if (n->op==SIR_CONST && n->type!=T_FLOAT) {
        /* コンパイル時 I2F: ival <<= 8（§7.1 定数I2F）。範囲チェックは§5.3でfold時に行う */
        n->ival = (int)(int16_t)(n->ival << 8);
        n->type = T_FLOAT; n->base = T_FLOAT;
        return n;
    }
    sir_node_t *c=sir_new(SIR_I2F); c->left=n;
    c->type=T_FLOAT; c->base=T_FLOAT;
    return c;
}

/* [v2.00] §7.2: 定数畳み込み本体。op を a,b(整数表現,Q8.8 or int) で計算。
 * type==T_FLOAT のとき float(Q8.8)演算、それ以外は整数演算。
 * 0除算はerror、FMULオーバーフローはwarning(§7.2)。ISA非依存の純粋C計算。 */
static int fold_binop_val(sir_op_t op, int a, int b, ctype_t type) {
    if (type==T_FLOAT) {
        switch (op) {
        case SIR_ADD:  return (int16_t)(a + b);
        case SIR_SUB:  return (int16_t)(a - b);
        case SIR_FMUL: {
            int32_t tmp = (int32_t)a * b;
            if (tmp > (int32_t)0x7FFF00 || tmp < -(int32_t)0x800000)
                warning("float overflow in constant FMUL");
            return (int16_t)(tmp >> 8);
        }
        case SIR_FDIV:
            if (b == 0) { error("division by zero"); return 0; }
            return (int16_t)(((int32_t)a << 8) / b);
        default: return 0;
        }
    } else { /* T_INT / T_CHAR */
        switch (op) {
        case SIR_ADD:   return (int16_t)(a + b);
        case SIR_SUB:   return (int16_t)(a - b);
        case SIR_MUL:   return (int16_t)(a * b);
        case SIR_DIV:
            if (b == 0) { error("division by zero"); return 0; }
            return (int16_t)(a / b);
        case SIR_MOD:
            if (b == 0) { error("modulo by zero"); return 0; }
            return (int16_t)(a % b);
        case SIR_AND:   return (int16_t)(a & b);
        case SIR_OR:    return (int16_t)(a | b);
        case SIR_XOR:   return (int16_t)(a ^ b);
        case SIR_SHL:   return (int16_t)(a << b);
        case SIR_SHR:   return (int16_t)((unsigned int)(a & 0xFFFF) >> b); /* 論理 */
        case SIR_SAR:   return (int16_t)((int16_t)a >> b);                 /* 算術 */
        default: return 0;
        }
    }
}

/* 定数畳み込み: 両辺がSIR_CONSTなら計算結果のSIR_CONSTに縮退して返す。
 * 縮退できなければNULL。生成元(binop_promote/sir_binop)から呼ぶ。 */
static int is_const_node(sir_node_t *n){ return n && n->op==SIR_CONST; }
static sir_node_t *try_fold(sir_op_t op, sir_node_t *l, sir_node_t *r, ctype_t rtype) {
    /* [v2.2] §2.5.7: -O0-strictでは定数畳み込みを行わない（回帰運用でv1.04相当を保つ）。 */
    if (g_opt_level == OPT_O0_STRICT) return NULL;
    if (!is_const_node(l) || !is_const_node(r)) return NULL;
    int v = fold_binop_val(op, l->ival, r->ival, rtype);
    sir_node_t *n = sir_new(SIR_CONST);
    n->ival = v; n->type = rtype; n->base = rtype;
    sir_free(l); sir_free(r);
    return n;
}

/* [v2.00] §5.1: 二項演算の型昇格。一方がfloatなら他方をI2Fで昇格し、
 * 乗算->SIR_FMUL / 除算->SIR_FDIV / 加減算->SIR_ADD|SUB(結果T_FLOAT) を生成。
 * 両方intなら従来通り int_op をそのまま使う。 */
/* [v2.3 Step9] O1代数簡約用ヘルパ群 ============================ */
/* ノードが副作用(関数呼び出し・代入)を含むか後順再帰で判定。
 * 簡約で「捨てられる側」にこれがあれば簡約しない(副作用保護)。 */
static int has_side_effect(sir_node_t *n) {
    int i;
    if (!n) return 0;
    switch (n->op) {
        case SIR_CALL:                       /* 関数呼び出し */
        case SIR_STORE:                      /* 代入 */
        case SIR_ASGN_OP:                    /* 複合代入 */
            return 1;
        default: break;
    }
    if (has_side_effect(n->left))  return 1;
    if (has_side_effect(n->right)) return 1;
    if (has_side_effect(n->extra)) return 1;
    if (has_side_effect(n->r2))    return 1;
    for (i=0;i<n->nargs;i++) if (has_side_effect(n->args[i])) return 1;
    return 0;
}
/* 定数値判定: nがSIR_CONSTでival==vなら真 */
static int is_const_val(sir_node_t *n, int v){ return n && n->op==SIR_CONST && n->ival==v; }
/* ゼロ判定(int 0 / float 0.0=ival0 共通: Q8.8の0.0もival==0) */
static int is_zero_node(sir_node_t *n){ return is_const_val(n,0); }
/* make_const: 指定型の定数ノード生成 */
static sir_node_t *make_const_node(int v, ctype_t t){
    sir_node_t *n=sir_new(SIR_CONST); n->ival=v; n->type=t; n->base=t; return n;
}
/* same_simple_sym: 両者が同一の単純シンボル参照(SIR_SYM, 副作用なし)か。
 * 保守的判定: 複雑な式の構造比較は誤判定リスクがあるため SIR_SYM 同名のみ真。 */
static int same_simple_sym(sir_node_t *a, sir_node_t *b){
    if (!a||!b) return 0;
    if (a->op!=SIR_SYM || b->op!=SIR_SYM) return 0;
    return a->sym && a->sym==b->sym;
}
/* O1代数簡約。縮退できればノードを返す。不可ならNULL。
 * 捨てる側に副作用があれば簡約しない(C意味論保護)。 */
static sir_node_t *fold_algebraic(sir_op_t op, sir_node_t *L, sir_node_t *R) {
    if (g_opt_level != OPT_O1) return NULL;
    /* x * 0 / x * 0.0 -> 0  (Lを捨てるのでLの副作用を保護) */
    if ((op==SIR_MUL||op==SIR_FMUL) && is_zero_node(R) && !has_side_effect(L)) {
        ctype_t t = (op==SIR_FMUL)?T_FLOAT:L->type;
        sir_free(L); sir_free(R);
        return make_const_node(0, t);
    }
    /* x * 1.0 (FMUL, R=256=Q8.8の1.0) -> x  (Rを捨てる, Rは定数で副作用なし) */
    if (op==SIR_FMUL && is_const_val(R,256)) { sir_free(R); return L; }
    /* x / 1.0 (FDIV, R=256) -> x */
    if (op==SIR_FDIV && is_const_val(R,256)) { sir_free(R); return L; }
    /* x + 0 / x - 0 -> x  (Rを捨てる) */
    if ((op==SIR_ADD||op==SIR_SUB) && is_zero_node(R)) { sir_free(R); return L; }
    /* x - x -> 0  (両辺同一単純シンボルかつ副作用なし) */
    if (op==SIR_SUB && same_simple_sym(L,R)) {
        ctype_t t=L->type; sir_free(L); sir_free(R);
        return make_const_node(0, t);
    }
    return NULL;
}
/* ============================================================== */

static sir_node_t *binop_promote(sir_op_t int_op, sir_node_t *l, sir_node_t *r) {
    int lf = l && l->type==T_FLOAT;
    int rf = r && r->type==T_FLOAT;
    if (!lf && !rf) {
        /* [v2.00] §7.1: int定数同士はコンパイル時畳み込み(O0常時) */
        sir_node_t *f = try_fold(int_op, l, r, T_INT);
        if (f) return f;
        sir_node_t *a = fold_algebraic(int_op, l, r);  /* [v2.3 Step9] O1代数簡約 */
        if (a) return a;
        return sir_binop(int_op, l, r);  /* int同士: 従来動作 */
    }
    /* どちらかfloat -> 両辺floatへ昇格 */
    l = wrap_i2f(l);
    r = wrap_i2f(r);
    sir_op_t fop;
    switch (int_op) {
        case SIR_MUL: fop=SIR_FMUL; break;
        case SIR_DIV: fop=SIR_FDIV; break;
        case SIR_MOD:
            error("float operand not allowed for '%%'");
            fop=SIR_FMUL; break;  /* エラー後の暫定 */
        default:      fop=int_op;  break;  /* ADD/SUB: Q8.8は整数加減算と同一 */
    }
    /* [v2.00] §7.1: float定数同士もコンパイル時畳み込み(O0常時)。
     * wrap_i2fで両辺T_FLOAT化済みなので、定数ならQ8.8で計算される。 */
    sir_node_t *f = try_fold(fop, l, r, T_FLOAT);
    if (f) return f;
    sir_node_t *a = fold_algebraic(fop, l, r);  /* [v2.3 Step9] O1代数簡約 */
    if (a) return a;
    sir_node_t *n=sir_new(fop); n->left=l; n->right=r;
    n->type=T_FLOAT; n->base=T_FLOAT;
    return n;
}

/* ============================================================
 * 字句解析（v2.11から流用）
 * ============================================================ */
#define TOK_EOF      "\x01EOF"
#define TOK_NUM      "\x01NUM"
#define TOK_FNUM     "\x01FNUM"   /* [v2.00] float数値リテラル(1.5等)。cur_fvalに値を保持 */
#define TOK_IDENT    "\x01ID"
#define TOK_STR      "\x01STR"
#define TOK_CHAR_LIT "\x01CHAR"

static int next_char(void) {
    cur_char=fgetc(src_fp);
    if (cur_char=='\n') cur_line++;
    return cur_char;
}
static void skip_ws(void) {
    for (;;) {
        while (cur_char!=EOF && isspace((unsigned char)cur_char)) next_char();
        if (cur_char=='/') {
            int nc=fgetc(src_fp);
            if (nc=='/') { while (cur_char!=EOF&&cur_char!='\n') next_char(); continue; }
            else if (nc=='*') {
                next_char();
                while (cur_char!=EOF) {
                    if (cur_char=='*') { next_char(); if (cur_char=='/'){next_char();break;} }
                    else next_char();
                }
                continue;
            } else { ungetc(nc,src_fp); }
        }
        break;
    }
}

static void push_tok(const char *tok, int ival) {
    if (pb_count>=PUSHBACK_DEPTH) { error("pushback overflow"); return; }
    strncpy(pb_str[pb_count], tok, MAX_STR-1);
    pb_ival[pb_count]=ival;
    strncpy(pb_sval[pb_count], cur_str, MAX_STR-1);
    pb_count++;
}

static const char *next_tok(void) {
    if (pb_count>0) {
        pb_count--;
        strncpy(cur_tok, pb_str[pb_count], MAX_STR-1);
        cur_ival=pb_ival[pb_count];
        strncpy(cur_str, pb_sval[pb_count], MAX_STR-1);
        return cur_tok;
    }
    skip_ws();
    if (cur_char==EOF) { strcpy(cur_tok,TOK_EOF); return cur_tok; }

    /* 数値 */
    if (isdigit((unsigned char)cur_char)||
        (cur_char=='0'&&(fgetc(src_fp)=='x'||ungetc(fgetc(src_fp),src_fp)))) {
        char buf[64]; int i=0;
        if (cur_char=='0') {
            buf[i++]='0'; next_char();
            if (cur_char=='x'||cur_char=='X') {
                buf[i++]=(char)cur_char; next_char();
                while (isxdigit((unsigned char)cur_char)&&i<62)
                    { buf[i++]=(char)cur_char; next_char(); }
            } else {
                while (isdigit((unsigned char)cur_char)&&i<62)
                    { buf[i++]=(char)cur_char; next_char(); }
            }
        } else {
            while (isdigit((unsigned char)cur_char)&&i<62)
                { buf[i++]=(char)cur_char; next_char(); }
        }
        buf[i]='\0';
        /* [v2.00] float リテラル: 整数部の直後に '.' が続けば小数として読む。
         * 16進(0x..)パスはここに来ない(上のif分岐)。 'f'/'F'サフィックスも許容。 */
        if (cur_char=='.') {
            buf[i++]='.'; next_char();
            while (isdigit((unsigned char)cur_char)&&i<62)
                { buf[i++]=(char)cur_char; next_char(); }
            buf[i]='\0';
            if (cur_char=='f'||cur_char=='F') next_char();
            cur_fval=strtod(buf,NULL);
            strcpy(cur_tok,TOK_FNUM); return cur_tok;
        }
        if (cur_char=='u'||cur_char=='U'||cur_char=='l'||cur_char=='L') next_char();
        cur_ival=(int)strtol(buf,NULL,0);
        strcpy(cur_tok,TOK_NUM); return cur_tok;
    }

    /* 識別子・キーワード */
    if (isalpha((unsigned char)cur_char)||cur_char=='_') {
        int i=0;
        while ((isalnum((unsigned char)cur_char)||cur_char=='_')&&i<MAX_STR-1)
            { cur_tok[i++]=(char)cur_char; next_char(); }
        cur_tok[i]='\0';
        return cur_tok;
    }

    /* 文字リテラル */
    if (cur_char=='\'') {
        next_char();
        if (cur_char=='\\') {
            next_char();
            switch(cur_char) {
                case 'n': cur_ival='\n'; break;
                case 't': cur_ival='\t'; break;
                case 'r': cur_ival='\r'; break;
                case '0': cur_ival=0; break;
                case '\\': cur_ival='\\'; break;
                case '\'': cur_ival='\''; break;
                default:  cur_ival=cur_char; break;
            }
        } else { cur_ival=cur_char; }
        next_char(); /* 文字の次 */
        if (cur_char=='\'') next_char(); /* 閉じクォート */
        strcpy(cur_tok,TOK_CHAR_LIT); return cur_tok;
    }

    /* 文字列リテラル */
    if (cur_char=='"') {
        next_char();
        int i=0;
        while (cur_char!='"'&&cur_char!=EOF&&i<MAX_STR-2) {
            if (cur_char=='\\') {
                next_char();
                switch(cur_char){
                    case 'n':  cur_str[i++]='\n'; break;
                    case 't':  cur_str[i++]='\t'; break;
                    case 'r':  cur_str[i++]='\r'; break;
                    case '0':  cur_str[i++]='\0'; break;
                    case '\\': cur_str[i++]='\\'; break;
                    case '"':  cur_str[i++]='"';  break;
                    default:   cur_str[i++]=(char)cur_char; break;
                }
            } else { cur_str[i++]=(char)cur_char; }
            next_char();
        }
        cur_str[i]='\0'; cur_ival=i;
        if (cur_char=='"') next_char();
        strcpy(cur_tok,TOK_STR); return cur_tok;
    }

    /* 2文字演算子 */
    char c=(char)cur_char; next_char();
    cur_tok[0]=c; cur_tok[1]='\0';
    char c2=(char)cur_char;
    if ((c=='='&&c2=='=')||(c=='!'&&c2=='=')||(c=='<'&&c2=='=')||
        (c=='>'&&c2=='=')||(c=='&'&&c2=='&')||(c=='|'&&c2=='|')||
        (c=='+'&&c2=='+')||(c=='-'&&c2=='-')||(c=='<'&&c2=='<')||
        (c=='>'&&c2=='>')||(c=='-'&&c2=='>')||
        (c=='+'&&c2=='=')||(c=='-'&&c2=='=')||(c=='*'&&c2=='=')||
        (c=='/'&&c2=='=')||(c=='%'&&c2=='=')||(c=='&'&&c2=='=')||
        (c=='|'&&c2=='=')||(c=='^'&&c2=='=')) {
        cur_tok[1]=c2; cur_tok[2]='\0'; next_char();
    }
    return cur_tok;
}

static void expect(const char *tok) {
    const char *t=next_tok();
    if (strcmp(t,tok)!=0)
        error("expected '%s', got '%s'", tok, t);
}

/* ============================================================
 * sizeof計算（v2.11から流用）
 * ============================================================ */
static int sizeof_type(ctype_t type, ctype_t base, int is_ptr,
                        int is_array, int arr_size, int struct_idx, int dim2) {
    if (is_ptr) return 2;
    if (is_array) {
        int esz;
        if (type==T_STRUCT||type==T_UNION)
            esz=(struct_idx>=0)?structs[struct_idx].total_size:2;
        else esz=(base==T_CHAR)?1:2;
        if (dim2>0) return arr_size*dim2*esz;
        return arr_size*esz;
    }
    if (type==T_STRUCT||type==T_UNION)
        return (struct_idx>=0)?structs[struct_idx].total_size:2;
    if (type==T_CHAR) return 1;
    /* [v2.00] §3.2: float=Q8.8(int16_tと同サイズ)=2。bool/uintは将来用に2。 */
    if (type==T_FLOAT) return 2;
    if (type==T_BOOL)  return 2;  /* 将来用 */
    if (type==T_UINT)  return 2;  /* 将来用 */
    return 2;
}

/* ============================================================
 * 型情報解析（v2.11から流用）
 * ============================================================ */
typedef struct {
    ctype_t type, base;
    int is_ptr, is_array, arr_size, struct_idx, dim2;
} typeinfo_t;

static int try_parse_type(const char *t, typeinfo_t *ti) {
    memset(ti,0,sizeof(typeinfo_t));
    ti->struct_idx=-1; ti->dim2=-1;
    ti->type=T_INT; ti->base=T_INT;

    if (strcmp(t,"int")==0)    { ti->type=T_INT;  ti->base=T_INT;  return 1; }
    if (strcmp(t,"char")==0)   { ti->type=T_CHAR; ti->base=T_CHAR; return 1; }
    /* [v2.00] §3.1: float型キーワード。Q8.8固定小数・base自身。 */
    if (strcmp(t,"float")==0)  { ti->type=T_FLOAT; ti->base=T_FLOAT; return 1; }
    if (strcmp(t,"void")==0)   { ti->type=T_VOID; ti->base=T_VOID; return 1; }
    if (strcmp(t,"long")==0)   {
        const char *nx=next_tok();
        if (strcmp(nx,"int")!=0) push_tok(nx,cur_ival);
        ti->type=T_INT; ti->base=T_INT; return 1;
    }
    if (strcmp(t,"short")==0)  { ti->type=T_INT;  ti->base=T_INT;  return 1; }

    /* enum: 整数型として扱う。{...}があれば値を登録して読み飛ばす */
    if (strcmp(t,"enum")==0) {
        const char *tag=next_tok();
        const char *nx;
        if (strcmp(tag,"{")==0) {
            nx=tag; /* 無名enum: {を戻さずそのまま処理 */
        } else {
            nx=next_tok(); /* タグ名の次を読む */
        }
        if (strcmp(nx,"{")==0) {
            /* 列挙値を登録して読み飛ばす */
            int val=0;
            for (;;) {
                const char *en=next_tok();
                if (strcmp(en,"}")==0||strcmp(en,TOK_EOF)==0) break;
                if (strcmp(en,",")==0) continue;
                char ename[IDENT_LEN]; strncpy(ename,en,IDENT_LEN-1);
                const char *eq=next_tok();
                if (strcmp(eq,"=")==0) {
                    const char *ev=next_tok();
                    if (strcmp(ev,TOK_NUM)==0) val=cur_ival;
                    else push_tok(ev,cur_ival);
                    eq=next_tok(); /* , or } */
                    push_tok(eq,cur_ival);
                } else push_tok(eq,cur_ival);
                sym_t *es=sym_find(ename);
                if (!es) es=sym_alloc();
                strncpy(es->name,ename,IDENT_LEN-1);
                es->sclass=SC_ENUM_VAL; es->ival=val++;
            }
        } else {
            push_tok(nx,cur_ival); /* { なければ戻す */
        }
        ti->type=T_INT; ti->base=T_INT; return 1;
    }

    if (strcmp(t,"struct")==0||strcmp(t,"union")==0) {
        int is_union=(strcmp(t,"union")==0);
        const char *tag=next_tok();
        int sidx;
        if (strcmp(tag,"{")==0) {
            push_tok(tag,cur_ival);
            sidx=struct_new("",is_union);
        } else {
            sidx=struct_find(tag,is_union);
            if (sidx<0) sidx=struct_new(tag,is_union);
        }
        ti->type=is_union?T_UNION:T_STRUCT;
        ti->base=ti->type; ti->struct_idx=sidx; return 1;
    }

    typedef_t *td=typedef_find(t);
    if (td) {
        ti->type=td->type; ti->base=td->base; ti->is_ptr=td->is_ptr;
        ti->is_array=td->is_array; ti->arr_size=td->arr_size;
        ti->struct_idx=td->struct_idx; ti->dim2=td->dim2; return 1;
    }

    { sym_t *ds=sym_find(t); if (ds&&ds->sclass==SC_DEFINE) return 0; }
    return 0;
}

/* ============================================================
 * プリプロセッサ処理（v2.11から流用）
 * ============================================================ */
static void skip_to_endif(void);
static void skip_to_endif_only(void);

static void handle_define(void) {
    /* 行内空白のみスキップ（改行を越えない）*/
    while (cur_char==' '||cur_char=='\t') next_char();
    char name[IDENT_LEN]; int i=0;
    while ((isalnum((unsigned char)cur_char)||cur_char=='_')&&i<IDENT_LEN-1)
        { name[i++]=(char)cur_char; next_char(); }
    name[i]='\0';

    /* 既存シンボル検索 */
    sym_t *existing=sym_find(name);

    /* 引数付きマクロ: 行末まで読み飛ばして空マクロとして登録 */
    if (cur_char=='(') {
        while (cur_char!='\n'&&cur_char!=EOF) next_char();
        if (existing) return;
        sym_t *s=sym_alloc();
        strncpy(s->name,name,IDENT_LEN-1);
        s->sclass=SC_DEFINE; s->defval[0]='\0';
        return;
    }
    /* 行内空白のみスキップ（改行を越えない）*/
    while (cur_char==' '||cur_char=='\t') next_char();

    char val[MAX_STR]; int vi=0;
    while (cur_char!='\n'&&cur_char!=EOF&&vi<MAX_STR-1)
        { val[vi++]=(char)cur_char; next_char(); }
    /* 末尾の空白をトリム */
    while (vi>0&&(val[vi-1]==' '||val[vi-1]=='\t')) vi--;
    val[vi]='\0';

    if (existing&&existing->sclass==SC_DEFINE) {
        strncpy(existing->defval,val,MAX_STR-1); return;
    }
    sym_t *s=sym_alloc();
    strncpy(s->name,name,IDENT_LEN-1);
    s->sclass=SC_DEFINE;
    strncpy(s->defval,val,MAX_STR-1);
}

static void skip_to_endif(void) {
    int depth=1;
    while (cur_char!=EOF) {
        if (cur_char=='#') {
            next_char(); skip_ws();
            char d[16]; int i=0;
            while (isalpha((unsigned char)cur_char)&&i<15)
                { d[i++]=(char)cur_char; next_char(); }
            d[i]='\0';
            if (strcmp(d,"ifdef")==0||strcmp(d,"ifndef")==0||strcmp(d,"if")==0) depth++;
            else if (strcmp(d,"endif")==0) {
                depth--;
                if (depth==0) { while(cur_char!='\n'&&cur_char!=EOF) next_char(); return; }
            } else if (strcmp(d,"else")==0&&depth==1) {
                while(cur_char!='\n'&&cur_char!=EOF) next_char();
                g_stopped_at_else=1;  /* v2.11準拠: elseブランチへ移行 */
                return;
            }
        }
        while (cur_char!='\n'&&cur_char!=EOF) next_char();
        if (cur_char=='\n') next_char();
    }
}

static void skip_to_endif_only(void) {
    int depth=1;
    while (cur_char!=EOF) {
        if (cur_char=='#') {
            next_char(); skip_ws();
            char d[16]; int i=0;
            while (isalpha((unsigned char)cur_char)&&i<15)
                { d[i++]=(char)cur_char; next_char(); }
            d[i]='\0';
            if (strcmp(d,"ifdef")==0||strcmp(d,"ifndef")==0||strcmp(d,"if")==0) depth++;
            else if (strcmp(d,"endif")==0) {
                depth--;
                if (depth==0) { while(cur_char!='\n'&&cur_char!=EOF) next_char(); return; }
            }
        }
        while (cur_char!='\n'&&cur_char!=EOF) next_char();
        if (cur_char=='\n') next_char();
    }
}

static void handle_ifdef(int is_ifndef) {
    skip_ws();
    char name[IDENT_LEN]; int i=0;
    while ((isalnum((unsigned char)cur_char)||cur_char=='_')&&i<IDENT_LEN-1)
        { name[i++]=(char)cur_char; next_char(); }
    name[i]='\0';
    while (cur_char!='\n'&&cur_char!=EOF) next_char();
    sym_t *def=sym_find(name);
    int defined=(def&&def->sclass==SC_DEFINE);
    int take=(is_ifndef?!defined:defined);
    g_stopped_at_else=0;
    if (!take) {
        /* 偽ブランチ: #elseまでスキップ → g_stopped_at_else=1にしてelse以降を出力 */
        skip_to_endif();
        /* skip_to_endifがg_stopped_at_else=1をセット済み（#elseがある場合）*/
    } else {
        /* 真ブランチを出力し、後で#elseを見たらskip_to_endif_onlyでスキップ */
        g_stopped_at_else=1;
    }
}

static void handle_if_directive(void) {
    /* #if 0 / #if 1 の簡易処理 */
    skip_ws();
    char val[64]; int i=0;
    while (cur_char!='\n'&&cur_char!=EOF&&i<63)
        { val[i++]=(char)cur_char; next_char(); }
    val[i]='\0';
    int v=(int)strtol(val,NULL,0);
    g_stopped_at_else=0;
    if (!v) {
        skip_to_endif();
        /* skip_to_endifがg_stopped_at_else=1をセット済み（#elseがある場合）*/
    } else {
        g_stopped_at_else=1;
    }
}

/* ============================================================
 * struct本体解析（v2.11から流用）
 * ============================================================ */
static int find_member(int sidx, const char *name, member_t **out_mem) {
    if (sidx<0||sidx>=nstructs) return -1;
    for (int i=0; i<structs[sidx].nmembers; i++) {
        if (strcmp(structs[sidx].members[i].name,name)==0) {
            *out_mem=&structs[sidx].members[i]; return i;
        }
    }
    return -1;
}

static void parse_struct_body(int sidx) {
    expect("{");
    structdef_t *sd=&structs[sidx];
    int offset=0, max_size=0;

    while (1) {
        const char *t=next_tok();
        if (strcmp(t,"}")==0||strcmp(t,TOK_EOF)==0) break;

        typeinfo_t ti;
        if (!try_parse_type(t,&ti)) {
            error("expected type in struct member, got '%s'", t);
            while (strcmp(next_tok(),";")!=0&&strcmp(cur_tok,TOK_EOF)!=0);
            continue;
        }

        /* struct/union本体定義が続く場合 */
        if (ti.type==T_STRUCT||ti.type==T_UNION) {
            int sidx2=ti.struct_idx;
            const char *nx=next_tok();
            if (strcmp(nx,"{")==0) {
                push_tok(nx,cur_ival);
                if (sidx2<0) { sidx2=struct_new("",ti.type==T_UNION); ti.struct_idx=sidx2; }
                parse_struct_body(sidx2);
                nx=next_tok();
            }
            if (strcmp(nx,";")==0) {
                /* 無名struct/union（メンバ名なし）*/
                if (sidx2>=0) {
                    int msz=structs[sidx2].total_size;
                    if (msz&1) msz++;
                    if (sd->nmembers<MAX_STRUCT_MEM) {
                        member_t *m=&sd->members[sd->nmembers++];
                        snprintf(m->name,IDENT_LEN,"__anon_%d",sd->nmembers);
                        m->type=ti.type; m->base=ti.base;
                        m->struct_idx=sidx2; m->size=msz;
                        m->offset=sd->is_union?0:offset;
                    }
                    if (sd->is_union){if(msz>max_size)max_size=msz;}
                    else offset+=msz;
                }
                continue;
            }
            push_tok(nx,cur_ival);
            ti.struct_idx=sidx2;
        }

        /* メンバ宣言ループ（同じ型の複数メンバ: int a, b, c;）*/
        int sep_is_semicolon=0;
        for (;;) {
            int is_ptr=ti.is_ptr, is_array=ti.is_array;
            int arr_size=ti.arr_size, dim2=ti.dim2;
            int sidx2=ti.struct_idx;
            ctype_t type=ti.type, base=ti.base;

            const char *nm=next_tok();
            while (strcmp(nm,"*")==0){is_ptr=1;nm=next_tok();}

            if (strcmp(nm,";")==0||strcmp(nm,TOK_EOF)==0){sep_is_semicolon=1;break;}

            char mname[IDENT_LEN]; strncpy(mname,nm,IDENT_LEN-1);

            /* 配列サイズ */
            const char *nx=next_tok();
            if (strcmp(nx,"[")==0) {
                is_array=1;
                const char *ns=next_tok();
                if (strcmp(ns,TOK_NUM)==0){arr_size=cur_ival;next_tok();}
                nx=next_tok();
                if (strcmp(nx,"[")==0) {
                    const char *ns2=next_tok();
                    if (strcmp(ns2,TOK_NUM)==0){dim2=cur_ival;next_tok();}
                    nx=next_tok();
                }
            }

            /* バイトサイズ計算 */
            int msz;
            if ((type==T_STRUCT||type==T_UNION)&&!is_ptr) {
                msz=(sidx2>=0)?structs[sidx2].total_size:2;
                if(msz&1)msz++;
            } else if (is_ptr) {
                msz=2;
            } else {
                msz=(base==T_CHAR)?1:2;
            }
            if (is_array) msz *= (dim2>0)?arr_size*dim2:arr_size;
            if (msz&1) msz++;

            if (sd->nmembers<MAX_STRUCT_MEM) {
                member_t *m=&sd->members[sd->nmembers++];
                strncpy(m->name,mname,IDENT_LEN-1);
                m->type=is_ptr?T_PTR:(is_array?T_ARRAY:type);
                m->base=base; m->struct_idx=sidx2;
                m->is_ptr=is_ptr; m->is_array=is_array;
                m->arr_size=arr_size; m->dim2=dim2;
                m->size=msz;
                m->offset=sd->is_union?0:offset;
            }
            if (sd->is_union){if(msz>max_size)max_size=msz;}
            else offset+=msz;

            if (strcmp(nx,";")==0){sep_is_semicolon=1;break;}
            if (strcmp(nx,",")==0) continue;
            push_tok(nx,cur_ival); break;
        }
        if (!sep_is_semicolon) expect(";");
    }

    sd->total_size=sd->is_union?max_size:offset;
    if (sd->total_size==0) sd->total_size=2;
    if (sd->total_size&1) sd->total_size++;
}

/* ============================================================
 * P2: フロントエンド parse_expr系（SirNode*返却版）
 * ============================================================ */
static sir_node_t *parse_expr(void);
static sir_node_t *parse_assign(void);
static sir_node_t *parse_logor(void);
static sir_node_t *parse_logand(void);
static sir_node_t *parse_bitor(void);
static sir_node_t *parse_bitxor(void);
static sir_node_t *parse_bitand(void);
static sir_node_t *parse_equality(void);
static sir_node_t *parse_relational(void);
static sir_node_t *parse_shift(void);
static sir_node_t *parse_add(void);
static sir_node_t *parse_mul(void);
static sir_node_t *parse_unary(void);
static sir_node_t *parse_postfix(void);
static sir_node_t *parse_primary(void);

/* parse_stmt前方宣言 */
static void parse_stmt(void);
static void parse_block(void);

/* ------------------------------------------------------------
 * parse_primary: リテラル・変数・関数呼び出し
 * ------------------------------------------------------------ */
static sir_node_t *parse_primary(void) {
    const char *t=next_tok();

    /* 数値定数 */
    if (strcmp(t,TOK_NUM)==0)      { return sir_const(cur_ival); }
    if (strcmp(t,TOK_FNUM)==0)     { return sir_fconst(cur_fval); }  /* [v2.00] float定数 */
    if (strcmp(t,TOK_CHAR_LIT)==0) { return sir_const(cur_ival); }

    /* 文字列リテラル */
    if (strcmp(t,TOK_STR)==0) {
        int id=strlit_add(cur_str,cur_ival);
        sir_node_t *n=sir_new(SIR_STRLIT);
        n->str_id=id; n->type=T_PTR; n->base=T_CHAR;
        return n;
    }

    /* sizeof */
    if (strcmp(t,"sizeof")==0) {
        expect("(");
        const char *inner=next_tok();
        typeinfo_t ti;
        int sz=2;
        if (try_parse_type(inner,&ti)) {
            const char *nx=next_tok();
            int ip=ti.is_ptr, ia=0, as=0, d2=-1, si=ti.struct_idx;
            while (strcmp(nx,"*")==0){ip=1;nx=next_tok();}
            if (strcmp(nx,"[")==0){ia=1;const char *ns=next_tok();if(strcmp(ns,TOK_NUM)==0)as=cur_ival;expect("]");nx=next_tok();}
            if (strcmp(nx,")")!=0) push_tok(nx,cur_ival);
            sz=sizeof_type(ti.type,ti.base,ip,ia,as,si,d2);
        } else {
            sym_t *s=sym_find(inner);
            if (s) sz=sizeof_type(s->type,s->base,(s->type==T_PTR),s->is_array,s->size,s->struct_idx,s->dim2);
            expect(")");
        }
        return sir_const(sz);
    }

    /* 括弧式 or キャスト */
    if (strcmp(t,"(")==0) {
        const char *inner=next_tok();
        typeinfo_t ti;
        if (try_parse_type(inner,&ti)) {
            const char *nx=next_tok();
            while (strcmp(nx,"*")==0) nx=next_tok();
            if (strcmp(nx,")")!=0) push_tok(nx,cur_ival);
            sir_node_t *operand=parse_unary();
            /* [v2.00] §5.1: float絡みのキャストはI2F/F2Iノードを挿入する。
             *   (float)int_expr  -> SIR_I2F   (int->float)
             *   (int)float_expr  -> SIR_F2I   (float->int)
             *   それ以外(同型・ポインタ等)は従来通りSIR_CAST。 */
            int to_f   = (ti.type==T_FLOAT) && !ti.is_ptr;
            int from_f = operand && operand->type==T_FLOAT;
            if (to_f && !from_f) {
                /* int->float */
                sir_node_t *n=wrap_i2f(operand);  /* 定数なら畳み込み、非定数はI2Fノード */
                return n;
            }
            if (!to_f && from_f && (ti.type==T_INT||ti.type==T_CHAR) && !ti.is_ptr) {
                /* float->int: F2Iノード（定数は§7でfold） */
                sir_node_t *n=sir_new(SIR_F2I); n->left=operand;
                n->type=ti.type; n->base=ti.base;
                return n;
            }
            sir_node_t *n=sir_new(SIR_CAST);
            n->left=operand; n->type=ti.type; n->base=ti.base; return n;
        }
        push_tok(inner,cur_ival);
        sir_node_t *n=parse_expr();
        expect(")");
        return n;
    }

    /* 識別子 */
    if (isalpha((unsigned char)t[0])||t[0]=='_') {
        char name[IDENT_LEN]; strncpy(name,t,IDENT_LEN-1);
        sym_t *def=sym_find(name);

        /* #define 展開 */
        if (def&&def->sclass==SC_DEFINE) {
            char *endp;
            long v=strtol(def->defval,&endp,0);
            if (endp!=def->defval&&*endp=='\0') return sir_const((int)v);
            if (def->defval[0]=='\0') return sir_nop();
            sym_t *def2=sym_find(def->defval);
            if (def2&&def2->sclass==SC_DEFINE) {
                long v2=strtol(def2->defval,NULL,0);
                return sir_const((int)v2);
            }
            return sir_const((int)v);
        }

        /* ENUM値 */
        if (def&&def->sclass==SC_ENUM_VAL) return sir_const(def->ival);

        /* 関数呼び出し */
        const char *peek=next_tok();
        if (strcmp(peek,"(")==0) {
            sir_node_t *cn=sir_new(SIR_CALL);
            strncpy(cn->fname,name,IDENT_LEN-1);
            /* [FIX 2026-06-25] 関数戻り値型を関数シンボルから引く。
               旧: 無条件T_INT固定→float返し関数でwrap_i2fが二重I2F昇格しバグ。
               未定義(前方宣言なし)の場合のみT_INTフォールバック。 */
            {
                sym_t *cfs=sym_find(name);
                if (cfs && cfs->sclass==SC_FUNC) {
                    cn->type = cfs->type;
                    cn->base = cfs->base;
                } else {
                    cn->type = T_INT; cn->base = T_INT;
                }
            }
            /* 引数リスト */
            const char *first=next_tok();
            if (strcmp(first,")")!=0) {
                push_tok(first,cur_ival);
                for (;;) {
                    if (cn->nargs>=SIR_MAX_ARGS) { error("too many args"); break; }
                    cn->args[cn->nargs++]=parse_assign();
                    const char *sep=next_tok();
                    if (strcmp(sep,")")==0) break;
                    if (strcmp(sep,",")!=0) { error("expected ',' in arg list"); break; }
                }
            }
            return cn;
        }
        push_tok(peek,cur_ival);

        /* 変数参照 */
        sym_t *s=sym_find(name);
        if (!s) { error("undefined symbol: '%s'", name); return sir_const(0); }
        return sir_sym(s);
    }

    error("unexpected token in primary: '%s'", t);
    return sir_const(0);
}

/* ------------------------------------------------------------
 * parse_postfix: 後置演算子・配列・メンバアクセス
 * ------------------------------------------------------------ */
static sir_node_t *parse_postfix(void) {
    sir_node_t *n=parse_primary();

    for (;;) {
        const char *op=next_tok();

        /* 後置 ++ / -- */
        if (strcmp(op,"++")==0) {
            sir_node_t *r=sir_new(SIR_POST_INC);
            r->left=n; r->type=n->type; r->base=n->base; n=r; continue;
        }
        if (strcmp(op,"--")==0) {
            sir_node_t *r=sir_new(SIR_POST_DEC);
            r->left=n; r->type=n->type; r->base=n->base; n=r; continue;
        }

        /* 配列添字 [ ] */
        if (strcmp(op,"[")==0) {
            sir_node_t *idx=parse_expr();
            expect("]");

            /* 要素サイズ・型決定 */
            int esz=2;
            ctype_t etype=T_INT, ebase=T_INT;
            int sidx=-1;
            if (n->sym) {
                sym_t *s=n->sym;
                sidx=s->struct_idx;
                if (s->base==T_STRUCT||s->base==T_UNION) {
                    esz=(sidx>=0)?structs[sidx].total_size:2;
                    if(esz&1)esz++;
                    etype=s->base; ebase=s->base;
                } else {
                    esz=(s->base==T_CHAR)?1:2;
                    etype=s->base; ebase=s->base;
                }
            } else if (n->type==T_ARRAY) {
                /* [F2] SIR_MEMBERの配列メンバ: base から esz を決定 */
                esz=(n->base==T_CHAR)?1:2;
                etype=n->base; ebase=n->base;
                sidx=n->struct_idx;
            } else if (n->type==T_PTR) {
                esz=2; etype=n->base; ebase=n->base;
            }

            /* 2次元配列チェック */
            const char *nx2=next_tok();
            if (strcmp(nx2,"[")==0 && n->sym && n->sym->dim2>0) {
                sir_node_t *idx2=parse_expr();
                expect("]");
                sir_node_t *r=sir_new(SIR_INDEX2D);
                if (n->sym->sclass==SC_PARAM)
                    r->left=sir_sym(n->sym);  /* パラメータ: ポインタ値 */
                else
                    r->left=sir_addr(n->sym); /* 通常: アドレス */
                r->right=idx;             /* 行インデックス */
                r->r2=idx2;               /* 列インデックス */
                r->dim2=n->sym->dim2;
                r->esz=esz;
                r->type=etype; r->base=ebase;
                r->struct_idx=sidx;
                sir_free(n);
                n=r; continue;
            }
            push_tok(nx2,cur_ival);

            /* 1次元配列 */
            sir_node_t *r=sir_new(SIR_INDEX);
            if (n->sym) {
                if (n->sym->sclass==SC_PARAM) {
                    /* パラメータ配列: ポインタ値をロード（sir_sym） */
                    r->left=sir_sym(n->sym);
                } else {
                    r->left=sir_addr(n->sym);
                }
            } else { r->left=n; n=NULL; }
            r->right=idx;
            r->esz=esz;
            r->type=etype; r->base=ebase;
            r->struct_idx=sidx;
            if (n) sir_free(n);
            n=r; continue;
        }

        /* メンバアクセス . / -> */
        if (strcmp(op,".")==0 || strcmp(op,"->")==0) {
            int is_arrow=(strcmp(op,"->")==0);
            const char *mname=next_tok();
            /* struct_idx 決定: symから、またはノード自体のstruct_idxから */
            int sidx=-1;
            if (n->sym) sidx=n->sym->struct_idx;
            if (sidx<0) sidx=n->struct_idx;  /* 前のSIR_MEMBERノードから継承 */
            if (sidx<0&&n->type==T_PTR) {
                /* ポインタ: typedef検索で型名からstruct_idxを特定 */
                /* まずn->symの型名でtypedefを検索 */
                if (n->sym) {
                    for (int ti2=0;ti2<ntypedefs;ti2++) {
                        if (typedefs[ti2].is_ptr&&typedefs[ti2].struct_idx>=0)
                            { sidx=typedefs[ti2].struct_idx; break; }
                    }
                }
            }
            if (sidx<0&&nstructs>0) sidx=0;
            member_t *mem=NULL;
            int moff=0;
            ctype_t mtype=T_INT, mbase=T_INT;
            int msidx=-1;
            if (sidx>=0) {
                find_member(sidx,mname,&mem);
                if (mem) {
                    moff=mem->offset;
                    mtype=mem->type; mbase=mem->base;
                    msidx=mem->struct_idx;
                }
            }
            if (!mem) error("unknown member '%s'", mname);
            sir_node_t *r=sir_new(SIR_MEMBER);
            r->left=n; n=NULL;
            r->offset=moff;
            r->is_ptr=is_arrow;
            r->struct_idx=msidx;  /* 次段のメンバアクセスに引き継がれる */
            r->type=mtype; r->base=mbase;
            r->is_array=(mem && mem->is_array); /* [F2] 配列メンバはVK_LVALUE */
            n=r; continue;
        }

        push_tok(op,cur_ival);
        break;
    }
    return n;
}

/* ------------------------------------------------------------
 * parse_unary: 前置演算子
 * ------------------------------------------------------------ */
static sir_node_t *parse_unary(void) {
    const char *t=next_tok();
    if (strcmp(t,"-")==0)  return sir_unop(SIR_NEG,  parse_unary());
    if (strcmp(t,"!")==0)  return sir_unop(SIR_NOT,  parse_unary());
    if (strcmp(t,"~")==0)  return sir_unop(SIR_COMPL,parse_unary());
    if (strcmp(t,"*")==0) {
        sir_node_t *operand = parse_unary();
        sir_node_t *n = sir_unop(SIR_DEREF, operand);
        /* [P5] v1.01: baseがchar*の場合はT_CHAR・is_byte=1に設定 */
        if (operand->type == T_PTR && operand->base == T_CHAR) {
            n->type    = T_CHAR;
            n->is_byte = 1;
        } else if (operand->type == T_PTR) {
            n->type    = operand->base;  /* int*→T_INT等 */
            n->is_byte = 0;
        } else {
            n->type = T_INT;  /* 旧動作（非ポインタ）*/
        }
        return n;
    }
    if (strcmp(t,"&")==0) {
        /* &expr: postfix式のアドレスを返す */
        sir_node_t *operand=parse_postfix();
        if (operand->op==SIR_SYM) {
            /* 単純変数: SIR_ADDRノード */
            sir_node_t *r=sir_addr(operand->sym);
            sir_free(operand);
            return r;
        }
        /* SIR_MEMBER/SIR_INDEX等: leftにoperandを格納したSIR_ADDRノード
         * emit_exprでSIR_ADDR(sym==NULL)のとき emit_lval(left)を呼ぶ */
        sir_node_t *r=sir_new(SIR_ADDR);
        r->sym=NULL; r->left=operand;
        r->type=T_PTR; r->base=operand->type;
        return r;
    }
    if (strcmp(t,"++")==0) {
        sir_node_t *n=parse_unary();
        return sir_unop(SIR_PRE_INC, n);
    }
    if (strcmp(t,"--")==0) {
        sir_node_t *n=parse_unary();
        return sir_unop(SIR_PRE_DEC, n);
    }
    push_tok(t,cur_ival);
    return parse_postfix();
}

/* ------------------------------------------------------------
 * parse_mul / parse_add / parse_shift / parse_relational
 * parse_equality / parse_bitand / parse_bitxor / parse_bitor
 * parse_logand / parse_logor
 * ------------------------------------------------------------ */
static sir_node_t *parse_mul(void) {
    sir_node_t *n=parse_unary();
    for (;;) {
        char op[8]; strncpy(op,next_tok(),7); op[7]='\0';
        if (strcmp(op,"*")==0)       { sir_node_t *r=parse_unary(); n=binop_promote(SIR_MUL,n,r); }
        else if (strcmp(op,"/")==0)  { sir_node_t *r=parse_unary(); n=binop_promote(SIR_DIV,n,r); }
        else if (strcmp(op,"%")==0)  { n=sir_binop(SIR_MOD,n,parse_unary()); }
        else { push_tok(op,cur_ival); break; }
    }
    return n;
}

/* [P1][P2] parse_add: ポインタ算術スケーリング対応 (v1.01)
 * ptr + n  → ptr + n * sizeof(*ptr)
 * ptr - n  → ptr - n * sizeof(*ptr)
 * ptr - ptr → (ptr - ptr) / sizeof(*ptr)  [C標準: 要素数返し]
 */
static sir_node_t *ptr_scale(sir_node_t *ptr, sir_node_t *idx) {
    /* ptrの指す要素サイズを取得（T_PTR/T_ARRAYの両方対応）*/
    int esz = (ptr->base == T_CHAR) ? 1 : 2;
    if (esz == 1) return idx;  /* char*はスケール不要 */
    /* idx * 2 = SHL idx, #1 */
    sir_node_t *two = sir_const(1);   /* SHL用: シフト量1 = ×2 */
    sir_node_t *scaled = sir_binop(SIR_SHL, idx, two);
    return scaled;
}

/* is_ptr_or_array: ポインタ算術スケーリングが必要な型か判定 */
static int is_ptr_or_array(sir_node_t *n) {
    return (n->type == T_PTR || n->type == T_ARRAY);
}

static sir_node_t *parse_add(void) {
    sir_node_t *n=parse_mul();
    for (;;) {
        char op[8]; strncpy(op,next_tok(),7); op[7]='\0';
        if (strcmp(op,"+")==0) {
            sir_node_t *r = parse_mul();
            /* [P1] ptr/array + int: インデックスをスケール */
            if (is_ptr_or_array(n) && !is_ptr_or_array(r)) {
                r = ptr_scale(n, r);
                n = sir_binop(SIR_ADD, n, r);
            } else {
                /* [v2.00] §5.1: float混在ならI2F昇格・結果T_FLOAT。int同士は従来通り */
                n = binop_promote(SIR_ADD, n, r);
            }
        } else if (strcmp(op,"-")==0) {
            sir_node_t *r = parse_mul();
            /* [P1] ptr/array - int: インデックスをスケール */
            if (is_ptr_or_array(n) && !is_ptr_or_array(r)) {
                r = ptr_scale(n, r);
                n = sir_binop(SIR_SUB, n, r);
            }
            /* [P2] ptr/array - ptr/array: 要素数返し（C標準準拠） */
            else if (is_ptr_or_array(n) && is_ptr_or_array(r)) {
                sir_node_t *diff = sir_binop(SIR_SUB, n, r);
                int esz = (n->base == T_CHAR) ? 1 : 2;
                if (esz == 2) {
                    /* バイト差を要素数に変換: diff >> 1 (算術右シフト) */
                    sir_node_t *one = sir_const(1);
                    n = sir_binop(SIR_SAR, diff, one);  /* [P6] SAR: 符号保存右シフト */
                } else {
                    n = diff;  /* char*はバイト差=要素数 */
                }
            } else {
                n = binop_promote(SIR_SUB, n, r);  /* [v2.00] §5.1: float混在対応 */
            }
        }
        else { push_tok(op,cur_ival); break; }
    }
    return n;
}

static sir_node_t *parse_shift(void) {
    sir_node_t *n=parse_add();
    for (;;) {
        char op[8]; strncpy(op,next_tok(),7); op[7]='\0';
        if (strcmp(op,"<<")==0)     { n=sir_binop(SIR_SHL,n,parse_add()); }
        else if (strcmp(op,">>")==0){ n=sir_binop(SIR_SHR,n,parse_add()); }
        else { push_tok(op,cur_ival); break; }
    }
    return n;
}

static sir_node_t *parse_relational(void) {
    sir_node_t *n=parse_shift();
    char op[8]; strncpy(op,next_tok(),7); op[7]='\0';
    if (strcmp(op,"<")==0)       { n=sir_binop(SIR_LT,n,parse_shift()); }
    else if (strcmp(op,"<=")==0) { n=sir_binop(SIR_LE,n,parse_shift()); }
    else if (strcmp(op,">")==0)  { n=sir_binop(SIR_GT,n,parse_shift()); }
    else if (strcmp(op,">=")==0) { n=sir_binop(SIR_GE,n,parse_shift()); }
    else push_tok(op,cur_ival);
    return n;
}

static sir_node_t *parse_equality(void) {
    sir_node_t *n=parse_relational();
    for (;;) {
        char op[8]; strncpy(op,next_tok(),7); op[7]='\0';
        if (strcmp(op,"==")==0)     { n=sir_binop(SIR_EQ,n,parse_relational()); }
        else if (strcmp(op,"!=")==0){ n=sir_binop(SIR_NE,n,parse_relational()); }
        else { push_tok(op,cur_ival); break; }
    }
    return n;
}

static sir_node_t *parse_bitand(void) {
    sir_node_t *n=parse_equality();
    while (strcmp(next_tok(),"&")==0) n=sir_binop(SIR_AND,n,parse_equality());
    push_tok(cur_tok,cur_ival); return n;
}
static sir_node_t *parse_bitxor(void) {
    sir_node_t *n=parse_bitand();
    while (strcmp(next_tok(),"^")==0) n=sir_binop(SIR_XOR,n,parse_bitand());
    push_tok(cur_tok,cur_ival); return n;
}
static sir_node_t *parse_bitor(void) {
    sir_node_t *n=parse_bitxor();
    while (strcmp(next_tok(),"|")==0) n=sir_binop(SIR_OR,n,parse_bitxor());
    push_tok(cur_tok,cur_ival); return n;
}

static sir_node_t *parse_logand(void) {
    sir_node_t *n=parse_bitor();
    while (strcmp(next_tok(),"&&")==0) n=sir_binop(SIR_LAND,n,parse_bitor());
    push_tok(cur_tok,cur_ival); return n;
}
static sir_node_t *parse_logor(void) {
    sir_node_t *n=parse_logand();
    while (strcmp(next_tok(),"||")==0) n=sir_binop(SIR_LOR,n,parse_logand());
    push_tok(cur_tok,cur_ival); return n;
}

/* ------------------------------------------------------------
 * parse_assign: 代入式（= += -= *= /= %= &= |= ^=）
 * ------------------------------------------------------------ */
static sir_node_t *parse_assign(void) {
    sir_node_t *lhs=parse_logor();
    char op[8]; strncpy(op,next_tok(),7); op[7]='\0';

    if (strcmp(op,"=")==0) {
        sir_node_t *rhs=parse_assign();
        sir_node_t *n=sir_new(SIR_ASSIGN);
        n->left=lhs; n->right=rhs; n->type=rhs?rhs->type:T_INT; return n;
    }

    sir_op_t aop=SIR_NOP;
    if      (strcmp(op,"+=")==0) aop=SIR_ADD;
    else if (strcmp(op,"-=")==0) aop=SIR_SUB;
    else if (strcmp(op,"*=")==0) aop=SIR_MUL;
    else if (strcmp(op,"/=")==0) aop=SIR_DIV;
    else if (strcmp(op,"%=")==0) aop=SIR_MOD;
    else if (strcmp(op,"&=")==0) aop=SIR_AND;
    else if (strcmp(op,"|=")==0) aop=SIR_OR;
    else if (strcmp(op,"^=")==0) aop=SIR_XOR;

    if (aop!=SIR_NOP) {
        sir_node_t *rhs=parse_assign();
        sir_node_t *n=sir_new(SIR_ASGN_OP);
        n->left=lhs; n->right=rhs; n->aop=aop;
        n->type=lhs?lhs->type:T_INT; return n;
    }

    push_tok(op,cur_ival);
    return lhs;
}

static sir_node_t *parse_expr(void) {
    return parse_assign();
}

/* ============================================================
 * P3: バックエンド emit_expr() / emit_lval()
 *
 * レジスタ契約（厳守）:
 *   戻り値: A
 *   B: 破壊される可能性あり（呼び出し元がPUSHで保護すること）
 *   X: 不変（フレームポインタ）
 *   SP: バランス維持（PUSH/POPは必ず対応）
 * ============================================================ */

/* SP経由スタック操作ヘルパー */
static void emit_push_a(void) {
    emit("    SUBI SP, #2");
    emit("    STW  A, [SP]");
}
static void emit_pop_b(void) {
    emit("    LDW  B, [SP]");
    emit("    ADDI SP, #2");
}

/* アドレスA経由でロード（X退避版 - Xを破壊しない） */
static void emit_load_at_a(int is_char) {
    /* Xを一時退避してアドレスレジスタとして使用 */
    emit("    SUBI SP, #2");
    emit("    STW  X, [SP]");
    emit("    MOV  X, A");
    if (is_char) emit("    LDB  A, [X]");
    else         emit("    LDW  A, [X]");
    emit("    LDW  X, [SP]");
    emit("    ADDI SP, #2");
}

/* アドレスB経由でAをストア: [B] = A */
static void emit_store_a_at_b(int is_char) {
    emit("    SUBI SP, #2");
    emit("    STW  X, [SP]");
    emit("    MOV  X, B");          /* X = アドレス(B) */
    if (is_char) emit("    STB  A, [X]");
    else         emit("    STW  A, [X]");
    emit("    LDW  X, [SP]");
    emit("    ADDI SP, #2");
}

/* アドレスA経由でBをストア: [A] = B */
static void emit_store_b_at_a(int is_char) {
    emit("    SUBI SP, #2");
    emit("    STW  X, [SP]");
    emit("    MOV  X, A");          /* X = アドレス(A) */
    if (is_char) emit("    STB  B, [X]");
    else         emit("    STW  B, [X]");
    emit("    LDW  X, [SP]");
    emit("    ADDI SP, #2");
}

/* sym_t のフレームオフセット計算（v2.11から流用） */
static int real_offset(sym_t *s) {
    if (s->sclass==SC_PARAM) {
        return s->offset;
    }
    return -(4+s->offset);
}

/* ============================================================
 * [F1] value_kind: lvalue/rvalue判定（設計書v1.5 D1,D3,D4,R1対応）
 * T_PTR   → VK_RVALUE（ポインタ値はロードが必要）
 * 配列    → VK_LVALUE（アドレスをそのまま渡す）
 * struct  → VK_LVALUE（アドレスをそのまま渡す）
 * それ以外 → VK_RVALUE
 * ============================================================ */
typedef enum { VK_RVALUE, VK_LVALUE } value_kind_t;

static value_kind_t node_vkind(sir_node_t *n) {
    if (!n) return VK_RVALUE;
    if (n->is_array)                           return VK_LVALUE;
    if (n->type==T_STRUCT || n->type==T_UNION) return VK_LVALUE;
    /* [B7] T_PTRはstruct_idx>=0でもポインタ値をロードすべきVK_RVALUE */
    if (n->type==T_PTR)                        return VK_RVALUE;
    if (n->struct_idx >= 0)                    return VK_LVALUE;
    return VK_RVALUE;
}
/* 将来の最適化用ヘルパー（現時点では未使用だが定義しておく） */
static int should_load(sir_node_t *n) { return node_vkind(n)==VK_RVALUE; (void)should_load; }

/* 前方宣言 */
static void emit_expr(sir_node_t *n);
static void emit_lval(sir_node_t *n);

/* emit_lval: 左辺値のアドレスをAに返す（ロードはしない） */
static void emit_lval(sir_node_t *n) {
    if (!n) { error("null lval node"); return; }
    switch (n->op) {
    case SIR_STRLIT:
        /* [§4.2] 文字列リテラルはアドレスを返す（VK_LVALUE） */
        emit("    LDW  A, #$_S_%04d", n->str_id);
        break;
    case SIR_SYM: {
        sym_t *s=n->sym;
        if ((s->is_array||s->type==T_STRUCT||s->type==T_UNION)
            && s->sclass==SC_PARAM) {
            /* パラメータ配列/構造体: フレーム上のポインタ値がアドレス */
            int off=real_offset(s);
            if (off==0)     emit("    LDW  A, [X]");
            else if (off>0) emit("    LDW  A, [X + #%d]", off);
            else            emit("    LDW  A, [X + #$%04X]", (unsigned short)off);
        } else if (s->sclass==SC_GLOBAL) {
            emit("    LDW  A, #$%04X", (unsigned)(DATA_ORG+s->offset));
        } else {
            int off=real_offset(s);
            emit("    MOV  A, X");
            if (off>0)       emit("    ADDI A, #%d", off);
            else if (off<0)  emit("    SUBI A, #%d", -off);
        }
        break;
    }
    case SIR_ADDR:
        /* &var → アドレスそのもの */
        if (n->sym) {
            if (n->sym->sclass==SC_GLOBAL)
                emit("    LDW  A, #$%04X", (unsigned)(DATA_ORG+n->sym->offset));
            else {
                int off=real_offset(n->sym);
                emit("    MOV  A, X");
                if (off>0)      emit("    ADDI A, #%d", off);
                else if (off<0) emit("    SUBI A, #%d", -off);
            }
        } else {
            emit_lval(n->left);
        }
        break;
    case SIR_DEREF:
        /* *ptr → ptrの値がアドレス */
        emit_expr(n->left);
        break;
    case SIR_INDEX: {
        /* アドレス計算のみ（ロードなし）*/
        int esz=n->esz;
        emit_expr(n->left);    /* A = ベースアドレス */
        emit_push_a();
        emit_expr(n->right);   /* A = インデックス */
        if (esz==2) { emit("    LDW  B, #1"); emit("    SHL  A, B"); }
        emit_pop_b();          /* B = ベースアドレス */
        emit("    ADD  A, B"); /* A = 要素アドレス */
        break;
    }
    case SIR_INDEX2D: {
        /* 安全形アドレス計算のみ（ロードなし）*/
        int esz=n->esz, dim2=n->dim2;
        emit_expr(n->left);
        emit_push_a();
        emit_expr(n->right);
        emit("    LDW  B, #%d", dim2);
        g_use_mul=1; emit("    JSR  _cc_mul");
        emit_push_a();
        emit_expr(n->r2);
        emit_pop_b();
        emit("    ADD  A, B");
        if (esz==2) { emit("    LDW  B, #1"); emit("    SHL  A, B"); }
        emit_pop_b();
        emit("    ADD  A, B");
        break;
    }
    case SIR_MEMBER: {
        /* メンバアドレスのみ（ロードなし）*/
        sir_node_t *base=n->left;
        if (n->is_ptr) {
            /* ->: ポインタ値をロードしてアドレスとして使う */
            if (base->sym) {
                sym_t *s=base->sym;
                if (s->sclass==SC_GLOBAL)
                    emit("    LDW  A, [$%04X]", (unsigned)(DATA_ORG+s->offset));
                else {
                    int off=real_offset(s);
                    if (off==0)     emit("    LDW  A, [X]");
                    else if (off>0) emit("    LDW  A, [X + #%d]", off);
                    else            emit("    LDW  A, [X + #$%04X]", (unsigned short)off);
                }
            } else emit_expr(base);
        } else {
            /* .: ベースアドレスを計算 */
            if (base->sym) {
                sym_t *s=base->sym;
                if (s->sclass==SC_GLOBAL)
                    emit("    LDW  A, #$%04X", (unsigned)(DATA_ORG+s->offset));
                else {
                    int off=real_offset(s);
                    emit("    MOV  A, X");
                    if (off>0)      emit("    ADDI A, #%d", off);
                    else if (off<0) emit("    SUBI A, #%d", -off);
                }
            } else emit_expr(base);
        }
        if (n->offset>0) emit("    ADDI A, #%d", n->offset);
        break;
    }
    default:
        /* fallback: 式を評価してその値をアドレスとして使う */
        emit_expr(n);
        break;
    }
}

/* emit_expr: SirNodeを評価してAに結果を返す */
/* [v2.3 Step8] 不要ノード削除pass: 同型CAST(型不変)・SIR_NOPラッパを素通しする。
 *   emitは元々SIR_CAST/SIR_NOPを透過処理するためバイナリ出力は不変(回帰なし)。
 *   本passはIRツリーを正規化し後続(O1代数簡約)が余計なノードに惑わされないため。
 *   -O0-strict時は無効化(§2.5.7・回帰運用でv1.04相当を保つ)。 */
static sir_node_t *elim_redundant(sir_node_t *n) {
    if (!n) return NULL;
    if (g_opt_level == OPT_O0_STRICT) return n;
    /* 同型CAST: (T)expr で expr が既にT型なら CAST を剥がす。
     * I2F/F2Iは別ノード(SIR_I2F/F2I)なのでここには来ない=float意味論は保持。 */
    while (n && n->op==SIR_CAST && n->left && n->left->type==n->type) {
        n = n->left;
    }
    /* SIR_NOPが式の位置に来た場合も剥がす(空ラッパ) */
    while (n && n->op==SIR_NOP && n->left) {
        n = n->left;
    }
    return n;
}

static void emit_expr(sir_node_t *n) {
    if (!n) return;
    n = elim_redundant(n);   /* [v2.3 Step8] 不要ノード素通し(非strict時) */
    if (!n) return;
    switch (n->op) {

    /* ── リテラル ── */
    case SIR_CONST:
        emit("    LDW  A, #%d", n->ival);
        break;

    case SIR_STRLIT:
        emit("    LDW  A, #$_S_%04d", n->str_id);
        break;

    case SIR_NOP:
        /* 何もしない */
        break;

    /* ── 変数参照 ── */
    case SIR_SYM: {
        sym_t *s=n->sym;
        if (s->is_array||s->type==T_STRUCT||s->type==T_UNION) {
            if (s->sclass==SC_PARAM) {
                /* パラメータ配列/構造体: フレーム上のポインタ値をロード */
                int off=real_offset(s);
                if (off==0)     emit("    LDW  A, [X]");
                else if (off>0) emit("    LDW  A, [X + #%d]", off);
                else            emit("    LDW  A, [X + #$%04X]", (unsigned short)off);
            } else if (s->sclass==SC_GLOBAL) {
                emit("    LDW  A, #$%04X", (unsigned)(DATA_ORG+s->offset));
            } else {
                /* ローカル配列/構造体: フレームアドレスを返す */
                int off=real_offset(s);
                emit("    MOV  A, X");
                if (off>0)      emit("    ADDI A, #%d", off);
                else if (off<0) emit("    SUBI A, #%d", -off);
            }
        } else {
            int is_char=(s->type==T_CHAR);
            if (s->sclass==SC_GLOBAL) {
                unsigned addr=(unsigned)(DATA_ORG+s->offset);
                if (is_char) emit("    LDB  A, [$%04X]", addr&0xFFFF);
                else         emit("    LDW  A, [$%04X]", addr&0xFFFF);
            } else {
                int off=real_offset(s);
                if (off==0)     emit("    LDW  A, [X]");
                else if (off>0) emit("    LDW  A, [X + #%d]", off);
                else            emit("    LDW  A, [X + #$%04X]", (unsigned short)off);
            }
        }
        break;
    }

    /* ── アドレス取得 ── */
    case SIR_ADDR: {
        if (n->sym) {
            /* 単純変数アドレス */
            sym_t *s=n->sym;
            if (s->sclass==SC_GLOBAL)
                emit("    LDW  A, #$%04X", (unsigned)(DATA_ORG+s->offset));
            else {
                int off=real_offset(s);
                emit("    MOV  A, X");
                if (off>0)      emit("    ADDI A, #%d", off);
                else if (off<0) emit("    SUBI A, #%d", -off);
            }
        } else {
            /* &(複合式): emit_lvalでアドレスを計算 */
            emit_lval(n->left);
        }
        break;
    }

    /* ── メモリロード ── */
    case SIR_LOAD:
        emit_expr(n->left);      /* A = アドレス */
        emit_load_at_a(n->is_byte);
        break;

    /* ── メモリストア ── */
    case SIR_STORE:
        emit_expr(n->right);     /* A = 値（レジスタ契約: Aに返す） */
        emit_push_a();           /* スタックに値を退避 */
        emit_expr(n->left);      /* A = アドレス */
        emit_pop_b();            /* B = 値 */
        emit_store_b_at_a(n->is_byte);
        break;

    /* ── 算術2項演算 ── */
    case SIR_ADD:
        emit_expr(n->left);
        emit_push_a();
        emit_expr(n->right);
        emit_pop_b();
        emit("    ADD  B, A");
        emit("    MOV  A, B");
        break;

    case SIR_SUB:
        emit_expr(n->left);
        emit_push_a();
        emit_expr(n->right);
        emit_pop_b();
        emit("    SUB  B, A");
        emit("    MOV  A, B");
        break;

    case SIR_MUL:
        emit_expr(n->left);
        emit_push_a();
        emit_expr(n->right);
        emit_pop_b();
        /* _cc_mul: A=left, B=right → A=left*right */
        g_use_mul=1; emit("    JSR  _cc_mul");
        break;

    case SIR_DIV:
        emit_expr(n->left);
        emit_push_a();
        emit_expr(n->right);
        emit_pop_b();
        g_use_div=1; emit("    JSR  _cc_div");
        break;

    case SIR_MOD:
        emit_expr(n->left);
        emit_push_a();
        emit_expr(n->right);
        emit_pop_b();
        g_use_mod=1; emit("    JSR  _cc_mod");
        break;

    /* ── ビット演算 ── */
    case SIR_AND:
        emit_expr(n->left); emit_push_a();
        emit_expr(n->right); emit_pop_b();
        emit("    AND  B, A"); emit("    MOV  A, B"); break;

    case SIR_OR:
        emit_expr(n->left); emit_push_a();
        emit_expr(n->right); emit_pop_b();
        emit("    OR   B, A"); emit("    MOV  A, B"); break;

    case SIR_XOR:
        emit_expr(n->left); emit_push_a();
        emit_expr(n->right); emit_pop_b();
        emit("    XOR  B, A"); emit("    MOV  A, B"); break;

    case SIR_SHL:
        emit_expr(n->left); emit_push_a();
        emit_expr(n->right); emit_pop_b();
        emit("    SHL  B, A"); emit("    MOV  A, B"); break;

    case SIR_SHR:
        emit_expr(n->left); emit_push_a();
        emit_expr(n->right); emit_pop_b();
        emit("    SHR  B, A"); emit("    MOV  A, B"); break;

    case SIR_SAR:  /* [P6] v1.01: 算術右シフト（符号保存） ptr-ptr除算用 */
        emit_expr(n->left); emit_push_a();
        emit_expr(n->right); emit_pop_b();
        emit("    SAR  B, A"); emit("    MOV  A, B"); break;

    /* ===== [v2.00] float(Q8.8) 演算（§2.5.1 ISA2.3適合形・cc_mul評価規約踏襲）===== */
    case SIR_FMUL:
        /* A=left(Q8.8), B=right(Q8.8) → A=(left*right)>>8。_fmulオンデマンド出力 */
        emit_expr(n->left); emit_push_a();
        emit_expr(n->right); emit_pop_b();
        g_use_fmul=1; emit("    JSR  _fmul");
        break;

    case SIR_FDIV:
        /* A=numerator(Q8.8), B=denominator(Q8.8) → A=(num<<8)/den。非負前提(§6.5) */
        emit_expr(n->left); emit_push_a();
        emit_expr(n->right); emit_pop_b();
        g_use_fdiv=1; emit("    JSR  _fdiv");
        break;

    case SIR_I2F:
        /* int→float: A <<= 8。ISA2.3はレジスタ経由シフトのみ(§2.5.1) */
        emit_expr(n->left);
        emit("    LDW  B, #8");
        emit("    SHL  A, B");
        break;

    case SIR_F2I:
        /* float→int: A >>= 8 算術(符号保存)。SAR rD,rS(§2.5.1) */
        emit_expr(n->left);
        emit("    LDW  B, #8");
        emit("    SAR  A, B");
        break;

    /* ── 比較 ── */
    case SIR_EQ: case SIR_NE:
    case SIR_LT: case SIR_LE: case SIR_GT: case SIR_GE: {
        emit_expr(n->left); emit_push_a();
        emit_expr(n->right); emit_pop_b();
        int Ltrue=new_label(), Lend=new_label();
        emit("    CMP  B, A");
        switch (n->op) {
        case SIR_EQ: emit("    BEQ  _L_%04d", Ltrue); break;
        case SIR_NE: emit("    BNE  _L_%04d", Ltrue); break;
        case SIR_LT: emit("    BLT  _L_%04d", Ltrue); break;
        case SIR_GT:
            /* B > A → A < B: 入れ替えてBLT */
            emit("    CMP  A, B");
            emit("    BLT  _L_%04d", Ltrue);
            break;
        case SIR_LE:
            emit("    BLT  _L_%04d", Ltrue);
            emit("    BEQ  _L_%04d", Ltrue);
            break;
        case SIR_GE:
            emit("    BGE  _L_%04d", Ltrue);
            break;
        default: break;
        }
        emit("    LDW  A, #0");
        emit("    JMP  _L_%04d", Lend);
        emit_label(Ltrue);
        emit("    LDW  A, #1");  /* C規格: 比較/論理演算子は 0 か 1 を返す */
        emit_label(Lend);
        break;
    }

    /* ── 論理演算（short-circuit） ── */
    case SIR_LAND: {
        int Lfalse=new_label(), Lend=new_label();
        emit_expr(n->left);
        emit("    CMPI A, #0");
        emit("    BEQ  _L_%04d", Lfalse);
        emit_expr(n->right);
        emit("    CMPI A, #0");
        emit("    BEQ  _L_%04d", Lfalse);
        emit("    LDW  A, #1");  /* C規格: 比較/論理演算子は 0 か 1 を返す */
        emit("    JMP  _L_%04d", Lend);
        emit_label(Lfalse);
        emit("    LDW  A, #0");
        emit_label(Lend);
        break;
    }
    case SIR_LOR: {
        int Ltrue=new_label(), Lend=new_label();
        emit_expr(n->left);
        emit("    CMPI A, #0");
        emit("    BNE  _L_%04d", Ltrue);
        emit_expr(n->right);
        emit("    CMPI A, #0");
        emit("    BNE  _L_%04d", Ltrue);
        emit("    LDW  A, #0");
        emit("    JMP  _L_%04d", Lend);
        emit_label(Ltrue);
        emit("    LDW  A, #1");  /* C規格: 比較/論理演算子は 0 か 1 を返す */
        emit_label(Lend);
        break;
    }

    /* ── 単項演算 ── */
    case SIR_NEG:
        emit_expr(n->left);
        emit("    LDW  B, #0");
        emit("    SUB  B, A");
        emit("    MOV  A, B");
        break;

    case SIR_NOT: {
        int L=new_label(), Lend=new_label();
        emit_expr(n->left);
        emit("    CMPI A, #0");
        emit("    BEQ  _L_%04d", L);
        emit("    LDW  A, #0");
        emit("    JMP  _L_%04d", Lend);
        emit_label(L);
        emit("    LDW  A, #1");   /* C規格: ! は 0 か 1 を返す */
        emit_label(Lend);
        break;
    }

    case SIR_COMPL:
        emit_expr(n->left);
        emit("    NOT  A");
        break;

    case SIR_DEREF:
        emit_expr(n->left);
        emit_load_at_a(n->is_byte);  /* [A1] is_byteでchar/int区別 */
        break;

    case SIR_CAST:
        emit_expr(n->left);
        /* キャストはコードサイズ変更なし（YSD8800は16bitアドレス統一）*/
        break;

    /* ── 1次元配列インデックス（アドレスを返す）── */
    case SIR_INDEX: {
        int esz=n->esz;
        emit_expr(n->left);    /* A = ベースアドレス */
        emit_push_a();
        emit_expr(n->right);   /* A = インデックス */
        if (esz==2) { emit("    LDW  B, #1"); emit("    SHL  A, B"); }
        emit_pop_b();          /* B = ベースアドレス */
        emit("    ADD  A, B"); /* A = 要素アドレス */
        /* 値のロード（構造体はアドレスのまま） */
        if (n->struct_idx<0) {
            emit_load_at_a(esz==1);
        }
        break;
    }

    /* ── P3.5: 2次元配列インデックス（安全形・レビュー反映）── */
    case SIR_INDEX2D: {
        /* addr = base + (row * dim2 + col) * esz
         * 安全形展開（emit_exprはAのみ保証）*/
        int esz=n->esz, dim2=n->dim2;
        emit_expr(n->left);     /* A = base アドレス */
        emit_push_a();          /* [SP] = base */
        emit_expr(n->right);    /* A = row */
        emit("    LDW  B, #%d", dim2);
        g_use_mul=1; emit("    JSR  _cc_mul");   /* A = row * dim2 */
        emit_push_a();          /* [SP] = row*dim2, [SP+2] = base */
        emit_expr(n->r2);       /* A = col */
        emit_pop_b();           /* B = row*dim2 */
        emit("    ADD  A, B");  /* A = row*dim2 + col */
        if (esz==2) { emit("    LDW  B, #1"); emit("    SHL  A, B"); }
        emit_pop_b();           /* B = base */
        emit("    ADD  A, B");  /* A = 最終アドレス */
        /* 値ロード */
        if (n->struct_idx<0) {
            emit_load_at_a(esz==1);
        }
        break;
    }

    /* ── 構造体メンバアクセス（アドレスを返す）── */
    case SIR_MEMBER: {
        sir_node_t *base=n->left;
        if (n->is_ptr) {
            /* ->: ポインタをロードしてアドレスとして使う */
            if (base->sym) {
                sym_t *s=base->sym;
                if (s->sclass==SC_GLOBAL) {
                    emit("    LDW  A, [$%04X]", (unsigned)(DATA_ORG+s->offset));
                } else {
                    int off=real_offset(s);
                    if (off==0)     emit("    LDW  A, [X]");
                    else if (off>0) emit("    LDW  A, [X + #%d]", off);
                    else            emit("    LDW  A, [X + #$%04X]", (unsigned short)off);
                }
            } else emit_expr(base);
        } else {
            /* .: ベースアドレスを計算 */
            if (base->sym) {
                sym_t *s=base->sym;
                if (s->sclass==SC_GLOBAL)
                    emit("    LDW  A, #$%04X", (unsigned)(DATA_ORG+s->offset));
                else {
                    int off=real_offset(s);
                    emit("    MOV  A, X");
                    if (off>0)      emit("    ADDI A, #%d", off);
                    else if (off<0) emit("    SUBI A, #%d", -off);
                }
            } else emit_expr(base);
        }
        if (n->offset>0) emit("    ADDI A, #%d", n->offset);
        /* メンバ値ロード（構造体・配列・配列メンバはアドレスのまま）
         * T_PTR は struct_idx が非負（構造体へのポインタ）でもロードが必要 */
        if ((n->struct_idx<0 || n->type==T_PTR) && n->type!=T_STRUCT && n->type!=T_UNION
            && !n->is_array) {  /* [F2] 配列メンバはアドレスのまま返す */
            int is_char=(n->type==T_CHAR&&!n->is_ptr);
            emit_load_at_a(is_char);
        }
        break;
    }

    /* ── P3.5: 関数呼び出し ── */
    case SIR_CALL: {
        /* [F2] 引数評価: node_vkind判定で lvalue/rvalue を区別（D2,R2,A4対応）
         * VK_LVALUE（配列・構造体）→ emit_lval でアドレスを渡す
         * VK_RVALUE（int・char・ptr等）→ emit_expr で値を渡す
         * ADDI SP #argsize は絶対に省略禁止 */
        for (int i=n->nargs-1; i>=0; i--) {
            sir_node_t *arg = n->args[i];
            if (node_vkind(arg) == VK_LVALUE)
                emit_lval(arg);   /* アドレスを渡す */
            else
                emit_expr(arg);   /* 値をロードして渡す */
            emit_push_a();
        }
        emit("    JSR  _%s", n->fname);
        if (n->nargs>0)
            emit("    ADDI SP, #%d", n->nargs*2);  /* [F2] ★省略禁止 */
        break;
    }

    /* ── 代入 ── */
    case SIR_ASSIGN: {
        emit_expr(n->right);    /* A = 右辺値 */
        emit_push_a();
        emit_lval(n->left);     /* A = 左辺アドレス */
        emit_pop_b();           /* B = 値 */
        /* is_byte判定: 左辺ノードのtypeがT_CHARかチェック */
        int is_char=0;
        if (n->left) {
            sir_node_t *lv=n->left;
            if (lv->op==SIR_SYM && lv->sym && lv->sym->type==T_CHAR) is_char=1;
            else if (lv->type==T_CHAR && lv->op!=SIR_ADDR) is_char=1;
        }
        emit_store_b_at_a(is_char);  /* [A] = B */
        emit("    MOV  A, B");  /* 代入式の値は代入した値 */
        break;
    }

    /* ── 複合代入 ── */
    case SIR_ASGN_OP: {
        /* [P7] v1.01: ポインタ型の+=/-=スケーリング対応
         * lhsがT_PTR/T_ARRAYかつaop=ADD/SUBの場合、rhsをスケールして加算 */
        int lhs_is_ptr = is_ptr_or_array(n->left);
        int lhs_is_char_ptr = (lhs_is_ptr && n->left->base == T_CHAR);
        int ptr_esz = lhs_is_char_ptr ? 1 : 2;
        /* ロード時のバイト幅: 左辺がchar型ならバイトロード */
        int load_byte = (!lhs_is_ptr && n->left->type == T_CHAR) ? 1 : 0;

        /* 左辺アドレスを求める */
        emit_lval(n->left);     /* A = 左辺アドレス */
        emit_push_a();          /* [SP] = addr */
        /* 現在値をロード */
        emit_load_at_a(load_byte); /* A = *addr（char*はバイトロード）*/
        emit_push_a();          /* [SP] = 旧値, [SP+2] = addr */
        emit_expr(n->right);    /* A = 右辺値 */
        /* [P7] ptr += n / ptr -= n: rhsをスケール */
        if (lhs_is_ptr && (n->aop == SIR_ADD || n->aop == SIR_SUB)
            && ptr_esz == 2) {
            /* A = rhs * 2: SHL A, #1 */
            emit("    LDW  B, #1");
            emit("    SHL  A, B");   /* A = rhs << 1 = rhs * 2 */
        }
        emit_pop_b();           /* B = 旧値 */
        /* 演算 */
        switch (n->aop) {
        case SIR_ADD: emit("    ADD  B, A"); emit("    MOV  A, B"); break;
        case SIR_SUB: emit("    SUB  B, A"); emit("    MOV  A, B"); break;
        case SIR_MUL: g_use_mul=1; emit("    JSR  _cc_mul"); break;
        case SIR_DIV: g_use_div=1; emit("    JSR  _cc_div"); break;
        case SIR_MOD: g_use_mod=1; emit("    JSR  _cc_mod"); break;
        case SIR_AND: emit("    AND  B, A"); emit("    MOV  A, B"); break;
        case SIR_OR:  emit("    OR   B, A"); emit("    MOV  A, B"); break;
        case SIR_XOR: emit("    XOR  B, A"); emit("    MOV  A, B"); break;
        default: break;
        }
        /* A = 新値 → ストア */
        emit_push_a();          /* [SP] = 新値 */
        emit("    LDW  B, [SP]");  /* B = 新値（一時） */
        emit("    ADDI SP, #2");
        emit("    LDW  A, [SP]");  /* A = addr */
        emit("    ADDI SP, #2");
        emit_store_b_at_a(load_byte);  /* [P7] char*はバイトストア */
        emit("    MOV  A, B");
        break;
    }

    /* ── 後置/前置 ++ / --
     * YSD8800制約: [SP+N]アドレッシング不可, emit_load_at_aはX使用
     * → ワーク変数(C_XSAVE_ADDR/C_TMP_ADDR)を使って addr と 旧値 を保持
     *   C_XSAVE_ADDR($C7E8): アドレス退避  ※v1.03で$FBD0→$C7E8へ移設
     *   C_TMP_ADDR  ($C7EA): 旧値退避
     * ── */
    case SIR_POST_INC: {
        /* [P3] v1.01: ポインタ型はstepを要素サイズに（int*→2, char*→1）*/
        int inc_step = (n->left->type == T_PTR && n->left->base != T_CHAR) ? 2 : 1;
        emit_lval(n->left);
        emit("    STW  A, [$%04X]", C_XSAVE_ADDR); /* addr退避 */
        emit_load_at_a(0);                           /* A = 旧値 */
        emit("    STW  A, [$%04X]", C_TMP_ADDR);    /* 旧値退避 */
        if (inc_step == 2) emit("    ADDI A, #2");
        else               emit("    ADDI A, #1");
        emit("    MOV  B, A");                       /* B = 新値 */
        emit("    LDW  A, [$%04X]", C_XSAVE_ADDR);  /* A = addr */
        emit_store_b_at_a(0);                        /* [addr] = 新値 */
        emit("    LDW  A, [$%04X]", C_TMP_ADDR);    /* A = 旧値（戻り値）*/
        break;
    }
    case SIR_POST_DEC: {
        /* [P3] v1.01: ポインタ型はstepを要素サイズに */
        int dec_step = (n->left->type == T_PTR && n->left->base != T_CHAR) ? 2 : 1;
        emit_lval(n->left);
        emit("    STW  A, [$%04X]", C_XSAVE_ADDR);
        emit_load_at_a(0);
        emit("    STW  A, [$%04X]", C_TMP_ADDR);
        if (dec_step == 2) emit("    SUBI A, #2");
        else               emit("    SUBI A, #1");
        emit("    MOV  B, A");
        emit("    LDW  A, [$%04X]", C_XSAVE_ADDR);
        emit_store_b_at_a(0);
        emit("    LDW  A, [$%04X]", C_TMP_ADDR);
        break;
    }

    /* ── 前置 ++ / -- ── */
    case SIR_PRE_INC: {
        /* [P3] v1.01: ポインタ型はstepを要素サイズに */
        int inc_step = (n->left->type == T_PTR && n->left->base != T_CHAR) ? 2 : 1;
        emit_lval(n->left);
        emit("    STW  A, [$%04X]", C_XSAVE_ADDR); /* addr退避 */
        emit_load_at_a(0);                           /* A = 旧値 */
        if (inc_step == 2) emit("    ADDI A, #2");
        else               emit("    ADDI A, #1");
        emit("    MOV  B, A");                       /* B = 新値 */
        emit("    LDW  A, [$%04X]", C_XSAVE_ADDR);  /* A = addr */
        emit_store_b_at_a(0);                        /* [addr] = 新値 */
        emit("    MOV  A, B");                       /* A = 新値（戻り値）*/
        break;
    }
    case SIR_PRE_DEC: {
        /* [P3] v1.01: ポインタ型はstepを要素サイズに */
        int dec_step = (n->left->type == T_PTR && n->left->base != T_CHAR) ? 2 : 1;
        emit_lval(n->left);
        emit("    STW  A, [$%04X]", C_XSAVE_ADDR);
        emit_load_at_a(0);
        if (dec_step == 2) emit("    SUBI A, #2");
        else               emit("    SUBI A, #1");
        emit("    MOV  B, A");
        emit("    LDW  A, [$%04X]", C_XSAVE_ADDR);
        emit_store_b_at_a(0);
        emit("    MOV  A, B");
        break;
    }

    /* ── 三項演算子 ── */
    case SIR_COND: {
        int Lelse=new_label(), Lend=new_label();
        emit_expr(n->left);     /* 条件 */
        emit("    CMPI A, #0");
        emit("    BEQ  _L_%04d", Lelse);
        emit_expr(n->right);    /* then */
        emit("    JMP  _L_%04d", Lend);
        emit_label(Lelse);
        emit_expr(n->extra);    /* else */
        emit_label(Lend);
        break;
    }

    default:
        warning("emit_expr: unhandled op %d", n->op);
        break;
    }
}

/* ============================================================
 * parse_stmt: 文の解析＋コード生成（軽めIR - emit_expr統合版）
 * ============================================================ */
static void parse_stmt(void) {
    const char *t=next_tok();

    /* 空値マクロスキップ */
    while (1) {
        sym_t *def=sym_find(t);
        if (def&&def->sclass==SC_DEFINE&&def->defval[0]=='\0') {
            const char *nx=next_tok();
            if (strcmp(nx,"(")==0) {
                int depth=1;
                while (depth>0) {
                    const char *tt=next_tok();
                    if (strcmp(tt,"(")==0) depth++;
                    else if (strcmp(tt,")")==0) depth--;
                    else if (strcmp(tt,TOK_EOF)==0) break;
                }
                const char *sc=next_tok();
                if (strcmp(sc,";")!=0) push_tok(sc,cur_ival);
                return;
            } else { push_tok(nx,cur_ival); t=next_tok(); }
        } else break;
    }

    if (strcmp(t,";")==0) return;
    if (strcmp(t,"{")==0) { parse_block(); return; }

    /* [ISA2.3] asm("...") インラインアセンブラ */
    if (strcmp(t,"asm")==0) {
        expect("(");
        /* 文字列リテラルを取得: cur_tok==TOK_STR、実内容はcur_str */
        const char *s = next_tok();
        if (strcmp(s, TOK_STR) != 0) { error("asm: string literal expected"); return; }
        char asmstr[256];
        strncpy(asmstr, cur_str, sizeof(asmstr) - 1);
        asmstr[sizeof(asmstr) - 1] = '\0';
        expect(")");
        expect(";");
        emit_asm_inline(asmstr);
        return;
    }

    /* return */
    if (strcmp(t,"return")==0) {
        const char *nx=next_tok();
        if (strcmp(nx,";")==0) {
            emit("    LDW  A, #0");
        } else {
            push_tok(nx,cur_ival);
            sir_node_t *e=parse_expr();
            emit_expr(e); sir_free(e);
            expect(";");
        }
        /* [A7] return: frame_size分のローカル変数を全解放してエピローグへJMP */
        if (frame_size > 0)
            emit("    ADDI SP, #%d", frame_size);
        emit("    JMP  _L_%04d", func_end_label);
        func_has_return = 1;  /* [A7fix3] 末尾ADDI SP抑制 */
        return;
    }

    /* if */
    if (strcmp(t,"if")==0) {
        expect("(");
        sir_node_t *cond=parse_expr();
        expect(")");
        emit_expr(cond); sir_free(cond);
        int Lelse=new_label(), Lend=new_label();
        emit("    CMPI A, #0");
        emit("    BEQ  _L_%04d", Lelse);
        parse_stmt();
        const char *nx=next_tok();
        if (strcmp(nx,"else")==0) {
            emit("    JMP  _L_%04d", Lend);
            emit_label(Lelse);
            parse_stmt();
            emit_label(Lend);
        } else {
            push_tok(nx,cur_ival);
            emit_label(Lelse);
        }
        return;
    }

    /* while */
    if (strcmp(t,"while")==0) {
        int Ltop=new_label(), Lend=new_label();
        if (loop_depth<MAX_BREAK) {
            break_stack[loop_depth]=Lend;
            cont_stack[loop_depth]=Ltop;
            break_is_switch[loop_depth]=0;
            loop_depth++;
        }
        emit_label(Ltop);
        expect("(");
        sir_node_t *cond=parse_expr();
        expect(")");
        emit_expr(cond); sir_free(cond);
        emit("    CMPI A, #0");
        emit("    BEQ  _L_%04d", Lend);
        parse_stmt();
        emit("    JMP  _L_%04d", Ltop);
        emit_label(Lend);
        if (loop_depth>0) loop_depth--;
        return;
    }

    /* for */
    if (strcmp(t,"for")==0) {
        expect("(");
        int Ltop=new_label(), Lupdate=new_label(), Lbody=new_label(), Lend=new_label();
        if (loop_depth<MAX_BREAK) {
            break_stack[loop_depth]=Lend;
            cont_stack[loop_depth]=Lupdate;
            break_is_switch[loop_depth]=0;
            loop_depth++;
        }
        /* 初期化 */
        { const char *nx=next_tok();
          if (strcmp(nx,";")!=0) { push_tok(nx,cur_ival); parse_stmt(); }
        }
        /* 条件 */
        emit_label(Ltop);
        { const char *nx=next_tok();
          if (strcmp(nx,";")!=0) {
              push_tok(nx,cur_ival);
              sir_node_t *cond=parse_expr(); expect(";");
              emit_expr(cond); sir_free(cond);
              emit("    CMPI A, #0");
              emit("    BEQ  _L_%04d", Lend);
          }
        }
        emit("    JMP  _L_%04d", Lbody);
        /* 更新式 */
        emit_label(Lupdate);
        { const char *nx=next_tok();
          if (strcmp(nx,")")!=0) {
              push_tok(nx,cur_ival);
              /* 更新式: カンマ区切りの式リスト（)まで） */
              for (;;) {
                  sir_node_t *upd=parse_assign();
                  emit_expr(upd); sir_free(upd);
                  const char *sep=next_tok();
                  if (strcmp(sep,")")==0) break;
                  if (strcmp(sep,",")==0) continue;
                  push_tok(sep,cur_ival); break;
              }
          }
        }
        emit("    JMP  _L_%04d", Ltop);
        /* 本体 */
        emit_label(Lbody);
        parse_stmt();
        emit("    JMP  _L_%04d", Lupdate);
        emit_label(Lend);
        if (loop_depth>0) loop_depth--;
        return;
    }

    /* do-while */
    if (strcmp(t,"do")==0) {
        int Ltop=new_label(), Lend=new_label();
        if (loop_depth<MAX_BREAK) {
            break_stack[loop_depth]=Lend;
            cont_stack[loop_depth]=Ltop;
            break_is_switch[loop_depth]=0;
            loop_depth++;
        }
        emit_label(Ltop);
        parse_stmt();
        expect("while"); expect("(");
        sir_node_t *cond=parse_expr();
        expect(")"); expect(";");
        emit_expr(cond); sir_free(cond);
        emit("    CMPI A, #0");
        emit("    BNE  _L_%04d", Ltop);
        emit_label(Lend);
        if (loop_depth>0) loop_depth--;
        return;
    }

    /* switch */
    if (strcmp(t,"switch")==0) {
        expect("(");
        sir_node_t *sw=parse_expr();
        expect(")");
        emit_expr(sw); sir_free(sw);
        emit_push_a();   /* switch値をスタックに保存 */
        int Lend=new_label();
        if (switch_depth<MAX_SWITCH) switch_end[switch_depth++]=Lend;
        if (loop_depth<MAX_BREAK) {
            break_stack[loop_depth]=Lend;
            break_is_switch[loop_depth]=1;
            loop_depth++;
        }
        expect("{");
        for (;;) {
            const char *st=next_tok();
            if (strcmp(st,"}")==0||strcmp(st,TOK_EOF)==0) break;
            if (strcmp(st,"case")==0) {
                sir_node_t *cv=parse_expr(); expect(":");
                emit_expr(cv); sir_free(cv);
                int Lnext=new_label();
                emit("    LDW  B, [SP]");  /* switch値 */
                emit("    CMP  B, A");
                emit("    BNE  _L_%04d", Lnext);
                for (;;) {
                    const char *bt=next_tok();
                    if (strcmp(bt,"case")==0||strcmp(bt,"default")==0||
                        strcmp(bt,"}")==0||strcmp(bt,TOK_EOF)==0)
                        { push_tok(bt,cur_ival); break; }
                    push_tok(bt,cur_ival); parse_stmt();
                }
                emit_label(Lnext);
                continue;
            }
            if (strcmp(st,"default")==0) {
                expect(":");
                for (;;) {
                    const char *bt=next_tok();
                    if (strcmp(bt,"}")==0||strcmp(bt,TOK_EOF)==0)
                        { push_tok(bt,cur_ival); break; }
                    push_tok(bt,cur_ival); parse_stmt();
                }
                continue;
            }
            push_tok(st,cur_ival);
            parse_stmt();
        }
        emit("    ADDI SP, #2");  /* switch値pop */
        emit_label(Lend);
        if (switch_depth>0) switch_depth--;
        if (loop_depth>0) loop_depth--;
        return;
    }

    /* break */
    if (strcmp(t,"break")==0) {
        expect(";");
        if (loop_depth>0) {
            /* [B9] switch break: switch値をpopしてからJMP
             * break_is_switch=1(switch内): ADDI SP,#2してからLendへ
             * break_is_switch=0(ループ内): SPを触らずJMPのみ */
            if (break_is_switch[loop_depth-1])
                emit("    ADDI SP, #2");   /* switch値pop */
            emit("    JMP  _L_%04d", break_stack[loop_depth-1]);
        }
        return;
    }

    /* continue */
    if (strcmp(t,"continue")==0) {
        expect(";");
        if (loop_depth>0) {
            /* [A7] SPを触らずJMPのみ（設計書v1.6 §6.7） */
            emit("    JMP  _L_%04d", cont_stack[loop_depth-1]);
        }
        return;
    }

    /* ローカル変数宣言 */
    typeinfo_t ti;
    if (try_parse_type(t,&ti)) {
        for (;;) {
            int is_ptr=ti.is_ptr, is_array=ti.is_array, arr_size=ti.arr_size, dim2=ti.dim2;
            int sidx=ti.struct_idx;
            ctype_t type=ti.type, base=ti.base;

            const char *nm=next_tok();
            while (strcmp(nm,"*")==0){is_ptr=1;nm=next_tok();}
            char name[IDENT_LEN]; strncpy(name,nm,IDENT_LEN-1);

            const char *nx=next_tok();
            if (strcmp(nx,"[")==0) {
                is_array=1;
                const char *ns=next_tok();
                if (strcmp(ns,TOK_NUM)==0){arr_size=cur_ival;next_tok();}
                nx=next_tok();
                if (strcmp(nx,"[")==0) {
                    const char *ns2=next_tok();
                    if (strcmp(ns2,TOK_NUM)==0){dim2=cur_ival;next_tok();}
                    nx=next_tok();
                }
            }

            int esz;
            if ((type==T_STRUCT||type==T_UNION)&&!is_ptr) {
                esz=(sidx>=0)?structs[sidx].total_size:2;
                if(esz&1)esz++;
            } else {
                esz=(base==T_CHAR&&!is_ptr)?1:2;
                if(esz==1&&!is_array)esz=2;
            }
            int total=is_array?(dim2>0?arr_size*dim2*esz:arr_size*esz):esz;
            if(total&1)total++;

            int var_offset=frame_size;
            frame_size+=total;
            emit("    SUBI SP, #%d", total);

            /* [A7fix3] offset はSUBI SP後の先頭アドレスに対応する値にする
             * real_offset = -(4 + var_offset) がSUBI SP後のSP（＝先頭アドレス）と一致するよう
             * var_offset = frame_size - 2 とする（totalに依らず2バイト境界で先頭を指す）
             * スカラー(total=2): frame_size-2 = 旧frame_size = var_offset_before（変化なし）
             * 配列(total=N): frame_size-2 = 旧frame_size + N - 2（SUBI SP後のSP位置） */
            var_offset = frame_size - 2;

            sym_t *s=sym_alloc();
            strncpy(s->name,name,IDENT_LEN-1);
            s->type=is_ptr?T_PTR:(is_array?T_ARRAY:type);
            s->base=base; s->sclass=SC_LOCAL;
            s->is_array=is_array; s->size=arr_size;
            s->offset=var_offset; s->struct_idx=sidx;
            s->dim2=dim2; local_count++;

            /* 初期化式 */
            if (strcmp(nx,"=")==0) {
                sir_node_t *init=parse_expr();
                emit_expr(init); sir_free(init);
                emit_push_a();          /* [SP] = 値 */
                /* アドレス計算: A = &s */
                int off=real_offset(s);
                emit("    MOV  A, X");
                if (off>0)      emit("    ADDI A, #%d", off);
                else if (off<0) emit("    SUBI A, #%d", -off);
                emit_pop_b();           /* B = 値 */
                emit_store_b_at_a(type==T_CHAR&&!is_ptr); /* [A] = B */
                nx=next_tok();
            }

            if (strcmp(nx,";")==0) break;
            if (strcmp(nx,",")==0) continue;
            push_tok(nx,cur_ival); break;
        }
        return;
    }

    /* 式文（代入・関数呼び出し・++等） */
    push_tok(t,cur_ival);
    sir_node_t *e=parse_expr();
    emit_expr(e); sir_free(e);
    expect(";");
}

static void parse_block_inner(void);

static void parse_block(void) { parse_block_inner(); }

static void parse_block_inner(void) {
    /* [A7] ブロック退出時にSPを操作しない（frame_size方式）
     * frame_size は関数内で累積し続け、return が全解放を担う */
    for (;;) {
        skip_ws();
        while (cur_char=='#') {
            next_char(); skip_ws();
            char dir[32]; int di=0;
            while (isalpha((unsigned char)cur_char)&&di<31)
                { dir[di++]=(char)cur_char; next_char(); }
            dir[di]='\0';
            if (strcmp(dir,"define")==0)      handle_define();
            else if (strcmp(dir,"ifdef")==0)  handle_ifdef(0);
            else if (strcmp(dir,"ifndef")==0) handle_ifdef(1);
            else if (strcmp(dir,"if")==0)     handle_if_directive();
            else if (strcmp(dir,"else")==0) {
                while(cur_char!='\n'&&cur_char!=EOF) next_char();
                if (g_stopped_at_else) { g_stopped_at_else=0; skip_to_endif_only(); }
            }
            else if (strcmp(dir,"endif")==0) {
                while(cur_char!='\n'&&cur_char!=EOF) next_char();
                g_stopped_at_else=0;
            }
            else { while(cur_char!='\n'&&cur_char!=EOF) next_char(); }
            skip_ws();
        }
        const char *t=next_tok();
        if (strcmp(t,"}")==0||strcmp(t,TOK_EOF)==0) break;
        push_tok(t,cur_ival);
        parse_stmt();
    }
    /* [A7] ブロック退出: SPを触らない（設計書v1.6 §6.8） */
}

/* ============================================================
 * ランタイム出力（v2.11から流用）
 * ============================================================ */
static void emit_runtime(void) {
    emit("; ============================================================");
    emit("; C Runtime  org=$%04X", RUNTIME_ORG);
    emit("; ============================================================");
    emit("");

    /* putchar(c): push c → JSR _putchar → ADDI SP,#2
     * JSR後スタック: [SP]=戻りアドレス, [SP+2]=引数
     * XレジスタにSPをセットしてフレームポインタとして使用
     * [X+0]=旧X, [X+2]=戻りアドレス, [X+4]=引数 */
    emit("_putchar:");
    emit("    SUBI SP, #2");
    emit("    STW  X, [SP]");       /* 旧Xを退避 */
    emit("    MOV  X, SP");         /* X = FP */
    emit("    LDW  A, [X + #4]");   /* A = 引数(文字コード) */
    emit("_putchar_wait:");
    emit("    LDW  B, [$FC84]");
    emit("    CMPI B, #0");
    emit("    BEQ  _putchar_wait");
    emit("    STW  A, [$FC80]");
    emit("    LDW  X, [X]");        /* Xを復元 */
    emit("    ADDI SP, #2");
    emit("    RET");
    emit("");

    /* getchar: 戻り値A（UART受信） */
    emit("_getchar:");
    emit("    LDW  A, [$FC84]");
    emit("    CMPI A, #0");
    emit("    BEQ  _getchar");
    emit("    LDW  A, [$FC82]");
    emit("    RET");
    emit("");

    /* puts(str): 文字列を出力して改行を追加
     * フレーム: [X+4]=str ptr */
    emit("_puts:");
    emit("    SUBI SP, #2");
    emit("    STW  X, [SP]");
    emit("    MOV  X, SP");
    emit("    LDW  A, [X + #4]");      /* A = str ptr */
    emit("    STW  A, [$%04X]", C_TMP_ADDR);
    emit("_puts_loop:");
    emit("    SUBI SP, #2");
    emit("    STW  X, [SP]");
    emit("    LDW  X, [$%04X]", C_TMP_ADDR);
    emit("    LDB  A, [X]");           /* A = *ptr */
    emit("    LDW  X, [SP]");
    emit("    ADDI SP, #2");
    emit("    CMPI A, #0");
    emit("    BEQ  _puts_done");
    emit("_puts_wait:");
    emit("    LDW  B, [$FC84]");
    emit("    CMPI B, #0");
    emit("    BEQ  _puts_wait");
    emit("    STW  A, [$FC80]");
    emit("    LDW  A, [$%04X]", C_TMP_ADDR);
    emit("    ADDI A, #1");
    emit("    STW  A, [$%04X]", C_TMP_ADDR);
    emit("    JMP  _puts_loop");
    emit("_puts_done:");
    emit("    LDW  B, [$FC84]");       /* 改行出力 */
    emit("    CMPI B, #0");
    emit("    BEQ  _puts_done");
    emit("    LDW  A, #10");
    emit("    STW  A, [$FC80]");
    emit("    LDW  X, [X]");           /* X復元 */
    emit("    ADDI SP, #2");
    emit("    RET");
    emit("");

    /* strcpy(dst, src): [M23] dst=args[0]→[X+4], src=args[1]→[X+6] */
    emit("_strcpy:");
    emit("    SUBI SP, #2");
    emit("    STW  X, [SP]");
    emit("    MOV  X, SP");
    emit("    ; [M23] dst=args[0]=[X+4], src=args[1]=[X+6]");
    emit("    LDW  A, [X + #4]");  /* dst (args[0]) */
    emit("    STW  A, [$%04X]", C_TMP_ADDR);
    emit("    LDW  B, [X + #6]");  /* src (args[1]) */
    emit("    STW  B, [$%04X]", C_TMP_ADDR+2);
    emit("_strcpy_loop:");
    emit("    SUBI SP, #2");
    emit("    STW  X, [SP]");
    emit("    LDW  X, [$%04X]", C_TMP_ADDR+2);  /* src ptr */
    emit("    LDB  A, [X]");
    emit("    LDW  X, [SP]");
    emit("    ADDI SP, #2");
    emit("    CMPI A, #0");
    emit("    BEQ  _strcpy_done");
    emit("    SUBI SP, #2");
    emit("    STW  X, [SP]");
    emit("    LDW  X, [$%04X]", C_TMP_ADDR);  /* dst ptr */
    emit("    STB  A, [X]");
    emit("    LDW  X, [SP]");
    emit("    ADDI SP, #2");
    /* src++ dst++ */
    emit("    LDW  A, [$%04X]", C_TMP_ADDR);
    emit("    ADDI A, #1");
    emit("    STW  A, [$%04X]", C_TMP_ADDR);
    emit("    LDW  A, [$%04X]", C_TMP_ADDR+2);
    emit("    ADDI A, #1");
    emit("    STW  A, [$%04X]", C_TMP_ADDR+2);
    emit("    JMP  _strcpy_loop");
    emit("_strcpy_done:");
    emit("    SUBI SP, #2");
    emit("    STW  X, [SP]");
    emit("    LDW  X, [$%04X]", C_TMP_ADDR);
    emit("    STB  A, [X]");  /* NUL終端 */
    emit("    LDW  X, [SP]");
    emit("    ADDI SP, #2");
    emit("    LDW  A, [X + #4]");  /* return dst */
    emit("    LDW  X, [X]");
    emit("    ADDI SP, #2");
    emit("    RET");
    emit("");

    /* strcmp(s1, s2): [M23] s1=args[0]=[X+4], s2=args[1]=[X+6] */
    emit("_strcmp:");
    emit("    SUBI SP, #2");
    emit("    STW  X, [SP]");
    emit("    MOV  X, SP");
    emit("    LDW  A, [X + #4]");  /* s1 (args[0]) */
    emit("    STW  A, [$%04X]", C_TMP_ADDR);
    emit("    LDW  A, [X + #6]");  /* s2 (args[1]) */
    emit("    STW  A, [$%04X]", C_TMP_ADDR+2);
    emit("_strcmp_loop:");
    emit("    SUBI SP, #2");
    emit("    STW  X, [SP]");
    emit("    LDW  X, [$%04X]", C_TMP_ADDR);
    emit("    LDB  A, [X]");       /* *s1 */
    emit("    LDW  X, [SP]");
    emit("    ADDI SP, #2");
    emit("    SUBI SP, #2");
    emit("    STW  A, [SP]");      /* save *s1 */
    emit("    SUBI SP, #2");
    emit("    STW  X, [SP]");
    emit("    LDW  X, [$%04X]", C_TMP_ADDR+2);
    emit("    LDB  B, [X]");       /* *s2 */
    emit("    LDW  X, [SP]");
    emit("    ADDI SP, #2");
    emit("    LDW  A, [SP]");      /* restore *s1 */
    emit("    ADDI SP, #2");
    emit("    CMP  A, B");
    emit("    BNE  _strcmp_diff");
    emit("    CMPI A, #0");
    emit("    BEQ  _strcmp_eq");
    /* advance */
    emit("    LDW  A, [$%04X]", C_TMP_ADDR);
    emit("    ADDI A, #1");
    emit("    STW  A, [$%04X]", C_TMP_ADDR);
    emit("    LDW  A, [$%04X]", C_TMP_ADDR+2);
    emit("    ADDI A, #1");
    emit("    STW  A, [$%04X]", C_TMP_ADDR+2);
    emit("    JMP  _strcmp_loop");
    emit("_strcmp_eq:");
    emit("    LDW  A, #0");
    emit("    LDW  X, [X]");
    emit("    ADDI SP, #2");
    emit("    RET");
    emit("_strcmp_diff:");
    emit("    SUB  A, B");
    emit("    LDW  X, [X]");
    emit("    ADDI SP, #2");
    emit("    RET");
    emit("");

    /* memcpy(dst, src, len): [M23] dst=args[0]→[X+4], src=args[1]→[X+6], len=args[2]→[X+8] */
    emit("_memcpy:");
    emit("    SUBI SP, #2");
    emit("    STW  X, [SP]");
    emit("    MOV  X, SP");
    emit("    LDW  A, [X + #4]");  /* dst (args[0]) [M23] */
    emit("    STW  A, [$%04X]", C_MEMCPY_DEST);
    emit("    LDW  A, [X + #6]");  /* src (args[1]) */
    emit("    STW  A, [$%04X]", C_MEMCPY_SRC);
    emit("    LDW  A, [X + #8]");  /* len (args[2]) */
    emit("    STW  A, [$%04X]", C_MEMCPY_CNT);
    emit("_memcpy_loop:");
    emit("    LDW  A, [$%04X]", C_MEMCPY_CNT);
    emit("    CMPI A, #0");
    emit("    BEQ  _memcpy_done");
    emit("    SUBI A, #1");
    emit("    STW  A, [$%04X]", C_MEMCPY_CNT);
    emit("    SUBI SP, #2");
    emit("    STW  X, [SP]");
    emit("    LDW  X, [$%04X]", C_MEMCPY_SRC);
    emit("    LDB  A, [X]");
    emit("    LDW  X, [SP]");
    emit("    ADDI SP, #2");
    emit("    SUBI SP, #2");
    emit("    STW  X, [SP]");
    emit("    LDW  X, [$%04X]", C_MEMCPY_DEST);
    emit("    STB  A, [X]");
    emit("    LDW  X, [SP]");
    emit("    ADDI SP, #2");
    emit("    LDW  A, [$%04X]", C_MEMCPY_SRC);
    emit("    ADDI A, #1");
    emit("    STW  A, [$%04X]", C_MEMCPY_SRC);
    emit("    LDW  A, [$%04X]", C_MEMCPY_DEST);
    emit("    ADDI A, #1");
    emit("    STW  A, [$%04X]", C_MEMCPY_DEST);
    emit("    JMP  _memcpy_loop");
    emit("_memcpy_done:");
    emit("    LDW  A, [X + #4]");  /* return dst (args[0]) */
    emit("    LDW  X, [X]");
    emit("    ADDI SP, #2");
    emit("    RET");
    emit("");

    /* 乗除算ランタイム（EQUシンボル使用・v1.02オンデマンド出力） */
    /* cc_mul: 独立。g_use_mul のときのみ出力 */
    if (g_use_mul) {
    emit("_C_MUL_A EQU $%04X", C_MUL_BASE);
    emit("_C_MUL_B EQU $%04X", C_MUL_BASE + 2);
    emit("_C_MUL_R EQU $%04X", C_MUL_BASE + 4);
    emit("_cc_mul:");
    emit("    STW  A, [_C_MUL_A]");
    emit("    STW  B, [_C_MUL_B]");
    emit("    LDW  A, #0");
    emit("    STW  A, [_C_MUL_R]");
    emit("_ccmul_loop:");
    emit("    LDW  B, [_C_MUL_B]");
    emit("    CMPI B, #0");
    emit("    BEQ  _ccmul_done");
    emit("    ANDI B, #1");
    emit("    BEQ  _ccmul_skip");
    emit("    LDW  A, [_C_MUL_R]");
    emit("    LDW  B, [_C_MUL_A]");
    emit("    ADD  A, B");
    emit("    STW  A, [_C_MUL_R]");
    emit("_ccmul_skip:");
    emit("    LDW  A, [_C_MUL_A]");
    emit("    LDW  B, #1");
    emit("    SHL  A, B");
    emit("    STW  A, [_C_MUL_A]");
    emit("    LDW  A, [_C_MUL_B]");
    emit("    SHR  A, B");
    emit("    STW  A, [_C_MUL_B]");
    emit("    JMP  _ccmul_loop");
    emit("_ccmul_done:");
    emit("    LDW  A, [_C_MUL_R]");
    emit("    RET");
    emit("");
    } /* if g_use_mul */

    /* _C_DIV_A/B/Q の EQU は cc_div 本体と cc_mod の両方が参照する（§2.4 依存）
       → 出力条件は (g_use_div || g_use_mod)。cc_mod 単独でも未定義にならない */
    if (g_use_div || g_use_mod) {
    emit("_C_DIV_A EQU $%04X", C_DIV_BASE);
    emit("_C_DIV_B EQU $%04X", C_DIV_BASE + 2);
    emit("_C_DIV_Q EQU $%04X", C_DIV_BASE + 4);
    } /* if div||mod */

    /* cc_div: body は g_use_div のときのみ */
    if (g_use_div) {
    emit("_cc_div:");
    emit("    CMPI A, #0");
    emit("    BEQ  _ccdiv_zero");
    emit("    STW  A, [_C_DIV_A]");
    emit("    STW  B, [_C_DIV_B]");
    emit("    LDW  A, #0");
    emit("    STW  A, [_C_DIV_Q]");
    emit("_ccdiv_loop:");
    emit("    LDW  A, [_C_DIV_B]");
    emit("    LDW  B, [_C_DIV_A]");
    emit("    CMP  A, B");
    emit("    BLT  _ccdiv_done");
    emit("    SUB  A, B");
    emit("    STW  A, [_C_DIV_B]");
    emit("    LDW  A, [_C_DIV_Q]");
    emit("    ADDI A, #1");
    emit("    STW  A, [_C_DIV_Q]");
    emit("    JMP  _ccdiv_loop");
    emit("_ccdiv_done:");
    emit("    LDW  A, [_C_DIV_Q]");
    emit("    RET");
    emit("_ccdiv_zero:");
    emit("    LDW  A, #0");
    emit("    RET");
    emit("");
    } /* if g_use_div */

    /* cc_mod: body は g_use_mod のときのみ（_C_DIV_A/B は上の if で定義済） */
    if (g_use_mod) {
    emit("_cc_mod:");
    emit("    STW  A, [_C_DIV_A]");
    emit("    STW  B, [_C_DIV_B]");
    emit("_ccmod_loop:");
    emit("    LDW  A, [_C_DIV_B]");
    emit("    LDW  B, [_C_DIV_A]");
    emit("    CMP  A, B");
    emit("    BLT  _ccmod_done");
    emit("    SUB  A, B");
    emit("    STW  A, [_C_DIV_B]");
    emit("    JMP  _ccmod_loop");
    emit("_ccmod_done:");
    emit("    LDW  A, [_C_DIV_B]");
    emit("    RET");
    emit("");
    } /* if g_use_mod */

    /* ===== [v2.00 Step7] _fmul: Q8.8乗算 r=(a*b)>>8 (§2.5.3) =====
     * 入口: A=a(被乗数Q8.8), B=b(乗数Q8.8)。出口: A=result(Q8.8)。
     * アルゴリズム(プロト3・C先行検証済NG=0): 符号分離→絶対値→
     *   for i=0..15: if(WB&1){ i>=8: WR+=WA<<(i-8); else WR+=WA>>(8-i); } WB>>=1
     *   最後に符号適用。
     * ワーク(案A・§2.5.2範囲): WA=cc_mul領域, WB,WR=cc_mul領域, WSIGN=cc_div先頭1B借用。
     *   _C_MUL_A=$DBF4(WA), _C_MUL_B=$DBF6(WB), _C_MUL_R=$DBF8(WR),
     *   _C_DIV_A=$DBFA を符号フラグに借用(float中はcc_div非走行)。
     * 注: _C_MUL_A/B/R, _C_DIV_A のEQUは g_use_mul / (g_use_div||g_use_mod) 側で
     *   出力されるが、float単独使用時は未定義になるため、ここで未定義なら出力する。 */
    if (g_use_fmul) {
    /* EQU未定義対策: mul/div未使用でfloatのみのとき、必要なEQUをここで定義 */
    if (!g_use_mul) {
        emit("_C_MUL_A EQU $%04X", C_MUL_BASE);
        emit("_C_MUL_B EQU $%04X", C_MUL_BASE + 2);
        emit("_C_MUL_R EQU $%04X", C_MUL_BASE + 4);
    }
    if (!(g_use_div || g_use_mod)) {
        emit("_C_DIV_A EQU $%04X", C_DIV_BASE);
    }
    /* 入口: A=a(被乗数), B=b(乗数)。WSIGN=$DBFA, WA=$DBF4, WB=$DBF6, WR=$DBF8 */
    emit("_fmul:");
    emit("    PUSH X");                    /* [FIX 2026-06-24] callee-save X(フレームポインタ保護) */
    emit("    STW  A, [_C_MUL_A]");        /* WA = a */
    emit("    STW  B, [_C_MUL_B]");        /* WB = b */
    emit("    LDW  A, #0");
    emit("    STW  A, [_C_DIV_A]");        /* WSIGN = 0 */
    emit("    STW  A, [_C_MUL_R]");        /* WR = 0 */
    /* aの符号: WA<0 なら WSIGN^=1, WA=-WA(2の補数 NOT+1) */
    emit("    LDW  A, [_C_MUL_A]");
    emit("    CMPI A, #0");
    emit("    BGE  _fmul_a_pos");
    emit("    NOT  A");
    emit("    ADDI A, #1");
    emit("    STW  A, [_C_MUL_A]");
    emit("    LDW  A, [_C_DIV_A]");        /* WSIGN ^= 1 */
    emit("    XORI A, #1");
    emit("    STW  A, [_C_DIV_A]");
    emit("_fmul_a_pos:");
    /* bの符号: WB<0 なら WSIGN^=1, WB=-WB */
    emit("    LDW  A, [_C_MUL_B]");
    emit("    CMPI A, #0");
    emit("    BGE  _fmul_b_pos");
    emit("    NOT  A");
    emit("    ADDI A, #1");
    emit("    STW  A, [_C_MUL_B]");
    emit("    LDW  A, [_C_DIV_A]");
    emit("    XORI A, #1");
    emit("    STW  A, [_C_DIV_A]");
    emit("_fmul_b_pos:");
    /* ループ: i=0..15。i はレジスタ X で管理。 */
    emit("    LDW  X, #0");                /* i = 0 */
    emit("_fmul_loop:");
    emit("    CMPI X, #16");
    emit("    BGE  _fmul_loop_end");
    /* WB の最下位ビット判定 */
    emit("    LDW  A, [_C_MUL_B]");
    emit("    ANDI A, #1");
    emit("    BEQ  _fmul_skip");
    /* 寄与 term を計算: i>=8 ? WA<<(i-8) : WA>>(8-i) */
    emit("    LDW  A, [_C_MUL_A]");        /* A = WA */
    emit("    CMPI X, #8");
    emit("    BLT  _fmul_rsh");
    /* i>=8: B = i-8, term = WA << B */
    emit("    MOV  B, X");
    emit("    SUBI B, #8");
    emit("    SHL  A, B");
    emit("    JMP  _fmul_add");
    emit("_fmul_rsh:");
    /* i<8: B = 8-i, term = WA >> B (論理。WAは正) */
    emit("    LDW  B, #8");
    emit("    SUB  B, X");                 /* B = 8 - i */
    emit("    SHR  A, B");
    emit("_fmul_add:");
    /* WR += term(A) */
    emit("    LDW  B, [_C_MUL_R]");
    emit("    ADD  A, B");
    emit("    STW  A, [_C_MUL_R]");
    emit("_fmul_skip:");
    /* WB >>= 1 (論理右シフト1) */
    emit("    LDW  A, [_C_MUL_B]");
    emit("    LDW  B, #1");
    emit("    SHR  A, B");
    emit("    STW  A, [_C_MUL_B]");
    /* i++ */
    emit("    ADDI X, #1");
    emit("    JMP  _fmul_loop");
    emit("_fmul_loop_end:");
    /* 符号適用: WSIGN!=0 なら WR=-WR */
    emit("    LDW  A, [_C_DIV_A]");
    emit("    CMPI A, #0");
    emit("    BEQ  _fmul_ret");
    emit("    LDW  A, [_C_MUL_R]");
    emit("    NOT  A");
    emit("    ADDI A, #1");
    emit("    STW  A, [_C_MUL_R]");
    emit("_fmul_ret:");
    emit("    LDW  A, [_C_MUL_R]");
    emit("    POP  X");                    /* [FIX 2026-06-24] restore X */
    emit("    RET");
    emit("");
    } /* if g_use_fmul */

    /* ===== [v2.00 Step7] _fdiv: Q8.8除算 r=(a<<8)/b (§6.5) =====
     * 入口: A=a(被除数Q8.8), B=b(除数Q8.8)。出口: A=result(Q8.8)。
     * アルゴリズム(プロト3・C検証済NG=0): 符号分離→絶対値→24ループ長除算。
     *   被除数 na<<8 を上位ビットから供給(前半16=naのMSB, 後半8=0)。
     *   各ループ: WR=(WR<<1)|bit; WQ<<=1; if(WR>=WD){WR-=WD;WQ|=1} 前半はWN<<=1。
     * 0除算: 商0返し(設計§6.5)。負数除算: 符号分離で対応(§6.5は本来非負前提だが符号対応済)。
     * ワーク(案A・§2.5.2範囲: cc_mul+cc_div領域共用):
     *   WN=$DBF4, WD=$DBF6, WQ=$DBF8 (cc_mul領域), WR=$DBFA, WSIGN=$DBFC (cc_div領域)。 */
    if (g_use_fdiv) {
    if (!g_use_mul && !g_use_fmul) {
        emit("_C_MUL_A EQU $%04X", C_MUL_BASE);
        emit("_C_MUL_B EQU $%04X", C_MUL_BASE + 2);
        emit("_C_MUL_R EQU $%04X", C_MUL_BASE + 4);
    }
    if (!(g_use_div || g_use_mod)) {
        if (!g_use_fmul) emit("_C_DIV_A EQU $%04X", C_DIV_BASE);
        emit("_C_DIV_B EQU $%04X", C_DIV_BASE + 2);
    } else {
        /* div/mod使用時は _C_DIV_B 既定義。_C_DIV_A も既定義 */
    }
    /* WN=_C_MUL_A, WD=_C_MUL_B, WQ=_C_MUL_R, WR=_C_DIV_A, WSIGN=_C_DIV_B */
    emit("_fdiv:");
    emit("    PUSH X");                    /* [FIX 2026-06-24] callee-save X */
    /* [FIX 2026-06-24] emit規約: A=除数(right), B=被除数(left)。cc_divと同一規約に統一。
       0除算チェックは除数=A==0。WN(被除数)<-B, WD(除数)<-A で読み替え（A<->B swap）。
       旧: A=被除数前提で逆数バグ。SIR_DIV(正常)とemit規約が同一であることを確認済。 */
    emit("    CMPI A, #0");
    emit("    BNE  _fdiv_nz");
    emit("    LDW  A, #0");
    emit("    POP  X");                    /* [FIX 2026-06-24] restore X (0除算経路) */
    emit("    RET");
    emit("_fdiv_nz:");
    emit("    STW  B, [_C_MUL_A]");        /* WN = 被除数(=B=left) [FIX 2026-06-24] */
    emit("    STW  A, [_C_MUL_B]");        /* WD = 除数(=A=right)  [FIX 2026-06-24] */
    emit("    LDW  A, #0");
    emit("    STW  A, [_C_DIV_B]");        /* WSIGN = 0 */
    emit("    STW  A, [_C_MUL_R]");        /* WQ = 0 */
    emit("    STW  A, [_C_DIV_A]");        /* WR = 0 */
    /* aの符号 */
    emit("    LDW  A, [_C_MUL_A]");
    emit("    CMPI A, #0");
    emit("    BGE  _fdiv_a_pos");
    emit("    NOT  A");
    emit("    ADDI A, #1");
    emit("    STW  A, [_C_MUL_A]");
    emit("    LDW  A, [_C_DIV_B]");
    emit("    XORI A, #1");
    emit("    STW  A, [_C_DIV_B]");
    emit("_fdiv_a_pos:");
    /* bの符号 */
    emit("    LDW  A, [_C_MUL_B]");
    emit("    CMPI A, #0");
    emit("    BGE  _fdiv_b_pos");
    emit("    NOT  A");
    emit("    ADDI A, #1");
    emit("    STW  A, [_C_MUL_B]");
    emit("    LDW  A, [_C_DIV_B]");
    emit("    XORI A, #1");
    emit("    STW  A, [_C_DIV_B]");
    emit("_fdiv_b_pos:");
    /* ループ i=0..23。i は X。 */
    emit("    LDW  X, #0");
    emit("_fdiv_loop:");
    emit("    CMPI X, #24");
    emit("    BGE  _fdiv_loop_end");
    /* --- bit を A に作る（前半i<16: WN MSB、後半: 0）。同時にWN<<=1（前半のみ）--- */
    emit("    CMPI X, #16");
    emit("    BGE  _fdiv_bit0");
    /* 前半: A = (WN>>15)&1 */
    emit("    LDW  A, [_C_MUL_A]");
    emit("    LDW  B, #15");
    emit("    SHR  A, B");
    emit("    ANDI A, #1");
    /* WN <<= 1 */
    emit("    LDW  B, [_C_MUL_A]");
    emit("    PUSH A");                     /* bit退避 */
    emit("    MOV  A, B");
    emit("    LDW  B, #1");
    emit("    SHL  A, B");
    emit("    STW  A, [_C_MUL_A]");
    emit("    POP  A");                      /* bit復帰 */
    emit("    JMP  _fdiv_haverbit");
    emit("_fdiv_bit0:");
    emit("    LDW  A, #0");
    emit("_fdiv_haverbit:");
    /* --- WR = (WR<<1) | bit(A) --- */
    emit("    LDW  B, [_C_DIV_A]");          /* B = WR */
    emit("    PUSH A");                       /* bit退避 */
    emit("    MOV  A, B");
    emit("    LDW  B, #1");
    emit("    SHL  A, B");                    /* A = WR<<1 */
    emit("    MOV  B, A");                    /* B = WR<<1 */
    emit("    POP  A");                       /* A = bit */
    emit("    OR   B, A");                    /* B = (WR<<1)|bit */
    emit("    STW  B, [_C_DIV_A]");           /* WR = B */
    /* --- WQ <<= 1 --- */
    emit("    LDW  A, [_C_MUL_R]");
    emit("    LDW  B, #1");
    emit("    SHL  A, B");
    emit("    STW  A, [_C_MUL_R]");
    /* --- if WR >= WD: WR-=WD; WQ|=1 --- (符号なし比較が要るが値は正なのでCMP/BLTで可) */
    emit("    LDW  A, [_C_DIV_A]");           /* A = WR */
    emit("    LDW  B, [_C_MUL_B]");           /* B = WD */
    emit("    CMP  A, B");                     /* A - B, flags */
    emit("    BLT  _fdiv_noupd");             /* WR < WD ならスキップ */
    emit("    SUB  A, B");                     /* A = WR - WD */
    emit("    STW  A, [_C_DIV_A]");           /* WR = WR - WD */
    emit("    LDW  A, [_C_MUL_R]");
    emit("    ORI  A, #1");                    /* WQ |= 1 */
    emit("    STW  A, [_C_MUL_R]");
    emit("_fdiv_noupd:");
    emit("    ADDI X, #1");
    emit("    JMP  _fdiv_loop");
    emit("_fdiv_loop_end:");
    /* 符号適用 */
    emit("    LDW  A, [_C_DIV_B]");
    emit("    CMPI A, #0");
    emit("    BEQ  _fdiv_ret");
    emit("    LDW  A, [_C_MUL_R]");
    emit("    NOT  A");
    emit("    ADDI A, #1");
    emit("    STW  A, [_C_MUL_R]");
    emit("_fdiv_ret:");
    emit("    LDW  A, [_C_MUL_R]");
    emit("    POP  X");                    /* [FIX 2026-06-24] restore X */
    emit("    RET");
    emit("");
    } /* if g_use_fdiv */
}

/* ============================================================
 * データセクション出力（v2.11から流用）
 * ============================================================ */
static void emit_data_section(void) {
    emit("");
    emit("; ============================================================");
    emit("; Data section  org=$%04X", DATA_ORG);
    emit("; ============================================================");
    emit("    .org $%04X", DATA_ORG);

    /* [M25] sym_tableは逆順(最後宣言が先頭)のため、data_offset(宣言順)でソートして出力 */
    /* グローバルシンボルを収集してoffset昇順でソート */
    int gcnt=0;
    for(sym_t *s=sym_table;s;s=s->next) if(s->sclass==SC_GLOBAL) gcnt++;
    sym_t **garr=(sym_t**)malloc(gcnt*sizeof(sym_t*));
    int gi=0;
    for(sym_t *s=sym_table;s;s=s->next) if(s->sclass==SC_GLOBAL) garr[gi++]=s;
    /* offsetで昇順ソート(バブルソート) */
    for(int i=0;i<gcnt-1;i++) for(int j=i+1;j<gcnt;j++)
        if(garr[i]->offset>garr[j]->offset){sym_t*tmp=garr[i];garr[i]=garr[j];garr[j]=tmp;}

    for(int gi2=0;gi2<gcnt;gi2++) {
        sym_t *s=garr[gi2];
        if (s->is_array) {
            /* [F3] esz: 論理サイズ（sizeof相当）/ 実配置はDW統一 */
            int esz_logical;
            if (s->base==T_STRUCT||s->base==T_UNION) {
                int si2=s->struct_idx;
                esz_logical=(si2>=0)?structs[si2].total_size:2;
                if(esz_logical&1)esz_logical++;
            } else esz_logical=(s->base==T_CHAR)?1:2;
            int total=(s->dim2>0)?s->size*s->dim2*esz_logical:s->size*esz_logical;
            int out_bytes=(total+1)&~1;  /* DW単位に切り上げ */
            fprintf(out_fp,"_%s:\n",s->name);
            for (int i=0;i<out_bytes;i+=2)
                fprintf(out_fp,"    DW  0\n");
        } else if (s->type==T_STRUCT||s->type==T_UNION) {
            int sz=(s->struct_idx>=0)?structs[s->struct_idx].total_size:2;
            if(sz&1)sz++;
            fprintf(out_fp,"_%s:\n",s->name);
            for (int i=0;i<sz;i+=2) fprintf(out_fp,"    DW  0\n");
        } else {
            /* [M26] char scalar also uses 2 bytes to match offset calculation */
            fprintf(out_fp,"_%s:\n    DW  0\n",s->name);
        }
    }
    free(garr);

    if (strlit_list) {
        emit(""); emit("; String literal pool");
        for (strlit_t *sl=strlit_list; sl; sl=sl->next) {
            fprintf(out_fp,"_S_%04d:\n    DB  ",sl->id);
            for (int i=0;i<=sl->len;i++) {
                fprintf(out_fp,"%d",(unsigned char)sl->text[i]);
                if(i<sl->len) fprintf(out_fp,", ");
            }
            fprintf(out_fp,"\n");
            /* [P4] v1.01: 文字列リテラルの2バイトアライメント保証
             * len+1 (NUL含む長さ) が奇数なら DB 0 でパディング */
            if (((sl->len + 1) % 2) != 0) {
                fprintf(out_fp,"    DB  0\n");
            }
        }
    }
}

/* ============================================================
 * グローバル宣言・関数定義解析
 * ============================================================ */
static void parse_global(void);

static void parse_global(void) {
    const char *t=next_tok();
    if (strcmp(t,TOK_EOF)==0) return;

    /* '#'が来たら行末まで読み飛ばす（main loopで処理済みのはずだが念のため）*/
    if (t[0]=='#') { while(cur_char!='\n'&&cur_char!=EOF) next_char(); return; }

    /* 空値マクロ（REG, my_printf等）をスキップ */
    while (1) {
        sym_t *def=sym_find(t);
        if (def&&def->sclass==SC_DEFINE&&def->defval[0]=='\0') {
            const char *nx=next_tok();
            if (strcmp(nx,"(")==0) {
                int depth=1;
                while (depth>0) {
                    const char *tt=next_tok();
                    if (strcmp(tt,"(")==0) depth++;
                    else if (strcmp(tt,")")==0) depth--;
                    else if (strcmp(tt,TOK_EOF)==0) break;
                }
                const char *sc=next_tok();
                if (strcmp(sc,";")!=0) push_tok(sc,cur_ival);
                return;
            } else { push_tok(nx,cur_ival); t=next_tok(); }
        } else break;
    }
    if (strcmp(t,TOK_EOF)==0) return;

    /* typedef （v2.11から移植・複数typedef名対応）*/
    if (strcmp(t,"typedef")==0) {
        const char *tx=next_tok();

        /* typedef enum { ... } Name; の特別処理 */
        if (strcmp(tx,"enum")==0) {
            const char *etag=next_tok();
            int has_body=0;
            if (strcmp(etag,"{")==0) { push_tok(etag,cur_ival); has_body=1; }
            else {
                const char *nx2=next_tok();
                if (strcmp(nx2,"{")==0) { push_tok(nx2,cur_ival); has_body=1; }
                else push_tok(nx2,cur_ival);
            }
            if (has_body) {
                expect("{");
                int val=0;
                for (;;) {
                    const char *en=next_tok();
                    if (strcmp(en,"}")==0||strcmp(en,TOK_EOF)==0) break;
                    if (strcmp(en,",")==0) continue;
                    char ename[IDENT_LEN]; strncpy(ename,en,IDENT_LEN-1);
                    const char *nx3=next_tok();
                    if (strcmp(nx3,"=")==0) {
                        const char *nv=next_tok();
                        if (strcmp(nv,TOK_NUM)==0) val=cur_ival;
                        nx3=next_tok();
                    }
                    push_tok(nx3,cur_ival);
                    sym_t *es=sym_alloc();
                    strncpy(es->name,ename,IDENT_LEN-1);
                    es->sclass=SC_ENUM_VAL; es->ival=val++;
                }
            }
            /* typedef名（複数可） */
            const char *tdname=next_tok();
            if (strcmp(tdname,";")==0) return;
            typedef_add(tdname,T_INT,T_INT,0,0,0,-1,-1);
            const char *sep=next_tok();
            while (strcmp(sep,",")==0) {
                const char *nm2=next_tok();
                typedef_add(nm2,T_INT,T_INT,0,0,0,-1,-1);
                sep=next_tok();
            }
            if (strcmp(sep,";")!=0) push_tok(sep,cur_ival);
            return;
        }

        /* typedef struct/union/int/char/... Name[, *Name2]; */
        typeinfo_t ti;
        if (!try_parse_type(tx,&ti)) {
            error("expected type after typedef, got '%s'",tx);
            while (strcmp(next_tok(),";")!=0&&strcmp(cur_tok,TOK_EOF)!=0);
            return;
        }

        /* struct/union本体定義が続く場合 */
        if ((ti.type==T_STRUCT||ti.type==T_UNION)&&ti.struct_idx>=0) {
            const char *nx=next_tok();
            if (strcmp(nx,"{")==0) { push_tok(nx,cur_ival); parse_struct_body(ti.struct_idx); nx=next_tok(); }
            push_tok(nx,cur_ival);
        }

        /* 複数のtypedef名を処理（例: typedef struct {...} Rec_Type, *Rec_Pointer;）*/
        for (;;) {
            int is_ptr=ti.is_ptr, is_array=0, arr_size=0, dim2=-1, sidx=ti.struct_idx;
            const char *nm=next_tok();
            while (strcmp(nm,"*")==0) { is_ptr=1; nm=next_tok(); }
            char tdname[IDENT_LEN]; strncpy(tdname,nm,IDENT_LEN-1);
            const char *nx=next_tok();
            if (strcmp(nx,"[")==0) {
                is_array=1;
                const char *ns=next_tok();
                if (strcmp(ns,TOK_NUM)==0) { arr_size=cur_ival; next_tok(); }
                nx=next_tok();
                if (strcmp(nx,"[")==0) {
                    const char *ns2=next_tok();
                    if (strcmp(ns2,TOK_NUM)==0) { dim2=cur_ival; next_tok(); }
                    nx=next_tok();
                }
            }
            ctype_t ttype=is_ptr?T_PTR:(is_array?T_ARRAY:ti.type);
            typedef_add(tdname,ttype,ti.base,is_ptr,is_array,arr_size,sidx,dim2);
            if (strcmp(nx,";")==0) return;
            if (strcmp(nx,",")==0) continue;
            push_tok(nx,cur_ival);
            return;
        }
    }

    /* enum */
    if (strcmp(t,"enum")==0) {
        const char *tag=next_tok();
        const char *nx=(strcmp(tag,"{")==0)?tag:next_tok();
        if (strcmp(nx,"{")==0) {
            int val=0;
            for (;;) {
                const char *en=next_tok();
                if (strcmp(en,"}")==0||strcmp(en,TOK_EOF)==0) break;
                if (strcmp(en,",")==0) continue;
                char ename[IDENT_LEN]; strncpy(ename,en,IDENT_LEN-1);
                const char *eq=next_tok();
                if (strcmp(eq,"=")==0) {
                    const char *ev=next_tok();
                    if (strcmp(ev,TOK_NUM)==0) val=cur_ival;
                    else push_tok(ev,cur_ival);
                } else push_tok(eq,cur_ival);
                sym_t *es=sym_find(ename);
                if (!es) es=sym_alloc();
                strncpy(es->name,ename,IDENT_LEN-1);
                es->sclass=SC_ENUM_VAL; es->ival=val++;
            }
        }
        const char *semi=next_tok();
        if (strcmp(semi,";")!=0) push_tok(semi,cur_ival);
        return;
    }

    /* struct/union グローバル定義 */
    if (strcmp(t,"struct")==0||strcmp(t,"union")==0) {
        int is_union=(strcmp(t,"union")==0);
        const char *tag=next_tok();
        int sidx;
        if (strcmp(tag,"{")==0) { sidx=struct_new("",is_union); push_tok(tag,cur_ival); }
        else { sidx=struct_find(tag,is_union); if(sidx<0)sidx=struct_new(tag,is_union); }
        const char *nx=next_tok();
        if (strcmp(nx,"{")==0) { push_tok(nx,cur_ival); parse_struct_body(sidx); nx=next_tok(); }
        if (strcmp(nx,";")==0) return;
        push_tok(nx,cur_ival);
        typeinfo_t ti2; memset(&ti2,0,sizeof(ti2));
        ti2.type=is_union?T_UNION:T_STRUCT; ti2.base=ti2.type;
        ti2.struct_idx=sidx; ti2.dim2=-1;
        for (;;) {
            int ip=0,ia=0,as=0,d2=-1;
            const char *nm=next_tok();
            while(strcmp(nm,"*")==0){ip=1;nm=next_tok();}
            char name[IDENT_LEN]; strncpy(name,nm,IDENT_LEN-1);
            const char *ox=next_tok();
            if(strcmp(ox,"[")==0){ia=1;const char *ns=next_tok();if(strcmp(ns,TOK_NUM)==0){as=cur_ival;next_tok();}ox=next_tok();
                if(strcmp(ox,"[")==0){const char *ns2=next_tok();if(strcmp(ns2,TOK_NUM)==0){d2=cur_ival;next_tok();}ox=next_tok();}}
            int esz=(structs[sidx].total_size>0)?structs[sidx].total_size:2;
            if(esz&1)esz++;
            int total=ia?(as*(d2>0?d2*esz:esz)):esz;
            sym_t *gs=sym_alloc();
            strncpy(gs->name,name,IDENT_LEN-1);
            gs->type=ip?T_PTR:(ia?T_ARRAY:(is_union?T_UNION:T_STRUCT));
            gs->base=ti2.base; gs->sclass=SC_GLOBAL;
            gs->is_array=ia; gs->size=as;
            gs->offset=data_offset; gs->struct_idx=sidx; gs->dim2=d2;
            data_offset+=total;
            if(strcmp(ox,",")==0)continue;
            if(strcmp(ox,";")==0)return;
            if(strcmp(ox,"=")==0){while(strcmp(next_tok(),";")!=0);}
            return;
        }
    }

    /* ストレージクラス修飾子 */
    int is_extern=0;
    while (strcmp(t,"extern")==0||strcmp(t,"static")==0||
           strcmp(t,"volatile")==0||strcmp(t,"const")==0||
           strcmp(t,"register")==0) {
        if(strcmp(t,"extern")==0)is_extern=1;
        t=next_tok();
    }

    /* 型 */
    typeinfo_t ti;
    if (!try_parse_type(t,&ti)) {
        if(strcmp(t,TOK_EOF)==0)return;
        char name[IDENT_LEN]; strncpy(name,t,IDENT_LEN-1);
        const char *nx=next_tok();
        if(strcmp(nx,"(")==0){
            ti.type=T_INT;ti.base=T_INT;ti.struct_idx=-1;ti.dim2=-1;
            goto parse_func;
        }
        error("expected type declaration, got '%s'",t);
        while(strcmp(next_tok(),";")!=0&&strcmp(cur_tok,TOK_EOF)!=0);
        return;
    }

    if((ti.type==T_STRUCT||ti.type==T_UNION)&&ti.struct_idx>=0){
        const char *nx=next_tok();
        if(strcmp(nx,"{")==0){push_tok(nx,cur_ival);parse_struct_body(ti.struct_idx);nx=next_tok();}
        if(strcmp(nx,";")==0)return;
        push_tok(nx,cur_ival);
    }

    {
    int is_ptr=ti.is_ptr;
    const char *nm=next_tok();
    while(strcmp(nm,"*")==0){is_ptr=1;nm=next_tok();}
    char name[IDENT_LEN]; strncpy(name,nm,IDENT_LEN-1);
    const char *nx=next_tok();

    if(strcmp(nx,"(")==0){
        char fname[IDENT_LEN]; strncpy(fname,name,IDENT_LEN-1);
        int is_ptr = 0; /* suppress uninitialized warning */
        parse_func:
        {
        sym_t *fs=sym_find(fname);
        if(!fs)fs=sym_alloc();
        strncpy(fs->name,fname,IDENT_LEN-1);
        fs->type=is_ptr?T_PTR:ti.type; fs->sclass=SC_FUNC; fs->defined=1;
        fs->base=is_ptr?T_PTR:ti.base; /* [FIX 2026-06-25] 戻り値baseも記録(float伝播) */
        cur_func=fs;
        local_count=0;param_count=0;frame_size=0;loop_depth=0;func_has_return=0;
        func_end_label=new_label();

        const char *pt=next_tok();
        int pcount=0;
        /* [M23] param offset fix: collect sym ptrs, rewrite after pcount known */
        sym_t *param_syms[MAX_PARAM];
        if(strcmp(pt,")")!=0){
            push_tok(pt,cur_ival);
            for(;;){
                const char *ptt=next_tok();
                if(strcmp(ptt,"void")==0){
                    const char *nx2=next_tok();
                    if(strcmp(nx2,")")==0)break;
                    push_tok(nx2,cur_ival);
                }
                typeinfo_t pti;
                if(try_parse_type(ptt,&pti)){
                    int pp=pti.is_ptr||pti.is_array;
                    const char *pn=next_tok();
                    while(strcmp(pn,"*")==0){pp=1;pn=next_tok();}
                    char pname[IDENT_LEN];
                    if(strcmp(pn,")")==0||strcmp(pn,",")==0){
                        snprintf(pname,IDENT_LEN,"_p%d",pcount);
                        push_tok(pn,cur_ival);
                    } else {
                        strncpy(pname,pn,IDENT_LEN-1);
                        const char *nx2=next_tok();
                        if(strcmp(nx2,"[")==0){
                            pp=1;
                            while(strcmp(next_tok(),"]")!=0&&strcmp(cur_tok,TOK_EOF)!=0);
                            nx2=next_tok();
                            if(strcmp(nx2,"[")==0){
                                while(strcmp(next_tok(),"]")!=0&&strcmp(cur_tok,TOK_EOF)!=0);
                                nx2=next_tok();
                            }
                        }
                        if(strcmp(nx2,")")!=0&&strcmp(nx2,",")!=0) push_tok(nx2,cur_ival);
                        else push_tok(nx2,cur_ival);
                    }
                    sym_t *ps=sym_alloc();
                    strncpy(ps->name,pname,IDENT_LEN-1);
                    ps->type=pp?T_PTR:pti.type; ps->base=pti.base;
                    ps->sclass=SC_PARAM; ps->offset=pcount*2; /* temp; fixed below [M23] */
                    ps->struct_idx=pti.struct_idx;
                    ps->is_array=pti.is_array; ps->size=pti.arr_size; ps->dim2=pti.dim2;
                    if(pcount<MAX_PARAM) param_syms[pcount]=ps;
                    pcount++; param_count++;
                } else {
                    push_tok(ptt,cur_ival); break;
                }
                const char *sep=next_tok();
                if(strcmp(sep,")")==0)break;
                if(strcmp(sep,",")==0)continue;
                push_tok(sep,cur_ival); break;
            }
        }
        /* [M23] C calling conv: right-to-left push
         * leftmost param is pushed last -> lands at [X+4]
         * offset = 4 + (pcount-1-i)*2  */
        /* [M23] Right-to-left push: args[n-1] first → highest offset
         * args[0] pushed last → lowest offset [X+4]
         * Callee uses offset = 4+i*2:
         *   i=0 (args[0]) → [X+4]  (pushed last  = on top before JSR)
         *   i=1 (args[1]) → [X+6]  (pushed earlier)
         * Runtime functions (putchar/strcpy etc.) use [X+4]=args[0] */
        for(int _pi=0;_pi<pcount&&_pi<MAX_PARAM;_pi++){
            param_syms[_pi]->offset = 4 + _pi*2;
        }

        const char *body=next_tok();
        if(strcmp(body,";")==0){sym_pop_locals();cur_func=NULL;return;}
        if(strcmp(body,"{")==0){
            static const char *builtins[]={"putchar","getchar","puts","printf","sprintf","strcpy","strcmp","memcpy","strlen",NULL};
            int is_builtin=0;
            for(int bi=0;builtins[bi];bi++){if(strcmp(fname,builtins[bi])==0){is_builtin=1;break;}}
            if(is_builtin){
                int bd=1;
                while(bd>0){
                    const char *tt=next_tok();
                    if(strcmp(tt,"{")==0)bd++;
                    else if(strcmp(tt,"}")==0)bd--;
                    else if(strcmp(tt,TOK_EOF)==0){error("unexpected EOF in builtin '%s'",fname);break;}
                }
                sym_pop_locals();cur_func=NULL;return;
            }
            g_insbuf_on = 1;          /* [v2.01] 関数命令列バッファ開始 */
            emit("");
            emit("; --- %s ---", fname);
            emit("_%s:", fname);
            emit("    SUBI SP, #2");
            emit("    STW  X, [SP]");
            emit("    MOV  X, SP");
            emit("    SUBI SP, #2");  /* [M25] guard word: local base at [X-4] */
            /* [A7] frame_size方式: parse_block_inner()はブロック退出時にSP操作しない
             * returnが frame_size 分の ADDI SP を発行してエピローグへ JMP
             * エピローグ到達時: frame_size=累積値, SP=X-2（guard位置）（設計書v1.6 §6.2 不変条件1） */
            parse_block_inner();
            /* [A7fix3] return なし末尾到達のみ frame_size 分を解放
             * return があった場合は JMP でエピローグへ飛んでいるためここは到達不能
             * func_has_return=1 なら出力抑制（二重解放防止） */
            if (!func_has_return && frame_size > 0)
                emit("    ADDI SP, #%d", frame_size);
            emit("_L_%04d:", func_end_label);
            /* [A7] エピローグ（設計書v1.6 §6.5 ISA2.2対応版）
             * 到達時: SP = X - 2（guard位置）
             * LDW X,[X]: 旧X復元（SPは動かない）
             * ADDI SP,#2: guard解放 → SP = X（旧SP = PUSH X前の位置）
             * ADDI SP,#2: 旧X（PUSH分）解放
             * RET: 戻りアドレスはJSRがPUSH済み */
            emit("    LDW  X, [X]");   /* 旧X復元（SP不変） */
            emit("    ADDI SP, #2");   /* guard解放 */
            emit("    ADDI SP, #2");   /* 旧X（PUSH分）解放 */
            emit("    RET");
            peephole_pass();          /* [v2.01] -O1時のみ書換(基盤段階はno-op) */
            insbuf_flush();           /* [v2.01] バッファ→out_fp実書き込み */
            g_insbuf_on = 0;          /* [v2.01] 関数命令列バッファ終了 */
            sym_pop_locals();cur_func=NULL;return;
        }
        error("expected '{' or ';', got '%s'",body);
        insbuf_flush(); g_insbuf_on = 0;   /* [v2.01] 念のためバッファ掃き出し */
        sym_pop_locals();cur_func=NULL;return;
        }
    }

    /* グローバル変数 */
    {
    int done=0;
    while(!done){
        int lp=is_ptr, la=ti.is_array, larr=ti.arr_size, ldim2=ti.dim2;
        if(strcmp(nx,"[")==0){
            la=1;
            const char *ns=next_tok();
            if(strcmp(ns,TOK_NUM)==0){larr=cur_ival;next_tok();}
            nx=next_tok();
            if(strcmp(nx,"[")==0){const char *ns2=next_tok();if(strcmp(ns2,TOK_NUM)==0){ldim2=cur_ival;next_tok();}nx=next_tok();}
        }
        /* [F3] esz: 論理サイズ（sizeof/ポインタ演算用）、data_offsetはDW統一 */
        int esz;
        if((ti.type==T_STRUCT||ti.type==T_UNION)&&!lp){
            int si2=ti.struct_idx; esz=(si2>=0)?structs[si2].total_size:2; if(esz&1)esz++;
        } else { esz=(ti.base==T_CHAR&&!lp)?1:2; }
        int total;
        if(la){total=(ldim2>0)?larr*ldim2*esz:larr*esz;} else total=esz;
        if(total&1)total++;  /* DW統一: 常に偶数バイト */

        /* externの場合は既存シンボルを再利用 */
        sym_t *gs=NULL;
        if(is_extern){gs=sym_find(name);if(!gs){gs=sym_alloc();gs->offset=data_offset;data_offset+=total;}}
        else{gs=sym_alloc();gs->offset=data_offset;data_offset+=total;}
        strncpy(gs->name,name,IDENT_LEN-1);
        gs->type=lp?T_PTR:(la?T_ARRAY:ti.type);
        gs->base=ti.base; gs->sclass=SC_GLOBAL;
        gs->is_array=la; gs->size=larr;
        gs->struct_idx=ti.struct_idx; gs->dim2=ldim2;

        /* 初期化値処理 */
        if(strcmp(nx,"=")==0){
            const char *iv=next_tok();
            strncpy(gs->defval,iv,MAX_STR-1);
            while(strcmp(next_tok(),";")!=0&&strcmp(cur_tok,TOK_EOF)!=0);
            done=1; break;
        }
        if(strcmp(nx,";")==0){done=1;break;}
        if(strcmp(nx,",")==0){
            nm=next_tok();while(strcmp(nm,"*")==0){lp=1;nm=next_tok();}
            strncpy(name,nm,IDENT_LEN-1); nx=next_tok();
            continue;
        }
        push_tok(nx,cur_ival); done=1; break;
    }
    }
    }
}

/* ============================================================
 * main
 * ============================================================ */
/* ベースアドレス引数の16進パース（$XXXX / 0xXXXX / 裸16進 を受理。§3.3） */
static int parse_org_arg(const char *s, unsigned *out) {
    const char *p = s;
    if (p[0]=='$') p++;                 /* アセンブラ慣習 $XXXX */
    /* 0x は strtoul が base16 で解釈する。先頭$除去後も0x可 */
    char *end = NULL;
    unsigned long v = strtoul(p, &end, 16);
    if (end==p || *end!='\0') return -1; /* 解釈不能 or 余分文字 */
    if (v > 0xFFFF) return -1;           /* 16bit空間外 */
    *out = (unsigned)v;
    return 0;
}

int main(int argc, char **argv) {
    src_name="input.c"; out_fp=stdout;
    char *outname=NULL;

    for (int i=1;i<argc;i++) {
        if(strcmp(argv[i],"-o")==0&&i+1<argc){ outname=argv[++i]; }
        else if(strcmp(argv[i],"-v")==0||strcmp(argv[i],"--version")==0){
            fprintf(stderr,"scc23 v%s (%s) for YSD8800 ISA2.3\n",SCC_VERSION,SCC_DATE);
            return 0;
        }
        else if(strcmp(argv[i],"--code-org")==0&&i+1<argc){
            if(parse_org_arg(argv[++i],&g_code_org)){fprintf(stderr,"scc23: invalid --code-org '%s'\n",argv[i]);return 1;}
        }
        else if(strcmp(argv[i],"--data-org")==0&&i+1<argc){
            if(parse_org_arg(argv[++i],&g_data_org)){fprintf(stderr,"scc23: invalid --data-org '%s'\n",argv[i]);return 1;}
        }
        else if(strcmp(argv[i],"--runtime-org")==0&&i+1<argc){
            if(parse_org_arg(argv[++i],&g_runtime_org)){fprintf(stderr,"scc23: invalid --runtime-org '%s'\n",argv[i]);return 1;}
        }
        else if(strcmp(argv[i],"-O0-strict")==0){ g_opt_level=OPT_O0_STRICT; }
        else if(strcmp(argv[i],"-O0")==0){ g_opt_level=OPT_O0; }
        else if(strcmp(argv[i],"-O1")==0){ g_opt_level=OPT_O1; }
        else if(strcmp(argv[i],"--no-peep")==0){ g_no_peep=1; }  /* [P1/C-1検証] peephole無効化 */
        else if(argv[i][0]!='-'){ src_name=argv[i]; }
    }

    src_fp=fopen(src_name,"r");
    if(!src_fp){perror(src_name);return 1;}
    if(outname){out_fp=fopen(outname,"w");if(!out_fp){perror(outname);fclose(src_fp);return 1;}}

    fprintf(stderr,"scc23 v%s (%s) - compiling '%s'\n",SCC_VERSION,SCC_DATE,src_name);

    emit("; scc23 v%s (%s)  source: %s",SCC_VERSION,SCC_DATE,src_name);
    emit("; Target: YSD8800 ISA2.3");
    emit(";");
    /* v1.02 (B): RUNTIME出力は parse loop の後へ移動（オンデマンドフラグ確定後）。
       .org により物理配置は不変（RUNTIMEは指定アドレスに配置される） */
    emit("    .org $%04X", CODE_ORG);
    emit("");
    emit("; ============================================================");
    emit("; User code");
    emit("; ============================================================");
    emit("    JMP  _main      ; entry point ($%04X)", CODE_ORG);
    emit("");

    /* 組み込み関数登録 */
    static const char *builtins[]={"putchar","getchar","puts","printf","sprintf","strcpy","strcmp","memcpy","strlen",NULL};
    for(int bi=0;builtins[bi];bi++){
        sym_t *bs=sym_alloc();
        strncpy(bs->name,builtins[bi],IDENT_LEN-1);
        bs->type=T_INT;bs->sclass=SC_FUNC;bs->defined=1;
    }

    cur_line=1;cur_str[0]='\0';
    next_char();

    for(;;){
        skip_ws();
        if(cur_char==EOF)break;
        if(cur_char=='#'){
            next_char();skip_ws();
            char dir[32];int i=0;
            while(isalpha((unsigned char)cur_char)&&i<31){dir[i++]=(char)cur_char;next_char();}
            dir[i]='\0';
            if(strcmp(dir,"define")==0)handle_define();
            else if(strcmp(dir,"ifdef")==0)handle_ifdef(0);
            else if(strcmp(dir,"ifndef")==0)handle_ifdef(1);
            else if(strcmp(dir,"if")==0)handle_if_directive();
            else if(strcmp(dir,"else")==0){
                while(cur_char!='\n'&&cur_char!=EOF)next_char();
                if(g_stopped_at_else){g_stopped_at_else=0;skip_to_endif_only();}
            }
            else if(strcmp(dir,"endif")==0){while(cur_char!='\n'&&cur_char!=EOF)next_char();g_stopped_at_else=0;}
            else{while(cur_char!='\n'&&cur_char!=EOF)next_char();}
            continue;
        }
        parse_global();
    }

    /* v1.02 (B): parse 完了後（g_use_mul/div/mod 確定後）に RUNTIME を出力。
       .org により物理配置は RUNTIME_ORG 固定。CODE 内の JSR _cc_* は前方参照となるが
       hasm23 が 2パスで解決する（前方参照対応） */
    emit("");
    emit("    .org $%04X", RUNTIME_ORG);
    emit("");
    emit_runtime();
    emit("");

    emit_data_section();

    fclose(src_fp);
    if(outname)fclose(out_fp);

    if(error_count>0)
        fprintf(stderr,"scc23: %d error(s) in '%s'\n",error_count,src_name);
    else
        fprintf(stderr,"scc23: compiled '%s'  errors=0\n",src_name);

    return error_count?1:0;
}
