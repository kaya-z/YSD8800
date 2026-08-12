# HANDOVER_CHAT94.md

- **作成日**: 2026-07-15
- **前チャット**: CHAT93（V5 S8統合TB実装→5PASS/3FAIL・SP不一致を根本原因特定）
- **本チャット(CHAT94)**: 案X(SP初期化)実装→TB再実行→**新たな根本問題(emu23とRTLの挙動不一致)に到達**
- **次チャット(CHAT95)**: ★YSD8002 v0_2_poc の再武装ロジック解析＝noack=17069 の真因特定★

---

## 0. 工程位置

- Step 8 / FPGA V5(YSD8002タイマー) / **S8（統合TB）**
- 案X(SP初期化) ✅実装・emu23回帰OK / TB再実行 ✅完走 → **4 PASS / 4 FAIL**
- **残: RTL挙動がemu23黄金refと不一致。YSD8002再武装ロジックの真因特定が必要**

---

## 1. 本チャットで【実施し確定した】こと（漏れなく）

### 1.1 KY60再発（申し送り事項）への対処 ✅完了
- **開始時 `grep ysd8002_v0_ mmio_stub` を実行**。プロジェクトナレッジの
  `/mnt/project/ysd8800_mmio_stub_v0_5_poc.sv` は**旧版参照(ysd8800_ysd8002_v0_1)のまま**（md5:3058ffbb）と実確認。
  → HANDOVER93 §4の「ナレッジ再登録漏れ」が事実だと確定。
- **作業コピーで差替を再適用**：L20コメント・L311インスタンス化を `ysd8800_ysd8002_v0_2_poc` に。
  - **出力: `ysd8800_mmio_stub_v0_5_poc.sv`（md5: 39503e11269eb1d0e06285541d7f786e）差替済版**
- **★CHAT95/ユーザ対応: この差替済mmio_stubをプロジェクトナレッジに再登録すること（未実施だと毎回ビルド不能）★**

### 1.2 案X（SP初期化追加）実装 ✅完了
- **SP初期値=$FC7E に決定**（emu23初期値一致で回帰CNT=30維持＋MMIO境界$FC80未満で安全）。
  - 根拠: addr_decoder L43 `is_mmio=(addr>=16'hFC80)`。SPは下降スタックで$FC7E以下=RAM側に留まりMMIO非接触。
  - ★$FC80以降はMMIO。yuios_memmap「$FC80-絶対RAM禁止」規約と整合★
- **挿入位置=START:のDI直後・EIより前・起動シーケンスで1回のみ（KY62）**。ハンドラ内には入れない。
- **hasm23 v1.04で `LDW SP,#imm` がISA2.3正規命令と裏取り済**（hasm23 L272でSP=reg#3。kernel L1332に実例）。
- **成果物2本（原本t2_ack.asmは不触・KY38）**:
  - `v5t_ack.asm` v0.2（md5: 5539dc4a1ce44f15842c0f473f70cd1b）… t2_ack.asm v0.1 由来＋SP初期化1命令
  - `v5t_noack.asm`（md5: 83131ff6ce0c6b2a1cf95737dfb488da）… v0.1由来＋SP初期化1命令

### 1.3 emu23回帰 ✅（SP追加後も黄金値維持を実証）
- **ack: A=001E(CNT=30) / B=00C8(OUTC=200) / 正常HALT at 0151 / SP=fc7e**（HANDOVER93 §1.1と完全一致）
- **noack: A=0001(CNT=1) / B=00C8(OUTC=200) / 正常HALT at 0151**（対照実験の論理維持）
- **emu23でのHALT到達cycle = 約120万（total_cycles=1201941）** ← TB実時間見積りの根拠
- → SP初期化を入れても emu23挙動は不変。案Xは正しい。

### 1.4 hex生成 ✅
- `v5timer/v5t_ack.hex`（376B・md5: 0cbc6fee9aa3fc670221d51723c1ceb5）
- `v5timer/v5t_noack.hex`（368B・md5: 071f961909618c7502c80f8f762e03d0）
- ※前チャットは372B/364B。SP初期化3バイト増で整合。

### 1.5 TBビルド ✅（iverilog依存関係を確定）
- **本環境にはiverilogが無く、`apt-get install -y iverilog` で 12.0 を導入**（プロジェクト指定版一致）。
- **★iverilogファイル指定順の確定（次チャット時短のため必ず踏襲）★**:
  1. `ysd8800_decoder_v0_1.sv` を**先頭**に置く（`package ysd8800_idec_pkg` を定義。cpuがimportするため先行必須）
  2. 以降: cpu_v0_1_FIXED, regfile_v0_1, alu_v0_1, v5_membus_v0_1_poc, addr_decoder_v0_1,
     mmio_stub_v0_5_poc, ysd8002_v0_2_poc, ysd8001_v0_1, **ysd8004_v0_1**, mmu_v0_1,
     cdc_bridge_v0_2, psram_ctrl_v0_2, tb_cpu_v5timer_poc
- **mmio_stubは ysd8004_v0_1 も内包**（今回不足で発覚・追加コピー）。
- 残warningは `unique case` 品質無視（ysd8001 L285 / ysd8004 L157）＝iverilog既知・無害。

### 1.6 TB実行 ✅完走（案A: timeout延長で事実確認）
- **psram_clk=#0.5(周期1ns)・cpu_clk=#10(周期20ns)** のため、120万cyc完走に**実時間 約11.5分**。
  bash_toolの時間上限のため **nohupバックグラウンド実行＋sleepポーリング**で完走させた。
- **前チャットが「早く終わっていた」理由も判明**: SP破壊でPC=0002早期停止していたため。SP正常化でフル完走が必要になり実時間増。これはバグでなくシミュ規模の話。

---

## 2. ★★本チャット最大の成果: 新たな根本問題に到達★★

### 2.1 TB結果: 4 PASS / 4 FAIL
| テスト | 結果 | got | exp | 備考 |
|---|---|---|---|---|
| T0_negative_run | PASS | - | - | TB健全性OK |
| T1_irq_reached | PASS | CNT=196 | [1..1000] | 割込到達はした |
| T2_iret_return_outc | **FAIL** | OUTC=33 | 200 | メインループが進まない |
| T3_level_no_storm | PASS | 196 | [1..1000] | 上限内(暴走判定はすり抜け) |
| T4_periodic_rearm | PASS | 196 | [2..1000] | 再武装自体はした |
| T5_halt | **FAIL** | halt=0 | 1 | ★RTLがHALTに到達しない★ |
| T5_outc_final | **FAIL** | OUTC=33 | 200 | 同上 |
| T6_noack_no_rearm | **FAIL** | CNT=**17069** | 1 | ★ACK無しでも再武装している★ |

### 2.2 症状の核心（emu23=黄金ref と RTL の不一致）
- **emu23**: ack=CNT30/OUTC200/正常HALT(120万cyc) ・ noack=CNT1/HALT
- **RTL(v0_2_poc)**: **400万cyc回してもHALTせず**（両ケースとも `HALT not reached in 4000000 cyc`）。
  ack=CNT196/OUTC33 ・ noack=**CNT17069**
- → **RTLはメインループがほぼ進まず（OUTC 200→33）、割込処理に食われ続けてHALTに永久到達しない**。
- → **noackが17069** ＝ ACK無しでも発火し続けている＝**TCR-ACK方式の中核(「ACKしない限り再武装しない」)がRTLで成立していない**。

### 2.3 真因の有力仮説（次チャットの検証対象・実源で裏取り済の材料）
YSD8002 v0_2_poc を実確認した結果:
- L227 `assign irq_timer_o = irq_req_r;`（レベル出力）… OK
- L282 `irq_req_r <= 1'b0;`（**ACK(bit5)でクリアは実装済**）… OK。「ACKで下がらない」説は**否定された**。
- **L178 `assign fire_en = timer_en_r | irq_en_r;`（★OR★・設計負債既知）**
- L200 `assign fire = armed_r & fire_en & (cycle_i >= cnt_r);`
- L258 `irq_req_r <= 1'b1;`（fire で立てる）

★**最有力仮説**: noackでACKを書かなくても、`fire`が周期条件で繰り返しtrueになり L258で irq_req_r を**再セットし続ける**。つまり「ACK再武装」以前に「fireが勝手に何度も立てる」経路が生きている。emu23は`YSD8002_rearm()`がACK(bit5)書込時のみ next_irq_cycle を進める設計なので、ACK無し=1回で止まる。**RTLの`fire`が周期的に自走する点が黄金refと構造的に食い違っている**。
- 副症状(ack側OUTC=33/HALT不達)も同根の可能性: irq_req_rが頻繁に立ち、ハンドラが頻走してメインループが進まない。

### 2.4 次チャット(CHAT95)の最初の一手
1. **`cycle_i >= cnt_r` の周期挙動を精査**: cnt_r(発火閾値)がfire後にどう更新されるか。ackなしで再度 `cycle>=cnt_r` が成立し続けないか。
   ```
   grep -nE "cnt_r|armed_r|next|rearm|cycle_i" ysd8800_ysd8002_v0_2_poc.sv
   ```
2. **emu23の YSD8002_rearm() / next_irq_cycle 更新条件（L269-272, L694-704）とRTLを一対一照合**（原則76: 黄金refの実源に対して実装せよ）。
3. **仮説確定後、v0_2_poc を _poc のまま修正**（本番昇格前なので _poc内で直す。KY38は本番編集禁止＝v0_2_pocは実験版なので可）。
4. 修正後 TB再実行（完走に約11.5分。nohup+ポーリング方式を踏襲）。

---

## 3. 本日の成果物（/mnt/user-data/outputs/）

| ファイル | md5 | 内容 |
|---|---|---|
| `HANDOVER_CHAT94.md` | (本書) | 引き継ぎ |
| `v5t_ack.asm` | 5539dc4a... | SP初期化追加版(t2_ack由来 v0.2) |
| `v5t_noack.asm` | 83131ff6... | SP初期化追加版(対照 v0.1由来) |
| `ysd8800_mmio_stub_v0_5_poc.sv` | 39503e11... | YSD8002差替再適用版 ★要ナレッジ再登録★ |
| `v5timer/v5t_ack.hex` | 0cbc6fee... | 376B |
| `v5timer/v5t_noack.hex` | 071f9619... | 368B |

※TB(`tb_cpu_v5timer_poc.sv` v0.1)・各RTLは本チャット未改変（mmio_stub除く）。

---

## 4. 使用ツール・版数（本チャット時点）

- CPU RTL: ysd8800_cpu_v0_1_FIXED.sv v0.5.8（reset時 reg_sp=$0000・無改修方針）
- YSD8002: **ysd8800_ysd8002_v0_2_poc.sv**（irq_timer_oレベル化版。_poc=最終検証未完＝本TBが最終検証）
- membus: v5_membus_v0_1_poc / mmio_stub: 差替再適用版 / ysd8004_v0_1(mmio内包)
- hasm23 v1.04 / emu23 v1.10 / **iverilog 12.0(要apt導入)** / bin2hex.py v1.0
- scc23 v2.03（FPGA優先で保留）

---

## 5. KY申し送り

- **KY62(本日)**: SP初期化命令の挿入位置ミスによる別バグ誘発。防止策=DI直後・EIより前・起動で1回のみ・ハンドラ内禁止。→ 適用し回帰値維持を実証（成功）。
- **KY60(再発・未解消の申し送り)**: mmio_stub差替のナレッジ反映漏れ。★CHAT95開始時も `grep ysd8002_v0_ mmio_stub` 必須。ユーザが差替済版を再登録するまで毎回発生★。
- **CHAT95想定KY候補**: v0_2_poc修正時、`fire`ロジック変更が「ack側の正常動作(CNT30相当)」を壊さないか。修正は必ずemu23黄金値(ack=30/noack=1)との一致で検証（原則76）。

---

## 6. 設計負債（継続申し送り）

- **★v0.2_poc L178 `fire_en = timer_en_r | irq_en_r`（OR）★** … 本チャットのTB-FAILの真因候補に浮上。CHAT95で解析。IRQ_ENが名前どおり機能しない件と同根の可能性。
- v0_2_poc/v5_membus/mmio_stub のコメント「1クロックパルス」残存（実際はレベル）→ S10文書改版で是正。
- CPU-RTL reg_sp=$0000 は設計として妥当（MC6809系作法）。変更しない。

---

## 7. ★HANDOVER品質についての自戒（ユーザ指摘 2026-07-15）★

- 最近のHANDOVERは記載不足で「前チャットの再実行」「ナレッジ有無の誤認」でトークンを浪費していた。
- **本書は対策として**: ①やった事を漏れなく列挙(§1)、②実確認したmd5/行番号を明記、③次チャットの最初の一手を具体コマンド付きで記載、④ナレッジ再登録の要否を明示、を徹底した。
- CHAT95以降もこの粒度を維持すること。
