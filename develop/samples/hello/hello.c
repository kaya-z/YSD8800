/*
 * hello.c - YSD8800 ISA2.2 Hello World (C)
 * scc22 v1.00 でコンパイル
 *
 * ビルド方法:
 *   make hello_c
 * または手動:
 *   ./scc22/scc22 samples/hello/hello.c -o build/hello_c/hello.asm
 *   ./hasm22 build/hello_c/hello.asm
 *   python3 scripts/make_harness.py build/hello_c/hello.asm.sym > build/hello_c/harness.asm
 *   ./hasm22 build/hello_c/harness.asm
 *   python3 scripts/merge_simple.py \
 *       build/hello_c/hello.asm.bin build/hello_c/harness.asm.bin \
 *       build/hello_c/hello.bin
 *   ./emu22 build/hello_c/hello.bin -n 200000
 */

void putchar(int c);

/* 改行 */
void newline() {
    putchar(10);
}

/* 1文字出力 */
void emit(int c) {
    putchar(c);
}

int main() {
    /* Hello, YSD8800! */
    emit('H'); emit('e'); emit('l'); emit('l'); emit('o'); emit(',');
    emit(' ');
    emit('Y'); emit('S'); emit('D'); emit('8'); emit('8'); emit('0'); emit('0');
    emit('!');
    newline();
    return 0;
}
