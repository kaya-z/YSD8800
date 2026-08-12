# YUI OS コンテキストスイッチ A/B レジスタ復元漏れ 修正設計書 v1.0

- 作成日: 2026-06-01
- 対象: `kernel_v12_5.asm` の `IRQ0_HANDLER`（プリエンプティブ・コンテキストスイッチ）
- 関連: HANDOVER_CHAT39（真因究明）, `yuios_tcb_design_v1_3.md`, `force_memory_contract_v1_1.md`, `yuios_memmap_design_v1_5.md`
- ステータス: **レビュー前**（実装GO未承認。本書はレビュー用）

---

## 1. 背景と真因

FILE-WRITE-IMPL の書込みで LBA6（第1セクタ）の byte434-511（78バイト）が欠落する不具合を CHAT34〜39 で追跡し、本チャットで真因を確定した。

**真因**: YUI OS のプリエンプティブ・コンテキストスイッチ（`IRQ0_HANDLER` 内の復元ルーチン `_sched_found`）が、退避済みの **A レジスタ（SAVED_A=TCB+8）を復元しない**。さらに **B レジスタは退避も復元もしていない**。

YSD8800 の割込（ISA2.3）は受理時に PC と FLAGS のみをスタックへ退避し、A/B/X はソフトウェア（カーネル）の保存責任とする仕様である（emu23 v1.04 のIRQ受理処理および IRET 処理で確認）。カーネルは A/X を退避するが、復元時に A を戻さず、B は退避自体が無い。

通常の Forth ワードは「演算結果をスタックへ格納してからワードを抜ける」ため、ワード境界では A/B は揮発でよい。しかしプリエンプティブIRQ（タイマー100Hz）は**任意の命令境界**で発火するため、A/B に演算途中値を保持した瞬間に中断されうる。

---

## 2. 真因の証拠（本チャットの観測・要約）

`MEMCPY-B ( dst src len -- )` の逆アセンブル先頭は `0>` 判定で、`[7C08] LDW A,[X]`（A←remain）→ `[7C0A] CMPI A,#0` → `BEQ/BLT` で真偽を決める。

LBA6充填（len=512）で off=433 を書いた直後、remain=78 を A に載せた状態（`[7C08]`後・`[7C0A]`前）でタイマーIRQが発火。観測ログ：

```
cyc=5259025 A=004f X(DSP)=fa76   ← 最後の正常周回（remain=79）
（off=433書込 cyc=5259071 → IRQ受理 → 別タスク実行 → 復帰）
cyc=5339637 A=fa76 X(DSP)=fa76   ← 復帰後：A=78のはずがA=$fa76
```

復帰後 `A=$fa76`（=SAVED_X の値、bit15=1 で負）。`CMPI A,#0` → N=1 → `BLT` 成立 → `0>` が **false** → WHILE 偽脱出。remain=78 を残して MEMCPY 終了し、off=434-511 が未書込となる。

- len=512 が正しく渡されていることは入口観測で確定（dst=$4860, TOS=512）。
- dst 書込先は off=433（$4A11）まで正常進行後に停止。dst 破壊ではない。
- LBA7充填（同コード）は同区間でIRQが発火せず正常完了。再現はタイミング決定論的。

復元処理は A を「SAVED_X を運ぶ一時レジスタ」に転用しており、IRET 直前は常に `A = SAVED_X` になる。これが偽脱出の直接原因。

---

## 3. 設計方針

### 3.1 対策範囲の切り分け

| 切替経路 | 発生境界 | A/B の扱い | 対策 |
|---|---|---|---|
| `IRQ0_HANDLER` → `_sched_found` | 任意命令境界（プリエンプティブ） | A/B に演算途中値があり得る → **保護必須** | **本書の対象** |
| 協調切替 `TASK_SLEEP`/`TASK_EXIT`/IPC → `_sched_common` → `_sc_found` | カーネルワード呼出（ワード境界） | A/B は呼出側ABIで揮発 → 保存も復元も不要 | 変更しない |
| `IRQ1_HANDLER`（UART/STOR） | 割込元タスクへ IRET 復帰（タスク切替なし） | `IRQ1_WK_A/B/X` で退避・復帰し同一タスクへ戻る | 変更しない |

協調切替・IRQ1 を変更しないことの根拠は §5 に記載。

### 3.2 基本方針

プリエンプティブ経路では「割込で中断された全 GP レジスタ（A/B/X）と FLAGS を退避し、ディスパッチ先タスクのそれを完全復元する」を原則とする。X/FLAGS は既に保存・復元済み。本修正で **A の復元** と **B の保存・復元** を補完し、原則を満たす。

emu23（ISA2.3実装）は変更しない。割込時 PC/FLAGS のみ退避という ISA 仕様は維持し、カーネル側で A/B/X を保護する従来設計を踏襲する。

---

## 4. 変更内容（`IRQ0_HANDLER` のみ）

TCB スロットは既存定義を使用（`yuios_tcb_design_v1_3.md` 準拠）：
`TCB_SAVED_A EQU 8` / `TCB_SAVED_B EQU 10` / `TCB_SAVED_FLAGS EQU 12`。SAVED_B スロットは確保済みだが現状未使用だった。

新規ワーク変数 `IRQ_WK_B` を1個追加（§6）。復元時の一時退避には保存完了後に空く `IRQ_WK_A`/`IRQ_WK_B` を再利用し、追加変数を最小化する。

### 変更1: 入口に B 退避を追加

```asm
IRQ0_HANDLER:
    DI
    STW  A, [IRQ_WK_A]
    STW  X, [IRQ_WK_X]
    STW  B, [IRQ_WK_B]      ; ★追加: 中断時の B を退避（以降ハンドラが B を破壊するため）
```

### 変更2: コンテキスト保存部に SAVED_B 保存を追加

保存部（state==RUNNING のとき）の SAVED_A 保存の直後に追加。この区間の `X` は保存先 TCB アドレス。

```asm
    LDW  A, [IRQ_WK_A]
    STW  A, [X + #8]        ; (既存) SAVED_A
    LDW  A, [IRQ_WK_B]      ; ★追加
    STW  A, [X + #10]       ; ★追加: SAVED_B
```

### 変更3: 復元部 `_sched_found` に A/B 復元を追加

既存末尾は `LDW X,[MISC_WK_X]`（X←TCBアドレス）→ `MOV X,A`（X←SAVED_X=DSP）→ `IRET`。この間に A/B 復元用の一時退避を挟む。

```asm
    LDW  X, [MISC_WK_X]     ; (既存) X = 復元先 TCB アドレス
    LDW  B, [X + #8]        ; ★追加: B = SAVED_A
    STW  B, [IRQ_WK_A]      ; ★追加: 一時退避（保存完了済の IRQ_WK_A を再利用）
    LDW  B, [X + #10]       ; ★追加: B = SAVED_B
    STW  B, [IRQ_WK_B]      ; ★追加: 一時退避（IRQ_WK_B を再利用）
    MOV  X, A              ; (既存) X = SAVED_X（DSP）
    LDW  A, [IRQ_WK_A]      ; ★追加: A = SAVED_A 復元
    LDW  B, [IRQ_WK_B]      ; ★追加: B = SAVED_B 復元
    IRET                   ; (既存) FLAGS/PC のみ pop。A/B は不変 → 復元値が維持される
```

IRET が A/B を破壊しないことは emu23 で確認済み（IRET は FLAGS←pop, PC←pop のみ）。

### 修正後の動作

$7C0A 復帰後 `A=78` が復元され、`CMPI A,#0` → N=0,Z=0 → `0>` true → ループ継続。off=434-511 を書込み、LBA6 が完全一致となる。

---

## 5. 非対象とその根拠

- **協調切替（`_sched_common`/`_sc_found`）**: `TASK_SLEEP` 等の保存部は SAVED_A/B を保存しない。ワード境界では A/B は呼出側ABIで揮発であり、保存・復元しないのが正しい。誤って SAVED_A/B（未保存のゴミ）を復元するとかえって破壊するため、現状維持が正解。
- **`IRQ1_HANDLER`**: `_sched` 系へ JMP せず IRET で割込元タスクへ戻る。自身が使う A/B/X は `IRQ1_WK_A/B/X` で退避・復帰するため、同一タスクのレジスタは保護される。本バグの対象外。
- **emu23（ISA2.3実装）**: 割込時 PC/FLAGS のみ退避という ISA 仕様を変更しない。レジスタ保護はカーネル責任という設計を維持。

---

## 6. ワーク変数・memmap への影響

新規 `IRQ_WK_B`（2B）を追加配置する。配置候補は frequently used 残余予約 `$47B6-$47BF`（`force_memory_contract_v1_1.md` §4.2 第1候補・現状未使用）。

```asm
IRQ_WK_B            EQU $47B6       ; ★新設: IRQ0用 B退避（A/Bレジスタ完全保護）
```

`$47B0-$47B5` は Force 占有（`_FMUL_A/B/R`）のため使用しない。`$47B6` をカーネル占有とし、Force 拡張候補領域を `$47B8-$47BF`（8B）へ縮小する。

**要改版（実装GO後）**:
- `force_memory_contract_v1_1.md` → v1.2（`$47B6` をカーネル占有として明記、Force拡張候補を `$47B8-$47BF` に縮小）
- `yuios_memmap_design_v1_5.md` → v1.6（同上、`IRQ_WK_B` 追記）

---

## 7. ISA2.3 適合性

使用命令は `DI`/`STW`/`LDW`/`MOV`/`IRET` および `[X+#n]` 変位アドレッシング、`EQU` 即値のみ。ISA2.3 に存在しない命令は使用しない。間接アドレッシングは `[X]`/`[X+#n]` のみ（`[A]`/`[B]` 不使用）。

---

## 8. 検証計画

1. `kernel_forth_v0_10_8.fs` は無変更（カーネル `kernel_v12_5.asm` のみ修正）。ビルドは `build_v0_10_8.sh`。
2. 標準手順で実行し、**ディスク実体の全512B照合**で合否判定（UART出力では判定しない）。
   - 合格基準: **LBA6 mismatch=0 かつ LBA7 mismatch=0**。
3. 回帰確認:
   - UART テスト出力が従来通り正常であること。
   - STOR-TEST/UART-TEST/FileMgr 各タスクが正常動作すること。
   - 端数セクタ（size<512）パディング経路（MEMSET-B）に副作用がないこと。
4. ツール（emu23/hasm23/lnk23/Force）は無改修のため Dhrystone 回帰は対象外。ただし任意で実施可。

---

## 9. リスクと KY

| 項目 | 内容 | 防止策 |
|---|---|---|
| KY30（継続） | 観測・検証時の対象取り違え（複数MEMCPY/フェーズの混同） | cyc範囲・dst文脈・X(DSP)でフレーム同一性を確認 |
| 設計KY | 復元経路の見落とし（IRQ0だけ直し協調/IRQ1を残す） | 全3経路を確認済み（§3.1）。対策はIRQ0限定で十分と確認 |
| 実装リスク | 復元の一時退避に IRQ_WK_A/B を再利用するため、保存→復元の順序依存がある | 復元直前に必ず `LDW B,[X+#n]; STW B,[IRQ_WK_*]` で書き直してから使用（中断値の残留を上書き） |
| memmap競合 | `$47B6` は Force 拡張候補領域 | memory_contract/memmap を改版しカーネル占有を明記、Force拡張を `$47B8-` へ |

---

## 10. レビュー観点（レビュアーへの問い）

1. プリエンプティブ経路のみ A/B 保護を補完し、協調切替・IRQ1 を非対象とする切り分けは妥当か。
2. 復元一時退避での `IRQ_WK_A`/`IRQ_WK_B` 再利用に、見落としている並行・再入リスクはないか（IRQ0_HANDLER は入口で `DI`、IRET まで割込禁止のため再入なしと判断している）。
3. `IRQ_WK_B = $47B6`（Force拡張候補領域への侵入）の可否。別領域が望ましいか。
4. SAVED_B スロット（TCB+10）の利用開始に伴い、他に B を前提とする経路がないか。

---

## 改版履歴

| 版 | 日付 | 内容 |
|---|---|---|
| v1.0 | 2026-06-01 | 初版。真因（IRQ0復元のA復元漏れ・B非保護）と修正設計（IRQ0_HANDLER 3箇所＋IRQ_WK_B新設）を記載。 |
