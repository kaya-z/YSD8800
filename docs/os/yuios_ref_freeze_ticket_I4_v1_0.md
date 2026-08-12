# yuios_road2 リファレンス凍結票 v1.0

- 発行日: 2026-07-29
- 発行工程: V8-b Pre-5（kernel_v12_8_migration_design v1.2 §5 Pre-5）
- 発行者: Claude（開発担当）
- 目的: kernel v12.8 化に伴い、リファレンスバイナリを I3 → I4 に切替。旧 I3 は前版情報欠落防止のためアーカイブ保持。
- 判定: **AC-3 完了**（新リファレンス凍結・旧リファレンス退避リネーム・ハッシュ記録・ビルド時ツール版数一覧記録・KERN_SRC 版数記録すべて完了）

---

## 1. 現用リファレンス（新・I4）

| 項目 | 値 |
|---|---|
| ファイル名 | `yuios_ref_road2_I4.bin` |
| サイズ | **56,416 バイト** |
| MD5 | `7a6a5b87afb1ef9f413a7d0c1360e706` |
| 由来 | kernel v12.8 版でビルド（Pre-3 実測分の複製） |
| 凍結日 | 2026-07-29 |
| 有効性 | **現用**（Makefile v1.2 の REF_BIN 更新は Pre-6 で実施予定） |
| 新 AC-1 適合 | ✅ TCR-ACK パターン `21102300230190fc` = **1 hit**（offset $003D） |

## 2. 退避リファレンス（旧・I3_archived）

| 項目 | 値 |
|---|---|
| ファイル名 | `yuios_ref_road2_I3_archived.bin` |
| サイズ | **56,416 バイト** |
| MD5 | `a1f1001fe96d9c2e7b4db8e47d4046e4` |
| 由来 | kernel v12.7 版でビルド（Pre-3 実測分の複製） |
| 退避日 | 2026-07-29 |
| 有効性 | **参考保持**（比較検証用・現用ビルドの対象外） |
| 新 AC-1 適合 | ❌ TCR-ACK パターン `21102300230190fc` = **0 hit**（v12.7 由来のため当然） |

## 3. 新旧リファレンスの差分

- **サイズ**: 両者とも **56,416 バイト**（`.org` パディング吸収によりトータルサイズは同一）
- **内容差**: **271 バイト**（`cmp -l yuios_ref_road2_I4.bin yuios_ref_road2_I3_archived.bin | wc -l` の実測）
- **差分開始オフセット**: $003D（v12.8 の TCR-ACK 8B 挿入位置）
- **差分の意味**: v12.8 の TCR-ACK 命令 8B が offset $003D に挿入され、その後のバイト列が 8B シフト。以降 264B の連鎖ずれで合計 271B の差分（$003D + 8 + 264 - オーバーラップ）。

**サイズ同一・内容差**という特殊条件のため、**ハッシュ値照合が識別の唯一の手段**（AC-3 補記の必然性が実例で立証された）。

## 4. ビルド時ツール版数一覧

Pre-0（2026-07-29）でソースから再ビルドしたツール群。**両リファレンスは同一ツール群で生成**（KERN_SRC のみ差異）。

| ツール | 版数 | ソースファイル | ソース MD5 | バイナリ MD5 |
|---|---|---|---|---|
| Force | v1.5 | force_v1_5.c | 83cdfd15904c062a6b3f264676aa6705 | 51b31b3f6f5a833735a38650b8e9da15 |
| hasm23 | v1.04 | hasm23_v1_04.c | bd49d6d194c596f62e51fca66e6637b4 | 3ac0ee3a7737e2f244635d13cb0c1044 |
| lnk23 | v2.01 | lnk23_v2_01.c | c72b05af72efde59de4431cc3b3d3b95 | c4cb3f8a501092e3a6ead2724d61a01f |
| scc23 | v2.04 | scc23_v2_04.c | 9c2beacaaccd2dd08711c3b35401ee31 | 27fd90be7e9334bee021dd7d66e01d94 |
| emu23 | v1.11 | emu23_v111.c | feb5a8911c20208bf4542d3b86a4f6ed | 7c07e676123aae5eba8eb40f359eff8a |

**起動バナー実測**（Pre-0 verify log 参照）：
- `Force v1.5`
- `hasm23 v1.04 (2026-06-20) for YSD8800 ISA2.3`
- `lnk23 - YSD8800 ISA2.3 Linker v2.01`
- `scc23 v2.04 (2026-07-26) for YSD8800 ISA2.3`
- `emu23 v1.11 (2026-07-18) for YSD8800 ISA2.3`

## 5. 入力ソース版数一覧

### 5.1 新リファレンス I4 のビルド構成

| ファイル | 用途 | MD5 |
|---|---|---|
| **kernel_v12_8.asm** | **kernel 主体（V5 TCR-ACK 対応）** | **80e7d1517ad63b68e5c31fa927ed0cd2** |
| kernel_forth_v0_10_18.fs | Forth コード | 00c98b25c5ac834d4fc16281ca1efc66 |
| ysd8800_kern.tgt | ターゲット定義（v0.6 由来） | 2fed74d837cde610d349365555c22ba3 |
| ysd8800.prim | Force プリミティブ定義 | 17785c6c54a855857f22b7988b3180a1 |
| mk_post1.sh | ポスト処理スクリプト | 5d013aee981a734a7d028c72c8b159d5 |
| mkfs_yuifs.py | ファイルシステム作成（v1.1 由来） | c0143a7b6832b4e12170c1bbd67febdd |
| Makefile | ビルドシステム（v1.2） | e54198dc1018c5d33845cd3f8a7d895f |

### 5.2 退避リファレンス I3_archived のビルド構成

I3_archived は新リファレンスと同一ツール群・同一入力ソース群で構成、**唯一 KERN_SRC を kernel_v12_7.asm に切替**して生成。

| ファイル | MD5 |
|---|---|
| **kernel_v12_7.asm**（差分の唯一の元） | **a0d5c51f2014b62d5c1dbf6e69a1a34a** |

その他の入力ソース・Makefile・ツール群はすべて I4 と同一。

## 6. 検証コマンド（再現性確認用）

以下のコマンド列で凍結票の内容が再現できる：

```bash
# 新リファレンス I4 の照合
md5sum yuios_ref_road2_I4.bin
# 期待値: 7a6a5b87afb1ef9f413a7d0c1360e706

# 退避リファレンス I3_archived の照合
md5sum yuios_ref_road2_I3_archived.bin
# 期待値: a1f1001fe96d9c2e7b4db8e47d4046e4

# 新 AC-1（TCR-ACK パターン）の適用
od -An -tx1 -v yuios_ref_road2_I4.bin | tr -d ' \n' | grep -oE '21102300230190fc' | wc -l
# 期待値: 1

od -An -tx1 -v yuios_ref_road2_I3_archived.bin | tr -d ' \n' | grep -oE '21102300230190fc' | wc -l
# 期待値: 0

# サイズ確認
stat -c %s yuios_ref_road2_I4.bin
stat -c %s yuios_ref_road2_I3_archived.bin
# 期待値: いずれも 56416

# 差分バイト数
cmp -l yuios_ref_road2_I4.bin yuios_ref_road2_I3_archived.bin | wc -l
# 期待値: 271
```

## 7. AC-3 判定

kernel_v12_8_migration_design v1.2 §3.1 AC-3 の完了判定：

- ✅ 新リファレンス `yuios_ref_road2_I4.bin` が凍結された
- ✅ ファイル名・ハッシュ値・ビルド時 KERN_SRC 版数が明記された凍結票が作成された（本書）
- ✅ v12.7 由来 `yuios_ref_road2_I3.bin` は `yuios_ref_road2_I3_archived.bin` にリネーム保持された
- ✅ 新旧リファレンスがサイズ同一（56,416B）でも内容が異なるため、ハッシュ値の記録は必須（AC-3 補記）→ 本書 §1・§2 に MD5 明記済

**AC-3 完了**。Pre-6（Makefile v1.2 の REF_BIN 更新・regress 実行）に進める。

## 8. 変更履歴

| 版 | 日付 | 内容 |
|---|---|---|
| v1.0 | 2026-07-29 | 初版発行。V8-b Pre-5 完了時点の凍結票。 |
