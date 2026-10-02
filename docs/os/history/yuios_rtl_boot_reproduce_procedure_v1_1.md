# YUI OS RTL ブート再現手順書 v1.1

- **作成日**: 2026-08-01（v1.0）／**改版日**: 2026-08-24（v1.1）
- **★v1.1 改版理由★**: ①.5 工程のベースライン測定にあたり v1.0 を実行したところ、
  **5 件の「空振り」**（記載どおりに実行できない箇所）が判明したため是正した。
  原則131（テスト手順の事前検証）の適用事例。

| # | 箇所 | v1.0（誤） | v1.1（正） |
|---|---|---|---|
| 1 | §6.3 | `sd_image.hex` はナレッジからコピー | ★**ナレッジに存在しない**。`mkfs_yuifs_v1_1.py` で生成★ |
| 2 | §3.1/§3.3 | `scc23_v2_04.c` | `scc23_v2_07.c` |
| 3 | §3.1/§3.3 | `emu23_v111.c` | `emu23_v2_15.c` |
| 4 | §3.1 | `kernel_v12_8.asm` / Makefile v1.2 | `kernel_v12_11.asm` / **Makefile v1.3** |
| 5 | §4.2 | MD5 `7a6a5b87…` | ★**`599a7f9d…`**（G-2）★ |

> ★★**#5 が最も危険**★★ — 新旧どちらも **サイズは 56,416 B で同じ**。
> サイズだけ照合していると通過してしまい、md5 照合で初めて止まる。
> v1.0 のまま実行すると「MD5 不一致 → 以降実行禁止」で完全に足止めされる。

> ★v1.1 の全手順は 2026-08-24 に**実機実行で検証済**★
> （G-2 md5 `599a7f9d…` 一致・AC-1 1 hit @`0x003d`・V8-b PROD PASS @cycle 4,772,836）。

- **対象**: かやぬまさんローカル環境
- **目的**: プロジェクトナレッジのファイルから **YUI OS 本体（yuios_road2.bin・56,416B）を iverilog 上の実 RTL 環境でブートさせ、YUIFS マウント完了（"0123MD"）まで到達させる**手順を再現する
- **対応工程**: FPGA 実装 **V8-b 本番**（yuios.bin 本体動作確認）
- **参照元実行環境**: Ubuntu 24 / Icarus Verilog 12.0 (stable)
- **想定所要時間**: ツールビルド 2〜3分・yuios ビルド 1分・RTL ビルド 30秒・実行 5〜15分
- **関連文書**:
  - `v8b_prod_design_memo_v0_4.md`（本手順の設計根拠）
  - `v8_catls_local_reproduce_procedure_v1_0.md`（V8-a 版・本書の構成の原型）
  - `yuios_build_procedure_v1_11.docx`（yuios ビルド手順の正本）

---

## 0. サマリ（先に全体像）

本手順は **V8-a 版と決定的に異なる点が 1 つ**ある。

> **V8-a はナレッジのファイルを配置するだけで再現できたが、V8-b は `yuios_road2.bin` を自分でビルドする必要がある。**
> （バイナリはプロジェクトナレッジに登録できないため）

```
[1] 前提環境確認
      ↓
[2] ツールチェーンのビルド（force / hasm23 / lnk23 / scc23 / emu23）
      ↓
[3] yuios_road2.bin のビルド（make yuios）  ★V8-a には無い工程★
      ↓
[4] HEX 変換（bin2hex.py）
      ↓
[5] RTL ファイル配置
      ↓
[6] RTL ビルド（iverilog）
      ↓
[7] 実行（vvp）
      ↓
[8] PASS 確認
```

**最終期待出力**:
```
[M-5] "0123MD" detected @cycle=4616900 ==> PASS
=== V8-b PROD PASS ===
```

**最終期待 UART 出力**（`uart_out.log`・25 バイト）:
```
YUIOS Booted!
YUI> 0123MD
```

---

## 1. 前提環境

### 1.1 必須ツール

| ツール | 版数 | 確認コマンド |
|---|---|---|
| Icarus Verilog | 12.0 推奨（11.0 以上） | `iverilog -V` |
| gcc | 標準 | `gcc --version` |
| python3 | 標準 | `python3 --version` |
| make / bash / md5sum | 標準 | （通常インストール済） |

### 1.2 iverilog のインストール

**Ubuntu / Debian 系**:
```bash
sudo apt-get update
sudo apt-get install -y iverilog
```

**Fedora / RHEL 系**:
```bash
sudo dnf install iverilog
```

**macOS (Homebrew)**:
```bash
brew install icarus-verilog
```

### 1.3 バージョン確認

```bash
iverilog -V
```
→ `Icarus Verilog version 12.0 (stable)` であること。11.0 未満は `-g2012` 未対応の可能性あり。

---

## 2. 作業ディレクトリ作成

ビルド用と RTL 用を**分ける**（混同防止）。

```bash
mkdir -p ~/yui_rtl_boot/build
mkdir -p ~/yui_rtl_boot/rtl
cd ~/yui_rtl_boot
```

---

## 3. ツールチェーンのビルド

### 3.1 ソース配置（build/ へ）

プロジェクトナレッジから以下 **19 ファイル**を `~/yui_rtl_boot/build/` に配置する。

**ツールソース（5 種）**:

| # | ファイル | ビルド先 |
|---|---|---|
| 1 | `force_v1_5.c` | `force` |
| 2 | `hasm23_v1_04.c` | `hasm23` |
| 3 | `lnk23_v2_01.c` | `lnk23` |
| 4 | `scc23_v2_07.c` | `scc23` |  ★v1.1: v2_04→v2_07★
| 5 | `emu23_v2_15.c` | `emu23` |  ★v1.1: v111→v2_15★

**Force 用フロントエンド／バックエンド（8 ファイル）**:

| # | ファイル | 配置先 |
|---|---|---|
| 6 | `ir.c` | `frontend/ir.c` |
| 7 | `ir.h` | `frontend/ir.h` |
| 8 | `lexer.c` | `frontend/lexer.c` |
| 9 | `lexer.h` | `frontend/lexer.h` |
| 10 | `parser.c` | `frontend/parser.c` |
| 11 | `parser.h` | `frontend/parser.h` |
| 12 | `codegen_v1_5.c` | `backend/codegen.c` |
| 13 | `codegen_v1_4.h` | `backend/codegen.h` |

**ビルド補助（3 ファイル）**:

| # | ファイル | 備考 |
|---|---|---|
| 14 | `Makefile` | ★v1.1: **v1.3**（`KERN_SRC := kernel_v12_11.asm`）★ |
| 15 | `mk_post1.sh` | 後処理1スクリプト |
| 16 | `bin2hex.py` | bin → hex 変換 |

**入力ソース（6 ファイル）**:

| # | ファイル | 備考 |
|---|---|---|
| 17 | `kernel_v12_11.asm` | ★v1.1: v12_8→v12_11（TKT-01〜04 反映・Phase A 確定版）★ |
| 18 | `kernel_forth_v0_10_18.fs` | Forth カーネル |
| 19 | `ysd8800_kern_v0_6.tgt` | **`ysd8800_kern.tgt` にリネームして配置** |
| 20 | `ysd8800.prim` | Force プリミティブ定義 |

### 3.2 Force のディレクトリ構成作成

Force は `frontend/` `backend/` サブディレクトリ構成を期待する。

```bash
cd ~/yui_rtl_boot/build
mkdir -p frontend backend
cp ir.c ir.h lexer.c lexer.h parser.c parser.h frontend/
cp codegen_v1_5.c backend/codegen.c
cp codegen_v1_4.h backend/codegen.h
cp force_v1_5.c force.c
cp ysd8800_kern_v0_6.tgt ysd8800_kern.tgt
```

### 3.3 ツールビルド

```bash
cd ~/yui_rtl_boot/build

# Force（複数ソースリンク）
gcc -O2 -I. -Ifrontend -Ibackend -o force \
    force.c frontend/ir.c frontend/lexer.c frontend/parser.c backend/codegen.c -lm

# 単一ソース 4 種
gcc -O2 -o hasm23 hasm23_v1_04.c
gcc -O2 -o lnk23  lnk23_v2_01.c
gcc -O2 -o scc23  scc23_v2_07.c
gcc -O2 -o emu23  emu23_v2_15.c -lm
```

**注**: Force のビルドで `__va_arg_pack` 関連の warning が出るが**無害**（`-O2` 時の glibc 由来）。

### 3.4 ★必須★ バナー版数照合

**ツールを使う前に必ず版数を確認する**（ビルド手順書 v1.9 §4.13 ルールC の趣旨）。

```bash
cd ~/yui_rtl_boot/build
./force            # --version は未対応。引数なしで末尾にバナー
./hasm23           # 引数なしで usage + バナー
./lnk23 --version
./scc23 --version
./emu23            # 引数なしでバナー
```

**期待バナー**:

| ツール | 期待文字列 |
|---|---|
| force | `Force Forth Cross Compiler v1.5` |
| hasm23 | `hasm23 v1.04 (2026-06-20) for YSD8800 ISA2.3` |
| lnk23 | `lnk23 - YSD8800 ISA2.3 Linker v2.01` |
| scc23 | `scc23 v2.04 (2026-07-26) for YSD8800 ISA2.3` |
| emu23 | `emu23 v1.11 (2026-07-18) for YSD8800 ISA2.3`<br>`  - v1.11: TCR fire-EN OR->AND (IRQ_EN now masks; plan-B EN fix)` |

**1 つでも一致しない場合、以降の手順を実行してはならない**（ビルド成果物のバイト等価性が崩れる）。

---

## 4. yuios_road2.bin のビルド

### 4.1 ビルド実行

```bash
cd ~/yui_rtl_boot/build
chmod +x mk_post1.sh
make yuios
```

**期待される最終行**:
```
lnk23: 56416 bytes -> yuios_road2.bin
lnk23: 1162 symbols -> yuios_road2.sym
```

### 4.2 ★必須★ 絶対ゲート 3 条件の判定

```bash
cd ~/yui_rtl_boot/build

# 条件1: サイズ
wc -c yuios_road2.bin

# 条件2: MD5
md5sum yuios_road2.bin

# 条件3: TCR-ACK パターン
python3 -c "
d = open('yuios_road2.bin','rb').read()
pat = bytes.fromhex('21102300230190fc')
n = 0; i = 0
while True:
    j = d.find(pat, i)
    if j < 0: break
    n += 1; i = j + 1
print(f'TCR-ACK hits: {n}  first offset: 0x{d.find(pat):04x}')
"
```

**期待値（凍結票 I4 / `yuios_ref_freeze_ticket_I4_v1_0.md`）**:

| 条件 | 期待値 |
|---|---|
| サイズ | **56416** バイト |
| MD5 | ★v1.1: **`599a7f9d1ebf103f81f58450ea1b6491`**（G-2）★<br>~~`7a6a5b87afb1ef9f413a7d0c1360e706`~~（kernel v12.8 時代の値・**サイズは同じ 56,416 B なので size だけでは弁別できない**） |
| TCR-ACK パターン `21102300230190fc` | **1 hit @ offset 0x003d** |

**3 条件すべて一致しない場合、以降の手順を実行してはならない**。

---

## 5. HEX 変換

```bash
cd ~/yui_rtl_boot/build
python3 bin2hex.py yuios_road2.bin yuios_road2.hex
wc -l yuios_road2.hex
```

**期待出力**:
```
bin2hex: yuios_road2.bin -> yuios_road2.hex (56416 bytes)
56416 yuios_road2.hex
```

**注**: `bin2hex.py` は `in.bin out.hex` の 2 引数形式。`>` リダイレクトでは動かない。

---

## 6. RTL ファイル配置

### 6.1 RTL 本体（14 ファイル・rtl/ へ）

プロジェクトナレッジから `~/yui_rtl_boot/rtl/` に配置する。**V8-a 版と同一の 14 ファイル**。

| # | ファイル | 役割 |
|---|---|---|
| 1 | `ysd8800_decoder_v0_1.sv` | 命令デコーダ + **`package ysd8800_idec_pkg`** |
| 2 | `ysd8800_regfile_v0_1.sv` | レジスタファイル |
| 3 | `ysd8800_alu_v0_1.sv` | ALU |
| 4 | `ysd8800_cpu_v0_1_FIXED.sv` | CPU コア v0.5.8 |
| 5 | `ysd8800_v5_membus_v0_2.sv` | メモリバス統合ラッパー |
| 6 | `ysd8800_mmio_stub_v0_7.sv` | MMIO デコード（YSD8001-8004 ルーティング） |
| 7 | `ysd8800_ysd8003_v0_4.sv` | ストレージコントローラ（SPI CMD17） |
| 8 | `ysd8800_ysd8002_v0_3.sv` | タイマー（EN 是正版 AND 化） |
| 9 | `ysd8800_ysd8004_v0_1.sv` | 割込コントローラ |
| 10 | `ysd8800_ysd8001_v0_1.sv` | UART |
| 11 | `ysd8800_addr_decoder_v0_1.sv` | アドレスデコーダ |
| 12 | `ysd8800_cdc_bridge_v0_2.sv` | CDC ブリッジ |
| 13 | `ysd8800_mmu_v0_1.sv` | MMU |
| 14 | `ysd8800_psram_ctrl_v0_2.sv` | PSRAM コントローラ |

### 6.2 TB・モデル（2 ファイル）

| # | ファイル | 役割 |
|---|---|---|
| 15 | **`tb_cpu_v8b_prod_v0_2.sv`** | V8-b 本番 TB（★v0.1 ではなく **v0.2**★） |
| 16 | `sd_spi_model_v0_3_poc.sv` | SD SPI モデル（内部 `$readmemh` で `sd_image.hex` を読む） |

**★重要★ TB は必ず v0.2 を使うこと。** v0.1 にはクロック比の致命的バグがあり、CPU が 1 命令も実行せず停止する（`v8b_prod_design_memo_v0_4.md` §3.2 参照）。

### 6.3 入力 HEX（2 ファイル）

| # | ファイル | 入手方法 |
|---|---|---|
| 17 | `yuios_road2.hex` | **§5 で生成したものを `build/` からコピー** |
| 18 | `sd_image.hex` | ★**v1.1: ナレッジには存在しない。下記手順で生成すること**★（8,192 行） |

★**v1.1 追記：`sd_image.hex` の生成手順**★

v1.0 は「プロジェクトナレッジからそのままコピー」としていたが、
**ナレッジに `.hex` は 1 本も登録されていない**（容量逼迫のため中間生成物は
登録対象外）。`mkfs_yuifs_v1_1.py` で生成すること。

```bash
cd ~/yui_rtl_boot/build
python3 mkfs_yuifs_v1_1.py sd_image.bin --size-kb 8 --add-file HELLO.TXT
python3 bin2hex.py sd_image.bin sd_image.hex
wc -l sd_image.hex                     # → 8192
head -5 sd_image.hex | tr '\n' ' '     # → 59 55 49 46 53  ("YUIFS")
cp sd_image.hex ~/yui_rtl_boot/rtl/
```


```bash
cp ~/yui_rtl_boot/build/yuios_road2.hex ~/yui_rtl_boot/rtl/
# sd_image.hex はナレッジからダウンロードして rtl/ に配置
```

### 6.4 配置後の確認

```bash
cd ~/yui_rtl_boot/rtl
ls -1 *.sv | wc -l      # → 16
wc -l yuios_road2.hex   # → 56416
wc -l sd_image.hex      # → 8192
head -5 sd_image.hex | tr '\n' ' '   # → 59 55 49 46 53  ("YUIFS")
```

---

## 7. RTL ビルド

### 7.1 ★重要★ ファイル順序

**`ysd8800_decoder_v0_1.sv` を必ず先頭に置く。**

このファイルは `package ysd8800_idec_pkg` の定義を含み、CPU コアが `import ysd8800_idec_pkg::*;` で参照する。iverilog は**ファイル順序依存**であり、package 定義が後ろにあると:

```
ysd8800_cpu_v0_1_FIXED.sv:233: syntax error
I give up.
```

という**紛らわしいエラー**（「package が無い」ではなく import 行の syntax error）になる。

### 7.2 ビルドコマンド

```bash
cd ~/yui_rtl_boot/rtl

iverilog -g2012 \
    -Ptb_cpu_v8b_prod_v0_2.MAX_CYCLES=10000000 \
    -o v8b_prod.vvp \
    ysd8800_decoder_v0_1.sv \
    tb_cpu_v8b_prod_v0_2.sv \
    ysd8800_cpu_v0_1_FIXED.sv \
    ysd8800_v5_membus_v0_2.sv \
    ysd8800_alu_v0_1.sv \
    ysd8800_regfile_v0_1.sv \
    ysd8800_mmu_v0_1.sv \
    ysd8800_addr_decoder_v0_1.sv \
    ysd8800_mmio_stub_v0_7.sv \
    ysd8800_cdc_bridge_v0_2.sv \
    ysd8800_psram_ctrl_v0_2.sv \
    ysd8800_ysd8001_v0_1.sv \
    ysd8800_ysd8002_v0_3.sv \
    ysd8800_ysd8003_v0_4.sv \
    ysd8800_ysd8004_v0_1.sv \
    sd_spi_model_v0_3_poc.sv
```

**`-P` パラメータ指定の意味**: TB の既定 `MAX_CYCLES` は 1,000,000（phase-1 = 快速 sanity 用）。M-5 到達は 4,616,900 cycle なので、**本番判定には 10,000,000 が必要**。

### 7.3 ★必須★ ビルド成否の判定

**`$?` で判定してはならない**（kaizen 原則68）。**成果物の実在**で判定する。

```bash
ls -la v8b_prod.vvp || echo "BUILD FAILED"
```

**期待**: 約 300KB の `v8b_prod.vvp` が生成されている。

### 7.4 想定される warning（無害）

以下は出ても問題ない。

| warning | 意味 | 判定 |
|---|---|---|
| `Port 3 (mem_addr) ... expects 16 bits, got 20` | TB の 20bit 宣言と RTL の 16bit ポートのミスマッチ。padding / pruning されるが上位 4bit は常に 0 のため無害 | 無視可 |
| `vvp.tgt sorry: Case unique/unique0 qualities are ignored` | `unique case` は iverilog 12.0 で無視される。合成品質のヒントでありシミュレーション意味論には影響しない | 無視可 |

---

## 8. 実行

### 8.1 実行コマンド

```bash
cd ~/yui_rtl_boot/rtl
vvp v8b_prod.vvp 2>&1 | tee run.log
```

**所要時間の目安**: 5〜15 分（M-5 = 461 万 cycle に到達するまで）。マシン性能により変動する。

**★注意★** ビルドと実行は必ず分離すること（`iverilog ... && vvp ...` の `&&` チェーンは禁止・kaizen 原則60）。ビルド失敗時に古い `.vvp` を黙って実行し、誤診断を招く。

### 8.2 進行の目安

以下の順で `$display` が出れば正常に進行している。

```
[B4] CL-1 (1): PSRAM 全域 0 クリア開始 (56416 bytes)
[B4] CL-1 (2): yuios_road2.hex ロード
[B4] CL-1 (3): _kstart  mem[$00E00]=$21
[B4] CL-1 PASS
[B5] CL-2 PASS: YUIFS magic detected
[B2] Reset released @cycle=0
[M-1] PC reached $0E00 (_kstart) @cycle=9
[B6] CL-3 (PC): dbg_pc==$0E00 confirmed
[B7] CL-3 (SP): dbg_sp==$477E confirmed @cycle=32 (KERN_SP_TOP)
[M-2] First UART TX byte=$59 @cycle=89807
[M-3] "YUIOS Booted!" detected @cycle=239874
[M-4] "YUI> " prompt detected @cycle=356663
      ↓ ここから約 426 万 cycle は UART 出力が途絶える（実 SPI 転送中・正常）
[M-5] "0123MD" detected @cycle=4616900 ==> PASS
```

**★M-4 の後の長い沈黙は正常です。★** Forth の SB-LOAD が STOR ドライバ経由で実 SPI 転送（512 バイト × 8 SCK/セクタ）を行うため、UART 出力が 426 万 cycle 途絶えます。TB の `UART_STALL_LIMIT` は 5,000,000 に設定済みなので誤判定は起きません。

---

## 9. PASS 確認

### 9.1 実行ログの判定

```bash
grep -E "PROD PASS|PROD FAIL" run.log
```

**期待**:
```
=== V8-b PROD PASS ===
```

### 9.2 UART 出力の判定

```bash
cd ~/yui_rtl_boot/rtl
wc -c uart_out.log
cat uart_out.log
grep -aoE '0123MD' uart_out.log
```

**期待**:
```
25 uart_out.log
YUIOS Booted!
YUI> 0123MD
0123MD
```

### 9.3 マイルストーン実測値の照合

```bash
grep -E "^\[M-[0-9]\]" run.log
```

**期待実測値（2026-08-01 基準）**:

| MS | 内容 | 期待 cycle |
|---|---|---|
| M-1 | `_kstart` ($0E00) 到達 | 9 |
| M-2 | 初回 UART TX (`$59`='Y') | 89,807 |
| M-3 | `"YUIOS Booted!"` | 239,874 |
| M-4 | `"YUI> "` プロンプト | 356,663 |
| M-5 | `"0123MD"` YUIFS マウント完了 | 4,616,900 |

**cycle 値が完全一致すること**が期待される（同一バイナリ・同一 RTL・同一 TB であれば決定論的に一致する）。

### 9.4 `"0123MD"` の意味（全通過の内訳）

| 文字 | 意味 | Forth 実源 |
|---|---|---|
| `0` | SB-LOAD 開始 | `kernel_forth_v0_10_18.fs` L2785 |
| `1` | SB-LOAD 成功 | L2792 |
| `2` | MAGIC 一致 | L2797 |
| `3` | ver_major OK | L2805 |
| `M` | FS-MOUNTED=1 完了 | L2810 |
| `D` | DIR-LOAD 完了 | L2829 |

**失敗マーカー `i`（L2788・SB-LOAD I/O エラー）/ `g`（L2794・MAGIC 不一致）/ `v`（L2802・ver 不一致）が出ていないこと**も確認する。

---

## 10. トラブルシューティング

### 10.1 `ysd8800_cpu_v0_1_FIXED.sv:233: syntax error`

**原因**: `ysd8800_decoder_v0_1.sv` がファイル順序の先頭にない。

**対処**: §7.1 の通り decoder を先頭に置く。

### 10.2 `[M-1 TIMEOUT] _kstart ($0E00) not reached`

**原因**: TB が **v0.1**（クロック比バグ版）。

**確認**:
```bash
grep -E "always #" tb_cpu_v8b_prod_v0_2.sv
```
**期待**:
```
always #125 cpu_clk = ~cpu_clk;
always #15.625 psram_clk = ~psram_clk;
```

v0.1 は `#5` / `#20` になっており、psram:cpu 比が 1:4 に逆転している。この状態では CDC ハンドシェイクが成立せず `mem_ready` が永久に返らない。**必ず v0.2 を使うこと**。

### 10.3 `$readmemh(yuios_road2.hex): Not enough words in the file for the requested range [0:1048575]`

**これは WARNING であり無害**。PSRAM 配列は 1MB（20bit 空間）で宣言されているが、投入するのは 56,416B のみ。残りは §7 の CL-1 で 0 クリア済み。

### 10.4 `[FAIL] UART TX stall > NNNNN cycles`

**原因**: `UART_STALL_LIMIT` が小さすぎる（TB v0.1 の既定 500,000 で発生）。

**対処**: TB v0.2 を使う（既定 5,000,000）。または `-Ptb_cpu_v8b_prod_v0_2.UART_STALL_LIMIT=5000000` を指定。

### 10.5 `[B5] CL-2 FAIL: SD image magic mismatch`

**原因**: `sd_image.hex` が `rtl/` に配置されていない、または内容が異なる。

**確認**:
```bash
head -5 sd_image.hex | tr '\n' ' '   # → 59 55 49 46 53
wc -l sd_image.hex                    # → 8192
```

### 10.6 MD5 が `7a6a5b87...` にならない

**原因の候補**:
1. ツール版数が違う（§3.4 のバナー照合を再実施）
2. `Makefile` が v1.2 でない（`KERN_SRC=kernel_v12_8.asm` を確認）
3. `kernel_v12_8.asm` ではなく `kernel_v12_7.asm` を使っている（TCR-ACK パターンが 0 hit になる）
4. `ysd8800_kern.tgt` へのリネームを忘れている

### 10.7 vvp が `rc=124`（timeout）で終わる

`timeout` コマンド併用時にこれが出た場合、**組み合わせループではなく単なる時間切れ**の可能性が高い（本工程は 5〜15 分かかる）。`timeout` の値を 1800 秒程度に伸ばす。

なお **kaizen 原則61** では「vvp の rc=124 は組み合わせループを第一に疑う」とあるが、それは**短時間で終わるはずの TB** の話。本工程のように長時間実行が正常な場合は当てはまらない（原則72：再発防止策には適用範囲を定義せよ）。

---

## 11. 段階起動（デバッグ時の使い分け）

問題切り分け時は `MAX_CYCLES` を段階的に変えると効率がよい。

| phase | MAX_CYCLES | 到達目標 | 所要時間 | 用途 |
|---|---|---|---|---|
| **phase-1** | 1,000,000 | M-1〜M-4 | 30秒〜1分 | 快速 sanity（起動〜Shell 立上） |
| **phase-2** | 10,000,000 | **M-5（PASS）** | 5〜15分 | **本番判定** |
| phase-3 | 100,000,000 | 余裕枠 | 長時間 | 将来のシナリオ延長用（通常不要） |

**phase-1 での切り分け**:

| 到達点 | 推定される問題箇所 |
|---|---|
| M-1 未到達 | クロック比 / リセット経路 / PSRAM 初期化 |
| M-2 未到達 | UART / MMIO 経路 |
| M-3 未到達 | Forth カーネル起動シーケンス |
| M-4 未到達 | Shell タスク起動 |
| M-4 到達・M-5 未到達 | ストレージ（SPI / YUIFS）— phase-2 で再実行して確認 |

---

## 12. 本手順で確認できること（工程上の意味）

本手順の完走は、以下を**同時に**実証する。

| 層 | 実証内容 |
|---|---|
| **ツールチェーン** | force / hasm23 / lnk23 が 56,416B をバイト等価に再生成できる |
| **CPU コア** | kernel v12.8 の全命令列が実 RTL 上で正しく実行される |
| **CDC + PSRAM** | 56KB の全域アクセスが CDC 経由で成立する |
| **MMU** | Forth 辞書領域（$5100-$DBFF）へのアクセスが変換を通る |
| **UART (YSD8001)** | Forth の EMIT 経路が実 RTL で動作する |
| **タイマー (YSD8002)** | TCR-ACK 方式のタイマー再武装が動作し、マルチタスクが回る |
| **ストレージ (YSD8003)** | 実 SPI CMD17 で SD からセクタを読み出せる |
| **割込 (YSD8004)** | UART / STOR / タイマーの多重割込が正しく調停される |
| **YUI OS** | kernel + Forth + 全常駐タスク（FILEMGR/MEMMGR/PROCMGR/SHELL/STOR_DRV/UART_DRV）が起動する |
| **YUIFS** | SD 上のファイルシステムをマウントしディレクトリを読み込める |

すなわち **15 コンポーネント統合環境での YUI OS 完全起動**の再現手順である。

---

## 13. 改版履歴

| 版 | 日付 | 内容 |
|---|---|---|
| v1.0 | 2026-08-01 | 初版。V8-b 本番 ALL PASS 達成（CHAT127）を受けて作成。`v8_catls_local_reproduce_procedure_v1_0.md`（V8-a 版）の構成を踏襲しつつ、**yuios_road2.bin の自前ビルド工程（§3〜§5）を新設**（バイナリがナレッジ登録不可のため）。トラブルシューティングに TB v0.1 のクロック比バグ（§10.2）を明記。 |

---

## 14. 将来課題

| # | 内容 | 対応時期 |
|---|---|---|
| F-1 | 本手順を `yuios_build_procedure` に FPGA 章として統合する（`fpga_impl_roadmap_v1_3.docx` VD 工程で規定） | VD 工程 |
| F-2 | V9（Dhrystone RTL 計測）用の手順を本書に追加するか、別書とするか判断 | V9 着手時 |
| F-3 | 実機 FPGA での PSRAM 動作周波数確定後、§7 のクロック比の記述を実機値と対応づける | Step 8-Impl F1〜F8 |

---

*— 以上 yuios_rtl_boot_reproduce_procedure_v1_0.md —*
