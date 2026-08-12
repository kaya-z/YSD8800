# HANDOVER_CHAT96.md

- **作成日**: 2026-07-16
- **前HANDOVER**: HANDOVER_CHAT95.md
- **工程位置**: Step 8 / FPGA V5(YSD8002 タイマー) / S8 統合TB FAIL恒久対策 / **案0-a' 設計承認＋RTL実装(S2)完了。S3(統合TB再実行)は未着手**
- **作成理由**: ログ長大化の危険回避のため、ユーザ明示指示により作成

---

## 1. CHAT96 の成果サマリ

CHAT96 は「タイマー10」= V5/S8 統合TB FAIL の恒久対策（案0-a'）について、
**①設計メモ起票 → ②有識者レビュー承認 → ③RTL実装(S2)完了・全ファイル構文PASS**
までを完遂した。S3(統合TB再実行)以降は次チャットへ引継ぐ。

### 1.1 設計判断（案0-a'）の確定
- CHAT95で有識者が推奨した案0-a を、実源確認で精緻化して **案0-a'** として起票。
- ★重要訂正★: HANDOVER_CHAT95 §3.1 / 前回回答書の「irq_ack を YSD8004経由」は
  **タイマー(IRQ0)には当てはまらない**。実源照合の結果、タイマーはYSD8004非経由の
  独立系統(IRQ0直結)と確定。`irq0_ack` は CPU→membus→mmio_stub→YSD8002 に**直結**。
- ★これにより UART(V4完了・19/19PASS) / YSD8004 は完全無改修。デグレ範囲を系統ごと排除★

### 1.2 信号名・表記の確定（ユーザ指摘反映）
- 名称: **`irq0_ack`**（当初 `irq_ack_timer` はtimer特化しすぎとのユーザ指摘。
  IRQ0系統の抽象＝既存 `irq1_o` と同じ系統番号ベース命名に統一）
- 表記: **小文字スネークケース**（プロジェクト規約=信号は小文字/定数は大文字。
  実源 `irq_src_*`・`irq1_o`・`dbg_irq_pending` で裏取り）

### 1.3 レビュー承認
- `v5_irq0_ack_design_review_reply_v1_0.md`（有識者回答・uploads受領）
- **総合判定: 承認（Mレベル指摘なし）。原則43クリア・実装着手可。**
- 未決3点に実源決着（後述§3）。

---

## 2. ★確定した真因と対策（案0-a'）★

### 2.1 真因（実源で裏取り済み）
現状RTL(v0_2_poc)は `irq_req_r` を下ろす経路が **ACK(bit5)書込の1箇所だけ**。
emu23では割込線消滅は**受理**で起きる(`irq_pending=-1`=チケット消費)が、
**RTLには受理でクリアする経路が存在しない**。
→ noack時: fire→irq_req_r=1→受理→IRET(ACKなし)→irq_req_r=1のまま
  →EI復帰で即再受理→無限ループ→CNT暴走(17069)。
★ACKは本来「再武装」契機。「割込線クリア」契機ではない。両者をACK一発に短絡させたのが元バグ★

### 2.2 対策（案0-a'）
CPUの割込受理確定を `irq0_ack` パルスとしてYSD8002へ直結し `irq_req_r` を下ろす。
ACK(bit5)は「再武装」専任に戻す。emu23の2層モデル
（発火チケット＝受理で消費／ACK＝再武装）と構造的に一致させる。

---

## 3. レビュー回答書の実源決着（S3実装で厳守）

- **§5-1 fire優先**: 同一クロックで fire と irq0_ack が競合したら fire(set)優先。
  実装 `if(fire) irq_req_r<=1; else if(irq0_ack) irq_req_r<=0;`。
  （発火取りこぼしは回復不能／クリア1クロック遅延は無害）→ **実装済み**
- **§5-2 comb assign**: CPUは独立 assign 1文で出せる。既存 ff/comb ブロック無改変。
  → **実装済み**（下記 assign）
- **§5-3 irq_latch==1 ガード**: 全受理がCTX_IRQVEC共通経路だが、
  irq_latch値でtimer(1)のみ抽出。device(2)/align(3)/syscall(4)では立たない。
  → **実装済み**

---

## 4. ★S2実装(完了)の内容と成果物md5★

4ファイルを修正、各段で iverilog 12.0 構文チェック PASS。

| # | ファイル | md5(CHAT96終了時) | 修正内容 | 構文 |
|---|---|---|---|---|
| ① | ysd8800_ysd8002_v0_2_poc.sv | `a52984cc47598f491e4be8537d3a9b05` | irq0_ack入力＋受理クリア経路(fire優先else if) | PASS |
| ② | ysd8800_cpu_v0_1_FIXED.sv | `e742b59c012e102c47a536bc0c16f88b` | irq0_ack出力ポート＋独立assign1文(既存ff無改変) | PASS |
| ③ | ysd8800_mmio_stub_v0_5_poc.sv | `22f10ae8b1cfc3db740bc56b5ccde16d` | irq0_ack入力＋YSD8002接続＋**v0_2_poc差替(KY60解消)** | PASS |
| ④ | ysd8800_v5_membus_v0_1_poc.sv | `d5f8c531ae5e9aa9709d8c1a812ca2d8` | irq0_ack入力＋mmio_stub中継 | PASS |

設計メモ: `v5_irq0_ack_design_v0_1.md` (`ad6a4afdc1d98a62a36b1205fe83e07e`)

### 4.1 実装したコードの要点（次チャットが参照する箇所）

**② CPU irq0_ack 生成（独立assign, dbg_irq_pending always_comb 終端の直後）**:
```systemverilog
assign irq0_ack = (state == S_MEMR_HI) && mem_ready
                  && (stack_ctx == CTX_IRQVEC) && (irq_latch == 3'd1);
```
（β点=ベクタ読み完了。CPUポートは `output logic irq0_ack` を dbg_irq_pending の後に追加）

**① YSD8002 受理クリア（fireブロックに else if 追加）**:
```systemverilog
if (fire) begin
    armed_r   <= 1'b0;
    irq_req_r <= 1'b1;
end
else if (irq0_ack) begin
    irq_req_r <= 1'b0;   // 受理=割込線を下ろす(再武装せず)
end
```
（YSD8002ポートは `input logic irq0_ack` を cycle_i の後に追加）

**③④ 配線**: CPU.irq0_ack → membus.irq0_ack(入力) → mmio_stub.irq0_ack(入力)
→ u_ysd8002.irq0_ack。★membusにCPUインスタンスは無い★。CPUは統合TB側でインスタンス化。

---

## 5. ★次工程(CHAT97)の残タスク★

### 5.1 S3: 統合TB修正・再実行（最優先）
- ★統合TB `tb_cpu_v5timer_poc.sv` に **CPUの irq0_ack 出力 → membus の irq0_ack 入力**
  の結線追加が必須★（CPU新ポート追加に伴う。これを忘れるとポート未接続で
  irq0_ackが常時Xまたは0になり、noackが直らない）。
- ビルド順序(CHAT94確定・厳守):
  1. `ysd8800_decoder_v0_1.sv`(package定義のため**最初**)
  2. 依存: addr_decoder / ysd8001 / ysd8002_v0_2_poc / ysd8004 / mmu /
     psram_ctrl / cdc_bridge / mmio_stub / membus / cpu(regfile,alu含む) / TB
  3. `ysd8800_ysd8004_v0_1.sv` は mmio_stub 依存として必須(忘れやすい)
- 実行: **vvp は timeout 付き**。前回 psram_clk=#0.5 で約11.5分・約8000万sim event。
  nohup バックグラウンド＋sleep polling 推奨(CHAT93/94方式)。build/run分離・`&&`連結禁止。
- ★合否判定(原則63・回答書§7)★:
  - **noack = CNT1**（暴走17069→1に回復）
  - **ack = OUTC200**（33→200に回復。★片方だけの回復で満足しない★）
  - 両方回復して初めて真因クローズ。

### 5.2 S4: デグレ絶対ゲート（CPU改修が入ったため必須）
- **V1/V2 全82ベクタ再走 → デグレゼロ**（comb1行追加だが実証省略しない・回答書§7）
- **Dhrystone 絶対ゲート = 826/48405/P:20** 完全一致
  （IE=0で割込受理せず irq0_ack は一度も立たない見込みだが実証で確定）

### 5.3 S5: 版数・台帳更新
- RTL版数繰り上げ（v0_2_poc→次版、cpu/mmio_stub/membus も版数整合）
- `fpga_source_version_ledger` 更新
- ★emu23 無変更ゆえ黄金ref再ベースライン不要★（案0の決定的優位。案3不採用の帰結）

### 5.4 文書整合（KY41・4点整合）
- mmio_stub ヘッダ L20 のコメント「ysd8800_ysd8002_v0_1 をインスタンス化」が
  実体(v0_2_poc差替済)と不整合。**KY41で修正要**（ファイル名/版文字列/ヘッダ日付/変更履歴の4点整合）。
- 各RTLの版数を上げる際、ヘッダ・変更履歴も同時更新（追記のみ・旧情報欠落禁止）。

---

## 6. kaizen 登録候補（未登録・CHAT97で登録要否判断）

- **原則78候補（回答書§9推奨）**:
  「割込アクノリッジ(や外部ハンドシェイク)の経路は、一般論(INTAはPIC経由)でなく、
   当該割込源が実際にどの系統でCPUへ入るかを実源で確認してから決めよ。」
  - 本件で前回回答書の「YSD8004経由」という一般論記述が、実プロジェクトのIRQ0直結
    構成で訂正された好例。レビュアー側の一般化の落とし穴。
- ※HANDOVER_CHAT95 §4の「原則77候補(モデル非等価の主張は層ごと対応づけ後に)」は
  既存原則77(設計負債は記録先行)と番号衝突。CHAT97で番号整理して登録要否判断。

---

## 7. 申し送り事項

### 7.1 KY60 — ★解消済★
- mmio_stub の YSD8002 インスタンスを v0_1→v0_2_poc に差替済(本CHAT96 ③)。
- ただし**ヘッダコメント(L20)は未修正**。§5.4のKY41対応で本文と揃えること。
- セッション開始スナップショット(`/mnt/project/`)は旧md5で見える場合があるが、
  「未登録」でなく「セッション開始後に更新された可能性」を先に疑う(CHAT95教訓)。

### 7.2 環境
- iverilog は**セッション標準では未インストール**。`apt-get install -y iverilog`
  (root環境ゆえsudo不要。sudoは存在しない)。バージョンは 12.0(プロジェクト指定と一致)。
- 作業ディレクトリ `/home/claude/w/` はセッション間で消える。CHAT97では
  必要RTL(§5.1のビルド順序の全ファイル)＋TB＋hexを再配置すること。

### 7.3 CPU RTL 照合の注意
- 回答書は `ysd8800_cpu_v0_1.sv`(irq_latch L290等)を照合しているが、
  ナレッジ実体は `ysd8800_cpu_v0_1_FIXED.sv`(irq_latch L324等)のみ。
  **行番号は異なるが論理内容は同一**(CHAT96で内容照合済)。実装対象はFIXED版。

### 7.4 テストプログラム
- `v5t_ack.asm/.hex`, `v5t_noack.asm/.hex` はナレッジにあり(SP初期化済・CHAT93対応版)。
  S3で流用。emu23黄金値: ack=CNT30/OUTC200/正常HALT, noack=CNT1。

---

## 8. CHAT97 想定 KY

- ★TB結線漏れの危険★: CPU新ポート `irq0_ack` を TB で membus に繋ぎ忘れると、
  irq0_ack が届かず noack が直らない(17069のまま)。「直ってない=結線漏れ」を
  最初に疑う(実装ロジックを疑う前にポート接続をgrepで確認)。
  - 防止策: TB修正後、`grep -n irq0_ack tb_cpu_v5timer_poc.sv` で CPU出力→membus入力の
    結線を目視確認してからビルドする。1変更1検証。

---

（以上 HANDOVER_CHAT96.md v1.0 / 2026-07-16）
