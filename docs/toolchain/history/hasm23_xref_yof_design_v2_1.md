# hasm23 ＋ lnk23 クロスファイルシンボル参照対応 ＋ YOF 固定アドレス配置ビルド 設計書

| 項目 | 内容 |
|---|---|
| ファイル名 | hasm23_xref_yof_design_v2_1.md |
| Version | v2.1 |
| Status | **DRAFT（再レビュー待ち）** |
| 作成日 | 2026-06-20 |
| 対象工程 | Step 8-F-2（ビルド手順書 §10 将来課題 No.2/3/6 の恒久対処） |
| 関連 | yuios_build_procedure_v1_5.docx §10 / kaizen 原則31 / lnk23_design_v1_3.docx / yuios_memmap_design_v2_4.md / review_hasm23_xref_yof_v1_0.md / review_hasm23_xref_yof_v2_0.md / review_hasm23_xref_yof_v3_0.md |

---

## 改版履歴

| Version | 日付 | 変更内容 | 担当 |
|---|---|---|---|
| v1.0 | 2026-06-20 | 新規作成。PoC（CHAT61）実証結果に基づく設計確定。 | Claude |
| v1.1 | 2026-06-20 | レビュー指摘書 review_hasm23_xref_yof_v1_0.md（差し戻し）対応。M-1/M-2/C-1/C-2＋D-1/N-1/N-2/E-1 を本文反映。 | Claude |
| **v2.0** | **2026-06-20** | **【大改版・根幹前提の是正】結合テスト I1（YUI OS 実ビルド）で v1.1 の根幹前提「lnk23 無改修」（旧 C-1）が崩壊。原因は YUI OS が forth=$5100／kernel=$0000 の2固定アドレス配置であり、YOF リンクの自動連続配置と整合しないこと。PoC（CHAT61 続）で方式α-A（位置独立化）が内部参照 reloc 無しで破綻することを実証し、方式α-B（道2：hasm23 が `.org` を配置アドレスとして尊重・空白除去・load_addr 記録、lnk23 が load_addr 尊重配置）の技術的成立を完全実証（forth $5100／kernel $0000／クロス UNDEF 解決／内部参照 $5108 保持／非 YOF Dhrystone 回帰 826/48405/P:20）。これに伴い (1) 改修対象を hasm23 単独 → **hasm23＋lnk23 両改修**に拡張、(2) 旧 C-1「lnk23 無改修保証」を全面撤回（§3.1・§9）、(3) 道2 仕様を新設（§3.5）、(4) α-A 不成立の設計判断を記録（§3.6）、(5) YUI OS 実配置反映（§3.4）、(6) テスト計画拡張（§5）。v1.1 までの記述は取り消し線で保持。 | Claude |
| **v2.1** | **2026-06-20** | **レビュー指摘書 review_hasm23_xref_yof_v3_0.md（条件付き承認）対応。承認ブロッカー M-3／C-3 を §3.5.3 に確定追記、推奨 E-2／N-3／N-4 反映。主変更：①M-3-2 機序明記＝道2 の YUI OS リンクは `--machine force` モード必須（baremetal の ROM境界$3FFF チェック L591-593 を回避。forth@$5100 は RAM 正当配置）。②M-3-1 混在可否＝当面「全 YOF セクションが load_addr/has_org を持つ前提・自動/固定混在は非サポート（混在時はエラー）」と明記。③C-3 確定＝load_addr=0 の曖昧性を解消するため YOF flags バイト（既存・空きビット bit4=0x10）に `has_org` フラグを新設。`has_org=1` なら値が$0000でも固定配置、`has_org=0` は自動配置（後方互換）。④E-2 版数誤記（v2.1→v1.1）訂正。⑤N-3（overlap 異常系 T10）・N-4（I3 空白部アドレス明文化）追加。v2.0 までの記述は取り消し線で保持。 | Claude |

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
**No.2/3/6 の sed を廃止**する。これにより:

- ビルドの自動化・堅牢化（シンボルアドレスの自動解決）
- kaizen 原則31 の根本遵守（ハードコード自体の消滅）
- 将来の分割コンパイル（scc23 Phase 2）への基盤整備

**【v1.1・D-1 正確化】廃止範囲の限定**: 本設計で廃止するのは **No.2/3/6 の sed のみ**。
~~sed を全廃~~。No.1（Force 混入行 `#WORD_xxx`）の sed は Force 出力品質問題であり
**残置**する（§2.3）。加えて本設計は新たに `.global` 付与の後処理（案F2・§4.1）を
導入するため、実像は「**No.2/3/6 の sed は廃止されるが、No.1 の sed および
`.global` 付与後処理は残る**」。「全 sed 廃止」ではない点に注意。

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

**【v1.1・C-1 確定 → v2.0 で全面撤回】**（v2.1・E-2: 旧「v2.1」表記は誤記訂正） ~~YOF オンディスク形式不変・lnk23 無改修の保証~~。
~~本設計で hasm23 に追加する `is_undef` フラグ（§3.3）はアセンブラ内部表現に閉じ、YOF 形式は不変、lnk23 無改修という本設計の根幹前提は保証される。~~

> **⚠ v2.0 重大是正**: 上記「lnk23 無改修」前提は **結合テスト I1（YUI OS 実ビルド）で崩壊した**。
> YUI OS は forth=$5100／kernel=$0000 の **2固定アドレス配置**であり、YOF リンクの自動連続配置
> （place_sections が $0000 から順に積む）と整合せず、`TEXT exceeds ROM area ($3FFF)` で失敗した。
> このため **lnk23 も改修対象**となる（§3.4・§3.5）。是正後の正しい前提を §3.1.1 に記す。

#### 3.1.1 v2.0 改修方針サマリ（hasm23＋lnk23 両改修）

| 対象 | 改修内容 | 規模 |
|---|---|---|
| hasm23 | (A) `.global` 疑似命令追加（D-1・§3.2） | 小 |
| hasm23 | (B) UNDEF 複数参照対応（D-2・§3.3） | 小 |
| hasm23 | **(C) 道2：YOFモードの `.org` を配置アドレスとして尊重（空白除去・load_addr 記録・offset 相対化）（§3.5）** | 中 |
| lnk23 | **(D) 道2：YOF セクションの load_addr を尊重して固定配置（§3.5）** | 中 |
| ビルド手順書 | YOF 移行・固定配置フロー刷新 | 中（文書改版） |

**YOF オンディスク形式の変更**: 道2 により、hasm23 は YOF セクションの `load_addr`
フィールドに **セクション原点（最初の `.org` 値）を記録**する（従来は R13 で 0 固定）。
これは 8 バイトのセクションヘッダ内の既存フィールドであり、**バイト数・レイアウトは不変**
（`YOF_SYM_SZ=36` 等のサイズ定数は変わらない）。lnk23 はこの load_addr を読んで配置に使う。

#### 3.1.2 旧サマリ（参考・v1.1）

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

#### 3.2.4 `.global` の v1.03 仕様確定【v1.1・C-2】

レビュー C-2（Q2/T5 の確定要求）に対し、v1.03 における `.global` 仕様を以下に確定する。

- **`.global SYM` は「定義済みシンボルを GLOBAL へ格上げする export 専用」とする。**
- `.global` 宣言したシンボルが**当該ファイル内で未定義**の場合は **エラー**とする
  （アセンブル失敗）。export 宣言は実体定義の存在を前提とするため。
- **import（外部参照）は `.global` の対象外**。外部シンボルの参照は、従来通り
  「未定義ラベルの自動 UNDEF 化」（hasm23 -c の既存機能）で扱う。明示的 import 宣言
  `.extern` の導入は **v1.03 のスコープ外**（将来バージョンへ分離）。

これにより T5 の期待挙動は「`.global` 宣言＋当該ファイル未定義 → **エラー**」と一意に定まる。
GLOBAL-UNDEF（GLOBAL かつ addr 未確定）という種別組合せは v1.03 では発生させない
（発生させる設計は lnk23 の挙動確認が新規に必要となり「lnk23 無改修」前提と衝突するため不採用）。
（旧 §7 Q2 は本項で確定済みとしてクローズ。）

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
    int is_undef;   /* UNDEF（外部参照・addr未確定）なら1。アセンブラ内部表現に閉じる */
} symbol_t;
```

#### 3.3.2.1 reloc 生成の 1 箇所集約【v1.1・M-2 最重要】

**現状の構造的問題**: 実ソース（hasm23_v1_02.c）では reloc 生成コードが
即値経路 L1020-1027・分岐経路 L1123-1130 の通り、いずれも **`if(!s)`
（＝シンボル未登録）ブロックの内側**に置かれている。

このため、対処を安直に「`else` 側に分岐を足す」だけで実装すると:
- 2 個目の参照（`find_sym` ヒット）は `else` 経由となり、`if(!s)` 内の
  既存 reloc 生成コードに**到達しない**
- 「`else` 側の新規 reloc 生成」と「`if(!s)` 内の旧 reloc 生成」が**二重定義**化、
  または旧コードが死蔵する

これは kaizen「コンパイラ内部状態の変更箇所は一か所に集約」に反する。

**設計要求**: reloc 生成を `if(!s)` ブロックから**括り出し**、
`s == NULL || s->is_undef` を満たす場合の**共通後処理として 1 箇所に集約**する。
改修後の制御構造を以下の疑似コードで定める（即値経路・分岐経路の双方を
**同一構造**に統一する。経路ごとに reloc の offset 計算式のみ異なる）。

```
s = find_sym(lbl);

if (s == NULL) {
    /* 未登録 → UNDEF 新規登録 */
    if (!already_in_symbols(lbl))
        add_symbol(lbl, addr=0, is_undef=1);
    need_reloc = 1;
}
else if (s->is_undef) {
    /* 登録済みだが UNDEF → 再登録せず、参照は未解決扱い */
    need_reloc = 1;
}
else {
    /* 定義済み（addr 確定） */
    imm = s->addr;
    need_reloc = 0;
}

/* ★ reloc 生成は分岐の外（集約点・唯一）に置く ★ */
if (need_reloc && opt_yof) {
    if (rel_count < MAX_REL) {
        rels[rel_count].offset = <経路別: 即値=pc+2 / 分岐=pc+1+has_reg>;
        memcpy(rels[rel_count].sym, lbl, 31);
        rels[rel_count].type = R_ABS16;  /* 0 */
        rel_count++;
    }
    imm = 0;   /* プレースホルダ */
}
```

集約後、reloc 生成コードは各経路につき **1 箇所のみ**存在し、
3 分岐（NULL / UNDEF / 定義済み）は `need_reloc` フラグで合流する。
これにより二重定義・死蔵を構造的に排除する。

#### 3.3.2.2 確定する 3 分岐の挙動

- `s == NULL`：UNDEF 新規登録（`is_undef=1`）→ reloc 生成（集約点）
- `s != NULL && s->is_undef`：登録済みにつき再登録せず → reloc 生成（集約点・同一）
- `s != NULL && !s->is_undef`：`s->addr` を確定値として使用（reloc 不要）

#### 3.3.3 PoC 実証結果

最小例（即値＋JSR が同一 UNDEF を参照）にて:
- 対処前: reloc=1、JSR が `68 00 00`（$0000・未解決）→ 暴走
- 対処後: reloc=2、JSR が `68 28 00`（$0028・解決）、即値 `21 00 28 00`、
  実行で A=$BEEF（参照先実行成功）を確認。

### 3.4 YUI OS の実メモリ配置（v2.0 新設・I1 で判明）

結合テスト I1 で、YUI OS のリンクには以下の **2固定アドレス配置**が必須と判明した
（yuios_memmap_design_v2_4.md §6）。

| 領域 | アドレス | 内容 |
|---|---|---|
| ベクタ＋カーネルコード（kernel.asm） | **$0000-$3FFF** | リセットベクタ $0000、本体 $0010〜（ROM 性質） |
| Forth 辞書（kernel_forth＝Force 出力） | **$5100**〜 | Forth カーネル本体 |

従来の .bin リンクでは、Force 出力 asm が `.org $5100` を内包し、kernel asm が `.org $0000`
を内包していたため、lds の `SECTION forth 0x0000 / SECTION kernel 0x0000`（mem[] 直接流し込み・
後勝ち）で各 bin 内部の絶対アドレス通りに展開され、結果的に正しく配置されていた。

**YOF リンクの問題**: YOF 引数モードの place_sections は両セクションを $0000 から
**自動連続配置**するため、forth が kernel の後ろに積まれ ROM 境界 $3FFF を超過する。
固定アドレス配置の指定手段が YOF モードに無かったことが、旧前提崩壊の直接原因。

### 3.5 道2：`.org` 配置アドレス尊重方式（v2.0 新設・PoC 完全実証）

#### 3.5.1 方式の要旨

YOF オブジェクトを「位置独立」にするのではなく、**`.org` で示された配置アドレスを
セクションの load_addr として尊重**し、lnk23 がそのアドレスに固定配置する。
forth は `.org $5100` のまま（内部参照も $5100 基準で正しく埋め込み済み）、
kernel は `.org $0000` のまま。両者は重ならず配置され、kernel→forth の
クロスファイル UNDEF（WORD_OS_START）だけリンカが解決する。

#### 3.5.2 hasm23 改修 (C)：空白除去・load_addr 記録・offset 相対化

現状 hasm23 の YOF モードは `.org $5100` を「$5100 までゼロパディング挿入」と解釈し、
$5100 バイトの空白を含む巨大セクション（size=$510d）を生成していた。これを是正する。

- **最初の `.org` をセクション原点 `sec_origin` として記録**。以降そのアドレスから
  コードを生成するが、**code_buf には sec_origin を引いた位置（0 基準）で詰める**
  （空白パディングを挿入しない）。
- **YOF セクションヘッダの `load_addr` に sec_origin を出力**（従来 R13 で 0 固定だった値）。
- **シンボル offset・reloc offset を YOF 出力時に sec_origin 減算でセクション相対化**。
  UNDEF シンボルの offset は 0 のまま。
- **コード内部のラベル絶対参照（例 `JSR sub_helper`）は sec_origin 基準の絶対値
  （$5108 等）のまま保持**する。これによりセクションが sec_origin に配置されれば
  内部参照は正しい位置を指す（reloc 不要）。

擬似コード（`.org` 処理）:
```
on ".org NEW":
    if yof_mode:
        if not sec_origin_set:
            sec_origin = NEW; sec_origin_set = 1
            pc = NEW                 # pc は絶対アドレスで進む
            # code_buf_pos は 0 のまま（パディングしない）→ code_buf位置 = pc - sec_origin
        else:
            if NEW < pc: error("backward .org")
            while pc < NEW: OUT_BYTE(0); pc++   # 2回目以降は従来通り
```

YOF 出力（write_yof）:
```
section.load_addr = sec_origin
if sec_origin_set:                         # .orgが1つでもあった
    section.flags |= 0x10                  # v2.1 C-3: has_org ビット
for each symbol s:
    out_offset = s.is_undef ? 0 : (s.addr - sec_origin)
for each reloc r:
    out_offset = r.offset - sec_origin
```

**【v2.1・C-3】has_org フラグ**: `.org` を1つでも持つセクションは flags bit4 (0x10) を立てる。
これにより lnk23 が「load_addr=$0000 でも固定配置」と「自動配置」を区別できる（§3.5.3.3）。

#### 3.5.3 lnk23 改修 (D)：load_addr 尊重配置

- **load_yof でセクションの load_addr フィールドと `has_org` フラグ（後述 C-3）を読む。**
  `has_org=1` なら（値が $0000 でも）その load_addr へ**固定配置**。`has_org=0` なら従来通り
  **自動配置**（後方互換）。現状 lnk23.c:341 で 8B 読むが L351 で load_addr を 0 で捨てている。
  この捨てを止め、has_org と共に読んで使う（`.bin` 経路 L459-473 と構造同型の局所改修）。
- 配置後、既存の resolve_symbols → apply_relocations を通して UNDEF を解決
  （この経路は既存・無改修で機能する）。

##### 3.5.3.1 ROM 境界チェックの通過機序【v2.1・M-3-2 確定】

forth は **TEXT 型・load_addr=$5100** で配置されるため text_end が $510C となり、
baremetal モードの ROM 境界チェック（lnk23.c:591-593 `if (opt_machine==MACH_BAREMETAL)
{ if (text_end > 0x3FFF) err(...) }`）に**引っかかる**。

**確定**: 道2 の YUI OS リンクは **`--machine force` モードを使用する**。force モードでは
L591 の baremetal 限定ガードにより ROM 境界チェックが**実行されない**。forth@$5100 は
RAM 領域（$5100〜、yuios_memmap §6）への正当な配置であり、force モードがこれを許容する。
PoC（§3.5.4）が通ったのはこの機序による（`--machine force` 指定を実コードで確認済み）。

> **⚠ 注意（後日の再発防止）**: もし将来 baremetal モードでリンクすると forth@$5100 が
> L592 で静かにエラーになる。**ビルド手順書 v1.6 に「道2 リンクは `--machine force` 必須」を
> 明記**すること。SEC 型を DATA に変える等の回避は採らない（forth は実行コードであり TEXT が正）。

##### 3.5.3.2 固定配置と自動配置の混在【v2.1・M-3-1 確定】

**確定**: 道2 では当面、**全 YOF セクションが `.org`（＝has_org=1）を持つ前提**とし、
**固定配置セクションと自動配置セクションの混在は非サポート**とする。YUI OS は
forth/kernel の2固定のみで自動配置セクションが無いため、現状はこの前提を満たす。
混在を検出した場合（has_org=1 と has_org=0 が同一リンクに共存）は lnk23 が**エラー**とし、
意図しない配置（自動配置セクションが固定セクションの隙間/後方に滑り込む）を防ぐ。
将来 scc23 Phase 2 で混在が必要になれば別途設計する。

overlap チェック（lnk23.c:569-578・全セクション総当たり）は固定配置でもそのまま機能し、
forth@$5100／kernel@$0000 は重ならず通る（PoC 実証済み）。意図的に重なる load_addr を
与えた場合は overlap エラーで弾く（T10 で検証・N-3）。

##### 3.5.3.3 load_addr=0 の意味論確定【v2.1・C-3 確定】

旧 v2.0 §7 Q6 の曖昧性（load_addr=$0000 が「$0000 固定」か「自動配置」か区別不能）を解消する。
kernel は `.org $0000` ゆえ sec_origin=$0000→load_addr=$0000 となり、「$0000 固定」意図と
「未指定＝自動」が同じ $0000 で衝突していた。

**確定**: YOF セクションが `.org` を1つでも持てば sec_origin が確定し、**YOF flags バイト
（既存 8B ヘッダ内・現状 0x0B=ALLOC|EXEC|READ、上位ビット空き）の bit4 (0x10) に
`has_org` フラグを立てて記録**する。これにより:
- `has_org=1`（flags & 0x10）: load_addr が $0000 でも**固定配置**
- `has_org=0`: **自動配置**（後方互換・従来 .obj）

8B ヘッダのバイト数・レイアウトは不変（flags の空きビット利用のみ）。lnk23 は flags の
has_org ビットで固定/自動を判定する。これで kernel@$0000 は「$0000 固定」と明示され、
自動配置との混同が起きない。

#### 3.5.4 PoC 実証結果（CHAT61 続）

最小実配置（forth=$5100＋内部参照 sub_helper、kernel=$0000＋WORD_OS_START UNDEF 参照）で:

| 検証 | 結果 |
|---|---|
| forth 空白除去（size=$510d → **13**） | ✅ |
| forth load_addr=$5100 自動配置 | ✅ |
| kernel→forth クロス UNDEF 解決（A=$5100） | ✅ |
| **内部参照（JSR sub_helper → $5108）保持** | ✅（α-A で壊れた箇所） |
| 実行（A=$BEEF, B=$CAFE） | ✅ |
| セクション overlap なし（kernel@$0000／forth@$5100） | ✅ |
| **非 YOF Dhrystone 回帰（826/48405/P:20）** | ✅（道2 が単一ファイル .bin ビルドを壊さない） |

### 3.6 設計判断の記録：方式α-A（位置独立化）の不採用（v2.0）

当初、forth を `.org $0000`（位置独立 obj）化し配置をリンカに委ねる**方式α-A**を検討したが、
PoC で**不成立**と実証した。理由: hasm23 は**同一ファイル内の定義済みラベル参照を
reloc 化せず、セクション内絶対アドレス（$0000 基準）で直接埋め込む**ため、位置独立 obj を
$5100 に配置すると内部参照（`JSR sub_helper`）が $0008 のまま補正されず壊れる。

位置独立化には**内部参照のセクション相対リロケーション（R_SECREL）導入＝全ラベル参照の
reloc 化**という hasm23 の大改修が必要で、影響甚大。一方、道2 は「`.org` 通りに配置する」
という YOF の実態（内部参照は .org 基準で埋め込み済み）に忠実で、改修が局所的。
よって**道2 を採用、α-A は不採用**とする。



```
[kernel_forth_*.fs]
  │ Force コンパイル
  v [kernel_forth_*.asm]  ← .org $5100 を内包。Force 混入行(#WORD_xxx)あり
  │ ★後処理1: 混入行(#WORD_xxx)を .sym アドレスで #$addr に修正（No.1 sed・残置）
  │           ※対象シンボルは固定リストでなく #WORD_xxx を全自動抽出（手順書の旧固定リストは廃止）
  │ ★後処理2: WORD_OS_START 定義ラベル直前に「.global WORD_OS_START」挿入（案F2）
  │ hasm23 -c でアセンブル（道2: load_addr=$5100 記録・空白除去・WORD_OS_START GLOBAL export）
  v [kernel_forth_*.obj]  ← load_addr=$5100／WORD_OS_START='G'
[kernel_v12_7.asm]
  │ ★恒久ソース修正: 「LDW A, #$e96e」2箇所 → 「LDW A, #$WORD_OS_START」（sed系統②=No.6 廃止）
  │ hasm23 -c でアセンブル（道2: load_addr=$0000・WORD_OS_START は UNDEF 参照・reloc=2）
  v [kernel_v12_7.obj]    ← load_addr=$0000／WORD_OS_START UNDEF
  │ lnk23（道2: 各 obj の load_addr 尊重 → forth@$5100／kernel@$0000 固定配置・UNDEF 自動解決）
  v [yuios.bin] + [yuios.sym]
```

#### 3.7.2 廃止される手順 / 残る手順

| 手順 | 旧 | 新 |
|---|---|---|
| WORD_OS_START の sed 置換（No.6） | 必須 | **廃止** |
| Forth シンボルアドレス sed 置換（No.3） | 必須 | **廃止** |
| JSR _main の sed 直書き（No.2） | 必須 | **廃止** |
| Force 混入行 #WORD_xxx 修正（No.1） | 必須 | **残置**（Force 課題） |
| SECTION 順序 forth 先 → kernel 後 | 必須 | 必須（不変・後勝ちルール） |

#### 3.7.3 SECTION 順序と固定配置（道2）

道2 では各セクションが YOF の load_addr で**固定配置**されるため、kernel@$0000／forth@$5100
は重ならず、従来の「forth 先→kernel 後・後勝ち（mem[] 上書き）」に依存しない。
入力順は配置アドレスに影響しない（load_addr が絶対位置を決める）。ただし lnk23 の
overlap チェックを通すため、各セクションの実コード領域が重複しないこと（kernel ≤$3FFF、
forth $5100〜）を前提とする。

なお後処理1（混入行修正）の対象シンボルは、ビルド手順書 v1.5 の固定リスト
（WORD_MEMMGR_TASK 等5個）では **kernel_forth v0.10.18 の実態（6個）に不足**するため、
**`#WORD_xxx` を全自動抽出する方式**に改める（手順書 v1.6 で反映）。

---

## 4. 影響範囲

| 対象 | 影響 | 対応 |
|---|---|---|
| hasm23 | `.global` 追加・`is_undef` 追加・**道2（.org 空白除去/load_addr 記録/offset 相対化）** | v1.02 → **v1.03** |
| lnk23 | **道2（YOF load_addr 尊重の固定配置）** ~~なし~~ | v2.00 → **v2.01** |
| emu23 | なし | v1.06 維持（F-001 修正済・Step 8-F-1） |
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
| T4 | 同一 UNDEF への**即値・分岐混在の3参照以上**（例: `LDW A,#$WORD_X` ／ `JSR WORD_X` ／ `BRA WORD_X` が同一 UNDEF を参照）【v1.1・N-1】 | reloc=N、全解決。M-1（両経路適用）・M-2（reloc 集約）を一括検証・片側漏れ炙り出し |
| T5 | `.global` 宣言したシンボルが当該ファイルで**未定義**【v1.1・C-2 確定】 | **エラー**（export 専用・実体定義必須） |
| T6 | `.global` 宣言がラベル定義行より**前**（前方参照）【v1.1・N-2】 | PASS1 全走査で拾える・GLOBAL export 成功 |
| **T7** | **道2: `.org $5100` の obj 生成**【v2.0】 | **section size=実コード長（空白除去）・YOF load_addr=$5100・シンボル offset がセクション相対** |
| **T8** | **道2: `.org $5100` obj 内の内部ラベル絶対参照**【v2.0】 | **JSR 等が $5100 基準絶対値（例 $5108）で保持される（reloc 不要）** |
| **T9** | **道2: lnk23 が load_addr を尊重配置**【v2.0】 | **forth@$5100／kernel@$0000 固定配置・overlap なし・内部参照とクロス UNDEF が実行で正解（A=$BEEF, B=$CAFE 相当）** |
| **T10** | **道2: 意図的に重なる load_addr を与える異常系**【v2.1・N-3】 | **overlap エラーで正しく弾く（ガードが効くことの確認）** |

### 5.2 結合テスト

| # | 項目 | 期待 |
|---|---|---|
| I1 | kernel + forth の道2 YOF リンク（sed系統②無し・固定配置） | yuios.bin 生成・forth@$5100/kernel@$0000・WORD_OS_START 解決・reloc=2 |
| I2 | YUI OS 起動 | 期待出力（従来 .bin リンク版と**一致**） |
| **I3** | **道2 yuios.bin と従来 .bin リンク版 yuios.bin のバイト比較**【v2.0】 | **実コード領域が一致（配置・内容の非回帰確認）。【v2.1・N-4】比較対象＝kernel 実体 $0000-$3FFF と forth 実体 $5100-（辞書終端まで）。許容差異＝両領域の隙間（$4000-$50FF 等の未使用パディング $00）に限定。比較スクリプトはこの2領域のみを cmp 対象とする** |

### 5.3 回帰テスト（必須）

hasm23 はツールチェーン構成要素であり、**改修時は Dhrystone 回帰が必須**
（Force 改修以外は回帰必須の原則）。

| 項目 | 基準値 |
|---|---|
| Dhrystones/sec | 826 |
| cycles | 48405 |
| 正答チェック | P:20 |

加えて hasm23 v1.02 の W001/E001 機能の非回帰も確認する。

**【v2.0 追記】道2 の非回帰確認**: 道2 は YOF（-c）モードの `.org` 処理を変更するため、
**非 YOF（.bin 直接出力）モードの Dhrystone ビルドが不変であること**を必ず確認する
（PoC で 826/48405/P:20 一致を実証済み）。「forth だけ見て Dhrystone を見ない」片手落ちを禁ずる。

---

## 6. 実装ステップ（承認後）

1. hasm23_v1_02.c → hasm23_v1_03.c（KY38: 別ファイル名）
2. 改修 (A) `.global` 追加（§3.2.4 の v1.03 仕様＝export 専用・未定義エラー）
3. 改修 (B) `is_undef` 複数参照対応。
   **【v1.1・M-1】改修 (B) は即値経路・分岐経路の両方へ同一改修を適用すること。**
   両経路は別ルーチンとして二重に存在するため（即値 L1006-1035 系／分岐 L1106-1135 系）、
   片側のみ修正する事故が起きやすい。§3.3.2.1 の集約構造を両経路に適用し、
   **片側漏れがないことを T3/T4（特に即値＋分岐混在の T4）で検証**する。
4. 単体テスト T1-T6（A・B 分）。**1 変更 1 検証で (A)→検証→(B)→検証の順**。
5. **改修 (C) 道2：hasm23 YOF モードの `.org` 空白除去・load_addr 記録・offset 相対化（§3.5.2）。
   sec_origin 減算が「コード生成・シンボル offset・reloc offset・W001 重ね書き検出・.vector 書込み」
   の全箇所に整合して波及するか確認（KY: 一箇所でも漏らすと内部参照が壊れる）。
   併せて has_org フラグ（flags bit4=0x10）を出力（§3.5.2・C-3）。**
6. **単体テスト T7-T8（道2 obj 生成・内部参照保持・has_org フラグ確認）。**
7. **lnk23_v2_00.c → lnk23_v2_01.c（KY38）。改修 (D) 道2：YOF load_addr＋has_org 尊重配置（§3.5.3）。
   `--machine force` での ROM 境界回避（§3.5.3.1）・固定/自動混在エラー（§3.5.3.2）も実装。**
8. **単体テスト T9-T10（lnk23 固定配置・実行正解・overlap 異常系）。**
9. Dhrystone 回帰（826/48405/P:20）＋ W001/E001 非回帰。
   **特に道2 が非 YOF（.bin）Dhrystone ビルドを壊さないことを必ず確認（§5.3）。**
10. 結合テスト I1-I3（YUI OS 実ビルド・sed系統② 廃止・道2 固定配置・従来版とのバイト比較）。
11. ビルド手順書 v1.5 → v1.6 改版（後処理1 自動抽出化・後処理2 `.global` 付与・道2 リンク手順）。
12. 関連設計書改版（toolchain23_design 等・lnk23_design）。

**原則43**: 本設計書のレビュー承認を得るまで実装着手しない。
**KY28**: 各改修は実験ファイル名で先行検証可だが、本実装は承認後に本番版数（v1.03/v2.01）で行う。

---

## 7. 未解決・レビュー確認事項

【v2.0 更新】Q1 は案F2 でPoC実証済み（要承認）。Q4 は道2 で前提が変化（YOF load_addr を使用）。
新たに道2 関連の確認事項 Q5・Q6 を追加。

| # | 論点 | 内容 | 状態 |
|---|---|---|---|
| Q1 | Force `.global` 付与方法 | 案F2（後処理付与）で確定し I1 で実証済み（kernel_forth v0.10.18 で WORD_OS_START を `.global` 付与→GLOBAL export 確認）。**要承認** | 実証済・要承認 |
| Q2 | ~~T5 の仕様~~ | → §3.2.4 で確定（C-2） | ✅ クローズ |
| Q3 | No.1（Force 混入行）残置の是非 | 本設計スコープ外で残置。ただし後処理1 の対象を固定リスト→**全自動抽出**に改善（§3.7.3）。別工程化の要否を確認 | 要確認 |
| Q4 | ~~YOF 構造体バイト整合 / lnk23 無改修~~ | **道2 で是正**：YOF の load_addr フィールド（既存 8B ヘッダ内）に sec_origin を記録。バイト数不変だが **lnk23 はこれを読むため改修必要**（旧「無改修」撤回・§3.1） | ✅ 道2 で確定 |
| **Q5** | **道2 の sec_origin 波及範囲** | sec_origin 減算が全 offset 算出箇所（シンボル/reloc/W001/.vector）に漏れなく適用されるか。実装時 §6 ステップ5 で確認。レビューでは設計の網羅性を確認 | 要確認 |
| ~~Q6~~ | ~~load_addr=0 の扱い~~ | → **§3.5.3.3（C-3）で確定**：YOF flags bit4 に `has_org` フラグを新設し、`has_org=1` なら $0000 でも固定配置、`has_org=0` は自動配置と一意に区別 | ✅ C-3 で確定 |

---

## 8. v2.0 根幹是正サマリ（レビュア向け）

本 v2.0 は v1.1（承認済）から**根幹前提が変わった**大改版である。レビューの要点:

1. **旧前提「lnk23 無改修」は実ビルドで崩壊**。YUI OS の2固定アドレス配置（forth $5100／kernel $0000）が原因。
2. **改修対象は hasm23 単独 → hasm23＋lnk23 両改修**に拡大（道2）。
3. **道2 は PoC で完全実証済み**（空白除去・固定配置・クロス UNDEF・内部参照保持・非 YOF Dhrystone 非回帰）。
4. α-A（位置独立化）は内部参照 reloc 無しで**不成立**と実証し不採用（§3.6）。
5. v1.1 で承認済の (A)`.global`・(B)`is_undef` 複数参照対応は**変更なし**（既に hasm23 v1.03 実装・T1-T6 PASS・Dhrystone 回帰済み）。v2.0 の追加分は (C)(D) 道2。

---

*— YSD8800 Project / Step 8-F-2 —*
