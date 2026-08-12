/* scc23_v1_03.c - Small C Compiler for YSD8800 ISA2.3
 * Version: 1.03 (2026-06-16)
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
#define SCC_VERSION   "1.03"
#define SCC_DATE      "2026-06-16"

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
/* 既定値は v1.01 と同一（後方互換: オプション省略時は従来動作） */
#define DATA_ORG_DEFAULT     0x4000
#define RUNTIME_ORG_DEFAULT  0x0100
#define CODE_ORG_DEFAULT     0x0400
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

/* [v1.03] ランタイムワーク領域を $FBD0系 → $C7E8系 へ移設。
 *   旧 $FBD0-$FBE7 は kernel タスクスタック領域 $F000-$FBFF（tid7 データスタック
 *   $FB80-$FBFE）に侵入し、ProcMgr 経由ロード時に tid7 のデータスタックを破壊する
 *   サイレント・コラプションを起こす（設計書 scc23_runtime_wk_relocation_design_v1_1）。
 *   Cプロセス承認区画 $C000-$C7FF（2KB）の DATA 区画末尾 $C7E8-$C7FF（24B）へ移設し、
 *   プロセス全状態を区画内に自己完結させる。グローバル変数（$C680から上方成長）とは
 *   反対端（$C7FF詰め）で離す配置。論理コードは不変・アドレス値のみ付け替え。 */
#define C_XSAVE_ADDR    0xC7E8   /* inc/dec addr退避 */
#define C_TMP_ADDR      0xC7EA   /* inc/dec旧値/strcpy/strcmp ワーク */
#define C_TMP_ADDR1     0xC7EC   /* [F4] 追加ワーク（設計書v1.5 D9） */
/* [v1.03] ランタイムワーク領域 $C7E8〜$C7FF（24B・Cプロセス区画内DATA末尾） */
#define C_MEMCPY_DEST   0xC7EE   /* memcpy dest ptr */
#define C_MEMCPY_SRC    0xC7F0   /* memcpy src ptr  */
#define C_MEMCPY_CNT    0xC7F2   /* memcpy count    */
#define C_MUL_BASE      0xC7F4   /* _cc_mul A */
#define C_MUL_B         0xC7F6   /* _cc_mul B */
#define C_MUL_R         0xC7F8   /* _cc_mul R */
#define C_DIV_BASE      0xC7FA   /* _cc_div A */
#define C_DIV_B         0xC7FC   /* _cc_div B */
#define C_DIV_Q         0xC7FE   /* _cc_div Q（占有 $C7FE-$C7FF・区画末尾$C7FF詰め） */

/* SirNode 専用定数 */
#define SIR_MAX_ARGS    16
#define SIR_MAX_STMTS   256  /* parse_block内最大文数（動的割当のため参考値）*/

/* ============================================================
 * 型定義（v2.11から流用）
 * ============================================================ */
typedef enum {
    T_INT = 0, T_CHAR, T_PTR, T_ARRAY, T_VOID, T_STRUCT, T_UNION
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
static void emit(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vfprintf(out_fp, fmt, ap);
    va_end(ap);
    fprintf(out_fp, "\n");
}
static void emit_label(int n) { fprintf(out_fp, "_L_%04d:\n", n); }
static int  new_label(void)   { return label_seq++; }

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

/* ============================================================
 * 字句解析（v2.11から流用）
 * ============================================================ */
#define TOK_EOF      "\x01EOF"
#define TOK_NUM      "\x01NUM"
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
            cn->type=T_INT;
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
        if (strcmp(op,"*")==0)       { n=sir_binop(SIR_MUL,n,parse_unary()); }
        else if (strcmp(op,"/")==0)  { n=sir_binop(SIR_DIV,n,parse_unary()); }
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
            }
            n = sir_binop(SIR_ADD, n, r);
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
                n = sir_binop(SIR_SUB, n, r);
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
static void emit_expr(sir_node_t *n) {
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
            sym_pop_locals();cur_func=NULL;return;
        }
        error("expected '{' or ';', got '%s'",body);
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
