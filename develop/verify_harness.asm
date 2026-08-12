; verify_harness.asm v1.0
; F55統合検証(案B)専用ハーネス。本番ソース無改変・カーネル不在emu23単体検証用。
;   (1) リセットベクタ $0000 = $C000 (crt0エントリ _proc_entry へ初期PC)
;   (2) $0460 TASK-EXIT を HALT で代替
    .org $0000
RESET_VEC:
    .word $C000          ; emu23 初期PC = crt0 _proc_entry
    .org $0460
TASK_EXIT_STUB:
    HALT
