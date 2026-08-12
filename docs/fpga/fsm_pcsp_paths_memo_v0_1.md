# FSM PC/SP 更新経路 設計メモ  v0.1  (2026-07-01)

YSD8800 FPGA V1 CPUコア FSM肉付けの PC/SP 更新経路一覧。
本日KY(2026-07-01)防止策②に基づき、実装前に加算量と発火条件を明記する。
根拠は emu23 v1.09 実照合(下記L番号)。

## 原則(本日KY防止策①)
- PC/SP のインクリメントは「state==X かつ 遷移確定サイクル」でのみ1回実行。
- メモリアクセス状態は mem_ready 待ちで滞留する。
  滞留中(mem_ready==0)は加算しない。mem_ready==1 の遷移サイクルでのみ加算。
- regfile の we_pc/we_sp は1クロックパルス(遷移確定サイクルのみ1)。

## PC 更新経路 (emu23実照合)
| 経路 | 状態 | 加算量 | 発火条件 | emu23根拠 |
|---|---|---|---|---|
| リセットベクタ | S_RESET | PC←rd16(0x0000) | mem_ready(hi取得後) | V0§8.2 |
| opcodeフェッチ | S_FETCH | PC+1 | mem_ready | L1191 pc++ |
| rbフェッチ | S_OPFETCH | PC+1 | mem_ready(rb要命令) | L1306 pc++ |
| サブopフェッチ | S_SUBOP | PC+1 | mem_ready(0x1F時) | L1243 pc++ |
| imm下位 | S_IMML | PC+1 | mem_ready | L1259 pc+=2の前半 |
| imm上位 | S_IMMH | PC+1 | mem_ready | L1259 pc+=2の後半 |
| 分岐成立 | S_EXEC_BRANCH | PC←PC+rel16 | 条件成立時のみ | §6.5(BEQ等) |
| JMP | S_EXEC_BRANCH | PC←imm(絶対) | 常時(JMP) | §6.5 |
| JSR | S_EXEC_JSR | PC←target | push後 | §6.5 |
| RET/IRET | S_POP系 | PC←pop | pop完了 | §6.3 |
| 割込受理 | S_IRQ_ACCEPT | PC←rd16(pending*2) | ベクタ読み後 | §6.2 L1096- |

注意: imm16は S_IMML/S_IMMH で +1 ずつ計 +2。emu23の pc+=2 と等価。
      滞留中の二重加算を防ぐため、各状態 mem_ready のワンショットで +1。

## SP 更新経路 (emu23実照合 L832-839)
| 経路 | 加算量 | 順序 | emu23根拠 |
|---|---|---|---|
| push16 | SP-2 | SP-=2 → wr16(SP) (pre-dec) | L832-834 |
| pop16 | SP+2 | rd16(SP) → SP+=2 (post-inc) | L837-839 |

push発生: 割込受理(PC/FLAGS)、JSR(PC)、PUSH A/B/X
pop発生:  IRET(FLAGS/PC)、RET(PC)、POP A/B/X
※ SP/PC/FLAGS の汎用PUSH/POPは無い(§6.5 C-1)。A/B/Xのみ。

## メモリbyte順 (emu23 L824-827, fetch16/wr16/rd16)
- 16bit read : lo=mem[a], hi=mem[a+1], 値={hi,lo} (リトルエンディアン)
- 16bit write: mem[a]←v[7:0], mem[a+1]←v[15:8] (下位→上位)

## 本日の実装スコープ(段階)
1. フェッチ経路(S_RESET/S_FETCH/S_OPFETCH/S_SUBOP/S_IMML/S_IMMH)のPC前進
   → NOP列でPCが1ずつ進むことを最小TBで確認(KY防止策③)
2. 以降(ALU実行/分岐/メモリ/スタック)は確認後に順次肉付け
