CC      ?= cc
CFLAGS  ?= -std=c11 -O2 -Wall -Wextra -Wpedantic -Wshadow -Wconversion -Wformat=2 -Werror \
           -D_FORTIFY_SOURCE=2 -fstack-protector-strong
SAN     := -fsanitize=address,undefined -fno-omit-frame-pointer -g
LIB     := src/parse.c src/solve.c src/schedule.c src/report.c

.PHONY: all test analyze clean

all: roomwright

roomwright: $(LIB) src/main.c src/room.h
	$(CC) $(CFLAGS) -o $@ $(LIB) src/main.c

# Tests run with AddressSanitizer and UndefinedBehaviorSanitizer switched on.
test: $(LIB) src/main.c tests/test_room.c src/room.h
	$(CC) $(CFLAGS) $(SAN) -Isrc -o tests/test_room $(LIB) tests/test_room.c
	$(CC) $(CFLAGS) $(SAN) -o tests/roomwright_san $(LIB) src/main.c
	./tests/test_room
	./tests/test_cli.sh ./tests/roomwright_san

# GCC's static analyser looks for leaks, null dereferences and out-of-bounds use.
analyze:
	for f in $(LIB) src/main.c; do $(CC) $(CFLAGS) -fanalyzer -c $$f -o /dev/null || exit 1; done

clean:
	rm -f roomwright tests/test_room tests/roomwright_san
