# HANDOVER_CHAT80.md — FPGA V3完了 → V3.5（MMU統合）引き継ぎ

- 文書名: HANDOVER_CHAT80.md
- 版数: v1.0
- 作成日: 2026-07-11
- 前チャット: CHAT80「FPGA実装の続き（V3 メモリ・バス・MMIOデコード／PSRAM統合）」
- 次チャット作業: **V3.5（MMU統合）着手**
- 黄金リファレンス: emu23 v1.09（emu23_v109.c、`--mmu`オプションでFM-11方式16ページMMU）
- 関連台帳: fpga_source_version_ledger_v1_1.md（FPGAソース側）／tool_version_ledger_v1_10.md（ツールチェーン側）

---

## 0. 最初に読むもの / セッション開始プロトコル

次チャット開始時、以下を順に実施（規約）:

1. **本HANDOVER文書**を確認
2. `claude_tool_operation_guide_v1_0.txt` を1回参照（規律1〜5。ツール呼び出しの書式崩れ防止）
3. `kaizen.txt` を参照。特に**原則59〜63**（RTL/Icarus固有＋本チャットで新設の原則63）
4. 工程確認: 「進捗と予定の確認(latest)」の最新ロードマップを参照 →「工程ヨシ!」「次工程の確認ヨシ!」
5. KY活動（1つ挙げ、防止策を作業中に実行）
6. ユーザーの「ご安全に!」で作業開始

**環境**: Icarus Verilog は毎セッション未インストール。`apt-get install -y iverilog` で 12.0 が入る（原則62）。最初に実施すること。

---

## 1. 現在地（2026-07-11時点）

```
Step 8 FPGA SystemVerilog 実装
   ├ ✅ V(-1) emu23 MMU復活移植（v1.08）
   ├ ✅ V0  実装仕様確定・環境定義
   ├ ✅ V1  CPUコア実装（decoder/regfile/alu/cpu、FSM全段）
   ├ ✅ V2  CPUコア単体検証（82ベクタ ALL PASS・CPIテーブルv1.0）
   ├ ✅ V3  メモリ・バス・MMIOデコード／PSRAM統合  ← 本チャットで完了
   ├ ⬜ V3.5 MMU統合                              ← 次の作業
   ├ ⬜ V4  UART / V5 タイマー / V6-A/B ストレージ
   ├ ⬜ V7/V8 初期イメージロード・YUI OS実機ブート
   └ ⬜ VD  Dhrystone / YUI OS 実機確認
```

---

## 2. V3で完成したもの（次工程の土台）

### 2.1 V3メモリサブシステム構成

```
CPU抽象バスI/F ─ アドレスデコーダ ─┬─ MMIOスタブ（$FC80-$FFFF）
                                   └─ CDCブリッジ ─ PSRAMコントローラ（$0000-$FC7F）
   ↑ CPUコアは無改修                    ↑ req/ack 4相ハンドシェイク・2FF同期器
                                          CPU 4MHz ⇔ PSRAM 高速クロック（案A CDC同期方式）
```

**重要**: V1のCPUコア（`ysd8800_cpu_v0_1`）は `mem_ready` が立つまで滞留するFSMなので、V3のPSRAM統合でも**CPUコアFSMは一切変更していない**（`ysd8800_v3_membus_v0_1` を差し替えるだけで理想メモリ⇔PSRAM経路を切替可能）。

### 2.2 V3 RTL一式（新規5本）

| ファイル | 版 | 役割 |
|---|---|---|
| ysd8800_addr_decoder_v0_1.sv | v0.1 | $FC80境界でRAM/MMIO振り分け（純組合せ） |
| ysd8800_mmio_stub_v0_1.sv | v0.1 | MMIOスタブ（即時ready・固定0x00・アクセスカウンタ診断） |
| ysd8800_cdc_bridge_v0_1.sv | v0.1 | CPU⇔PSRAM CDCブリッジ（req/ack・2FF同期器） |
| ysd8800_psram_ctrl_v0_1.sv | v0.1 | PSRAMビヘイビアモデル（通常12/リフレッシュ15サイクル可変レイテンシ） |
| ysd8800_v3_membus_v0_1.sv | v0.1 | 上記4本を結線した統合ラッパー |

### 2.3 V3 検証TB一式（新規7本）・全ALL PASS

| TB | 対象 | 結果 |
|---|---|---|
| tb_addr_decoder_v0_1.sv | デコーダ+MMIOスタブ単体 | 6/6 PASS |
| tb_cdc_bridge_v0_1.sv | CDCブリッジ単体（背中合わせ連続要求含む） | 4/4 PASS |
| tb_psram_ctrl_v0_1.sv | PSRAMモデル単体 | 2/2 PASS |
| tb_bridge_psram_integ_v0_1.sv | ブリッジ+PSRAM実結合 | 2/2 PASS |
| tb_cpu_v3_v0_1.sv | 実CPU+V3（ALU系・V2-aベクタ再利用） | 20/20 PASS |
| tb_cpu_v3mem_v0_1.sv | 実CPU+V3（LDW/STW絶対・XI・間接・PUSH/POP・LDB/STB） | 5/5 PASS |
| tb_cpu_v3boundary_v0_1.sv | 実CPU+V3（境界$FC7F/$FC80＋JSR/RET/BEQ複合） | 1/1 PASS |

### 2.4 ベクタ生成器（黄金値の単一ソース・偽合格防止）

| 生成器 | 版 | 対象 |
|---|---|---|
| gen_v2_vectors.py | v0.1（既存） | ALU系20（V3で再利用） |
| gen_v3_mem_vectors.py | v0.1（新規） | メモリ系5 |
| gen_v3_boundary_vectors.py | v0.1（新規） | 境界+JSR/RET/BEQ 1（簡易2パスアセンブラ内蔵） |

すべて **emu23で実行して黄金値を自動取得**する方式（期待値を手計算で埋めない）。

---

## 3. ★最重要★ 本チャットで発見・修正したCPUコアのバグ

### 3.1 内容

`ysd8800_cpu_v0_1.sv` のバス出力`always_comb`（状態別 mem_addr/mem_rd/mem_wr 振り分け）に **S_SUBOP（EXTプリフィックス0x1Fサブopcodeフェッチ）のcaseが欠落**しており、`mem_rd` が常に0のまま出力されていた。

対象命令: **PUSH/POP/LDB/STB 等、0x1F経由の全命令**。

### 3.2 なぜV1/V2で見つからなかったか（原則63として一般化）

V1/V2のTBは `assign mem_ready = 1'b1;`（要求信号を一切見ない理想メモリ）だったため、`mem_rd=0` でも `mem_ready` は無条件に1を返し、`mem_rdata` も常時有効だった。→ 最終レジスタ値に影響せず「82ベクタALL PASS」の裏で完全に見過ごされた。

V3の実req/ack型メモリで初めて「mem_rd=0→要求未発行→ack永久に来ず→ハング」として顕在化。

### 3.3 修正

```systemverilog
S_SUBOP: begin mem_addr = rf_pc; mem_rd = 1'b1; end
```

**ysd8800_cpu_v0_1.sv は v0.5.6 → v0.5.7 に版数更新済み。次チャットは必ず v0.5.7 を使うこと。**

### 3.4 教訓（kaizen.txt 原則63として追記済）

> **理想メモリ（mem_ready固定1）のTBは「バス要求信号のアサート漏れ」を検出できない。理想メモリTBのALL PASSは必要条件であって十分条件ではない。**
>
> 新規state・新規命令クラスを追加する際は、「バス出力always_combにその state の case が存在するか」を、状態遷移側の `if (mem_ready)` 条件の有無と機械的に突き合わせる。

**V3.5でMMU用の新規stateやアドレス変換パスを追加する場合、この照合を必ず行うこと。**

---

## 4. V3で確定した設計方針（V3.5が引き継ぐ前提）

| 項目 | 確定内容 | 根拠 |
|---|---|---|
| ターゲット | Sipeed Tang Nano 9K（GW1NR-9・QN88P） | 既定方針 |
| CPUクロック | 4MHz（27MHz水晶からPLL） | 既定方針 |
| メインメモリ | オンチップPSRAM 64Mbit（HyperRAM系） | 既定方針（工程表のBRAM記述はv1.1で是正済） |
| PSRAM IP | **Gowin公式 PSRAM HS IP を第一候補**（1:2ギア比）。OSS版zf3はTang Nano 9Kでタイミングクロージャ失敗が既知のため条件付き | v3_design_memo_v0_2 §3 |
| クロックドメイン | **案A（CDC同期方式）**。CPUコア無改修・req/ack＋2FF同期器 | v3_design_memo_v0_2 §4.1 |
| バス粒度 | byte-enable（LDB/STB対応のため必然） | 既定方針 |
| **★物理アドレス配線** | **「インタフェースは将来幅（20bit+）・実装は現在幅（上位ビット0固定）」** | v3_design_memo_v0_2 §4.3（**V3.5のMMUがこの上位ビットを埋める**） |
| MMIOスタブ | 即時ready・固定0x00・ライト無視・アクセスカウンタ診断あり。V4以降で実デバイス化 | v3_design_memo_v0_2 §4.2 |
| **★MMIO協調ベクタ** | **emu23はMMIOにデバイス固有値を返すため、協調等価ベクタからMMIOアクセスを除外する** | v3_design_memo_v0_2 §4.2（V3.5でも同様に守ること） |
| リフレッシュ | HyperRAMは約0.05%の頻度でレイテンシ2x（12→15サイクル）。TBに可変レイテンシケースを組込済 | v3_design_memo_v0_2 §3.1 |
| FPGAゲート | **cycle一致は対象外**（emu23はCPI=1固定のため定義上不一致）。ゲート＝「完走＋論理結果一致」のみ | 既定方針 |

---

## 5. V3.5（MMU統合）作業のとっかかり

### 5.1 工程表の定義（fpga_impl_roadmap_v1_1.docx）

V3.5 = MMU統合。**MMU有効/無効の動作分離を明文化**（指摘3対応）。正解リファレンスは **emu23 v1.08（`--mmu`）との協調等価＋設計書単体TBの両肺**（指摘4対応）。

### 5.2 設計書

`YSD8800_MMU_Design_v1_1_0.docx`（FM-11方式16ページMMU・物理1MB/256ページ）。emu23実装（`emu23_v109.c`、`--mmu`）が黄金。

### 5.3 V3が用意した接続点

- 物理アドレス線は**既に20bit幅で引いてある**（V3では上位ビット0固定・ソース内にコメントで明記済）。V3.5でMMUがここを埋める形になる。
- CPUコアとPSRAM経路の間（`ysd8800_v3_membus_v0_1` の入口）にMMUを挿入するのが自然な構成。CPUコア側は論理アドレスのまま、MMUが物理アドレスへ変換して下流（デコーダ）へ渡す。
- **【注意】アドレスデコーダの $FC80境界判定は論理アドレスに対して行うのか物理アドレスに対して行うのか**、MMU設計書とemu23実装を実照合して確定すること（KY34）。V3では恒等写像なので区別が無かったが、V3.5では本質的な差が出る。**これが V3.5 最初の設計論点になる見込み。**

### 5.4 V3から持ち越した設計項目（reset vector）

reset解除時点でベクタ$0000が正しく読める必要があるが、SPI Flash→PSRAM展開方式ではコピー完了前にCPUがfetchする競合が起きうる。V3ではCPUへのreset保持信号の余地を残す方針としたのみ（**V7/V8で本格対応**）。V3.5のスコープ外だが、MMU有効時のreset時MMU状態（恒等写像リセット）と絡むため頭の片隅に置くこと。

---

## 6. ★申し送り（未解消・要対応）★

### 6.1 V3成果物のプロジェクトナレッジ未登録

**本チャットで作成したV3のRTL5本・TB7本・生成器2本・修正版CPUコアが、すべてプロジェクトナレッジに未登録。**

V2-b/c/dで既に同じ事故（実装完了だがソース未登録で監査不能）が起きており、`fpga_source_version_ledger_v1_1.md` §7所見にも記録されている。**次チャット開始時にまず登録状況を確認し、未登録ならユーザーへ登録を依頼すること。**

登録対象（`/mnt/user-data/outputs/v3_rtl/` に出力済）:
```
ysd8800_addr_decoder_v0_1.sv       ysd8800_mmio_stub_v0_1.sv
ysd8800_cdc_bridge_v0_1.sv         ysd8800_psram_ctrl_v0_1.sv
ysd8800_v3_membus_v0_1.sv          ysd8800_cpu_v0_1_FIXED.sv（v0.5.7・要差替）
tb_addr_decoder_v0_1.sv            tb_cdc_bridge_v0_1.sv
tb_psram_ctrl_v0_1.sv              tb_bridge_psram_integ_v0_1.sv
tb_cpu_v3_v0_1.sv                  tb_cpu_v3mem_v0_1.sv
tb_cpu_v3boundary_v0_1.sv
gen_v3_mem_vectors.py              gen_v3_boundary_vectors.py
v3mem_vectors/  v3boundary_vectors/（golden・expected hex）
```

文書（`/mnt/user-data/outputs/`）:
```
v3_design_memo_v0_3.md             fpga_v1_cpucore_design_v1_2.md
fpga_impl_roadmap_v1_1.docx        fpga_source_version_ledger_v1_1.md
kaizen_updated.txt（原則63追記版・kaizen.txtへ反映要）
```

### 6.2 V2-b/c/d/e成果物の未登録（既存の持ち越し）

`fpga_source_version_ledger_v1_1.md` §5/§7参照。V2-b(41)/V2-c(64)/V2-d(75)ベクタのALL PASS実績はあるがソース実体なし。V3では V2-a ベクタのみ再利用可能だった。**V3.5でも同様に、再利用できるのはV2-aのみ**である点に注意。

### 6.3 ysd8800_cpu_v0_1.sv のファイル名と実版数の乖離

ファイル名は `_v0_1` 固定・実版数はヘッダで管理（v0.5.7）という意図的な運用。V1完成時に一括リネーム予定。リネーム忘れ防止のため台帳で追跡中。

---

## 7. ビルド・実行手順（Icarus 12.0）

```bash
# 環境（毎セッション必要）
apt-get install -y iverilog     # 12.0が入る
iverilog -V | head -1           # 確認

# コンパイル順: decoder→regfile→alu→cpu→V3周辺→統合ラッパー→tb（依存順）
iverilog -g2012 -o tb.vvp \
  ysd8800_decoder_v0_1.sv ysd8800_regfile_v0_1.sv ysd8800_alu_v0_1.sv \
  ysd8800_cpu_v0_1.sv \
  ysd8800_addr_decoder_v0_1.sv ysd8800_mmio_stub_v0_1.sv \
  ysd8800_cdc_bridge_v0_1.sv ysd8800_psram_ctrl_v0_1.sv \
  ysd8800_v3_membus_v0_1.sv \
  tb_cpu_v3_v0_1.sv

# ★ビルドと実行は必ず分離（&&チェーン禁止）。間でタイムスタンプ確認
ls -la tb.vvp
timeout 30 vvp tb.vvp            # ★timeout必須（rc=124=組合せループ/無限ループ）

# emu23（黄金）のビルド
gcc -O2 -o emu23 emu23_v109.c
./emu23                          # 起動時に版数表示（v1.09）を確認
# 黄金取得は ./emu23 <bin> -n <N>（-qなし。-qはtrace抑制）

# ベクタ生成（emu23が同ディレクトリに必要）
python3 gen_v3_mem_vectors.py
python3 gen_v3_boundary_vectors.py
```

---

## 8. 本チャットで得た技術的知見（V3.5でも有効）

- **CDCブリッジのreq取りこぼし**: CPUコアは `S_MEMR_LO→S_MEMR_HI` のように **mem_rdを下げずにアドレスだけ変える背中合わせアクセス**を多用する。mem_rdの立下りを新規要求の区切りに使うと握りつぶされる。→ ack後1サイクルだけreqを強制的に下げてギャップを作る方式で解決。
- **PSRAMのSPリセット差異**: emu23はリセット時 SP=0xFC7E 既定、RTLは S_RESET_HI で SP<=0x0000。**全ベクタ先頭に `LDW SP,#imm16` を明示挿入して中和**する（V2-d方式の踏襲）。
- **emu23トレースのパース**: `PC=.. SP=.. F=.. A=.. B=.. X=..` 形式。`-q` を付けるとtraceが抑制されるので黄金取得時は付けない。
- **SystemVerilogのlocalparam演算**: 32bit演算はオーバーフローしうる。確率計算等は `longint` で計算してからスライスする（本チャットで実際に踏んだ）。
- **Icarus 12.0**: `always_comb` 内の定数ビット選択は `assign` で外出しする（原則59・再発多数）。

---

## 9. 関連文書一覧

| 文書 | 版 | 内容 |
|---|---|---|
| v3_design_memo_v0_3.md | v0.3 | V3設計メモ（設計決定事項の根拠はv0.2、実装結果はv0.3 §8/§9） |
| v3_design_fixorder_v1_0.docx | v1.0 | V3設計への有識者レビュー指示書（指示No.1〜9） |
| fpga_v1_cpucore_design_v1_2.md | v1.2 | V1 CPUコア設計書（§7.1にS_SUBOPバグ修正を追記） |
| fpga_impl_roadmap_v1_1.docx | v1.1 | 工程表（BRAM→PSRAM是正・V3完了記録） |
| fpga_source_version_ledger_v1_1.md | v1.1 | FPGAソース版数台帳（§9にV3一式） |
| YSD8800_MMU_Design_v1_1_0.docx | v1.1.0 | **★V3.5の主設計書** |
| kaizen.txt | （原則63追記版） | 設計・デバッグ原則。**原則59〜63がRTL関連** |
| yuios_memmap_design_v2_4.md | v2.4 | MMIO境界$FC80のsingle source of truth |
| emu23_v109.c | v1.09 | 黄金リファレンス（`--mmu`でMMU有効） |
| claude_tool_operation_guide_v1_0.txt | v1.0 | ツール操作規律1〜5 |
