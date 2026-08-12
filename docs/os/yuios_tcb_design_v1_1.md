# YUI OS TCB レイアウト改版設計書（16 タスク化）

**Version:** 1.1
**作成日:** 2026-05-07
**作成者:** Claude
**対象フェーズ:** Ph.3.5-c カーネル基盤改訂（TCB 拡張）
**前提文書:** `yuios_ipc4_pool_design_v1_1.md`（FIX 済）
**ステータス:** レビュー待ち（v1.1）

---

## 改版履歴

| 版 | 日付 | 内容 | 作成者 |
|---|---|---|---|
| v1.0 | 2026-05-07 | 初版作成（Ph.3.5-c TCB 拡張、IPC4 Pool 設計 v1.1 を前提） | Claude |
| v1.1 | 2026-05-07 | レビュー指摘（review13.txt）反映：①`WAIT_MSG(4)` を unused 化、②`WAIT_REPLY` 永久 block 可能を明記、③nested CALL 禁止条件を「WAIT_REPLY 中の CALL 禁止」に明文化、④RUNNING 状態の唯一性・書込制限を原則明記、⑤TASK_WAKEUP による WAIT_IPC 起床はドライバ IRQ 用途限定と明記 | Claude |

---

## 1. 文書の目的とスコープ

### 1.1 目的

本文書は、YUI OS のタスク管理基盤を **8 タスクから 16 タスクへ拡張**するための詳細設計を定義する。前提となる IPC4 共通メッセージプール方式（`yuios_ipc4_pool_design_v1_1.md`）と整合させ、以下を確定する：

- TCB プールの新範囲
- `MAX_TASKS = 16` への影響範囲
- タスク状態遷移の厳密な再定義
- スケジューラと IPC4 キューの協調動作の検証
- POOL_SIZE 最終値の確定

### 1.2 スコープ

**本文書に含むもの：**
- TCB プール容量・配置（オフセット計算）
- タスク数依存箇所の網羅と修正方針
- 状態遷移図と遷移条件の厳密化
- スケジューラ整合性の机上検証（複数 pending、再 enqueue、nested CALL）
- POOL_SIZE の確定

**本文書のスコープ外（→ Ph.3.5-b で確定）：**
- TCB プール／MsgPool／タスクスタックの**絶対アドレス配置**
- カーネル領域と Forth 領域の境界
- MMIO 境界固定化
- 領域成長予約

### 1.3 設計の前提

- IPC4 Pool 設計 v1.1（FIX 済）に基づく
- TCB サイズ 80 B は **維持**（変更なし）
- 既存 API 互換性を維持（Forth クライアント／サーバコード無修正）

---

## 2. レビュー指摘の反映ポイント（review12.txt）

レビューで挙げられた「次レビューで特に見たいポイント」を本書で扱う：

| # | 指摘 | 対応セクション |
|---|---|---|
| 1 | queue head/tail/last_sender_tid 配置 | §3（IPC4 Pool 設計 v1.1 で確定済を再掲） |
| 2 | 状態遷移の厳密化（WAIT_IPC/WAIT_REPLY 境界、および旧 `WAIT_MSG` の扱い） | §5 |
| 3 | scheduler との整合（複数 pending・RECV 直後再 enqueue・nested CALL） | §6 |

メモリマップ側のレビュー指摘（最大消費量・成長予約・MMIO 境界）は (b) Ph.3.5-b へ持ち越し。

---

## 3. TCB レイアウト（v1.1 FIX 版の再掲）

`yuios_ipc4_pool_design_v1_1.md` §3.2.2 で確定済。本書では変更しない。再掲のみ：

| Offset | Size | フィールド | 用途 |
|---|---|---|---|
| +0  | 2 | `state` | タスク状態（§5） |
| +2  | 2 | `saved_pc` | 保存 PC |
| +4  | 2 | `saved_sp` | 保存 SP（コールスタック） |
| +6  | 2 | `saved_x` | 保存 X（データスタック） |
| +8  | 2 | `saved_a` | 保存 A |
| +10 | 2 | `saved_b` | 保存 B |
| +12 | 2 | `saved_flags` | 保存 FLAGS |
| +14 | 2 | `ipc_queue_tail` | IPC4 キュー末尾 index |
| +16 | 2 | `ipc_msg[0]` | reply バッファ word0 |
| +18 | 2 | `ipc_msg[1]` | reply バッファ word1 |
| +20 | 2 | `ipc_msg[2]` | reply バッファ word2 |
| +22 | 2 | `ipc_msg[3]` | reply バッファ word3 |
| +24 | 2 | `ipc_valid` | reply 到着フラグ |
| +26 | 2 | `last_sender_tid` | 直近 RECV した sender |
| +28 | 2 | `priority` | タスク優先度（未使用、将来用） |
| +30 | 2 | `ipc_queue_head` | IPC4 キュー先頭 index |
| **計** | **80 B** | | |

---

## 4. MAX_TASKS = 16 拡張

### 4.1 TCB プール容量

| 項目 | 旧（v0.11.3） | 新（Ph.3.5-c） |
|---|---|---|
| MAX_TASKS | 8 | **16** |
| TCB サイズ | 80 B | 80 B（変更なし） |
| TCB プール容量 | 8 × 80 = 640 B | **16 × 80 = 1280 B** |

絶対アドレスは Ph.3.5-b で確定するが、暫定的に `$4000-$44FF`（1280 B）を叩き台とする。

### 4.2 アドレス計算式の検証

TCB アドレスは `$4000 + tid × 80` で計算する。tid×80 はアセンブリでは：

```
A = tid << 6 ;  A = tid × 64
A = A + (tid << 4) ; A = tid × 64 + tid × 16 = tid × 80
A = A + $4000      ; A = TCB アドレス
```

**16-bit 演算でのオーバーフロー検証：**

| tid | tid × 80 | $4000 + tid × 80 | 16-bit 範囲内？ |
|---|---|---|---|
| 0  | 0     | $4000 | ✓ |
| 7  | 560   | $4230 | ✓ |
| 8  | 640   | $4280 | ✓ |
| 15 | 1200  | $44B0 | ✓ |
| 31（参考）| 2480  | $4970 | ✓ |

→ tid = 15 まで余裕がある（最大 $44B0 で 16-bit 範囲内）。**32 タスクへの将来拡張も計算式は同一**。

### 4.3 タスク数 8 に依存している箇所の網羅

`kernel_v11_3.asm` を grep で確認した結果、`#8` というハードコードが以下に存在：

| 行 | 箇所 | 内容 | 修正方針 |
|---|---|---|---|
| 318 | `_sched`（IRQ0 タイマ後のスケジューラ） | `CMPI A, #8` （tid==8 でラップ） | `#16` に変更 |
| 429 | `_sc_sched`（_sched_common） | `CMPI A, #8` | `#16` に変更 |
| 607 | `TASK_CREATE` の `_tc_scan` | `CMPI A, #8` （空き slot 検索上限） | `#16` に変更 |
| 1145 | `_init_tcb`（カーネル初期化） | `CMPI B, #8` （TCB ゼロクリアループ） | `#16` に変更 |

**他の `#8` の用途（修正不要）：**
- 行 304, 666, 1166: `[X + #8]` は TCB+8 (`saved_a`) のオフセットで、タスク数とは無関係
- 行 641, 658: `LDW B, #8` は `tid << 8 = tid × 256`（スタックギャップ計算）で、タスク数とは無関係

### 4.4 修正の網羅性確認方針

実装前に以下のチェックを必須とする：

```
$ grep -nE "CMPI [AB], #8($|[^0-9])" kernel_v11.asm
```

これで「タスク数上限の比較」候補が抽出できる。さらに目視で：
- 「ループ変数 vs 上限値」の比較であること
- 「tid を 0..N-1 の範囲で扱っているループ」であること

を確認する。

### 4.5 シンボル化の推奨

将来の拡張容易性のため、`MAX_TASKS` を**定数定義**として導入する：

```asm
MAX_TASKS           EQU 16          ; Ph.3.5-c新設
TCB_POOL            EQU $4000
TCB_SIZE            EQU 80
```

ただし hasm22/23 が即値 EQU を `CMPI` 命令の即値部分に展開できるかは要確認。展開できない場合は数値直書きにコメントで `; MAX_TASKS=16` を併記する。

---

## 5. タスク状態の厳密な再定義

### 5.1 状態一覧（v1.1 確定版）

| 値 | 名称 | 意味 | 遷移元から |
|---|---|---|---|
| 0 | `DEAD` | 未使用スロット（TCB 空き） | (初期化) / (タスク終了：未実装) |
| 1 | `READY` | 実行可能、スケジューラ待ち | RUNNING / SLEEPING / WAIT_IPC / WAIT_REPLY |
| 2 | `RUNNING` | CPU 実行中（同時に 1 つだけ） | READY |
| 3 | `SLEEPING` | `TASK-SLEEP` で自発的にブロック中 | RUNNING |
| 4 | **(unused / 予約)** | **v1.1 で旧 `WAIT_MSG` を廃止。値 4 は将来 `WAIT_DRIVER` や `WAIT_POOL` 等への再利用予約** | — |
| 5 | `WAIT_IPC` | IPC4-RECV でキュー空のため待機 | RUNNING |
| 6 | `WAIT_REPLY` | IPC4-CALL で reply 待機 | RUNNING |

**v1.1 で `WAIT_MSG(4)` を廃止した理由：**
- 旧 IPC（MSG-RECV/MSG-SEND）は IPC4 系統に統合済みで実質未使用
- v1.0 では「新規コードでは使用禁止」と記載したが、レビュー指摘（review13.txt 重大①）どおり「使用禁止と書くなら消すほうが安全」
- スケジューラや dump/timeout/ps コマンドで `if state >= 4` のような雑な比較が混入した場合、レガシ状態が紛れ込むと挙動が壊れるリスク
- 値 4 を歯抜けにせず**「予約」**としておくことで、将来 `WAIT_DRIVER`（ドライバ専用待機）や `WAIT_POOL`（プール枯渇待ち）として転用可能

### 5.2 状態遷移図

```
                              [DEAD (0)]
                                  │ TASK_CREATE
                                  ↓
                              [READY (1)] ←─────────────────────────┐
                                  │                                  │
                  ┌───────────────┼───────────────────────┐         │
                  │ scheduler     │                       │         │
                  ↓               │                       │         │
              [RUNNING (2)]       │                       │         │
                  │               │                       │         │
        ┌─────────┼─────────┬─────┴─────┐                 │         │
        │         │         │           │                 │         │
        │ IRQ0    │ TASK-   │ IPC4-     │ IPC4-           │         │
        │ tick    │ SLEEP   │ RECV      │ CALL            │         │
        │         │         │ (キュー   │                 │         │
        │         │         │  空時)    │                 │         │
        ↓         ↓         ↓           ↓                 │         │
    [READY]  [SLEEPING] [WAIT_IPC]  [WAIT_REPLY]          │         │
              (3)        (5)         (6)                  │         │
                 │         │           │                  │         │
                 │ TASK-   │ 他者の    │ 他者の           │         │
                 │ WAKEUP  │ IPC4-SEND │ IPC4-REPLY       │         │
                 │         │ /CALL    │                  │         │
                 │         │           │                  │         │
                 └─────────┴───────────┴──────────────────┘         │
                                                                    │
                                                          [READY] ←─┘
```

### 5.3 各状態の遷移条件（厳密化）

#### 5.3.1 READY → RUNNING

- スケジューラ（`_sched_common`）が READY なタスクを発見し、CPU を割り当てる
- 同時に 1 タスクのみ RUNNING になる（unicore 前提）

#### 5.3.2 RUNNING → READY

- IRQ0 タイマ割込で `_irq_sched` が起動、現タスクを READY 化してから次タスクを探索
- 現タスクが他にやるべきこと（自発ブロック等）がないとき

#### 5.3.3 RUNNING → SLEEPING

- `TASK-SLEEP` を呼び出した
- 起こすには `TASK-WAKEUP(tid)` を別タスクが呼ぶ必要がある

#### 5.3.4 SLEEPING → READY

- 別タスクが `TASK-WAKEUP(tid)` を呼んだ
- `TASK_WAKEUP` 実装（行 487-517）は state == 3 (SLEEPING) または state == 5 (WAIT_IPC) を READY 化する
- **【v1.1 追加】WAIT_IPC への TASK_WAKEUP はドライバ IRQ 起床用途に限定**（§5.4 原則 4 参照）。一般用途の WAIT_IPC 起床は `_ipc4_enqueue` 経由（IPC4-SEND/CALL）に限る

#### 5.3.5 RUNNING → WAIT_IPC

- `IPC4-RECV` を呼び、自分の `ipc_queue_head == IDX_NIL`（キュー空）だった
- TCB に `saved_pc = IPC4_RECV_RESUME` 設定後にスケジューラへ JMP

#### 5.3.6 WAIT_IPC → READY

- 他タスクが自分宛に `IPC4-SEND` または `IPC4-CALL` を発行
- `_ipc4_enqueue` の最後に `if dst.state == WAIT_IPC then dst.state = READY` で起こされる

#### 5.3.7 RUNNING → WAIT_REPLY

- `IPC4-CALL` を実行し、宛先キューに enqueue 完了
- TCB に `saved_pc = IPC4_CALL_RESUME` 設定後にスケジューラへ JMP

#### 5.3.8 WAIT_REPLY → READY

- 他タスク（典型的にはサーバ）が自分宛に `IPC4-REPLY` を発行
- `IPC4-REPLY` の最後に `if dst.state == WAIT_REPLY then dst.state = READY` で起こされる

**【v1.1 重要警告】WAIT_REPLY は永久ブロック可能な状態である：**
- timeout 機構が未実装のため、サーバが応答しない（バグ／死亡／無限ループ）と、クライアントは**永久に WAIT_REPLY のまま**になる
- cancel 機構も未実装。一度 IPC4-CALL に入ったクライアントは、サーバが REPLY を返すまで自発的に抜け出せない
- **将来課題（§12）**：timeout 付き CALL（`IPC4-CALL-TIMEOUT`）、cancel API、task kill によるキュー後始末（`task_cleanup_queue`：IPC4 Pool 設計 §6.3 参照）が必要
- **当面の運用**：サーバ実装は「必ず REPLY を返す」ことをコード規約として徹底する。デバッグ時は emu23 のタスク状態ダンプで WAIT_REPLY の蓄積を監視

#### 5.3.9 値 4（旧 WAIT_MSG）からの／への遷移

**v1.1 で削除（unused 化）。** 該当する遷移は存在しない。値 4 は将来再利用のための予約。

### 5.4 状態の境界に関する重要原則（v1.1 で確定）

レビュー指摘の「混線が根本原因」に応え、以下を**設計原則**として明記する：

#### 原則 1: 「サーバの待ち」と「クライアントの待ち」を区別する

- `WAIT_IPC`（5）：**サーバ側**（リクエスト到着待ち）
- `WAIT_REPLY`（6）：**クライアント側**（応答到着待ち）

ドライバが「IRQ から起こされる」のもサーバの一形態なので `WAIT_IPC`（5）を使う（soudan3.txt 解釈A 確定）。

#### 原則 2: 状態遷移は**唯一の起床経路**を持つ

| 寝ている状態 | 起こせる API |
|---|---|
| SLEEPING (3) | `TASK-WAKEUP(tid)` |
| WAIT_IPC (5) | `_ipc4_enqueue`（内部）／ `TASK-WAKEUP(tid)`（**ドライバ IRQ 起床用途のみ**、§原則 4） |
| WAIT_REPLY (6) | `IPC4-REPLY` のみ |

→ 「クライアントを `TASK-WAKEUP` で起こす」「サーバを `IPC4-REPLY` で起こす」のような**経路の混乱は禁止**。

#### 原則 3: state を変える者は必ず DI/EI 区間内にいる（原則）

state を変更する操作は**原則として**DI で囲む。理由：state を読んだ瞬間と書いた瞬間の間に IRQ が割り込むと一貫性が崩れる。

具体的には：
- スケジューラ自身は IRQ 文脈、または DI 区間で動作する
- IPC4 系（`_ipc4_enqueue`, `IPC4-RECV`, `IPC4-CALL`, `IPC4-REPLY`）はすべて DI/EI で囲まれる
- `TASK-WAKEUP` は呼出元側で DI を保証するか、内部で DI/EI

**【v1.1 注記：将来の最適化余地】**
本質的に必要なのは「state ＋ queue 整合の原子性」であり、**単独の state 書換のみ**であれば IRQ 文脈で実行しても安全な場合がある（review13.txt 中程度①）。将来 scheduler latency や IRQ jitter が問題化した際は、本原則を緩和する余地がある。ただし本フェーズ（Ph.3.5）では**安全側に倒し DI/EI を必須**とし、最適化は将来課題（§12）として残す。

#### 原則 4: ドライバの「IRQ 起床」は専用 API（wake_*_waiter）

`wake_uart_waiter` のようなドライバ用起床ルーチンは：
- 対象ドライバの state を `WAIT_IPC (5) → READY (1)` にする
- 同時に reply 経路（TCB の `ipc_msg[]`）にデータを書き込む
- これは `IPC4-REPLY` の **コピーペースト**で実装する（カスタム実装禁止、HANDOVER_CHAT22 の重要原則）

**【v1.1 強調】WAIT_IPC への `TASK_WAKEUP` 適用範囲：**
- 一般のクライアント／サーバ間通信での WAIT_IPC 起床は `_ipc4_enqueue` 経由（IPC4-SEND/CALL）**のみ**
- `TASK_WAKEUP` で WAIT_IPC を起こすのは**ドライバ IRQ 起床用途に限定**する
- 将来的に状態を増やす余裕ができたら、独立した `WAIT_DRIVER` 状態（値 4 の予約位置）を導入し、WAIT_IPC と分離するのが綺麗（→ §12 将来課題）
- 当面は state 数節約のため WAIT_IPC を共用するが、**コード上のコメントで「これはドライバ用途」と明示**する

#### 原則 5: RUNNING 状態の唯一性と書込制限（v1.1 新設）

レビュー指摘（review13.txt 重大②）を受けて明文化：

- **RUNNING (state == 2) は同時に高々 1 個**（unicore 前提）
- **state == RUNNING のタスクは必ず `CUR_TASK` と一致する**（不一致は致命バグ）
- **RUNNING への書込／RUNNING からの書込はスケジューラ（`_sched_common` および IRQ0 ハンドラ内のスケジューラ）以外行ってはならない**

理由：
- IRQ 中で「RUNNING → READY」を更新する順序を間違えると、瞬間的に RUNNING が 0 個または 2 個になる事故が起きうる
- これは古典的だが見つけにくいバグ（race condition の温床）
- スケジューラ専用の遷移として扱うことで責任の所在を明確化

**デバッグビルド推奨アサート：**
```
ASSERT: count(state == RUNNING) <= 1
ASSERT: state[CUR_TASK] == RUNNING （CUR_TASK 設定後）
```

**【将来課題】RUNNING 状態の廃止案（→ §12）：**
RUNNING を独立状態として持つ代わりに、`CUR_TASK` だけで「現在実行中のタスク」を表現する設計も可能。実装変更は大きいが、状態数を 1 つ減らせる。Ph.5 以降で再検討する余地あり。

#### 原則 6: nested CALL の禁止条件（v1.1 で明文化）

レビュー指摘（review13.txt 中程度③）を受け、禁止条件を厳密化：

- **禁止：`state == WAIT_REPLY` のタスクが `IPC4-CALL` を発行すること**
- **OK：`IPC4-CALL` から復帰（state が READY に戻った後）に再度 `IPC4-CALL` を発行すること**

つまり「CALL 中に CALL するな」ではなく「**WAIT_REPLY のまま CALL するな**」が正しい禁止条件。

**実装上の検出：**
```
IPC4_CALL の入口で：
  if self.state == WAIT_REPLY then PANIC   ★デバッグビルド推奨
```

通常の RUNNING 状態からの CALL であれば、たとえ過去に何度も CALL していても問題ない。WAIT_REPLY 中はクライアントは自分のキューを RECV する能力がないため、循環待ちになる（§6.3 シナリオ C 参照）。

---

## 6. スケジューラ整合性の机上検証

レビュー指摘 #3「REPLY → READY 化だけで本当に十分か？」に応えるため、3 つの懸念シナリオを机上検証する。

### 6.1 シナリオ A: 複数 pending（同一サーバに 3 件同時 CALL）

```
時刻  状態
 t0   client1, client2, client3 が READY
      server が WAIT_IPC（キュー空）
 t1   client1 が IPC4-CALL → enqueue idx=0、server を READY 化
      client1 → WAIT_REPLY
 t2   スケジューラ：client2 が選ばれる
 t3   client2 が IPC4-CALL → enqueue idx=1（server は既に READY なので state 変更なし）
      client2 → WAIT_REPLY
 t4   client3 が IPC4-CALL → enqueue idx=2
      client3 → WAIT_REPLY
 t5   server が走り、IPC4-RECV → idx=0 取得（client1 のメッセージ）
      キュー head = 1, tail = 2 となる
 t6   server が処理して IPC4-REPLY(client1) → client1 を READY 化
 t7   server が次の IPC4-RECV → idx=1 取得（client2 のメッセージ）
      キュー head = 2, tail = 2
 t8   ...
```

**検証結果：** 
- 3 件全てがプールに保持され、FIFO 順で処理される ✓
- server は最初の enqueue で READY 化された後、自分で次の RECV を呼ぶまで READY のまま（連続処理可能）✓
- 各クライアントは独立に WAIT_REPLY → READY 遷移する ✓

**REPLY → READY 化だけで十分？**
- 答え：**十分**。なぜなら client は独立した TCB を持ち、server からの REPLY は宛先 client tid を指定して直接届くため。

### 6.2 シナリオ B: RECV 直後の再 enqueue

```
時刻  状態
 t0   server が IPC4-RECV を呼んだ。キューは [idx=0] のみ。
      → idx=0 を dequeue、メッセージを取得
      → キュー空（head = NIL, tail = NIL）
      → server は DSP に msg を持ったまま継続（state は RUNNING のまま）
 t1   IRQ0 で client1 にコンテキスト切替
      client1 が IPC4-CALL → enqueue idx=3（プールから新規 alloc）
      server は WAIT_IPC ではないので state 変更なし
 t2   IRQ0 で server に切替
      server が処理を完了して、次の IPC4-RECV を呼ぶ
      → キュー先頭 = idx=3、これを dequeue して取得
```

**検証結果：**
- server が連続して RECV を呼んでも、間に enqueue が来た分が正しく FIFO で取得される ✓
- 「RECV 直後にキュー空 → 新規 enqueue」と「server が次の RECV を呼ぶ」のタイミング順序は問わない（state == RUNNING のまま処理されるため、enqueue 側は state 変更不要）✓

**懸念点：** 
- もし server が RECV を呼んだ瞬間にキューが空でかつ enqueue が DI の途中で走った場合？
  - → DI 区間で保護されているので、enqueue は server の RECV が DI を握っている間は実行できない。順序は必ず一方向に決まる。

### 6.3 シナリオ C: nested CALL（A → B → A 循環）

```
時刻  状態
 t0   A が IPC4-CALL(B) → A は WAIT_REPLY、B のキューに enqueue
 t1   B が IPC4-RECV → A のメッセージ取得
 t2   B が処理中に IPC4-CALL(A) を呼びたくなった ★
      → B → WAIT_REPLY、A のキューに enqueue
      しかし A は既に WAIT_REPLY 状態で、自分のキューを RECV する能力がない
 t3   デッドロック発生：A は B からの REPLY を待ち、B は A からの REPLY を待つ
```

**検証結果：**
- これは**設計上のデッドロック**であり、IPC4 機構自体の問題ではない
- Mach や L4 等の他のマイクロカーネルでも同じ問題が存在する（"nested IPC" 問題）

**v1.1 での対応方針（禁止条件の厳密化）：**

レビュー指摘（review13.txt 中程度③）を受け、禁止条件を以下のとおり**厳密に**定義：

| 状況 | 可否 |
|---|---|
| RUNNING 状態のタスクが IPC4-CALL を発行 | **OK**（通常の使い方） |
| 過去に CALL した後、REPLY を受信して RUNNING に戻ったタスクが再度 CALL | **OK**（連続 CALL は問題なし） |
| **WAIT_REPLY 状態のタスクが IPC4-CALL を発行** | **禁止**（デッドロック原因） |

つまり「CALL 中に CALL するな」という曖昧な表現ではなく、「**WAIT_REPLY のまま CALL するな**」が正しい禁止条件。CALL → REPLY 受信 → 次の CALL のシーケンスは何ら問題ない。

**実装上の検出（デバッグビルド推奨）：**
```
function IPC4-CALL(...):
    if CUR_TASK.state == WAIT_REPLY:
        PANIC("nested CALL forbidden: caller is WAIT_REPLY")
    ...
```

**例外について：**
- 「ドライバ A が ドライバ B に CALL する」シーン自体は禁止していない（A が RUNNING のままなら OK）
- 問題なのは「A が CALL で WAIT_REPLY 中に、B からの REPLY 経路上で A 自身が再度 CALL を呼ばれる」状況
- 現実には、ドライバ間の CALL は避けるのが健全な設計。サーバ間で循環呼出を作らない API 設計を心がける（§12 将来課題）

**特殊ケース：A がドライバ起床のために RECV を間接的に呼ぶケース**
- 例：A がストレージドライバ、A が CALL(B=UARTドライバ) で文字を出したい場合
- これは現実的には起きない（ドライバ間で CALL し合う設計は避ける）
- もし必要なら、「CALL を発行する側の state」を厳密にチェックする補助機構が必要

### 6.4 検証まとめ：REPLY → READY 化で十分

| シナリオ | 結果 |
|---|---|
| A. 複数 pending | ✓ 動作する |
| B. RECV 直後再 enqueue | ✓ 動作する |
| C. nested CALL | × デッドロック（**WAIT_REPLY 中の CALL を API で禁止**することで回避） |

→ シナリオ A/B は機構上正しく動く。C はマイクロカーネル一般の問題で、API 規約（原則 6）で対処する。

---

## 7. POOL_SIZE の確定

### 7.1 in-flight メッセージ数の見積もり

POOL_SIZE は「同時に **in-flight な request メッセージ**の最大数」で決まる。

**worst case の計算：**

| クライアント | 同時に保留できる request 数 | 備考 |
|---|---|---|
| 各 task | 最大 1 件 | IPC4-CALL は WAIT_REPLY するので、同一 task が同時に 2 件 in-flight にすることはない |
| 16 タスク全員が CALL を発行 | 16 件 | 全員が同じサーバに送ると max |

つまり「**16 タスクが全員 CALL 発行 → 全員 WAIT_REPLY**」という最悪条件で in-flight 数 = 16。

### 7.2 安全マージン

以下を考慮して安全マージンを上乗せ：

| 要因 | 追加分 |
|---|---|
| `IPC4-SEND`（非ブロッキング送信）が連続する場合の追加滞留 | +8 |
| 将来 16 → 32 タスク拡張時の余裕 | +8 |
| 設計上の安全マージン | — |

合計：16 + 8 + 8 = **32 が妥当**。

### 7.3 POOL_SIZE = 32 確定

| 項目 | 値 |
|---|---|
| POOL_SIZE | **32** |
| MsgEntry サイズ | 16 B |
| MsgPool 総容量 | 32 × 16 = **512 B** |

絶対アドレス（MSG_POOL_BASE）は Ph.3.5-b で確定。

### 7.4 POOL_SIZE 変更時の影響

万が一 32 で不足が判明した場合の変更コストは小さい：

- 定数 `POOL_SIZE` の変更（1 箇所）
- メモリマップでのプール領域確保サイズ変更（Ph.3.5-b）
- `init_msg_pool` のループ上限は定数参照になっているので自動追従

ただし `IDX_NIL = $FFFF` は POOL_SIZE が 65535 を超えない限り問題なし（実質無制限）。

---

## 8. 実装変更点まとめ

### 8.1 kernel_v11.asm → kernel_v12.asm

| 変更カテゴリ | 行数の見積もり | 内容 |
|---|---|---|
| 定数追加 | +5 行 | `MAX_TASKS = 16`, `POOL_SIZE = 32`, `IDX_NIL = $FFFF`, `ERR_IPC_NOSLOT = $FFFE`, `MSG_ENTRY_SIZE = 16` |
| TCB プール拡張 | +0 行（容量変更のみ） | `$4000-$44FF` に拡大 |
| `_init_tcb` ループ上限 | 1 行修正 | `CMPI B, #8` → `CMPI B, #16` |
| `_irq_sched` のラップ | 1 行修正 | `CMPI A, #8` → `CMPI A, #16` |
| `_sc_sched` のラップ | 1 行修正 | `CMPI A, #8` → `CMPI A, #16` |
| `TASK_CREATE` の slot 検索上限 | 1 行修正 | `CMPI A, #8` → `CMPI A, #16` |
| `TCB_RSVD1`/`TCB_RSVD2` rename | 2 行修正 | `TCB_IPC_QUEUE_TAIL = 14`, `TCB_IPC_QUEUE_HEAD = 30` |
| MsgPool 初期化呼出 | +5 行 | `JSR init_msg_pool` を `_kstart` に追加 |
| MsgPool 初期化ルーチン本体 | +50 行 | 新規（IPC4 Pool 設計 §6.1） |
| IPC4_RECV/CALL/REPLY 全面書換 | +200 行 | IPC4 Pool 設計 §5 に基づく |
| TASK_CREATE 内 TCB 初期化追加 | +6 行 | `ipc_queue_tail = NIL`, `ipc_queue_head = NIL` |

合計：約 **270 行追加 / 6 行修正**。

### 8.2 kernel_forth_v0_7_2.fs

**変更なし**。API 完全互換のため。

ただし、`STOR-WAIT-TID` のような**単一スロット前提の補助変数**は今後不要になる可能性がある。これは Ph.3.5 実装後の整理項目とする（本書では削除しない）。

### 8.3 yuios_design_v2_0.docx

設計書全体の改版項目（§10 で網羅）：
- §3 タスク管理：MAX_TASKS = 16、TCB プール範囲更新
- §4 IPC：共通メッセージプール方式の説明追加（既に IPC4 Pool 設計 v1.1 で詳細化済）
- §10.1 ロードマップ表に Ph.3.5 行を追加

---

## 9. メモリ消費の見積もり（Ph.3.5-b 用の参考値）

| 項目 | 旧 | 新 | 差分 |
|---|---|---|---|
| TCB プール | 8 × 80 = 640 B | 16 × 80 = 1280 B | +640 B |
| MsgPool | 0 B | 32 × 16 = 512 B | +512 B |
| タスクスタック領域 | 8 × $100 = 2 KB | 16 × $100 = 4 KB | +2 KB |
| カーネルワーク変数 | 約 50 B | 約 60 B（MSG_POOL_FREE 等追加） | +10 B |
| **合計** | — | — | **+3162 B（約 +3 KB）** |

→ Ph.3.5-b でこの増加分を吸収するメモリマップを設計する必要がある。

タスクスタックは現状 1 タスク = $100（256 B）でコール 128 + データ 128 の暫定制限がかかっている。Ph.3.5-b ではここも見直す。

---

## 10. 設計レビュー観点（v1.1 チェックリスト）

レビュー時に確認していただきたい項目：

- [ ] **MAX_TASKS = 16 の妥当性**：将来 32 タスクへの拡張容易性も含めて
- [ ] **アドレス計算式**：tid = 15 までオーバーフローしないことの確認
- [ ] **タスク数依存箇所の網羅**：grep で抽出した 4 箇所で十分か、他に隠れていないか
- [ ] **状態遷移図の厳密性**：レビュー指摘 2 への応答として十分か
- [ ] **`WAIT_MSG(4)` の unused 化**（v1.1）：レガシ削除の妥当性、値 4 を予約として残す判断の妥当性
- [ ] **`WAIT_REPLY` 永久 block 警告**（v1.1）：§5.3.8 の記載で運用上十分か、当面の回避策が現実的か
- [ ] **状態遷移の境界原則**（§5.4）：原則 1〜6 の網羅性
- [ ] **原則 5（RUNNING の唯一性）**（v1.1）：書込制限の妥当性、デバッグアサート提案
- [ ] **原則 6（nested CALL 禁止）**（v1.1）：「WAIT_REPLY 中の CALL 禁止」という条件の妥当性
- [ ] **原則 4（TASK_WAKEUP の用途限定）**（v1.1）：ドライバ用途限定の明記で十分か
- [ ] **scheduler 整合性検証**（§6）：3 シナリオ（A/B/C）の机上検証で十分か
- [ ] **POOL_SIZE = 32**：見積もり方法の妥当性、安全マージンの十分性
- [ ] **メモリ消費見積もり**（§9）：Ph.3.5-b への引継ぎ情報として十分か
- [ ] **kernel_forth.fs 無変更**：本当に変更不要か（特に STOR-WAIT-TID 等の整理タイミング）

---

## 11. KY 項目（v1.1 追加分）

`yuios_ipc4_pool_design_v1_1.md` §9 の KY 項目に加えて、TCB 拡張固有の項目：

| # | 危険 | 防止策 |
|---|---|---|
| K11 | tid×80 計算式の修正漏れで TCB が混線 | 計算式は変更不要（tid=15 まで OK）。grep で全箇所網羅確認 |
| K12 | `#8` ハードコードの修正漏れでタスク 8〜15 が無視される | §4.4 のチェックリスト実施。修正後は emu23 で 16 タスク作成テスト |
| K13 | 状態遷移の経路混乱が再発（HANDOVER_CHAT22 と同種のバグ） | §5.4 の原則を守る。コードコメントで「この state 変更は原則 N に従う」と明記 |
| K14 | nested CALL を API 規約で禁止しても誤って実装される | コードレビューでチェック。**デバッグビルドで `if state==WAIT_REPLY then PANIC` を IPC4-CALL 入口に追加**（v1.1）。timeout 実装時に検出機構を追加 |
| K15 | POOL_SIZE 不足で本番中に枯渇エラー多発 | Ph.3.5 統合テストで stress test を実施。32 で不足ならば早期に増加 |
| K16 | TCB 初期化の追加項目（+14, +30）忘れで未定義動作 | TASK_CREATE のテストで初期値が NIL であることを emu23 ダンプで確認 |
| K17 | 値 4 (旧 WAIT_MSG) を誤って使用するコードが混入（v1.1） | コードレビューで「state == 4」「TASK_WAIT_MSG」参照を全面禁止。**設計書 §5.1 で「予約・未使用」を明記** |
| K18 | RUNNING 状態が瞬間的に 0 個または 2 個になる race（v1.1） | scheduler 以外が state==2 を書かない。**デバッグアサート：`count(state==RUNNING) <= 1`、`state[CUR_TASK] == RUNNING`** |
| K19 | `WAIT_REPLY` で永久 block する不具合（v1.1） | サーバ実装は「必ず REPLY を返す」をコード規約で徹底。emu23 のタスク状態ダンプで WAIT_REPLY 蓄積を監視 |
| K20 | `TASK_WAKEUP` を一般用途で WAIT_IPC に対して使ってしまう（v1.1） | コードレビューで `TASK_WAKEUP` の呼出元が**ドライバ IRQ 起床のみ**であることを確認。コメントで「ドライバ用途」と明示 |

---

## 12. オープン項目（→ Ph.3.5-b および将来フェーズへ持ち越し）

### 12.1 Ph.3.5-b へ持ち越し

| 項目 | 備考 |
|---|---|
| TCB プール絶対アドレス | $4000-$44FF が叩き台 |
| MsgPool 絶対アドレス | 512 B 確保 |
| タスクスタック領域配置 | 16 × $100 = 4 KB |
| カーネル変数領域整理 | レビュー指摘「最大消費量設計」「成長予約」「MMIO 境界固定」反映 |
| TEST バッファ再配置 | 現状 $E800-$EBFF |
| Forth コード成長余地確保 | 将来 FileMgr/Shell/libc 増加に備える |

### 12.2 将来課題（Ph.5 以降、v1.1 で追加明記）

レビュー指摘（review13.txt）で挙げられた将来検討項目：

| 項目 | 概要 | 想定フェーズ |
|---|---|---|
| **WAIT_REPLY の timeout 機構** | `IPC4-CALL-TIMEOUT` API 追加。サーバ無応答時の救済 | Ph.5 以降 |
| **WAIT_REPLY の cancel 機構** | クライアントが自発的に CALL を中断する API | Ph.5 以降 |
| **task kill によるキュー後始末** | `task_cleanup_queue`（IPC4 Pool 設計 §6.3）の実装 | Ph.5 ProcMgr |
| **`WAIT_DRIVER` 独立状態の導入**（v1.1 追加） | 値 4 の予約位置に再定義。WAIT_IPC と用途分離して綺麗にする | Ph.5 以降（必要時） |
| **`RUNNING` 状態の廃止**（v1.1 追加） | `CUR_TASK` だけで「現実行」を表現。状態数を 1 つ減らす | Ph.5 以降（実装変更大） |
| **state 単独書換の DI/EI 緩和**（v1.1 追加） | scheduler latency / IRQ jitter が問題化した際の最適化 | Ph.5 以降（必要時） |
| **`priority inversion` 対策** | priority inheritance / priority ceiling 等 | Ph.5 以降 |
| **port 抽象への昇格** | tid 直接指定から port 番号による間接化へ | Ph.6 以降 |
| **サーバ間循環呼出の禁止規約** | nested CALL 問題の予防 | Ph.5 ProcMgr 設計時 |

---

## 13. 関連文書

- `yuios_ipc4_pool_design_v1_1.md`：IPC4 共通メッセージプール方式詳細設計（FIX 済、本書の前提）
- `HANDOVER_CHAT22.docx`：Ph.3.5 引継ぎ
- `review11.txt`：IPC4 Pool 設計 v1.0 のレビュー指摘
- `review12.txt`：IPC4 Pool 設計 v1.1 への FIX 承認＋ TCB/memory map レビュー観点
- `review13.txt`：本書 v1.0 のレビュー指摘（v1.1 で反映）
- `yuios_design_v2_0.docx`：YUI OS 全体設計書（本書反映で改版予定）
- `kernel_v11_3.asm`：現行カーネル実装（v0.11.3 暫定版）
- `kernel_forth_v0_7_2.fs`：現行 Forth カーネル（v0.7.2）
- `soudan3.txt`：WAIT_IPC vs WAIT_REPLY 解釈確定（解釈A）

---

*--- 以上 ---*
