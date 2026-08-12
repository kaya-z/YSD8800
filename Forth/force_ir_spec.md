# Force IR（中間表現）仕様 v1.0
# YSD8800 Forthクロスコンパイラ Force
# 設計日: 2026-03

---

## 1. IR の基本原則

1. **アーキテクチャ非依存**: レジスタ名・アドレス値・機種固有定数を含まない
2. **テキスト形式**: 1行1命令、デバッグ・差し替えが容易
3. **完全性**: Forthの全制御構造・定義形式を表現できる
4. **最小性**: バックエンドへの負荷を最小化する粒度

---

## 2. テキストフォーマット

```
; コメント（セミコロン以降行末まで）
命令 [オペランド...]
```

- 大文字・小文字は区別しない（内部で大文字正規化）
- ラベルは `.L` プレフィックス + 数字: `.L0:` `.L1:` ...
- ワード名ラベル: `WORD_名前:` 形式（衝突防止）
- 文字列オペランドはダブルクォートで囲む: `"hello"`
- 数値オペランド: 10進または 0x前置16進

---

## 3. IR命令一覧

### 3-1. 構造定義命令

| 命令 | オペランド | 説明 |
|------|-----------|------|
| `WORD` | name | ワード定義開始。ラベル `WORD_name:` を生成 |
| `END-WORD` | — | ワード定義終了。後処理（サイズ計算等）用 |
| `CONST-DEF` | name val | CONSTANT定義。バックエンドがEQUまたは即値として展開 |
| `VAR-DEF` | name size | VARIABLE定義。`size`バイトのデータ領域を確保 |
| `VALUE-DEF` | name init | VALUE定義。初期値`init`を持つ書き込み可能定数 |
| `DEFER-DEF` | name | DEFER宣言。実行ベクタ領域を確保 |
| `IS-DEF` | defer_name impl_name | IS実装。ベクタに`impl_name`のアドレスを設定 |
| `CODE-BLOCK` | — | CODE...END-CODEの開始。以降ASM_LINEが続く |
| `END-CODE` | — | CODE...END-CODEの終了 |
| `ASM-LINE` | text | アセンブラ生テキスト1行（CODE内）。バックエンドに素通し |

### 3-2. スタック操作・データ命令

| 命令 | オペランド | スタック効果 | 説明 |
|------|-----------|-------------|------|
| `PUSH-LIT` | n | ( -- n ) | 数値リテラルをデータスタックにpush |
| `PUSH-STR` | "text" | ( -- addr len ) | 文字列リテラル（データ領域確保+アドレスpush） |
| `PRIM` | name | 可変 | プリミティブワード展開（バックエンドがテンプレートで展開） |

### 3-3. 制御フロー命令

| 命令 | オペランド | 説明 |
|------|-----------|------|
| `LABEL` | .Ln | ラベル定義（分岐ターゲット） |
| `BRANCH` | .Ln | 無条件分岐 |
| `BRANCH-F` | .Ln | スタックTOSが偽（0）なら分岐。TOSをpop |
| `BRANCH-T` | .Ln | スタックTOSが真（非0）なら分岐。TOSをpop |
| `CALL` | name | ワードをサブルーチン呼び出し |
| `RETURN` | — | 現在のワードからリターン |
| `JUMP-TABLE` | n .L0 .L1 ... | n番目のラベルへジャンプ（CASE用、Phase 2） |

### 3-4. メモリアクセス命令

| 命令 | オペランド | スタック効果 | 説明 |
|------|-----------|-------------|------|
| `FETCH-W` | — | ( addr -- val ) | 16bit読み込み |
| `STORE-W` | — | ( val addr -- ) | 16bit書き込み |
| `FETCH-B` | — | ( addr -- val ) | 8bit読み込み（ゼロ拡張） |
| `STORE-B` | — | ( val addr -- ) | 8bit書き込み（下位8bitのみ） |

### 3-5. リターンスタック命令

| 命令 | オペランド | スタック効果 | 説明 |
|------|-----------|-------------|------|
| `RPUSH` | — | ( n -- ) ( R: -- n ) | リターンスタックへpush |
| `RPOP` | — | ( -- n ) ( R: n -- ) | リターンスタックからpop |
| `RFETCH` | — | ( -- n ) ( R: n -- n ) | リターンスタックTOSを読む（コピー） |

---

## 4. PRIMワード一覧

バックエンドのテンプレートで展開するプリミティブワードの標準名称。

### 4-1. スタック操作

| PRIM名 | Forth語 | スタック効果 |
|--------|---------|-------------|
| `DUP` | DUP | ( n -- n n ) |
| `DROP` | DROP | ( n -- ) |
| `SWAP` | SWAP | ( a b -- b a ) |
| `OVER` | OVER | ( a b -- a b a ) |
| `ROT` | ROT | ( a b c -- b c a ) |
| `NIP` | NIP | ( a b -- b ) |
| `TUCK` | TUCK | ( a b -- b a b ) |
| `2DUP` | 2DUP | ( a b -- a b a b ) |
| `2DROP` | 2DROP | ( a b -- ) |

### 4-2. 算術・論理

| PRIM名 | Forth語 | スタック効果 |
|--------|---------|-------------|
| `PLUS` | + | ( a b -- a+b ) |
| `MINUS` | - | ( a b -- a-b ) |
| `STAR` | * | ( a b -- a*b ) |
| `SLASH-MOD` | /MOD | ( a b -- rem quot ) |
| `SLASH` | / | ( a b -- quot ) |
| `MOD` | MOD | ( a b -- rem ) |
| `NEGATE` | NEGATE | ( n -- -n ) |
| `ABS` | ABS | ( n -- \|n\| ) |
| `MAX` | MAX | ( a b -- max ) |
| `MIN` | MIN | ( a b -- min ) |
| `ONE-PLUS` | 1+ | ( n -- n+1 ) |
| `ONE-MINUS` | 1- | ( n -- n-1 ) |
| `TWO-STAR` | 2* | ( n -- n*2 ) |
| `TWO-SLASH` | 2/ | ( n -- n/2 ) |
| `LSHIFT` | LSHIFT | ( n u -- n<<u ) |
| `RSHIFT` | RSHIFT | ( n u -- n>>u ) |

### 4-3. 比較

| PRIM名 | Forth語 | スタック効果 |
|--------|---------|-------------|
| `ZERO-EQ` | 0= | ( n -- flag ) |
| `ZERO-LT` | 0< | ( n -- flag ) |
| `ZERO-GT` | 0> | ( n -- flag ) |
| `EQ` | = | ( a b -- flag ) |
| `NE` | <> | ( a b -- flag ) |
| `LT` | < | ( a b -- flag ) |
| `GT` | > | ( a b -- flag ) |
| `LE` | <= | ( a b -- flag ) |
| `GE` | >= | ( a b -- flag ) |

### 4-4. ビット演算

| PRIM名 | Forth語 | スタック効果 |
|--------|---------|-------------|
| `AND` | AND | ( a b -- a&b ) |
| `OR` | OR | ( a b -- a\|b ) |
| `XOR` | XOR | ( a b -- a^b ) |
| `INVERT` | INVERT | ( n -- ~n ) |

### 4-5. メモリ（PRIMとして展開）

| PRIM名 | Forth語 | スタック効果 |
|--------|---------|-------------|
| `FETCH` | @ | ( addr -- val ) |
| `STORE` | ! | ( val addr -- ) |
| `CFETCH` | C@ | ( addr -- byte ) |
| `CSTORE` | C! | ( byte addr -- ) |
| `PLUS-STORE` | +! | ( n addr -- ) |

### 4-6. I/O

| PRIM名 | Forth語 | スタック効果 |
|--------|---------|-------------|
| `EMIT` | EMIT | ( c -- ) |
| `KEY` | KEY | ( -- c ) |

---

## 5. 制御構造のIR展開パターン

### 5-1. IF...THEN

```forth
: example  n IF action THEN ;
```
```
WORD example
  PUSH-LIT 0        ; n（例）
  BRANCH-F .L0      ; 偽なら .L0 へ
  CALL action
  LABEL .L0
  RETURN
END-WORD
```

### 5-2. IF...ELSE...THEN

```forth
: example  flag IF a ELSE b THEN ;
```
```
WORD example
  BRANCH-F .L0      ; 偽なら else部へ
  CALL a
  BRANCH .L1        ; then部終了
  LABEL .L0
  CALL b
  LABEL .L1
  RETURN
END-WORD
```

### 5-3. BEGIN...WHILE...REPEAT

```forth
: example  BEGIN cond WHILE body REPEAT ;
```
```
WORD example
  LABEL .L0         ; ループ先頭
  CALL cond
  BRANCH-F .L1      ; 条件偽でループ脱出
  CALL body
  BRANCH .L0        ; ループ先頭へ
  LABEL .L1
  RETURN
END-WORD
```

### 5-4. BEGIN...UNTIL

```forth
: example  BEGIN body cond UNTIL ;
```
```
WORD example
  LABEL .L0
  CALL body
  CALL cond
  BRANCH-F .L0      ; 偽なら繰り返し（UNTIL=真で脱出）
  RETURN
END-WORD
```

### 5-5. BEGIN...AGAIN（無限ループ）

```forth
: example  BEGIN body AGAIN ;
```
```
WORD example
  LABEL .L0
  CALL body
  BRANCH .L0
END-WORD          ; RETURNなし（到達しない）
```

### 5-6. VARIABLE

```forth
VARIABLE counter
```
```
VAR-DEF counter 2   ; 2バイト（16bit）のデータ領域
```

バックエンドが生成するアセンブラ:
```asm
WORD_counter:
    .org $XXXX
    DW   0
```
`counter`というワードを呼ぶと`WORD_counter`のアドレスをpushする。

### 5-7. CONSTANT

```forth
42 CONSTANT answer
```
```
CONST-DEF answer 42
```

バックエンドが生成するアセンブラ:
```asm
answer  EQU  42
; または PUSH-LIT 42 のインライン展開（ターゲット設定による）
```

### 5-8. VALUE / TO

```forth
0 VALUE cur-tid
5 TO cur-tid
```
```
VALUE-DEF cur-tid 0

; TO cur-tid の使用箇所:
PUSH-LIT 5
PRIM DUP          ; 値をスタックに積む
; バックエンドが VALUE のアドレスへ STW するコードを生成
; TO はコンパイル時に VALUE のアドレスを知る必要あり
```

**NOTE**: `VALUE`と`TO`の実装はフロントエンドがVALUEの名前→アドレスのマッピングを持ち、
`TO name`を `PUSH-LIT value_addr; STORE-W` に変換する。

### 5-9. DEFER / IS

```forth
DEFER irq-disable
' di-impl IS irq-disable
```
```
DEFER-DEF irq-disable
IS-DEF irq-disable di-impl
```

バックエンドが生成するアセンブラ（サブルーチンスレッド方式）:
```asm
; DEFER: ジャンプベクタとして1ワード（アドレス）を確保
DEFER_irq-disable:
    DW  DEFER_irq-disable_default

; 呼び出し側は間接JSR（ベクタ経由）
; IS: ベクタを書き換え
; [' di-impl IS irq-disable] → STW di-impl-addr, [DEFER_irq-disable]
```

**NOTE**: DEFERの実装方式はターゲット設定（THREAD-MODEL）に依存する。
YSD8800ではジャンプテーブル方式またはロード&ジャンプ方式を選択。

### 5-10. CODE...END-CODE

```forth
CODE irq-disable-impl
    DI
END-CODE
```
```
WORD irq-disable-impl
  CODE-BLOCK
  ASM-LINE "    DI"
  ASM-LINE "    RET"
  END-CODE
END-WORD
```

**NOTE**: `CODE`ブロック内のアセンブラはバックエンドに素通しするが、
`RET`はバックエンドが`RETURN`命令から自動生成するため、
CODEブロック内に`RET`を書くかどうかをターゲット設定で制御する。

---

## 6. IR生成の注意点

### 6-1. ラベル番号管理

ラベルはフロントエンドがグローバルカウンタで採番する。
ワードをまたいでも番号は単調増加する（衝突防止）。

```
WORD foo
  BRANCH-F .L0    ; ← グローバルで0番
  LABEL .L0
END-WORD

WORD bar
  BRANCH-F .L1    ; ← グローバルで1番（0の再利用なし）
  LABEL .L1
END-WORD
```

### 6-2. 名前衝突の回避

生成するアセンブララベルは以下の規則でマングリングする:

```
Forthワード名       → アセンブララベル
-----------         ----------------
double              WORD_double
+                   WORD_PLUS
@                   WORD_FETCH
cur-task            WORD_cur_task    (ハイフン→アンダースコア)
2dup                WORD_2dup
```

### 6-3. 即値の扱い

`PUSH-LIT`のオペランドは符号あり16bitの範囲（-32768〜65535）。
範囲外はフロントエンドがエラーとする。

### 6-4. IMMEDIATE ワードの扱い

`IF` `THEN` `BEGIN` `WHILE` `REPEAT` `UNTIL` `AGAIN` `ELSE`
はすべてフロントエンドがコンパイル時に展開する。
IRには制御構造のワード名は出現しない（BRANCH系命令に変換済み）。

`CONSTANT` `VARIABLE` `VALUE` `DEFER` `IS` も同様にフロントエンドが
対応するIR命令（CONST-DEF等）に変換する。

---

## 7. IRファイル例

```forth
\ kernel/scheduler.fs の一部をIRに変換した例

: task-sleep  ( -- )
  irq-disable
  cur-task @
  TCB-POOL +
  SLEEPING swap tcb-state!
  ( スケジューラ呼び出し )
  next-ready-task schedule-to ;
```

↓ IR:

```
; : task-sleep  ( -- )
WORD task-sleep
  CALL irq-disable
  CALL cur-task
  FETCH-W
  CALL TCB-POOL
  PRIM PLUS
  PUSH-LIT 3           ; SLEEPING = 3
  PRIM SWAP
  CALL tcb-state-store
  CALL next-ready-task
  CALL schedule-to
  RETURN
END-WORD
```

---

## 8. バックエンドとの境界

フロントエンドはIRまでを生成し、標準出力またはファイルに書き出す。
バックエンドはIRを読み込んでアセンブラを生成する。

2段階に分離することで：
- IRファイルを直接編集してデバッグできる
- バックエンドを差し替えるだけで別ターゲットに対応できる
- フロントエンドの単体テストが容易になる

```
force --target ysd8800 input.fs         # フロント+バック一括
force --frontend-only input.fs          # IR生成のみ
force --backend-only input.ir           # IR→アセンブラのみ
```

---

## 9. 未確定事項（Phase 2以降）

以下はPhase 1では実装しない。IRへの追加は後で行う。

| 機能 | 将来のIR命令 |
|------|------------|
| DO LOOP +LOOP | `DO-LOOP` `LOOP-END` `PLUS-LOOP-END` `INDEX` |
| CASE OF ENDOF ENDCASE | `CASE-START` `OF-TEST` `ENDCASE` |
| CREATE DOES> | `CREATE-DEF` `DOES-START` |
| THROW CATCH | `THROW` `CATCH-START` `CATCH-END` |
| S" ." | `PUSH-STR`（既定義）で対応 |
| LOCALS（ローカル変数） | `LOCAL-DEF` `LOCAL-FETCH` `LOCAL-STORE` |
