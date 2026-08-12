#!/usr/bin/env python3
# check_layout.py - アセンブル後のバイナリで各セクションの重なりを検出
import subprocess, re, sys

def check(binfile, symfile):
    syms = {}
    with open(symfile) as f:
        for line in f:
            parts = line.strip().split()
            if len(parts)==2:
                syms[parts[1]] = int(parts[0],16)

    # 全ての .org 位置のシンボルを取得して逆アセンブル
    r = subprocess.run(['./emu22', binfile],
        input='disas 0000 2000\nq\n', capture_output=True, text=True)

    # 各アドレスで実際に使われているバイトを収集
    used = {}
    for line in r.stdout.split('\n'):
        m = re.match(r'\s*([0-9a-fA-F]{4}):', line)
        if m:
            addr = int(m.group(1),16)
            used[addr] = line

    # .org 指定されたセクションの実際の末尾を調べる
    org_syms = ['IRQ0_HANDLER','TASK_SLEEP','TASK_WAKEUP','TASK_PRINT_ID',
                'TASK0_ENTRY','TASK1_ENTRY','_kstart']
    sections = [(k,syms[k]) for k in org_syms if k in syms]
    sections.sort(key=lambda x:x[1])

    print(f"{'セクション':25s} {'開始':6s} {'末尾':6s} {'サイズ':6s} {'次開始':6s} {'余裕':6s}")
    print("-"*70)
    ok = True
    for i,(name,start) in enumerate(sections):
        if i+1 < len(sections):
            next_start = sections[i+1][1]
            # このセクションで実際に使われる最大アドレスを調べる
            actual_end = start
            for addr in sorted(used.keys()):
                if start <= addr < next_start:
                    actual_end = addr
            margin = next_start - actual_end - 1
            overlap = "★重複！" if actual_end >= next_start else ""
            print(f"  {name:23s} ${start:04X}  ${actual_end:04X}  {actual_end-start+1:5d}  ${next_start:04X}  {margin:5d}  {overlap}")
            if overlap:
                ok = False

    if ok:
        print("\n✓ 重なりなし")
    else:
        print("\n✗ 重なりあり！再配置が必要")
    return ok

if __name__ == '__main__':
    binf = sys.argv[1] if len(sys.argv)>1 else 'kernel.asm.bin'
    symf = binf.replace('.bin','.sym')
    check(binf, symf)
