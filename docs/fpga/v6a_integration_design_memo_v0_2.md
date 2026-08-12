# V6-A 上位結合 設計メモ v0.1

- **作成日**: 2026-07-19（CHAT108）
- **目的**: 単体TB全PASS済みの YSD8003 v0.2（CMD17読出）を上位（mmio_stub → membus）へ結線し、CPUからの実MMIOアクセスで動作させる。最終的に YUI OS（sd_sample / mkfs_yuifs イメージ）を実SPI経由で読む。
- **原則43**: 本メモのレビュー承認を得てから RTL 改変に着手する。
- **KY60**: 旧版参照（v0.1）混入を実測で排除済み（§4）。

---

## 1. 現状の実測結果（KY34＝実ファイルが真実）

### 1.1 版数連鎖の現状
| 上位 | 参照している下位 | 備考 |
|---|---|---|
| ysd8800_v5_membus_v0_1.sv (L273) | **ysd8800_mmio_stub_v0_5** | ★古い★ |
| ysd8800_mmio_stub_v0_6.sv (L337) | ysd8800_ysd8002_v0_3 | EN是正版・最新 |

→ **membus が mmio_stub v0.5 を指しており、v0.6（EN是正・irq0_ack対応）に未追従**。本結合で v0.6 系へ更新が必要。

### 1.2 mmio_stub v0.6 のペリフェラル実装状況
| ペリフェラル | MMIO領域 | インスタンス | 割込 | wait-state |
|---|---|---|---|---|
| YSD8001 UART | $FC80-$FC87 | ✅ u_ysd8001 | - | - |
| YSD8002 タイマー | $FC90-$FC9F | ✅ u_ysd8002 (v0_3) | irq_timer_o 直出し | - |
| YSD8004 割込 | $FCB2-$FCB5 | ✅ | - | - |
| **YSD8003 ストレージ** | **$FCA0-$FCBF** | **❌未実装** | irq_src_stor（外部ポートのみ据置） | 未対応 |

→ 本結合の核心＝**mmio_stub に YSD8003（$FCA0系）を新規インスタンス化**すること。

### 1.3 YSD8003 v0.2 ポート（結線基準）
- MMIOバス: sel_i / addr_i[4:0] / we_i / wdata_i[7:0] / rdata_o[7:0]
- wait-state: ready_o（案D・STAT読み中SPI未完で 0）
- 割込: irq_stor_o（レベル）/ irq_stor_ack（irq0_ack同型）
- SPI物理線: spi_cs_n / spi_sck / spi_mosi / spi_miso
- 設定: disk_sectors_i[31:0]

---

## 2. 結合設計方針（YSD8002を手本とした同型結線）

### 2.1 mmio_stub 改版（v0.6 → v0.7）での追加項目
1. **MMIO領域定義**: `YS3_BASE=16'hFCA0` / `YS3_LAST=16'hFCBF`（YSD8003 v0.2 の addr_i[4:0]＝$FCA0-$FCBF に一致）
   - ★要確認★: 既存 YS4（$FCB2-$FCB5）と領域が重なる。§3で扱う。
2. **hit デコード**: `hit_ys3 = (mmio_addr >= YS3_BASE) && (mmio_addr <= YS3_LAST)`
3. **インスタンス化**: `ysd8800_ysd8003_v0_2` を `u_ysd8003` として追加
   - sel_i ← `hit_ys3 & access`
   - addr_i ← `mmio_addr[4:0]`
   - we_i / wdata_i / rdata_o ← バス結線
   - ready_o ← mmio_ready へ AND 合流（wait-state）
   - irq_stor_o → 外部ポート（YSD8004 IRQ1 STOR 入力へ）
   - irq_stor_ack ← irq1_ack 相当（CPU IRQ1受理でクリア）
   - SPI物理線4本 → 外部ポート新設（TB/Tang Nano GPIO へ）
   - disk_sectors_i ← 外部ポート新設
4. **rdata マルチプレクサ**: hit_ys3 時は u_ysd8003.rdata_o を選択
5. **ready マルチプレクサ**: hit_ys3 時は u_ysd8003.ready_o を mmio_ready に反映（他は 1）

### 2.2 membus 改版（v0.1 → v0.2）
- `u_mmio_stub` の参照を **v0.5 → v0.7** へ更新
- 追加ポート（SPI4本・disk_sectors・irq_stor系）を membus 外部へ透過
- irq0_ack / irq_timer_o の既存結線は維持（EN是正版追従）

---

## 3. ★レビュー要判断事項（原則43）★

### 論点A: MMIO領域の重なり（YS3 $FCA0-$FCBF と YS4 $FCB2-$FCB5）
- YSD8003 v0.2 は addr_i[4:0]（$FCA0-$FCBF＝32バイト）を受ける設計。
- しかし YSD8004（割込）が $FCB2-$FCB5 を占有済み。
- **単純に YS3=$FCA0-$FCBF とすると YS4 と衝突**。
- **候補**:
  - (A) YS3 を **$FCA0-$FCB1**（18バイト）に限定し、YSD8003 内部レジスタは §4.1（emu23互換 $FCA0-$FCAA）に収まるため実害なし。YS4（$FCB2-）は従来通り。
  - (B) YSD8003 の addr_i デコードを mmio_stub 側で $FCA0 基点にオフセットし、上位で範囲を絞る。
- **推奨: 候補(A)**。YSD8003 の実使用レジスタは $FCA0-$FCAA（HANDOVER §4.1）で $FCB2 に達しないため、hit_ys3 範囲を $FCA0-$FCB1 に絞れば衝突回避。YSD8003 内部の addr_i[4:0] デコードは変更不要。

- **【2026-07-19 追記・OS実測により確定】** sd_sample.c の実使用アドレスを実測した結果、OSは $FCA0-$FCB0 を使用（CMD/STAT/LBA/BUF_PTR/DATA に加え **DISK_LO=$FCAE / DISK_HI=$FCB0**）。RTL v0.2 も DISK_LO/HI を addr[4:0]=5'h0E/5'h10 で実装済（L106-109,270-273 実測）。最上位は $FCB1（5'h11）。YSD8004 は $FCB2 起点のため **$FCB1|$FCB2 で無衝突接続**。→ **候補(A) は「推奨」から「OS実装により確定」へ格上げ。hit_ys3 = $FCA0-$FCB1（5'h00-5'h11）で OS・RTL・割込 三者整合。**

### 論点B: 割込線 irq_stor の接続先
- YSD8003 の irq_stor_o は「YSD8004 IRQ1(STOR)」へ入る想定。
- 現状 mmio_stub は irq_src_stor を**外部ポートで受けている**（未接続の据置プレースホルダ）。
- **方針**: u_ysd8003.irq_stor_o を内部で irq_src_stor 相当へ結線し、YSD8004 の IRQ1 経路に載せる。irq_stor_ack は CPU の IRQ1 受理信号から供給。
- ★要確認★: CPU 側 IRQ1 受理→ack のパスが irq0_ack（タイマー用）と別系統で用意されているか。無ければ本結合で新設が必要（§次ステップで実測）。
- **【2026-07-19 実測・確定】** CPU(ysd8800_cpu_v0_1_FIXED.sv L919-920)の irq0_ack は `(state==S_MEMR_HI)&&mem_ready&&(stack_ctx==CTX_IRQVEC)&&(irq_latch==3'd1)`。**irq_latch の比較値で受理割込番号を判別**しており、IRQ1(vec2)用は `irq_latch==3'd2` の同型 assign で生成可能。→ **方針確定: CPUに irq1_ack を irq0_ack と同型追加（大改造不要）。membus は irq1_ack を透過し u_ysd8003.irq_stor_ack へ中継。** 現状 membus に irq1_o はあるが irq1_ack 入力は無い（新設が必要）。

### 論点C: ready_o（wait-state）の合流
- YSD8002 には wait-state が無かったため、mmio_ready への ready 合流は YSD8003 が初。
- STAT読み中SPI未完で ready_o=0 → CPUストール。既存 mmio_ready ロジックと AND 合流する箇所の特定が必要（§次ステップで実測）。
- **【2026-07-19 実測・確定】** mmio_stub v0.6 L398 `assign mmio_ready = access;`（現状は常時即応答・wait-stateユーザー皆無）。合流点は**この1箇所**。→ **方針確定: `assign mmio_ready = hit_ys3 ? (access & ys3_ready) : access;` に変更。** hit_ys3 時のみ YSD8003.ready_o を反映し、他ペリフェラルの即応答は不変。改修1行・状態変更箇所は一元化（kaizen準拠）。

---

## 4. KY60 実測ログ（旧版参照排除）
- membus v0.1 → mmio_stub **v0.5** 参照（要更新・§1.1）
- mmio_stub v0.6 → ysd8002 **v0.3**（最新・OK）
- YSD8003 は現状どこからもインスタンス化されていない（新規結線）→ v0.2 を明示参照する
- 結線後、`grep -nE "ysd8003_v0_1|ysd8002_v0_1|ysd8002_v0_2[^_]"` で旧版混入ゼロを再確認する

---

## 5. 次ステップ（レビュー承認後）
1. 論点B・C の実測（CPU IRQ1 ack パス / mmio_ready 合流点）
2. mmio_stub v0.6 → v0.7（YSD8003結線・KY41追記のみ）
3. membus v0.1 → v0.2（stub参照更新・ポート透過）
4. 統合TB作成（CPUからCMD17実行 → sd_buf 一致）
5. YUI OS統合（sd_sample / mkfs_yuifs イメージ読出で cat/ls）

---

## 6. 段階的検証方針（1変更1検証）
- Step1: mmio_stub 単体で YSD8003 結線 → コンパイル通過（iverilog警告ゼロ）
- Step2: membus 結線 → コンパイル通過
- Step3: 統合TB（CPU→CMD17）で sd_buf 512B 一致
- Step4: 全回帰（既存 V1〜V5 系 TB が無破壊）
- Step5: YUI OS統合

（以上 v6a_integration_design_memo_v0.1。レビュー承認をお願いします）
