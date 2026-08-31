# V2-e 設計メモ  v0.1  (2026-07-10)
## YSD8800 FPGA V2-e : C8制御割込（EI/DI/SYSCALL/IRET/割込受理）外部観測等価検証

対象読者: レビュアー（かやぬまさん）
位置づけ: 原則43に基づく実装前設計メモ（レビュー承認後に実装着手）
土台: V2-d設計メモ v0.1 / gen_v2_vectors_v2d_poc.py / tb_cpu_v2d_v0_1.sv

---

## 1. 目的とスコープ

### 1.1 目的
V2-a〜d で構築した「emu23 v1.09 黄金突合フレーム（プログラムを置きHALTまで
自走 → 最終レジスタ/FLAGS/PC/SP を emu23 黄金と突合）」に、C8制御割込命令群を
統合し、V2 CPUコア単体検証の回帰体系を完成させる。

### 1.2 検証対象命令（emu23_v109.c 実照合済・KY34）
| 命令 | opcode | emu23挙動(行) | FLAGS |
|---|---|---|---|
| EI      | 0x02 | flags \|= 0x80 (FL_IE)         (L1205) | IE=1 |
| DI      | 0x03 | flags &= ~0x80                 (L1209) | IE=0 |
| IRET    | 0x04 | flags=(uint8_t)pop16; pc=pop16 (L1213) | pop復元(下位8bit) |
| SYSCALL | 0x05 | irq_pending=4 (その場は飛ばない)(L1225) | 不変 |
| 割込受理 | -   | push16(PC);push16(FLAGS);IE=0;PC=rd16(irq*2) (L1176-1184) | IE=0 |

補助（既存流用）: LDW SP,#imm(SP初期化), PUSH/POP(手動スタック構築), MOV X,SP(SP観測)

### 1.3 ★スコープ確定（実地確認に基づく判断）
実地確認（emu23_v109 実照合・本メモ§3）の結果、以下に確定する。

**V2-e に含める（自走HALTで黄金取得可能）**:
- (a) EI / DI / IRET の命令単体動作
- (b1) **SYSCALL 起点の割込受理**シーケンス（irq_pending=4 →
      vec=rd16($0008) → push×2 → ハンドラ）※vec=$0008は実測§5 R-1で確定

**V2-e 対象外（別工程で担保）**:
- (b2) タイマーIRQ（YSD8002_tick駆動）/ 外部 irq_in 注入による受理
  → 理由: 周辺デバイスモデル依存で自走HALT黄金が取れない。かつ
    **V1 Stage5-3 で機能TB（tb_cpu_irq_*, tb_cpu_iret_*）検証済**。
  → V7（IRQ統合）で周辺込みで再検証する。二重実装を避ける。

【判断根拠】外部観測等価の原則に照らし、SYSCALL起点なら周辺なしで
「受理→ベクタ参照→push退避→ハンドラ到達」の全観測点が黄金で取れる。
タイマー駆動は観測点が同じ（同じS_IRQ_ACCEPT機構）ため、SYSCALL起点で
受理機構を突合すれば、割込受理FSMの外部観測等価は十分に担保される。

---

## 2. 検証観点と突合項目

### 2.1 突合項目（V2-d を継承・6word）
A, B, X, FLAGS(下位8bit), PC, SP を emu23黄金と突合。
SP突合対象は本V2-e新規ベクタ（grp=ctl/irq）とする。既存75は従来通り
（stk/sub=SP突合、leg/br/mem=SP除外）。

### 2.2 命令別の検証観点
- **EI/DI**: FLAGS の IE ビット(0x80)操作を FLAGS突合で確認。
  EI後 F=0x80, DI後 F=0x00（他ビット非汚染も確認）。
- **IRET**: 手動でスタックに [PC][FLAGS] を積み（V2-d RET_only 手法流用）、
  IRET で FLAGS←pop / PC←pop が復元されることを確認。
  ★観点: FLAGS復元は下位8bitのみ（emu23 (uint8_t)キャスト・L1215）。
  上位に 1 を積んでも復元後は 0 になることを確認（マスク検証）。
- **SYSCALL受理**: 下記シーケンスの外部観測を確認（§2.3）。

### 2.3 SYSCALL割込受理シーケンス（最重要観点）
```
ベクタ配置: $0008 = IRQ4ハンドラ番地(handler_addr)  ※SYSCALL単独はirq_pending=4のまま→vec=rd16($0008)
main : LDW SP,#SP_INIT; EI; SYSCALL; (受理でここは踏まない)
       ↓ SYSCALL実行後、次サイクル冒頭の受理フェーズで:
       push16(PC=SYSCALL次番地); push16(FLAGS=0x80); IE=0; PC←rd16($0008)
handler: (受理到達の印) A←0x1234; HALT
```
観測点:
- A=0x1234 → ハンドラに到達した（受理成功）
- SP = SP_INIT-4 → PC/FLAGS の2ワードpush（各2バイト）でSP-=4
- FLAGS の IE=0 → 受理時 IE クリア（F bit7=0）

★注記(実測§5 R-1で確定): SYSCALLは irq_pending=4 を立てるのみ(L1225)。
  次のfetch前チェック(L1176)で IE=1 かつ irq_pending>=0 なら受理。
  vec=rd16(4*2)=rd16($0008)。ysd8004_raiseの4→2正規化は本経路では通らない。
  gen側は emu23 をそのまま走らせるだけ（特別処理不要・黄金が正）。

---

## 3. 実地確認結果（emu23_v109 実照合・2026-07-10）

原則43の設計判断根拠として、机上でなく実ソースを照合した。

### 3.1 受理条件と動作（L1176-1188）
```
if (irq_pending >= 0 && (flags & FL_IE)) {   // IE=1 が受理の必須条件
    irq = irq_pending; irq_pending = -1;
    push16(pc);                 // PC を先に push
    push16((uint16_t)flags);    // FLAGS を後に push
    flags &= ~FL_IE;            // IE=0
    vec = rd16(irq * 2);        // ベクタ = $0000起点・irq*2
    pc = vec;
}
```
→ **周辺デバイス不要**。ベクタテーブルを $0000〜 に置けば自走で受理黄金取得可。

### 3.2 SYSCALL の irq番号正規化（L322-325）
SYSCALL は irq_pending=4 を立てる。次サイクル、YSD8004経由で
irq_pending==4 は 2 へ上書き正規化される（vec=$0004=IRQ1エントリ）。
→ gen側は SYSCALL を置くだけでよい。正規化は emu23 内部で完結。

### 3.3 ベクタ域とコード域の非衝突
- リセットベクタ: $0000-$0001
- IRQ1ベクタ:     $0004-$0005
- CODE_ORG:       $0100
→ ベクタ域($0000-$0007)とコード域は分離。衝突なし（V2-d make_image流用可）。

### 3.4 FLAGSビット定義（L93-95）
FL_Z=0x01, FL_N=0x02, FL_IE=0x80。

---

## 4. ベクタ設計（新規 約6〜8本）

grp: ctl（制御命令単体）/ irq（受理シーケンス）。全ベクタ先頭で SP 初期化。

### C8-ctl（制御命令単体・4本）
| id | 内容 | 主観測 |
|---|---|---|
| EI_set     | LDW SP; EI; HALT              | F=0x80(IE=1) |
| DI_clear   | LDW SP; EI; DI; HALT          | F=0x00(IE=0・他ビット非汚染) |
| IRET_basic | 手動push[PC][FLAGS]; IRET      | PC=戻り先, F=積んだ値の下位8bit |
| IRET_mask  | FLAGS上位に1を積み IRET         | F上位が0にマスクされる（(uint8_t)確認） |

### C8-irq（SYSCALL受理・2〜4本）
※実測(§5 R-1)確定: SYSCALL単独は irq_pending=4 のまま vec=rd16($0008)。
  よってベクタは **$0008** にhandler番地を書く（$0004ではない）。
| id | 内容 | 主観測 |
|---|---|---|
| SYS_accept | ベクタ$0008=handler; EI; SYSCALL; handler:A←0x1234;HALT | A=0x1234, SP=SP_INIT-4, F IE=0 |
| SYS_noEI   | EI無しで SYSCALL（IE=0のため受理されない） | irq_pending立つが受理されず→挙動を黄金で確認 |
| SYS_iret   | 受理→handler内でIRET→mainに復帰→HALT | 復帰後PC/FLAGS/SP整合(往復対称) |

★SYS_noEI は「IE=0では受理されない」ガード条件(L1176)の検証。
  ただし emu23 は irq_pending=4 を保持したまま次命令へ進むため、
  黄金が示す最終状態を確認し、RTL と一致すればよい（挙動定義の突合）。

---

## 5. RTL側の前提（既存実装の確認事項）

C8のRTL実装は V1 Stage5-1〜5-3 で完了済（cpu v0.5.4以降・現行v0.5.6）。
本V2-eは新規RTL実装ではなく、既存RTLの外部観測等価を黄金突合で確認する。

確認すべき既存RTL挙動（レビュー時に要確認）:
- EI/DI: FLAGS.IE 操作が emu23 と一致するか
- IRET: pop_count方式（2→1→0）で FLAGS←pop / PC←pop、下位8bit復元
- S_IRQ_ACCEPT: irq_latch でラッチ後、push×2＋vec=rd16(irq*2)
- ★SYSCALL の irq番号: RTL が emu23 と同じ vec を参照するか（論点R-1・下記で決着済）

【論点R-1（実測で決着・2026-07-10）】
~~emu23 は SYSCALL→irq_pending=4→YSD8004正規化→2→vec=$0004。~~
~~RTL(v0.5.x)が vec=$000A[irq5相当]か $0004[irq1相当]かを実RTL照合で確認要。~~
↑起票時の懸念は誤り。実測プローブ(sysprobe.bin・emu23実走)で決着した:

  **SYSCALL 単独 → irq_pending=4 のまま受理 → vec=rd16($0008)**
  （実測ログ: "IRQ 4 accepted, vec=0300", 最終 A=0x0008/SP=FC7A/F=00）

  ysd8004_raise の 4→2 正規化(L322-325)は **UART等デバイスがirq_statを
  セットした時のみ**発動する経路で、SYSCALL単独では通らない。
  emu23コメント L310「irq_pending=2→vec=$0004」は YSD8004経由時の記述で、
  SYSCALL単独には適用されない（コメントに引きずられた起票時の誤読）。

  RTL(L1130 irq_pending<=4 / L1163 addr_r<=irq_pending<<1=$0008)は
  emu23実測($0008)と**一致**。バグではない。V2-eではこの一致を
  黄金突合で追認する（RTL修正不要）。

  ★教訓(kaizen候補): emu23の内部コメントは特定経路(YSD8004)前提のことが
    あり、命令単独挙動と混同しない。断定前に実走で確認する(KY34)。

---

## 6. 実装手順（レビュー承認後・次チャット）

1. gen_v2_vectors_v2e_poc.py 作成（v2d土台＋C8エンコーダ＋ベクタ配置）
   - EI/DI/IRET/SYSCALL エンコーダ追加
   - ベクタ$0004 への handler_addr 書込を make_image で対応
2. emu23黄金取得（自走）・目視検証（受理でA=0x1234, SP-=4, IE=0）
3. tb_cpu_v2e_v0_1.sv 作成（grp=ctl/irq 追加・受理観測）
4. コンパイル→実行→ALL PASS（既存75＋新規約6〜8）
5. 論点R-1（SYSCALL vec）でRTL差異が出たら bug修正して再回帰
6. レビュー→承認→V2完了

---

## 7. KY（本設計に潜む危険）

**危険**: 割込受理の「PC push値」を取り違える危険。emu23は
push16(cpu.pc) を受理時に行うが、この cpu.pc は「SYSCALL命令実行後・
次命令をfetchする前」の値（=SYSCALL次番地）。gen/TBで「SYSCALL命令の
番地」と誤認すると期待PC(復帰先)が1命令ずれる。

**防止策**: 
1. SYSCALL受理の期待値は emu23黄金をそのまま使う（手計算しない・KY34）。
2. IRET往復ベクタ(SYS_iret)で「受理でpushしたPC」==「IRETで復帰するPC」==
   「SYSCALL次番地」の三者一致を黄金で確認してから実装。
3. handler内 A←0x1234 到達 と SP-=4 の両方が揃って初めて受理成功と判定
   （片方だけでは push回数/vec先の誤りを見逃す）。

---

## 8. レビュー依頼事項（この設計メモで承認いただきたい点）

- [ ] Q1: スコープ確定（§1.3）— SYSCALL起点受理を含め、タイマー/外部irq注入を
        V2-e対象外（V7送り）とする判断は妥当か。
- [ ] Q2: ベクタ設計（§4）— ctl4本＋irq2〜4本の粒度・観測点は十分か。
        特に SYS_noEI（IE=0で非受理）を入れるべきか。
- [x] Q3: 論点R-1（§5）— 実測(sysprobe.bin)で決着済。SYSCALL単独は
        vec=$0008、RTL(irq_pending=4<<1=$0008)とemu23実測が一致。RTL修正不要。
        → レビューでは「この実測決着を承認いただく」形（争点消滅）。
- [ ] Q4: IRET_mask（§4）— FLAGS上位マスク（(uint8_t)）検証を1本立てる価値は
        あるか（V1 Stage5-3 D-2で確認済のため冗長かもしれない）。
- [ ] Q5: SP突合対象grp（§2.1）— 新規ctl/irqをSP突合対象に含める方針で良いか。

---

## 変更履歴
- v0.1 (2026-07-10): 初版。V2-d完了・承認を受けてV2-e設計を起票。
  emu23_v109実照合（受理L1176/SYSCALL L1225/正規化L322/FLAGS L93）に基づき
  スコープ確定（SYSCALL起点受理を含む・タイマー/外部irq注入はV7送り）。
  ★同日、論点R-1を実測プローブ(sysprobe.bin・emu23実走)で決着:
    SYSCALL単独はirq_pending=4のままvec=rd16($0008)、RTL($0008)と一致。
    起票時のvec=$0004懸念は誤読と判明し、§1.3/§2.3/§4/§5/§8を$0008基準に改版。
    RTL修正不要を確認（争点R-1消滅）。
