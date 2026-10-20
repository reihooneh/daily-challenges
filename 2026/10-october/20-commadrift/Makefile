CC      ?= cc
CFLAGS  ?= -std=c11 -O2 -Wall -Wextra -Wpedantic -Wshadow -Wconversion -Wdouble-promotion -Wformat=2 -Werror \
           -D_FORTIFY_SOURCE=2 -D_POSIX_C_SOURCE=200809L -fstack-protector-strong
LDLIBS  := -lm
SAN     := -fsanitize=address,undefined -fno-omit-frame-pointer -g
LIB     := src/parse.c src/chords.c src/solve.c

.PHONY: all test analyze clean

all: commadrift

commadrift: $(LIB) src/main.c src/drift.h
	$(CC) $(CFLAGS) -o $@ $(LIB) src/main.c $(LDLIBS)

# Tests run with AddressSanitizer and UndefinedBehaviorSanitizer switched on.
test: $(LIB) src/main.c tests/test_drift.c src/drift.h
	$(CC) $(CFLAGS) $(SAN) -Isrc -o tests/test_drift $(LIB) tests/test_drift.c $(LDLIBS)
	$(CC) $(CFLAGS) $(SAN) -o tests/commadrift_san $(LIB) src/main.c $(LDLIBS)
	./tests/test_drift
	./tests/test_cli.sh ./tests/commadrift_san

# GCC's static analyser looks for leaks, null dereferences and out-of-bounds use.
analyze:
	for f in $(LIB) src/main.c; do $(CC) $(CFLAGS) -fanalyzer -c $$f -o /dev/null || exit 1; done

clean:
	rm -f commadrift tests/test_drift tests/commadrift_san
