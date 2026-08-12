# HANDOVER_CHAT77.md (2026-07-10)
## 引継ぎ：V2-d 設計レビュー承認済 → TB実装から再開

- 発行元: 「FPGA実装の継続」(V2-c完了→V2-d設計レビューまで)
- 宛先: V2-d 実装 新チャット
- 対象RTL: ysd8800_cpu_v0_1.sv v0.5.6 / decoder・regfile・alu v0.1
- 黄金: emu23_v109.c (v1.09・★ナレッジ登録済=N-1解消)

---

## 0. 最重要・申し送り

本チャットはツール呼び出しの書式崩れ(生テキスト化)の兆候が出たため、
V2-d 実装着手直前で新チャットへ移行。**V2-d は設計レビュー承認済(Mなし)・
実装未着手**。原則43クリア済、次は gen生成器(_poc)作成から。

書式崩れ回避策(前チャット継続): **応答冒頭でツール呼び出し・長い前置き文の
直後にツールを置かない・1応答1ツール基本**。崩れたら即停止し仕切り直す。

---

## 1. 工程位置

Step 8 FPGA → V2 CPUコア単体検証 → V2-d(C6スタック/C7サブルーチン)
- ✅ V2-a(C1) ALL PASS 20 / V2-b(C2/C3) ALL PASS 41 / V2-c(C4分岐/C5メモリ) ALL PASS 64
- 🔧 V2-d: 設計メモ v0.1 → レビュー承認(v2d_design_review_reply_v1_0.docx) → 実装着手直前で中断
- ⬜ V2-e(C8制御割込 EI/DI/SYSCALL/IRET/割込受理) は V2-d完了後
- スコープ: C6スタック+C7サブルーチンの2グループ(C8はV2-eへ独立・確定済)

---

## 2. V2-d レビュー結果(承認・Mなし)

総合承認。命令仕様・SP方向・JSR/RET・初期SP全て実装一致。反映事項:
- **Q5是正**: PUSH #imm は存在しない(PUSHはレジスタA/B/Xのみ)。RET_only_chkは
  「戻り先番地をLDWでレジスタに入れ→PUSH→RET」の構造。積む値=HALT配置番地。
- **Q6最重要**: push/popエンコーダは必ず [0x1F, sub] 2バイトを吐く。
  _pocでPUSH命令先頭バイト=0x1F をassert/目視確認(EXT漏れ再発防止)。
- **Q1補足**: メモに「$FC7E=emu素環境 / $F87E=YUI OS運用時memmap」の区別を1行付記。
- C-2: JSR_SPmoveのSP→X転送は MOV X,SP=[0x20,0x23] で可能(実照合済)。
- Q1〜Q4/Q6承認、Q4=V2-d新規のみSP突合(既存64はSP除外継続)。

---

## 3. V2-d 設計確定事項(実照合済 emu23_v109)

### 対象命令エンコード
- C6 PUSH/POP: ★EXT方式★ [0x1F, sub]
  PUSH A/B/X = 1F 00 / 1F 01 / 1F 02
  POP  A/B/X = 1F 03 / 1F 04 / 1F 05
  (トップレベル0x00-05=NOP/HALT/EI/DI/IRET/SYSCALLとは別命令。EXT漏れ厳禁)
- push16/pop16: SP-=2;wr16 / rd16;SP+=2 (pre-dec push/post-inc pop・6809同方向)
- C7: JSR imm16 = [0x68, lo, hi] (絶対アドレス・push16(next PC)後 PC<-imm)
      RET = [0x69] (PC<-pop16)
- JSR/RET/PUSH/POP は FLAGS不変
- 補助: LDW SP,#imm = [0x21, 0x30, lo, hi] (SP=reg3上位) でSP初期化
        MOV X,SP = [0x20, 0x23] でSP観測(JSR_SPmove用)

### SP初期値問題(決着済)
- emu23初期SP=0xFC7E(L1909) / RTLリセットSP=0x0000(regfile L92)
- 対策: 各ベクタ先頭で LDW SP,#$FC7E 明示初期化 → 差を無効化 → SPを突合復帰
- RTL/emu23とも汎用ポートSP書込有効(実照合済)

### 検証方式(V2-c踏襲+SP突合)
- 単一ソース生成・emu23黄金自動取得(手計算せず)
- PC観測点=実行後サマリ行(FLAGS=形式・HALT後PC)採取 →RTL dbg_pc一致
  (V2-cで確立: emu_goldenはFLAGS=行優先。expected hexは今回 A,B,X,F,PC,SP の6word)
- 突合対象に SP追加(6点突合)。V2-d新規のみ。既存64はSP除外のまま。
- スタックデータ検証: PUSH→POP読み戻し+レジスタ突合(emu無改修・KY38)

### ベクタ設計(暫定・設計メモ§5)
- C6(7本): PUSH_POP_A/B/X, CROSS_AB, SP_DECR, SP_INCR, MULTI_PUSH(LIFO)
- C7(4本): JSR_RET, JSR_SPmove(MOV X,SP), NEST_JSR(2段), RET_only_chk
- 計11本 + 既存回帰64 = 75本想定

---

## 4. 環境再現手順(セッション揮発対策)

作業DIR /home/claude/v1_rtl/ は揮発。再現:
1. ツール操作ガイド確認・工程確認・KY活動(作業開始プロトコル)
2. iverilog導入: apt-get install -y iverilog
3. /mnt/project/ から作業DIRへcp:
   ysd8800_{decoder,regfile,alu,cpu}_v0_1.sv, emu23_v109.c
   gen_v2_vectors_v2c_poc.py, tb_cpu_v2c_v0_1.sv (V2-c土台)
   ※V2-c成果物はプロジェクトナレッジ登録要(未登録なら本HANDOVER添付から)
4. emu23ビルド: gcc -O2 -o emu23 emu23_v109.c
5. コンパイル順は必ず decoder先頭:
   iverilog -g2012 -o sim decoder regfile alu cpu tb (この順)
6. V2-c回帰でALL PASS(64)を確認し土台健全性を裏取り

---

## 5. 次チャットの再開手順

1. 作業開始プロトコル(ガイド確認/工程確認「次工程の確認ヨシ!」/KY活動)
2. 環境再現(§4)・V2-c回帰でALL PASS(64)裏取り
3. gen_v2_vectors_v2c_poc.py をベースに V2-d生成器 _poc 作成
   (§3確定仕様・Q5是正・Q6のEXT徹底[push/pop先頭0x1F assert]・C-2のMOV活用)
4. v2dベクタ生成・golden取得(emu23黄金・6word:A,B,X,F,PC,SP)
   → tb_cpu_v2d_v0_1.sv 作成(SP突合追加) → コンパイル→実行→ALL PASS
5. V2-a/b/c回帰維持も確認 → V2-d完了 → レビュー → V2-e(C8)へ

---

## 6. V2-d完了時のまとめ反映(持ち越しPDCA-Act・累積)

- 設計メモ改版: v2b/v2c/v2d を v1.0化(KY41・4点整合)
  - v2c: LDB/STB EXT方式訂正・M-1(STW下位ニブル)・PC観測点方針
  - v2d: Q1補足($FC7E/$F87E区別)・Q5構造・Q6注記
- kaizen.txt追記候補(未反映・累積):
  - LDB/STB・PUSH/POPはEXT(0x1F)配下(ISA表のopcode列=サブop空間の罠)
  - PC観測点: emu実行前トレース vs RTL(HALT後・フェッチ先行インクリメント)
    →黄金は実行後サマリ行採取
  - vvp判定は grep -c FAIL / grep FAIL で全件確認(tail厳禁・見落とし防止)
  - ツール書式崩れ再発防止(応答冒頭ツール・前置き直後回避・1応答1ツール)
- tool_version_ledger更新: gen_v2c/tb_v2c/(v2d成果物)登録
- 進捗報告(latest 4b67e76b)へ 2026-07-09/07-10 分日報記載
- N-1解消済(emu23_v109ナレッジ登録)を台帳へ反映

---

## 7. 注意

- scc23 Phase 1〜6 は承認済・FPGA優先で意図的延期(停滞ではない)
- V2-c成果物(gen_v2_vectors_v2c_poc.py/tb_cpu_v2c_v0_1.sv/golden/expected/veclist)
  と V2-b成果物 が未だプロジェクトナレッジ未登録の可能性。登録要確認。
