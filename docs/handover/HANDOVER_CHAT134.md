# HANDOVER_CHAT134.md

## emu23 大規模改修作業（その4）引継文書

| 項目 | 内容 |
|---|---|
| **ファイル名** | `HANDOVER_CHAT134.md` |
| **Version** | v1.0 |
| **作成日** | 2026-08-12 |
| **対象チャット** | 「emu23大規模改修作業(その4)」（2026-08-10 〜 2026-08-12） |
| **前引継文書** | `HANDOVER_CHAT133.md` |
| **次チャット** | emu23 大規模改修作業（その5）を想定 |
| **引継理由** | ログ長大化のため（ツール呼び出し不安定化の予防） |

---

## 0. 三行サマリ

1. **Phase B'（B-1 TKT-03 ＋ B-C 改良2）が完全完了**し、**emu23 v1.12 を確定発番**した。
2. **B-C の完了条件 6 項目すべてクリア**（検証・台帳・手順書・マニュアル・設計書・kaizen 原則登録）。
3. 次工程は **B-2〜B-5（EMU-A/B/C ＋ 文書整理）**。その後 改良3（マシンサイクル）→ 改良4（キャッシュ）。

---

## 1. 本チャットの成果

### 1.1 B-1（TKT-03：`c_iflag` 未処理）— 完了

**症状**：YUI OS シェルでキー入力しても行が確定しない。

**原因**：`it_enable_raw_mode()` が `c_iflag` を触っておらず、termios 既定の **`ICRNL` が生き残って CR($0D)→LF($0A) 変換**されていた。YUI OS の `SH-READLINE`（`kernel_forth_v0_10_18.fs` L3148）は **`$0D` のみを行終端**とするため行が確定しなかった。

**★重要な判定★ 本件は実装漏れではなく「設計の欠落」**。設計書 v1.2 §3.1 のコード例自体が `c_iflag` を規定しておらず、実装は設計に忠実だった。

**修正**：`raw.c_iflag &= ~(IGNBRK|BRKINT|PARMRK|ISTRIP|INLCR|IGNCR|ICRNL|IXON|INPCK);`（`cfmakeraw(3)` の 8 フラグ＋`INPCK`）

**検証**：T03-N（改修前で症状再現）→ T03-1（`YUIOS V0.10.18` 応答到達）→ T03-2（`help`+LF で `?` 応答）→ T03-3/4/5（非回帰）全 PASS。**T03-6（実端末での `stty -a` 確認）のみ未実施のままクローズ**（ユーザー判断 2026-08-10）。

### 1.2 B-C（改良2：バス・プルアップ）— 完了

**5 段階に分割して実装**（各段で絶対ゲート 3 種を確認）。

| 段 | 内容 |
|---|---|
| B-C-1a-1 | MMIO アドレスデコード層 `mmio_classify()` を 4 経路（`rd8`/`rd16`/`wr8`/`wr16`）に新設。**完全な非機能変更** |
| B-C-1a-2 | **8bit 経路の被覆漏れ解消**（YSD8002 全8本・YSD8003 7本・YSD8004 2本＝計17本が `mem[]` に落ちていた）＋ 第4状態 `MMIO_MAPPED_UNSUPPORTED` |
| B-C-1a-3 | MMU レジスタ（`$FF00`-`$FF10`）の `--mmu` 非依存化（RTL 準拠） |
| B-C-1b | 未接続 MMIO の**プルアップ応答**（`$FF`/`$FFFF`）＋ 警告α ＋ `--strict-mmio`β |
| B-C-2 | **既定切替**（プルアップを既定に。`--no-bus-pullup` で切り戻し可） |

**★設計上の最重要論点★**：未接続読出値 `$FFFF` は YUI OS の **`IDX_NIL`（IPC キュー終端番兵・`kernel_v12_11.asm` L292）と一致**する。壊れたポインタが未接続領域を指すと、`$FFFF` が「キューは空」という**完全に正常な状態として受理され、例外も出ずタスクが静かに寝る**。症状が発生地点から遠く離れて現れる。この問題への対処として **α（警告ログ）＋β（`--strict-mmio` 即時停止）** を設計に組み込んだ。

### 1.3 emu23 v1.12 確定

| 項目 | 値 |
|---|---|
| ソース | **`emu23_v1_12.c`** |
| 起動表示 | `emu23 v1.12 (2026-08-11) for YSD8800 ISA2.3` |
| Dhrystone | **819 / 48,785 / P:20**（3 値一致） |
| `yuios_road2.bin` | **56,416 B / md5 `599a7f9d1ebf103f81f58450ea1b6491`** |
| 既定動作 | v1.11 と **stdout byte-exact 一致**・MMIO 警告 **0 件** |

### 1.4 新オプション（v1.12）

| オプション | 用途 |
|---|---|
| `--bus-pullup` | 既定で有効のため **no-op**（互換受理） |
| `--no-bus-pullup` | v1.11 挙動（`mem[]` フォールスルー）へ**切り戻し** |
| `--strict-mmio` | 未接続 MMIO アクセス検出時点で**停止**（`--bus-pullup` と独立） |

**出力タグ**：`[MMIO-UNMAPPED]`（未接続）／`[MMIO-UNSUP]`（幅未対応）／`[MMIO-SUMMARY]`（終了時・0件でも出力）。**すべて stderr。**

---

## 2. ★次チャットで最初に読むべき注意事項★

### 2.1 stdout / stderr の分離（回帰判定に直結）

**MMIO 警告とサマリは stderr に出る。** `-q` の byte-exact 比較は **stdout のみ**を対象とすること。

```bash
# 正
./emu23 yuios_road2.bin -q --disk disk.img > out.txt 2>/dev/null
diff out_expected.txt out.txt
# 誤（MMIOサマリが差分として現れる）
./emu23 yuios_road2.bin -q --disk disk.img > out.txt 2>&1
```

### 2.2 サマリは HALT 到達時のみ出る

`atexit` 出力のため **`timeout` 強制終了では出ない**。YUI OS は待機ループで HALT しないため**サマリを取得できない**。サマリ確認は Dhrystone 等で行う。

```bash
./emu23 dhry.asm.bin -q 2>&1 >/dev/null | grep MMIO
  → [MMIO-SUMMARY] unmapped=0 unsup=0
```

### 2.3 `size` 引数の意味（実装を触る場合）

`mmio_classify(addr, size)` の **`size` は「その CPU アクセスの幅」（1 or 2）**。分類対象バイトの幅ではない。**16bit アクセスでは上位／下位バイト双方の呼び出しに `size=2` を渡す。** これを誤ると `$FC86` UART_BAUD の正常な 16bit アクセスが `MMIO_MAPPED_UNSUPPORTED` に誤分類され `$00`＋警告を返す退行が起きる。

### 2.4 MMU レジスタはスロット規則の適用外

`$FF00`-`$FF0F` は **PTR[0]〜PTR[15]（16 個の独立した 8bit レジスタ）**。`$FF01` は PTR[0] の上位バイトではなく **PTR[1]**。16bit スロット規則を適用すると**奇数番 PTR 8 本が読めなくなり MMU が壊れる**（設計書 §2.3.4(6-ex)）。

---

## 3. 未了事項・申し送り

| # | 項目 | 内容 | 優先 |
|---|---|---|---|
| 1 | **T03-6 未実施** | 実端末での `stty -a` による termios 復帰確認。PTY 環境では代替不可。**未実施のままクローズと決定済**（設計書 v1.6 §5.1.4 に記録） | 低 |
| 2 | **BC-8M の検証限界** | `--mmu` 非依存化は**否定制御が構造的に成立しない**（改修前後で同一出力）。コード確認＋回帰一致で完了と判断済。**厳密には未実証**（設計書 v1.11 §11.3.1 に記録） | 低 |
| 3 | **RTL 未接続応答の乖離** | `ysd8800_mmio_stub_v0_7.sv` L458 `8'h00` → `8'hFF` 是正が必要。**軸A（キャッシュRTL工程）の冒頭タスクとして着手条件化済**（`fpga_source_version_ledger_v1_11.md` §18.5） | **中** |
| 4 | **D-3（Makefile 追従漏れ）** | `Makefile` の `KERN_SRC` が `kernel_v12_8.asm` のまま（現行は v12_11）。`REF_BIN` md5 も旧 I4 凍結品。**`make yuios`/`make verify` が現 golden を再現しない**。`make dhrystone`/`make regress` は影響なし | **中**（B-5 で対処） |
| 5 | **EMU-E** | `signal(SIGTERM, exit)` が async-signal-safe でない。実害は異常終了時のみ | 低（B-5） |
| 6 | 軸B scc23 Phase 1 C-1 | 行列テストスイート設計書 v0.2 が**レビュー待ちのまま停滞** | 要判断 |

---

## 4. 次工程（ロードマップ）

```
✅ Step 8-Sim（RTLシミュレーション・V8-b完了）
✅ emu23 Phase A（TKT-00〜04）
✅ emu23 Phase B'（B-1 TKT-03 ＋ B-C 改良2）← 本チャットで完了
🔧 emu23 Phase B''（次チャット）
   ├ B-2  EMU-A : 起動引数解析（-i等のオプションが.symと誤認される）
   ├ B-3  EMU-B : MAX_SYM=128 の拡張      ※B-2と対で意味を持つ
   ├ B-4  EMU-C : BP停止位置から c で再開できない
   └ B-5  文書整理（D-3 Makefile追従・EMU-E・.docx拡張子不一致の残り）
⬜ 改良3 マシンサイクル対応（-mc）
⬜ 改良4 キャッシュ導入          ※改良3に依存
⬜ 軸A キャッシュRTL開発          ※冒頭タスク＝RTL未接続応答の追随（申し送り3）
⬜ 軸B scc23 Phase 1 C-1〜
⬜ 軸C ISA3.0 / YSD8810
⬜ FPGA物理実装（Step 8-Impl・F1〜F8）
```

### 4.1 B-2／B-3 は必ず同一実装単位で

**B-2（引数解析）だけ直しても B-3（`MAX_SYM=128`）が残る限りラベル BP は使えない。** 実 PoC は 1,199 シンボルあり後半が読めない。分けると「直したのに使えない」中間状態が生まれ検証が空振りする。

### 4.2 B-2 の KY（先送り済み・次チャットで想起すること）

**★EMU-A の引数解析変更は既存スクリプトを silent に壊す★**
現行 emu23 は `argv[2]`/`argv[3]` を**無条件に** `.dbg`/`.sym` と解釈する。ここにオプション解析を割り込ませる改修は引数解釈の意味論そのものを変える。最悪なのは**落ちてくれない壊れ方**で、`.sym` が読めず `Loaded 0 label symbols` でも実行は継続するため、回帰スクリプトが「動いたように見えて BP が効いていない」状態を素通しする。

**防止策**：①着手前に既存の emu23 起動行を全数 grep（`*.sh`／`Makefile`／各設計書）②後方互換を設計要件として明文化（オプション無しの従来形は byte 単位で同一挙動）③`.sym` 読込結果を起動時に必ず表示 ④打切り発生時に警告を出す（黙って切り捨てない）。

---

## 5. ★プロジェクトナレッジ登録リスト（逼迫対応・優先度付き）★

**ナレッジ逼迫のため、必須のみに絞った推奨。**

### 5.1 【必須】登録しないと次工程が回らないもの

| # | ファイル | 理由 | 置換対象（削除可） |
|---|---|---|---|
| 1 | **`emu23_v1_12.c`** | **現行エミュレータ本体**。これが無いと全工程が止まる | `emu23_v111.c` |
| 2 | **`kaizen.txt`** | 原則119〜121 を追加（118→121）。毎セッション参照する | 旧 `kaizen.txt` |
| 3 | **`tool_version_ledger_v1_14.md`** | ツール版数の正本 | `tool_version_ledger_v1_13.md` |
| 4 | **`yuios_build_procedure_v1_13.md`** | ビルド手順の正本。**§4.7.2 に既定動作変更を記載** | `yuios_build_procedure_v1_12.docx` |
| 5 | **`HANDOVER_CHAT134.md`** | 本文書 | `HANDOVER_CHAT133.md` |

### 5.2 【強く推奨】次工程で参照する可能性が高いもの

| # | ファイル | 理由 | 置換対象 |
|---|---|---|---|
| 6 | **`emu23_debug_manual_v1_3.md`** | **B-2〜B-4 は emu23 デバッガの改修**。§2.4 の MMIO 誤アクセス検知は次工程で使う | `emu23_debug_manual_v1_2.docx` |
| 7 | **`fpga_source_version_ledger_v1_11.md`** | **軸A の着手条件（§18.5）が書かれている**。RTL 工程で必須 | `fpga_source_version_ledger_v1_10.md` |
| 8 | **`emu23_device_design_v1_12.md`** | B-C の設計正本。改良3/4（マシンサイクル・キャッシュ）で MMIO 層に再び触る | `emu23_device_design_v1_5.docx` |

### 5.3 【任意】余裕があれば

| # | ファイル | 理由 |
|---|---|---|
| 9 | `emu23_interactive_mode_design_v1_6.md` | B-1 の設計。**§2.5 の `SH-DISPATCH` 先頭文字分岐**は今後のテスト設計に効く（→ ただし `yuios_ph6_shell_design_v1_3.md` にも横展開済） |
| 10 | `yuios_ph6_shell_design_v1_3.md` | シェル設計。§9 項10 に「入力破損検証は完全一致グループを使う」を追加済 |
| 11 | `mmio_classify_test_poc.c` | 分類器の全数検算ハーネス。**改良3/4 で MMIO 層を触る際の回帰に使える** |

### 5.4 【登録不要】

- **中間版の設計書**（`emu23_device_design_v1_6`〜`v1_11`／`emu23_interactive_mode_design_v1_3`〜`v1_5`）… 最終版に全内容が取消線付きで保持されている
- **検証 PoC の大半**（`mmio8_test_poc.asm`／`mmio8_fx_poc.asm`／`mmio8_wfx_poc.asm`／`mmio_pullup_poc.asm`／`mmu_byte_poc.asm`／`cycle_latch_poc.asm`／`irqstat_w2c_poc.asm`／`pty_test_poc.py`）… **検証は完了済みで再実行の予定なし**。手順は設計書 §11.3 に記録されており再作成可能
- `emu23_v112_poc.c`（`emu23_v1_12.c` と同内容の作業版）
- `yuios_road2.bin` / `.sym`（`build_road2.sh` で再生成可能）

> **★削除推奨★** 上記「置換対象」列のファイルは新版登録後に削除してよい。特に **`.docx` 拡張子のもの3件**（`yuios_build_procedure_v1_12.docx`／`emu23_debug_manual_v1_2.docx`／`emu23_device_design_v1_5.docx`）は実体がプレーンテキストであり、本チャットで `.md` へ是正済み。

---

## 6. 本チャットで得られた教訓（kaizen 登録済）

| 原則 | 内容 | 由来 |
|---|---|---|
| **119** | 照合値は当該作業内で一次情報を確認してから根拠に使う | レビュー側が旧 md5 `9769f…` を根拠に指摘 → 実測で反証・撤回 |
| **120** | 一般規則を新設したら既存実装済オブジェクト全数に当てはめて検算する | 16bit スロット規則が MMU のバイト粒度と矛盾（M-10・実装前に検出） |
| **121** | 新設節は既存節の末尾に追加し既存の節番号を動かさない | M-1／M-12／F-1 と**3回連続**で参照崩れ |

### 6.1 原則化していないが有効だった手法

- **ネガティブコントロール先行**（KY54）：本チャットの全検証で「改修前に症状を再現してから改修版を測る」を徹底した。T03-N・BC-N・BC-8N・BC-8WN。**BC-8M ではこれが構造的に成立せず、それ自体が検証限界の発見につながった**
- **段階分離**：B-C を 5 段に割り、各段で絶対ゲートを取った。1a-1 を「完全な非機能変更」に保ったことで、以降の差分の由来を常に特定できた
- **分類器の全数検算**：設計書の机上計算（896＝63＋833）と実装を独立に突合。65,536 アドレス × 2 幅で不一致 0 件

---

## 7. セッション開始時の手順（次チャット向け）

1. 本文書（`HANDOVER_CHAT134.md`）を読む
2. `claude_tool_operation_guide_v1_0.txt` を参照し規律1〜5 を確認
3. 「進捗と予定の確認(latest)」チャットで最新ロードマップを照合 → **工程ヨシ!**
4. KY 活動を 1 件挙げる（**B-2 着手なら §4.2 の EMU-A 後方互換 KY を使うこと**）
5. 「ご安全に！」の合図を待って作業開始

### 7.1 環境再構築コマンド（作業領域が消えている場合）

> **★前提★** `emu23_v1_12.c` が**プロジェクトナレッジに登録済み**であること（§5.1 の必須項目1）。未登録の場合は本チャットの出力からアップロードするか、`emu23_v111.c` に本文書 §1.2 の改修を再適用する必要がある。**他のファイルは 2026-08-12 時点ですべて登録済みを確認済み。**

```bash
mkdir -p /home/claude/work && cd /home/claude/work
cp /mnt/project/{emu23_v1_12.c,hasm23_v1_04.c,lnk23_v2_01.c,scc23_v2_05.c} .
cp /mnt/project/{force_v1_5.c,ysd8800.prim,Makefile,dhry_timer.c,startup_harness23_v17.asm} .
cp /mnt/project/{build_road2.sh,kernel_forth_v0_10_18.fs,kernel_v12_11.asm,mkfs_yuifs_v1_1.py} .
cp /mnt/project/ysd8800_kern_v0_6.tgt ysd8800_kern.tgt
mkdir -p frontend backend
cp /mnt/project/{ir.c,ir.h,lexer.c,lexer.h,parser.c,parser.h} frontend/
cp /mnt/project/codegen_v1_5.c backend/codegen.c
cp /mnt/project/codegen_v1_4.h backend/codegen.h
gcc -O2 -o emu23 emu23_v1_12.c
gcc -O2 -o hasm23 hasm23_v1_04.c
gcc -O2 -o lnk23 lnk23_v2_01.c
gcc -O2 -o scc23 scc23_v2_05.c
gcc -O2 -o force force_v1_5.c frontend/*.c backend/codegen.c -Ifrontend -Ibackend
```

### 7.2 絶対ゲート（改修前に必ず取ること）

```bash
# Dhrystone: 819 / 48785 / P:20
make dhrystone && make regress

# yuios_road2.bin: 56416 B / md5 599a7f9d1ebf103f81f58450ea1b6491
bash build_road2.sh && md5sum yuios_road2.bin
```

---

以上 / HANDOVER_CHAT134.md v1.0 / 2026-08-12
