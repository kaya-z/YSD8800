#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# i2_taskcount_audit_v1_0.py  v1.01
# YUI OS Ph.3.5-I-2 自動検査：タスク数 8→16 化の網羅修正チェック
#
# 目的（KY38: 本番ソース無改変・別ファイル名で検査）:
#   yuios_tcb_design_v1_3.md §4.3/§4.4 が指定する「タスク数8依存箇所」の
#   #16 化が漏れなく行われ、かつタスク数無関係の #8（TCBオフセット/スタック
#   計算）を誤って #16 化していないことを機械的に判定する。
#
# 判定（PASS条件）:
#   [C1] 期待される4つのタスクループ(_sched/_sc_sched/_tc_scan/_init_tcb)の
#        ループ上限 CMPI が全て #16 である。
#   [C2] #8 を伴う CMPI [AB], #8 が1件も残っていない（タスク上限比較の#8残存ゼロ）。
#   [C3] 残存する #8 は全て許可リスト（[X + #8] オフセット / ADDI X, #8 スタック
#        計算 / コメント行）のいずれかに分類できる（未分類の#8がゼロ）。
#   [C4] MAX_TASKS EQU 16 が定義されている。
#
# 使い方:
#   python3 i2_taskcount_audit_v1_0.py <kernel.asm>
# 終了コード: PASS=0 / FAIL=1

import sys
import re

VERSION = "1.01"  # v1.01: C1偽陽性修正（ループ本体内の別用途CMPI#0誤検出を解消）

# 設計書 §4.3 が定める「タスク数依存ループ」のラベル
EXPECTED_LOOP_LABELS = ["_sched", "_sc_sched", "_tc_scan", "_init_tcb"]

# タスク数比較の検出: CMPI A,#N / CMPI B,#N （Nは比較上限）
RE_CMPI_TASK = re.compile(r"^\s*CMPI\s+[AB]\s*,\s*#(\d+)\b")
# 許可される #8（タスク数無関係）
RE_OFFSET_8  = re.compile(r"\[\s*X\s*\+\s*#8\s*\]")          # TCBオフセット saved_a
RE_ADDI_X_8  = re.compile(r"^\s*ADDI\s+X\s*,\s*#8\b")        # スタックワード消費


def strip_comment(line):
    # hasm23 のコメントは ';' 始まり
    idx = line.find(";")
    return line if idx < 0 else line[:idx]


def find_label_above(lines, idx):
    """idx 行から上方向に走査し、直近のラベル(行頭で ':' 終端ではなく
    行末が ':' を持たない hasm 形式 = 'label:' 形式)を返す。"""
    for j in range(idx, -1, -1):
        code = lines[j].rstrip("\n")
        # ラベル形式: 行頭から空白なしで始まり末尾が ':'（命令でない）
        m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*):\s*$", code)
        if m:
            return m.group(1), j + 1
    return None, None


def main():
    if len(sys.argv) != 2:
        sys.stderr.write("usage: i2_taskcount_audit_v1_0.py <kernel.asm>\n")
        return 2
    path = sys.argv[1]
    print(f"i2_taskcount_audit v{VERSION}  ---  Ph.3.5-I-2 task-count audit")
    print(f"target: {path}\n")

    with open(path, encoding="utf-8") as f:
        raw = f.readlines()

    fails = []
    warns = []

    # --- C4: MAX_TASKS EQU 16 ---
    max_tasks_val = None
    for line in raw:
        m = re.match(r"^\s*MAX_TASKS\s+EQU\s+(\d+)\b", strip_comment(line))
        if m:
            max_tasks_val = int(m.group(1))
            break
    if max_tasks_val == 16:
        print(f"[C4] PASS: MAX_TASKS EQU 16 定義あり")
    else:
        fails.append(f"[C4] MAX_TASKS が 16 でない（検出値: {max_tasks_val}）")

    # --- 全 CMPI [AB],#N を収集（コメント除去後） ---
    task_cmpi = []   # (lineno, regN, label)
    for i, line in enumerate(raw):
        code = strip_comment(line)
        m = RE_CMPI_TASK.search(code)
        if m:
            n = int(m.group(1))
            label, _ = find_label_above(raw, i)
            task_cmpi.append((i + 1, n, label))

    # --- C1: 4ループの上限が全て16 ---
    # ラップ上限は「ループラベル直後の最初の CMPI [AB],#N」である（4箇所とも
    # この構造: ラベル行の直下に CMPI が来る）。ループ本体内の別用途 CMPI #0
    # （state==DEAD 判定等）を誤って上限とみなさないよう、各ループラベルの
    # 「次の命令行が CMPI [AB],#N」のものだけを上限として採用する。
    def first_cmpi_after_label(label):
        for i, line in enumerate(raw):
            code = line.rstrip("\n")
            if re.match(rf"^{re.escape(label)}:\s*$", code):
                # ラベル直後の最初の非空・非コメント命令を探す
                for k in range(i + 1, len(raw)):
                    body = strip_comment(raw[k]).strip()
                    if body == "":
                        continue
                    m = RE_CMPI_TASK.search(body)
                    if m:
                        return k + 1, int(m.group(1))
                    return None, None      # 直後が CMPI でない
        return None, None

    print("\n[C1] タスクループ上限の検査（ラベル直後の上限CMPIのみ）:")
    for lbl in EXPECTED_LOOP_LABELS:
        lineno, n = first_cmpi_after_label(lbl)
        if lineno is None:
            fails.append(f"[C1] ループ {lbl} の上限比較 CMPI が見つからない")
            print(f"   {lbl:12s}: NOT FOUND  <- FAIL")
            continue
        mark = "OK" if n == 16 else "FAIL"
        print(f"   {lbl:12s}: line {lineno}  CMPI #{n}  [{mark}]")
        if n != 16:
            fails.append(f"[C1] {lbl} (line {lineno}) の上限が #{n}（#16 必須）")

    # --- C2: タスク上限比較に #8 が残存していないか ---
    leftover8 = [(ln, lbl) for (ln, n, lbl) in task_cmpi if n == 8]
    print("\n[C2] タスク上限比較の #8 残存検査:")
    if leftover8:
        for ln, lbl in leftover8:
            print(f"   line {ln} (label {lbl}): CMPI #8 残存  <- FAIL")
            fails.append(f"[C2] CMPI #8 残存 line {ln} (label {lbl})")
    else:
        print("   残存なし  [OK]")

    # --- C3: #8 出現の全分類（未分類ゼロ） ---
    print("\n[C3] #8 出現箇所の分類:")
    unclassified = []
    n_offset = n_addi = n_comment = n_cmpi8 = 0
    for i, line in enumerate(raw):
        if "#8" not in line:
            continue
        # #80 等の誤検出回避: #8 の直後が数字でないこと
        if not re.search(r"#8($|[^0-9])", line):
            continue
        code = strip_comment(line)
        if "#8" not in code:
            n_comment += 1          # コメント内のみ
            continue
        if RE_OFFSET_8.search(code):
            n_offset += 1
        elif RE_ADDI_X_8.search(code):
            n_addi += 1
        elif RE_CMPI_TASK.search(code) and re.search(r"#8($|[^0-9])", code):
            n_cmpi8 += 1            # C2 でFAIL済み
        else:
            unclassified.append((i + 1, code.strip()))
    print(f"   [X + #8] TCBオフセット : {n_offset} 件")
    print(f"   ADDI X, #8 スタック計算: {n_addi} 件")
    print(f"   コメント内のみ         : {n_comment} 件")
    print(f"   CMPI #8（=C2でFAIL）   : {n_cmpi8} 件")
    if unclassified:
        for ln, txt in unclassified:
            print(f"   未分類: line {ln}: {txt}  <- 要確認")
            fails.append(f"[C3] 未分類の #8 line {ln}: {txt}")
    else:
        print("   未分類 #8: なし  [OK]")

    # --- 総合判定 ---
    print("\n" + "=" * 56)
    if fails:
        print(f"I-2 自動検査: FAIL（{len(fails)} 件）")
        for x in fails:
            print("  - " + x)
        return 1
    else:
        print("I-2 自動検査: PASS")
        print("  設計書 §4.3 の4箇所が全て #16 化済み・#8 残存は無関係用途のみ")
        return 0


if __name__ == "__main__":
    sys.exit(main())
