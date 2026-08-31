# yuios_road2 リファレンス凍結票 v1.0（I5）

- 発行日: 2026-08-12
- 発行工程: D-3 対応（Makefile KERN_SRC 追従漏れ是正）
- 発行者: Claude（開発担当）
- 目的: kernel v12.8 → v12.11（TKT-01/02/03/04 反映・Phase A 確定版）への
        切替に伴い、リファレンスバイナリを I4 → I5 に切替。旧 I4 は
        前版情報欠落防止のためアーカイブ保持。
- 判定: **D-3 対応完了**（新リファレンス凍結・旧リファレンス退避リネーム・
        ハッシュ記録・ビルド時ツール版数一覧記録・KERN_SRC 版数記録
        すべて完了）
- 関連: HANDOVER_CHAT134.md 記載の D-3（重要度「中」・B-5 で対処予定）。
        本件は独立修正としてかやぬまさんの承認のもと B-5 に先行して実施。

---

## 1. 現用リファレンス（新・I5）

| 項目 | 値 |
|---|---|
| ファイル名 | `yuios_ref_road2_I5.bin` |
| サイズ | **56,416 バイト** |
| MD5 | `599a7f9d1ebf103f81f58450ea1b6491` |
| 由来 | kernel v12.11 版でビルド（TKT-01〜04 反映・Phase A 確定版） |
| 凍結日 | 2026-08-12 |
| 有効性 | **現用**（Makefile v1.3 で REF_BIN 更新済） |
| 3点照合 | ✅ kernel_v12_11.asm ヘッダ記載値と一致<br>✅ yuios_paired_impl_ledger_v1_0.md 記載値と一致<br>✅ 本凍結票の実測値と一致 |
| TCR-ACK パターン適合 | ✅ `21102300230190fc` = **1 hit**（I4 から継続・V5 方式のまま） |

## 2. 退避リファレンス（旧・I4_archived）

| 項目 | 値 |
|---|---|
| ファイル名 | `yuios_ref_road2_I4_archived.bin` |
| サイズ | **56,416 バイト** |
| MD5 | `7a6a5b87afb1ef9f413a7d0c1360e706` |
| 由来 | kernel v12.8 版でビルド（V5 TCR-ACK 対応版） |
| 退避日 | 2026-08-12 |
| 有効性 | **参考保持**（比較検証用・現用ビルドの対象外） |

※ I3_archived（kernel v12.7 版・md5=a1f1001fe96d9c2e7b4db8e47d4046e4）も
   引き続き参考保持（yuios_ref_freeze_ticket_I4_v1_0.md 参照）。

## 3. 新旧リファレンスの差分

- **サイズ**: I4・I5 とも **56,416 バイト**（`.org` パディング吸収により
  トータルサイズは同一）
- **内容差**: kernel v12.8 → v12.11 間の TKT-01（UART受信リングバッファ修正）・
  TKT-02・TKT-03（ICRNL関連）・TKT-04（コンテキストスイッチ A/B レジスタ
  復元欠落修正）を反映した差分。具体的差分バイト数は本票発行時点で
  未実測（必要に応じて `cmp -l` で追加実測可能）。
- **差分の意味**: TKT-04 の修正は SYSCALL 保存経路 4 箇所（M-1〜M-4）に
  saved_a/saved_b 初期化を追加し、_sc_found（M-5）で復元を追加したもの。
  詳細は `kernel_v12_11.asm` ヘッダコメントおよび
  `yuios_ctxsw_abreg_restore_design_v0_3.md` を参照。

## 4. ビルド時ツール版数一覧

本票発行時点（2026-08-12）でソースから再ビルドしたツール群。

| ツール | 版数 | ソースファイル | ソース MD5 | バイナリ MD5 |
|---|---|---|---|---|
| Force | v1.5 | force_v1_5.c | 83cdfd15904c062a6b3f264676aa6705 | f0dbc3fc5a4635ce9ddd116d5500ffc4 |
| hasm23 | v1.04 | hasm23_v1_04.c | bd49d6d194c596f62e51fca66e6637b4 | 23f572954c881badb0726b6fd203be4a |
| lnk23 | v2.01 | lnk23_v2_01.c | c72b05af72efde59de4431cc3b3d3b95 | 3953179bcf1b324ee0e81f7ab07940f1 |
| scc23 | v2.05 | scc23_v2_05.c | （未記録・regress実行時ビルド） | （未記録） |
| emu23 | v1.12 | emu23_v1_12.c | （未記録・regress実行時ビルド） | （未記録） |

**起動バナー実測**（本票発行時 verify/regress ログ参照）：
- `Force Forth Cross Compiler v1.5`
- `hasm23 v1.04 (2026-06-20) for YSD8800 ISA2.3`
- `lnk23 - YSD8800 ISA2.3 Linker v2.01`
- `scc23 v2.05 (2026-08-02) - compiling ...`

※ ツールバイナリ MD5 は force/hasm23/lnk23 のバイナリ MD5であり、I4 凍結票
  （Pre-0 時点・force v1.5 等）とはビルド環境の差異により値が異なりうる。
  ソース MD5 は I4 凍結票と完全一致しており、ツールソース自体に変更は
  ないことを確認済み。

## 5. 入力ソース版数一覧

### 5.1 新リファレンス I5 のビルド構成

| ファイル | 用途 | MD5 |
|---|---|---|
| **kernel_v12_11.asm** | **kernel 主体（TKT-01〜04 反映・Phase A 確定版）** | **a67d3b131ff690594713740952d4f348** |
| kernel_forth_v0_10_18.fs | Forth コード | 00c98b25c5ac834d4fc16281ca1efc66 |
| ysd8800_kern.tgt | ターゲット定義（v0.6 由来） | 2fed74d837cde610d349365555c22ba3 |
| ysd8800.prim | Force プリミティブ定義 | 17785c6c54a855857f22b7988b3180a1 |
| mk_post1.sh | ポスト処理スクリプト | 5d013aee981a734a7d028c72c8b159d5 |
| Makefile | ビルドシステム（v1.3・本改版） | ba6cfdd88eed24dd4908335cdb867b1e |

※ kernel_forth_v0_10_18.fs / ysd8800_kern.tgt / ysd8800.prim / mk_post1.sh は
  I4 のビルド構成（yuios_ref_freeze_ticket_I4_v1_0.md §5.1）から**不変**。
  唯一 KERN_SRC のみ kernel_v12_8.asm → kernel_v12_11.asm に切替。

### 5.2 I4 との相違点

I5 は I4 と同一ツール群・同一入力ソース群（kernel_forth/tgt/prim/mk_post1）で
構成、**唯一 KERN_SRC を kernel_v12_11.asm に切替**して生成。

## 6. 検証コマンド（再現性確認用）

以下のコマンド列で凍結票の内容が再現できる：

```bash
# 新リファレンス I5 の照合
md5sum yuios_ref_road2_I5.bin
# 期待値: 599a7f9d1ebf103f81f58450ea1b6491

# サイズ確認
stat -c %s yuios_ref_road2_I5.bin
# 期待値: 56416

# 新 AC-1（TCR-ACK パターン）の適用（I4 から継続確認）
od -An -tx1 -v yuios_ref_road2_I5.bin | tr -d ' \n' | grep -oE '21102300230190fc' | wc -l
# 期待値: 1

# make による通しビルド・検証
make clean && make verify
# 期待値: VERIFY OK

make regress
# 期待値: Dhrystones/sec=819 / cycles=48785 / P:20
```

## 7. D-3 判定

HANDOVER_CHAT134.md 記載の D-3 の完了判定：

- ✅ 新リファレンス `yuios_ref_road2_I5.bin` が凍結された
- ✅ ファイル名・ハッシュ値・ビルド時 KERN_SRC 版数が明記された凍結票が
  作成された（本書）
- ✅ 旧 `yuios_ref_road2_I4.bin` は `yuios_ref_road2_I4_archived.bin` に
  リネーム保持された（前版情報欠落防止・KY41）
- ✅ Makefile を v1.2 → v1.3 に改版（KERN_SRC 切替・REF_BIN 切替・
  改版履歴追記・旧情報保持）
- ✅ `make verify` で VERIFY OK（クリーンビルドと I5 の md5 完全一致）
- ✅ `make regress` で Dhrystone 絶対ゲート 819/48785/P:20 維持を確認
- ✅ 3点照合（kernel_v12_11.asm ヘッダ値／
  yuios_paired_impl_ledger_v1_0.md 記載値／本票実測値）すべて一致

**D-3 対応完了**。

## 8. 変更履歴

| 版 | 日付 | 内容 |
|---|---|---|
| v1.0 | 2026-08-12 | 初版発行。D-3 対応（KERN_SRC 追従漏れ是正）完了時点の凍結票。 |
