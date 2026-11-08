CC      ?= cc
CFLAGS  ?= -std=c11 -O2 -Wall -Wextra -Wpedantic -Wshadow -Wconversion -Wdouble-promotion -Wformat=2 -Werror \
           -D_FORTIFY_SOURCE=2 -D_DEFAULT_SOURCE -fstack-protector-strong
LDLIBS  := -lm
SAN     := -fsanitize=address,undefined -fno-omit-frame-pointer -g
LIB     := src/parse.c src/pack.c src/report.c

.PHONY: all test analyze clean

all: kilnstack

kilnstack: $(LIB) src/main.c src/kilnstack.h
	$(CC) $(CFLAGS) -o $@ $(LIB) src/main.c $(LDLIBS)

# Tests run with AddressSanitizer and UndefinedBehaviorSanitizer switched on.
test: $(LIB) src/main.c tests/test_kilnstack.c src/kilnstack.h
	$(CC) $(CFLAGS) $(SAN) -Isrc -o tests/test_kilnstack $(LIB) tests/test_kilnstack.c $(LDLIBS)
	$(CC) $(CFLAGS) $(SAN) -o tests/kilnstack_san $(LIB) src/main.c $(LDLIBS)
	./tests/test_kilnstack
	./tests/test_cli.sh ./tests/kilnstack_san

# GCC's static analyser looks for leaks, null dereferences and out-of-bounds use.
analyze:
	for f in $(LIB) src/main.c; do $(CC) $(CFLAGS) -fanalyzer -c $$f -o /dev/null || exit 1; done

clean:
	rm -f kilnstack tests/test_kilnstack tests/kilnstack_san
