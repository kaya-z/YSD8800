# v3_5_design_memo_v0_1.md — FPGA V3.5（MMU統合）設計メモ

- 文書名: v3_5_design_memo_v0_1.md
- 版数: v0.1（**レビュー未実施・承認前**）
- 作成日: 2026-07-11
- 対象工程: Step 8 FPGA実装 / **V3.5（MMU統合）**
- 前提工程: V3（メモリ・バス・MMIOデコード／PSRAM統合）完了
- 主設計書: `YSD8800_MMU_Design_v1_1_0.docx`（FM-11方式16ページMMU）
- 黄金リファレンス: **emu23 v1.09（`emu23_v109.c`、`--mmu`）**
- 上位工程表: `fpga_impl_roadmap_v1_1.docx`

---

## 1. スコープ

### 1.1 やること

| # | 項目 |
|---|---|
| 1 | MMUモジュール新規実装（`ysd8800_mmu_v0_1.sv`・16論理ページ／4KB／20bit物理） |
| 2 | MMIOスタブへMMUレジスタ実装（PTR[0..15]@$FF00-$FF0F、MCR@$FF10） |
| 3 | **CDCブリッジの物理アドレス幅を20bit化**（現状16bit固定。§4.2） |
| 4 | 統合ラッパー`ysd8800_v3_membus`の`PHYS_AW`を16→20へ |
| 5 | MMU単体TB＋実CPU統合TB（emu23 `--mmu` 協調等価） |
| 6 | **MMU無効時のV3等価性（回帰デグレ無）確認** |

### 1.2 やらないこと（スコープ外）

- KRN_PROT（MCR bit1・ユーザモード保護）→ 設計書§10「将来拡張」
- TLBキャッシュ、ページ属性（R/W/X）→ 同上
- reset vector / SPI Flash→PSRAM展開の競合対策 → **V7/V8**
- MMIO実デバイス化（UART/TIMER/SD/IRQC）→ **V4以降**
- cycle一致検証 → **既定方針によりゲート対象外**（emu23はCPI=1固定）

---

## 2. ★最重要★ MMU挿入位置の確定（V3.5 最大の設計論点）

### 2.1 結論

> **アドレスデコーダ（論理$FC80判定）が前段。MMUはその後段・RAM側パスにのみ挿入する。**
> **MMIO（MMUレジスタ自身を含む）はアドレス変換を受けない。**

### 2.2 根拠（emu23 v1.09 実装照合・KY34）

`emu23_v109.c` の `rd16()`/`wr16()`/`rd8()`/`wr8()` の**ディスパッチ順序**を実ソースで確認した（設計書の記述ではなく実装が黄金）。

```c
uint16_t rd16(uint16_t a) {          // a = 【論理アドレス】
    if (a & 1) { /* アライメント例外 */ }

    /* ---- MMIO判定：すべて論理アドレス a と直接比較 ---- */
    if (a == UART_...)      ...      //  YSD8001 UART
    if (a == TIMER_/SCORE_) ...      //  YSD8002 タイマー
    if (a == SD_...)        ...      //  YSD8003 ストレージ
    if (a == IRQ_STAT_ADDR) return irq_stat;   //  YSD8004 IRQC
    if (a == IRQ_MASK_ADDR) return irq_mask;

    /* MMUレジスタ自身も論理アドレスで判定（変換を受けない） */
    if (mmu_mode && a >= MMU_PTR_BASE && a <= MMU_MCR_ADDR)
        return rd8(a) | (rd8(a+1) << 8);

    /* ---- ここで初めてMMU変換（通常メモリのみ） ---- */
    uint8_t lo = phys_rd8(mmu_translate(a));
    uint8_t hi = phys_rd8(mmu_translate(a + 1));
    return lo | (hi << 8);
}
```

`mmu_translate()` の呼び出しは `phys_rd8()`/`phys_wr8()` の引数としてのみ現れる（L152/638-639/771-772/793/820）。**MMIO分岐はすべてその手前で `return` するため、変換関数に到達しない。**

### 2.3 設計的必然性（なぜMMIOを変換外にするのか）

MMIOを変換対象にすると以下が破綻する。

| 破綻 | 内容 |
|---|---|
| **MMUの自己ロックアウト** | MCR（$FF10）自身が変換対象だと、ページテーブル設定次第でMCRに到達できなくなり、**MMUを切り戻す手段が失われる** |
| **割り込みコントローラの喪失** | IRQCが消えると、コンテキストスイッチ中に割り込みをマスク解除できない |
| **カーネルの足元崩壊** | YUI OSはコンテキストスイッチのたびにPTR[0..15]を書き換える。その書き換え動作自体がMMIO経由であり、ここが変換対象だと**プロセス切替コードが自分の実行基盤を壊す** |

FM-11・Dragon・CoCo3（GIME）等のMC6809+SAM/DAT系でもI/Oは変換の外側に固定されている。**「I/Oは常に見えていなければならない」がページングMMUの鉄則**であり、本設計もそれに従う。

**ユーザー判断（2026-07-11）**: 「MMIOを変換してしまうと外部デバイスが見えなくなってしまうということなら変換外とする」→ **変換外で確定**。

### 2.4 設計書との食い違い（★作業完了後に設計書改版が必要★）

| 箇所 | 設計書 v1.1.0 の記述 | 実装（黄金）との整合 |
|---|---|---|
| §7 FPGA実装概要 | 「MMUは**CPUコアとメモリバスの間**に挿入する」 | ❌ デコーダ前段に読めるが、正しくは**デコーダ後段・RAM側のみ** |
| §5 物理メモリマップ | `0xFC000〜0xFFFFF … I/O・MMUレジスタ` | ❌ I/Oは物理空間に存在しない（論理固定・変換外） |

→ **V3.5完了後に `YSD8800_MMU_Design_v1_2_0.docx` へ改版**（KY41：追記のみ・取り消し線で旧情報保持・4点整合）。本メモ §9 に改版項目を掲げる。

---

## 3. アーキテクチャ

### 3.1 V3.5 ブロック図

```
              CPUコア ysd8800_cpu v0.5.7（★無改修★）
                    │ mem_addr[15:0] / mem_wdata / mem_rdata
                    │ mem_rd / mem_wr / mem_ready
        ┌───────────┴────────────┐
        │  ysd8800_addr_decoder   │  ← 【論理アドレス】$FC80判定（V3のまま・位置不変）
        └──┬──────────────────┬───┘
     MMIO側│                  │RAM側（論理アドレス16bit）
           │                  │
  ┌────────┴─────────┐  ┌─────┴───────────────┐
  │ ysd8800_mmio_stub │  │  ysd8800_mmu  ★新規★ │
  │  ＋ MMU_REGS ★新規│  │  純組合せ            │
  │  PTR[16] @$FF00-0F│─▶│  phys = mcr_en       │
  │  MCR     @$FF10   │ptr│    ? {ptr[a[15:12]], │
  │  （変換外・常時可視）│mcr│       a[11:0]}      │
  └───────────────────┘  │    : {4'b0, a[15:0]} │
                          └─────┬───────────────┘
                                │ phys_addr[19:0] ★20bit★
                    ┌───────────┴────────────┐
                    │  ysd8800_cdc_bridge     │ ← ★PHYS_AWパラメタライズ改修★
                    │  req/ack 4相・2FF同期器  │
                    └───────────┬────────────┘
                                │ psram_addr[19:0]
                    ┌───────────┴────────────┐
                    │  ysd8800_psram_ctrl     │ ← PHYS_AW=20（既に対応済）
                    └────────────────────────┘
```

### 3.2 各モジュールの改修区分

| モジュール | 区分 | 内容 |
|---|---|---|
| `ysd8800_cpu_v0_1.sv`（v0.5.7） | **無改修** | 論理アドレスのみ扱う。MMUはCPUから透過 |
| `ysd8800_addr_decoder_v0_1.sv` | **無改修** | 論理$FC80判定のまま。位置も変えない |
| `ysd8800_mmio_stub_v0_1.sv` | **改修**（→ v0.2） | MMUレジスタ（PTR[16]/MCR）を実装。他は従来スタブ挙動 |
| `ysd8800_mmu_v0_1.sv` | **新規** | 純組合せアドレス変換 |
| `ysd8800_cdc_bridge_v0_1.sv` | **改修**（→ v0.2） | `PHYS_AW`パラメタライズ（現状16bit固定） |
| `ysd8800_psram_ctrl_v0_1.sv` | **無改修** | `PHYS_AW=20`デフォルトで既に対応済 |
| `ysd8800_v3_membus_v0_1.sv` | **改修**（→ `ysd8800_v35_membus_v0_1.sv` 新規） | MMU挿入・`PHYS_AW(16)`→`(20)` |

---

## 4. 詳細設計

### 4.1 `ysd8800_mmu_v0_1.sv`（新規・純組合せ）

```systemverilog
module ysd8800_mmu_v0_1 #(
    parameter int PHYS_AW = 20
) (
    input  logic [15:0]        logical_addr,
    input  logic               mmu_en,          // MCR bit0
    input  logic [7:0]         ptr [0:15],      // PTRレジスタ（MMIO側から供給）
    output logic [PHYS_AW-1:0] physical_addr
);
    logic [3:0] page;
    assign page = logical_addr[15:12];          // ★原則59: always_comb内のビット選択はassign外出し★

    always_comb begin
        if (mmu_en)
            physical_addr = {ptr[page], logical_addr[11:0]};      // 8+12 = 20bit
        else
            physical_addr = {{(PHYS_AW-16){1'b0}}, logical_addr}; // 恒等写像
    end
endmodule
```

**設計上の要点:**

1. **純組合せである必然性**
   CPUコアは16bitアクセスを `S_MEMR_LO` → `S_MEMR_HI`（アドレス+1）の**2バイトアクセスに分解するFSM**である。MMUを純組合せに置けば、**各バイトアクセスのアドレスがそれぞれ独立に変換される**。
   → 設計書§9-4「16bitアクセスのページ境界またぎは低位/高位バイトが個別変換される」および emu23 実装（`mmu_translate(a)` と `mmu_translate(a+1)` を別々に呼ぶ）と**自動的に一致**する。**RTL側で境界またぎの特別な細工は不要**。

2. **原則59適用**：`always_comb` 内の定数ビット選択は Icarus 12.0 で制約があるため、`page` の抽出を `assign` で外出しする。

3. **原則63チェック**：**MMUは新規stateを一切追加しない**（純組合せ）。したがってCPUコアのバス出力`always_comb`への影響なし。→ **原則63の突き合わせ対象外**であることを明記しておく（追加した場合は突き合わせ必須）。

### 4.2 `ysd8800_cdc_bridge` の20bit化（★V3の実態と要注意★）

**KY34で判明した実態:**

| モジュール | 現状（実ソース） |
|---|---|
| `ysd8800_psram_ctrl_v0_1` | `parameter int PHYS_AW = 20`（デフォルト20bit）・ポート `addr[PHYS_AW-1:0]` → **既に20bit対応済** |
| `ysd8800_cdc_bridge_v0_1` | `output logic [15:0] psram_addr;` / `assign psram_addr = cpu_mem_addr;` → **16bit固定** |
| `ysd8800_v3_membus_v0_1` | PSRAMを `.PHYS_AW(16)` でオーバーライド → **意図的に16bitへ絞っている** |

HANDOVER §4「物理アドレス線は既に20bit幅で引いてある」は**PSRAMコントローラのみに当てはまり、CDCブリッジには当てはまらない**。V3.5では以下の改修が必須。

```systemverilog
module ysd8800_cdc_bridge_v0_2 #(
    parameter int PHYS_AW = 20                       // ★追加★
) (
    ...
    input  logic [PHYS_AW-1:0] cpu_phys_addr,        // ★MMU出力を受ける（旧: cpu_mem_addr[15:0]）★
    ...
    output logic [PHYS_AW-1:0] psram_addr,           // ★16 → PHYS_AW★
    ...
);
    assign psram_addr = cpu_phys_addr;               // 幅一致
```

そして統合ラッパーで `.PHYS_AW(20)` を指定する。

### 4.3 MMIOスタブへのMMUレジスタ実装（→ `ysd8800_mmio_stub_v0_2.sv`）

| アドレス | 名称 | R/W | 幅 | リセット値 |
|---|---|---|---|---|
| $FF00 + n（n=0..15） | PTR[n] | R/W | 8bit | **n（恒等写像）** |
| $FF10 | MCR | R/W | 8bit | **0x00（MMU無効）** |
| $FF11〜$FF1F | 予約 | — | — | 0 |
| 上記以外の$FC80〜$FFFF | 従来スタブ挙動 | — | — | 固定0x00リード・ライト無視 |

**インタフェース追加（MMUへ供給）:**
```systemverilog
output logic [7:0] ptr_o [0:15],   // PTRレジスタ配列
output logic       mmu_en_o        // MCR bit0
```

**設計上の要点:**
- **アクセス幅**: 設計書§3-1「すべて8bitアクセス」。CPUコアはバイト単位でMMIOへアクセスするため、V3のバイト粒度I/Fのままで整合する。
- **リセット値**: 設計書§4・emu23 `mmu_reset()`（`for(i<16) ptr[i]=i; mcr=0;`）と一致させる。**この恒等写像リセットにより、reset直後は MMU 有効/無効で挙動が同一**となる（V7/V8のreset vector問題への布石）。
- **`mmu_en_o` の抽出**: `assign mmu_en_o = mcr[0];`（原則59・EI/DI の FLAGS bit7 抽出と同じ轍を踏まない）

### 4.4 MMU有効/無効の動作分離（工程表 指摘3対応）

| MCR.EN | MMU挙動 | V3との関係 |
|---|---|---|
| **0（リセット値）** | `physical_addr = {4'b0, logical_addr}`（恒等写像） | **V3のRTLとbit-exact等価**。上位4bitは常に0 |
| **1** | `physical_addr = {PTR[page], offset}` | V3.5新規挙動 |

**等価性の担保方法**: V3で ALL PASS した全TB（`tb_cpu_v3_v0_1`(20)／`tb_cpu_v3mem_v0_1`(5)／`tb_cpu_v3boundary_v0_1`(1)）を、**V3.5構成（MMU挿入済み・MCR=0）で再実行し、ALL PASS を再確認**する。これがデグレ無の証明になる。

---

## 5. 検証計画（設計書単体TB＋emu23協調等価の「両肺」・工程表 指摘4対応）

### 5.1 単体TB

| TB | 対象 | 検証内容 |
|---|---|---|
| `tb_mmu_v0_1.sv` | MMU単体 | ①MCR=0で恒等写像（全16ページ）②MCR=1で `{PTR[page],offset}` ③PTR書換の即時反映 ④ページ境界（$0FFF/$1000）で変換ページが切り替わる |
| `tb_mmio_mmureg_v0_1.sv` | MMIOスタブ v0.2 | ①リセット後 PTR[n]=n / MCR=0 ②PTR/MCR の R/W ③非MMU領域は従来スタブ挙動 |

### 5.2 emu23協調等価TB（黄金＝emu23 v1.09 `--mmu`）

| TB | ベクタ | 内容 |
|---|---|---|
| `tb_cpu_v35_regress_v0_1.sv` | V3の26ベクタ再実行 | **MCR=0でV3等価**（デグレ無確認・§4.4） |
| `tb_cpu_v35mmu_v0_1.sv` | 新規MMUベクタ | MMU有効時の協調等価 |

**新規MMUベクタ（案・生成器 `gen_v35_mmu_vectors.py`）:**

| # | ベクタ名 | 内容 | 設計書根拠 |
|---|---|---|---|
| 1 | MMU_IDENT_ON | PTR恒等のままMCR=1 → 挙動不変 | §4 |
| 2 | MMU_REMAP_P4 | PTR[4]=$14 → 論理$4000 → 物理$14000 へSTW/LDW | §9-1 OK例 |
| 3 | MMU_ISOLATION | MMU ONで論理$4000へ書込 → MMU OFFで論理$4000読出 → 元値のまま | §9-2 |
| 4 | MMU_BOUNDARY | PTR[4]=$14,PTR[5]=$15 で $4FFF/$5000 の個別変換 | §9-4 |
| 5 | MMU_PTR_RW | PTR/MCR のリード検証 | §3 |

**★遵守事項（V3から継承）★**
- **KY41/原則43**: ベクタ期待値は**手計算せず、emu23 `--mmu` を実行して黄金取得**する
- **MMIO協調ベクタ除外原則**: emu23はMMIOにデバイス固有値を返す。**MMUレジスタ（$FF00-$FF10）以外のMMIOアクセスをベクタに含めない**
- **SPリセット差異の中和**: emu23は SP=0xFC7E 既定、RTLは S_RESET_HI で SP<=0x0000。**全ベクタ先頭に `LDW SP,#imm16` を明示挿入**（V2-d方式）
- **§9-1 遵守**: **PTR[0]（コードページ）を変更してからMMU ONにしない**。ベクタは page4/page5 のみリマップする
- **§9-2 遵守**: MMU ON前に対象物理ページを**$00クリア**する（未初期化=$FF による偽FAIL防止）

### 5.3 ゲート基準

**既定方針どおり「完走＋論理結果一致」のみ**（cycle一致は対象外。emu23がCPI=1固定のため定義上不一致）。

---

## 6. 作業手順（1変更1検証・原則遵守）

| Step | 内容 | 検証 |
|---|---|---|
| S1 | `ysd8800_mmu_v0_1.sv` 実装 | `tb_mmu_v0_1` PASS |
| S2 | `ysd8800_mmio_stub_v0_2.sv`（MMUレジスタ追加） | `tb_mmio_mmureg_v0_1` PASS |
| S3 | `ysd8800_cdc_bridge_v0_2.sv`（PHYS_AW化） | 既存 `tb_cdc_bridge` / `tb_bridge_psram_integ` 再実行 PASS（デグレ無） |
| S4 | `ysd8800_v35_membus_v0_1.sv`（統合・PHYS_AW=20） | — |
| S5 | **V3全26ベクタをV3.5構成（MCR=0）で再実行** | **ALL PASS（デグレ無の証明）** |
| S6 | `gen_v35_mmu_vectors.py`（emu23 `--mmu` 黄金取得） | 黄金生成 |
| S7 | `tb_cpu_v35mmu_v0_1.sv` | **ALL PASS** |
| S8 | 文書改版（§9） | — |

**Icarusワークフロー厳守（原則60/61/62）**: build → `ls -la` タイムスタンプ確認 → **別コマンド**で `timeout 30 vvp`（`&&`チェーン禁止）。rc=124 は組合せループを疑う。

---

## 7. リスクと対策（KY）

| # | リスク | 対策 |
|---|---|---|
| R1 | **MMU挿入位置の取り違え**（MMIOを変換対象にしてしまう） | 本メモ§2で確定・実装照合済。デコーダは**位置不変** |
| R2 | **CDCブリッジ16bit固定の見落とし** | §4.2で明示。KY34で実ソース確認済。`PHYS_AW` パラメタライズ必須 |
| R3 | **MMU有効時のみ顕在化するバグ**（原則63の類型） | MCR=0（V3等価）とMCR=1の**両方**でTBを回す（S5+S7） |
| R4 | ベクタが §9-1（コードページPTR変更禁止）に違反しハングする | 生成器で page4/page5 のみリマップ。page0/1 は触らない |
| R5 | phys_mem 未初期化（$FF）による偽FAIL | §9-2 に従い、MMU ON 前に対象物理ページを $00 クリアするコードをベクタに含める |
| R6 | Icarus の `always_comb` 内ビット選択制約 | 原則59：`page` / `mmu_en` 抽出を `assign` で外出し（§4.1・§4.3に反映済） |

---

## 8. 未確定事項（レビューで確認したい点）

| # | 論点 | 現案 |
|---|---|---|
| Q1 | MMU無効時（MCR.EN=0）でも **PTR/MCR レジスタは読み書き可能**とするか | **可能とする**。emu23は `mmu_mode`（`--mmu`起動フラグ）が真ならMCR値に関わらずレジスタアクセス可。RTLには起動フラグの概念がないため、**MMUレジスタは常時アクセス可**とする（MCR=0でも書ける＝でないとMMUを有効化できない） |
| Q2 | PSRAM物理容量（現行TBは16bit=64KBモデル）を20bit=1MBに拡張するか | **拡張する**（MMUの意味がなくなるため）。ただしIcarusシミュレーション上のメモリ確保量に注意 |
| Q3 | 統合ラッパーのファイル名 | `ysd8800_v35_membus_v0_1.sv` 新規作成（V3の`v3_membus`は**そのまま残す**＝V3構成での回帰実行を可能にするため） |

---

## 9. 作業完了後の文書改版項目（KY41・追記のみ・4点整合）

| # | 文書 | 改版内容 |
|---|---|---|
| 1 | `YSD8800_MMU_Design_v1_1_0.docx` → **v1.2.0** | §7 MMU挿入位置を実装に整合（デコーダ後段・RAM側のみ）／§5 物理メモリマップからI/O行を是正（取り消し線で旧記述保持）／FPGA実装章にCDCブリッジPHYS_AW化を追記 |
| 2 | `v3_5_design_memo_v0_1.md` → **v0.2以降** | 実装結果・検証結果を追記 |
| 3 | `fpga_impl_roadmap_v1_1.docx` → **v1.2** | V3.5完了記録 |
| 4 | `fpga_source_version_ledger_v1_1.md` → **v1.2** | V3.5ソース一式（MMU/mmio_stub v0.2/cdc_bridge v0.2/v35_membus/TB/生成器）を登録 |
| 5 | `kaizen.txt` | 新規原則があれば追記（候補: 「HANDOVER記述も実ソース照合の対象。『引いてある』は幅まで確認する」＝KY34のRTL適用） |

---

## 10. レビュー依頼事項

本メモ v0.1 について、以下のご確認をお願いします（**原則43: 承認まで実装着手しません**）。

1. **§2 MMU挿入位置の確定**（デコーダ前段・MMIO変換外）— ユーザー判断済だが設計として妥当か
2. **§4.2 CDCブリッジの20bit化** — HANDOVER記述との差異を含め、この改修範囲でよいか
3. **§5 検証計画**（MMUベクタ5本＋V3全26ベクタ再実行）— 過不足はないか
4. **§8 未確定事項 Q1〜Q3** — 現案でよいか
5. **§9 文書改版項目** — 漏れはないか

---

## 改版履歴

| 版 | 日付 | 内容 |
|---|---|---|
| v0.1 | 2026-07-11 | 新規作成（レビュー用ドラフト）。emu23 v1.09実装照合によりMMU挿入位置を確定。CDCブリッジ16bit固定をKY34で検出し改修項目に追加 |
