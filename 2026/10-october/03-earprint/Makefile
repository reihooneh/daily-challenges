CC      ?= cc
# Warnings as errors, plus hardening flags that make memory bugs harder to exploit.
CFLAGS  ?= -std=c11 -O2 -Wall -Wextra -Wpedantic -Wshadow -Wconversion -Wformat=2 -Werror \
           -D_FORTIFY_SOURCE=2 -fstack-protector-strong -fPIE
LDFLAGS ?= -pie -Wl,-z,relro,-z,now
LDLIBS  := -lm
# Sanitizers catch out-of-bounds access, use-after-free and undefined behaviour at run time.
SANITIZE := -std=c11 -g -O1 -Wall -Wextra -Werror -fsanitize=address,undefined -fno-sanitize-recover=all

LIB := src/sha256.c src/melody.c src/wav.c

earprint: $(LIB) src/main.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^ $(LDLIBS)

build/test_earprint: $(LIB) tests/test_earprint.c
	@mkdir -p build
	$(CC) $(SANITIZE) -Isrc -o $@ $^ $(LDLIBS)

build/earprint-san: $(LIB) src/main.c
	@mkdir -p build
	$(CC) $(SANITIZE) -o $@ $^ $(LDLIBS)

test: build/test_earprint build/earprint-san
	./build/test_earprint
	sh tests/cli_test.sh ./build/earprint-san

clean:
	rm -rf earprint build

.PHONY: test clean
