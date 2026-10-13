// Finds the fewest squares to change so that a grid passes every rule.
#pragma once

#include <vector>

#include "grid.hpp"

namespace blackout {

struct FixOptions {
  int maxMoves = 3;          // 1 to 4
  long budget = 1'000'000;   // most grids to try before giving up (a few seconds at most)
};

struct FixResult {
  bool found = false;
  bool stopped = false;      // ran out of budget before finishing a size
  int moves = 0;             // moves in the fix (a move changes a square and its partner)
  int searchedUpTo = 0;      // every fix with this many moves or fewer was tried
  bool exact = true;         // false when only squares near problems were tried
  long tried = 0;
  long others = 0;           // other fixes of the same size
  Grid grid;                 // the fixed grid
  std::vector<int> changed;  // squares that changed colour
};

FixResult findFix(const Grid& g, Style style, const FixOptions& options = {});

}  // namespace blackout
