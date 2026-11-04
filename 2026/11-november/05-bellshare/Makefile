CXX ?= g++
CXXFLAGS ?= -std=c++20 -O2
WARN = -Wall -Wextra -Wpedantic -Wconversion -Wsign-conversion -Wshadow -Werror
SAN = -fsanitize=address,undefined -fno-omit-frame-pointer -g

LIB = src/parse.cpp src/assign.cpp src/report.cpp

.PHONY: all test lint clean

all: build/bellshare

build/bellshare: $(LIB) src/main.cpp src/*.hpp
	@mkdir -p build
	$(CXX) $(CXXFLAGS) $(WARN) -o $@ $(LIB) src/main.cpp

build/tests: $(LIB) tests/tests.cpp src/*.hpp
	@mkdir -p build
	$(CXX) -std=c++20 -O1 $(WARN) -Wno-maybe-uninitialized $(SAN) -Isrc -o $@ $(LIB) tests/tests.cpp

test: build/tests
	./build/tests

lint:
	clang-tidy $(LIB) src/main.cpp --quiet -checks='bugprone-*,cert-*,clang-analyzer-*,performance-*,-bugprone-easily-swappable-parameters,-cert-err58-cpp' -- -std=c++20

clean:
	rm -rf build
