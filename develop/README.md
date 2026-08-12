# YSD8800 ISA2.2 開発環境

YSD8800 は独自設計の 16bit CPU です。
最終目標は FPGA (SystemVerilog) での実装と、その上でのマイクロカーネル動作です。

## ディレクトリ構成

```
.
├── Makefile              ビルドシステム
├── README.md             このファイル
├── hasm22.c              アセンブラ (ISA2.2)
├── emu22.c               エミュレータ (ISA2.2)
├── disasm22.c            逆アセンブラ (ISA2.2)
├── kernel.asm            マイクロカーネル v0.5
├── kernel_api.inc        カーネルAPI定義
├── scc22/
│   └── scc22.c           Small-C コンパイラ (YSD8800専用)
├── force/
│   ├── force.c           Forth クロスコンパイラ Force v1.0
│   └── targets/
│       ├── ysd8800.tgt   YSD8800 ターゲット設定
│       └── ysd8800.prim  YSD8800 プリミティブ定義
├── scripts/
│   ├── make_harness.py   ハーネス自動生成
│   ├── merge_simple.py   バイナリマージ (カーネルなし)
│   └── merge.py          バイナリマージ (カーネルあり)
└── samples/
    ├── hello/
    │   ├── hello.c       Hello World (C)
    │   └── hello.fs      Hello World (Forth)
    ├── counter/
    │   ├── counter.c     カウンタ 0〜9 (C)
    │   └── counter.fs    カウンタ 0〜9 (Forth)
    ├── fibonacci/
    │   └── fibonacci.c   フィボナッチ数列 (C)
    ├── calc/
    │   └── calc.c        四則演算・ビット演算 (C)
    └── task_demo/
        └── task_demo.fs  マルチタスクデモ (Forth + カーネル)
```

## セットアップ

```sh
# ホストツールをビルド
make tools

# カーネルをアセンブル
make kernel
```

## サンプルのビルドと実行

### Hello World (C)
```sh
make hello_c
# 出力: Hello, YSD8800!
```

### Hello World (Forth)
```sh
make hello_fs
# 出力: Hello, YSD8800!
```

### カウンタ 0〜9 (C / Forth)
```sh
make counter_c    # C版
make counter_fs   # Forth版
# 出力: 0\n1\n...\n9\nDone!
```

### フィボナッチ数列 (C)
```sh
make fibonacci
# 出力:
# N : FIB
# 0 : 0000
# 1 : 0001
# ...
# A : 0037
```

### 電卓 (C)
```sh
make calc
# 出力:
# + 0064 001E = 0082   (100 + 30 = 130)
# - 0064 001E = 0046
# ...
```

### 全サンプル一括ビルド
```sh
make samples
```

## 手動ビルド手順 (Cプログラム)

```sh
# 1. Cソースをコンパイル
./scc22/scc22 samples/hello/hello.c -o build/hello.asm

# 2. アセンブル
./hasm22 build/hello.asm

# 3. ハーネス生成 (ベクタテーブル + スタック初期化)
python3 scripts/make_harness.py build/hello.asm.sym > build/harness.asm
./hasm22 build/harness.asm

# 4. バイナリマージ
python3 scripts/merge_simple.py \
    build/hello.asm.bin build/harness.asm.bin build/hello.bin

# 5. 実行 (エミュレータ)
echo 's 500000
q' | ./emu22 build/hello.bin
```

## 手動ビルド手順 (Forthプログラム)

```sh
# 1. Forthをコンパイル (force ディレクトリから実行)
cd force && ./force ../samples/hello/hello.fs -o ../build/hello.asm
cd ..

# 2〜5. 以降はCと同じ
```

## メモリマップ (方式A: 静的リンク)

| アドレス範囲 | 用途 |
|-------------|------|
| $0000-$0008 | ベクタテーブル |
| $0030-$08E9 | カーネルコード |
| $0A00-$0DFF | ユーザコード (C/Forth) |
| $0E00-$0EFF | kernel _kstart |
| $0F00-$0F3F | C↔カーネル ブリッジ |
| $1000-$11FF | TCBプール (8タスク) |
| $2000-$3FFF | タスクスタック |
| $E0D0-$E0DF | scc22 ワーク変数 |
| $E100-$E104 | カーネルワーク変数 |
| $E300-      | グローバル変数領域 |
| $F800-$FBFF | Forthデータスタック |
| $FC00-$FFFE | コール/リターンスタック |
| $FC80       | UART TX |
| $FC84       | UART STAT |

## カーネルAPI (kernel_api.inc)

| シンボル | アドレス | 機能 |
|---------|---------|------|
| KERN_TASK_ID     | $0440 | 現タスクIDを取得 |
| KERN_TASK_EXIT   | $0460 | タスク終了 |
| KERN_TASK_CREATE | $0520 | タスク生成 |
| KERN_TASK_SLEEP  | $01C0 | タスクスリープ |
| KERN_TASK_WAKEUP | $02C0 | タスク起床 |
| KERN_MSG_SEND    | $0740 | メッセージ送信 |
| KERN_MSG_RECV    | $07E0 | メッセージ受信 |

## ツール仕様

| ツール | バージョン | 説明 |
|-------|----------|------|
| hasm22   | v1.00 | YSD8800 ISA2.2 アセンブラ |
| emu22    | v1.01 | YSD8800 ISA2.2 エミュレータ |
| scc22    | v1.00 | Small-C コンパイラ (YSD8800専用) |
| force    | v1.00 | Forth クロスコンパイラ |
| disasm22 | v1.00 | 逆アセンブラ |
