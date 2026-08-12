# HANDOVER — scc23 v2.00 Step 7（float ランタイム）作業引き継ぎ

日付: 2026-06-23
作成理由: チャット内で表示混入（不正文字列）が多発したため、チャットを改める。
次チャットはこの文書を起点に再開する。

---

## 0. 即・最優先タスク（次チャットの最初の作業）

**🔴 _fdiv の引数逆転バグを修正する。** これは「見えているバグ」であり最優先で潰す。

### バグの確定内容
- 症状: float除算 `a / b` の結果が **逆数（b/a相当）** になる。
  - 実測: `3.0/1.5` → 0x0080(=0.5, 期待0x0200=2.0)、`1.0/4.0` → 0x0400(=4.0, 期待0x0040=0.25)、`10.0/2.0` → 0x0033(≈0.2, 期待0x0500=5.0)。全て逆数。
- 真因（asm目視で確定済）: `emit_expr` の **SIR_FDIV** が cc_mul と同じ評価規約
  （left→push, right→pop B）で出力しているため、JSR _fdiv 時点で
  **A=right(除数b), B=left(被除数a)** となる。
  しかし _fdiv ランタイムの入口規約は **A=被除数a, B=除数b**。A/Bが逆。
- _fmul で露見しなかった理由: 乗算は可換なので A↔B が逆でも結果が同じだった。
  除算は非可換なので露見した。

### 修正方針（どちらか。要・実装時判断＋emu23再検証）
- 案1: `emit_expr` の `case SIR_FDIV:` で、JSR直前に A↔B をスワップする命令を足す
  （ただしISA2.3にレジスタ交換命令があるか要確認。無ければ一時退避でswap）。
- 案2（推奨・シンプル）: SIR_FDIVのemitを「left→評価しpush、right→評価、
  そのあと **A=pop(left=被除数), B=right(除数)** になるよう順序を入れ替える」。
  - 具体的には _fmul/_fdiv 共通の評価規約を見直し、_fdiv だけ
    「B←right を先に確保、A←left を後」にする。
  - cc_div（整数除算）が同じ規約でどう正しく動いているか先に確認し、それに倣うのが安全
    （cc_div は正しく動いている＝整数除算は逆転していない。SIR_DIV と SIR_FDIV の
    emit を比較し、なぜ SIR_DIV は正しくて SIR_FDIV が逆転するのか差分を見ること）。
- **修正後、必ず emu23 で _fdiv 全境界ケース（下記）を再検証**してから次へ。

### _fdiv 期待値（emu23検証用・C先行検証 NG=0 で確定済）
```
3.0 / 1.5  = 0x0200    3.0 / 2.0  = 0x0180
1.0 / 4.0  = 0x0040    10.0 / 2.0 = 0x0500
-3.0 / 1.5 = 0xFE00    -6.0 / -2.0= 0x0300
100.0/10.0 = 0x0A00    127.0/ 1.0 = 0x7F00
```

---

## 1. Step 7 進捗サマリ

### ✅ 完了
- **テストハーネス** `ftest_harness.asm` v1.1: SHR_N(ISA非実在)→SHR A,B是正済。
  _main を呼び戻り値Aを16進4桁でUART出力しHALT。hasm23通過。
- **_fmul（Q8.8乗算）完成・検証済**:
  - アルゴリズム: 符号分離＋ビットごと可変シフト累算（Cプロト3でNG=0）。
  - ワーク: 案A範囲。WA=$DBF4, WB=$DBF6, WR=$DBF8（cc_mul領域）, WSIGN=$DBFA（cc_div先頭1B借用）。
  - emu23実機 **全8境界ケース完全一致**（正/負/端数/大値）。1.5*2.0=0x0300 等。
  - NEG命令がISA非実在のため **NOT+ADDI #1** で2の補数（符号反転）。
- **_fdiv（Q8.8除算）実装済・但しバグあり（上記0章）**:
  - アルゴリズム: 符号分離＋24ループ長除算（前半16=被除数MSB供給、後半8=0供給）。Cプロト3でNG=0。
  - ワーク: WN=$DBF4, WD=$DBF6, WQ=$DBF8（cc_mul領域）, WR=$DBFA, WSIGN=$DBFC（cc_div領域）。
  - 0除算: 商0返し。bit即WR反映でレジスタ逼迫回避（PUSH/POP A使用）。
  - hasm23通過・emu23実行可。**ただし引数逆転で数値全滅（要修正）**。

### 実装場所
- 全て `scc23_v2_00.c` の `emit_runtime()` 内、cc_mod ブロックの後。
  `if(g_use_fmul){...}` と `if(g_use_fdiv){...}` で各々オンデマンド出力。
- EQU未定義対策: float単独使用時（mul/div未使用）に _C_MUL_A/B/R, _C_DIV_A/B を
  各ブロック先頭で条件付き定義済み。

---

## 2. 検証環境（/home/claude/dhry_regress/）

- ツール: scc23_v200（最新・要再ビルド時は ../scc23_v2_00.c から）, scc23_v104（基準）,
  hasm23 v1.04, lnk23 v2.01, emu23 v1.07 — 全ビルド済。
- ハーネス: ftest_harness.asm（v1.1是正済）。obj名は `ftest_harness.asm.obj`（hasm23 -c の自動命名）。
- float単体テストの手動ビルド手順（重要・build_ftest.shはobj名がずれるので手動推奨）:
  ```
  cat > _t.c << 'EOF'
  int main(){ float a; float b; a=3.0; b=1.5; return a/b; }
  EOF
  ./scc23_v200 --code-org 0x0400 --data-org 0xE000 -o _t.asm _t.c
  ./hasm23 -c _t.asm                 # -> _t.asm.obj
  ./hasm23 -c ftest_harness.asm      # -> ftest_harness.asm.obj（初回のみ）
  ./lnk23 --machine force --entry _startup ftest_harness.asm.obj _t.asm.obj -o _t.bin
  timeout 10 ./emu23 _t.bin -q       # 先頭行に16進4桁が出る
  ```
- 配置: ハーネス$0000〜 / scc生成コード$0400〜 / ランタイム$D780(scc既定) / データ$E000〜。
  （データを$4000にするとランタイム$D780より前で .org backward エラーになる。$E000必須）

### Cプロトタイプ（アルゴリズム検証済・再利用可）
- /tmp は揮発。アルゴリズムは本文書§1とソースコメントに記載。
  - _fmul: プロト3 = 符号分離＋for i=0..15{ if(WB&1){ i>=8:WR+=WA<<(i-8); else WR+=WA>>(8-i)} WB>>=1 }
  - _fdiv: プロト3 = 符号分離＋for i=0..23{ bit=(i<16?WN_MSB:0); WR=(WR<<1)|bit; WQ<<=1; if(WR>=WD){WR-=WD;WQ|=1}; i<16ならWN<<=1 }

---

## 3. Step 7 残作業（_fdiv修正後）

1. **_fdiv引数逆転バグ修正＋emu23全境界再検証**（§0）
2. **混在式テスト**: `float r = (float)i / 2.0` 等、I2F/F2I と _fmul/_fdiv の組合せ動作確認。
3. **call前spill検証**: _fmul/_fdiv は cc_mul評価規約踏襲の無spill。ネスト式
   （例 `a*b + c*d`、`a/b/c`）で B/X 破壊が起きないか生成asm目視＋emu23で確認。
   問題あれば設計書§6.1のhas_call spillを実装。
4. **ワーク共用の衝突確認**: float式中にint乗除算が混在する式
   （例 `a_float * (i / j)`）で cc_mul/cc_div ワークと _fmul/_fdiv ワークが
   衝突しないか生成asm目視（案Aの前提検証）。
5. **設計書 v2.3 改版**: _fmul/_fdivの確定アルゴリズム・ワーク割当（cc_div領域の
   符号フラグ借用＝§2.5.2範囲内運用）を §6.4/§6.5 に履歴反映（KY41 append-only）。

## 4. Step 8（Step7完了後）
- **Dhrystone絶対ゲート回帰**: `-O0-strict` で 56416バイト byte-exact /
  826/48405/P:20 を確認。floatを使わないDhrystoneでは g_use_fmul/fdiv=0 で
  ランタイム未出力 → v1.04と完全一致のはず（既にStep5/6で-O0-strict asm一致は実証済）。
- 通常 -O0/-O1 でのfloat動作総合テスト。

---

## 5. 完了済み（Step 1〜6・前チャット）
- S1 型(T_FLOAT,sizeof=2) / S2 IR(SIR_FMUL/FDIV/I2F/F2I,g_use_*) /
  S3 floatリテラル(Q8.8,to_fixed) / S4 parse型昇格(binop_promote,wrap_i2f,キャストI2F/F2I) /
  S5 定数畳み込み(fold_binop) / S6 emit(I2F=LDW B,#8;SHL A,B / F2I=SAR / FMUL,FDIV=JSR)
- **-O0-strict拡張**: 定数畳み込み含む最適化を全OFF。Dhrystone asmがv1.04と完全一致（差分0）実証済。
- 設計書: v2.0→v2.1（v1.04ベース化是正・ISA2.3適合・リネーム見送り）→v2.2（-O0-strict拡張）。

## 6. 重要原則の再掲（本作業で効いたもの／反省）
- KY39: 命令はhasm23/ISAソースで実在確認してから使う。NEG非実在→NOT+1で代替したのは好例。
- アルゴリズムは **Cプロトで先行検証(NG=0)** してからアセンブリ化（_fmul/_fdiv両方で有効だった）。
- 「コンパイル通過≠正しい」: _fdivは通ったが数値全滅。**emu23数値検証必須**（本日KYの的中）。
- 反省: emit評価規約の非可換性（除算でA/B順序が効く）を _fmul(可換)で見落とし _fdiv で露見。
  → 次回 SIR_DIV(整数・正常) と SIR_FDIV の emit を必ず比較すること。

## 7. 既知の課題（別途・未対応）
- tool_version_ledger: codegen.c L563 "v1.4"バナー、codegen_v1_4.h命名不整合 等（scc23とは別件）。
- 表示混入問題（court等の不正文字列）: 本チャットで多発。機能影響なしだが品質問題。

## 8. 絶対ゲート（不変）
- YUI OSバイナリ 56416バイト byte-exact / Dhrystone 826/48405/P:20 /
  参照 yuios_ref_road2_I3.bin（MD5 a1f1001fe96d9c2e7b4db8e47d4046e4）
