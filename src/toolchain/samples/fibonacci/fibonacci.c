/*
 * fibonacci.c - YSD8800 ISA2.2 フィボナッチ数列 (C)
 * scc22 v1.00
 *
 * fib(0)〜fib(10) を計算して16進数で出力する。
 * 再帰関数の動作を確認するサンプル。
 *
 * ビルド: make fibonacci
 */

void putchar(int c);

void newline()  { putchar(10); }
void put_sp()   { putchar(32); }  /* スペース */

/* 16進1桁出力 */
void put_hex1(int n) {
    n = n & 15;
    if (n < 10) { putchar(n + 48); }
    else        { putchar(n + 55); }  /* 'A'-'F' */
}

/* 16進4桁出力 */
void put_hex4(int n) {
    put_hex1((n >> 12) & 15);
    put_hex1((n >>  8) & 15);
    put_hex1((n >>  4) & 15);
    put_hex1( n        & 15);
}

/* フィボナッチ数（再帰） */
int fib(int n) {
    if (n <= 1) { return n; }
    return fib(n - 1) + fib(n - 2);
}

int main() {
    int i;
    /* "fib(n) = xxxx" を出力 */
    /* ヘッダ: "N : FIB\n" */
    putchar('N'); put_sp();
    putchar(':'); put_sp();
    putchar('F'); putchar('I'); putchar('B');
    newline();
    i = 0;
    while (i <= 10) {
        put_hex1(i);   /* n を1桁16進で表示 */
        put_sp();
        putchar(':');
        put_sp();
        put_hex4(fib(i));
        newline();
        i = i + 1;
    }
    return 0;
}
