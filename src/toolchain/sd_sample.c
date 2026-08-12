/*
 * sd_sample.c - YSD8003 ストレージコントローラ サンプルプログラム
 * Version: 1.00 (2026-04-19)
 *
 * 対象: YSD8800 ISA2.3 / emu23 v1.01
 * 設計書: emu23_device_design_v1_2.docx
 *
 * 動作内容:
 *   TEST1: LBA0 書き込み（パターン: i & 0xFF）・読み出し全バイト照合
 *   TEST2: LBA0 先頭・末尾バイト値確認（0x00, 0x01, 0xFF等）
 *   TEST3: LBA1 別パターン（0xAA固定）書き込み・読み出し照合
 *   TEST4: LBA0とLBA1の独立性確認（LBA1書き込み後にLBA0再読み出し）
 *
 * ビルド手順:
 *   ./scc23 -o sd_sample.asm sd_sample.c
 *   ./hasm23 sd_sample.asm
 *   python3 -c "
 *   mem=bytearray(65536)
 *   with open('sd_sample.asm.bin','rb') as f: c=f.read()
 *   for i,b in enumerate(c): mem[i]=b
 *   with open('startup_harness23.asm.bin','rb') as f: h=f.read()
 *   for i,b in enumerate(h): mem[i]=b
 *   open('sd_sample_final.bin','wb').write(mem)
 *   "
 *   dd if=/dev/zero of=disk.img bs=512 count=2048
 *   ./emu23 sd_sample_final.bin -q --disk disk.img
 *
 * YSD8003 MMIOアドレスマップ:
 *   $FCA0  SD_CMD  : 0=READ_SETUP / 1=WRITE_SETUP / 2=EXEC
 *   $FCA2  SD_STAT : bit0=BUSY / bit1=ERROR / bit2=READY
 *   $FCA4  LBA_LO  : LBAアドレス下位16bit
 *   $FCA6  LBA_HI  : LBAアドレス上位16bit
 *   $FCA8  BUF_PTR : バッファポインタ (0-511, EXEC時自動リセット)
 *   $FCAA  DATA    : PIOデータ 8bit (読み書きでBUF_PTR自動++)
 *   $FCAE  DISK_LO : 総セクタ数下位16bit (読み出し専用)
 *   $FCB0  DISK_HI : 総セクタ数上位16bit (読み出し専用)
 *
 * BUSYラッチ方式:
 *   EXEC発行  -> 1回目STAT読み出し = BUSY=1 (ラッチクリア)
 *   2回目以降 -> BUSY=0, bit2=READY or bit1=ERROR
 */

/* ---- UART ---- */
#define UART_TX   0xFC80

/* ---- YSD8003 MMIO ---- */
#define REG_SD_CMD    0xFCA0
#define REG_SD_STAT   0xFCA2
#define REG_LBA_LO    0xFCA4
#define REG_LBA_HI    0xFCA6
#define REG_BUF_PTR   0xFCA8
#define REG_DATA      0xFCAA
#define REG_DISK_LO   0xFCAE
#define REG_DISK_HI   0xFCB0

/* ---- SD_STAT ビット ---- */
#define STAT_BUSY  1
#define STAT_ERROR 2
#define STAT_READY 4

/* ---- バッファ (グローバル・512要素) ---- */
int wbuf[512];
int rbuf[512];

/* ================================================================
 * UART出力ユーティリティ
 * ================================================================ */
int putchar(int c) {
    int *p;
    p = (int *)UART_TX;
    *p = c;
    return c;
}

void put_hex8(int v) {
    int h;
    int l;
    h = (v >> 4) & 15;
    l = v & 15;
    if (h < 10) { putchar('0' + h); } else { putchar('A' + h - 10); }
    if (l < 10) { putchar('0' + l); } else { putchar('A' + l - 10); }
}

void put_dec(int v) {
    if (v >= 10) { put_dec(v / 10); }
    putchar('0' + v % 10);
}

/* ================================================================
 * YSD8003 ドライバ
 * ================================================================ */

/*
 * sd_wait_ready - EXEC後のSTAT読み出し（BUSYラッチ方式）
 * 戻り値: 0=READY成功 / 1=ERROR
 */
int sd_wait_ready(void) {
    int stat;
    int *p;
    p = (int *)REG_SD_STAT;
    stat = *p;               /* 1回目: BUSYラッチクリア (BUSY=1が返る) */
    stat = *p;               /* 2回目: 実際のSTAT値 */
    if (stat & STAT_ERROR) { return 1; }
    if (stat & STAT_READY) { return 0; }
    return 1;                /* READYもERRORも無い = 異常 */
}

/*
 * sd_write - 1セクタ書き込み (512バイト)
 * 引数:
 *   lba    - LBAアドレス下位16bit
 *   lba_hi - LBAアドレス上位16bit
 *   buf    - 書き込みデータ (int配列512要素, 下位8bitのみ使用)
 * 戻り値: 0=成功 / 1=失敗
 */
int sd_write(int lba, int lba_hi, int *buf) {
    int i;
    int *p;

    /* LBAアドレス設定 */
    p = (int *)REG_LBA_LO;  *p = lba;
    p = (int *)REG_LBA_HI;  *p = lba_hi;

    /* WRITE_SETUP */
    p = (int *)REG_SD_CMD;  *p = 1;

    /* BUF_PTR明示リセット */
    p = (int *)REG_BUF_PTR; *p = 0;

    /* データ転送 (PIO 8bit x 512) */
    p = (int *)REG_DATA;
    i = 0;
    while (i < 512) {
        *p = buf[i] & 255;
        i++;
    }

    /* EXEC発行 */
    p = (int *)REG_SD_CMD;  *p = 2;

    return sd_wait_ready();
}

/*
 * sd_read - 1セクタ読み出し (512バイト)
 * 引数:
 *   lba    - LBAアドレス下位16bit
 *   lba_hi - LBAアドレス上位16bit
 *   buf    - 読み出し先バッファ (int配列512要素)
 * 戻り値: 0=成功 / 1=失敗
 */
int sd_read(int lba, int lba_hi, int *buf) {
    int i;
    int *p;

    /* LBAアドレス設定 */
    p = (int *)REG_LBA_LO;  *p = lba;
    p = (int *)REG_LBA_HI;  *p = lba_hi;

    /* READ_SETUP */
    p = (int *)REG_SD_CMD;  *p = 0;

    /* EXEC発行 */
    p = (int *)REG_SD_CMD;  *p = 2;

    if (sd_wait_ready()) { return 1; }

    /* データ受信 (EXECでBUF_PTR自動リセット済み) */
    p = (int *)REG_DATA;
    i = 0;
    while (i < 512) {
        buf[i] = *p & 255;
        i++;
    }
    return 0;
}

/* ================================================================
 * テスト補助
 * ================================================================ */

/* テスト番号付きPASS/FAILを出力し pass を更新 */
int report(int testnum, int ok, int pass) {
    putchar('T');
    put_dec(testnum);
    putchar(':');
    if (ok) {
        putchar('P'); putchar('A'); putchar('S'); putchar('S');
        pass++;
    } else {
        putchar('F'); putchar('A'); putchar('I'); putchar('L');
    }
    putchar('\n');
    return pass;
}

/* ================================================================
 * main
 * ================================================================ */
int main(void) {
    int i;
    int ok;
    int pass;
    int disk_lo;
    int disk_hi;
    int *p;

    pass = 0;

    /* ---- ディスク情報表示 ---- */
    p = (int *)REG_DISK_LO;  disk_lo = *p;
    p = (int *)REG_DISK_HI;  disk_hi = *p;

    putchar('D'); putchar('I'); putchar('S'); putchar('K');
    putchar(':');
    if (disk_hi > 0) { put_dec(disk_hi); }
    put_dec(disk_lo);
    putchar('s'); putchar('e'); putchar('c'); putchar('\n');

    if (disk_lo == 0 && disk_hi == 0) {
        /* --disk オプション未指定またはディスク未接続 */
        putchar('E'); putchar('R'); putchar('R');
        putchar(':'); putchar('N'); putchar('O');
        putchar('D'); putchar('I'); putchar('S'); putchar('K');
        putchar('\n');
        return 1;
    }

    /* ================================================================
     * TEST1: LBA0 書き込み・読み出し全バイト照合
     *   書き込みパターン: wbuf[i] = i & 0xFF (0x00〜0xFF繰り返し)
     * ================================================================ */
    i = 0;
    while (i < 512) { wbuf[i] = i & 255; i++; }

    ok = 0;
    if (sd_write(0, 0, wbuf) == 0) {
        if (sd_read(0, 0, rbuf) == 0) {
            ok = 1;
            i = 0;
            while (i < 512) {
                if (rbuf[i] != (i & 255)) { ok = 0; }
                i++;
            }
        }
    }
    pass = report(1, ok, pass);

    /* ================================================================
     * TEST2: LBA0 先頭・末尾バイト値確認
     *   rbuf[0]=0x00, rbuf[1]=0x01, rbuf[2]=0x02, rbuf[3]=0x03
     *   rbuf[255]=0xFF, rbuf[256]=0x00(折り返し), rbuf[511]=0xFF
     * ================================================================ */
    ok = 1;
    if (rbuf[0]   != 0)   { ok = 0; }
    if (rbuf[1]   != 1)   { ok = 0; }
    if (rbuf[2]   != 2)   { ok = 0; }
    if (rbuf[3]   != 3)   { ok = 0; }
    if (rbuf[255] != 255) { ok = 0; }
    if (rbuf[256] != 0)   { ok = 0; }  /* 0x100 & 0xFF = 0x00 */
    if (rbuf[511] != 255) { ok = 0; }  /* 0x1FF & 0xFF = 0xFF */
    pass = report(2, ok, pass);

    /* FAILした場合は先頭8バイトを16進ダンプ */
    if (ok == 0) {
        putchar('[');
        i = 0;
        while (i < 8) { put_hex8(rbuf[i]); putchar(' '); i++; }
        putchar(']'); putchar('\n');
    }

    /* ================================================================
     * TEST3: LBA1 別パターン（0xAA固定）書き込み・読み出し照合
     * ================================================================ */
    i = 0;
    while (i < 512) { wbuf[i] = 170; i++; }  /* 0xAA = 170 */

    ok = 0;
    if (sd_write(1, 0, wbuf) == 0) {
        if (sd_read(1, 0, rbuf) == 0) {
            ok = 1;
            i = 0;
            while (i < 512) {
                if (rbuf[i] != 170) { ok = 0; }
                i++;
            }
        }
    }
    pass = report(3, ok, pass);

    /* ================================================================
     * TEST4: LBA0/LBA1 独立性確認
     *   LBA1に0xAAを書いた後でLBA0を再読み出しし、
     *   LBA0のデータ（i&0xFF）が保たれていることを確認
     * ================================================================ */
    ok = 0;
    if (sd_read(0, 0, rbuf) == 0) {
        ok = 1;
        i = 0;
        while (i < 512) {
            if (rbuf[i] != (i & 255)) { ok = 0; }
            i++;
        }
    }
    pass = report(4, ok, pass);

    /* ================================================================
     * 最終サマリ
     * ================================================================ */
    putchar('\n');
    put_dec(pass); putchar('/'); putchar('4'); putchar(' ');
    if (pass == 4) {
        putchar('A'); putchar('L'); putchar('L');
        putchar('P'); putchar('A'); putchar('S'); putchar('S');
    } else {
        putchar('F'); putchar('A'); putchar('I'); putchar('L');
        putchar('E'); putchar('D');
    }
    putchar('\n');

    return 0;
}
