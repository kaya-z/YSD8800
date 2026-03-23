/* force/force.c
 * Force Forth Cross Compiler v1.1
 * YSD8800 Forthカーネルプロジェクト
 *
 * 使用法:
 *   force [options] input.fs
 *
 * オプション:
 *   --target <tgt>      ターゲット名 (default: ysd8800)
 *   --tgt-file <path>   ターゲット設定ファイル (default: targets/<tgt>.tgt)
 *   --prim-file <path>  プリミティブファイル   (default: targets/<tgt>.prim)
 *   -o <path>           出力ファイル           (default: stdout)
 *   --ir-only           IR出力のみ（バックエンドを実行しない）
 *   --backend-only      バックエンドのみ（.irファイルを入力）
 *   -v                  バージョン情報
 *
 * build:
 *   gcc -std=c99 -O2 -Wall \
 *       frontend/ir.c frontend/lexer.c frontend/parser.c \
 *       backend/codegen.c force.c -o force
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "frontend/ir.h"
#include "frontend/lexer.h"
#include "frontend/parser.h"
#include "backend/codegen.h"

#define FORCE_VERSION "1.00"

/* ============================================================
 * IRファイルの読み込み（--backend-only用）
 * 簡易実装: テキストIRを解析してir_listを生成
 * ============================================================ */
static ir_list_t *load_ir_file(const char *path) {
    FILE *fp = fopen(path, "r");
    if (!fp) { perror(path); return NULL; }

    ir_list_t *ir = ir_list_new();
    char line[512];

    while (fgets(line, sizeof(line), fp)) {
        /* コメント・空行スキップ */
        char *p = line;
        while (*p == ' ' || *p == '\t') p++;
        if (*p == ';' || *p == '\n' || *p == '\0') continue;

        /* 行末改行除去 */
        int len = (int)strlen(p);
        while (len > 0 && (p[len-1]=='\n'||p[len-1]=='\r'||p[len-1]==' '))
            p[--len] = '\0';

        char kw[64], op1[256], op2[256];
        op1[0] = op2[0] = '\0';
        int n = sscanf(p, "%63s %255s %255s", kw, op1, op2);
        if (n < 1) continue;

        /* 大文字化 */
        for (int i = 0; kw[i]; i++)
            kw[i] = (char)((kw[i]>='a'&&kw[i]<='z') ? kw[i]-32 : kw[i]);

        /* ラベル .L0: */
        if (p[0] == '.' && p[1] == 'L') {
            int num = atoi(p+2);
            ir_append(ir, ir_make_label(num));
            continue;
        }

        /* 各IR命令のパース */
        if (strcmp(kw,"WORD")==0)      { ir_append(ir, ir_make_word(op1)); continue; }
        if (strcmp(kw,"END-WORD")==0)  { ir_append(ir, ir_make_end_word()); continue; }
        if (strcmp(kw,"RETURN")==0)    { ir_append(ir, ir_make_return()); continue; }
        if (strcmp(kw,"CALL")==0)      { ir_append(ir, ir_make_call(op1)); continue; }
        if (strcmp(kw,"PRIM")==0)      { ir_append(ir, ir_make_prim(op1)); continue; }
        if (strcmp(kw,"PUSH-LIT")==0)  { ir_append(ir, ir_make_push_lit(atoi(op1))); continue; }
        if (strcmp(kw,"BRANCH")==0)    { ir_append(ir, ir_make_branch(atoi(op1+2))); continue; }
        if (strcmp(kw,"BRANCH-F")==0)  { ir_append(ir, ir_make_branch_f(atoi(op1+2))); continue; }
        if (strcmp(kw,"BRANCH-T")==0)  { ir_append(ir, ir_make_branch_t(atoi(op1+2))); continue; }
        if (strcmp(kw,"CONST-DEF")==0) { ir_append(ir, ir_make_const_def(op1, atoi(op2))); continue; }
        if (strcmp(kw,"VAR-DEF")==0)   { ir_append(ir, ir_make_var_def(op1, atoi(op2))); continue; }
        if (strcmp(kw,"VALUE-DEF")==0) { ir_append(ir, ir_make_value_def(op1, atoi(op2))); continue; }
        if (strcmp(kw,"DEFER-DEF")==0) { ir_append(ir, ir_make_defer_def(op1)); continue; }
        if (strcmp(kw,"IS-DEF")==0)    { ir_append(ir, ir_make_is_def(op1, op2)); continue; }
        if (strcmp(kw,"CODE-BLOCK")==0){ ir_append(ir, ir_make_code_block()); continue; }
        if (strcmp(kw,"END-CODE")==0)  { ir_append(ir, ir_make_end_code()); continue; }
        if (strcmp(kw,"FETCH-W")==0)   { ir_append(ir, ir_make_simple(IR_FETCH_W)); continue; }
        if (strcmp(kw,"STORE-W")==0)   { ir_append(ir, ir_make_simple(IR_STORE_W)); continue; }
        if (strcmp(kw,"FETCH-B")==0)   { ir_append(ir, ir_make_simple(IR_FETCH_B)); continue; }
        if (strcmp(kw,"STORE-B")==0)   { ir_append(ir, ir_make_simple(IR_STORE_B)); continue; }
        if (strcmp(kw,"RPUSH")==0)     { ir_append(ir, ir_make_simple(IR_RPUSH)); continue; }
        if (strcmp(kw,"RPOP")==0)      { ir_append(ir, ir_make_simple(IR_RPOP)); continue; }
        if (strcmp(kw,"RFETCH")==0)    { ir_append(ir, ir_make_simple(IR_RFETCH)); continue; }
        if (strcmp(kw,"ASM-LINE")==0) {
            /* "text" から引用符を除去 */
            char *s = op1;
            if (*s == '"') s++;
            int sl = (int)strlen(s);
            if (sl > 0 && s[sl-1] == '"') s[sl-1] = '\0';
            ir_append(ir, ir_make_asm_line(s)); continue;
        }
    }
    fclose(fp);
    return ir;
}

/* ============================================================
 * usage
 * ============================================================ */
static void usage(const char *prog) {
    fprintf(stderr,
        "Force Forth Cross Compiler v%s\n"
        "Usage: %s [options] input.fs\n"
        "Options:\n"
        "  --target <name>      Target name (default: ysd8800)\n"
        "  --tgt-file <path>    Target config file\n"
        "  --prim-file <path>   Primitives template file\n"
        "  -o <path>            Output file (default: stdout)\n"
        "  --ir-only            Emit IR only (no assembly)\n"
        "  --backend-only       Read .ir file, emit assembly\n"
        "  -v                   Version\n"
        "\nExamples:\n"
        "  %s kernel.fs -o kernel.asm\n"
        "  %s --ir-only kernel.fs -o kernel.ir\n"
        "  %s --backend-only kernel.ir -o kernel.asm\n",
        FORCE_VERSION, prog, prog, prog, prog);
}

/* ============================================================
 * main
 * ============================================================ */
int main(int argc, char **argv) {
    const char *input_path  = NULL;
    const char *output_path = NULL;
    const char *target_name = "ysd8800";
    const char *tgt_file    = NULL;
    const char *prim_file   = NULL;
    int ir_only      = 0;
    int backend_only = 0;

    /* オプション解析 */
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-v") == 0) {
            printf("Force v%s\n", FORCE_VERSION);
            return 0;
        } else if (strcmp(argv[i], "--ir-only") == 0) {
            ir_only = 1;
        } else if (strcmp(argv[i], "--backend-only") == 0) {
            backend_only = 1;
        } else if (strcmp(argv[i], "--target") == 0 && i+1 < argc) {
            target_name = argv[++i];
        } else if (strcmp(argv[i], "--tgt-file") == 0 && i+1 < argc) {
            tgt_file = argv[++i];
        } else if (strcmp(argv[i], "--prim-file") == 0 && i+1 < argc) {
            prim_file = argv[++i];
        } else if (strcmp(argv[i], "-o") == 0 && i+1 < argc) {
            output_path = argv[++i];
        } else if (argv[i][0] != '-') {
            input_path = argv[i];
        } else {
            fprintf(stderr, "unknown option: %s\n", argv[i]);
            usage(argv[0]);
            return 1;
        }
    }

    if (!input_path) { usage(argv[0]); return 1; }

    /* デフォルトのターゲットファイルパスを生成 */
    char tgt_buf[256], prim_buf[256];
    if (!tgt_file) {
        /* 実行ファイルのディレクトリ基準で targets/ を探す */
        snprintf(tgt_buf,  sizeof(tgt_buf),
                 "targets/%s.tgt", target_name);
        tgt_file = tgt_buf;
    }
    if (!prim_file) {
        snprintf(prim_buf, sizeof(prim_buf),
                 "targets/%s.prim", target_name);
        prim_file = prim_buf;
    }

    /* 出力先 */
    FILE *out = stdout;
    if (output_path) {
        out = fopen(output_path, "w");
        if (!out) { perror(output_path); return 1; }
    }

    /* ============ バックエンドのみモード ============ */
    if (backend_only) {
        ir_list_t *ir = load_ir_file(input_path);
        if (!ir) return 1;

        codegen_t *cg = codegen_new(tgt_file, prim_file, out);
        int err = codegen_emit(cg, ir);
        codegen_free(cg);
        ir_list_free(ir);
        if (output_path) fclose(out);
        fprintf(stderr, "force: backend %s -> %s  errors=%d\n",
                input_path, output_path ? output_path : "(stdout)", err);
        return err ? 1 : 0;
    }

    /* ============ フロントエンド ============ */
    FILE *fp = fopen(input_path, "r");
    if (!fp) { perror(input_path); return 1; }

    lexer_t  *lex    = lexer_new(fp, input_path);
    parser_t *parser = parser_new(lex);
    ir_list_t *ir    = parser_parse(parser);
    int fe_errors    = parser_errors(parser);

    if (fe_errors > 0) {
        fprintf(stderr, "force: %d frontend error(s)\n", fe_errors);
    }

    /* ============ IR出力のみモード ============ */
    if (ir_only) {
        ir_print(ir, out);
        fprintf(stderr, "force: frontend %s -> IR  errors=%d  nodes=%d\n",
                input_path, fe_errors, ir->count);
        parser_free(parser);
        lexer_free(lex);
        fclose(fp);
        ir_list_free(ir);
        if (output_path) fclose(out);
        return fe_errors ? 1 : 0;
    }

    /* ============ バックエンド ============ */
    codegen_t *cg = codegen_new(tgt_file, prim_file, out);
    int be_errors = codegen_emit(cg, ir);

    int total_errors = fe_errors + be_errors;
    fprintf(stderr, "force: %s -> %s  errors=%d  (fe=%d be=%d)\n",
            input_path,
            output_path ? output_path : "(stdout)",
            total_errors, fe_errors, be_errors);

    codegen_free(cg);
    parser_free(parser);
    lexer_free(lex);
    fclose(fp);
    ir_list_free(ir);
    if (output_path) fclose(out);

    return total_errors ? 1 : 0;
}
