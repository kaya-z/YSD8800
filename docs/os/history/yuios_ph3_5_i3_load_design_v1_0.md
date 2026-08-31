# YUI OS Ph.3.5-I-3 負荷試験（16タスク同時 CALL）設計書

**Version:** 1.0
**作成日:** 2026-06-05
**対象工程:** Ph.3.5-I-3（IPC4 共通プール枯渇耐性・スタック watermark 実測）
**前提文書:** yuios_tcb_design_v1_3.md §7（POOL_SIZE=32 確定）・§9（スタック配置）／emu23_watermark_design v1.1
**実装対象:** kernel_forth v0.10.11 → 試験版 **kernel_forth_i3_load.fs**（KY38：本番無改変・別ファイル名）
**計測ツール:** emu23_wm（emu23_wm_v104w.c v1.2・本番 emu23_v104.c 無改変）
**ステータス:** ドラフト（レビュー前）

---

## 1. 目的と検証項目

TCB 設計書 §7.1 の worst-case「16 タスク全員が CALL 発行 → 全員 WAIT_REPLY、
in-flight=16」を**物理的に再現**し、以下を実測で裏取りする。

| # | 検証項目 | 合格基準 |
|---|---|---|
| V1 | in-flight=16 でプール（容量32）が枯渇しない | 16 タスク全員の CALL が成功（ERR_IPC_NOSLOT を返さない） |
| V2 | プール枯渇時もパニックしない | 意図的枯渇で ERR_IPC_NOSLOT($FFFE) 返却・実行継続（V2 は派生試験） |
| V3 | スタック watermark が 128B 枠に収まる | 全 tid のコール／データスタック使用が ≤128B、guard intact |
| V4 | 全 CALL が正しく REPLY を受け取る | 各タスクが期待 reply 値を受信し、UART に成功記号を出す |

## 2. 試験構成（フル16タスクハーネス）

### 2.1 タスク配置（MAX_TASKS=16 を使い切る）

| tid | タスク | 役割 |
|---|---|---|
| 0 | MAIN（既存・起動タスク） | ハーネス起動後アイドル |
| 1 | **ECHO-SERVER**（新規） | RECV→受信値+1 を REPLY するエコーサーバ |
| 2〜15 | **LOAD-TASK ×14**（新規） | 一斉に ECHO-SERVER へ CALL |

→ CALL 発行側は tid 2〜15 の **14 タスク**＋（MAIN も加える場合 15）。
in-flight 最大は「サーバが REPLY を保留している間に全クライアントが WAIT_REPLY」
の同時数。14 クライアントで in-flight=14、設計の 16 に近い負荷を与える。

**16 を厳密に満たす案**：ECHO-SERVER を tid=1 に置き、クライアントを MAIN(0)＋
tid 2〜15（14）＝**15 クライアント**にできる。サーバ自身は CALL しないので
in-flight 上限は 15。**完全な 16 は「サーバも別サーバへ CALL する二段構成」が必要**
だが、プール容量 32 に対し 15〜16 はマージン内であり、容量検証としては
15 で POOL_SIZE 半分超の負荷を与えられるため十分。**本試験は 15 クライアントで実施**し、
「in-flight=15 で枯渇せず」を V1 の実測値とする（32 の安全マージン妥当性確認）。

### 2.2 同時性の作り方（in-flight を溜める機構）

単純に各クライアントが CALL すると、サーバが即 REPLY して in-flight=1 のまま捌ける。
**同時に 15 個を溜める**には、サーバが「15 個受信し終えるまで REPLY しない」
バッチ方式を採る：

```
ECHO-SERVER:
  BEGIN
    received < EXPECTED?  →  RECV して sender tid を配列に記録、received++
  received == EXPECTED になったら
    記録した全 sender へ順に REPLY    \ ここで初めて全員が起床
  AGAIN
```

- クライアントが CALL すると enqueue されサーバが RECV するまでプールに滞留。
- サーバが 15 個 RECV するまで REPLY しない間、15 クライアントは全員 WAIT_REPLY。
- この瞬間が **in-flight=15**（プール内 dequeue 済み＋WAIT_REPLY 中の reply 待ち）。

※ 厳密には「プール滞留数」と「WAIT_REPLY 数」は別物。プール枯渇(V1)は
**enqueue 時点**で起きるため、15 クライアントが RECV 前に一斉 enqueue した瞬間の
プール占有（最大 15）が POOL_SIZE=32 を超えないことが V1 の本質。

## 3. 実装方針（KY36 準拠：Dスタック完結・グローバルループ変数禁止）

### 3.1 新規ワード

| ワード | 内容 |
|---|---|
| `ECHO-SERVER-TASK` | §2.2 のバッチエコーサーバ。sender 記録は専用配列 `I3-SENDER-BUF`（$EC00 系の試験バッファ流用） |
| `LOAD-TASK` | `(自tid をメッセージにして) ECHO-SERVER(tid=1) へ IPC4-CALL → reply 検証 → 成功なら UART に記号` |
| `I3-HARNESS-START` | tid 2〜15（14個）の LOAD-TASK を TASK-CREATE。MAIN もクライアントに加える |

### 3.2 sender 記録バッファ

`I3-SENDER-BUF`：**$5080-$509F（32B＝16ワード）に確保**。当初 $EC00 系 TEST バッファ
への配置を検討したが、$EC00-$EFFF は STOR-TEST/FILEMGR-TEST が時分割で全域使用
しており（HANDOVER_CHAT43 で実際に FT-RW-BUF 上書き破壊が発生した領域）、
競合を避けるため **FileMgr 残余領域**（$5060=FT-NAME2 / $5070=FT-STAT の次・
$5080-$50FF は空き、Forth 辞書先頭 $5100 の手前）に隔離する。サーバ単一タスクのみが
触り、かつ他用途と物理的に分離（kaizen 原則35：使用者マップの取り違え回避）。

### 3.3 成功判定の UART 記号

全クライアントが正しい reply（送信値+1）を受け取ったら、各クライアントが
`'a'+tid` を UART 出力。MAIN が全タスク起動後に区切り記号 `'#'` を出す。
期待出力：`#` の後に 15 個のクライアント記号（順不同）。

## 4. 計測手順

```
# ビルド（kernel_forth_i3_load.fs を v0.10.11 と同じ手順でビルド）
# 実行（watermark 付き・常駐OSなので --wm-steps で打切り）
printf "c\nq\n" | timeout 90 ./emu23_wm yuios_i3.bin --disk disk.img \
    -i /dev/null -q -w --wm-steps 20000000 2>wm.txt >uart.txt
```

- `uart.txt`：`#` ＋ 15 記号が出れば V1・V4 PASS。
- `wm.txt`：全 tid の used ≤128B、guard intact なら V3 PASS。

## 5. KY（本試験固有）

- **I3-K1**: バッチサーバが EXPECTED 未達で永久 WAIT（クライアント不足）。
  → クライアント数とEXPECTEDを定数で一致させ、TASK-CREATE 成功数を確認。
- **I3-K2**: 15 クライアント同時 enqueue でもプールは 15 ≤ 32 で枯渇しない想定だが、
  既存 7 タスク（FILEMGR 等）の in-flight と合算しうる。試験は既存サーバ群を
  停止せず動かすため、合算ピークを wm/プール監視で確認。
- **I3-K3**: KY38 継続。本番 kernel_forth_v0_10_11.fs / emu23_v104.c 無改変。
  試験版は kernel_forth_i3_load.fs。
- **I3-K4**: emu23 改修なし（計測は既存 emu23_wm）。∴ 本試験で Dhrystone 回帰不要
  （Force/カーネルへのワード追加のみ）。
- **I3-K5**: WAIT_REPLY 永久 block（TCB §5.3.8）。サーバが必ず全員へ REPLY する
  ことをコードで保証。timeout 機構は未実装（Ph.5 課題）なので試験は決定的に組む。

## 6. レビュー観点

- [ ] §2.1 の 15 クライアント構成で「16 worst-case」の容量検証として十分か
      （厳密 16 には二段サーバが要る点の割り切り妥当性）
- [ ] §2.2 バッチ方式で in-flight=15 が確実に同時成立するか（サーバ RECV と
      クライアント WAIT_REPLY のタイミング）
- [x] §3.2 sender バッファのアドレス → $5080-$509F（FileMgr 残余・TEST バッファと分離）で競合回避済み（kaizen 原則35）
- [ ] V1 の本質が「enqueue 時点のプール占有 ≤32」である理解の妥当性
- [ ] I3-K2 既存タスクとの in-flight 合算ピークの扱い

---
*--- 以上（ドラフト v1.0・レビュー前）---*
