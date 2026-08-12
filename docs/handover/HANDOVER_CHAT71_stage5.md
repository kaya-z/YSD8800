# HANDOVER — V1 CPUコア 第5段(スタック・制御・割込受理) 実装引継ぎ

- ファイル名: HANDOVER_CHAT71_stage5.md
- バージョン: v1.0
- 作成日: 2026-07-04
- 前提成果物: ysd8800_cpu_v0_1.sv **v0.5.1**（作業ディレクトリ/outputs/v1_rtl_20260704）
- 位置づけ: 第5段は2段階レビュー承認済・設計確定。実装本体が未着手。
  本チャット(CHAT71相当)がログ肥大したため案bで区切り、次チャットで実装再開する。

---

## 1. 現在地(工程)

```
🔧 Step 8 第Ⅱ部 V1 CPUコア RTL実装 / FSM命令実行の肉付け
   ├ ✅ 第1段 レジスタALU/MOV/CMP        (v0.3, 7/03)
   ├ ✅ 第2段 即値ALU/LDWI/CMPI          (v0.3, 7/03)
   ├ ✅ 第3段 分岐 JMP/Bcc               (v0.3, 7/03)
   ├ ✅ 第4-A段 メモリLDW/STW+アライメント例外 (v0.4, 7/04)
   ├ ✅ 第4-B段 バイトLDB/STB(EXT経由)    (v0.5, 7/04)
   └ 🔧 第5段 スタック・制御・割込受理    (v0.5.1=設計完了/実装未了) ←次チャット
⬜ V2 CPUコア単体検証(全命令 emu23外部観測等価)
```

現状の検証: 6TB全通過(alu/imm/branch/mem/memalign/byte)。第5段の制御レジスタ
宣言のみ追加済(未使用・コンパイル健全)。

---

## 2. 第5段 設計確定事項(実照合+2段階レビュー承認済)

すべて emu23_v109.c 実照合に基づく実装事実。cpu v0.5.1 ヘッダにも記録済。

### 2.1 スタック基盤(emu23 L832-840)
- **SP方向**: pre-decrement push / post-increment pop (MC6809方式)。
  - push16: `SP-=2; wr16(SP,v)` (wr16=LE: mem[SP]=下位, mem[SP+1]=上位)
  - pop16 : `v=rd16(SP); SP+=2`
- 専用状態 S_PUSH_LO/HI, S_POP_LO/HI (論点F承認)。

### 2.2 PUSH/POP A/B/X (EXT 0x1F, サブop 0x00-05, 2バイト, L1248-1255)
- 0x00/01/02=PUSH A/B/X, 0x03/04/05=POP A/B/X。対象reg=subop下位2bit(0=A/1=B/2=X)。
- 経路: S_OPFETCH(need_subop)→S_SUBOP→S_DECODE→S_PUSH_LO/HI or S_POP_LO/HI。

### 2.3 制御命令(1バイト通常opcode, EXT非経由, L1195-1233)
- opcode: EI=0x02, DI=0x03, IRET=0x04, SYSCALL=0x05 (NOP=0x00/HALT=0x01は実装済)。
  BRK=0x06(halted)。
- EI: FLAGS.IE=1 / DI: FLAGS.IE=0。
- IRET(L1213-1216): `FLAGS←(uint8_t)pop16()` (下位8bitのみ) → `PC←pop16()`。
  pop 2回。pop_dst_selで1回目=FLAGS/2回目=PC。
- SYSCALL(L1225-1231): `irq_pending←4`。スタック操作なし。次のS_IRQCHKで受理発火。

### 2.4 JSR/RET (L1531-1536)
- JSR(0x68, 3バイト): `push16(nextPC)` → `PC←imm16`(絶対)。
  経路: S_OPFETCH→S_IMML→S_IMMH→S_EXEC_JSR→(push機構)→PC←imm_r。
- RET(0x69, 1バイト): `PC←pop16()`。経路: S_OPFETCH→S_EXEC_RET→(pop機構)→PC。

### 2.5 割込受理 (S_IRQCHK→S_IRQ_ACCEPT, L1174-1189)
- 条件: `irq_pending≠0 && FLAGS.IE=1` (S_IRQCHKに実装済 L361-366)。
- シーケンス: push16(PC) → push16(FLAGS) → IE=0 → PC←rd16(pending*2)。
  - push順 PC→FLAGS (IRETのpop順 FLAGS→PCと対称/LIFO整合)。
  - ベクタ = mem[pending*2] の16bit(LE)。pending値(1=タイマー/2=デバイス/4=SYSCALL/
    3=アライメント例外)そのもので計算。
- push 2回 + ベクタ読み。stack_ctx=CTX_IRQ/CTX_IRQVEC と push_count で制御。

### 2.6 複合命令制御(論点G-a/I/J/K承認)
- 共通 S_PUSH/POP 機構を stack_ctx(CTX_*)で戻り先分岐。
- 多重push/pop(IRET=pop2, 割込受理=push2)は pop_count/push_count カウンタ。
- ベクタ読み(論点K)は S_MEMR_LO/HI を stack_ctx=CTX_IRQVEC で流用し完了時PCへ。

---

## 3. 既に宣言済みの資産(v0.5.1)

- **enum状態**(全て既存): S_IRQ_ACCEPT, S_PUSH_LO/HI, S_POP_LO/HI,
  S_EXEC_IRET, S_EXEC_SYSCALL, S_EXEC_JSR, S_EXEC_RET。新規増設不要。
- **制御レジスタ**(宣言済・未使用): stack_ctx[2:0], push_count[1:0],
  pop_count[1:0], push_src[15:0]。CTX_NONE/PUSH/POP/JSR/RET/IRET/IRQ/IRQVEC の
  localparam命名済。
- **irq_pending**[2:0]: 流用(論点H)。0=なし/1/2/3(align)/4(syscall)。
- S_IRQCHK: 受理分岐 実装済(L361-366)。S_IRQ_ACCEPT本体が未実装。

---

## 4. 実装順(次チャット・各段でTB検証)

1. **第5-1段**: EI/DI/SYSCALL(スタック無し・最単純) + PUSH/POP(スタック基盤)。
   - TB: PUSH A→POP B で値移動、SP増減、EI/DIでIEビット、SYSCALLでirq_pending=4。
2. **第5-2段**: JSR/RET(push/pop各1回・基盤の応用)。
   - TB: JSRでサブルーチン呼び出し→RETで復帰、戻り先PC・SP往復。
3. **第5-3段**: IRET(pop2回) + 割込受理S_IRQ_ACCEPT(push2回+ベクタ読み)。
   - TB: irq_in投入→受理(PC/FLAGS push, IE=0, vec飛び)→ハンドラ→IRET復帰。
   - アライメント例外(irq_pending=3, 第4-A段で検出済)の受理もここで完結。

---

## 5. 留意事項・KY(次チャットでも継続)

- **7/01 KY**: PC/SP更新は「state==X && mem_ready」の遷移確定サイクルの
  ワンショットのみ。滞留中は加算しない。SP pre-dec/post-incで最重要。
- **本日(7/04) KY**: スタックSP方向・IRET復元順(FLAGS→PC,下位8bit)・割込受理
  ベクタ(mem[pending*2])/IEクリア/pendingオフセット。全て実照合済。
- **Icarus制約**: always_comb内ビット選択は assign中間信号に抽出
  (push_src[7:0]等も要注意)。unique case非対応→case。
- **ツール操作**: パイプ2段まで、.sv編集はstr_replace(直前view・1箇所ずつ)、
  生成はcreate_file(ヒアドキュメント禁止)。1応答のツール数を抑える。
- **timer_in_service**(emu23 IRET内): ソフト固有。FPGAは模倣不要。

---

## 6. 設計変更(文書改版が必要・作業完了後)

fpga_v1_cpucore_design 次版で追記(V1完成時に一括改版が効率的):
- 第1〜3段: S_DECODE用途変更、S_EXEC_ALUI不使用(S_EXEC_ALU合流)。
- 第4-A段: 案X(S_DECODEでアドレス確定)、判断①(アライメント検出/受理分離)、論点A。
- 第4-B段: EXTデコード経路(subop_valid)、案U(バイトはアライメント判定スキップ)、
  論点C-b/D。
- 第5段: 本HANDOVER §2の確定事項(実装後に反映)。

---

## 変更履歴

| 版 | 日付 | 変更内容 |
|---|---|---|
| v1.0 | 2026-07-04 | 新規作成。第5段の2段階レビュー承認済設計を集約。実装は次チャット。cpu v0.5.1(設計完了/実装未了)を前提成果物とする。 |
