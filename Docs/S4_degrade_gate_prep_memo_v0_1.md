# S4 デグレ絶対ゲート 準備メモ v0.1

- **作成日**: 2026-07-16 (CHAT98 / タイマー12)
- **目的**: 次チャット(CHAT99)が S4デグレ絶対ゲート(V1/V2全82ベクタ＋Dhrystone)を
  迷わず着手できるよう、基準・手順・ハマりポイントを事前整理する。
- **前提**: CHAT98 で案Y+X+Z による V5統合TB短縮版が **ALL PASS(8 checks)** 達成済。
  CPU改修(irq0_ack出力ポート追加=cpu_v0_1_FIXED)が入ったため、S4デグレゲートは必須。

---

## 1. S4 デグレゲートの合否基準(HANDOVER_CHAT96/97 確定)

| 対象 | 基準 | 意味 |
|---|---|---|
| V1/V2 全82ベクタ | **デグレゼロ(全PASS)** | irq0_ack追加後CPUが従来命令で不変 |
| Dhrystone | **826 / 48405 / P:20 完全一致** | 実プログラムでの絶対等価 |

**論点**: IE=0(割込禁止)では irq0_ack は一度も立たない見込み。
だが「見込み」で省略せず**実証で確定**すること(HANDOVER明記)。

---

## 2. ★次チャット最大のハマりポイント(事前に潰した知見)★

### 2.1 CPUファイルの二重性(重要)
- 本日使用の CPU は `ysd8800_cpu_v0_1_FIXED.sv`。
- **ファイル名は FIXED だが module 名は `ysd8800_cpu_v0_1`(同一)**。
  → V2 TB群(`ysd8800_cpu_v0_1 dut`)はファイル差替だけで通る。TB無改修。
- FIXED版は **`irq0_ack` 出力ポート(L263)を持つ**。V2 TB群はこれを接続しない。
  → iverilog 12.0 は未接続出力(floating output)を**警告止まりで通す**見込み。
    ★ビルド時に "port ... not connected" 系 warning が出ても FAIL ではない★
  → もし error になる場合のみ、TBの dut インスタンスに `.irq0_ack()`(空結線)追加で対処。

### 2.2 V2 TB は CPU単体(membus非依存)
- `tb_cpu_v2a/v2c/v2d/v2e_v0_1.sv` は `ysd8800_cpu_v0_1 dut` を直接叩く純CPUテスト。
- ビルドに membus/mmio_stub/psram は**不要**。必要なのは:
  decoder / regfile / alu / cpu(FIXED) / 各V2 TB のみ。
- 黄金値は `gen_v2_vectors*.py` が emu23 を呼んで動的生成 → SV TB が RTL と比較。

### 2.3 82ベクタの内訳
- V2 CPU等価検証の全TB群(v2a/v2c/v2d/v2e)で**合計82ベクタ**。
- (参考: V1=YSD8001 UART系 c1〜c4等も含む。CHAT86 §で82と確定)

---

## 3. 次チャット実行手順(推奨シーケンス)

### Step A: 環境再構築
```
mkdir -p /home/claude/w && cd /home/claude/w
apt-get install -y iverilog   # 12.0 (sudo不要・セッション標準は未インストール)
```

### Step B: V2ベクタ再走(82ベクタ)
1. 必要ファイル配置:
   `ysd8800_decoder_v0_1.sv` / `ysd8800_regfile_v0_1.sv` / `ysd8800_alu_v0_1.sv`
   / `ysd8800_cpu_v0_1_FIXED.sv` / `tb_cpu_v2a/v2c/v2d/v2e_v0_1.sv`
   / `gen_v2_vectors*.py` / `golden_v2a.txt`
2. gen_v2_vectors*.py で黄金値生成(emu23 v1.10使用・無変更)
3. 各V2 TB を iverilog -g2012 でビルド→vvp実行(timeout付)
4. **全82ベクタ PASS = デグレゼロ** を確認

### Step C: Dhrystone絶対ゲート
1. `dhry_all.c`(または dhry_all_ansi2.c)を scc23_v2_03 でコンパイル
   → hasm23 v1.04 → lnk23 v2.01 でリンク
2. emu23 v1.10 で実行
3. **826 / 48405 / P:20 完全一致**を確認
   (Dhrystoneは回帰チェック必須項目。scc23/hasm23/lnk23/emu23全ツールの健全性を担保)

### Step D: 判定
- V2全82 PASS かつ Dhrystone 826/48405/P:20 一致 → **S4ゲート通過**
- irq0_ack が IE=0 中に立たないことも実証(波形 or カウンタで確認)

---

## 4. CHAT98(本日)確定成果物 md5

| ファイル | md5 | 種別 |
|---|---|---|
| v5t_ack_short.asm (v0.3) | `41d3bcc7c92c2f994f48e430f700957d` | 新規(内100) |
| v5t_noack_short.asm (v0.3) | `2acd58c733b8c368073c5e8ac3484994` | 新規(内100) |
| v5t_ack_short.hex | `12d86038856aedb2c6ed79e3a0f8c322` | 新規 |
| v5t_noack_short.hex | `be2ddc6c3b1bf69f8eb7b34b4483054c` | 新規 |
| tb_cpu_v5timer_short_poc.sv (v0.2) | `ef25eadc0ca6472f4da736746bdc5ace` | 新規(案X+Y+Z) |
| ysd8800_mmio_stub_v0_5_poc.sv | `75e0595a23fbfb5d2e633a1a0fd213e7` | ★是正版(§5参照)★ |

### emu23 v1.10 黄金値(短縮版・確定)
| プログラム | CNT | OUTC | HALT |
|---|---|---|---|
| v5t_ack_short (内100) | 3 | 200 | 正常(PC=0152) |
| v5t_noack_short (内100) | 1 | 200 | 正常(PC=0152) |

### RTL統合TB実測値(比8:1/MAX_CYC=3M・ALL PASS)
| プログラム | CNT | OUTC | HALT cyc |
|---|---|---|---|
| ack (RTL) | 72 | 200 | 2903717 |
| noack (RTL) | 1 | 200 | 2880161 |
※CNTがemu23(3)とRTL(72)で異なるのは CPI差(emu=1/RTL≒18)による**想定通り**。
  だから絶対CNT一致を求めず範囲判定(CNT>=2)にした(案Z=原則80の実証)。
  noack=1 は論理的絶対値ゆえ両者一致。

---

## 5. ★★S5で必須: mmio_stub ナレッジ登録(再発防止・最重要)★★

### 5.1 登録漏れの二重発生を検出(原則79の実証)
- プロジェクトナレッジの `ysd8800_mmio_stub_v0_5_poc.sv` は
  md5=`3058ffbb…`(旧版) のまま。
- CHAT97 HANDOVER §7 の期待値 `e271f571…`(是正版)が**未登録**だった。
- つまり CHAT96③ の登録漏れ(CHAT97で指摘)が、**CHAT97でも再度登録されず二重で漏れた**。
- CHAT98 で実源に再適用し、割込経路3点(下記)を復元:
  - `input logic irq0_ack` ポート追加
  - `ysd8800_ysd8002_v0_2_poc u_ysd8002`(v0_1→差替)
  - `.irq0_ack(irq0_ack)` 中継結線
- **本日の再適用版 md5 = `75e0595a23fbfb5d2e633a1a0fd213e7`**
  (CHAT97 の `e271f571…` とはコメント字面差のみ。論理結線は同一。
   コメント除去後の論理ハッシュ = `d71e125ffa2369cf72c91bd2998c397e`)

### 5.2 次チャットの必須アクション
1. ★この `75e0595a…` 版を**必ずナレッジ登録**する★(三度目の漏れを起こさない)
2. 登録後、`fpga_source_version_ledger` に mmio_stub 版数・md5 を記録
3. RTL版数繰上げ(v0_2_poc→次版, cpu/mmio_stub/membus 版数整合)
4. emu23 無変更ゆえ黄金 ref 再ベースライン不要

---

## 6. kaizen 登録候補(CHAT99 で番号確定)
- **原則79(確定推奨)**: マルチファイル修正のナレッジ登録は部分/全体の登録漏れが起きうる。
  次セッション冒頭で修正全ファイルの md5 を期待値照合し、不一致を実源へ再適用(KY34応用)。
  ★本チャットで「二度漏れ」を実証。照合を怠ると漏れが世代を跨いで蓄積する★
- **原則80(確定推奨)**: emu23(CPI=1)基準の cycle値(MAX_CYC/CNT期待値)を
  RTL(実CPI≒18)判定に流用しない。RTL合否は完走＋論理性質(範囲判定)で。
- **原則81候補(本日)**: 短縮版TBの MAX_CYC は「内1/10だから総1/10」と机上で決めず、
  短縮版を1回実走させ実測 cyc/OUTC から必要MAX_CYCを逆算する。
  (本日 800k で不足→実測14545×200=291万→3Mで完走。机上見積りの1回目は外した)

---

## 7. 本日KY(実施済・成功)
- ★案Y のテストプログラム改版で emu23 黄金値取り直しを忘れる危険★
  → 防止策通り「改版直後に emu23 実行→値記録→TB期待値に転記」を厳守し回避成功。
  ループ変更(内1000→100)と黄金値取り直し(CNT3/1)をワンセットで実施した。

---

（以上 S4_degrade_gate_prep_memo_v0_1.md / 2026-07-16 / CHAT98）
