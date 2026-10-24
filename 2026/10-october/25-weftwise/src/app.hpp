#pragma once

#include <istream>
#include <ostream>
#include <string>
#include <vector>

namespace weftwise {

// The whole command line, with its streams passed in so the tests can drive it.
// Exit codes: 0 a plan was printed, 2 bad usage or input.
int run(const std::vector<std::string>& args, std::istream& in, std::ostream& out, std::ostream& err);

}  // namespace weftwise
