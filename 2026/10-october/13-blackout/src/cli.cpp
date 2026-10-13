#include "cli.hpp"

#include <filesystem>
#include <fstream>
#include <istream>
#include <ostream>
#include <sstream>
#include <string>
#include <vector>

namespace blackout {

namespace {

const char* const kUsage =
    "usage: blackout [--style cryptic|american] [--fix] [--max 1-4] [--entries] GRID   (use - for standard input)";

std::string entryName(const Grid& g, const Analysis& a, int cell, bool across) {
  int r = cell / g.cols;
  int c = cell % g.cols;
  for (const Entry& e : a.entries) {
    if (e.row == r && e.col == c && e.across == across) {
      return std::to_string(e.number) + (across ? " Across" : " Down");
    }
  }
  return std::string(across ? "the across entry at " : "the down entry at ") + where(g, cell);
}

// Reads at most kMaxBytes + 1 bytes, so a huge file or an endless stream is refused, not loaded.
std::string readLimited(std::istream& in) {
  std::string data(kMaxBytes + 1, '\0');
  in.read(&data[0], static_cast<std::streamsize>(data.size()));
  data.resize(static_cast<std::size_t>(in.gcount()));
  return data;
}

std::string readGrid(const std::string& path, std::istream& in) {
  if (path == "-") return readLimited(in);
  std::error_code ec;
  if (!std::filesystem::is_regular_file(path, ec) || ec) throw InputError("the grid file could not be read");
  std::ifstream file(path, std::ios::binary);
  if (!file) throw InputError("the grid file could not be read");
  return readLimited(file);
}

// Only plain characters from a file name reach the terminal.
std::string safeName(const std::string& path) {
  if (path == "-") return "standard input";
  std::string name = std::filesystem::path(path).filename().string();
  for (char& ch : name) {
    bool plain = (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') ||
                 ch == '.' || ch == '-' || ch == '_' || ch == ' ';
    if (!plain) ch = '?';
  }
  return name.substr(0, 80);
}

}  // namespace

std::string where(const Grid& g, int cell) {
  return "r" + std::to_string(cell / g.cols + 1) + " c" + std::to_string(cell % g.cols + 1);
}

std::string describe(const Grid& g, const Analysis& a, const Problem& p) {
  switch (p.kind) {
    case Kind::NoWhite:
      return "The grid has no white squares to fill in.";
    case Kind::Asymmetric:
      return where(g, p.cell) + " and " + where(g, p.value) +
             ": one is black and the other white, so the grid is not the same upside down.";
    case Kind::Disconnected:
      return std::to_string(p.value) + " white square" + (p.value == 1 ? " is" : "s are") + " cut off from the rest (from " +
             where(g, p.cell) + ").";
    case Kind::TwoLetter:
      return entryName(g, a, p.cell, p.across) + " has only 2 letters; entries need at least 3.";
    case Kind::Unchecked:
      return where(g, p.cell) + " is only in " + (p.across ? "an across" : "a down") +
             " entry; in an American grid every square is in both.";
    case Kind::Orphan:
      return where(g, p.cell) + " is a white square that is in no entry.";
    case Kind::UnderChecked: {
      int len = static_cast<int>(p.cells.size());
      return entryName(g, a, p.cell, p.across) + " (" + std::to_string(len) + ") has only " + std::to_string(p.value) +
             " letters crossed by other entries; at least " + std::to_string(len / 2) + " should be.";
    }
    case Kind::DoubleUnch:
      return entryName(g, a, p.cells.front(), p.across) + " has two uncrossed letters in a row, from " +
             where(g, p.cell) + ".";
  }
  return "Unknown problem.";
}

std::string report(const Grid& g, Style style, const Analysis& a, const std::string& name, bool listEntries) {
  std::ostringstream out;
  int across = 0;
  for (const Entry& e : a.entries) across += e.across ? 1 : 0;
  int down = static_cast<int>(a.entries.size()) - across;
  out << "BLACKOUT  " << name << "  (" << g.rows << " x " << g.cols << ", "
      << (style == Style::Cryptic ? "cryptic" : "American") << " rules)\n";
  out << "Black squares: " << a.black << " of " << g.size() << " (" << (a.black * 100 + g.size() / 2) / g.size()
      << "%)   Entries: " << a.entries.size() << " (" << across << " across, " << down << " down)\n";
  if (style == Style::American && a.black * 6 > g.size()) {
    out << "Note: more than 1 in 6 squares are black, which is more than most published American grids.\n";
  }
  if (listEntries) {
    out << "\nENTRIES\n";
    for (int dir = 0; dir < 2; ++dir) {
      out << (dir == 0 ? "  Across:" : "  Down:  ");
      for (const Entry& e : a.entries) {
        if (e.across == (dir == 0)) out << ' ' << e.number << " (" << e.length << ")";
      }
      out << '\n';
    }
  }
  out << '\n';
  if (a.problems.empty()) {
    out << "No problems: the grid follows every " << (style == Style::Cryptic ? "cryptic" : "American") << " rule.\n";
  } else {
    out << "PROBLEMS (" << a.problems.size() << ")\n";
    for (const Problem& p : a.problems) out << "  " << describe(g, a, p) << '\n';
  }
  return out.str();
}

std::string fixReport(const Grid& g, const FixResult& fix) {
  std::ostringstream out;
  out << '\n';
  if (!fix.found) {
    out << "NO SMALL FIX: nothing with " << fix.searchedUpTo << " move" << (fix.searchedUpTo == 1 ? "" : "s")
        << " or fewer passes every rule";
    if (fix.stopped) {
      out << ".\nThe search stopped after trying " << fix.tried << " grids; fix the problems above by hand first.\n";
    } else {
      out << ".\nTry a bigger --max (up to 4), or fix the problems above by hand first.\n";
    }
    return out.str();
  }
  out << "SMALLEST FIX: change " << fix.changed.size() << " square" << (fix.changed.size() == 1 ? "" : "s");
  if (fix.others > 0) out << "  (" << fix.others << " other fix" << (fix.others == 1 ? "" : "es") << " of the same size)";
  out << '\n';
  for (int cell : fix.changed) {
    out << "  " << where(g, cell) << " -> " << (fix.grid.black(cell) ? "black" : "white") << '\n';
  }
  out << "\n  New grid (* newly black, o newly white):\n";
  for (int r = 0; r < g.rows; ++r) {
    out << "  ";
    for (int c = 0; c < g.cols; ++c) {
      int i = g.index(r, c);
      bool changed = g.black(i) != fix.grid.black(i);
      out << (changed ? (fix.grid.black(i) ? '*' : 'o') : fix.grid.cells[static_cast<std::size_t>(i)]);
    }
    out << '\n';
  }
  if (!fix.exact) out << "\n  (A big grid: only moves near the problems were tried.)\n";
  if (fix.stopped) out << "\n  (The search stopped early, so a different fix of this size may drift less.)\n";
  return out.str();
}

int run(const std::vector<std::string>& args, std::istream& in, std::ostream& out, std::ostream& err) {
  try {
    Style style = Style::Cryptic;
    bool doFix = false;
    bool listEntries = false;
    FixOptions options;
    std::string path;
    bool havePath = false;
    for (std::size_t i = 0; i < args.size(); ++i) {
      const std::string& a = args[i];
      if (a == "--style") {
        if (i + 1 >= args.size()) throw InputError("--style needs cryptic or american");
        const std::string& v = args[++i];
        if (v == "cryptic") {
          style = Style::Cryptic;
        } else if (v == "american") {
          style = Style::American;
        } else {
          throw InputError("--style must be cryptic or american");
        }
      } else if (a == "--max") {
        if (i + 1 >= args.size()) throw InputError("--max needs a number from 1 to 4");
        const std::string& v = args[++i];
        if (v.size() != 1 || v[0] < '1' || v[0] > '4') throw InputError("--max must be a number from 1 to 4");
        options.maxMoves = v[0] - '0';
        doFix = true;
      } else if (a == "--fix") {
        doFix = true;
      } else if (a == "--entries") {
        listEntries = true;
      } else if (a == "-h" || a == "--help") {
        out << kUsage << '\n';
        return 0;
      } else if (!a.empty() && a[0] == '-' && a != "-") {
        throw InputError("unknown option");
      } else {
        if (havePath) throw InputError("give exactly one grid");
        path = a;
        havePath = true;
      }
    }
    if (!havePath) throw InputError("give a grid to check");

    Grid g = parse(readGrid(path, in));
    Analysis a = analyse(g, style);
    out << report(g, style, a, safeName(path), listEntries);
    if (doFix && !a.problems.empty()) out << fixReport(g, findFix(g, style, options));
    return a.problems.empty() ? 0 : 1;
  } catch (const InputError& e) {
    err << "blackout: " << e.what() << '\n' << kUsage << '\n';
    return 2;
  }
}

}  // namespace blackout
