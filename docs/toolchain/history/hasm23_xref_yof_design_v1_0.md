# hasm23 クロスファイルシンボル参照対応 ＋ YOF 移行ビルド 設計書

| 項目 | 内容 |
|---|---|
| ファイル名 | hasm23_xref_yof_design_v1_0.md |
| Version | v1.0 |
| Status | **DRAFT（レビュー待ち）** |
| 作成日 | 2026-06-20 |
| 対象工程 | Step 8-F-2（ビルド手順書 §10 将来課題 No.2/3/6 の恒久対処） |
| 関連 | yuios_build_procedure_v1_5.docx §10 / kaizen 原則31 / lnk23_design_v1_3.docx |

---

## 改版履歴

| Version | 日付 | 変更内容 | 担当 |
|---|---|---|---|
| v1.0 | 2026-06-20 | 新規作成。PoC（CHAT61）実証結果に基づく設計確定。 | Claude |

---

## 1. 背景と目的

### 1.1 背景

YUI OS のビルドでは、手書きカーネル（kernel_v12_7.asm 等）が Forth カーネル成果物
（Force 出力 kernel_forth_*.asm）で定義されるシンボル（`WORD_OS_START` 等）の
アドレスを必要とする。現行ビルドは、これらのクロスファイル参照を **sed による
アドレス直書き置換**で回避している（ビルド手順書 §10 将来課題 No.2/3/6）。

| §10 No. | 課題 | 現行の暫定対処 |
|---|---|---|
| 2 | startup_harness の `JSR _main` | sed で `JSR $XXXX` に直書き |
| 3 | kernel.asm の Forth シンボルアドレス | sed でビルド毎に .sym から取得・置換 |
| 6 | `WORD_OS_START` の sed 置換 | sed でビルド毎に .sym から取得・置換 |

この sed 依存は kaizen 原則31（Forth シンボルアドレスのハードコード禁止。
リネーム・ワード増減でアドレスが変化すると即値が静かに腐る）の根本解決には
至っておらず、ビルドの脆弱性・手作業性の温床となっている。

### 1.2 目的

クロスファイルシンボル参照を **YOF（オブジェクトファイル）リンクで正規に解決**し、
No.2/3/6 の sed を全廃する。これにより:

- ビルドの自動化・堅牢化（シンボルアドレスの自動解決）
- kaizen 原則31 の根本遵守（ハードコード自体の消滅）
- 将来の分割コンパイル（scc23 Phase 2）への基盤整備

### 1.3 当初想定からの重要な方向転換（PoC による）

本工程は当初「**lnk23 大改修**（クロスセクション参照解決）」と位置付けていた。
しかし PoC 調査（CHAT61）の結果、**lnk23 v2.00 は既にクロスファイル UNDEF 解決を
実装済み**であり、改修不要であることが実証された。真に不足していたのは
**hasm23 側の外部シンボル export 能力**であった。

→ 本設計の改修対象は **hasm23** と **ビルド手順** であり、lnk23 は無改修とする。

---

## 2. 現状分析（PoC 実証済み事実）

PoC（CHAT61）にて、最小例（2ファイル構成）で以下を実コードにより実証した。
すべて実ソース行番号・実行結果を一次根拠とする（KY34）。

### 2.1 既に動作している機能（改修不要）

| 機能 | 実証 | 根拠 |
|---|---|---|
| hasm23 -c の未定義ラベル自動 UNDEF 化 | ✅ | hasm23_v1_02.c:1010-1031（即値）/1109-1128（分岐）。b.asm の `JSR _main` が 2 syms/1 reloc で YOF 出力 |
| lnk23 の UNDEF クロスファイル解決 | ✅ | lnk23.c:649-702。`2 global symbol(s) resolved` / `applying N relocation(s)` |
| --alias によるエントリ名解決 | ✅ | lnk23.c:656-664（案Y、Forth エントリ用） |
| `_main`（`_`始まり）の GLOBAL export | ✅ | _main/_start が解決され A=$1234 を実行確認 |

### 2.2 不足していた機能（改修対象）

| # | 不足 | 実証された症状 | 根拠 |
|---|---|---|---|
| **D-1** | `WORD_xxx`（`_`非始まり）の GLOBAL export | lnk23 が `undefined symbol: WORD_OS_START` | hasm23_v1_02.c:455-457 `yof_sym_kind` は `name[0]=='_'` のみ GLOBAL 判定 |
| **D-2** | 同一 UNDEF シンボルへの複数参照（即値＋JSR 等） | 2 個目以降の参照が reloc 化されず addr=0 が埋め込まれ暴走 | 1 個目参照で UNDEF symbol を `symbols[]` 登録（addr=0）→ 2 個目が `find_sym` で「解決済み」と誤認 |

### 2.3 sed 依存の真の分類

| §10 No. | 参照の性質 | YOF で解決可能か | 備考 |
|---|---|---|---|
| 2 (JSR _main) | クロスファイル・`_`始まり | ✅ 解決可 | hasm23 -c + lnk23 で廃止可（PoC 実証） |
| 3 (Forth シンボル) | クロスファイル・`WORD_` 始まり | ✅ 解決可（D-1/D-2 改修後） | `.global` 追加で廃止可 |
| 6 (WORD_OS_START) | クロスファイル・`WORD_` 始まり | ✅ 解決可（D-1/D-2 改修後） | No.3 と同一機構 |
| **1 (Force 混入行 #WORD_xxx)** | **同一ファイル内**・Force 出力品質問題 | ❌ **対象外** | YOF 移行では解決しない。Force 側の別課題として残置 |

**重要**: No.1（Force 混入行）は本設計のスコープ外。YOF 移行で No.2/3/6 は廃止できるが、
No.1 の sed は残る。これを設計書に明記し、誤って「全 sed 廃止」と期待しないこと。

---

## 3. 設計

### 3.1 改修方針サマリ

| 対象 | 改修内容 | 規模 |
|---|---|---|
| hasm23 | (A) `.global` 疑似命令の追加（D-1 対処） | 小 |
| hasm23 | (B) UNDEF シンボル複数参照対応（D-2 対処） | 小 |
| lnk23 | 無改修 | — |
| ビルド手順書 | YOF 移行に伴うフロー刷新（No.2/3/6 sed 廃止） | 中（文書改版） |
| Force 出力 / kernel.asm | `WORD_xxx` 参照を `.global` 宣言＋`#$LABEL` 構文へ | 中（ソース修正） |

### 3.2 改修 (A): `.global` 疑似命令の追加（D-1 対処）

#### 3.2.1 仕様

新疑似命令 `.global SYM` を追加する。当該シンボルを YOF 出力時に
GLOBAL（外部公開）として記録する。`_` 始まりでない Forth 語シンボル
（`WORD_OS_START` 等）を別ファイルから参照可能にする。

```
.global WORD_OS_START      ; WORD_OS_START を GLOBAL export 宣言
WORD_OS_START:
    ...
```

#### 3.2.2 設計詳細（PoC 実装に基づく）

- グローバル明示リスト `g_globals[MAX_GLOBALS]`（256 エントリ）を新設。
- **PASS1** で `.global SYM` を読み、`g_globals[]` に登録（重複排除）。
- **PASS2** では `.global` 行はコード非生成・素通り（PC 不変）。
- `yof_sym_kind()` を拡張:
  ```c
  static char yof_sym_kind(const char *name) {
      if (name[0] == '_' || is_declared_global(name)) return YSYM_GLOBAL;
      return YSYM_LOCAL;
  }
  ```
- 後方互換: `.global` 未使用の既存ソースは従来通り（`_` 始まり＝GLOBAL）動作。

#### 3.2.3 命名規約との関係（MC6809 系の慣習）

本設計は明示宣言方式（`.global`）を採る。命名規約依存（`WORD_` を機械的に
GLOBAL 化する案A）は暗黙的で誤 export を招くため不採用。MC6809 標準アセンブラ
（AS9 等）でも外部公開は明示宣言が常識であり、本方式はその踏襲である。
将来 import 側に `.extern` を導入する場合、`.global`（export）/ `.extern`（import）
の対称ペアとして整合する。

### 3.3 改修 (B): UNDEF シンボル複数参照対応（D-2 対処）

#### 3.3.1 問題

同一の未定義（外部）シンボルを 1 ファイル内で複数回参照
（例: `LDW A, #$WORD_OS_START` と `JSR WORD_OS_START`）した場合、
1 個目の参照で UNDEF シンボルが `symbols[]` に addr=0 で登録され、
2 個目の参照は `find_sym()` がそれを発見して「解決済み」と誤認し、
reloc を生成せず addr=0 を埋め込む。結果、2 個目の参照先が $0000 となり暴走する。

#### 3.3.2 対処（対処1：UNDEF は解決済みと見なさない）

`symbol_t` に `is_undef` フラグを追加。UNDEF として登録したシンボルには
`is_undef=1` を立てる。参照解決時、`find_sym()` がヒットしても
**`is_undef` なら未解決として扱い、参照ごとに必ず reloc を生成**する。

```c
typedef struct {
    char name[64];
    uint16_t addr;
    int is_undef;   /* UNDEF（外部参照・addr未確定）なら1 */
} symbol_t;
```

参照箇所（即値側・分岐側の両方）に以下の分岐を追加:
- `s == NULL`: 従来通り UNDEF 登録＋reloc 化＋`is_undef=1`。
- `s != NULL && s->is_undef`: reloc を毎回生成（addr は仮値 0）。
- `s != NULL && !s->is_undef`: 従来通り `s->addr` を使用。

#### 3.3.3 PoC 実証結果

最小例（即値＋JSR が同一 UNDEF を参照）にて:
- 対処前: reloc=1、JSR が `68 00 00`（$0000・未解決）→ 暴走
- 対処後: reloc=2、JSR が `68 28 00`（$0028・解決）、即値 `21 00 28 00`、
  実行で A=$BEEF（参照先実行成功）を確認。

### 3.4 YOF 移行後のビルドフロー

#### 3.4.1 新フロー（No.2/3/6 sed 廃止）

```
[kernel_forth_*.fs]
  │ Force コンパイル
  v [kernel_forth_*.asm]  ← Force 混入行(#WORD_xxx)は残る → No.1 sed で修正（残置）
  │ ★ Forth 側で公開すべきシンボルに .global 宣言を付与
  │ hasm23 -c でアセンブル（YOF 出力）
  v [kernel_forth_*.obj]  ← WORD_OS_START 等を GLOBAL export
[kernel_v12_7.asm]
  │ ★ Forth シンボル参照を #$LABEL 構文＋ハードコード削除に修正
  │ hasm23 -c でアセンブル（YOF 出力・未定義は自動 UNDEF 化）
  v [kernel_v12_7.obj]    ← WORD_OS_START を UNDEF 参照
  │ lnk23 -o yuios.bin（forth 先 → kernel 後・UNDEF 自動解決）
  v [yuios.bin] + [yuios.sym]
```

#### 3.4.2 廃止される手順 / 残る手順

| 手順 | 旧 | 新 |
|---|---|---|
| WORD_OS_START の sed 置換（No.6） | 必須 | **廃止** |
| Forth シンボルアドレス sed 置換（No.3） | 必須 | **廃止** |
| JSR _main の sed 直書き（No.2） | 必須 | **廃止** |
| Force 混入行 #WORD_xxx 修正（No.1） | 必須 | **残置**（Force 課題） |
| SECTION 順序 forth 先 → kernel 後 | 必須 | 必須（不変・後勝ちルール） |

#### 3.4.3 SECTION 順序の維持

YOF リンクでも「forth 先 → kernel 後」順序は維持する（ビルド手順書 §6.2、
後勝ちルール）。YOF 化はシンボル解決方式の変更であり、配置順序の制約は不変。

---

## 4. 影響範囲

| 対象 | 影響 | 対応 |
|---|---|---|
| hasm23 | `.global` 追加・`is_undef` 追加 | v1.02 → **v1.03** |
| lnk23 | なし | v2.00 維持 |
| emu23 | なし | v1.06 維持 |
| scc23 | なし（将来 Phase 2 で .global 自動付与の余地） | v1.04 維持 |
| Force 出力 | 公開シンボルへの `.global` 付与が必要 | Force 改修 or 後処理で付与 |
| kernel_v12_7.asm | Forth シンボル参照を `#$LABEL`＋ハードコード削除 | ソース修正 |
| ビルド手順書 | フロー刷新 | v1.5 → **v1.6** |
| 各設計書 | hasm23 仕様変更の反映 | toolchain23_design 等 |

### 4.1 Force 側の `.global` 付与方法（要検討事項）

Forth 語シンボル（`WORD_xxx`）を GLOBAL export するには、Force 出力 asm に
`.global` 宣言が必要。実現方法は2案:
- **案F1**: Force コンパイラ本体を改修し、公開対象ワードに `.global` を自動出力。
- **案F2**: ビルドスクリプトの後処理で、必要シンボルの `.global` 行を機械的に挿入。

→ **本設計では案F2（後処理付与）を第一候補**とする。Force 本体改修（案F1）は
影響が大きく、Force 改修時は Dhrystone 回帰免除の特例があるとはいえ、
Force の出力仕様変更は別途設計を要するため。案F2 なら hasm23 改修のみで完結する。
（この点はレビューで方針確認を要する。）

---

## 5. テスト計画

### 5.1 単体テスト（hasm23 v1.03）

| # | 項目 | 期待 |
|---|---|---|
| T1 | `.global SYM` で `WORD_xxx` が GLOBAL export | YOF シンボル種別 = 'G' |
| T2 | `.global` 未使用の既存 asm | 従来通りアセンブル（後方互換） |
| T3 | 同一 UNDEF への即値＋JSR 複数参照 | reloc=2、両方解決 |
| T4 | 同一 UNDEF への3参照以上 | reloc=N、全解決 |
| T5 | `.global` 宣言したシンボルが当該ファイルで未定義 | 適切なエラー or LOCAL 扱い（要仕様確定） |

### 5.2 結合テスト

| # | 項目 | 期待 |
|---|---|---|
| I1 | kernel + forth の YOF リンク（sed 無し） | yuios.bin 生成・WORD_OS_START 解決 |
| I2 | YUI OS 起動 | 期待出力 `A BCP`（従来と一致） |

### 5.3 回帰テスト（必須）

hasm23 はツールチェーン構成要素であり、**改修時は Dhrystone 回帰が必須**
（Force 改修以外は回帰必須の原則）。

| 項目 | 基準値 |
|---|---|
| Dhrystones/sec | 826 |
| cycles | 48405 |
| 正答チェック | P:20 |

加えて hasm23 v1.02 の W001/E001 機能の非回帰も確認する。

---

## 6. 実装ステップ（承認後）

1. hasm23_v1_02.c → hasm23_v1_03.c（KY38: 別ファイル名）
2. 改修 (A) `.global` 追加
3. 改修 (B) `is_undef` 複数参照対応
4. 単体テスト T1-T5
5. Dhrystone 回帰（826/48405/P:20）＋ W001/E001 非回帰
6. 結合テスト I1-I2（YUI OS 実ビルド・sed 廃止確認）
7. ビルド手順書 v1.5 → v1.6 改版
8. 関連設計書改版（toolchain23_design 等）

**原則43**: 本設計書のレビュー承認を得るまで実装着手しない。

---

## 7. 未解決・レビュー確認事項

| # | 論点 | 内容 |
|---|---|---|
| Q1 | Force `.global` 付与方法 | 案F1（Force本体）/ 案F2（後処理）のどちらを採るか（§4.1） |
| Q2 | T5 の仕様 | `.global` 宣言したが当該ファイルで未定義のシンボルの扱い（エラー / GLOBAL-UNDEF として export？） |
| Q3 | No.1（Force 混入行）残置の是非 | 本設計スコープ外で残置とするが、別工程で扱うか確認 |
| Q4 | YOF 構造体バイト整合 | 過去に YOF 構造体パディング（36/6 vs 38/8）でハマった経緯あり。本実装でも load 側バイト整合を再確認すること |

---

*— YSD8800 Project / Step 8-F-2 —*
