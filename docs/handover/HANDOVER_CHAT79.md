# HANDOVER_CHAT79.md  (2026-07-11発行)
## 次チャット引継ぎ: V2完了・サイクル表v1.0完了 → V3(周辺機器統合)着手前

発行元: FPGA実装チャット（V2-e実装〜V2完了〜サイクル表v1.0作成）
宛先  : 次工程チャット（V3着手 or 持ち越しPDCA-Act処理）
前提原則: 原則43 / KY34(実ファイルが真実) / KY38(_poc別名) / KY39(使用前存在確認) / KY41

---

## 0. 一行サマリ

**V2（CPUコア単体検証）完了**（V2-e ALL PASS 82ベクタ・レビュー不要判断済）。
**サイクルカウントテーブル v1.0**（理想メモリ前提・全33項目）作成完了。
次は V3（周辺機器統合）着手、または累積した持ち越しPDCA-Actの処理。

---

## 1. 現在地（工程）

```
🔧 Step 8 FPGA
   ├ ✅ V(-1)/V0/V1  完了
   ├ ✅ V2 CPUコア単体検証  完了 🎉
   │   ├ ✅ V2-a(C1) 20 / V2-b(C2/C3) 41 / V2-c(C4/C5) 64
   │   ├ ✅ V2-d(C6/C7) 75  ALL PASS
   │   └ ✅ V2-e(C8制御割込) 82 ALL PASS ← 本チャット完了
   │        (EI/DI/IRET/SYSCALL/割込受理・レビュー不要判断済)
   ├ ✅ サイクルカウントテーブル v1.0（理想メモリ前提）← 本チャット完了
   └ ⬜ V3（周辺機器統合）以降  ← 次の主工程
⬜ 実効サイクル表（PSRAM待ち込み）: V3のPSRAM統合後に作成（本表を基準）
```

---

## 2. 本チャット成果物（outputs出力済・要プロジェクトナレッジ登録）

| ファイル | 内容 | 状態 |
|---|---|---|
| gen_v2_vectors_v2e_poc.py | V2-e生成器(C8エンコーダ+IRQベクタ$0008配置) | _poc(KY38) |
| tb_cpu_v2e_v0_1.sv | V2-e検証TB(82ベクタ・SP突合ctl/irq拡張) | v0.1 |
| golden_v2e.txt / expected_v2e.hex / veclist_v2e.txt | V2-e黄金・期待値・grp | 生成物 |
| v2e_run_result.txt | ALL PASS(82)ログ | 記録 |
| ★ysd8800_cycle_count_table_v1_0.md | サイクル表v1.0(全33項目・理想メモリ) | v1.0 |
| tb_cpi_probe_poc.sv | 単一命令CPI実測ハーネス(16種) | _poc・★保管方針確定 |
| tb_cpi_probe2_poc.sv | 複合命令CPI較正ハーネス(RET/IRET/受理) | _poc・★保管方針確定 |
| cpi_raw_measured.txt | 実測rawサイクルログ | 記録 |

★CPI測定_poc 2本は「_pocのままプロジェクトナレッジ保管」がユーザー確定方針。
  V3のPSRAM統合後、実効サイクル表作成時に mem_ready を待ちモデルに差し替えて
  再利用する（ハーネス構造は流用可・変更は mem_ready 生成部の一行のみ）。
  ★登録ファイル名は現状名のまま（接頭辞付与は保留・次チャットで要否確認可）。

---

## 3. V2-e 実装の確定事項（次工程で参照）

### 3.1 C8命令エンコード（emu23_v109実照合済・KY34）
| 命令 | opcode | CPI | 挙動 |
|---|---|---|---|
| EI | 0x02 | 2 | flags\|=0x80(IE=1) |
| DI | 0x03 | 2 | flags&=~0x80 |
| IRET | 0x04 | 7 | flags=(u8)pop16; pc=pop16 |
| SYSCALL | 0x05 | 3 | irq_pending=4(その場飛ばない) |
| 割込受理 | - | 9 | push16(PC);push16(FLAGS);IE=0;PC=rd16(irq*2) |

### 3.2 R-1（決着済・RTL修正不要）
SYSCALL単独 → irq_pending=4のまま → 受理vec=**rd16($0008)**。
4→2正規化はYSD8004デバイス経由時のみ（SYSCALL単独では通らない）。
RTL(v0.5.6)はemu23実測と一致。V2-eでSYS_acceptにより黄金突合で追認済。

### 3.3 検証で確認した重要事項（KY34実走）
- LDW/LDW SP はZNフラグを更新する。EI後のF下位に直前LDWのN値が残る（正常）。
- 受理時pushするPC=SYSCALL次番地。手計算せず黄金採用（HANDOVER §6の危険回避）。
- SYS_iretで受理push-PC == IRET復帰PC の往復対称(SP完全復帰)を黄金で確認。

---

## 4. サイクル表 v1.0 の要点（次工程で参照）

- **前提**: 理想メモリ(mem_ready常時1)。★実効値はPSRAM統合後に別表。
- **出典**: RTL FSM v0.5.6 の状態遷移を実測（emu23はCPI=1固定ゆえサイクル源にせず）。
- **CPI帯域**: 2〜9。制御単発=2, SYSCALL=3, レジスタALU=4, 分岐=5,
  即値ALU/スタック=6, ワードメモリ/サブルーチン=7, ワードロード[imm]=8, 割込受理=9。
- **測定法**: NOP固有CPI=2基準の差分法。複合命令はセットアップ既知CPI差引。

---

## 5. ★持ち越しPDCA-Act（latest累積・次チャット最優先で解消推奨）

本チャットでは V2-e実装とサイクル表作成に集中したため、以下が未処理累積:

1. **設計メモ v0.x→v1.0 昇格**（KY41・4点整合）: v2b/c/d/e の4本
2. **kaizen.txt 追記候補**（累積）:
   - E-1: emu内部コメントは特定経路(YSD8004)前提のことあり、命令単独挙動と
     混同しない。断定前に実走確認(KY34)。← R-1の好例
   - LDW SPのZNフラグ更新（EI後F下位にN残存）
   - サイクル出典はRTL FSM（emu23はCPI=1固定でサイクル源にできない）
   - ★本チャット新規: _pocハーネスでもopcodeは実decoder/ISAから引く
     （記憶で書かない）。CPI測定_pocでADDI/CMP opcode誤記→異常値の反省。
     既存KY39そのものだが「実験ハーネスだから」の油断が原因。
   - grep FAIL全件確認（tail厳禁）
3. **プロジェクトナレッジ登録**: V2-b/c/d/e一式・emu23_v109・CPI測定_poc2本・サイクル表
4. **tool_version_ledger 更新**: gen_v2e/tb_v2e/CPI probe_poc/サイクル表v1.0
5. **latest へ日報記載**: 2026-07-09/10/11分（V2-d/V2-e/サイクル表）
6. **サイクル表のdocx化**（任意・プロジェクト文書は主にdocx。ユーザー要否未確認）

---

## 6. 環境再現（そのまま使える）

作業DIR /home/claude/v2e/ は揮発。再現:
```
apt-get install -y iverilog                    # Icarus Verilog 12.0
# /mnt/project/ から: ysd8800_{decoder,regfile,alu,cpu}_v0_1.sv, emu23_v109.c
gcc -O2 -o emu23 emu23_v109.c                  # 黄金
# コンパイル順厳守: decoder→regfile→alu→cpu→tb
iverilog -g2012 -o sim <上記4本> <tb>
timeout 90 vvp sim > run.txt                   # KY29 timeout必須
grep -c FAIL run.txt                           # 規律5 全件確認(tail厳禁)
```
★V2-e/CPI測定成果物はプロジェクト未登録の可能性大。冒頭でls確認し、
  無ければ本HANDOVER添付/前チャットoutputsから入手すること。

---

## 7. ツール版数（2026-07-11時点・変更なし）

Force v1.5 / hasm23 v1.04 / lnk23 v2.01 / emu23 v1.09 / scc23 v2.03
kernel_forth v0.10.18 / ysd8800_cpu RTL FSM v0.5.6 / Icarus Verilog 12.0

---

## 8. 次チャット再開手順

1. 作業開始プロトコル（claude_tool_operation_guide確認 / 工程確認
   「次工程の確認ヨシ!」/ kaizen確認 / KY活動 /「ご安全に！」）
2. 本HANDOVER §5の持ち越しPDCA-Act処理か、V3着手か、ユーザー指示を待つ
3. V3着手の場合: fpga_impl_roadmap_v1_0.docx でV3スコープ（周辺機器統合:
   UART/タイマ/ストレージのRTL化）を確認してから設計メモ→レビュー→実装

---

（本HANDOVERはユーザー明示指示「引継ぎせよ」により発行。次チャットは
  本文書の確認→ロードマップ確認→KY活動→「ご安全に！」で着手する）
