#!/usr/bin/env python3
# add_binary_temp.py — 案B検証専用・使い捨て (KY28: 本番ツール無改変)
# 目的: 任意バイナリファイルを YuiFS disk の index=0 に格納する。
#       mkfs_yuifs v1.1 はファイル内容が固定("Hello,YUI OS!")のため、
#       Ph.5 Step4本体 ProcMgr経由ロード検証用に Cプロセスバイナリを載せる。
# 注意: これは検証用の暫定手段。恒久版は mkfs_yuifs v1.2 (--add-binary) で実装予定。
# 流用元: mkfs_yuifs_v1_1.py のフォーマット定数・関数(import)で一貫性を担保。

import sys, struct, math
import mkfs_yuifs_v1_1 as M   # フォーマット定数・関数を流用(KY:既存の動く実体に倣う)

def main():
    if len(sys.argv) != 4:
        print("usage: add_binary_temp.py <image> <name> <binfile>", file=sys.stderr)
        return 1
    image, name, binfile = sys.argv[1], sys.argv[2], sys.argv[3]

    # 名前バリデーション(mkfs v1.1と同基準: 1..15 ASCII)
    if not (1 <= len(name) <= 15):
        print(f"error: name length must be 1..15, got {len(name)}", file=sys.stderr)
        return 1
    name.encode("ascii")

    content = open(binfile, "rb").read()
    size = len(content)
    sec_count = math.ceil(size / M.SECTOR_SIZE)
    if sec_count < 1:
        print("error: empty binary", file=sys.stderr); return 1

    # ディスク総セクタ数: メタ4 + データ(sec_count + 余裕)。32KB(64sec)で十分。
    size_kb = 32
    total_sectors = size_kb * 2  # 64セクタ

    # スーパーブロック: file_count=1, next_free = DATA_START + sec_count
    sb = bytearray(M.SECTOR_SIZE)
    struct.pack_into(f"{len(M.FS_MAGIC)}s", sb, M.SB_MAGIC_OFS, M.FS_MAGIC)
    struct.pack_into("B",  sb, M.SB_VER_MAJOR_OFS, M.FS_VER_MAJOR)
    struct.pack_into("B",  sb, M.SB_VER_MINOR_OFS, M.FS_VER_MINOR)
    struct.pack_into("<H", sb, M.SB_SECSIZE_OFS,   M.SECTOR_SIZE)
    struct.pack_into("<H", sb, M.SB_TOTAL_SEC_OFS, total_sectors)
    struct.pack_into("<H", sb, M.SB_DIR_START_OFS, M.DIR_START)
    struct.pack_into("<H", sb, M.SB_DIR_SEC_OFS,   M.DIR_SECTORS)
    struct.pack_into("<H", sb, M.SB_DIR_ENT_OFS,   M.DIR_ENTRIES)
    struct.pack_into("<H", sb, M.SB_DATA_START_OFS,M.DATA_START)
    struct.pack_into("<H", sb, M.SB_DATA_SEC_OFS,  total_sectors - M.DATA_START)
    struct.pack_into("<H", sb, M.SB_NEXT_FREE_OFS, M.DATA_START + sec_count)
    struct.pack_into("<H", sb, M.SB_FILE_COUNT_OFS, 1)

    # ディレクトリ: index=0 に name 登録
    dir_bytes = bytearray(M.DIR_SECTORS * M.SECTOR_SIZE)
    nb = name.encode("ascii")
    dir_bytes[M.DE_NAME_OFS : M.DE_NAME_OFS + len(nb)] = nb
    struct.pack_into("<I", dir_bytes, M.DE_SIZE_OFS,      size)            # u32 size
    struct.pack_into("<H", dir_bytes, M.DE_START_SEC_OFS, M.DATA_START)    # start_sec=4
    struct.pack_into("<H", dir_bytes, M.DE_SEC_COUNT_OFS, sec_count)       # sec_count
    struct.pack_into("<H", dir_bytes, M.DE_FLAGS_OFS,     M.FLG_USED)      # USED

    # 書き出し: SB(1) + DIR(3) + データ(content をセクタ境界詰め + 残り0)
    with open(image, "wb") as f:
        f.write(bytes(sb))
        f.write(bytes(dir_bytes))
        # データ領域先頭に content を sec_count セクタ分(512B境界padding)
        padded = bytearray(sec_count * M.SECTOR_SIZE)
        padded[:size] = content
        f.write(bytes(padded))
        # 残りデータセクタを0埋め
        remain = (total_sectors - M.DATA_START) - sec_count
        for _ in range(remain):
            f.write(bytes(M.SECTOR_SIZE))

    print(f"add_binary_temp: '{name}' size={size}B sec_count={sec_count} "
          f"start_sec={M.DATA_START} -> {image}")
    print(f"  total={total_sectors}sec ({size_kb}KB), next_free={M.DATA_START+sec_count}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
