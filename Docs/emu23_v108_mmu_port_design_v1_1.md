# emu23 v1.08 MMU復活移植 設計検討メモ

| 項目 | 内容 |
|---|---|
| 文書名 | emu23_v108_mmu_port_design_v1_1.md |
| 版数 | ~~v0.2（再レビュー対象）~~ → ~~v1.0（承認・実装着手可）~~ → **v1.1（実装完了反映版）** |
| 作成日 | 2026-06-24 |
| 対象工程 | Step 8 FPGA実装 V(-1)：emu23 v1.08 MMU復活移植 |
| ステータス | ~~再レビュー待ち~~ → ~~再レビュー承認可（review v2.0）＋ユーザー判断1/2受領済み → v1.0確定／実装着手可（原則43クリア）~~ → **実装完了・検証ゲート G1〜G4・非干渉・G2 全PASS（2026-06-25）／emu23_v108.c 本番確定済み** |
| 移植元 | emu22-1_10.c（MMU実体あり・実view照合済み） |
| 移植先 | emu23_v107.c（MMU完全欠落＝grep 0件で実証・KY34） |
| 設計リファレンス | YSD8800_MMU_Design_v1_1_0.docx（FM-11方式・**実体はUTF-8テキスト**） |

## 改版履歴
| 版 | 日付 | 変更内容 |
|---|---|---|
| v0.1 | 2026-06-24 | 初版（ドラフト）。差し戻し（M指摘3件）。 |
| v0.2 | 2026-06-24 | レビュー指摘 M-1/M-2/M-3/C-1/C-2/D-1/E-1/N-1/N-2 を反映。全出典を実view照合値に貼り直し。論点A・Cを諮問から確定へ。 |
| v1.0 | 2026-06-24 | review v2.0で承認可（M/C/N全クローズ）。ユーザー判断受領：判断1=**(b)再生成**／判断2=**デバッガ移植スコープ含める**。§5 D-1・§6 E-1 を留保→確定へ。実装着手可。 |
| v1.1 | 2026-06-25 | **実装完了反映版。** §3.1〜3.3・確定A（フェッチ26箇所 fetch8化）・判断2（デバッガ mmu/physmem）を emu23_v108.c に実装完了。検証ゲート §10 全PASS（G1: mem[cpu.pc 残存0・fetch8×26／G3: Dhrystone 826/48405/P:20 一致・v1.07 baseline と --mmu無効 v1.08 完全一致／G4: test_mmu1〜4_poc 付録B期待出力で全PASS／非干渉: fib_verify_combined MD5一致／**G2: 道2フルビルドで yuios.bin=56416 バイト一致・lnk23配置 forth@\$5100/kernel@\$0000/reloc=2 が build_procedure v1.8 §4.11.5 I1実績と一致**）。emu23_v108.c 本番確定・tool_version_ledger v1.6 改版済み。§11 として実装結果・既知の差異注記（test_mmu4 vs MMU設計書§9-4）を新設。旧版情報は取消線で保持（KY41）。 |

---

## 0. 本メモの位置づけ

引継ぎ HANDOVER_CHAT66.md §3 の V(-1) 設計検討。原則43によりレビュー承認まで実装着手しない。
**v0.2では、v0.1で記憶/推測由来だった出典を全て移植元 emu22-1_10.c の実viewで貼り直した**
（レビューM-1指摘＝本日KY「再構成リスク」の顕在化を是正）。

---

## 1. デグレ事実の実証（KY34）

| 確認項目 | 結果 |
|---|---|
| emu23_v107.c の `mmu_translate`/`phys_mem`/`MCR_EN` シンボル数 | **0**（grep -c 実証） |
| emu22-1_10.c の MMU実体 | あり（全シンボル実在） |

---

## 2. 移植元 emu22 v1.10 の MMU 仕様（**実view照合・出典貼り直し済み**）

| 要素 | 出典行（emu22-1_10.c） | 内容 |
|---|---|---|
| 制御レジスタ定義 | :105-108 | `MMU_PTR_BASE=0xFF00`／`MMU_MCR_ADDR=0xFF10`／`MCR_EN=0x01`／`MCR_KRN_PROT=0x02` |
| 物理メモリサイズ | :61 | `PHYS_MEM_SIZE = 1MB` |
| mmu_mode グローバル | :112 | `--mmu` で1 |
| phys_mem | :116 | mmu時 malloc 確保 |
| mmu_t 構造体・mmu 変数 | :118-124 | ptr[16], mcr |
| `mmu_translate()` | **:127-135**（関数本体は127開始、return文含め135まで） | MCR_EN=1で`(PTR[page]<<12)\|offset`、=0で恒等写像 |
| `mmu_reset()` | **:137-141**（v0.1の:137-140を訂正・N-2） | PTR[n]=n、MCR=0 |
| `phys_rd8()/phys_wr8()` | :355-361 | mmu時`phys_mem[pa&0xFFFFF]`、非mmu時`mem[]` |
| `fetch8()` | **:432-435**（v0.1の:432を訂正） | `phys_rd8(mmu_translate(a))` |
| メインIRフェッチ | **:753** | `cpu.ir = fetch8(cpu.pc++)`（M-2の核心） |
| binロード（mmu時） | **:538**（v0.1の誤記:749を訂正・M-1核心） | `fread(phys_mem, 1, PHYS_MEM_SIZE, f)` |
| binロード（非mmu時） | :545 | `fread(mem, 1, MEM_SIZE, f)` |
| MMUデバッガコマンド | :1253（mmu）/:1284（physmem） | E-1参照 |
| --mmu オプション | :1352 | `mmu_mode=1` |

---

## 3. 移植差分（emu23 v1.07 → v1.08）

### 3.1 新規追加（v1.07 に不在）
§2の各要素（マクロ・グローバル・mmu_t・mmu_translate・mmu_reset・phys_rd8/wr8・fetch8・--mmu）を
移植元からそのまま移植。emu23 v1.07 には fetch8 が存在しないため新規追加。

### 3.2 既存関数の中身差し替え（関数名一致・中身をMMU対応へ）
v1.07 構造：各アクセス関数は「MMIO判定（論理アドレス）→末尾 `mem[a]` フォールバック」。
**MMIO判定部は温存し、末尾フォールバックのみ MMU 変換経由へ差し替える。**

| 関数 | v1.07現状（出典行） | v1.08改修方針 |
|---|---|---|
| `rd8` | UART/SD MMIO→`return mem[a]`（:629） | MMUレジスタ読出追加＋末尾`phys_rd8(mmu_translate(a))` |
| `wr8` | UART/SD MMIO→`mem[a]=v`（:650付近） | MMUレジスタ書込追加＋末尾`phys_wr8(mmu_translate(a),v)` |
| `rd16` | UART/TIMER/SD/IRQC MMIO→`mem[a]\|mem[a+1]`（:491） | **MMUレジスタ範囲は rd8 へ委譲**（C-2）＋末尾を変換経由（ページ境界対応） |
| `wr16` | 各MMIO→`mem[a]=…`（:615-616） | **MMUレジスタ範囲は wr8 へ委譲**（C-2）＋末尾を変換経由（ページ境界対応） |
| `fetch16` | `mem[a]\|mem[a+1]`（:652-654） | `fetch8(a)\|fetch8(a+1)<<8`（ページ境界対応） |

**C-2（委譲構造・移植元 :403-404／:421-423 で実証）**：
rd16/wr16 内で `la>=MMU_PTR_BASE && la<=MMU_MCR_ADDR` の範囲は rd8/wr8 経由に委譲する。

### 3.3 命令フェッチの mem[] 直アクセス（**26箇所**・N-1訂正）
v1.07 は命令フェッチ系で `mem[cpu.pc++]` を直使用（**26箇所**＝メインIR :1010 を含む。v0.1の25は数え漏れ）：
- `cpu.ir = mem[cpu.pc++]`（:1010）
- `uint8_t sub = mem[cpu.pc++]`（:1062）
- `uint8_t rb = mem[cpu.pc++]`（:1125〜:1309、各命令オペランド）
- 16bitオペランドは全て `fetch16(cpu.pc)` 経由（21箇所）＝fetch16改修で自動対応。

---

## 4. 確定事項（v0.1の「論点」をレビュー指摘で確定）

### 確定A（旧論点A・M-2）：命令フェッチは**全26箇所を fetch8(cpu.pc++) に置換**
- 根拠：移植元 v1.10 は `cpu.ir = fetch8(cpu.pc++)`（:753）、`mem[cpu.pc++]` 直アクセス **0件**（grep実証）。
  移植元は既に全フェッチ fetch8 化済み。これが v1.10 思想。
- v0.1のA-2（マクロ化）/A-3（非変換）は撤回。**A-1（個別fetch8化）で確定**。退行回避のため非変換案は不採用。
- 実装上の留意：26箇所の機械的置換のため、置換後に `grep -c "mem\[cpu.pc" emu23_v108*.c == 0` を
  検証ゲートに加える（移植漏れ検出・1変更1検証）。

### 確定B（旧論点B・C-1）：無効時 byte-exact 懸念は杞憂
- mmu_mode=0時：mmu_translateは恒等写像、phys_rd8/wr8は mem[] を返す（:356-357）。
  byte-exactは**出力バイナリの一致**を指し実行経路コストと無関係。経路完全一致にこだわる必要なし。
- ただしC-1推奨に従い、**v1.07のmem[a]直返しと挙動一致を1ケースだけ実機差分確認**する（検証項目へ）。

### 確定C（旧論点C・M-3）：phys_mem 一本化
- 根拠：移植元 mmu時 `fread(phys_mem,…)`（:538）／非mmu時 `fread(mem,…)`（:545）と分岐済み。
  二重持ちなし。**phys_mem 一本化で確定**。v0.1 §5の「どちらが正本か精査」項目は削除。

---

## 5. 実装前の追加調査（D-1・縮小）
- ~~phys_mem/mem[]使い分け~~ → **確定C で解決済み・削除**。
- **D-1（検証ケース正解集合）**：YSD8800_MMU_Design_v1_1_0.docx 付録B（:396-406）に検証テスト一覧が実在：
  - test_mmu1_basic（MMU OFF基本）／test_mmu2_bitops（ビット演算10命令）／
    test_mmu3_mmu_on（ページ変換 page4/5）／test_mmu4_boundary（ページ境界またぎ $4FFF/$5000）／
    kernel v0.6（MMU OFF・emu22比較）。全PASS実績あり。
  - **ただし test_mmu*.asm 本体は emu22-1_10.c 内に無い（grep 0件）。** ~~ソース発掘 or 設計書記載の
    期待出力から再生成の要否を実装着手前にユーザー確認する~~
    → **【判断1 受領＝(b)再生成で確定】** 設計書付録Bの期待出力（test_mmu1: HELLO/ARITH ／
    test_mmu2: AND:P/OR:P…SAR:P ／ test_mmu3: MMU ON/WR:P/ISO:P/DONE ／
    test_mmu4: BOUND/V1:P/V2:P/DONE）を正解として、**hasm23 v1.04 で再生成する**。
    再生成物は KY28/38 に従い `test_mmu1_basic_poc.asm`〜`test_mmu4_boundary_poc.asm` の命名とし、
    本番ソースと混在させない。kernel v0.6（T0/T1 交互出力）は別途 emu22 比較で扱う。
    各 _poc を期待出力で PASS 判定（検証の自己完結）。
  - 設計書§9の重要制約：phys_memは**$FF初期化**（FPGA未初期化RAM模擬）。書込→MMU OFF読返し検証は
    事前$00クリアが必要（:261）。これは移植時の挙動再現必須項目。

---

## 6. E-1：MMUデバッガコマンドの移植スコープ
移植元にMMU対応デバッガコマンド実在（mmu表示/en/dis :1253、physmemダンプ :1284、help追記 :1311）。
Step8デバッグ容易性に直結。~~移植スコープに含める方針を提案するが、最終可否はレビュー判断に委ねる。~~
→ **【判断2 受領＝移植スコープに含めるで確定】** 移植元 :1253（`mmu`／`mmu en`／`mmu dis`／`mmu ptr N V`）、
:1284（`physmem A [n]` 物理ダンプ）、:1311（helpへのMMUコマンド追記）を v1.08 のデバッガに移植する。
いずれも `mmu_mode` ガード付きで、非mmu時は無効（既存コマンド体系に非干渉）。

---

## 7. 完了条件（引継ぎ §3.4・不変）
1. `--mmu` 無効時、yuios.bin が **byte-exact 一致**でブート（56416バイト）。
2. MMU設計書 v1.1.0 検証ケース（§5 D-1の test_mmu1〜4 + kernel v0.6）全通過。
3. 回帰ゲート維持：Dhrystone **826/48405/P:20**・yuios.bin **56416バイト**。

---

## 8. 本日のKY（危険予知）と顕在化の総括
- **危険**：移植元非現存前提の記憶再構成→誤配置混入。
- **顕在化**：v0.1で移植元が現存したにもかかわらず一部出典を実照合せず記憶で記載（binロード:749誤記等）。
  レビューM-1で指摘され差し戻し。**KY防止策①（実view照合）が一部未実行だったのが原因**。
- **是正**：v0.2で全出典を実viewで貼り直し（§2の表）。論点A/Cは移植元viewで答えが出ており諮問不要だった。
- **再発防止（kaizen候補）**：「出典付き」と書く項目は、書く直前にその行を実viewする。
  特に「精査する」「確認する」と書いた項目こそ先に実viewして条件分岐で先送りしない（HANDOVER学び4と同根）。

---

## 9. 次アクション（v1.0確定後）
~~v0.2 の再レビューを依頼。E-1スコープ可否・D-1のtest_mmu再生成方針の判断を受領後、v1.0化 → 承認 → 実装着手。~~
→ review v2.0承認可＋判断1/2受領済み。**v1.0確定・実装着手可（原則43クリア）**。実装手順（次回作業開始時）：
1. 移植元 emu22-1_10.c の MMU実体を emu23_v107.c へ移植 → 実験ビルド `emu23_v108_poc.c`（KY28/38：本番不変）。
   §3.1（新規追加）→§3.2（既存関数差し替え＋C-2委譲）→確定A（フェッチ26箇所 fetch8化）→判断2（デバッガ）の順。
2. test_mmu1〜4 を hasm23 v1.04 で再生成 `test_mmu*_poc.asm`（判断1）。
3. 検証ゲート G1〜G4 適用（§10）。全PASS後に `emu23_v108.c` へ確定。
4. tool_version_ledger 改版（emu23 v1.08登録＋「MMU対応」バナー陳腐化是正＝旧指摘5）／設計書改版（KY41）。

## 10. 検証ゲート（実装フェーズで適用）
- G1：`grep -c "mem\[cpu.pc" emu23_v108*.c` == 0（確定A 置換漏れ検出）
- G2：--mmu無効ビルドで yuios.bin == 56416 byte かつ byte-exact
- G3：Dhrystone 826/48405/P:20
- G4：test_mmu1〜4_poc（hasm23 v1.04再生成・判断1）を付録B期待出力でPASS判定 ＋ kernel v0.6（emu22比較）

---

## 11. 実装結果（v1.1・2026-06-25 実装完了反映）

### 11.1 検証ゲート実測値

| ゲート | 内容 | 実測 / 結果 |
|---|---|---|
| G1 | `grep -c "mem\[cpu.pc" emu23_v108.c` == 0 | **0**（PASS）。`fetch8(cpu.pc` は **26箇所**＝確定A の置換数と一致 |
| G2 | 道2フルビルドで yuios.bin == 56416 byte | **56416 バイト（0xDC60）一致**（PASS）。md5=a1f1001fe96d9c2e7b4db8e47d4046e4。lnk23配置 forth@\$5100・kernel@\$0000・reloc=2・418 global解決＝build_procedure v1.8 §4.11.5 I1実績と完全一致 |
| G3 | Dhrystone 826/48405/P:20 | **一致**（PASS）。v1.07 baseline と v1.08（--mmu無効）が完全一致＝確定B（無効時 byte-exact 非干渉）を実証 |
| G4 | test_mmu1〜4_poc 付録B期待出力 | **全PASS**。test_mmu1: HELLO/ARITH ／ test_mmu2: AND:P/OR:P/XOR:P/NOT:P/SHL:P/SHR:P/SAR:P ／ test_mmu3: MMU ON/WR:P/ISO:P/DONE ／ test_mmu4: BOUND/V1:P/V2:P/DONE |
| 非干渉 | fib_verify_combined（50721B/8378cyc）MD5 | **一致**（PASS）。--mmu有効でも恒等写像で v1.07 一致 |
| 完了条件1（実ブート） | emu23 v1.08（--mmu無効）で yuios.bin を実行 | **PASS**。`./emu23 yuios_road2.bin -q --disk disk.img` で 56416 bytes ロード・reset vector=0e00・`YUIOS Booted!` 出力・`0YUI> ` シェルプロンプト表示＝build_procedure v1.8 §4.11.5 I2実績と一致。※G2 はビルド時の 56416 byte 一致確認であり、本行は MMU復活版 emu23 で実際にブートすることを別途確認したもの（設計書 §7 完了条件1 の "ブート" を充足） |

### 11.2 ★既知の差異注記（test_mmu4 vs MMU設計書 §9-4）

MMU設計書 **YSD8800_MMU_Design_v1_1_0.docx §9-4** の検証例には「16bit境界またぎ（`LDW [\$4FFF]`）」が
記載されているが、これは emu23 の **アライメント例外（奇数アドレスでの16bitアクセス禁止）** と矛盾する。

- 矛盾の所在：`LDW [\$4FFF]` は \$4FFF/\$5000 の2バイトにまたがり、かつ \$4FFF は奇数アドレス。
  emu23 は奇数16bitアクセスをアライメント例外として禁止しているため、設計書の例をそのまま実行できない。
- 本実装での対処：test_mmu4_boundary_poc は **8bitアクセス（LDB/STB）による各ページ独立変換**で
  ページ境界（page4/page5 = \$4xxx/\$5xxx）の変換正当性を検証する方式に変更した。
  これにより 16bit境界またぎを介さずにページ境界変換を検証でき、BOUND/V1:P/V2:P/DONE を PASS。
- 影響範囲：検証手段の差し替えのみ。MMUのページ変換ロジック（`mmu_translate`）自体は設計書 FM-11方式に忠実。
- **TODO（将来）**：MMU設計書 §9-4 の `LDW [\$4FFF]` 例を、emu のアライメント方針（奇数16bitアクセス禁止）
  と整合させるか、8bit検証例に差し替えるかを別途検討する。本注記は設計書側の改版課題として記録。

### 11.3 確定作業の完了状況（§9 次アクション 4 の進捗）
- ✅ emu23_v108.c 本番確定（_poc から昇格・中身不変 md5 一致）
- ✅ tool_version_ledger v1.5→**v1.6** 改版（emu23 v1.08 登録・§1現行/§2系譜反映・「MMU対応」バナー陳腐化是正＝旧指摘5 解消）
- ✅ 本設計書 v1.0→**v1.1** 改版（本節）
- ⬜ emu23_device_design / emu23_debug_manual への MMUデバッガコマンド（mmu/physmem）追記（別途・元docx揃え次第）
- ⬜ マスター工程「進捗と予定の確認(latest)」へ V(-1)完了の日報報告
