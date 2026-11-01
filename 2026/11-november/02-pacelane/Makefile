CC      ?= cc
CFLAGS  ?= -std=c11 -O2 -Wall -Wextra -Wpedantic -Wshadow -Wconversion -Wdouble-promotion -Wformat=2 -Werror \
           -D_FORTIFY_SOURCE=2 -D_POSIX_C_SOURCE=200809L -fstack-protector-strong
LDLIBS  := -lm
SAN     := -fsanitize=address,undefined -fno-omit-frame-pointer -g
LIB     := src/parse.c src/split.c src/report.c

.PHONY: all test analyze clean

all: pacelane

pacelane: $(LIB) src/main.c src/pacelane.h
	$(CC) $(CFLAGS) -o $@ $(LIB) src/main.c $(LDLIBS)

# Tests run with AddressSanitizer and UndefinedBehaviorSanitizer switched on.
test: $(LIB) src/main.c tests/test_pacelane.c src/pacelane.h
	$(CC) $(CFLAGS) $(SAN) -Isrc -o tests/test_pacelane $(LIB) tests/test_pacelane.c $(LDLIBS)
	$(CC) $(CFLAGS) $(SAN) -o tests/pacelane_san $(LIB) src/main.c $(LDLIBS)
	./tests/test_pacelane
	./tests/test_cli.sh ./tests/pacelane_san

# GCC's static analyser looks for leaks, null dereferences and out-of-bounds use.
analyze:
	for f in $(LIB) src/main.c; do $(CC) $(CFLAGS) -fanalyzer -c $$f -o /dev/null || exit 1; done

clean:
	rm -f pacelane tests/test_pacelane tests/pacelane_san
