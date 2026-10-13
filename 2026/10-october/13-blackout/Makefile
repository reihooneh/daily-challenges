CXX      ?= g++
CXXFLAGS ?= -std=c++17 -O2 -Wall -Wextra -Wpedantic -Wshadow -Werror
SAN      := -fsanitize=address,undefined -fno-omit-frame-pointer -g
LIB      := src/grid.cpp src/fix.cpp src/cli.cpp

.PHONY: all test clean

all: blackout

blackout: $(LIB) src/main.cpp src/*.hpp
	$(CXX) $(CXXFLAGS) -o $@ $(LIB) src/main.cpp

build/tests: $(LIB) tests/test_blackout.cpp src/*.hpp
	@mkdir -p build
	$(CXX) $(CXXFLAGS) $(SAN) -Isrc -o $@ $(LIB) tests/test_blackout.cpp

test: build/tests
	./build/tests

clean:
	rm -rf blackout build
