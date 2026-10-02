## ★§31 プロジェクトナレッジ整理（第2回）に伴うFPGA検証資産の廃棄（v1.26 新設）★

### 31.1 背景

工程②-B（キャッシュRTL開発）完了に伴うプロジェクトナレッジ容量逼迫（85%）を受け、
`knowledge_relocation_plan_v2_1.md`（承認済・2026-09-10）に基づき、旧世代のFPGA検証資産49本を
プロジェクトナレッジから削除した。

### 31.2 削除方針

削除対象は「現行の上位TB・RTLに機能面で包含される旧世代検証資産」に限定した。
★Google Driveへの退避は行わない★（Drive上の`.sv`/`.py`はMarkdownエスケープにより
識別子・インデント・比較演算子が破壊され、二度と参照できなくなることが実証されている。
`knowledge_relocation_plan_v1_0.md` §3／`v2_1.md` §7-R2〜R4参照）。
実体はかやぬまさんのローカル環境にのみ保管される。

### 31.3 削除ファイル一覧（FPGA検証資産49本 / 445,155 B）

#### V1/V2 CPU単体検証（13本・上位互換：`tb_cpu_v8e_dhry_v0_3.sv`が結合状態で継続回帰）

| ファイル | 容量 | 削除理由 |
|---|---:|---|
| `tb_cpu_fetch_v0_1.sv` | 3,789 B | CPUコア20フェーズ連続無改修 |
| `tb_cpu_mem_v0_1.sv` | 5,325 B | 同上 |
| `tb_cpu_byte_v0_1.sv` | 4,915 B | 同上 |
| `tb_cpu_memalign_v0_1.sv` | 3,072 B | 同上 |
| `tb_cpu_iret_v0_1.sv` | 4,403 B | 同上 |
| `tb_cpu_irq_v0_1.sv` | 6,656 B | 同上 |
| `tb_cpu_irq_iret_v0_1.sv` | 6,861 B | 同上 |
| `tb_cpu_align_irq_v0_1.sv` | 8,909 B | 同上 |
| `tb_cpu_v2a_v0_1.sv` | 6,144 B | 同上 |
| `tb_cpu_v2c_v0_1.sv` | 9,216 B | 同上 |
| `tb_cpu_v2d_v0_1.sv` | 11,264 B | 同上 |
| `tb_cpu_v2e_v0_1.sv` | 12,186 B | 同上 |
| `gen_v2_vectors.py` | 7,475 B | 対応TB群の生成器 |

#### V3/V3.5検証（14本・上位互換：`tb_psram_ctrl_v0_3.sv`／`tb_bridge_psram_20bit_v0_3.sv`／`tb_psram_equiv_v0_1.sv`が据置・現行）

| ファイル | 容量 |
|---|---:|
| `tb_cpu_v3_v0_1.sv` | 6,861 B |
| `tb_cpu_v3mem_v0_1.sv` | 5,734 B |
| `tb_cdc_bridge_v0_1.sv` | 7,885 B |
| `tb_psram_ctrl_v0_1.sv` | 3,072 B |
| `tb_bridge_psram_integ_v0_1.sv` | 3,891 B |
| `tb_addr_decoder_v0_1.sv` | 5,939 B |
| `tb_mmio_mmureg_v0_1.sv` | 7,885 B |
| `tb_mmu_v0_1.sv` | 5,222 B |
| `tb_cpu_v35mmu_v0_1.sv` | 7,373 B |
| `tb_bridge_psram_20bit_v0_1.sv` | 7,475 B |
| `gen_v3_mem_vectors.py` | 6,349 B |
| `gen_v3_boundary_vectors.py` | 5,837 B |
| `gen_v35_mmu_vectors.py` | 10,752 B |
| `build_v35.sh` | 943 B |

#### V4 UART検証（8本・上位互換：`tb_cpu_v8e_dhry_v0_3.sv`のUART TX判定`tx_count==9`で継続確認）

| ファイル | 容量 |
|---|---:|
| `tb_cpu_v4uart_v0_2.sv` | 23,859 B |
| `tb_ysd8001_v0_1.sv` | 13,619 B |
| `gen_v4_uart_vectors.py` | 9,421 B |
| `gen_v4_uart_c_vectors.py` | 11,264 B |
| `mk_v4_regress_tb.py` | 2,458 B |
| `build_v4.sh` | 1,331 B |
| `t1_noack.asm` | 2,867 B |
| `t2_ack.asm` | 2,867 B |

#### V5/V6検証（10本・上位互換：`ysd8800_ysd8003_v0_4.sv`＋V8-b/V8-e系TBがSD経由ブートまで含めて検証）

| ファイル | 容量 |
|---|---:|
| `tb_cpu_v5timer_short.sv` | 13,619 B |
| `tb_cpu_v6mask.sv` | 12,390 B |
| `tb_cpu_v6sdread.sv` | 11,059 B |
| `tb_ysd8003_v0_3.sv` | 12,186 B |
| `v5t_ack.asm` | 3,379 B |
| `v5t_noack.asm` | 3,072 B |
| `v6t_mask.asm` | 2,560 B |
| `v6t_sdread.asm` | 3,482 B |
| `build_v5en.sh` | 1,229 B |
| `sd_spi_model_v0_3_poc.sv` | 13,312 B |

#### V8-b prod旧世代（5本・★派生系譜を実ファイルで確認済★：`tb_cpu_v8e_dhry_v0_3.sv`コメントに「以下は派生元 `tb_cpu_v8b_prod_v0_3.sv` の記述」と明記）

| ファイル | 容量 |
|---|---:|
| `tb_cpu_v8b_prod_v0_2.sv` | 21,914 B |
| `tb_cpu_v8b_prod_v0_3.sv` | 23,859 B |
| `tb_v8b_pcprobe_poc.sv` | 22,323 B |
| `tb_v8b_tcbprobe_poc.sv` | 24,781 B |
| `measure_cpi_poc.sh` | 2,458 B |

#### ②-B初期段階・段4/段5完了分（2本・§22/§24で「陽性対照として資産保存」と記載あるが、現行`ysd8800_cache_v0_6.sv`が該当段階を包含）

| ファイル | 容量 |
|---|---:|
| `tb_cache_wt_poc.sv` | 11,162 B |
| `tb_cache_flush_poc.sv` | 19,251 B |

**小計：49本 / 445,155 B**

⚠️ 上記49本に加え、`cache_study_handover_v1_0.md`（10,240B・§19.4に単独参照禁止と自己注記済）と
HANDOVER旧世代文書（当初廃棄候補としたが、かやぬまさんの判断により据置に変更）を含めた
`knowledge_relocation_plan_v2_1.md`全体の廃棄合計は53本・455,395Bである。
本台帳（FPGAソース台帳）の対象範囲であるFPGA検証資産は49本・445,155Bであり、
残る4本（文書・HANDOVER）は`tool_version_ledger`側または対象外として扱う。

### 31.4 削除確認

`project_knowledge_search`により、削除対象のコード本文が検索結果から消失していることを確認した
（2026-09-10）。台帳（本ファイル）自体の§9〜§16の登録状況欄（「✅登録済」等）は
削除作業と連動して自動更新されないため、当時の記録として温存し、本§31を削除の正式な記録とする。

### 31.5 CPUコア無改修の継続

本削除作業はFPGAソースの内容には一切影響しない（検証資産の整理のみ）。
`ysd8800_cpu_v0_1_FIXED.sv`（v0.5.8）は引き続き無改修であり、
**20フェーズ連続無改修**の記録（§29.1）に変更はない。

### 31.6 変更履歴

| 版 | 日付 | 内容 |
|---|---|---|
| v1.26 | 2026-09-10 | §31新設。`knowledge_relocation_plan_v2_1.md`承認・実施に伴い、V1〜V8-b旧世代検証資産49本（445,155B）をプロジェクトナレッジから削除した記録。RTL本体・md5・CPUコア版数（v0.5.8・20フェーズ連続無改修）は無変更。Drive退避は行わず、実体はローカルのみに保管。 |

