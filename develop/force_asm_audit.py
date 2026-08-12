#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
force_asm_audit.py — Force 出力 ASM のメモリ領域違反検出ツール

== 概要 ==
Force Forth Cross Compiler が出力する .asm ファイルを静的解析し、
EQU $XXXX 形式の固定アドレスシンボル定義が
yuios_memmap_design v1.4 で定められた禁止領域に違反していないか検査する。

HANDOVER_CHAT33 §5.1 観点5 の自動検査機構として実装。

== 検査対象 ==
- EQU $XXXX 形式のシンボル定義
- .org $XXXX ディレクティブ
- LDW/STW などで参照される [$XXXX] 形式の直接アドレス参照

== 検査基準 ==
Force コンパイラ メモリ使用契約書 v1.1 §4.3 に定める「触れてはならない領域」
（MMIO デバイス別の根拠: emu23_device_design_v1_2.docx）

== 依存設計書（KY19 対応：同期改版必須）==
- yuios_memmap_design_v1_4.md
- force_memory_contract_v1_1.md
- emu23_device_design_v1_2.docx (MMIO アドレスマップ)
※ 上記設計書の §4.3 禁止領域定義が変わった場合は本スクリプトの
   PROHIBITED_REGIONS テーブルを同期改版すること。

== バージョン ==
v1.0 (2026-05-26): 初版作成（HANDOVER_CHAT33 §5.1 観点5 対応）
v1.1 (2026-05-26): 契約書 v1.1 レビュー反映に同期改版。MMIO をデバイス別に分割、
                   $FC40-$FC7F の説明拡充、frequently used 領域の影響欄訂正。

== 使用方法 ==
  python3 force_asm_audit.py <input.asm> [--verbose] [--ignore-tgt]

  --verbose    : 全シンボル定義をリスト表示
  --ignore-tgt : CODE-START/DATA-START 領域内のアドレスを警告対象から除外

== 終了コード ==
  0: 違反なし
  1: 違反検出
  2: 引数エラー・ファイル読み込み失敗
"""

import sys
import re
import argparse

VERSION = "1.1"

# yuios_memmap_design v1.4 + Force メモリ使用契約書 v1.1 §4.3 禁止領域定義
# (low, high, label, severity, note)
#   severity: "ERROR" = 必ず違反、"WARN" = 状況により違反
#
# v1.1 (2026-05-26): 契約書 v1.1 レビュー反映で MMIO をデバイス別に分割。
#                    $FC40-$FC7F の説明拡充。frequently used 領域の影響欄訂正。
PROHIBITED_REGIONS = [
    (0x0000, 0x07FF, "Forth カーネル本体 (ROM)",                          "ERROR", "ROM 書き換え不能"),
    (0x4000, 0x44FF, "TCB プール (16 タスク)",                            "ERROR", "★真因② 衝突領域"),
    (0x4500, 0x46FF, "MsgPool 他カーネルワーク",                          "ERROR", "IPC4 メッセージング破壊"),
    (0x4700, 0x477F, "KERN_SP 専用スタック",                              "ERROR", "カーネルスタック破壊"),
    (0x4780, 0x47AF, "frequently used カーネルワーク (Force 占有前)",      "ERROR", "カーネルワーク変数破壊"),
    # $47B0-$47B5 は Force 占有領域 (FORCE_AUTHORIZED_REGIONS で除外)
    # $47B6-$47BF は Force 拡張用予約 (FORCE_RESERVED_REGIONS で除外)
    (0x4800, 0x505F, "FileMgr 専用領域 (Ph.4)",                           "ERROR", "ファイルシステム破壊"),
    (0xF800, 0xFBCF, "タスクスタック",                                    "ERROR", "全タスクのスタック破壊"),
    (0xFC00, 0xFC3F, "スタックガード",                                    "ERROR", "ガード検出機構の無効化"),
    (0xFC40, 0xFC7F, "OS 共有変数 (UART/STOR ドライバ・Forth 共有変数)",  "ERROR", "OS/ドライバ状態破壊"),
    # MMIO 領域（emu23_device_design_v1_2.docx に準拠してデバイス別に分割）
    (0xFC80, 0xFC8F, "YSD8001 UART (TX/RX/STAT)",                        "ERROR", "UART 通信異常"),
    (0xFC90, 0xFC9E, "YSD8002 タイマー (TCR/PERIOD/CYCLE/SCORE/SW_RUNS)", "ERROR", "タイマー異常・IRQ0 暴走"),
    (0xFCA0, 0xFCB1, "YSD8003 ストレージ I/F (SD_CMD/STAT/LBA/DATA)",    "ERROR", "ストレージ I/O 異常"),
    (0xFCB2, 0xFCB5, "YSD8004 割り込みコントローラ (IRQ_STAT/IRQ_MASK)",  "ERROR", "割り込み制御異常"),
    (0xFCB6, 0xFEFF, "MMIO 将来拡張予備",                                 "ERROR", "将来デバイスの異常"),
    (0xFF00, 0xFF10, "MMU (特権モード専用)",                              "ERROR", "MMU 異常・特権モード違反"),
    (0xFF11, 0xFFFF, "MMIO 予約",                                         "ERROR", "予約領域の破壊"),
]

# Force 占有領域（contract v1.1 §4.1）— 違反検出から除外
FORCE_AUTHORIZED_REGIONS = [
    (0x47B0, 0x47B5, "Force ランタイムワーク (_FMUL)"),
]

# Force 拡張用予約領域（contract v1.1 §4.2）— 違反検出から除外（ただし WARN として記録）
FORCE_RESERVED_REGIONS = [
    (0x47B6, 0x47BF, "Force 拡張用予約"),
]

# 正規表現パターン
RE_EQU       = re.compile(r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s+EQU\s+\$([0-9A-Fa-f]+)', re.IGNORECASE)
RE_ORG       = re.compile(r'^\s*\.org\s+\$([0-9A-Fa-f]+)', re.IGNORECASE)
RE_DIRECT    = re.compile(r'\[\s*\$([0-9A-Fa-f]+)\s*\]')


def classify_address(addr):
    """アドレスを分類する。
    返り値: (status, label, severity, note)
      status: "PROHIBITED" | "FORCE_AUTHORIZED" | "FORCE_RESERVED" | "ALLOWED"
    """
    for low, high, label, severity, note in PROHIBITED_REGIONS:
        if low <= addr <= high:
            return ("PROHIBITED", label, severity, note)
    for low, high, label in FORCE_AUTHORIZED_REGIONS:
        if low <= addr <= high:
            return ("FORCE_AUTHORIZED", label, "OK", "")
    for low, high, label in FORCE_RESERVED_REGIONS:
        if low <= addr <= high:
            return ("FORCE_RESERVED", label, "INFO", "Force 拡張用予約領域")
    return ("ALLOWED", "", "OK", "")


def scan_file(path, verbose=False):
    """ASM ファイルを走査し、検出された全アドレス参照を返す。
    返り値: list of (line_no, kind, symbol_or_blank, addr, line_text)
    """
    findings = []
    try:
        with open(path, 'r', encoding='utf-8', errors='replace') as f:
            for line_no, raw in enumerate(f, 1):
                line = raw.rstrip('\n')
                # コメント除外（; 以降）
                code = line.split(';', 1)[0]

                m = RE_EQU.search(code)
                if m:
                    sym = m.group(1)
                    addr = int(m.group(2), 16)
                    findings.append((line_no, "EQU", sym, addr, line))
                    continue

                m = RE_ORG.search(code)
                if m:
                    addr = int(m.group(1), 16)
                    findings.append((line_no, "ORG", "", addr, line))
                    continue

                # [$XXXX] 形式の直接参照（同一行に複数ある可能性）
                for m in RE_DIRECT.finditer(code):
                    addr = int(m.group(1), 16)
                    findings.append((line_no, "REF", "", addr, line))
    except IOError as e:
        print("ERROR: ファイル読み込み失敗: %s (%s)" % (path, e), file=sys.stderr)
        sys.exit(2)
    return findings


def audit(findings, verbose=False):
    """検出結果から違反を判定し、レポートを出力する。
    返り値: violation_count
    """
    violation_count = 0
    info_count = 0

    print("=" * 70)
    print("Force ASM 静的検査レポート (force_asm_audit v%s)" % VERSION)
    print("=" * 70)
    print()

    if verbose:
        print("--- 全シンボル定義一覧 ---")
        for line_no, kind, sym, addr, line in findings:
            if kind == "EQU":
                status, label, sev, note = classify_address(addr)
                print("  L%-5d  %-20s = $%04X  [%s]" % (line_no, sym, addr, status))
        print()

    print("--- 違反検出結果 ---")
    for line_no, kind, sym, addr, line in findings:
        status, label, sev, note = classify_address(addr)

        if status == "PROHIBITED":
            violation_count += 1
            print("[%s] L%d %s = $%04X" % (sev, line_no, sym if sym else "(直接参照)", addr))
            print("       領域: %s" % label)
            print("       注記: %s" % note)
            print("       行: %s" % line.strip())
            print()
        elif status == "FORCE_RESERVED":
            info_count += 1
            print("[INFO] L%d $%04X は Force 拡張用予約領域 (%s)" % (line_no, addr, label))

    print("-" * 70)
    print("検査結果サマリ:")
    print("  検出シンボル/参照: %d 件" % len(findings))
    print("  違反 (ERROR):     %d 件" % violation_count)
    print("  情報 (INFO):      %d 件" % info_count)
    print()

    if violation_count == 0:
        print("[PASS] 禁止領域への違反は検出されませんでした。")
    else:
        print("[FAIL] %d 件の違反を検出しました。" % violation_count)
        print()
        print("対処方針:")
        print("  1. ハードコードアドレスを Force コンパイラ メモリ使用契約書 v1.1")
        print("     §4.1 (Force 占有領域) または §4.2 (拡張候補領域) へ移動する。")
        print("  2. 移動先を memmap 設計書 §3.5 に同期登録する。")
        print("  3. ysd8800_kern.tgt のコメントを同期改版する。")
        print("  4. KY19 防止策に従って同期改版手順 (契約書 §5.2) を完了させる。")

    return violation_count


def main():
    ap = argparse.ArgumentParser(
        description='Force 出力 ASM のメモリ領域違反検出ツール v%s' % VERSION
    )
    ap.add_argument('input', help='検査対象の .asm ファイル')
    ap.add_argument('--verbose', '-v', action='store_true', help='全シンボル定義を列挙')
    ap.add_argument('--version', action='version', version='force_asm_audit v%s' % VERSION)
    args = ap.parse_args()

    print("force_asm_audit v%s — 入力: %s" % (VERSION, args.input))
    print()

    findings = scan_file(args.input, verbose=args.verbose)
    violations = audit(findings, verbose=args.verbose)

    sys.exit(1 if violations > 0 else 0)


if __name__ == '__main__':
    main()
