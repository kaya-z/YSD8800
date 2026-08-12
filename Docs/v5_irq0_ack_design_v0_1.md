# v5_irq0_ack_design_v0_1.md

- **文書種別**: 設計メモ（レビュー用・未承認）
- **バージョン**: v0.1
- **作成日**: 2026-07-16
- **工程**: Step 8 / FPGA V5(YSD8002 タイマー) / S8 統合TB FAIL の恒久対策（案0-a'）
- **黄金リファレンス**: emu23 v1.10（TCR-ACK方式）
- **関連**: HANDOVER_CHAT95.md §3、v5_irq_model_decision_reply_v1_0.docx（有識者回答書）、原則76/63/43

---

## 1. 目的

V5/S8 統合TB の FAIL（noack=CNT17069暴走 / ack=OUTC33）を、黄金リファレンス
emu23 v1.10 と構造的に等価な形で恒久解決する。有識者回答書が推奨する
**案0（RTL修正・黄金ref無変更）** を、CHAT96 の実源確認で得た知見により
**案0-a'** として具体化する。

---

## 2. 確定した真因（実源で裏取り済み）

### 2.1 emu23（黄金・2層モデル）
1. **発火**: `YSD8002_tick` が1回だけ `irq_pending=1`(チケット) を置く。
   同時に `next_irq_cycle=UINT64_MAX` で発火源が黙る（自己武装解除）。
2. **再武装**: IRET/ACK が `next_irq_cycle=cycle+period` を再設定するまで沈黙。
3. 発火チケットは **CPU受理で消費**（`irq_pending=-1`）。

### 2.2 RTL(v0_2_poc) の真のバグ
現状 `irq_req_r` を下ろす経路は **ACK(bit5)書込の1箇所だけ**
（ysd8800_ysd8002_v0_2_poc.sv L282）。
emu23 では割込線消滅は **受理** で起きるが、**RTLには受理で `irq_req_r` を
下ろす経路が存在しない**。

- `armed_r=0`（L257 で実装済み）は「次の fire を止める」効果のみ。
  「既に立っている `irq_req_r` を消す」効果はない。
- noack時: fire→irq_req_r=1 → 受理 → IRET(ACKなし) → irq_req_r=1のまま
  → EI復帰で **即再受理** → 無限ループ → CNT暴走(17069)。
- ★ACK は本来「再武装」契機。「割込線クリア」契機ではない。
  両者を ACK 一発に短絡させたことがバグ。★（MC6840 PTM でも
  「割込フラグのクリア」と「タイマー再スタート」は別操作）

---

## 3. 対策（案0-a'）

### 3.1 方針
CPUの割込受理を **`irq0_ack`** として YSD8002 へ返し、それで `irq_req_r` を
下ろす。ACK(bit5) は「再武装」専任に戻す。これで emu23 の2層モデル
（発火チケット＝受理で消費／ACK＝再武装）と RTL が構造的に一致する。

### 3.2 ★YSD8004 は経由しない（重要な訂正）★
HANDOVER_CHAT95 §3.1 / 有識者回答書の「YSD8004経由でデバイスに伝える」は
**タイマー(IRQ0)には当てはまらない**。実源で確定した割込系統:

| 系統 | デバイス | 集約 | irq_latch値 |
|---|---|---|---|
| IRQ0 | YSD8002(timer) | なし(直結) | **1** |
| IRQ1 | UART_RX/STOR/UART_TX | YSD8004(ワイヤードOR) | 2(device) |

- YSD8004 は **IRQ1系統の集約器**。出力は `irq1_o` レベル1本のみ
  （ysd8800_ysd8004_v0_1.sv L86）。逆方向(CPU→デバイス)ポートは持たない。
- タイマーは **IRQ0で直接CPUに入る独立系統**。YSD8004を通らない。
- ゆえに `irq0_ack` は **YSD8004を経由せず YSD8002 へ直結**する。
- ★結果: UART(V4完了・19/19PASS)・YSD8004 ともに **完全無改修**。
  デグレ危険を系統ごと排除。★

### 3.3 信号名・表記（確定）
- 名称: **`irq0_ack`**（IRQ0系統の受理。timer特化名を避け、
  既存 `irq1_o` と同じ系統番号ベース命名に合わせる）
- 表記: **小文字スネークケース**
  （本プロジェクト規約=信号は小文字/定数は大文字。
   実源 `irq_src_*`・`irq1_o`・`dbg_irq_pending` で裏取り済み）

### 3.4 `irq0_ack` の生成条件（CPUコア側）
実源確定事項:
- `irq_latch`(3bit, L324) が受理中IRQ番号を保持。**1=timer / 2=device /
  3=align / 4=syscall**。FSMは受理中番号を完全に区別できる。
- 割込ベクタ読み完了は `S_MEMR_HI` 状態で
  `mem_ready && stack_ctx==CTX_IRQVEC` のとき PC←ベクタ値（L1084-1088）。

**生成条件（推奨=β点）**:
```
irq0_ack = (state==S_MEMR_HI) && mem_ready && (stack_ctx==CTX_IRQVEC)
                              && (irq_latch==3'd1);   // 1クロックパルス
```
- ★β点(ベクタ読み完了)を採る理由★: この瞬間が「受理が後戻りしない
  確定点」。emu23 でチケットが消費される(irq_pending=-1)タイミングと
  最も等価。α点(S_IRQ_ACCEPT入口)だと受理途中アボート時に線を早く
  消しすぎるリスクがある(現状アボート経路は無いが、将来の安全側)。
- `irq_latch==3'd1` ガードにより、**UART受理(irq_latch==2)では
  `irq0_ack` は立たない**。IRQ1系統に一切影響しない。

### 3.5 YSD8002 側の受け（`irq_req_r` クリア経路の新設）
現状 `irq_req_r` は fire で set / ACK(bit5) で clear。
これに **`irq0_ack` で clear** を追加する。

```
// (0) 受理による割込線クリア ★新設★ (emu23: 受理でチケット消費)
if (irq0_ack) begin
    irq_req_r <= 1'b0;      // 受理=割込線を下ろす(再武装はしない)
end
// (1) 発火 → 自己武装解除 (既存 L256-261)
if (fire) begin ... end
// (2) ACK(bit5) → 再武装(cnt_r更新+armed_r=1) ★clearはもう担わない★
```

**優先順位の設計**（同一クロック競合時）:
- `irq0_ack` と `fire` が同クロック: 通常は起こらない（fireは発火時のみ、
  irq0_ackは受理完了時。受理はfireの数クロック後）。万一競合したら
  fire(set)を優先すべきか要検討 → §5 未決事項。
- `irq0_ack` と ACK(bit5) が同クロック: どちらも clear なので結果同一。競合無害。

### 3.6 emu23 との等価性（noack/ack両ケース）
| ケース | emu23 | 修正後RTL(期待) |
|---|---|---|
| noack | fire→受理→irq_pending消費→再武装されず→**CNT1** | fire→irq_req_r=1→**受理でirq0_ackクリア**→再武装なし→CNT1 |
| ack | fire→受理→消費→ACKで再武装→周期発火→**CNT30/OUTC200** | fire→受理でクリア→ACKで再武装→周期発火→CNT30/OUTC200 |

---

## 4. 影響範囲とデグレ対策

### 4.1 改修ファイル
| ファイル | 改修内容 | 版 |
|---|---|---|
| ysd8800_cpu_v0_1_FIXED.sv | `irq0_ack` 出力ポート新設 + β点パルス生成 | 次版 |
| ysd8800_ysd8002_v0_2_poc.sv | `irq0_ack` 入力 + irq_req_r クリア経路追加 | 次版 |
| ysd8800_mmio_stub_v0_5_poc.sv | irq0_ack 配線 + YSD8002 v0_2版へ差替(KY60解消) | 次版 |
| ysd8800_v5_membus_v0_1_poc.sv | irq0_ack 引き回し(CPU→mmio_stub→YSD8002) | 次版 |

### 4.2 ★デグレ絶対ゲート（原則63/76）★
CPUコア改修が入るため、以下を **必達**:
1. **V1/V2 全82ベクタ再走 → デグレゼロ**
2. **Dhrystone 絶対ゲート = 826/48405/P:20** 完全一致
3. S8統合TB: **noack=CNT1 と ack=OUTC200 の両方**回復（片方だけで満足しない）

### 4.3 CPU改修の封じ込め（KY）
- CPU改修は **`irq0_ack` 出力1本の追加のみ**。既存FSM状態遷移
  （S_IRQCHK/S_IRQ_ACCEPT/S_MEMR_HI）のロジックには **手を入れない**
  （追加はすれど改変せず）。
- `irq0_ack` は combのassign（既存ffに触れない）で生成できるか要確認 → §5。

---

## 5. 未決事項（レビューで方針確定したい点）

1. **§3.5 fire と irq0_ack の同クロック競合**の優先順位。
   （現実には数クロック離れるため競合しない想定。安全側の明文化のみ）
2. **§4.3 irq0_ack を comb assign で出せるか**、ff追加が要るか。
   comb で出せれば既存ff無改変を保証でき、デグレ危険が最小。
3. β点(S_MEMR_HI)で `stack_ctx==CTX_IRQVEC` ガードが timer/device/align/
   syscall の全受理で正しく立つか（align/syscall受理でも CTX_IRQVEC を
   通るなら irq_latch==1 ガードで排除できているか）の実源再確認。

---

## 6. 実施順序（承認後）

- S2: 上記4ファイルを次版へRTL修正（1ファイル1検証）
- S3: 統合TB再実行 → noack=CNT1 / ack=OUTC200 両方確認
- S4: Dhrystone絶対ゲート + V1/V2全82ベクタ再走(デグレゼロ)
- S5: fpga_source_version_ledger 更新（emu23無変更ゆえ黄金ref再ベースライン不要）

---

（以上 v5_irq0_ack_design_v0_1.md v0.1 / 2026-07-16 / レビュー待ち）
