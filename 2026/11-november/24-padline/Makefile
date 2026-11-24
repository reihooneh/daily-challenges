CXX ?= g++
CXXFLAGS ?= -std=c++20 -O2 -Wall -Wextra -Wpedantic -Wshadow -Wconversion -Werror
SAN = -fsanitize=address,undefined -fno-omit-frame-pointer -g

padline: src/main.cpp src/padline.cpp src/padline.hpp
	$(CXX) $(CXXFLAGS) -o $@ src/main.cpp src/padline.cpp

test: tests/test_padline.cpp src/padline.cpp src/padline.hpp
	$(CXX) $(CXXFLAGS) $(SAN) -o tests/run tests/test_padline.cpp src/padline.cpp && ./tests/run

lint:
	clang-tidy src/*.cpp tests/*.cpp -- -std=c++20

clean:
	rm -f padline tests/run

.PHONY: test lint clean
