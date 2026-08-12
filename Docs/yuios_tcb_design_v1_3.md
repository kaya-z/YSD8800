# YUI OS TCB レイアウト改版設計書（16 タスク化）

**Version:** 1.3
**最終改版:** 2026-05-17
**作成日:** 2026-05-08
**作成者:** Claude
**対象フェーズ:** Ph.3.5-c カーネル基盤改訂（TCB 拡張）
**前提文書:**
- `yuios_ipc4_pool_design_v1_2.md`（FIX 済）
**ステータス:** **FIX**（v1.2 で全項目確定）

---

## 改版履歴

| 版 | 日付 | 内容 | 作成者 |
|---|---|---|---|
| v1.0 | 2026-05-07 | 初版作成（Ph.3.5-c TCB 拡張、IPC4 Pool 設計 v1.1 を前提） | Claude |
| v1.1 | 2026-05-07 | レビュー指摘（review13.txt）反映：①`WAIT_MSG(4)` を unused 化、②`WAIT_REPLY` 永久 block 可能を明記、③nested CALL 禁止条件を「WAIT_REPLY 中の CALL 禁止」に明文化、④RUNNING 状態の唯一性・書込制限を原則明記、⑤TASK_WAKEUP による WAIT_IPC 起床はドライバ IRQ 用途限定と明記 | Claude |
| v1.2 | 2026-05-08 | 後発設計書（memmap v1.1）の確定値を反映：①TCB プール絶対アドレス $4000-$44FF 確定、②MsgPool 配置 $4500-$46FF 確定、③タスクスタック完全分離設計反映（コール $F000-$F7FF / データ $F800-$FBFF）、④KERN_SP 専用配置 $4700-$477F の参照追加、⑤stack guard 領域 $FC00-$FC3F の存在を関連 KY に追加、⑥カーネルワーク領域 $4780-$47BF への参照更新。**確定値の反映のみで新規設計要素は追加せず** | Claude |
| v1.3 | 2026-05-17 | Ph.3.5 Step 6 デバッグで判明した IRQ0_HANDLER バグの設計書反映：①IRQ0 コンテキスト保存条件「state==RUNNING 時のみ」を§5.3.2 に追記、②アイドルループ中 IRQ による saved_pc 破壊バグの原因・修正を§5.5 に記述（新設） | Claude |

---

## 1. 文書の目的とスコープ

### 1.1 目的

本文書は、YUI OS のタスク管理基盤を **8 タスクから 16 タスクへ拡張**するための詳細設計を定義する。前提となる IPC4 共通メッセージプール方式（`yuios_ipc4_pool_design_v1_2.md`）と整合させ、以下を確定する：

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

**本文書のスコープ外（v1.2 時点で memmap 設計 v1.1 にて確定済）：**
- TCB プール／MsgPool／タスクスタックの**絶対アドレス配置** → memmap 設計 v1.1 §4.1 で確定
- カーネル領域と Forth 領域の境界 → memmap 設計 v1.1 §3.2 で確定
- MMIO 境界固定化 → memmap 設計 v1.1 §4.2 で確定（$FC80- 絶対 RAM 禁止）
- 領域成長予約 → memmap 設計 v1.1 §4.4, §4.5 で確定

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

`yuios_ipc4_pool_design_v1_2.md` §3.2.2 で確定済。本書では変更しない。再掲のみ：

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

**v1.2 確定：絶対アドレス `$4000-$44FF`（1280 B）**（memmap 設計 v1.1 §4.1 で確定済）。

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

**【v1.3 追記】IRQ0_HANDLER のコンテキスト保存条件：**

IRQ0_HANDLER は割り込み時の TCB コンテキスト（`saved_pc`, `saved_sp`, `saved_x`, `saved_flags`）を保存してから RUNNING→READY へ遷移する。
**この保存は `state == RUNNING(2)` のタスクにのみ実施する。**

```asm
; v0.12.6 修正版
MOV  X, A           ; X = &TCB[CUR_TASK]
LDW  A, [X]         ; state 読出
CMPI A, #2          ; RUNNING?
BNE  _irq_sched     ; 非RUNNING → コンテキスト保存をスキップ

; コンテキスト保存（RUNNING 時のみ）
...
LDW  A, #1
STW  A, [X]         ; RUNNING → READY
```

**修正背景（2026-05-17）：** `_sc_idle`（アイドルループ）実行中にタイマー IRQ0 が発生すると、`CUR_TASK` が直前に寝たタスク（例: STORドライバ tid=3）のままになっている場合がある。v1.2 以前の実装では state チェックなしにコンテキストを保存したため、アイドルループのPC（`$031F`）が寝ているタスクの `saved_pc` に誤って書き込まれ、そのタスクが正常に起床できなくなるバグが発生した。`state == RUNNING` 限定にすることでこれを防ぐ。
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

### 5.5 IRQ0 アイドル中のコンテキスト破壊バグ（v1.3 新設、実装注意事項）

**バグの概要（2026-05-17 発見・修正）：**

STORドライバ（tid=3）が `TASK_WAIT_IPC_ENTRY` で WAIT_IPC に遷移し、`saved_pc=$D820` を TCB に保存してスケジューラへ JMP した。スケジューラは全タスクが WAIT 状態のため `_sc_idle`（アイドルループ、`EI; NOP; DI; JMP _sched_common`）に入った。

`_sc_idle` 実行中にタイマー IRQ0 が発生。v1.2 以前の `IRQ0_HANDLER` は `CUR_TASK`（= 3）の TCB に、**割り込まれた時点の PC（アイドルループ内 `$031F`）を `saved_pc` として保存**した。

結果として tid=3 の `saved_pc` が `$D820`（正しい起床先）→ `$031F`（アイドルループ）に破壊され、ストレージドライバが IRQ 完了後に起床しても正しいアドレスで再開できず、READ の R3 ループ（SD_DATA 転送）に到達できない症状が発生した。

**根本原因：**

- `_sc_idle` で EI するため IRQ を受け付けられる状態になる
- `CUR_TASK` がアイドル移行時に切り替わらず、直前に寝たタスクの tid のまま
- `IRQ0_HANDLER` が `state == RUNNING` チェックなしにコンテキストを保存

**修正（v0.12.6）：**

§5.3.2 に示す通り、`IRQ0_HANDLER` のコンテキスト保存を `state == RUNNING(2)` 時のみに制限。アイドル中の IRQ では保存をスキップして `_irq_sched` へ直接ジャンプする。

**設計上の教訓（再発防止ルール）：**

> **「`CUR_TASK` が指すタスクが必ずしも RUNNING とは限らない」**  
> スケジューラがアイドルに入っても `CUR_TASK` は変化しない。  
> `IRQ0_HANDLER` など `CUR_TASK` を参照するコードは、必ず state を確認してから操作する。

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
| MsgPool 絶対アドレス | **$4500-$46FF**（v1.2 確定、memmap 設計 v1.1 §4.3） |

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

## 9. メモリ消費の見積もり（v1.2 で memmap 設計 v1.1 と整合）

| 項目 | 旧 | 新 | 差分 | v1.2 確定アドレス |
|---|---|---|---|---|
| TCB プール | 8 × 80 = 640 B | 16 × 80 = 1280 B | +640 B | **$4000-$44FF** |
| MsgPool | 0 B | 32 × 16 = 512 B | +512 B | **$4500-$46FF** |
| カーネル専用スタック（KERN_SP） | （タスクスタック流用） | 128 B 専用確保 | +128 B | **$4700-$477F** |
| カーネルワーク変数（frequently used） | 約 50 B | 64 B | +14 B | **$4780-$47BF** |
| カーネルワーク予約（reserved growth） | — | 64 B | +64 B | **$47C0-$47FF** |
| コールスタック領域（完全分離） | （混在 2 KB） | 16 × 128 B = 2 KB | — | **$F000-$F7FF** |
| データスタック領域（完全分離） | （混在に含まれた） | 16 × 128 B = 2 KB | +2 KB | **$F800-$FBFF** |
| stack guard 領域 | — | 64 B | +64 B | **$FC00-$FC3F** |
| **合計増分** | — | — | **約 +3.4 KB** | — |

**v1.2 重要更新：タスクスタック完全分離設計の反映**

v1.1 では「タスクスタック領域 16 × $100 = 4 KB」と単一領域の前提だったが、memmap 設計 v1.1 の確定により以下に変更：

| 項目 | v1.1 想定 | v1.2 確定（memmap 設計 v1.1 §6.5） |
|---|---|---|
| 配置方針 | コール／データ混在（旧設計の根本欠陥継承） | **コール／データ完全分離**（衝突不可能構造） |
| コール領域 | （単一領域内に分散） | **$F000-$F7FF**（連続 2 KB） |
| データ領域 | （単一領域内に分散） | **$F800-$FBFF**（連続 2 KB） |
| 1 タスクあたり | コール 128 + データ 128 = 256 B | 同（領域分離化） |
| アドレス計算 | tid × $100 系 | **tid << 7** で 1 命令 |
| 衝突可能性 | あり（旧設計から継承） | **なし**（領域が物理的に分離） |

これにより HANDOVER_CHAT22 で発生したスタック衝突バグは**構造的に再発不能**になる。

→ 増加分はすべて memmap 設計 v1.1 で確定したメモリマップに収まっている。

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

`yuios_ipc4_pool_design_v1_2.md` §9 の KY 項目に加えて、TCB 拡張固有の項目：

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
| **K-mem1** | **タスクスタック分離設計の実装誤りで再衝突**（v1.2 新設、memmap 設計 v1.1 §6.5 参照） | コール領域 $F000-$F7FF とデータ領域 $F800-$FBFF の独立性をアサート。`tid << 7` 計算式を全箇所で統一。詳細は memmap 設計 v1.1 K23 |
| **K-mem2** | **KERN_SP の専用配置 ($4700-$477F) の混乱** | 旧設計の「タスクスタック流用」を完全排除。memmap 設計 v1.1 K32 / canary 監視を参照 |
| **K-mem3** | **stack guard ($FC00-$FC3F) の初期化忘れで MMIO 突入検出不能** | memmap 設計 v1.1 §7.4 / K31 を参照。`_kstart` での $A55A 埋めが必須 |

---

## 12. オープン項目（→ 将来フェーズへ持ち越し）

### 12.1 Ph.3.5-b で確定済（v1.2 でクローズ）

本書 v1.0/v1.1 で Ph.3.5-b へ持ち越したすべての項目は、memmap 設計 v1.1 で**確定済**：

| 項目 | v1.0/v1.1 ステータス | v1.2 確定状況 |
|---|---|---|
| TCB プール絶対アドレス | $4000-$44FF が叩き台 | **✓ $4000-$44FF 確定**（memmap 設計 v1.1 §4.1） |
| MsgPool 絶対アドレス | 512 B 確保 | **✓ $4500-$46FF 確定**（memmap 設計 v1.1 §4.1, §4.3） |
| タスクスタック領域配置 | 16 × $100 = 4 KB | **✓ コール $F000-$F7FF / データ $F800-$FBFF 完全分離確定**（memmap 設計 v1.1 §6.5） |
| カーネル変数領域整理 | 最大消費量設計・成長予約・MMIO 境界固定 | **✓ 確定**（memmap 設計 v1.1 §4.1）：frequently used $4780-$47BF / reserved growth $47C0-$47FF / 成長予約 $4800-$4FFF |
| TEST バッファ再配置 | 現状 $E800-$EBFF | **✓ $EC00-$EFFF 確定**（memmap 設計 v1.1 §4.1） |
| Forth コード成長余地確保 | 将来 FileMgr/Shell/libc 増加に備える | **✓ $C000-$DFFF (8 KB) 予約確定**（memmap 設計 v1.1 §4.5） |
| KERN_SP 配置 | （v1.0/v1.1 で言及なし） | **✓ $4700-$477F 専用カーネルスタック確定**（memmap 設計 v1.1 §4.1） |
| stack guard 領域 | （v1.0/v1.1 で言及なし） | **✓ $FC00-$FC3F (64 B) 確定**（memmap 設計 v1.1 §4.1, §7.4） |

→ 本書のスコープ内で残された未確定項目は**ゼロ**。実装フェーズへ進める状態。

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

**Ph.3.5 設計フェーズ（FIX 済 3 文書、v1.2 で相互整合済）：**
- `yuios_ipc4_pool_design_v1_2.md`：IPC4 共通メッセージプール方式（FIX 済、本書の前提）
- 本書（`yuios_tcb_design_v1_2.md`）：TCB レイアウト改版
- `yuios_memmap_design_v1_1.md`：メモリマップ再設計（FIX 済）

**前提・参照文書：**
- `HANDOVER_CHAT22.docx`：Ph.3.5 引継ぎ
- `yuios_design_v2_0.docx`：YUI OS 全体設計書（本書反映で改版予定）
- `kernel_v11_3.asm`：現行カーネル実装（v0.11.3 暫定版）
- `kernel_forth_v0_7_2.fs`：現行 Forth カーネル（v0.7.2）
- `soudan3.txt`：WAIT_IPC vs WAIT_REPLY 解釈確定（解釈A）

**レビュー履歴：**
- `review11.txt`〜`review12.txt`：IPC4 Pool 設計のレビュー履歴
- `review13.txt`：本書 v1.0 のレビュー指摘（v1.1 で反映）
- `review14.txt`：本書 v1.1 への FIX 承認 + memory map レビュー観点
- `review15.txt`〜`review17.txt`：memmap 設計のレビュー履歴

---

*--- 以上 ---*
