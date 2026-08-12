# HANDOVER_CHAT61.md — Step 8-F ツール不具合改修＋lnk23大改修（道2）

| 項目 | 内容 |
|---|---|
| 文書名 | HANDOVER_CHAT61.md |
| 作成日 | 2026-06-20 |
| 対象工程 | Step 8-F（F-001 修正＝完了 / lnk23大改修＝設計承認済・本実装待ち） |
| 前引継ぎ | HANDOVER_CHAT60.md |
| 作成契機 | ユーザーからの明示的引継ぎ指示（ログ長大化のため新チャットへ移行） |

---

## 0. 最優先：新チャット冒頭でやること

1. 工程確認（マスター工程「進捗と予定の確認(latest)」参照）。本工程は **Step 8-F の続き**。
   - Step 8-F-1（F-001 修正）＝**完了済**
   - Step 8-F-2（lnk23大改修＝道2）＝**設計承認済・本実装が次アクション**
2. **本実装に着手**：承認済設計書 `hasm23_xref_yof_design_v2_2.md`（Status: 承認済 Approved）の
   §6 実装ステップ5〜12（道2 の (C)hasm23 ＋ (D)lnk23）。原則43 クリア済み＝実装着手可。
3. 進捗チャート(latest)への日報は **その日の作業終了時のみ**（本日 2026-06-20 分は CHAT61 で未投稿。
   投稿要否はユーザー指示を待つ）。

---

## 1. 本日（2026-06-20・CHAT61）の完了事項

### 1.1 Step 8-F-1：F-001 修正 ＝完了

- **emu23 v1.06**（`emu23_v106.c`・outputs 済）。REPL `bd N`（ブレークポイント削除）バグ修正。
- 原因：分岐順序誤り。`cmd[0]=='b'`（L1447）が `bd` 分岐（L1474）を先取りし不到達だった。
  → `bd` 分岐を `b` 分岐の**前**へ移動して解消。
- 検証：`bd 0` 削除・繰り上げ動作確認、`b`設定/`b`一覧 非回帰、**Dhrystone 回帰 826/48405/P:20 一致**。
- F-002（hasm23 .org重なり無警告）＝hasm23 v1.02 で W001 実装済・**解消確認**。
- F-003（emu23 DBGprintf残骸）＝v1.04 で除去済・**解消確認**。
- → Step 8-F-1 で実改修が必要だったのは **F-001 のみ**。

### 1.2 Step 8-F-2：(A)(B) ＝実装済（hasm23 v1.03 前半）

`hasm23_v1_03.c`（outputs 済）に以下を実装・検証済み：
- **改修(A) `.global` 疑似命令**：`_`非始まり（`WORD_xxx`）を GLOBAL export 可能に。
  export 専用・宣言シンボルが当該ファイル未定義ならエラー（C-2仕様）。
- **改修(B) `is_undef` 複数参照対応**：同一 UNDEF への即値+JSR 複数参照を全 reloc 化。
  §3.3.2.1 の集約構造（`need_reloc`フラグで3分岐合流・reloc生成1箇所）で即値/分岐両経路に適用。
- 単体 T1-T6 全 PASS／W001・E001 非回帰／**Dhrystone 回帰 826/48405/P:20 一致**／-Wall 警告ゼロ。

### 1.3 Step 8-F-2：道2 設計 ＝承認済（本実装は未）

`hasm23_xref_yof_design_v2_2.md`（outputs 済・Status 承認済）。
- レビュー経緯：v1.0 →（差し戻し）→ v1.1 承認 →（道2大改版）v2.0 →（条件付き承認）v2.1
  →（KY41是正）v2.2 → **承認（review v4.0）**。
- 改修対象は **hasm23（C）＋lnk23（D）両方**（当初「lnk23 無改修」前提は実ビルドで崩壊し撤回）。

---

## 2. 道2（次にやる本実装）の要点

### 2.1 なぜ道2が必要か（背景）

- 目的：ビルド手順書 §10 No.2/3/6 の **sed を廃止**し、クロスファイルシンボル参照
  （kernel.asm → Forth の `WORD_OS_START`）を YOF リンクで正規解決する。
- 障害：YUI OS は **forth=$5100／kernel=$0000 の2固定アドレス配置**。YOF 引数モードの
  自動連続配置だと forth が kernel の後ろに積まれ ROM 境界 $3FFF 超過で失敗した。
- 解決＝**道2**：hasm23 が `.org` を配置アドレスとして尊重（空白除去・load_addr 記録）、
  lnk23 が load_addr を尊重して固定配置。**PoC で完全実証済み**（後述 §3）。

### 2.2 改修(C) hasm23（YOFモードの.org処理）

設計書 §3.5.2。**実験実装 `hasm23_road2_poc.c` に動く実装あり**（本番 v1.03 に移植する）。
- 最初の `.org` を `sec_origin` として記録。code_buf は sec_origin 基準（空白パディングしない）。
- YOF セクションヘッダの `load_addr` に sec_origin 出力（従来 0 固定だった）。
- シンボル offset・reloc offset を YOF 出力時に **sec_origin 減算**で相対化（UNDEF は 0 のまま）。
- コード内部のラベル絶対参照（JSR sub_helper 等）は sec_origin 基準絶対のまま保持（reloc 不要）。
- **has_org フラグ**：`.org` を1つでも持てば YOF flags bit4 (0x10) を立てる（C-3）。

### 2.3 改修(D) lnk23（load_addr 尊重配置）

設計書 §3.5.3。**実験実装 `lnk23_alpha_poc.c` に動く実装あり**（本番 lnk23_v2_01.c に移植）。
- load_yof で load_addr＋has_org を読む。`has_org=1` なら（$0000でも）固定配置、`=0` は自動配置。
  ※PoC版は「load_addr≠0 なら固定」の暫定判定。**本実装では has_org ビット判定に変えること**（L-7）。
- 固定配置は place_sections で自動配置をスキップ（`.bin` の bin_addr 経路 L459-473 と構造同型）。
- `--machine force` で ROM 境界チェック回避（§3.5.3.1）。固定/自動混在はエラー（§3.5.3.2）。
- 配置後、既存 resolve_symbols → apply_relocations で UNDEF 解決（既存・無改修で機能）。

### 2.4 ビルド後処理（案F2・I1 で実証済み）

- 後処理1：Force 出力 kernel_forth.asm の混入行 `#WORD_xxx` を `.sym` アドレスで `#$addr` 修正
  （No.1 sed・残置）。**対象は固定リストでなく `#WORD_xxx` を全自動抽出**（v0.10.18 実態は6個）。
- 後処理2：`WORD_OS_START` 定義ラベル直前に `.global WORD_OS_START` 挿入（案F2）。
- kernel_v12_7.asm の `LDW A, #$e96e` 2箇所 → `LDW A, #$WORD_OS_START`（恒久修正・sed系統②=No.6廃止）。

---

## 3. PoC 実証結果（道2が動く根拠・実験コード所在）

実験コード（KY28準拠・本番非改変。`/home/claude` にあり。新チャットでは要再生成または再添付）：
- `hasm23_road2_poc.c`：道2 の hasm23（本番 v1.03 に (A)(B) 込みで道2 を追加した実験版）
- `lnk23_alpha_poc.c`：道2 の lnk23（load_addr 尊重＋`file.obj@0xADDR` 指定の実験版）

**実証された事実**（最小例 forth=$5100＋内部参照 sub_helper／kernel=$0000＋WORD_OS_START UNDEF）：
- forth 空白除去（size $510d→13）／load_addr=$5100 固定配置 ✅
- kernel→forth クロス UNDEF 解決（A=$5100）✅
- 内部参照 JSR sub_helper→$5108 保持（α-A で壊れた箇所）✅
- 実行 A=$BEEF, B=$CAFE ✅／overlap なし ✅
- **非 YOF Dhrystone 回帰 826/48405/P:20 一致**（道2 が .bin ビルドを壊さない）✅

---

## 4. 地雷マップ（実装時に必ず踏む/注意）

| # | 地雷 | 対策 |
|---|---|---|
| L-6 | sec_origin 減算の**波及漏れ**。「コード生成・シンボル offset・reloc offset・W001重ね書き検出・.vector書込み」の全箇所に効かせる。1箇所漏れると内部参照が静かに壊れる | 全箇所を洗い出し、PoC `hasm23_road2_poc.c` の該当差分を照合 |
| L-7 | has_org **ペア実装**。hasm23 write_yof（書く）と lnk23 load_yof（読む）を必ず両方。片方だけだと後方互換崩壊（書くだけ＝無視/読むだけ＝既存obj誤判定）。PoC版lnk23は「load_addr≠0で固定」の暫定なので本実装で has_org 判定へ要修正 | T9 で書き読み両方を通す |
| L-8 | **`--machine force` 必須**をビルド手順書 v1.6 に明記。落とすと後日 baremetal リンクで forth@$5100 が静かに L592 エラー | 手順書改版（§6 ステップ11）で確実に |
| L-9 | **非YOF Dhrystone 非回帰**（826/48405/P:20）必須。「forth だけ見て Dhrystone 見ない」片手落ち禁止 | ツール改修のたび回帰 |
| KY28 | 実験は別ファイル名・本番非改変。本日 CHAT61 で一度本番 v1.03 を直接編集しかけ即是正した実績あり。**本実装でも実験は `*_poc` 名で**、本番は承認後の版数で | — |
| 1変更1検証 | (C)→検証→(D)→検証 の順（L-1）。両方一度に書かない | — |

---

## 5. ツールバージョン台帳（CHAT61 終了時点）

| ツール | 版数 | 状態 |
|---|---|---|
| emu23 | **v1.06** | F-001 修正済（outputs: emu23_v106.c）。Dhrystone回帰OK |
| hasm23 | **v1.03** | (A)(B) 実装済（outputs: hasm23_v1_03.c）。**道2(C)は未**＝本実装で追加 |
| lnk23 | v2.00 | **道2(D)は未**＝本実装で lnk23_v2_01.c へ |
| Force | v1.5 | 変更なし |
| scc23 | v1.04 | 変更なし |
| disasm23 | v1.00 | 変更なし |
| mkfs_yuifs.py | v1.1 | 変更なし |
| kernel_forth | v0.10.18 | 変更なし |

---

## 6. 成果物一覧（outputs 済）

- `emu23_v106.c`（F-001修正）
- `hasm23_v1_03.c`（(A)(B)実装・道2は未）
- `hasm23_xref_yof_design_v2_2.md`（**承認済設計書・本実装の指針**）
- （参考・旧版）design v1_0/v1_1/v2_0/v2_1

レビュー指摘書（ユーザー手元）：review v1_0（差戻）/ v2_0（v1.1承認）/ v3_0（条件付承認）/ v4_0（承認）。

---

## 7. 本実装の順序（承認済 §6 ステップ5〜12）

5. 改修(C) hasm23 v1.03 に道2 追加（空白除去・load_addr・offset相対化・has_org）。L-6 全箇所波及確認。
6. 単体 T7-T8（道2 obj 生成・内部参照保持・has_org フラグ）。
7. lnk23_v2_00.c → v2_01.c。改修(D)（load_addr＋has_org 尊重・force ROM回避・混在エラー）。L-7 ペア実装。
8. 単体 T9-T10（固定配置・実行正解・overlap 異常系）。
9. **Dhrystone 回帰**＋W001/E001 非回帰（L-9・非YOF .bin も必ず）。
10. 結合 I1-I3（YUI OS 実ビルド・sed系統②廃止・道2固定配置・従来版とバイト比較）。
11. ビルド手順書 v1.5 → v1.6（後処理1自動抽出・後処理2 .global付与・道2リンク手順・force必須＝L-8）。
12. 関連設計書改版（toolchain23_design・lnk23_design 等）。

---

## 8. 未確認・要判断（ユーザー指示待ち）

- Q3：No.1（Force 混入行）の sed 残置は確定だが、別工程化の要否は未確認（設計書 §7 Q3）。
- Q5：sec_origin 波及範囲の網羅性は実装ステップ5で確認（L-6）。
- E-4：設計書 §3.5.4 PoC 表の用語は「固定配置(has_org=1)」に修正済み。
- 本日分の進捗チャート(latest)日報は未投稿（その日の作業終了時のみ・要ユーザー指示）。

---

*— YSD8800 Project / Step 8-F-2 / HANDOVER_CHAT61 —*
