/* lnk22.c - YSD8800 ISA2.2 Linker
 * Version: 1.00
 * YSD8800 YUI OS Project
 *
 * 使用法:
 *   lnk22 <script.lnk> [-o output.bin] [--sym output.sym]
 *   lnk22 --version
 *
 * リンカスクリプト書式:
 *   # コメント
 *   OUTPUT  output.bin             出力バイナリ（-oで上書き可）
 *   SYMOUT  output.sym             出力シンボルファイル（省略可）
 *
 *   SECTION name addr file.bin [file.sym]
 *     name: セクション名（任意の識別子）
 *     addr: 配置開始アドレス（$XXXX または 10進数）
 *     file.bin: 配置するバイナリ
 *     file.sym: シンボルテーブル（省略可、あれば addr を加算してマージ）
 *
 *   PATCH addr value               1ワード(2B)パッチ
 *   PATCHB addr value              1バイトパッチ
 *
 * 動作:
 *   1. 各SECTIONのバイナリを addr から配置
 *   2. SECTIONに .sym が指定されていればシンボルを addr 分オフセットしてマージ
 *      ※ hasm22 の .sym は絶対アドレスで出力されるため offset=0 が通常
 *   3. PATCH/PATCHB で任意アドレスに値を書き込む
 *   4. 結合バイナリと .sym を出力
 *
 * v1.00: 初版
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <stdint.h>

#define VERSION      "1.00"
#define TOOL_NAME    "lnk22"
#define MAX_SYMS     8192
#define MEM_SIZE     65536
#define MAX_LINE     512

/* ---- シンボルテーブル ---- */
typedef struct {
    char     name[128];
    uint32_t addr;
} sym_t;

static sym_t  syms[MAX_SYMS];
static int    nsyms = 0;

static void sym_add(const char *name, uint32_t addr) {
    if (nsyms >= MAX_SYMS) {
        fprintf(stderr, TOOL_NAME ": too many symbols\n");
        return;
    }
    /* 重複はスキップ */
    for (int i = 0; i < nsyms; i++)
        if (strcmp(syms[i].name, name) == 0) return;
    strncpy(syms[nsyms].name, name, 127);
    syms[nsyms].name[127] = '\0';
    syms[nsyms].addr = addr & 0xFFFF;
    nsyms++;
}

static int sym_load(const char *path, int offset) {
    FILE *f = fopen(path, "r");
    if (!f) {
        fprintf(stderr, TOOL_NAME ": warning: cannot open sym: %s\n", path);
        return 0;
    }
    char line[256];
    int  count = 0;
    while (fgets(line, sizeof(line), f)) {
        char     name[128];
        uint32_t addr;
        if (sscanf(line, "%x %127s", &addr, name) == 2) {
            sym_add(name, (addr + offset) & 0xFFFF);
            count++;
        }
    }
    fclose(f);
    return count;
}

static void sym_write(const char *path) {
    FILE *f = fopen(path, "w");
    if (!f) { perror(path); return; }
    for (int i = 0; i < nsyms; i++)
        fprintf(f, "%04x %s\n", syms[i].addr & 0xFFFF, syms[i].name);
    fclose(f);
    printf(TOOL_NAME ": %d symbols -> %s\n", nsyms, path);
}

/* ---- メモリバッファ ---- */
static uint8_t  mem[MEM_SIZE];
static uint8_t  used[MEM_SIZE];   /* 書き込み済みフラグ */

/* バイナリを addr から配置 */
static int section_place(const char *path, uint32_t addr) {
    FILE *f = fopen(path, "rb");
    if (!f) {
        fprintf(stderr, TOOL_NAME ": error: cannot open bin: %s\n", path);
        return -1;
    }
    int c, idx = 0;
    while ((c = fgetc(f)) != EOF) {
        uint32_t a = addr + idx;
        if (a >= MEM_SIZE) {
            fprintf(stderr, TOOL_NAME ": error: section overflow at $%04X (%s)\n", a, path);
            fclose(f);
            return -1;
        }
        if (c != 0) {        /* 非ゼロのみ上書き（先行セクションを保護） */
            mem[a]  = (uint8_t)c;
            used[a] = 1;
        }
        idx++;
    }
    fclose(f);
    return idx;
}

/* ---- パーサ補助 ---- */
static char *trim(char *s) {
    while (*s && isspace((unsigned char)*s)) s++;
    char *e = s + strlen(s);
    while (e > s && isspace((unsigned char)*(e-1))) e--;
    *e = '\0';
    return s;
}

/* $XXXX または 10進数をパース */
static int parse_addr(const char *s, uint32_t *out) {
    char *endp;
    if (s[0] == '$') {
        *out = (uint32_t)strtoul(s + 1, &endp, 16);
    } else if (s[0] == '0' && (s[1] == 'x' || s[1] == 'X')) {
        *out = (uint32_t)strtoul(s + 2, &endp, 16);
    } else {
        *out = (uint32_t)strtoul(s, &endp, 10);
        if (*endp != '\0') {
            /* 10進失敗 → 16進で再試行 */
            *out = (uint32_t)strtoul(s, &endp, 16);
        }
    }
    return (*endp == '\0');
}

/* ---- メイン ---- */
int main(int argc, char **argv) {
    const char *script_path = NULL;
    const char *out_bin     = NULL;
    const char *out_sym     = NULL;

    /* 引数解析 */
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--version") == 0 || strcmp(argv[i], "-v") == 0) {
            printf(TOOL_NAME " - YSD8800 ISA2.2 Linker v%s\n", VERSION);
            return 0;
        } else if (strcmp(argv[i], "-o") == 0 && i+1 < argc) {
            out_bin = argv[++i];
        } else if (strcmp(argv[i], "--sym") == 0 && i+1 < argc) {
            out_sym = argv[++i];
        } else if (argv[i][0] != '-') {
            script_path = argv[i];
        } else {
            fprintf(stderr, TOOL_NAME ": unknown option: %s\n", argv[i]);
            return 1;
        }
    }

    if (!script_path) {
        fprintf(stderr,
            "Usage: " TOOL_NAME " <script.lnk> [-o output.bin] [--sym output.sym]\n"
            "       " TOOL_NAME " --version\n");
        return 1;
    }

    /* メモリ初期化 */
    memset(mem,  0, sizeof(mem));
    memset(used, 0, sizeof(used));

    /* リンカスクリプト読み込み */
    FILE *sf = fopen(script_path, "r");
    if (!sf) {
        fprintf(stderr, TOOL_NAME ": error: cannot open script: %s\n", script_path);
        return 1;
    }

    char line[MAX_LINE];
    int  lineno = 0;
    int  errors = 0;
    /* スクリプトから読んだ OUTPUT/SYMOUT をデフォルトとして保存 */
    char script_out_bin[256] = "";
    char script_out_sym[256] = "";

    while (fgets(line, sizeof(line), sf)) {
        lineno++;
        char *s = trim(line);
        if (*s == '#' || *s == '\0') continue;   /* コメント・空行 */

        /* トークン分割（最大5トークン） */
        char *tok[5] = {NULL};
        int  ntok = 0;
        char *p = s;
        while (*p && ntok < 5) {
            while (*p && isspace((unsigned char)*p)) p++;
            if (!*p) break;
            tok[ntok++] = p;
            while (*p && !isspace((unsigned char)*p)) p++;
            if (*p) { *p = '\0'; p++; }
        }
        if (ntok == 0) continue;

        /* 大文字化してキーワード判定 */
        char kw[32];
        strncpy(kw, tok[0], 31); kw[31] = '\0';
        for (int i = 0; kw[i]; i++) kw[i] = toupper((unsigned char)kw[i]);

        /* OUTPUT output.bin */
        if (strcmp(kw, "OUTPUT") == 0) {
            if (ntok < 2) {
                fprintf(stderr, TOOL_NAME ": %s:%d: OUTPUT requires filename\n",
                        script_path, lineno);
                errors++;
                continue;
            }
            strncpy(script_out_bin, tok[1], 255);
            continue;
        }

        /* SYMOUT output.sym */
        if (strcmp(kw, "SYMOUT") == 0) {
            if (ntok < 2) {
                fprintf(stderr, TOOL_NAME ": %s:%d: SYMOUT requires filename\n",
                        script_path, lineno);
                errors++;
                continue;
            }
            strncpy(script_out_sym, tok[1], 255);
            continue;
        }

        /* SECTION name addr file.bin [file.sym] */
        if (strcmp(kw, "SECTION") == 0) {
            if (ntok < 4) {
                fprintf(stderr, TOOL_NAME ": %s:%d: SECTION requires name addr bin [sym]\n",
                        script_path, lineno);
                errors++;
                continue;
            }
            const char *sec_name = tok[1];
            uint32_t    sec_addr;
            if (!parse_addr(tok[2], &sec_addr)) {
                fprintf(stderr, TOOL_NAME ": %s:%d: invalid address: %s\n",
                        script_path, lineno, tok[2]);
                errors++;
                continue;
            }
            const char *bin_path = tok[3];
            const char *sym_path = (ntok >= 5) ? tok[4] : NULL;

            int placed = section_place(bin_path, sec_addr);
            if (placed < 0) { errors++; continue; }

            printf(TOOL_NAME ":   SECTION %-16s @$%04X  %5d bytes  (%s)\n",
                   sec_name, sec_addr, placed, bin_path);

            /* シンボルをマージ（hasm22の.symは絶対アドレスなのでoffset=0） */
            if (sym_path) {
                int sc = sym_load(sym_path, 0);
                printf(TOOL_NAME ":     sym: %d entries (%s)\n", sc, sym_path);
            }
            continue;
        }

        /* PATCH addr value  — 16bitワードパッチ (リトルエンディアン) */
        if (strcmp(kw, "PATCH") == 0) {
            if (ntok < 3) {
                fprintf(stderr, TOOL_NAME ": %s:%d: PATCH requires addr value\n",
                        script_path, lineno);
                errors++;
                continue;
            }
            uint32_t addr, val;
            if (!parse_addr(tok[1], &addr) || !parse_addr(tok[2], &val)) {
                fprintf(stderr, TOOL_NAME ": %s:%d: invalid PATCH args\n",
                        script_path, lineno);
                errors++;
                continue;
            }
            if (addr + 1 >= MEM_SIZE) {
                fprintf(stderr, TOOL_NAME ": %s:%d: PATCH addr out of range: $%04X\n",
                        script_path, lineno, addr);
                errors++;
                continue;
            }
            mem[addr]   = (uint8_t)(val & 0xFF);
            mem[addr+1] = (uint8_t)((val >> 8) & 0xFF);
            used[addr]  = used[addr+1] = 1;
            printf(TOOL_NAME ":   PATCH  $%04X = $%04X\n", addr, val);
            continue;
        }

        /* PATCHB addr value  — 1バイトパッチ */
        if (strcmp(kw, "PATCHB") == 0) {
            if (ntok < 3) {
                fprintf(stderr, TOOL_NAME ": %s:%d: PATCHB requires addr value\n",
                        script_path, lineno);
                errors++;
                continue;
            }
            uint32_t addr, val;
            if (!parse_addr(tok[1], &addr) || !parse_addr(tok[2], &val)) {
                fprintf(stderr, TOOL_NAME ": %s:%d: invalid PATCHB args\n",
                        script_path, lineno);
                errors++;
                continue;
            }
            if (addr >= MEM_SIZE) {
                fprintf(stderr, TOOL_NAME ": %s:%d: PATCHB addr out of range: $%04X\n",
                        script_path, lineno, addr);
                errors++;
                continue;
            }
            mem[addr]  = (uint8_t)(val & 0xFF);
            used[addr] = 1;
            printf(TOOL_NAME ":   PATCHB $%04X = $%02X\n", addr, val & 0xFF);
            continue;
        }

        fprintf(stderr, TOOL_NAME ": %s:%d: unknown directive: %s\n",
                script_path, lineno, tok[0]);
        errors++;
    }
    fclose(sf);

    if (errors) {
        fprintf(stderr, TOOL_NAME ": %d error(s), aborting\n", errors);
        return 1;
    }

    /* 出力先を確定（コマンドライン > スクリプト内 OUTPUT）*/
    const char *final_bin = out_bin  ? out_bin  :
                            script_out_bin[0] ? script_out_bin : NULL;
    const char *final_sym = out_sym  ? out_sym  :
                            script_out_sym[0] ? script_out_sym : NULL;

    if (!final_bin) {
        fprintf(stderr, TOOL_NAME ": error: no output file specified\n");
        return 1;
    }

    /* バイナリ出力 */
    int last = -1;
    for (int i = MEM_SIZE - 1; i >= 0; i--) {
        if (used[i]) { last = i; break; }
    }
    if (last < 0) {
        fprintf(stderr, TOOL_NAME ": warning: no data placed\n");
        last = 0;
    }

    FILE *of = fopen(final_bin, "wb");
    if (!of) { perror(final_bin); return 1; }
    fwrite(mem, 1, last + 1, of);
    fclose(of);
    printf(TOOL_NAME ": %d bytes -> %s\n", last + 1, final_bin);

    /* シンボル出力 */
    if (final_sym)
        sym_write(final_sym);

    return 0;
}
