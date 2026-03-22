/* force/frontend/parser.h
 * Force Forth Cross Compiler v1.0
 * 構文解析・IR生成
 */
#ifndef PARSER_H
#define PARSER_H

#include "lexer.h"
#include "ir.h"

/* ============================================================
 * CONSTANT辞書（使用箇所でPUSH-LITに展開）
 * ============================================================ */
#define MAX_CONSTS  256
typedef struct {
    char     name[64];
    int32_t  val;
} const_entry_t;

/* ============================================================
 * VALUE辞書（TO のためにアドレスを記憶）
 * ============================================================ */
#define MAX_VALUES  256
typedef struct {
    char     name[64];
    int32_t  init;
    int      idx;       /* データ領域内のインデックス */
} value_entry_t;

/* ============================================================
 * パーサ状態
 * ============================================================ */
typedef struct {
    lexer_t       *lex;
    ir_list_t     *ir;
    int            label_counter;   /* グローバルラベル番号 */
    int            in_definition;   /* : ... ; の内側か */
    int            in_code;         /* CODE ... END-CODE の内側か */
    int            data_offset;     /* VARIABLEデータ領域オフセット */

    /* CONSTANT辞書 */
    const_entry_t  consts[MAX_CONSTS];
    int            const_count;

    /* VALUE辞書 */
    value_entry_t  values[MAX_VALUES];
    int            value_count;

    /* エラーカウント */
    int            errors;
} parser_t;

/* ============================================================
 * API
 * ============================================================ */
parser_t  *parser_new(lexer_t *lex);
void       parser_free(parser_t *p);

/* ソースを全て解析してIRリストを返す */
ir_list_t *parser_parse(parser_t *p);

/* エラーカウントを返す */
int        parser_errors(parser_t *p);

#endif /* PARSER_H */
