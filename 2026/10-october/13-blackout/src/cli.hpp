#pragma once

#include <iosfwd>
#include <string>
#include <vector>

#include "fix.hpp"
#include "grid.hpp"

namespace blackout {

std::string where(const Grid& g, int cell);  // "r3 c7", counting from 1
std::string describe(const Grid& g, const Analysis& a, const Problem& p);
std::string report(const Grid& g, Style style, const Analysis& a, const std::string& name, bool listEntries);
std::string fixReport(const Grid& g, const FixResult& fix);

// The command line. Returns 0 if the grid passes, 1 if it has problems, 2 for bad input.
int run(const std::vector<std::string>& args, std::istream& in, std::ostream& out, std::ostream& err);

}  // namespace blackout
