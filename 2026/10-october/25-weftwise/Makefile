CXX ?= g++
CXXFLAGS ?= -std=c++20 -O2
WARN = -Wall -Wextra -Wpedantic -Wconversion -Wsign-conversion -Wshadow -Werror
SAN = -fsanitize=address,undefined -fno-omit-frame-pointer -g

LIB = src/measure.cpp src/parse.cpp src/cutting.cpp src/report.cpp src/app.cpp

.PHONY: all test lint clean

all: build/weftwise

build/weftwise: $(LIB) src/main.cpp src/*.hpp
	@mkdir -p build
	$(CXX) $(CXXFLAGS) $(WARN) -o $@ $(LIB) src/main.cpp

build/tests: $(LIB) tests/tests.cpp src/*.hpp
	@mkdir -p build
	$(CXX) -std=c++20 -O1 $(WARN) $(SAN) -Isrc -o $@ $(LIB) tests/tests.cpp

test: build/tests
	./build/tests

lint:
	clang-tidy $(LIB) src/main.cpp --quiet -checks='bugprone-*,cert-*,clang-analyzer-*,performance-*,-bugprone-easily-swappable-parameters,-cert-err58-cpp' -- -std=c++20

clean:
	rm -rf build
