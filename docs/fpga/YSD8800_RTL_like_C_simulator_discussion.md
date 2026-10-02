# YSD8800 RTLライクCシミュレータ構想

## 1. 目的

YSD8800 CPUについて、現在の機能レベルのCシミュレータとは別に、

> **SystemVerilog RTL実装のリファレンスとなる、RTLライクなCモデル**

を作成する。

最終的には、次の3段階でYSD8800を検証する。

```text
             ISA仕様
                │
                ▼
┌─────────────────────────┐
│ 機能レベルCシミュレータ │
│ ・命令動作の検証         │
│ ・ISA準拠性の検証        │
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│ RTLライクCモデル        │
│ ・クロック               │
│ ・立上り/立下りエッジ    │
│ ・q/dレジスタ             │
│ ・Blocking assignment    │
│ ・Non-blocking assignment│
│ ・Delta cycle             │
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│ SystemVerilog RTL       │
│ ・CPUコア               │
│ ・テストベンチ          │
│ ・iverilog/Verilator等   │
│ ・GTKWave                │
└─────────────────────────┘
```

RTLライクCモデルを、SystemVerilog RTLに対する **Golden RTL Model** として利用することを想定する。

---

# 2. なぜ現在の機能シミュレータだけでは不足するのか

現在のYSD8800シミュレータは、基本的には

```text
命令を実行
    ↓
CPU状態を更新
    ↓
次の命令
```

という機能モデルになっている。

これはISA検証には非常に有効だが、SystemVerilog RTLとの比較には抽象度が高すぎる。

RTLでは例えば、

```systemverilog
always_ff @(posedge clk)
    pc_q <= pc_d;

always_comb begin
    pc_d = pc_q + 2;
end
```

のように、

- クロック
- レジスタの現在値
- 次状態
- 組み合わせ回路
- クロックエッジ
- non-blocking assignment
- delta cycle

などが明示的に存在する。

したがって、C側でもこれらをある程度再現する。

---

# 3. Cモデルで目指す構造

基本的には、

```text
FF
 ↓
Reg16
 ↓
PC / SP / A / B / X / FLAGS / IR
 ↓
ALU / MUX / Decoder / Bus
 ↓
YSD8800 CPU
```

という構造をCで表現する。

ただし、C++のようなクラス階層にはせず、**純粋なCのstruct + function**で実装する。

例えば16bitレジスタは、

```c
typedef struct {
    uint16_t q;
    uint16_t d;
} reg16_t;
```

とする。

ここで、

- `q` = 現在の値
- `d` = 次状態

とする。

SystemVerilogとの対応は、

```text
C                 SystemVerilog

reg16_t pc        logic [15:0] pc_q, pc_d

pc.q              pc_q
pc.d              pc_d

cpu_eval()        always_comb

posedge処理       always_ff @(posedge clk)
```

となる。

---

# 4. q/d方式

基本となる考え方は、

```c
typedef struct {
    uint16_t q;
    uint16_t d;
} reg16_t;
```

である。

例えばPCなら、

```c
typedef struct {
    reg16_t pc;
} cpu_t;
```

とする。

組み合わせ回路では、

```c
cpu->pc.d = cpu->pc.q + 2;
```

のように次状態を計算する。

クロックエッジで、

```c
cpu->pc.q = cpu->pc.d;
```

として状態を更新する。

概念的には、

```text
          combinational logic
        ┌────────────────────┐
        │                    │
        │    PC + 2          │
        │                    │
        └───────┬────────────┘
                │
                ▼
             pc.d
                │
          ┌─────┴─────┐
          │   clock   │
          │   edge    │
          └─────┬─────┘
                │
                ▼
             pc.q
                │
                └───────────┐
                            │
                            ▼
                    combinational logic
```

となる。

---

# 5. クロックを明示的にモデル化する

単なる

```c
cycle++;
```

ではなく、実際のクロックエッジをモデル化する。

例えば、

```c
typedef enum {
    EDGE_NONE,
    EDGE_RISING,
    EDGE_FALLING
} edge_t;
```

そしてクロック状態として、

```c
typedef struct {
    uint64_t time;
    uint64_t cycle;
    unsigned delta;
    int clk;
    edge_t edge;
} sim_clock_t;
```

を持つ。

これにより、

```text
clk = 0
   ↓
rising edge
   ↓
clk = 1
   ↓
falling edge
   ↓
clk = 0
```

をCモデル上でも明示できる。

---

# 6. Delta cycle

RTLシミュレータでは、同一シミュレーション時刻内でも信号変化に応じて回路を再評価する。

例えば、

```text
time = 100

clk ↑
 ↓
PC更新
 ↓
PC変更を検出
 ↓
命令アドレス変更
 ↓
メモリ出力変更
 ↓
IR変更
 ↓
デコーダ出力変更
```

という一連の変化が発生する。

これをCモデルでも、

```text
time
 └─ delta 0
     └─ delta 1
         └─ delta 2
             └─ stable
```

のように扱う。

例えば、

```c
static void cpu_settle(cpu_t *cpu)
{
    for (unsigned delta = 0; delta < MAX_DELTA; delta++) {
        if (!cpu_eval(cpu))
            break;
    }
}
```

のような構造を想定する。

---

# 7. Blocking assignment

Verilog/SystemVerilogのblocking assignmentは、

```systemverilog
a = b;
```

のように、評価した時点で直ちに値を更新する。

例えば、

```systemverilog
a = b;
c = a;
```

なら、

```text
b = 2
a = 1

a = b;
 ↓
a = 2

c = a;
 ↓
c = 2
```

となる。

Cで単純に書けば、

```c
a = b;
c = a;
```

なので、これは自然に表現できる。

---

# 8. Non-blocking assignment

一方、

```systemverilog
a <= b;
c <= a;
```

では、右辺は現在の値で評価され、更新は後でまとめて行われる。

例えば、

```text
a = 1
b = 2
```

なら、

```systemverilog
a <= b;
c <= a;
```

の結果は、

```text
a = 2
c = 1
```

となる。

重要なのは、

```text
a <= b
```

によってaが即座に2になるわけではないこと。

したがって、

```text
現在値
 a = 1
 b = 2

        │
        ├── a <= b
        │     → aの更新を予約
        │
        └── c <= a
              → cの更新を予約

        ↓

NBA commit

a = 2
c = 1
```

となる。

---

# 9. これまでの最初のCモデルでのNBA表現

最初に提案した

```c
typedef struct {
    uint16_t q;
    uint16_t d;
} reg16_t;
```

方式では、

```text
q = 現在値
d = 次状態
```

としているため、実質的にはnon-blocking assignmentに近い。

例えば、

```c
cpu->a.d = cpu->b.q;
cpu->c.d = cpu->a.q;
```

とすれば、

```text
Aの現在値
Bの現在値
```

を使って次状態を計算できる。

その後、

```c
cpu->a.q = cpu->a.d;
cpu->c.q = cpu->c.d;
```

と一括して更新すれば、

```text
a <= b;
c <= a;
```

と同じ動作になる。

ただし、これはあくまで**暗黙的なNBAモデル**であり、VerilogのNBAキューそのものを実装しているわけではない。

---

# 10. 明示的なNBAキュー

よりRTLシミュレータらしくするなら、NBAを明示的に扱う。

概念的には、

```text
Active region
     │
     │ blocking assignment
     ▼
組み合わせ回路評価
     │
     │ non-blocking assignment
     ▼
NBA queue
     │
     ▼
NBA commit
     │
     ▼
q更新
     │
     ▼
Delta cycle
     │
     ▼
再評価
```

とする。

例えば、

```c
typedef struct {
    reg16_t *target;
    uint16_t value;
} nba_event16_t;
```

のようなイベントを用意する。

そして、

```c
void nba_assign16(nba_queue_t *q,
                  reg16_t *target,
                  uint16_t value);
```

によって、

```c
nba_assign16(&nba, &cpu->a, cpu->b.q);
nba_assign16(&nba, &cpu->c, cpu->a.q);
```

とする。

その後、

```c
nba_commit(&nba);
```

で、

```text
a.q = 2
c.q = 1
```

となる。

---

# 11. RTLシミュレーションの基本フェーズ

最終的には、1クロックを次のようなフェーズに分ける。

```text
                 ┌─────────────────────┐
                 │      Time N         │
                 └─────────┬───────────┘
                           │
                           ▼
                    Clock transition
                           │
                           ▼
                     Rising edge
                           │
                           ▼
                    Active region
                           │
             ┌─────────────┴─────────────┐
             │                           │
             ▼                           ▼
       blocking assignment       NBA scheduling
             │                           │
             └─────────────┬─────────────┘
                           ▼
                      NBA commit
                           │
                           ▼
                         Q更新
                           │
                           ▼
                     Delta cycle
                           │
                           ▼
                  Combinational eval
                           │
                           ▼
                     Stable ?
                       │       │
                      No      Yes
                       │       │
                       └───┐   │
                           │   ▼
                           │ next clock
                           ▼
                       Delta + 1
```

ただし、実際のSystemVerilogイベントスケジューラを完全再現する必要はない。

YSD8800のRTL検証に必要な範囲に限定する。

---

# 12. rising edgeとfalling edge

YSD8800 Cモデルでは、立上り・立下りを明示的に扱えるようにする。

例えば、

```c
static void cpu_posedge(cpu_t *cpu)
{
    /*
     * clocked state update
     */
}

static void cpu_negedge(cpu_t *cpu)
{
    /*
     * optional
     */
}
```

とする。

クロック遷移は、

```c
static void clock_transition(sim_clock_t *sim,
                             int new_clk)
{
    int old_clk = sim->clk;

    sim->clk = new_clk;

    if (!old_clk && new_clk)
        sim->edge = EDGE_RISING;
    else if (old_clk && !new_clk)
        sim->edge = EDGE_FALLING;
    else
        sim->edge = EDGE_NONE;
}
```

のように表現できる。

---

# 13. YSD8800への適用

最終的には、

```c
typedef struct {
    reg16_t pc;
    reg16_t sp;

    reg16_t a;
    reg16_t b;
    reg16_t x;

    reg16_t flags;

    reg16_t ir;

    ...
} ysd8800_cpu_t;
```

のようにCPU内部状態を表現する。

重要なのは、**現在値と次状態を分離すること**。

---

# 14. SystemVerilogとの対応

最終的に、

### C

```c
cpu->pc.q
cpu->pc.d
```

### SystemVerilog

```systemverilog
pc_q
pc_d
```

という1対1に近い対応を目指す。

例えばC側：

```c
void cpu_eval(ysd8800_cpu_t *cpu)
{
    cpu->pc.d = cpu->pc.q + 2;
}
```

SystemVerilog側：

```systemverilog
always_comb begin
    pc_d = pc_q + 16'd2;
end
```

またC側：

```c
void cpu_posedge(ysd8800_cpu_t *cpu)
{
    cpu->pc.q = cpu->pc.d;
}
```

SystemVerilog側：

```systemverilog
always_ff @(posedge clk) begin
    pc_q <= pc_d;
end
```

という対応になる。

---

# 15. 命令実行について

RTLライクCモデルでは、現在の機能シミュレータのように、

```text
fetch
decode
execute
```

を1回の関数呼び出しで完結させるのではなく、最終的にはCPU内部の状態遷移を意識する。

例えば、

```text
FETCH
 ↓
DECODE
 ↓
EXECUTE
 ↓
MEMORY
 ↓
WRITEBACK
```

のようなステートマシンを持たせることもできる。

ただし、これは最初から完全なマイクロアーキテクチャを作る必要はない。

まずは、

```text
clock
register q/d
blocking
non-blocking
delta cycle
combinational logic
```

というRTLシミュレーション基盤を完成させ、その上にYSD8800 CPUを載せる。

---

# 16. 目標とする検証方法

最終的には、同じプログラムを

```text
             YSD8800 binary
                    │
          ┌─────────┴─────────┐
          │                   │
          ▼                   ▼
    RTL-like C            SystemVerilog
       model                  RTL
          │                   │
          ▼                   ▼
      trace C              trace SV
          │                   │
          └─────────┬─────────┘
                    ▼
               cycle compare
```

する。

比較対象として、

```text
PC
A
B
X
SP
FLAGS
IR
memory write
I/O write
interrupt state
```

などを比較する。

---

# 17. VCD/GTKWave

さらに進めるなら、CモデルからVCDを出力する。

例えば、

```text
clk
pc_q
pc_d
a_q
a_d
b_q
b_d
x_q
x_d
sp_q
sp_d
flags_q
flags_d
ir_q
ir_d
```

などを波形として記録する。

SystemVerilog RTL側でもVCDを出力すれば、

```text
YSD8800 C RTL model
        │
        │ VCD
        ▼
    GTKWave
        ▲
        │ VCD
        │
SystemVerilog RTL
```

として同じ波形を比較できる。

これは、RTL実装時のデバッグにかなり有効。

---

# 18. 現時点での実装方針

現段階では、いきなりYSD8800全体をRTL化するのではなく、まず小さなシミュレーションカーネルを作る。

最初の目標は、

```text
1. クロック
2. rising/falling edge
3. q/d register
4. blocking assignment
5. non-blocking assignment
6. NBA queue
7. NBA commit
8. delta cycle
9. combinational evaluation
10. stable判定
```

まで。

その上で、

```text
PC
 ↓
IR
 ↓
Decoder
 ↓
ALU
 ↓
A/B/X/SP/FLAGS
 ↓
Memory
```

と徐々にYSD8800 CPUを載せていく。

---

# 19. 特に重要な設計原則

このCモデルは「CでCPUをエミュレートする」のが目的ではない。

目的は、

> **SystemVerilogでYSD8800 RTLを書く前に、RTLの状態遷移をCで検証できるようにすること**

である。

したがって、

```text
高速な命令エミュレータ
```

よりも、

```text
SystemVerilog RTLと構造・タイミング・状態遷移が対応するCモデル
```

を優先する。

そのため、

```text
Cの便利な書き方
```

より、

```text
RTLでどう記述するか
```

を基準にC側の構造を決める。

---

# 20. 最終的な位置付け

YSD8800プロジェクト全体では、

```text
                    ISA仕様
                       │
                       ▼
              ┌────────────────┐
              │ 機能シミュレータ │
              │  命令レベル      │
              └───────┬────────┘
                      │
                      ▼
              ┌────────────────┐
              │ RTLライクC      │
              │ Golden RTL Model│
              └───────┬────────┘
                      │
                      │ cycle-by-cycle
                      │ comparison
                      ▼
              ┌────────────────┐
              │ SystemVerilog  │
              │ RTL CPU        │
              └───────┬────────┘
                      │
                      ▼
                FPGA / 実機
```

という構成を目指す。

特にRTLライクCモデルについては、

```text
q/d state
clock edge
blocking assignment
non-blocking assignment
NBA queue
delta cycle
combinational settle
```

を明示的にモデル化することで、SystemVerilog RTLとの対応を明確にする。

これによって、SystemVerilog側でバグが発生した場合、

```text
ISA上は正しい
        ↓
C機能モデルも正しい
        ↓
RTLライクCモデルも正しい
        ↓
SystemVerilog RTLだけ異なる
```

という切り分けが可能になる。

逆にRTLライクCモデルとSystemVerilog RTLが一致していれば、その上位にあるISA機能シミュレータとの比較によって、

```text
ISA実装の問題
RTLモデルの問題
SystemVerilog実装の問題
```

を段階的に切り分けられる。
