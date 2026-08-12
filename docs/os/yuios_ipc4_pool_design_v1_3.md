# YUI OS IPC4 共通メッセージプール方式 詳細設計書

**Version:** 1.3
**作成日:** 2026-05-08
**最終改版:** 2026-05-17
**作成者:** Claude
**対象フェーズ:** Ph.3.5 カーネル基盤改訂
**ステータス:** **FIX**（v1.2 で全項目確定）

---

## 改版履歴

| 版 | 日付 | 内容 | 作成者 |
|---|---|---|---|
| v1.0 | 2026-05-07 | 初版作成（HANDOVER_CHAT22.docx 案 ②-C を具体化） | Claude |
| v1.1 | 2026-05-07 | レビュー指摘（review11.txt）反映：①プール枯渇を即 ERR_IPC_NOSLOT 返却に変更、②`ipc_queue_tail` を TCB+14 に追加し O(1) enqueue 化、③`ipc_sender` の意味を「last_sender_tid」と明確化、④MsgEntry から valid 削除（free list 管理）、⑤priority inversion / IPC4-CALL timeout を将来課題として明記 | Claude |
| v1.2 | 2026-05-08 | 後発設計書（TCB v1.1 / memmap v1.1）の確定値を反映：①MAX_TASKS=16 確定、②POOL_SIZE=32 確定、③MSG_POOL_BASE=$4500 確定、④TCB プール $4000-$44FF 確定、⑤WAIT_MSG(4) 廃止に伴う状態定義整合、⑥nested CALL 禁止条件「WAIT_REPLY 中の CALL 禁止」追記、⑦RUNNING 唯一性原則の参照追加、⑧オープン項目を確定済としてクローズ。**確定値の反映のみで新規設計要素は追加せず** | Claude |
| v1.3 | 2026-05-17 | Ph.3.5 Step 6 デバッグ（実装検証）で判明したバグの設計書反映：①`_ipc4_enqueue` の msg インデックス誤り修正（§5.1）、②IPC4_RECV/IPC4_CALL の `saved_sp` 計算方針修正（§5.2/§5.3）、③IPC4_RECV スロット内 `_ipc4recv_resume` 統合の記録（§5.7 新設）、④IPC4_RECV スロットサイズ上限の明記（§5.7） | Claude |

---

## 1. 文書の目的とスコープ

### 1.1 目的

本文書は、HANDOVER_CHAT22.docx で合意された **「案 ②-C 共通メッセージプール方式」** の詳細設計を定義する。
従来の「TCB 内 1 件保持方式」では複数クライアントから単一サーバへ同時に IPC4-CALL が来た場合に msg/sender が上書きされる競合バグが発生していた。本設計はこれを根本解決する。

### 1.2 スコープ

- 本文書（**TCB 数に非依存**な部分）
  - メッセージプールの構造設計
  - IPC4-CALL/RECV/REPLY/SEND の新セマンティクス
  - キュー操作アルゴリズム
  - プール枯渇時の挙動
  - 既存 API との後方互換性
  - 移植性に関する考慮（YUI OS の汎用化方針）

- 本文書のスコープ外（**v1.2 で確定済、参照先記載**）
  - **POOL_SIZE の最終値** → **POOL_SIZE = 32 確定**（TCB 設計 v1.2 §7.3 で確定済）
  - **MsgPool の配置アドレス** → **MSG_POOL_BASE = $4500 確定**（memmap 設計 v1.1 §4.3 で確定済）
  - **ipc_queue_head の絶対アドレス** → **TCB+30**、TCB プール $4000-$44FF（memmap 設計 v1.1 §4.1 で確定済）

### 1.3 設計の前提（v1.2 で全項目確定）

設計内で使う値は以下のシンボルで定義する。すべて **v1.2 で確定済**：

| シンボル | 値 | 意味 | 確定根拠 |
|---|---|---|---|
| `MAX_TASKS` | **16** | 同時に存在できるタスク数の上限 | TCB 設計 v1.2 §4.1 |
| `POOL_SIZE` | **32** | メッセージプールのエントリ数 | TCB 設計 v1.2 §7.3 |
| `MSG_POOL_BASE` | **$4500** | プールの先頭アドレス | memmap 設計 v1.1 §4.1, §4.3 |
| `TCB_POOL_BASE` | **$4000** | TCB プール先頭アドレス | memmap 設計 v1.1 §4.1 |
| `TCB_SIZE` | 80 | 1 TCB のバイト数 | TCB 設計 v1.2 §3 |
| `TCB_IPC_QUEUE_HEAD` | 30 | TCB 内のキュー先頭 index フィールド offset | 本書 §3.2.2 |
| `TCB_IPC_QUEUE_TAIL` | 14 | TCB 内のキュー末尾 index フィールド offset | 本書 §3.2.2 |
| `MSG_ENTRY_SIZE` | 16 | 1 エントリのバイト数 | 本書 §3.2.1 |
| `IDX_NIL` | $FFFF | 「次がない／空」を示すセンチネル値 | 本書 |
| `ERR_IPC_NOSLOT` | $FFFE | プール枯渇時のエラーコード | 本書 §5.5 |

---

## 2. 既存設計（v0.11.3 / yuios_design_v2_0.docx）の問題点まとめ

### 2.1 競合バグの再現条件

複数のクライアントタスクが同一サーバ（ドライバ）に対して、サーバが IPC4-RECV を実行する前に連続して IPC4-CALL を発行すると、後発の CALL がサーバ TCB の `ipc_msg[0..3]`/`ipc_sender`/`ipc_valid` を**無条件上書き**する。

```
時刻  クライアント       サーバ TCB（UART-DRV）
 t0   tid=4 IPC4-CALL  → msg=A, sender=4, valid=1
 t1   tid=5 IPC4-CALL  → msg=B, sender=5, valid=1  ← tid=4 のメッセージ消失
 t2   サーバ IPC4-RECV → msg=B, sender=5 を取得
 t3   サーバ IPC4-REPLY(tid=5) → tid=5 起床
 t4   tid=4 永久に WAIT_REPLY
```

### 2.2 設計上の根本原因

`yuios_design_v2_0.docx §4.5` の動作シーケンスは「クライアント1：サーバ1」前提で記述されており、**多重クライアントに対するキュー機構の規定がない**。kernel_v11.asm の `IPC4_CALL` 実装（行 879-880）はこの仕様に忠実に実装されているため、実装バグというより仕様レベルの欠落である。

### 2.3 解決の方向性

サーバ TCB が「最後に届いた 1 件」しか保持できないことが根本原因なので、

- **サーバ TCB は『キューの先頭ポインタ』だけ持つ**（容量を分離）
- **メッセージ実体は共通プールに置く**（容量と TCB を分離）
- **複数の保留メッセージは FIFO リンクリストでつなぐ**（順序保証）

これにより、N 個のクライアントが同時に CALL しても全員のメッセージが保持され、サーバは IPC4-RECV を呼ぶたびに先着順で 1 件ずつ受け取れる。

---

## 3. 共通メッセージプール方式の全体像

### 3.1 アーキテクチャ概観

```
┌────────────┐       ┌─────────────────┐
│ TCB[client0]│       │ TCB[server]     │
│ state       │       │ state           │
│ ipc_queue_  │       │ ipc_queue_tail ─┼───┐
│  head=NIL   │       │ ipc_queue_head ─┼─┐ │
│ ipc_queue_  │       │                 │ │ │
│  tail=NIL   │       └─────────────────┘ │ │ 末尾
└────────────┘                            │ │
                                          │ │
┌────────────┐    ┌─────────────────────┐ │ │
│ TCB[client1]│    │  MsgPool[POOL_SIZE] │ │ │
│ state       │    │  ┌────┐  ┌────┐  ┌─┴─┴┐│
│ ipc_queue_  │    │  │  3 │─>│  7 │─>│ NIL││
│  head=NIL   │    │  └────┘  └────┘  └────┘│
│ ipc_queue_  │    │   sender  sender  sender│
│  tail=NIL   │    │   =4      =5      =9    │
└────────────┘    │   msg[4]  msg[4]  msg[4] │
                  │   ↑先頭            ↑末尾 │
                  └─────────────────────────┘
```

**ポイント：**

- メッセージ実体は `MsgPool` に集約。エントリは index（0..POOL_SIZE-1）で参照。
- サーバ TCB は **`ipc_queue_head`（先頭 index）** と **`ipc_queue_tail`（末尾 index）** の二つを保持（v1.1 で tail 追加）。
- 両方が `IDX_NIL` のときキュー空。
- 各エントリの `next` フィールドで FIFO リンクリストを構成。
- enqueue は **O(1)**（tail->next = new, tail = new）。
- IPC4-REPLY の応答メッセージは別経路（後述）で client TCB に直接届ける。プールエントリは reply 専用には使わない。

### 3.2 データ構造

#### 3.2.1 MsgEntry（プールの 1 エントリ）

| Offset | Size | フィールド | 内容 |
|---|---|---|---|
| +0 | 2 B | `sender` | 送信者 tid |
| +2 | 2 B | `msg[0]` | メッセージワード0（opcode） |
| +4 | 2 B | `msg[1]` | メッセージワード1（arg0） |
| +6 | 2 B | `msg[2]` | メッセージワード2（arg1） |
| +8 | 2 B | `msg[3]` | メッセージワード3（arg2/result） |
| +10 | 2 B | `next` | 次エントリ index、末尾は `IDX_NIL` |
| +12 | 4 B | `_pad` | 16 B 境界調整（将来拡張予約） |
| **計** | **16 B** | | |

設計判断（v1.1 で更新）：
- **`valid` フィールドは削除**（v1.0 から変更）。
  - 理由：free list 方式（`MSG_POOL_FREE` から `next` 鎖で連結）を採用するので、「フリーリスト上にある＝空」「TCB のキュー上にある＝使用中」と一意に判定可能。`valid` フィールドは冗長であり、削除することで O(1) alloc/free が実現できる。
- **`sender` を先頭に配置**：エントリ取得直後に sender を読み出すケースが多いため。
- **msg[0..3] を揃えて配置**：TCB 既存レイアウト（+16〜+22）と同じ msg 順序にして、コピー処理の使い回しが容易。
- **16 B 切り上げ（_pad は 4 B）**：tid×16 がアセンブリの SHL #4（1 命令）で計算可能。MC6809 等への移植時も `LSL` 4 回で済む。
- **`_pad` は将来拡張用予約**：例えば timeout 機能（§10）を入れる際の `expire_tick` などに転用可能。

#### 3.2.2 TCB 拡張

| Offset | 旧（v0.11.3） | 新（v1.1） | 備考 |
|---|---|---|---|
| +14 | `rsvd1` | **`ipc_queue_tail`** | キュー末尾 index、空時は `IDX_NIL`（v1.1 追加） |
| +24 | `ipc_valid` | `ipc_valid`（用途変更） | **§4.4 参照**（reply 到着フラグに専用化） |
| +26 | `ipc_sender` | `last_sender_tid`（意味明確化） | **§4.4 参照**（最後に IPC4-RECV した sender） |
| +30 | `rsvd2` | **`ipc_queue_head`** | キュー先頭 index、空時は `IDX_NIL` |

**TCB サイズ 80 B は維持**。+16〜+22 の `ipc_msg[0..3]` フィールドは「reply 受け取り専用バッファ」として残す（§4 参照）。

**v1.1 設計判断（tail 追加）：**
- enqueue を **O(1)** にするため、`ipc_queue_tail` を追加。tail->next = new, tail = new だけで末尾追加が完了する。
- v1.0 の末尾追跡ループ（O(キュー長)）は将来 FileMgr/ProcMgr で IPC 量が増えた際に性能問題化する懸念があった。
- 旧 `rsvd1` (+14) を流用するので、TCB サイズ・他フィールドオフセットは変更なし。互換性維持。

**TCB レイアウト全体（v1.1 確定版）：**

| Offset | Size | フィールド | 用途 |
|---|---|---|---|
| +0  | 2 | `state` | タスク状態 |
| +2  | 2 | `saved_pc` | 保存 PC |
| +4  | 2 | `saved_sp` | 保存 SP（コールスタック） |
| +6  | 2 | `saved_x` | 保存 X（データスタック） |
| +8  | 2 | `saved_a` | 保存 A |
| +10 | 2 | `saved_b` | 保存 B |
| +12 | 2 | `saved_flags` | 保存 FLAGS |
| **+14** | **2** | **`ipc_queue_tail`** | **【v1.1 新設】キュー末尾 index** |
| +16 | 2 | `ipc_msg[0]` | reply バッファ word0 |
| +18 | 2 | `ipc_msg[1]` | reply バッファ word1 |
| +20 | 2 | `ipc_msg[2]` | reply バッファ word2 |
| +22 | 2 | `ipc_msg[3]` | reply バッファ word3 |
| +24 | 2 | `ipc_valid` | reply 到着フラグ |
| +26 | 2 | `last_sender_tid` | 直近 RECV した sender |
| +28 | 2 | `priority` | タスク優先度 |
| **+30** | **2** | **`ipc_queue_head`** | **【v1.1 新設】キュー先頭 index** |
| **計** | **80 B** | | |

### 3.3 グローバル変数

新規追加：

| 名称 | サイズ | 内容 |
|---|---|---|
| `MSG_POOL_FREE` | 2 B | フリーリスト先頭 index（`IDX_NIL` =プール枯渇）。memmap 設計 v1.1 で **$47AC** に配置 |
| `MSG_POOL_BASE` | (アドレス定数) | プール先頭アドレス。**v1.2 で確定：$4500**（memmap 設計 v1.1 §4.3） |

`MSG_POOL_FREE` は OS 起動時に「全エントリを `next` で連結したフリーリスト」の先頭を指すよう初期化する（後述 §6.1）。

---

## 4. IPC4 API の新セマンティクス

### 4.1 API 一覧（変更なし、内部実装のみ変更）

| ワード | スタック効果 | 変更点 |
|---|---|---|
| `IPC4-SEND` | ( msg3 msg2 msg1 msg0 tid -- ) | 内部でプールエントリ確保、宛先キューに enqueue |
| `IPC4-RECV` | ( -- msg3 msg2 msg1 msg0 ) | 内部で自キューから dequeue、エントリ解放 |
| `IPC4-CALL` | ( msg3 msg2 msg1 msg0 tid -- r3 r2 r1 r0 ) | 内部で SEND 相当 + WAIT_REPLY |
| `IPC4-REPLY` | ( r3 r2 r1 r0 tid -- ) | プールを使わず宛先 TCB の `ipc_msg[]` に直接書込 |
| `IPC4-SENDER` | ( -- tid ) | 「直前に IPC4-RECV した sender」を返す（自 TCB から取得） |
| `IPC4-SENDER-DIRECT` | ( -- tid ) | 同上（CODE 版） |

**API は完全互換**。既存 Ph.1〜Ph.3 のクライアント／サーバコードは無修正で動作する。

### 4.2 メッセージ伝送方式の二系統化

設計上、メッセージの流れには 2 種類ある。本設計では両者を**異なる経路**で実装する：

| 流れ | 用途 | 実装方式 |
|---|---|---|
| **request** | client → server の要求メッセージ | プール経由（複数保留可能） |
| **reply** | server → client の応答メッセージ | client TCB 直接書込（保留不要） |

reply をプール経由にしないのは以下の理由：

1. reply は必ず「特定のクライアントが WAIT_REPLY で待っている」状態に届く。クライアントは同時に 1 件しか待てない（IPC4-CALL がブロックするため）。よってクライアント側でキューを持つ必要がない。
2. reply 経路までプールを使うと、プール枯渇時に応答返却が失敗するリスクが生じる（デッドロック温床）。
3. 既存の TCB+16〜+22 の `ipc_msg[]` フィールドを reply 専用に流用すれば実装が単純化する。

### 4.3 TCB IPC フィールドの用途再定義

TCB+14, +16〜+26, +30 の用途を以下のように再定義する：

| Offset | フィールド | 新しい用途 |
|---|---|---|
| **+14** | `ipc_queue_tail` | **request キュー末尾 index**（v1.1 新設） |
| +16〜+22 | `ipc_msg[0..3]` | **reply 受け取り専用バッファ**（IPC4-CALL のクライアント側で使用） |
| +24 | `ipc_valid` | **reply 到着フラグ**（0=未到着、1=到着済） |
| +26 | `last_sender_tid` | **直近 RECV した sender 保存**（IPC4-RECV で書込、IPC4-SENDER で参照） |
| +30 | `ipc_queue_head` | **request キュー先頭 index** |

意味的には：
- 「`ipc_msg[]`/`ipc_valid` ＝ reply 経路用」
- 「`ipc_queue_head`/`ipc_queue_tail` ＋ MsgPool ＝ request 経路用」
- 「`last_sender_tid` ＝ RECV 後の `IPC4-SENDER` クエリ用キャッシュ」

と、**役割が完全に分離**される。これが旧設計の「同じフィールドを request と reply で兼用していた」混乱を解消する。

**v1.1 命名変更：**
- 旧 `ipc_sender` → 新 `last_sender_tid`：「最後に受信したメッセージの送信元」という意味を明示。queue 化により**1 件に絞らず時系列で更新される**フィールドであることを命名で表現。
- なお、API 名 `IPC4-SENDER` / `IPC4-SENDER-DIRECT` は既存互換のため維持。内部的に `last_sender_tid` を読み出す。

### 4.4 状態遷移

タスク状態の定義は変更しないが、各状態への遷移条件を明確化する：

| 状態 | 値 | 遷移元 | 遷移先 |
|---|---|---|---|
| READY | 1 | (各種) | RUNNING |
| RUNNING | 2 | スケジューラ | (各種) |
| WAIT_IPC | 5 | IPC4-RECV（キュー空時） | READY（誰かが SEND/CALL したとき） |
| WAIT_REPLY | 6 | IPC4-CALL（送信完了後） | READY（IPC4-REPLY 受信時） |

**v1.2 注記：** TCB 設計 v1.2 §5.1 で **`WAIT_MSG(4)` は廃止（unused / 予約）**となった。本書の IPC4 系統は WAIT_MSG を使用しないため、本書の記述は変更不要。状態定義の全体一覧と境界原則は TCB 設計 v1.2 §5 を参照のこと。

特に重要な原則（TCB 設計 v1.2 §5.4 より、IPC4 実装に関わるもの）：
- **原則 1**：WAIT_IPC（5）はサーバ側、WAIT_REPLY（6）はクライアント側（経路混乱禁止）
- **原則 2**：WAIT_IPC は `_ipc4_enqueue` で起こす、WAIT_REPLY は `IPC4-REPLY` でのみ起こす
- **原則 3**：state 変更は DI/EI 区間内（本書 §5 のアルゴリズムは全て準拠）
- **原則 5**：RUNNING は同時に 1 個のみ、scheduler 以外が書込禁止（本書のアルゴリズムは RUNNING を変更しない）
- **原則 6**：**WAIT_REPLY 状態のタスクが IPC4-CALL を発行することは禁止**（§5.2 参照）

---

## 5. アルゴリズム詳細

### 5.1 IPC4-SEND / IPC4-CALL の共通前処理：エンキュー（O(1) 版）

両者に共通する処理を `_ipc4_enqueue(dst_tid, sender_tid, msg[4])` として記述する。

**v1.1 で O(1) 化：** tail を使い、末尾追跡ループを廃止。プールから取り出す処理も free list 先頭からの O(1) alloc とした。

```
function _ipc4_enqueue(dst_tid, sender_tid, msg[4]):
    DI                                # 割り込み禁止（クリティカルセクション開始）

    # 1. プールから空エントリを確保（O(1) alloc：free list 先頭から取る）
    idx = MSG_POOL_FREE
    if idx == IDX_NIL:
        EI
        return ERR_IPC_NOSLOT          # プール枯渇 → 即エラー返却（§5.5）

    entry = &MsgPool[idx]
    MSG_POOL_FREE = entry.next         # フリーリストから外す

    # 2. エントリにデータを書込（valid フィールドは無し）
    entry.sender = sender_tid
    entry.msg[0..3] = msg[0..3]        # msg[0]=op, msg[1]=arg0, msg[2]=arg1, msg[3]=arg2
    entry.next = IDX_NIL               # 末尾になるので NIL

    # ★ v1.3 実装注意:
    # IPC4_CALL 冒頭で tid を DSP(X) から pop（ADDI X,#2）した後、
    # IPC4_WK_X に「msg0 先頭アドレス（= 旧TOS+2）」を保存する。
    # _ipc4_enqueue では IPC4_WK_X が msg0 を指す前提でオフセットを計算する：
    #   entry.msg[0] ← [IPC4_WK_X + 0]  (op)
    #   entry.msg[1] ← [IPC4_WK_X + 2]  (arg0)
    #   entry.msg[2] ← [IPC4_WK_X + 4]  (arg1)
    #   entry.msg[3] ← [IPC4_WK_X + 6]  (arg2)
    # v1.2 以前の設計書では「msg3 先頭」と誤記していたため、
    # 実装でインデックスが逆転し op=0000 になるバグが発生した（2026-05-17修正）。

    # 3. 宛先 TCB のキュー末尾に挿入（O(1)：tail を使った追加）
    dst_tcb = &TCB[dst_tid]
    if dst_tcb.ipc_queue_head == IDX_NIL:
        # キュー空 → head と tail 両方を新エントリに
        dst_tcb.ipc_queue_head = idx
        dst_tcb.ipc_queue_tail = idx
    else:
        # キュー非空 → 旧 tail の next と tail だけ更新
        old_tail = dst_tcb.ipc_queue_tail
        MsgPool[old_tail].next = idx
        dst_tcb.ipc_queue_tail = idx

    # 4. 宛先が WAIT_IPC で寝ていたら起こす
    if dst_tcb.state == TASK_WAIT_IPC:
        dst_tcb.state = TASK_READY

    EI
    return OK
```

**ポイント（v1.1 で改善）：**
- alloc/free ともに **O(1)**：free list 先頭からの take/put。
- enqueue の末尾追加も **O(1)**：tail->next = new, tail = new だけ。
- `valid` フィールド廃止：「キューに居る＝使用中、フリーリストに居る＝空」で判定可能（フリーリストは `MSG_POOL_FREE` から `next` 鎖でたどれる）。
- 将来 16 タスク × 多重呼出になっても性能劣化なし。Dhrystone 影響を最小化。

### 5.2 IPC4-CALL の本体

```
function IPC4-CALL(msg[4], dst_tid):
    # ステップ 0（v1.2 追加）: nested CALL 禁止チェック
    # TCB 設計 v1.2 §5.4 原則 6 より、WAIT_REPLY 中の CALL は禁止
    # （A→B→A 循環デッドロックを防ぐ API 規約）
    if CUR_TASK.state == TASK_WAIT_REPLY:
        PANIC("nested CALL forbidden: caller is WAIT_REPLY")
        # ※デバッグビルドのみ。リリースビルドでは省略可

    # ステップ 1: メッセージをエンキュー
    rc = _ipc4_enqueue(dst_tid, CUR_TASK, msg)
    if rc == ERR_IPC_NOSLOT:
        # v1.1: プール枯渇時は即エラー返却（§5.5）
        # 戻り値 4 ワード = (ERR_IPC_NOSLOT, 0, 0, 0) を DSP に push して RET
        push 0
        push 0
        push 0
        push ERR_IPC_NOSLOT
        RET

    # ステップ 2: 自分の reply フィールドをクリア
    DI
    self_tcb = &TCB[CUR_TASK]
    self_tcb.ipc_valid = 0             # reply 未到着

    # ステップ 3: WAIT_REPLY に遷移してスケジューラへ
    self_tcb.saved_pc = &IPC4_CALL_RESUME
    self_tcb.saved_sp = SP             # ★ v1.3 修正: SP のみ（+2 しない）
                                       # saved_pc が別ルーチン（戻り先でない）のため。
                                       # 起床時: SP=saved_sp-4, IRET→SP=saved_sp=SP_orig,
                                       # IPC4_CALL_RESUME 末尾の RET で [SP_orig] pop ✓
    self_tcb.saved_x  = X               # 現 DSP
    self_tcb.state = TASK_WAIT_REPLY
    SP = KERNEL_SP
    JMP _sched_common
    # ※ ここで戻ってきたとき、saved_x が指す DSP に
    #    reply の 4 ワードが既に書き込まれている（§5.4 参照）

IPC4_CALL_RESUME:
    # ステップ 4: TCB の reply バッファ → DSP に転記
    DI
    self_tcb = &TCB[CUR_TASK]
    push self_tcb.ipc_msg[3]
    push self_tcb.ipc_msg[2]
    push self_tcb.ipc_msg[1]
    push self_tcb.ipc_msg[0]
    self_tcb.ipc_valid = 0              # 消費完了
    EI
    RET
```

**v1.1 でのエラー処理（重要）：**
- プール枯渇時は **WAIT_REPLY せずに即返却**。クライアントは戻り値の word0 が `ERR_IPC_NOSLOT` であることをチェックして判断する。
- 既存クライアントコード（Ph.1〜Ph.3）は word0 を opcode 応答として使っているが、`ERR_IPC_NOSLOT = $FFFE` は通常の opcode 応答とは衝突しない値（既存 opcode は $0xxx 系のため）。
- ただし新規コードでは `IPC4-CALL` の戻り値の最初のワードを必ずチェックすることを設計書で推奨する（§5.5 参照）。

**v1.2 で追加された nested CALL 禁止条件：**
- TCB 設計 v1.2 §5.4 原則 6 で確定された API 規約をアルゴリズムに反映。
- 禁止：`state == WAIT_REPLY` のタスクが `IPC4-CALL` を発行
- OK：`IPC4-CALL` 復帰後（state が READY に戻った後）の連続 CALL は問題なし
- 違反するとデッドロック（A→B→A 循環）が発生するため、デバッグビルドで PANIC 検出する。

### 5.3 IPC4-RECV の本体

```
function IPC4-RECV():
    DI
    self_tcb = &TCB[CUR_TASK]

    # ステップ 1: キューが空なら WAIT_IPC で寝る
    if self_tcb.ipc_queue_head == IDX_NIL:
        self_tcb.saved_pc = &IPC4_RECV     # ★ v1.3 修正: 冒頭アドレス（_RESUME廃止）
        self_tcb.saved_sp = SP             # ★ v1.3 修正: SP のみ（+2 しない）
                                           # 起床後 IPC4_RECV 冒頭から再実行し最後に RET。
                                           # RET 時 SP=SP_orig で [SP_orig] pop → 呼元 ✓
        self_tcb.saved_x  = X
        self_tcb.state = TASK_WAIT_IPC
        SP = KERNEL_SP
        JMP _sched_common

# ★ v1.3 変更: IPC4_RECV_RESUME を廃止し IPC4_RECV 冒頭に統合。
#   旧 _RESUME は DI / STW X / JMP IPC4_RECV と等価だったため、
#   saved_pc を IPC4_RECV 冒頭にすることで 9 バイト削減（スロット超過解消）。
IPC4_RECV:   # ← 起床時もここから再開（saved_pc = &IPC4_RECV）
    DI
    # ステップ 2: 起こされた = キューに少なくとも 1 件ある
    self_tcb = &TCB[CUR_TASK]
    idx = self_tcb.ipc_queue_head
    entry = &MsgPool[idx]

    # ステップ 3: キュー先頭を次に進める（v1.1: tail も保守）
    nxt = entry.next
    self_tcb.ipc_queue_head = nxt
    if nxt == IDX_NIL:
        # キューが空になる → tail も NIL に
        self_tcb.ipc_queue_tail = IDX_NIL

    # ステップ 4: sender を TCB に保存（IPC4-SENDER 用）
    self_tcb.last_sender_tid = entry.sender   # v1.1: 命名変更

    # ステップ 5: メッセージを DSP に push
    push entry.msg[3]
    push entry.msg[2]
    push entry.msg[1]
    push entry.msg[0]

    # ステップ 6: エントリをフリーリストに返却（O(1) free）
    entry.next = MSG_POOL_FREE
    MSG_POOL_FREE = idx
    # v1.1: valid フィールドは無いので、valid=0 のクリアは不要

    EI
    RET
```

**ポイント（v1.1 で改善）：**
- dequeue 時に `ipc_queue_tail` も保守する。「head を進めた結果 NIL になった ⇒ キュー空 ⇒ tail も NIL」という規則。
- alloc/free ともに O(1)。
- 「起こされた直後にキューが空」ということは原理的に起きない（起こす側が必ずエントリ追加してから state 変更するため、§5.1 の DI/EI 区間で保証される）。
- ただし防御的コーディングとして、Ph.3.5 実装時にアサート挿入を検討する。

### 5.4 IPC4-REPLY の本体

```
function IPC4-REPLY(reply[4], dst_tid):
    DI
    dst_tcb = &TCB[dst_tid]

    # ステップ 1: reply バッファに書込
    dst_tcb.ipc_msg[0..3] = reply[0..3]
    dst_tcb.ipc_valid = 1
    # dst_tcb.ipc_sender は変更しない（CUR_TASK は呼び元で必要なら別途設定）

    # ステップ 2: 宛先が WAIT_REPLY なら起こす
    if dst_tcb.state == TASK_WAIT_REPLY:
        dst_tcb.state = TASK_READY

    EI
    RET
```

**プールに触らない**点が新設計の重要な特徴。reply 経路は単純で、プール枯渇の影響を受けない。

### 5.5 プール枯渇時の挙動（v1.1 確定）

POOL_SIZE = 32 を想定すると、現実のシステムでは枯渇は稀だが、設計上は明文化が必須。

#### 5.5.1 候補方式の比較

| 方式 | 動作 | メリット | デメリット |
|---|---|---|---|
| A) スピン待ち | 空きが出るまで CPU を回す | 実装最小 | ビジー、デッドロック温床 |
| B) ブロック待ち | 呼出元を WAIT_POOL 状態にして寝かせ、エントリ返却時に起こす | 効率的 | **デッドロック可能性大**（全クライアント WAIT、サーバも WAIT、誰も進まない） |
| **C) 即エラー応答** | `IPC4-CALL` は仮想 reply で `ERR_IPC_NOSLOT` を返す、`IPC4-SEND` は失敗を返す | **deterministic、debug 容易、deadlock 回避** | クライアントがエラー処理必須 |
| D) ASSERT/PANIC | システム異常として停止 | バグ検出に強い | 本番運用に不向き |

#### 5.5.2 採用方針：**方式 C（即エラー応答）** ★ v1.1 で確定

レビュー指摘（review11.txt 重大①）を受け、v1.0 の「初版 PANIC、将来 block」方針を見直し、**初版から方式 C を採用**する。

**理由：**
- **deadlock 回避**：方式 B（block 待ち）は全クライアントが WAIT_POOL になりサーバも進めない状況を作りうる。本物のデッドロック温床。
- **deterministic**：プール枯渇という事象がエラー応答として観測可能。デバッグしやすい。
- **将来移行容易**：将来 block 待ちが必要になったら、エラーを受けたクライアント側でリトライするか、内部で WAIT_POOL に移行するか選択可能。
- **POSIX 文化との整合**：`ENOMEM` 相当のエラー返却は標準的な API パターン。

**仕様：**

| API | 枯渇時の戻り値 |
|---|---|
| `IPC4-CALL` | `( -- 0 0 0 ERR_IPC_NOSLOT )`（DSP に擬似 reply を push） |
| `IPC4-SEND` | カーネル戻り値で失敗を通知（具体方式は実装時に確定。例：エラー時 carry セット等） |

**`ERR_IPC_NOSLOT = $FFFE`** とする。これは：
- `IDX_NIL = $FFFF` と区別可能
- 既存 opcode 応答（0x0000〜0x0FFF 程度）と衝突しない
- 16-bit 符号付きで -2、判定しやすい

**クライアント側のエラー処理推奨パターン：**
```forth
: SAFE-CALL  ( msg3 msg2 msg1 msg0 tid -- r3 r2 r1 r0 success? )
    IPC4-CALL
    DUP $FFFE = IF
        \ ENOSLOT 検出 - リトライまたはエラー報告
        DROP DROP DROP DROP 0   \ failure
    ELSE
        1                        \ success
    THEN ;
```

設計書では枯渇を**「あってはならないが、起きたら検出して処理する事象」として扱う**。POOL_SIZE は「通常運用で枯渇しない値」を選ぶ（POOL_SIZE = 32 が目安、Ph.3.5-c で確定）。

#### 5.5.3 将来拡張：方式 B（ブロック待ち）の検討余地

将来、プール枯渇が頻発するワークロードが発生した場合は方式 B も検討する。その際は以下の deadlock 防止策が必須：
- 各クライアントが保持できるエントリ数に上限を設ける（per-client quota）
- POOL_SIZE をタスク数の 2 倍以上に確保
- 待機キューを優先度付きにし、サーバタスクの待機は短時間に限定

ただし v1.1 では**実装しない**。実装は最低でも Ph.5 ProcMgr 以降。

### 5.6 並行性とクリティカルセクション

| 操作 | クリティカル区間 | 理由 |
|---|---|---|
| `_ipc4_enqueue` | DI 〜 EI で全体保護 | フリーリスト操作とキュー操作が割り込みと競合すると整合性破壊 |
| `IPC4-RECV` の dequeue | 同上 | 同上 |
| `IPC4-REPLY` | 同上 | TCB 状態遷移と reply 書込の不可分性 |
| `IPC4-SENDER` クエリ | 不要 | `ipc_sender` は RECV 完了後に書込まれ、その後変化しない |

すべての DI 区間は短い（数十命令以内）ので、IRQ 応答性への影響は無視できる。

---

## 6. 初期化と運用

### 6.1 起動時のプール初期化

OS 起動シーケンスに以下を追加する：

```
function init_msg_pool():
    # 全エントリを連結してフリーリストを構成
    # v1.1: valid フィールドは無いので初期化不要
    for i in 0..POOL_SIZE-1:
        MsgPool[i].sender = 0
        MsgPool[i].msg[0..3] = 0
        if i < POOL_SIZE - 1:
            MsgPool[i].next = i + 1
        else:
            MsgPool[i].next = IDX_NIL
        MsgPool[i]._pad = 0

    MSG_POOL_FREE = 0     # フリーリスト先頭は index 0
```

### 6.2 TCB 初期化への追加

`TASK_CREATE` の TCB 初期化時、以下を追加する（v1.1 で 2 箇所）：

```
TCB[new_tid].ipc_queue_tail = IDX_NIL    # +14 オフセット（v1.1 新設）
TCB[new_tid].ipc_queue_head = IDX_NIL    # +30 オフセット
```

両方を NIL に初期化することで「キュー空」を表現する。tail だけ NIL にして head が非 NIL という状態は不正であり、絶対に発生してはならない。

### 6.3 タスク終了時のキュー後始末（重要）

**タスクが終了する際、自分のキューに残っているメッセージは全てプールに返却**する必要がある。さもないとプールリーク発生。

```
function task_cleanup_queue(tid):
    DI
    tcb = &TCB[tid]
    idx = tcb.ipc_queue_head
    while idx != IDX_NIL:
        nxt = MsgPool[idx].next
        # 送信者が WAIT_REPLY で待っているはずなので、
        # エラー応答を返す（推奨）
        sender = MsgPool[idx].sender
        if TCB[sender].state == TASK_WAIT_REPLY:
            # ENORECVR 相当のエラー reply（word0 にエラーコード）
            TCB[sender].ipc_msg[0] = ERR_NO_RECEIVER
            TCB[sender].ipc_msg[1..3] = 0
            TCB[sender].ipc_valid = 1
            TCB[sender].state = TASK_READY
        # プールに返却（O(1)）
        MsgPool[idx].next = MSG_POOL_FREE
        MSG_POOL_FREE = idx
        # v1.1: valid フィールドは無いので、valid=0 のクリアは不要
        idx = nxt
    tcb.ipc_queue_head = IDX_NIL
    tcb.ipc_queue_tail = IDX_NIL          # v1.1: tail も NIL に
    EI
```

これは Ph.3.5 では未実装でも構わない（YUI OS は現状タスク動的終了を行わないため）が、Ph.5 ProcMgr で必要になる。**設計書には記載しておく**。

---

## 7. 既存コードへの影響と移行戦略

### 7.1 ソースコードレベルの変更点

| ファイル | 変更箇所 | 規模 |
|---|---|---|
| `kernel_v11.asm` → `kernel_v12.asm` | `IPC4_RECV`/`IPC4_CALL`/`IPC4_REPLY` 全面書き換え、プール管理ルーチン新規 | 大（200〜300 行追加） |
| `kernel_v11.asm` | `TASK_CREATE` の TCB 初期化（+14 = NIL, +30 = NIL） | 小（数行） |
| `kernel_v11.asm` | OS 初期化シーケンス（プール初期化呼出） | 小（数行） |
| `kernel_v11.asm` | `TCB_RSVD1`/`TCB_RSVD2` 定数を `TCB_IPC_QUEUE_TAIL`/`TCB_IPC_QUEUE_HEAD` に rename | 小 |
| `kernel_forth.fs` | 変更なし（API 完全互換） | ゼロ |
| `wake_uart_waiter` / `wake_stor_waiter` | reply 書込部分は IPC4-REPLY コピペベースを維持（§4.2 reply 経路は変更ないため） | ゼロ／微修正 |

### 7.2 クライアント／サーバコードへの影響

**通常運用ではほぼ完全に互換**。Ph.1〜Ph.3 の Forth コードは無修正で動作する。理由：
- API のスタック効果が同一
- セマンティクスが「クリーンな単一クライアント前提」と同じ（多重クライアントが正しく扱えるようになっただけ）

**v1.1 で追加された変更点：プール枯渇時の戻り値**
- `IPC4-CALL` がプール枯渇時に `( -- 0 0 0 $FFFE )` を返す（§5.5）。
- 既存コードは戻り値の word0 を opcode 応答として扱っており、$FFFE は既存 opcode と衝突しないため**実害は出ない**。
- ただし新規コードでは `ERR_IPC_NOSLOT` チェックを推奨。
- 既存コードへの影響はゼロではないが、「枯渇しない POOL_SIZE を選ぶ」ことで実質発生しない。

### 7.3 移植性（YUI OS の汎用化方針との整合）

YUI OS は MC6809 等への移植を想定（プロジェクト方針）。本設計の移植性を確認：

| 要素 | 移植性 |
|---|---|
| プールエントリ 16 B | 8/16/32-bit いずれの CPU でも自然に表現可能 |
| index ベース参照 | ポインタ未使用なのでアドレス幅非依存 |
| `IDX_NIL = $FFFF` | 16-bit 環境前提だが、8-bit/32-bit でも符号反転値などで代替可 |
| FIFO リンクリスト | アルゴリズム自体はアーキテクチャ非依存 |
| POOL_SIZE 可変 | MC6809 等メモリ少環境では `POOL_SIZE = 4` 等に削減可能 |
| DI/EI 区間 | 各 CPU の同等命令で置換可能 |

**移植時の注意：**
- MC6809 では index×16 を `LSL #4` 相当で計算（直接サポートあり）
- ポインタ計算が 16-bit 加算で済むようプール先頭を 16 B 境界に配置することを推奨

---

## 8. 検証計画

### 8.1 単体テスト（Ph.3.5 実装後）

| テストケース | 期待結果 |
|---|---|
| T1: 1:1 通信（既存パターン） | 既存テストが全て通る |
| T2: 2 クライアント → 1 サーバ同時 CALL | 両クライアントとも正しく reply を受け取る |
| T3: 3 クライアント → 1 サーバ同時 CALL | FIFO 順で処理される |
| **T4: クライアント＞ POOL_SIZE** | **`ERR_IPC_NOSLOT` がクライアントに返る（v1.1 仕様）** |
| T5: サーバが RECV 前に複数 SEND | キューに蓄積され、順次取得可能 |
| T6: REPLY のみの単独動作 | プール非使用で動作 |
| T7: HANDOVER_CHAT22 で発覚した競合シナリオ | UART-TEST と STOR-TEST が両立して動く |
| **T8: enqueue O(1) 性能確認** | **キュー長 N に対し enqueue 時間が一定（v1.1 tail 化検証）** |

### 8.2 回帰テスト

- Ph.1（IPC4 Hello/Echo）
- Ph.2（メモリマネージャ）
- Ph.3-A（UART ドライバ）
- Ph.3-B（ストレージドライバ）
- **Dhrystone**（基準値 826 DPS、性能劣化を許容しない）

### 8.3 メモリ消費の確認

| 項目 | 旧 | 新 |
|---|---|---|
| TCB プール | 8 × 80 = 640 B | 16 × 80 = 1280 B（+640 B） |
| MsgPool | 0 | 32 × 16 = 512 B |
| **合計増加** | — | **+1152 B** |

これは Ph.3.5-b メモリマップ再設計で吸収する。

---

## 9. KY 項目（永続的に意識すべき危険）

| # | 危険 | 防止策 |
|---|---|---|
| K1 | プール枯渇時の挙動が曖昧だとフリーズの可能性 | **§5.5 で即 ERR_IPC_NOSLOT 返却に確定。POOL_SIZE は十分大きく取る（32 が叩き台）** |
| K2 | DI/EI の取り忘れでフリーリスト破損 | クリティカル区間を**個別関数化**してコードレビュー対象を明確化 |
| K3 | head/tail の不整合（片方 NIL、片方非 NIL） | enqueue/dequeue の両方で head と tail の整合性を保つコード、デバッグビルドでアサート |
| K4 | reply 経路がプールを使わないことを忘れて誤実装 | **§4.2 で「二系統」を明文化。コードコメントで両系統を区別** |
| K5 | `ipc_queue_head`/`ipc_queue_tail` 初期化忘れ | `TASK_CREATE` で必ず両方 NIL に初期化。初期化漏れアサートを検討 |
| K6 | POOL_SIZE 変更時に IDX_NIL のスキャン範囲を間違える | `POOL_SIZE` は単一の定数で集約定義。複数箇所での重複定義禁止 |
| K7 | リンクリスト循環参照（バグで発生し得る） | デバッグビルドで `next` チェイン長 > POOL_SIZE 時に PANIC |
| K8 | タスク終了時のキューリーク | §6.3 を Ph.5 ProcMgr 設計時に必ず実装 |
| K9 | クライアントが ERR_IPC_NOSLOT を無視して暴走 | 新規コードでは IPC4-CALL の戻り値 word0 をチェック。設計書例（§5.5.2）を参照 |
| K10 | `last_sender_tid` を IPC4-RECV 直後以外に参照すると古い値を読む | API 仕様で「IPC4-RECV から次の操作まで」のみ有効と明記 |

---

## 10. オープン項目（将来課題および後続フェーズ持ち越し）

### 10.1 後続フェーズで確定すべき項目（**v1.2 で全て確定済**）

| 項目 | v1.0/v1.1 ステータス | v1.2 確定状況 |
|---|---|---|
| POOL_SIZE 最終値 | Ph.3.5-c で確定予定 | **✓ 32 確定**（TCB 設計 v1.2 §7.3） |
| MSG_POOL_BASE アドレス | Ph.3.5-b で確定予定 | **✓ $4500 確定**（memmap 設計 v1.1 §4.3） |
| TCB プールの新アドレス範囲 | Ph.3.5-c で確定予定 | **✓ $4000-$44FF 確定**（memmap 設計 v1.1 §4.1） |
| カーネル領域と Forth 領域の明確分離 | Ph.3.5-b で確定予定 | **✓ 確定**（memmap 設計 v1.1 §3.2 で 6 ゾーン分離） |
| Forth code 成長余地の確保 | Ph.3.5-b で確定予定 | **✓ 確定**（memmap 設計 v1.1 §4.5、$C000-$DFFF に 8 KB 予約） |

→ 本書のスコープ内で残された未確定項目は**ゼロ**。実装フェーズへ進める状態。

### 10.2 将来課題（Ph.5 以降）★ v1.1 で明記

| 項目 | 概要 | 想定フェーズ |
|---|---|---|
| **タスク終了時のキュー後始末（task_cleanup_queue）** | §6.3 に設計済み、ProcMgr 実装時に組み込む | Ph.5 ProcMgr |
| **プール枯渇時のブロック待ち（方式 B）** | 現状は即 ERR 返却。将来必要なら WAIT_POOL 状態を新設 | Ph.5 以降 |
| **priority inversion 対策** | 低優先度 server がキューを抱え込むと高優先 client が待たされる。priority inheritance / priority ceiling 等の機構未対応 | Ph.5 以降（必要に応じて） |
| **IPC4-CALL timeout** | 現状は無限待ち。サーバ無応答時の救済機構として `IPC4-CALL-TIMEOUT` API 追加を検討 | Ph.5 以降 |
| **port 抽象への昇格** | 現状は tid を直接アドレスとして使用。port 番号による間接化で動的な service 配置が可能に | Ph.6 以降 |
| **per-client quota** | 1 クライアントが大量にプールを占有することを防ぐ | 必要に応じて |

### 10.3 priority inversion / timeout の現状ステータス（v1.1 明記）

**両者とも v1.1 では未対応**。設計書として以下を明示する：

- **priority inversion 未対応**：YUI OS v2.0 時点では全タスクが同等優先度で動作することを前提とし、priority inheritance 機構は実装しない。将来 FileMgr/ProcMgr/Shell 等の階層構造が複雑化した際に再検討する。
- **IPC4-CALL timeout 未対応**：IPC4-CALL は応答が返るまで無期限にブロックする。サーバタスクのバグやデッドロックによる無応答時、システム全体がハングする可能性がある。デバッグ時は emu23 のタイムアウト機能で検出可能。本番運用での timeout 機構は将来課題とする。

これらは**現時点の設計判断として「シンプルさを優先」**しており、複雑化に対する保険として記録する。実装が必要になった時点で本設計を改版する。

---

## 11. 設計レビュー観点（レビュアー向けチェックリスト）

レビュー時に以下を確認すること：

- [ ] **競合シナリオの根本解決**：HANDOVER_CHAT22 §4.2 のシナリオが本設計で正しく動くか机上検証
- [ ] **API 後方互換性**：既存 Forth コードが無修正で動くことの確認
- [ ] **TCB レイアウト整合**：+14 (rsvd1) を `ipc_queue_tail`、+30 (rsvd2) を `ipc_queue_head` に転用することの妥当性（v1.1）
- [ ] **head/tail 整合性**：両者を NIL/非 NIL の組み合わせで矛盾なく管理できているか（v1.1）
- [ ] **reply 経路の分離**：プール非経由とした判断の妥当性
- [ ] **プール枯渇方針**：即 ERR_IPC_NOSLOT 返却の妥当性、ERR コード値の妥当性（v1.1）
- [ ] **クリティカルセクション**：DI/EI 区間の必要十分性
- [ ] **O(1) alloc/free**：free list 方式の妥当性、valid フィールド削除の妥当性（v1.1）
- [ ] **移植性**：MC6809 等への移植時の懸念事項に抜けがないか
- [ ] **未確定項目の切り分け**：Ph.3.5-c/-b に正しく持ち越されているか
- [ ] **将来課題の明記**：priority inversion / timeout / port 抽象の扱いが明確か（v1.1）
- [ ] **Dhrystone 回帰**：性能影響の見積もり（v1.1 で O(1) 化したので影響軽微）
- [ ] **KY 項目**：実装時の注意点として十分か

---

## 12. 関連文書

**Ph.3.5 設計フェーズ（FIX 済 3 文書、v1.2 で相互整合済）：**
- 本書（`yuios_ipc4_pool_design_v1_3.md`）：IPC4 共通メッセージプール方式
- `yuios_tcb_design_v1_3.md`（最新版）：TCB レイアウト改版
- `yuios_memmap_design_v1_2.md`：メモリマップ再設計

**前提・参照文書：**
- HANDOVER_CHAT22.docx：本設計の出発点（Ph.3.5 引継ぎ）
- yuios_design_v2_0.docx：YUI OS 全体設計書（本設計を反映して改版予定）
- yuios_kernel_memmap_v1_2.md：旧メモリマップ仕様書
- kernel_v12_5.asm：現行カーネル実装（v0.12.6）
- kernel_forth_v0_8_5.fs：現行 Forth カーネル（v0.8.5）
- soudan3.txt：WAIT_IPC vs WAIT_REPLY 解釈確定（解釈A）
- kaizen.txt：開発・デバッグ原則

**レビュー履歴：**
- review11.txt：本書 v1.0 のレビュー指摘（v1.1 で反映）
- review12.txt：v1.1 への FIX 承認 + TCB/memmap レビュー観点
- review13.txt〜review17.txt：TCB / memmap 設計のレビュー履歴

---

## 5.7 IPC4_RECV スロット制約と実装上の注意（v1.3 新設）

IPC4_RECV は `$07E0` から `$08BF`（224 バイト）の固定スロットに配置される。
`$08C0` は IPC4_CALL の先頭（`DI` 命令）であり、IPC4_RECV のコードが 1 バイトでもはみ出すと IPC4_CALL の `DI` 命令を破壊し、アライメント例外や不正動作を引き起こす。

**スロット超過防止ルール（設計レビュー必須項目）：**

| 項目 | 内容 |
|------|------|
| スロット範囲 | `$07E0`〜`$08BF`（224 バイト） |
| 超過検出 | `$08C0` の内容が `03`（DI）であることをアセンブル後に確認 |
| hasm23 の既知制限 | `.org` でコード重なりを警告しない（Step 8-F で対処予定） |
| コードサイズ余裕 | v0.12.6 では `$08BA`〜`$08BF` の 6 バイトが未使用（余裕あり） |

**v1.3 での変更（スロット超過解消のために実施した削減）：**

- msgコピーループの X 退避／復元を廃止し、DSP と entry ポインタを別変数で保持（8 バイト削減）
- `SUBI B,#1` 後の `CMPI B,#0` を削除（SUBI が Z フラグを更新するため不要、4 バイト削減）
- `_ipc4recv_resume` ブロック（`DI / STW X / JMP`）を廃止し IPC4_RECV 冒頭に統合（9 バイト削減）

合計 **21 バイト削減**により、v1.2 のスロット超過を解消し 6 バイトの余裕を確保。

---

*--- 以上 ---*
