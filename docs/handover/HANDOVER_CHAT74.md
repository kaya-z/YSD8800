# HANDOVER_CHAT74.md  v1.0  (2026-07-07)
## 引き継ぎ文書：V1 CPUコア完了 → V2 CPUコア単体検証 着手

- 発行元チャット: 「FPGA実装の継続」(第5-3段(b)(c)実施, 2026-07-06〜07)
- 宛先: V2 CPUコア単体検証 新チャット
- 対象ソース: ysd8800_cpu_v0_1.sv **v0.5.6** (FPGA V1 CPUコア)
- 黄金リファレンス: emu23 **v1.09** (emu23_v109.c)
- 関連台帳: tool_version_ledger_v1_10.md

---

## 0. これは何か / 最初に読むこと

V1 CPUコア(FSM命令実行)の実装が **全段完了** した。次工程は **V2: CPUコア単体検証**
＝全命令をemu23黄金と外部観測等価で突合する工程。本書はV2チャットが即着手できる
よう、現状・環境・検証方式・全命令・教訓を集約したもの。

**セッション開始プロトコル(必須)**:
1. claude_tool_operation_guide_v1_0.txt を1回参照(規律1〜5)
2. 「進捗と予定の確認(latest)」の最新ロードマップで工程確認 → 「工程ヨシ！」
   ※ 4b67e76b が latest。4月の古チャット/7-01〜7-04のRTL途中版と混同しないこと
   ※ V1完了・v0.5.6・第5段完了が反映済であることを確認済(2026-07-06 14:41更新)
3. KY活動を1つ挙げる
4. 作業開始の合図(「ご安全に！」)を待つ

---

## 1. 現状サマリ (V1完了)

### 1.1 実装済みRTL (作業DIR /home/claude/v1_rtl/ ※セッションでリセットされる)
| ファイル | 版 | 内容 |
|---|---|---|
| ysd8800_cpu_v0_1.sv | v0.5.6 | トップFSM(命令実行全段) |
| ysd8800_decoder_v0_1.sv | v0.1 | 命令デコーダ(idec/instr_len/ie_set等) |
| ysd8800_regfile_v0_1.sv | v0.1 | レジスタファイル(A/B/X/SP/PC/FLAGS) |
| ysd8800_alu_v0_1.sv | v0.1 | ALU(Z/N更新, MUL無し/桁上げ無し) |

※ これらはプロジェクトナレッジ(/mnt/project/)に同名で登録済み。**cpu.svのみ v0.5.6
  がチャット内改版版**(ナレッジは登録タイミング次第。V2開始時にcpu.svはv0.5.6を正とする)。

### 1.2 実装済みTB (全8本 ALL PASS を 2026-07-07 実行確認済)
| TB | 検証内容 | 結果 |
|---|---|---|
| tb_cpu_fetch_v0_1 | フェッチ経路 | ALL PASS |
| tb_cpu_mem_v0_1 | LDW/STW/LDB/STB | ALL PASS |
| tb_cpu_memalign_v0_1 | 整列アクセス | ALL PASS |
| tb_cpu_byte_v0_1 | バイトアクセス | ALL PASS |
| tb_cpu_iret_v0_1 | IRET単体 | ALL PASS |
| tb_cpu_irq_v0_1 | 割込受理(第5-3段b) | ALL PASS |
| tb_cpu_irq_iret_v0_1 | 受理→IRET往復(第5-3段c) | ALL PASS |
| tb_cpu_align_irq_v0_1 | align例外受理 LDW/STW(第5-3段c,E-1) | ALL PASS |

補助(診断用, KY38 _poc, 本番非依存): tb_cpu_irq_diag_poc, tb_cpu_irq_iret_diag_poc

### 1.3 FSM実装済み命令段
```
第1段 レジスタALU/MOV/CMP     第2段 即値ALU/LDWI/CMPI
第3段 分岐 JMP/Bcc            第4段 メモリ LDW/STW/LDB/STB(abs/[rS]/[rD]/[X+imm])
第5-1段 EI/DI/SYSCALL/PUSH/POP 第5-2段 JSR/RET
第5-3段(a) IRET  (b)割込受理S_IRQ_ACCEPT  (c)受理→IRET往復+align例外受理
```

---

## 2. 昨日(2026-07-06)完了した作業の要点

### 2.1 第5-3段(b) 割込受理 — 真因修正 (v0.5.5→v0.5.6)
- **真因**: EI/DIのFLAGS.IE書込が IE=bit7 でなく bit15 を操作していた。
  旧 `rf_wdata_flags={1'b1, flags_lo15}`(flags_lo15=rf_flags[14:0]) は 1'b1 が
  MSB(bit15)に載り、受理判定 flags_ie=rf_flags[7] は 0 のまま → EI後もIE=0で
  割込が永久に受理されず(CPU_IRQ_TB 7FAIL)。
- **修正**: bit7のみ差替え・他15bit保持へ訂正。Icarus制約(always_comb内の定数
  ビット選択=sorry)回避のため保持ビットをassign外出し:
  `flags_ie_hi=rf_flags[15:8]`, `flags_ie_lo=rf_flags[6:0]`,
  `rf_wdata_flags={flags_ie_hi, IE, flags_ie_lo}`。旧flags_lo15は削除。
- cpu.sv L451-452(宣言), L882-888(書込式)付近。

### 2.2 第5-3段(c) 受理→IRET往復 + align例外受理 — RTL無変更・TB2本で実証
- レビュー(stage5_3c_design_review_reply_v1_0.docx)で Q1〜Q4 全承認。
- 必要パーツ(受理/IRET/align検出)は既存実装済 → (c)はTB実証が本体。
- **確定事項(レビューで実照合)**:
  - Q3: align例外でpushされるPC = **例外命令の次命令PC**(黄金=emu23が正)。
    emu23はFETCH pc++ → オペランド pc++ → rd16/wr16でirq_pending=3 & early
    return。この時点でPCは次命令を指す。TB-2実測で010F確認済。
  - C-1: align例外命令は **副作用なし**(fault-then-continue, MC6809のSWI/割込と
    同思想=次命令PC退避・命令リトライなし)。LDWでロード先不変, STWで書込なし。
  - Q4: align例外は **ワードアクセスのみ**(rd8/wr8にalign検査なし=バイトは整列扱い)。
- 往復対称性(実照合): 受理 push(PC→FLAGS)→IE=0 / IRET pop(FLAGS下位8bit→PC)。
  IE=bit7は下位8bit復元に含まれ往復整合。

---

## 3. V2 の作業定義と検証方式 (最重要)

### 3.1 V2のゴール
全命令(約45命令)について、RTL(v0.5.6)の実行結果を emu23黄金(v1.09)と
**外部観測等価**で突合し、一致を確認する。

### 3.2 検証ゲート = 外部観測等価のみ (cycle一致は除外)
- **ゲート対象**: 命令完了後の PC / A / B / X / SP / FLAGS / メモリ内容 / 出力 / MD5。
- **ゲート対象外**: cycle数。**emu23はCPI=1固定, RTLは多サイクル**のため cycle一致は
  定義上不可能(プロジェクト確立方針, ロードマップ準拠)。TBは `dbg_halt` で命令完了を
  検出し、その時点の状態を黄金と比較する構造にする。cycle不一致を機能バグと誤検出しない。

### 3.3 黄金の取得方法
- emu23_v109.c を cc でビルドし、同一プログラム(バイナリ)を実行 → 最終状態を得る。
- emu23詳細は emu23_debug_manual_v1_2.docx / emu23_interactive_mode_design_v1_2.md 参照。
- `-n N`トレース等で命令毎の状態も取得可(cycle以外の観測点)。
- レジスタ番号(emu23 get_reg_ptr): **A=0 B=1 X=2 SP=3**。4/5(PC/FLAGS)はNULL=no-op
  (RTLも同挙動を再現済=M-1確認済)。

### 3.4 命令エンコード早見(V2 TB作成用, 実照合済)
```
LDWI rD,#imm16 = 21 (rD<<4) lo hi      ; imm16はLE
MOV  rD,rS     = 20 (rD<<4|rS)
LDW  rD,[rS]   = 24 (rD<<4|rS)         ; eff_addr=rS値
STW  rS,[rD]   = 25 (rD<<4|rS)         ; ★rD=アドレス, rS=データ(役割逆転)
ADD/SUB/CMP    = 40/42/44 (rD<<4|rS)
EI=02 DI=03(要確認) HALT=01 IRET=04
```
※ 完全な命令表は ISA2_3_v231.docx を正とする。TB作成時は都度ISAで実照合(KY39)。

### 3.5 推奨アプローチ
- 命令カテゴリ別に小プログラムを書き、emu23実行結果を期待値としてRTL TBを回す。
- 既存8TBの構造(mem[]モデル, dbg_*ポート, chk16/chk8タスク)を土台に流用。
- V2完了後、各命令の状態遷移経路メモを集計して **命令サイクル数テーブルv1.0**
  (理想メモリ前提)を一括作成する(2026-07-06決定)。V2作業中に遷移経路を軽くメモ推奨。

---

## 4. 環境再現手順 (セッション毎にFSリセットされるため必須)

```bash
# 1. Icarus Verilog(毎セッション要インストール)
apt-get install -y iverilog        # 12.0-2build2

# 2. 作業DIR復元(ナレッジ /mnt/project/ から)
mkdir -p /home/claude/v1_rtl && cd /home/claude/v1_rtl
cp /mnt/project/ysd8800_decoder_v0_1.sv .
cp /mnt/project/ysd8800_regfile_v0_1.sv .
cp /mnt/project/ysd8800_alu_v0_1.sv .
cp /mnt/project/ysd8800_cpu_v0_1.sv .      # ★v0.5.6か要確認。古ければ本書§2の修正を再適用
cp /mnt/project/tb_cpu_*.sv .              # 既存TB
cp /mnt/project/emu23_v109.c .             # 黄金

# 3. ビルドは iverilog→ls確認→vvp を分離(&&チェーン禁止=KY)
iverilog -g2012 -o /tmp/sim <core4.sv> <tb.sv>
ls -la /tmp/sim                            # タイムスタンプ確認(stale回避)
timeout 60 vvp /tmp/sim > /tmp/sim.log 2>&1  # timeout十分長く(rc=124誤診回避)
grep -E "ALL PASS|FAIL" /tmp/sim.log
```
コンパイル順: decoder(idec_pkg定義)を先に指定。core4本 = decoder/regfile/alu/cpu。

---

## 5. 引き継ぐ教訓 (デバッグ層・恒久)

- **rc=124 の二義性**: 組合せループ(真のゼロ時間ハング)と、単なる長時間シム+timeout
  killの両方でrc=124になる。**timeout killはstdoutバッファを消す**ため「log空」を
  「ハング」と誤診しやすい(2026-07-06に実際に誤診→是正)。
  → rc=124観測時は、まず `$fdisplay`+`$fclose`のファイル即書き込み or シム内
    ウォッチドッグ(`#時刻;$finish`)で **実行到達を確認してから** ハング判定する。
  → 複数ケース連続TBは実行時間が延びるので timeout を十分長く(60s+)取る。
- **Icarus制約**: always_comb内の定数ビット選択(sig[15:8]等)は `sorry` 警告で
  全ビット扱いになる。**assignで外出し**して回避する(§2.1のflags_ie_hi/loが実例)。
- **iverilog && vvp 禁止**: ビルドと実行を分け、間で `ls -la` タイムスタンプ確認
  (stale binary実行で誤読するため)。
- **KY34**: ログの不在・summary・記憶でなく、実ソース/実行結果で確認する。
- コンパイル警告0を常に確認(sorryが出たら外出し漏れ)。

---

## 6. 申し送り (未処理・要対応)

### 6.1 文書改版 (作業完了後の改版ルール, 未実施)
- **fpga_v1_cpucore_design_v1_1.md** → 以下を反映して改版:
  - FLAGS: IE=bit7(§2.1の修正を設計に明記)
  - align例外 = fault-then-continue(次命令PC退避・命令リトライなし, MC6809 SWI型)
  - IRET FLAGS復元は下位8bitのみ
  ※ 改版は追記のみ(旧内容は取消線で保持=KY41), 4点整合(ファイル名/版/日付/履歴)。

### 6.2 N-2: 黄金 emu23_v109 のナレッジ登録・台帳更新 (レビュー継続課題)
- レビューはv108で論理照合(v109実体は/mnt/projectに存在し行番号一致確認済)。
- tool_version_ledger を emu23 v1.09 で更新。V2のgolden実測にv109実体を使う。

### 6.3 cpu.sv v0.5.6 のナレッジ登録
- チャット内改版版(v0.5.6)を /mnt/project/ の正とするための登録。

### 6.4 版数管理メモ
- cpu.sv は V1完成時に部品群とファイル名を揃えて一括リネーム予定(ヘッダ注記済)。
  現状はファイル名 _v0_1 維持・ヘッダ版数 v0.5.6 で管理。

---

## 7. 停滞警告 (ロードマップ確認事項)

- **scc23 Phase 1〜6** (型システム統合/プリプロセッサ/関数ポインタ/Q16.16等) が
  scc23_phase_roadmap_v1_0.md で承認済だが実装未着手。Step 8(FPGA)優先方針下の
  意図的後回しと理解。V2と並行で動かす意図があれば別チャットで着手検討。

---

## 8. 本チャットの成果物 (2026-07-06〜07)
- ysd8800_cpu_v0_1.sv (v0.5.6) — 第5-3段(b)真因修正 + (c)完了マイルストン追記
- tb_cpu_irq_iret_v0_1.sv (v0.1) — 受理→IRET往復統合TB
- tb_cpu_align_irq_v0_1.sv (v0.1) — align例外受理TB(LDW/STW, E-1)
- stage5_3c_design_memo_v0_1.md — (c)設計メモ(レビュー承認済)
- (診断) tb_cpu_irq_diag_poc.sv, tb_cpu_irq_iret_diag_poc.sv

---

## 9. 次工程 (V2) の位置づけ
```
✅ V1 CPUコア RTL実装(全命令段) ← 完了
🔧 V2 CPUコア単体検証(全命令 emu23外部観測等価)  ← 次(本引き継ぎの宛先)
⬜ 命令サイクル数テーブルv1.0(V2完了後に一括, 理想メモリ前提)
⬜ V3 メモリ・バス / V3.5 MMU / V4 UART / V5 Timer / V6 Storage /
   V7 IRQ統合 / V8 OS統合ブート / VD 実機
⬜ Ph.7 FAT12(将来) / Ph.8 MMU連携Level2(将来) ※削除禁止
```

---
(以上 HANDOVER_CHAT74.md v1.0)
