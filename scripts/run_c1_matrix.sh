#!/bin/bash
# ============================================================
# run_c1_matrix.sh  v1.0
# scc23 Phase 1 / C-1 マトリクステスト実行スクリプト
#
# 設計書 : scc23_C1_matrix_test_design_v0_4.md
# 対応    : scc23 v2.06 以降（golden 基準版 = v2.06）
# 作成日  : 2026-08-13
#
# 判定方式（設計書 §2.2 / §2.2.1 / §2.3）:
#   compile_ok   : warning 0 / error 0 / golden asm と byte 一致
#   warning_only : warning>=1 / error 0 / golden asm と byte 一致
#                  ※ v2.06 時点では該当 0 件。分類は将来のため残置。
#   error_stop   : 非0終了 AND error メッセージに expect_error_contains を全て含む
#                  ※ 生成された壊れ asm は corrupt_asms/ へ隔離（§2.6）
#
# golden 更新は原則禁止（設計書 §7.5）。差分は回帰疑いとして調査すること。
# 本スクリプトに golden 自動更新機能は実装しない（無検討の上書き防止）。
# ============================================================

set -u

SCC="${SCC:-./scc23}"
OUTDIR="out"
GOLDDIR="goldens"
EXPDIR="expected"
CORRUPT="corrupt_asms"

mkdir -p "$OUTDIR" "$CORRUPT"

if [ ! -x "$SCC" ]; then
    echo "ERROR: compiler not found or not executable: $SCC"
    exit 2
fi

# ------------------------------------------------------------
# golden_cmp <actual.asm> <golden.asm>
#
# golden 比較はコード本体のみを対象とし、コンパイラ版数を含む
# バナー行（"; scc23 vX.XX (date)  source: ..."）を除外する。
#
# 理由（設計書 v0.5 section 2.3 / section 7.5）:
#   バナー行はコメントであり生成コードではない。これを比較対象に含めると
#   コンパイラを改版するたび golden が全件 FAIL し、毎回 golden 更新を
#   強いられる。それは section 7.5 が禁じた「安易な golden 上書き」を
#   常態化させ、本来検出すべきコード本体の回帰がバナー差分に埋もれる
#   （オオカミ少年化）。よってコード本体のみを比較する。
#
# 本チャットの Dhrystone 絶対ゲート判定でも「バナー行のみ差分＝byte-exact」
# として運用しており、それと整合する。
# ------------------------------------------------------------
golden_cmp() {
    diff -q \
        <(grep -v '^; scc23 v' "$1") \
        <(grep -v '^; scc23 v' "$2") >/dev/null 2>&1
}

echo "============================================================"
echo " C-1 matrix test  (run_c1_matrix.sh v1.0)"
echo " compiler : $("$SCC" --version 2>&1 | head -1 || true)"
"$SCC" -o /tmp/_ver_probe.asm /dev/null >/dev/null 2>&1
echo " golden   : base version = v2.06 (see expected/*.expected)"
echo "============================================================"
printf "%-16s %-13s %-13s %s\n" "NAME" "EXPECT" "ACTUAL" "RESULT"
echo "------------------------------------------------------------"

PASS=0
FAIL=0
TOTAL=0
N_OK=0
N_WO=0
N_ES=0
FAILED_LIST=""

for src in m1_*.c; do
    name="${src%.c}"
    expfile="$EXPDIR/$name.expected"
    TOTAL=$((TOTAL + 1))

    if [ ! -f "$expfile" ]; then
        printf "%-16s %-13s %-13s %s\n" "$name" "(none)" "-" "FAIL(no expected)"
        FAIL=$((FAIL + 1)); FAILED_LIST="$FAILED_LIST $name"
        continue
    fi

    # --- 期待値の読み込み ---
    expect_result=$(grep '^expect_result=' "$expfile" | head -1 | cut -d= -f2-)
    golden_version=$(grep '^golden_version=' "$expfile" | head -1 | cut -d= -f2-)
    golden_asm=$(grep '^golden_asm=' "$expfile" | head -1 | cut -d= -f2-)

    # --- コンパイル ---
    "$SCC" -o "$OUTDIR/$name.asm" "$src" >/dev/null 2>"$OUTDIR/$name.log"
    rc=$?
    nw=$(grep -c "warning:" "$OUTDIR/$name.log")
    ne=$(grep -c "error:" "$OUTDIR/$name.log")

    # --- 実測分類 ---
    if [ "$ne" -gt 0 ]; then
        actual="error_stop"
    elif [ "$nw" -gt 0 ]; then
        actual="warning_only"
    else
        actual="compile_ok"
    fi

    # --- 分類集計 ---
    case "$actual" in
        compile_ok)   N_OK=$((N_OK + 1)) ;;
        warning_only) N_WO=$((N_WO + 1)) ;;
        error_stop)   N_ES=$((N_ES + 1)) ;;
    esac

    result="PASS"
    detail=""

    # --- 分類一致判定 ---
    if [ "$actual" != "$expect_result" ]; then
        result="FAIL"
        detail="class mismatch"
    else
        case "$expect_result" in
        error_stop)
            # AND条件1: 非0終了
            if [ "$rc" -eq 0 ]; then
                result="FAIL"; detail="rc=0 (expected non-zero)"
            fi
            # AND条件2: 全ての expect_error_contains を含むこと
            if [ "$result" = "PASS" ]; then
                while IFS= read -r pat; do
                    [ -z "$pat" ] && continue
                    if ! grep -qF "$pat" "$OUTDIR/$name.log"; then
                        result="FAIL"; detail="missing error text: $pat"
                        break
                    fi
                done <<EOF
$(grep '^expect_error_contains=' "$expfile" | cut -d= -f2-)
EOF
            fi
            # 壊れ asm の隔離（§2.6）: error 時の生成物は後続工程へ渡さない
            if [ -f "$OUTDIR/$name.asm" ]; then
                mv -f "$OUTDIR/$name.asm" "$CORRUPT/$name.asm"
            fi
            ;;
        compile_ok|warning_only)
            # golden byte 一致（主判定・§2.3）
            if [ -z "$golden_asm" ] || [ ! -f "$golden_asm" ]; then
                result="FAIL"; detail="golden not found: $golden_asm"
            elif ! golden_cmp "$OUTDIR/$name.asm" "$golden_asm"; then
                result="FAIL"; detail="golden byte mismatch"
            fi
            # golden 基準版の確認（V4 相当）
            if [ "$result" = "PASS" ] && [ "$golden_version" != "v2.06" ]; then
                result="FAIL"; detail="golden_version=$golden_version (expected v2.06)"
            fi
            ;;
        esac
    fi

    if [ "$result" = "PASS" ]; then
        PASS=$((PASS + 1))
        printf "%-16s %-13s %-13s %s\n" "$name" "$expect_result" "$actual" "PASS"
    else
        FAIL=$((FAIL + 1)); FAILED_LIST="$FAILED_LIST $name"
        printf "%-16s %-13s %-13s %s\n" "$name" "$expect_result" "$actual" "FAIL ($detail)"
    fi
done

echo "------------------------------------------------------------"
echo "Result: $PASS/$TOTAL PASS   (FAIL=$FAIL)"
echo ""
echo "actual class distribution:"
echo "  compile_ok   : $N_OK"
echo "  warning_only : $N_WO   (v2.06 時点で 0 件が正常。分類は将来のため残置)"
echo "  error_stop   : $N_ES"

if [ "$FAIL" -ne 0 ]; then
    echo ""
    echo "FAILED:$FAILED_LIST"
    echo ""
    echo "!! golden 差分が出た場合、安易に golden を上書きしないこと（設計書 §7.5）。"
    echo "!! 原則は「回帰疑いとして調査」。仕様変更が正当な場合のみ、変更理由を記録し"
    echo "!! golden_version を刻み直したうえで設計レビューを経て更新すること。"
    exit 1
fi

echo ""
echo "ALL PASS."
exit 0
