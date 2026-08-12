# HANDOVER_CHAT72 — FPGA V1 CPU RTL 第5-3段(b)割込受理 引き継ぎ

- 文書名: HANDOVER_CHAT72.md
- 版数: v1.0
- 作成日: 2026-07-05
- 前チャット: 「FPGA実装の継続」(第5-1〜5-3(a)実装)
- 次チャット作業: 第5-3段(b) 割込受理 S_IRQ_ACCEPT から再開
- 黄金リファレンス: emu23_v109.c (外部観測等価。cycle一致は非対象)

---

## 0. 最初に読むもの / セッション開始プロトコル

次チャット開始時、以下を順に実施(規約):
1. `claude_tool_operation_guide_v1_0.txt` を1回参照(規律1〜5)。
   ※前チャットで地の文に無意味文字列("court")を混入させる不具合が複数回発生。
     ツール呼び出しは落ち着いて1つずつ、地の文に余計な語を出さないこと。
2. 工程確認: 「進捗と予定の確認(latest)」(URL 4b67e76b-ee54-446a-a2fd-b49b65dfc3ba、
   内容キーワードで検索)を参照 → 「工程ヨシ!」「次工程の確認ヨシ!」。
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
   ├ 🔧 第5-3段(b) 割込受理 S_IRQ_ACCEPT ← 次の作業
   └ ⬜ 第5-3段(c) 受理→IRET往復統合 + align例外受理
⬜ V2 CPUコア単体検証(全命令 emu23外部観測等価)
```

- **現行版**: `ysd8800_cpu_v0_1.sv` v0.5.4 (ファイル名は_v0_1のまま=V1完成時一括リネーム
  方針。内容バージョンで管理)。
- **全6TB ALL PASS**確認済(byte/mem/memalign/stack/jsr/iret)。
- 作業DIR: `/home/claude/v1_rtl/`、出力: `/mnt/user-data/outputs/v1_rtl_20260704/`
  (次チャットは日付更新して v1_rtl_20260705/ を推奨)。
- **セッション跨ぎでFSリセット**。次チャットは outputs または /mnt/project から
  SVファイル一式を作業DIRへ復元して開始する(KY34: まずls/headで実体確認)。

### コンパイル/実行手順(Icarus 12.0)
```
# マルチファイル順: decoder→regfile→alu→cpu→tb (パッケージ定義が先)
iverilog -g2012 -o /tmp/sim \
  ysd8800_decoder_v0_1.sv ysd8800_regfile_v0_1.sv ysd8800_alu_v0_1.sv \
  ysd8800_cpu_v0_1.sv tb_cpu_XXX_v0_1.sv
timeout 30 vvp /tmp/sim    # 必ずtimeout付き
```

---

## 2. 第5-3段(b) 割込受理 実装内容(emu23_v109実照合済・確定)

### 2.1 受理シーケンス (emu23 L1174-1189)
```c
if (irq_pending>=0 && (flags&FL_IE)) {   // RTL等価: irq_pending!=0 && flags_ie
    int irq = irq_pending; irq_pending=-1; // RTL: irq_latchへ退避(C-1)
    push16(cpu.pc);              // PCを先にpush
    push16((uint16_t)cpu.flags); // FLAGSを後にpush(16bit化,上位0)
    cpu.flags &= ~FL_IE;         // IE=0 (push後!)
    vec = rd16(irq*2);           // ベクタ=mem[irq*2] 16bit LE
    cpu.pc = vec;
}
```
- push順: **PC(先)→FLAGS(後)**。IRETのpop順(FLAGS→PC)とLIFO対称。
- ベクタ = mem[irq_latch*2] の16bit LE。irq値(1=timer/2=device/3=align/4=syscall)
  をそのまま2倍。vec配置: mem[2/4/6/8]。リセットベクタmem[0/1]とは非重複。
- 受理条件は S_IRQCHK に実装済(cpu.sv内): `irq_pending!=0 && flags_ie`→S_IRQ_ACCEPT。

### 2.2 状態遷移(実装予定)
```
S_IRQCHK(受理成立) → S_IRQ_ACCEPT
  [S_IRQ_ACCEPT] ff: stack_ctx←CTX_IRQ, push_count←2, push_src←rf_pc(PC),
                     irq_latch←irq_pending  ★C-1: 入口でirq退避
  → S_PUSH_LO → S_PUSH_HI  (1回目=PC push)
     HI完了: SP-=2, push_count 2→1, push_src←rf_flags(FLAGS), →S_PUSH_LO
  → S_PUSH_LO → S_PUSH_HI  (2回目=FLAGS push)
     HI完了: SP-=2, push_count 1→0, IE=0(flags更新), →S_MEMR_LO(ベクタ読み)
  → S_MEMR_LO → S_MEMR_HI  (stack_ctx=CTX_IRQVEC, addr=irq_latch*2)
     HI完了: PC←{hi,lo}(vec), irq_pending←0クリア, →S_FETCH
```
- **push_count制御**: pop_countと同型(残り回数2→1→0)。減算はS_PUSH_HI完了ワンショット
  (SP更新と同期・滞留中不変・7/01 KY)。既にpop_count/push_countはリセット初期化済。
- **push_src 2段セット**: S_IRQ_ACCEPTでPC、1回目PUSH_HI完了でFLAGS。
- **push_data経路**: cpu.sv内push_data always_combに `CTX_IRQ: push_data=push_src`
  が既に配置済(第5-2段で先行実装)。CTX_IRQで合流する。
- **ベクタ読み**: S_MEMR_LO/HIを stack_ctx=CTX_IRQVEC で流用(論点K承認)。mem出力always
  で ctx==CTX_IRQVEC のとき mem_addr=irq_vec_addr(={irq_latch,1'b0}=irq*2)。
  完了時の戻り先を通常ロード(S_WRITEBACK)でなくPC←vec+S_FETCHに分岐させる。

### 2.3 実装必要箇所(cpu.sv)
- **next_state**: S_IRQ_ACCEPT→S_PUSH_LO。S_PUSH_HIにCTX_IRQ&push_count分岐追加
  (>1→S_PUSH_LO継続, ==1→S_MEMR_LO)。S_MEMR_HIにCTX_IRQVEC分岐追加(→S_FETCH)。
- **レジスタ更新comb**: S_PUSH_HIにCTX_IRQ時のpush_count分岐(2回目でIE=0)。
  S_MEMR_HIにCTX_IRQVEC時のPC←load相当。
- **mem出力**: S_MEMR_LO/HIのaddrをctx=CTX_IRQVEC時はirq_vec_addrに。
- **ff**: S_IRQ_ACCEPTでstack_ctx/push_count/push_src/irq_latch設定。push_count減算
  (S_PUSH_HI完了)。1回目PUSH_HI完了でpush_src←rf_flags。ベクタ読み完了でirq_pending←0。
- **新規信号**: `irq_latch`(logic[2:0])宣言+リセット初期化。`irq_vec_addr`(assign
  ={irq_latch,1'b0})。CTX_IRQ/CTX_IRQVECはlocalparam宣言済か要確認(未宣言なら追加)。

---

## 3. レビュー結果(条件付き承認・反映必須)

前チャットで設計レビュー実施済(stage5_3_design_review_v1_0.docx 提出 →
reply受領)。**D-1/D-2は確定承認**。クローズ条件:

| 区分 | 内容 | 反映先 |
|---|---|---|
| D-1(承認) | pushするFLAGSはIE=1(旧値)、IEクリアはpush後。emu23順序通り。 | (b)で実装 |
| D-2(承認) | IRET FLAGS復元は下位8bitのみ`{8'h00,pop[7:0]}`。ISA2.3で有効bit(Z=b0/N=b1/IE=b7)は下位8bit内と確定。 | (a)で実装済 |
| **C-1** | irq番号をS_IRQ_ACCEPT入口でirq_latchへ退避(受理中の競合遮断)。 | **(b)で反映** |
| C-2 | push/pop_count減算はHI完了ワンショット(ff出力のみ分岐条件)。 | (a)反映済/(b)継続 |
| C-3 | 既存TB全数回帰を合格条件。 | (b)(c)で厳守 |
| E-1 | align例外(irq=3)はLDW/STW両経路の受理TB。 | (c)で反映 |
| M-1 | golden実体はemu23_v109で確定(作業環境・台帳整合済)。レビュー環境はv108だったが論理一致。行番号相違は版差。 | 情報共有のみ |

---

## 4. 昨日までの実装知見(重要)

- **stack_ctx統合方式**(論点G-a承認): 共通S_PUSH/POP機構をstack_ctx(CTX_NONE/PUSH/
  POP/JSR/RET/IRET/IRQ/IRQVEC)で「pushデータ源」「pop書戻し先」「完了後遷移」を分岐。
  push_data always_combで源を選択(CTX_PUSH:A/B/X, CTX_JSR/IRQ:push_src)。
- **POP対象reg判定バグ(第5-1段で修正済)**: HANDOVER§2.2「下位2bit」はPUSH専用。POPは
  0x03起点で不成立→`stk_pop_sel=subop_r[2:0]-3`。emu23 L1253-1255照合で確定。
- **Icarus制約**: always_comb内の定数ビット選択(rf_flags[14:0]等)はsorry警告→assign
  外出し(flags_lo15/subop_lo3等)。既存の対処パターンに倣うこと。
- **TB知見(IRET/割込のFLAGS検証)**: 復帰先にフラグ不変命令(MOV)を置く。LDWI等の
  フラグ更新命令を置くと復元FLAGSが上書きされ検証不能(第5-3(a)初回FAILの原因)。
- **観測ポート**: dbg_irq_pending追加済(SYSCALL/割込のirq_pending観測用)。
- **SP初期化**: TBではLDWI SP(rD=3=SP)でSP設定可能(regfileがwaddr_gp==3でSP書込)。

---

## 5. TB計画(第5-3段)

- (a)完了: tb_cpu_iret_v0_1.sv (復帰PC/SP+4/FLAGS下位8bit=D-2実証) ALL PASS。
- **(b)予定**: tb_cpu_irq_v0_1.sv — IE=1でirq_in投入→受理(PC/FLAGS push, IE=0,
  vec飛び)→ハンドラ実行。ベクタテーブルmem[irq*2]を仕込む。push順PC→FLAGS、
  SP-4、IE=0、PC←vec を確認。
- **(c)予定**: 受理→IRET往復統合(PC/FLAGS/SPが受理前に戻る=LIFO対称の最重要検証)。
  + align例外(奇数addr LDW/STW→irq_pending=3→受理→vec=mem[6])をLDW/STW両経路で。

---

## 6. KY活動(2026-07-05・第5-3段(b)固有・当日有効)

**危険**: 割込受理で stack_ctx/push_count/irq_latch の状態管理を取り違え、
(ア)ベクタ読み後PCが飛ばない/誤アドレス (イ)受理中の新irq_inでベクタ番号書換
(ウ)pushするFLAGSがIE=0になる(クリア順序ミス)。

**防止策**:
1. irq番号はS_IRQ_ACCEPT入口でirq_latchへ退避、以降ベクタ計算はirq_latchのみ参照
   (C-1)。irq_pendingには触らない。
2. ベクタ読み(CTX_IRQVEC)完了の戻り先をPC←vec+S_FETCHに分岐(通常ロードと区別)。
3. FLAGS pushはIE=1(旧値)のまま、IE=0は2回目push完了後(D-1)。
4. 実装前に受理シーケンス各サイクルを1サイクルずつ紙上トレース。3回失敗したら
   stage5_3_design_memo に戻る。

---

## 7. 申し送り(未完タスク・次チャット必須)

- **【文書改版・未了】** レビューで本線採用したC-1(irq入口ラッチ)を
  `stage5_3_design_memo_v0_1.md` → v0.2に反映する作業が未了。方針1(作業完了後に
  改版)で合意済のため、第5-3段(b)(c)完了後にまとめて設計メモを改版すること。
- 第5段完了時: cpuヘッダ4点整合(ファイル名/版数/日付/変更履歴)を最終確認。
  fpga_v1_cpucore_design 次版への追記(V1完成時一括改版)。
- scc23 Phase1〜6は計画済・未着手(Step8最優先で意図的後回し)。停滞警告継続。

---

## 8. 版数台帳・参照文書

- ツール版数: emu23 v1.09(golden), hasm23 v1.04, lnk23 v2.01, scc23 v2.03,
  Force v1.5, mkfs_yuifs.py v1.1。台帳=tool_version_ledger_v1_10.md。
- 設計文書: stage5_3_design_review_v1_0.docx(レビュー依頼), stage5_3_design_memo
  _v0_1.md(実装設計・要v0.2改版)。
- emu23実照合キー行(v109): IRET L1213-1224, 受理 L1174-1189, SYSCALL L1231,
  JSR L1529-1533, RET L1535, PUSH/POP L1247-1255。
