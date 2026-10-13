// Blackout: reads a crossword grid, numbers it and checks it against house rules.
#pragma once

#include <cstddef>
#include <stdexcept>
#include <string>
#include <vector>

namespace blackout {

constexpr int kMinSide = 3;
constexpr int kMaxSide = 25;
constexpr std::size_t kMaxBytes = 4096;

// Bad input. The message never repeats the input, so it is always safe to print.
struct InputError : std::runtime_error {
  using std::runtime_error::runtime_error;
};

// American: every white square is in an across and a down entry.
// Cryptic (British style): some squares may be in only one entry, within limits.
enum class Style { American, Cryptic };

struct Grid {
  int rows = 0;
  int cols = 0;
  std::vector<char> cells;  // '#' black, '.' empty white, 'A'-'Z' a filled-in letter

  int size() const { return rows * cols; }
  int index(int r, int c) const { return r * cols + c; }
  bool black(int i) const { return cells[static_cast<std::size_t>(i)] == '#'; }
  bool lettered(int i) const {
    char ch = cells[static_cast<std::size_t>(i)];
    return ch >= 'A' && ch <= 'Z';
  }
  // The square that matches i when the grid is turned upside down.
  int partner(int i) const { return size() - 1 - i; }
  std::string text() const;
};

// Parses '#', '.' and letters, one row per line. Throws InputError.
Grid parse(const std::string& text);

struct Entry {
  int number = 0;
  bool across = true;
  int row = 0;
  int col = 0;
  int length = 0;
  int checked = 0;  // letters also in an entry the other way
};

enum class Kind {
  NoWhite,       // nothing to fill in
  Asymmetric,    // square and its partner differ
  Disconnected,  // white squares cut off from the rest
  TwoLetter,     // an entry of only two letters
  Unchecked,     // American: a square in only one entry
  Orphan,        // a white square in no entry at all
  UnderChecked,  // Cryptic: fewer than half an entry's letters are crossed
  DoubleUnch     // Cryptic: two uncrossed letters in a row
};

struct Problem {
  Kind kind;
  int cell = 0;        // where to point at (row-major index)
  bool across = true;  // for entry problems
  int value = 0;       // partner cell, cut-off count or crossed letters
  std::vector<int> cells;  // every square involved
};

struct Analysis {
  std::vector<Entry> entries;
  std::vector<Problem> problems;
  int black = 0;
  int white = 0;
};

Analysis analyse(const Grid& g, Style style);

// The same rules as analyse(), stopping at the first problem. Used by the fixer.
bool valid(const Grid& g, Style style);

}  // namespace blackout
