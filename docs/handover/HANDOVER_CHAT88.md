# HANDOVER_CHAT88.md

**作成日**: 2026-07-13
**前チャット**: CHAT88（FPGA V5 タイマー：S4 完了）
**次チャット**: **S5（CPU RTL v0.5.8）から再開**
**工程**: Step 8 / FPGA 実装 V5（YSD8002 タイマー）

---

## 0. 【最初にやること】実在確認（KY49）

新チャット冒頭で、以下がプロジェクトナレッジに実在するか必ず `ls`/`view` で確認すること。
HANDOVER に「完成済み」と書かれていても実在確認を先に行う（過去2回の実害あり）。

必須（無ければ先に登録を依頼し、無いまま S5 に進まない）:

1. `kernel_v12_8.asm` … 本日の主成果物。V5 ACK 対応カーネル
2. `startup_harness23_v16.asm` … 本日の主成果物。V5 ACK 対応ハーネス
3. `v5_design_memo_v0_2.md` … V5 設計メモ（承認済）。ただし §5.3 に誤りあり（後述 §5）
4. `emu23_v110.c` … 黄金リファレンス。**★無改修のまま使用する★**
5. `ysd8800_cpu_v0_1_FIXED.sv` … S5 の改修対象（v0.5.7）
6. `kaizen.txt` … 原則72 まで（S10 で 73・74 を追加予定）

補足: `v5_design_review_reply_v1_0.docx` は本チャット開始時点で未登録だった。
設計根拠は `v5_design_memo_v0_2.md` に集約されているため作業阻害はないが、
監査証跡としては欠落しているので登録が望ましい。

### emu23 v1.09 の扱い

**★V5 が S10 まで完了するまで削除しないこと。★** 理由:

- S3 の退行検証は「v1.09 の golden と v1.10 の golden を md5 突合」で実証した。
  `gen_*.py` は `./emu23` を実行して golden を動的生成するため、v1.09 が無いと再現不能
- 設計メモ §6 の撤退基準（S2/S3 が落ちたら再設計）が S5〜S9 完了まで生きている
- V1〜V4 の合格（82ベクタ＋55回帰）は v1.09 を黄金として得た資産である

---

## 1. 本チャットの結論（一言）

> **V5 の ACK は「TCR ← $0023」である。「$0020」ではない。**
> **ACK 単独を書くと状態ビット（TIMER_EN/IRQ_EN）が 0 に落ち、ACK が ACK 自身を殺す。**

---

## 2. S4 完了 — 全ゲート PASS

### 検証結果

- **S4ゲート1（起動）**: 「YUIOS Booted!」出力。全タスク（tid=0〜6）起動完了 ✅
- **S4ゲート2（A/B 保護・LBA6 完全性）**: ProcMgr(`D`) 起動＝スケジューリング正常＝A/B 破壊なし ✅
- **S4ゲート3（Dhrystone 絶対ゲート）**: **826 / 48405 / P:20** 完全一致 ✅
- **本質判定（タイマー周期発火）**: 受理 **1回 → 4回**（20万step・理論周期40000cycle と一致）✅
- `yuios.bin` = **56416 バイト**（黄金一致）✅

### ★V5 改修の効果（実証データ）★

改修前（emu23 v1.10 + ACK 無しカーネル）と改修後の比較:

- タイマー受理（20万step）: 改修前 **1回**（初回発火後に永久停止） → 改修後 **4回**
- 起動マーカー: 改修前 `0YUI> 123M` → 改修後 `0YUI> 123M` **`D`**
- **改修前は ProcMgr(tid=5) が一度もスケジュールされていなかった。**
  タイマーが1回で死ぬためプリエンプションが起きず、`D` マーカーが出なかった。
  改修後はタイマーが周期発火し、ProcMgr が正常起動した。

起動マーカーの意味（`kernel_forth_v0_10_18.fs` L3431 のコメントで確認）:
`0`=Root / `1`=MemMgr / `2`=UART / `3`=Stor / `M`=FileMgr / `D`=ProcMgr / `YUI> `=Shell

> ★注意★ 古いコメント（L91）にある期待出力 `0A BC123MPDQLORSCWVX` は
> **v0.10.9 時点のテストタスク構成のもの**であり、現行 v0.10.18（Ph.6 Shell 常駐構成）
> には該当しない。**「YUIOS Booted!」が出れば全コアサービス起動完了**である
> （`OS-START` が `BOOT-MSG` に到達している証拠）。

---

## 3. 実装内容（成果物2件）

### 3.1 `kernel_v12_8.asm`（v0.12.7 → v0.12.8）

追加した EQU 定数:

```
TCR                 EQU $FC90
TCR_ACK_REARM       EQU $0023      ; TIMER_EN|IRQ_EN|IRQ_ACK
```

`IRQ0_HANDLER`（$0030）入口・B 退避直後に挿入した **2命令**:

```asm
IRQ0_HANDLER:
    DI
    STW  A, [IRQ_WK_A]
    STW  X, [IRQ_WK_X]
    STW  B, [IRQ_WK_B]

    LDW  B, #$TCR_ACK_REARM     ; ★V5: ACK＋再武装
    STW  B, [TCR]

    ; 現TCBアドレス計算 ...
```

★設計メモ §5.3 の 3命令案（`LDW A,#$FC90` / `LDW B,#$0020` / `STW B,[A]`）から改善した:
- EQU 定数は**直接メモリオペランドに書ける**（`IRQ1_HANDLER` の `[IRQ_STAT]` 参照と同作法。
  `kernel_v12_7.asm` L1189/L1210 で実源確認）→ **A を破壊しない・2命令で済む**
- 書込値は **$0023**（$0020 ではない。理由は §4）

★挿入位置は「入口・B退避直後」の1点に固定。ここ以外は不可（設計メモ §5.2/§5.3）:
- 復元部 `_sched_found` → 他経路と共有のため誤再武装
- 保存部 → `state==RUNNING` 時のみ実行のため、アイドル中の割込で ACK がスキップされ
  **タイマー永久停止**（致命的）

### 3.2 `startup_harness23_v16.asm`（v1.5 → v1.6）

- ISR 退避ワークを新設（`$000C`-`$0011`。`_syscall_disp_ptr` と `_startup` の間の空き。
  hasm23 の W001 警告なし＝`.org` 重なりなし）
- `_timer_handler` を `IRET` のみ → **A/B/X 退避＋ACK＋復元** に変更

```asm
_timer_handler:
    STW  A, [_isr_wk_a]
    STW  B, [_isr_wk_b]
    STW  X, [_isr_wk_x]
    LDW  A, #$FC90
    LDW  B, #$0023          ; ★$0020 不可★
    STW  B, [A]
    LDW  A, [_isr_wk_a]
    LDW  B, [_isr_wk_b]
    LDW  X, [_isr_wk_x]
    IRET
```

### 3.3 emu23 は**無改修**

v1.10（`emu23_v110.c`）のまま。**S2/S3 の再走は不要**である。

---

## 4. ★★本日の最重要発見（kaizen 原則74 候補）★★

### 原則74（登録必須）

> **原則74: レジスタ書込は「そのレジスタの全ビットを決める行為」である。**
> **一部のビットだけを立てるつもりで書くと、他のビットを 0 に落とす。**
>
> 背景: TCR bit5(IRQ_ACK) だけを立てるつもりで `TCR ← $0020` と書いたところ、
> TIMER_EN(bit0)/IRQ_EN(bit1) が 0 に落ち、**ACK が ACK 自身を殺した**（タイマー恒久停止）。
> メモリマップド I/O では、RMW かシャドウ変数を持たない限り、**書込値が全ビットを決める**。
> これは RTL でも同じである: `always_ff @(posedge clk) if (we) reg <= wdata;`
> MC6840 PTM でもハンドラは制御レジスタの全ビットを決めて書く。
>
> **正: `TCR ← $0023`（TIMER_EN|IRQ_EN|IRQ_ACK）＝状態ビット込みの完全な値を書く。**

### 経緯（設計判断の記録）

1. 当初 ACK を `$0020`（bit5 のみ）で実装 → **タイマー受理が 1回のまま**（改修前と同じ）
2. 「ストローブが状態ビットを壊すのは emu23 のバグではないか（案B）」と考えたが、
   **実源照合により誤りと判明**。TCR write は状態ビットを常に上書きする。
   これは emu23 のバグではなく、**RTL でも同じ挙動**である
3. **案C（ハンドラが状態ビット込みの完全値 `$0023` を書く）を採用** → PASS

### FPGA(RTL) 実装への含意（★S7 で使う★）

案C なら RTL は素直な形で済む。**追加ロジックは一切不要**:

```systemverilog
// 状態レジスタ（TCR write で全ビット更新＝メモリマップドI/Oの原則）
always_ff @(posedge clk or posedge rst)
    if (rst)          {irq_en, timer_en} <= 2'b11;   // 初期値 $03
    else if (tcr_we)  {irq_en, timer_en} <= wdata[1:0];

// イベントストローブ（1クロックパルス・状態を持たない・readで常に0）
assign irq_ack_stb  = tcr_we & wdata[5];
assign sw_start_stb = tcr_we & wdata[2];
assign sw_stop_stb  = tcr_we & wdata[3];
```

`wdata=$0023` なら `timer_en=1, irq_en=1, irq_ack_stb=1` で **emu23 と完全一致**する。

TCR が「状態ビット」と「イベントストローブ」の混在レジスタであることの実源根拠:
`emu23_v110.c` L616-619 の TCR read は **bit0/1/4 しか返さない**（bit2/3/5 は常に0）。
返らない＝状態を持たない＝ストローブ、である。

---

## 5. ★設計メモ v0.2 の誤り2件（S10 で訂正すること）★

### 誤り1: §5.3 の「Dhrystone は IE=0 で受理しない」

**誤り。** IE は `EI`（`startup_harness23_v15.asm` L63）で立っている。

**真因**: `dhry_timer.c` の `timer_start()`（L542-544）が `TCR ← $0004`（SW_START）を書く。
TCR write は丸ごと上書きなので `emu23_v110.c` L696 で `irq_enabled = 0` になる。
→ `YSD8002_tick()` が L258 で即 return 0 → **タイマーが発火しない**。

実測でも Dhrystone 実行中の **IRQ 受理は 0件**（`-q` を外して全ログ観測）。
結論（実害なし）は同じだが、根拠が違う。

> ★これは既存の潜在バグでもある★ `timer_start()` は意図せず IRQ_EN を殺している。
> ただし Dhrystone はタイマー割込を使わないため実害ゼロであり、**黄金値 826/48405 を
> 変えないために触らないのが正解**。V5 のスコープ外とする（記録に留める）。
> RTL でも同じ挙動になるため、S8 の協調等価は通る。

### 誤り2: §5.3 の ACK 命令列

3命令（`LDW A,#$FC90` / `LDW B,#$0020` / `STW B,[A]`）→ **2命令かつ書込値 `$0023`** に訂正。
EQU 定数は直接メモリオペランドに書けるため A の破壊は不要（§3.1 参照）。

---

## 6. 残工程

- S1 emu23 v1.10 実装 … ✅ 完了（CHAT87）
- S2 退行 Dhrystone … ✅ PASS（CHAT87）
- S3 退行 FPGA 回帰 55/55 … ✅ PASS（CHAT87）
- **S4 YUI OS 改修＋起動確認 … ✅ 完了（CHAT88＝本チャット）**
- **S5 CPU RTL v0.5.8（第1段 pending 保護）… ⬜ ★次はここ★**
- S6 退行 V1/V2 全82ベクタ再走 … ⬜
- S7 YSD8002 RTL 実装＋単体TB（KY54 ネガティブラン先行）… ⬜
- S8 V5 統合TB（emu23 協調等価。判定は CPU レジスタ readback）… ⬜
- S9 V5 全回帰 … ⬜
- S10 文書改版（4点整合・KY41）… ⬜

### S5 の実装内容（先出し）

`ysd8800_cpu_v0_1_FIXED.sv` を v0.5.7 → **v0.5.8** へ:

```systemverilog
if (state == S_IRQCHK && irq_in != 3'd0 && irq_pending == 3'd0)
    irq_pending <= irq_in;      // ★空の時だけ受け付ける（emu23 L1591 と同形）★
```

★注意★
- **`flags_ie` を条件に含めてはならない**（emu23 の pending ラッチは IE を見ていない）。
  実装後 `grep -n "flags_ie"` で保護ロジック行に混入していないことを**機械確認**する
- CPU コアは V3.5/V3.7/V4 と**3フェーズ連続無改修**だったため、
  **V1/V2 全82ベクタ再走が必須**（S6）

---

## 7. S10 文書改版対象

- `ysd8002_timer_design_v1_0.docx` → v1.1: TCR bit5=IRQ_ACK 新設。**ACK 書込値は $0023**。
  再武装契機 IRET → TCR-ACK。TCR が状態ビット／ストローブ混在であることを明記。旧記述は取消線で保持（KY41）
- `emu23_device_design_v1_5.docx` → v1.6: タイマー再武装方式変更。Step 8-I 廃止理由
- `v5_design_memo_v0_2.md` → **v0.3**: §5 の誤り2件を訂正（上記 §5）
- `tool_version_ledger`: emu23 v1.09 → v1.10
- `fpga_source_version_ledger`: §13（V5）新設。CPU v0.5.7 → v0.5.8
- `yuios_build_procedure`: emu23 v1.10 反映。**KERN_SRC/HARNESS が v12.8/v16 に変わる**
- YUI OS 設計書: **IRQ0_HANDLER の ACK 義務**・挿入位置の固定・**書込値 $0023**
- **`kaizen.txt`**: **原則73（CHAT87 提案）＋ 原則74（本チャット提案・上記 §4）を登録**

### 原則73（CHAT87 から持ち越し・未登録）

> **原則73: エミュレータの実装都合（命令フックによる副作用）を仕様と誤認するな。**
> **FPGA 実装可能性を仕様の妥当性判定基準に使え。**

---

## 8. 検証環境（再現手順）

```bash
# 作業DIR
mkdir -p /home/claude/w && cd /home/claude/w

# ツール（★必ずソースから自前ビルド。バージョン詐称バイナリ事故の再発防止★）
gcc -O2 -o emu23  emu23_v110.c      # ★v1.10 のまま。改修しない★
gcc -O2 -o scc23  scc23_v2_03.c
gcc -O2 -o hasm23 hasm23_v1_04.c
gcc -O2 -o lnk23  lnk23_v2_01.c

# Force はディレクトリ構成が必要（L-F 地雷）
mkdir -p frontend backend
cp ir.c ir.h lexer.c lexer.h parser.c parser.h frontend/
cp codegen_v1_5.c backend/codegen.c
cp codegen_v1_4.h backend/codegen.h
gcc -O2 -o force force_v1_5.c backend/codegen.c frontend/ir.c frontend/lexer.c frontend/parser.c

# Makefile が期待する名前へ
cp ysd8800_kern_v0_6.tgt ysd8800_kern.tgt
cp mkfs_yuifs_v1_1.py mkfs_yuifs.py

# Makefile の KERN_SRC を v12.8 に変更してから
make yuios      # → 56416 バイト
make disk       # → disk.img
./emu23 yuios_road2.bin --disk disk.img -q   # → 「YUIOS Booted!」＋ 0YUI> 123MD
```

### ★IRQ 受理を観測する方法（本チャットで確立・S8 で有用）★

emu23 は IRQ 受理時に `** IRQ N accepted, vec=XXXX **` を出力する（`emu23_v110.c` L1223-1224）。
**`-q` を付けると消える**ので、割込の実測時は `-q` を外すこと。

```bash
./emu23 yuios_road2.bin --disk disk.img -n 200000 < /dev/null 2>&1 \
  | grep -oE "IRQ [0-9] accepted" | sort | uniq -c
# 改修前: IRQ 1 が 1回（永久停止） / 改修後: IRQ 1 が 4回（周期発火）
```

> ★emu23 内部の `irq_pending` 番号は ISA IRQ 番号 +1★
> IRQ0(タイマー) → ログ上は `IRQ 1` / IRQ1(デバイス) → ログ上は `IRQ 2`

---

## 9. KY

**KY56（2026-07-13・本チャット）**:
「ACK 挿入で `IRQ0_HANDLER` の A/B を破壊し、過去の FILE-WRITE LBA6 バグを再来させる。
また `_timer_handler` は A/B を退避していないため、Dhrystone が壊れる」

→ **防止策を実行し、的中・回避した。**
- 防止策2（「Dhrystone は IE=0 だから安全」を信じず実証する）が**実際に効いた**。
  実測の結果、設計メモの前提が誤っていることを発見した（§5 誤り1）
- `_timer_handler` には A/B/X 退避を追加（案1）。Dhrystone は 826/48405/P:20 で退行なし

### 次チャットで新規に KY を1件挙げること

**S5 の KY 候補**: 「CPU コアは3フェーズ連続無改修だった。ここに手を入れると
V1〜V4 の全資産（82ベクタ＋55回帰）が一斉に壊れうる。`flags_ie` の混入も含め、
1変更1検証と S6 の全82ベクタ再走を省略しない」

---

## 10. 本チャットで効いた規律

> **「見込み」を書いた設計書は、その見込み自体を検証対象にする。**
>
> 設計メモ §5.3 には「Dhrystone は IE=0 なので実害はない**見込み**だが、KY34 により実証すること」
> と書かれていた。**この一文が本チャットを救った。** 実証した結果、見込みの根拠は誤りだった。
> 見込みのまま進んでいれば、Dhrystone が壊れた時に原因を見失っていた。
>
> **設計書に「〜の見込み」と書いたら、それは必ず実測でクローズする。**

---

## 11. 改版履歴

| 版 | 日付 | 内容 |
|---|---|---|
| v1.0 | 2026-07-13 | CHAT88 引継ぎ。**S4 完了（全ゲート PASS）**。ACK 書込値を $0020 → **$0023** に是正（原則74）。emu23 は無改修で確定。次は S5（CPU RTL v0.5.8）。 |
