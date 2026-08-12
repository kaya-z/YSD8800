# YSD8800 FPGA V1 CPUコア実装設計書 v1.0（本体）

| 項目 | 内容 |
|---|---|
| 文書名 | fpga_v1_cpucore_design_v1_1.md |
| 版数 | **v1.1（レビュー反映・本体クローズ）** |
| 作成日 | 2026-06-30（v1.0）／改版 2026-06-30（v1.1） |
| 対象工程 | Step 8 FPGA SystemVerilog 実装 V1（CPUコア実装FSM） |
| 入力（承認済骨子） | fpga_v1_cpucore_design_skeleton_v1_1.md（骨子クローズ済） |
| 完了条件（V1工程） | ISA2_3_v231 全命令（53 case）の単体TBが emu23 v1.08 と一致 |
| 正解リファレンス | 黄金リファレンス＝emu23 v1.08 `exec_one()`（L1089-）／ ISA真実＝ISA2_3_v231.docx |
| Ref | ISA2_3_v231 / emu23_v108.c / fpga_v0_impl_spec_v1_1.md（V0本体最新正式版） |
| スコープ | CPUコアの多サイクルFSM設計。PSRAM物理実装=V2／MMU=V3.5／デバイス=V4以降 |

---

## 第Ⅰ部：総則

### 1. 目的とスコープ

#### 1.1 目的
emu23 v1.08 の `exec_one()` と外部観測等価な YSD8800 CPUコアを、多サイクル・ステートマシンとして SystemVerilog で実装するための設計を確定する。本書の承認後に RTL（.sv）実装へ進む（原則43）。

#### 1.2 スコープ境界
- **V1 が設計するもの**：命令フェッチ／デコード／実行／メモリアクセス要求の FSM、レジスタファイル（A/B/X/SP/PC/FLAGS）、ALU、分岐ユニット、割り込み受理 FSM、抽象バス I/F。
- **V1 が設計しないもの（V2 以降）**：PSRAM コントローラ物理実装（V2）、MMU 変換（V3.5）、デバイス MMIO（V4-）。V1 の TB は固定レイテンシのビヘイビアメモリで実メモリを代替する。

#### 1.3 正解リファレンス
emu23 v1.08 `exec_one()`（L1089-）。ISA真実＝ISA2_3_v231。本書の全命令仕様は emu23 ハンドラを行番号付きで実照合して確定した（KY34）。

---

### 2. 全体方針

#### 2.1 多サイクル FSM 方針
1命令を複数状態に分解し、状態ごとに1クロックを消費する（V0本体 §2.1 継承）。

#### 2.2 emu23 exec_one の3段階構造（FSM 骨格）
emu23 の1命令処理は次の3段階（L1094-1115 実照合）。これを FSM の骨格とする。

1. **(A) IRQ受理チェック**：`irq_pending>=0 && (FLAGS&IE)` なら割り込み受理シーケンスへ（§6.2）。
2. **(B) FETCH**：`ir = fetch8(pc++)`（オペコード1バイト取得、PC を +1）。追加オペランド（オペランドバイト rb・imm16）は各命令の状態内で後続フェッチする。
3. **(C) DECODE/EXEC**：`switch(ir)` で命令ごとの処理。

#### 2.3 抽象バス I/F 方針
V1 では `mem_addr/mem_wdata/mem_rdata/mem_rd/mem_wr/mem_ready` の抽象バス（byte 粒度）を定義（§7）。PSRAM 実レイテンシは V2、V1 TB は固定レイテンシのビヘイビアメモリ。

---

## 第Ⅱ部：CPUコア アーキテクチャ設計

### 3. レジスタファイル

#### 3.1 構成とレジスタ番号（M-1 実照合是正）
A/B/X/SP/PC/FLAGS の6本、各16bit。レジスタは物理的に6本存在するが、**命令の rD/rS フィールドで指定できるのは 0=A / 1=B / 2=X / 3=SP の4本のみ**。emu23 `get_reg_ptr()`（L1024-1032）は case 0:A / 1:B / 2:X / 3:SP / **default:NULL** で、**番号4(PC)/5(FLAGS)は NULL を返す**（コメントも「0=A 1=B 2=X 3=SP」と明記）。全レジスタ命令は `if(rd && rs)`（または `if(rd)`）でガードされ、rD/rS=4,5 を与えると get_reg_ptr が NULL を返し当該命令は**何も書かず break（no-op）**する（MOV L1229/CMP L1326/LDW L1236 等）。

- **PC・FLAGS は汎用オペランド経路では触れない**。PC は分岐/JMP/JSR/RET/IRET/FETCH、FLAGS は演算の set_zn と割り込み/IRET でのみ更新される（専用パス）。
- **RTL 含意（重要）**：レジスタファイルを6本持つこと自体は可だが、**デコーダで rD/rS∈{4,5} のとき汎用ライトポートをイネーブルしない（no-op 化）**こと。6本すべてを rD/rS で読み書き可に実装すると、4/5 指定時に emu23（no-op）と外部観測が分かれる（§3.3/§7.1 で担保）。

命令のオペランドバイト `rb` は上位4bit=rD、下位4bit=rS（emu23 全レジスタ命令で共通、L1227-1228 実照合）。

#### 3.2 FLAGS の実装幅（LV-2 確定）
**FLAGS は 16bit 幅で保持する**（3bit 圧縮実装は採らない）。確定根拠：emu23 は `cpu.flags`（16bit）を push16/pop16 でスタックに退避・復帰する（割り込み受理・IRET、§6.2/§6.3）。RTL も割り込みで FLAGS を 16bit 幅でスタック push/pop するため、16bit 保持の方がスタック操作と素直に整合する（3bit 実装だと push 時にゼロ拡張ロジックが余分に要る）。有効ビットは Z(bit0)/N(bit1)/IE(bit7) のみで、他ビットは 0 を保持する（V0本体 §3.2）。

#### 3.3 レジスタ書き込みポートの競合整理
書き込み発生源は (a) FETCH 段の PC++、(b) EXEC 段のレジスタ更新（rD・FLAGS）、(c) 割り込み/JSR/RET の SP 操作。多サイクル方式のため同一クロックでの競合は原則生じない（各状態で1書き込み）。PC は FETCH 段でのみ +1、分岐/JMP/JSR/RET/IRET の EXEC 段でのみ書き換える。
- **【C-3 M-1担保】** rD/rS デコードで **4(PC)/5(FLAGS) は汎用ライトポートをイネーブルしない**（no-op）。PC/FLAGS は専用パス（分岐・FETCH・割り込み受理 FSM・IRET・set_zn）でのみ更新する。これにより emu23 の「rD/rS=4,5 → no-op」と外部観測等価を保つ。

---

### 4. ALU

#### 4.1 演算種別
Arith-Logic 帯（0x40-0x5F）の全演算（emu23 実照合）：ADD/ADDI/SUB/SUBI/CMP/CMPI/AND/ANDI/OR/ORI/XOR/XORI/NOT/SHL/SHR/SAR。MUL/DIV 等は存在しない。

#### 4.2 フラグ生成（C/V 無し・LV-1 クローズ済）
**ALU はキャリー線・オーバーフロー線を持たない**。生成するのは Z（結果==0）と N（結果 bit15）のみ。emu23 の `set_zn(result)` がこれに相当する。シフト SHL(0x57)/SHR(0x58)/SAR(0x59) は**こぼれビットを破棄**し、シフト量は `rs & 0x0F`（下位4bit）（L1387-1420 実照合）。乗算はソフトランタイム（ISA外）。

#### 4.3 命令ごとのフラグ更新有無（実照合・最重要）
フラグ更新は命令ごとに異なる。**類推不可・emu23 ハンドラ実照合で確定**（KY34）。

| 命令群 | フラグ更新 | 根拠（emu23） |
|---|---|---|
| ADD/ADDI/SUB/SUBI/AND/ANDI/OR/ORI/XOR/XORI/NOT/SHL/SHR/SAR | **Z/N 更新** | `演算; set_zn(*rd)`（L1298 等） |
| CMP/CMPI | **Z/N 更新（結果は書かない）** | `set_zn(*rd - *rs)` のみ（L1326） |
| **MOV（レジスタ間 0x20）** | **不変** | `*rd = *rs` のみ、set_zn なし（L1229） |
| LDW #imm/[imm16]/[rS]/[X+imm]（0x21-0x27 のロード系） | **Z/N 更新** | `*rd = …; set_zn(*rd)`（L1236/L1243 等） |
| **LDB/STB（0x1F 0x10-0x17）** | **不変** | バイト転送、set_zn なし（V0本体 §3.4 実照合） |
| STW（ストア系 0x23/0x25/0x27） | **不変** | メモリ書込のみ、レジスタ・フラグ不変 |

**設計含意**：RTL の ALU/転送ユニットは「フラグ更新イネーブル」線を命令デコードで制御する。MOV とロード（LDW）でフラグ挙動が分かれる点、CMP は結果を書かずフラグのみ更新する点が、特に取り違えやすい。

---

### 5. 命令デコードと分類

#### 5.1 デコード方式
FETCH で opcode 1バイト（`ir=fetch8(pc++)`、L1111）。レジスタ命令は続いてオペランドバイト `rb=fetch8(pc++)`（rD=rb>>4, rS=rb&0x0F）。即値命令はさらに `imm16=fetch16(pc); pc+=2`。EXT プリフィックス 0x1F は2バイト目をサブopcodeとして再 switch（PUSH/POP/LDB/STB、L1162 系）。

#### 5.2 EXT プリフィックス 0x1F
opcode 0x1F を読むと、続く1バイトをサブopcodeとしてデコードする（emu23 は 0x1F ケース内で `sub=fetch8(pc++)` し内側 switch）。サブopcード：0x00-0x05=PUSH/POP、0x10-0x17=LDB/STB。LV-4（yuios.bin での 0x1F 実使用実績）は §10 参照。

#### 5.3 命令分類表（53 case・emu23 switch 実照合）
全命令を「必要状態数」でクラス分類する。FETCH 段数・メモリアクセス・SP操作・フラグ更新を実照合で確定。

**クラスA：レジスタ内完結（FETCH + 1 EXEC）**

| opcode | 命令 | フラグ | 備考 |
|---|---|---|---|
| 0x00 | NOP | 不変 | 何もしない |
| 0x01 | HALT | 不変 | 停止 |
| 0x02 | EI | IE←1 | 割り込み許可 |
| 0x03 | DI | IE←0 | 割り込み禁止 |
| 0x06 | BRK | 不変 | デバッグトラップ |
| 0x20 | MOV rD,rS | **不変** | `*rd=*rs` |
| 0x40 | ADD rD,rS | Z/N | |
| 0x42 | SUB rD,rS | Z/N | |
| 0x44 | CMP rD,rS | Z/N（書かない） | |
| 0x50 | AND rD,rS | Z/N | |
| 0x52 | OR rD,rS | Z/N | |
| 0x54 | XOR rD,rS | Z/N | |
| 0x56 | NOT rD | Z/N | ビット反転 |
| 0x57 | SHL rD,rS | Z/N | こぼれ破棄 |
| 0x58 | SHR rD,rS | Z/N | 0埋め |
| 0x59 | SAR rD,rS | Z/N | 符号保持 |
| 0x1F/0x00-0x02 | PUSH A/B/X | 不変 | SP操作（クラスC的だが値源はレジスタ） |
| 0x1F/0x03-0x05 | POP A/B/X | 不変 | SP操作 |

**クラスB：imm16 追加フェッチ（FETCH + オペランド + imm16 + EXEC）**

| opcode | 命令 | フラグ | 備考 |
|---|---|---|---|
| 0x21 | LDW rD,#imm16 | Z/N | |
| 0x41 | ADDI rD,#imm16 | Z/N | |
| 0x43 | SUBI rD,#imm16 | Z/N | |
| 0x45 | CMPI rD,#imm16 | Z/N（書かない） | |
| 0x51 | ANDI rD,#imm16 | Z/N | |
| 0x53 | ORI rD,#imm16 | Z/N | |
| 0x55 | XORI rD,#imm16 | Z/N | |
| 0x60 | JMP rel16 | 不変 | PC 相対 |
| 0x61 | BEQ rel16 | 不変 | Z=1 で分岐 |
| 0x62 | BNE rel16 | 不変 | Z=0 で分岐 |
| 0x63 | BLT rel16 | 不変 | N=1 で分岐 |
| 0x64 | BGE rel16 | 不変 | N=0 で分岐 |

**クラスC：メモリアクセス（FETCH + … + メモリ wait 段）**

| opcode | 命令 | アクセス | フラグ |
|---|---|---|---|
| 0x1F/0x10 | LDB A,[imm16] | rd8 | 不変 |
| 0x1F/0x11 | LDB A,[X] | rd8 | 不変 |
| 0x1F/0x12 | LDB B,[imm16] | rd8 | 不変 |
| 0x1F/0x13 | LDB B,[X] | rd8 | 不変 |
| 0x1F/0x14 | STB A,[imm16] | wr8 | 不変 |
| 0x1F/0x15 | STB A,[X] | wr8 | 不変 |
| 0x1F/0x16 | STB B,[imm16] | wr8 | 不変 |
| 0x1F/0x17 | STB B,[X] | wr8 | 不変 |
| 0x22 | LDW rD,[imm16] | rd16 | Z/N |
| 0x23 | STW rS,[imm16] | wr16 | 不変 |
| 0x24 | LDW rD,[rS] | rd16 | Z/N |
| 0x25 | STW rS,[rD] | wr16 | 不変 |
| 0x26 | LDW rD,[X+imm16] | rd16 | Z/N |
| 0x27 | STW rS,[X+imm16] | wr16 | 不変 |

**クラスD：制御フロー・多段スタック**

| opcode | 命令 | 動作 | フラグ |
|---|---|---|---|
| 0x04 | IRET | FLAGS←pop / PC←pop（§6.3） | FLAGS←(uint8_t)pop16() 下位8bit復元 |
| 0x05 | SYSCALL | A=番号、IRQ4 発火（§6.4） | — |
| 0x68 | JSR imm16 | PC push / PC←imm16 | 不変 |
| 0x69 | RET | PC←pop | 不変 |
| （割り込み受理） | — | PC push/FLAGS push/IE=0/PC←vec（§6.2） | IE←0 |

#### 5.4 各クラスの状態数見積もり（§6 で詳細）
- クラスA：FETCH(1)+OPFETCH(1)+EXEC(1) ≈ 3 状態
- クラスB：上記＋IMM16フェッチ（byte×2 = 2状態）≈ 5 状態
- クラスC：上記＋メモリアクセス wait（rd16/wr16 はbyte×2）≈ 6-8 状態
- クラスD：スタック push/pop の byte×2 を複数回 ≈ 8-12 状態（IRET は FLAGS+PC の2ワード pop）

---

### 6. FSM 状態遷移設計（V1 の核心）

#### 6.1 トップレベル状態
1命令の処理を以下の状態列で表す。多サイクル方式のため各状態は1クロック消費（メモリ wait は ready まで滞留）。

```
S_RESET → S_IRQCHK → S_FETCH → S_OPFETCH → S_DECODE
                ↑                              ↓
                └────── S_WRITEBACK ←── S_EXEC_* (命令クラス別)
```

- **S_RESET**：reset 解除後、`PC ← rd16($0000)`（間接ベクタ、V0本体 §8.2）。FLAGS=0、SP 初期化、irq_pending=-1。完了後 S_IRQCHK へ。
- **S_IRQCHK**：`irq_pending>=0 && (FLAGS&IE)` なら S_IRQ_ACCEPT（§6.2）へ。さもなくば S_FETCH。
- **S_FETCH**：`ir ← mem[PC]`（byte 読み）、`PC ← PC+1`。バス wait あり。
- **S_OPFETCH**：レジスタ命令なら `rb ← mem[PC]`、`PC←PC+1`（rD=rb[7:4], rS=rb[3:0]）。オペランド不要命令（NOP 等）はスキップ。
- **S_DECODE**：`ir`（と 0x1F の場合サブopcode）で分岐先 S_EXEC_* を決定。
- **S_EXEC_***：命令クラス別の実行（§6.5）。
- **S_WRITEBACK**：rD・FLAGS 更新。次命令へ（S_IRQCHK）。

#### 6.2 割り込み受理 FSM（S_IRQ_ACCEPT）
emu23 受理シーケンス（L1096-1104 実照合）を状態列にする。

1. `SP ← SP-2; mem[SP..SP+1] ← PC`（PC を push・16bit＝byte×2、pre-decrement）
2. `SP ← SP-2; mem[SP..SP+1] ← FLAGS`（FLAGS を push・16bit）
3. `FLAGS[IE] ← 0`（多重割り込み禁止）
4. `PC ← rd16(irq_pending × 2)`（ベクタテーブルから飛び先・byte×2 読み）
5. `irq_pending ← クリア`、S_FETCH へ

- **pending 体系**：irq_pending ∈ {1,2,3,4}、ベクタ＝pending×2（V0本体 §5.2 厳守）。**名称数字で実装しない**（ベクタ2バイトずれ厳禁）。
- **reset は別系統**：reset はベクタ番号0だが pending 経由でなく S_RESET で処理（V0本体 §8.2）。
- **【N-1】timer_in_service は RTL 非写像**：emu23 は irq==1 受理時に `timer_in_service=1`（L1098）をセットするが、これはソフト固有（V0本体 §5.1）。RTL では写さず、タイマー側の1段ラッチ（§6.6）で等価を取る。

#### 6.3 IRET FSM（S_EXEC_IRET）
emu23 IRET（L1133-1143 実照合）。受理と**逆順**。

1. `FLAGS ← (mem[SP..SP+1] の下位8bit); SP ← SP+2`（FLAGS を先に pop。**下位8bitのみ復元**＝emu23 `(uint8_t)pop16()`。上位は0）
2. `PC ← mem[SP..SP+1]; SP ← SP+2`（PC を後に pop。post-increment）
3. タイマー復帰処理（`YSD8002_iret`）は **RTL 非写像**。RTL ではタイマー1段ラッチの解除で代替（§6.6・D-1）。

**設計注意**：FLAGS 復元は 16bit pop の下位8bit のみ採用（LV-2 で FLAGS は16bit保持だが、IRET 復元時は下位8bit マスク）。有効ビット Z/N/IE は下位8bit 内（bit0/1/7）に収まるので情報欠落はない。

#### 6.4 SYSCALL（S_EXEC_SYSCALL）
emu23 SYSCALL（L1145-1153 実照合）。**1バイト命令**（imm16 フェッチなし）。動作は `irq_pending ← 4` をセットするのみ。実際の受理（スタック退避・ベクタ飛び）は次の S_IRQCHK で S_IRQ_ACCEPT 経由で起きる。A レジスタにシステムコール番号が入っている前提（ハンドラが参照）。

#### 6.5 命令クラス別の状態遷移（代表）
- **クラスA（例 ADD rD,rS）**：S_FETCH → S_OPFETCH → S_EXEC_ALU（`rD ← rD+rS`、`set_zn`）→ S_WRITEBACK。
- **クラスB（例 ADDI rD,#imm）**：S_FETCH → S_OPFETCH → S_IMML（imm 下位byte）→ S_IMMH（imm 上位byte）→ S_EXEC_ALUI → S_WRITEBACK。
- **クラスB 分岐（例 BEQ rel16）**：imm（rel16）フェッチ後、`FLAGS[Z]==1` なら `PC ← PC+rel16`、else 何もしない（フラグ不変）。条件は Z/N のみ（§3.9 / D-3）。
- **クラスC ロード（例 LDW rD,[imm16]）**：imm フェッチ → S_MEMR_LO（`mem[addr]`）→ S_MEMR_HI（`mem[addr+1]`）→ 合成（リトルエンディアン）→ `rD←値; set_zn` → S_WRITEBACK。各 S_MEMR_* はバス ready 待ち。
- **クラスC ストア（例 STW rS,[imm16]）**：imm フェッチ → S_MEMW_LO（`mem[addr]←rS[7:0]`）→ S_MEMW_HI（`mem[addr+1]←rS[15:8]`）→ 次命令（フラグ不変）。
- **クラスC バイト（LDB/STB）**：8bit アクセス1回（S_MEMR8 / S_MEMW8）。**align チェック対象外**（§6.7）。フラグ不変。
- **クラスD（JSR）**：imm（target）フェッチ → `PC` 前進済み → S_PUSH_LO/S_PUSH_HI（戻り先PC push）→ `PC←target`。
- **クラスD（RET）**：S_POP_LO/S_POP_HI（`PC←pop`）。
- **クラスD（PUSH A）**：`SP←SP-2` → S_PUSH_LO（`mem[SP]←A[7:0]`）→ S_PUSH_HI（`mem[SP+1]←A[15:8]`）。POP は逆。**【C-1】PUSH/POP のレジスタ対象は A/B/X の3本のみ**（0x1F サブ 0x00-0x02=PUSH A/B/X、0x03-0x05=POP A/B/X。L1174 等実照合）。SP/PC/FLAGS の汎用 PUSH/POP は無く、これらは割り込み受理・IRET・JSR・RET の専用パスでのみスタック操作される（§3.1 の rD/rS 範囲限定と一貫）。

#### 6.6 タイマー1段ラッチ（emu23 非対称の合わせ込み）
emu23 の `next_irq_cycle=UINT64_MAX`／`timer_in_service` による IRET 前連続発火抑止（V0本体 §5.3）は、RTL では「**timer_irq をクリア（IRET 相当でタイマーハンドラが抜ける）するまで、次のリロード由来 timer_irq をペンドさせない1段ラッチ**」で等価を取る。検証は D-1（§9）で IRET 直後に即期限到来する境界を反例テスト。

#### 6.7 アライメント例外の発火
16bit アクセス（rd16/wr16 相当の S_MEMR_*/S_MEMW_* 系）で `addr[0]==1` のとき、アクセスを中断し `irq_pending ← 3`（align・ベクタ$0006、V0本体 §5.4）をセットして S_IRQCHK へ。read/write 両経路に置く。**8bit アクセス（LDB/STB）は align チェック対象外**（奇数アドレス正当、V0本体 §7.4）。

#### 6.8 SP の偶数維持
push/pop は必ず ±2（§5 実照合：push16=SP-2, pop16=SP+2）。reset 時 SP が偶数なら以降も偶数を保つため、スタックアクセスは常に偶数境界＝align 例外を踏まない。これは MC6809 のスタック（pre-decrement push / post-increment pull）と同方式。

---

### 7. 抽象バス I/F

#### 7.1 信号定義（byte 粒度・LV-3 確定）
**バスは 8bit データ幅（byte 粒度）に固定する**（LV-3：8bit×2 トランザクション方式）。

| 信号 | 幅 | 向き | 意味 |
|---|---|---|---|
| `mem_addr` | 16 | CPU→bus | バイトアドレス |
| `mem_wdata` | 8 | CPU→bus | 書込データ |
| `mem_rdata` | 8 | bus→CPU | 読込データ |
| `mem_rd` | 1 | CPU→bus | 読込要求 |
| `mem_wr` | 1 | CPU→bus | 書込要求 |
| `mem_ready` | 1 | bus→CPU | アクセス完了 |

確定根拠：emu23 のメモリアクセスはバイト粒度（rd8/wr8、rd16 は lo=mem[a]/hi=mem[a+1] のbyte×2合成、V0本体 §7.4）。8bit バスとすれば LDB/STB（8bit）と rd16/wr16（8bit×2）が同一バスで自然に表現でき、byte-enable 方式（V0本体 §7.4）と整合。**V2 で 16bit 化する場合も、本 I/F を内部で束ねる形にすれば CPU コア FSM は不変**（V2 手戻り最小化）。

#### 7.2 16bit アクセスのバイト分割プロトコル
16bit リード：`mem_addr=a, mem_rd=1` で下位バイト取得 → `mem_addr=a+1, mem_rd=1` で上位バイト取得 → `{hi,lo}` に合成（リトルエンディアン）。各段で `mem_ready` を待つ。ライトは下位→上位の順に `mem_wr`。

#### 7.3 V1 TB のビヘイビアメモリ
V1 検証では、固定レイテンシ（例：1〜数クロックで ready）のビヘイビアメモリで実メモリを代替する。実 PSRAM コントローラ（可変レイテンシ）は V2。CPU コア FSM は `mem_ready` を待つ作りなので、レイテンシ変化に対して FSM 変更不要。

---

## 第Ⅲ部：検証設計

### 8. 検証方式（emu23 突合）

#### 8.1 突合基準フォーマット
RTL の1命令完了後の状態を `PC=%04x A=%04x B=%04x X=%04x SP=%04x F=%02x` 形式で出力し、emu23 のトレース出力（L1534 同形式）と diff する。**emu23 トレース行末尾の逆アセンブル列（`| dbg_lookup(pc)`）は diff 対象外**（レジスタ値部分のみ比較・N-2）。

#### 8.2 emu23 突合ハーネス
golden は emu23 v1.08 の **`-n N`（Nステップ実行＋トレースダンプ、非対話）**（L1742）で生成。**emu23 v1.08 に `-it` は存在しない**（v1.09 追加の対話モード）ため、突合には v1.08 同梱の `-n`／トレースのみ使う（C-1）。

#### 8.3 命令別単体 TB
各命令（53 case）につき、初期レジスタ/メモリを与えて1命令実行し、RTL 状態と emu23 `-n 1` 相当の状態を diff する。テスト観点：
- フラグ更新有無（§4.3 の表通りか。特に MOV 不変／LDW 更新／CMP 結果非書込）
- メモリアクセスのアドレス・データ・粒度（byte/word）
- SP 増減方向（push=SP-2/pop=SP+2）
- 分岐の成立・不成立（Z/N 境界）

#### 8.4 完了条件（V1 工程）
**53 case すべての単体 TB が emu23 と一致**（C-3：53＝exec_one case 数、サブopcode 含む。トップ opcode 47）。割り込み受理・IRET・SYSCALL の経路も TB に含める。

---

### 9. V1 で消化する追加検証項目
- **D-3（分岐 Z/N 網羅）**：BEQ/BNE/BLT/BGE を Z/N の境界値（結果 0・正・負・0x8000）で網羅突合。
- **D-1（1段ラッチ）部分**：§6.6 のタイマー1段ラッチは、本格突合は V3（タイマー実装）だが、V1 でも IRET 後の irq 再ペンド抑止ロジックの単体確認を行う。
- **align 発火**：16bit アクセスの奇数アドレスで irq_pending=3 が立つことを TB で確認（本格突合 D-2 は V2）。

---

## 第Ⅳ部：付録

### 10. 未確定論点（V1 残）
- ~~LV-1 ALU キャリー~~ → クローズ（§4.2）
- ~~LV-2 FLAGS 実装幅~~ → **16bit 保持で確定**（§3.2。IRET 復元時のみ下位8bit マスク、§6.3）
- ~~LV-3 バス 16bit 分割~~ → **8bit バス（8bit×2）で確定**（§7.1。V2 で内部束ね可）
- LV-4 EXT 0x1F 実使用実績：yuios.bin 逆アセンブルで 0x1F 出現数を実測し、未使用なら V1 実装優先度を下げる。**ただし PUSH/POP/LDB/STB は 0x1F サブopcード経由のため、0x1F デコード自体は必須**（これら8命令が 0x1F プリフィックスを使う、§5.2）。よって 0x1F デコードは V1 で実装し、「0x1F 配下で未使用のサブopcード」があれば後回し可、と整理を修正。yuios.bin 入手時に実測。

### 11. 関連文書・改版履歴

**関連文書：**
- ISA2_3_v231.docx（ISA 真実）
- emu23_v108.c（黄金リファレンス・exec_one L1089-、push16/pop16 L752-761）
- fpga_v0_impl_spec_v1_1.md（V0 本体最新正式版＝v1.0のレビュー反映クローズ版。outputs実在確認済）
- fpga_v1_cpucore_design_skeleton_v1_1.md（承認済骨子・v1.0のレビュー反映クローズ版。outputs実在確認済・本書の入力）

**改版履歴：**

| 版 | 日付 | 内容 |
|---|---|---|
| v1.0 | 2026-06-30 | 本体初版。承認済骨子 v1.1 を本文化。53命令を emu23 ハンドラで個別実照合し、フラグ更新有無（MOV不変/LDW更新/CMP結果非書込）・メモリアクセス粒度・SP操作方向（push=SP-2 pre-dec/pop=SP+2 post-inc）を §4.3/§5.3 の表に確定。§6 に FSM 状態遷移（トップレベル・割り込み受理・IRET・SYSCALL・クラス別・タイマー1段ラッチ・align・SP偶数維持）を記述。LV-2（FLAGS 16bit 保持・IRET 下位8bit マスク）・LV-3（8bit バス）を確定。LV-4 を「0x1F デコードは必須・配下未使用サブopは後回し可」と整理修正。 |
| v1.1 | 2026-06-30 | レビュー指摘書 fpga_v1_cpucore_body_review_v1_0.docx を反映（条件付き承認→クローズ・RTL着手可）。**M-1**＝§3.1 レジスタ番号を get_reg_ptr 実照合（L1024-1032：0=A/1=B/2=X/3=SP/default=NULL）で是正。**rD/rS指定可は0-3のみ、4(PC)/5(FLAGS)はNULL＝オペランド指定不可でno-op**。RTLはデコーダで4/5のライトポートを抑止すること（**従来 4=PC/5=FLAGS と誤記＝V0本体§3.1から引きずった見落とし。KY34違反の自戒**）。**C-1**＝§6.5 PUSH/POP は A/B/X 限定を補足。**C-2**＝§5.3 IRETフラグ欄を「(uint8_t)pop16() 下位8bit復元」に整合。**C-3**＝§3.3 デコーダ4/5無効化を担保。**N-2**＝入力文書 v1_1（V0本体/V1骨子とも outputs実在確認済・最新正式版）を関連文書に明記。RTL(.sv)実装フェーズへ進行可。 |

