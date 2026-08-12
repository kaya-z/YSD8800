/* force/backend/codegen.h
 * Force Forth Cross Compiler v1.0
 * バックエンド: IR → アセンブラ変換
 */
#ifndef CODEGEN_H
#define CODEGEN_H

#include <stdio.h>
#include "../frontend/ir.h"

/* ============================================================
 * ターゲット設定
 * ============================================================ */
#define TGT_STR_MAX 64

typedef struct {
    char arch[TGT_STR_MAX];
    int  cell_size;          /* バイト単位 */
    char assembler[TGT_STR_MAX];
    char code_start[TGT_STR_MAX];   /* 例: "$0020" */
    char data_start[TGT_STR_MAX];   /* 例: "$E200" */
    char ds_reg[TGT_STR_MAX];       /* データスタックポインタレジスタ */
    char rs_reg[TGT_STR_MAX];       /* リターンスタックポインタ */
    char tos_reg[TGT_STR_MAX];      /* TOS演算レジスタ */
    char aux_reg[TGT_STR_MAX];      /* 補助レジスタ */
    char thread_model[TGT_STR_MAX]; /* "subroutine" / "indirect" */
    char hex_prefix[TGT_STR_MAX];   /* "$" または "0x" */
    char defer_model[TGT_STR_MAX];  /* "vector" */
    char label_prefix[TGT_STR_MAX]; /* "WORD_" */
    int  code_auto_ret;             /* 1: CODEブロックにRET自動挿入 */
} target_t;

/* ============================================================
 * プリミティブテンプレート
 * ============================================================ */
#define PRIM_NAME_MAX  32
#define PRIM_BODY_MAX  2048
#define PRIM_COUNT_MAX 128

typedef struct {
    char name[PRIM_NAME_MAX];
    char body[PRIM_BODY_MAX];
} prim_template_t;

typedef struct {
    prim_template_t prims[PRIM_COUNT_MAX];
    int             count;
} prim_table_t;

/* ============================================================
 * コードジェネレータ
 * ============================================================ */
typedef struct {
    target_t    tgt;
    prim_table_t ptbl;
    FILE        *out;
    int          data_org;   /* 現在のデータ領域ORGアドレス */
    int          errors;
} codegen_t;

/* ============================================================
 * API
 * ============================================================ */
/* ターゲット設定ファイルを読み込む */
int  target_load(target_t *tgt, const char *path);

/* プリミティブテンプレートファイルを読み込む */
int  prim_load(prim_table_t *ptbl, const char *path, const target_t *tgt);

/* コードジェネレータを生成 */
codegen_t *codegen_new(const char *tgt_path, const char *prim_path, FILE *out);
void       codegen_free(codegen_t *cg);

/* IRリストからアセンブラを生成 */
int  codegen_emit(codegen_t *cg, ir_list_t *ir);

#endif /* CODEGEN_H */
