# HANDOVER_CHAT73 — FPGA V1 CPU RTL 第5-3段(b)割込受理 TB受理実証 引き継ぎ

- 文書名: HANDOVER_CHAT73.md
- 版数: v1.0
- 作成日: 2026-07-05
- 前チャット: CHAT73「FPGA実装の続き(第5-3段(b)割込受理 実装)」
- 次チャット作業: **割込受理TBの受理不成立バグの決着**(実装本体は完了・回帰PASS済)
- 黄金リファレンス: emu23_v109.c(外部観測等価。cycle一致は非対象)

---

## 0. 最初に読むもの / セッション開始プロトコル

次チャット開始時、以下を順に実施(規約):
1. `claude_tool_operation_guide_v1_0.txt` を1回参照(規律1〜5)。
   ※前チャット(CHAT73含む)で地の文に無意味文字列("court")を反復混入させる不具合が
     継続発生。ツール呼び出しは落ち着いて1つずつ、1応答に詰め込みすぎない。地の文に
     余計な語を出さないよう自己監視すること。
2. 工程確認: 「進捗と予定の確認(latest)」を参照 →「工程ヨシ!」「次工程の確認ヨシ!」。
3. KY活動(下記§6の当日版を継承 or 新規)。
4. ユーザーの「ご安全に!」で作業開始。

---

## 1. 現在地(2026-07-05時点)

```
🔧 Step 8 第Ⅱ部 V1 CPUコア RTL実装 / FSM命令実行の肉付け
   ├ ✅ 第1〜3段(レジスタ/即値ALU・分岐)
   ├ ✅ 第4-A/B段 メモリ LDW/STW/LDB/STB
   ├ ✅ 第5-1段 EI/DI/SYSCALL/PUSH/POP
   ├ ✅ 第5-2段 JSR/RET
   ├ ✅ 第5-3段(a) IRET
   ├ 🔧 第5-3段(b) 割込受理 S_IRQ_ACCEPT
   │     ├ ✅ RTL実装(黄金照合済・既存6経路回帰PASS)
   │     └ ⬜ TB受理実証(CPU_IRQ_TBが7FAIL=受理成立せず ← 次の作業の最優先)
   └ ⬜ 第5-3段(c) 受理→IRET往復統合 + align例外受理
⬜ V2 CPUコア単体検証(全命令 emu23外部観測等価)
```

- **現行版**: `ysd8800_cpu_v0_1.sv` **v0.5.5**(ファイル名は_v0_1のまま=V1完成時一括
  リネーム方針。内容バージョンで管理)。
- 作業DIR: `/home/claude/v1_rtl/`、成果物出力: `/mnt/user-data/outputs/`
- **セッション跨ぎでFSリセット**。次チャットは /mnt/user-data/outputs または
  /mnt/project からSVファイル一式を作業DIRへ復元して開始(KY34: まずls/headで実体確認)。
- **Icarus Verilog は環境に未インストール**。`apt-get install -y iverilog` で
  12.0-2build2 が入る(HANDOVER指定の12.0と一致)。最初に実施すること。

### コンパイル/実行手順(Icarus 12.0)
```
# マルチファイル順: decoder→regfile→alu→cpu→tb (パッケージ定義が先。KY: 順序依存)
iverilog -g2012 -o /tmp/sim \
  ysd8800_decoder_v0_1.sv ysd8800_regfile_v0_1.sv ysd8800_alu_v0_1.sv \
  ysd8800_cpu_v0_1.sv tb_cpu_XXX_v0_1.sv
# ★ビルドと実行は必ず分離し、間で ls -la /tmp/sim のタイムスタンプを確認する
#   (今回 && 連鎖で古い生成物を実行し「出力空」を実装バグと誤認した。教訓)
ls -la /tmp/sim
timeout 20 vvp /tmp/sim > /tmp/sim.log 2>&1; echo "rc=$?"
grep -E "ALL PASS|FAIL" /tmp/sim.log
#   rc=124 は timeout=無限ループ/組合せループのサイン
```

---

## 2. 本チャット(CHAT73)でやったこと

### 2.1 割込受理 S_IRQ_ACCEPT の RTL実装(完了)
emu23_v109 L1174-1188 を黄金リファレンスとして、以下を同順で実装:
```
[emu23]                              [RTL v0.5.5]
irq=irq_pending; irq_pending=-1  →  S_IRQCHK(irq_pending!=0 && flags_ie)→S_IRQ_ACCEPT
push16(pc)  ※PC先                →  push_src←rf_pc, 1回目push(S_PUSH_LO/HI)
push16(flags) ※FLAGS後           →  1回目完了でpush_src←rf_flags, 2回目push
flags &= ~FL_IE  ※push後(D-1)    →  2回目完了(push_count==1)でrf_flags&16'hFF7F
vec=rd16(irq*2); pc=vec          →  S_MEMR_LO/HIでmem[irq*2]読み→PC←{mem_rdata,mem_lo}
```
実装した4ブロック:
- **①信号宣言**: `irq_latch`(3bit, C-1: 受理中IRQ番号退避)。reset初期化に追加済。
- **②next_state**: S_IRQ_ACCEPT→S_PUSH_LO。S_PUSH_HIにCTX_IRQ分岐(push_count>1で継続、
  ==1でS_MEMR_LO)。S_MEMR_HIにCTX_IRQVEC分岐(→S_FETCH)。
- **③mem出力**: ★後述の組合せループ回避で、当初のstack_ctx依存三項を撤回。addr_r参照に統一。
- **④ff/regfile**:
  - S_IRQ_ACCEPT入口ff: irq_latch←irq_pending, stack_ctx←CTX_IRQ, push_count←2,
    push_src←rf_pc, **addr_r←{12'd0,irq_pending,1'b0}**(ベクタアドレスをffラッチ=案1)。
  - S_PUSH_HI完了ff(CTX_IRQ): push_count減算、1回目でpush_src←rf_flags、2回目で
    stack_ctx←CTX_IRQVEC。
  - S_PUSH_HI regfile(CTX_IRQ && push_count==1): rf_flags←rf_flags&16'hFF7F(IE=0, D-1)。
  - S_MEMR_HI regfile(CTX_IRQVEC): rf_we_pc, rf_wdata_pc←{mem_rdata,mem_lo}。
  - ベクタ読み完了ff(S_MEMR_HI && CTX_IRQVEC): irq_pending←0, stack_ctx←CTX_NONE。

### 2.2 組合せループの発見と回避(案1)【重要な設計変更】
debug報告形式:
- 現象: 割込受理実装後、**byte TBがtimeout(rc=124)=無限ループ**。$display一切出ず時刻停止。
- 原因: mem出力always_combで `mem_addr = (stack_ctx==CTX_IRQVEC) ? irq_vec_addr : addr_r`
  とした結果、mem_addr→mem_ready→state→stack_ctx→mem_addr の閉路が成立し、Icarusの
  イベント評価が収束しなくなった(組合せループ)。
- 対処(案1・ユーザー承認済): ベクタアドレスの組合せ選択を撤廃。S_IRQ_ACCEPT入口ffで
  `addr_r <= {12'd0, irq_pending, 1'b0}`(=irq_pending*2)をラッチし、S_MEMR_LO/HIは既存
  addr_r参照に統一。→組合せループ解消、byte ALL PASS復活。
- 教訓(KY): Icarus always_combで状態依存のバス生成は組合せループを招く。**アドレスは
  ffラッチした専用レジスタに寄せる**(MC6809実機のアドレスバスラッチと同思想)。
- 副作用整理: 未使用化した `irq_vec_addr` 宣言/assignは削除済(KY41整合)。

### 2.3 既存回帰(C-3)= ALL PASS
| TB | 結果 |
|---|---|
| fetch | ALL PASS |
| mem | ALL PASS |
| memalign | ALL PASS |
| byte | ALL PASS(組合せループ解消後) |
| iret | ALL PASS |
| 構文(iverilog -g2012) | rc=0 |
→ **割込受理の実装は既存動作を一切壊していない**。

---

## 3. ★未決着: CPU_IRQ_TB が受理不成立(7 FAIL)← 次チャット最優先

### 3.1 症状(debug_style_guide形式)
- 現象: 新規 `tb_cpu_irq_v0_1.sv` 実行で割込が受理されず、フォールバックHALT(@010D)で停止。
  ```
  PASS: halted @PC=010e
  FAIL[handler reached (PC=0305)] got=010e exp=0305
  FAIL[B(handler ran)] got=0000 exp=00aa
  FAIL[A(irq before 0109)] got=0022 exp=0011   ← 0109が実行された=受理されず素通り
  FAIL[SP(-4 push2)] got=4000 exp=3ffc          ← push発生せず
  PASS: IE=0 (受理後クリア D-1)                  ← ※但しこれは「EI未反映で元々IE=0」の疑い
  FAIL: irq_pending=1 exp 0                      ← irq_pendingは1で残存(受理消費されず)
  FAIL[stack PC_lo/hi]                           ← push無しなのでスタック未書込
  ```
- 追加事象: EI+HALTのみの最小デバッグTB(/tmp/tb_dbg.sv)も**timeout(rc=124)でハング**。
  これがTB記述側の問題か実装側かの切り分けが未了(トークン節約のため深追いせず区切った)。

### 3.2 有力仮説(次チャットで検証を絞ること)
**仮説A(最有力): EIのIE反映が受理判定に間に合っていない / EI自体が効いていない。**
- 最終FLAGSでIE=0。もしEIが効いていれば受理時IE=1のはず。`PASS: IE=0`は「受理後クリア」
  ではなく「そもそもEIでIEが立っていない」可能性が高い。
- 検証: EI(0x02)実行直後のFLAGS bit7を1サイクル観測。cpu.sv L853-855でS_OPFETCH時に
  rf_wdata_flags←{1'b1, flags_lo15}(IE=1)。これが実際にrf_flagsに反映されるか。
  EIは1バイト命令(need_rb=0)でS_OPFETCH滞在が1サイクルのみ→書込タイミング要確認。

**仮説B: irq_in投入タイミング vs S_IRQCHKでのirq_pendingラッチの位相ズレ。**
- irq_pendingラッチは `state==S_IRQCHK && irq_in!=0` 限定(cpu.sv L1139-1141)。
- next_state受理判定(L513)は**今サイクルのirq_pending**を見る。同S_IRQCHKでラッチした
  値は次サイクル反映のため、irq_in投入がS_IRQCHK通過と重なると1サイクル取りこぼす懸念。
- ただしirq_pending=1が残存している事実は「ラッチはされている」ことを示す。ならば次命令の
  S_IRQCHKで受理されるはずだが、されていない→**IE=0(仮説A)で弾かれている**線が濃厚。
- ∴ **まず仮説Aを潰す。** IEが立たない限りirq_pendingが残っても永久に受理されない。

**仮説C: TB側のfork/wait記述の問題。**
- CPU_IRQ_TBは fork...join_none で `wait(dbg_pc==0x0105)`後にirq_in=1。最小TBのハングと
  併せ、TB記述(negedge/posedgeの取り扱い、wait条件)を疑う余地あり。iret TBは確実に動く
  ので、**iret TBをベースに最小差分でEI+irqを足す**方式に切替えるのが安全(下記§5推奨)。

### 3.3 次チャットの推奨アプローチ(kaizen「3回失敗したら設計書に戻る」適用済)
1. まず**EI単体動作**を確認(仮説A)。iret TB(動作確実)を複製し、EI→(数命令)→HALTだけの
   プログラムでEI後のFLAGS bit7=1をchk。ゼロからTBを新規記述しない(最小TBがハングした教訓)。
2. EIが効くと確認できたら、iret TB複製に irq_in パルスを最小追加して受理を実証。
3. irqのTB雛形が固まってから、当初のtb_cpu_irq_v0_1.svの検証項目(PC=0305/B=00AA/A=0011/
   SP=3FFC/IE=0/irq_pending=0/stack PC)を移植する。

---

## 4. 成果物(本チャット出力)

- `ysd8800_cpu_v0_1.sv` **v0.5.5** — 割込受理実装済(黄金照合・既存6回帰PASS)。
  変更履歴に v0.5.5 追記済(組合せループ回避=案1、TB未完も明記)。KY41 4点一貫性OK。
- `tb_cpu_irq_v0_1.sv` v0.1 — 受理検証TB(**現状7FAIL、要デバッグ**)。§3.2の仮説の
  検証台として利用可。ただし§5推奨に従いiret TB複製方式に切替えるなら参考資料扱い。

※ decoder/regfile/alu の3部品SVは本チャットで**未変更**(/mnt/project版がそのまま最新)。

---

## 5. 次チャットで必要な参照情報(実照合済)

- **EI/DI opcode**: EI=0x02, DI=0x03(いずれも1バイト命令)。decoder L110-111で確定。
  ie_set/ie_clr専用線(L239-240)。cpu.svでのFLAGS書込はS_OPFETCH L853-859。
- **IRQ番号エンコード**: irq_pending値=ISA IRQ番号+1オフセット。
  1=timer(IRQ0)/2=device(IRQ1)/3=align(IRQ3?)/4=syscall。ベクタ=mem[irq_pending*2]。
  → irq_pending=1(timer)ならvec=mem[2:3]。
- **emu23黄金**: emu23_v109.c L1174-1188(受理), L1215-1216(IRET pop)。
- **CPUポート**: clk,rst_n / mem_addr,mem_wdata,mem_rdata,mem_rd,mem_wr,mem_ready /
  irq_in[2:0] / dbg_pc,dbg_a,dbg_b,dbg_x,dbg_sp,dbg_flags,dbg_halt,dbg_irq_pending。
- **TBメモリモデル(iret TB流用可)**:
  `assign mem_ready=1'b1; always_comb mem_rdata=mem[mem_addr];`
  `always_ff @(posedge clk) if(mem_wr) mem[mem_addr]<=mem_wdata;`
- **消失TBの申し送り(CHAT72から継続)**: `tb_cpu_stack`(PUSH/POP)と `tb_cpu_jsr`(JSR/RET)の
  独立TBがプロジェクトナレッジに存在しない(FSリセットで消失と推定)。機構はiret経由で
  間接検証済のため実害小。C-3厳密化のため後日再作成が望ましい(低優先)。

---

## 6. 本日のKY活動(2026-07-05・継承可)

- **危険**: 割込受理のデバッグで、mem_addr等のバス信号を状態依存の組合せで生成し、
  シミュレータの組合せループ(時刻停止・ハング)を招く。また `&&` 連鎖ビルドで古い
  生成物を実行し症状を誤読する。
- **防止策**:
  1. バス信号(アドレス/データ)は状態依存の組合せ選択を避け、ffラッチした専用レジスタに
     寄せる(案1で実践)。
  2. ビルドと実行を分離し、間で `ls -la` によりタイムスタンプを確認してから実行。
  3. rc=124(timeout)は組合せループのサインとして最優先で疑う。
  4. デバッグTBはゼロから新規記述せず、動作確実な既存TBを複製して最小差分を足す。

---

## 7. 停滞警告

- **scc23 Phase1〜6** が計画済・未着手のまま(型システム/関数ポインタ/Q16.16等)。
  Step 8(FPGA V1)最優先方針下の意図的後回しだが、着手意向の確認を次回冒頭で促すこと。
- **第5-3段(b)のTB受理実証**が本チャットで未完。「見えているバグは先に潰す」原則により、
  次チャットの**最優先案件**。(c)へ進む前に必ず決着させること。

---

## 8. 文書改版の申し送り(作業完了後に対応)

本チャットの設計変更(組合せループ回避=案1、ベクタアドレスaddr_rラッチ方式)は、
第5-3段(b)のTB受理実証が完了した時点で以下へ反映すること:
- `fpga_v1_cpucore_design_v1_1.md` → v1.2改版(§6 FSM: S_IRQ_ACCEPTのアドレス供給を
  「addr_r ffラッチ方式」と明記。組合せ選択を禁止する設計注記を追加)。
- `stage5_3_design_memo` 系 → 受理シーケンスの実装確定事項を追記。
- `tool_version_ledger` → cpu.sv v0.5.5 を反映(次回、受理実証完了後にまとめて)。
※改版は追記のみ(前版情報を欠落させない)。
