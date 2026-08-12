/*
 * v6_sdread_test_poc.c   v0.1  (2026-07-20)
 *
 *  【目的】
 *    B-2: sd_sample.c 無改修のまま、read専用の最小テストCを scc23 で
 *    ビルドし、実SPI統合TB上で sd_read の512B取得＆案D 2回読み契約の
 *    保存を C 経由で確認する。
 *
 *  【契約の同一性（重要）】
 *    レジスタ定義($FCA0系)と2回読み契約(sd_wait_ready)は sd_sample.c
 *    L47-106 と同一。これにより「C経由でも案D 2回読み契約が保存される」
 *    ことを検証する。sd_sample.c 本体は一切改変しない(KY38/無改修死守)。
 *
 *  【検証枠組み(既存 tb_cpu_v6sdread と同一)】
 *    SDモデルは LBA=n に対し data[i]=(n*512+i)&0xFF を返す。
 *    LBA=1 なので期待値 = (512+i)&0xFF = i&0xFF。
 *    不一致数を MISM($0300)、最終結果を RESULT($0306) に書く。
 *    判定: RESULT==0 かつ MISM==0 で成功。
 */

/* ---- SDレジスタマップ (sd_sample.c L47-54 と同一) ---- */
#define REG_SD_CMD    0xFCA0
#define REG_SD_STAT   0xFCA2
#define REG_LBA_LO    0xFCA4
#define REG_LBA_HI    0xFCA6
#define REG_DATA      0xFCAA

/* ---- STATビット (sd_sample.c L57-59 と同一) ---- */
#define STAT_BUSY  1
#define STAT_ERROR 2
#define STAT_READY 4

/* ---- SDコマンド ---- */
#define CMD_READ_SETUP 0
#define CMD_EXEC       2

/* ---- TB照合用固定番地 (v6t_sdread.asm と同一) ---- */
#define ADDR_MISM    0x0300
#define ADDR_RESULT  0x0306

/*
 * sd_wait_ready - EXEC後のSTAT読み出し（案D 2回読み契約）
 *   sd_sample.c L97-106 と同一ロジック。
 *   1回目: BUSYラッチクリア (BUSY=1が返る)
 *   2回目: 実際のSTAT値
 *   ただし実バスは wait-state 環境のため、READY/ERROR が確定するまで
 *   ループで待つ（v6t_sdread.asm WAIT_RDY と同型）。
 *   戻り値: 0=READY成功 / 1=ERROR
 */
int sd_wait_ready(void) {
    int stat;
    int *p;
    p = (int *)REG_SD_STAT;
    stat = *p;               /* 1回目: BUSYラッチクリア */
    while (1) {
        stat = *p;           /* 2回目以降: 実STAT値 */
        if (stat & STAT_ERROR) { return 1; }
        if (stat & STAT_READY) { return 0; }
        /* BUSY継続 → wait-state 環境ではループ継続 */
    }
}

/*
 * sd_read - 1セクタ読み出し (512バイト)
 *   sd_sample.c L152- と同一の発行シーケンス。
 *   READ_SETUP → LBA設定 → EXEC → wait_ready → SD_DATA を512回読む。
 *   戻り値: 0=成功 / 1=失敗
 */
int sd_read(int lba, int lba_hi, int *buf) {
    int i;
    int *p;

    /* LBA設定 */
    p = (int *)REG_LBA_LO;  *p = lba;
    p = (int *)REG_LBA_HI;  *p = lba_hi;

    /* READ_SETUP → EXEC */
    p = (int *)REG_SD_CMD;  *p = CMD_READ_SETUP;
    p = (int *)REG_SD_CMD;  *p = CMD_EXEC;

    /* STAT待ち（案D 2回読み契約） */
    if (sd_wait_ready()) { return 1; }

    /* 512B を SD_DATA から連続読み（BUF_PTR自動++） */
    p = (int *)REG_DATA;
    i = 0;
    while (i < 512) {
        buf[i] = *p;
        i++;
    }
    return 0;
}

int rbuf[512];

int main(void) {
    int i;
    int mism;
    int *pm;
    int *pr;

    /* MISM=0 初期化 */
    mism = 0;

    /* LBA=1 を読む */
    if (sd_read(1, 0, rbuf)) {
        /* 読出エラー → RESULT=0xFFFF */
        pr = (int *)ADDR_RESULT;
        *pr = 0xFFFF;
        return 1;
    }

    /* 512B照合: 期待値 = i & 0xFF */
    i = 0;
    while (i < 512) {
        if ((rbuf[i] & 0xFF) != (i & 0xFF)) {
            mism = mism + 1;
        }
        i++;
    }

    /* MISM と RESULT を固定番地へ */
    pm = (int *)ADDR_MISM;
    *pm = mism;
    pr = (int *)ADDR_RESULT;
    *pr = mism;              /* 0なら全一致=成功 */

    return 0;
}
