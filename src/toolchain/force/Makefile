# force/Makefile - Force Forth Cross Compiler v1.0 ビルドシステム
# Version: 1.0
#
# 使用法:
#   make          force バイナリをビルド
#   make clean    生成物を削除
#   make test     基本テストを実行

CC      = gcc
CFLAGS  = -std=c99 -O2 -Wall -D_GNU_SOURCE

SRCS = force.c \
       frontend/lexer.c \
       frontend/parser.c \
       frontend/ir.c \
       backend/codegen.c

.PHONY: all clean test

all: force

force: $(SRCS)
	$(CC) $(CFLAGS) $(SRCS) -o force
	@echo "  [OK] force built"

clean:
	rm -f force *.asm *.bin *.sym

test: force
	@echo "=== Force basic test ==="
	./force test_basic.fs -o /tmp/force_test.asm && echo "  [OK] test_basic.fs"
	@echo "=== Force e2e test ==="
	./force test_e2e.fs -o /tmp/force_e2e.asm && echo "  [OK] test_e2e.fs"
