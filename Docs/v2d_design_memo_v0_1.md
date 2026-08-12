# V2-d 設計メモ v0.1 (2026-07-10)
## FPGA V2 CPUコア単体検証 — C6スタック / C7サブルーチン

---

## 0. 位置づけ
- 親: V2 CPUコア単体検証（設計メモ v0.1 承認済）
- 前段: V2-a(C1) / V2-b(C2/C3) / V2-c(C4分岐/C5メモリ) 全 ALL PASS(累積64)
- 本メモ: V2-d（C6スタック群 / C7サブルーチン群）の検証設計
- 原則43: 本メモのレビュー承認を得てから実装(TB作成)に着手する。
- スコープ確定: C6スタック＋C7サブルーチンの2グループ（ユーザー指示 2026-07-10）。
  C8制御割込(EI/DI/SYSCALL/IRET/割込受理)は V2-e として独立。
- 本V2-dの主眼: これまで検証除外してきた SP(スタックポインタ)を検証対象に復帰させ、
  スタック機構(退避/復帰)の外部観測等価を確立する。

---

## 1. 対象命令（ISA2_3_v231 / emu23_v109 実照合済）

### C6 スタック（EXTプレフィックス(0x1F)+サブオペコード方式）
| バイト列 | 命令 | 動作 |
|----------|------|------|
| 1F 00 | PUSH A | SP-=2; mem16[SP]<-A |
| 1F 01 | PUSH B | SP-=2; mem16[SP]<-B |
| 1F 02 | PUSH X | SP-=2; mem16[SP]<-X |
| 1F 03 | POP A  | A<-mem16[SP]; SP+=2 |
| 1F 04 | POP B  | B<-mem16[SP]; SP+=2 |
| 1F 05 | POP X  | X<-mem16[SP]; SP+=2 |

- PUSH/POPはEXT配下(emu23 L988/L1052-53実照合)。V2-cのLDB/STBと同型。
  トップレベル0x00-0x05(NOP/HALT/EI/DI/IRET/SYSCALL)とは別命令。数値衝突に注意。
- push16/pop16(L832-839): SP-=2;wr16 / rd16;SP+=2。SP増減方向確定。
- PUSH/POPは FLAGS不変(ISA L254明記)。

### C7 サブルーチン（分岐帯・直接opcode）
| opcode | 命令 | 長さ | 動作 |
|--------|------|------|------|
| 0x68 | JSR imm16 | 3B | push16(next PC); PC<-imm16 |
| 0x69 | RET       | 1B | PC<-pop16() |

- JSR(L1531): 戻り先=次命令アドレス(next PC)をpushしてからPC<-imm。
  (V2-cの分岐と同じく、fetch後PC=次命令アドレスが基準)
- RET: pop16でPC復帰。JSR/RETは FLAGS不変。
- imm16はLE。JSRのターゲットは絶対アドレス(rel16ではない・分岐と異なる)。

---

## 2. SP初期値問題の決着（本V2-dの前提・実照合済）
- emu23 初期SP = 0xFC7E(L1909・スタック領域$F800-$FC7F頂上・ISA2.2仕様)。
- RTL リセットSP = 0x0000(regfile L92)。
- 両者は初期化ポリシー差(ソフト慣習 vs ハードリセット0クリア)。仕様差ではない。
- 対策: テストプログラム先頭で LDW SP,#imm16 により SPを既知値へ明示初期化。
  - RTL/emu23とも汎用ポート経由SP書込が有効(RTL regfile L104 gp_we_sp、
    emu23 get_reg_ptr(3)=&cpu.sp)。実照合済。
  - 初期化値は emu23スタック領域内の偶数番地 $FC7E を採用
    (emu23慣習と一致させ実スタック動作と自然整合。コード域$0100/データ域$0200と非干渉)。
  - これにより初期SP差(0x0000 vs 0xFC7E)を無効化し、SPを突合対象に復帰。
  - HANDOVER_CHAT75の宿題「SP検証はC8へ持ち越し」を本V2-dで回収。

---

## 3. 検証方式（V2-c方式を踏襲 + SP突合復帰）
1. 単一ソース生成: 同一バイト列から emu23用bin と $readmemh用hex(偽合格防止)。
2. 期待値は emu23 v1.09 黄金から自動取得(手計算しない・KY34)。
   PC観測点はV2-c同様「実行後サマリ行(FLAGS=形式・HALT後PC)」を採る(RTL dbg_pc一致)。
3. 外部観測等価が合格基準。回帰ゲート: 完走+論理結果一致(cycle除外)。
4. 突合対象に SP を追加(A/B/X/F/PC/SP の6点突合)。V2-a〜cはSP除外だったが本V2-dで復帰。
5. スタックに積まれた値の検証: POPで読み戻してレジスタ突合
   (V2-cのストア読み戻し方式の応用。メモリダンプ不要・emu無改修)。

---

## 4. 設計上の論点と決定

### 論点1: SP突合の復帰（本V2-dの核心その1）
- 問題: V2-a〜cは初期SP差ゆえSPを突合除外。C6/C7はSPが主結果なので突合必須。
- 決定: 全ベクタ先頭で LDW SP,#$FC7E 明示初期化 -> SP差を無効化 -> SPを突合対象化。
  - PUSH1回でSP=$FC7C(-2)、POP1回で+2。増減方向をSP突合で直接検証。
  - expected hexにSP列を追加(A,B,X,F,PC,SP の6word/ベクタ)。

### 論点2: スタックデータの検証（核心その2・偽合格防止）
- 問題: PUSHの結果はスタックメモリに出る。SP突合だけでは「積んだ値」が正しいか不明。
- 決定: PUSH->POP往復で積んだ値をレジスタに読み戻し、レジスタ突合で値を検証。
  - 例: A<-0x1234; PUSH A; A<-0; POP A -> Aが0x1234復元ならスタックデータ健全。
  - さらにクロスレジスタ往復(PUSH A; POP B)でデータがレジスタ間で正しく移送されるか、
    SP経由の値搬送を検証(A以外も使いニブル取り違え等を検出)。

### 論点3: JSR/RETのPC退避・復帰（核心その3）
- 問題: JSRはPCをスタックに退避しPCを飛ばす。RETで復帰。PC遷移+スタック副作用の複合。
- 決定: JSR先で既知レジスタ値を書き、RETで戻った後の最終PC・レジスタをPC/レジスタ突合。
  - 構造: init -> JSR sub -> [戻り先: HALT] ; sub:[A<-0xJJJJ; RET]
    JSRでsubへ->A<-0xJJJJ->RETで戻り先(JSR次)へ->HALT。
    最終A=0xJJJJ(sub実行の証拠)、最終PC=戻り先HALT+1、SP=初期値(JSR/RETでpush/pop相殺)。
  - SP相殺確認: JSR(SP-2)とRET(SP+2)で最終SP=初期SPに戻ることを突合(退避/復帰の対称性)。
  - ネストJSR(sub内で更にJSR)を1本入れ、2段退避/復帰を検証(スタック深さ方向)。

### 論点4: エンコーダ追加（ISAに無い命令を作らない）
- push(reg) = [0x1F, sub] sub: PUSH A/B/X=0x00/01/02。
- pop(reg)  = [0x1F, sub] sub: POP A/B/X=0x03/04/05。
- jsr(addr) = [0x68, lo, hi](絶対アドレスLE)。
- ret()     = [0x69]。
- ldw_imm(3, val) で SP(reg3)初期化(既存ldw_immに rd=3 を渡す)。

### 論点5: build_code一般化
- 現状(V2-c): kind別に末尾命令を分岐。
- 変更: C6/C7は "prog"方式(各ベクタが命令列を組む)。V2-cのbranch/mem同様、
  gen側でコード列を組み立て emu23黄金->(A,B,X,F,PC,SP)取得。

### 論点6: 段階承認
- V2-d で新規ベクタ ALL PASS + V2-a/b/c回帰維持 -> レビュー -> V2-e(C8制御割込)へ。

---

## 5. ベクタ設計（暫定・レビューで調整）

### C6 スタック
- PUSH_POP_A: SP初期化; A<-0x1234; PUSH A; A<-0; POP A -> A=0x1234, SP=初期値
- PUSH_POP_B: 同上 B<-0x5678(データ=B, ニブル取り違え検出)
- PUSH_POP_X: 同上 X<-0x9ABC
- CROSS_AB  : A<-0x1111; PUSH A; POP B -> B=0x1111(レジスタ間移送)
- SP_DECR   : SP初期化; PUSH A -> SP=初期-2(増減方向・POPせず)
- SP_INCR   : PUSH A; POP A -> SP=初期値(復帰)
- MULTI_PUSH: A<-v1;B<-v2; PUSH A; PUSH B; POP A; POP B
              -> A=v2,B=v1(LIFO順序検証) ※後入れ先出し
- 計 7本前後

### C7 サブルーチン
- JSR_RET     : JSR sub; [戻り:HALT]; sub:[A<-0xAAAA;RET]
                -> A=0xAAAA, PC=戻りHALT+1, SP=初期値(相殺)
- JSR_SPmove  : JSR先でSP観測(JSR直後SP=初期-2を、sub内でSPをXにコピーし検証)
- NEST_JSR    : JSR s1; s1:[JSR s2; ...; RET]; s2:[A<-0xBBBB; RET]
                -> 2段退避/復帰。最終SP=初期値
- RET_only_chk: PUSH imm(戻り先を手で積む)-> RET -> PCがその値へ(RET単体のpop動作)
- 計 4本前後

（計 C6=7 / C7=4 の 11本 + 既存回帰64 = 75本想定。過不足はレビューで調整）

---

## 6. 成果物（予定）
- gen_v2_vectors_v2d_poc.py（V2-c統合生成器を拡張。_poc先行=KY38）
- tb_cpu_v2d_v0_1.sv（SP突合追加・PUSH/POP往復・JSR/RET突合TB）
- v2d/ 生成ベクタ一式・golden_v2d.txt

---

## 7. 未確定・レビュー確認事項（Q）
- Q1: SP明示初期化値を $FC7E(emu23慣習=スタック領域頂上)とする方針でよいか。
  別の値(例$F87E)が良い理由があれば指摘を仰ぐ。
- Q2: スタックデータ検証を「PUSH->POP読み戻し+レジスタ突合」で行い、
  スタックメモリ番地の直接ダンプはしない方針(V2-c論点5-b応用)でよいか。
- Q3: JSR/RETのSP相殺(最終SP=初期SP)を突合し、退避/復帰の対称性を検証する方針。
  加えてネストJSR(2段)を入れる範囲でよいか、深さ方向をどこまで見るか。
- Q4: SP突合を全ベクタ(既存回帰64本含む)で有効化するか、V2-d新規ベクタのみか。
  (既存64本はSP初期化命令が無く、RTL初期SP=0/emu23=FC7Eで不一致になる。
   -> 既存はSP除外継続、V2-d新規のみSP突合が無難)
- Q5: RET_only_chk(手で戻り先を積んでRET)で、積む値=有効なコード番地にする必要がある
  (RET後そこを実行するため)。HALT配置番地を積む設計でよいか。
- Q6: PUSH/POPが数値上EXT配下0x00-05でトップレベルのHALT(0x01)等と衝突する点、
  gen/TBで 0x1F プレフィックス必須を徹底する確認(V2-cのLDB/STB EXT漏れ再発防止)。
