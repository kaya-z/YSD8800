// disasm22.c - YSD8800 ISA2.2 Disassembler
// disasm22 v1.00
//
// 機能:
//   - バイナリ → アセンブリテキスト出力
//   - .sym ファイル読み込みでラベル付き出力
//   - .dbg ファイル読み込みでソース行コメント付き出力
//   - hasm22 で再アセンブル可能なソース形式で出力
//   - ベクタテーブル（$0000-$000F）を .vector ディレクティブで出力
//   - ゼロ埋め領域は .org でスキップ
//
// 使用法:
//   disasm22 file.bin [options]
//   disasm22 file.bin --sym file.sym --dbg file.dbg
//   disasm22 file.bin --start 0x0030 --end 0x01BF
//   disasm22 file.bin -o output.asm
//
//   .sym / .dbg は指定がなければ file.bin から自動検出
//
// build: gcc -std=c99 -O2 -Wall disasm22.c -o disasm22

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <ctype.h>

// ============================================================
// 定数・グローバル
// ============================================================
#define MEM_SIZE  65536
#define MAX_SYM   2048
#define MAX_DBG   8192

typedef struct { uint16_t addr; char name[64];  } sym_t;
typedef struct { uint16_t addr; int  line; char text[128]; } dbg_t;

static uint8_t  mem[MEM_SIZE];
static uint16_t mem_loaded = 0;

static sym_t syms[MAX_SYM];  static int sym_count = 0;
static dbg_t dbgs[MAX_DBG];  static int dbg_count = 0;

static const char *regname[] = {
    "A","B","X","SP","PC","FLAGS","?6","?7",
    "?8","?9","?A","?B","?C","?D","?E","?F"
};

// ベクタテーブル（ISA2.2 §7.2）
static const struct { uint16_t addr; const char *name; } vec_tbl[] = {
    {0x0000,"reset"},{0x0002,"irq0"},{0x0004,"irq1"},
    {0x0006,"align"},{0x0008,"syscall"},
};
#define VEC_COUNT (int)(sizeof(vec_tbl)/sizeof(vec_tbl[0]))

// ============================================================
// ルックアップ
// ============================================================
static const char *sym_by_addr(uint16_t a) {
    for (int i = 0; i < sym_count; i++)
        if (syms[i].addr == a) return syms[i].name;
    return NULL;
}

/* 即値用: 小さな定数値（状態フラグ等）はシンボル解決しない */
#define SYM_ADDR_MIN_IMM  0x0010u
static const char *sym_by_imm(uint16_t a) {
    if (a < SYM_ADDR_MIN_IMM) return NULL;
    return sym_by_addr(a);
}

static const char *dbg_by_addr(uint16_t a) {
    for (int i = 0; i < dbg_count; i++)
        if (dbgs[i].addr == a) return dbgs[i].text;
    return NULL;
}

static const char *vec_name(uint16_t a) {
    for (int i = 0; i < VEC_COUNT; i++)
        if (vec_tbl[i].addr == a) return vec_tbl[i].name;
    return NULL;
}

// ============================================================
// ファイルロード
// ============================================================
static void load_bin(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) { perror(path); exit(1); }
    mem_loaded = (uint16_t)fread(mem, 1, MEM_SIZE, f);
    fclose(f);
}

static void load_sym(const char *path) {
    FILE *f = fopen(path, "r");
    if (!f) return;
    char line[128];
    while (sym_count < MAX_SYM && fgets(line, sizeof(line), f)) {
        unsigned addr; char name[64];
        if (sscanf(line, "%x %63s", &addr, name) == 2) {
            syms[sym_count].addr = (uint16_t)addr;
            snprintf(syms[sym_count].name, sizeof(syms[sym_count].name), "%s", name);
            sym_count++;
        }
    }
    fclose(f);
}

static void load_dbg(const char *path) {
    FILE *f = fopen(path, "r");
    if (!f) return;
    char line[256];
    while (dbg_count < MAX_DBG && fgets(line, sizeof(line), f)) {
        unsigned addr; int lineno; char text[128];
        int n = sscanf(line, "%x %d %127[^\n]", &addr, &lineno, text);
        if (n >= 2) {
            dbgs[dbg_count].addr = (uint16_t)addr;
            dbgs[dbg_count].line = lineno;
            if (n == 3) snprintf(dbgs[dbg_count].text, sizeof(dbgs[dbg_count].text), "%s", text);
            else        dbgs[dbg_count].text[0] = '\0';
            dbg_count++;
        }
    }
    fclose(f);
}

// ============================================================
// 命令デコード（1命令分をニーモニック文字列に変換）
// 戻り値: 命令バイト数
// ============================================================
static int decode(uint16_t pc, char *buf, size_t bsz) {
    uint8_t  op  = mem[pc];
    uint8_t  rb  = (pc+1 < MEM_SIZE) ? mem[(uint16_t)(pc+1)] : 0;
    /* imm: レジスタバイトあり命令 (pc+2 から) */
    uint16_t imm = (pc+2 < MEM_SIZE) ? (uint16_t)(mem[(uint16_t)(pc+2)]
                 | ((uint16_t)mem[(uint16_t)(pc+3)] << 8)) : 0;
    /* imm1: レジスタバイトなし命令 (pc+1 から) - 分岐/JSR/SYSCALL 用 */
    uint16_t imm1 = (pc+1 < MEM_SIZE) ? (uint16_t)(mem[(uint16_t)(pc+1)]
                  | ((uint16_t)mem[(uint16_t)(pc+2)] << 8)) : 0;
    uint8_t  rD = (rb >> 4) & 0xF;
    uint8_t  rS = rb & 0xF;

    /* 分岐ターゲット: (命令終端 pc+3) + rel16(imm1) */
    uint16_t bt = (uint16_t)((int16_t)(pc + 3) + (int16_t)imm1);

    // シンボル解決ヘルパー
    const char *ln = sym_by_imm(imm);          // レジスタ付き命令の即値用
    const char *bn = sym_by_addr(bt);          // 分岐ターゲット用
    const char *jn = sym_by_imm(imm1);         // JSR/SYSCALL絶対アドレス用

    // 即値・アドレスの文字列表現
    // is: レジスタ付き命令の #imm16   (imm = pc+2 から)
    // j1: JSR/SYSCALL の imm16        (imm1 = pc+1 から)
    char is[32], bs[32], as[32], j1[32];
    if (ln) snprintf(is, sizeof(is), "#$%s",    ln);
    else    snprintf(is, sizeof(is), "#$%04X",  imm);
    if (jn) snprintf(j1, sizeof(j1), "%s",      jn);
    else    snprintf(j1, sizeof(j1), "$%04X",   imm1);
    if (bn) snprintf(bs, sizeof(bs), "%s",      bn);
    else    snprintf(bs, sizeof(bs), "$%04X",   bt);
    if (sym_by_addr(imm)) snprintf(as, sizeof(as), "[%s]",    sym_by_addr(imm));
    else                  snprintf(as, sizeof(as), "[$%04X]", imm);

    switch (op) {
    // Control
    case 0x00: snprintf(buf,bsz,"NOP");                               return 1;
    case 0x01: snprintf(buf,bsz,"HALT");                              return 1;
    case 0x02: snprintf(buf,bsz,"EI");                                return 1;
    case 0x03: snprintf(buf,bsz,"DI");                                return 1;
    case 0x04: snprintf(buf,bsz,"IRET");                              return 1;
    case 0x05: snprintf(buf,bsz,"SYSCALL %s", j1);                    return 3;
    case 0x06: snprintf(buf,bsz,"BRK");                               return 1;
    // Data Transfer
    case 0x20: snprintf(buf,bsz,"MOV  %s, %s",  regname[rD],regname[rS]); return 2;
    case 0x21: snprintf(buf,bsz,"LDW  %s, %s",  regname[rD],is);          return 4;
    case 0x22: snprintf(buf,bsz,"LDW  %s, %s",  regname[rD],as);          return 4;
    case 0x23: snprintf(buf,bsz,"STW  %s, %s",  regname[rS],as);          return 4;
    case 0x24: snprintf(buf,bsz,"LDW  %s, [%s]",regname[rD],regname[rS]); return 2;
    case 0x25: snprintf(buf,bsz,"STW  %s, [%s]",regname[rS],regname[rD]); return 2;
    case 0x26: snprintf(buf,bsz,"LDW  %s, [X + %s]",regname[rD],is);      return 4;
    case 0x27: snprintf(buf,bsz,"STW  %s, [X + %s]",regname[rS],is);      return 4;
    // ALU (ISA2.0)
    case 0x40: snprintf(buf,bsz,"ADD  %s, %s",  regname[rD],regname[rS]); return 2;
    case 0x41: snprintf(buf,bsz,"ADDI %s, %s",  regname[rD],is);          return 4;
    case 0x42: snprintf(buf,bsz,"SUB  %s, %s",  regname[rD],regname[rS]); return 2;
    case 0x43: snprintf(buf,bsz,"SUBI %s, %s",  regname[rD],is);          return 4;
    case 0x44: snprintf(buf,bsz,"CMP  %s, %s",  regname[rD],regname[rS]); return 2;
    case 0x45: snprintf(buf,bsz,"CMPI %s, %s",  regname[rD],is);          return 4;
    // Bit Ops (ISA2.2)
    case 0x50: snprintf(buf,bsz,"AND  %s, %s",  regname[rD],regname[rS]); return 2;
    case 0x51: snprintf(buf,bsz,"ANDI %s, %s",  regname[rD],is);          return 4;
    case 0x52: snprintf(buf,bsz,"OR   %s, %s",  regname[rD],regname[rS]); return 2;
    case 0x53: snprintf(buf,bsz,"ORI  %s, %s",  regname[rD],is);          return 4;
    case 0x54: snprintf(buf,bsz,"XOR  %s, %s",  regname[rD],regname[rS]); return 2;
    case 0x55: snprintf(buf,bsz,"XORI %s, %s",  regname[rD],is);          return 4;
    case 0x56: snprintf(buf,bsz,"NOT  %s",       regname[rD]);             return 2;
    case 0x57: snprintf(buf,bsz,"SHL  %s, %s",  regname[rD],regname[rS]); return 2;
    case 0x58: snprintf(buf,bsz,"SHR  %s, %s",  regname[rD],regname[rS]); return 2;
    case 0x59: snprintf(buf,bsz,"SAR  %s, %s",  regname[rD],regname[rS]); return 2;
    // Branch
    case 0x60: snprintf(buf,bsz,"JMP  %s", bs);  return 3;
    case 0x61: snprintf(buf,bsz,"BEQ  %s", bs);  return 3;
    case 0x62: snprintf(buf,bsz,"BNE  %s", bs);  return 3;
    case 0x63: snprintf(buf,bsz,"BLT  %s", bs);  return 3;
    case 0x64: snprintf(buf,bsz,"BGE  %s", bs);  return 3;
    case 0x68:
        snprintf(buf,bsz,"JSR  %s", j1);
        return 3;
    case 0x69: snprintf(buf,bsz,"RET");  return 1;
    // EXT prefix
    case 0x1F: {
        uint8_t  sub = (pc+1 < MEM_SIZE) ? mem[(uint16_t)(pc+1)] : 0;
        uint16_t a16 = (pc+2 < MEM_SIZE) ? (uint16_t)(mem[(uint16_t)(pc+2)]
                     | ((uint16_t)mem[(uint16_t)(pc+3)] << 8)) : 0;
        const char *sn = sym_by_addr(a16);
        char es[32];
        if (sn) snprintf(es,sizeof(es),"[%s]",    sn);
        else    snprintf(es,sizeof(es),"[$%04X]",  a16);
        switch (sub) {
        case 0x00: snprintf(buf,bsz,"PUSH A");           return 2;
        case 0x01: snprintf(buf,bsz,"PUSH B");           return 2;
        case 0x02: snprintf(buf,bsz,"PUSH X");           return 2;
        case 0x03: snprintf(buf,bsz,"POP  A");           return 2;
        case 0x04: snprintf(buf,bsz,"POP  B");           return 2;
        case 0x05: snprintf(buf,bsz,"POP  X");           return 2;
        case 0x10: snprintf(buf,bsz,"LDB  A, %s", es);  return 4;
        case 0x11: snprintf(buf,bsz,"LDB  A, [X]");     return 2;
        case 0x12: snprintf(buf,bsz,"LDB  B, %s", es);  return 4;
        case 0x13: snprintf(buf,bsz,"LDB  B, [X]");     return 2;
        case 0x14: snprintf(buf,bsz,"STB  A, %s", es);  return 4;
        case 0x15: snprintf(buf,bsz,"STB  A, [X]");     return 2;
        case 0x16: snprintf(buf,bsz,"STB  B, %s", es);  return 4;
        case 0x17: snprintf(buf,bsz,"STB  B, [X]");     return 2;
        default:
            snprintf(buf,bsz,"; .db $1F, $%02X  ; unknown EXT sub=%02X", sub, sub);
            return 2;
        }
    }
    default:
        snprintf(buf,bsz,"; .db $%02X  ; unknown op=%02X", op, op);
        return 1;
    }
}

// ============================================================
// 命令サイズのみ返す（ギャップ判定用）
// ============================================================
/* instr_size: for future use */
static int instr_size(uint16_t pc) {
    char tmp[128];
    return decode(pc, tmp, sizeof(tmp));
}

// ============================================================
// 逆アセンブル本体
// ============================================================
static void disasm(FILE *out, uint16_t start, uint16_t end_a,
                   int with_equ) {
    // EQU定数ヘッダ（コード範囲外のシンボル）
    if (with_equ && sym_count > 0) {
        fprintf(out, "; --- EQU / symbol definitions ---\n");
        for (int i = 0; i < sym_count; i++) {
            uint16_t a = syms[i].addr;
            if (a < start || a > end_a) {
                fprintf(out, "%-20s EQU $%04X\n", syms[i].name, a);
            }
        }
        fprintf(out, "\n");
    }

    uint16_t pc       = start;
    uint16_t prev_end = start;
    int      first    = 1;

    while (pc <= end_a && pc < mem_loaded) {

        // ---- ゼロ埋め領域をスキップ ----
        if (pc == prev_end) {
            int zero_run = 0;
            while ((uint16_t)(pc + zero_run) < mem_loaded &&
                   (uint16_t)(pc + zero_run) <= end_a &&
                   mem[(uint16_t)(pc + zero_run)] == 0)
                zero_run++;
            if (zero_run >= 8) {
                uint16_t skip_end = (uint16_t)(pc + zero_run);
                for (uint16_t z = (uint16_t)(pc+1); z < skip_end; z++) {
                    if (sym_by_addr(z) || vec_name(z)) { skip_end = z; break; }
                }
                if (skip_end > pc + 1) {
                    // スキップして .org を強制出力（firstをリセット）
                    prev_end = skip_end;
                    pc       = skip_end;
                    first    = 1;   // 次のループで .org を出力させる
                    continue;
                }
            }
        }

        // ---- ギャップ / .org 出力 ----
        if (first || pc != prev_end) {
            if (!first) {
                // ギャップ内にゼロ以外のデータがあれば .db で出力
                int has_data = 0;
                for (uint16_t g = prev_end; g < pc && g < mem_loaded; g++)
                    if (mem[g]) { has_data = 1; break; }
                if (has_data) {
                    fprintf(out, "\n    .org $%04X\n", prev_end);
                    for (uint16_t g = prev_end; g < pc && g < mem_loaded; g++)
                        fprintf(out, "    DB   $%02X\n", mem[g]);
                }
            }
            fprintf(out, "\n    .org $%04X\n", pc);
            first = 0;
        }

        // ---- ベクタテーブルエントリ ----
        const char *vn = vec_name(pc);
        if (vn) {
            uint16_t haddr = (pc+1 < mem_loaded)
                ? (uint16_t)(mem[pc] | ((uint16_t)mem[(uint16_t)(pc+1)] << 8))
                : 0;
            const char *hn = sym_by_addr(haddr);
            if (hn) fprintf(out, "    .vector %-10s %s\n",    vn, hn);
            else    fprintf(out, "    .vector %-10s $%04X\n", vn, haddr);
            prev_end = (uint16_t)(pc + 2);
            pc       = (uint16_t)(pc + 2);
            continue;
        }

        // ---- ラベル出力 ----
        const char *lbl = sym_by_addr(pc);
        if (lbl) fprintf(out, "%s:\n", lbl);

        // ---- 命令デコード ----
        char mnem[128];
        int sz = decode(pc, mnem, sizeof(mnem));

        // バイト列
        char bytes[24] = "";
        for (int i = 0; i < sz && i < 5; i++) {
            char tmp[8];
            snprintf(tmp, sizeof(tmp), "%02X ", mem[(uint16_t)(pc+i)]);
            strncat(bytes, tmp, sizeof(bytes) - strlen(bytes) - 1);
        }

        // ソースコメント（.dbg）
        const char *ds = dbg_by_addr(pc);
        char sc[128] = "";
        if (ds && ds[0]) {
            snprintf(sc, sizeof(sc), "%s", ds);
            int slen = (int)strlen(sc);
            while (slen > 0 && (sc[slen-1]=='\n'||sc[slen-1]=='\r'||sc[slen-1]==' '))
                sc[--slen] = '\0';
        }

        if (sc[0])
            fprintf(out, "    %-28s ; [%04X] %s | %s\n", mnem, pc, bytes, sc);
        else
            fprintf(out, "    %-28s ; [%04X] %s\n",      mnem, pc, bytes);

        prev_end = (uint16_t)(pc + sz);
        pc       = (uint16_t)(pc + sz);
    }
}

// ============================================================
// main
// ============================================================
static void usage(const char *prog) {
    fprintf(stderr,
        "YSD8800 ISA2.2 Disassembler - disasm22 v1.00\n"
        "Usage: %s <file.bin> [options]\n"
        "Options:\n"
        "  --sym <file.sym>   Load symbol file  (auto-detect if omitted)\n"
        "  --dbg <file.dbg>   Load debug file   (auto-detect if omitted)\n"
        "  --start <hex>      Start address     (default: 0x0000)\n"
        "  --end   <hex>      End address       (default: end of file)\n"
        "  -o <file.asm>      Output file       (default: stdout)\n"
        "  --no-equ           Suppress EQU header block\n"
        "\nExamples:\n"
        "  %s kernel.asm.bin -o kernel_dis.asm\n"
        "  %s kernel.asm.bin --start 0x0030 --end 0x01BF\n",
        prog, prog, prog);
}

int main(int argc, char **argv) {
    if (argc < 2) { usage(argv[0]); return 1; }

    const char *binfile  = argv[1];
    const char *symfile  = NULL;
    const char *dbgfile  = NULL;
    const char *outfile  = NULL;
    uint16_t    start    = 0;
    uint16_t    end_addr = 0xFFFF;
    int         has_start = 0, has_end = 0;
    int         with_equ  = 1;

    for (int i = 2; i < argc; i++) {
        if      (!strcmp(argv[i],"--sym") && i+1<argc)   symfile  = argv[++i];
        else if (!strcmp(argv[i],"--dbg") && i+1<argc)   dbgfile  = argv[++i];
        else if (!strcmp(argv[i],"-o")    && i+1<argc)   outfile  = argv[++i];
        else if (!strcmp(argv[i],"--start") && i+1<argc) { start    = (uint16_t)strtoul(argv[++i],NULL,16); has_start=1; }
        else if (!strcmp(argv[i],"--end")   && i+1<argc) { end_addr = (uint16_t)strtoul(argv[++i],NULL,16); has_end=1; }
        else if (!strcmp(argv[i],"--no-equ")) with_equ = 0;
        else { fprintf(stderr,"Unknown option: %s\n",argv[i]); return 1; }
    }

    load_bin(binfile);

    // .sym / .dbg 自動検出
    char asym[512], adbg[512];
    if (!symfile) {
        snprintf(asym, sizeof(asym), "%s", binfile);
        char *e = strstr(asym, ".bin");
        if (e) { strcpy(e, ".sym"); symfile = asym; }
    }
    if (!dbgfile) {
        snprintf(adbg, sizeof(adbg), "%s", binfile);
        char *e = strstr(adbg, ".bin");
        if (e) { strcpy(e, ".dbg"); dbgfile = adbg; }
    }

    if (symfile) load_sym(symfile);
    if (dbgfile) load_dbg(dbgfile);

    if (!has_start) start    = 0;
    if (!has_end)   end_addr = (mem_loaded > 0) ? (uint16_t)(mem_loaded-1) : 0;

    FILE *out = stdout;
    if (outfile) {
        out = fopen(outfile, "w");
        if (!out) { perror(outfile); return 1; }
    }

    fprintf(out, "; disasm22 v1.00  ISA2.2 disassembler\n");
    fprintf(out, "; Binary: %s\n;\n\n", binfile);

    disasm(out, start, end_addr, with_equ);

    if (outfile) fclose(out);

    fprintf(stderr, "disasm22: %s [%04X-%04X]  sym=%d  dbg=%d%s\n",
            binfile, start, end_addr, sym_count, dbg_count,
            outfile ? "" : " (stdout)");
    return 0;
}
