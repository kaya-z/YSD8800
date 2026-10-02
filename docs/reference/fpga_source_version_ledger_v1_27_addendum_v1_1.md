# `fpga_source_version_ledger` v1.27 追補 — 工程②.5 TKT-V10・TKT-V12 完了

| 項目 | 内容 |
|---|---|
| 文書名 | `fpga_source_version_ledger_v1_27_addendum_v1_1.md` |
| 版数 | ~~v1.0~~ → **v1.1**（★TKT-V15成果物④。§A5にTKT-V12分を追記★） |
| 作成日 | 2026-09-20（v1.0）／改訂 2026-09-26（v1.1） |
| 対象台帳 | `fpga_source_version_ledger_v1_27.md`（★本体は無改変★） |
| 追補理由 | 工程②.5（TKT-V10 ライトバッファ・TKT-V12 UART物理層）完了に伴う RTL 版数更新 |

★本書は本体台帳の**追記**である。本体の既存行は一切変更していない（原則121）。★
★次回の本体改版（v1.28）時に、本書の内容を §1 現行一覧へ取り込むこと。★

---

## §A1. ★現行 RTL 版数の更新（2026-09-20）★

| モジュール | 旧 | ★新★ | md5 | 備考 |
|---|---|---|---|---|
| `ysd8800_wbuf` | v0.2 | ★**v0.3**★ | `fa475eee1e8e5bb94d83534602075d5d` | ★案G：`up_burst_len_i`/`dn_burst_len_o` 新設★ |
| `ysd8800_v5_membus` | v0.14 | ★**v0.15**★ | `2a4fe8360300dbaa3a9a152163c5dcd2` | ★`cache_burst_len` を wbuf 経由へ★ |
| `ysd8800_psram_ctrl` | v0.3 | ★**v0.4**★ | `770e0b6f489e3266f98ef3afbcc7f082` | ★案D：`beat_valid <= ~we`★＋コメント是正 |
| `ysd8800_cache` | v0.6 | v0.6（★据置★） | — | ★無改修★（TKT-V7 直後のため触らない方針） |
| `ysd8800_cdc_bridge` | v0.5 | v0.5（据置） | — | 無改修 |

### 検証資産

| ファイル | 版 | md5 | 用途 |
|---|---|---|---|
| `tb_cpu_v8e_dhry_v0_3_bwr_poc.sv` | v1.0 | `ebd2db61773d20202790dab663dfd572` | ★BWR プローブ（DUT 無改変・階層参照のみ）★ |
| `rtl18_v2.f` | v2 | `8c967dc362685491886ac0ad5938ba38` | ★RTL 18本のファイルリスト（上記3本の版追従済）★ |

★`rtl18_v2.f` は手順書 §4.14.7 の 17本リストの後継である（wbuf を加えて 18本）。★
★手順書 `yuios_build_procedure` の改版が**必要**（§A3）。★

---

## §A2. ★変更の要旨★

### A2.1 何が壊れていたか

★`cache.burst_len_o` が wbuf を**迂回して** psram_ctrl へ直結していた（`membus_v0_14` L542→L638）。★
★一方 wbuf は `rd_block`（フィル要求中そのもの）を契機にドレイン**書込**を発行する。★
★その結果、wbuf の書込要求に cache の `burst_len=32` が付き、psram_ctrl では★

1. `we && blen_r==1` が偽 → ★書込消失★
2. `we` を見ずに PS_BURST へ遷移 → ★32本のビート★
3. cache がそれを吸い込み ★書込先アドレスの内容でライン誤充填★

> ★要求経路は横取りしたのに、要求に付随する属性を横取りしなかった。★

### A2.2 対策（2つで完全になる）

| 案 | 実装 | 止めるもの |
|---|---|---|
| ★案G★ | `wbuf_v0_3` ＋ `membus_v0_15` | ★書込消失と32本バースト★ |
| ★案D★ | `psram_ctrl_v0_4` | ★`blen_r=1` 書込が出す1本のビート（W-0）★ |

★実測で分離済：案G のみでは DHRY FAIL（W-0 残存）、案G＋案D で PASS。★

### A2.3 ★恒久アサーションの追加★

`wbuf_v0_3` に `assert (!(dn_wr_o && dn_rd_o))`（`ifndef SYNTHESIS`）を追加。
★案G は `burst_len` を要求経路に載せる改修であり、「要求の種別が一意である」ことが
これまで以上に重要になったため。★全実行で無発火を確認済。

---

## §A3. ★波及（要処置）★

| # | 対象 | 内容 | 状態 |
|---|---|---|---|
| ★1★ | ★`yuios_build_procedure` §4.14.7★ | ★RTL 17本リスト → `rtl18_v2.f`（18本）★ | ★**改版済**（v1.21・TKT-V15成果物②で統合。§A5参照）★ |
| 2 | `v10_psram_burst_design` | バースト書きの扱いを `psram_ctrl_v0_4` に合わせる | 未実施 |
| 3 | `tb_psram_equiv_v0_1` | `psram_ctrl_v0_2` 参照で実行不能。案D は `beat_valid` 仕様を変えるため等価性基準に直接効く | 未実施 |
| 4 | `cache_v0_6` コメント | 設計書 v0.4 M-3 の指摘分 | 未実施 |

★ツールチェーン（scc23/hasm23/lnk23/emu23）は無改修。★
★ただし**絶対ゲートの値が変わっている**（`tool_version_ledger_v1_30_addendum.md` 参照）。★

---

## §A4. 検証結果（要約）

| 構成 | 結果 |
|---|---|
| ★WBUF_EN=0（W-0）★ | ★C_total 613,237・stall_wr 63,671・stall_rd 153,743 — 基準と完全一致★ |
| ★WBUF_EN=1 / CEN=1★ | ★G-M MISMATCH=0・DHRY PASS・C_total 551,433（-10.1%）★ |
| 単体回帰 | `tb_wbuf_poc` ALL PASS ／ `tb_psram_ctrl` 段2 BURST ALL PASS |

★詳細は `v23_stage25_wbuf_design_v0_8.md` §22 および `v0_9.md` §24。★

---

## §A5. ★【v1.1追記】TKT-V12（UART物理層実装）完了に伴うRTL版数更新（2026-09-25）★

★本節はv1.1追補（本ファイル）の新規追記。§A1〜A4（TKT-V10分）は無変更。対象台帳`fpga_source_version_ledger_v1_27.md`本体はTKT-V12分について無改訂のまま（本節が実質的な最新版）。次回の本体改版（v1.28）時に、本節の内容も含めて§1現行一覧へ取り込むこと。★

### A5.1 現行RTL版数の更新（TKT-V12・実測md5）

| モジュール | 旧 | ★新★ | md5（実測） | 変更内容 |
|---|---|---|---|---|
| `ysd8800_ysd8001` | v0.1 | ★**v0.3**★ | `1e7ee24fc134883494c138b426e5ef97` | ★TKT-V12の本体。v0.2でPHY_EN/BAUD_ENパラメータ新設・物理層ポート（`uart_txd_o`/`uart_rxd_i`/`uart_rx_frame_err_o`）追加。v0.3でB-17是正（`txd_o`のFF出力化・R-10対応）。単一モジュール構成（サブモジュール分割なし）。RX側3段FF同期化。★ |
| `ysd8800_v5_membus` | v0.15 | ★**v0.17**★ | `46a1666a9d6ea76e53ffea2e6af92ef5` | ★v0.16でYSD8001参照をv0_1→v0_2に追従、PHY_EN/BAUD_ENパラメータ新設・stub透過、外部ポート3本追加。v0.17でu_mmio_stub参照をv0_10→v0_11に追従のみ。モジュール名`ysd8800_v5_membus_v0_1`・WBUF_EN宣言行は無変更（`_wbuf1_poc`のsedパターンはそのまま使える）★ |
| `ysd8800_mmio_stub` | v0.9 | ★**v0.11**★ | `5e68c286b3eeefcc0e4f5d4f7aaacc61` | ★v0.10でYSD8001参照をv0_1→v0_2に追従、PHY_EN/BAUD_ENパラメータ新設・YSD8001へ透過、物理層ポート3本追加（疑似ポート4本は現行どおり残す）。v0.11でYSD8001参照をv0_2→v0_3に追従のみ。`ccr_cen_r`リセット行は無変更（`_cen1_poc`のsedパターンはそのまま使える）★ |
| `ysd8800_wbuf` | v0.3 | v0.3（据置） | — | 無改修（TKT-V12はUART物理層のみが対象） |
| `ysd8800_cache` | v0.6 | v0.6（据置） | — | 無改修 |
| `ysd8800_psram_ctrl` | v0.4 | v0.4（据置） | — | 無改修 |

### A5.2 PHY_EN／BAUD_EN構成表（新設パラメータ）

| 構成 | PHY_EN | BAUD_EN | 用途 |
|:-:|:-:|:-:|---|
| C-0 | 0 | 0 | 既定。既存回帰（Dhrystone等）と完全互換 |
| C-1 | 1 | 0 | 段階検証用 |
| C-2 | 1 | 1 | FPGA実機構成。実分周・実シリアライズ有効 |
| C-3 | 0 | 1 | 禁止構成（RTL側`$fatal`で拒否） |

`-P`オプションでは切り替わらないため、`_phy1_poc`（sed生成）方式で切り替える。詳細は`yuios_build_procedure_v1_21.md` §4.14.7a。

### A5.3 検証資産

| ファイル | 版 | md5 | 用途 |
|---|---|---|---|
| `tb_ysd8001_phy_v0_7.sv` | v0.7 | `14e25810`〜 | UART物理層単体TB。M-3〜M-15（M-10除く）全項目 |
| `tb_cpu_v8b_prod_v0_6_1_phy_poc.sv` | v0.6.1 | — | システム階層TB（M-10／M-10N／M-10N-F） |
| `rtl18_v4.f` | — | `f879f296`〜 | 素版18本構成（membus_v0_17／stub_v0_11／ysd8001_v0_3） |
| `rtl18_v4_dhry_cen1wbuf1.f` | — | `51a022f0` | Dhrystone回帰用（CEN=1/WBUF=1）。C_body=535,469／C_total=551,433 |
| `rtl18_v4_phy1_tb061.f` | — | — | M-10用（membus_v0_17_phy1_poc使用） |
| `ysd8800_v5_membus_v0_17_phy1_poc.sv` | 生成物 | `45cea0d8254240726024d69e821a99a4` | membus_v0_17からsed生成（PHY_EN/BAUD_EN=1）。登録不要（再生成可） |

### A5.4 波及（要処置）

| # | 対象 | 内容 | 状態 |
|---|---|---|---|
| 1 | `yuios_build_procedure` §4.14.7 | RTLリストの`ysd8001_v0_1`→`v0_3`更新、PHY_EN/BAUD_EN切替手順（§4.14.7a）・iverilog12制約（§4.14.7c）追加 | ★**改版済**（v1.21）★ |
| 2 | `ysd8001_uart_design`（上位仕様） | TKT-V12完了反映（C-16①②③・C-28） | ★**改版済**（v1.3.2）★ |
| 3 | RTLヘッダのSpec参照（`ysd8800_ysd8001_v0_3.sv` L11） | `ysd8001_uart_design_v1_2.docx`→現行md文書への参照更新 | ★**未実施・持越し登録**（本ファイル§A5.5参照）★ |

### A5.5 ★C-16③・C-41：RTLヘッダ版数追従の持越し登録★

`ysd8800_ysd8001_v0_3.sv` ヘッダのSpec参照行（L11相当）は、上位仕様がv1.2→v1.3.2へ改版されたことを受けて、**次回のRTL改版（v0.4以降）時に、参照先を`ysd8001_uart_design_v1_3_2.md`（またはその時点の最新版）へ更新すること**。現時点（v0.3のまま）ではRTLソース自体への変更は行わない。この持越し事項は、次回`ysd8800_ysd8001`のRTL改版チケットが起票された時点で、そのチケットの完了条件として明記すること（「次回」を無期限の先送りにしないための措置。`ysd8001_uart_design_v1_3_2.md` §14項目2および`review_ysd8001_uart_design_v1_3_r1_0.md` C-41に対応）。

---

*— 以上 `fpga_source_version_ledger_v1_27_addendum_v1_1.md` v1.1 —*
