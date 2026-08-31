# scc23 v2.06 C-3追補 未定義関数呼び出しのエラー化（案G）設計メモ

- 文書版数: **v0.1（ドラフト・レビュー用）**
- 日付: 2026-08-02
- 対象ツール: scc23（C コンパイラ・YSD8800 ISA2.3）
- 完成形版数: **scc23 v2.06**（本修正完了時に確定）
- 種別: 検証負債対応（Phase 1 / C-3 の追補）
- 起点: **scc23 v2.05**（C-3 案D＋案C 実装済・2026-08-02 確定）
- 作成: Claude（設計・解析担当）
- 上位設計書: `scc23_v2_05_C3_forward_decl_design_v0_3.md`（v2.05 の C-3 設計・承認版）
- 工程表: `scc23_phase_roadmap_v1_0.md` Phase 1
- 発見経緯: **Phase 1 / C-1（マトリクステスト整備）の作業中に発見**。24 ケースの期待値を
  事前確定させたうえで実測と突合したところ、`m1_f_add_c_n` / `m1_f_div_c_n`
  （float×右辺call×プロトタイプなし）の2件が期待 `error_stop` に対し実測
  `warning_only` となり MISMATCH。調査の結果、v2.05 の案D に網羅性の穴があることが判明した。
- 参照原則: 「見えているバグは先に潰すこと。残したまま進行しないこと」／原則43（設計レビュー
  →承認→実装）／KY34（実源照合）／本日 KY「golden は正しいと仮定してはいけない」

---

## 改訂履歴サマリ（KY41）

| 版 | 日付 | 主な変更 |
|----|------|---------|
| v0.1 | 2026-08-02 | 初版（レビュー用ドラフト）。C-1 作業中に発見した v2.05 案D の網羅性の穴（両辺とも未定義 call の場合に float 経路へ入らず不発）を実測で確定。穴が代入だけでなく return 文・関数引数にも存在することを probe で実証。案E（parse_assign 判定）／案F（型不定フラグ伝播）／**案G（未定義 call そのものを error 化）** を比較し、**案G を採用**。プロジェクト内全 C ソースで undeclared warning 0 件を実測し後方互換の実害ゼロを確認。 |

---

## 0. ゴールと前提

### 0.1 ゴール

v2.05 の C-3 修正（案D）が**取りこぼしていた**「**両辺とも前方未定義 call**」のケースで、
Q8.8 float 演算が int 演算（`_cc_mul` / `_cc_div`）として生成され値が壊れる問題を解消する。

完成形を **scc23 v2.06** として確定する。

### 0.2 着手前の絶対条件（原則43）

本書は**設計フェーズの成果物**である。実装着手前に必ず: **レビュー → 指摘反映・承認
→ 工程確認 → KY → 「ご安全に！」→ 実装**。実装は KY38 に従い、本番
`scc23_v2_05.c` は直接改変せず、**新ファイル `scc23_v2_06.c`** として起こす。
**承認前の実装着手は厳禁。**

### 0.3 現在地（KY34・実ファイル確認済）

- scc23 v2.05 確定（`SCC_VERSION "2.05"` / `SCC_DATE "2026-08-02"`）。
- Phase 1 / C-3 は v2.05 で「完了」と記録したが、**本追補により完了条件を満たしていなかった**
  ことが判明（後述 §1）。C-3 の完了判定は本 v2.06 をもって行う。
- Phase 1 / C-1（マトリクステスト整備）は着手済・**本件のため一時中断**。
  設計メモ `scc23_C1_matrix_test_design_v0_3.md` は最終承認済。
- 絶対ゲート：-O0-strict 826/48405/P:20/21846B（v2.05 で byte-exact 維持確認済）。

---

## 1. バグの確定内容（実測実証済）

### 1.1 v2.05 案D の網羅性の穴

v2.05 設計メモ v0.3 §2.4.1 は「ボトムアップ評価により、未定義 SIR_CALL が float 演算に
最初に触れる `binop_promote` 呼び出しで必ず捕捉され、複合式でも漏れない」と論証した。
**この論証には前提の抜けがあった**。

**抜けていた前提**：「float 演算に触れる」と判定されるのは `binop_promote` の
`lf`/`rf`（どちらかが T_FLOAT）が真のときだけである。**両辺とも未定義 call の場合、
両方 T_INT にフォールバックされるため `lf=0, rf=0` となり、int 経路へ入って
そのまま return する**（案D の判定より手前）。

**実源（`scc23_v2_05.c` L1229-1252）**：

```c
static sir_node_t *binop_promote(sir_op_t int_op, sir_node_t *l, sir_node_t *r) {
    int lf = l && l->type==T_FLOAT;      ← 未定義 call は T_INT → lf=0
    int rf = r && r->type==T_FLOAT;      ← 未定義 call は T_INT → rf=0
    if (!lf && !rf) {
        sir_node_t *f = try_fold(int_op, l, r, T_INT);
        if (f) return f;
        sir_node_t *a = fold_algebraic(int_op, l, r);
        if (a) return a;
        return sir_binop(int_op, l, r);  ← ★ここで return。案D に到達しない★
    }
    /* [v2.05 C-3] float 経路 --- 案D の error 判定はここ（到達せず） */
    if (is_undecl_call(l)) { error(...); }
    if (is_undecl_call(r)) { error(...); }
    l = wrap_i2f(l);
    r = wrap_i2f(r);
    ...
}
```

### 1.2 実測による実証（C-1 マトリクステストで検出）

**PoC `m1_f_div_c_n.c`（float×除算×右辺call×プロトタイプなし）**：

```c
int main() {
    float x;
    x = getval() / getval2();
    return 0;
}
float getval(void) { return 2.5; }
float getval2(void) { return 4.0; }
```

**v2.05 の生成コード（実測）**：

```
    JSR  _getval
    SUBI SP, #2
    STW  A, [SP]
    JSR  _getval2
    LDW  B, [SP]
    ADDI SP, #2
    JSR  _cc_div          ← ★int 除算。正解は _fdiv★
```

**プロトタイプありの正解版（`m1_f_div_c_p.c`）との差**：

```
    JSR  _fdiv            ← Q8.8 除算（シフト補正あり）
```

**値破壊の実害**：Q8.8 の `2.5 ÷ 4.0` を int 除算すると
`0x0280 / 0x0400 = 0` となり、正解 `0.625 = 0x00A0` とは全く異なる値になる。

**警告は出るが error にならない（実測ログ）**：

```
m1_f_div_c_n.c:12: warning: call to undeclared function 'getval': assumed to return int. ...
m1_f_div_c_n.c:12: warning: call to undeclared function 'getval2': assumed to return int. ...
scc23: compiled 'm1_f_div_c_n.c'  errors=0     ← ★errors=0 で通過★
```

### 1.3 穴は代入以外にも存在（probe で実証）

当初「代入先の型を見れば足りる」と考えたが、**probe による実測で否定された**。

| 文脈 | probe | 実測結果 |
|---|---|---|
| 代入 `float x = a()/b();` | m1_f_div_c_n | `_cc_div` 生成・error なし |
| **return 文** `return a()/b();`（float 関数内） | probe1 | `_cc_div` 2件・`_fdiv` 0件・error なし |
| **関数引数** `use(a()/b());`（float 引数） | probe2 | `_cc_div` 2件・`_fdiv` 0件・error なし |

**結論**：穴は「float 文脈の種類」に依存せず、**未定義 call の型仮定そのもの**に起因する。
代入だけを直しても取りこぼす。

### 1.4 発現条件の整理

| 左辺 | 右辺 | v2.05 案D | 結果 |
|---|---|---|---|
| 未定義call | float定数/変数 | 発火 ✅ | error_stop（正しい） |
| float定数/変数 | 未定義call | 発火 ✅ | error_stop（正しい） |
| **未定義call** | **未定義call** | **不発 ❌** | **warning のみ・int 演算生成・値破壊** |

**演算別の実害**：
- **加算・減算**：Q8.8 同士の加減算は int 加減算と**ビット演算として同一**のため、
  偶然正しい結果になる（実害は顕在化しない）
- **乗算・除算**：`_cc_mul` / `_cc_div` が呼ばれ Q8.8 補正が入らないため
  **確実に値が壊れる**

---

## 2. 修正案の比較

### 2.1 候補案

| 案 | 概要 | 実装範囲 | 網羅性 | 後方互換 | 判定 |
|---|---|---|---|---|---|
| 案E | `parse_assign` で左辺 T_FLOAT 時に右辺ツリーを走査し検出 | 小 | ❌ return文・関数引数を取りこぼす（§1.3 実測） | ○ | **却下** |
| 案F | `sir_node_t` に「型不定（未定義call由来）」フラグを持たせ式ツリーに伝播、float 文脈判定時に error | 中〜大 | ○ | ○ | 保留（案G で足りるため） |
| **案G** | **未定義 call そのものを error 化（プロトタイプ必須化）** | **最小（1行）** | **○ 完全** | **○（実測で影響0件）** | **★採用★** |

### 2.2 案E 却下の根拠

§1.3 の probe 実測により、**return 文・関数引数でも同じ値破壊が起きる**ことが判明した。
`parse_assign` だけを直しても取りこぼすため、C-3 の完了条件（値破壊の阻止）を満たさない。

### 2.3 案F 保留の根拠

網羅性は確保できるが、`sir_node_t` の意味論変更＋型伝播の全経路への影響があり、
Dhrystone 絶対ゲート破壊リスクが案G より高い。**案G で同じ目的を最小改変で達成できる**
ため、本 Phase では採用しない（将来 Phase 2 の型システム統合時に再検討可・§7.2）。

### 2.4 案G の詳細（採用）

**方針**：未定義関数呼び出しを検出した時点で **error 化**する。型が不明な call を
式に持ち込ませないことで、float 文脈の種類（代入・return・引数・複合式）を問わず
**原理的に値破壊を阻止**する（fail-safe）。

**修正コード案**（`scc23_v2_05.c` L1937-1948 相当）：

```c
            {
                sym_t *cfs=sym_find(name);
                if (cfs && cfs->sclass==SC_FUNC) {
                    cn->type = cfs->type;
                    cn->base = cfs->base;
                } else {
                    /* [v2.06 C-3追補/案G] 未定義関数呼び出しを error 化。
                       v2.05 は warning + T_INT フォールバックだったが、
                       「両辺とも未定義 call」のとき binop_promote が int 経路へ
                       落ち、案D の float 文脈判定に到達しないまま _cc_mul/_cc_div
                       が生成され Q8.8 の値が壊れる穴があった（C-1 作業中に発見）。
                       穴は代入だけでなく return 文・関数引数にも存在するため、
                       型不明な call を式に持ち込ませない fail-safe とする。
                       (設計書 scc23_v2_06_C3_undecl_call_error_design_v0_x.md §2.4) */
                    error("call to undeclared function '%s': "
                          "add a prototype declaration before use "
                          "(implicit int return is not assumed)",
                          name);
                    cn->type = T_INT; cn->base = T_INT;  /* 後段解析継続のため型は入れる */
                }
            }
```

**変更点**：
- `warning(...)` → `error(...)` へ格上げ（1関数呼び出しの変更）
- メッセージを「int と仮定した」から「プロトタイプ宣言を追加せよ」へ変更
- `cn->type = T_INT` の代入は**維持**（`error()` は生成を止めないため、後段の
  NULL 参照等を避ける目的で型は入れておく）

**案D（v2.05 の `binop_promote` 内 error）の扱い**：
- **残置する**。案G で未定義 call は全て error になるため案D は実質デッドコードとなるが、
  **多重防御（defense in depth）として残す**。将来 case G が緩和された場合の保険。
- 案D が出す error メッセージは案G の後に出るため、1つの未定義 call に対し
  最大2件の error が出る可能性がある。これは**許容**（どちらも同じ問題を指しており、
  ユーザの対処法は同一「プロトタイプを書く」）。

### 2.5 案G の妥当性根拠

1. **網羅性が原理的に完全**：未定義 call が存在した時点で止まるため、
   float 文脈の種類・複合式の深さ・両辺の組合せを問わない
2. **実装が最小**：1行の変更（`warning` → `error`）＋メッセージ調整
3. **後方互換の実害ゼロ**（実測）：プロジェクト内の全 C ソースで
   undeclared warning が **0 件**（§3.1）
4. **C 標準に整合**：C99 以降は暗黙の関数宣言（implicit function declaration）が禁止。
   GCC/Clang でも `-Werror=implicit-function-declaration` が現代の既定に近い
5. **fail-safe 原則**：「型が分からないものは通さない」

---

## 3. 安全性・副作用の解析

### 3.1 既存 C ソースへの影響（実測済・影響ゼロ）

v2.05 で各ソースをコンパイルし `warning: call to undeclared` の件数を実測：

| ソース | undeclared warning 件数 | 案G 適用時の影響 |
|---|---|---|
| `dhry_all_ansi2.c`（**絶対ゲート対象**） | **0 件** | **なし（絶対ゲート無傷）** |
| `fib.c` | 0 件 | なし |
| `sd_sample.c` | 0 件 | なし |
| `v6_sdread_test_poc.c` | 0 件 | なし |
| `v8_catls_demo_poc.c` | 0 件 | なし |
| `dhry_timer.c` | 0 件 | なし |

**結論**：プロジェクト内の実運用 C ソースは全てプロトタイプ完備であり、
**案G を適用しても既存ビルドは一切影響を受けない**。

### 3.2 Dhrystone 絶対ゲートへの影響

`dhry_all_ansi2.c` の undeclared warning が 0 件であることから、案G 適用後も
**error は発生せず、生成コードは v2.05 と byte-exact 一致**する見込み。
V2 検証で実測確認する。

### 3.3 `dhry_all.c`（K&R 版）への影響

- 現状 v2.04/v2.05 ともに **167 件の error**（K&R パラメータ宣言・`#define` 未対応）で
  コンパイル不能（本チャットで実測済）
- 案G により undeclared call の error が加算される可能性があるが、
  **元々コンパイル不能なので実害の変化はない**
- K&R サポートは Phase 3（プリプロセッサ移植）の課題（§7.1）

### 3.4 C-1 マトリクステストへの影響（期待値の変更）

案G 適用により、C-1 の 24 ケースのうち **`proto=n`（プロトタイプなし）の 12 ケース全てが
`error_stop` になる**。C-1 設計メモ v0.3 §1.2 の期待挙動表を更新する必要がある。

| プロトタイプ | 戻り値型 | v2.05 期待 | **v2.06 期待** |
|---|---|---|---|
| あり | int | compile_ok | compile_ok（不変） |
| あり | float | compile_ok | compile_ok（不変） |
| なし | int | warning_only | **error_stop（変更）** |
| なし | float | error_stop | error_stop（不変・ただし発火元が案G に変わる） |

**C-1 の期待値マトリクス（24 ケース）の改訂**：
- compile_ok: 12 件（不変）
- warning_only: 6 件 → **0 件**
- error_stop: 6 件 → **12 件**

**golden 基準版**：C-1 設計メモ v0.3 §1.2 / §7.5 の「golden 基準版 = scc23 v2.05」を
**v2.06 へ更新**する。C-1 はまだ golden を凍結していない（本件で中断）ため、
握り潰しのリスクなく更新できる（不幸中の幸い）。

### 3.5 emu23 動作への影響

生成コードが不変（既存ソースは全て error なし）のため、emu23 上の実行結果も不変。

---

## 4. 検証計画（実装承認後に実施）

### 4.1 V1: 穴の閉塞確認（本件の核心）

`m1_f_div_c_n.c` / `m1_f_add_c_n.c`（両辺未定義 call）を v2.06 でコンパイルし：
- **error が発生する**（非0終了）
- error メッセージに `undeclared function` が含まれる
- **`_cc_div` を含む壊れた asm が「正解」として通過しない**

### 4.2 V2: Dhrystone 絶対ゲート維持（プロジェクト規約）

- `dhry_all_ansi2.c` を v2.05 と v2.06 でビルドし、生成 asm の
  **バナー行以外 byte-exact 一致**を確認
- emu23 上で `-O0-strict` 完走し **826/48405/P:20/21846B** を維持
- error 0 件を確認

### 4.3 V3: -O1 トラック維持

- -O1 で生成 asm がバナー行以外 v2.05 と一致（**cycles 47795 維持**）

### 4.4 V4: 既存ソース回帰

§3.1 の全ソース（fib.c / sd_sample.c / v6_sdread_test_poc.c / v8_catls_demo_poc.c /
dhry_timer.c）を v2.06 でビルドし、**error 0 件・生成 asm が v2.05 と一致**を確認。

### 4.5 V5: C-3 元 PoC 回帰（v2.05 の case1〜case6）

- case1（プロトタイプあり）：error なし・v2.05 と byte-exact
- case2〜case4（プロトタイプなし）：error 発生
- case5（プロトタイプあり float）：error なし
- case6（再帰）：error なし

### 4.6 V6: C-1 マトリクス全 24 ケース

§3.4 の改訂後の期待値（compile_ok 12 / error_stop 12）で **24/24 MATCH** を確認。
この確認をもって C-1 の golden 凍結へ進む。

---

## 5. 実装手順（承認後の実装フェーズ）

1. `scc23_v2_05.c` を `scc23_v2_06.c` にコピー
2. `SCC_VERSION` を `"2.05"` → `"2.06"`、`SCC_DATE` を `"2026-08-02"` のまま（同日）
3. 冒頭ヘッダに v2.06 改版履歴を追記（v2.05 以前の履歴は保持・KY41）
4. `parse_primary` の T_INT フォールバック分岐（L1937-1948 相当）の
   `warning(...)` を `error(...)` に変更しメッセージを差替（§2.4）
5. 案D（`binop_promote` 内 error）は**残置**（多重防御・§2.4）
6. コンパイル成功確認（`gcc -std=c99 -O2 -Wall -o scc23_v2_06 scc23_v2_06.c`）
7. バナーが `scc23 v2.06` を表示することを確認
8. §4 V1 → V2 → V3 → V4 → V5 → V6 の順で検証
9. 全 PASS 後、`tool_version_ledger` を v1.14 へ改版
10. **C-1 設計メモを v0.4 へ改版**（§3.4 の期待値マトリクス改訂・golden 基準版を v2.06 へ）
11. C-1 実装フェーズを再開（golden 凍結から）

---

## 6. 実装前の追加確認事項

1. `error()` の実装（L536-542）が `error_count++` のみで exit しないことの再確認（済・v2.05 で確認）
2. 案G と案D の二重 error 発生時のメッセージ重複が許容範囲か（§2.4 で許容と判断・レビュー確認事項）
3. `cn->type = T_INT` を残す判断の妥当性（error 後も解析継続するため型は必要）

---

## 7. 将来課題（申し送り・KY41）

### 7.1 K&R スタイルサポート

`dhry_all.c` のような K&R スタイルは現状コンパイル不能（167 error）。
案G により暗黙の int 宣言も明示的に禁止されるため、K&R サポートを行う場合は
Phase 3（プリプロセッサ移植・scc22 v3_03 からの移植）で
**プロトタイプ自動生成 or 暗黙 int の許可オプション**の導入を検討する。

### 7.2 案F（型不定フラグ伝播）の再検討余地

案G は「未定義 call を一切許さない」強い制約。将来 K&R 互換モード等で
未定義 call を許容する必要が生じた場合、案F（型不定フラグを伝播し
float 文脈でのみ error）を実装すれば、より柔軟な制御が可能になる。
Phase 2（型システム統合）で `sir_node_t` を拡張する際に併せて検討。

### 7.3 error 抑止フラグ

将来 `-Wno-error=implicit-decl` 相当のオプション追加を検討。
現時点では追加せず、値破壊阻止を最優先とする（v2.05 §7.3 の判断を継承）。

### 7.4 v2.05 設計メモ §2.4.1 の網羅性論証の訂正

`scc23_v2_05_C3_forward_decl_design_v0_3.md` §2.4.1 は
「複合式でも漏れない」と論証したが、**両辺とも未定義 call のケースが抜けていた**。
本 v2.06 設計メモの承認後、v2.05 設計メモを **v0.4 へ改版**し、
§2.4.1 に「ただし両辺とも未定義 call の場合は float 経路に入らないため不発。
v2.06 の案G で閉塞」と追記する（KY41・前版情報は取り消し線で保持）。

### 7.5 レビュー・検証プロセスへの教訓（kaizen 候補）

- v2.05 の検証（V1〜V5）は「片側が float 定数/変数」のケースのみを試験しており、
  **両辺とも未定義 call の組合せを試験していなかった**
- C-1 のマトリクステスト（戻り値型×演算×**右辺種別**）を整備したことで、
  「右辺種別 = call」という次元が追加され、初めて発見できた
- **教訓**：修正の検証は「修正対象の判定条件が**偽になる経路**」も網羅すべき。
  案D は `lf || rf` が真の経路のみ試験し、偽になる経路（両辺 T_INT）を見落とした
- kaizen.txt への原則追加を提案（レビューで要否判断いただきたい）

---

## 8. 参照資料

- `scc23_v2_05.c` L536-548（error/warning）、L1229-1252（binop_promote）、
  L1937-1948（parse_primary の T_INT フォールバック）
- `scc23_v2_05_C3_forward_decl_design_v0_3.md` §2.4/§2.4.1（案D の網羅性論証・要訂正）
- `scc23_C1_matrix_test_design_v0_3.md` §1.2/§7.5（期待挙動表・golden 更新ルール）
- `scc23_phase_roadmap_v1_0.md` Phase 1 定義
- 本設計メモ起票時の実測（m1_f_div_c_n / probe1 / probe2 / 全ソース warning 件数）
- `kaizen.txt`「見えているバグは先に潰すこと」／原則43／KY34

---

## 9. レビュー観点（レビュアへの依頼事項）

1. **§1 のバグ機序と実測実証は妥当か**（両辺未定義 call → int 経路 → 案D 不発）
2. **§1.3 の穴の広がり（return 文・関数引数）の実証は十分か**
3. **§2 の案G 採用根拠は妥当か**（案E 却下・案F 保留の理由）
4. **§2.4 の修正コードは正しいか**（`warning`→`error`・`cn->type=T_INT` 残置・案D 残置）
5. **§3.1 の後方互換影響ゼロの実測は十分か**（他に確認すべきソースはないか）
6. **§3.4 の C-1 期待値マトリクス改訂（warning_only 6件 → 0件、error_stop 6件 → 12件）は妥当か**
7. **§7.4 の v2.05 設計メモ改版（v0.4）の要否**
8. **§7.5 の教訓を kaizen.txt の原則として追加すべきか**

---

## 改版履歴

| 版 | 日付 | 内容 |
|---|---|---|
| v0.1 | 2026-08-02 | 初版（レビュー用ドラフト）。C-1 マトリクステスト整備中に発見した v2.05 案D の網羅性の穴（両辺とも未定義 call のとき `binop_promote` が int 経路へ落ち案D の float 文脈判定に到達しない）を実源照合＋実測で確定。穴が代入だけでなく return 文・関数引数にも存在することを probe1/probe2 で実証（いずれも `_cc_div` 生成・`_fdiv` 0件）。案E（parse_assign 判定・網羅性不足で却下）／案F（型不定フラグ伝播・保留）／**案G（未定義 call を error 化・採用）** を比較。プロジェクト内全 C ソース（dhry_all_ansi2.c 含む）で undeclared warning 0 件を実測し後方互換の実害ゼロを確認。C-1 期待値マトリクスの改訂（warning_only 6→0件、error_stop 6→12件）と golden 基準版の v2.06 への更新を §3.4 に明記。v2.05 設計メモ §2.4.1 の論証訂正（v0.4 改版）を §7.4 に、検証プロセスの教訓（判定条件が偽になる経路も網羅すべき）を §7.5 に申し送り。 |

— 以上 —
