#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""
kaizen2_check.py  Version: 1.2  (2026-09-03)
YSD8800 / YUI OS  kaizen2.txt 整合検査スクリプト

目的:
  kaizen2.txt への追記が規約どおり行われたかを機械的に検査する。
  人間（および Claude）の注意力に依存させないための防壁である。
  （原則52/55 の思想を文書に適用したもの）

検査項目（4件）:
  C-1 収録漏れ   : 見出しのある原則/KY が付録B 索引に載っているか
                   索引に載っている番号に見出しが実在するか（双方向）
  C-2 二重発番   : 同一番号の見出しが2件以上ないか
                   （枝番 -A/-B/b は既知の例外として許容し、一覧表示する）
  C-3 参照先不在 : 本文が参照する「原則NNN」「KYNN」が実在するか
                   （欠番 101〜110・未収録 KY1〜54 は既知として除外）
  C-4 行数上限   : 第15部（追記層）の1件が 20 行以内か

使い方:
  python3 kaizen2_check.py [kaizen2.txt]
終了コード:
  0 = 全検査 PASS / 1 = FAIL あり / 2 = 実行不能（ファイル無し等）

★注意（原則136）★
  本スクリプト自体が判定器である。FAIL が出たら、まず本スクリプトの
  判定条件を疑ってから文書を直すこと。特に見出し書式を変更した場合、
  本スクリプトの正規表現が追随しているかを先に確認する。

改版履歴:
  v1.0 (2026-09-03) 新規作成。C-1〜C-4 の4検査を実装。
  v1.1 (2026-09-03) MISSING_PRINCIPLES を 101〜110 → {101} に変更。
                    原則102〜110 が kaizen2.txt v2.2 第15部へ回収されたため。
  v1.2 (2026-09-03) ★判定器自体の欠陥2件を是正。★
                    (a) 枝番の正規表現が `-[AB]` 固定で、v2.2 で新設した
                        ★原則43-C を見落としていた★（C-1〜C-3 が素通り）。
                        → `-[A-Z]` に拡張。
                    (b) C-1 の索引逆照合の正規表現が「原則」の2文字を
                        無視しており ★恒久的に不発（dead code）だった★。
                        「索引にあるが本文に無い」を一度も検出できていない。
                        → `原則N(-[A-Z])?\s*:` に是正。
                    ★検出の経緯★: 収録件数の期待値141（131+43-C+102〜110の9件）
                    に対し実測140 と1件食い違ったことから追跡した。
                    ★両欠陥とも「ALL PASS」を出した状態で潜んでいた。★
                    期待値を立てて実測と突合しなければ、判定器の欠陥ごと
                    合格していた（原則79 / 原則136）。
"""

import re
import sys

VERSION = "1.2"

# 既知の例外（第0部 0.2 / 0.3 に記録済み）
MISSING_PRINCIPLES = {101}                  # 原則101 のみ恒久欠番（採番ミス・第0部 0.2）
KY_NOT_INCLUDED    = set(range(1, 55))      # KY1〜54 は本ファイル未収録（別管理）
KNOWN_DUP_BRANCH   = {"31", "43"}           # 31 は -A/-B、43 は -A/-B/-C
MAX_LINES_PER_ITEM = 20                     # 第15部 規約【3】

# 見出し書式
RE_P_HEAD  = re.compile(r'^■ 原則(\d+)(-[A-Z])?[ \u3000]', re.M)
RE_KY_HEAD = re.compile(r'^KY(\d+)(b?)[ \u3000]*\(', re.M)
# 本文中の参照
RE_P_REF   = re.compile(r'原則(\d+)')
RE_KY_REF  = re.compile(r'KY(\d+)')


def load(path):
    try:
        with open(path, encoding='utf-8') as f:
            return f.read()
    except OSError as e:
        print("実行不能: %s" % e)
        sys.exit(2)


def split_sections(text):
    """確定層 / 索引(付録B) / 追記層(第15部) に分割する。
    ★見出し文字列の【最後の出現】を使う。目次側にマッチさせないため。★
    （2026-09-02 に目次側へ誤マッチして全件を偽の未収録と報告した実績あり）"""
    i_idx = text.rindex('付録B  原則番号')
    i_apc = text.rindex('付録C  同族グループ')
    i_add = text.rindex('第15部  追記層')
    body  = text[:i_idx]                 # 第0〜14部 + 付録A
    index = text[i_idx:i_apc]            # 付録B
    add   = text[i_add:]                 # 第15部
    return body, index, add


def check_c1(text, index):
    """C-1 収録漏れ（双方向）"""
    ng = []
    heads_p = {m.group(1) for m in RE_P_HEAD.finditer(text)}
    heads_k = {m.group(1) for m in RE_KY_HEAD.finditer(text)}

    # 見出しはあるが索引に無い
    for n in sorted(heads_p, key=int):
        if not re.search(r'(?<!\d)%s(?!\d)' % n, index):
            ng.append("原則%s : 見出しはあるが付録B索引に無い" % n)
    # KY は索引で範囲表記のため、範囲外のみ検出
    for n in sorted(heads_k, key=int):
        if not (55 <= int(n) <= 86):
            if 'KY%s' % n not in index:
                ng.append("KY%s : 見出しはあるが付録B索引に無い" % n)

    # 索引にあるが見出しが無い（原則のみ・欠番除く）
    for n in range(1, 500):
        if n in MISSING_PRINCIPLES:
            continue
        if re.search(r'^\s+原則%d(-[A-Z])?\s*:' % n, index, re.M) and str(n) not in heads_p:
            ng.append("原則%d : 付録B索引にあるが本文見出しが無い" % n)
    return ng


def check_c2(text):
    """C-2 二重発番"""
    ng, seen = [], {}
    for m in RE_P_HEAD.finditer(text):
        key = m.group(1) + (m.group(2) or "")
        seen[key] = seen.get(key, 0) + 1
    for k, v in sorted(seen.items()):
        if v > 1:
            ng.append("原則%s : 見出しが %d 件ある（二重発番）" % (k, v))
    base = {}
    for k in seen:
        b = k.split('-')[0]
        base.setdefault(b, []).append(k)
    for b, ks in sorted(base.items(), key=lambda x: int(x[0])):
        if len(ks) > 1 and b not in KNOWN_DUP_BRANCH:
            ng.append("原則%s : 枝番が未登録の重複（%s）" % (b, "/".join(sorted(ks))))

    seen_k = {}
    for m in RE_KY_HEAD.finditer(text):
        key = m.group(1) + m.group(2)
        seen_k[key] = seen_k.get(key, 0) + 1
    for k, v in sorted(seen_k.items()):
        if v > 1:
            ng.append("KY%s : 見出しが %d 件ある（二重発番）" % (k, v))
    return ng


def check_c3(text):
    """C-3 参照先不在"""
    ng = []
    heads_p = {m.group(1) for m in RE_P_HEAD.finditer(text)}
    heads_k = {m.group(1) for m in RE_KY_HEAD.finditer(text)}
    for n in sorted({m.group(1) for m in RE_P_REF.finditer(text)}, key=int):
        if n in heads_p:
            continue
        if int(n) in MISSING_PRINCIPLES:
            continue          # 欠番。第0部 0.2 に記録済み
        ng.append("原則%s が参照されているが見出しが存在しない" % n)
    for n in sorted({m.group(1) for m in RE_KY_REF.finditer(text)}, key=int):
        if n in heads_k:
            continue
        if int(n) in KY_NOT_INCLUDED:
            continue          # 本ファイル未収録。第13部 13.0 に要旨あり
        ng.append("KY%s が参照されているが見出しが存在しない" % n)
    return ng


def check_c4(add):
    """C-4 第15部の1件あたり行数上限"""
    ng = []
    lines = add.split('\n')
    starts = [i for i, l in enumerate(lines)
              if RE_P_HEAD.match(l) or RE_KY_HEAD.match(l)]
    for j, s in enumerate(starts):
        e = starts[j + 1] if j + 1 < len(starts) else len(lines)
        n = len([l for l in lines[s:e] if l.strip()])
        if n > MAX_LINES_PER_ITEM:
            ng.append("%s… : %d行（上限%d行超過）"
                      % (lines[s][:40], n, MAX_LINES_PER_ITEM))
    return ng


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else 'kaizen2.txt'
    print("kaizen2_check.py Version: %s" % VERSION)
    print("対象: %s" % path)
    text = load(path)
    body, index, add = split_sections(text)

    m = re.search(r'^Version\s*:\s*(\S+)', text, re.M)
    print("文書版数: %s" % (m.group(1) if m else "不明"))
    print("総行数  : %d" % (text.count('\n') + 1))
    print("-" * 60)

    results = [
        ("C-1 収録漏れ",   check_c1(text, index)),
        ("C-2 二重発番",   check_c2(text)),
        ("C-3 参照先不在", check_c3(text)),
        ("C-4 行数上限",   check_c4(add)),
    ]
    fail = 0
    for name, ng in results:
        if ng:
            fail += 1
            print("FAIL: %s (%d件)" % (name, len(ng)))
            for x in ng:
                print("        - %s" % x)
        else:
            print("PASS: %s" % name)
    print("-" * 60)
    n_p = len(RE_P_HEAD.findall(text))
    n_k = len(RE_KY_HEAD.findall(text))
    print("収録件数: 原則見出し %d 件 / KY見出し %d 件" % (n_p, n_k))
    print("RESULT: %s" % ("ALL PASS" if fail == 0 else "FAIL=%d" % fail))
    return 0 if fail == 0 else 1


if __name__ == '__main__':
    sys.exit(main())
