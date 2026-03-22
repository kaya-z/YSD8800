/* force/frontend/parser.c
 * Force Forth Cross Compiler v1.0
 * 構文解析・IR生成実装
 *
 * トップレベルで認識する構文:
 *   : name ... ;           コロン定義
 *   CONSTANT  VARIABLE  VALUE  DEFER  IS
 *   CODE ... END-CODE
 *   数値 単体              トップレベル数値（定数定義の前置値）
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include "parser.h"

/* ============================================================
 * エラー報告
 * ============================================================ */
static void parse_error(parser_t *p, const char *msg) {
    fprintf(stderr, "%s:%d: error: %s\n",
            p->lex->filename, p->lex->cur.lineno, msg);
    p->errors++;
}

/* ============================================================
 * ラベル番号採番
 * ============================================================ */
static int new_label(parser_t *p) {
    return p->label_counter++;
}

/* ============================================================
 * ワード名のマングリング（記号 → ASCII名）
 * ============================================================ */
static void mangle_name(const char *src, char *dst, int dstsz) {
    /* よく使う記号ワードの変換テーブル */
    static const struct { const char *forth; const char *mangled; } tbl[] = {
        {"+",  "PLUS"},    {"-",  "MINUS"},   {"*",  "STAR"},
        {"/",  "SLASH"},   {"<",  "LT"},      {">",  "GT"},
        {"=",  "EQ"},      {"<>", "NE"},      {"<=", "LE"},
        {">=", "GE"},      {"@",  "FETCH"},   {"!",  "STORE"},
        {"c@", "CFETCH"},  {"c!", "CSTORE"},  {"+!", "PLUSSTORE"},
        {"0=", "0EQ"},     {"0<", "0LT"},     {"0>", "0GT"},
        {"2*", "2STAR"},   {"2/", "2SLASH"},
        {"/mod","SLASHMOD"},
        {NULL, NULL}
    };
    /* 小文字化して検索 */
    char lower[128];
    int i;
    for (i = 0; src[i] && i < 127; i++)
        lower[i] = tolower((unsigned char)src[i]);
    lower[i] = '\0';

    for (int j = 0; tbl[j].forth; j++) {
        if (strcmp(lower, tbl[j].forth) == 0) {
            snprintf(dst, dstsz, "%s", tbl[j].mangled);
            return;
        }
    }

    /* ハイフン→アンダースコア、それ以外はそのまま */
    int di = 0;
    for (i = 0; src[i] && di < dstsz-1; i++) {
        if (src[i] == '-') dst[di++] = '_';
        else dst[di++] = src[i];
    }
    dst[di] = '\0';
}

/* ============================================================
 * VALUE辞書
 * ============================================================ */
/* ============================================================
 * CONSTANT辞書
 * ============================================================ */
static void add_const(parser_t *p, const char *name, int32_t val) {
    if (p->const_count >= MAX_CONSTS) { parse_error(p,"too many CONSTANTs"); return; }
    const_entry_t *c = &p->consts[p->const_count++];
    snprintf(c->name, sizeof(c->name), "%s", name);
    c->val = val;
}

static const_entry_t *find_const(parser_t *p, const char *name) {
    for (int i = 0; i < p->const_count; i++)
        if (strcasecmp(p->consts[i].name, name) == 0)
            return &p->consts[i];
    return NULL;
}

static value_entry_t *find_value(parser_t *p, const char *name) {
    for (int i = 0; i < p->value_count; i++)
        if (strcasecmp(p->values[i].name, name) == 0)
            return &p->values[i];
    return NULL;
}

static void add_value(parser_t *p, const char *name, int32_t init) {
    if (p->value_count >= MAX_VALUES) {
        parse_error(p, "too many VALUEs");
        return;
    }
    value_entry_t *v = &p->values[p->value_count++];
    snprintf(v->name, sizeof(v->name), "%s", name);
    v->init = init;
    v->idx  = p->data_offset;
    p->data_offset += 2;  /* 16bit = 2bytes */
}

/* ============================================================
 * 内部ワードのコンパイル（: ... ; の本体）
 * ============================================================ */
/*
 * 制御構造スタック
 * IF/ELSE/THEN, BEGIN/WHILE/REPEAT, BEGIN/UNTIL/AGAIN
 * をネストするためのスタック
 */
#define CS_MAX 64
typedef struct {
    int type;   /* CS_IF CS_BEGIN CS_WHILE */
    int L1;
    int L2;
} cs_entry_t;

#define CS_IF    1
#define CS_BEGIN 2
#define CS_WHILE 3

typedef struct {
    cs_entry_t stack[CS_MAX];
    int top;
} cs_stack_t;

static void cs_push(cs_stack_t *cs, int type, int L1, int L2) {
    if (cs->top >= CS_MAX) { fprintf(stderr, "control stack overflow\n"); return; }
    cs->stack[cs->top].type = type;
    cs->stack[cs->top].L1   = L1;
    cs->stack[cs->top].L2   = L2;
    cs->top++;
}
static cs_entry_t *cs_pop(cs_stack_t *cs) {
    if (cs->top <= 0) return NULL;
    return &cs->stack[--cs->top];
}
static cs_entry_t *cs_peek_cs(cs_stack_t *cs) {
    if (cs->top <= 0) return NULL;
    return &cs->stack[cs->top-1];
}

/* ワード本体をコンパイルしてIRを追加する */
static void compile_body(parser_t *p, cs_stack_t *cs) {
    token_t *tok;

    while ((tok = lexer_next(p->lex))->type != TOK_EOF) {
        /* ; — 定義終了 */
        if (tok->type == TOK_WORD && strcasecmp(tok->sval, ";") == 0) {
            ir_append(p->ir, ir_make_return());
            return;
        }

        /* EXIT — 定義の途中でリターン */
        if (tok->type == TOK_WORD && strcasecmp(tok->sval, "EXIT") == 0) {
            ir_append(p->ir, ir_make_return());
            continue;
        }

        /* HALT — CPU停止（デバッグ/終了用） */
        if (tok->type == TOK_WORD && strcasecmp(tok->sval, "HALT") == 0) {
            ir_node_t *hn = ir_node_new(IR_ASM_LINE);
            snprintf(hn->sval, IR_MAX_STR, "    HALT");
            ir_append(p->ir, hn);
            continue;
        }

        /* 数値リテラル */
        if (tok->type == TOK_NUMBER) {
            ir_append(p->ir, ir_make_push_lit(tok->ival));
            continue;
        }

        /* 文字列リテラル */
        if (tok->type == TOK_STRING) {
            ir_node_t *n = ir_node_new(IR_PUSH_STR);
            snprintf(n->sval, IR_MAX_STR, "%s", tok->sval);
            ir_append(p->ir, n);
            continue;
        }

        if (tok->type != TOK_WORD) continue;

        /* 大文字比較用 */
        char up[128];
        int j;
        for (j = 0; tok->sval[j] && j < 127; j++)
            up[j] = toupper((unsigned char)tok->sval[j]);
        up[j] = '\0';

        /* ============ 制御構造 ============ */

        /* IF → BRANCH-F .L0 */
        if (strcmp(up, "IF") == 0) {
            int L0 = new_label(p);
            ir_append(p->ir, ir_make_branch_f(L0));
            cs_push(cs, CS_IF, L0, -1);
            continue;
        }

        /* ELSE → BRANCH .L1 ; LABEL .L0 */
        if (strcmp(up, "ELSE") == 0) {
            cs_entry_t *e = cs_peek_cs(cs);
            if (!e || e->type != CS_IF) {
                parse_error(p, "ELSE without IF"); continue;
            }
            int L1 = new_label(p);
            ir_append(p->ir, ir_make_branch(L1));
            ir_append(p->ir, ir_make_label(e->L1));
            e->L1 = L1;     /* THENで使うラベルをL1に更新 */
            e->type = CS_WHILE; /* ELSEがあったことを示すためにCS_WHILEを流用 */
            continue;
        }

        /* THEN → LABEL .L0 */
        if (strcmp(up, "THEN") == 0) {
            cs_entry_t *e = cs_pop(cs);
            if (!e) { parse_error(p, "THEN without IF"); continue; }
            ir_append(p->ir, ir_make_label(e->L1));
            continue;
        }

        /* BEGIN → LABEL .L0 */
        if (strcmp(up, "BEGIN") == 0) {
            int L0 = new_label(p);
            ir_append(p->ir, ir_make_label(L0));
            cs_push(cs, CS_BEGIN, L0, -1);
            continue;
        }

        /* WHILE → BRANCH-F .L1 */
        if (strcmp(up, "WHILE") == 0) {
            cs_entry_t *e = cs_peek_cs(cs);
            if (!e || e->type != CS_BEGIN) {
                parse_error(p, "WHILE without BEGIN"); continue;
            }
            int L1 = new_label(p);
            ir_append(p->ir, ir_make_branch_f(L1));
            e->type = CS_WHILE;
            e->L2   = L1;   /* REPEAT用の脱出ラベル */
            continue;
        }

        /* REPEAT → BRANCH .L0 ; LABEL .L1 */
        if (strcmp(up, "REPEAT") == 0) {
            cs_entry_t *e = cs_pop(cs);
            if (!e || e->type != CS_WHILE) {
                parse_error(p, "REPEAT without BEGIN/WHILE"); continue;
            }
            ir_append(p->ir, ir_make_branch(e->L1));
            ir_append(p->ir, ir_make_label(e->L2));
            continue;
        }

        /* UNTIL → BRANCH-F .L0 */
        if (strcmp(up, "UNTIL") == 0) {
            cs_entry_t *e = cs_pop(cs);
            if (!e || e->type != CS_BEGIN) {
                parse_error(p, "UNTIL without BEGIN"); continue;
            }
            ir_append(p->ir, ir_make_branch_f(e->L1));
            continue;
        }

        /* AGAIN → BRANCH .L0 */
        if (strcmp(up, "AGAIN") == 0) {
            cs_entry_t *e = cs_pop(cs);
            if (!e || e->type != CS_BEGIN) {
                parse_error(p, "AGAIN without BEGIN"); continue;
            }
            ir_append(p->ir, ir_make_branch(e->L1));
            continue;
        }

        /* ============ リターンスタック ============ */
        if (strcmp(up, ">R") == 0)  { ir_append(p->ir, ir_make_simple(IR_RPUSH));  continue; }
        if (strcmp(up, "R>") == 0)  { ir_append(p->ir, ir_make_simple(IR_RPOP));   continue; }
        if (strcmp(up, "R@") == 0)  { ir_append(p->ir, ir_make_simple(IR_RFETCH)); continue; }

        /* ============ メモリアクセス直接指定 ============ */
        if (strcmp(up, "@") == 0)   { ir_append(p->ir, ir_make_simple(IR_FETCH_W)); continue; }
        if (strcmp(up, "!") == 0)   { ir_append(p->ir, ir_make_simple(IR_STORE_W)); continue; }
        if (strcmp(up, "C@") == 0)  { ir_append(p->ir, ir_make_simple(IR_FETCH_B)); continue; }
        if (strcmp(up, "C!") == 0)  { ir_append(p->ir, ir_make_simple(IR_STORE_B)); continue; }

        /* ============ TO（VALUE書き込み） ============ */
        if (strcmp(up, "TO") == 0) {
            token_t *nt = lexer_next(p->lex);
            if (nt->type != TOK_WORD) {
                parse_error(p, "TO expects a name"); continue;
            }
            value_entry_t *ve = find_value(p, nt->sval);
            if (!ve) {
                char msg[128];
                snprintf(msg, sizeof(msg), "TO: unknown VALUE '%s'", nt->sval);
                parse_error(p, msg); continue;
            }
            /* val addr STORE-W */
            char mangled[128];
            mangle_name(nt->sval, mangled, sizeof(mangled));
            ir_append(p->ir, ir_make_call(mangled)); /* VARの場合はアドレスをpush */
            ir_append(p->ir, ir_make_simple(IR_STORE_W));
            continue;
        }

        /* ============ PRIM認識（よく使うワード） ============ */
        /* @/! は上で処理済み。PRIMとして展開するワードの一覧 */
        static const char *prims[] = {
            "DUP","DROP","SWAP","OVER","ROT","NIP","TUCK","2DUP","2DROP",
            "+","-","*","/MOD","/","MOD","NEGATE","ABS","MAX","MIN",
            "1+","1-","2*","2/","LSHIFT","RSHIFT",
            "0=","0<","0>","0<>","=","<>","<",">","<=",">=",
            "AND","OR","XOR","INVERT",
            "+!","EMIT","KEY",
            NULL
        };
        int is_prim = 0;
        for (int pi = 0; prims[pi]; pi++) {
            if (strcasecmp(tok->sval, prims[pi]) == 0) {
                /* PRIMの標準名称に変換 */
                char pname[64];
                mangle_name(tok->sval, pname, sizeof(pname));
                /* 特別マッピング */
                if (strcmp(up, "+") == 0)     strcpy(pname, "PLUS");
                else if (strcmp(up, "-") == 0) strcpy(pname, "MINUS");
                else if (strcmp(up, "*") == 0) strcpy(pname, "STAR");
                else if (strcmp(up, "/") == 0) strcpy(pname, "SLASH");
                else if (strcmp(up, "1+") == 0) strcpy(pname, "ONE-PLUS");
                else if (strcmp(up, "1-") == 0) strcpy(pname, "ONE-MINUS");
                else if (strcmp(up, "2*") == 0) strcpy(pname, "TWO-STAR");
                else if (strcmp(up, "2/") == 0) strcpy(pname, "TWO-SLASH");
                else if (strcmp(up, "0=") == 0) strcpy(pname, "ZERO-EQ");
                else if (strcmp(up, "0<") == 0) strcpy(pname, "ZERO-LT");
                else if (strcmp(up, "0>") == 0) strcpy(pname, "ZERO-GT");
                else if (strcmp(up, "0<>") == 0) strcpy(pname, "ZERO-NE");
                else if (strcmp(up, "=") == 0)  strcpy(pname, "EQ");
                else if (strcmp(up, "<>") == 0) strcpy(pname, "NE");
                else if (strcmp(up, "<") == 0)  strcpy(pname, "LT");
                else if (strcmp(up, ">") == 0)  strcpy(pname, "GT");
                else if (strcmp(up, "<=") == 0) strcpy(pname, "LE");
                else if (strcmp(up, ">=") == 0) strcpy(pname, "GE");
                else if (strcmp(up, "+!") == 0) strcpy(pname, "PLUS-STORE");
                else if (strcmp(up, "/MOD") == 0) strcpy(pname, "SLASH-MOD");
                else {
                    /* それ以外はUPPER化 */
                    for (int k = 0; up[k]; k++) pname[k] = up[k];
                    pname[strlen(up)] = '\0';
                }
                ir_append(p->ir, ir_make_prim(pname));
                is_prim = 1;
                break;
            }
        }
        if (is_prim) continue;

        /* ============ CONSTANT → PUSH-LIT に展開 ============ */
        {
            const_entry_t *ce = find_const(p, tok->sval);
            if (ce) {
                ir_append(p->ir, ir_make_push_lit(ce->val));
                continue;
            }
        }

        /* ============ 通常のワード呼び出し ============ */
        char mangled[128];
        mangle_name(tok->sval, mangled, sizeof(mangled));
        ir_append(p->ir, ir_make_call(mangled));
    }

    /* ; に到達せずにEOF */
    parse_error(p, "missing ; at end of definition");
    ir_append(p->ir, ir_make_return());
}

/* ============================================================
 * トップレベルパーサ
 * ============================================================ */
static void parse_toplevel(parser_t *p) {
    int32_t pending_num = 0;
    int     has_pending = 0;
    char    pending_name[128] = "";   /* ['] で記憶したimpl名 */
    int     has_pending_name = 0;

    token_t *tok;
    while ((tok = lexer_next(p->lex))->type != TOK_EOF) {

        /* 数値: 次のCONSTANT/VARIABLE/VALUEのための前置値 */
        if (tok->type == TOK_NUMBER) {
            pending_num = tok->ival;
            has_pending = 1;
            continue;
        }

        if (tok->type != TOK_WORD) continue;

        char up[128];
        int j;
        for (j = 0; tok->sval[j] && j < 127; j++)
            up[j] = toupper((unsigned char)tok->sval[j]);
        up[j] = '\0';

        /* ======== : name ... ; ======== */
        if (strcmp(up, ":") == 0) {
            token_t *nt = lexer_next(p->lex);
            if (nt->type == TOK_EOF) { parse_error(p, "unexpected EOF after :"); return; }
            char mangled[128];
            mangle_name(nt->sval, mangled, sizeof(mangled));
            ir_append(p->ir, ir_make_word(mangled));
            p->in_definition = 1;
            cs_stack_t cs = {0};
            compile_body(p, &cs);
            p->in_definition = 0;
            ir_append(p->ir, ir_make_end_word());
            has_pending = 0;
            continue;
        }

        /* ======== CONSTANT ======== */
        if (strcmp(up, "CONSTANT") == 0) {
            token_t *nt = lexer_next(p->lex);
            if (!has_pending) { parse_error(p, "CONSTANT without preceding value"); continue; }
            ir_append(p->ir, ir_make_const_def(nt->sval, pending_num));
            add_const(p, nt->sval, pending_num);  /* 辞書に登録 */
            has_pending = 0;
            continue;
        }

        /* ======== VARIABLE ======== */
        if (strcmp(up, "VARIABLE") == 0) {
            token_t *nt = lexer_next(p->lex);
            char mangled[128];
            mangle_name(nt->sval, mangled, sizeof(mangled));
            ir_append(p->ir, ir_make_var_def(mangled, 2)); /* 16bit = 2bytes */
            has_pending = 0;
            continue;
        }

        /* ======== VALUE ======== */
        if (strcmp(up, "VALUE") == 0) {
            token_t *nt = lexer_next(p->lex);
            if (!has_pending) { parse_error(p, "VALUE without preceding init value"); continue; }
            char mangled[128];
            mangle_name(nt->sval, mangled, sizeof(mangled));
            ir_append(p->ir, ir_make_value_def(mangled, pending_num));
            add_value(p, nt->sval, pending_num);
            has_pending = 0;
            continue;
        }

        /* ======== DEFER ======== */
        if (strcmp(up, "DEFER") == 0) {
            token_t *nt = lexer_next(p->lex);
            char mangled[128];
            mangle_name(nt->sval, mangled, sizeof(mangled));
            ir_append(p->ir, ir_make_defer_def(mangled));
            has_pending = 0;
            continue;
        }

        /* ======== ['] name  (tick) ======== */
        if (strcmp(up, "[']") == 0) {
            token_t *nt = lexer_next(p->lex);
            if (nt->type == TOK_WORD) {
                mangle_name(nt->sval, pending_name, sizeof(pending_name));
                has_pending_name = 1;
            }
            has_pending = 0;
            continue;
        }

        /* ======== IS  書式: ['] impl IS defer ======== */
        if (strcmp(up, "IS") == 0) {
            token_t *defer_tok = lexer_next(p->lex);
            char mdefer[128];
            mangle_name(defer_tok->sval, mdefer, sizeof(mdefer));
            if (has_pending_name) {
                ir_append(p->ir, ir_make_is_def(mdefer, pending_name));
                has_pending_name = 0;
            } else {
                fprintf(stderr, "warning: IS without preceding [']\n");
            }
            has_pending = 0;
            continue;
        }

        /* ======== CODE ... END-CODE ======== */
        if (strcmp(up, "CODE") == 0) {
            token_t *nt = lexer_next(p->lex);
            char mangled[128];
            mangle_name(nt->sval, mangled, sizeof(mangled));
            ir_append(p->ir, ir_make_word(mangled));
            ir_append(p->ir, ir_make_code_block());
            p->in_code = 1;

            /* END-CODEまでの行を ASM-LINE として読む */
            char linebuf[256];
            int  li = 0;
            int  c;
            /* 行の途中から読み始めるので改行まで読み飛ばす */
            while ((c = fgetc(p->lex->fp)) != EOF && c != '\n')
                ;
            /* 以降、END-CODEが出るまで行単位で読む */
            while (!feof(p->lex->fp)) {
                li = 0;
                while ((c = fgetc(p->lex->fp)) != EOF && c != '\n') {
                    if (li < 254) linebuf[li++] = (char)c;
                }
                linebuf[li] = '\0';
                /* 行をtrimして END-CODE チェック */
                char *s = linebuf;
                while (*s == ' ' || *s == '\t') s++;
                char chk[16];
                int ci = 0;
                while (s[ci] && !isspace((unsigned char)s[ci]) && ci < 15)
                    chk[ci] = toupper((unsigned char)s[ci]), ci++;
                chk[ci] = '\0';
                if (strcmp(chk, "END-CODE") == 0) break;
                ir_append(p->ir, ir_make_asm_line(linebuf));
            }
            ir_append(p->ir, ir_make_end_code());
            ir_append(p->ir, ir_make_return());
            ir_append(p->ir, ir_make_end_word());
            p->in_code = 0;
            has_pending = 0;
            continue;
        }

        /* ======== TO（トップレベル: n TO value-name）======== */
        if (strcmp(up, "TO") == 0) {
            token_t *nt = lexer_next(p->lex);
            if (!has_pending) {
                parse_error(p, "TO without preceding value"); continue;
            }
            char mangled[128];
            mangle_name(nt->sval, mangled, sizeof(mangled));
            /* PUSH-LIT n + PUSH-LIT addr + STORE-W をWORD定義として生成 */
            /* トップレベルTOは初期化コードとして出力 */
            /* シンプル化: VALUE-DEFの初期値を変更する IS-DEF相当 */
            /* バックエンドはVAL_nameに pending_numを書き込むコードを生成 */
            ir_node_t *n2 = ir_node_new(IR_CONST_DEF);
            /* TODO: トップレベルTOの本格対応は初期化ルーティンで行う */
            /* 現在は VALUE-DEFの初期値を上書きするEQUとして扱う（近似） */
            snprintf(n2->sval, IR_MAX_STR, "_TO_%s", mangled);
            n2->ival = pending_num;
            ir_append(p->ir, n2);
            has_pending = 0;
            continue;
        }

        /* ======== INCLUDE（簡易対応: 無視してコメント） ======== */
        if (strcmp(up, "INCLUDE") == 0) {
            lexer_next(p->lex); /* ファイル名を読み飛ばす（今は未対応） */
            has_pending = 0;
            continue;
        }

        /* 未知のトップレベルワードは無視（警告のみ） */
        if (tok->type == TOK_WORD) {
            /* has_pendingを持ち越す（数値の後ろのワードが来た場合）*/
        }
    }
}

/* ============================================================
 * API実装
 * ============================================================ */
parser_t *parser_new(lexer_t *lex) {
    parser_t *p = calloc(1, sizeof(parser_t));
    if (!p) { perror("parser_new"); exit(1); }
    p->lex  = lex;
    p->ir   = ir_list_new();
    return p;
}

void parser_free(parser_t *p) {
    /* IRリストはparser外で使うので解放しない */
    free(p);
}

ir_list_t *parser_parse(parser_t *p) {
    parse_toplevel(p);
    return p->ir;
}

int parser_errors(parser_t *p) {
    return p->errors;
}
