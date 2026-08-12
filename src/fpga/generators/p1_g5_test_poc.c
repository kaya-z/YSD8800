/* p1_g5_test_poc.c  v1.0  (2026-07-03)
 * scc23 v2.03 P1（スタックラウンドトリップ除去）のガードG1〜G5の単体検証ハーネス。
 * poc本体(scc23_v2_03_poc.c)からP1判定ロジックとP1走査ブロックを忠実に複製し、
 * 人工命令列で各ガードの発動/非発動を確認する（V2c/V3(CONT-1)の実証）。
 * ※poc本体は非改変（KY38）。本ファイルは検証専用。
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ---- poc本体 L537 から忠実複製 ---- */
static const char *ph_skipws(const char *s){ while(*s==' '||*s=='\t')s++; return s; }

/* ---- poc本体 P1ヘルパ(p1_is_line/p1_next_reads_ZN)から忠実複製 ---- */
static int p1_is_line(const char *s, const char *want){
    return strcmp(ph_skipws(s), want) == 0;
}
static int p1_next_reads_ZN(const char *s){
    const char *p = ph_skipws(s);
    if (p[0]=='B' && (strncmp(p+1,"EQ",2)==0 || strncmp(p+1,"NE",2)==0
                   || strncmp(p+1,"LT",2)==0 || strncmp(p+1,"GE",2)==0)) return 1;
    return 0;
}

/* ---- poc本体 peephole_pass内 P1走査ブロックを関数化して忠実複製 ----
 * g_insbuf[0..n) を書き換え、置換件数を返す。走査ロジックはpoc本体と同一。 */
static int p1_pass(char **buf, int *pn){
    int n = *pn;
    int w = 0, r = 0, replaced = 0;
    while (r < n) {
        if (r + 3 < n
            && p1_is_line(buf[r],   "SUBI SP, #2")
            && p1_is_line(buf[r+1], "STW  A, [SP]")
            && p1_is_line(buf[r+2], "LDW  B, [SP]")
            && p1_is_line(buf[r+3], "ADDI SP, #2")
            && !(r + 4 < n && p1_next_reads_ZN(buf[r+4]))) {
            char *rep = strdup("    MOV  B, A");
            if (rep) {
                free(buf[r]); free(buf[r+1]); free(buf[r+2]); free(buf[r+3]);
                buf[w++] = rep; r += 4; replaced++;
                continue;
            }
        }
        buf[w++] = buf[r]; r += 1;
    }
    *pn = w;
    return replaced;
}

/* テスト補助: 文字列配列からg_insbuf相当を作る */
static int build(char **dst, const char **src, int n){
    for (int i=0;i<n;i++) dst[i]=strdup(src[i]);
    return n;
}
static void dump(const char *tag, char **buf, int n){
    printf("  [%s] 結果%d行:\n", tag, n);
    for (int i=0;i<n;i++) printf("      %s\n", buf[i]);
}
static void freebuf(char **buf, int n){ for(int i=0;i<n;i++) free(buf[i]); }

int main(void){
    int pass=0, fail=0;
    char *buf[64];

    /* --- T1: 単純窓（直後が非分岐）→ 置換1件（G1〜G4成立・G5非該当）--- */
    {
        const char *src[] = {
            "    SUBI SP, #2","    STW  A, [SP]","    LDW  B, [SP]","    ADDI SP, #2",
            "    LDW  A, #5"
        };
        int n=build(buf,src,5); int rep=p1_pass(buf,&n);
        int ok = (rep==1 && n==2 && p1_is_line(buf[0],"MOV  B, A") && p1_is_line(buf[1],"LDW  A, #5"));
        printf("T1 単純窓(直後 LDW A,#5): 置換=%d 期待=1 -> %s\n", rep, ok?"PASS":"FAIL");
        if(!ok) dump("T1",buf,n);
        ok?pass++:fail++; freebuf(buf,n);
    }

    /* --- T2【G5発動】: 窓直後が BEQ → 非置換 --- */
    {
        const char *src[] = {
            "    SUBI SP, #2","    STW  A, [SP]","    LDW  B, [SP]","    ADDI SP, #2",
            "    BEQ  _L_0001"
        };
        int n=build(buf,src,5); int rep=p1_pass(buf,&n);
        int ok = (rep==0 && n==5);  /* G5で非置換・5行のまま */
        printf("T2 G5発動(直後 BEQ):    置換=%d 期待=0 -> %s\n", rep, ok?"PASS":"FAIL");
        if(!ok) dump("T2",buf,n);
        ok?pass++:fail++; freebuf(buf,n);
    }

    /* --- T2b/T2c/T2d【G5発動】: BNE/BLT/BGE 各々 --- */
    {
        const char *brs[] = {"    BNE  _L_1","    BLT  _L_1","    BGE  _L_1"};
        const char *nm[] = {"BNE","BLT","BGE"};
        for(int k=0;k<3;k++){
            const char *src[] = {
                "    SUBI SP, #2","    STW  A, [SP]","    LDW  B, [SP]","    ADDI SP, #2", brs[k]
            };
            int n=build(buf,src,5); int rep=p1_pass(buf,&n);
            int ok=(rep==0 && n==5);
            printf("T2%c G5発動(直後 %s):    置換=%d 期待=0 -> %s\n", 'b'+k, nm[k], rep, ok?"PASS":"FAIL");
            ok?pass++:fail++; freebuf(buf,n);
        }
    }

    /* --- T3【G5非該当】: 窓直後が JMP → 置換する（JMPはZ/N読まない）--- */
    {
        const char *src[] = {
            "    SUBI SP, #2","    STW  A, [SP]","    LDW  B, [SP]","    ADDI SP, #2",
            "    JMP  _L_0002"
        };
        int n=build(buf,src,5); int rep=p1_pass(buf,&n);
        int ok=(rep==1 && n==2 && p1_is_line(buf[0],"MOV  B, A"));
        printf("T3 G5非該当(直後 JMP):  置換=%d 期待=1 -> %s\n", rep, ok?"PASS":"FAIL");
        if(!ok) dump("T3",buf,n);
        ok?pass++:fail++; freebuf(buf,n);
    }

    /* --- T4【G3破れ】: LDW が A（B でない）→ 非置換 --- */
    {
        const char *src[] = {
            "    SUBI SP, #2","    STW  A, [SP]","    LDW  A, [SP]","    ADDI SP, #2",
            "    LDW  A, #5"
        };
        int n=build(buf,src,5); int rep=p1_pass(buf,&n);
        int ok=(rep==0 && n==5);
        printf("T4 G3破れ(LDW A,[SP]):  置換=%d 期待=0 -> %s\n", rep, ok?"PASS":"FAIL");
        ok?pass++:fail++; freebuf(buf,n);
    }

    /* --- T5【G4破れ】: [SP+2] オフセット付き → 非置換 --- */
    {
        const char *src[] = {
            "    SUBI SP, #2","    STW  A, [SP+2]","    LDW  B, [SP]","    ADDI SP, #2",
            "    LDW  A, #5"
        };
        int n=build(buf,src,5); int rep=p1_pass(buf,&n);
        int ok=(rep==0 && n==5);
        printf("T5 G4破れ([SP+2]):      置換=%d 期待=0 -> %s\n", rep, ok?"PASS":"FAIL");
        ok?pass++:fail++; freebuf(buf,n);
    }

    /* --- T6【G1破れ】: 窓の間にラベルが挟まる → 非置換 --- */
    {
        const char *src[] = {
            "    SUBI SP, #2","    STW  A, [SP]","_L_0003:","    LDW  B, [SP]","    ADDI SP, #2"
        };
        int n=build(buf,src,5); int rep=p1_pass(buf,&n);
        int ok=(rep==0 && n==5);
        printf("T6 G1破れ(窓内ラベル):  置換=%d 期待=0 -> %s\n", rep, ok?"PASS":"FAIL");
        ok?pass++:fail++; freebuf(buf,n);
    }

    /* --- T7【V2c 連続窓】: 窓が2連続 → 両方畳込み2件・SP収支不変 --- */
    {
        const char *src[] = {
            "    SUBI SP, #2","    STW  A, [SP]","    LDW  B, [SP]","    ADDI SP, #2",
            "    SUBI SP, #2","    STW  A, [SP]","    LDW  B, [SP]","    ADDI SP, #2",
            "    RET"
        };
        int n=build(buf,src,9); int rep=p1_pass(buf,&n);
        int ok=(rep==2 && n==3 && p1_is_line(buf[0],"MOV  B, A")
                && p1_is_line(buf[1],"MOV  B, A") && p1_is_line(buf[2],"RET"));
        printf("T7 V2c連続窓×2:         置換=%d 期待=2 -> %s\n", rep, ok?"PASS":"FAIL");
        if(!ok) dump("T7",buf,n);
        ok?pass++:fail++; freebuf(buf,n);
    }

    /* --- T8【CONT-1境界】: 窓が配列末尾に密着（直後命令なし）→ G5判定は素通し置換 --- */
    {
        const char *src[] = {
            "    SUBI SP, #2","    STW  A, [SP]","    LDW  B, [SP]","    ADDI SP, #2"
        };
        int n=build(buf,src,4); int rep=p1_pass(buf,&n);
        int ok=(rep==1 && n==1 && p1_is_line(buf[0],"MOV  B, A"));
        printf("T8 末尾密着(直後なし):  置換=%d 期待=1 -> %s\n", rep, ok?"PASS":"FAIL");
        if(!ok) dump("T8",buf,n);
        ok?pass++:fail++; freebuf(buf,n);
    }

    /* --- T9【CONT-1】: 連続窓の2つ目直後がBEQ → 1つ目は置換・2つ目は非置換 --- */
    {
        const char *src[] = {
            "    SUBI SP, #2","    STW  A, [SP]","    LDW  B, [SP]","    ADDI SP, #2",
            "    SUBI SP, #2","    STW  A, [SP]","    LDW  B, [SP]","    ADDI SP, #2",
            "    BEQ  _L_9"
        };
        int n=build(buf,src,9); int rep=p1_pass(buf,&n);
        /* 1つ目窓: 直後は2つ目窓のSUBI（非分岐）→置換。2つ目窓: 直後BEQ→G5非置換。 */
        int ok=(rep==1 && p1_is_line(buf[0],"MOV  B, A"));
        printf("T9 CONT-1(2窓目直後BEQ):置換=%d 期待=1 -> %s\n", rep, ok?"PASS":"FAIL");
        if(!ok) dump("T9",buf,n);
        ok?pass++:fail++; freebuf(buf,n);
    }

    printf("\n==== P1 ガード単体検証: PASS=%d FAIL=%d ====\n", pass, fail);
    return fail?1:0;
}
