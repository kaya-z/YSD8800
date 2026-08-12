/* ================================================================
 * v8_catls_demo_poc.c   v0.1  (2026-07-20)
 *   V8 YUI OS統合（選択肢A / A-1: read専用 cat/ls デモ）
 *
 *   目的:
 *     mkfs_yuifs が書いた YUIFS イメージを、実SPI経由(sd_read)で読み、
 *     ls（ファイル名一覧）と cat（ファイル内容）を UART 出力する。
 *     書込(CMD24)は一切行わない。
 *
 *   契約保存(KY38):
 *     sd_read / sd_wait_ready / putchar は sd_sample.c と同一
 *     （$FCA0系レジスタ・案D 2回読み契約・UART $FC80）。ハードコード無し。
 *
 *   YUIFS レイアウト（mkfs_yuifs_v1_1.py と同一・KY34確認済）:
 *     sector0 = superblock  (magic "YUIFS\0\0\0", +18 dir_entries,
 *                            +20 data_start, +26 file_count)
 *     sector1..3 = directory (32 entries * 48B)
 *       DE: +0 name[16] / +16 size(u32) / +20 start_sec(u16)
 *           +22 sec_count(u16) / +24 flags(u16, bit0=USED)
 *     sector4.. = data
 *
 *   注意: scc23 は char/構造体が弱いため、512B セクタを int 配列
 *     (rbuf[512], 1要素=1バイト) で受ける sd_sample.c 方式を踏襲。
 *     マルチバイト値は下位/上位を手動合成する。
 *
 *   設計レビュー: v8_catls_integ_design_review_reply_v1_0.md (承認)
 * ================================================================ */

/* ---- UART ---- */
#define UART_TX   0xFC80

/* ---- YSD8003 MMIO（sd_sample.c と同一） ---- */
#define REG_SD_CMD    0xFCA0
#define REG_SD_STAT   0xFCA2
#define REG_LBA_LO    0xFCA4
#define REG_LBA_HI    0xFCA6
#define REG_DATA      0xFCAA

/* ---- SD_STAT ビット ---- */
#define STAT_BUSY  1
#define STAT_ERROR 2
#define STAT_READY 4

/* ---- SD_CMD ---- */
#define CMD_READ_SETUP 0
#define CMD_EXEC       2

/* ---- 結果番地（TB照合用・CHAT111方式） ---- */
#define ADDR_RESULT  0x0306

/* ---- YUIFS 定数 ---- */
#define SB_DIR_ENTRIES_OFS  18
#define SB_DATA_START_OFS   20
#define SB_FILE_COUNT_OFS   26
#define DE_SIZE             48
#define DE_NAME_OFS         0
#define DE_FSIZE_OFS        16
#define DE_START_SEC_OFS    20
#define DE_FLAGS_OFS        24
#define FLG_USED            1
#define DIR_START_SEC       1
#define DIR_SECTORS         3

/* ---- 512要素セクタバッファ（1要素=1バイト） ---- */
int secbuf[512];

/* ================================================================
 * UART出力（sd_sample.c と同一）
 * ================================================================ */
int putchar(int c) {
    int *p;
    p = (int *)UART_TX;
    *p = c;
    return c;
}

void puts_n(int *s, int n) {
    int i;
    i = 0;
    while (i < n) {
        putchar(s[i]);
        i++;
    }
}

/* ================================================================
 * sd_wait_ready - EXEC後のSTAT読み出し（案D 2回読み契約・無改修流用）
 * ================================================================ */
int sd_wait_ready(void) {
    int stat;
    int *p;
    p = (int *)REG_SD_STAT;
    /* 1回目 */
    stat = *p;
    /* 2回目（案D 契約: 2回読みで確定） */
    stat = *p;
    while ((stat & STAT_READY) == 0) {
        if (stat & STAT_ERROR) { return 1; }
        stat = *p;
    }
    return 0;
}

/* ================================================================
 * sd_read - 1セクタ(512B)読出（sd_sample.c と同一契約）
 * ================================================================ */
int sd_read(int lba, int lba_hi, int *buf) {
    int i;
    int *p;
    p = (int *)REG_LBA_LO;  *p = lba;
    p = (int *)REG_LBA_HI;  *p = lba_hi;
    p = (int *)REG_SD_CMD;  *p = CMD_READ_SETUP;
    p = (int *)REG_SD_CMD;  *p = CMD_EXEC;
    if (sd_wait_ready()) { return 1; }
    p = (int *)REG_DATA;
    i = 0;
    while (i < 512) {
        buf[i] = *p;
        i++;
    }
    return 0;
}

/* ================================================================
 * u16合成: buf[ofs] | (buf[ofs+1]<<8)  （リトルエンディアン）
 * ================================================================ */
int rd_u16(int *buf, int ofs) {
    return buf[ofs] | (buf[ofs + 1] << 8);
}

/* ================================================================
 * ls: dirセクタ(1..3)を走査し、USEDエントリのnameを出力
 *   name[16] は NUL終端まで出力（strlen的・レビュー依頼5明確化）
 * ================================================================ */
void fs_list(void) {
    int sec;
    int de;
    int base;
    int flags;
    int j;
    int ch;
    /* "ls:\n" */
    putchar('l'); putchar('s'); putchar(':'); putchar('\n');

    sec = 0;
    while (sec < DIR_SECTORS) {
        sd_read(DIR_START_SEC + sec, 0, secbuf);
        /* 1セクタ=512B に 48B エントリが最大10個 (512/48=10) */
        de = 0;
        while (de + DE_SIZE <= 512) {
            base = de;
            flags = rd_u16(secbuf, base + DE_FLAGS_OFS);
            if (flags & FLG_USED) {
                /* name[16] を NUL まで出力 */
                j = 0;
                while (j < 16) {
                    ch = secbuf[base + DE_NAME_OFS + j];
                    if (ch == 0) { j = 16; }   /* break相当 */
                    else { putchar(ch); j++; }
                }
                putchar('\n');
            }
            de = de + DE_SIZE;
        }
        sec++;
    }
}

/* ================================================================
 * name一致判定: secbuf内DEのnameと target を比較
 *   一致=1, 不一致=0
 * ================================================================ */
int name_match(int *buf, int base, int *target, int tlen) {
    int j;
    int ch;
    j = 0;
    while (j < tlen) {
        ch = buf[base + DE_NAME_OFS + j];
        if (ch != target[j]) { return 0; }
        j++;
    }
    /* target末尾の次がNULか（完全一致確認） */
    if (buf[base + DE_NAME_OFS + tlen] != 0) { return 0; }
    return 1;
}

/* ================================================================
 * cat: dir走査でtarget一致DEを見つけ、start_sec/size を得て
 *   そのセクタを読み size分 UART出力
 *   戻り: 0=成功, 1=未検出
 * ================================================================ */
int fs_cat(int *target, int tlen) {
    int sec;
    int de;
    int base;
    int flags;
    int start_sec;
    int fsize;
    int i;

    sec = 0;
    while (sec < DIR_SECTORS) {
        sd_read(DIR_START_SEC + sec, 0, secbuf);
        de = 0;
        while (de + DE_SIZE <= 512) {
            base = de;
            flags = rd_u16(secbuf, base + DE_FLAGS_OFS);
            if (flags & FLG_USED) {
                if (name_match(secbuf, base, target, tlen)) {
                    start_sec = rd_u16(secbuf, base + DE_START_SEC_OFS);
                    fsize     = rd_u16(secbuf, base + DE_FSIZE_OFS);
                    /* データセクタ読出（size<=512前提・本デモ範囲） */
                    sd_read(start_sec, 0, secbuf);
                    i = 0;
                    while (i < fsize) {
                        putchar(secbuf[i]);
                        i++;
                    }
                    return 0;
                }
            }
            de = de + DE_SIZE;
        }
        sec++;
    }
    return 1;
}

/* ================================================================
 * main
 * ================================================================ */
int main(void) {
    int *pr;
    int rc;
    /* target = "HELLO.TXT" (9文字)。scc23向けに1文字ずつint配列で保持 */
    int tgt[9];
    tgt[0]='H'; tgt[1]='E'; tgt[2]='L'; tgt[3]='L'; tgt[4]='O';
    tgt[5]='.'; tgt[6]='T'; tgt[7]='X'; tgt[8]='T';

    /* ls */
    fs_list();

    /* "cat HELLO.TXT:\n" */
    putchar('c'); putchar('a'); putchar('t'); putchar(' ');
    putchar('H'); putchar('E'); putchar('L'); putchar('L'); putchar('O');
    putchar('.'); putchar('T'); putchar('X'); putchar('T');
    putchar(':'); putchar('\n');

    /* cat HELLO.TXT */
    rc = fs_cat(tgt, 9);

    /* 結果番地（TB照合の補助・0=cat成功） */
    pr = (int *)ADDR_RESULT;
    *pr = rc;

    return 0;
}
