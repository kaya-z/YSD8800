/* force/frontend/ir.c
 * Force Forth Cross Compiler v1.0
 * IR（中間表現）実装
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "ir.h"

/* ============================================================
 * リスト管理
 * ============================================================ */
ir_list_t *ir_list_new(void) {
    ir_list_t *l = calloc(1, sizeof(ir_list_t));
    if (!l) { perror("ir_list_new"); exit(1); }
    return l;
}

void ir_list_free(ir_list_t *list) {
    ir_node_t *n = list->head;
    while (n) {
        ir_node_t *nx = n->next;
        free(n);
        n = nx;
    }
    free(list);
}

ir_node_t *ir_node_new(ir_opcode_t op) {
    ir_node_t *n = calloc(1, sizeof(ir_node_t));
    if (!n) { perror("ir_node_new"); exit(1); }
    n->op = op;
    return n;
}

void ir_append(ir_list_t *list, ir_node_t *node) {
    node->next = NULL;
    if (!list->head) list->head = node;
    else             list->tail->next = node;
    list->tail = node;
    list->count++;
}

/* ============================================================
 * ショートカット生成
 * ============================================================ */
ir_node_t *ir_make_word(const char *name) {
    ir_node_t *n = ir_node_new(IR_WORD);
    snprintf(n->sval, IR_MAX_STR, "%s", name);
    return n;
}
ir_node_t *ir_make_end_word(void)        { return ir_node_new(IR_END_WORD); }
ir_node_t *ir_make_return(void)          { return ir_node_new(IR_RETURN); }
ir_node_t *ir_make_code_block(void)      { return ir_node_new(IR_CODE_BLOCK); }
ir_node_t *ir_make_end_code(void)        { return ir_node_new(IR_END_CODE); }
ir_node_t *ir_make_simple(ir_opcode_t op){ return ir_node_new(op); }

ir_node_t *ir_make_push_lit(int32_t val) {
    ir_node_t *n = ir_node_new(IR_PUSH_LIT);
    n->ival = val;
    return n;
}
ir_node_t *ir_make_prim(const char *name) {
    ir_node_t *n = ir_node_new(IR_PRIM);
    snprintf(n->sval, IR_MAX_STR, "%s", name);
    return n;
}
ir_node_t *ir_make_call(const char *name) {
    ir_node_t *n = ir_node_new(IR_CALL);
    snprintf(n->sval, IR_MAX_STR, "%s", name);
    return n;
}
ir_node_t *ir_make_label(int num) {
    ir_node_t *n = ir_node_new(IR_LABEL);
    n->ival = num;
    return n;
}
ir_node_t *ir_make_branch(int num) {
    ir_node_t *n = ir_node_new(IR_BRANCH);
    n->ival = num;
    return n;
}
ir_node_t *ir_make_branch_f(int num) {
    ir_node_t *n = ir_node_new(IR_BRANCH_F);
    n->ival = num;
    return n;
}
ir_node_t *ir_make_branch_t(int num) {
    ir_node_t *n = ir_node_new(IR_BRANCH_T);
    n->ival = num;
    return n;
}
ir_node_t *ir_make_const_def(const char *name, int32_t val) {
    ir_node_t *n = ir_node_new(IR_CONST_DEF);
    snprintf(n->sval, IR_MAX_STR, "%s", name);
    n->ival = val;
    return n;
}
ir_node_t *ir_make_var_def(const char *name, int size) {
    ir_node_t *n = ir_node_new(IR_VAR_DEF);
    snprintf(n->sval, IR_MAX_STR, "%s", name);
    n->ival = size;
    return n;
}
ir_node_t *ir_make_value_def(const char *name, int32_t init) {
    ir_node_t *n = ir_node_new(IR_VALUE_DEF);
    snprintf(n->sval, IR_MAX_STR, "%s", name);
    n->ival = init;
    return n;
}
ir_node_t *ir_make_defer_def(const char *name) {
    ir_node_t *n = ir_node_new(IR_DEFER_DEF);
    snprintf(n->sval, IR_MAX_STR, "%s", name);
    return n;
}
ir_node_t *ir_make_is_def(const char *defer, const char *impl) {
    ir_node_t *n = ir_node_new(IR_IS_DEF);
    snprintf(n->sval,  IR_MAX_STR, "%s", defer);
    snprintf(n->sval2, IR_MAX_STR, "%s", impl);
    return n;
}
ir_node_t *ir_make_asm_line(const char *text) {
    ir_node_t *n = ir_node_new(IR_ASM_LINE);
    snprintf(n->sval, IR_MAX_STR, "%s", text);
    return n;
}

/* ============================================================
 * テキスト出力
 * ============================================================ */
const char *ir_opname(ir_opcode_t op) {
    static const char *names[] = {
        "WORD","END-WORD","CONST-DEF","VAR-DEF","VALUE-DEF",
        "DEFER-DEF","IS-DEF","CODE-BLOCK","END-CODE","ASM-LINE",
        "PUSH-LIT","PUSH-STR","PRIM",
        "LABEL","BRANCH","BRANCH-F","BRANCH-T","CALL","RETURN",
        "FETCH-W","STORE-W","FETCH-B","STORE-B",
        "RPUSH","RPOP","RFETCH"
    };
    if (op >= 0 && op < IR_OPCODE_MAX) return names[op];
    return "???";
}

void ir_print(ir_list_t *list, FILE *fp) {
    for (ir_node_t *n = list->head; n; n = n->next) {
        switch (n->op) {
        case IR_WORD:
            fprintf(fp, "\n; --- WORD %s ---\n", n->sval);
            fprintf(fp, "WORD %s\n", n->sval);
            break;
        case IR_END_WORD:
            fprintf(fp, "END-WORD\n");
            break;
        case IR_CONST_DEF:
            fprintf(fp, "CONST-DEF %s %d\n", n->sval, n->ival);
            break;
        case IR_VAR_DEF:
            fprintf(fp, "VAR-DEF %s %d\n", n->sval, n->ival);
            break;
        case IR_VALUE_DEF:
            fprintf(fp, "VALUE-DEF %s %d\n", n->sval, n->ival);
            break;
        case IR_DEFER_DEF:
            fprintf(fp, "DEFER-DEF %s\n", n->sval);
            break;
        case IR_IS_DEF:
            fprintf(fp, "IS-DEF %s %s\n", n->sval, n->sval2);
            break;
        case IR_CODE_BLOCK:
            fprintf(fp, "  CODE-BLOCK\n");
            break;
        case IR_END_CODE:
            fprintf(fp, "  END-CODE\n");
            break;
        case IR_ASM_LINE:
            fprintf(fp, "  ASM-LINE \"%s\"\n", n->sval);
            break;
        case IR_PUSH_LIT:
            fprintf(fp, "  PUSH-LIT %d\n", n->ival);
            break;
        case IR_PUSH_STR:
            fprintf(fp, "  PUSH-STR \"%s\"\n", n->sval);
            break;
        case IR_PRIM:
            fprintf(fp, "  PRIM %s\n", n->sval);
            break;
        case IR_LABEL:
            fprintf(fp, ".L%d:\n", n->ival);
            break;
        case IR_BRANCH:
            fprintf(fp, "  BRANCH .L%d\n", n->ival);
            break;
        case IR_BRANCH_F:
            fprintf(fp, "  BRANCH-F .L%d\n", n->ival);
            break;
        case IR_BRANCH_T:
            fprintf(fp, "  BRANCH-T .L%d\n", n->ival);
            break;
        case IR_CALL:
            fprintf(fp, "  CALL %s\n", n->sval);
            break;
        case IR_RETURN:
            fprintf(fp, "  RETURN\n");
            break;
        case IR_FETCH_W: fprintf(fp, "  FETCH-W\n"); break;
        case IR_STORE_W: fprintf(fp, "  STORE-W\n"); break;
        case IR_FETCH_B: fprintf(fp, "  FETCH-B\n"); break;
        case IR_STORE_B: fprintf(fp, "  STORE-B\n"); break;
        case IR_RPUSH:   fprintf(fp, "  RPUSH\n");   break;
        case IR_RPOP:    fprintf(fp, "  RPOP\n");    break;
        case IR_RFETCH:  fprintf(fp, "  RFETCH\n");  break;
        default:
            fprintf(fp, "  ; unknown op %d\n", n->op);
        }
    }
}
