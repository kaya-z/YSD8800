/* force/frontend/lexer.h
 * Force Forth Cross Compiler v1.0
 * 字句解析
 */
#ifndef LEXER_H
#define LEXER_H

#include <stdint.h>
#include <stdio.h>

/* ============================================================
 * トークン種別
 * ============================================================ */
typedef enum {
    TOK_EOF = 0,
    TOK_WORD,       /* 一般ワード名 / 命令 */
    TOK_NUMBER,     /* 数値リテラル */
    TOK_STRING,     /* S" text" または ." text" の文字列部分 */
    TOK_CHAR,       /* CHAR x → 文字コード */
} tok_type_t;

typedef struct {
    tok_type_t  type;
    char        sval[256];  /* TOK_WORD / TOK_STRING */
    int32_t     ival;       /* TOK_NUMBER / TOK_CHAR */
    int         lineno;
} token_t;

/* ============================================================
 * レクサー状態
 * ============================================================ */
typedef struct {
    FILE       *fp;
    const char *filename;
    int         lineno;
    int         pushback;   /* 1文字プッシュバック */
    int         base;       /* 現在の数値基数（10/16） */
    token_t     cur;        /* 現在のトークン */
    token_t     peek;       /* 先読みトークン */
    int         has_peek;
} lexer_t;

/* ============================================================
 * API
 * ============================================================ */
lexer_t   *lexer_new(FILE *fp, const char *filename);
void       lexer_free(lexer_t *lex);

/* 次のトークンを取得（スキップ: 空白・コメント）*/
token_t   *lexer_next(lexer_t *lex);

/* 現在のトークンを返す（advanceしない）*/
token_t   *lexer_peek(lexer_t *lex);

/* 残り行末までをtrimmingして文字列として読む（." 用）*/
int        lexer_read_until(lexer_t *lex, char delim, char *buf, int bufsz);

#endif /* LEXER_H */
