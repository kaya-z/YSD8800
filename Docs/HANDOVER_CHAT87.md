# HANDOVER_CHAT87.md

**作成日**: 2026-07-13
**前チャット**: CHAT87（FPGA V5 タイマー：設計〜S3 完了）
**次チャット**: **S4（YUI OS 改修）から再開**
**工程**: Step 8 / FPGA 実装 V5（YSD8002 タイマー）

---

## 0. 【最初にやること】§0.1 実在確認

新チャット冒頭で、以下がプロジェクトナレッジに実在するか **必ず `ls`/`view` で確認**すること（KY49：HANDOVER に「完成済み✅」と書かれていても実在確認を先に行う。過去2回発生）。

| # | ファイル | 用途 |
|---|---|---|
| 1 | `emu23_v110.c` | ★本日の主成果物。emu23 v1.10（黄金リファレンス改修版）★ |
| 2 | `v5_design_memo_v0_2.md` | ★V5 設計メモ（承認済）。S4 以降の唯一の設計根拠★ |
| 3 | `v5_design_review_reply_v1_0.docx` | レビュー回答書（D1〜D6 全承認） |
| 4 | `kernel_v12_7.asm` | S4 の改修対象（IRQ0_HANDLER） |
| 5 | `startup_harness23_v15.asm` | S4 の改修対象（_timer_handler） |
| 6 | `kaizen.txt` | 原則72 まで（S10 で **原則73** を追加予定） |

★1・2 が無い場合は先に登録を依頼すること。無いまま S4 に進んではならない。★

---

## 1. 本チャットの結論（一言）

> **emu23 v1.09 の「IRET 命令でタイマーを再武装する」設計は FPGA 実装不能な設計負債であった。**
> **これを TCR bit5(IRQ_ACK) 方式に是正し（v1.10）、退行ゲート S2/S3 を通過した。**

---

## 2. 完了工程

### ✅ 設計（原則43：設計→レビュー→承認→実装）

- `v5_design_memo_v0_1.md` 作成 → レビュー（`v5_design_review_reply_v1_0.docx`）
- **D1〜D6 全承認。★黄金リファレンス改修（emu23 v1.09→v1.10）承認★**
- C級指摘3件（C-1/C-2/C-3）を反映し **`v5_design_memo_v0_2.md`** へ改版

### ✅ S1: emu23 v1.10 実装

| # | 改修 |
|---|---|
| ① | `static int timer_in_service` **削除** |
| ② | IRQ受理部 `timer_in_service = 1` **削除** |
| ③ | IRET 内 `YSD8002_iret()` 呼出 **削除**（★v1.07 Step 8-I 修正が丸ごと不要化★） |
| ④ | TCR write マスク `0x17` → **`0x37`**。**bit5 = IRQ_ACK 新設**（書込時 `YSD8002_rearm()` 呼出＋自動クリア） |
| ⑤ | `YSD8002_iret()` → **`YSD8002_rearm()`** に改名（意味の是正） |
| ⑥ | バージョン表示を v1.10 に更新（**`--version` と REPL バナーの両方**。バナー側が漏れていたので修正済） |

### ✅ S2: Dhrystone 絶対ゲート — **PASS**

| 項目 | v1.09 | v1.10 | 判定 |
|---|---|---|---|
| Dhrystones/sec | 826 | **826** | ✅ |
| cycles | 48405 | **48405** | ✅ |
| P | 20 | **20** | ✅ |
| 全出力 diff | — | **★差分ゼロ★** | ✅ |

### ✅ S3: FPGA 回帰 55/55 — **PASS**

| 検証 | 結果 |
|---|---|
| **golden 完全一致**（v1.09 vs v1.10・92ファイル） | ✅ `diff -r` 差分ゼロ／**md5 = `31105277e84bdc680db7c97c8f683f11`** |
| **RTL 回帰** | ✅ **55/55 ALL PASS・FAIL=0** |

内訳: v4regress 20 / v4mem 5 / v4boundary 1 / v4mmu 6 / v4uart(S5統合) 23 = **55**

> ★**S3 の方法論に注意**★
> `gen_*.py` が **`./emu23` を実行して golden を動的生成する**構造である。
> よって「emu23 を差し替えて TB を再実行する」だけでは退行検出にならない場合がある。
> **正しくは「v1.09 の golden」と「v1.10 の golden」を md5 で突き合わせる。** 本チャットはこの方式で実証した。

**→ 設計メモ §6 の撤退基準（S2/S3 落ちたら撤回）をクリア。TCR-ACK 方式は続行可能。**

---

## 3. ★次工程 S4（YUI OS 改修）— 本工程の最大リスク★

### 3.1 なぜ最大リスクか

**過去に A/B 復元漏れで実バグ（FILE-WRITE LBA6 byte434-511 欠落）を起こした `IRQ0_HANDLER` へ、A/B を破壊する命令を挿入する。**

### 3.2 ★ACK 挿入位置は「1点」に確定済み。ここ以外は不可★

設計メモ v0.2 §5.2/§5.3 で、**復元部・保存部の双方が不可**であることを実源照合で確定した。

| 候補 | 可否 | 理由 |
|---|---|---|
| 復元部 `_sched_found` 末尾 | ❌ **論外** | IRET 直前は A/B/X/SP が全て**新タスクの値**。しかも `IRQ_WK_A`/`IRQ_WK_B` すら復元の一時退避に**再利用済み**で空き領域が無い |
| 復元部（別位置） | ❌ | `_sched_found` は **TASK_SLEEP 等から JMP される共有経路**。タイマー割込以外でも ACK が出る＝**誤再武装** |
| 保存部 | ❌ **致命的** | 保存部は **`state==RUNNING` 時のみ実行**（v0.12.6 修正）。**アイドル中の割込で ACK がスキップ → タイマー永久停止** |
| **★入口・B退避直後★** | ✅ **唯一安全** | 分岐より前／入口は他経路と非共有／1回のみ／A/B/X 退避済み |

### 3.3 実源（KY34：この行番号で実ファイルを開いて確認すること）

**`kernel_v12_7.asm`**（実測 2026-07-13）:
```
400:    .org $0030
401: IRQ0_HANDLER:
402:     DI
403:     STW  A, [IRQ_WK_A]
404:     STW  X, [IRQ_WK_X]
405:     STW  B, [IRQ_WK_B]          ; v0.12.6: 中断時のBを退避
406:                                  ← ★ここに挿入★
407:     ; 現TCBアドレス計算
408:     LDW  A, [CUR_TASK]
```

**挿入する3命令:**
```asm
    ;--- ★V5: タイマーACK＋再武装（TCR bit5）★ ---
    LDW  A, #$FC90              ; TCR
    LDW  B, #$0020              ; IRQ_ACK (bit5)
    STW  B, [A]                 ; A/B破壊可（L403-405 で退避済み）
```

**`startup_harness23_v15.asm`**（実測）:
```
72: _timer_handler:
73:     IRET
```
→ ACK 3命令を IRET の前に挿入。
> ★**要注意**★ `_timer_handler` は **A/B を退避していない**（現状 IRET のみで A/B 不使用のため顕在化せず）。
> V5 で A/B を破壊するため、**A/B 退避の要否を S4 で判断すること**。
> （Dhrystone は IE=0 でタイマー割込を受理しないため実害は無い見込みだが、**KY34 により実証すること**）

### 3.4 S4 のゲート

| # | 確認 |
|---|---|
| 1 | yuios.bin が **「YUIOS Booted!」** を出力（`--disk disk.img` 必須） |
| 2 | ★**FILE-WRITE LBA6 完全性の再現テスト**★（レビュー C-1 で強く推奨。過去バグの再発検出） |
| 3 | Dhrystone 再確認（`_timer_handler` 改修の影響確認） |

---

## 4. 残工程（設計メモ v0.2 §6）

| # | 作業 | 状態 |
|---|---|---|
| S1 | emu23 v1.10 実装 | ✅ **完了** |
| S2 | ★退行★ Dhrystone 826/48405/P:20 | ✅ **PASS** |
| S3 | ★退行★ FPGA 回帰 55/55 | ✅ **PASS** |
| **S4** | **YUI OS 改修＋起動確認＋LBA6 再現テスト** | ⬜ **次はここ** |
| S5 | CPU RTL v0.5.8（第1段 pending 保護） | ⬜ |
| S6 | ★退行★ V1/V2 全82ベクタ再走 | ⬜ |
| S7 | YSD8002 RTL 実装＋単体TB（**KY54 ネガティブラン先行**） | ⬜ |
| S8 | V5 統合TB（emu23 協調等価。**判定は CPU レジスタ readback**） | ⬜ |
| S9 | V5 全回帰 | ⬜ |
| S10 | 文書改版（4点整合・KY41） | ⬜ |

### S5 の実装内容（先出し）

```systemverilog
// ysd8800_cpu_v0_1_FIXED.sv  v0.5.7 → v0.5.8
if (state == S_IRQCHK && irq_in != 3'd0 && irq_pending == 3'd0)
    irq_pending <= irq_in;      // ★空の時だけ受け付ける（emu23 L1556 と同形）★
```
> ★**`flags_ie` を条件に含めてはならない**★（emu23 L1556 も `FL_IE` を見ていない）。
> 実装後 `grep -n "flags_ie"` で保護ロジック行に混入していないことを**機械確認**する。
> CPU コアは V3.5/V3.7/V4 と**3フェーズ連続無改修**だったため、**V1/V2 全82ベクタ再走が必須**（S6）。

---

## 5. S10 文書改版対象

| 文書 | 改版内容 |
|---|---|
| `ysd8002_timer_design_v1_0.docx` → **v1.1** | TCR bit5=IRQ_ACK 新設。再武装契機 IRET→TCR-ACK。**旧記述は取消線で保持（KY41）** |
| `emu23_device_design_v1_5.docx` → **v1.6** | タイマー再武装方式変更。Step 8-I 廃止理由 |
| `tool_version_ledger` | emu23 v1.09 → **v1.10** |
| `fpga_source_version_ledger` | §13（V5）新設。CPU **v0.5.7 → v0.5.8** |
| `yuios_build_procedure` | emu23 v1.10 反映 |
| YUI OS 設計書 | **IRQ0_HANDLER の ACK 義務**・挿入位置の固定 |
| **`kaizen.txt`** | **★原則73（下記）を登録★** |

### ★kaizen 原則73（登録必須・レビューが「最も価値ある教訓の一つ」と評価）★

> **原則73: エミュレータの実装都合（命令フックによる副作用）を仕様と誤認するな。**
> **FPGA 実装可能性を仕様の妥当性判定基準に使え。**
>
> 背景: emu23 は IRET 命令をフックしてタイマーを再武装していた（`timer_in_service`）。
> エミュレータは命令実行をフックできるが、**ハードウェアにそんなフックはない**。
> MC6809 は RTI を外部にブロードキャストしない。バスにそんな信号は存在しない。
> **「実機ならこの信号線をどう引くか？」を問えば、実装不能な仕様が炙り出せる。**

---

## 6. 技術メモ（S5 以降で効く）

- **タイマー割込は「1クロックパルス＋自己武装解除」**。V4 の UART TX（TDRE＝**レベル**）とは性質が異なる。
  TDRE は「バッファが空である限り要求し続ける」**状態信号**、タイマーは「時刻が来た」**イベント信号**。
- 本方式では **タイマーは発火後に自己沈黙し、ACK があるまで再発火しない**。
  → V4 の TX で問題になった「余分1発」（原則69）は **タイマーでは構造的に発生しない**。
  ただし**原則69 の要件自体は IRQ1/UART 側で依然有効**。
- **ACK は1割込につき1回だけ**。複数回書くと周期がずれる（§3.3 C-2）。
- **将来課題（V5スコープ外）**: 本方式は再トリガ型のため割込応答レイテンシ分のドリフトを持つ
  （IRET 自動再武装も同性質だったので等価性は保たれる）。ジッタのない固定周期が必要になったら
  **free-run カウンタ＋比較レジスタ（コンペアマッチ）方式**へ移行する余地がある。

---

## 7. 検証環境（再現手順）

```bash
# ツール（★必ずソースから自前ビルド。バージョン詐称バイナリ事故の再発防止＝手順書v1.9 ルールC/D★）
gcc -O2 -o emu23  emu23_v110.c
gcc -O2 -o scc23  scc23_v2_03.c
gcc -O2 -o hasm23 hasm23_v1_04.c     # 実体検証: strings ./hasm23 | grep has_vector
gcc -O2 -o lnk23  lnk23_v2_01.c

# Dhrystone（S2）※オプションはプログラム名の【後ろ】
./scc23 --code-org 0x0400 --data-org 0x4000 --runtime-org 0x0100 -o dhry.asm dhry_timer.c
./hasm23 dhry.asm
MAIN=$(grep -E '^[0-9a-f]+ _main$' dhry.asm.sym | awk '{print $1}')
sed -E "s/JSR[[:space:]]+_main/JSR  \\\$${MAIN}/" startup_harness23_v15.asm > startup_harness23.asm
./hasm23 startup_harness23.asm
printf 'SECTION code 0x0000 dhry.asm.bin\nSECTION harness 0x0000 startup_harness23.asm.bin\n' > dhry.lds
./lnk23 -o dhry_final.bin --sym dhry_final.sym dhry.lds
timeout 180 ./emu23 dhry_final.bin -q < /dev/null      # → 826 / 48405 / P:20

# FPGA 回帰（S3）
apt-get install -y iverilog                            # Icarus Verilog 12.0
python3 mk_v4_regress_tb.py                            # V3.5 TB → V4 へ機械変換
for g in gen_v2_vectors.py gen_v3_mem_vectors.py gen_v3_boundary_vectors.py \
         gen_v35_mmu_vectors.py gen_v4_uart_vectors.py gen_v4_uart_c_vectors.py; do
  python3 $g; done                                     # ★./emu23 を呼んで golden 生成★
for t in tb_cpu_v4regress_poc tb_cpu_v4mem_poc tb_cpu_v4boundary_poc \
         tb_cpu_v4mmu_v0_1 tb_cpu_v4uart_v0_2; do
  ./build_v4.sh $t.sv $t $t.vvp && timeout 300 vvp $t.vvp; done   # → 55/55 ALL PASS
```

> **落とし穴**: `grep -c FAIL` は `FAIL=0` 行にも反応する（偽陽性）。集計は TB 自身の
> 「ALL PASS」「N error(s)」行を見ること。

---

## 8. KY（本日 KY55・次チャットで新規に1件挙げること）

**KY55（2026-07-13）**: 「V5 のタイマー割込をパルス/レベルで無検討に決め、原則69 を織り込み忘れて
二重カウント／取りこぼしを埋め込む」
→ **防止策を実行し、実源照合により「パルス＋自己武装解除」を根拠づけて決定した。的中・回避済み。**

**S3 で実際に効いた規律**:
> golden に差分が出た際、**まず自分の手順を疑った**（結果：両版で生成スクリプトの実行条件が
> 非対称だった＝私の手順ミス）。早合点して V5 案を撤回していたら**正しい設計を誤って捨てていた**。
> **差分を見たら、まず手順を疑う。**

---

## 9. 改版履歴

| 版 | 日付 | 内容 |
|---|---|---|
| v1.0 | 2026-07-13 | CHAT87 引継ぎ。V5 設計（TCR-ACK 方式）承認〜S1（emu23 v1.10）〜S2（Dhrystone PASS）〜S3（golden md5 一致・回帰 55/55 PASS）完了。**次は S4（YUI OS 改修・本工程の最大リスク）**。 |
