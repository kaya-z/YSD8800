#!/usr/bin/env python3
# mkfs_yuifs.py — YUI OS フラットFS ディスクイメージ初期化ツール
# Version 1.0 / 2026-05-23
# 対応FS: YUI OS Phase 1 フラットFS (ver_major=1, ver_minor=1)
# 上位設計: yuios_ph4_filemgr_design_v1_2.md §3, §7
# 設計書:   mkfs_yuifs_design_memo_v1_1.md
#
# 改版履歴:
#   v1.0  2026-05-23  初版 (設計メモ v1.1 を反映して実装)

"""
YUI OS フラットFS ディスクイメージ初期化ツール

使い方:
    mkfs_yuifs.py <image_file> [--size-kb N] [-v|--verbose]

例:
    python3 mkfs_yuifs.py disk.img                 # 1024 KB (1MB) で作成
    python3 mkfs_yuifs.py disk.img --size-kb 32 -v # 32 KB, 詳細出力
"""

import sys
import struct
import argparse


# ============================================================
# バージョン情報
# ============================================================
MKFS_VERSION = "1.0"


# ============================================================
# FS フォーマット定数 (設計書 §3.2 / §3.6 と一致)
# ============================================================
SECTOR_SIZE        = 512
FS_VER_MAJOR       = 1
FS_VER_MINOR       = 1
FS_MAGIC           = b"YUIFS\x00\x00\x00"   # 8B
DIR_START          = 1
DIR_SECTORS        = 3
DIR_ENTRIES        = 32
DATA_START         = 4
DE_SIZE            = 48

# スーパーブロック内オフセット (設計書 §3.6 対照表と完全一致)
SB_MAGIC_OFS       = 0
SB_VER_MAJOR_OFS   = 8
SB_VER_MINOR_OFS   = 9
SB_SECSIZE_OFS     = 10
SB_TOTAL_SEC_OFS   = 12
SB_DIR_START_OFS   = 14
SB_DIR_SEC_OFS     = 16
SB_DIR_ENT_OFS     = 18
SB_DATA_START_OFS  = 20
SB_DATA_SEC_OFS    = 22
SB_NEXT_FREE_OFS   = 24
SB_FILE_COUNT_OFS  = 26

# サイズ制約 (設計メモ v1.1 §2.1)
MIN_SIZE_KB        = 8           # メタ4セクタ + データ最低12セクタ
MAX_SIZE_KB        = 32767       # u16範囲 (65534セクタ) ・1KB境界
DEFAULT_SIZE_KB    = 1024        # デフォルト 1MB
MIN_SECTORS        = MIN_SIZE_KB * 2
MAX_SECTORS        = MAX_SIZE_KB * 2


# ============================================================
# 自己検証 (kaizen原則26: 設計書⇔実装定数 対照表の起動時チェック)
# ============================================================
def _self_check():
    """定数間の整合を起動時に検査。設計書改版時の定数取り違えバグを即検出。"""
    # マジック長さ
    assert len(FS_MAGIC) == 8, "FS_MAGIC must be 8 bytes"
    # スーパーブロックオフセット (§3.6 対照表と一致)
    assert SB_MAGIC_OFS == 0
    assert SB_VER_MAJOR_OFS == 8
    assert SB_VER_MINOR_OFS == 9
    assert SB_SECSIZE_OFS == 10
    assert SB_TOTAL_SEC_OFS == 12
    assert SB_DIR_START_OFS == 14
    assert SB_DIR_SEC_OFS == 16
    assert SB_DIR_ENT_OFS == 18
    assert SB_DATA_START_OFS == 20
    assert SB_DATA_SEC_OFS == 22
    assert SB_NEXT_FREE_OFS == 24
    assert SB_FILE_COUNT_OFS == 26
    # FS構造の整合
    assert DE_SIZE == 48
    assert DIR_SECTORS * SECTOR_SIZE >= DIR_ENTRIES * DE_SIZE, \
        f"DIR area {DIR_SECTORS * SECTOR_SIZE}B < entries {DIR_ENTRIES * DE_SIZE}B"
    # サイズ制約
    assert MIN_SECTORS >= DATA_START + 1, "MIN_SECTORS must leave at least 1 data sector"
    assert MAX_SECTORS <= 65535, "MAX_SECTORS must fit in u16"
    # データ領域開始LBA
    assert DATA_START == DIR_START + DIR_SECTORS, \
        f"DATA_START({DATA_START}) must equal DIR_START({DIR_START}) + DIR_SECTORS({DIR_SECTORS})"


# ============================================================
# 引数解析
# ============================================================
def parse_args():
    """コマンドライン引数を解析。範囲外は ValueError で exit(1)。"""
    parser = argparse.ArgumentParser(
        prog="mkfs_yuifs.py",
        description="YUI OS flat FS disk image formatter",
        add_help=True,
    )
    parser.add_argument(
        "image_file",
        help="output disk image file path",
    )
    parser.add_argument(
        "--size-kb",
        type=int,
        default=DEFAULT_SIZE_KB,
        metavar="N",
        help=f"disk size in KB (default: {DEFAULT_SIZE_KB}, "
             f"range: {MIN_SIZE_KB}..{MAX_SIZE_KB})",
    )
    parser.add_argument(
        "-v", "--verbose",
        action="store_true",
        help="verbose output (dump fields after formatting)",
    )
    args = parser.parse_args()

    # 範囲チェック (K7: 引数パース失敗対策)
    if args.size_kb < MIN_SIZE_KB or args.size_kb > MAX_SIZE_KB:
        raise ValueError(
            f"--size-kb {args.size_kb} out of range "
            f"[{MIN_SIZE_KB}..{MAX_SIZE_KB}]"
        )

    return args


# ============================================================
# スーパーブロック構築 (リトルエンディアン書込)
# ============================================================
def build_superblock(total_sectors):
    """設計書 §3.2 の仕様で 512B のスーパーブロックバイト列を生成。
       全フィールドはリトルエンディアン (struct '<H' / '<I')。"""

    sb = bytearray(SECTOR_SIZE)   # 512B 全0で初期化

    # +0..+7: magic (8B)
    struct.pack_into(f"{len(FS_MAGIC)}s", sb, SB_MAGIC_OFS, FS_MAGIC)

    # +8: ver_major (1B)
    struct.pack_into("B", sb, SB_VER_MAJOR_OFS, FS_VER_MAJOR)

    # +9: ver_minor (1B)
    struct.pack_into("B", sb, SB_VER_MINOR_OFS, FS_VER_MINOR)

    # +10..+11: sector_size (2B LE)
    struct.pack_into("<H", sb, SB_SECSIZE_OFS, SECTOR_SIZE)

    # +12..+13: total_sectors (2B LE)
    struct.pack_into("<H", sb, SB_TOTAL_SEC_OFS, total_sectors)

    # +14..+15: dir_start (2B LE)
    struct.pack_into("<H", sb, SB_DIR_START_OFS, DIR_START)

    # +16..+17: dir_sectors (2B LE)
    struct.pack_into("<H", sb, SB_DIR_SEC_OFS, DIR_SECTORS)

    # +18..+19: dir_entries (2B LE)
    struct.pack_into("<H", sb, SB_DIR_ENT_OFS, DIR_ENTRIES)

    # +20..+21: data_start (2B LE)
    struct.pack_into("<H", sb, SB_DATA_START_OFS, DATA_START)

    # +22..+23: data_sectors (2B LE)
    data_sectors = total_sectors - DATA_START
    struct.pack_into("<H", sb, SB_DATA_SEC_OFS, data_sectors)

    # +24..+25: next_free_sec (2B LE) — 初期値はデータ領域先頭
    struct.pack_into("<H", sb, SB_NEXT_FREE_OFS, DATA_START)

    # +26..+27: file_count (2B LE) — 初期値0
    struct.pack_into("<H", sb, SB_FILE_COUNT_OFS, 0)

    # +28以降は全0のまま (予約領域)

    assert len(sb) == SECTOR_SIZE
    return bytes(sb)


# ============================================================
# イメージ書き出し
# ============================================================
def write_image(path, total_sectors, sb_bytes, verbose=False):
    """ディスクイメージをファイルへ書き出す。
       構成: SB(1) + ディレクトリ0埋め(3) + データ領域0埋め(残り)
       OSError は呼出元で捕捉。"""

    zero_sector = bytes(SECTOR_SIZE)   # 512B 全0

    with open(path, "wb") as f:
        # LBA 0: スーパーブロック
        f.write(sb_bytes)

        # LBA 1..3: ディレクトリ領域 (3セクタを0埋め)
        for _ in range(DIR_SECTORS):
            f.write(zero_sector)

        # LBA 4..(total_sectors-1): データ領域 (0埋め物理書出)
        data_sec_count = total_sectors - DATA_START
        for _ in range(data_sec_count):
            f.write(zero_sector)

    written_bytes = total_sectors * SECTOR_SIZE
    if verbose:
        print(f"Total written: {written_bytes} bytes")


# ============================================================
# 詳細出力 (-v時) — フィールドダンプ
# ============================================================
def verify_image(path, total_sectors):
    """書き出したイメージを読み戻してフィールドをダンプ。-v時のみ。"""
    with open(path, "rb") as f:
        sb = f.read(SECTOR_SIZE)
    assert len(sb) == SECTOR_SIZE, f"Failed to read superblock: got {len(sb)}B"

    # 各フィールドを読み戻し (LE)
    magic        = sb[SB_MAGIC_OFS:SB_MAGIC_OFS + 8]
    ver_major    = sb[SB_VER_MAJOR_OFS]
    ver_minor    = sb[SB_VER_MINOR_OFS]
    sector_size  = struct.unpack_from("<H", sb, SB_SECSIZE_OFS)[0]
    total_sec    = struct.unpack_from("<H", sb, SB_TOTAL_SEC_OFS)[0]
    dir_start    = struct.unpack_from("<H", sb, SB_DIR_START_OFS)[0]
    dir_sectors  = struct.unpack_from("<H", sb, SB_DIR_SEC_OFS)[0]
    dir_entries  = struct.unpack_from("<H", sb, SB_DIR_ENT_OFS)[0]
    data_start   = struct.unpack_from("<H", sb, SB_DATA_START_OFS)[0]
    data_sectors = struct.unpack_from("<H", sb, SB_DATA_SEC_OFS)[0]
    next_free    = struct.unpack_from("<H", sb, SB_NEXT_FREE_OFS)[0]
    file_count   = struct.unpack_from("<H", sb, SB_FILE_COUNT_OFS)[0]

    # magic を見やすく表示
    magic_disp = repr(magic.decode("latin-1")).replace("\\x00", "\\0")

    print(f"Superblock @ LBA=0 ({SECTOR_SIZE}B):")
    print(f"  +0   magic         = {magic_disp:<22}            (8B)")
    print(f"  +8   ver_major     = {ver_major:<5}                       (1B)")
    print(f"  +9   ver_minor     = {ver_minor:<5}                       (1B)")
    print(f"  +10  sector_size   = {sector_size:<5} (0x{sector_size:04X})            (2B LE)")
    print(f"  +12  total_sectors = {total_sec:<5} (0x{total_sec:04X})            (2B LE)")
    print(f"  +14  dir_start     = {dir_start:<5} (0x{dir_start:04X})            (2B LE)")
    print(f"  +16  dir_sectors   = {dir_sectors:<5} (0x{dir_sectors:04X})            (2B LE)")
    print(f"  +18  dir_entries   = {dir_entries:<5} (0x{dir_entries:04X})            (2B LE)")
    print(f"  +20  data_start    = {data_start:<5} (0x{data_start:04X})            (2B LE)")
    print(f"  +22  data_sectors  = {data_sectors:<5} (0x{data_sectors:04X})            (2B LE)")
    print(f"  +24  next_free_sec = {next_free:<5} (0x{next_free:04X})            (2B LE)")
    print(f"  +26  file_count    = {file_count:<5} (0x{file_count:04X})            (2B LE)")

    # ディレクトリ・データ領域の説明
    dir_bytes_total = DIR_SECTORS * SECTOR_SIZE
    data_bytes_total = data_sectors * SECTOR_SIZE
    last_lba = total_sectors - 1
    print(f"Directory @ LBA=1..3 ({dir_bytes_total}B): all zero ({dir_entries} free entries)")
    print(f"Data area @ LBA=4..{last_lba} ({data_bytes_total}B): all zero")

    # 自己整合検査 (書き戻し値が期待と一致するか)
    assert magic == FS_MAGIC, f"magic mismatch: {magic!r} != {FS_MAGIC!r}"
    assert ver_major == FS_VER_MAJOR, f"ver_major mismatch: {ver_major} != {FS_VER_MAJOR}"
    assert ver_minor == FS_VER_MINOR, f"ver_minor mismatch: {ver_minor} != {FS_VER_MINOR}"
    assert sector_size == SECTOR_SIZE
    assert total_sec == total_sectors
    assert dir_start == DIR_START
    assert dir_sectors == DIR_SECTORS
    assert dir_entries == DIR_ENTRIES
    assert data_start == DATA_START
    assert data_sectors == total_sectors - DATA_START
    assert next_free == DATA_START
    assert file_count == 0


# ============================================================
# main
# ============================================================
def main():
    # 起動時バナー (プロジェクトルール: ツール起動時にバージョン表示)
    print(f"mkfs_yuifs.py v{MKFS_VERSION} — YUI OS flat FS formatter")

    try:
        _self_check()
        args = parse_args()

        total_sectors = args.size_kb * 2   # KB → セクタ (1KB = 2セクタ)

        # 引数のおさらい (詳細モード)
        if args.verbose:
            print(f"Target: {args.image_file}")
            print(f"Disk size: {args.size_kb} KB ({total_sectors} sectors)")

        # スーパーブロック構築
        sb = build_superblock(total_sectors)

        # ファイルへ書き出し
        write_image(args.image_file, total_sectors, sb, verbose=args.verbose)

        # 詳細出力 (-v時)
        if args.verbose:
            verify_image(args.image_file, total_sectors)

        print("mkfs: OK")
        return 0

    except ValueError as e:
        print(f"mkfs_yuifs: error: {e}", file=sys.stderr)
        return 1
    except OSError as e:
        print(f"mkfs_yuifs: I/O error: {e}", file=sys.stderr)
        return 2
    except AssertionError as e:
        print(f"mkfs_yuifs: internal assertion failed: {e}", file=sys.stderr)
        return 3


if __name__ == "__main__":
    sys.exit(main())
