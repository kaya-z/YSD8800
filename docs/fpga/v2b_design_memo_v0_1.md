# V2-b 設計メモ v0.1 (2026-07-09)
## FPGA V2 CPUコア単体検証 — C2即値ALU / C3比較

---

## 0. 位置づけ
- 親: V2 CPUコア単体検証（設計メモ v0.1 承認済 Q1〜Q6）
- 本メモ: V2-b（C2即値ALU群 / C3比較群）の検証設計
- 前提: V2-a（C1レジスタALU）ALL PASS・環境再現済
- 原則43: 本メモのレビュー承認を得てから実装に着手する

---

## 1. 対象命令（ISA2_3_v231 実照合済）

### C2 即値ALU（4B: `op [rD<<4|0] lo hi`, imm16 LE, rD更新, Z/N）
| opcode | 命令 | 動作 |
|--------|------|------|
| 0x41 | ADDI rD,#imm16 | rD += imm |
| 0x43 | SUBI rD,#imm16 | rD -= imm |
| 0x51 | ANDI rD,#imm16 | rD &= imm |
| 0x53 | ORI  rD,#imm16 | rD \|= imm |
| 0x55 | XORI rD,#imm16 | rD ^= imm |

### C3 比較（レジスタ不変・FLAGSのみ更新, Z/N）
| opcode | 命令 | 長さ | 動作 |
|--------|------|------|------|
| 0x44 | CMP  rD,rS     | 2B | FLAGS ← rD - rS （rD不変） |
| 0x45 | CMPI rD,#imm16 | 4B | FLAGS ← rD - imm（rD不変） |

- CMP/CMPIの「rD不変」は emu23実ソース L1402/1409 でも確認済（set_znのみ、*rdへの代入なし）。

---

## 2. 検証方式（V2-a方式を踏襲）
1. 単一ソース生成: 同一バイト列から emu23用bin と $readmemh用hex を生成（偽合格防止）。
2. 期待値は emu23 v1.09 黄金から自動取得（手計算しない）。
3. 外部観測等価が合格基準（内部構造一致は不要）。回帰ゲート: 完走＋論理結果一致。

---

## 3. 設計上の論点と決定

### 論点1: C3のレジスタ不変検証（★本V2-bの核心・本日KY）
- 問題: V2-aのbuild_codeは「最後のALUでrDが変化する」前提。CMPを素直に足すと
  rD不変チェックが抜け、CMPをSUB相当と誤実装しても偽合格する。
- 決定: ベクタに命令種別 `kind`（'alu2'|'cmp'）を導入。
  - kind='cmp' のとき、TBは「対象rDが実行前後で不変」＋「FLAGS(Z/N)一致」の
    **両方**をアサートする。
  - 実行前rDは「初期化LDWで入れた既知値」を期待値とする（emu23黄金の最終rDとも一致するはず）。

### 論点2: エンコーダ追加（ISAに無い命令を作らない）
- 追加: `alu_imm(op, rd, imm)` = 4B `[op, rd<<4|0, lo, hi]`（ldw_immと同型・op差し替え）。
  - C2（0x41/43/51/53/55）と CMPI（0x45）に使用。
- CMP(0x44)は既存 `alu_rr` を流用（op=0x44）。

### 論点3: build_code の一般化
- 現状: init + 単一alu_rr + HALT 固定。
- 変更: 末尾命令を種別で分岐。
  - 'alu2': alu_imm(op,rd,imm) を積む（rd更新）
  - 'cmp' : op=0x44なら alu_rr(0x44,rd,rs)、op=0x45なら alu_imm(0x45,rd,imm)
- initは従来通り ldw_imm 群。

### 論点4: ベクタ設計（Z/N境界網羅）
- C2即値（各Z/N代表）:
  - ADDI: pos / zero(結果0) / neg(結果bit15=1)
  - SUBI: pos / zero / neg
  - ANDI: zero / neg
  - ORI : pos / neg
  - XORI: zero / neg
- C3比較:
  - CMP : 等値(Z1N0) / rD<rS→負(Z0N1) / rD>rS(Z0N0)
  - CMPI: 等値(Z1N0) / rD<imm→負(Z0N1) / rD>imm(Z0N0)
  - CMPは必ずrD不変チェックを伴う。

### 論点5: 段階承認
- V2-b で新規ベクタ ALL PASS ＋ V2-a回帰維持を確認 → レビュー → V2-c へ。

---

## 4. 成果物（予定）
- `gen_v2_vectors_v2b.py`（V2-a生成器を拡張。_poc で先行実験しKY38遵守）
- `tb_cpu_v2b_v0_1.sv`（cmp不変チェック付き突合TB）
- `v2b/` 生成ベクタ一式・golden_v2b.txt

---

## 5. 未確定・レビュー確認事項（Q）
- Q1: CMPの「実行前rD不変」の期待値は初期化LDW値を真とする方針でよいか
  （emu23黄金の最終rDと二重で突合する）。
- Q2: C2/C3のベクタ本数（上記で C2=11, C3=6 の計17。過不足の指摘を仰ぐ）。
- Q3: TBを V2-a とは別ファイル(tb_cpu_v2b)にするか、統合TBにするか。
  （V2-aは別ファイル運用。踏襲案＝別ファイルを推奨）
- Q4: SP不変チェック（C2/C3はSP非対象）を V2-a同様に付けるか。
