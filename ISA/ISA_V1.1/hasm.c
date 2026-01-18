#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

static void emit(FILE *out, unsigned char b) {
    fprintf(out, "%02X\n", b);
}

int main(int argc, char **argv) {
    FILE *in, *out;
    char line[256];

    if (argc != 3) {
        fprintf(stderr, "usage: hasm input.asm output.hex\n");
        return 1;
    }

    in  = fopen(argv[1], "r");
    out = fopen(argv[2], "w");
    if (!in || !out) {
        perror("file");
        return 1;
    }

    while (fgets(line, sizeof(line), in)) {
        char op[32];
        unsigned int val;

        // コメント除去
        char *c = strchr(line, ';');
        if (c) *c = 0;

        if (sscanf(line, "%31s", op) != 1)
            continue;

        if (!strcmp(op, "NOP")) {
            emit(out, 0x00); emit(out, 0x00); emit(out, 0x00); emit(out, 0x00);
        }
        else if (!strcmp(op, "LDA")) {
            sscanf(line, "LDA #%u", &val);
            emit(out, 0x10);
            emit(out, val & 0xFF);
            emit(out, 0x00);
            emit(out, 0x00);
        }
        else if (!strcmp(op, "STA")) {
            sscanf(line, "STA %x", &val);
            emit(out, 0x20);
            emit(out, (val >> 8) & 0xFF);
            emit(out, val & 0xFF);
            emit(out, 0x00);
        }
        else if (!strcmp(op, "JMP")) {
            sscanf(line, "JMP %x", &val);
            emit(out, 0x30);
            emit(out, (val >> 8) & 0xFF);
            emit(out, val & 0xFF);
            emit(out, 0x00);
        }
        else if (!strcmp(op, "HALT")) {
            emit(out, 0xFF); emit(out, 0x00); emit(out, 0x00); emit(out, 0x00);
        }
        else {
            fprintf(stderr, "unknown opcode: %s\n", op);
            return 1;
        }
    }

    fclose(in);
    fclose(out);
    return 0;
}
