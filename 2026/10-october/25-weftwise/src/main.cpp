#include <iostream>
#include <string>
#include <vector>

#include "app.hpp"

int main(int argc, char** argv) {
  std::vector<std::string> args(argv + 1, argv + argc);
  return weftwise::run(args, std::cin, std::cout, std::cerr);
}
