# HANDOVER_CHAT101.md

**作成日**: 2026-07-18
**前チャット**: CHAT101（本チャット。FPGA V5残作業を完了。ログ長大化のため区切り）
**次チャット**: CHAT102（emu23再点検 → ナレッジ整理 → EN是正工程の順を想定）

---

## 0. 最優先: セッション開始時にやること

1. 本文書を読む
2. **成果物のナレッジ登録確認**: 下記 §2 の成果物 md5 を `/mnt/project/` で実測照合（KY34）。
   - ★重要★ `/mnt/project/` はセッション開始時スナップショット。登録が本セッション開始後だと旧版が見える。**旧版が見えても登録失敗とは限らない**。迷ったら `/mnt/user-data/uploads/` で照合。
3. 工程確認 → 「工程ヨシ！」
4. KY活動 1 件
5. `claude_tool_operation_guide_v1_0.txt` 参照（規律1〜5）
6. 「ご安全に！」の合図で作業開始

---

## 1. 工程位置（★V5 完了・大きな節目★）

**Step 8 / FPGA V5（YSD8002 タイマー）= ★S1〜S10 全完了（2026-07-18）★**

- V(-1)〜V4: ✅完了
- **V5 S1〜S10: ✅全完了** ← 本チャット CHAT101 で S8/S9/S10 を完了
  - S8 統合TB: ✅ ALL PASS (8 checks)（★方針C確定＝下記 §3.1）
  - S9 全回帰: ✅ V2デグレ82ベクタ ALL PASS・デグレゼロ
  - S10 文書改版: ✅ `v5_design_memo_v0_4.md`（KY41 4点整合クリア）

**次工程の順序（★ユーザ確定済 2026-07-18）**:

| 順 | 工程 | 状態 | 備考 |
|---|---|---|---|
| 1 | **emu23 再点検**（FPGA不適切実装の洗い出し） | ⬜次チャット最初 | 下記 §4。SW_START/STOP 機能に着目点あり |
| 2 | **ナレッジ整理**（削除候補【A】【B】） | ⬜ | 下記 §5。実削除はユーザ操作 |
| 3 | **★EN 是正工程（V6 の前に独立工程として実施）★** | ⬜承認待ち | 下記 §3.2。TCR EN=OR→AND。設計レビュー要 |
| 4 | V6 以降（他ペリフェラル） | ⬜ | EN是正の後 |

★**工程管理チャット(latest)への反映依頼**: 「V6 の前に EN 是正工程を挿入」がユーザ判断で確定済（2026-07-18）。latest ロードマップへの反映をユーザにお願いすること。

---

## 2. 本チャットの成果物（要ナレッジ登録・md5実測値）

| ファイル | md5 | 種別 | 状態 |
| --- | --- | --- | --- |
| `v5_design_memo_v0_4.md` | `c8a362ac5986a5d0a25d324dd3db933e` | V5設計メモ（v0.3→v0.4） | 改版済・要登録 |
| `HANDOVER_CHAT101.md` | （本文書） | 引継ぎ | — |

★登録注意: `v5_design_memo_v0_4.md` は本チャットの唯一の実成果物。§9 新設で S8/S9 完了記録・方針C・PDCA-A を追加。旧 `v5_design_memo_v0_3.md` は KY41 に従い削除せず保持（ナレッジ整理【B】で判断）。

---

## 3. 本チャットの重要な決定・設計変更

### 3.1 ★設計変更：方針C＝full版統合TB凍結・short版を正式統合TBに確定★【ユーザ承認 2026-07-18】

**発端**: S8「full版統合TB `tb_cpu_v5timer.sv` の完走確認」で、full版が watchdog `MAX_CYC=4000000` 内で **HALT 未到達・T2/T5 FAIL**。

**原因（debug_style_guide 準拠の切り分け）**:
- RTL は無改修・short版で ALL PASS 実績 → RTL 論理は正常。
- `v5t_ack.hex`(full) と `v5t_ack_short.hex`(short) の差は **305-306行の1即値のみ**。
  - full = `e8 03` = `0x03E8` = **1000回ループ**（過大）
  - short = `64 00` = `0x0064` = **100回ループ**（設計正）
- TBヘッダ設計正は「emu23実測 CNT=30 / HALT到達」の軽量プログラム。full版1000回ループは vvp では約2900万cyc必要で回帰不能。
- 根本原因: `v5t_ack.hex`(full) のループ即値が過大な**残骸**（前工程で未完走のまま昇格）。

**決定（方針C）**:
- **short版 `tb_cpu_v5timer_short.sv` を S8 正式統合TBに確定。**
- **full版 `tb_cpu_v5timer.sv`・`v5t_ack.hex`・`v5t_noack.hex` は凍結。**
- short版は **T0〜T6 全項目を内包**（full版固有と誤認されていた T6=noack負テストも内包）。full版に固有価値は無かった。

**S8 実測結果（short版・再現確認済）**:
- ackラン: HALT到達 cyc=2903717 (PC=0152), CNT=72, OUTC=200
- noackラン: HALT到達 cyc=2880161 (PC=0152), CNT=1
- T0〜T6 = **V5TIMER_TB: ALL PASS (8 checks)**

### 3.2 ★EN 是正工程を V6 の前に置く（ユーザ判断確定 2026-07-18）★

**負債の本質**（`v5_design_memo` §3.5.2・実源確認済）:
- 現行 `fire_en = |tcr_r[1:0]`（OR）。`IRQ_EN`(bit1) が名称どおり機能せず、`IRQ_EN=0` でも割込が止まらない＝**デバイス契約違反**。
- 正しい姿（MC6840 PTM 系）: `TIMER_EN`（カウンタ進行）と `IRQ_EN`（割込許可）を分離、発火 = `armed && cnt==0 && TIMER_EN && IRQ_EN`（AND）。

**V6 前に独立工程として置く根拠（本チャットで判断）**:
1. V5 完了により「emu23 無改修で回帰基準（Dhrystone黄金値）を保つ」制約が解除された → 今が是正の好機。
2. AND化は V6 のストレージ割込検証と混線する → V6 着手前に片付ける方が切り分けが健全。
3. 改修規模（emu23 / YSD8002 RTL / dhry_timer.c / Dhrystone全回帰 / 文書）が大きく独立工程が適切。
4. ユーザ指示（2026-07-14）で既に「近日中に抜本改修」決定済。

**改修範囲（`v5_design_memo` §3.5.2 より）**:
| 対象 | 内容 |
|---|---|
| `emu23` | L696 `(tcr & 0x03) ? 1 : 0`（OR）→ AND。かつ **TIMER_EN=0 時のカウンタ停止概念を新設**（現行は irq_enabled 一本で兼用） |
| YSD8002 RTL | `fire_en = |tcr_r[1:0]` → `tcr_r[1] & tcr_r[0]`（または EN 分離） |
| `dhry_timer.c` | `timer_start()` の `TCR←$0004` が IRQ_EN を殺す件も同時是正 |
| 回帰 | ★**Dhrystone 黄金値 826/48405/P:20 が変わる可能性**★ 全回帰やり直し必須 |
| 文書 | `ysd8002_timer_design_v1_0.docx` → v1.1（TCR 定義を AND に是正） |

★**着手前に設計レビュー→承認（原則43）が必須。本チャットでは実装していない。位置づけ（V6前・独立工程）のみ確定。**

---

## 4. 次チャット最初の作業：emu23 v1.10 FPGA不適切実装 再点検

**目的**: 原則73「エミュ実装都合を仕様と誤認するな」の再適用。TCR-ACK 移行時に emu 内部で辻褄合わせした箇所が FPGA RTL と乖離していないか洗う。

**本チャットで事前に発見した着目点（要精査）**:
- **emu23 v1.10 の TCR write は `v & 0x37` で bit2(SW_START=0x04)・bit3(SW_STOP=0x08) のソフトウェアストップウォッチ機能を持つ**（`emu23_v110.c` L694〜付近）。SCORE / Dhrystones-sec 表示を含む。
- これは **Dhrystone 計測用の emu 固有機能**であり、**FPGA 上には存在しない（ホストシミュレータの計測支援）可能性が高い**。原則73 の典型的な注意対象。
- **要確認**: FPGA RTL（`ysd8800_ysd8002_v0_2.sv`）が SW_START/STOP/SCORE をどう扱っているか。RTL に実装が無い／別扱いなら「emu 固有機能」として文書に明記し、FPGA 契約から除外すべき。
- 併せて確認: TCRマスク 0x37 の emu/RTL 一致、IRQ_ACK(bit5) 挙動一致、iret_pulse_o 廃止の徹底（v1.10 で IRET フック削除済のはず）。

**参照ファイル**: `emu23_v110.c`（黄金ref v1.10）、`ysd8800_ysd8002_v0_2.sv`（RTL正式版）、`ysd8002_timer_design_v1_0.docx`、`kaizen.txt`（原則73）。

**ビルド再現**（本チャットで確認済・rc=0）:
```
gcc -O2 -o emu23 emu23_v110.c    # 起動時 "emu23 v1.10 (2026-07-13)" 表示
```

---

## 5. ナレッジ整理：削除候補リスト（★実削除はユーザ操作★）

現状 **204 ファイル**。KY活動の防止策により、**Claude は候補提示のみ・実削除しない**方針。依存確認（grep 参照チェック）を必ず経ること。

### 【A】削除安全性が高い（旧HANDOVER・履歴）
| ファイル | 理由 | 留意 |
|---|---|---|
| `HANDOVER_CHAT92〜98.md`（7件） | 最新 CHAT100/101 で不要 | **CHAT99 は保持**（S9回帰基準 md5 `09de967...` の出典） |
| `HANDOVER_PEEPHOLE_P1_IMPL_v1_0.md` | 上位 v2_0 が現存 | v2_0 保持 |

### 【B】削除候補だが依存確認推奨
| ファイル | 状況 | 未確認事項 |
|---|---|---|
| `ysd8800_ysd8002_v0_1.sv` | v0_2 現存。v0_2 からはコメント参照のみ | **V2 単体TBからの参照が未確認** |
| `ysd8800_mmio_stub_v0_5_poc.sv` | v0_5 正式版に昇格済 | poc 昇格元。要確認 |
| `emu23_v109.c` | v110 現存 | **tool_version_ledger で系譜保持のためソース実体を消すか要判断** |
| `tb_cpu_v5timer.sv`(full) + `v5t_ack.hex` + `v5t_noack.hex` | 本チャットで方針C凍結 | 「凍結＝記録として残す」判断も可 |
| `v5_design_memo_v0_3.md` | v0_4 現存 | KY41 の履歴保持観点。判断要 |
| 各種一時 poc（`tb_cpi_probe*_poc.sv`, `tb_cpu_irq_diag_poc.sv` 等） | 一時検証用 | 現役 poc と混在注意 |

### 【C】★削除禁止★（現役依存あり・機械削除の罠。本チャットで実証）
| ファイル | 理由 |
|---|---|
| `ysd8800_mmio_stub_v0_4.sv` | **`build_v4.sh` L40 で実ビルド対象。V4 回帰に必須** |
| `gen_v2_vectors_v2e_poc.py` | **本セッション S9 で使用。V2e 回帰の必須ツール**（poc 名だが現役） |
| `codegen_v1_4.h` | `.h`（宣言）は `.c`（実装）と別物。Force 構成ファイル |
| `build_road2/v35/v4.sh` | 各工程専用スクリプト（版数違いではない） |
| 各種旧 `_design` メモ | KY41 情報欠落防止・履歴的価値で保持推奨 |

★**教訓**: poc 名＝削除可 ではない（gen_v2e が反例）。旧版 RTL＝削除可 ではない（mmio_stub_v0_4 が反例）。**必ず `grep -l "<basename>" *.sv *.sh *.py` で実ビルド参照を確認**してから候補確定すること。

**推奨進め方**: まず【A】8件のみ確定 → ユーザ削除。【B】は1件ずつ依存確認後に判断。【C】は削除しない。

---

## 6. 常駐管理項目（失念厳禁）

- **EN 是正工程**（§3.2）: V6 の前・独立工程・設計レビュー必須。
- scc23 Phase 1〜6 実装（FPGA 優先で保留・Step 8 完了後）。
- Ph.7（FAT12 移行）・Ph.8（MMU 連携・Level 2 移行トリガー）。
- **版数台帳の追随**: `v5_design_memo` v0.4 改版に伴い `fpga_source_version_ledger` への反映要否を確認。

---

## 7. 本チャットの教訓（PDCA-A）

1. **前チャットで full版TB を「昇格済」としながら完走検証していなかった**。→ **改善: 統合TBの昇格は「完走・ALL PASS の実測」を条件とする**（kaizen 反映候補）。未完走TBを昇格させない。
2. **ナレッジ機械削除の危険**: poc 名でも現役（gen_v2e）、旧版でも現役依存（mmio_stub_v0_4 は build_v4.sh が参照）。**削除候補確定前に grep 参照チェック必須**。
3. KY41 追記は「既存行を残し末尾に新行挿入」。str_replace の old_str に既存履歴行を含めない（CHAT100 の v1.4 欠落インシデント教訓の継承）。
4. ログ長大化でツール書式崩れリスク。本チャットも長くなったため区切った。次チャットは emu23 再点検→ナレッジ整理と作業量があるので、適宜区切ること。

---

## 8. 参照すべき主要ファイル（次チャット）

- `v5_design_memo_v0_4.md`（本チャット成果・§9 に S8/S9/方針C）
- `emu23_v110.c`（黄金ref v1.10・再点検対象）
- `ysd8800_ysd8002_v0_2.sv`（RTL 正式版・再点検対象）
- `tb_cpu_v5timer_short.sv`（S8 正式統合TB）
- `fpga_source_version_ledger_v1_5.md` / `tool_version_ledger_v1_11.md`（版数台帳）
- `kaizen.txt`（原則73 ほか）
- `claude_tool_operation_guide_v1_0.txt`（規律1〜5）

---

## 9. ビルド再現メモ（次チャット用）

```
# iverilog 12.0（apt-get install -y iverilog）
# S8 short版統合TB（正式）:
mkdir -p v5timer && cp v5t_ack_short.hex v5t_noack_short.hex v5timer/
iverilog -g2012 -o sim_short.vvp \
  ysd8800_decoder_v0_1.sv ysd8800_regfile_v0_1.sv ysd8800_alu_v0_1.sv \
  ysd8800_addr_decoder_v0_1.sv ysd8800_ysd8001_v0_1.sv ysd8800_ysd8002_v0_2.sv \
  ysd8800_ysd8004_v0_1.sv ysd8800_mmu_v0_1.sv ysd8800_psram_ctrl_v0_2.sv \
  ysd8800_cdc_bridge_v0_2.sv ysd8800_mmio_stub_v0_5.sv ysd8800_v5_membus_v0_1.sv \
  ysd8800_cpu_v0_1_FIXED.sv tb_cpu_v5timer_short.sv
timeout 300 vvp sim_short.vvp     # → V5TIMER_TB: ALL PASS (8 checks)

# S9 V2e 82ベクタ回帰:
gcc -O2 -o emu23 emu23_v110.c
python3 gen_v2_vectors_v2e_poc.py    # v2e/ に82ベクタ+expected生成（要 ./emu23）
iverilog -g2012 -o sim_v2e.vvp \
  ysd8800_decoder_v0_1.sv ysd8800_regfile_v0_1.sv ysd8800_alu_v0_1.sv \
  ysd8800_cpu_v0_1_FIXED.sv tb_cpu_v2e_v0_1.sv
timeout 120 vvp sim_v2e.vvp        # → CPU_V2E_TB: ALL PASS (82 vectors)
# expected_v2e.hex md5 = 09de96788c67b1e795d38277375eafcf（CHAT99値と一致）
```

★注意: emu23 は CPI=1 固定。FPGA と cycle 一致は定義上不可。回帰ゲートは「完走＋論理結果一致」のみ。

---

以上。次チャットは emu23 再点検 → ナレッジ整理 → EN是正工程（要レビュー承認）の順で。
