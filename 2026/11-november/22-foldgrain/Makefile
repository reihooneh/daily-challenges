CC ?= cc
CFLAGS ?= -std=c11 -O2 -Wall -Wextra -Wpedantic -Wshadow -Wconversion -Werror
SAN = -fsanitize=address,undefined -fno-omit-frame-pointer -g

foldgrain: src/main.c src/foldgrain.c src/foldgrain.h
	$(CC) $(CFLAGS) -o $@ src/main.c src/foldgrain.c -lm

lint:
	clang-tidy src/*.c tests/*.c -- -std=c11

test: tests/test_foldgrain.c src/foldgrain.c src/foldgrain.h
	$(CC) $(CFLAGS) $(SAN) -o tests/run tests/test_foldgrain.c src/foldgrain.c -lm && ./tests/run

clean:
	rm -f foldgrain tests/run

.PHONY: test lint clean
