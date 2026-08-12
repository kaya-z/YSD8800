/*
 * calc.c - YSD8800 ISA2.2 電卓サンプル (C)
 * scc22 v1.00
 *
 * 四則演算の結果を表示する。
 * グローバル変数とローカル変数の両方を使用。
 *
 * ビルド: make calc
 */

void putchar(int c);

void newline() { putchar(10); }
void put_sp()  { putchar(32); }

/* 符号付き16進4桁出力 */
void put_hex1(int n) {
    n = n & 15;
    if (n < 10) putchar(n + 48);
    else        putchar(n + 55);
}

void put_hex4(int n) {
    put_hex1((n >> 12) & 15);
    put_hex1((n >>  8) & 15);
    put_hex1((n >>  4) & 15);
    put_hex1( n        & 15);
}

/* 文字列出力（定数で並べる） */
void put_eq() {
    put_sp(); putchar('='); put_sp();
}

/* 演算結果を "A op B = XXXX\n" の形式で出力 */
void show(int a, int b, int result) {
    put_hex4(a);
    put_sp();
    put_hex4(b);
    put_eq();
    put_hex4(result);
    newline();
}

/* グローバル変数 */
int acc;
int tmp;

int main() {
    int a;
    int b;

    /* ヘッダ */
    putchar('C'); putchar('A'); putchar('L'); putchar('C');
    newline();

    a = 0x0064;   /* 100 */
    b = 0x001E;   /* 30  */

    /* 加算: 100 + 30 = 0082 */
    putchar('+'); put_sp();
    show(a, b, a + b);

    /* 減算: 100 - 30 = 004A */
    putchar('-'); put_sp();
    show(a, b, a - b);

    /* 乗算: 100 * 30 = 0BB8 */
    putchar('*'); put_sp();
    show(a, b, a * b);

    /* 除算: 100 / 30 = 0003 */
    putchar('/'); put_sp();
    show(a, b, a / b);

    /* 剰余: 100 % 30 = 000A */
    putchar('%'); put_sp();
    show(a, b, a % b);

    /* ビット演算 */
    a = 0x00FF;
    b = 0x0F0F;

    /* AND: 0x00FF & 0x0F0F = 000F */
    putchar('&'); put_sp();
    show(a, b, a & b);

    /* OR:  0x00FF | 0x0F0F = 0FFF */
    putchar('|'); put_sp();
    show(a, b, a | b);

    /* XOR: 0x00FF ^ 0x0F0F = 0FF0 */
    putchar('^'); put_sp();
    show(a, b, a ^ b);

    /* グローバル変数を使った累積計算 */
    putchar('A'); putchar('C'); putchar('C'); newline();
    acc = 0;
    tmp = 1;
    while (tmp <= 5) {
        acc = acc + tmp;
        tmp = tmp + 1;
    }
    /* 1+2+3+4+5 = 15 = 000F */
    put_hex4(acc);
    newline();

    return 0;
}
