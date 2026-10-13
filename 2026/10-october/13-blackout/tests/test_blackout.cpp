// Tests for Blackout. Built with AddressSanitizer and UndefinedBehaviorSanitizer by `make test`.
#include <chrono>
#include <cstdio>
#include <fstream>
#include <functional>
#include <iostream>
#include <random>
#include <sstream>
#include <string>
#include <vector>

#include "cli.hpp"
#include "fix.hpp"
#include "grid.hpp"

using namespace blackout;

namespace {

int failures = 0;
int checks = 0;

#define CHECK(cond)                                                          \
  do {                                                                       \
    ++checks;                                                                \
    if (!(cond)) {                                                           \
      ++failures;                                                            \
      std::cerr << __FILE__ << ":" << __LINE__ << ": failed: " #cond "\n"; \
    }                                                                        \
  } while (0)

bool has(const Analysis& a, Kind k) {
  for (const Problem& p : a.problems) {
    if (p.kind == k) return true;
  }
  return false;
}

std::string rejectMessage(const std::string& text) {
  try {
    parse(text);
  } catch (const InputError& e) {
    return e.what();
  }
  return "";
}

std::string slurp(const std::string& path) {
  std::ifstream f(path);
  std::stringstream s;
  s << f.rdbuf();
  return s.str();
}

int cli(const std::vector<std::string>& args, const std::string& input, std::string* out, std::string* err) {
  std::istringstream in(input);
  std::ostringstream o;
  std::ostringstream e;
  int code = run(args, in, o, e);
  if (out) *out = o.str();
  if (err) *err = e.str();
  return code;
}

const std::string kExample = "examples/sunday-cryptic.txt";
const std::string kBroken = "examples/broken-cryptic.txt";

void testParse() {
  Grid g = parse("\n#..\n.a.\r\n..#  \n\n");
  CHECK(g.rows == 3 && g.cols == 3);
  CHECK(g.text() == "#..\n.A.\n..#\n");
  CHECK(g.lettered(4) && !g.black(4));

  CHECK(rejectMessage("") == "the file has no grid in it");
  CHECK(rejectMessage("...\n..\n...\n").find("same width") != std::string::npos);
  CHECK(rejectMessage("...\n\n...\n...\n").find("blank") != std::string::npos);
  CHECK(rejectMessage("..\n..\n").find("between 3 and 25") != std::string::npos);
  CHECK(rejectMessage(std::string(26, '.') + "\n" + std::string(26, '.') + "\n" + std::string(26, '.')).find("between") !=
        std::string::npos);
  CHECK(rejectMessage(std::string(5000, '.')).find("4 KB") != std::string::npos);
  // Hostile characters are refused, and the message never repeats them.
  for (const std::string& bad : {std::string("..\x1b[2J\n...\n...\n"), std::string("...\n.\0.\n...\n", 12),
                                 std::string("..\xc3\xa9\n...\n...\n"), std::string("...\n.<s\n...\n"),
                                 std::string("...\n.\r.\n...\n")}) {
    std::string m = rejectMessage(bad);
    CHECK(m.find("not #, . or a letter") != std::string::npos);
    CHECK(m.find('\x1b') == std::string::npos && m.find('<') == std::string::npos);
  }
}

void testNumbering() {
  // 1 2 3 # 4
  // 5 . . 6 .
  // # 7 . . .
  Grid g = parse("...#.\n.....\n#....\n");
  Analysis a = analyse(g, Style::Cryptic);
  std::vector<std::string> got;
  for (const Entry& e : a.entries) {
    got.push_back(std::to_string(e.number) + (e.across ? "A" : "D") + std::to_string(e.length));
  }
  std::vector<std::string> want = {"1A3", "1D2", "2D3", "3D3", "4D3", "5A5", "6D2", "7A4"};
  CHECK(got == want);
  CHECK(a.black == 2 && a.white == 13);
}

void testRules() {
  // Symmetry.
  CHECK(has(analyse(parse("#....\n.....\n.....\n.....\n.....\n"), Style::American), Kind::Asymmetric));
  // Cut off: the right column is walled away.
  Analysis cut = analyse(parse("...#...\n...#...\n...#...\n"), Style::Cryptic);
  CHECK(has(cut, Kind::Disconnected));
  // Two-letter entries.
  CHECK(has(analyse(parse("..#..\n.....\n.....\n.....\n..#..\n"), Style::American), Kind::TwoLetter));
  // American: every square must be in two entries; the lattice gives singly-checked squares.
  Grid lattice = parse(slurp(kExample));
  CHECK(valid(lattice, Style::Cryptic));
  CHECK(has(analyse(lattice, Style::American), Kind::Unchecked));
  CHECK(valid(parse(slurp("examples/mini-american.txt")), Style::American));
  // A white square in no entry at all.
  CHECK(has(analyse(parse(".#.\n#.#\n.#.\n"), Style::Cryptic), Kind::Orphan));
  CHECK(has(analyse(parse("###\n###\n###\n"), Style::Cryptic), Kind::NoWhite));
  // Cryptic: under-checked and two uncrossed letters in a row.
  //   .......
  //   .#####.
  //   .......   the top entry has 2 of 7 crossed, and five uncrossed letters in a row
  Analysis box = analyse(parse(".......\n.#####.\n.......\n"), Style::Cryptic);
  CHECK(has(box, Kind::UnderChecked));
  CHECK(has(box, Kind::DoubleUnch));
  // valid() agrees with analyse() on every one of these.
  for (const std::string& t : {std::string(".......\n.#####.\n.......\n"), std::string(".#.\n#.#\n.#.\n"),
                               std::string("...#...\n...#...\n...#...\n"), slurp(kExample), slurp(kBroken)}) {
    for (Style s : {Style::Cryptic, Style::American}) {
      Grid g = parse(t);
      CHECK(valid(g, s) == analyse(g, s).problems.empty());
    }
  }
}

void testExampleFix() {
  Grid g = parse(slurp(kBroken));
  CHECK(!valid(g, Style::Cryptic));
  FixResult f = findFix(g, Style::Cryptic);
  CHECK(f.found && f.exact && !f.stopped);
  CHECK(f.moves == 2 && f.changed.size() == 3);
  CHECK(valid(f.grid, Style::Cryptic));
  // Nothing smaller works.
  FixOptions one;
  one.maxMoves = 1;
  FixResult none = findFix(g, Style::Cryptic, one);
  CHECK(!none.found && none.searchedUpTo == 1);
}

void testFixKeepsLetters() {
  // Squares holding letters are never changed by a fix.
  Grid g = parse("#...#\n.....\n..Q..\n.....\n#....\n");
  FixResult f = findFix(g, Style::American);
  CHECK(f.found);
  for (int i = 0; i < g.size(); ++i) {
    if (g.lettered(i)) CHECK(f.grid.cells[static_cast<std::size_t>(i)] == g.cells[static_cast<std::size_t>(i)]);
  }
  CHECK(valid(f.grid, Style::American));
}

// Compares the fixer with a brute force over every set of one or two squares, on random
// small grids. If flipping k squares makes a valid grid, the fixer must find a fix with at
// most k moves (a move flips a square and its partner, so k squares need at most k moves).
void testFixMatchesBruteForce() {
  std::mt19937 rng(7);
  int compared = 0;
  for (int trial = 0; trial < 400; ++trial) {
    int side = 4 + static_cast<int>(rng() % 3);
    Grid g;
    g.rows = g.cols = side;
    for (int i = 0; i < side * side; ++i) g.cells.push_back(rng() % 5 == 0 ? '#' : '.');
    Style style = trial % 2 ? Style::American : Style::Cryptic;
    if (valid(g, style)) continue;
    int brute = 0;
    Grid h = g;
    auto flip = [&](int i) { h.cells[static_cast<std::size_t>(i)] = h.black(i) ? '.' : '#'; };
    for (int i = 0; i < g.size() && brute == 0; ++i) {
      flip(i);
      if (valid(h, style)) brute = 1;
      flip(i);
    }
    for (int i = 0; i < g.size() && brute == 0; ++i) {
      for (int j = i + 1; j < g.size() && brute == 0; ++j) {
        flip(i);
        flip(j);
        if (valid(h, style)) brute = 2;
        flip(i);
        flip(j);
      }
    }
    FixOptions opt;
    opt.maxMoves = 2;
    FixResult f = findFix(g, style, opt);
    if (f.found) {
      CHECK(valid(f.grid, style));
      for (int i = 0; i < g.size(); ++i) {
        bool changed = g.black(i) != f.grid.black(i);
        bool listed = false;
        for (int c : f.changed) listed = listed || c == i;
        CHECK(changed == listed);
      }
    }
    if (brute > 0) {
      ++compared;
      CHECK(f.found && f.moves <= brute);
    }
  }
  CHECK(compared > 20);
}

void testRandomInputNeverCrashes() {
  std::mt19937 rng(11);
  const std::string alphabet("#.#..aZ\n\r \x1b\0~", 13);
  for (int trial = 0; trial < 3000; ++trial) {
    std::string t;
    int len = static_cast<int>(rng() % 120);
    for (int i = 0; i < len; ++i) t.push_back(alphabet[rng() % alphabet.size()]);
    try {
      Grid g = parse(t);
      Analysis a = analyse(g, Style::Cryptic);
      CHECK(a.black + a.white == g.size());
      FixOptions opt;
      opt.maxMoves = 1;
      findFix(g, trial % 2 ? Style::Cryptic : Style::American, opt);
    } catch (const InputError&) {
    }
  }
}

void testBigGridIsQuick() {
  // A messy 25 x 25 grid with no small fix: the search must stop at its budget.
  std::mt19937 rng(3);
  Grid g;
  g.rows = g.cols = 25;
  for (int i = 0; i < 625; ++i) g.cells.push_back(rng() % 10 < 3 ? '#' : '.');
  FixOptions opt;
  opt.maxMoves = 4;
  opt.budget = 200'000;
  auto start = std::chrono::steady_clock::now();
  FixResult f = findFix(g, Style::Cryptic, opt);
  double seconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - start).count();
  CHECK(seconds < 20.0);  // generous: the tests run under sanitizers
  CHECK(!f.found && f.stopped && f.tried == opt.budget);
  CHECK(!f.exact);
  // An open 25 x 25 grid with one stray black square is fixed in one move.
  std::string t;
  for (int r = 0; r < 25; ++r) t += std::string(25, '.') + "\n";
  t[3] = '#';
  FixResult easy = findFix(parse(t), Style::Cryptic);
  CHECK(easy.found && easy.moves == 1);
}

void testCommandLine() {
  std::string out;
  std::string err;
  CHECK(cli({kExample}, "", &out, &err) == 0);
  CHECK(out.find("No problems") != std::string::npos && err.empty());

  CHECK(cli({"--fix", kBroken}, "", &out, &err) == 1);
  CHECK(out.find("32 Across has only 2 letters") != std::string::npos || out.find("has only 2 letters") != std::string::npos);
  CHECK(out.find("SMALLEST FIX: change 3 squares") != std::string::npos);
  CHECK(out.find("r13 c3 -> white") != std::string::npos);

  CHECK(cli({"--style", "american", "--entries", "-"}, "#....\n.....\n.....\n.....\n....#\n", &out, &err) == 0);
  CHECK(out.find("Across: 1 (4) 5 (5)") != std::string::npos);

  CHECK(cli({"--max", "1", kBroken}, "", &out, &err) == 1);
  CHECK(out.find("NO SMALL FIX") != std::string::npos);

  CHECK(cli({"--help"}, "", &out, &err) == 0);

  const std::vector<std::vector<std::string>> bad = {
      {}, {"a", "b"}, {"--style"}, {"--style", "bogus"}, {"--max", "9"}, {"--max", "1e3"}, {"--max"}, {"--bogus"},
      {"/no/such/grid"}, {"."}, {"/dev/zero"}, {"\x1b]0;owned\a$(reboot)"}};
  for (const auto& args : bad) {
    CHECK(cli(args, "", &out, &err) == 2);
    CHECK(out.empty());
    CHECK(err.rfind("blackout: ", 0) == 0);
    CHECK(err.find("owned") == std::string::npos && err.find("reboot") == std::string::npos);
  }
  // Endless or huge standard input is refused, not loaded.
  CHECK(cli({"-"}, std::string(100000, '.'), &out, &err) == 2);
  CHECK(err.find("4 KB") != std::string::npos);
}

void testOddFileNamesArePrintedSafely() {
  std::string path = "build/bad\x1b[31mname.txt";
  {
    std::ofstream f(path);
    f << slurp(kExample);
  }
  std::string out;
  CHECK(cli({path}, "", &out, nullptr) == 0);
  CHECK(out.find('\x1b') == std::string::npos);
  CHECK(out.find("bad??31mname.txt") != std::string::npos);
  std::remove(path.c_str());
}

}  // namespace

int main() {
  const std::vector<std::pair<const char*, std::function<void()>>> tests = {
      {"parse", testParse},
      {"numbering", testNumbering},
      {"rules", testRules},
      {"example fix", testExampleFix},
      {"fix keeps letters", testFixKeepsLetters},
      {"fix matches brute force", testFixMatchesBruteForce},
      {"random input never crashes", testRandomInputNeverCrashes},
      {"big grid is quick", testBigGridIsQuick},
      {"command line", testCommandLine},
      {"odd file names", testOddFileNamesArePrintedSafely},
  };
  for (const auto& [name, test] : tests) {
    int before = failures;
    test();
    std::cout << (failures == before ? "ok    " : "FAIL  ") << name << '\n';
  }
  std::cout << checks << " checks, " << failures << " failed\n";
  return failures == 0 ? 0 : 1;
}
