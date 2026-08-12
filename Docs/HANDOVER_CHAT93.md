# HANDOVER_CHAT93.md

- **作成日**: 2026-07-15
- **前チャット**: CHAT92（V5 S8 §5.1差替＋テスト項目レビュー承認）
- **本チャット(CHAT93)**: V5 S8統合TB ─ §5.4(t2_ack 4要件確認)→§5.5(TB実装)→§5.6(実行・根本原因特定)
- **次チャット(CHAT94)**: ★案X実装（SP初期化追加）→ TB再実行 → ALL PASS 目標★

---

## 0. 工程位置

- Step 8 / FPGA V5(YSD8002タイマー) / **S8（統合TB）後半**
- §5.4 ✅完了 / §5.5(TB実装) ✅完了 / §5.6(実行) 実施→**3 FAIL・根本原因特定済**
- **残: 案X(SP初期化)を入れて再実行 → ALL PASS 確認**

---

## 1. 本チャットの確定成果

### 1.1 §5.4 t2_ack.asm 4要件実確認 ✅完了
- **4要件すべて充足**（HANDOVER92 §3の「PoCに欠落の可能性」懸念は外れ、良質な骨格だった）
  - 要件1 ベクタ: L51-52 `.org $0002 / .word TIMER_ISR`（IRQ0）
  - 要件2 主ループ: L79-95 二重ループ(外200×内1000)
  - 要件3 ハンドラ: L103-120（ACK $0023 ＋ CNT++ ＋ IRET）
  - 要件4 HALT: L97-100 正常HALT
- **`#$TCR_ACK` 構文疑念を解消**: hasm23 v1.04 L286-297 の `#$LABEL` 正規構文。TCR_ACK→$0023 に正しく解決。実アセンブル成功を実証。
- **emu23 v1.10 で発火実証（黄金ref・実測駆動）**:
  - **ACKあり(t2_ack): CNT=30 / OUTC=200 / 正常HALT(PC=014D)**
  - **ACKなし(v5t_noack): CNT=1 / HALT** ← ACK 2命令削除の対照実験
  - → ★差分がACKであること＝周期発火の原因がTCR-ACK再武装であることを機械的に立証★

### 1.2 §5.5 統合TB実装 ✅完了
- **成果物: `tb_cpu_v5timer_poc.sv` v0.1**（md5: 2e0785accb46165cbeaf980c4f434e74）
- 構成: CPU + v5_membus を個別インスタンス、`irq_in = irq_timer_o?3'd1:(irq1_o?3'd2:3'd0)` をTB内assign（v5_membus L25-26の指示どおり。membusはCPU非内包）
- 初期化順序はV4-TB実績を逐語踏襲: **(1)rst保持 (2)mem[0..0x1FF]クリア(KY52) (3)$readmemh (4)rst解除**
- T0〜T6実装（T0=ネガティブラン先行KY54）
- テストプログラム2本をhex化: `v5timer/v5t_ack.hex`(372B) / `v5timer/v5t_noack.hex`(364B)

### 1.3 §5.6 実行結果: 3 FAIL・根本原因特定 ✅
- 実行結果: **5 PASS / 3 FAIL**
  - PASS: T0, T1, T3, T5_halt, T6
  - **FAIL: T2(OUTC=0期待200), T4(CNT=1期待≥2), T5_outc(OUTC=0期待200)**
- 観測: **CNT=1, OUTC=0, HALT到達がPC=0002**（正常はPC=014D）。cyc=40287≈初回発火周期。

---

## 2. ★根本原因（特定済・CHAT94はここから）★

### 2.1 原因: reset時SP初期値の不一致
- **CPU-RTL(ysd8800_regfile_v0_1.sv L92): `reg_sp <= 16'h0000;`** ← reset時 SP=$0000
- **emu23 は SP=$fc7e で初期化**（ログ `SP=fc7e`）
- **t2_ack.asm 自身は SP初期化命令を持たない**（DIから始まりSP設定なし）
- → RTLでは SP=$0000 のまま割込受理 → PC/FLAGS push が $0000近傍/ラップ領域を破壊
  → IRET復帰PCが壊れ **PC=$0002(=IRQ0ベクタ番地) で停止**、主ループに戻れず OUTC=0

### 2.2 なぜemu23で正常・RTLで異常だったか
- emu23がエミュレータの便宜で SP=$fc7e を初期化していたため、SP未設定のPoCでも動いていた。
- **t2_ack.asm は「SP初期化済み環境(emu23)専用のPoC」**であり、FPGA-TBにそのまま流用するには先頭のSP設定が欠落。
- → これがKY61「丸ごと流用の危険」の実体だった。

### 2.3 対処方針: 案X（ユーザ承認済）
- **テストプログラム先頭に SP初期化命令を追加する**（案X採用）。
- 理由(MC6809/OS-9系の作法): **reset後のSP設定はソフトウェア(起動コード)の責務**。CPUがSPを特定値に初期化しないのは設計として妥当。CPU-RTLは無改修方針を守る。
- ※案Y(CPU-RTLのreg_sp初期値変更)は不採用＝無改修方針・設計思想に反する。

---

## 3. ★CHAT94の最初の一手★

1. **kernel_v12_8.asm の実SP設定値を確認**（起動コードが設定するSP値。これに合わせる）
   ```bash
   cd /home/claude/w && grep -nE "LDW +SP|SP,|#\$[Ff][Cc]" /mnt/project/kernel_v12_8.asm | head
   ```
2. **TB用プログラム(v5t_ack.asm=t2_ack.asm由来 と v5t_noack.asm)の START直後に SP初期化を追加**
   - 例: `START: DI` の直後に `LDW SP, #$FC7E`（実SP値はkernel確認後に確定）
   - ★KY38: 本番編集禁止。作業コピーで `_poc`相当に修正★
   - ★注意: t2_ack.asm は元PoC。TB専用の派生 v5t_ack.asm を作ってSP追加する（原本t2_ackは触らない）★
3. **再アセンブル(hasm23 v1.04)→ emu23で回帰(CNT=30維持確認)→ bin2hex → TB再実行**
4. **期待: T2/T4/T5_outc がPASSし ALL PASS(8チェック)**

---

## 4. ★重要申し送り: KY60再発（成果物反映漏れ）★

- **CHAT92でmmio_stubのYSD8002差替(v0_1→v0_2_poc)を実施したが、プロジェクトナレッジに未反映だった**
  - `/mnt/project/ysd8800_mmio_stub_v0_5_poc.sv` は差替前(md5:3058ffbb=旧v0_1参照)のままだった
  - HANDOVER92記載の差替済md5(b4f9dce7)と不一致
- **CHAT93で作業コピーに差替を再適用**（L311/L20を v0_2_poc に。ビルド成功でポート互換も実証）
  - **出力: `ysd8800_mmio_stub_v0_5_poc.sv`（md5: f731abe2a1bfd231ee4ccfa81d5c4bca）差替済版**
- **★CHAT94/ユーザ対応: この差替済mmio_stubをプロジェクトナレッジに再登録すること。でないとまた旧版参照でビルド不能★**
- **教訓(PDCA-A)**: 開始時に KY60「差替が生きているかgrep」を実行すべきだった。怠ったためビルドで発覚。CHAT94開始時は必ず `grep ysd8002_v0_ mmio_stub` を実行。

---

## 5. 本日の成果物（/mnt/user-data/outputs/）

- `tb_cpu_v5timer_poc.sv`（統合TB本体 v0.1・md5:2e0785ac）
- `v5t_noack.asm`（T6用ACK削除版 v0.1・md5:087de561）
- `ysd8800_mmio_stub_v0_5_poc.sv`（YSD8002差替再適用版・md5:f731abe2）★要ナレッジ再登録★
- `v5timer/v5t_ack.hex`（372B）/ `v5timer/v5t_noack.hex`（364B）

※ v5t_ack.asm は本チャットでは t2_ack.asm をそのまま流用（未改変）。CHAT94でSP追加した派生を作る。

---

## 6. 使用ツール・版数（本チャット時点）

- CPU RTL: **ysd8800_cpu_v0_1_FIXED.sv v0.5.8**（pending保護入り・無改修）
  - ★reset時 reg_sp=$0000（regfile L92）を今回確認。案Xの根拠★
- YSD8002: **ysd8800_ysd8002_v0_2_poc.sv**（irq_timer_o レベル化版）
- membus: ysd8800_v5_membus_v0_1_poc.sv / mmio_stub: 差替再適用版
- hasm23 v1.04 / emu23 v1.10 / iverilog 12.0 / bin2hex.py v1.0
- scc23 v2.03（FPGA優先で保留）

---

## 7. KY申し送り

- **KY61(本日)**: 「t2_ack.asm丸ごと流用の誘惑」→ 4要件は満たしたが**SP初期化欠落**という別の落とし穴。emu23で動く=FPGAで動く ではない。**PoCはエミュ前提の暗黙初期化に依存しうる**。防止策: 流用時はSP等の初期化前提を必ず確認。
- **KY60再発(申し送り)**: 差替成果のナレッジ反映漏れ。CHAT94開始時 `grep ysd8002_v0_ mmio_stub` 必須。
- CHAT94想定KY候補: SP初期化命令を入れる位置（レジスタ退避との順序）。DI直後・主処理前に1回だけ通す位置に置く（ハンドラ内でなく起動シーケンス）。

---

## 8. 設計負債（V5完了後の独立工程・継続申し送り）

- v0.2_poc L178 `fire_en = timer_en_r | irq_en_r;`（OR。IRQ_EN が名前どおり機能しない）→ OR→AND 抜本改修はV5完了後
- v0.2_poc/v5_membus/mmio_stub のコメント「1クロックパルス」残存 → S10文書改版で是正予定
- CPU-RTL reg_sp=$0000 は設計として妥当（MC6809系作法）。変更しない。
