# Inkvault: the C core is built twice, natively for tests and as WebAssembly for the page.
CC       ?= cc
CFLAGS   := -std=c17 -O2 -Wall -Wextra -Wpedantic -Wshadow -Wconversion -Werror
SAN      := -O1 -g -fsanitize=address,undefined -fno-omit-frame-pointer
CORE     := core/util.c core/rs.c core/layout.c core/scan.c
WASMFLAGS := --target=wasm32 -O2 -nostdlib -ffreestanding -DIV_FREESTANDING -std=c17 \
             -Wall -Wextra -Wpedantic -Wshadow -Werror \
             -Wl,--no-entry -Wl,--initial-memory=18874368 -Wl,--max-memory=18874368 \
             -Wl,-z,stack-size=262144 -Wl,--strip-all

.PHONY: all wasm test test-core test-fuzz fuzz test-web lint clean

all: wasm

wasm: web/inkvault.wasm

web/inkvault.wasm: $(CORE) core/wasm.c core/inkvault.h
	clang $(WASMFLAGS) -o $@ $(CORE) core/wasm.c

build/test_core: $(CORE) tests/test_core.c core/inkvault.h
	@mkdir -p build
	$(CC) $(CFLAGS) $(SAN) -o $@ $(CORE) tests/test_core.c -lm

test-core: build/test_core
	./build/test_core

# Random inputs to every decoder, under the sanitizers (any compiler).
build/fuzz_driver: $(CORE) tests/fuzz_decode.c core/inkvault.h
	@mkdir -p build
	$(CC) $(CFLAGS) $(SAN) -DIV_FUZZ_DRIVER -o $@ $(CORE) tests/fuzz_decode.c

test-fuzz: build/fuzz_driver
	./build/fuzz_driver 3000

# Coverage-guided fuzzing with libFuzzer (needs clang with compiler-rt).
fuzz:
	@mkdir -p build
	clang -std=c17 -g -O1 -fsanitize=fuzzer,address,undefined -o build/fuzz $(CORE) tests/fuzz_decode.c
	./build/fuzz -max_total_time=300 -max_len=20000

lint:
	clang-tidy $(CORE) core/wasm.c -warnings-as-errors='*' \
	  -checks='-*,bugprone-*,cert-*,clang-analyzer-*,-bugprone-easily-swappable-parameters,-cert-err33-c' -- -std=c17

test-web: wasm
	node --test tests/web/*.test.mjs
	node tests/ui-tests.mjs

test: test-core test-fuzz test-web

clean:
	rm -rf build web/inkvault.wasm
