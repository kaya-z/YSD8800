# V8-b 本番 TB 設計書  v0.1

- 発行日 : 2026-07-31
- 発行者 : Claude (YSD8800 FPGA 実装担当)
- 対象   : `tb_cpu_v8b_prod_v0_1.sv`（V8-b 本番用テストベンチ）
- 前提資料 :
  - HANDOVER_CHAT125.md（V8-b Pre 完了・本番着手引継）
  - v5_design_memo_v0_5.md（V5 TCR-ACK ACK 型仕様）
  - v6a_integration_design_memo_v0_3.md（YSD8003 統合・SD 経路）
  - yuios_ph3_storage_design_v1_2.md（ストレージ経路設計）
- 状態   : **【レビュー未実施】** レビュー承認後に TB 実装（SV）に着手

---

## §1 目的

`yuios_road2.bin`（56,416B, MD5 = `7a6a5b87afb1ef9f413a7d0c1360e706`, kernel v12.8 + Forth v0.10.18 + YUI OS 全常駐タスク）を、iverilog 上に統合された **YSD8800 CPU + MMIO + PSRAM + YSD8001/8002/8003/8004 + SD SPI モデル** の実 RTL 環境で実行し、以下の到達を実証する：

```
起動シーケンス期待出力(UART TX):
    "YUIOS Booted!\n" ← BOOT-MSG (Forth kernel_forth_v0_10_18.fs:3432)
    "0YUI> "          ← SHELL-START プロンプト
    "123MD"           ← Shell 内蔵マーカー (M-5 判定文字列)
```

**PASS 判定**：UART 収集ログに `123MD` 文字列を検出。
**FAIL 判定**：`MAX_CYCLES` 到達、または明示エラー（$fatal 相当）検出。

---

## §2 前提条件（Pre 完了・環境確認完了）

CHAT124/CHAT125 で以下は完了済み：

| 前提 | 状態 | 根拠 |
|---|---|---|
| yuios_road2.bin 生成手順の凍結 (Makefile v1.2 / kernel v12.8 / scc23 v2.04) | ✅ | Pre-3〜Pre-6 完了 |
| 期待バイナリ 56,416B / MD5 `7a6a5b87...` | ✅ | Pre-6 verify PASS |
| ツール 5 種の版数固定 (force v1.5 / hasm23 v1.04 / lnk23 v2.01 / scc23 v2.04 / emu23 v1.11) | ✅ | 本チャット §6.1 バナー照合 |
| iverilog 12.0 動作環境 | ✅ | 本チャット §6.2 |
| RTL 15 コンポーネント集約 (top-level v0.2 / CPU core v0.5.8) | ✅ | 本チャット §6.3 |
| SD image (sd_image.hex, 24,576B, YUIFS マジック確認) | ✅ | V8-a 実績流用 |

---

## §3 TB 全体構造

### §3.1 top-level 接続

- **DUT** : `ysd8800_v5_membus_v0_2`（top-level v0.2）
- **クロック**  : 100 MHz (CPU) / 25 MHz (SPI) を DUT 内 CDC bridge が調停
- **リセット**  : `rst_n` を初回 20 cycle Low → High
- **UART TX**   : DUT 出力 `uart_txd` を TB で 1 文字ずつ受信、`uart_out.log` にストリーム書き出し + 内部リングバッファ蓄積（判定用）
- **UART RX**   : 本番では未使用（TB 側 idle High 固定）。CPU 内 Shell は入力なしでも "123MD" マーカーを起動時に出力する経路が存在（要確認・§10 未確定事項 UC-1）
- **SD SPI**    : `sd_spi_model_v0_3_poc` を DUT 外部でインスタンス化、SD_MISO/MOSI/SCK/CS を接続。image は `sd_image.hex` を `$readmemh` で 24,576 Bytes 供給。

### §3.2 PSRAM 初期化（ゴールデン等価性 CL-1）

- **供給元** : `yuios_road2.bin` を `bin2hex.py` で HEX 変換したもの（1 バイト/行）
- **配置**   : PSRAM モデル `mem[]` の物理アドレス `0x00000` から 56,416 Bytes 全域を `$readmemh` で書込
- **論理アドレス写像** :
  - lnk23 出力の kernel セクション → 物理 `$0000` 起点 (5,238B)
  - lnk23 出力の Forth セクション → 物理 `$5100` 起点 (35,680B)
  - 合計 56,416B が MMU 論理→物理の恒等写像で覆われる（現時点 kernel v12.8 は MMU 恒等使用）
- **チェックリスト CL-1** :
  1. `$readmemh` 対象行数が 56,416 と一致するか（TB 初期化直後に $display で表示）
  2. 先頭 4 バイト = kernel 先頭ベクタ（実測値を Pre で確認、TB 起動時 assert）
  3. 物理 `$5100` の 4 バイト = Forth 先頭（同上）

### §3.3 SD image 供給（ゴールデン等価性 CL-2）

- **モデル**  : `sd_spi_model_v0_3_poc.sv`（V8-a で実戦投入済）
- **image**   : `sd_image.hex`（24,576B = 48 セクタ, YUIFS マジック "YUIFS" 先頭）
- **役割**    : kernel_forth_v0_10_18.fs の `STOR-START` / `FILEMGR-START` が YUIFS 認識に成功する必要がある（BOOT-MSG より前の起動シーケンス）
- **チェックリスト CL-2** :
  1. `sd_image.hex` の先頭 5 バイトが ASCII "YUIFS" (0x59,0x55,0x49,0x46,0x53)
  2. モデルが初期化時に image 全域を読み込めていること（$display で行数表示）

### §3.4 UART 収集

- **TX ラインの監視** : DUT の `uart_txd` を start bit 立ち下がりで検出 → 9600bps × 実測 baud 分周比で 8 ビット受信（YSD8001 UART design v1.2 準拠）
- **蓄積**            : `uart_bytes[]` にバイト列で保存、同時に `$fwrite(fd, "%c", byte)` で `uart_out.log` に即時書き出し
- **マイルストーン検出** : 蓄積バッファに対して `"YUIOS Booted!"`, `"0YUI> "`, `"123MD"` の各文字列包含を判定（部分マッチで足りる）

---

## §4 観測マイルストーン方式（M-1 〜 M-5）

**KY 防止策 1** に基づき、以下 5 マイルストーンを TB に**先に実装**する。各 M で「到達時 cycle 数の想定」「未到達時のタイムアウト cycle 数」「通過時の 1 行 $display」を事前に明記する。

| M | 名称 | 判定条件 | 想定到達 cycle | phase-1 打切 | 通過時 $display |
|---|---|---|---|---|---|
| M-1 | リセット解除・PC 到達 | CPU の `pc` レジスタが `$5100`（Forth OS-START エントリ）に到達 | 〜100 cycle | 10,000 | `[M-1] PC reached $5100 @cycle=%d` |
| M-2 | 最初の UART TX | uart_bytes[] に最初の 1 バイトが記録 | 〜10 万 cycle | 200,000 | `[M-2] First UART TX byte=$%02x @cycle=%d` |
| M-3 | "YUIOS Booted!" 到達 | uart_bytes[] に `Y U I O S 20 B o o t e d 21` 包含 | 〜数百万 cycle | 5,000,000 | `[M-3] "YUIOS Booted!" detected @cycle=%d` |
| M-4 | "0YUI> " プロンプト | uart_bytes[] に `30 59 55 49 3E 20` 包含 | M-3 + 数十万 cycle | 8,000,000 | `[M-4] "0YUI> " prompt detected @cycle=%d` |
| M-5 | "123MD" マーカー | uart_bytes[] に `31 32 33 4D 44` 包含 | M-4 + 数百万 cycle | phase-3 で判定 | `[M-5] "123MD" detected @cycle=%d ==> PASS` |

**未到達時**: 該当 M の phase 打切り cycle に到達したら `[M-X TIMEOUT] not reached @cycle=%d` を出力し、次 phase に進む前に人手判断を仰ぐ（本 TB では `$finish` を呼ぶ）。

**注意（KY 防止策 3・段階起動との連動）**:
- phase-1 は M-1/M-2 まで確認できれば OK。M-3 に届かなくても即失敗判定はしない（想定 cycle が phase-1 予算を超えるため）。
- phase-2 で M-3/M-4 到達を狙う。
- phase-3 で M-5 到達を狙う（本番判定）。

---

## §5 段階起動プラン（KY 防止策 3）

いきなり大きい `MAX_CYCLES` を回すと、iverilog 完走が遅く、途中経過も観測しにくい。以下 3 段階で拡大する。

### §5.1 phase-1（快速 sanity）

- `MAX_CYCLES = 1,000,000`（100 万）
- **狙い** : M-1 通過 + M-2 通過（UART TX が発生し始めるところまで）
- **失敗時** : M-1 未到達なら **PSRAM 初期化 or リセット経路の異常**（原則 88）。M-2 未到達なら **UART クロック分周比 or MMIO 経路の異常**。
- **想定時間** : iverilog 5〜30 秒

### §5.2 phase-2（起動完走確認）

- `MAX_CYCLES = 10,000,000`（1000 万）
- **狙い** : M-3 通過（"YUIOS Booted!"）+ M-4 通過（"0YUI> " プロンプト）
- **失敗時** : M-3 未到達なら **常駐タスク起動シーケンスの停止**（STOR-START / FILEMGR-START が SD 認識に失敗している可能性大 → CL-2 再チェック）。
- **想定時間** : iverilog 1〜5 分

### §5.3 phase-3（本番判定）

- `MAX_CYCLES = 100,000,000`（1 億）
- **狙い** : M-5 通過（"123MD" マーカー）→ **PASS 宣言**
- **想定時間** : iverilog 10〜30 分（要スペック確認）

**注意** : phase 間で `MAX_CYCLES` パラメータを差し替えるだけで TB 本体は同一を保つ（原則 82・観測整合）。

---

## §6 判定基準

### §6.1 PASS

以下すべて成立で **PASS**：
1. M-5 到達（TB 内 `$display("... ==> PASS")`）
2. `uart_out.log` に対する `grep -aoE '123MD' uart_out.log` が非空
3. TB が正常に `$finish` を呼び、iverilog 終了コード 0

### §6.2 FAIL

以下のいずれか成立で **FAIL**：
1. `MAX_CYCLES` 到達（M-5 未検出のまま）
2. `$fatal` / `$error` 発火
3. 途中で UART TX が長時間停止（連続 500,000 cycle 出力なし → デッドロック疑い）

### §6.3 部分 PASS（本番の前段確認）

phase-1 / phase-2 でここまで到達したという中間結果として：
- **P1-OK** : M-1 と M-2 到達（quick sanity）
- **P2-OK** : M-3 と M-4 到達（起動完走・Shell 立ち上げ）
- **P3-OK** : M-5 到達（**本番 PASS**）

---

## §7 ゴールデン等価性チェックリスト（原則 94 / KY 防止策 2）

TB v0.1 で **必ず** 適用する 3 項目。各項目は TB 起動直後の `initial` ブロックで実行し、失敗時は `$fatal` で即停止する。

| CL | 項目 | 検査内容 | 失敗時の推定 |
|---|---|---|---|
| **CL-1** | PSRAM 初期化範囲 | `$readmemh` 完了後、`mem[]` の非デフォルト要素数を数えて 56,416 と一致 | HEX 変換の欠落 / lnk23 出力異常 |
| **CL-2** | SD image | sd_spi_model 内 `sd_mem[]` の先頭 5 バイト = "YUIFS" | image 供給パス誤り |
| **CL-3** | CPU 初期状態 | リセット直後 (cycle=1): `pc == $5100`, `sp == $E000`（kernel_v12.8 対応スタック位置、要確認・§10 UC-2） | CPU コアのリセット挙動異常 |

**V8-D の PSRAM 1KB 事故を反復させない**（原則 94 の再登板）。CL-1 は特に重要。

---

## §8 SD image 準備方針

- **採用** : `sd_image.hex`（V8-a 用・24,576B・YUIFS マジック確認済）を**そのまま流用**する
- **理由** :
  1. V8-a 実 SPI 経路で kernel v12.8 + 同 image の組合せが動作実績あり（HANDOVER §2.3）
  2. 起動シーケンス（STOR-START/FILEMGR-START）に必要な YUIFS 認識までカバー
  3. M-5 判定文字列 "123MD" は Shell 内蔵マーカーで SD 参照不要（Forth SH-CMD-VER 系）
- **配置** : TB と同一ディレクトリに `sd_image.hex` を置く。`sd_spi_model_v0_3_poc` の `$readmemh` 対象。
- **新規生成不要** : mkfs_yuifs 再実行はしない（バイト等価性を維持するため）

---

## §9 UART 出力の永続化方針

- **手法** : TB 内 `integer fd = $fopen("uart_out.log", "w");` → UART TX 1 バイト受信ごとに `$fwrite(fd, "%c", byte);` → シミュ終了時 `$fclose(fd);`
- **理由** :
  1. iverilog を長時間走らせる際、`$display` の標準出力だけだと途中のログ量が制御しにくい
  2. `grep -aoE '123MD'` による判定を独立プロセスで実行可能
  3. **KY 防止策の間接効果** : 標準出力を切り離すことで規律 5（ログ肥大化）を抑止
- **同時にターミナル出力** : マイルストーン到達 $display は標準出力にも残す（UART 生ログは `uart_out.log` のみ）

---

## §10 未確定事項・確認事項

以下 3 点、レビューで判定願います：

- **UC-1** : Shell の "123MD" マーカー出力は、UART RX 入力なしで発生するか？
  - Forth 側 `SH-CMD-VER` の起動時自動発火の有無を kernel_forth の該当箇所で最終確認したい
  - もし RX 入力が必要な場合、TB から `1 2 3 \r` などの入力刺激をスクリプト化する必要あり
  - **暫定案** : phase-1 で M-2 通過確認後、UART TX の実出力を目視し、Shell が自発的に "123MD" を吐くか観察 → 吐かなければ phase-2 開始前に RX 刺激を追加

- **UC-2** : CL-3 の SP 初期値 `$E000` は kernel v12.8 の実配置と一致するか
  - kernel_v12_8.asm の SP 設定コードを最終確認する必要あり（現時点でスタック領域は $E000〜$EFFF 想定だが実測未確認）

- **UC-3** : phase-1 の M-1 タイムアウト値 10,000 cycle は妥当か
  - CPU リセット → PC=$5100 への到達は数十 cycle のはず（原則 88 実データ経路で確認済）
  - 10,000 は余裕を持たせすぎかもしれないが、初回は保守的に設定

---

## §11 版数・付記

- v0.1 (2026-07-31) : 初版起票。レビュー未実施。
- 想定 TB 実装ファイル名 : `tb_cpu_v8b_prod_v0_1.sv`（レビュー承認後に着手）
- 想定生成物 : `uart_out.log`, iverilog 実行ログ, PASS/FAIL 判定
- 関連原則 : 82, 83, 86, 87, 88, 93, 94, 95, 96, 97（kaizen.txt）

**レビュー観点（推奨）**：
1. M-1〜M-5 の cycle 想定値の妥当性
2. UC-1〜UC-3 の判断
3. 段階起動 phase-1/2/3 の予算配分
4. CL-1〜CL-3 で漏れがないか（特に CPU 初期状態）
5. PASS/FAIL 判定基準の網羅性
