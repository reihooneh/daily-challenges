// Tests, built with AddressSanitizer and UBSan by `make test`.
#include <algorithm>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iostream>
#include <random>
#include <sstream>

#include "bellshare.hpp"

using namespace bellshare;

namespace {

int checks = 0, failed = 0;

void check(bool ok, const std::string& what) {
  ++checks;
  if (!ok) {
    ++failed;
    std::cout << "FAIL: " << what << '\n';
  }
}

void rejects(const std::string& text, const std::string& fragment) {
  try {
    parse(text);
    check(false, "should reject: " + fragment);
  } catch (const InputError& e) {
    const std::string m = e.what();
    check(m.find(fragment) != std::string::npos, "message '" + m + "' should mention '" + fragment + "'");
    check(m.find("SECRET") == std::string::npos, "never echoes the input");
  }
}

Piece piece(const std::vector<std::vector<int>>& chords, int ringers = 1, double swap = 1) {
  Piece p;
  p.ringers = ringers;
  p.swapBeats = swap;
  p.maxBells = 12;
  double t = 0;
  for (const auto& c : chords) {
    Chord ch;
    ch.time = t;
    ch.notes = c;
    std::sort(ch.notes.begin(), ch.notes.end());
    p.chords.push_back(ch);
    t += 1;
  }
  return p;
}

// The fewest changes possible for one ringer, by trying every choice of which hand to free.
int fewestChanges(const Piece& p, const std::vector<int>& bells) {
  std::vector<std::vector<int>> events;
  for (const auto& c : p.chords) {
    std::vector<int> need;
    for (int n : c.notes)
      if (std::find(bells.begin(), bells.end(), n) != bells.end()) need.push_back(n);
    if (!need.empty()) events.push_back(need);
  }
  int best = 1 << 20;
  std::function<void(std::size_t, std::size_t, int, int, int)> go = [&](std::size_t e, std::size_t k, int h0, int h1, int changes) {
    if (changes >= best) return;
    if (e == events.size()) {
      best = changes;
      return;
    }
    const auto& need = events[e];
    if (k == need.size()) return go(e + 1, 0, h0, h1, changes);
    const int n = need[k];
    if (h0 == n || h1 == n) return go(e, k + 1, h0, h1, changes);
    if (h0 < 0) return go(e, k + 1, n, h1, changes);
    if (h1 < 0) return go(e, k + 1, h0, n, changes);
    // Can't drop a bell this chord still needs.
    const bool keep0 = std::find(need.begin(), need.end(), h0) != need.end();
    const bool keep1 = std::find(need.begin(), need.end(), h1) != need.end();
    if (!keep0) go(e, k + 1, n, h1, changes + 1);
    if (!keep1) go(e, k + 1, h0, n, changes + 1);
  };
  go(0, 0, -1, -1, 0);
  return best;
}

}  // namespace

int main() {
  // ---------- Notes ----------
  check(parseNote("C4") == 60 && parseNote("A4") == 69, "middle C and A440");
  check(parseNote("Bb5") == parseNote("A#5"), "flats and sharps share a bell");
  check(parseNote("C2") == 36 && parseNote("C9") == 120 && parseNote("B1") == -1 && parseNote("D9") == -1, "the range of bells");
  check(parseNote("H4") == -1 && parseNote("C#") == -1 && parseNote("c4") == -1 && parseNote("C44") == -1, "not notes");
  check(noteName(61) == "C#4" && noteName(84) == "C6", "names");

  // ---------- One ringer's hands ----------
  check(play(piece({{60}, {62}, {60}, {62}}), {60, 62}).changes.empty(), "two bells never need a change");
  Load l = play(piece({{60}, {62}, {64}, {60}, {62}, {64}}), {60, 62, 64});
  check(l.possible && l.changes.size() == 2, "three bells in turn: the fewest changes (" + std::to_string(l.changes.size()) + ")");
  Load clash = play(piece({{60, 62, 64}}), {60, 62, 64});
  check(!clash.possible && clash.clashes == 1, "three bells at once can't be rung");
  // C4 rings at beat 0, D4 at 1, E4 at 2: the hand holding C4 has two beats to swap it for E4.
  Load quick = play(piece({{60}, {62}, {64}}, 1, 2.5), {60, 62, 64});
  check(quick.changes.size() == 1 && quick.tight == 1 && quick.changes[0].down == 60, "two beats free is tight when 2.5 are needed");
  Load slow = play(piece({{60}, {62}, {64}}, 1, 2.0), {60, 62, 64});
  check(slow.tight == 0 && std::abs(slow.changes[0].room - 2) < 1e-12, "and comfortable when two are enough");
  // Neither bell is needed again: put down the one rung longest ago.
  Load fair = play(piece({{62}, {60}, {64}}), {60, 62, 64});
  check(fair.changes.size() == 1 && fair.changes[0].down == 62, "ties go to the hand free longest");

  // Belady's rule gives the fewest changes: checked against every choice on random parts.
  std::mt19937 rng(17);
  for (int round = 0; round < 300; ++round) {
    const int nb = 3 + static_cast<int>(rng() % 3);
    std::vector<std::vector<int>> chords;
    const int len = 4 + static_cast<int>(rng() % 9);
    for (int i = 0; i < len; ++i) {
      std::vector<int> c{60 + static_cast<int>(rng() % static_cast<unsigned>(nb))};
      if (rng() % 4 == 0) {
        const int other = 60 + static_cast<int>(rng() % static_cast<unsigned>(nb));
        if (other != c[0]) c.push_back(other);
      }
      chords.push_back(c);
    }
    std::vector<int> bells;
    for (int b = 0; b < nb; ++b) bells.push_back(60 + b);
    const Piece p = piece(chords);
    check(static_cast<int>(play(p, bells).changes.size()) == fewestChanges(p, bells), "Belady matches brute force, round " + std::to_string(round));
  }

  // ---------- Sharing the bells ----------
  // Every way to split the bells into runs, for small random pieces.
  for (int round = 0; round < 120; ++round) {
    const int nb = 4 + static_cast<int>(rng() % 5);
    const int ringers = 2 + static_cast<int>(rng() % 3);
    std::vector<std::vector<int>> chords;
    for (int i = 0; i < 14; ++i) {
      std::vector<int> c;
      for (int b = 0; b < nb; ++b)
        if (rng() % 4 == 0) c.push_back(60 + b);
      if (c.empty()) c.push_back(60 + static_cast<int>(rng() % static_cast<unsigned>(nb)));
      chords.push_back(c);
    }
    Piece p = piece(chords, ringers, 1.0);
    p.maxBells = 4;
    const std::vector<int> bells = bellsUsed(p);
    const int m = static_cast<int>(bells.size());
    const int r = std::min(ringers, m);
    double bestCost = INFINITY;
    // Choose r-1 cut points among the m-1 gaps.
    std::vector<int> cut(static_cast<std::size_t>(m - 1), 0);
    std::fill(cut.end() - (r - 1), cut.end(), 1);
    do {
      std::vector<std::vector<int>> runs(1);
      for (int i = 0; i < m; ++i) {
        runs.back().push_back(bells[static_cast<std::size_t>(i)]);
        if (i < m - 1 && cut[static_cast<std::size_t>(i)]) runs.emplace_back();
      }
      bestCost = std::min(bestCost, evaluate(p, runs).cost);
    } while (std::next_permutation(cut.begin(), cut.end()));
    const Assignment a = best(p);
    check(std::abs(a.cost - bestCost) < 1e-9, "the split is the best of every split, round " + std::to_string(round));
    check(a.cost <= equalSplit(p).cost + 1e-9, "never worse than equal shares");
    check(static_cast<int>(a.ringers.size()) == r, "one run per ringer");
  }

  // ---------- The piece file ----------
  const Piece ex = parse("piece Test\nringers 3\ntime 3/4\n1:1 C5 E5 G5\n1:2.5 D5\n2:1 C5\n");
  check(ex.chords.size() == 3 && std::abs(ex.chords[1].time - 1.5) < 1e-12 && std::abs(ex.chords[2].time - 3) < 1e-12, "measure:beat times");
  check(where(ex, 4.0) == "m2:2", "times back to measure:beat");
  rejects("", "ringers");
  rejects("ringers 3\n", "no chords");
  rejects("ringers 30\n1:1 C5\n", "from 1 to 20");
  rejects("ringers 3\n1:1 H5\n", "notes are written like");
  rejects("ringers 3\n1:5 C5\n", "a beat must be from 1");
  rejects("ringers 3\n2:1 C5\n1:1 D5\n", "after the one before");
  rejects("ringers 3\n1:1 C5\ntime 3/4\n", "before the first chord");
  rejects("ringers 3\n1:1 C4 D4 E4 F4 G4 A4 B4 C5 D5 E5 F5 G5 A5\n", "at most 12 notes");
  rejects("piece <script>\nringers 3\n1:1 C5\n", "piece's name");
  rejects("piece Bells\xE2\x80\xAESECRET\nringers 3\n1:1 C5\n", "invisible formatting");
  rejects("piece Bells\x1b[2J\nringers 3\n1:1 C5\n", "control");
  rejects("ringers 3\nrm -rf SECRET\n", "lines are piece");
  rejects("ringers 3\n# " + std::string(300, 'x') + "\n1:1 C5\n", "longer than 200");
  rejects(std::string(70000, '#'), "larger than 64 KB");
  rejects("ringers 3\n1:1 C5\xff\n", "UTF-8");

  // ---------- The command line ----------
  {
    std::ostringstream out, err;
    std::istringstream none;
    check(run({"examples/evening-chime.txt"}, none, out, err) == 0, "the example runs");
    check(out.str().find("In all: 15 bell changes, 0 tight.") != std::string::npos, "the example's total");
    std::ifstream f("examples/evening-chime.txt");
    std::stringstream buf;
    buf << f.rdbuf();
    std::istringstream in(buf.str());
    std::ostringstream out2, err2;
    check(run({"-"}, in, out2, err2) == 0 && out2.str() == out.str(), "standard input gives the same");
  }
  {
    std::ostringstream out, err;
    std::istringstream in("ringers 1\n1:1 C5 E5 G5\n");
    check(run({"-"}, in, out, err) == 1 && out.str().find("three bells at once at m1:1") != std::string::npos, "an impossible piece exits 1 and says where");
  }
  {
    std::ostringstream out, err;
    std::istringstream none;
    check(run({"tests"}, none, out, err) == 2 && err.str().find("regular file") != std::string::npos, "a folder is refused");
    std::ostringstream e2;
    check(run({"secret-name-zz.txt"}, none, out, e2) == 2 && e2.str().find("secret-name") == std::string::npos, "the path isn't echoed");
    const auto dir = std::filesystem::temp_directory_path() / "bellshare-test";
    std::filesystem::create_directories(dir);
    const auto link = dir / "link.txt";
    std::filesystem::remove(link);
    std::filesystem::create_symlink(std::filesystem::absolute("examples/evening-chime.txt"), link);
    std::ostringstream e3;
    check(run({link.string()}, none, out, e3) == 2, "a symbolic link is refused");
    std::filesystem::remove_all(dir);
    std::istringstream big(std::string(100000, '#'));
    std::ostringstream e4;
    check(run({"-"}, big, out, e4) == 2 && e4.str().find("64 KB") != std::string::npos, "big input refused");
    std::ostringstream e5;
    check(run({}, none, out, e5) == 2 && run({"a", "b"}, none, out, e5) == 2, "usage");
  }

  std::cout << checks << " checks, " << failed << " failed\n";
  return failed == 0 ? 0 : 1;
}
