/* scc22.c - Small C Compiler for YSD8800 ISA2.2
 * Version: 1.01
 * YSD8800 Forthカーネルプロジェクト
 * v1.01: フレームレイアウト修正（ローカル変数を負オフセット[X-N]に）
 *         引数オフセット計算を左→右push方式に対応
 *         stdint.h追加、[B]アドレッシングを[X]経由に修正
 *
 * Small-C仕様をリファレンスにゼロから実装（ライセンス問題なし）
 *
 * 呼び出し規約:
 *   A  = 式評価主レジスタ / 戻り値
 *   B  = 補助演算レジスタ
 *   X  = フレームポインタ（関数実行中）
 *   SP = Cスタック（引数/ローカル/戻りアドレス）
 *
 * スタックフレーム（X = フレームポインタ = ローカル先頭）:
 *   [X + 0]          = ローカル変数1
 *   [X + 2]          = ローカル変数2
 *   [X + locals*2+0] = 戻りアドレス（JSR自動）
 *   [X + locals*2+2] = 引数1（第1引数）
 *   [X + locals*2+4] = 引数2
 *
 * build: gcc -std=c99 -O2 -Wall scc22.c -o scc22
 * usage: scc22 [-o output.asm] input.c
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <stdarg.h>
#include <stdint.h>

/* ============================================================
 * 定数
 * ============================================================ */
#define SCC_VERSION     "1.00"
#define MAX_SYM         512     /* シンボルテーブルサイズ */
#define MAX_LOCAL       32      /* 関数内ローカル変数最大数 */
#define MAX_PARAM       8       /* 引数最大数 */
#define MAX_BREAK       32      /* break/continueスタック深さ */
#define MAX_STR         256     /* 文字列バッファ */
#define IDENT_LEN       64      /* 識別子最大長 */

/* データ配置開始アドレス */
#define DATA_ORG        0xE300  /* グローバル変数領域 */
#define CODE_ORG        0x0A00  /* コード配置開始（カーネル$0030〜$09EFの後） */

/* Cランタイム専用ワーク変数 */
#define C_XSAVE_ADDR    0xE0D0
#define C_TMP_ADDR      0xE0D2

/* ============================================================
 * 型定義
 * ============================================================ */
typedef enum {
    T_INT = 0, T_CHAR, T_PTR, T_ARRAY, T_VOID
} ctype_t;

typedef enum {
    SC_GLOBAL, SC_LOCAL, SC_PARAM, SC_FUNC, SC_DEFINE
} sclass_t;

typedef struct sym {
    char     name[IDENT_LEN];
    ctype_t  type;
    ctype_t  base;     /* ポインタ/配列のベース型 */
    sclass_t sclass;
    int      offset;   /* LOCAL/PARAM: フレームオフセット, GLOBAL: 0 */
    int      size;     /* ARRAY: 要素数 */
    int      is_array;
    int      defined;  /* FUNC: 定義済みフラグ */
    char     defval[MAX_STR]; /* DEFINE: 置換テキスト */
    struct sym *next;
} sym_t;

/* ============================================================
 * グローバル状態
 * ============================================================ */
static FILE   *src_fp;
static FILE   *out_fp;
static char   *src_name;

/* 字句解析 */
static int     cur_char;
static int     cur_line;
static char    cur_tok[MAX_STR];    /* 現在のトークン文字列 */
static int     cur_ival;            /* 数値トークンの値 */
/* プッシュバックスタック（2段） */
#define PUSHBACK_DEPTH 4
static int     pb_count;
static char    pb_str[PUSHBACK_DEPTH][MAX_STR];
static int     pb_ival[PUSHBACK_DEPTH];
/* 旧名との互換エイリアス（削除予定） */
#define pushed_tok  (pb_count > 0)
#define pushed_str  pb_str[pb_count-1]
#define pushed_ival pb_ival[pb_count-1]

/* シンボルテーブル */
static sym_t  *sym_table;
static int     sym_count;

/* ラベルカウンタ */
static int     label_seq;

/* 関数コンテキスト */
static sym_t  *cur_func;
static int     local_count;    /* 現在の関数のローカル変数数 */
static int     param_count;    /* 現在の関数の引数数 */
static int     frame_size;     /* ローカル変数の合計バイト数 */

/* break/continue スタック */
static int     break_stack[MAX_BREAK];
static int     cont_stack[MAX_BREAK];
static int     loop_depth;

/* 文字列リテラルプール */
typedef struct strlit { int id; char text[MAX_STR]; struct strlit *next; } strlit_t;
static strlit_t *strlit_list;
static int       strlit_count;

/* グローバルデータオフセット */
static int     data_offset;  /* DATA_ORGからのオフセット */

/* エラーカウント */
static int     error_count;

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
 * 出力
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

/* ============================================================
 * シンボルテーブル
 * ============================================================ */
static sym_t *sym_alloc(void) {
    sym_t *s = calloc(1, sizeof(sym_t));
    if (!s) { perror("sym_alloc"); exit(1); }
    s->next = sym_table;
    sym_table = s;
    sym_count++;
    return s;
}

/* スコープ内のシンボルを検索（最近追加されたものが優先）*/
static sym_t *sym_find(const char *name) {
    for (sym_t *s = sym_table; s; s = s->next)
        if (strcmp(s->name, name) == 0)
            return s;
    return NULL;
}

/* ローカル/パラメータシンボルを削除（関数終了時）*/
static void sym_pop_locals(void) {
    sym_t *prev = NULL;
    sym_t *s = sym_table;
    while (s) {
        sym_t *next = s->next;
        if (s->sclass == SC_LOCAL || s->sclass == SC_PARAM) {
            if (prev) prev->next = next;
            else      sym_table  = next;
            free(s);
            sym_count--;
        } else {
            prev = s;
        }
        s = next;
    }
}

/* ============================================================
 * 字句解析
 * ============================================================ */
static int next_char(void) {
    cur_char = fgetc(src_fp);
    if (cur_char == '\n') cur_line++;
    return cur_char;
}

/* 空白・コメントをスキップ */
static void skip_ws(void) {
    for (;;) {
        while (cur_char != EOF && isspace((unsigned char)cur_char))
            next_char();
        if (cur_char == '/' ) {
            int nc = fgetc(src_fp);
            if (nc == '/') {
                while (cur_char != EOF && cur_char != '\n') next_char();
                continue;
            } else if (nc == '*') {
                next_char();
                while (cur_char != EOF) {
                    if (cur_char == '*') {
                        next_char();
                        if (cur_char == '/') { next_char(); break; }
                    } else next_char();
                }
                continue;
            } else {
                ungetc(nc, src_fp);
            }
        }
        break;
    }
}

/* トークンの種別を表す文字列（比較用）*/
#define TOK_EOF     "\x01"
#define TOK_IDENT   "\x02"
#define TOK_NUM     "\x03"
#define TOK_STR     "\x04"
#define TOK_CHAR_LIT "\x05"

static const char *next_tok(void) {
    if (pb_count > 0) {
        pb_count--;
        strcpy(cur_tok, pb_str[pb_count]);
        cur_ival = pb_ival[pb_count];
        return cur_tok;
    }

    skip_ws();

    if (cur_char == EOF) { strcpy(cur_tok, TOK_EOF); return cur_tok; }

    /* 識別子・キーワード */
    if (isalpha((unsigned char)cur_char) || cur_char == '_') {
        int i = 0;
        while ((isalnum((unsigned char)cur_char) || cur_char == '_') && i < IDENT_LEN-1) {
            cur_tok[i++] = (char)cur_char;
            next_char();
        }
        cur_tok[i] = '\0';
        return cur_tok;
    }

    /* 数値リテラル */
    if (isdigit((unsigned char)cur_char)) {
        char buf[64]; int i = 0;
        int base = 10;
        if (cur_char == '0') {
            buf[i++] = (char)cur_char; next_char();
            if (cur_char == 'x' || cur_char == 'X') {
                base = 16; buf[i++] = (char)cur_char; next_char();
            }
        }
        while ((base==16 ? isxdigit((unsigned char)cur_char)
                         : isdigit((unsigned char)cur_char)) && i < 62) {
            buf[i++] = (char)cur_char; next_char();
        }
        buf[i] = '\0';
        cur_ival = (int)strtol(buf, NULL, 0);
        strcpy(cur_tok, TOK_NUM);
        return cur_tok;
    }

    /* 文字リテラル */
    if (cur_char == '\'') {
        next_char();
        if (cur_char == '\\') {
            next_char();
            switch (cur_char) {
            case 'n': cur_ival = '\n'; break;
            case 't': cur_ival = '\t'; break;
            case 'r': cur_ival = '\r'; break;
            case '0': cur_ival = 0;   break;
            default:  cur_ival = cur_char;
            }
        } else {
            cur_ival = cur_char;
        }
        next_char();
        if (cur_char == '\'') next_char();
        strcpy(cur_tok, TOK_CHAR_LIT);
        return cur_tok;
    }

    /* 文字列リテラル */
    if (cur_char == '"') {
        next_char();
        int i = 0;
        while (cur_char != EOF && cur_char != '"' && i < MAX_STR-1) {
            if (cur_char == '\\') {
                next_char();
                switch (cur_char) {
                case 'n': cur_tok[i++] = '\n'; break;
                case 't': cur_tok[i++] = '\t'; break;
                case 'r': cur_tok[i++] = '\r'; break;
                case '0': cur_tok[i++] = '\0'; break;
                default:  cur_tok[i++] = (char)cur_char;
                }
            } else {
                cur_tok[i++] = (char)cur_char;
            }
            next_char();
        }
        cur_tok[i] = '\0';
        if (cur_char == '"') next_char();
        /* 戻り値はTOK_STRだが内容はcur_tokに入っている — 別変数に保存 */
        static char str_buf[MAX_STR];
        memcpy(str_buf, cur_tok, i+1);
        cur_ival = i;  /* 長さ */
        strcpy(cur_tok, TOK_STR);
        /* str_bufにテキストが入っている */
        extern char *scc22_str_buf;  /* 前方宣言 */
        /* 簡略化: cur_tok はTOK_STRで、内容はstr_bufに */
        (void)str_buf;
        return cur_tok;
    }

    /* 複合演算子 */
    char c = (char)cur_char;
    next_char();
    cur_tok[0] = c; cur_tok[1] = '\0';

    /* 2文字演算子チェック */
    static const char *ops2[] = {
        "==","!=","<=",">=","&&","||","++","--","<<",">>",
        "+=","-=","*=","/=","%=","&=","|=","^=","<<=",">>=",
        NULL
    };
    char c2 = (char)cur_char;
    for (int i = 0; ops2[i]; i++) {
        if (ops2[i][0] == c && ops2[i][1] == c2) {
            cur_tok[1] = c2; cur_tok[2] = '\0';
            next_char();
            /* <<= >>= の3文字チェック */
            if ((strcmp(cur_tok,"<<")==0 || strcmp(cur_tok,">>")==0) && cur_char == '=') {
                cur_tok[2] = '='; cur_tok[3] = '\0';
                next_char();
            }
            return cur_tok;
        }
    }
    return cur_tok;
}

static void push_tok(const char *tok, int ival) {
    if (pb_count >= PUSHBACK_DEPTH) {
        fprintf(stderr, "push_tok overflow\n"); return;
    }
    strncpy(pb_str[pb_count], tok, MAX_STR-1);
    pb_str[pb_count][MAX_STR-1] = '\0';
    pb_ival[pb_count] = ival;
    pb_count++;
}

static int expect(const char *tok) {
    const char *t = next_tok();
    if (strcmp(t, tok) != 0) {
        error("expected '%s', got '%s'", tok, t);
        return 0;
    }
    return 1;
}

/* ============================================================
 * #define 処理（簡易）
 * ============================================================ */
static void handle_define(void) {
    /* #define NAME VALUE の形式のみ */
    skip_ws();
    char name[IDENT_LEN]; int i = 0;
    while ((isalnum((unsigned char)cur_char)||cur_char=='_') && i<IDENT_LEN-1)
        { name[i++]=(char)cur_char; next_char(); }
    name[i]='\0';
    skip_ws();
    char val[MAX_STR]; i = 0;
    while (cur_char != '\n' && cur_char != EOF && i < MAX_STR-1)
        { val[i++]=(char)cur_char; next_char(); }
    val[i]='\0';

    sym_t *s = sym_alloc();
    strncpy(s->name, name, IDENT_LEN-1);
    s->sclass = SC_DEFINE;
    strncpy(s->defval, val, MAX_STR-1);
}

/* ============================================================
 * 型解析
 * ============================================================ */
static ctype_t parse_basetype(void) {
    const char *t = next_tok();
    if (strcmp(t,"int")  == 0) return T_INT;
    if (strcmp(t,"char") == 0) return T_CHAR;
    if (strcmp(t,"void") == 0) return T_VOID;
    error("expected type, got '%s'", t);
    return T_INT;
}

/* ============================================================
 * コード生成ヘルパー
 * ============================================================ */
static int  real_offset(sym_t *s);
/* Aをスタックにpush（式評価スタック） */
static void gen_push_a(void) {
    emit("    SUBI SP, #2");
    emit("    STW  A, [SP]");
}

/* スタックからBにpop */
static void gen_pop_b(void) {
    emit("    LDW  B, [SP]");
    emit("    ADDI SP, #2");
}

/* 変数のアドレスをAにロード */
static void gen_addr(sym_t *s) {
    if (s->sclass == SC_GLOBAL) {
        emit("    LDW  A, #$%04X", DATA_ORG + s->offset);
    } else {
        /* LOCAL or PARAM: X(フレームポインタ)相対アドレス */
        int real_off = real_offset(s);
        emit("    MOV  A, X");
        if (real_off > 0)
            emit("    ADDI A, #%d", real_off);
        else if (real_off < 0)
            emit("    SUBI A, #%d", -real_off);
    }
}

/* 実アクセスオフセットを計算
 * フレームレイアウト（X=FP）:
 *   [X+0]    = 旧X（エントリ先頭でpush、SPと同位置→MOV X,SP）
 *   [X+2]    = 戻りアドレス（JSRがpush、FPより高アドレス）
 *   [X+4]    = 第N引数（最後push）
 *   [X+6]    = 第N-1引数
 *   ...
 *   [X+2+N*2] = 第1引数（最初push）
 *
 *   [X-2]    = ローカル変数1（SUBI SP,#2で確保）
 *   [X-4]    = ローカル変数2
 *
 * 引数: 左→右にpushするため最後がスタックTOP
 * 第k引数（0始まり）: off = 4 + (N-1-k)*2
 */
static int real_offset(sym_t *s) {
    if (s->sclass == SC_PARAM) {
        int k = s->offset / 2;
        int n = param_count > 0 ? param_count : k + 1;
        return 4 + (n - 1 - k) * 2;
    }
    /* ローカル変数: Xより低アドレス（負オフセット） */
    /* offset=0 → [X-2], offset=2 → [X-4], ... */
    return -(2 + s->offset);
}

/* 変数の値をAにロード */
static void gen_load(sym_t *s) {
    if (s->is_array) {
        gen_addr(s);
        return;
    }
    if (s->sclass == SC_GLOBAL) {
        if (s->type == T_CHAR)
            emit("    LDB  A, [$%04X]", DATA_ORG + s->offset);
        else
            emit("    LDW  A, [$%04X]", DATA_ORG + s->offset);
    } else {
        /* X = フレームポインタ（関数実行中は常に有効） */
        int off = real_offset(s);
        if (off == 0)
            emit("    LDW  A, [X]");
        else if (off > 0)
            emit("    LDW  A, [X + #%d]", off);
        else
            emit("    LDW  A, [X + #$%04X]", (uint16_t)off);
    }
}

/* Aの値を変数に格納 */
static void gen_store(sym_t *s) {
    if (s->sclass == SC_GLOBAL) {
        if (s->type == T_CHAR)
            emit("    STB  A, [$%04X]", DATA_ORG + s->offset);
        else
            emit("    STW  A, [$%04X]", DATA_ORG + s->offset);
    } else {
        int off = real_offset(s);
        if (off == 0)
            emit("    STW  A, [X]");
        else if (off > 0)
            emit("    STW  A, [X + #%d]", off);
        else
            emit("    STW  A, [X + #$%04X]", (uint16_t)off);
    }
}

/* ============================================================
 * 式の解析（再帰下降）
 * 各関数はAに結果を返す規約
 * ============================================================ */
static void parse_expr(void);
static void parse_assign(void);
static void parse_logor(void);

static void parse_primary(void) {
    const char *t = next_tok();

    /* 数値リテラル */
    if (strcmp(t, TOK_NUM) == 0) {
        emit("    LDW  A, #%d", cur_ival);
        return;
    }
    /* 文字リテラル */
    if (strcmp(t, TOK_CHAR_LIT) == 0) {
        emit("    LDW  A, #%d", cur_ival);
        return;
    }
    /* 文字列リテラル: アドレスをプールに登録してAにロード */
    if (strcmp(t, TOK_STR) == 0) {
        /* cur_tokはTOK_STRだがコンテンツは失われている問題 */
        /* 簡略実装: 空文字列アドレスを返す */
        int id = strlit_count++;
        emit("    LDW  A, #$_S_%04d", id);
        return;
    }
    /* 括弧式 */
    if (strcmp(t, "(") == 0) {
        parse_expr();
        expect(")");
        return;
    }
    /* 単項マイナス */
    if (strcmp(t, "-") == 0) {
        parse_primary();
        emit("    LDW  B, #0");
        emit("    SUB  B, A");
        emit("    MOV  A, B");
        return;
    }
    /* 論理否定 */
    if (strcmp(t, "!") == 0) {
        parse_primary();
        emit("    CMPI A, #0");
        emit("    LDW  A, #$FFFF");
        int L = new_label();
        emit("    BEQ  _L_%04d", L);
        emit("    LDW  A, #0");
        emit_label(L);
        return;
    }
    /* ビット反転 */
    if (strcmp(t, "~") == 0) {
        parse_primary();
        emit("    NOT  A");
        return;
    }
    /* 前置インクリメント */
    if (strcmp(t, "++") == 0) {
        const char *id = next_tok();
        sym_t *s = sym_find(id);
        if (!s) { error("undefined: %s", id); return; }
        gen_load(s);
        emit("    ADDI A, #1");
        gen_store(s);
        return;
    }
    /* 前置デクリメント */
    if (strcmp(t, "--") == 0) {
        const char *id = next_tok();
        sym_t *s = sym_find(id);
        if (!s) { error("undefined: %s", id); return; }
        gen_load(s);
        emit("    SUBI A, #1");
        gen_store(s);
        return;
    }
    /* アドレス演算子 & */
    if (strcmp(t, "&") == 0) {
        const char *id = next_tok();
        sym_t *s = sym_find(id);
        if (!s) { error("undefined: %s", id); return; }
        gen_addr(s);
        return;
    }
    /* 間接参照 * */
    if (strcmp(t, "*") == 0) {
        parse_primary();
        /* Aはアドレス → [A]をAに（X経由でアクセス） */
        emit("    SUBI SP, #2");
        emit("    STW  X, [SP]");  /* push X(FP) */
        emit("    MOV  X, A");     /* X = アドレス */
        emit("    LDW  A, [X]");
        emit("    LDW  X, [SP]");  /* pop X(FP) */
        emit("    ADDI SP, #2");
        return;
    }

    /* 識別子 */
    if (isalpha((unsigned char)t[0]) || t[0] == '_') {
        char name[IDENT_LEN];
        strncpy(name, t, IDENT_LEN-1);

        /* #define 置換チェック */
        sym_t *def = sym_find(name);
        if (def && def->sclass == SC_DEFINE) {
            /* 数値定数として扱う */
            int v = (int)strtol(def->defval, NULL, 0);
            emit("    LDW  A, #%d", v);
            return;
        }

        /* 次トークンを見て関数呼び出しか判定 */
        const char *peek = next_tok();
        if (strcmp(peek, "(") == 0) {
            /* 関数呼び出し */
            /* 引数リストを収集してから右→左でpush */
            /* 簡略化: 引数を左から評価してpush（最大8個） */
            int argc = 0;
            int arg_labels[MAX_PARAM];

            /* 引数を一時ラベルに退避する方法は複雑なのでスタックに積む */
            if (strcmp(next_tok(), ")") != 0) {
                push_tok(cur_tok, cur_ival);
                /* 引数を左から評価してスタックにpush */
                /* 最後にまとめて逆順でJSRに渡す必要あり */
                /* 簡略化: 左から順にpushしてJSR */
                int saved[MAX_PARAM];
                argc = 0;
                for (;;) {
                    /* 各引数を評価してスタックへ */
                    /* parse_logorを使う: parse_assignは次トークンをpush_tokするため */
                    parse_logor();
                    saved[argc++] = 0; /* ダミー */
                    gen_push_a();
                    const char *sep = next_tok();
                    if (strcmp(sep, ")") == 0) break;
                    if (strcmp(sep, ",") != 0) {
                        error("expected ',' in argument list, got '%s'", sep);
                        break;
                    }
                    if (argc >= MAX_PARAM) { error("too many arguments"); break; }
                }
                (void)arg_labels; (void)saved;
            }
            emit("    JSR  _%s", name);
            /* 引数をpop */
            if (argc > 0)
                emit("    ADDI SP, #%d", argc * 2);
            return;
        }
        push_tok(peek, cur_ival);

        /* 変数参照 */
        sym_t *s = sym_find(name);
        if (!s) { error("undefined symbol: %s", name); return; }

        gen_load(s);

        /* 後置インクリメント/デクリメントチェック */
        const char *op = next_tok();
        if (strcmp(op, "++") == 0) {
            emit("    LDW  B, A");
            emit("    ADDI B, #1");
            /* Bをstoreして元のAを返す */
            if (s->sclass == SC_GLOBAL)
                emit("    STW  B, [$%04X]", DATA_ORG + s->offset);
            else {
                int off = s->offset;
                if (off == 0) emit("    STW  B, [X]");
                else emit("    STW  B, [X + #%d]", off);
            }
            return;
        }
        if (strcmp(op, "--") == 0) {
            emit("    LDW  B, A");
            emit("    SUBI B, #1");
            if (s->sclass == SC_GLOBAL)
                emit("    STW  B, [$%04X]", DATA_ORG + s->offset);
            else {
                int off = s->offset;
                if (off == 0) emit("    STW  B, [X]");
                else emit("    STW  B, [X + #%d]", off);
            }
            return;
        }
        /* 配列添字 */
        if (strcmp(op, "[") == 0) {
            gen_push_a();    /* 配列先頭アドレス */
            parse_expr();    /* インデックス */
            expect("]");
            /* A = index, スタックtop = base_addr */
            /* addr = base + index * element_size */
            int esz = (s->base == T_CHAR) ? 1 : 2;
            if (esz == 2) {
                emit("    LDW  B, #1");
                emit("    SHL  A, B");  /* A *= 2 */
            }
            gen_pop_b();      /* B = base_addr */
            emit("    ADD  A, B");  /* A = addr */
            /* ISA2.2: [reg]はXのみ対応 → XをFPから一時借用 */
            emit("    SUBI SP, #2");
            emit("    STW  X, [SP]");  /* push X(FP) */
            emit("    MOV  X, A");     /* X = 要素アドレス */
            if (esz == 1) emit("    LDB  A, [X]");
            else          emit("    LDW  A, [X]");
            emit("    LDW  X, [SP]");  /* pop X(FP) */
            emit("    ADDI SP, #2");
            return;
        }
        push_tok(op, cur_ival);
        return;
    }

    error("unexpected token in expression: '%s'", t);
}

/* 乗除算 */
static void parse_mul(void) {
    parse_primary();
    for (;;) {
        char op[8]; strncpy(op, next_tok(), 7); op[7]='\0';
        if (strcmp(op,"*")==0 || strcmp(op,"/")==0 || strcmp(op,"%")==0) {
            gen_push_a();
            parse_primary();
            gen_pop_b();
            /* B=left A=right */
            if (strcmp(op,"*")==0) {
                emit("    JSR  _cc_mul");
            } else if (strcmp(op,"/")==0) {
                emit("    JSR  _cc_div");
            } else {
                emit("    JSR  _cc_mod");
            }
        } else {
            push_tok(op, cur_ival);
            break;
        }
    }
}

/* 加減算 */
static void parse_add(void) {
    parse_mul();
    for (;;) {
        char op[8]; strncpy(op, next_tok(), 7); op[7]='\0';
        if (strcmp(op,"+")==0 || strcmp(op,"-")==0) {
            gen_push_a();
            parse_mul();
            gen_pop_b();
            /* B=left A=right */
            if (strcmp(op,"+")==0) {
                emit("    ADD  B, A");
                emit("    MOV  A, B");
            } else {
                emit("    SUB  B, A");
                emit("    MOV  A, B");
            }
        } else {
            push_tok(op, cur_ival);
            break;
        }
    }
}

/* シフト */
static void parse_shift(void) {
    parse_add();
    for (;;) {
        char op[8]; strncpy(op, next_tok(), 7); op[7]='\0';
        if (strcmp(op,"<<")==0 || strcmp(op,">>")==0) {
            gen_push_a();
            parse_add();
            gen_pop_b();
            if (strcmp(op,"<<")==0) emit("    SHL  B, A");
            else                    emit("    SHR  B, A");
            emit("    MOV  A, B");
        } else {
            push_tok(op, cur_ival);
            break;
        }
    }
}

/* 比較 < > <= >= */
static void parse_relational(void) {
    parse_shift();
    char op_rel[8]; strncpy(op_rel, next_tok(), 7); op_rel[7]='\0';
    { const char *op = op_rel;
    if (strcmp(op_rel,"<")==0||strcmp(op_rel,">")==0||
        strcmp(op_rel,"<=")==0||strcmp(op_rel,">=")==0) {
        gen_push_a();
        parse_shift();
        gen_pop_b();
        /* B=left A=right */
        int Ltrue = new_label(), Lend = new_label();
        emit("    CMP  B, A");  /* B - A */
        if (strcmp(op_rel,"<")==0)       emit("    BLT  _L_%04d", Ltrue);
        else if (strcmp(op_rel,">")==0)  emit("    BGT_  _L_%04d", Ltrue); /* BGT は BLT の逆 */
        else if (strcmp(op_rel,"<=")==0) { emit("    BLT  _L_%04d", Ltrue); emit("    BEQ  _L_%04d", Ltrue); }
        else                         { emit("    BGE  _L_%04d", Ltrue); } /* >= */
        emit("    LDW  A, #0");
        emit("    JMP  _L_%04d", Lend);
        emit_label(Ltrue);
        emit("    LDW  A, #$FFFF");
        emit_label(Lend);
    } else {
        push_tok(op_rel, cur_ival);
    }
    } /* scope */
}

/* == != */
static void parse_equality(void) {
    parse_relational();
    for (;;) {
        char op[8]; strncpy(op,next_tok(),7); op[7]='\0';
        if (strcmp(op,"==")==0 || strcmp(op,"!=")==0) {
            gen_push_a();
            parse_relational();
            gen_pop_b();
            int Ltrue = new_label(), Lend = new_label();
            emit("    CMP  B, A");
            if (strcmp(op,"==")==0) emit("    BEQ  _L_%04d", Ltrue);
            else                    emit("    BNE  _L_%04d", Ltrue);
            emit("    LDW  A, #0");
            emit("    JMP  _L_%04d", Lend);
            emit_label(Ltrue);
            emit("    LDW  A, #$FFFF");
            emit_label(Lend);
        } else {
            push_tok(op, cur_ival);
            break;
        }
    }
}

/* & */
static void parse_bitand(void) {
    parse_equality();
    while (strcmp(next_tok(),"&")==0) {
        gen_push_a(); parse_equality(); gen_pop_b();
        emit("    AND  B, A"); emit("    MOV  A, B");
    }
    push_tok(cur_tok, cur_ival);
}
/* ^ */
static void parse_bitxor(void) {
    parse_bitand();
    while (strcmp(next_tok(),"^")==0) {
        gen_push_a(); parse_bitand(); gen_pop_b();
        emit("    XOR  B, A"); emit("    MOV  A, B");
    }
    push_tok(cur_tok, cur_ival);
}
/* | */
static void parse_bitor(void) {
    parse_bitxor();
    while (strcmp(next_tok(),"|")==0) {
        gen_push_a(); parse_bitxor(); gen_pop_b();
        emit("    OR   B, A"); emit("    MOV  A, B");
    }
    push_tok(cur_tok, cur_ival);
}

/* && */
static void parse_logand(void) {
    parse_bitor();
    while (strcmp(next_tok(),"&&")==0) {
        int Lfalse = new_label(), Lend = new_label();
        emit("    CMPI A, #0");
        emit("    BEQ  _L_%04d", Lfalse);
        parse_bitor();
        emit("    CMPI A, #0");
        emit("    BEQ  _L_%04d", Lfalse);
        emit("    LDW  A, #$FFFF");
        emit("    JMP  _L_%04d", Lend);
        emit_label(Lfalse);
        emit("    LDW  A, #0");
        emit_label(Lend);
    }
    push_tok(cur_tok, cur_ival);
}
/* || */
static void parse_logor(void) {
    parse_logand();
    while (strcmp(next_tok(),"||")==0) {
        int Ltrue = new_label(), Lend = new_label();
        emit("    CMPI A, #0");
        emit("    BNE  _L_%04d", Ltrue);
        parse_logand();
        emit("    CMPI A, #0");
        emit("    BNE  _L_%04d", Ltrue);
        emit("    LDW  A, #0");
        emit("    JMP  _L_%04d", Lend);
        emit_label(Ltrue);
        emit("    LDW  A, #$FFFF");
        emit_label(Lend);
    }
    push_tok(cur_tok, cur_ival);
}

/* 代入式 */
static void parse_assign(void) {
    /* 左辺値を先読みして代入かどうか判断 */
    /* 簡略: まずparse_logorで評価、次トークンが代入演算子なら代入 */
    parse_logor();
    const char *op = next_tok();

    /* 複合代入演算子テーブル */
    struct { const char *tok; const char *op; } compound[] = {
        {"+=","+"},{"-=","-"},{"*=","*"},{"/=","/"},
        {"%=","%"},{"&=","&"},{"|=","|"},{"^=","^"},
        {"<<=","<<"},{">>=",">>"},
        {NULL,NULL}
    };

    /* 通常代入 */
    if (strcmp(op,"=")==0) {
        /* Aは左辺値のアドレスのはずだが、parse_logorではrvalueが返る */
        /* 簡略実装: 直前のparse_logorが識別子単体だった場合のみ対応 */
        /* → 実装は後で改善。今は変数代入のみ対応 */
        error("assignment in expression context not yet supported via generic path");
        parse_assign();
        return;
    }

    /* 代入演算子なし */
    push_tok(op, cur_ival);
}

static void parse_expr(void) {
    parse_assign();
}

/* ============================================================
 * 文の解析
 * ============================================================ */
static void parse_stmt(void);
static void parse_block(void);
static void parse_decl_local(void);

static void parse_stmt(void) {
    const char *t = next_tok();

    /* 複合文 */
    if (strcmp(t, "{") == 0) {
        parse_block();
        return;
    }

    /* if */
    if (strcmp(t, "if") == 0) {
        expect("("); parse_expr(); expect(")");
        int Lelse = new_label(), Lend = new_label();
        emit("    CMPI A, #0");
        emit("    BEQ  _L_%04d", Lelse);
        parse_stmt();
        const char *nt = next_tok();
        if (strcmp(nt, "else") == 0) {
            emit("    JMP  _L_%04d", Lend);
            emit_label(Lelse);
            parse_stmt();
            emit_label(Lend);
        } else {
            emit_label(Lelse);
            emit_label(Lend);
            push_tok(nt, cur_ival);
        }
        return;
    }

    /* while */
    if (strcmp(t, "while") == 0) {
        int Lloop = new_label(), Lend = new_label();
        if (loop_depth < MAX_BREAK) {
            break_stack[loop_depth] = Lend;
            cont_stack[loop_depth]  = Lloop;
            loop_depth++;
        }
        emit_label(Lloop);
        expect("("); parse_expr(); expect(")");
        emit("    CMPI A, #0");
        emit("    BEQ  _L_%04d", Lend);
        parse_stmt();
        emit("    JMP  _L_%04d", Lloop);
        emit_label(Lend);
        if (loop_depth > 0) loop_depth--;
        return;
    }

    /* do...while */
    if (strcmp(t, "do") == 0) {
        int Lloop = new_label(), Lend = new_label();
        if (loop_depth < MAX_BREAK) {
            break_stack[loop_depth] = Lend;
            cont_stack[loop_depth]  = Lloop;
            loop_depth++;
        }
        emit_label(Lloop);
        parse_stmt();
        expect("while"); expect("("); parse_expr(); expect(")"); expect(";");
        emit("    CMPI A, #0");
        emit("    BNE  _L_%04d", Lloop);
        emit_label(Lend);
        if (loop_depth > 0) loop_depth--;
        return;
    }

    /* for */
    if (strcmp(t, "for") == 0) {
        int Lloop = new_label(), Lcont = new_label(), Lend = new_label();
        if (loop_depth < MAX_BREAK) {
            break_stack[loop_depth] = Lend;
            cont_stack[loop_depth]  = Lcont;
            loop_depth++;
        }
        expect("(");
        /* 初期化 */
        const char *init = next_tok();
        if (strcmp(init, ";") != 0) {
            push_tok(init, cur_ival);
            parse_expr();
            expect(";");
        }
        /* 条件 */
        emit_label(Lloop);
        const char *cond = next_tok();
        if (strcmp(cond, ";") != 0) {
            push_tok(cond, cur_ival);
            parse_expr();
            emit("    CMPI A, #0");
            emit("    BEQ  _L_%04d", Lend);
            expect(";");
        } else {
            /* 条件なし → 無限ループ */
        }
        /* ステップ式を後回しにするためラベルで飛ばす */
        /* 簡略: ステップを先に読んで文字列に保存する方式は複雑 */
        /* → 今は ) まで読み捨てる（for(;;)とfor(init;cond;)のみ完全対応）*/
        const char *step = next_tok();
        if (strcmp(step, ")") != 0) {
            /* ステップ式あり: 読み捨て（暫定）*/
            push_tok(step, cur_ival);
            while (strcmp(next_tok(), ")") != 0)
                ;
            warning("for-loop step expression not yet supported");
        }
        parse_stmt();
        emit_label(Lcont);
        emit("    JMP  _L_%04d", Lloop);
        emit_label(Lend);
        if (loop_depth > 0) loop_depth--;
        return;
    }

    /* return */
    if (strcmp(t, "return") == 0) {
        const char *nt = next_tok();
        if (strcmp(nt, ";") != 0) {
            push_tok(nt, cur_ival);
            parse_expr();
            expect(";");
        }
        /* フレーム解放してRET */
        if (frame_size > 0)
            emit("    ADDI SP, #%d", frame_size);
        emit("    LDW  X, [X]");   /* X = 旧X */
        emit("    ADDI SP, #2");
        emit("    RET");
        return;
    }

    /* break */
    if (strcmp(t, "break") == 0) {
        expect(";");
        if (loop_depth > 0)
            emit("    JMP  _L_%04d", break_stack[loop_depth-1]);
        else
            error("break outside loop");
        return;
    }

    /* continue */
    if (strcmp(t, "continue") == 0) {
        expect(";");
        if (loop_depth > 0)
            emit("    JMP  _L_%04d", cont_stack[loop_depth-1]);
        else
            error("continue outside loop");
        return;
    }

    /* セミコロン（空文）*/
    if (strcmp(t, ";") == 0) return;

    /* ローカル変数宣言 */
    if (strcmp(t,"int")==0 || strcmp(t,"char")==0) {
        push_tok(t, cur_ival);
        parse_decl_local();
        return;
    }

    /* 式文（代入・関数呼び出し等）*/
    push_tok(t, cur_ival);

    /* 代入文の特別処理: ident = expr ; */
    const char *id_tok = next_tok();
    if ((isalpha((unsigned char)id_tok[0])||id_tok[0]=='_') ) {
        char id_name[IDENT_LEN];
        strncpy(id_name, id_tok, IDENT_LEN-1);
        const char *op = next_tok();

        /* 代入演算子チェック */
        static const struct { const char *tok; const char *iop; } asgn[] = {
            {"=",NULL},{"+=","+"},{"-=","-"},{"*=","*"},
            {"/=","/"},{"%=","%"},{"&=","&"},{"|=","|"},
            {"^=","^"},{"<<=","<<"},{">>>=",">>"},
            {NULL,NULL}
        };
        int found_asgn = 0;
        for (int i = 0; asgn[i].tok; i++) {
            if (strcmp(op, asgn[i].tok) == 0) {
                found_asgn = 1;
                sym_t *s = sym_find(id_name);
                if (!s) { error("undefined: %s", id_name); break; }

                if (asgn[i].iop) {
                    /* 複合代入: load, push, eval, op, store */
                    gen_load(s);
                    gen_push_a();
                    parse_expr();
                    gen_pop_b();
                    /* B=old, A=rhs */
                    if (strcmp(asgn[i].iop,"+")==0) { emit("    ADD  B, A"); emit("    MOV  A, B"); }
                    else if (strcmp(asgn[i].iop,"-")==0) { emit("    SUB  B, A"); emit("    MOV  A, B"); }
                    else if (strcmp(asgn[i].iop,"&")==0) { emit("    AND  B, A"); emit("    MOV  A, B"); }
                    else if (strcmp(asgn[i].iop,"|")==0) { emit("    OR   B, A"); emit("    MOV  A, B"); }
                    else if (strcmp(asgn[i].iop,"^")==0) { emit("    XOR  B, A"); emit("    MOV  A, B"); }
                    else if (strcmp(asgn[i].iop,"*")==0) emit("    JSR  _cc_mul");
                    else if (strcmp(asgn[i].iop,"/")==0) emit("    JSR  _cc_div");
                    else if (strcmp(asgn[i].iop,"%")==0) emit("    JSR  _cc_mod");
                    else if (strcmp(asgn[i].iop,"<<")==0) { emit("    SHL  B, A"); emit("    MOV  A, B"); }
                    else if (strcmp(asgn[i].iop,">>")==0) { emit("    SHR  B, A"); emit("    MOV  A, B"); }
                } else {
                    parse_expr();
                }
                gen_store(s);
                break;
            }
        }
        if (found_asgn) {
            expect(";");
            return;
        }

        /* 配列添字代入: ident[expr] = expr */
        if (strcmp(op, "[") == 0) {
            sym_t *s = sym_find(id_name);
            if (!s) { error("undefined: %s", id_name); }
            gen_addr(s);
            gen_push_a();     /* base addr */
            parse_expr(); expect("]");
            /* A = index */
            int esz = (s && s->base == T_CHAR) ? 1 : 2;
            if (esz == 2) { emit("    LDW  B, #1"); emit("    SHL  A, B"); }
            gen_pop_b();
            emit("    ADD  A, B"); /* A = addr */
            gen_push_a();          /* addr をスタックへ */
            expect("=");
            parse_expr();
            gen_pop_b();  /* B = addr */
            /* ISA2.2: [reg]はXのみ → X経由でアクセス */
            emit("    SUBI SP, #2");
            emit("    STW  X, [SP]");   /* push X(FP) */
            emit("    MOV  X, B");      /* X = addr */
            if (esz == 1) emit("    STB  A, [X]");
            else          emit("    STW  A, [X]");
            emit("    LDW  X, [SP]");   /* pop X(FP) */
            emit("    ADDI SP, #2");
            expect(";");
            return;
        }

        /* 代入でない場合は通常の式文として処理 */
        push_tok(op, cur_ival);
        push_tok(id_name, 0);
    }

    /* 通常の式文（関数呼び出しを含む） */
    parse_logor();
    expect(";");
}

static void parse_block(void) {
    /* { stmt* } — すでに { を消費済みと仮定 */
    for (;;) {
        const char *t = next_tok();
        if (strcmp(t, "}") == 0 || strcmp(t, TOK_EOF) == 0) break;
        push_tok(t, cur_ival);
        parse_stmt();
    }
}

/* ============================================================
 * ローカル変数宣言
 * ============================================================ */
static void parse_decl_local(void) {
    ctype_t base = parse_basetype();

    for (;;) {
        /* ポインタチェック */
        int is_ptr = 0;
        const char *t = next_tok();
        if (strcmp(t, "*") == 0) { is_ptr = 1; t = next_tok(); }

        if (strcmp(t, TOK_IDENT) == 0 || (t[0] && (isalpha((unsigned char)t[0])||t[0]=='_'))) {
            /* 識別子として処理 */
        }
        char name[IDENT_LEN];
        strncpy(name, t, IDENT_LEN-1);

        /* 配列チェック */
        int arr_size = 0;
        const char *peek = next_tok();
        if (strcmp(peek, "[") == 0) {
            const char *ns = next_tok();
            if (strcmp(ns, TOK_NUM) == 0) arr_size = cur_ival;
            expect("]");
            peek = next_tok();
        }

        /* ローカル変数をフレームに配置 */
        int esz = (base == T_CHAR && !is_ptr) ? 2 : 2; /* 全部2バイト割り当て */
        int total = (arr_size > 0) ? arr_size * esz : esz;
        frame_size += total;

        /* SPを伸ばす */
        emit("    SUBI SP, #%d", total);

        sym_t *s = sym_alloc();
        strncpy(s->name, name, IDENT_LEN-1);
        s->type     = is_ptr ? T_PTR : (arr_size > 0 ? T_ARRAY : base);
        s->base     = base;
        s->sclass   = SC_LOCAL;
        s->is_array = (arr_size > 0);
        s->size     = arr_size;
        /* フレームポインタXからのオフセット: ローカルは0以上 */
        /* X設定時: X = SP (フレーム先頭) */
        /* ローカル変数は宣言順に0, 2, 4... */
        s->offset   = local_count * 2;
        local_count++;

        if (strcmp(peek, ",") == 0) continue;
        if (strcmp(peek, ";") == 0) break;
        push_tok(peek, cur_ival);
        break;
    }
}

/* ============================================================
 * グローバル宣言・関数定義
 * ============================================================ */
static void parse_global(void) {
    const char *t = next_tok();

    /* #pragma / #include は無視 */
    if (t[0] == '#') {
        /* 行末まで読む */
        while (cur_char != '\n' && cur_char != EOF) next_char();
        return;
    }

    /* extern は無視して次の型を読む */
    if (strcmp(t,"extern")==0 || strcmp(t,"static")==0) {
        t = next_tok();
    }

    /* 型 */
    if (strcmp(t,"int")!=0 && strcmp(t,"char")!=0 && strcmp(t,"void")!=0) {
        if (strcmp(t, TOK_EOF) == 0) return;
        error("expected type declaration, got '%s'", t);
        while (strcmp(next_tok(),";")!=0 && strcmp(cur_tok,TOK_EOF)!=0)
            ;
        return;
    }
    ctype_t base;
    if (strcmp(t,"int")==0)       base = T_INT;
    else if (strcmp(t,"char")==0) base = T_CHAR;
    else                           base = T_VOID;

    /* ポインタ? */
    int is_ptr = 0;
    t = next_tok();
    if (strcmp(t,"*")==0) { is_ptr=1; t=next_tok(); }

    char name[IDENT_LEN];
    strncpy(name, t, IDENT_LEN-1);

    t = next_tok();

    /* 関数定義 */
    if (strcmp(t,"(")==0) {
        sym_t *fs = sym_alloc();
        strncpy(fs->name, name, IDENT_LEN-1);
        fs->type    = is_ptr ? T_PTR : base;
        fs->sclass  = SC_FUNC;
        fs->defined = 1;
        cur_func    = fs;
        local_count = 0;
        param_count = 0;
        frame_size  = 0;
        loop_depth  = 0;

        /* 関数ラベル */
        emit("");
        emit("; --- %s ---", name);
        emit("_%s:", name);

        /* 引数リスト解析 */
        /* 引数はJSR後、スタックに積まれている */
        /* [SP+0] = 戻りアドレス, [SP+2] = arg1, [SP+4] = arg2, ... */
        t = next_tok();
        int pcount = 0;
        if (strcmp(t,")")==0) {
            /* 引数なし */
        } else {
            push_tok(t, cur_ival);
            for (;;) {
                /* 型 */
                const char *pt = next_tok();
                ctype_t ptype;
                if (strcmp(pt,"int")==0)  ptype=T_INT;
                else if (strcmp(pt,"char")==0) ptype=T_CHAR;
                else if (strcmp(pt,"void")==0) { next_tok(); break; }
                else { error("expected param type"); break; }
                int pp = 0;
                const char *pn = next_tok();
                if (strcmp(pn,"*")==0) { pp=1; pn=next_tok(); }
                sym_t *ps = sym_alloc();
                strncpy(ps->name, pn, IDENT_LEN-1);
                ps->type   = pp ? T_PTR : ptype;
                ps->base   = ptype;
                ps->sclass = SC_PARAM;
                /* 引数オフセット: ローカル変数の後に続く */
                /* エントリ時: X=SP (ローカル先頭)
                   戻りアドレスは [X + frame_size]
                   引数k は [X + frame_size + 2 + k*2] */
                /* 後でframe_size確定後に調整: ここでは仮値 */
                ps->offset = pcount * 2; /* PARAMは gen_load で frame_size+2+offset に変換 */
                pcount++;
                param_count++;
                const char *sep = next_tok();
                if (strcmp(sep,")")==0) break;
                if (strcmp(sep,",")==0) continue;
                error("expected , or ) in param list");
                break;
            }
        }

        /* プロトタイプ宣言チェック: { の代わりに ; が来たらスキップ */
        const char *maybe_brace = next_tok();
        if (strcmp(maybe_brace, ";") == 0) {
            /* プロトタイプ宣言のみ: シンボルを登録して終了 */
            /* カーネルAPI等の extern 関数はここで登録される */
            sym_pop_locals();
            cur_func = NULL;
            return;
        }
        if (strcmp(maybe_brace, "{") != 0) {
            error("expected '{' or ';', got '%s'", maybe_brace);
            sym_pop_locals();
            cur_func = NULL;
            return;
        }
        /* 関数本体 */

        /* フレームセットアップ: 旧XをSPにpushしてX=フレームポインタに設定 */
        emit("    SUBI SP, #2");
        emit("    STW  X, [SP]");   /* push 旧X */
        emit("    MOV  X, SP");     /* X = フレームポインタ */

        parse_block();

        /* 関数末尾: returnがない場合のフォールスルー */
        /* フレーム解放: ローカル変数をpopして旧Xを復元 */
        if (frame_size > 0)
            emit("    ADDI SP, #%d", frame_size);
        emit("    LDW  X, [X]");   /* X = 旧X（[X+0]から読む） */
        emit("    ADDI SP, #2");   /* 旧X分をpop */
        emit("    RET");

        sym_pop_locals();
        cur_func = NULL;
        return;
    }

    /* グローバル変数宣言 */
    int arr_size = 0;
    if (strcmp(t,"[")==0) {
        const char *ns = next_tok();
        if (strcmp(ns, TOK_NUM)==0) arr_size = cur_ival;
        expect("]");
        t = next_tok();
    }

    /* グローバル変数をデータ領域に配置 */
    emit("");
    emit("; global: %s", name);

    sym_t *gs = sym_alloc();
    strncpy(gs->name, name, IDENT_LEN-1);
    gs->type     = is_ptr ? T_PTR : (arr_size>0 ? T_ARRAY : base);
    gs->base     = base;
    gs->sclass   = SC_GLOBAL;
    gs->is_array = (arr_size > 0);
    gs->size     = arr_size;
    gs->offset   = data_offset;

    int esz = (base == T_CHAR && !is_ptr) ? 1 : 2;
    int total = (arr_size > 0) ? arr_size * esz : esz;
    data_offset += total;

    /* アドレス定数を EQU で定義（コード内からのアクセス用） */
    /* データ実体は emit_data_section() で出力 */
    /* EQU はコードセクション内に出力（.orgより前） */
    emit("%-22s EQU $%04X", name, DATA_ORG + gs->offset);

    /* 初期値 */
    if (strcmp(t,"=")==0) {
        /* グローバル初期値 — 簡略: 0のみ対応 */
        next_tok(); /* = の右辺を読む（今は使わない） */
        t = next_tok();
    }
    if (strcmp(t,",")==0) {
        /* 複数宣言 — 簡略: 1変数のみ対応 */
        warning("multiple declarations in one statement not fully supported");
    }
    if (strcmp(t,";")!=0) {
        error("expected ';' after global declaration, got '%s'", t);
    }
}

/* ============================================================
 * ランタイムルーチン出力
 * ============================================================ */
static void emit_runtime(void) {
    emit("");
    emit("; ============================================================");
    emit("; scc22 runtime routines");
    emit("; ============================================================");
    emit("");

    /* putchar: A=char → UART出力 */
    emit("_putchar:");
    emit("    ; A = char to output");
    emit("_putchar_wait:");
    emit("    LDW  B, [$FC84]");
    emit("    CMPI B, #0");
    emit("    BEQ  _putchar_wait");
    emit("    STW  A, [$FC80]");
    emit("    RET");
    emit("");

    /* getchar: A = 読み込んだ文字 */
    emit("_getchar:");
    emit("    LDW  A, [$FC84]");
    emit("    CMPI A, #0");
    emit("    BEQ  _getchar");
    emit("    LDW  A, [$FC82]");
    emit("    RET");
    emit("");

    /* _cc_mul: B=left A=right → A=left*right */
    emit("_C_MUL_A EQU $E0D4");
    emit("_C_MUL_B EQU $E0D6");
    emit("_C_MUL_R EQU $E0D8");
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

    /* _cc_div: B=left(dividend) A=right(divisor) → A=quotient */
    emit("_C_DIV_A EQU $E0DA");
    emit("_C_DIV_B EQU $E0DC");
    emit("_C_DIV_Q EQU $E0DE");
    emit("_cc_div:");
    emit("    ; B / A → A");
    emit("    CMPI A, #0");
    emit("    BEQ  _ccdiv_zero");
    emit("    STW  A, [_C_DIV_A]");  /* divisor */
    emit("    STW  B, [_C_DIV_B]");  /* dividend */
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

    /* _cc_mod: B % A → A */
    emit("_cc_mod:");
    emit("    ; B mod A → A");
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
}

/* ============================================================
 * データセクション出力
 * ============================================================ */
static void emit_data_section(void) {
    if (data_offset == 0 && strlit_count == 0) return;

    emit("");
    emit("; ============================================================");
    emit("; Data section");
    emit("; ============================================================");
    emit("    .org $%04X", DATA_ORG);

    /* グローバル変数の実体 */
    for (sym_t *s = sym_table; s; s = s->next) {
        if (s->sclass != SC_GLOBAL || s->is_array) continue;
        int esz = (s->type == T_CHAR) ? 1 : 2;
        if (esz == 1)
            fprintf(out_fp, "_%s:\n    DB  0\n", s->name);
        else
            fprintf(out_fp, "_%s:\n    DW  0\n", s->name);
    }
    for (sym_t *s = sym_table; s; s = s->next) {
        if (s->sclass != SC_GLOBAL || !s->is_array) continue;
        int esz = (s->base == T_CHAR) ? 1 : 2;
        fprintf(out_fp, "_%s:\n    ", s->name);
        for (int i = 0; i < s->size; i++)
            fprintf(out_fp, "%s 0%s", esz==1?"DB":"DW",
                    i < s->size-1 ? ", " : "\n");
    }
}

/* ============================================================
 * main
 * ============================================================ */
int main(int argc, char **argv) {
    src_name   = "input.c";
    out_fp     = stdout;
    char *outname = NULL;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-o") == 0 && i+1 < argc) {
            outname = argv[++i];
        } else if (strcmp(argv[i], "-v") == 0) {
            printf("scc22 v%s\n", SCC_VERSION);
            return 0;
        } else if (argv[i][0] != '-') {
            src_name = argv[i];
        }
    }

    src_fp = fopen(src_name, "r");
    if (!src_fp) { perror(src_name); return 1; }
    if (outname) {
        out_fp = fopen(outname, "w");
        if (!out_fp) { perror(outname); fclose(src_fp); return 1; }
    }

    /* 出力ヘッダ */
    emit("; scc22 v%s  output: %s", SCC_VERSION, src_name);
    emit("; Target: YSD8800 ISA2.2");
    emit("; build: gcc -std=c99 -O2 -Wall scc22.c -o scc22");
    emit(";");
    emit("    .org $%04X", CODE_ORG);
    emit("");

    /* ランタイムを先頭に出力 */
    emit_runtime();
    emit("");
    emit("; ============================================================");
    emit("; User code");
    emit("; ============================================================");

    /* 組み込み関数を事前登録 */
    static const char *builtins[] = {
        "putchar","getchar","puts","printf",NULL
    };
    for (int bi = 0; builtins[bi]; bi++) {
        sym_t *bs = sym_alloc();
        strncpy(bs->name, builtins[bi], IDENT_LEN-1);
        bs->type    = T_INT;
        bs->sclass  = SC_FUNC;
        bs->defined = 1;
    }

    /* 初期化 */
    cur_line = 1;
    next_char();

    /* パース */
    for (;;) {
        skip_ws();
        if (cur_char == EOF) break;
        if (cur_char == '#') {
            next_char();
            const char *directive = next_tok();
            if (strcmp(directive, "define") == 0) handle_define();
            else {
                /* include等は無視 */
                while (cur_char != '\n' && cur_char != EOF) next_char();
            }
            continue;
        }
        parse_global();
    }

    /* データセクション */
    emit_data_section();

    fclose(src_fp);
    if (outname) fclose(out_fp);

    if (error_count > 0)
        fprintf(stderr, "scc22: %d error(s)\n", error_count);
    else
        fprintf(stderr, "scc22: compiled '%s'  errors=0\n", src_name);

    return error_count ? 1 : 0;
}
