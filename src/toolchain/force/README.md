# Force - Forth Cross Compiler v1.0

YSD8800 ISA2.2 向け Forth クロスコンパイラです。
Forth ソース (.fs) を YSD8800 アセンブリ (.asm) に変換します。

## ディレクトリ構成

```
force/
├── Makefile
├── README.md
├── force.c              メインエントリポイント
├── frontend/
│   ├── lexer.c/h        字句解析
│   ├── parser.c/h       構文解析・IR生成
│   └── ir.c/h           中間表現 (IR)
├── backend/
│   └── codegen.c/h      YSD8800 コード生成
└── targets/
    ├── ysd8800.tgt      ターゲット設定（メモリマップ等）
    └── ysd8800.prim     プリミティブ命令テンプレート
```

## ビルド方法

```sh
cd force
make
# → force バイナリが生成される
```

## 使用方法

```sh
# force ディレクトリ内から実行（targets/ を参照するため）
cd force
./force path/to/program.fs -o path/to/output.asm
```

**注意**: `force` は実行時に `targets/ysd8800.tgt` と `targets/ysd8800.prim` を
カレントディレクトリの `targets/` から読み込みます。
必ず `force/` ディレクトリ内から実行してください。

## Forthプログラムのビルド手順（プロジェクトルートから）

```sh
# 1. Forthソースをコンパイル
cd force && ./force ../samples/hello/hello.fs -o ../build/hello.asm && cd ..

# 2. アセンブル
./hasm22 build/hello.asm

# 3. ハーネス生成
python3 scripts/make_harness.py build/hello.asm.sym > build/harness.asm
./hasm22 build/harness.asm

# 4. バイナリマージ
python3 scripts/merge_simple.py \
    build/hello.asm.bin build/harness.asm.bin build/hello.bin

# 5. 実行（UART出力のみ表示）
./emu22 build/hello.bin -q
```

または `make hello_fs` で一括実行。

## サポートしているForth構文

| 構文 | 説明 |
|------|------|
| `: NAME ... ;` | ワード定義 |
| `N` | 整数リテラル（10進/16進 $XXXX） |
| `CONSTANT` | 定数定義 |
| `IF...THEN` | 条件分岐 |
| `IF...ELSE...THEN` | 条件分岐（else付き） |
| `BEGIN...WHILE...REPEAT` | 条件ループ |
| `BEGIN...UNTIL` | 後判定ループ |
| `DO...LOOP` | カウントループ |
| `@` `!` | メモリ読み書き（16bit） |
| `C@` `C!` | メモリ読み書き（8bit） |
| `DUP DROP SWAP OVER` | スタック操作 |
| `+ - * /` `MOD` | 算術演算 |
| `AND OR XOR NOT` | ビット演算 |
| `=` `<>` `<` `>` `<=` `>=` | 比較 |
| `0=` `0<>` `0<` | ゼロ比較 |
| `HALT` | CPU停止 |
| `\` `;` | コメント |

## ターゲット設定 (ysd8800.tgt)

```
CODE_START = $0030    ユーザコード開始アドレス
DATA_START = $E300    データ領域開始
DSP_INIT   = $F7FE    データスタックポインタ初期値
```
