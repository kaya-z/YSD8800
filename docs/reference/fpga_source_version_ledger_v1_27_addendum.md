# `fpga_source_version_ledger` v1.27 追補 — 工程②.5 TKT-V10 完了

| 項目 | 内容 |
|---|---|
| 文書名 | `fpga_source_version_ledger_v1_27_addendum.md` |
| 版数 | **v1.0** |
| 作成日 | 2026-09-20 |
| 対象台帳 | `fpga_source_version_ledger_v1_27.md`（★本体は無改変★） |
| 追補理由 | 工程②.5（TKT-V10 ライトバッファ）完了に伴う RTL 版数更新 |

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
| ★1★ | ★`yuios_build_procedure` §4.14.7★ | ★RTL 17本リスト → `rtl18_v2.f`（18本）★ | ★改版必要★ |
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

*— 以上 `fpga_source_version_ledger_v1_27_addendum.md` v1.0 —*
