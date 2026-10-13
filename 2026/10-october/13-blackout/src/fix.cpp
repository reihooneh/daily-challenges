#include "fix.hpp"

#include <algorithm>
#include <cstdlib>
#include <tuple>
#include <vector>

namespace blackout {

namespace {

// Grids with up to this many possible moves are searched completely (a 15 x 15 grid has 113).
constexpr std::size_t kExactMoves = 130;

void toggle(Grid& g, int i) {
  char& ch = g.cells[static_cast<std::size_t>(i)];
  ch = ch == '#' ? '.' : '#';
}

// A move flips a square and its partner together, so a symmetric grid stays symmetric.
// Where a pair is already mismatched, flipping either one alone is a move that repairs it.
// Squares holding letters are never changed.
std::vector<std::vector<int>> possibleMoves(const Grid& g) {
  std::vector<std::vector<int>> moves;
  for (int i = 0; i < g.size(); ++i) {
    int j = g.partner(i);
    if (i > j) continue;
    if (i == j) {
      if (!g.lettered(i)) moves.push_back({i});
    } else if (g.black(i) == g.black(j)) {
      if (!g.lettered(i) && !g.lettered(j)) moves.push_back({i, j});
    } else {
      if (!g.lettered(i)) moves.push_back({i});
      if (!g.lettered(j)) moves.push_back({j});
    }
  }
  return moves;
}

// On big grids, keep only moves within two squares of a problem.
std::vector<std::vector<int>> nearProblems(const Grid& g, const Analysis& a,
                                           const std::vector<std::vector<int>>& moves) {
  std::vector<char> near(static_cast<std::size_t>(g.size()), 0);
  for (const Problem& p : a.problems) {
    std::vector<int> spots = p.cells;
    spots.push_back(p.cell);
    for (int s : spots) {
      if (s < 0) continue;
      int r = s / g.cols;
      int c = s % g.cols;
      for (int dr = -2; dr <= 2; ++dr) {
        for (int dc = -2; dc <= 2; ++dc) {
          int rr = r + dr;
          int cc = c + dc;
          if (rr >= 0 && rr < g.rows && cc >= 0 && cc < g.cols) {
            near[static_cast<std::size_t>(g.index(rr, cc))] = 1;
            near[static_cast<std::size_t>(g.partner(g.index(rr, cc)))] = 1;
          }
        }
      }
    }
  }
  std::vector<std::vector<int>> kept;
  for (const auto& m : moves) {
    if (std::any_of(m.begin(), m.end(), [&](int i) { return near[static_cast<std::size_t>(i)] != 0; })) {
      kept.push_back(m);
    }
  }
  return kept;
}

}  // namespace

FixResult findFix(const Grid& start, Style style, const FixOptions& options) {
  FixResult result;
  result.grid = start;
  Analysis before = analyse(start, style);
  if (before.problems.empty()) {
    result.found = true;
    return result;
  }
  std::vector<std::vector<int>> moves = possibleMoves(start);
  if (moves.size() > kExactMoves) {
    moves = nearProblems(start, before, moves);
    result.exact = false;
  }
  const int maxMoves = std::clamp(options.maxMoves, 1, 4);
  const int k0 = static_cast<int>(moves.size());

  Grid g = start;
  // Best fix so far, scored by: how far the black-square count drifts, squares changed,
  // then the order found (so results are repeatable).
  std::tuple<int, int> bestScore{0, 0};
  std::vector<int> best;
  long found = 0;

  for (int depth = 1; depth <= maxMoves && depth <= k0; ++depth) {
    std::vector<int> pick(static_cast<std::size_t>(depth));
    for (int i = 0; i < depth; ++i) pick[static_cast<std::size_t>(i)] = i;
    while (true) {
      if (result.tried >= options.budget) {
        result.stopped = true;
        break;
      }
      ++result.tried;
      for (int m : pick) {
        for (int cell : moves[static_cast<std::size_t>(m)]) toggle(g, cell);
      }
      if (valid(g, style)) {
        int drift = 0;
        int changed = 0;
        for (int m : pick) {
          for (int cell : moves[static_cast<std::size_t>(m)]) {
            drift += g.black(cell) ? 1 : -1;
            ++changed;
          }
        }
        std::tuple<int, int> score{std::abs(drift), changed};
        if (found == 0 || score < bestScore) {
          bestScore = score;
          best = pick;
        }
        ++found;
      }
      for (int m : pick) {
        for (int cell : moves[static_cast<std::size_t>(m)]) toggle(g, cell);
      }
      // Next combination of `depth` moves, in increasing order.
      int i = depth - 1;
      while (i >= 0 && pick[static_cast<std::size_t>(i)] == k0 - depth + i) --i;
      if (i < 0) break;
      ++pick[static_cast<std::size_t>(i)];
      for (int j = i + 1; j < depth; ++j) pick[static_cast<std::size_t>(j)] = pick[static_cast<std::size_t>(j - 1)] + 1;
    }
    if (found > 0) {
      result.found = true;
      result.moves = depth;
      result.others = found - 1;
      if (!result.stopped) result.searchedUpTo = depth;
      for (int m : best) {
        for (int cell : moves[static_cast<std::size_t>(m)]) {
          toggle(result.grid, cell);
          result.changed.push_back(cell);
        }
      }
      std::sort(result.changed.begin(), result.changed.end());
      return result;
    }
    if (result.stopped) break;
    result.searchedUpTo = depth;
  }
  return result;
}

}  // namespace blackout
