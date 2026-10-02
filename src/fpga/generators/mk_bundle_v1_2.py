#!/usr/bin/env python3
# mk_bundle_v1_2.py - C-1 golden バンドル v1.2 を生成する
# 設計書 scc23_v2_08_cc_div_mod_sign_design_v0_8.md §4.10.3 手順4
# 区切り形式は v1.1 と同一（==== FILE: <名前> ====・末尾改行は展開側で付与）
import glob, os

HEADER = """# C-1 golden asm bundle  (scc23 Phase 1 / C-1)
#
# 版数     : v1.2
# 日付     : 2026-09-13
# golden基準版: scc23 v2.08
# 対象     : tests_c1 マトリクステスト（compile_ok 12ケース）
#
# ★v1.1 からの変更（golden 更新）★
#   変更理由: scc23 v2.08 の2つの変更により生成 asm が変化したため。
#     (A) _cc_div/_cc_mod の符号処理・ゼロ除算ガード追加
#         （負数除算が誤値・x%0 で実機ハングする潜在バグの修正）
#     (B) ランタイム出力の細粒度化
#         （未使用の _putchar/_getchar/_puts/_strcpy/_strcmp/_memcpy を出力しない）
#   設計書  : scc23_v2_08_cc_div_mod_sign_design_v0_8.md §3.11 / §4.10
#   レビュー: 指摘書 v6.0 A-1（golden 更新方針をレビュー事項として明示）
#   受入検証: 2段階比較で差分を分離し、全12件で受入基準を満たすことを確認
#     段階1 (A のみ) vs v2.06 golden : 追加=符号処理のみ・削除=0
#     段階2 (A+B)    vs (A のみ)     : 追加=0・削除=6関数ブロックのみ
#     → run_c1_matrix.sh 再実行で 24/24 PASS
#
# ★このファイルの目的★
#   goldens/*.golden.asm 12件を1ファイルに束ねたもの。
#   プロジェクトナレッジは tar.gz を扱えないため、テキスト1本にまとめて保存する。
#   golden は v2.08 で凍結した生成コードの実体であり ★再生成できない★
#   （ソースからのビルドは「別版コンパイラで作り直すこと」であり凍結の意味を失う）。
#
# ★展開方法★
#   python3 gen_matrix.py --unbundle c1_goldens_bundle_v1_2.txt
#
# ★golden 更新ルール（厳守・設計書 §7.5）★
#   1. golden との差分は「回帰疑い」として調査する（自動更新禁止）
#   2. 更新は仕様変更が正当と判断された場合のみ。変更理由の記録と
#      golden_version の刻み直しが必須
#   3. 無検討の上書きは禁止
#   4. Dhrystone 絶対ゲート（818/48875/P:20/21846B）と併走判定する
#      （v1.1 は 826/48405 と記載していたが、これは scc23 v2.03 時代の旧値であった。
#        v2.04 の char ロード幅是正で 819/48785 に更新され、
#        v2.08 の本改修で 818/48875 となった）
#   5. golden 更新の判断は設計レビューを経る（原則43）
#
# 区切り形式: ==== FILE: <名前> ====
#   各ファイルの内容は次の区切り行の直前までとし、末尾改行は展開側で付与する。
#   (v1.1: v1.0 は展開時に余分な空行が1行入る不具合があったため修正)

"""

files = sorted(glob.glob("goldens/*.golden.asm"))
assert len(files) == 12, "golden は12件でなければならない（実際: %d）" % len(files)

parts = [HEADER]
for f in files:
    name = os.path.basename(f)
    body = open(f, encoding="utf-8").read()
    if body.endswith("\n"):
        body = body[:-1]          # 末尾改行は展開側で付与する仕様
    parts.append("\n==== FILE: %s ====\n%s\n" % (name, body))

out = "".join(parts) + "\n==== END ====\n"
open("c1_goldens_bundle_v1_2.txt", "w", encoding="utf-8").write(out)
print("wrote c1_goldens_bundle_v1_2.txt (%d files, %d bytes)" % (len(files), len(out)))
print("NOTE: 末尾の '==== END ====' は必須。")
print("      gen_matrix.py の unbundle_goldens() はループ終了後の flush を行わないため、")
print("      END 行が無いと最終ファイル1件が失われる（v1.2 作成時に実際に発生）。")
