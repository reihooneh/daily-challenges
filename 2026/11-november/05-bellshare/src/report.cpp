// The assignment chart, each ringer's bell changes, and the reading of files.
#include <cmath>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <optional>
#include <sstream>

#include "bellshare.hpp"

namespace bellshare {

namespace {

std::string bellList(const std::vector<int>& bells) {
  std::string s;
  for (int b : bells) s += (s.empty() ? "" : " ") + noteName(b);
  return s;
}

std::string summary(const Piece& p, const Assignment& a) {
  int changes = 0, tight = 0, clashes = 0;
  double firstClash = INFINITY;
  for (const auto& l : a.loads) {
    changes += static_cast<int>(l.changes.size());
    tight += l.tight;
    clashes += l.clashes;
    if (!l.possible) firstClash = std::min(firstClash, l.firstClash);
  }
  std::ostringstream o;
  if (clashes) o << "can't be rung: a ringer needs three bells at once at " << where(p, firstClash);
  else o << changes << " bell change" << (changes == 1 ? "" : "s") << ", " << tight << " tight";
  for (std::size_t i = 0; i < a.ringers.size(); ++i)
    if (static_cast<int>(a.ringers[i].size()) > p.maxBells) o << "; ringer " << i + 1 << " has more than " << p.maxBells << " bells";
  return o.str();
}

}  // namespace

std::string render(const Piece& p) {
  const Assignment a = best(p);
  const Assignment eq = equalSplit(p);
  const std::vector<int> bells = bellsUsed(p);
  std::ostringstream o;
  o << "BELLSHARE  " << p.title << '\n';
  o << p.ringers << " ringer" << (p.ringers == 1 ? "" : "s") << ", " << bells.size() << " bells (" << noteName(bells.front()) << " to "
    << noteName(bells.back()) << "), " << p.chords.size() << " chords; a bell change needs " << p.swapBeats << " beat"
    << (p.swapBeats == 1 ? "" : "s") << ", at most " << p.maxBells << " bells each.\n\n";

  if (a.possible) o << "The best split of the bells, in pitch order:\n";
  else o << "No split works without a ringer needing three bells at once or too many bells. The least bad:\n";
  for (std::size_t i = 0; i < a.ringers.size(); ++i) {
    const Load& l = a.loads[i];
    std::ostringstream what;
    if (!l.possible) what << "three bells at once at " << where(p, l.firstClash);
    else if (l.changes.empty()) what << "no changes";
    else what << l.changes.size() << " change" << (l.changes.size() == 1 ? "" : "s") << (l.tight ? ", " + std::to_string(l.tight) + " tight" : "");
    o << "  Ringer " << std::setw(2) << i + 1 << "  " << std::left << std::setw(22) << bellList(a.ringers[i]) << std::right << what.str()
      << '\n';
  }
  if (static_cast<int>(bells.size()) < p.ringers) o << "  (" << p.ringers - static_cast<int>(bells.size()) << " ringers have no bells in this piece.)\n";
  o << "\nIn all: " << summary(p, a) << ".\n";
  o << "An equal share of bells each would give: " << summary(p, eq) << ".\n";

  bool any = false;
  for (std::size_t i = 0; i < a.ringers.size(); ++i) {
    for (const auto& c : a.loads[i].changes) {
      if (!any) o << "\nBell changes to mark in the music ('TIGHT' means less than " << p.swapBeats << " beat"
                  << (p.swapBeats == 1 ? "" : "s") << " to do it):\n";
      any = true;
      o << "  Ringer " << std::setw(2) << i + 1 << "  " << std::left << std::setw(9) << where(p, c.time) << std::right << "put down "
        << std::left << std::setw(4) << noteName(c.down) << std::right << " pick up " << std::left << std::setw(4) << noteName(c.up)
        << std::right;
      if (std::isfinite(c.room)) o << "  (" << c.room << " beat" << (c.room == 1 ? "" : "s") << " free)";
      if (c.tight) o << "  TIGHT";
      o << '\n';
    }
  }
  if (!any) o << "\nNobody changes bells: every ringer keeps their two bells in hand all the way through.\n";
  return o.str();
}

namespace {

std::string readBounded(std::istream& in) {
  std::string data(kMaxInput + 1, '\0');
  in.read(data.data(), static_cast<std::streamsize>(data.size()));
  data.resize(static_cast<std::size_t>(in.gcount()));
  return data;
}

std::optional<std::string> readFile(const std::string& path) {
  std::error_code ec;
  if (std::filesystem::is_symlink(std::filesystem::symlink_status(path, ec)) || ec) return std::nullopt;
  if (!std::filesystem::is_regular_file(path, ec) || ec) return std::nullopt;
  std::ifstream f(path, std::ios::binary);
  if (!f) return std::nullopt;
  return readBounded(f);
}

}  // namespace

int run(const std::vector<std::string>& args, std::istream& in, std::ostream& out, std::ostream& err) {
  if (args.size() != 1 || args[0].rfind("--", 0) == 0 || args[0] == "-h") {
    err << "usage: bellshare <piece.txt>   (or - to read standard input)\n";
    return 2;
  }
  const std::optional<std::string> text = args[0] == "-" ? std::optional<std::string>(readBounded(in)) : readFile(args[0]);
  if (!text) {
    err << "bellshare: the piece file could not be read (it must be a regular file, not a link)\n";
    return 2;
  }
  if (text->size() > kMaxInput) {
    err << "bellshare: the piece file is larger than 64 KB\n";
    return 2;
  }
  std::string body = *text;
  if (body.rfind("\xEF\xBB\xBF", 0) == 0) body.erase(0, 3);
  try {
    const Piece p = parse(body);
    out << render(p);
    return best(p).possible ? 0 : 1;
  } catch (const InputError& e) {
    err << "bellshare: " << e.what() << '\n';
    return 2;
  }
}

}  // namespace bellshare
