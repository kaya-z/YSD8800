#!/usr/bin/env python3
# inject_exectest_probe.py — PROC-EXEC-IMPL各段にUART直書きマーカー (切り分け用・KY28)
# 既存の _exectest.fs をベースに、PROC-EXEC-IMPL の各ステップ後へ
# UART-TX直書きマーカーを挿入。どこまで到達するか1回で観測する。
# マーカー: 入口='a' OPEN後='b' STAT後='c' size検証後='d' READ後='e'
#           CLOSE後='f' TASK-CREATE後='g' 登録後='h'

SRC = "kernel_forth_v0_10_14_exectest.fs"
DST = "kernel_forth_v0_10_14_probe.fs"

src = open(SRC, encoding="utf-8").read()

# UART直書きマーカーワードを PROC-EXEC-TEST の前(EXECTESTブロック先頭)に定義
# UART-TX($FC80)へ直接: char UART-STAT待ち→TX! (kernel L756-757作法)
marker_def = r"""\ ====== [EXECTEST] PROC_EXEC/WAIT 検証タスク (検証専用・KY28) ======"""
marker_new = r"""\ ====== [PROBE] PROC-EXEC-IMPL 切り分けマーカー ======
\ UART-TX直書き(IPC4ネスト回避)。char を直接送出。
: PRB-EMIT  ( char -- )
    BEGIN UART-STAT @ 0= INVERT UNTIL
    UART-TX ! ;
\ ====== [EXECTEST] PROC_EXEC/WAIT 検証タスク (検証専用・KY28) ======"""
assert src.count(marker_def) == 1
src = src.replace(marker_def, marker_new, 1)

# PROC-EXEC-IMPL の各ステップ後にマーカー挿入
# 入口直後(>R PE-NAME! DROP DROP の後、FT-STAT-BUF設定後)に 'a'
probes = [
    # (挿入位置の直前にある一意な文字列, 挿入するマーカーコード)
    ("""    FT-STAT-BUF PE-STATBUF !
""",
     """    FT-STAT-BUF PE-STATBUF !
    $61 PRB-EMIT                \\ [PROBE]a 入口到達
"""),
    # OPEN後(PE-FID ! の後)に 'b'
    ("""    PE-FID !                    \\ fid 退避
""",
     """    PE-FID !                    \\ fid 退避
    $62 PRB-EMIT                \\ [PROBE]b OPEN成功
"""),
    # STAT後(size取得後)に 'c'
    ("""    PE-STATBUF @ @ PE-SIZE !    \\ size = [statbuf+0]
""",
     """    PE-STATBUF @ @ PE-SIZE !    \\ size = [statbuf+0]
    $63 PRB-EMIT                \\ [PROBE]c STAT成功
"""),
    # READ後(actual破棄後・CLOSE前)に 'e'
    ("""    DROP                        \\ actual 破棄(Phase1は全読み前提)
""",
     """    DROP                        \\ actual 破棄(Phase1は全読み前提)
    $65 PRB-EMIT                \\ [PROBE]e READ成功
"""),
    # TASK-CREATE後(登録前)に 'g' : "(8) 登録" コメント直前
    ("""    \\ (8) 登録
""",
     """    $67 PRB-EMIT                \\ [PROBE]g TASK-CREATE成功
    \\ (8) 登録
"""),
]
for old, new in probes:
    assert src.count(old) == 1, f"probe anchor not unique ({src.count(old)}): {old[:40]!r}"
    src = src.replace(old, new, 1)

open(DST, "w", encoding="utf-8").write(src)
print(f"injected PROBE markers -> {DST}")
print("  マーカー: a=入口 b=OPEN後 c=STAT後 e=READ後 g=TASK-CREATE後")
print("  期待(全成功時): 0123MD E a b c e g 6 F55 W")
