# HANDOVER_CHAT100.md

**作成日**: 2026-07-18
**前チャット**: CHAT100（本チャット。ログ長大化・ツール呼び出し不安定化のため新チャットへ移行）
**次チャット**: CHAT101（V5残作業を実施）

---

## 0. 最優先: セッション開始時にやること

1. 本文書を読む
2. **成果物のナレッジ登録確認**: 下記§2の成果物9件のmd5を `/mnt/project/` で実測照合（KY34）。
   - ★重要★ 前チャットで「スナップショット未反映」問題が再発した。`/mnt/project/` はセッション開始時スナップショットのため、登録が本セッション開始後だと旧版が見える。**旧版が見えても登録失敗とは限らない**。判断に迷ったらユーザにアップロードを依頼し `/mnt/user-data/uploads/` で照合する。
3. 工程確認 → 「工程ヨシ！」
4. KY活動1件
5. claude_tool_operation_guide_v1_0.txt 参照（規律1〜5）
6. 「ご安全に！」の合図で作業開始

---

## 1. 工程位置

**Step 8 / FPGA V5（YSD8002タイマー）**

- V(-1)〜V4: ✅完了
- V5 S1〜S7 + S4デグレ絶対ゲート: ✅完了（〜CHAT99）
- **V5 S5「poc昇格＋版数台帳更新」: ✅完了（本チャットCHAT100）** ← New
- **V5残作業（次チャットCHAT101で実施）**: v5_design_memo内部系列 **S8/S9/S10**
  - S8: full版統合TB（`tb_cpu_v5timer.sv`）の完走確認（noack対照含む完全PASS）
  - S9: 全回帰（V1系＋V2e 82ベクタ + V5）
  - S10: v5_design_memo最終版への文書改版

---

## 2. 本チャットの成果物（要ナレッジ登録・md5実測値）

| ファイル | md5 | 種別 | 状態 |
| --- | --- | --- | --- |
| `ysd8800_ysd8002_v0_2.sv` | `f3aa717023d6fd488ad847c8eccc2872` | タイマーRTL本体（正式版） | 昇格済 |
| `ysd8800_mmio_stub_v0_5.sv` | `9c8cd6e93fa84fd7f2a12f6c9b0bfe94` | MMIOスタブ是正版（正式版） | 昇格済 |
| `ysd8800_v5_membus_v0_1.sv` | `aec1839c115026a9c7839a4c93166f80` | メモリ統合ラッパー（正式版） | 昇格済 |
| `tb_cpu_v5timer.sv` | `4f41148cacba65aa38491da6f003ad16` | 統合TB full版（正式版） | 昇格済 |
| `tb_cpu_v5timer_short.sv` | `d4c743d52b848946f91e78c48a8ce8e1` | 統合TB 短縮版（正式版） | 昇格済 |
| `v5t_ack_short.hex` | `12d86038856aedb2c6ed79e3a0f8c322` | テストベクタ | 変更なし |
| `v5t_noack_short.hex` | `be2ddc6c3b1bf69f8eb7b34b4483054c` | テストベクタ | 変更なし |
| `fpga_source_version_ledger_v1_5.md` | `7ba55c37b40c6461d49a49d6cf4522fb` | FPGA版数台帳（v1.4→v1.5） | 改版済 |
| `tool_version_ledger_v1_11.md` | `36ca5988ffc57ddf11824db4bcc549be` | ツール版数台帳（v1.10→v1.11） | 改版済 |

★登録時の注意: RTL/TB 5本は昇格編集で新md5。hex 2本は元と同一（再登録不要）。台帳2本は新規版数。

---

## 3. 本チャットで完了した作業の詳細

### 3.1 S5 poc→正式版昇格（原則43承認済 2026-07-18）
- 7ファイルを poc→正式版へ昇格。モジュール名を4段連鎖変更（ysd8002→mmio_stub→v5_membus→TB）。
- **iverilog 12.0 統合ビルド rc=0・error/warning ゼロ**でモジュール名整合を実証。
- **short版TB ack側 T0〜T5 ALL PASS**（HALT cyc=2903717, CNT=72, OUTC=200）。
  - T0=ネガティブラン健全性/T1=IRQ到達/T2=IRET復帰/T3=レベルストーム無し/T4=周期再武装/T5=正常HALT
- ★昇格条件★: 「OR実装のまま昇格・TCR EN是正はV6以降」を各RTLヘッダに明記。

### 3.2 fpga_source_version_ledger v1.4→v1.5
- §13「V5 YSD8002タイマー」新設。改版履歴・対象範囲・md5転記。
- 途中で v1.4改版履歴行を一時欠落させたが検出・復元済（教訓は§5）。

### 3.3 tool_version_ledger v1.10→v1.11
- **emu23 v1.09→v1.10 の登録漏れを是正**（V5のS1で改修済だったが台帳反映漏れ）。
- §1現行=v1.10、§2系譜にv1.10追記（v1.09保持）。
- emu23 v1.10 = TCR-ACK方式（IRETフック廃止・TCRマスク0x17→0x37・bit5 IRQ_ACK・kaizen原則73）。

---

## 4. 常駐管理項目（失念厳禁）

### 4.1 ★設計負債: TCR EN=OR（V6以降で是正）★
- `fire_en = |tcr_r[1:0]`（OR）実装のため IRQ_EN(bit1) が名前どおり機能せず、TIMER_EN(bit0)のみで発火。
- **是正（OR→AND）は V6以降の独立工程**（ユーザ承認 2026-07-14/17）。
- 据置根拠: 「タイマー回すが割込マスク」を要するYUI OS実装の近接予定なし（確認済 2026-07-17）。
- 各RTLヘッダ・fpga台帳§13.5に明記済。

### 4.2 その他常駐項目
- scc23 Phase 1〜6実装（FPGA優先で意図的保留・Step 8完了後着手）
- Ph.7（FAT12移行）・Ph.8（MMU連携・Level 2移行トリガー）

---

## 5. 本チャットの教訓（PDCA-A）

1. **同一セッションなら手元実体(`/home/claude/w/`・`/mnt/user-data/outputs/`)が最も確かな真実**。ナレッジ登録の有無に依存せず台帳作成・作業続行が可能。「登録済みか」をユーザに問う前に自分で実体照合すること（KY34の徹底）。
2. **改版履歴への追記は「既存行を残し末尾に新行を挿入」方式**。str_replaceのold_strに既存履歴行を含めると置換=削除になる（v1.4欠落インシデントの原因）。Pythonで「対象行の後に挿入」が安全。
3. **検証スクリプトのgrep正規表現は単純に**。複雑なパターンは誤警報（v1.4誤欠落判定）を生み確認往復でトークン浪費。
4. **ログ長大化でツール呼び出しが書式崩れ**（本チャット終盤で3回発生）。長時間セッションは早めに区切る。次チャットは残作業が少ないので問題ないはず。

---

## 6. 参照すべき主要ファイル（次チャット）

- `v5_design_memo_v0_3.md`（V5設計・内部工程S1〜S10）
- `fpga_source_version_ledger_v1_5.md`（本チャット成果）
- `tool_version_ledger_v1_11.md`（本チャット成果）
- `emu23_v110.c`（黄金リファレンス v1.10・TCR-ACK方式）
- `kernel_v12_8.asm` / `startup_harness23_v16.asm`（IRQ0ハンドラ・ACK先行で契約充足済）
- `kaizen.txt`（原則73=エミュ実装都合を仕様と誤認するな 等）

---

## 7. ビルド手順メモ（次チャット再現用）

```
# iverilog 12.0 必要（apt-get install -y iverilog）
# 統合ビルド（short版TB）:
iverilog -g2012 -o sim.vvp \
  ysd8800_decoder_v0_1.sv ysd8800_regfile_v0_1.sv ysd8800_alu_v0_1.sv \
  ysd8800_addr_decoder_v0_1.sv ysd8800_ysd8001_v0_1.sv ysd8800_ysd8002_v0_2.sv \
  ysd8800_ysd8004_v0_1.sv ysd8800_mmu_v0_1.sv ysd8800_psram_ctrl_v0_2.sv \
  ysd8800_cdc_bridge_v0_2.sv ysd8800_mmio_stub_v0_5.sv ysd8800_v5_membus_v0_1.sv \
  ysd8800_cpu_v0_1_FIXED.sv tb_cpu_v5timer_short.sv
# hexはサブディレクトリv5timer/に配置（TBが v5timer/v5t_ack_short.hex を参照）
mkdir -p v5timer && cp v5t_*_short.hex v5timer/
# 実行（timeout付き必須。full版TBはwatchdog 200msで実時間長い）:
timeout 180 vvp sim.vvp
```

★注意: emu23のcycleはCPI=1固定でFPGAとcycle一致は定義上不可。リグレッションゲートは「完走＋論理結果(出力・MD5)一致」のみ。

---

以上。次チャットはV5 S8/S9/S10（残り少）を実施し、完了後 V6（TCR EN是正含む）へ。
