# V6-A ストレージコントローラ（YSD8003）RTL設計メモ v0.1

- **作成日**: 2026-07-18
- **担当**: CHAT105（V6-A 設計検討フェーズ）
- **状態**: ★レビュー未承認★（原則43：本メモのレビュー承認まで実RTLを書かない）
- **上位規範**: sim_impl_policy v0.2（G1〜G4 実現可能性ゲート）
- **互換基準**: emu23_v111.c L295-320 / L642-666 / L761-810・sd_sample.c・yuios_ph3_storage_design_v1_5.md

---

## 0. 本メモの目的

FPGA-RTL版 YSD8003（ストレージコントローラ）の設計方針を定め、レビューを受ける。
V6-A の範囲は **SPIモードでのSDカード単一ブロック読出（CMD17）** の最小セット。
書込（CMD24）・マルチブロック・DMAはV6-Bに送る。

---

## 1. ★本テーマ最大の論点：emu23 と RTL の非対称★

### 1.1 emu23 側 YSD8003 の実体（実照合済み）
emu23（emu23_v111.c）の EXEC は、SDのSPIプロトコルを **完全に隠蔽** している：

```
SD_CMD=2(EXEC) 受理
  → fseek(disk_fp, lba*512)
  → fread(sd_buf, 1, 512)      ← ホストファイルから即時 memcpy
  → sd_stat = READY(0x04) or ERROR(0x02)
  → IRQ_EN なら sd_irq_delay=512 で完了IRQ(IRQ1)予約
```

CMD0/CMD8/ACMD41/CMD17・CRC7/CRC16・SCK生成・R1/R7レスポンス・データトークン(0xFE)
は emu23 に **一切存在しない**。ホストOSのファイルI/Oがそれらを肩代わりしている。

### 1.2 RTL 側 YSD8003 で新規実装せねばならないもの
FPGAには「ホストのfread」に相当する魔法がない。実SDカードはSPIプロトコルでしか
喋らないため、隠蔽層を **実RTLの状態機械** として起こす必要がある：

- SPI マスタ（SCK生成・MOSI/MISOシフト・CS制御）
- SDカード初期化シーケンス（CMD0 → CMD8 → ACMD41ループ → [CMD58]）
- 単一ブロック読出（CMD17 → R1 → データトークン0xFE待ち → 512バイト → CRC16 2バイト）
- R1/R7 レスポンス解釈、CRC7送出（初期化中はCRC必須）

**→ ここが本テーマの山場。emu23協調等価は使えない（§4 検証戦略参照）。**

### 1.3 非対称の帰結（設計判断）
- **MMIOレジスタI/F（$FCA0-$FCB0）だけは emu23 互換**にする（OS無改修の条件）。
- **レジスタの内部実装（EXECの意味）だけが別物**。
  emu23: EXEC=fread。RTL: EXEC=SPIブロック読出状態機械の起動。
- OSから見た外部観測（STAT=BUSY→READY、DATA を512回読むと中身が出る）は同一に保つ。

---

## 2. プログラマI/F（emu23互換・OS無改修の契約）

### 2.1 MMIOレジスタ（$FCA0-$FCB0・emu23 実照合済み）

| アドレス | 名前 | R/W | 説明 |
|---|---|---|---|
| $FCA0 | SD_CMD | W | 0=READ_SETUP / 1=WRITE_SETUP / 2=EXEC |
| $FCA2 | SD_STAT | R | bit0=BUSY / bit1=ERROR / bit2=READY（BUSYラッチ方式） |
| $FCA4 | SD_LBA_LO | R/W | LBA 下位16bit |
| $FCA6 | SD_LBA_HI | R/W | LBA 上位16bit |
| $FCA8 | SD_BUF_PTR | R/W | バッファポインタ 0-511（EXEC時0リセット） |
| $FCAA | SD_DATA | R/W | PIOデータ8bit・読書きでBUF_PTR自動++ |
| $FCAC | SD_IRQ_CTRL | R/W | bit0=IRQ_EN / bit1=ERR_EN |
| $FCAE | SD_DISK_LO | R | 総セクタ数 下位16bit |
| $FCB0 | SD_DISK_HI | R | 総セクタ数 上位16bit |

- **帯域は16バイト（$FCA0-$FCAF）＋$FCB0**。UART($FC80,下位3bit)/Timer($FC90,下位4bit)と
  同様、YSD8003は **下位5bit（$FCA0-$FCBF の32バイト枠）** でデコードするのが素直。
  → addr_decoder / mmio_stub に **$FCA0-$FCBF を YSD8003 へルーティングする改修**が要る（V4/V5と同型作業）。

### 2.2 BUSYラッチ方式（emu23 L642-651 準拠）
- EXEC 発行で BUSY ラッチ=1、sd_stat=0（READY落ち）。
- SD_STAT 1回目読出 → BUSY=1 を返し、ラッチクリア。
- 2回目以降 → sd_stat（READY=bit2 or ERROR=bit1）を返す。

**★RTLでの相違点★**: emu23 は fread が即完了なので「1回目BUSY・2回目READY」で足りる。
RTL は SPI転送に実時間がかかるため、**SPI転送完了までは STAT=BUSY を返し続ける**方式が自然。
OS側 sd_wait_ready() は「1回目STAT読→2回目STAT読で判定」の2アクセス固定（sd_sample.c L100-105）だが、
実SPIは512バイト読出に数千SCK掛かる。**この整合が設計の要注意点（§2.3）。**

### 2.3 ★要検討★ OS側 sd_wait_ready の2回読み固定 と 実SPI遅延の整合
- OS現行ドライバ（sd_sample.c）は sd_wait_ready で **STAT を2回読むだけ**でREADY判定している。
  emu23 では fread 即完了ゆえこれで成立する。
- RTL で SPI が実時間を要する場合、2回目STAT読の時点でまだ転送中なら BUSY のままとなり
  ドライバが「READYもERRORも無い＝異常(return 1)」と誤判定するリスクがある。
- **対策候補（レビューで選定）**:
  - (A) **EXEC を同期ブロッキング的に扱う**：EXEC書込に対する SPI 512バイト読出を、
    CPUから見て十分速く（4MHz・SCK分周次第で数百µs）完了させ、
    かつ **BUSY を「SPI完了まで返し続ける」ではなく emu23互換の「1回目のみBUSY」** にする。
    → 実転送は EXEC 受理〜最初のSTAT読の間に終わっている必要。ワースト転送時間の見積り必須。
  - (B) **OS側ドライバをポーリングループ化**（READYになるまでSTAT読を繰り返す）。
    → ただし「OS無改修」の完了条件に反する。**原則、案(B)は不可。**
  - (C) **完了IRQ(IRQ1)で待つ方式へOSを寄せる**。→ これもOS改修。不可。
  - **暫定方針**: **案(A)を第一候補**とし、SCK分周を上げてワースト転送時間を短縮、
    「EXEC受理後、最初のSTAT読までにSPI読出完了」を保証できるかをタイミング解析で確認する。
    保証できない場合はレビューで再協議（OS側の微修正許容可否をかやぬまさんに確認）。

### 2.4 完了IRQ（IRQ1・emu23 L786-792 準拠）
- emu23: IRQ_EN 時、EXEC受理後 512cycle で IRQ1（IRQ_STAT_BIT_STOR）発火。
- RTL: SPIブロック読出完了検出 → YSD8004 へ **レベル出力**（Timer irq_timer_o と同じ作法）。
- YSD8004 の STOR ビット（IRQ1）へ接続。ack で解除（YSD8002 の irq0_ack と同型）。

---

## 3. RTL構成案（モジュール分割）

```
ysd8800_ysd8003_v0_1.sv  （YSD8003 トップ）
 ├─ MMIO レジスタファイル（$FCA0-$FCB0・sel_i/addr_i/we_i/wdata_i/rdata_o）
 ├─ セクタバッファ 512B（BSRAM 1個 or 分散RAM）
 │    ※BSRAM(468Kbit)は将来キャッシュ用に温存方針だが、512B=4Kbitは僅少。要レビュー判断
 ├─ SPI マスタ（SCK/MOSI/MISO/CS・8bitシフタ・分周器）
 └─ SD 初期化＆読出 状態機械（FSM）
      INIT: CMD0→CMD8→ACMD41ループ→[CMD58] → IDLE
      READ: CMD17→R1→トークン0xFE待ち→512B→CRC16 → DONE(→IRQ1, STAT=READY)
```

### 3.1 SPI 信号（Tang Nano 9K 外部ピン）
- SCK / MOSI / MISO / CS_n の4線。Tang Nano 9K の GPIO へ割当（ピンアサインはV6-A実装時に確定）。
- SCK分周: CPU 4MHz に対し、初期化中は 100-400kHz 必須（SD規格）、
  読出中は分周比を上げて高速化（数MHz）。→ 分周レジスタ or 固定段切替で実装。

### 3.2 CDC の要否
- SPIは CPU クロック(4MHz)ドメインで完結させれば **CDC不要**（SCKは4MHzを分周生成）。
  PSRAM のような別ドメインは無い。→ **V6-A では CDC 不要**の見込み（レビュー確認）。

---

## 4. 検証戦略（★emu23 黄金リファレンス枠外★）

### 4.1 emu23協調等価が使えない理由
§1 の通り emu23 は SPI を持たない。よって「emu23黄金 vs RTL」の一致検証は **原理的に不可能**。

### 4.2 正解リファレンス＝SDカードSPIビヘイビアモデル（新規SV）
- `sd_spi_model_v0_1_poc.sv`（KY38：_poc）を新規作成。
- 模擬範囲（roadmap §96 準拠）:
  - CMD0(GO_IDLE) → R1=0x01（アイドル）
  - CMD8(SEND_IF_COND) → R7（0x01 + エコーバック）
  - ACMD41(SD_SEND_OP_COND) → R1=0x00（初期化完了）までループ
  - CMD17(READ_SINGLE_BLOCK) → R1=0x00 → データトークン0xFE → 512バイト（既知パターン）→ CRC16
- モデルのセクタ内容は既知パターン（例: LBA*512+i の下位バイト）とし、
  RTL経由でOSが読んだ512バイトが一致するかをTBで照合。

### 4.3 単体TB
- `tb_ysd8003_v0_1.sv`: YSD8003(RTL) ＋ sd_spi_model を接続。
  - T1: 初期化シーケンス完走（CMD0/8/41 が正しい順で出る・CSトグル・CRC7正当）
  - T2: CMD17 単一ブロック読出 → 512バイトが既知パターンと一致
  - T3: STAT BUSY→READY 遷移、SD_DATA 512回読出の中身一致
  - T4: 完了IRQ(IRQ1) がレベルで立ち、ack で落ちる
  - T5（negative・KY54先行）: MISOがトークンを返さない/CRCエラー時に ERROR(bit1) 立つ

### 4.4 統合検証（OS無改修ブート）
- YUI OS 現行ストレージドライバ（PIO/SD_DATA読出）で cat/ls が通るか。
- **§2.3 の2回読み整合が最終関門**。ここが通れば V6-A 完了条件達成。

---

## 5. sim_impl_policy v0.2 実現可能性ゲート適用（G1〜G4）

| ゲート | 判定 | 根拠 |
|---|---|---|
| G1 ハード実現可能性 | ✅ | SPIマスタ・FSMは標準的RTL。実SDカードで実績多数 |
| G2 リソース収容 | 要確認 | GW1NR-9 のLUT/BSRAM収容。512Bバッファ＋FSMは小規模。V6-A実装時に合成見積 |
| G3 タイミング収束 | 要確認 | SCK分周・4MHz。§2.3 のワースト転送時間 vs OS2回読みが焦点 |
| G4 外部I/F実在性 | ✅ | Tang Nano 9K GPIO でSPI 4線を物理的に出せる |

**→ emu23 に SPI隠蔽を持ち込まない（既に隠蔽済み・RTL側で実装）方針は policy に合致。
   逆に「RTLで実現不能な抽象（fread相当）をRTLに持ち込まない」＝実SPIで実装する、が本設計の核。**

---

## 6. 想定成果物（レビュー承認後・KY38準拠）

| ファイル | 種別 |
|---|---|
| ysd8800_ysd8003_v0_1.sv | YSD8003 RTL本体 |
| sd_spi_model_v0_1_poc.sv | SDカードSPIビヘイビアモデル（_poc） |
| tb_ysd8003_v0_1.sv | 単体TB |
| ysd8800_mmio_stub_v0_7.sv | $FCA0-$FCBF ルーティング追加（KY60対象にYSD8003追加） |
| ysd8800_addr_decoder_v0_2.sv | YSD8003 hit デコード追加 |
| build_v6a.sh | ビルドスクリプト（storage追加） |

---

## 7. ★レビューで諮りたい決定事項★

1. **§2.3 の整合方針**: 案(A)（SPIを十分速くしEXEC〜初回STAT読で完了保証）で進めてよいか。
   保証困難時にOS側の微修正を許容するか（完了条件「OS無改修」との兼ね合い）。
2. **セクタバッファ**: BSRAM温存方針に対し 512B(4Kbit) を BSRAM で取ってよいか、分散RAMにするか。
3. **SCK分周**: 初期化100-400kHz / 読出高速 の2段切替でよいか、可変分周レジスタを設けるか。
4. **CDC不要**の見込み（SPI=4MHzドメイン完結）で問題ないか。
5. **V6-A範囲**: 読出(CMD17)のみに絞り、書込(CMD24)はV6-Bで確定してよいか（roadmap通り）。

---

## 8. KY（本メモ関連）
- **KY38**: SPIモデル・実験RTLは `_poc` サフィックス厳守。
- **KY60拡張**: mmio_stub の YSD8003 参照を V6-A から監視対象に追加。
- **KY54**: TB は negative（T5）を先に実行してから positive を確認。
- **本テーマKY**: emu23協調等価が使えない点を常に意識（リファレンス不在での実装暴走を防ぐ）。

---

（改版履歴）
- v0.1 (2026-07-18) 新規作成。emu23/RTL非対称の確定、MMIO互換I/F、SPI-FSM構成案、
  検証戦略（emu23枠外・SPIモデル+単体TB）、sim_impl_policy G1-G4適用、
  レビュー諮問5点を記載。★レビュー未承認★
