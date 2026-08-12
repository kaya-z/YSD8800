#!/usr/bin/env python3
# inject_exectest.py — 案B検証専用・PROC-EXEC/WAITテストドライバ差し込み (KY28)
# 本番 kernel_forth_v0_10_14.fs は無改変。実験版 _exectest.fs を生成する。
# Step3 の PROC-LIST-TEST 作法に厳密に倣う。

SRC = "kernel_forth_v0_10_14.fs"
DST = "kernel_forth_v0_10_14_exectest.fs"

src = open(SRC, encoding="utf-8").read()

# 差し込みアンカー: PROCMGR-START 定義の直後(PROC-LIST-TESTと同じ位置)
anchor = """: PROCMGR-START  ( -- )
    0 LOAD-SLOT-BUSY !
    0 PROC-CUR-TID !
    0 PROC-EXIT-CODE !
    PROCMGR-TASK-ADDR TASK-CREATE
    PROC-TID-ADDR ! ;           \\ 自tid を $FC6A へ格納"""

block = anchor + r"""

\ ====== [EXECTEST] PROC_EXEC/WAIT 検証タスク (検証専用・KY28) ======
\ FT-NAME-BUF($5060) に "FIB\0" を配置し、ProcMgr へ PROC-EXEC-OP を発行。
\ new_tid を取得→数字化出力→PROC-WAIT-OP で完了待ち→'W'出力。
\ 間に fib プロセス本体の 'F''5''5' 出力が挟まる想定。
\ IPC4-CALL 引数順は PROC-LIST-TEST に倣う( arg2 arg1 arg0 op tid -- ... )。
VARIABLE EXT-NEWTID         \ EXEC が返す new_tid 退避
: PROC-EXEC-TEST  ( -- )
    \ (a) "FIB\0" を FT-NAME-BUF へ配置 (FileMgrテストと同作法 C!)
    $46 FT-NAME-BUF      C!         \ 'F'
    $49 FT-NAME-BUF 1 +  C!         \ 'I'
    $42 FT-NAME-BUF 2 +  C!         \ 'B'
    $00 FT-NAME-BUF 3 +  C!         \ NUL
    \ (b) 開始マーカー 'E' 出力 (EXEC発行前)
    $45 0 0 ROT UART-PUTC-OP UART-DRV-TID @ IPC4-CALL DROP DROP DROP DROP
    \ (c) PROC-EXEC-OP 発行: 0 0 name EXEC-OP procmgr_tid IPC4-CALL
    0 0 FT-NAME-BUF PROC-EXEC-OP PROC-TID-ADDR @ IPC4-CALL
    >R DROP DROP DROP R>            \ r0 = new_tid / err のみ残す
    DUP 0< IF
        \ EXEC失敗: '!' 出力して終了
        DROP $21 0 0 ROT UART-PUTC-OP UART-DRV-TID @ IPC4-CALL DROP DROP DROP DROP
        BEGIN TASK-EXIT AGAIN
    THEN
    DUP EXT-NEWTID !               \ new_tid 退避
    \ (d) new_tid を数字化して出力 ('0'+tid)
    $30 + 0 0 ROT UART-PUTC-OP UART-DRV-TID @ IPC4-CALL DROP DROP DROP DROP
    \ (e) PROC-WAIT-OP 発行: 0 0 new_tid WAIT-OP procmgr_tid IPC4-CALL
    \     ここで fib 本体が走り 'F''5''5' を出力し DEAD 化 → WAIT 脱出
    0 0 EXT-NEWTID @ PROC-WAIT-OP PROC-TID-ADDR @ IPC4-CALL
    DROP DROP DROP DROP            \ REPLY(終了コード) 破棄
    \ (f) WAIT完了マーカー 'W' 出力
    $57 0 0 ROT UART-PUTC-OP UART-DRV-TID @ IPC4-CALL DROP DROP DROP DROP
    BEGIN TASK-EXIT AGAIN ;
CODE PROC-EXEC-TEST-ADDR  ( -- addr )
    SUBI X, #2
    LDW  A, #WORD_PROC_EXEC_TEST
    STW  A, [X]
END-CODE
: PROC-EXEC-TEST-START  ( -- )
    PROC-EXEC-TEST-ADDR TASK-CREATE DROP ;
\ ====== [EXECTEST] ここまで ======"""

assert src.count(anchor) == 1, f"anchor not unique: {src.count(anchor)}"
src = src.replace(anchor, block, 1)

# OS-START の待機ループ手前に PROC-EXEC-TEST-START を追加(tid=6)
old = """    PROCMGR-START                   \\ tid=5: ProcMgr (★Ph.5 v0.10.13 新規)
    BEGIN TASK-SLEEP AGAIN ;        \\ ルートタスク(tid=0)は待機ループ"""
new = """    PROCMGR-START                   \\ tid=5: ProcMgr (★Ph.5 v0.10.13 新規)
    PROC-EXEC-TEST-START            \\ tid=6: [EXECTEST] 検証専用
    BEGIN TASK-SLEEP AGAIN ;        \\ ルートタスク(tid=0)は待機ループ"""
assert src.count(old) == 1, f"OS-START anchor not unique: {src.count(old)}"
src = src.replace(old, new, 1)

open(DST, "w", encoding="utf-8").write(src)
assert ": PROC-EXEC-TEST " in src and "CODE PROC-EXEC-TEST-ADDR" in src
print(f"injected EXECTEST -> {DST}")
print("  - PROC-EXEC-TEST: 'E'出力→EXEC発行→new_tid数字出力→WAIT→'W'出力")
print("  - OS-START tid=6 に PROC-EXEC-TEST-START 追加")
print("  - 期待出力: 0123MD E <tid> F 5 5 W  (fib本体のF55が挟まる)")
