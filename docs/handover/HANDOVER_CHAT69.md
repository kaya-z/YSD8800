# HANDOVER_CHAT69.md — Step 8 FPGA V0完了・V1設計完了（RTL実装直前）

| 項目 | 内容 |
|---|---|
| 作成日 | 2026-06-30 |
| 前チャット | HANDOVER_CHAT68（V(-1) emu23 v1.08 MMU復活完了） |
| 本チャット成果 | **Step 8 FPGA V0完了 + V1（CPUコアFSM）設計完了**。次は RTL(.sv) 実装 |
| 次チャットの目的 | **V1 CPUコア SystemVerilog 実装**（設計承認済・原則43クリア） |
| 重要 | ログ肥大で antml: プレフィックス書式崩れが起きるため RTL実装は新チャットで実施（本HANDOVERはその引継ぎ） |

---

## 0. 次チャット冒頭でやること（順守）

1. 本HANDOVER（CHAT69）を読む
2. claude_tool_operation_guide_v1_0.txt を1回参照（規律1〜5。特に**規律2：ヒアドキュメント禁止・create_file/str_replace使用**）
3. 工程確認（マスターチャット「進捗と予定の確認(latest)」最新照合）→「工程ヨシ！」
4. KY活動1件→「ご安全に！」
5. 作業開始の合図を待つ
6. **ファイル出力操作は新チャット冒頭（context蓄積前）に実施**＝書式崩れ予防（userMemory既知対処）

---

## 1. 本チャットの到達点（2026-06-30）

### 1.1 完了したフェーズ
- **Step 8 FPGA V0 完了**：実装仕様書 `fpga_v0_impl_spec_v1_1.md`（本体・レビュー承認クローズ）
- **Step 8 FPGA V1 設計完了**：
  - 骨子 `fpga_v1_cpucore_design_skeleton_v1_1.md`（3レビュー周回でクローズ）
  - 本体 `fpga_v1_cpucore_design_v1_1.md`（**レビュー条件付き承認→M-1是正でクローズ。RTL着手可**）

### 1.2 次工程
**V1 CPUコア SystemVerilog 実装**（fpga_v1_cpucore_design_v1_1.md に忠実に書く）。RTL設計承認済なので原則43はクリア済み、実装に進んでよい。

---

## 2. RTL実装の絶対前提（V1本体 fpga_v1_cpucore_design_v1_1.md より）

### 2.1 正解リファレンス
- **黄金リファレンス＝emu23 v1.08（emu23_v108.c）**：外部観測等価の正解。`exec_one()` L1089-。
- **ISA真実＝ISA2_3_v231.docx**。
- 検証：emu23 `-n N`（Nステップ実行＋トレースダンプ、非対話）で golden 生成。**emu23 v1.08 に `-it` は無い**（v1.09追加の対話モード）。トレース形式 `PC=%04x A=%04x B=%04x X=%04x SP=%04x F=%02x`（L1534）。逆アセンブル列は diff 対象外。

### 2.2 レジスタ（M-1：最重要・実照合確定）
- 6本：A/B/X/SP/PC/FLAGS（各16bit）。
- **rD/rSフィールドで指定可能なのは 0=A/1=B/2=X/3=SP の4本のみ**。`get_reg_ptr()`（L1024-1032）は **default=NULL**で 4(PC)/5(FLAGS)は指定不可＝渡すと no-op。
- **RTLはデコーダで rD/rS∈{4,5} のライトポートを抑止**（no-op化）。6本全部をrD/rSに繋ぐとemu23と乖離。
- PC/FLAGSは専用パス（分岐・FETCH・割込受理・IRET・set_zn）でのみ更新。
- オペランドバイト rb：rD=rb[7:4], rS=rb[3:0]（L1227-1228）。

### 2.3 FLAGS（LV-2確定）
- bit0=Z / bit1=N / bit7=IE のみ有効（**C/Vフラグ無し**）。他ビット0保持。
- **16bit幅で保持**（push16/pop16が16bit）。**IRET時のみ下位8bitマスク復元**（emu23 `(uint8_t)pop16()`、L1135）。

### 2.4 ALU（LV-1クローズ）
- キャリー線・オーバーフロー線を持たない。生成は Z/N のみ（set_zn相当）。
- シフト SHL/SHR/SAR：こぼれビット破棄、シフト量 rs&0x0F（L1387-1420）。MUL/DIV無し。

### 2.5 フラグ更新有無（実照合・類推厳禁）
| 命令群 | フラグ | 根拠 |
|---|---|---|
| ADD/SUB/AND/OR/XOR/NOT/SHL/SHR/SAR（+即値版） | Z/N更新 | set_zn |
| CMP/CMPI | Z/N更新（**結果は書かない**） | set_zn(*rd-*rs) L1326 |
| **MOV(0x20)** | **不変** | *rd=*rs のみ L1229 |
| LDW（0x21/22/24/26 ロード系） | Z/N更新 | set_zn(*rd) |
| **LDB/STB（0x1F 0x10-0x17）** | **不変** | バイト転送 |
| STW（0x23/25/27 ストア系） | **不変** | wr16のみ |

### 2.6 命令フォーマット・デコード
- FETCH：ir=fetch8(pc++)（opcode 1バイト、PC+1）。
- レジスタ命令：rb=fetch8(pc++)。即値命令：imm16=fetch16(pc); pc+=2。
- **EXT 0x1F**：続く1バイトをサブopcodeに（0x00-0x05=PUSH/POP A/B/X、0x10-0x17=LDB/STB）。**0x1Fデコードは必須**（PUSH/POP/LDB/STBの8命令が経由、LV-4）。
- opcode 4グループ：Control/System(0x00-0x1F)・DataTransfer(0x20-0x3F)・Arith-Logic(0x40-0x5F)・Branch-Flow(0x60-0x7F)。

### 2.7 割り込み（V0本体§5.2・最重要）
- **irq_pending ∈ {1,2,3,4}**（ISA§8.1ベクタ番号と恒等。timer=1/device=2/align=3/syscall=4）。ベクタ=`rd16(pending×2)`。
- **「irq0だからpending=0」と名称数字で実装するとベクタ2バイトずれ＝全割込誤ベクタ。厳禁**。
- 受理：PC push→FLAGS push→IE=0→PC=rd16(pending×2)→pending clear（L1096-1104）。
- IRET：FLAGS pop（下位8bit）→PC pop（逆順、L1133-1136）。
- reset：`PC=rd16($0000)` 間接ベクタ（pending経由でない別系統、L1809）。
- **timer_in_service（L1098）はRTL非写像**＝ソフト固有。タイマー1段ラッチで等価（V0本体§5.1/§5.3）。

### 2.8 スタック（実照合確定）
- **push16：SP-=2（pre-dec）→wr16**。**pop16：rd16→SP+=2（post-inc）**（L752-761）。MC6809と同方式。
- PUSH/POP対象は **A/B/X の3本のみ**。SP/PC/FLAGSの汎用push/pop無し。
- SPは常に偶数維持（±2）→スタックアクセスはalign例外を踏まない。

### 2.9 メモリ・バス（V0本体§7・LV-3確定）
- **メインメモリ＝PSRAM（64Mbit）**。BSRAM(468Kbit)は将来キャッシュ用に温存。
- **byte-enable方式（バイトアドレッサブル）**。8bit LDB/STB命令が奇数アドレスにアクセスするため16bitワード単位BRAM不適。
- **抽象バス＝8bitデータ幅**（mem_addr[15:0]/mem_wdata[7:0]/mem_rdata[7:0]/mem_rd/mem_wr/mem_ready）。16bitアクセスは8bit×2（lo=addr, hi=addr+1、リトルエンディアン）。
- **align例外**：16bitアクセスでaddr[0]==1なら irq_pending=3 セットしアクセス中断（read/write両系、L496-498/L565-567）。8bitアクセスはalign対象外。

### 2.10 メモリマップ（V0本体§4）
- $0000-$3FFF：ベクタ＋カーネルコード（write禁止前提）
- $4000-$50FF：カーネルRAM / $5100-$EFFF：Forth辞書等 / $F000-$FBFF：スタック / $FC00-$FC7F：guard+共有変数
- MMIO $FC80-$FFFF（RAM禁止）：UART$FC80/Timer$FC90/Storage$FCA0/IRQ-Ctrl$FCB2/**MMU PTR[16]@$FF00-$FF0F・MCR@$FF10**

---

## 3. FSM設計（V1本体§6・実装の骨格）

```
S_RESET → S_IRQCHK → S_FETCH → S_OPFETCH → S_DECODE → S_EXEC_* → S_WRITEBACK → (S_IRQCHK)
```
- S_RESET：PC=rd16($0000)、FLAGS=0、SP初期化、irq_pending=-1
- S_IRQCHK：`irq_pending>=0 && (FLAGS&IE)` → S_IRQ_ACCEPT、else S_FETCH
- メモリアクセス状態：mem_ready待ち（多サイクル、PSRAMレイテンシ吸収）
- クラス別状態数：A≈3 / B≈5 / C≈6-8 / D≈8-12

詳細な状態遷移（割込受理・IRET・SYSCALL・クラス別・タイマー1段ラッチ）は **fpga_v1_cpucore_design_v1_1.md §6 を必ず参照**。

---

## 4. 命令一覧（53 case・V1本体§5.3）

- **クラスA（レジスタ内完結）**：NOP/HALT/EI/DI/BRK/MOV/ADD/SUB/CMP/AND/OR/XOR/NOT/SHL/SHR/SAR/PUSH/POP
- **クラスB（imm16追加）**：LDW#/ADDI/SUBI/CMPI/ANDI/ORI/XORI/JMP/BEQ/BNE/BLT/BGE
- **クラスC（メモリ）**：LDB/STB×8 / LDW[imm]/STW[imm]/LDW[rS]/STW[rD]/LDW[X+imm]/STW[X+imm]
- **クラスD（制御）**：IRET/SYSCALL/JSR/RET＋割込受理
- 分岐4命令：BEQ(0x61,Z=1)/BNE(0x62,Z=0)/BLT(0x63,N=1)/BGE(0x64,N=0)。Z/Nのみ、Cフラグ非依存。

---

## 5. RTL実装の進め方（推奨）

原則43は設計承認済でクリア。実装は以下の順が安全（V1本体§8 検証設計）：
1. **環境スモークテスト**：iverilog 12.0（-g2012）/vvp で always_comb/always_ff/logic/$readmemh が通るか最小TBで実証
2. **レジスタファイル＋デコーダ**（M-1：rD/rS 0-3のみ有効、4/5抑止を最初に作り込む）
3. **ALU**（フラグ更新イネーブル線。MOV不変/CMP結果非書込/LDW更新を正確に）
4. **FSMコア**（FETCH→DECODE→EXEC）＋抽象バス（8bit、固定レイテンシTBメモリ）
5. **命令別TB**：53 case を emu23 `-n 1` 突合。MOV/CMP/LDW を最優先（取り違え検出力高）
6. 割込受理・IRET・SYSCALL経路のTB
7. D-3（分岐Z/N網羅）、rD/rS=4,5のno-op確認TB

**命名**：ysd8800_<機能>_v0_1.sv（V0本体§9.1）。合成RTLは$不使用、TBは$可。

---

## 6. KY教訓（本チャット3日間で繰り返し露呈・次チャット最重要）

**本プロジェクト最大の事故源は「emu23実ソースを実照合せず、類推・推測で設計を書くこと」**。本チャットで以下が連続発生し、全てレビューまたは指摘で是正された：

| 誤り | 正 | 教訓 |
|---|---|---|
| V0本体§3.4 opcode帯分類（LDB/STB=DataTransfer帯と誤記） | 実はControl/System帯sub-op | 分類は必ずswitch実体を見る |
| V1骨子 -it=対話モードと記述 | v1.08に-it自体が無い（v1.09追加） | バージョン別機能を実照合 |
| V1骨子 LV-4「0x1F未使用なら後回し」 | 0x1Fデコードは必須（PUSH/POP/LDB/STB経由） | 類推で優先度を決めない |
| V1本体§3.1 レジスタ番号4=PC/5=FLAGS指定可 | get_reg_ptrでdefault=NULL、4/5指定不可 | レジスタ番号すら実照合 |

**次チャットの鉄則**：命令・レジスタ・アドレスを書く前に、必ず emu23_v108.c の該当箇所を行番号付きで実照合（KY34）。「たぶんこう」で書かない。RTL実装は誤りが回路の根幹に入るため、設計書以上に実照合が命綱。

---

## 7. 関連文書（次チャットで参照すべきもの）

| 文書 | 用途 |
|---|---|
| **fpga_v1_cpucore_design_v1_1.md** | **V1実装の設計図（最重要・これに忠実に書く）** |
| fpga_v0_impl_spec_v1_1.md | V0実装仕様（メモリ/バス/ボード/クロック前提） |
| emu23_v108.c | 黄金リファレンス（全実照合元） |
| ISA2_3_v231.docx | ISA真実 |
| yuios_memmap_design_v2_4.md | メモリマップ詳細 |
| claude_tool_operation_guide_v1_0.txt | ツール操作規律 |
| kaizen.txt | 設計・デバッグ原則 |

※ V1本体v1.1・V0本体v1.1・V1骨子v1.1 は outputs に実在（版数台帳整合済）。

---

## 8. ツール版数（現況）
- emu23 v1.09（-it対話。ただし**突合は v1.08 同梱 -n を使う**＝黄金リファレンスはv1.08）
- scc23 v2.02 / hasm23 v1.04 / lnk23 v2.01 / Force v1.5 / disasm23 v1.00
- 並行トラック：scc23ピープホールP1（高リスク・197箇所・設計準備中、別チャット進行）
- FPGA検証：Icarus Verilog 12.0（-g2012/vvp）、合成=Gowin IDE想定

---

## 9. ロードマップ現況（2026-06-30）
- ✅ V(-1) emu23 MMU復活 / ✅ V0 実装仕様 / ✅ V1 CPUコアFSM設計
- 🔧 **V1 RTL実装** ← 次チャット
- ⬜ V2（メモリ/バス・PSRAM ctrl）/ V3（割込・タイマー）/ V3.5（MMU）/ V4-（デバイス）/ V7-8（統合・ブート）/ VD（実機Tang Nano 9K）
- ⬜ Ph.7（FAT12・将来）/ Ph.8（MMU連携Level2・将来）※削除禁止

---

## 10. 本日のKY記録（2026-06-30）
- 危険：命令を実照合せず類推でFSM状態表を埋める
- 防止策：命令ごとにemu23ハンドラを実照合（フェッチ数/mem有無/フラグ/SP操作の4点）してから状態割付
- 結果：的中（M-1レジスタ番号・LV-4で類推の罠に踏みかけ、実照合で是正）。次チャットも同じ危険が最大リスク。
