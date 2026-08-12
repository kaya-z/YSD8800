; task_patch.asm - task_demo用カーネルパッチ（自動生成）
; TASK0_ENTRY($0360) → WORD_main        ($155E)
; TASK1_ENTRY($03C0) → WORD_task1_main  ($1503)

    .org $0360
TASK0_ENTRY:
    JSR  $155E
    HALT

    .org $03C0
TASK1_ENTRY:
    JSR  $1503
    HALT
