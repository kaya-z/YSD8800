# `yuios_build_procedure` v1.20 追補 — 工程②.5 反映

| 項目 | 内容 |
|---|---|
| 文書名 | `yuios_build_procedure_v1_20_addendum.md` |
| 版数 | **v1.0**（手順書本体を ~~v1.19~~ → **v1.20** 相当へ更新する追補） |
| 作成日 | 2026-09-20 |
| 対象 | `yuios_build_procedure_v1_19.md`（★本体は無改変★） |
| 改版理由 | ★(1) §4.14.7 の RTL リストが 17 本のままで wbuf が欠落 (2) §4.14.8 の絶対ゲート値が旧ツールチェーンのもの★ |

★本書は本体手順書の**追記**である。本体の既存節は一切変更していない（原則121）。★
★次回の本体改版時に §4.14.7・§4.14.8 へ取り込むこと。★

---

## §C1. ★§4.14.7 の改訂 — RTL リストは 18 本になった★

### C1.1 何が問題か

★本体 §4.14.7 の現行リスト（17 本）には `ysd8800_wbuf_*.sv` が無い。★
★工程②.5 でライトバッファを導入して以降、このリストで組むと次が起きる。★

| WBUF_EN | 結果 |
|---|---|
| 0（既定） | ★`membus_v0_15` が `ysd8800_wbuf_v0_3` を参照するため `Unknown module type` で**停止する**★ |

★幸い本件は**沈黙しない**（v1.17 が是正した cache 欠落とは違い、リンクエラーになる）。★
★ただし `membus` を旧版のままにすると沈黙する。★
★実際に 2026-09-20 の前工程で、`membus_v0_13` が実在しない `ysd8800_wbuf_v0_1` を
参照していたため **wbuf v0.2 が一度も結合実行されていなかった**事例がある。★

> ★版数は毎工程 `fpga_source_version_ledger` の最新版（および追補）と突合すること。★

### C1.2 ★現行リスト（18 本・工程②.5 時点／2026-09-20 実測でビルド・実走確認済）★

```
ysd8800_decoder_v0_1.sv
ysd8800_cpu_v0_1_FIXED.sv
ysd8800_alu_v0_1.sv
ysd8800_regfile_v0_1.sv
ysd8800_v5_membus_v0_15.sv       ← ★②.5 で v0.14→v0.15（案G）★
ysd8800_cache_v0_6.sv            ← 据置（②.5 は無改修）
ysd8800_wbuf_v0_3.sv             ← ★【v1.20 追加】②.5 の本体★
ysd8800_mmu_v0_1.sv
ysd8800_addr_decoder_v0_1.sv
ysd8800_cdc_bridge_v0_5.sv       ← 据置
ysd8800_psram_ctrl_v0_4.sv       ← ★②.5 で v0.3→v0.4（案D）★
ysd8800_mmio_stub_v0_9.sv        ← ★CEN=1 で測る場合は _cen1_poc 版に差替（§4.15.4）★
ysd8800_ysd8001_v0_1.sv
ysd8800_ysd8002_v0_3.sv
ysd8800_ysd8003_v0_4.sv
ysd8800_ysd8004_v0_1.sv
tb_cpu_v8b_prod_v0_4_mon_poc.sv  ← ★YUI OS 用。v0.2 は使用禁止（R-8）★
sd_spi_model_v0_3_poc.sv
```

★成果物として `rtl18_v2.f`（md5 `8c967dc362685491886ac0ad5938ba38`）を登録した。★
★ただし★★`.f` は毎回本節を見て起こし直すこと。既存 `.f` を無検証で使わない★★
（本体 §4.14.7 の警告は継続して有効）。★

### C1.3 ★エラボレート順の追加注意（2026-09-20 実測）★

★`ysd8800_decoder_v0_1.sv` は `package ysd8800_idec_pkg` を含むため、
**TB よりも前**に置く必要がある。★
★本体 §4.14.7 は「`decoder`／`regfile`／`alu` を先頭側に置くこと」としているが、
TB を先頭に置いたリストでは `ysd8800_cpu_v0_1_FIXED.sv:233: syntax error` で停止する。★
★`import ysd8800_idec_pkg::*;` はパッケージ定義より後でなければ解決できない。★

> ★「先頭側」ではなく★★「`decoder` を最初の1本にする」★★と読むこと。★

### C1.4 WBUF_EN の切替（`-P` は効かない）

```bash
# ★-P は効かない。_poc ファイル方式で切り替える★
sed "s/parameter bit WBUF_EN = 1'b0/parameter bit WBUF_EN = 1'b1/" \
    ysd8800_v5_membus_v0_15.sv > ysd8800_v5_membus_v0_15_wbuf1_poc.sv
diff ysd8800_v5_membus_v0_15.sv ysd8800_v5_membus_v0_15_wbuf1_poc.sv   # ★1箇所であることを確認（KY102）★
```

★CEN=1 の `mmio_stub` 生成（§4.15.4）と同じ作法である。★
★生成後に `diff` で 1 箇所だけ変わったことを必ず確認する。★

---

## §C2. ★§4.14.8 の改訂 — 絶対ゲートの値が変わった★

★本体 §4.14.8 および本体各所の `819 / 48,785` は、
**scc23 v2.07 / lnk23 v2.01 時代の値**であり現行ツールでは再現できない。★

| ゲート | ★現行（正・2026-09-20 実測）★ | 旧（本体に散在・使用禁止） |
|---|---|---|
| `dhry_final.bin` md5 | ★`e185df32a1bf67da602c1924f5ec8cc3`★ | ~~`e7e9836f…`~~ |
| `dhry_o0.hex` md5 | ★`4c782566c45be08e3dfe219bc49c85f7`★ | ~~`932cc3e9…`~~ |
| emu23 回帰 | ★818 / 48,875 / P:20★ | ~~819 / 48,785~~ |
| RTL CEN=1 / WBUF=0 `C_total` | ★613,237★ | ~~612,074~~ |

★サイズ 21,846 B は不変。★
★`-O1` 側（`dhry_o1.hex`）は本工程では未測定であり、旧値のままにしてある。★
★使用する場合は取り直すこと。★

詳細は `tool_version_ledger_v1_30_addendum.md` §B2／§B3。

---

## §C3. ★工程②.5 の測定手順（再現用）★

```bash
# 1) ツールチェーン
gcc -O2 -w -o scc23 scc23_v2_08.c ; gcc -O2 -w -o hasm23 hasm23_v1_04.c
gcc -O2 -w -o lnk23 lnk23_v2_02.c ; gcc -O2 -w -o emu23 emu23_v2_16.c
./scc23 -v 2>&1 ; ./lnk23 -v ; ./hasm23 ; ./emu23      # ★構文がツールごとに違う★

# 2) Dhrystone -O0 とゲート確認
make -f Makefile_v1_4 dhrystone
md5sum dhry_final.bin                       # → e185df32a1bf67da602c1924f5ec8cc3
timeout 60 ./emu23 dhry_final.bin -q        # → 818 / 48875 / P:20

python3 bin2hex.py dhry_final.bin dhry_o0.hex
python3 mkfs_yuifs_v1_1.py sd_image.bin --size-kb 8 --add-file HELLO.TXT
python3 bin2hex.py sd_image.bin sd_image.hex
mkdir -p run ; cp dhry_o0.hex run/dhry_final.hex ; cp sd_image.hex run/
md5sum run/dhry_final.hex                   # → 4c782566c45be08e3dfe219bc49c85f7 ★起動前に必ず★

# 3) CEN=1 / WBUF_EN=1 の poc 生成（各1行差分を diff で確認：KY102）
sed "s/ccr_cen_r         <= 1'b0;/ccr_cen_r         <= 1'b1;/" \
    ysd8800_mmio_stub_v0_9.sv > ysd8800_mmio_stub_v0_9_cen1_poc.sv
sed "s/parameter bit WBUF_EN = 1'b0/parameter bit WBUF_EN = 1'b1/" \
    ysd8800_v5_membus_v0_15.sv > ysd8800_v5_membus_v0_15_wbuf1_poc.sv

# 4) ビルドと実走
apt-get install -y iverilog                 # ★毎セッション必要（R-1）★
iverilog -g2012 -s <TB名> -o out.vvp -f rtl18_v2.f
cd run && nohup timeout 1200 vvp ../out.vvp > run.log 2>&1 &
```

★`vvp` は 1 回 2〜10 分かかる。bash の単発実行上限（300 秒）を超えるため
`nohup timeout 1200 vvp ... &` でバックグラウンド実行し `sleep` でポーリングすること。★

### C3.1 ★MAX_CYCLES の目安（2026-09-20 実測）★

| 構成 | 完了サイクル | 必要な MAX_CYCLES |
|---|---|---|
| CEN=1 / WBUF=1 | 551,433 | 1,000,000 で足りる |
| CEN=1 / WBUF=0 | 613,237 | 1,000,000 で足りる |
| ★CEN=0★ | ★1,072,016〜1,084,663★ | ★1,000,000 では**足りない**。3,000,000 を使う★ |

★CEN=0 側を 1,000,000 で回すと `[TIMEOUT] MAX_CYCLES reached` となり、
性能値が取れないだけでなく ★G-M の read_checked が途中で切れる★。★

---

## §C4. 改版履歴（本体へ取り込む際の記載案）

| 版 | 日付 | 内容 |
|---|---|---|
| ★v1.20★ | ★2026-09-20★ | ★【工程②.5 TKT-V10 の反映】①§4.14.7 の RTL リストを 17本→**18本**へ（`wbuf_v0_3` 追加・`membus_v0_15`／`psram_ctrl_v0_4` へ追従）。②★`decoder` は「先頭側」でなく**最初の1本**でなければ `idec_pkg` が解決できない★旨を §4.14.7 に明記（実測で判明）。③WBUF_EN の `_poc` 生成手順を追加（`-P` は効かない）。④§4.14.8 の絶対ゲートを現行値へ改訂（818/48,875・新 md5・C_total 613,237）。★旧値は取消線で保持★。⑤§C3.1 に MAX_CYCLES の目安を新設（CEN=0 は 1M では足りない）。v1.19 までの記述は削除せず保持★ |

---

*— 以上 `yuios_build_procedure_v1_20_addendum.md` v1.0 —*
