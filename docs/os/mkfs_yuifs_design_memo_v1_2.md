# mkfs_yuifs.py 設計メモ v1.2

**作成日:** 2026-05-23
**最終改版:** 2026-05-29
**目的:** YUI OS Ph.4 — フラットFSディスクイメージ初期化ツールの設計
**上位設計書:** yuios_ph4_filemgr_design_v1_5_2.md §3 / §7 / §8.4.3
**作成者:** Claude
**ステータス:** v1.2（mkfs_yuifs.py v1.1 実装反映済み・Step 5-2 動作実証済み）

---

## 改版履歴

| 版数 | 日付 | 変更内容 | 作成者 |
|---|---|---|---|
| v1.0 | 2026-05-23 | 初版作成。Ph.4 Step 3 mkfs_yuifs.py 設計メモ。エンディアン分析・引数仕様・スーパーブロック初期化・KY項目を整理 | Claude |
| v1.1 | 2026-05-23 | 社内レビュー（かやぬまさん）反映。主な変更：①§2.1 `--size-kb` 上限を 32768 → **32767 KB** に修正（u16 total_sectors 制約・最大65534セクタ）、②§2.1 最小サイズを 4 → **8 KB** に引き上げ（メタ4セクタ＋データ最低12セクタ確保）、③§3.2 自己検証 assert を追加（kaizen原則26 設計書⇔実装定数 対照表の実行時チェック）、④§3.3 `write_image()` の I/O 例外捕捉を明記、⑤§4.3 emu23+FileMgrテスト用サイズ `--size-kb 32` (HANDOVER_CHAT29整合) を明記、⑥§5 KY項目に K7（引数パース失敗対策）追加、⑦§6 に上位設計書改版要請（FileMgr v1.2 §3.1「最大セクタ数65536」→「65535」）を追記、⑧§2.1 切り上げ警告メッセージ形式を明記 | Claude |
| **v1.2** | **2026-05-29** | **Step 5-2 FILE-LIST-IMPL 動作確認のため `--add-file` オプションを追加（mkfs_yuifs.py v1.1 実装）：**①§2.1 引数仕様に `--add-file NAME` を追加（NAME は 1〜15 文字 ASCII）。②§2.5 として新節「初期ファイル作成機能（v1.2 新設）」を追加し、ディレクトリ index=0 への DE 書込仕様（name/size/start_sec/sec_count/flags=FLG_USED）とデータ領域 LBA=DATA_START へのコンテンツ書込（"Hello, YUI OS!\n" 15B 固定）を明文化。③§3.3 関数構成に `build_directory()` を追加。④§3.6 -v 出力例を `--add-file` 指定時用に追記。⑤§4.3 試験手順を `--add-file hello.txt` 形式に更新（設計書 v1.5.2 §8.4.3 と整合）。⑥本機能の動作実証：2026-05-29 emu23 上で `0A BC123MPDQL` 出力により FILE-LIST-IMPL の正常動作（r0=1 期待）と境界条件（空ディレクトリ→r0=0）の両方が PASS | Claude |

---

## 1. エンディアン確定事項（調査結果）

### 1.1 ISA2.3 仕様

`ISA2_3_v231.docx` §2.1 より:

> エンディアン | リトルエンディアン

YSD8800 CPU はリトルエンディアン。16bit値を `STW [addr], rS` でメモリへ書くと、メモリ上は
`addr+0: 下位バイト, addr+1: 上位バイト` の順で配置される。

### 1.2 ストレージドライバの転送方式

`yuios_ph3_storage_design_v1_3.md` §4.4 / §4.5 より:

**STOR-WRITE-IMPL** (src→ディスク):
```forth
512 0 DO
    DUP I + C@        \ メモリの第I バイトを取り出す（バイト単位）
    SD-DATA !         \ SD_DATA へ書き込み、BUF_PTR 自動++
LOOP
```

**STOR-READ-IMPL** (ディスク→dst):
```forth
512 0 DO
    SD-DATA @         \ ディスクの第I バイトを読み出す
    OVER I + C!       \ メモリの第I バイトに書き込む
LOOP
```

両者ともバイト単位 (`C@` / `C!`) で転送するため、

**「ディスク上のセクタの第N バイト」 = 「メモリ上のセクタバッファの第N バイト」**

という単純な1:1対応が成立する。

### 1.3 mkfs_yuifs.py の結論

mkfs 側が16bitフィールドを **リトルエンディアン** で書き出せば、FileMgr が `@`（LDW）で読んだ値とビット完全一致する。

Python での実装方針:
- `struct.pack('<H', value)` — little-endian unsigned 16bit
- `struct.pack('<I', value)` — little-endian unsigned 32bit
- 1バイトフィールドは `bytes([value])` または `struct.pack('B', value)`

**根拠の検証 (思考実験):**
- mkfs で `total_sectors = 2048` ($0800) を SB+12 に書く
- Python: `struct.pack('<H', 2048)` → `b'\x00\x08'` をディスクに書き込み
- FileMgr 起動後、SB-LOAD でセクタ0を `$E000` などに読み込むと、メモリ $E00C には `$00`、$E00D には `$08`
- FileMgr が `$E00C @` (LDW) を実行すると、リトルエンディアンCPUは下位先・上位後で組み立て、$0800 = 2048 を取得
- ✓ 一致

---

## 2. 実装仕様（設計書からの転記）

### 2.1 引数仕様

```
mkfs_yuifs.py <image_file> [--size-kb N] [-v|--verbose]
```

| 引数 | 必須 | 意味 |
|---|---|---|
| `image_file` | 必須 | 出力先ディスクイメージファイルパス |
| `--size-kb N` | オプション | ディスクサイズ（KB単位）。デフォルト 1024（=1MB=2048セクタ） |
| `-v`, `--verbose` | オプション | 詳細出力（書き込んだ各フィールドを表示） |

**設計判断:**
- 既存ファイルは **上書き**（`open(..., 'wb')`）。事前確認は不要（mkfsの一般慣習）。
- `--size-kb` の範囲: **8 KB（最小、メタ4セクタ＋データ12セクタ）〜 32767 KB（最大、約32MB）**。範囲外はエラー終了。
- `--size-kb` が 512B の倍数でない場合は切り上げる（ddで作ったイメージとの整合のため、file_size % 512 == 0 を保証）。

**【v1.1 修正】最小・最大サイズの根拠:**

| 項目 | 値 | 根拠 |
|---|---|---|
| 最小サイズ | 8 KB (16セクタ) | メタ領域4セクタ＋データ最低12セクタを確保。`--size-kb 4` を許容すると data_sectors=4 となり、ファイル作成の自由度が極小（実用最低限を確保） |
| 最大サイズ | 32767 KB (65534セクタ) | u16 total_sectors の表現範囲 0..65535。最大値65535 は奇数で 1KB境界に揃わないため、1KB単位（=2セクタ）で割り切れる最大値として 32767 KB (65534セクタ) を採用 |

**【v1.1 修正】切り上げ警告メッセージ形式:**

`--size-kb` が 512B（=0.5KB）の倍数でない場合（実質的には常に整数KB指定だが、念のため）、または内部処理で切り上げが発生した場合は **stderr** に以下形式で警告を出力する:

```
mkfs_yuifs: warning: --size-kb N was rounded up to M KB (must be multiple of 0.5 KB)
```

ただし `--size-kb` は `argparse(type=int)` で受けるため、実際には常に整数KBであり、512B境界の問題は発生しない。よって本警告は将来 `--size-bytes` オプション追加時のための予約仕様。

### 2.2 スーパーブロック初期化（LBA=0、512B）

設計書 §3.2 より:

| オフセット | サイズ | フィールド | 値 |
|---|---|---|---|
| +0 | 8 B | magic | `b"YUIFS\x00\x00\x00"` |
| +8 | 1 B | ver_major | 1 |
| +9 | 1 B | ver_minor | 1 |
| +10 | 2 B | sector_size | 512 |
| +12 | 2 B | total_sectors | size_kb * 2 |
| +14 | 2 B | dir_start | 1 |
| +16 | 2 B | dir_sectors | 3 |
| +18 | 2 B | dir_entries | 32 |
| +20 | 2 B | data_start | 4 |
| +22 | 2 B | data_sectors | total_sectors - 4 |
| +24 | 2 B | next_free_sec | 4 |
| +26 | 2 B | file_count | 0 |
| +28 | 4 B | (予約) | 0 埋め |
| +32〜+511 | 480 B | (予約) | 0 埋め |

### 2.3 ディレクトリ領域初期化（LBA=1〜3、計1536B）

設計書 §7.2 より:

> 全 1536B を 0 クリア（全エントリ FLG_USED=0）

48B エントリ × 32 個 = 1536B。flags の bit0 (FLG_USED) が 0 = 空きエントリ。
全0でちょうど全エントリ「未使用」状態となる。

### 2.4 データ領域（LBA=4以降）

設計書 §7.2 より:

> 初期化不要（next_free_sec=4 で未使用扱い）

ただし、Python では `open(..., 'wb')` で作る場合、ファイルサイズは write した分しか確保されない。データ領域も全0で物理的に書き出すか、または `truncate()` で sparse ファイルとするかを選択。

**設計判断:**
- **全領域 0 で物理書き出し** を採用する。
- 理由1: `dd if=/dev/zero of=disk.img bs=512 count=N` と同等の挙動とし、ddで作ったイメージをmkfsしても、最初からmkfsで作っても、ファイルサイズ・内容が一致するようにする。
- 理由2: sparseファイルだとhexdumpで「ホールの先」を見るときの挙動が処理系依存になり、検証が面倒。
- 理由3: 32MB上限なので物理書き出しでも実害なし（最悪32MBの書き込み数秒）。
- 性能が問題になれば後日 `--sparse` オプションで切り替え可能とする。

---

### 2.5 初期ファイル作成機能（★v1.2 新設）

#### 2.5.1 目的

Step 5-2 FILE-LIST-IMPL 動作確認時、空ディレクトリだと r0=0 しか返らず「FILE-LIST が動作している」のか「FS-MOUNT 失敗等の早期エラーで 0 を返している」のか区別がつかない。**1 個以上の USED エントリがある状態でテストする必要がある**。

このため `--add-file NAME` オプションを追加し、ディレクトリ index=0 に 1 個のファイルを書き込んで mkfs する機能を実装する。

#### 2.5.2 引数仕様

```
--add-file NAME
```

- NAME: 1〜15 文字の ASCII 文字列
- 制約違反は `ValueError` で exit code 1
- 未指定時は従来通り「全空ディレクトリ」でフォーマット（v1.0/v1.1 互換）

#### 2.5.3 ディレクトリエントリ index=0 への書込仕様

設計書 v1.5.2 §3 DE レイアウト対照表に従い：

| オフセット | 値 | 説明 |
|---|---|---|
| +0..+15 (DE-NAME)      | `NAME` + NUL パディング | 16B |
| +16..+19 (DE-SIZE)     | `15` (u32 LE)           | デフォルトコンテンツ長 |
| +20..+21 (DE-START-SEC)| `DATA_START` (=4)       | u16 LE |
| +22..+23 (DE-SEC-COUNT)| `1`                     | u16 LE（15B は 1 セクタ）|
| +24..+25 (DE-FLAGS)    | `0x0001` (FLG_USED)     | u16 LE |
| +26..+47               | 0                       | 予約領域 |

#### 2.5.4 デフォルトコンテンツ

```
"Hello, YUI OS!\n"  (15 バイト)
```

- データ領域 LBA=4 の先頭に書き込む（残り 497B は 0 埋め）
- Phase 1 ではコンテンツ内容は固定（カスタマイズ機能は Phase 2 以降の検討）

#### 2.5.5 スーパーブロックへの影響

`--add-file` 指定時、SB の以下フィールドが変化：

| フィールド | 未指定 | 指定時 |
|---|---|---|
| `next_free_sec` (+24) | `DATA_START` (=4) | `DATA_START + 1` (=5) |
| `file_count` (+26)    | 0                 | 1 |

#### 2.5.6 使用例

```bash
# Step 5-2 試験用（hello.txt を含む 32KB ディスク）
python3 mkfs_yuifs.py disk.img --size-kb 32 --add-file hello.txt -v

# 従来通り（全空）
python3 mkfs_yuifs.py disk.img --size-kb 32 -v
```

---

## 3. プログラム構造

### 3.1 ファイル先頭コメント

```
#!/usr/bin/env python3
# mkfs_yuifs.py — YUI OS フラットFS ディスクイメージ初期化ツール
# Version 1.0 / 2026-05-23
# 対応FS: YUI OS Phase 1 フラットFS (ver_major=1, ver_minor=1)
# 上位設計: yuios_ph4_filemgr_design_v1_2.md §3, §7
# 設計書: mkfs_yuifs_design_memo_v1_1.md
```

ファイル名・コメント中にバージョン明示（プロジェクトルール準拠）。
**注:** 本設計書は v1.1 だが、`mkfs_yuifs.py` の実装初版は v1.0 として作成する（設計書とツールのバージョンは独立管理）。

### 3.2 主要定数（実装定数として §3.6 対照表と整合）

```python
# FS フォーマット定数
SECTOR_SIZE      = 512
FS_VER_MAJOR     = 1
FS_VER_MINOR     = 1
FS_MAGIC         = b"YUIFS\x00\x00\x00"  # 8B
DIR_START        = 1
DIR_SECTORS      = 3
DIR_ENTRIES      = 32
DATA_START       = 4
DE_SIZE          = 48

# スーパーブロック内オフセット（§3.6 対照表と一致）
SB_MAGIC_OFS     = 0
SB_VER_MAJOR_OFS = 8
SB_VER_MINOR_OFS = 9
SB_SECSIZE_OFS   = 10
SB_TOTAL_SEC_OFS = 12
SB_DIR_START_OFS = 14
SB_DIR_SEC_OFS   = 16
SB_DIR_ENT_OFS   = 18
SB_DATA_START_OFS = 20
SB_DATA_SEC_OFS  = 22
SB_NEXT_FREE_OFS = 24
SB_FILE_COUNT_OFS = 26

# サイズ制約定数（v1.1 新設）
MIN_SIZE_KB      = 8        # 最小 8KB (16セクタ: メタ4 + データ12)
MAX_SIZE_KB      = 32767    # 最大 32767KB (65534セクタ: u16範囲)
MIN_SECTORS      = MIN_SIZE_KB * 2   # 16セクタ
MAX_SECTORS      = MAX_SIZE_KB * 2   # 65534セクタ
```

**【v1.1 追加】自己検証 assert（kaizen原則26 設計書⇔実装定数 対照表の実行時チェック）:**

プログラム起動直後（main() 冒頭）で以下を実行し、定数間の整合を起動時に検査する。設計書改版時の定数取り違えバグを即座に検出する。

```python
def _self_check():
    # マジック長さ
    assert len(FS_MAGIC) == 8, "FS_MAGIC must be 8 bytes"
    # スーパーブロックオフセット（§3.6 対照表と整合）
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

_self_check()
```

### 3.3 関数構成

```
main()
 ├ _self_check()       定数間整合の自己検査（§3.2）
 ├ parse_args()        引数解析・バリデーション（--add-file 含む v1.2）
 ├ build_superblock()  512Bのbytes生成（リトルエンディアン）。
 │                     v1.2: add_file_name 指定時は file_count=1, next_free_sec=DATA_START+1
 ├ build_directory()   ディレクトリ1536Bのbytes生成（★v1.2 新設）
 │                     add_file_name 指定時は index=0 に DE 書込（§2.5.3）
 ├ write_image()       ファイルへ書き出し
 │   ├ SB（1セクタ） + ディレクトリ3セクタ + データ領域
 │   └ v1.2: add_file_name 指定時は LBA=DATA_START にコンテンツ書込
 └ verify_image()      （-v時のみ）作成イメージを読み返してフィールドダンプ
                        v1.2: add_file_name の表示と SB の整合性検査
```

**【v1.1 追加】例外捕捉とエラーハンドリング:**

`main()` の最外側で `try/except` により以下の例外を捕捉し、適切な終了コードで終了する:

```python
def main():
    try:
        _self_check()
        args = parse_args()       # ValueError → exit(1)
        sb = build_superblock(args)
        write_image(args, sb)     # OSError → exit(2)
        if args.verbose:
            verify_image(args)
        print("mkfs: OK")
        return 0
    except ValueError as e:
        print(f"mkfs_yuifs: error: {e}", file=sys.stderr)
        return 1
    except OSError as e:
        print(f"mkfs_yuifs: I/O error: {e}", file=sys.stderr)
        return 2
    except AssertionError as e:
        # 自己検証失敗（プログラムバグ）
        print(f"mkfs_yuifs: internal assertion failed: {e}", file=sys.stderr)
        return 3
```

- `ValueError`: 引数バリデーション失敗（範囲外サイズ等） → exit(1)
- `OSError`: ファイル I/O 失敗（ディスクフル・権限・書き込みエラー等） → exit(2)
- `AssertionError`: 自己検証失敗（コードバグ） → exit(3)

### 3.4 起動時バナー（プロジェクトルール準拠）

```
mkfs_yuifs.py v1.0 — YUI OS flat FS formatter
```

ツール起動時にバージョン表示（プロジェクトルール: 開発ツールはバージョン分かるよう表示）。

### 3.5 終了コード

- 0: 成功
- 1: 引数エラー（範囲外サイズ・型不正等）
- 2: I/O エラー（書き込み失敗・権限不足等）
- 3: 内部 assertion 失敗（プログラムバグ。v1.1 追加）

### 3.6 -v 詳細出力例

```
mkfs_yuifs.py v1.0 — YUI OS flat FS formatter
Target: disk.img
Disk size: 1024 KB (2048 sectors)
Superblock @ LBA=0 (512B):
  +0   magic         = "YUIFS\0\0\0"           (8B)
  +8   ver_major     = 1                       (1B)
  +9   ver_minor     = 1                       (1B)
  +10  sector_size   = 512   (0x0200)          (2B LE)
  +12  total_sectors = 2048  (0x0800)          (2B LE)
  +14  dir_start     = 1     (0x0001)          (2B LE)
  +16  dir_sectors   = 3     (0x0003)          (2B LE)
  +18  dir_entries   = 32    (0x0020)          (2B LE)
  +20  data_start    = 4     (0x0004)          (2B LE)
  +22  data_sectors  = 2044  (0x07FC)          (2B LE)
  +24  next_free_sec = 4     (0x0004)          (2B LE)
  +26  file_count    = 0     (0x0000)          (2B LE)
Directory @ LBA=1..3 (1536B): all zero (32 free entries)
Data area @ LBA=4..2047 (1044480B): all zero
Total written: 1048576 bytes
mkfs: OK
```

---

## 4. テスト・検証手順

### 4.1 mkfs 後の hexdump 確認

```bash
python3 mkfs_yuifs.py disk.img --size-kb 1024 -v
hexdump -C disk.img | head -3
```

期待出力:
```
00000000  59 55 49 46 53 00 00 00  01 01 00 02 00 08 01 00  |YUIFS...........|
00000010  03 00 20 00 04 00 fc 07  04 00 00 00 00 00 00 00  |.. .............|
00000020  00 00 00 00 ...                                    |................|
```

検証ポイント:
- `+0..+7`: `59 55 49 46 53 00 00 00` = "YUIFS\0\0\0"
- `+8`: `01` = ver_major
- `+9`: `01` = ver_minor
- `+10..+11`: `00 02` = 0x0200 = 512 (LE)
- `+12..+13`: `00 08` = 0x0800 = 2048 (LE)
- `+14..+15`: `01 00` = 0x0001 = 1
- `+16..+17`: `03 00` = 0x0003 = 3
- `+18..+19`: `20 00` = 0x0020 = 32
- `+20..+21`: `04 00` = 0x0004 = 4
- `+22..+23`: `fc 07` = 0x07FC = 2044 (LE)
- `+24..+25`: `04 00` = 0x0004 = 4
- `+26..+27`: `00 00` = 0x0000 = 0

### 4.2 ディレクトリ・データ領域の0確認

```bash
hexdump -C disk.img | head -10 | tail -8
```

LBA=1 以降が全て `00 00 00 00 ...` であることを目視確認。

### 4.3 emu23 + FileMgr (Step 4以降) での実マウント

Step 4 以降で FileMgr の FS-MOUNT が成功することで最終的なエンディアン整合が確認できる。本Step 3 単独では hexdump 確認止まり。

**【v1.1 追加】emu23 テスト用イメージサイズ:**

HANDOVER_CHAT29 §2.2 では emu23 テスト用に `dd if=/dev/zero of=disk.img bs=512 count=64` (32KB = 64セクタ) を使用している。Step 4 以降の FileMgr 動作確認では:

```bash
# Step 3 完成後の標準テスト手順
python3 mkfs_yuifs.py disk.img --size-kb 32 -v
./emu23_v104 yuios_v0_9_0.bin yuios_v0_9_0.sym --disk disk.img -q
# 期待出力: A BCP (STOR-TEST 全パス) + FileMgr マウント成功表示
```

`--size-kb 32` で 64セクタ（メタ4 + データ60）となり、FileMgr の動作確認に十分。本番運用時は `--size-kb 1024`（1MB）以上を推奨。

---

## 5. 既知のリスク・KY項目

| # | リスク | 対策 |
|---|---|---|
| K1 | エンディアン取り違え（mkfs 側が big-endian で書く） | `struct.pack('<H', ...)` の `<` 指定を Code Review でダブルチェック。-v 出力で値とhexdumpを比較 |
| K2 | magic 文字列の長さ違い（"YUIFS" 5文字 + 0埋め3バイト = 8B が期待） | バイトリテラル `b"YUIFS\x00\x00\x00"` の長さを `assert len() == 8` |
| K3 | スーパーブロックのフィールドオフセット間違い | §3.6 対照表をプログラム冒頭に定数として全フィールド列挙、build_superblock では `struct.pack_into` でオフセット指定書き込み。§3.2 の `_self_check()` で起動時検査（v1.1 追加） |
| K4 | --size-kb が 512B 倍数でない | 切り上げ + 警告メッセージ（§2.1 形式参照） |
| K5 | total_sectors の u16 オーバーフロー（>65535） | 引数チェックで `8 <= size_kb <= 32767` に制限。`MAX_SIZE_KB = 32767` 定数で管理（v1.1 修正・上限値訂正） |
| K6 | sparse でない全書き出しで遅い・大ファイル | 32MB上限なので問題視せず。性能要件なら --sparse オプション追加 |
| K7 | `--size-kb` 引数の int パース失敗（負数・浮動小数・文字列） | `argparse(type=int)` で文字列・小数は自動拒否。範囲チェック `MIN_SIZE_KB <= n <= MAX_SIZE_KB` を parse_args 内で実施。負数は型変換通過後にチェック（v1.1 新設） |

---

## 6. レビュー結果・上位設計書改版要請

### 6.1 v1.0 レビュー結果（2026-05-23、かやぬまさん判定）

| # | レビュー観点 | 判定 | 反映先 |
|---|---|---|---|
| 1 | エンディアン（LE採用） | OK | — |
| 2 | デフォルトサイズ 1024 KB | **採用** | §2.1 維持 |
| 3 | データ領域全0書き出し | OK | §2.4 維持 |
| 4 | `--size-kb` 引数名・単位 | OK | §2.1 維持 |
| 5 | 既存ファイル無条件上書き | OK（mkfs慣習通り） | §2.1 維持 |
| 6 | `-v` 出力フォーマット | OK | §3.6 維持 |
| 7 | KY項目追加 | K7 追加 | §5 K7 |
| A-1 | `--size-kb` 上限 | **32768 → 32767 KB に修正** | §2.1 / 定数 MAX_SIZE_KB |
| A-3 | 最小サイズ | **4 → 8 KB に引き上げ** | §2.1 / 定数 MIN_SIZE_KB |
| B-2 | 自己検証 assert | 追加 | §3.2 `_self_check()` |
| C-1 | 切り上げ警告形式 | 明記 | §2.1 |
| C-4 | I/O 例外捕捉 | 明記 | §3.3 |

### 6.2 上位設計書（FileMgr v1.2）への改版要請

本設計書の検討過程で、上位設計書 `yuios_ph4_filemgr_design_v1_2.md` §3.1「全体レイアウトと容量設計」表の数値に誤りを発見した。次の機会に改版を要請する。

**指摘箇所:** §3.1 容量設計表

| 現行（v1.2） | 訂正案 | 根拠 |
|---|---|---|
| 最大セクタ数 65536 | **65535** | u16 LBA の表現範囲は 0..65535（65536 は u16 で表現不可） |
| 最大ディスク容量 33,554,432 B (32 MB) | 33,553,920 B (約32 MB) | 65535 × 512 = 33,553,920 |
| 最大データ領域 65532 セクタ（約31.99 MB） | **65531 セクタ**（約31.99 MB） | 65535 − 4 = 65531 |

**改版要請の優先度:** 中（実装には直接影響しないが、設計書の数値整合性のため次回改版時に修正）。

mkfs_yuifs.py 側は本要請より厳しい `MAX_SIZE_KB = 32767`（=65534セクタ）で実装し、65535 を「奇数=1KB境界に揃わない」理由で1段下げて運用する。よって本要請がFileMgr側に反映されなくても mkfs 側の動作には影響しない。

### 6.3 関連設計書の改版状況

| 設計書 | 現行版 | 本Step 3完了時の改版要否 |
|---|---|---|
| yuios_ph4_filemgr_design_v1_2.md | v1.2 | §3.1 数値訂正（§6.2 参照）。次回改版で対応 |
| yuios_build_procedure_v1_2.docx | v1.2 | `mkfs_yuifs.py` 使用手順追加（HANDOVER_CHAT29 §2.3 既出）。Step 3 実装完了後に改版 |

---

**以上、mkfs_yuifs.py 設計メモ v1.1**
