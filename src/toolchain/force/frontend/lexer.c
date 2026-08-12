/* force/frontend/lexer.c
 * Force Forth Cross Compiler v1.0
 * 字句解析実装
 *
 * Forthの字句解析はシンプル:
 *   空白区切りのトークン列
 *   コメント: \ 行末まで / ( 括弧コメント )
 *   文字列:   S" text"  ." text"
 *   数値:     123 / $FF / 0x1A / -1 / #65
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <errno.h>
#include "lexer.h"

/* ============================================================
 * 内部ヘルパー
 * ============================================================ */
static int lex_getc(lexer_t *lex) {
    int c;
    if (lex->pushback >= 0) {
        c = lex->pushback;
        lex->pushback = -1;
        return c;
    }
    c = fgetc(lex->fp);
    if (c == '\n') lex->lineno++;
    return c;
}

static void lex_ungetc(lexer_t *lex, int c) {
    lex->pushback = c;
    if (c == '\n') lex->lineno--;
}

/* 空白をスキップ */
static int skip_ws(lexer_t *lex) {
    int c;
    for (;;) {
        c = lex_getc(lex);
        if (c == EOF) return EOF;
        if (!isspace((unsigned char)c)) return c;
    }
}

/* 行末コメント \ をスキップ */
static void skip_line(lexer_t *lex) {
    int c;
    while ((c = lex_getc(lex)) != EOF && c != '\n')
        ;
}

/* 括弧コメント ( ... ) をスキップ */
static void skip_paren(lexer_t *lex) {
    int c;
    while ((c = lex_getc(lex)) != EOF && c != ')')
        ;
}

/* 数値解析: 成功したら1、失敗したら0 */
static int parse_number(const char *s, int base, int32_t *out) {
    if (!s || !*s) return 0;
    char *end;
    int neg = 0;
    const char *p = s;

    if (*p == '-') { neg = 1; p++; }
    if (!*p) return 0;

    errno = 0;
    int32_t val;

    if (p[0] == '$') {                      /* $FF 形式 */
        val = (int32_t)strtoul(p+1, &end, 16);
    } else if (p[0]=='0' && (p[1]=='x'||p[1]=='X')) { /* 0xFF 形式 */
        val = (int32_t)strtoul(p+2, &end, 16);
    } else if (p[0]=='#') {                 /* #65 文字コード（10進） */
        val = (int32_t)strtoul(p+1, &end, 10);
    } else {
        /* 現在の基数（デフォルト10） */
        val = (int32_t)strtoul(p, &end, base);
    }

    if (errno || end == p || *end != '\0') return 0;
    *out = neg ? -val : val;
    return 1;
}

/* トークン文字列を大文字正規化した比較 */
static int tok_eq(const char *s, const char *upper) {
    char tmp[256];
    int i;
    for (i = 0; s[i] && i < 255; i++)
        tmp[i] = toupper((unsigned char)s[i]);
    tmp[i] = '\0';
    return strcmp(tmp, upper) == 0;
}

/* ============================================================
 * API実装
 * ============================================================ */
lexer_t *lexer_new(FILE *fp, const char *filename) {
    lexer_t *lex = calloc(1, sizeof(lexer_t));
    if (!lex) { perror("lexer_new"); exit(1); }
    lex->fp       = fp;
    lex->filename = filename;
    lex->lineno   = 1;
    lex->pushback = -1;
    lex->base     = 10;
    return lex;
}

void lexer_free(lexer_t *lex) {
    free(lex);
}

/* ============================================================
 * 次のトークンを読む
 * ============================================================ */
token_t *lexer_next(lexer_t *lex) {
    token_t *tok = &lex->cur;

    if (lex->has_peek) {
        lex->cur = lex->peek;
        lex->has_peek = 0;
        return tok;
    }

retry:;
    int c = skip_ws(lex);

    if (c == EOF) {
        tok->type = TOK_EOF;
        tok->lineno = lex->lineno;
        return tok;
    }

    tok->lineno = lex->lineno;

    /* 行末コメント \ */
    if (c == '\\') {
        skip_line(lex);
        goto retry;
    }

    /* 括弧コメント ( ... ) */
    if (c == '(') {
        skip_paren(lex);
        goto retry;
    }

    /* 文字列: S" text"  または  ." text" */
    /* S" と ." は直後に空白1つ、その後 " まで */
    if ((c == 'S' || c == 's' || c == '.' ) ) {
        int nc = lex_getc(lex);
        if (nc == '"') {
            /* S"  または  ."  → 文字列読み取り */
            /* 先頭の空白1つをスキップ */
            int sc = lex_getc(lex);
            if (sc != ' ' && sc != '\t') lex_ungetc(lex, sc);
            int i = 0;
            while ((sc = lex_getc(lex)) != EOF && sc != '"' && i < 254)
                tok->sval[i++] = (char)sc;
            tok->sval[i] = '\0';
            tok->type = TOK_STRING;
            return tok;
        }
        lex_ungetc(lex, nc);
        /* 通常のワードとして処理 */
    }

    /* 通常トークン（空白で区切られた単語）を読む */
    int i = 0;
    tok->sval[i++] = (char)c;
    while (i < 254) {
        c = lex_getc(lex);
        if (c == EOF || isspace((unsigned char)c)) break;
        tok->sval[i++] = (char)c;
    }
    tok->sval[i] = '\0';

    /* CHAR x → 文字コード */
    if (tok_eq(tok->sval, "CHAR") || tok_eq(tok->sval, "[CHAR]")) {
        token_t *next = lexer_next(lex);
        if (next->type == TOK_WORD && next->sval[0]) {
            tok->type = TOK_NUMBER;
            tok->ival = (unsigned char)next->sval[0];
        }
        return tok;
    }

    /* BASE 変更命令 */
    if (tok_eq(tok->sval, "HEX"))     { lex->base = 16; goto retry; }
    if (tok_eq(tok->sval, "DECIMAL")) { lex->base = 10; goto retry; }

    /* 数値として解析を試みる */
    int32_t nval;
    if (parse_number(tok->sval, lex->base, &nval)) {
        tok->type = TOK_NUMBER;
        tok->ival = nval;
        return tok;
    }

    /* 通常のワード */
    tok->type = TOK_WORD;
    return tok;
}

/* 先読み */
token_t *lexer_peek(lexer_t *lex) {
    if (!lex->has_peek) {
        token_t saved = lex->cur;
        lexer_next(lex);
        lex->peek = lex->cur;
        lex->cur = saved;
        lex->has_peek = 1;
    }
    return &lex->peek;
}

/* デリミタまで読む（." 等で使用） */
int lexer_read_until(lexer_t *lex, char delim, char *buf, int bufsz) {
    int i = 0, c;
    while ((c = lex_getc(lex)) != EOF && c != delim && i < bufsz-1)
        buf[i++] = (char)c;
    buf[i] = '\0';
    return i;
}
