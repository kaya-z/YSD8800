# V8-b 本番 TB 設計書  v0.3

- 発行日 : 2026-08-01
- 発行者 : Claude (YSD8800 FPGA 実装担当)
- 対象   : `tb_cpu_v8b_prod_v0_1.sv`（V8-b 本番用テストベンチ、v0.3 承認後に着手）
- 版数   : **v0.3**（v0.2 条件付き承認対応・§3.1 コード例ミクロ実源照合修正）
- 前提資料 :
  - HANDOVER_CHAT125.md（V8-b Pre 完了・本番着手引継）
  - v8b_prod_design_memo_v0_1_review_v1_0.md（v0.1 → v0.2 改版契機）
  - **v8b_prod_design_memo_v0_2_review_v1_0.md（本改版の直接契機・条件付き承認）**
  - kernel_v12_8_migration_design_v1_3.md §10.5（V8-b への申し送り）
  - tb_cpu_v8catls_poc.sv（V8-a 実装参考実源・§3.1 は本 SV に厳密整合）
- 状態   : **【レビュー未実施・再レビュー依頼中】**

---

## §0 改版履歴と差分サマリ

### §0.0 v0.2 → v0.3 差分（本改版）

v0.2 レビュー（v8b_prod_design_memo_v0_2_review_v1_0.md）で **条件付き承認** とされ、**必修正 3 件（実装ブロッカー・iverilog 即エラー要因）+ 補足 2 件** が提示された。v0.3 では全 5 件を反映：

| # | 区分 | 反映箇所 | 内容 |
|---|---|---|---|
| 1 | 必修正 | §3.1 SD SPI モデル | `.clk(psram_clk)` 削除。V8-a L131-136 と同形（cs_n/sck/mosi/miso のみ）に修正 |
| 2 | 必修正 | §3.1 disk_sectors_i | `16'd16` → `32'd16` に修正（実源は 32bit 幅） |
| 3 | 必修正 | §3.1 irq_in 生成 | assign 文をコード例に明示追加 |
| 4 | 補足 | §7 CL-3 | 「リセット直後」→ 「リセットベクタ読出完了後」に修正 |
| 5 | 補足 | §4 失敗マーカー表 | 'v' に「UART RX なし前提で有効」の注記追加 |

さらに v0.2 レビュー §11 の教訓「**SV コード例のミクロレベル実源照合**」を §12 に運用ルール化して追加。

### §0.1 v0.1 → v0.2 差分（前改版・保存）

v0.1 に対するレビュー（v8b_prod_design_memo_v0_1_review_v1_0.md）で **必修正 5 件・補足 3 件** が提示された。v0.2 では全 8 件を反映し、さらに実源照合の副産物として **5 件の改善**を追加。v0.1 の情報は欠落させず、誤記部分は「v0.1 誤記→v0.2 訂正」として保持する（原則：設計文書改版時は前の版の情報を欠落させない）。

### §0.2 v0.1 → v0.2 レビュー指摘への対応対照表

| # | レビュー指摘 | v0.1 誤記 | v0.2 訂正 | 実源根拠 |
|---|---|---|---|---|
| 1 | §3.1 DUT 構造の不完全 | `ysd8800_v5_membus_v0_2` のみ | **CPU コア + membus 別インスタンス**（module 名 `ysd8800_v5_membus_v0_1`） | tb_cpu_v8catls_poc.sv L89/L103 |
| 2 | §3.2 Forth 物理アドレス `$5100` は根拠なし | `$5100` 起点 | **削除・実測値 `$D295`（WORD_OS_START、sym 実測）** | yuios_road2.sym（本チャット実測） |
| 3 | §4 M-1 到達 PC `$5100` 誤り | `$5100` | **`_kstart` = `$0E00`** | kernel_v12_8.asm L1330 `.org $0E00`、sym `0e00 _kstart` |
| 4 | §7 CL-3 SP 初期値 `$E000` 誤り | `$E000` | **`$477E`（KERN_SP_TOP）** | kernel_v12_8.asm L1332 `LDW SP, #$477E` |
| 5 | §1・§8 "123MD" Shell マーカー説誤り | Shell 内蔵マーカー・SD 参照不要 | **FILEMGR タスク YUIFS 起動マーカー・SD 参照必須**、期待出力は実は "0123MD"（'0' プレフィックス）、失敗マーカー 'i'/'g'/'v' あり | kernel_forth_v0_10_18.fs L2785-2810/L2829 |
| 6 | sd_image.hex サイズ乖離 | 24,576B = 48 セクタ | **8,192B = 16 セクタ**（V8-a 実績と同一。24,576 はファイルサイズ、実データは 8,192） | `wc -l /mnt/project/sd_image.hex` = 8192 行 × 1 バイト |
| 7 | UC-1 SH-CMD-VER 系再構成 | SH-CMD-VER 自動発火 | **削除・YUIFS 起動シーケンス経由に差替** | 同 5 |
| 8 | CL-1 判定方式現実性 | 「非デフォルト要素数」 | **全域 0 クリア + `$readmemh` 行数 == 56,416**（V8-a L287-289 手法踏襲） | tb_cpu_v8catls_poc.sv L287-289 |

### §0.3 v0.2 実源照合の副産物（追加改善 5 件・保存）

| 追 | 発見 | v0.2 での反映 |
|---|---|---|
| A1 | UART TX は `uart_tx_valid_o` パルス + `uart_tx_data_o` バイトで **パラレル出力**（9600bps サンプリング不要） | §3.4 UART 収集を大幅簡略化 |
| A2 | CPU コアに **dbg_pc/dbg_sp/dbg_a/dbg_b/dbg_halt** 露出 | §4 M-1・§7 CL-3 判定に直接利用（波形観測不要） |
| A3 | 失敗マーカー '0' → 'i' / '1' → 'g' / '2' → 'v' の**早期 FAIL パターン**が実源に定義済 | §6.2 FAIL 判定に追加（原則 87 弁別性） |
| A4 | kernel_v12_8.asm L1475 コメント `WORD_OS_START = $e988` は v0.12.0 時点の値、**sym 実測は $D295** | ソースコメント信用禁止・sym 実測値を絶対とする（原則 76） |
| A5 | V8-a TB の PSRAM 初期化は **先頭 1KB のみ** 0 クリア（`for (i=0; i<16'h0400)`）→ V8-D の PSRAM 1KB 事故の直接的な源 | V8-b は **56,416B 全域**を明示的に 0 クリア |

---

## §1 目的

`yuios_road2.bin`（56,416B, MD5 = `7a6a5b87afb1ef9f413a7d0c1360e706`, kernel v12.8 + Forth v0.10.18 + YUI OS 全常駐タスク）を、iverilog 上に統合された **YSD8800 CPU コア（v0.5.8）+ membus（v5, ファイル v0.2/module `_v0_1`）+ PSRAM + YSD8001/8002/8003/8004 + SD SPI モデル（v0.3 poc）** の実 RTL 環境で実行し、以下の到達を実証する：

```
起動シーケンス期待出力(UART TX):
    "YUIOS Booted!\n"   ← BOOT-MSG (Forth kernel_forth_v0_10_18.fs L3432)
    "0YUI> "            ← SHELL-START プロンプト
    "0123MD"            ← FILEMGR タスクの YUIFS 起動進捗マーカー
                          '0' : SB-LOAD 開始         (kernel_forth L2785)
                          '1' : SB-LOAD 成功         (L2792)
                          '2' : MAGIC 一致           (L2797)
                          '3' : ver_major OK          (L2805)
                          'M' : FS-MOUNTED=1 完了    (L2810)
                          'D' : DIR-LOAD 完了         (L2829)
```

**PASS 判定（M-5）**：UART 収集ログに **`0123MD`（6 バイト連続）**を検出。

**FAIL 判定**：以下のいずれか：
- `MAX_CYCLES` 到達
- **失敗マーカー `i` / `g` / `v` 検出**（YUIFS 起動失敗の即時判別・原則 87）
- 連続 500,000 cycle UART 出力なし（デッドロック疑い）

**v0.1 誤記**：「"123MD" は Shell 内蔵マーカー・SD 参照不要（SH-CMD-VER 系）」→ **誤り**。実源照合により **FILEMGR タスクの YUIFS 起動マーカーであり SD 参照必須**と確定。SH-CMD-VER は "YUIOS V0.10.18" を出力する別マーカー（L3265-3271）で、M-5 とは無関係。

---

## §2 前提条件（Pre 完了・環境確認完了）

| 前提 | 状態 | 根拠 |
|---|---|---|
| yuios_road2.bin 生成手順の凍結 | ✅ | Pre-3〜Pre-6 完了（CHAT124） |
| 期待バイナリ 56,416B / MD5 `7a6a5b87afb1ef9f413a7d0c1360e706` | ✅ | 本チャット §6.1 で make yuios 実行・再現確認済 |
| ツール 5 種の版数固定 | ✅ | 本チャット §6.1 バナー照合完了 |
| iverilog 12.0 動作環境 | ✅ | 本チャット §6.2 |
| RTL 15 コンポーネント集約 | ✅ | 本チャット §6.3（top-level ファイル v0.2 / module `_v0_1` / CPU core v0.5.8） |
| SD image (sd_image.hex, 8,192B = 16 セクタ, YUIFS マジック確認) | ✅ | 本チャット・V8-a 実績流用 |
| 実源照合 6 項目（A/B/C/D/E/F） | ✅ | 本チャット完了 |

---

## §3 TB 全体構造

### §3.1 DUT インスタンス構造【v0.1 全面改訂】

**v0.1 誤記**：「DUT: `ysd8800_v5_membus_v0_2`」（単一 module として記述、CPU コア別途を欠落）
**v0.2 訂正**：**CPU コアと membus は別々にインスタンス化する**（V8-a TB 参考実源準拠）。

```systemverilog
// tb_cpu_v8b_prod_v0_1.sv (v0.3 承認後に実装)

// --- 内部信号（IRQ 結合）v0.3 明示追加（v0.2 レビュー指摘3） ---
logic [2:0] irq_in;
assign irq_in = irq_timer_o ? 3'd1 : (irq1_o ? 3'd2 : 3'd0);

// --- DUT 1: CPU コア (無改修) ---
ysd8800_cpu_v0_1 dut_cpu (
    .clk(cpu_clk), .rst_n(cpu_rst_n),
    .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata),
    .mem_rd(mem_rd), .mem_wr(mem_wr), .mem_ready(mem_ready),
    .irq_in(irq_in),
    .dbg_pc(dbg_pc), .dbg_sp(dbg_sp), .dbg_halt(dbg_halt),
    // (v0.2 追加) M-1/CL-3 判定に dbg_pc/dbg_sp を直接使用
    .irq0_ack(irq0_ack)
);

// --- DUT 2: v5 membus (ファイル v0.2 / module 宣言名は _v0_1) ---
ysd8800_v5_membus_v0_1 #(.PHYS_AW(20), .MEM_AW(20)) u_membus (
    .cpu_clk(cpu_clk), .cpu_rst_n(cpu_rst_n),
    .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata),
    .mem_rd(mem_rd), .mem_wr(mem_wr), .mem_ready(mem_ready),
    .psram_clk(psram_clk), .psram_rst_n(psram_rst_n),
    .irq1_o(irq1_o), .irq_timer_o(irq_timer_o), .irq0_ack(irq0_ack),
    .spi_cs_n_o(spi_cs_n_o), .spi_sck_o(spi_sck_o),
    .spi_mosi_o(spi_mosi_o), .spi_miso_i(spi_miso_i),
    .uart_tx_valid_o(uart_tx_valid_o), .uart_tx_data_o(uart_tx_data_o),
    .uart_rx_valid_i(1'b0), .uart_rx_data_i(8'h00),
    // (RX は本番 idle。UC-1 の判断により差替可能性あり)
    .disk_sectors_i(32'd16)   // v0.3 訂正: 32bit 幅（実源 L197 は input logic [31:0]）
);

// --- 補助 1: SD SPI モデル (v0.3 訂正: clk ポート削除・V8-a L131-136 と同形) ---
sd_spi_model_v0_3_poc u_sd (
    .cs_n (spi_cs_n_o),
    .sck  (spi_sck_o),
    .mosi (spi_mosi_o),
    .miso (spi_miso_i)
);
```

- **module 宣言名注意**：ファイル `ysd8800_v5_membus_v0_2.sv` の module 宣言は **`ysd8800_v5_membus_v0_1`**（v0.2 では宣言名を変更していない）
- **IRQ 結合**：`irq_in` の assign 文を明示（v0.3 訂正・レビュー指摘 3）。V8-a L84 と完全同一。
- **disk_sectors_i**：実源 ysd8800_v5_membus_v0_2.sv L197 は `input logic [31:0]`。V8-a L278 でも `32'd131072` と 32bit 幅。**v0.2 の `16'd16` は幅ミスマッチ**（v0.3 訂正・レビュー指摘 2）。
- **SD SPI モデル**：実源 sd_spi_model_v0_3_poc.sv L41-45 のポートは `cs_n / sck / mosi / miso` の 4 本のみ。**v0.2 の `.clk(psram_clk)` は iverilog コンパイル時に「port `clk` not found」で即エラー**（v0.3 訂正・レビュー指摘 1）。sd モデルは `sck` エッジで内部同期する SPI モデル。

### §3.1 参考実源対応表（v0.3 追加・レビュー §11 教訓反映）

コード例の各接続について、V8-a 参考実源との対応行を以下に併記（レビュー §11 の「V8-a を diff 感覚で並べる」運用強化提案の実装）：

| v0.3 §3.1 の記述 | V8-a 参考実源 | 一致 |
|---|---|---|
| `assign irq_in = irq_timer_o ? 3'd1 : (irq1_o ? 3'd2 : 3'd0);` | tb_cpu_v8catls_poc.sv **L84** | 完全一致 |
| `ysd8800_cpu_v0_1 dut_cpu (...)` | tb_cpu_v8catls_poc.sv **L89-97** | 完全一致 |
| `ysd8800_v5_membus_v0_1 #(...) u_membus (...)` | tb_cpu_v8catls_poc.sv **L103-127** | 完全一致（disk_sectors_i の幅のみ本設計書独自：本番は 16 セクタ = 32'd16） |
| `sd_spi_model_v0_3_poc u_sd (...)` | tb_cpu_v8catls_poc.sv **L131-136** | 完全一致 |

### §3.2 PSRAM 初期化（ゴールデン等価性 CL-1）【v0.1 全面改訂】

**v0.1 誤記**：「lnk23 出力の Forth セクション → 物理 `$5100` 起点」（$5100 は実源に一切現れない）
**v0.2 訂正**：**Pre-3 で凍結された yuios_road2.bin を PSRAM 全域に $readmemh でロード**。物理アドレス配置は sym ファイル（yuios_road2.sym）で実測確定した以下を採用：

| シンボル | 実物理アドレス（sym 実測） |
|---|---|
| `_kstart`（kernel エントリ・リセットベクタ先） | **$00E00** |
| `WORD_OS_START`（Forth OS-START） | **$0D295** |

**注意（原則 76）**：kernel_v12_8.asm L1475 のコメントには `WORD_OS_START = $e988` と書かれているが、これは v0.12.0 時点の古い値。**現在の lnk23 出力実測は `$D295`**。ソースコメントは信用せず、sym 実測値を採用する。

**初期化手順**：

```systemverilog
initial begin
    // (v0.2 改善 A5) 56,416B 全域を明示的に 0 クリア
    for (int i = 0; i < 56416; i = i + 1)
        u_membus.u_psram_ctrl.mem[i] = 8'h00;
    // Pre-3 凍結バイナリを HEX 変換したものをロード
    $readmemh("yuios_road2.hex", u_membus.u_psram_ctrl.mem);
    // CL-1 チェックリスト実施 (§7 参照)
end
```

**チェックリスト CL-1**（§7 で詳述）：`$readmemh` の対象行数が 56,416 であることを $display で表示し、期待値と一致しない場合は $fatal で即停止する。

**v0.1 誤記**：「非デフォルト要素数を数えて」（PSRAM 初期値の扱いで判定困難）
**v0.2 訂正**：**行数カウント方式**を採用（V8-a L287-289 の手法に準じる。ただし V8-a の 1KB 限定初期化ではなく全域）。

### §3.3 SD image 供給（ゴールデン等価性 CL-2）

- **モデル**  : `sd_spi_model_v0_3_poc.sv`（V8-a 実戦投入済）
- **image**   : `sd_image.hex`（**8,192B = 16 セクタ**、YUIFS マジック "YUIFS" 先頭）
- **役割**    : kernel_forth_v0_10_18.fs の `FS-MOUNT-DBG`（L2784）と `DIR-LOAD` が YUIFS 認識に成功する必要がある（BOOT-MSG より前の起動シーケンス）
- **チェックリスト CL-2**（§7 で詳述）

**v0.1 誤記**：「24,576B = 48 セクタ」（ファイルサイズ 24,576B と実データサイズ 8,192B の混同。1 行 3 バイト × 8,192 行 = 24,576）
**v0.2 訂正**：実データサイズ **8,192B = 16 セクタ**（V8-a 実績と完全同一）。

### §3.4 UART 収集【v0.1 全面改訂】

**v0.1 案**：「9600bps × baud 分周比で 8 ビット受信」（実源未確認で複雑化していた）
**v0.2 改訂（A1）**：V8-a TB で確立された **`uart_tx_valid_o` パルス駆動**方式を踏襲。DUT が `uart_tx_valid_o = 1` を 1 cycle 上げるたびに `uart_tx_data_o[7:0]` を採取する。9600bps サンプリング不要。

```systemverilog
byte uart_bytes[$];   // UART バイト列蓄積 (dynamic queue)
integer uart_fd;

initial uart_fd = $fopen("uart_out.log", "w");

always_ff @(posedge cpu_clk) begin
    if (uart_tx_valid_o) begin
        uart_bytes.push_back(uart_tx_data_o);
        $fwrite(uart_fd, "%c", uart_tx_data_o);
        $fflush(uart_fd);  // 途中経過をリアルタイムに永続化
    end
end

final $fclose(uart_fd);
```

**マイルストーン検出**：蓄積 `uart_bytes` に対して部分列一致で `"YUIOS Booted!"`, `"0YUI> "`, `"0123MD"` を判定。

---

## §4 観測マイルストーン方式（M-1 〜 M-5）【v0.1 数値訂正】

KY 防止策 1 の基幹。各 M で「到達時 cycle 数の想定」「未到達時のタイムアウト cycle 数」「通過時の 1 行 $display」を事前明記。

| M | 名称 | 判定条件 | 想定到達 cycle | phase-1 打切 | 通過時 $display |
|---|---|---|---|---|---|
| M-1 | リセット解除・_kstart 到達 | **`dbg_pc == 16'h0E00`**（v0.2 訂正：$5100→$0E00） | 〜100 cycle | 10,000 | `[M-1] PC reached $0E00 (_kstart) @cycle=%d` |
| M-2 | 最初の UART TX | `uart_bytes.size() >= 1` | 〜10 万 cycle | 200,000 | `[M-2] First UART TX byte=$%02x @cycle=%d` |
| M-3 | "YUIOS Booted!" 到達 | uart_bytes に `59 55 49 4F 53 20 42 6F 6F 74 65 64 21` 包含 | 〜数百万 cycle | 5,000,000 | `[M-3] "YUIOS Booted!" detected @cycle=%d` |
| M-4 | "0YUI> " プロンプト | uart_bytes に `30 59 55 49 3E 20` 包含 | M-3 + 数十万 cycle | 8,000,000 | `[M-4] "0YUI> " prompt detected @cycle=%d` |
| M-5 | **"0123MD" マーカー**（v0.2 訂正：123MD→0123MD） | uart_bytes に `30 31 32 33 4D 44` 包含 | M-4 + 数百万 cycle | phase-3 で判定 | `[M-5] "0123MD" detected @cycle=%d ==> PASS` |

**v0.2 追加：失敗マーカー早期検出（A3・原則 87）**

M-2 通過後、以下のマーカーを検出したら即 FAIL とする（YUIFS 起動失敗の弁別）：

| マーカー | ASCII | 意味 | 推定原因 |
|---|---|---|---|
| `'i'` | $69 | SB-LOAD I/O エラー | SD SPI モデル or STOR ドライバの故障 |
| `'g'` | $67 | MAGIC 不一致 | sd_image.hex 破損・供給パス誤り |
| `'v'` | $76 | ver_major 不一致 | image version と kernel v12.8 の想定不一致 |

失敗マーカー検出時：`[FAIL-EARLY] YUIFS mount failed marker='%c' @cycle=%d` を出力して $finish。

**注記（v0.3 追加・レビュー指摘 5）**：本表の判定は `uart_rx_valid_i = 1'b0`（本番 idle）前提で有効。将来 UC-1 対応で **RX 刺激を追加する場合**、`'v'` は Shell コマンド `SH-CMD-VER`（kernel_forth_v0_10_18.fs L3398 の `$76 = IF SH-CMD-VER`）のエコー由来の可能性があり、判定条件の再検討が必要。`'i'` / `'g'` はシェルコマンドとしては未使用のため RX 追加後も判定有効。

---

## §5 段階起動プラン（KY 防止策 3）【v0.1 維持】

### §5.1 phase-1（快速 sanity, MAX_CYCLES = 1,000,000）

- **狙い** : M-1 通過（$0E00 到達）+ M-2 通過（UART TX 発生）
- **失敗時** : M-1 未到達なら PSRAM 初期化 or リセット経路異常。M-2 未到達なら UART/MMIO 経路異常。
- **想定時間** : iverilog 5〜30 秒

### §5.2 phase-2（起動完走確認, MAX_CYCLES = 10,000,000）

- **狙い** : M-3（"YUIOS Booted!"）+ M-4（"0YUI> "）通過
- **失敗時** : 常駐タスク起動シーケンスの停止（v0.2 では失敗マーカー 'i'/'g'/'v' で自動弁別可）
- **想定時間** : iverilog 1〜5 分

### §5.3 phase-3（本番判定, MAX_CYCLES = 100,000,000）

- **狙い** : M-5 通過（"0123MD"）→ **PASS 宣言**
- **想定時間** : iverilog 10〜30 分

---

## §6 判定基準【v0.1 拡張】

### §6.1 PASS

以下すべて成立：
1. M-5 到達（`$display("... ==> PASS")`）
2. `uart_out.log` に `grep -aoE '0123MD' uart_out.log` が非空
3. TB が正常に `$finish`、iverilog 終了コード 0

### §6.2 FAIL（v0.2 拡張・A3）

以下のいずれか：
1. `MAX_CYCLES` 到達（M-5 未検出）
2. `$fatal` / `$error` 発火
3. **失敗マーカー `i` / `g` / `v` 検出**（YUIFS 起動失敗・v0.2 新規）
4. 連続 500,000 cycle UART TX なし（デッドロック疑い）
5. **CL-1/CL-2/CL-3 のいずれか失敗**（TB 起動直後の $fatal）

### §6.3 部分 PASS

- **P1-OK** : M-1・M-2 到達（quick sanity）
- **P2-OK** : M-3・M-4 到達（起動完走・Shell 立上）
- **P3-OK** : M-5 到達（本番 PASS）

---

## §7 ゴールデン等価性チェックリスト【v0.1 CL-1 全面改訂・CL-3 訂正】

TB v0.1 の `initial` ブロックで **必ず** 実行し、失敗時は `$fatal` で即停止。

| CL | 項目 | 検査内容（v0.2 確定版） | 失敗時の推定 |
|---|---|---|---|
| **CL-1** | PSRAM 全域初期化 | **手順**: (1) `for (i=0; i<56416)` で mem[i]=8'h00 明示クリア、(2) $readmemh 実行、(3) 読込行数が 56,416 と一致することを $display で表示、(4) mem[$00E00] に kernel_v12_8 の先頭命令 opcode（要 Pre で確定・下記 UC-2）が存在することを確認 | HEX 変換の欠落 / lnk23 出力異常 |
| **CL-2** | SD image | sd_spi_model 内 `sd_mem[]` の先頭 5 バイト = "YUIFS" ($59, $55, $49, $46, $53) | image 供給パス誤り |
| **CL-3** | CPU 初期状態 | **リセットベクタ読出完了後（`_kstart` 実行前）**: **`dbg_pc == 16'h0E00`**（v0.2 訂正：$5100→$0E00 / v0.3 表現訂正：「リセット直後」→「リセットベクタ読出完了後」）、**`_kstart` の `LDW SP, #$477E` 実行完了後**: **`dbg_sp == 16'h477E`**（v0.2 訂正：$E000→$477E, KERN_SP_TOP） | CPU コアのリセット挙動異常 |

**V8-a の PSRAM 1KB 事故（V8-D 顕在化）を反復させない**。CL-1 の (1) 全域明示クリアは V8-a の `16'h0400` 限定初期化を反面教師にした v0.2 の中核改善。

**CL-3 実装ヒント（v0.3 追加）**：CPU コア（ysd8800_cpu_v0_1_FIXED.sv L586-604）は S_RESET_LO → S_RESET_HI の 2 段でリセットベクタを読出す。したがって「リセット解除後の cycle=1」に `dbg_pc == $0E00` は成立しない（リセットベクタ読出中は PC 未確定）。実装では「M-1 の判定（`dbg_pc == $0E00` を最初に検出した cycle）」に CL-3 の PC assert を紐付ける形が自然。SP assert は「`_kstart` の `LDW SP, #$477E` 完了直後」で行う（PC が $0E00 の次の命令アドレスに進んだ時点）。

---

## §8 SD image 準備方針【v0.1 訂正】

- **採用** : `sd_image.hex`（V8-a 用、**8,192B = 16 セクタ**、YUIFS マジック確認済）を**そのまま流用**
- **理由（v0.2 訂正）** :
  1. V8-a 実 SPI 経路で kernel v12.8 + 同 image の組合せが動作実績あり（cat/ls 出力実証）
  2. YUIFS スーパーブロック（先頭セクタ）が有効で、FS-MOUNT-DBG の SB-LOAD/MAGIC/version チェックを通過できる
  3. **M-5 判定文字列 "0123MD" は FILEMGR タスクの YUIFS 起動進捗マーカーであり、SD 参照が必須**（v0.1 の「SD 参照不要」は誤り）
- **配置** : TB と同一ディレクトリに `sd_image.hex` を置く（sd_spi_model_v0_3_poc の `$readmemh` 対象）
- **新規生成不要** : mkfs_yuifs 再実行はしない（バイト等価性維持）

**v0.1 誤記の記録**：「M-5 判定文字列 '123MD' は Shell 内蔵マーカーで SD 参照不要（Forth SH-CMD-VER 系）」→ **根本的誤り**。SH-CMD-VER (L3265-3271) は "YUIOS V0.10.18" を出力する別関数で、Shell コマンド `VER` として明示呼出しされる必要がある（起動時自動発火しない）。

---

## §9 UART 出力の永続化方針【v0.1 維持・実装簡素化】

- **手法** : `$fopen("uart_out.log", "w")` → UART TX 1 バイト受信ごとに `$fwrite(fd, "%c", byte)` → シミュ終了時 `$fclose`
- **追加**（v0.2）: `$fflush(uart_fd)` で途中経過をリアルタイム永続化（長時間シム時に途中確認可）
- **同時にターミナル出力** : マイルストーン到達 `$display` は標準出力にも残す（UART 生ログは `uart_out.log` のみ）

---

## §10 未確定事項・確認事項【v0.1 UC-1 廃止・UC 再構成】

以下 3 点、レビューで判定願います：

- **UC-1（v0.2 差替）** : V8-a の sd_image.hex（8KB・HELLO.TXT のみ）で、V8-b の YUIFS 完全起動シーケンス（SB-LOAD → MAGIC-CHECK → ver チェック → FS-MOUNTED → DIR-LOAD）が全通過するか
  - V8-a では cat/ls デモを実行するだけで、`FS-MOUNT-DBG` 経由の完全起動シーケンスが実際に走ったかは V8-a TB のログを見返す必要あり
  - **暫定案**：phase-1 で M-2 通過後、UART TX を目視観察。'0' → 'i' 系失敗が出たら sd_image.hex の内容を精査。'0' → '1' → '2' → '3' → 'M' → 'D' が期待通り流れれば OK。
  - **v0.1 UC-1（SH-CMD-VER 自動発火説）は廃止**（根拠が誤りだったため）

- **UC-2**（v0.2 新規）: CL-1 の 4 番目「mem[$00E00] に kernel_v12_8 先頭命令 opcode が存在」を assert するための実 opcode 値
  - kernel_v12_8.asm の `_kstart:` 直後 `LDW SP, #$477E` の hasm23 出力バイト列を Pre で確定する必要あり
  - 暫定案：CL-1 の (4) は初回 TB 実行時にダンプで確認し、v0.3 で固定値化する（v0.2 の CL-1 では (1)(2)(3) のみを必須、(4) は情報表示のみ）

- **UC-3**（v0.1 UC-3 継続）: phase-1 の M-1 タイムアウト値 10,000 cycle は妥当か
  - CPU リセット → PC=$0E00 到達は数十 cycle のはずだが、実源上の cycle 数実測なし
  - 10,000 は保守的余裕。過大なら phase-1 全体の予算に食い込むが 100 万に対して 1% なので許容

---

## §11 版数・付記

- v0.1 (2026-07-31) : 初版起票（差戻し）
- v0.2 (2026-07-31) : レビュー指摘（差戻し）5 件必修正 + 3 件補足 + 実源照合副産物 5 件反映。実源照合 6 項目（A/B/C/D/E/F）完了。**条件付き承認**。
- **v0.3 (2026-08-01) : v0.2 レビュー条件付き承認への対応。必修正 3 件（§3.1 コード例：SD `.clk` 削除・disk_sectors_i 32 bit 化・irq_in assign 明示）+ 補足 2 件（§7 CL-3 表現・§4 RX 前提注記）反映。§3.1 に V8-a 参考実源対応表を追加。**
- 想定 TB 実装ファイル名 : `tb_cpu_v8b_prod_v0_1.sv`（v0.3 承認後に着手）
- 想定生成物 : `uart_out.log`, iverilog 実行ログ, PASS/FAIL 判定
- 関連原則 : 76（実源照合）, 82, 83, 86, 87（弁別性・失敗マーカー活用）, 88, 93, 94（PSRAM 全域初期化）, 95, 96, 97

**レビュー観点（v0.3 推奨）**：
1. §3.1 コード例の V8-a 実源整合（必修正 3 件の反映確認、参考実源対応表の網羅性）
2. §7 CL-3 の「リセットベクタ読出完了後」表現と実装ヒントの明瞭性
3. §4 失敗マーカー表の RX なし前提注記の妥当性
4. UC-1（sd_image.hex の V8-a→V8-b 十分性）の判定（v0.2 から継続）
5. UC-2（CL-1 の 4 番目 opcode 値）と UC-3（M-1 タイムアウト）の妥当性（v0.2 から継続）

---

## §12 レビュー教訓の反映（v1.0 レビュー §10 対応）

v0.1 レビュー §10「本レビューでの追記」で **「Pre 工程申し送り情報の伝達精度」** が指摘された。**具体的には kernel_v12_8_migration_design v1.3 §10.5 で確立済の「123MD 由来」情報が v0.1 に反映されていなかった**。

v0.2 では以下の運用改善を組み込む：

1. **設計書起票前に必ず Pre 工程の確定事実一覧を照合**する（PC 起点・SP 初期値・マーカー由来・SD image 要件）
2. **ソースコメントは信用しない**（例：kernel_v12_8.asm L1475 `$e988` は古い値。sym 実測 `$D295` が絶対）
3. **実源照合結果の副産物発見も設計書に明示**（本 v0.2 の §0.3 追加改善 5 件）
4. **今後の Pre 工程完了時の申し送り書に「Pre 工程で確定した実源事実の項目一覧」を明示的に含める**運用を提案（HANDOVER 次版で反映依頼）

### §12.1 v0.2 → v0.3 レビュー教訓（SV コード例のミクロ実源照合）

v0.2 レビュー §11 で **「マクロレベル（アドレス値・レジスタ初期値）の実源照合は徹底したが、ミクロレベル（SV コード例のポート接続・ビット幅・assign 文）の実源照合が抜けていた」** と指摘された。具体的には SD SPI モデルの `.clk(psram_clk)` は「V8-a を踏襲」と書きながら実は V8-a と異なる形になっていた。**「V8-a の TB を実際に diff 感覚で並べて確認していない」** ことを示唆する事実であり、原則 76（実源照合）のミクロレベル運用不足。

v0.3 では以下の運用改善を追加で組み込む：

5. **設計書に SV コード例を含める場合、参考実源の該当行を diff 感覚で並べて確認**する。「◯◯を踏襲」と書きながら実は違う形になっているミスを防ぐ。
6. **参考実源対応表を設計書本体（§3.1 末尾）に転記**し、コード例の各接続について V8-a の対応行を明示する（v0.3 §3.1 実装済）。
7. **SV コード例をレビュー前に iverilog でコンパイル**（DUT の中身は空 module でよい）してポート接続の syntactic 正当性を確認する運用を検討。今回の指摘 1〜3 はコンパイル一発で全て検出できた。
8. 「マクロ実源照合済」で満足せず、**設計文書に含まれる全てのコード例を実源照合対象**とする（原則 76 の対象範囲拡張）。
