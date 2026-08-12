/* lnk23.c - YSD8800 ISA2.3 Linker
 * Version: 2.01
 * YSD8800 YUI OS Project
 *
 * 使用法:
 *   lnk23 -o out.bin a.obj b.obj                        複数.objをリンク
 *   lnk23 -o out.bin -T 0x0100 a.obj b.obj              TEXTアドレス指定
 *   lnk23 -o out.bin --text 0x0100 --data 0x4000 a.obj  TEXT/DATA別指定
 *   lnk23 -o out.bin --sym out.sym a.obj b.obj           シンボル出力
 *   lnk23 -o out.bin --entry _main a.obj b.obj           エントリ指定
 *   lnk23 -o out.bin --machine force a.obj b.obj         forceモード
 *   lnk23 -o out.bin --reserve 0xF000-0xF7FF a.obj       追加禁止領域
 *   lnk23 -o out.bin a.bin:0x0000 b.obj                  .bin後方互換
 *   lnk23 link.lds                                       リンカスクリプト
 *   lnk23 --version
 *
 * YOF (YSD Object Format) オブジェクトファイル形式に対応
 * lnk22 v1.00のリンカスクリプト（.lnk/.lds）との後方互換あり
 *
 * v2.01 [Step 8-F-2 道2/改修(D)]: YOF load_addr＋has_org 尊重の固定配置
 *        設計書: hasm23_xref_yof_design_v2_2.md（承認済 review v4.0）§3.5.3
 *        - load_yof でセクションの load_addr フィールドと has_org フラグ(flags&0x10)を読む。
 *          従来は load_addr を 0 で捨てていた（L351）。これを止めて保持する。
 *        - has_org=1 のセクションは（値が $0000 でも）その load_addr へ固定配置。
 *          has_org=0 は従来通り自動配置（後方互換）。
 *          ※PoC版の「load_addr≠0 で固定」暫定判定は採用しない（kernel@$0000 を
 *            固定配置すべきところを自動配置と誤判定するため）。has_org ビットで判定する。
 *        - 固定/自動の混在はエラー（§3.5.3.2・当面 YUI OS は全セクション固定前提）。
 *        - forceモードで ROM 境界($3FFF)チェック回避は既存機能（§3.5.3.1）。
 * v2.00: lnk22 v1.00から全面再設計
 *        - YOF形式対応・シンボル解決（2パス）・リロケーション
 *        - ISA2.3メモリマップ制約チェック
 *        - ツール名: lnk22 → lnk23（ISA2.3対応）
 *        - Python依存廃止
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <stdint.h>
#include <stdarg.h>

/* ============================================================
 * バージョン・定数
 * ============================================================ */
#define VERSION     "2.01"
#define TOOL_NAME   "lnk23"

#define MEM_SIZE    65536
#define MAX_INPUTS  256
#define MAX_SYMS    4096
#define MAX_RELS    8192
#define MAX_SECS    (MAX_INPUTS * 8)
#define MAX_LINE    512
#define MAX_RESERVE 16

/* ============================================================
 * YOF定義 (lnk23_design_v1_2.docx §2)
 * ============================================================ */
#define YOF_MAGIC   "YOF1"
#define YOF_VER     1

/* セクション種別 */
#define SEC_TEXT    0
#define SEC_DATA    1
#define SEC_BSS     2

/* セクションフラグ */
#define SEC_ALLOC   0x01
#define SEC_EXEC    0x02
#define SEC_WRITE   0x04
#define SEC_READ    0x08
/* v2.01 道2(C-3): hasm23 が .org セクションに立てる has_org ビット。
   flags & 0x10 が立っていれば load_addr へ固定配置（$0000 でも）。立っていなければ自動配置。 */
#define SEC_HAS_ORG 0x10

/* シンボル種別 */
#define SYM_GLOBAL  'G'
#define SYM_LOCAL   'L'
#define SYM_UNDEF   'U'

/* リロケーション種別 */
#define R_ABS16     0
#define R_REL8      1   /* 将来用・Phase 1では未使用 */

/* YOFヘッダ (16バイト固定) */
typedef struct {
    char     magic[4];    /* "YOF1" */
    uint8_t  version;     /* 1 */
    uint8_t  sec_count;   /* 1〜255 */
    uint16_t sym_count;
    uint16_t rel_count;
    uint8_t  reserved[6];
} yof_hdr_t;              /* 16バイト */

/* セクションエントリ (8バイト) */
typedef struct {
    uint8_t  type;        /* SEC_TEXT/DATA/BSS */
    uint8_t  flags;
    uint16_t file_offset; /* ファイル内データオフセット */
    uint16_t size;
    uint16_t load_addr;   /* obj時点=0固定・lnk23内部のみ更新 */
} yof_sec_t;              /* 8バイト */

/* シンボルエントリ (36バイト) */
typedef struct {
    char     name[32];    /* NUL終端 */
    uint8_t  sec_idx;     /* 0〜n-1, 0xFF=絶対 */
    uint16_t offset;      /* セクション内オフセット */
    uint8_t  kind;        /* 'G'/'L'/'U' */
} yof_sym_t;              /* 36バイト */

/* リロケーションエントリ (6バイト) */
typedef struct {
    uint8_t  sec_idx;
    uint16_t offset;
    uint16_t sym_idx;
    uint8_t  type;        /* R_ABS16 / R_REL8 */
} yof_rel_t;              /* 6バイト */

/* ============================================================
 * 内部データ構造
 * ============================================================ */

/* 入力ファイル種別 */
#define INPUT_OBJ   0
#define INPUT_BIN   1   /* 後方互換 */

/* ロード済みセクション（全inputを展開後の内部表現） */
typedef struct {
    int      input_idx;   /* 元inputのインデックス */
    int      sec_in_obj;  /* obj内セクション番号 */
    uint8_t  type;
    uint8_t  flags;
    uint16_t size;
    uint16_t load_addr;   /* lnk23が決定・objには書き戻さない */
    uint8_t *data;        /* セクションデータへのポインタ */
} lsec_t;

/* ロード済みシンボル */
typedef struct {
    char     name[32];
    uint8_t  kind;        /* G/L/U */
    int      sec_gidx;    /* lsec配列インデックス (-1=絶対/UNDEF) */
    uint16_t offset;      /* セクション内オフセット */
    uint16_t addr;        /* リンク後アドレス（確定後） */
    int      input_idx;
} lsym_t;

/* ロード済みリロケーション */
typedef struct {
    int      sec_gidx;    /* lsecのインデックス */
    uint16_t offset;      /* セクション内パッチ位置 */
    int      sym_gidx;    /* lsymのインデックス（解決前:参照名） */
    char     sym_name[32];/* 参照シンボル名 */
    uint8_t  type;
    int      input_idx;
} lrel_t;

/* 入力ファイル */
typedef struct {
    int      kind;        /* INPUT_OBJ / INPUT_BIN */
    char     path[256];
    uint16_t bin_addr;    /* BINモード時の配置アドレス */
    /* OBJモード: 読み込んだYOFデータ */
    uint8_t *raw;         /* immutable: 読み込んだままのバイト列 */
    int      raw_size;
    int      sec_start;   /* lsec配列内の開始インデックス */
    int      sec_count;
    int      sym_start;   /* lsym配列内の開始インデックス */
    int      sym_count;
    int      rel_start;   /* lrel配列内の開始インデックス */
    int      rel_count;
} input_t;

/* マシンモード */
#define MACH_BAREMETAL  0
#define MACH_FORCE      1
#define MACH_NONE       2

/* 禁止領域 */
typedef struct { uint16_t start; uint16_t end; } reserve_t;

/* グローバル状態 */
static uint8_t  mem[MEM_SIZE];
static uint8_t  mem_used[MEM_SIZE];

static input_t  inputs[MAX_INPUTS];
static int      ninputs = 0;

static lsec_t   lsecs[MAX_SECS];
static int      nlsecs = 0;

static lsym_t   lsyms[MAX_SYMS];
static int      nlsyms = 0;

static lrel_t   lrels[MAX_RELS];
static int      nlrels = 0;

static reserve_t reserves[MAX_RESERVE];
static int       nreserves = 0;

/* --alias オプション（案Y: Forceエントリシンボル対応） */
#define MAX_ALIASES 16
typedef struct { char from[32]; char to[32]; } alias_t;
static alias_t aliases[MAX_ALIASES];
static int     naliases = 0;

/* オプション */
static const char *opt_output   = NULL;
static const char *opt_sym_out  = NULL;
static const char *opt_entry    = NULL;
static int         opt_machine  = MACH_BAREMETAL;
static uint16_t    opt_text_addr = 0x0000;
static int         opt_text_addr_set = 0;
static uint16_t    opt_data_addr = 0x0000;
static int         opt_data_addr_set = 0;
/* リンカスクリプトモード */
static int         opt_script_mode = 0;
static const char *opt_script_path = NULL;

/* エラーカウンタ */
static int g_errors = 0;

/* ============================================================
 * ユーティリティ
 * ============================================================ */

static void err(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    fprintf(stderr, TOOL_NAME ": error: ");
    vfprintf(stderr, fmt, ap);
    fprintf(stderr, "\n");
    va_end(ap);
    g_errors++;
}

static void warn(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    fprintf(stderr, TOOL_NAME ": warning: ");
    vfprintf(stderr, fmt, ap);
    fprintf(stderr, "\n");
    va_end(ap);
}

static char *ltrim(char *s) {
    while (*s && isspace((unsigned char)*s)) s++;
    return s;
}

static char *trim(char *s) {
    s = ltrim(s);
    char *e = s + strlen(s);
    while (e > s && isspace((unsigned char)*(e-1))) e--;
    *e = '\0';
    return s;
}

static int parse_addr(const char *s, uint32_t *out) {
    char *endp;
    if (!s || !*s) return 0;
    if (s[0] == '$') {
        *out = (uint32_t)strtoul(s + 1, &endp, 16);
    } else if ((s[0] == '0') && (s[1] == 'x' || s[1] == 'X')) {
        *out = (uint32_t)strtoul(s + 2, &endp, 16);
    } else {
        *out = (uint32_t)strtoul(s, &endp, 16);
        if (*endp != '\0') *out = (uint32_t)strtoul(s, &endp, 10);
    }
    return (*endp == '\0');
}

/* LE 16bit読み書き */
static uint16_t rd16le(const uint8_t *p) {
    return (uint16_t)((uint16_t)p[0] | (uint16_t)(p[1] << 8));
}

static void wr16le(uint8_t *p, uint16_t v) {
    p[0] = (uint8_t)(v & 0xFF);
    p[1] = (uint8_t)((v >> 8) & 0xFF);
}

/* ============================================================
 * Step 1: YOF読み込み骨格 (§11 Step1)
 * ============================================================ */

static int load_yof(input_t *inp) {
    FILE *f = fopen(inp->path, "rb");
    if (!f) {
        err("cannot open: %s", inp->path);
        return -1;
    }

    /* ファイルサイズ取得 */
    fseek(f, 0, SEEK_END);
    long fsz = ftell(f);
    fseek(f, 0, SEEK_SET);

    /* immutableバッファに全読み込み */
    inp->raw = (uint8_t *)malloc(fsz);
    if (!inp->raw) {
        err("out of memory");
        fclose(f);
        return -1;
    }
    if ((long)fread(inp->raw, 1, fsz, f) != fsz) {
        err("read error: %s", inp->path);
        fclose(f);
        free(inp->raw);
        inp->raw = NULL;
        return -1;
    }
    fclose(f);
    inp->raw_size = (int)fsz;

    /* マジック確認 */
    if (fsz < 16 || memcmp(inp->raw, YOF_MAGIC, 4) != 0) {
        err("%s: not a YOF file (bad magic)", inp->path);
        return -1;
    }

    /* ヘッダ解析 */
    yof_hdr_t hdr;
    memcpy(&hdr, inp->raw, sizeof(yof_hdr_t));
    int nsec = hdr.sec_count;
    int nsym = (int)rd16le((uint8_t*)&hdr.sym_count);
    int nrel = (int)rd16le((uint8_t*)&hdr.rel_count);

    /* テーブルオフセット計算（設計書§2固定バイト数を使用） */
    int off_sec = 16;                         /* ヘッダ直後 */
    int off_sym = off_sec + nsec * 8;         /* sec=8バイト */
    int off_rel = off_sym + nsym * 36;        /* sym=36バイト */
    int off_dat = off_rel + nrel * 6;         /* rel=6バイト */

    if (off_dat > inp->raw_size) {
        err("%s: YOF file truncated", inp->path);
        return -1;
    }

    inp->sec_start = nlsecs;
    inp->sec_count = nsec;
    inp->sym_start = nlsyms;
    inp->sym_count = nsym;
    inp->rel_start = nlrels;
    inp->rel_count = nrel;

    /* セクション収集 */
    for (int i = 0; i < nsec; i++) {
        if (nlsecs >= MAX_SECS) { err("too many sections"); return -1; }
        yof_sec_t s;
        memcpy(&s, inp->raw + off_sec + i * 8, 8);
        uint16_t size        = rd16le((uint8_t*)&s.size);
        uint16_t file_offset = rd16le((uint8_t*)&s.file_offset);
        /* v2.01 道2: load_addr はバイト直読み（構造体アライメント差異回避）。
           YOF 8B セクションヘッダ: type(1)+flags(1)+file_offset(2)+size(2)+load_addr(2)。
           load_addr はオフセット6。 */
        uint16_t yof_load_addr = rd16le(inp->raw + off_sec + i * 8 + 6);

        lsec_t *ls = &lsecs[nlsecs++];
        ls->input_idx  = (int)(inp - inputs);
        ls->sec_in_obj = i;
        ls->type       = s.type;
        ls->flags      = s.flags;
        ls->size       = size;
        /* v2.01 道2(C-3): has_org(flags&0x10) が立っていれば YOF の load_addr を尊重して
           保持（固定配置の指定）。立っていなければ 0（=自動配置・後方互換）。
           ★PoC版の「load_addr≠0 で固定」暫定判定は採用しない。kernel@$0000 は
             has_org=1/load_addr=$0000 ゆえ、その判定だと自動配置に誤って流れる（KY-本日）。 */
        if (ls->flags & SEC_HAS_ORG) {
            ls->load_addr = yof_load_addr;   /* 固定配置（$0000 でも尊重） */
        } else {
            ls->load_addr = 0;               /* 配置前未定（place_sections で自動配置） */
        }
        /* データポインタ（immutableバッファ内を指す） */
        if (size > 0 && s.type != SEC_BSS) {
            ls->data = inp->raw + off_dat + file_offset;
        } else {
            ls->data = NULL;
        }

        /* BSSはPhase 1未対応 */
        if (s.type == SEC_BSS) {
            err("%s: BSS section not supported in Phase 1", inp->path);
            return -1;
        }
    }

    /* シンボル収集
     * YOFシンボルエントリは36バイト固定（設計書§2.4）
     *   name[32]:0-31, sec_idx:32, offset_LE:33-34, kind:35
     * ※ C構造体(yof_sym_t)はアライメントで38バイトになるため
     *    構造体memcpyは使わず直接バイトアクセスする */
    for (int i = 0; i < nsym; i++) {
        if (nlsyms >= MAX_SYMS) { err("too many symbols"); return -1; }
        const uint8_t *sp = inp->raw + off_sym + i * 36;

        lsym_t *ls = &lsyms[nlsyms++];
        memset(ls->name, 0, 32);
        memcpy(ls->name, sp,      31);          /* name[0..31] */
        uint8_t sec_idx = sp[32];
        ls->offset    = (uint16_t)(sp[33] | sp[34]<<8); /* offset LE */
        ls->kind      = sp[35];                          /* kind: G/L/U */
        ls->addr      = 0;
        ls->input_idx = (int)(inp - inputs);

        /* セクションインデックスをグローバルに変換 */
        if (sec_idx == 0xFF) {
            ls->sec_gidx = -1; /* 絶対アドレス */
        } else if (sec_idx < (uint8_t)nsec) {
            ls->sec_gidx = inp->sec_start + sec_idx;
        } else {
            err("%s: symbol '%s' has invalid sec_idx %d", inp->path, ls->name, sec_idx);
            return -1;
        }
    }

    /* リロケーション収集
     * YOFリロケーションエントリは6バイト固定（設計書§2.5）
     *   sec_idx:0, offset_LE:1-2, sym_idx_LE:3-4, type:5
     * ※ C構造体(yof_rel_t)はアライメントで8バイトになるため直接バイトアクセス */
    for (int i = 0; i < nrel; i++) {
        if (nlrels >= MAX_RELS) { err("too many relocations"); return -1; }
        const uint8_t *rp = inp->raw + off_rel + i * 6;

        lrel_t *lr = &lrels[nlrels++];
        uint8_t  r_sec_idx = rp[0];
        uint16_t r_offset  = (uint16_t)(rp[1] | rp[2]<<8);
        uint16_t r_sym_idx = (uint16_t)(rp[3] | rp[4]<<8);
        uint8_t  r_type    = rp[5];

        lr->offset    = r_offset;
        lr->sym_name[0] = '\0';
        lr->type      = r_type;
        lr->input_idx = (int)(inp - inputs);
        lr->sym_gidx  = -1;

        /* セクション番号をグローバルに変換 */
        if (r_sec_idx < (uint8_t)nsec) {
            lr->sec_gidx = inp->sec_start + r_sec_idx;
        } else {
            err("%s: reloc has invalid sec_idx %d", inp->path, r_sec_idx);
            return -1;
        }

        /* シンボル参照名を取得（sym_idxから） */
        int gsym_idx = inp->sym_start + r_sym_idx;
        if (r_sym_idx >= (uint16_t)nsym || gsym_idx >= nlsyms) {
            err("%s: reloc sym_idx %d out of range", inp->path, r_sym_idx);
            return -1;
        }
        memcpy(lr->sym_name, lsyms[gsym_idx].name, 32);
    }

    return 0;
}

/* ============================================================
 * .bin後方互換入力読み込み
 * ============================================================ */
static int load_bin_compat(input_t *inp) {
    warn(".bin input '%s' has no relocation info, assuming fixed placement", inp->path);

    FILE *f = fopen(inp->path, "rb");
    if (!f) { err("cannot open: %s", inp->path); return -1; }

    fseek(f, 0, SEEK_END);
    long fsz = ftell(f);
    fseek(f, 0, SEEK_SET);

    inp->raw = (uint8_t *)malloc(fsz);
    if (!inp->raw) { err("out of memory"); fclose(f); return -1; }
    if ((long)fread(inp->raw, 1, fsz, f) != fsz) {
        err("read error: %s", inp->path);
        fclose(f);
        return -1;
    }
    fclose(f);
    inp->raw_size = (int)fsz;

    /* .binは1セクション（TEXT固定）として登録 */
    if (nlsecs >= MAX_SECS) { err("too many sections"); return -1; }
    inp->sec_start = nlsecs;
    inp->sec_count = 1;
    inp->sym_start = nlsyms;
    inp->sym_count = 0;
    inp->rel_start = nlrels;
    inp->rel_count = 0;

    lsec_t *ls = &lsecs[nlsecs++];
    ls->input_idx  = (int)(inp - inputs);
    ls->sec_in_obj = 0;
    ls->type       = SEC_TEXT;
    ls->flags      = SEC_ALLOC | SEC_EXEC | SEC_READ;
    ls->size       = (uint16_t)fsz;
    ls->load_addr  = inp->bin_addr; /* 指定アドレスに固定 */
    ls->data       = inp->raw;

    return 0;
}

/* ============================================================
 * Step 2: セクション配置 (§11 Step2, §3)
 * ============================================================ */

static int align2(int v) { return (v + 1) & ~1; }

static int place_sections(void) {
    uint16_t text_cur = opt_text_addr_set ? opt_text_addr : 0x0000;
    uint16_t data_cur = 0x0000;

    /* v2.01 道2(§3.5.3.2): 固定配置(has_org=1)と自動配置(has_org=0)の混在を検出してエラー。
       当面 YUI OS は全 YOF セクションが has_org を持つ前提。混在は意図しない配置
       （自動配置が固定セクションの隙間/後方に滑り込む）を招くため弾く。
       .bin(INPUT_BIN)は元々固定なので集計対象外。 */
    {
        int n_fixed = 0, n_auto = 0;
        for (int i = 0; i < nlsecs; i++) {
            lsec_t *ls = &lsecs[i];
            if (inputs[ls->input_idx].kind == INPUT_BIN) continue;
            if (ls->size == 0) continue;
            if (ls->flags & SEC_HAS_ORG) n_fixed++; else n_auto++;
        }
        if (n_fixed > 0 && n_auto > 0) {
            err("mixed fixed(has_org) and auto-placed sections is not supported "
                "(fixed=%d, auto=%d). All YOF sections must carry .org/has_org.",
                n_fixed, n_auto);
            return -1;
        }
    }

    /* TEXT配置（入力順） */
    for (int i = 0; i < nlsecs; i++) {
        lsec_t *ls = &lsecs[i];
        /* .binは既にload_addrが確定 */
        if (inputs[ls->input_idx].kind == INPUT_BIN) continue;
        /* v2.01 道2: has_org=1 は load_yof で load_addr 確定済み→自動配置スキップ
           （.bin の固定配置経路と構造同型） */
        if (ls->flags & SEC_HAS_ORG) continue;
        if (ls->type != SEC_TEXT) continue;
        if (ls->size == 0) continue; /* R21: 空セクションスキップ */

        /* 2バイト境界 */
        text_cur = (uint16_t)align2(text_cur);
        ls->load_addr = text_cur;
        text_cur = (uint16_t)(text_cur + ls->size);
    }

    /* DATA配置: --data指定 or TEXTの直後 */
    if (opt_data_addr_set) {
        data_cur = opt_data_addr;
    } else {
        data_cur = (uint16_t)align2(text_cur);
    }

    for (int i = 0; i < nlsecs; i++) {
        lsec_t *ls = &lsecs[i];
        if (inputs[ls->input_idx].kind == INPUT_BIN) continue;
        if (ls->flags & SEC_HAS_ORG) continue;   /* v2.01 道2: 固定配置はスキップ */
        if (ls->type != SEC_DATA) continue;
        if (ls->size == 0) continue;

        data_cur = (uint16_t)align2(data_cur);
        ls->load_addr = data_cur;
        data_cur = (uint16_t)(data_cur + ls->size);
    }

    return 0;
}

/* ============================================================
 * Step 3: メモリ制約チェック (§11 Step3, §4)
 * ============================================================ */

static int check_memory(void) {
    uint16_t text_end = 0;
    uint16_t data_start = 0xFFFF;
    int has_data = 0;

    for (int i = 0; i < nlsecs; i++) {
        lsec_t *ls = &lsecs[i];
        if (ls->size == 0) continue;

        uint16_t sec_start = ls->load_addr;
        uint32_t sec_end32 = (uint32_t)ls->load_addr + ls->size - 1;
        if (sec_end32 > 0xFFFF) {
            err("section exceeds 64KB address space");
            continue;
        }
        uint16_t sec_end = (uint16_t)sec_end32;

        /* I/O領域チェック（全モード） */
        if (sec_end >= 0xFC80) {
            err("section @$%04X-$%04X overlaps I/O area ($FC80-$FFFF)", sec_start, sec_end);
        }

        /* 予約領域交差判定（R20）- 全モード */
        if (sec_end >= 0xFBD0 && sec_start <= 0xFC7F) {
            err("section @$%04X-$%04X overlaps reserved area ($FBD0-$FC7F)", sec_start, sec_end);
        }

        /* 追加禁止領域 */
        for (int r = 0; r < nreserves; r++) {
            if (sec_end >= reserves[r].start && sec_start <= reserves[r].end) {
                err("section @$%04X-$%04X overlaps reserved area ($%04X-$%04X)",
                    sec_start, sec_end, reserves[r].start, reserves[r].end);
            }
        }

        /* WRITABLEセクションのROM領域配置禁止（R17：全モード） */
        if ((ls->flags & SEC_WRITE) && sec_start < 0x4000) {
            err("writable section @$%04X cannot be placed in ROM area", sec_start);
        }

        /* オーバーラップ検出（既存配置との重複） */
        for (int j = 0; j < i; j++) {
            lsec_t *ls2 = &lsecs[j];
            if (ls2->size == 0) continue;
            uint16_t s2 = ls2->load_addr;
            uint16_t e2 = (uint16_t)(s2 + ls2->size - 1);
            if (sec_end >= s2 && sec_start <= e2) {
                err("section overlap: $%04X-$%04X vs $%04X-$%04X",
                    sec_start, sec_end, s2, e2);
            }
        }

        /* TEXT終端・DATA先頭 */
        if (ls->type == SEC_TEXT) {
            if (sec_end > text_end) text_end = sec_end;
        }
        if (ls->type == SEC_DATA) {
            if (!has_data || sec_start < data_start) data_start = sec_start;
            has_data = 1;
        }
    }

    /* baremetalモード限定チェック (§3.3, §4.3) */
    if (opt_machine == MACH_BAREMETAL) {
        if (text_end > 0x3FFF) {
            err("TEXT exceeds ROM area ($3FFF), text_end=$%04X", text_end);
        }
        if (has_data && data_start < 0x4000) {
            err("DATA must be in RAM (>= $4000), data_start=$%04X", data_start);
        }
    }

    return g_errors ? -1 : 0;
}

/* ============================================================
 * Step 4: シンボル解決 (2パス) (§11 Step4, §6)
 * ============================================================ */

/* グローバルシンボルテーブル（名前→lsymインデックス） */
typedef struct { char name[32]; int idx; } gsym_t;
static gsym_t   gsyms[MAX_SYMS];
static int      ngsyms = 0;

static int find_global(const char *name) {
    for (int i = 0; i < ngsyms; i++)
        if (strcmp(gsyms[i].name, name) == 0) return gsyms[i].idx;
    return -1;
}

static int resolve_symbols(void) {
    /* === 第1パス: 配置確定後にGLOBALシンボルアドレスを確定 === */
    for (int i = 0; i < nlsyms; i++) {
        lsym_t *ls = &lsyms[i];
        if (ls->kind != SYM_GLOBAL) continue;

        /* アドレス確定 */
        if (ls->sec_gidx >= 0) {
            ls->addr = (uint16_t)(lsecs[ls->sec_gidx].load_addr + ls->offset);
        }
        /* 注: 絶対シンボル(sec_gidx=-1)はoffsetをアドレスとして使用 */
        else {
            ls->addr = ls->offset;
        }

        /* GLOBAL重複エラー (R03) */
        int exist = find_global(ls->name);
        if (exist >= 0) {
            err("duplicate symbol: %s (in input[%d] and input[%d])",
                ls->name, lsyms[exist].input_idx, ls->input_idx);
            continue;
        }

        if (ngsyms >= MAX_SYMS) { err("too many global symbols"); return -1; }
        memcpy(gsyms[ngsyms].name, ls->name, 32);
        gsyms[ngsyms].idx = i;
        ngsyms++;
    }

    if (g_errors) return -1;

    /* === 第2パス: UNDEFシンボルを解決 === */
    for (int i = 0; i < nlsyms; i++) {
        lsym_t *ls = &lsyms[i];
        if (ls->kind != SYM_UNDEF) continue;

        int gi = find_global(ls->name);

        /* --alias による名前置換（案Y: _main=_forth_main 等） */
        if (gi < 0) {
            for (int a = 0; a < naliases; a++) {
                if (strcmp(aliases[a].from, ls->name) == 0) {
                    gi = find_global(aliases[a].to);
                    if (gi >= 0) {
                        printf(TOOL_NAME ":   alias: %s -> %s ($%04X)\n",
                               ls->name, aliases[a].to, lsyms[gi].addr);
                        break;
                    }
                }
            }
        }

        if (gi < 0) {
            err("undefined symbol: %s (referenced in input[%d])",
                ls->name, ls->input_idx);
            continue;
        }
        /* 解決済み: UNDEFをGLOBALと同じアドレスに */
        ls->addr = lsyms[gi].addr;
    }

    return g_errors ? -1 : 0;
}

/* ============================================================
 * Step 5: リロケーション適用 (§11 Step5, §7)
 * ============================================================ */

static int apply_relocations(void) {
    for (int i = 0; i < nlrels; i++) {
        lrel_t *lr = &lrels[i];

        /* .binエントリはスキップ（R18防御コード） */
        if (inputs[lr->input_idx].kind == INPUT_BIN) {
            continue;
        }

        /* シンボルアドレス解決 */
        int sym_idx = -1;
        /* まずGLOBALテーブルから検索 */
        int gi = find_global(lr->sym_name);
        if (gi >= 0) {
            sym_idx = gi;
        } else {
            /* ローカルまたはUNDEF解決済みを検索 */
            for (int j = 0; j < nlsyms; j++) {
                if (strcmp(lsyms[j].name, lr->sym_name) == 0 &&
                    lsyms[j].input_idx == lr->input_idx) {
                    sym_idx = j;
                    break;
                }
            }
        }

        if (sym_idx < 0) {
            err("reloc: unresolved symbol '%s'", lr->sym_name);
            continue;
        }

        uint16_t sym_addr;
        if (gi >= 0) {
            sym_addr = lsyms[gi].addr;   /* giはlsymsのインデックス */
        } else {
            sym_addr = lsyms[sym_idx].addr;
        }

        /* パッチアドレス計算 */
        lsec_t *sec = &lsecs[lr->sec_gidx];
        uint16_t patch_addr = (uint16_t)(sec->load_addr + lr->offset);

        if (lr->type == R_ABS16) {
            /* R_ABS16: リトルエンディアン16bit (R15) */
            if (patch_addr + 1 >= MEM_SIZE) {
                err("reloc R_ABS16: patch_addr $%04X out of range", patch_addr);
                continue;
            }
            wr16le(mem + patch_addr, sym_addr);
            mem_used[patch_addr] = mem_used[patch_addr+1] = 1;
        } else if (lr->type == R_REL8) {
            /* R_REL8: 将来用・Phase 1では未使用（到達した場合はエラー） */
            err("reloc R_REL8: not supported in Phase 1 (patch_addr=$%04X)", patch_addr);
        } else {
            err("reloc: unknown type %d", lr->type);
        }
    }

    return g_errors ? -1 : 0;
}

/* ============================================================
 * Step 6: バイナリ出力 (§11 Step6)
 * ============================================================ */

/* セクションデータをmemバッファに書き出す */
static void place_to_mem(void) {
    for (int i = 0; i < nlsecs; i++) {
        lsec_t *ls = &lsecs[i];
        if (ls->size == 0 || ls->data == NULL) continue;

        uint16_t base = ls->load_addr;
        for (int j = 0; j < ls->size; j++) {
            uint32_t a = (uint32_t)base + j;
            if (a >= MEM_SIZE) break;
            mem[a]      = ls->data[j];
            mem_used[a] = 1;
        }
    }
}

static int write_binary(void) {
    if (!opt_output) {
        err("no output file specified");
        return -1;
    }

    /* 有効末尾バイトを探す */
    int last = -1;
    for (int i = MEM_SIZE - 1; i >= 0; i--) {
        if (mem_used[i]) { last = i; break; }
    }
    if (last < 0) {
        warn("no data placed");
        last = 0;
    }

    FILE *f = fopen(opt_output, "wb");
    if (!f) { err("cannot create: %s", opt_output); return -1; }
    fwrite(mem, 1, last + 1, f);
    fclose(f);
    printf(TOOL_NAME ": %d bytes -> %s\n", last + 1, opt_output);

    /* シンボル出力 */
    if (opt_sym_out) {
        FILE *sf = fopen(opt_sym_out, "w");
        if (!sf) {
            err("cannot create sym: %s", opt_sym_out);
        } else {
            int cnt = 0;
            for (int i = 0; i < ngsyms; i++) {
                lsym_t *ls = &lsyms[gsyms[i].idx];
                fprintf(sf, "%04x %s\n", ls->addr & 0xFFFF, ls->name);
                cnt++;
            }
            /* ローカルシンボルも出力 */
            for (int i = 0; i < nlsyms; i++) {
                if (lsyms[i].kind == SYM_LOCAL) {
                    fprintf(sf, "%04x %s\n", lsyms[i].addr & 0xFFFF, lsyms[i].name);
                    cnt++;
                }
            }
            fclose(sf);
            printf(TOOL_NAME ": %d symbols -> %s\n", cnt, opt_sym_out);
        }
    }

    return 0;
}

/* ============================================================
 * PATCH適用（リンカスクリプト / §7.1）
 * ============================================================ */
static void apply_patch(uint16_t addr, uint16_t val) {
    if (addr + 1 >= MEM_SIZE) { err("PATCH addr $%04X out of range", addr); return; }
    wr16le(mem + addr, val);
    mem_used[addr] = mem_used[addr+1] = 1;
    printf(TOOL_NAME ":   PATCH $%04X = $%04X\n", addr, val);
}

static void apply_patchb(uint16_t addr, uint8_t val) {
    /* uint16_tの最大値は65535 < MEM_SIZE(65536)なので範囲外は起き得ないが防御コード */
    mem[addr]      = val;
    mem_used[addr] = 1;
    printf(TOOL_NAME ":   PATCHB $%04X = $%02X\n", addr, val);
}

/* ============================================================
 * リンカスクリプトモード（lnk22後方互換）(§14)
 * ============================================================ */
static int run_script(const char *path) {
    FILE *f = fopen(path, "r");
    if (!f) { err("cannot open script: %s", path); return -1; }

    char line[MAX_LINE];
    int  lineno = 0;
    char script_out[256] = "";
    char script_sym[256] = "";

    while (fgets(line, sizeof(line), f)) {
        lineno++;
        char *s = trim(line);
        if (*s == '#' || *s == ';' || *s == '\0') continue;

        char *tok[6] = {NULL};
        int ntok = 0;
        char *p = s;
        while (*p && ntok < 6) {
            while (*p && isspace((unsigned char)*p)) p++;
            if (!*p) break;
            tok[ntok++] = p;
            while (*p && !isspace((unsigned char)*p)) p++;
            if (*p) { *p = '\0'; p++; }
        }
        if (!ntok) continue;

        char kw[32];
        strncpy(kw, tok[0], 31); kw[31] = '\0';
        for (int i = 0; kw[i]; i++) kw[i] = (char)toupper((unsigned char)kw[i]);

        if (strcmp(kw, "OUTPUT") == 0) {
            if (ntok >= 2) strncpy(script_out, tok[1], 255);
        } else if (strcmp(kw, "SYMOUT") == 0) {
            if (ntok >= 2) strncpy(script_sym, tok[1], 255);
        } else if (strcmp(kw, "SECTION") == 0) {
            /* SECTION name addr file.bin [file.sym] */
            if (ntok < 4) {
                err("script:%d: SECTION requires name addr bin [sym]", lineno);
                continue;
            }
            uint32_t addr;
            if (!parse_addr(tok[2], &addr)) {
                err("script:%d: invalid address: %s", lineno, tok[2]);
                continue;
            }
            /* .bin配置（従来互換） */
            FILE *bf = fopen(tok[3], "rb");
            if (!bf) { err("script:%d: cannot open: %s", lineno, tok[3]); continue; }
            fseek(bf, 0, SEEK_END); long bsz = ftell(bf); fseek(bf, 0, SEEK_SET);
            printf(TOOL_NAME ":   SECTION %-16s @$%04X  %5ld bytes  (%s)\n",
                   tok[1], (uint16_t)addr, bsz, tok[3]);
            int bi = 0;
            int c;
            while ((c = fgetc(bf)) != EOF) {
                uint32_t a = addr + bi++;
                if (a < MEM_SIZE) { mem[a] = (uint8_t)c; mem_used[a] = 1; }
            }
            fclose(bf);
            /* .sym（オプション） */
            if (ntok >= 5) {
                FILE *sf = fopen(tok[4], "r");
                if (sf) {
                    char sl[256]; int sc = 0;
                    while (fgets(sl, sizeof(sl), sf)) {
                        char nm[128]; uint32_t a;
                        if (sscanf(sl, "%x %127s", &a, nm) == 2) {
                            nm[31] = '\0'; /* シンボル名を32バイト以内に切り詰め */
                            /* グローバルシンボルとして登録 */
                            if (ngsyms < MAX_SYMS) {
                                memset(gsyms[ngsyms].name, 0, 32);
                                memcpy(gsyms[ngsyms].name, nm, 31);
                                /* lsymに追加 */
                                if (nlsyms < MAX_SYMS) {
                                    lsyms[nlsyms].kind = SYM_GLOBAL;
                                    lsyms[nlsyms].addr = (uint16_t)a;
                                    lsyms[nlsyms].input_idx = -1;
                                    lsyms[nlsyms].sec_gidx = -1;
                                    memset(lsyms[nlsyms].name, 0, 32);
                                    memcpy(lsyms[nlsyms].name, nm, 31);
                                    gsyms[ngsyms].idx = nlsyms++;
                                    ngsyms++;
                                    sc++;
                                }
                            }
                        }
                    }
                    fclose(sf);
                    printf(TOOL_NAME ":     sym: %d entries (%s)\n", sc, tok[4]);
                }
            }
        } else if (strcmp(kw, "PATCH") == 0) {
            if (ntok < 3) { err("script:%d: PATCH requires addr value", lineno); continue; }
            uint32_t a, v;
            if (!parse_addr(tok[1], &a) || !parse_addr(tok[2], &v)) {
                err("script:%d: invalid PATCH args", lineno); continue;
            }
            apply_patch((uint16_t)a, (uint16_t)v);
        } else if (strcmp(kw, "PATCHB") == 0) {
            if (ntok < 3) { err("script:%d: PATCHB requires addr value", lineno); continue; }
            uint32_t a, v;
            if (!parse_addr(tok[1], &a) || !parse_addr(tok[2], &v)) {
                err("script:%d: invalid PATCHB args", lineno); continue;
            }
            apply_patchb((uint16_t)a, (uint8_t)(v & 0xFF));
        } else {
            err("script:%d: unknown directive: %s", lineno, tok[0]);
        }
    }
    fclose(f);

    if (!opt_output && script_out[0]) {
        char *p = (char*)malloc(256);
        strncpy(p, script_out, 255); p[255] = '\0';
        opt_output = p;
    }
    if (!opt_sym_out && script_sym[0]) {
        char *p = (char*)malloc(256);
        strncpy(p, script_sym, 255); p[255] = '\0';
        opt_sym_out = p;
    }

    return g_errors ? -1 : 0;
}

/* ============================================================
 * エントリポイント解決（--entry）
 * ============================================================ */
static void resolve_entry(void) {
    if (!opt_entry) {
        /* デフォルト $0000（R06） */
        warn("no entry point specified, defaulting to 0x0000");
        return;
    }

    /* 数値指定の場合 */
    uint32_t ea;
    if (parse_addr(opt_entry, &ea)) {
        printf(TOOL_NAME ": entry = $%04X\n", (uint16_t)ea);
        return;
    }

    /* シンボル名指定 */
    int gi = find_global(opt_entry);
    if (gi < 0) {
        err("entry symbol '%s' not found", opt_entry);
        return;
    }
    printf(TOOL_NAME ": entry = $%04X (%s)\n", lsyms[gsyms[gi].idx].addr, opt_entry);
}

/* ============================================================
 * コマンドライン解析
 * ============================================================ */
static void print_usage(void) {
    fprintf(stderr,
        "Usage: " TOOL_NAME " [options] input...\n"
        "       " TOOL_NAME " script.lds\n"
        "  -o <file>            Output binary\n"
        "  -T <addr>            TEXT section start address\n"
        "  --text <addr>        TEXT section start address\n"
        "  --data <addr>        DATA section start address\n"
        "  --sym <file>         Symbol output\n"
        "  --entry <sym|addr>   Entry point\n"
        "  --machine <mode>     baremetal(default)/force/none\n"
        "  --reserve <s>-<e>    Add forbidden region (hex)\n"
        "  --alias from=to      Symbol alias (e.g. --alias _main=_forth_main)\n"
        "  Input: file.obj | file.bin:0xADDR\n"
        "  --version\n"
    );
}

static int parse_args(int argc, char **argv) {
    if (argc < 2) { print_usage(); return -1; }

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--version") == 0 || strcmp(argv[i], "-v") == 0) {
            printf(TOOL_NAME " - YSD8800 ISA2.3 Linker v" VERSION "\n");
            printf("  YSD8800 YUI OS Project\n");
            exit(0);
        } else if (strcmp(argv[i], "-o") == 0 && i+1 < argc) {
            opt_output = argv[++i];
        } else if ((strcmp(argv[i], "-T") == 0 || strcmp(argv[i], "--text") == 0) && i+1 < argc) {
            uint32_t a;
            if (!parse_addr(argv[++i], &a)) { err("invalid address: %s", argv[i]); return -1; }
            opt_text_addr = (uint16_t)a;
            opt_text_addr_set = 1;
        } else if (strcmp(argv[i], "--data") == 0 && i+1 < argc) {
            uint32_t a;
            if (!parse_addr(argv[++i], &a)) { err("invalid address: %s", argv[i]); return -1; }
            opt_data_addr = (uint16_t)a;
            opt_data_addr_set = 1;
        } else if (strcmp(argv[i], "--sym") == 0 && i+1 < argc) {
            opt_sym_out = argv[++i];
        } else if (strcmp(argv[i], "--entry") == 0 && i+1 < argc) {
            opt_entry = argv[++i];
        } else if (strcmp(argv[i], "--machine") == 0 && i+1 < argc) {
            const char *m = argv[++i];
            if (strcmp(m, "baremetal") == 0)     opt_machine = MACH_BAREMETAL;
            else if (strcmp(m, "force") == 0)    opt_machine = MACH_FORCE;
            else if (strcmp(m, "none") == 0)     opt_machine = MACH_NONE;
            else { err("unknown machine: %s", m); return -1; }
        } else if (strcmp(argv[i], "--reserve") == 0 && i+1 < argc) {
            const char *rs = argv[++i];
            uint32_t rs_s, rs_e;
            char *dash = strchr(rs, '-');
            if (!dash) { err("--reserve: expected start-end, got: %s", rs); return -1; }
            *dash = '\0';
            if (!parse_addr(rs, &rs_s) || !parse_addr(dash+1, &rs_e)) {
                err("--reserve: invalid range"); return -1;
            }
            *dash = '-';
            if (nreserves >= MAX_RESERVE) { err("too many --reserve"); return -1; }
            reserves[nreserves].start = (uint16_t)rs_s;
            reserves[nreserves].end   = (uint16_t)rs_e;
            nreserves++;
        } else if (strcmp(argv[i], "--alias") == 0 && i+1 < argc) {
            /* --alias from=to  例: --alias _main=_forth_main */
            const char *al = argv[++i];
            char *eq = strchr(al, '=');
            if (!eq) { err("--alias: expected from=to, got: %s", al); return -1; }
            if (naliases >= MAX_ALIASES) { err("too many --alias"); return -1; }
            int flen = (int)(eq - al);
            if (flen <= 0 || flen >= 32) { err("--alias: invalid from name"); return -1; }
            memset(aliases[naliases].from, 0, 32);
            memset(aliases[naliases].to,   0, 32);
            memcpy(aliases[naliases].from, al, flen);
            {
                int tlen = (int)strlen(eq+1);
                if (tlen > 31) tlen = 31;
                memcpy(aliases[naliases].to, eq+1, tlen);
            }
            naliases++;
        } else if (argv[i][0] != '-') {
            /* 入力ファイル: file.obj または file.bin:0xADDR または .ldsスクリプト */
            const char *arg = argv[i];

            /* .lds/.lnk はスクリプトモード */
            const char *ext = strrchr(arg, '.');
            if (ext && (strcmp(ext, ".lds") == 0 || strcmp(ext, ".lnk") == 0)) {
                opt_script_mode = 1;
                opt_script_path = arg;
                continue;
            }

            if (ninputs >= MAX_INPUTS) { err("too many inputs"); return -1; }
            input_t *inp = &inputs[ninputs++];
            memset(inp, 0, sizeof(*inp));

            /* file.bin:0xADDR ? */
            char *colon = strrchr(arg, ':');
            if (colon && colon > arg + 4) {
                /* コロン以前が.binかチェック */
                char tmp[256];
                strncpy(tmp, arg, 255); tmp[255] = '\0';
                char *tc = strrchr(tmp, ':');
                if (tc) {
                    *tc = '\0';
                    const char *bext = strrchr(tmp, '.');
                    if (bext && strcmp(bext, ".bin") == 0) {
                        uint32_t ba;
                        if (!parse_addr(tc+1, &ba)) {
                            err("invalid bin address: %s", colon+1); return -1;
                        }
                        inp->kind = INPUT_BIN;
                        inp->bin_addr = (uint16_t)ba;
                        tmp[255] = '\0';
                        memcpy(inp->path, tmp, 255);
                        continue;
                    }
                }
            }

            /* .obj */
            inp->kind = INPUT_OBJ;
            strncpy(inp->path, arg, 255);
        } else {
            err("unknown option: %s", argv[i]);
            return -1;
        }
    }

    /* スクリプトのみで入力なし → スクリプトモード確定 */
    if (ninputs == 0 && !opt_script_mode) {
        print_usage();
        return -1;
    }

    return 0;
}

/* ============================================================
 * メイン
 * ============================================================ */
int main(int argc, char **argv) {
    memset(mem,      0, sizeof(mem));
    memset(mem_used, 0, sizeof(mem_used));

    /* ---------------------------
     * コマンドライン解析
     * --------------------------- */
    if (parse_args(argc, argv) < 0) return 1;

    printf(TOOL_NAME " - YSD8800 ISA2.3 Linker v" VERSION "\n");

    /* ---------------------------
     * リンカスクリプトモード
     * --------------------------- */
    if (opt_script_mode) {
        printf(TOOL_NAME ": script mode: %s\n", opt_script_path);
        if (run_script(opt_script_path) < 0) {
            fprintf(stderr, TOOL_NAME ": %d error(s)\n", g_errors);
            return 1;
        }
        /* スクリプトモードはmemバッファ直接操作のため出力へ */
        if (write_binary() < 0) {
            fprintf(stderr, TOOL_NAME ": %d error(s)\n", g_errors);
            return 1;
        }
        return 0;
    }

    /* ---------------------------
     * YOFリンクモード
     * --------------------------- */

    /* Step 1: YOF読み込み */
    printf(TOOL_NAME ": loading %d input(s)...\n", ninputs);
    for (int i = 0; i < ninputs; i++) {
        input_t *inp = &inputs[i];
        int r;
        if (inp->kind == INPUT_BIN) {
            r = load_bin_compat(inp);
        } else {
            r = load_yof(inp);
        }
        if (r < 0 && !g_errors) g_errors++;
    }
    if (g_errors) { fprintf(stderr, TOOL_NAME ": %d error(s)\n", g_errors); return 1; }

    /* Step 2: セクション配置 */
    printf(TOOL_NAME ": placing sections...\n");
    place_sections();
    if (g_errors) { fprintf(stderr, TOOL_NAME ": %d error(s)\n", g_errors); return 1; }

    /* セクション配置サマリ */
    for (int i = 0; i < nlsecs; i++) {
        lsec_t *ls = &lsecs[i];
        if (ls->size == 0) continue;
        printf(TOOL_NAME ":   sec[%d] type=%s flags=$%02X @$%04X size=%d (%s)\n",
               i,
               ls->type == SEC_TEXT ? "TEXT" : ls->type == SEC_DATA ? "DATA" : "BSS",
               ls->flags,
               ls->load_addr, ls->size,
               inputs[ls->input_idx].path);
    }

    /* Step 3: メモリ制約チェック */
    printf(TOOL_NAME ": checking memory layout (machine=%s)...\n",
           opt_machine == MACH_BAREMETAL ? "baremetal" :
           opt_machine == MACH_FORCE     ? "force"     : "none");
    check_memory();
    if (g_errors) { fprintf(stderr, TOOL_NAME ": %d error(s)\n", g_errors); return 1; }

    /* セクションデータをmemバッファへ展開 */
    place_to_mem();

    /* Step 4: シンボル解決（2パス） */
    printf(TOOL_NAME ": resolving symbols...\n");
    resolve_symbols();
    if (g_errors) { fprintf(stderr, TOOL_NAME ": %d error(s)\n", g_errors); return 1; }
    printf(TOOL_NAME ":   %d global symbol(s) resolved\n", ngsyms);

    /* --entry処理 */
    resolve_entry();
    if (g_errors) { fprintf(stderr, TOOL_NAME ": %d error(s)\n", g_errors); return 1; }

    /* Step 5: リロケーション適用 */
    printf(TOOL_NAME ": applying %d relocation(s)...\n", nlrels);
    apply_relocations();
    if (g_errors) { fprintf(stderr, TOOL_NAME ": %d error(s)\n", g_errors); return 1; }

    /* Step 6: 出力 */
    write_binary();
    if (g_errors) { fprintf(stderr, TOOL_NAME ": %d error(s)\n", g_errors); return 1; }

    return 0;
}
