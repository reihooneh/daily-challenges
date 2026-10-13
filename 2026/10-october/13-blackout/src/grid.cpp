#include "grid.hpp"

#include <string>
#include <utility>
#include <vector>

namespace blackout {

std::string Grid::text() const {
  std::string out;
  for (int r = 0; r < rows; ++r) {
    for (int c = 0; c < cols; ++c) out.push_back(cells[static_cast<std::size_t>(index(r, c))]);
    out.push_back('\n');
  }
  return out;
}

Grid parse(const std::string& text) {
  if (text.size() > kMaxBytes) throw InputError("the grid file is larger than 4 KB");

  std::vector<std::string> lines;
  std::string line;
  auto finish = [&]() {
    if (!line.empty() && line.back() == '\r') line.pop_back();  // Windows line endings
    while (!line.empty() && (line.back() == ' ' || line.back() == '\t')) line.pop_back();
    lines.push_back(line);
    line.clear();
  };
  for (char ch : text) {
    if (ch == '\n') {
      finish();
    } else {
      line.push_back(ch);
    }
  }
  if (!line.empty()) finish();

  // Blank lines are allowed only before and after the grid.
  std::size_t first = 0;
  std::size_t last = lines.size();
  while (first < last && lines[first].empty()) ++first;
  while (last > first && lines[last - 1].empty()) --last;
  if (first == last) throw InputError("the file has no grid in it");

  Grid g;
  g.rows = static_cast<int>(last - first);
  g.cols = static_cast<int>(lines[first].size());
  if (g.rows < kMinSide || g.cols < kMinSide || g.rows > kMaxSide || g.cols > kMaxSide) {
    throw InputError("a grid must be between 3 and 25 squares on each side");
  }
  for (std::size_t i = first; i < last; ++i) {
    const std::string& row = lines[i];
    std::string where = "line " + std::to_string(i + 1);
    if (row.empty()) throw InputError(where + " is blank, inside the grid");
    if (static_cast<int>(row.size()) != g.cols) throw InputError(where + " is not the same width as the first row");
    for (char ch : row) {
      if (ch == '#' || ch == '.') {
        g.cells.push_back(ch);
      } else if (ch >= 'A' && ch <= 'Z') {
        g.cells.push_back(ch);
      } else if (ch >= 'a' && ch <= 'z') {
        g.cells.push_back(static_cast<char>(ch - 'a' + 'A'));
      } else {
        throw InputError(where + " has a character that is not #, . or a letter");
      }
    }
  }
  return g;
}

namespace {

// For every square, the length of the across and down run of white squares it sits in
// (0 for a black square).
struct Runs {
  std::vector<int> across;
  std::vector<int> down;
};

Runs measure(const Grid& g) {
  Runs r{std::vector<int>(static_cast<std::size_t>(g.size()), 0),
         std::vector<int>(static_cast<std::size_t>(g.size()), 0)};
  for (int row = 0; row < g.rows; ++row) {
    int c = 0;
    while (c < g.cols) {
      if (g.black(g.index(row, c))) {
        ++c;
        continue;
      }
      int end = c;
      while (end < g.cols && !g.black(g.index(row, end))) ++end;
      for (int k = c; k < end; ++k) r.across[static_cast<std::size_t>(g.index(row, k))] = end - c;
      c = end;
    }
  }
  for (int col = 0; col < g.cols; ++col) {
    int rr = 0;
    while (rr < g.rows) {
      if (g.black(g.index(rr, col))) {
        ++rr;
        continue;
      }
      int end = rr;
      while (end < g.rows && !g.black(g.index(end, col))) ++end;
      for (int k = rr; k < end; ++k) r.down[static_cast<std::size_t>(g.index(k, col))] = end - rr;
      rr = end;
    }
  }
  return r;
}

int at(const std::vector<int>& v, int i) { return v[static_cast<std::size_t>(i)]; }

// Runs every rule. report(Problem&&) returns false to stop early.
// Returns true when there were no problems.
template <class Report>
bool check(const Grid& g, Style style, const Runs& runs, Report&& report) {
  bool ok = true;
  auto add = [&](Problem p) {
    ok = false;
    return report(std::move(p));
  };
  const int n = g.size();

  // 1. Symmetry: the grid looks the same turned upside down.
  for (int i = 0; i < n; ++i) {
    int j = g.partner(i);
    if (i < j && g.black(i) != g.black(j)) {
      if (!add(Problem{Kind::Asymmetric, i, true, j, {i, j}})) return false;
    }
  }

  // 2. Something to fill in, all in one piece.
  int first = -1;
  int whites = 0;
  for (int i = 0; i < n; ++i) {
    if (!g.black(i)) {
      ++whites;
      if (first < 0) first = i;
    }
  }
  if (whites == 0) {
    add(Problem{Kind::NoWhite, 0, true, 0, {}});
    return false;
  }
  std::vector<char> seen(static_cast<std::size_t>(n), 0);
  std::vector<int> stack{first};
  seen[static_cast<std::size_t>(first)] = 1;
  int reached = 1;
  while (!stack.empty()) {  // iterative, so a big grid cannot overflow the call stack
    int i = stack.back();
    stack.pop_back();
    int r = i / g.cols;
    int c = i % g.cols;
    const int nr[4] = {r - 1, r + 1, r, r};
    const int nc[4] = {c, c, c - 1, c + 1};
    for (int k = 0; k < 4; ++k) {
      if (nr[k] < 0 || nr[k] >= g.rows || nc[k] < 0 || nc[k] >= g.cols) continue;
      int j = g.index(nr[k], nc[k]);
      if (g.black(j) || seen[static_cast<std::size_t>(j)]) continue;
      seen[static_cast<std::size_t>(j)] = 1;
      ++reached;
      stack.push_back(j);
    }
  }
  if (reached < whites) {
    Problem p{Kind::Disconnected, -1, true, whites - reached, {}};
    for (int i = 0; i < n; ++i) {
      if (!g.black(i) && !seen[static_cast<std::size_t>(i)]) {
        if (p.cell < 0) p.cell = i;
        p.cells.push_back(i);
      }
    }
    if (!add(std::move(p))) return false;
  }

  // 3. Entries: no two-letter entries; for cryptic grids, enough crossing letters.
  for (int dir = 0; dir < 2; ++dir) {
    const bool across = dir == 0;
    const std::vector<int>& mine = across ? runs.across : runs.down;
    const std::vector<int>& other = across ? runs.down : runs.across;
    for (int i = 0; i < n; ++i) {
      if (g.black(i)) continue;
      int r = i / g.cols;
      int c = i % g.cols;
      bool starts = across ? (c == 0 || g.black(i - 1)) : (r == 0 || g.black(i - g.cols));
      int len = at(mine, i);
      if (!starts || len < 2) continue;
      const int step = across ? 1 : g.cols;
      std::vector<int> cells;
      for (int k = 0; k < len; ++k) cells.push_back(i + k * step);
      if (len == 2) {
        if (!add(Problem{Kind::TwoLetter, i, across, 2, cells})) return false;
        continue;
      }
      if (style != Style::Cryptic) continue;
      int checked = 0;
      int doubleAt = -1;
      for (int k = 0; k < len; ++k) {
        bool crossed = at(other, cells[static_cast<std::size_t>(k)]) >= 2;
        if (crossed) ++checked;
        if (!crossed && k > 0 && at(other, cells[static_cast<std::size_t>(k - 1)]) < 2 && doubleAt < 0) {
          doubleAt = cells[static_cast<std::size_t>(k - 1)];
        }
      }
      if (checked < len / 2) {
        if (!add(Problem{Kind::UnderChecked, i, across, checked, cells})) return false;
      }
      if (doubleAt >= 0) {
        if (!add(Problem{Kind::DoubleUnch, doubleAt, across, 0, cells})) return false;
      }
    }
  }

  // 4. Squares: in no entry at all, or (American) in only one.
  for (int i = 0; i < n; ++i) {
    if (g.black(i)) continue;
    bool inAcross = at(runs.across, i) >= 2;
    bool inDown = at(runs.down, i) >= 2;
    if (!inAcross && !inDown) {
      if (!add(Problem{Kind::Orphan, i, true, 0, {i}})) return false;
    } else if (style == Style::American && !(inAcross && inDown)) {
      if (!add(Problem{Kind::Unchecked, i, inDown, 0, {i}})) return false;
    }
  }
  return ok;
}

}  // namespace

Analysis analyse(const Grid& g, Style style) {
  Analysis a;
  Runs runs = measure(g);
  int number = 0;
  for (int i = 0; i < g.size(); ++i) {
    if (g.black(i)) {
      ++a.black;
      continue;
    }
    ++a.white;
    int r = i / g.cols;
    int c = i % g.cols;
    bool across = (c == 0 || g.black(i - 1)) && at(runs.across, i) >= 2;
    bool down = (r == 0 || g.black(i - g.cols)) && at(runs.down, i) >= 2;
    if (!across && !down) continue;
    ++number;
    for (int dir = 0; dir < 2; ++dir) {
      bool isAcross = dir == 0;
      if (isAcross ? !across : !down) continue;
      Entry e{number, isAcross, r, c, at(isAcross ? runs.across : runs.down, i), 0};
      for (int k = 0; k < e.length; ++k) {
        int cell = isAcross ? i + k : i + k * g.cols;
        if (at(isAcross ? runs.down : runs.across, cell) >= 2) ++e.checked;
      }
      a.entries.push_back(e);
    }
  }
  check(g, style, runs, [&](Problem&& p) {
    a.problems.push_back(std::move(p));
    return true;
  });
  return a;
}

bool valid(const Grid& g, Style style) {
  return check(g, style, measure(g), [](Problem&&) { return false; });
}

}  // namespace blackout
