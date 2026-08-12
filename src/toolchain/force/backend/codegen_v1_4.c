/* force/backend/codegen.c
 * Force Forth Cross Compiler v1.4
 * バックエンド: IR → アセンブラ変換実装
 *
 * v1.0: 初版
 * v1.3: ISA2.3 v2.2.1メモリマップ対応
 *       Forceランタイムワーク変数をDictionary領域($E060)から
 *       RAM固定領域($4232-$4236)に移動
 *       (カーネルワーク変数$4200-$4230の直後に配置)
 * v1.4: VARIABLE/VALUE/DEFER のデータ部とコード部を分離出力 (2026-05-23)
 *       【背景】従来は IR_VAR_DEF で「.org DATA-START → DW 0 → getterコード」
 *       を直書きしており、複数 VARIABLE 間で getter コードが次の VARIABLE の
 *       .org 後退で上書きされる重大バグがあった。getter は $5100〜 の通常
 *       コード領域に流し配置するよう変更し、.org 後退は VAR 部の 2B 区切り
 *       のみとなった。これにより hasm23 v1.02 で導入された W001 警告も
 *       VARIABLE 由来の重ね書きを発生させない。
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include "codegen.h"

/* ============================================================
 * ターゲット設定ファイル読み込み
 * 書式: KEY value  （# コメント）
 * ============================================================ */
int target_load(target_t *tgt, const char *path) {
    FILE *fp = fopen(path, "r");
    if (!fp) { perror(path); return -1; }

    /* デフォルト値 */
    strncpy(tgt->hex_prefix,   "$",          TGT_STR_MAX-1);
    strncpy(tgt->label_prefix, "WORD_",      TGT_STR_MAX-1);
    strncpy(tgt->thread_model, "subroutine", TGT_STR_MAX-1);
    strncpy(tgt->defer_model,  "vector",     TGT_STR_MAX-1);
    strncpy(tgt->code_start,   "$0020",      TGT_STR_MAX-1);
    strncpy(tgt->data_start,   "$E200",      TGT_STR_MAX-1);
    tgt->cell_size     = 2;
    tgt->code_auto_ret = 0;

    char line[256];
    while (fgets(line, sizeof(line), fp)) {
        /* コメント・空行スキップ */
        char *p = line;
        while (*p == ' ' || *p == '\t') p++;
        if (*p == '#' || *p == '\n' || *p == '\0') continue;

        char key[64], val[128];
        if (sscanf(p, "%63s %127s", key, val) != 2) continue;

        /* # 以降を除去 */
        char *comment = strchr(val, '#');
        if (comment) *comment = '\0';
        /* 末尾空白除去 */
        int vlen = (int)strlen(val);
        while (vlen > 0 && (val[vlen-1]==' '||val[vlen-1]=='\t'||val[vlen-1]=='\n'))
            val[--vlen] = '\0';

#define SET(field, k) if(strcasecmp(key, k)==0) strncpy(tgt->field, val, TGT_STR_MAX-1)
        SET(arch,         "ARCH");
        SET(assembler,    "ASSEMBLER");
        SET(code_start,   "CODE-START");
        SET(data_start,   "DATA-START");
        SET(ds_reg,       "DS-REG");
        SET(rs_reg,       "RS-REG");
        SET(tos_reg,      "TOS-REG");
        SET(aux_reg,      "AUX-REG");
        SET(thread_model, "THREAD-MODEL");
        SET(hex_prefix,   "HEX-PREFIX");
        SET(defer_model,  "DEFER-MODEL");
        SET(label_prefix, "LABEL-PREFIX");
#undef SET
        if (strcasecmp(key, "CELL-SIZE") == 0)
            tgt->cell_size = atoi(val);
        if (strcasecmp(key, "CODE-AUTO-RET") == 0)
            tgt->code_auto_ret = (strcasecmp(val,"yes")==0) ? 1 : 0;
    }
    fclose(fp);
    return 0;
}

/* ============================================================
 * プリミティブテンプレートファイル読み込み
 * 書式:
 *   PRIM name
 *   <アセンブラ行...>
 *   END-PRIM
 * テンプレート内の {DSP} {TOS} {AUX} をレジスタ名に展開
 * ============================================================ */
static void expand_template(const char *src, char *dst, int dstsz,
                            const target_t *tgt) {
    int si = 0, di = 0;
    while (src[si] && di < dstsz-1) {
        if (src[si] == '{') {
            /* {XXX} → レジスタ名に展開 */
            char var[32];
            int vi = 0;
            si++;
            while (src[si] && src[si] != '}' && vi < 31)
                var[vi++] = src[si++];
            var[vi] = '\0';
            if (src[si] == '}') si++;

            const char *repl = NULL;
            if (strcmp(var,"DSP")==0) repl = tgt->ds_reg;
            else if (strcmp(var,"TOS")==0) repl = tgt->tos_reg;
            else if (strcmp(var,"AUX")==0) repl = tgt->aux_reg;
            else if (strcmp(var,"RS")==0)  repl = tgt->rs_reg;

            if (repl) {
                int rlen = (int)strlen(repl);
                if (di + rlen < dstsz-1) {
                    memcpy(dst+di, repl, rlen);
                    di += rlen;
                }
            }
        } else {
            dst[di++] = src[si++];
        }
    }
    dst[di] = '\0';
}

int prim_load(prim_table_t *ptbl, const char *path, const target_t *tgt) {
    FILE *fp = fopen(path, "r");
    if (!fp) { perror(path); return -1; }

    ptbl->count = 0;
    prim_template_t *cur = NULL;

    char line[256];
    while (fgets(line, sizeof(line), fp)) {
        /* コメント・空行 */
        char *p = line;
        while (*p == ' ' || *p == '\t') p++;
        if (*p == '#' || *p == '\n' || *p == '\0') continue;

        /* 行末改行除去 */
        int len = (int)strlen(p);
        while (len > 0 && (p[len-1]=='\n'||p[len-1]=='\r')) p[--len] = '\0';

        char kw[32];
        sscanf(p, "%31s", kw);

        if (strcasecmp(kw, "PRIM") == 0) {
            if (ptbl->count >= PRIM_COUNT_MAX) {
                fprintf(stderr, "too many PRIMs\n"); continue;
            }
            cur = &ptbl->prims[ptbl->count++];
            sscanf(p + 5, "%31s", cur->name);
            cur->body[0] = '\0';
            /* 名前を大文字正規化 */
            for (int i = 0; cur->name[i]; i++)
                cur->name[i] = toupper((unsigned char)cur->name[i]);
            continue;
        }
        if (strcasecmp(kw, "END-PRIM") == 0) {
            cur = NULL;
            continue;
        }
        if (cur) {
            /* テンプレート変数を展開してbodyに追記 */
            char expanded[512];
            expand_template(p, expanded, sizeof(expanded), tgt);
            strncat(cur->body, expanded, PRIM_BODY_MAX - strlen(cur->body) - 1);
            strncat(cur->body, "\n",    PRIM_BODY_MAX - strlen(cur->body) - 1);
        }
    }
    fclose(fp);
    return 0;
}

/* PRIMテンプレートを名前で検索 */
static prim_template_t *find_prim(prim_table_t *ptbl, const char *name) {
    char up[PRIM_NAME_MAX];
    int i;
    for (i = 0; name[i] && i < PRIM_NAME_MAX-1; i++)
        up[i] = toupper((unsigned char)name[i]);
    up[i] = '\0';

    for (int j = 0; j < ptbl->count; j++)
        if (strcmp(ptbl->prims[j].name, up) == 0)
            return &ptbl->prims[j];
    return NULL;
}

/* ============================================================
 * コードジェネレータ
 * ============================================================ */
codegen_t *codegen_new(const char *tgt_path, const char *prim_path, FILE *out) {
    codegen_t *cg = calloc(1, sizeof(codegen_t));
    if (!cg) { perror("codegen_new"); exit(1); }
    cg->out = out;
    /* v1.4: データ部・コード部の分離バッファ */
    cg->data_section = tmpfile();
    cg->code_section = tmpfile();
    if (!cg->data_section || !cg->code_section) {
        perror("codegen_new: tmpfile");
        exit(1);
    }

    if (target_load(&cg->tgt, tgt_path) != 0) {
        fprintf(stderr, "failed to load target: %s\n", tgt_path);
        cg->errors++;
    }
    if (prim_load(&cg->ptbl, prim_path, &cg->tgt) != 0) {
        fprintf(stderr, "failed to load primitives: %s\n", prim_path);
        cg->errors++;
    }

    /* データ領域の開始アドレスをパース */
    const char *ds = cg->tgt.data_start;
    if (ds[0] == '$') cg->data_org = (int)strtol(ds+1, NULL, 16);
    else              cg->data_org = (int)strtol(ds, NULL, 0);

    return cg;
}

void codegen_free(codegen_t *cg) {
    if (cg->data_section) fclose(cg->data_section);
    if (cg->code_section) fclose(cg->code_section);
    free(cg);
}

/* ============================================================
 * ヘルパー: 数値 → アセンブラ即値文字列
 * ============================================================ */
static void fmt_num(codegen_t *cg, int32_t val, char *buf, int bufsz) {
    if (val >= 0 && val <= 9)
        snprintf(buf, bufsz, "#%d", (int)val);
    else
        snprintf(buf, bufsz, "#%s%04X", cg->tgt.hex_prefix, (unsigned)(val & 0xFFFF));
}

/* ============================================================
 * アセンブラ出力: IRノード1つ分
 * v1.4: 通常コードは cg->code_section に出力。VAR/VALUE/DEFER のデータ部は
 *       cg->data_section に分離出力する。
 * ============================================================ */
static void emit_node(codegen_t *cg, ir_node_t *n) {
    FILE *out  = cg->code_section;   /* v1.4: コード部はこちらへ */
    FILE *dout = cg->data_section;   /* v1.4: データ部はこちらへ */
    const char *dsp = cg->tgt.ds_reg;
    const char *tos = cg->tgt.tos_reg;
    const char *aux = cg->tgt.aux_reg;
    const char *rs  = cg->tgt.rs_reg;
    const char *pfx = cg->tgt.label_prefix;
    const char *hpfx = cg->tgt.hex_prefix;
    char num[32];

    switch (n->op) {
    case IR_WORD:
        fprintf(out, "\n; --- %s ---\n", n->sval);
        fprintf(out, "%s%s:\n", pfx, n->sval);
        break;

    case IR_END_WORD:
        break;

    case IR_CONST_DEF:
        fprintf(out, "%-20s EQU %s%04X\n", n->sval, hpfx,
                (unsigned)(n->ival & 0xFFFF));
        break;

    case IR_VAR_DEF: {
        /* v1.4: VARIABLEは2つの部分を生成
         * 1. データ領域（DATA-START側に .org でデータ位置を固定）→ data_section
         * 2. ワード定義（アドレスをpushするgetterルーチン）→ code_section
         * 旧仕様(v1.3まで)では両方を同一ファイル out に連続出力していたため、
         * 次の VARIABLE の .org 後退で getter コードが上書きされる重大バグが
         * あった。本版でデータ部とコード部を分離。 */
        int addr = cg->data_org;
        cg->data_org += n->ival;

        /* データ部: data_section へ */
        fprintf(dout, "\n; VARIABLE %s (data)\n", n->sval);
        fprintf(dout, "    .org %s%04X\n", hpfx, (unsigned)addr);
        fprintf(dout, "VAR_%s:\n", n->sval);
        fprintf(dout, "    DW   0\n");

        /* コード部 (getter): code_section へ。
         * .org は付けない (CODE 領域の自然な順次配置) */
        fprintf(out, "\n; VARIABLE %s (getter)\n", n->sval);
        fprintf(out, "%s%s:\n", pfx, n->sval);
        fmt_num(cg, addr, num, sizeof(num));
        fprintf(out, "    LDW  %s, %s\n", tos, num);
        fprintf(out, "    SUBI %s, #2\n", dsp);
        fprintf(out, "    STW  %s, [%s]\n", tos, dsp);
        fprintf(out, "    RET\n");
        break;
    }

    case IR_VALUE_DEF: {
        /* v1.4: VARIABLE と同様にデータ部とコード部を分離 */
        int addr = cg->data_org;
        cg->data_org += cg->tgt.cell_size;
        fmt_num(cg, n->ival, num, sizeof(num));

        /* データ部: data_section へ */
        fprintf(dout, "\n; VALUE %s (data)\n", n->sval);
        fprintf(dout, "    .org %s%04X\n", hpfx, (unsigned)addr);
        fprintf(dout, "VAL_%s:\n", n->sval);
        fprintf(dout, "    DW   %s%04X\n", hpfx, (unsigned)(n->ival & 0xFFFF));

        /* コード部: code_section へ */
        fprintf(out, "\n; VALUE %s (getter)\n", n->sval);
        fprintf(out, "%s%s:\n", pfx, n->sval);
        fmt_num(cg, addr, num, sizeof(num));
        fprintf(out, "    LDW  %s, %s\n", tos, num);
        fprintf(out, "    SUBI %s, #2\n", dsp);
        fprintf(out, "    STW  %s, [%s]\n", tos, dsp);
        fprintf(out, "    RET\n");
        break;
    }

    case IR_DEFER_DEF: {
        /* v1.4: DEFERのデータ部(ベクタ)とコード部(間接呼出)を分離 */
        int addr = cg->data_org;
        cg->data_org += cg->tgt.cell_size;

        /* データ部 (ベクタ): data_section へ */
        fprintf(dout, "\n; DEFER %s (vector)\n", n->sval);
        fprintf(dout, "    .org %s%04X\n", hpfx, (unsigned)addr);
        fprintf(dout, "VEC_%s:\n", n->sval);
        fprintf(dout, "    DW   DEFER_DEFAULT\n");

        /* コード部 (ワード本体): code_section へ */
        fprintf(out, "\n; DEFER %s (dispatch)\n", n->sval);
        fprintf(out, "%s%s:\n", pfx, n->sval);
        fmt_num(cg, addr, num, sizeof(num));
        fprintf(out, "    LDW  %s, [%s%04X]\n", tos, hpfx, (unsigned)addr);
        fprintf(out, "    ; indirect call via vector\n");
        fprintf(out, "    ; TODO: JSR [%s]  (要アーキテクチャ対応)\n", tos);
        /* YSD8800ではSTW+JSRのシーケンスが必要（後で改良）*/
        fprintf(out, "    STW  %s, [_DEFER_TMP]\n", tos);
        fprintf(out, "    JSR  _DEFER_DISPATCH\n");
        fprintf(out, "    RET\n");
        break;
    }

    case IR_IS_DEF:
        fprintf(out, "\n; IS %s <- %s\n", n->sval, n->sval2);
        /* hasm22: ラベルアドレスの即値参照は #$LABEL 形式 */
        fprintf(out, "    LDW  %s, #$%s%s\n", tos, pfx, n->sval2);
        fprintf(out, "    STW  %s, [VEC_%s]\n", tos, n->sval);
        break;

    case IR_CODE_BLOCK:
        /* CODE本体は ASM_LINE で出力される */
        break;

    case IR_END_CODE:
        if (cg->tgt.code_auto_ret)
            fprintf(out, "    RET\n");
        break;

    case IR_ASM_LINE:
        fprintf(out, "%s\n", n->sval);
        break;

    case IR_PUSH_LIT:
        fmt_num(cg, n->ival, num, sizeof(num));
        fprintf(out, "    LDW  %s, %s\n", tos, num);
        fprintf(out, "    SUBI %s, #2\n", dsp);
        fprintf(out, "    STW  %s, [%s]\n", tos, dsp);
        break;

    case IR_PUSH_STR:
        /* 文字列データを生成してアドレス+長さをpush */
        fprintf(out, "    ; PUSH-STR \"%s\"\n", n->sval);
        fprintf(out, "    ; (文字列データは別途 .org で配置)\n");
        /* TODO: 文字列プール管理 */
        break;

    case IR_PRIM: {
        prim_template_t *pt = find_prim(&cg->ptbl, n->sval);
        if (pt) {
            static int prim_seq = 0;
            prim_seq++;
            fprintf(out, "    ; PRIM %s\n", n->sval);
            /* ローカルラベルをユニーク化: _xxx → _xxx_N */
            const char *body = pt->body;
            char line[512];
            int bi = 0;
            while (*body) {
                char c = *body++;
                if (c == '\n') {
                    line[bi] = '\0';
                    /* ラベル定義行 (先頭が_でコロンで終わる) */
                    char outline[512];
                    if (line[0] == '_') {
                        /* ラベル定義: _xxx: → _xxx_N: */
                        int li = strlen(line);
                        if (li > 0 && line[li-1] == ':') {
                            line[li-1] = '\0';
                            snprintf(outline, sizeof(outline), "%s_%d:\n", line, prim_seq);
                        } else {
                            snprintf(outline, sizeof(outline), "%s\n", line);
                        }
                    } else {
                        /* ラベル参照を置換: _xxxで始まる語を_xxx_Nに */
                        /* 簡易実装: 行内の_で始まる単語を探して番号付加 */
                        char *p2 = line;
                        int oi = 0;
                        while (*p2 && oi < 500) {
                            if (*p2 == '_' && (p2 == line || !isalnum((unsigned char)*(p2-1)))) {
                                /* _で始まるラベル参照 */
                                int li2 = 0;
                                char lbuf[64];
                                while (*p2 && (isalnum((unsigned char)*p2) || *p2 == '_') && li2 < 63)
                                    lbuf[li2++] = *p2++;
                                lbuf[li2] = '\0';
                                /* _FORCE_ / _fmul_ などのランタイムラベルはユニーク化しない */
                                if (strncmp(lbuf, "_FORCE_", 7) == 0 ||
                                    strncmp(lbuf, "_fmul",  5) == 0 ||
                                    strncmp(lbuf, "_DEFER", 6) == 0) {
                                    int written = snprintf(outline+oi, 500-oi, "%s", lbuf);
                                    oi += written;
                                } else {
                                    int written = snprintf(outline+oi, 500-oi, "%s_%d", lbuf, prim_seq);
                                    oi += written;
                                }

                            } else {
                                outline[oi++] = *p2++;
                            }
                        }
                        outline[oi] = '\0';
                        strncat(outline, "\n", sizeof(outline)-strlen(outline)-1);
                    }
                    fprintf(out, "%s", outline);
                    bi = 0;
                } else {
                    if (bi < 510) line[bi++] = c;
                }
            }
        } else {
            fprintf(out, "    ; *** PRIM %s: template not found ***\n", n->sval);
            fprintf(out, "    JSR  PRIM_%s\n", n->sval);
            cg->errors++;
        }
        break;
    }

    case IR_LABEL:
        fprintf(out, ".L%d:\n", n->ival);
        break;

    case IR_BRANCH:
        fprintf(out, "    JMP  .L%d\n", n->ival);
        break;

    case IR_BRANCH_F:
        /* TOSを取り出して0なら分岐 */
        fprintf(out, "    LDW  %s, [%s]\n", tos, dsp);
        fprintf(out, "    ADDI %s, #2\n", dsp);
        fprintf(out, "    CMPI %s, #0\n", tos);
        fprintf(out, "    BEQ  .L%d\n", n->ival);
        break;

    case IR_BRANCH_T:
        fprintf(out, "    LDW  %s, [%s]\n", tos, dsp);
        fprintf(out, "    ADDI %s, #2\n", dsp);
        fprintf(out, "    CMPI %s, #0\n", tos);
        fprintf(out, "    BNE  .L%d\n", n->ival);
        break;

    case IR_CALL:
        fprintf(out, "    JSR  %s%s\n", pfx, n->sval);
        break;

    case IR_RETURN:
        fprintf(out, "    RET\n");
        break;

    case IR_FETCH_W:
        fprintf(out, "    LDW  %s, [%s]\n", tos, dsp);
        fprintf(out, "    LDW  %s, [%s]\n", tos, tos);
        fprintf(out, "    STW  %s, [%s]\n", tos, dsp);
        break;

    case IR_STORE_W:
        fprintf(out, "    LDW  %s, [%s]\n",    tos, dsp);      /* addr */
        fprintf(out, "    ADDI %s, #2\n",       dsp);
        fprintf(out, "    LDW  %s, [%s]\n",    aux, dsp);      /* val */
        fprintf(out, "    ADDI %s, #2\n",       dsp);
        fprintf(out, "    STW  %s, [%s]\n",    aux, tos);
        break;

    case IR_FETCH_B:
        /* C@ ( addr -- byte )
         * LDB/STB は [X] のみ可。{aux}(=B) をアドレスに使えないため
         * {dsp}(=X) をRSに退避してアドレス→Xで読み出す。
         * ISA2.3対応修正 (v0.6) */
        fprintf(out, "    LDW  %s, [%s]\n",   tos, dsp);      /* A = addr */
        fprintf(out, "    SUBI %s, #2\n",      rs);           /* RS push */
        fprintf(out, "    STW  %s, [%s]\n",   dsp, rs);       /* save DSP */
        fprintf(out, "    MOV  %s, %s\n",      dsp, tos);     /* X = addr */
        fprintf(out, "    LDB  %s, [%s]\n",   tos, dsp);      /* A = mem8[addr] */
        fprintf(out, "    LDW  %s, [%s]\n",   dsp, rs);       /* restore DSP */
        fprintf(out, "    ADDI %s, #2\n",      rs);           /* RS pop */
        fprintf(out, "    STW  %s, [%s]\n",   tos, dsp);      /* TOS = byte */
        break;

    case IR_STORE_B:
        /* C! ( byte addr -- )
         * ISA2.3対応修正 (v0.6) */
        fprintf(out, "    LDW  %s, [%s]\n",   tos, dsp);      /* A = addr */
        fprintf(out, "    ADDI %s, #2\n",      dsp);
        fprintf(out, "    LDW  %s, [%s]\n",   aux, dsp);      /* B = byte */
        fprintf(out, "    ADDI %s, #2\n",      dsp);
        fprintf(out, "    SUBI %s, #2\n",      rs);           /* RS push */
        fprintf(out, "    STW  %s, [%s]\n",   dsp, rs);       /* save DSP */
        fprintf(out, "    MOV  %s, %s\n",      dsp, tos);     /* X = addr */
        fprintf(out, "    STB  %s, [%s]\n",   aux, dsp);      /* mem8[addr] = byte */
        fprintf(out, "    LDW  %s, [%s]\n",   dsp, rs);       /* restore DSP */
        fprintf(out, "    ADDI %s, #2\n",      rs);           /* RS pop */
        break;

    case IR_RPUSH:
        fprintf(out, "    LDW  %s, [%s]\n",   tos, dsp);
        fprintf(out, "    ADDI %s, #2\n",      dsp);
        fprintf(out, "    SUBI %s, #2\n",      rs);
        fprintf(out, "    STW  %s, [%s]\n",   tos, rs);
        break;

    case IR_RPOP:
        fprintf(out, "    LDW  %s, [%s]\n",   tos, rs);
        fprintf(out, "    ADDI %s, #2\n",      rs);
        fprintf(out, "    SUBI %s, #2\n",      dsp);
        fprintf(out, "    STW  %s, [%s]\n",   tos, dsp);
        break;

    case IR_RFETCH:
        fprintf(out, "    LDW  %s, [%s]\n",   tos, rs);
        fprintf(out, "    SUBI %s, #2\n",      dsp);
        fprintf(out, "    STW  %s, [%s]\n",   tos, dsp);
        break;

    default:
        fprintf(out, "    ; unknown IR op %d\n", n->op);
        break;
    }
}

/* ============================================================
 * ヘッダ出力
 * v1.4: 出力先を cg->code_section に変更 (.org CODE-START 以降の本体)
 * ============================================================ */
static void emit_header(codegen_t *cg) {
    FILE *out = cg->code_section;
    fprintf(out, "; Generated by Force Forth Cross Compiler v1.4\n");
    fprintf(out, "; Target: %s  Thread: %s\n",
            cg->tgt.arch, cg->tgt.thread_model);
    fprintf(out, ";\n\n");
    fprintf(out, "    .org %s\n\n", cg->tgt.code_start);

    /* ============================================================ */
    /* ランタイムルーチン (Force自動生成)                           */
    /* ============================================================ */
    const char *dsp2 = cg->tgt.ds_reg;
    const char *tos2 = cg->tgt.tos_reg;
    const char *aux2 = cg->tgt.aux_reg;

    /* 16bit乗算ルーチン ( a b -- a*b ) */
    /* ワーク変数: ISA2.3 RAM領域 $4232-$423C (カーネルワーク変数$4200-$4230の直後) */
    fprintf(out, "; 16bit multiply runtime (uses $4232-$423C as temp)\n");
    fprintf(out, "_FMUL_A  EQU $4232\n");
    fprintf(out, "_FMUL_B  EQU $4234\n");
    fprintf(out, "_FMUL_R  EQU $4236\n");
    fprintf(out, "_FORCE_MUL:\n");
    fprintf(out, "    LDW  %s, [%s]\n",   tos2, dsp2);
    fprintf(out, "    ADDI %s, #2\n",      dsp2);
    fprintf(out, "    STW  %s, [_FMUL_B]\n", tos2);
    fprintf(out, "    LDW  %s, [%s]\n",   tos2, dsp2);
    fprintf(out, "    STW  %s, [_FMUL_A]\n", tos2);
    fprintf(out, "    LDW  %s, #0\n",     tos2);
    fprintf(out, "    STW  %s, [_FMUL_R]\n", tos2);
    fprintf(out, "_fmul_loop:\n");
    fprintf(out, "    LDW  %s, [_FMUL_B]\n", aux2);
    fprintf(out, "    CMPI %s, #0\n",     aux2);
    fprintf(out, "    BEQ  _fmul_done\n");
    fprintf(out, "    ANDI %s, #1\n",     aux2);
    fprintf(out, "    BEQ  _fmul_skip\n");
    fprintf(out, "    LDW  %s, [_FMUL_R]\n", tos2);
    fprintf(out, "    LDW  %s, [_FMUL_A]\n", aux2);
    fprintf(out, "    ADD  %s, %s\n",     tos2, aux2);
    fprintf(out, "    STW  %s, [_FMUL_R]\n", tos2);
    fprintf(out, "_fmul_skip:\n");
    fprintf(out, "    LDW  %s, [_FMUL_A]\n", aux2);
    fprintf(out, "    LDW  %s, #1\n",     tos2);
    fprintf(out, "    SHL  %s, %s\n",     aux2, tos2);
    fprintf(out, "    STW  %s, [_FMUL_A]\n", aux2);
    fprintf(out, "    LDW  %s, [_FMUL_B]\n", aux2);
    fprintf(out, "    SHR  %s, %s\n",     aux2, tos2);
    fprintf(out, "    STW  %s, [_FMUL_B]\n", aux2);
    fprintf(out, "    JMP  _fmul_loop\n");
    fprintf(out, "_fmul_done:\n");
    fprintf(out, "    LDW  %s, [_FMUL_R]\n", tos2);
    fprintf(out, "    STW  %s, [%s]\n",   tos2, dsp2);
    fprintf(out, "    RET\n\n");

    /* DEFERディスパッチヘルパー（YSD8800専用の暫定実装）*/
    fprintf(out, "; DEFER dispatch helper\n");
    fprintf(out, "_DEFER_TMP:\n");
    fprintf(out, "    DW   0\n");
    fprintf(out, "_DEFER_DISPATCH:\n");
    fprintf(out, "    LDW  %s, [_DEFER_TMP]\n", cg->tgt.tos_reg);
    fprintf(out, "    ; indirect jump: stub\n");
    fprintf(out, "    RET\n");
    fprintf(out, "DEFER_DEFAULT:\n");
    fprintf(out, "    RET\n\n");
}

/* ============================================================
 * メイン emit
 * v1.4: 「ヘッダ+コード本体 → データ部」の順で cg->out に出力する。
 *       ・code_section: ヘッダ+ランタイム+全 IR ノード のコード
 *       ・data_section: 全 VAR/VAL/DEFER のデータ部 (.org $C000系)
 *       コード本体の末尾にデータ部の .org $C000 が来ることで、hasm23 は
 *       通常コード領域 → データ領域 の順でアセンブルする。
 * ============================================================ */
static void flush_buffer(FILE *src, FILE *dst) {
    char buf[4096];
    size_t n;
    rewind(src);
    while ((n = fread(buf, 1, sizeof(buf), src)) > 0) {
        fwrite(buf, 1, n, dst);
    }
}

int codegen_emit(codegen_t *cg, ir_list_t *ir) {
    emit_header(cg);
    for (ir_node_t *n = ir->head; n; n = n->next)
        emit_node(cg, n);

    /* v1.4: 最終結合 — まずコード部、続いてデータ部を cg->out へ流す */
    flush_buffer(cg->code_section, cg->out);
    fprintf(cg->out, "\n; ==== Data section (VARIABLE/VALUE/DEFER) ====\n");
    flush_buffer(cg->data_section, cg->out);

    return cg->errors;
}
