# HANDOVER_CHAT75.md  (2026-07-08)
## FPGA V2-a 完了 → 次チャットへの引継ぎ

---

## 0. このチャットの結論(1行)
**V2-a(C1レジスタALU)検証 完了。CPU_V2A_TB: ALL PASS (20 vectors)。**
RTL(cpu v0.5.6)のC1 ALU 9命令が emu23 v1.09黄金と外部観測等価と確認。

---

## 1. 現在の工程位置
```
Step 8 FPGA実装
 └ V2 CPUコア単体検証
     ├ ✅ 設計メモ v0.1 承認(Q1〜Q6・前チャット)
     ├ ✅ V2-a: C1レジスタALU 検証完了 ← 本チャット完了 🎉
     │     CPU_V2A_TB: ALL PASS (20 vectors)
     └ ⬜ V2-b: C2即値ALU / C3比較 ← 次チャット最優先
        ⬜ V2-c: C4転送 / C5分岐
        ⬜ V2-d: C8スタック / C6C7C9既存TB整備
        ⬜ V2-e: 全カテゴリ回帰 + サイクル表素材
```

---

## 2. 本日の成果物(outputs/v2a_work/ に退避済)
- `gen_v2_vectors.py` v0.1 : C1ベクタ生成器。単一ソースでbin/hex生成し
   emu23を呼んで黄金期待値を自動取得(手計算排除=偽合格防止)
- `tb_cpu_v2a_v0_1.sv` v0.1 : 20ベクタ突合TB
- `v2a/` : ADD_pos.bin/.hex 〜 SAR_pos.bin/.hex (各20)、
   expected_v2a.hex(80word)、golden_v2a.txt、veclist_v2a.txt

### 検証済ベクタ(20)
ADD/SUB/AND/OR/XOR/NOT/SHL/SHR/SAR について
Z/N全パターン(Z0N0/Z1N0/Z0N1)を網羅。SAR符号拡張(0x8000→0xC000)、
SHR論理シフト(0x8000→0x4000)の差異も確認済。

---

## 3. 本日発見・確定した重要事項(★次チャットで必ず踏襲)

### 3.1 リセットベクタ規約(emu23/RTL共通・実照合済)
- emu23 L1910 §7.3 / RTL S_RESET_LO/HI(L565,821)とも
  `PC = rd16(0x0000)` でmem[0..1]をリセットベクタとして起動。
- **テストプログラムは mem[0]=lo,mem[1]=hi にベクタ、実コードは0x0100〜、末尾HALT。**
- 既存TB fetch(L58-65)と同じ作法。これを外すと空領域実行になる。

### 3.2 emu23 黄金取得の正しいコマンド(設計メモ§2.4の誤りを訂正)
- **誤**: `-q`付き → -qはトレース抑制(HALTまで無音実行)。トレース出ない。
- **正**: `./emu23 <bin> -n <N>` (■-q無し) → 各命令実行前トレース
  `PC=.. SP=.. F=.. A=.. B=.. X=..` を出力。HALTで`*** HALT at .. ***`。
- 最終状態 = 末尾HALT命令の実行前トレース行(=最後の実命令直後)。

### 3.3 FLAGS(ISA2_3_v231 L71実照合)
- bit0=Z, bit1=N, bit7=IE。突合は下位8bitで行う。

### 3.4 C1命令エンコード(ISA2_3_v231 L206-221実照合)
- 2B: `[op][rD<<4|rS]`  ADD40 SUB42 AND50 OR52 XOR54 NOT56 SHL57 SHR58 SAR59
- LDW#(初期値設定): `21 [rD<<4|0] lo hi` (4B, imm16 LE)
- HALT=01(1B)。 reg: A=0 B=1 X=2 SP=3。

### 3.5 SP初期値の食い違いと決着(選択肢1採用)
- RTL SP리셋=0x0000(regfile L92)、emu23=0xFC7E(L1909)。
- C1 ALUはSP不変(両実装実照合済)。よって**SPは突合対象外**。
  代わりに「実行後SP==0x0000不変」の保険チェックのみTBに実装。
- SP本格検証はC8スタックTBで行う(初期値の揃え方はそこで正面から扱う)。

---

## 4. デバッグ知見(kaizen.txt追記候補・未反映)
1. **Icarusメモリ全クリアのハング**: TBで`for(i<65536) mem[i]=0`を
   `always_comb mem_rdata=mem[mem_addr]`張り付き下で2巡目実行すると
   デルタ発散でハング(rc=124)。→ **使用域(0x0200)のみクリアで解消。**
   多ベクタをループで回すTBでは全域クリアしないこと。
2. vvp rc=124はタイムアウトでstdout消失(既知KY)。切り分けは
   本番TBを直接変えず(KY38)、NVEC縮小+段階DIAGで到達点を特定した。

---

## 5. 次チャットの冒頭手順(環境揮発のため毎回必要)
1. HANDOVER(本書)・ツール操作ガイド確認、工程確認(latest 4b67e76b)、KY1つ
2. Icarus導入: `apt-get install -y iverilog` (v12.0)
3. 作業DIR復元: /mnt/project から decoder/regfile/alu/cpu(v0.5.6)/tb一式/emu23_v109.c をコピー
   + outputs/v2a_work/ から gen_v2_vectors.py, tb_cpu_v2a, v2a/ を戻す
4. emu23ビルド: `gcc -O2 -o emu23 emu23_v109.c`
5. 8TB回帰でV1土台確認 → V2-a回帰(ALL PASS)確認 → V2-b着手

---

## 6. 次工程 V2-b の作業内容(C2即値ALU / C3比較)
- C2: ADDI/SUBI/ANDI/ORI/XORI (opcode 41/43/51/53/55, 4B: `op [rD<<4|0] lo hi`)
- C3: CMP/CMPI (44/45)。**CMPはFLAGSのみ更新しレジスタ不変**(要突合設計)。
  → 期待値: 対象レジスタが変化しないこと + FLAGS Z/Nが正しいこと。
- gen_v2_vectors.py を拡張(C2/C3のエンコーダとベクタ追加)。
  ★CMPのエンコードと「レジスタ不変」性はISA2_3_v231で必ず実照合(KY39)。
- 段階承認(V2-b)としてレビューを受けてから次段へ。

---

## 7. 未処理タスク(PDCA-Act・持ち越し)
- [ ] 設計メモ v0.1 → v1.1改版: §2.4(-q誤り訂正)、§4.3(リセットベクタ規約追記)。
      KY41: 追記のみ・取り消し線で旧情報保持・4点整合。
- [ ] kaizen.txt追記: 上記§4の2件(Icarusメモリ全クリアhang / 多ベクタTB作法)。
- [ ] 進捗報告(latest 4b67e76b)に 2026-07-08 分日報を記載。
- [ ] tool_version_ledger: 新規TB tb_cpu_v2a_v0_1 / gen_v2_vectors.py v0.1 を登録。

---

## 8. 停滞警告(継続監視)
- scc23 Phase 1〜6: 承認済・未着手(Step8優先の意図的後回し・別チャット)。
  FPGA V2完了までは保留で問題なし。
