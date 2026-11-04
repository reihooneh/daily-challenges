#include <iostream>
#include <string>
#include <vector>

#include "bellshare.hpp"

int main(int argc, char** argv) {
  std::ios::sync_with_stdio(false);
  std::vector<std::string> args(argv + 1, argv + argc);
  return bellshare::run(args, std::cin, std::cout, std::cerr);
}
