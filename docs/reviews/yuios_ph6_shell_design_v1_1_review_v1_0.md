# 設計レビュー指摘書（再レビュー）

## YUI OS Ph.6 Forth 常駐 Shell 設計書 v1.1

| 項目 | 内容 |
|---|---|
| **指摘書ファイル名** | yuios_ph6_shell_design_v1_1_review_v1_0.md |
| **Version** | v1.0 |
| **査読対象** | yuios_ph6_shell_design_v1_1.md（v1.1 / レビュー指摘反映版） |
| **査読日** | 2026-06-18 |
| **査読方法** | プロジェクトナレッジ一次確認（kernel_forth v0.10.16 の PROC-WAIT-IMPL/PROC-EXEC-IMPL 実体）＋ D-4 バッファ境界の独立検算 |
| **判定** | **承認（条件なし）** |
| **分類凡例** | M=必須修正 / C=確認推奨 / D=査読確認 / N=情報 / E=評価 |

---

## 1. 総評

v1.0 指摘書の M-1・M-2・C-1・C-2・D-1〜D-4 すべてに適切な是正がなされ、**特に M-1/M-2 は机上の
回答に留めず実機実証（§12）で裏取り**された。**本設計を承認する**。

前回 M-2 で査読側が「未確認」とした LOAD-SLOT-BUSY の解放経路は、kernel_forth v0.10.16 の
PROC-WAIT-IMPL 実体に **`0 LOAD-SLOT-BUSY !` が確かに存在**し、設計書 §5.4/§12.2 の主張が実体
そのものであることを確認した。繰り返し run の成立は実体・実機の両面で保証されている。

---

## 2. M 解消確認（実体裏取り）

### 2.1 M-2：LOAD-SLOT-BUSY 解放経路（実体確認・最重要）

kernel_forth v0.10.16 の PROC-WAIT-IMPL を実体確認：

```
: PROC-WAIT-IMPL  ( arg2 arg1 arg0 tid -- )
    >R
    SWAP DROP SWAP DROP              \ target のみ残す
    BEGIN  DUP TCB-STATE@ TASK-DEAD =  UNTIL    \ DEAD まで spin
    DROP
    0 LOAD-SLOT-BUSY !              \ ★占有解除（設計書 §5.4/§12.2 の主張どおり）
    PROC-EXIT-CODE @
    R> PROC-REPLY ;
```

→ 設計書 §5.4 の「PROC-WAIT-IMPL が子プロセス DEAD 検出後に `0 LOAD-SLOT-BUSY !` を実行して占有
解除する」は **実体と完全一致**。さらに PROC-KILL-IMPL にも `0 LOAD-SLOT-BUSY !` があり、自発
TASK_EXIT（WAIT 経由）・強制 KILL の両経路で解放される。**前回 M-2 の懸念（落ちないと 1 回しか
run できない）は実体上すでに解決済み**であった。§12.2 の 2 回 run 実機実証（`0E123MDF557WF557W`・
2 回目も new_tid=7 で BUSY 弾きなし）も妥当。

### 2.2 M-1：GETC 単一クライアント不変条件＋実機実証

§3.1 で「Level 1 では UART_GETC を発行できるのは Shell（tid=6）ただ 1 タスク」を不変条件として
明記し、UART-WAIT-TID（$FC5E）が単一待機 tid 前提であることを実体に基づき説明。§1.4 で子プロセスの
stdin 非サポートを Level 2 送りと明示。§12.1 で GETC エコー経路を実機実証（`G→a→b→c→Z`）。
前回 M-1 の「GETC 経路未実証・不変条件未明示」は解消。

### 2.3 D-4：バッファ上限オフバイワン（検算確認）

SH-LINE-BUF を 65B 確保・上限 `SH-LINE-LEN @ 64 <` に是正。検算：最大 64 文字（index 0-63）格納後
LEN=64 で停止、確定時 buf[64]=NUL。必要バッファ 65B と確保 65B が**過不足なく一致**。v1.0 の
「buf=64B で buf[64]=NUL がバッファ外」が解消された。

---

## 3. その他反映確認（C/D/N）

| 指摘 | 反映内容 | 判定 |
|---|---|---|
| C-1 run 経路=exectest | 経路同一（FT-NAME-BUF→SH-ARG-BUF 差分のみ）。繰り返し成立は M-2 で別途保証 | OK |
| C-2/D-1 バッファ配置 | SH-ARG-BUF 等を VARIABLE 化（テストバッファ域 $EF00 STAT との競合回避）。§4 確定。$DCFF 超過検査も §9-3 に追加 | OK |
| D-2 トークン分割 | Phase1 cmd+arg1 で確定・将来複数化は予約のみ | OK |
| D-3 NUL 終端 | §5.2 擬似コード本体に Enter 確定時の `0 SH-LINE-BUF SH-LINE-LEN @ + C!` を反映 | OK |
| N-1 行編集範囲 | BS のみで Phase1 確定 | OK |
| N-2 STRCMP 不在 | Shell 内 `SH-STR=` 実装方針。C@/C! 使用実績裏取り済 | OK |
| N-3/N-4 tid 監視・組込位置 | tid6/7 安全圏・PROCMGR-START 直後 tid6 | OK |
| E-1 サイズ楽観性 | .sym 早期補正（O-2）を必須工程化 | OK |

§9 回帰計画に M-1（SH-READLINE 単体実証を run の前段に最優先配置）・M-2（run fib 2 回連続）を
受入項目として追加した点も適切。§10 論点決着表・§12 実証記録の新設で対応関係が追える。

---

## 4. 評価（E）

- **E-1**：M-1/M-2 を机上回答で済ませず、CHAT57 で GETC エコー実証（§12.1）・2 回 run 実証（§12.2）
  まで実施して裏取りした姿勢は、「見えているバグは先に潰す」「実体を真とする（KY39）」の優れた
  実践。特に M-2 は実体（PROC-WAIT-IMPL の解放）の発見により、懸念が杞憂であることを積極的に
  証明した。
- **E-2**：既存 IPC4 サービスの 2B トークンラッパで Shell を構成し、新規カーネル機能ゼロで
  run/ps/help を実現する設計は、Level 1 の制約下で最小コストの解。スレッデッドコード密度効果を
  正しく活用している。
- **E-3**：D-4 のような細かなオフバイワンまで擬似コードに正確に反映し、バッファサイズを 65B に
  是正した丁寧さは、実装段階のバグを設計段階で潰す good practice。

---

## 5. 判定と次アクション

**承認（条件なし）。**

v1.0 指摘書の M-1・M-2（必須）・C-1・C-2・D-1〜D-4 はすべて反映済み。M-1/M-2 は実機実証付きで
裏取りされ、M-2 の LOAD-SLOT-BUSY 解放は kernel_forth v0.10.16 実体で確認した。本 v1.1 をもって
Ph.6 Shell 設計の有識者レビューは完了とする。

実装着手を可とする。実装時の申し送り（設計書に既記載）：
- §2/§9-3：Shell 搭載後の辞書実終端 ≦ $D3FF と、SH バッファ VARIABLE の $DCFF 非超過を .sym 実測
  （K38）。最初の 2〜3 コマンド実装時点で早期補正（O-2）。
- §8/§11：ビルド手順書（yuios_build_procedure）へ `WORD_SHELL_TASK` の sed ラベル置換リスト追加
  （本番ビルド恒久）。
- §9：回帰は SH-READLINE 単体実証 → 5 サービス非回帰 → run fib → run fib 2 回連続 の順で 1 変更
  1 検証。

> ※ 本指摘はプロジェクトナレッジ（kernel_forth v0.10.16 PROC-WAIT-IMPL/PROC-EXEC-IMPL）の実体と
> 独立検算に基づく（KY34/KY39：実体を真とする）。

---

以上。
YUI OS Level 1 の大詰め、Shell 設計の完成を確認しました。
ご安全に！
