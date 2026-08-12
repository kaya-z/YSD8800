# V8-D Step K: PC遷移生ダンプ 設計メモ

- **文書ID**: v8d_stepK_pcdump_design_memo_v0_5.md
- **作成日**: 2026-07-25
- **前版**: v0.4 (2026-07-25) — 条件付き差戻し（出典表記の重大な不正確・v0.3 実測を活かせず観測点誤シフト）
- **前々版**: v0.3 (実装済み・実測完了) / v0.2 / v0.1
- **前工程**: CHAT116 Step I 結論・HANDOVER_CHAT116.md §5 Step K 指示
- **目的**: **PC=$2610 到達後の PC 遷移** を毎cyc生ダンプし、$248D への遷移機序を確定する（HANDOVER_CHAT116.md L68 準拠に回帰）
- **状態**: 設計中（v0.4 の観測点シフトを撤回・v0.3 実測を活かす代替案「Ch_Loc 値追跡モード」採用・レビュー待ち）

---

## 0. v0.4→v0.5 変更の要旨（先頭で明示）

### 変更理由（v0.4 レビュー指摘1・2への対応）

**v0.4 の重大な誤り**: v0.4 §0/§1 で「CHAT116 Step I 最終結論・Step J 案(1) の観測ターゲットは $262D JMP _L_0150」と引用したが、**HANDOVER_CHAT116.md には該当記述が存在しない**。実際は `tb_cpu_v8d_dhry_stepJ_jmp.sv` L338-339 のコメント（「実は $2626 が BGE (私が誤解していた)」）および L502-505 の initial `$display` 文（Step J 実装時の作業仮説メモ）を、私が **HANDOVER 記載の確定情報と誤読**した。KY-K-add4「HANDOVER 精読による再発防止」の趣旨と正面から衝突する事態。

**HANDOVER_CHAT116.md 実源**（v0.5 で厳密に行番号付き引用）:
- **L41**: `Ch_Loc の参照 → アセンブラ $2610: LDW A, [X + #$FFFA] (2バイト読み)` — $2610 は LDW 実行位置
- **L47**: `$2610 の LDW 命令実行中に何かで PC が $248D に飛ぶ機序は未解明`
- **L51**: `仮説θ1: LDW A, [X+imm16] の実装バグ`
- **L55**: `仮説θ2: IRQ 受理経路の異常`
- **L60**: `仮説θ3: scc23 コード生成バグ（Ch_Loc の型不整合）`
- **L68-70**: `Step K: PC 遷移生ダンプ ($2610到達後、次の 50cyc の PC を1cyc毎に記録) - $2610→$?→$?→...→$248D の中間PCを実測 - IRQ受理経路か、LDW命令実装バグか、他かを確定`
- **L115**: `「$248D に PC が飛ぶ」の説明で「JSR/CALL 由来」の可能性も排除しないこと（LDW とは限らない）`

**v0.3 実測結果の位置づけ（レビュー指摘3対応）**: v0.3 実測（100 エピソード全て $2610→$24C9 の while 継続経路）は「v0.3 の仮説が誤り」ではなく、**探索空間を絞り込んだ成果**として位置づける。Ch_Loc<'W' が100連続成立していた事実から、$248D 遷移エピソードは Dhrystone 走行のより後段の低頻度事象と推定される。

### 変更範囲

| 節 | v0.4 | v0.5 |
|---|---|---|
| §0/§1 出典表記 | 「HANDOVER 記載」と誤引用 | **HANDOVER_CHAT116.md の行番号 (L41/L47/L51/L55/L60/L68/L115) 明記** |
| §2 仮説 | θ1〜θ4 (JMP系4本) | **HANDOVER §4 準拠 θ1 (LDW)/θ2 (IRQ)/θ3 (scc23) + θ4 (JSR/CALL) 復元** |
| §3.2 dump 開始 | PC=$2626 (BGE) | **PC=$2610 に回帰** (HANDOVER L68 準拠) |
| §3.2 dump 停止 | PC=$2634 or $2630 or 100cyc | **PC=$248D 到達で $finish のみ**（20cyc経過で dump停止・ep 継続） |
| §3.2 ダンプ項目 | PC/A/B/X/SP/FLAGS/PSRAM | **+ Ch_Loc実値 ([X-6][X-5]) をエピソード開始マーカに追加** |
| §3.2 エピソード数 | 100（累計5000行安全弁で強制停止） | **無制限**（累計50000行安全弁 or max_cyc） |
| §3.2 観測窓 | 100cyc | **20cyc**（$2610 直後の PC のみ確認） |
| §3.4 停止条件 | $2634/$2630/$248D/50cyc/5000行 | **$248D で $finish / 20cyc で dump停止 ep 継続 / 50000行安全弁** |
| §6 KY | KY-K-add4 (出典整合) 追加したが自ら違反 | **KY-K-add4 の実効性回復**（PC値・引用は全て HANDOVER 行番号明記）+ KY-K-add5 新規（v0.4 事故の再発防止） |

### 変更しない範囲（v0.3 継承・v0.4 でも変更しなかった部分）

- 案K1（毎cyc生ダンプ）
- 案C（全ブロッキング代入 `=`・エピソード開始マーカ縮小）
- PSRAM信号（addr/wdata/we/req/ack/rdata）観測

---

## 1. 背景

### 1.1 CHAT116 の実源（HANDOVER_CHAT116.md 準拠）

HANDOVER_CHAT116.md L41-47 (発見2・3):
> Ch_Loc の参照 → アセンブラ $2610: **LDW A, [X + #$FFFA]** (2バイト読み)  
> Ch_Loc 汚れは A レジスタに影響するだけで PC には無関係のはず。**$2610 の LDW 命令実行中に何かで PC が $248D に飛ぶ機序は未解明**。

HANDOVER_CHAT116.md L51/L55/L60 (§4 未検証仮説):
- **θ1**: LDW A, [X+imm16] の実装バグ (opcode 0x26)
- **θ2**: IRQ 受理経路の異常
- **θ3**: scc23 コード生成バグ (Ch_Loc の型不整合、Char型を STB書き / LDW読みで型不整合)

HANDOVER_CHAT116.md L68-70 (§5 次チャットで実施):
> Step K: PC 遷移生ダンプ (**$2610到達後、次の 50cyc の PC を1cyc毎に記録**)  
> - $2610→$?→$?→...→$248D の中間PCを実測  
> - IRQ受理経路か、LDW命令実装バグか、他かを確定

HANDOVER_CHAT116.md L115 (§9 KY予測):
> 「$248D に PC が飛ぶ」の説明で「**JSR/CALL 由来**」の可能性も排除しないこと（LDW とは限らない）

### 1.2 v0.3 実測の新事実（探索空間絞込成果）

v0.3 は HANDOVER L68 指示に忠実だった。v0.3 実測結果:

- **100 エピソード連続で $2610→$24C9 の while 継続経路**（Ch_Loc<'W' 成立、BGE _L_0149 が $2630 に飛ぶ）
- **$248D 遷移は100 エピソードでは1回も発生せず**
- 累計5000行安全弁（=100エピソード×50cyc）で強制停止

**この実測の意味**（レビュー指摘3対応）:
- Step I が集計した「$2610 到達 3557回」の中に $248D 異常遷移が含まれているが、100 サンプルでは異常経路にヒットしなかった
- **$248D 遷移は Dhrystone 走行のより後段（別 iloop・別 while 反復）で発生する低頻度事象**
- Ch_Loc の値が Dhrystone の実行フェーズ（Str_1_Loc/Str_2_Loc に代入される文字列の実データ）に応じて変化する

### 1.3 v0.4 の暴走仮説（撤回記録）

v0.4 で「$262D JMP _L_0150 が真因」と主張した根拠は、CHAT116 チャット中の私の**仮説メモ**および `tb_cpu_v8d_dhry_stepJ_jmp.sv` の作業コメント（L338-339「実は $2626 が BGE (私が誤解していた)」）を、HANDOVER の確定情報と**私が誤読**したもの。**HANDOVER には $262D JMP を真因とする記述は存在しない**。v0.5 で全面撤回する。

## 2. 目的（v0.5 で HANDOVER §4/§5 に回帰）

**PC=$2610 到達後の PC 遷移**を毎cyc生ダンプで実測し、以下の4仮説のいずれかを確定する:

| 仮説 | 予想される観測パターン | 出典 |
|---|---|---|
| **θ1**: LDW A, [X+imm16] の実装バグ (opcode 0x26) | $2610 で PSRAM が $260A (=X-6) を read するはずが addr が異常 or rdata が誤り、直後 PC=$248D | HANDOVER L51 |
| **θ2**: IRQ 受理経路の異常 | $2610 実行後、IRQベクタ相当 ($0025 or 他) を経由して $248D | HANDOVER L55 |
| **θ3**: scc23 コード生成バグ (Ch_Loc 型不整合) | LDW/PSRAM は正常、Ch_Loc の値そのものが誤り、$2610 通過→$248D遷移までの中間PCが scc23 生成コードの想定と異なる | HANDOVER L60 |
| **θ4**: JSR/CALL 由来の PC 破壊（v0.5 で HANDOVER L115 KY予測を反映） | $2610 実行後、SP push/pop が発生し PC が誤って更新される | HANDOVER L115 |

## 3. 実装方針

### 3.1 ベース

- 現 `tb_cpu_v8d_dhry_stepK_pcdump.sv` (v0.1、v0.3準拠で実装済・実測済) をベースに **v0.4 の $2626/$2630/$2634 分岐を撤回し v0.3 準拠に戻したうえで、Ch_Loc値追跡と観測窓20cyc、累計50000行に変更**
- ファイル名継続: `tb_cpu_v8d_dhry_stepK_pcdump.sv` (バージョンヘッダを v0.1→v0.2 更新)
- 派生元は `tb_cpu_v8d_dhry_stepJ_jmp.sv`（不変）

### 3.2 追加ロジック（案K1+案C 継承・Ch_Loc値追跡追加）

**変数**（v0.3 と同一・変更なし）:
```systemverilog
logic       k_dump_active;
integer     k_dump_cnt;
integer     k_episode;
integer     k_total_dumped;
```

**動作ロジック**:

```systemverilog
    // PC変化検出 case 内
    16'h2610: begin  // ★v0.5: dump 開始は $2610 に回帰（HANDOVER L68 準拠）
        L0140_ent = L0140_ent + 1;
        k_dump_active = 1'b1;
        k_dump_cnt    = 0;
        k_episode     = k_episode + 1;
        // ★v0.5 新規: Ch_Loc実値をエピソード開始マーカに含める
        //   $2610 = LDW A, [X + #$FFFA] は Ch_Loc の読み出し。
        //   Ch_Loc は [X-6] (下位バイト) + [X-5] (上位バイト) に格納。
        //   Ch_Loc値の変動を観測することで、Ch_Loc==$248D 相当値の周回を捕捉。
        $display("★[STEPK ep=%0d cyc=%0d] $2610 (L_0140) 到達 - PC遷移生ダンプ開始  Ch_Loc [X-6=%04h][X-5]=%02h %02h",
                 k_episode, to_cyc,
                 dbg_x - 16'd6,
                 u_membus.u_psram_ctrl.mem[dbg_x - 16'd6],
                 u_membus.u_psram_ctrl.mem[dbg_x - 16'd5]);
    end
    16'h248D: begin  // ★v0.5: BUG検出（$finish は毎cyc動作で判定）
        func2_ent = func2_ent + 1;
        if (k_dump_active) begin
            $display("★★★ [STEPK ep=%0d cyc=%0d] BUG DETECTED! PC=$248D 到達 (n=%0d cyc)",
                     k_episode, to_cyc, k_dump_cnt);
        end
    end
```

**毎cyc動作ブロック**:

```systemverilog
    if (k_dump_active) begin
        k_dump_cnt = k_dump_cnt + 1;
        k_total_dumped = k_total_dumped + 1;
        $display("  [K ep=%0d n=%0d cyc=%0d] PC=%04h A=%04h B=%04h X=%04h SP=%04h FLAGS=%04h PSRAM: req=%0b we=%0b ack=%0b addr=%05h wdata=%02h rdata=%02h",
                 k_episode, k_dump_cnt, to_cyc,
                 dbg_pc, dbg_a, dbg_b, dbg_x, dbg_sp, dbg_flags,
                 u_membus.u_psram_ctrl.req, u_membus.u_psram_ctrl.we,
                 u_membus.u_psram_ctrl.ack, u_membus.u_psram_ctrl.addr,
                 u_membus.u_psram_ctrl.wdata, u_membus.u_psram_ctrl.rdata);
        // 停止判定
        if (dbg_pc == 16'h248D) begin
            $display("  [STEPK] BUG cyc の n=%0d ダンプ済 → $finish", k_dump_cnt);
            $finish;
        end
        if (k_dump_cnt >= 20) begin  // ★v0.5: 50→20 (窓縮小・ep数緩和)
            // 20cyc到達で dump停止するが ep は継続（次の$2610到達で再開）
            k_dump_active = 1'b0;
        end
        if (k_total_dumped >= 50000) begin  // ★v0.5: 5000→50000 (ep無制限化)
            $display("  [STEPK] SAFETY: 累計50000行到達→強制停止");
            $finish;
        end
    end
```

**注**:
- $2618 の dump 停止処理は v0.5 では**削除**（v0.3 では入れていたが、20cyc 窓で自然に停止するため不要）
- $2618/$261A/$2626/$2630/$2634 case は Step J 既存の観測（bge_dump_cnt / ldw_dump_cnt / jmp_dump_cnt / L0149_ent / L0150_ent）はそのまま残す
- Step J の Func_2 RET ダンプ（10回制限）も残す

### 3.3 ダンプフォーマット

```
★[STEPK ep=1 cyc=XXXXXX] $2610 (L_0140) 到達 - PC遷移生ダンプ開始  Ch_Loc [X-6=XXXX][X-5]=XX XX
  [K ep=1 n=1 cyc=XXXXXX] PC=2610 A=... B=... X=... SP=... FLAGS=... PSRAM: req=... addr=... rdata=...
  ... (20cyc分、以降ep=2で$2610再到達まで dump 抑止)
★[STEPK ep=2 cyc=YYYYYY] $2610 (L_0140) 到達 - PC遷移生ダンプ開始  Ch_Loc [X-6=XXXX][X-5]=XX XX
  ...
★★★ [STEPK ep=N cyc=ZZZZZZ] BUG DETECTED! PC=$248D 到達 (n=%d cyc)  ← 真因確定
  [STEPK] BUG cyc の n=... ダンプ済 → $finish
```

### 3.4 停止条件（優先順）

1. **$248D 到達 cyc の n=... ダンプ完了後** → `$finish`（真因確定）
2. **累計 50000 行到達** → `$finish`（安全弁・上限見込み: 3557回×20cyc=71,140行、50000行で ep≈2500 相当）
3. **20cyc 経過** → dump 停止・**エピソード継続**（次の $2610 到達で ep+1）
4. **HALT 到達** → 元TB終了処理
5. **max_cyc 到達** → タイムアウト

### 3.5 既存 Step J 出力の扱い

- v0.4 で削除案とした Step J $2618/$261A ダンプは **v0.5 では残す**（$2610到達の Step K dump と併存、$2626/$2630/$2634 の Step J エントリカウンタも維持）
- Step J の Func_2 RET ダンプ（10回制限）も残す（$248D 到達時の post-mortem 補助）
- **v0.3 実装済みの $2610 case (post_jmp_dump_cnt<3) は Step K TB 内で削除**（Step K のエピソード開始マーカに統合）— これは v0.3 で既に実施済み、v0.5 でも継続

## 4. TB以外の変更

- 現 v0.1 TB を **v0.2 に版数アップ**して修正（元TB `tb_cpu_v8d_dhry_stepJ_jmp.sv` は不変）
- v0.4 では未実装（差戻し）なので、v0.3 実装 → v0.5 修正の1ステップで反映

## 5. 実行手順

1. **v0.3 → v0.5 差分適用**:
   - v0.3 の $2610 case のエピソード開始マーカに **Ch_Loc実値ダンプを追加**
   - $2618 case の dump停止処理を削除
   - `k_dump_cnt >= 50` → `>= 20`
   - `k_total_dumped >= 5000` → `>= 50000`
   - バージョンヘッダを v0.1→v0.2 更新
2. iverilog ビルド（RTL 依存は v0.3 と同一・確定済）
3. **短時間走行 (max_cyc=1万) で $2610 未到達＝ダンプ0行を確認**
4. 本走 (max_cyc=1000万) で $248D 到達 or 50000行到達を観測
5. 結果を θ1〜θ4 で判定

## 6. KY再確認（v0.5 で KY-K-add4 実効性回復・KY-K-add5 新規追加）

| KY 項目 | 対応 |
|---|---|
| （v0.3 継承 8項目） | 変更なし |
| **KY-K-add4** (v0.4 で追加した項目) | **v0.5 で実効性回復**: PC値・仮説・引用は全て **HANDOVER_CHAT116.md の行番号 (L41/L47/L51/L55/L60/L68/L115)** を §1 に明記。設計メモ本文の PC値は HANDOVER 記述と1対1で照合。 |
| **KY-K-add5** (v0.5 新規): **v0.4 事故（作業メモ・TB コメントを HANDOVER の確定情報と誤読）の再発防止** | 出典引用は必ず「引用元ファイル名 + 行番号 or 節番号」まで書く。原則5.1（実源照合）を運用強化。「HANDOVER 記載」等の曖昧引用は禁止、常に **`HANDOVER_CHAT116.md L47`** のように行番号を付す。 |

## 7. 期待される結論

| ダンプ結果 | 判定 |
|---|---|
| $2610 で PSRAM read の addr が $260A (=X-6) 以外 | **θ1** (LDW アドレス生成バグ) |
| $2610 で PSRAM read の rdata が Ch_Loc 期待値と不一致 | **θ1** (LDW writeback/PSRAM ctrl バグ) |
| $2610 → IRQベクタ ($0025 等) の中間PC を経由して $248D | **θ2** (IRQ 受理経路) |
| $2610 の LDW A の値が想定 Ch_Loc と異なる（PSRAM read は正常だが FLAGS/A が異常） | **θ3** (scc23 コード生成バグ) |
| $2610 実行後、SP に何か PUSH され、その後 POP で PC=$248D | **θ4** (JSR/CALL 由来 PC 破壊) |
| 累計50000行到達も $248D 未到達 | 「サンプル不足」→ Ch_Loc の値変化パターンをログから解析、$248D 発生条件を推定 |

### 事前予測（レビュー指摘2対応）

v0.3 実測から、Ch_Loc<'W' が100連続成立していた。v0.5 で Ch_Loc実値をダンプすることで:
- Ch_Loc の値が全 ep で 'W' 未満のままかを実測
- **Ch_Loc==$248D 相当の値（例: 'X'/'Y'/'Z' or 特殊コード）に変化する ep があるか**を観測
- 値変化と $248D 遷移の相関を確認

もし 50000行到達も $248D 未到達なら、Ch_Loc の値は Dhrystone 走行中 常に $2610 通過時点で正常な文字コードのままである可能性が高く、そのケースは HANDOVER §5 追記事項「別工程で $2610 以前の Ch_Loc 書込側 (STB) を疑う」に進む。

## 8. 確認事項（v0.3 で確定・v0.5 変更なし）

- 変数スコープ: task ローカル
- 代入セマンティクス: 全てブロッキング `=`
- $2610 のPC値: **HANDOVER_CHAT116.md L41 「$2610: LDW A, [X + #$FFFA]」** で確定
- $248D のPC値: **HANDOVER_CHAT116.md L47 「$248D (Func_2入口)」** で確定
- Ch_Loc 格納位置 [X-6][X-5]: Step J TB L316-325 で実装済・実源照合済

## 9. v0.4 → v0.5 差分の全リスト

- §0: 変更要旨を全面書き直し（v0.4 の暴走仮説撤回・実源引用行番号付き）
- §1: 背景を **HANDOVER_CHAT116.md 行番号引用**（L41/L47/L51/L55/L60/L68/L115）で構成
- §2: 仮説を **HANDOVER §4 準拠 θ1/θ2/θ3 + HANDOVER L115 KY予測反映 θ4** に復元
- §3.2 case:
  - **$2626/$2630/$2634 の dump制御ロジックは v0.4 で追加したが v0.5 で撤回**
  - **$2610 case に v0.5 新規: Ch_Loc実値ダンプを開始マーカに追加**
- §3.2 毎cyc動作:
  - `k_dump_cnt >= 100` → **`>= 20`**
  - `k_total_dumped >= 5000` → **`>= 50000`**
- §3.4: 停止条件を「$248D で $finish・20cyc で dump停止 ep 継続・50000行安全弁」に整理
- §6: KY-K-add4 実効性回復・KY-K-add5 新規追加
- §7: 期待結論を HANDOVER 仮説準拠に置換・事前予測を追記
- §8: 確認事項に PC値の HANDOVER 出典を明記

## 10. v0.3 → v0.5 差分（実装作業リスト）

v0.4 は撤回のため v0.3 実装済み TB (`tb_cpu_v8d_dhry_stepK_pcdump.sv` v0.1) をベースに以下のみ変更:

1. $2610 case の `★[STEPK ep=... cyc=...] L0140到達 - PC遷移生ダンプ開始` の後ろに **Ch_Loc実値ダンプ** (`Ch_Loc [X-6=%04h][X-5]=%02h %02h`) を追加
2. $2618 case の `dump 停止処理` (v0.3 で追加) を削除
3. `k_dump_cnt >= 50` → **`>= 20`**
4. `k_total_dumped >= 5000` → **`>= 50000`**
5. バージョンヘッダを v0.1 → v0.2 更新（変更理由: v0.5 設計メモ準拠）

## 11. 参照資料

- v8d_stepK_pcdump_design_memo_v0_1〜v0_4.md（過去版）
- v8d_stepK_pcdump_design_memo_v0_4_review_v1_0.md（本版の直接出典）
- **HANDOVER_CHAT116.md** — L41, L47, L51, L55, L60, L68-70, L115（全て v0.5 §1 で行番号明記引用）
- tb_cpu_v8d_dhry_stepJ_jmp.sv — 派生元（不変）
- ysd8800_psram_ctrl_v0_2.sv — L43 (LATENCY_NORMAL=12)・L52-57 (信号名)
- kaizen.txt 原則43（実装前レビュー）・原則57（仮説絞込）・原則77（複数観測値の食い違いは片方の写像ミスを疑う）
- review_insights_v1_0.docx 原則5.1（実源照合・v0.5 KY-K-add5 の根拠）

## 改版履歴

| 版 | 日付 | 内容 |
|---|---|---|
| v0.1 | 2026-07-25 | 初版。CHAT117 Step K の PC遷移生ダンプ TB 設計。条件付き差戻し。 |
| v0.2 | 2026-07-25 | v0.1 レビュー反映。案K1・PSRAM信号追加・KY追加・Step J統合。条件付き承認。 |
| v0.3 | 2026-07-25 | v0.2 レビュー反映。案C（ブロッキング統一）・$248D dump後 $finish・LATENCY 準拠サンプル。実装済・実測済。 |
| v0.4 | 2026-07-25 | 観測ポイント誤訂正。「$262D JMP が真因」を HANDOVER 出典と誤引用。条件付き差戻し。 |
| **v0.5** | **2026-07-25** | **v0.4 全面撤回・v0.3 派生に回帰**。HANDOVER_CHAT116.md L41/L47/L51/L55/L60/L68/L115 を**行番号付きで正確に引用**。観測点を $2610 に戻し（HANDOVER L68 準拠）、v0.3 実測（100連続 Ch_Loc<'W'）を「探索空間絞込成果」として §1.2 に位置づけ、レビュア推奨代案「Ch_Loc 値追跡モード」採用: Ch_Loc実値 ([X-6][X-5]) をエピソード開始マーカに追加、観測窓 20cyc、累計 50000行安全弁、エピソード無制限化。仮説を HANDOVER §4 準拠 θ1/θ2/θ3 に戻し、L115 KY予測反映 θ4 (JSR/CALL) を追加。KY-K-add4 実効性回復・KY-K-add5 新規追加。 |
