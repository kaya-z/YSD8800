/*
 * counter.c - YSD8800 ISA2.2 カウンタサンプル (C)
 * scc22 v1.00
 *
 * 0〜9 を1行ずつ出力して "Done!\n" で終了する。
 *
 * ビルド: make counter_c
 */

void putchar(int c);

/* 改行出力 */
void newline() { putchar(10); }

/* 1桁の数字を出力 */
void put_digit(int n) {
    putchar(n + 48);   /* '0' = 48 */
}

/* カウンタメイン */
int main() {
    int i;
    i = 0;
    while (i < 10) {
        put_digit(i);
        newline();
        i = i + 1;
    }
    /* Done! */
    putchar('D'); putchar('o'); putchar('n'); putchar('e'); putchar('!');
    newline();
    return 0;
}
