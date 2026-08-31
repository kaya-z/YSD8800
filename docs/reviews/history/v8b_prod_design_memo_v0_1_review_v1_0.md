# V8-b 本番 TB 設計書 v0.1 レビュー指摘書

- **文書ID**: v8b_prod_design_memo_v0_1_review_v1_0.md
- **レビュア**: Claude（設計レビュー担当）
- **レビュー対象**: v8b_prod_design_memo_v0_1.md
- **レビュー日**: 2026-07-31
- **判定**: **差戻し（重要修正必須）** — TB 全体構造・PSRAM 配置・M-1 到達 PC・CL-3 SP 初期値・§1 と §8 の "123MD" マーカー由来の理解に**実源乖離が5件**あり、そのまま実装すると起動時に即失敗する

---

## 1. 総評

段階起動 phase-1/2/3（KY 防止策 3）・観測マイルストーン M-1〜M-5（KY 防止策 1）・ゴールデン等価性チェックリスト CL-1〜CL-3（原則94・V8-D PSRAM 1KB 事故の反省）といった**設計思想は理想的**。特に「TB 予算を段階的に拡大」「先に判定を実装してから走らせる」「初期化状態を assert で自己防衛」の 3 本柱は、V8-a・V8-D の教訓を的確に反映している。

しかし、**具体的な実装値・アドレス・起動フロー理解に実源乖離が集中**しており、そのまま TB 実装に着手すると起動 100 サイクル以内に M-1 で偽 FAIL する。乖離事項は以下 5 件：

1. **DUT 構造の不完全**：`ysd8800_v5_membus_v0_2` を DUT と記述しているが、これは membus 統合ラッパーで **CPU コアを含まない**。V8-a TB (tb_cpu_v8catls_poc.sv) では **CPU コア (`ysd8800_cpu_v0_1`) と membus を別々にインスタンス化**しており、V8-b でも同じ構造が必要
2. **Forth セクション物理アドレス `$5100`**：実源に一切根拠なし。kernel v12.8 の Forth セクションは lnk23 が配置し、`OS-START = $e988`（L1475）等 v0.12.0 以降 $e9xx 帯を使用
3. **M-1 到達 PC `$5100`**：リセット時 PC は `.vector reset _kstart` (L427) で `_kstart` に到達。`_kstart` は $0E00 (L206) 相当。**$5100 到達は起こらない**
4. **CL-3 SP 初期値 `$E000`**：`_kstart` L1332 で `LDW SP, #$477E` （KERN_SP_TOP）。**$E000 ではない**
5. **§8「123MD は Shell 内蔵マーカーで SD 参照不要」**：kernel_forth L2792/2797/2805/2810/2829 で **123MD は FILEMGR タスクの起動進捗マーカー**（'1'=SB-LOAD 成功 / '2'=magic OK / '3'=ver_major OK / 'M'=FS-MOUNTED / 'D'=DIR-LOAD 完了）。**SD 経由で YUIFS を認識できないと出力されない**。SH-CMD-VER は "YUIOS V0.10.18" を出力する別マーカー

これらは v1.3（kernel_v12_8_migration_design v1.3）の Pre 工程で確認済の内容と**齟齬**があり、Pre 工程の申し送り情報（v1.3 §10.5）が本設計書に正しく反映されていない懸念がある。

---

## 2. 実源照合サマリ

| 実源 | 該当箇所 | 設計書の主張 | 判定 |
|---|---|---|---|
| ysd8800_v5_membus_v0_2.sv | L162 `module ysd8800_v5_membus_v0_1` | §3.1「DUT: `ysd8800_v5_membus_v0_2`」 | **乖離**（module 名は `_v0_1`、CPU コア別途） |
| ysd8800_v5_membus_v0_2.sv | L166-224（ポート） | §3.1 top-level 接続 | **乖離**（`mem_addr/wdata/rdata/rd/wr/ready` は CPU バスで、CPU コアが外部にある必要） |
| tb_cpu_v8catls_poc.sv | L89 (CPU コア) / L103 (membus) | §3.1 DUT 構造 | V8-a では両者を別々にインスタンス化・**参考実源** |
| kernel_v12_8.asm | L427 `.vector reset _kstart` | §4 M-1 PC=$5100 | **乖離**（リセット時 PC は `_kstart` シンボル位置） |
| kernel_v12_8.asm | L206 `$0E00 _kstart` | §4 M-1 PC=$5100 | **乖離**（`_kstart` は $0E00 相当） |
| kernel_v12_8.asm | L1332 `LDW SP, #$477E` | §7 CL-3 `sp == $E000` | **乖離**（SP 初期値は $477E） |
| kernel_v12_8.asm | L1475 `WORD_OS_START = $e988` | §3.2「Forth セクション → 物理 $5100 起点」 | **乖離**（Forth OS-START は $e988 付近） |
| kernel_v12_8.asm | 全ファイル | §3.2「$5100」 | **`$5100` は実源に一切現れず** |
| kernel_forth_v0_10_18.fs | L2792 `$31 FILEMGR-PUTC \ '1' SB-LOAD 成功` | §1・§8「Shell 内蔵マーカー・SD 参照不要」 | **乖離**（FILEMGR タスクの起動進捗マーカー） |
| kernel_forth_v0_10_18.fs | L2797 `$32 \ '2' magic OK` | 同上 | **乖離**（YUIFS magic 認識通過が必要 → SD 参照必須） |
| kernel_forth_v0_10_18.fs | L2805 `$33 \ '3' ver_major OK` | 同上 | **乖離**（YUIFS version 通過が必要） |
| kernel_forth_v0_10_18.fs | L2810 `$4D \ 'M' 完了` (FS-MOUNTED=1) | 同上 | **乖離**（FS-MOUNTED になれない = M 出ない） |
| kernel_forth_v0_10_18.fs | L2829 `$44 \ 'D' = DIR-LOAD 完了` | 同上 | **乖離**（DIR-LOAD 通過が必要） |
| kernel_forth_v0_10_18.fs | L3265-3271 SH-CMD-VER 実装 | §10 UC-1「SH-CMD-VER 系」 | **乖離**（SH-CMD-VER は "YUIOS V0.10.18" 出力・別マーカー） |
| tb_cpu_v8catls_poc.sv | L9 `SDイメージ: sd_image.hex (mkfs_yuifs 8KB)` | §3.3「sd_image.hex（24,576B = 48 セクタ）」 | **乖離**（V8-a では 8KB=16 セクタ） |
| HANDOVER_CHAT125.md | 全文 | §8「HANDOVER §2.3」 | 根拠不在（HANDOVER に sd_image への言及なし） |

**結論**: 実源照合 15 箇所中 **11 箇所で乖離**、根拠不在 1 箇所、V8-a 参考実源 3 箇所。設計書の技術的前提の再確認が必要。

---

## 3. 指摘一覧

| # | 区分 | 内容 | 対応 |
|---|---|---|---|
| 1 | **必修正** | §3.1 DUT は CPU コアを含まない構造 | V8-a TB (tb_cpu_v8catls_poc.sv L89/L103) と同じ「CPU コア + membus 別インスタンス」構造に修正 |
| 2 | **必修正** | §3.2 Forth セクション物理 `$5100` 起点は実源に根拠なし | lnk23 出力の実際のセクション配置を Pre-3 成果物から確認、修正 |
| 3 | **必修正** | §4 M-1 到達 PC `$5100` は誤り | M-1 は `_kstart` 到達（$0E00 相当）に変更 |
| 4 | **必修正** | §7 CL-3 SP 初期値 `$E000` は誤り | `$477E` (KERN_SP_TOP) に修正 |
| 5 | **必修正** | §1・§8 "123MD" は Shell マーカーで SD 参照不要は誤り | 123MD は FILEMGR タスクの YUIFS 起動進捗マーカー、**SD 参照は必須**の理解に修正 |
| 6 | 補足 | §3.3 sd_image.hex サイズが V8-a と乖離（24,576B vs 8,192B） | V8-a 実績サイズ 8KB を採用、または 24,576B の根拠を明示 |
| 7 | 補足 | §10 UC-1 の SH-CMD-VER 系による "123MD" 起動時発火説は成立しない | UC-1 の質問を再構成、または削除 |
| 8 | 補足 | §7 CL-1 「非デフォルト要素数が 56,416 と一致」の判定は現実的か | PSRAM モデルの初期値と `$readmemh` 後の状態を実源で確認 |

---

## 4. 指摘1（必修正）: §3.1 DUT 構造の不完全

### 4.1 該当箇所

v0.1 §3.1（原文引用）:

> - **DUT** : `ysd8800_v5_membus_v0_2`（top-level v0.2）
> - **クロック**  : 100 MHz (CPU) / 25 MHz (SPI) を DUT 内 CDC bridge が調停

### 4.2 実源事実

**ysd8800_v5_membus_v0_2.sv L162-224**（原文引用）:

```systemverilog
module ysd8800_v5_membus_v0_1 #(
    ...
) (
    input  logic        cpu_clk,
    input  logic        cpu_rst_n,

    // CPU バス（CPU コアと接続）
    input  logic [15:0] mem_addr,     // 【論理アドレス】
    input  logic [7:0]  mem_wdata,
    output logic [7:0]  mem_rdata,
    input  logic        mem_rd,
    input  logic        mem_wr,
    output logic        mem_ready,
    ...
);
```

**重要な事実**:
1. **module 名は `ysd8800_v5_membus_v0_1`**（ファイル名は `_v0_2.sv` だが宣言名は `_v0_1`）
2. **CPU コアを内包しない** — `mem_addr/wdata/rdata/rd/wr/ready` は CPU コアと接続するバスポート

**V8-a TB (`tb_cpu_v8catls_poc.sv`) L85-125**（実源）:

```systemverilog
    // DUT: CPUコア (無改修)
    ysd8800_cpu_v0_1 dut_cpu (
        .clk(cpu_clk), .rst_n(cpu_rst_n),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata),
        .mem_rd(mem_rd), .mem_wr(mem_wr), .mem_ready(mem_ready),
        .irq_in(irq_in),
        ...
    );

    // DUT: v5 membus (ファイル v0.2・YSD8003結線版・無改修)
    ysd8800_v5_membus_v0_1 #(.PHYS_AW(20), .MEM_AW(20)) u_membus (
        .cpu_clk(cpu_clk), .cpu_rst_n(cpu_rst_n),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata),
        .mem_rd(mem_rd), .mem_wr(mem_wr), .mem_ready(mem_ready),
        ...
    );
```

V8-a では **CPU コアと membus を別々にインスタンス化**し、mem_addr/wdata/rdata/rd/wr/ready で接続している。V8-b でも同じ構造が必須。

### 4.3 修正提案

v0.2 §3.1 を以下に置換：

> - **DUT** : `ysd8800_cpu_v0_1`（CPU コア・実版 v0.5.8）＋ `ysd8800_v5_membus_v0_1`（membus 統合ラッパー・ファイル v0.2）
>   - **module 名注意**：ファイル `ysd8800_v5_membus_v0_2.sv` の module 宣言は `ysd8800_v5_membus_v0_1`（ファイル名/module 名乖離運用・fpga_source_version_ledger 参照）
> - **接続**：CPU バス（mem_addr/wdata/rdata/rd/wr/ready）で CPU コアと membus を接続
> - V8-a TB (tb_cpu_v8catls_poc.sv L89/L103) と同じ構造を踏襲

---

## 5. 指摘2〜4（必修正）: 起動時 PC・SP・Forth 配置の乖離

### 5.1 該当箇所と実源事実

**v0.1 §4 M-1**：

> M-1 | リセット解除・PC 到達 | CPU の `pc` レジスタが `$5100`（Forth OS-START エントリ）に到達 | 〜100 cycle | 10,000

**v0.1 §3.2**：

> - lnk23 出力の kernel セクション → 物理 `$0000` 起点 (5,238B)
> - lnk23 出力の Forth セクション → 物理 `$5100` 起点 (35,680B)

**v0.1 §7 CL-3**：

> CPU 初期状態 | リセット直後 (cycle=1): `pc == $5100`, `sp == $E000`

**実源確認**：

**kernel_v12_8.asm L427**（リセットベクタ定義）:
```asm
.vector reset   _kstart
```

**kernel_v12_8.asm L206**（コメント内の配置マップ）:
```
$0E00        _kstart
```

**kernel_v12_8.asm L1331-1332**（_kstart 実装）:
```asm
_kstart:
    LDW  SP, #$477E              ; v0.12.3: $FBCE→$477E (KERN_SP_TOP)
```

**kernel_v12_8.asm L1475**（OS-START 定義）:
```asm
; v0.12.0: WORD_OS_START = $e988
```

**確定事実**：
- リセット時 PC は `_kstart` シンボル → **$0E00 相当**（$5100 ではない）
- SP 初期値は `$477E` （**$E000 ではない**）
- Forth OS-START は `$e988` 付近（**$5100 ではない**）
- 設計書の `$5100` は kernel_v12_8.asm 全体で**一切現れない**

### 5.2 修正提案

**M-1（§4）修正案**：

> M-1 | リセット解除・_kstart 到達 | CPU の `pc` レジスタが `_kstart`（実測値：kernel v12.8 lnk23 出力 map で確定）に到達 | 〜100 cycle | 10,000

**§3.2 修正案**：

> lnk23 出力の実配置は Pre-3 成果物の map ファイル・yuios_road2.bin の disassembly から確定する。**設計書 v0.2 では仮値を書かず、Pre-3 で確定した実配置を引用する**。

**CL-3（§7）修正案**：

> CPU 初期状態 | リセット直後 (kernel v12.8 `_kstart` 実行後): `pc == _kstart` の位置（Pre-3 map で確定）, `sp == $477E`（KERN_SP_TOP, kernel_v12_8.asm L1332）

### 5.3 影響

- **M-1 判定基準の PC アドレスが誤っているため、TB を実装した瞬間に M-1 で偽 FAIL 確定**
- CL-3 の SP assert も同様に偽 FAIL 確定
- **修正しないと phase-1 sanity check で 100% 失敗する**

---

## 6. 指摘5（必修正）: "123MD" マーカーの由来誤解

### 6.1 該当箇所

v0.1 §1（原文引用）:

> "123MD"           ← Shell 内蔵マーカー (M-5 判定文字列)

v0.1 §8（原文引用）:

> 3. M-5 判定文字列 "123MD" は Shell 内蔵マーカーで SD 参照不要（Forth SH-CMD-VER 系）

v0.1 §10 UC-1（原文引用）:

> Shell の "123MD" マーカー出力は、UART RX 入力なしで発生するか？
> Forth 側 `SH-CMD-VER` の起動時自動発火の有無を kernel_forth の該当箇所で最終確認したい

### 6.2 実源事実

**kernel_forth_v0_10_18.fs L2777-2810**（原文引用・要約）:

```
\   '1' : SB-LOAD 成功、MAGIC-CHECK 開始前
\   '2' : MAGIC 一致、version 読出開始
\   '3' : ver_major OK、キャッシュ書込開始
\   'M' : FS-MOUNTED=1 で完了

    $31 FILEMGR-PUTC                    \ '1' SB-LOAD 成功
    $32 FILEMGR-PUTC                    \ '2' magic OK
    $33 FILEMGR-PUTC                    \ '3' ver_major OK
    $4D FILEMGR-PUTC ;                  \ 'M' 完了
```

**kernel_forth_v0_10_18.fs L2829**:

```
    $44 FILEMGR-PUTC ;                  \ 'D' = DIR-LOAD 完了
```

**kernel_forth_v0_10_18.fs L3265-3271**（SH-CMD-VER 実装・原文引用）:

```
: SH-CMD-VER  ( -- )
    $59 SH-EMIT $55 SH-EMIT $49 SH-EMIT $4F SH-EMIT $53 SH-EMIT  \ YUIOS
    $20 SH-EMIT                                                  \ ' '
    $56 SH-EMIT                                                  \ V
    $30 SH-EMIT $2E SH-EMIT $31 SH-EMIT $30 SH-EMIT              \ 0.10
    $2E SH-EMIT $31 SH-EMIT $38 SH-EMIT                          \ .18
    SH-CR ;
```

**確定事実**：
1. **123MD は FILEMGR タスクの YUIFS 起動進捗マーカー**（Shell 内蔵マーカーではない）
2. `123M` の出力には **SD 経由で YUIFS スーパーブロック読出・magic チェック・version チェック・マウント完了**が必要
3. `D` の出力には **DIR-LOAD 完了**が必要（さらに SD 参照）
4. **SH-CMD-VER は "YUIOS V0.10.18" を出力する別マーカー**
5. **UC-1 の想定「SH-CMD-VER の起動時自動発火」は成立しない**

### 6.3 kernel_v12_8_migration_design v1.3 との整合確認

v1.3 §9.4 教訓4（原文引用・v1.3 レビュー時に確認済）:

> ソースコメントに書かれた文字列（例：kernel_forth_v0_10_18.fs L34「非回帰=0123MD」）が実際にどのような形式で出力されるかは実行して確認する必要がある。

v1.3 レビューで確認済の通り、**123MD は FILEMGR 起動進捗マーカーであり、Pre-4 実測でも v12.8 版で "123MD" 出力を実証**している。V8-b 設計書 v0.1 は **v1.3 の確定内容と齟齬**があり、v1.3 §10.5「V8-b への申し送り」情報が正しく反映されていない。

### 6.4 修正提案

**§1 修正案**：

> ```
> 起動シーケンス期待出力(UART TX):
>     "YUIOS Booted!\n" ← BOOT-MSG (Forth kernel_forth_v0_10_18.fs L3432)
>     "0YUI> "          ← SHELL-START プロンプト
>     "123MD"           ← FILEMGR タスクの YUIFS 起動進捗マーカー
>                         (L2792/2797/2805/2810/2829)
> ```

**§8 修正案**：

> 3. M-5 判定文字列 "123MD" は **FILEMGR タスクの YUIFS 起動進捗マーカー**であり、**SD 経由で YUIFS スーパーブロック / magic / version / マウント / DIR-LOAD をすべて通過する必要がある**。SD image は起動シーケンスの必須要素。

**§10 UC-1 修正案または削除**：

> UC-1 は根拠が誤っていたため削除。**123MD は FILEMGR タスクで SD 経由の YUIFS 起動が成功した際に順次出力される。SD image 供給が正しく機能していれば UART RX 入力なしで自動発火する**。

### 6.5 波及影響

**「SD 参照不要」の理解に基づいた設計判断が §8 で下されている**：
- 「M-5 判定文字列 "123MD" は Shell 内蔵マーカーで SD 参照不要」→ **誤り**
- V8-a の sd_image.hex を「そのまま流用する」判断は結果的に妥当だが、**根拠が違う**（根拠は「SD 参照が必須で V8-a の image が YUIFS 形式のため使える」であるべき）

---

## 7. 指摘6〜8（補足）

### 7.1 指摘6: §3.3 sd_image.hex サイズの V8-a 乖離

**v0.1 §3.3**：「`sd_image.hex`（24,576B = 48 セクタ, YUIFS マジック "YUIFS" 先頭）」

**tb_cpu_v8catls_poc.sv L9**（原文）：「SDイメージ: sd_image.hex (mkfs_yuifs 8KB, HELLO.TXT="Hello, YUI OS!\n")」

**V8-a は 8KB (16 セクタ)**。設計書の 24,576B の根拠が不明。V8-a の image をそのまま流用するなら 8KB が正しい。

**修正案**：24,576B の根拠を明示、または 8KB に訂正。

### 7.2 指摘7: §10 UC-1 の再構成

指摘5と対応。SH-CMD-VER 系による自動発火説を削除し、代わりに以下を UC-1 として立てるべき：

> **UC-1（差替え）**：V8-a の sd_image.hex（8KB・HELLO.TXT のみ）で、V8-b の YUIFS 起動シーケンス（FILEMGR タスクの SB-LOAD → MAGIC-CHECK → version 読出 → FS-MOUNTED → DIR-LOAD）が全通過するか。V8-a では cat/ls を実行するだけで、FILEMGR タスク経由の完全起動シーケンスが通っていたかは要確認。

### 7.3 指摘8: §7 CL-1 「非デフォルト要素数」判定の現実性

**v0.1 §7 CL-1**：「`$readmemh` 完了後、`mem[]` の非デフォルト要素数を数えて 56,416 と一致」

**懸念**：PSRAM モデル `mem[]` の**初期値がどうなっているか**次第で「非デフォルト要素数」の判定は困難：
- 初期値が 0x00 の場合、yuios.bin 内の 0x00 バイト（かなりの数存在）が「デフォルトと同じ」扱いになる
- 初期値が不定 (X) の場合、`$readmemh` で書き込まれない領域は X のまま残る

**修正案**：CL-1 を以下いずれかに変更：

- **案A（推奨）**：`$readmemh` の**行数を数える**（読み込んだ行数が期待通りかを $display で表示）。tb_cpu_v8catls_poc.sv L288-289 の手法を踏襲。
- **案B**：yuios.bin の**特定オフセットの実バイト値を assert**（例：offset $0000 = kernel リセット命令の先頭バイト、offset $003D = TCR-ACK パターン先頭）。

V8-a TB では L288 で明示的に `mem[i] = 8'h00` で初期化してから `$readmemh` を実行しており、この方式が確実。

---

## 8. 承認条件

**判定: 差戻し（重要修正必須）**

**必修正（v0.2 での対応必達）:**

- 指摘1: DUT 構造を CPU コア + membus 別インスタンス化に修正（V8-a TB 参考）
- 指摘2: Forth セクション物理アドレスの根拠を Pre-3 実配置から取得、`$5100` を訂正
- 指摘3: M-1 到達 PC を `_kstart`（$0E00 相当）に修正
- 指摘4: CL-3 SP 初期値を `$477E` に修正
- 指摘5: "123MD" マーカー由来を FILEMGR タスクの YUIFS 起動進捗マーカーに訂正、§1・§8 全面書き直し

**推奨修正（v0.2 で対応推奨）:**

- 指摘6: sd_image.hex サイズを V8-a 実績 8KB に訂正、または 24,576B の根拠明示
- 指摘7: UC-1 を SH-CMD-VER 系から YUIFS 起動シーケンス経由に再構成
- 指摘8: CL-1 の判定方式を `$readmemh` 行数または特定オフセット値 assert に変更

**再レビューについて:**

- v0.2 で必修正5件を反映後に再レビュー
- 実装ブロック：v0.2 承認までは TB 実装（tb_cpu_v8b_prod_v0_1.sv）着手禁止

---

## 9. 特に評価すべき点（設計思想面）

### 9.1 段階起動 phase-1/2/3（KY 防止策 3）

`MAX_CYCLES = 100 万 → 1000 万 → 1 億`と段階的に拡大する方針は、iverilog シミュレーションの実運用として理想的。特に「phase-1 で M-1/M-2 まで OK 判定」と phase 間の判定粒度を分離している点は、失敗時の切り分けが容易になる。

### 9.2 観測マイルストーン M-1〜M-5（KY 防止策 1）

「先にマイルストーンを実装してから TB を走らせる」姿勢は、V8-a の cat/ls デモで確立された経験の反映として理想的。TB 内で各 M の判定を実装し、途中通過を $display で明示する構造は、TB のデバッグ効率を大きく上げる。

### 9.3 ゴールデン等価性チェックリスト CL-1〜CL-3（原則94）

「V8-D の PSRAM 1KB 事故を反復させない」の再登板は原則94 の忠実な適用。**初期化直後に assert で自己防衛**する姿勢は、V8-D で発見された「PSRAM 初期化ミスを気づかず走らせた」問題への直接的な対策。

### 9.4 UART 出力の永続化（§9）

`uart_out.log` へのファイル書き出し方針は、iverilog 長時間シム時のログ制御と、`grep -aoE '123MD' uart_out.log` による独立判定の両方に対応。**判定手段を「シミュレーション実行中」と「終了後のログ検査」の 2 系統に持つ**冗長設計は原則87 の応用として堅牢。

---

## 10. 本レビューでの追記

**教訓（Pre 工程申し送り情報の伝達精度）**：

kernel_v12_8_migration_design v1.3 §10.5「V8-b への申し送り」では、以下が明確化されていた：

- yuios_road2.bin リファレンス（MD5 = `7a6a5b87...`）
- v12.7 版比較用（保持中）
- ビルドツール版数
- Makefile v1.2 の主要パラメータ

しかし、**「123MD の由来が FILEMGR タスクの YUIFS 起動マーカーである」ことや、「AC-2 で確立された起動フローの詳細」までは §10.5 に明記されていない**。v1.3 §9.4 教訓4（コメント記述と実出力の照合）を確立した際に、その具体的な結論（"123MD" は FILEMGR タスク由来）を V8-b 設計書に伝達する仕組みが不十分だった。

**運用強化提案**：Pre 工程完了時の申し送り書（v1.3 §10.5 相当）に、**「Pre 工程で確定した実源事実の項目一覧」**（PC 起点・SP 初期値・マーカー由来・SD image 要件など）を明示的に含める。V8-b のような別設計書起票時にこの一覧を必ず参照する運用を確立すれば、本件のような**確定済事実の未反映**が防げる。

---

## 11. 参照資料

- v8b_prod_design_memo_v0_1.md（レビュー対象）
- kernel_v12_8_migration_design_v1_3.md §10.5（V8-b への申し送り・確認元）
- kernel_v12_8_migration_design_v1_3_review_v1_0.md（v1.3 レビュー・123MD 由来確認済）
- **kernel_v12_8.asm** L206（_kstart 配置）, L427（reset vector）, L1331-1332（SP 初期化）, L1475（OS-START）
- **kernel_forth_v0_10_18.fs** L2777-2810（123M マーカー実装）, L2829（D マーカー実装）, L3265-3271（SH-CMD-VER 実装）, L3432（BOOT-MSG）
- **ysd8800_v5_membus_v0_2.sv** L162（module 名 `_v0_1`）, L166-224（ポート）
- **tb_cpu_v8catls_poc.sv** L9（sd_image 8KB）, L85-125（DUT 構造・参考実源）
- **sd_spi_model_v0_3_poc.sv** L41-45（SD SPI モデル）
- HANDOVER_CHAT125.md（sd_image への言及なし）
- kaizen.txt 原則43（実装前レビュー）・原則76（実源照合）・原則87（弁別性）・原則94（PSRAM 事故反省）
- review_insights_v1_0.docx 原則5.1（実源照合の運用）

---

## 改版履歴

| 版 | 日付 | 内容 |
|---|---|---|
| v1.0 | 2026-07-31 | 初版。v8b_prod_design_memo_v0_1.md に対するレビュー。実源照合15箇所中 **11箇所で乖離**。必修正5件（DUT構造・Forth 配置・M-1 PC・CL-3 SP・"123MD" 由来）・補足3件で差戻し。設計思想（段階起動・マイルストーン・CL チェック・UART 永続化）は理想的だが、具体的な実装値の実源照合不足で TB 実装着手不可。 |

— 以上 —
