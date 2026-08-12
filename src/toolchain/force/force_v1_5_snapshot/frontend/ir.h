/* force/frontend/ir.h
 * Force Forth Cross Compiler v1.0
 * IR（中間表現）ノード定義
 */
#ifndef IR_H
#define IR_H

#include <stdint.h>

/* ============================================================
 * IR命令コード
 * ============================================================ */
typedef enum {
    /* 構造定義 */
    IR_WORD,        /* WORD name          */
    IR_END_WORD,    /* END-WORD           */
    IR_CONST_DEF,   /* CONST-DEF name val */
    IR_VAR_DEF,     /* VAR-DEF name size  */
    IR_VALUE_DEF,   /* VALUE-DEF name init*/
    IR_DEFER_DEF,   /* DEFER-DEF name     */
    IR_IS_DEF,      /* IS-DEF defer impl  */
    IR_CODE_BLOCK,  /* CODE-BLOCK         */
    IR_END_CODE,    /* END-CODE           */
    IR_ASM_LINE,    /* ASM-LINE "text"    */

    /* スタック・データ */
    IR_PUSH_LIT,    /* PUSH-LIT n         */
    IR_PUSH_STR,    /* PUSH-STR "text"    */
    IR_PRIM,        /* PRIM name          */

    /* 制御フロー */
    IR_LABEL,       /* LABEL .Ln          */
    IR_BRANCH,      /* BRANCH .Ln         */
    IR_BRANCH_F,    /* BRANCH-F .Ln       */
    IR_BRANCH_T,    /* BRANCH-T .Ln       */
    IR_CALL,        /* CALL name          */
    IR_RETURN,      /* RETURN             */

    /* メモリアクセス */
    IR_FETCH_W,     /* FETCH-W            */
    IR_STORE_W,     /* STORE-W            */
    IR_FETCH_B,     /* FETCH-B            */
    IR_STORE_B,     /* STORE-B            */

    /* リターンスタック */
    IR_RPUSH,       /* RPUSH              */
    IR_RPOP,        /* RPOP               */
    IR_RFETCH,      /* RFETCH             */

    IR_OPCODE_MAX
} ir_opcode_t;

/* ============================================================
 * IRノード
 * ============================================================ */
#define IR_MAX_STR  256

typedef struct ir_node {
    ir_opcode_t   op;
    int32_t       ival;         /* PUSH_LIT / LABEL / BRANCH* の値 */
    char          sval[IR_MAX_STR]; /* WORD/CALL/PRIM/ASM-LINE の文字列 */
    char          sval2[IR_MAX_STR];/* IS-DEF の第2オペランド */
    int           lineno;       /* デバッグ用ソース行番号 */
    struct ir_node *next;
} ir_node_t;

/* ============================================================
 * IRリスト（線形リスト）
 * ============================================================ */
typedef struct {
    ir_node_t *head;
    ir_node_t *tail;
    int        count;
} ir_list_t;

/* ============================================================
 * API
 * ============================================================ */
ir_list_t  *ir_list_new(void);
void        ir_list_free(ir_list_t *list);

ir_node_t  *ir_node_new(ir_opcode_t op);
void        ir_append(ir_list_t *list, ir_node_t *node);

/* ショートカット生成関数 */
ir_node_t  *ir_make_word(const char *name);
ir_node_t  *ir_make_end_word(void);
ir_node_t  *ir_make_push_lit(int32_t val);
ir_node_t  *ir_make_prim(const char *name);
ir_node_t  *ir_make_call(const char *name);
ir_node_t  *ir_make_return(void);
ir_node_t  *ir_make_label(int n);
ir_node_t  *ir_make_branch(int n);
ir_node_t  *ir_make_branch_f(int n);
ir_node_t  *ir_make_branch_t(int n);
ir_node_t  *ir_make_const_def(const char *name, int32_t val);
ir_node_t  *ir_make_var_def(const char *name, int size);
ir_node_t  *ir_make_value_def(const char *name, int32_t init);
ir_node_t  *ir_make_defer_def(const char *name);
ir_node_t  *ir_make_is_def(const char *defer, const char *impl);
ir_node_t  *ir_make_code_block(void);
ir_node_t  *ir_make_end_code(void);
ir_node_t  *ir_make_asm_line(const char *text);
ir_node_t  *ir_make_simple(ir_opcode_t op);  /* 引数なし命令 */

/* テキスト出力 */
void        ir_print(ir_list_t *list, FILE *fp);
const char *ir_opname(ir_opcode_t op);

#endif /* IR_H */
