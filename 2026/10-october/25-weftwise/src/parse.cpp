#include "parse.hpp"

#include <algorithm>
#include <sstream>
#include <vector>

namespace weftwise {
namespace {

[[noreturn]] void fail(int line, const std::string& what) {
  if (line > 0) throw InputError{"line " + std::to_string(line) + ": " + what};
  throw InputError{what};
}

// Valid UTF-8, no control characters (terminal escapes) and no invisible direction or
// zero-width marks, which can make a file read differently from how it prints.
void checkText(std::string_view text) {
  int line = 1;
  for (std::size_t i = 0; i < text.size();) {
    auto c = static_cast<unsigned char>(text[i]);
    if (c == '\n') { ++line; ++i; continue; }
    if (c < 0x80) {
      if ((c < 0x20 && c != '\t' && c != '\r') || c == 0x7f) fail(line, "contains a control or hidden character");
      ++i;
      continue;
    }
    std::size_t n = (c >= 0xf0 && c <= 0xf4) ? 4 : (c >= 0xe0) ? 3 : (c >= 0xc2 && c <= 0xdf) ? 2 : 0;
    if (n == 0 || i + n > text.size()) fail(line, "is not valid UTF-8");
    std::uint32_t cp = c & (n == 2 ? 0x1fu : n == 3 ? 0x0fu : 0x07u);
    for (std::size_t k = 1; k < n; ++k) {
      auto cc = static_cast<unsigned char>(text[i + k]);
      if ((cc & 0xc0) != 0x80) fail(line, "is not valid UTF-8");
      cp = (cp << 6) | (cc & 0x3fu);
    }
    const bool overlong = (n == 3 && cp < 0x800) || (n == 4 && (cp < 0x10000 || cp > 0x10ffff));
    if (overlong || (cp >= 0xd800 && cp <= 0xdfff)) fail(line, "is not valid UTF-8");
    const bool hidden = (cp >= 0x200b && cp <= 0x200f) || (cp >= 0x202a && cp <= 0x202e) ||
                        (cp >= 0x2066 && cp <= 0x2069) || cp == 0xfeff || (cp >= 0x80 && cp <= 0x9f);
    if (hidden) fail(line, "contains a control or hidden character");
    i += n;
  }
}

std::vector<std::string> words(const std::string& s) {
  std::vector<std::string> out;
  std::istringstream in(s);
  for (std::string w; in >> w;) out.push_back(w);
  return out;
}

std::string join(const std::vector<std::string>& w, std::size_t from, std::size_t to) {
  std::string out;
  for (std::size_t i = from; i < to; ++i) out += (i > from ? " " : "") + w[i];
  return out;
}

std::string checkedName(const std::string& name, int line, const char* what) {
  if (name.empty()) fail(line, std::string(what) + " needs a name");
  if (name.size() > kMaxName) fail(line, std::string(what) + " names are at most 60 characters");
  for (char c : name) {
    const bool ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') ||
                    std::string_view(" -'&().,").find(c) != std::string_view::npos;
    if (!ok) fail(line, std::string(what) + " names use letters, digits, spaces and - ' & ( ) . , only");
  }
  return name;
}

Len length(const std::string& s, Len min, Len max, int line, const std::string& what) {
  auto v = parseInches(s, max);
  if (!v || *v < min) {
    fail(line, what + " must be between " + inches(min) + " and " + inches(max) +
                   " inches, written like 6.5 or 6-1/2 and exact to 1/8 inch");
  }
  return *v;
}

void parsePiece(const std::vector<std::string>& w, Fabric& fabric, int line) {
  auto x = std::find(w.begin(), w.end(), "x");
  if (x == w.end() || x - w.begin() < 3 || x + 1 == w.end()) {
    fail(line, "write pieces as: piece <name> <across> x <along> [count N] [lengthwise | join]");
  }
  auto xi = static_cast<std::size_t>(x - w.begin());
  Piece p;
  p.line = line;
  p.name = checkedName(join(w, 1, xi - 1), line, "piece");
  p.across = length(w[xi - 1], kInch / 2, 600 * kInch, line, "piece sizes");
  p.along = length(w[xi + 1], kInch / 2, 600 * kInch, line, "piece sizes");
  for (std::size_t i = xi + 2; i < w.size(); ++i) {
    if (w[i] == "count" && i + 1 < w.size()) {
      const std::string& n = w[++i];
      if (n.empty() || n.size() > 3 || !std::all_of(n.begin(), n.end(), [](char c) { return c >= '0' && c <= '9'; }) ||
          std::stoi(n) < 1 || std::stoi(n) > kMaxCount) {
        fail(line, "count must be a whole number from 1 to " + std::to_string(kMaxCount));
      }
      p.count = std::stoi(n);
    } else if (w[i] == "lengthwise" && p.cut == Cut::Crosswise) {
      p.cut = Cut::Lengthwise;
    } else if (w[i] == "join" && p.cut == Cut::Crosswise) {
      p.cut = Cut::Joined;
    } else {
      fail(line, "after the size, a piece can only have 'count N' and one of 'lengthwise' or 'join'");
    }
  }
  for (const auto& other : fabric.pieces) {
    if (other.name == p.name) fail(line, "this fabric already has a piece with that name");
  }
  if (fabric.pieces.size() >= kMaxPieceTypes) fail(line, "a fabric can have at most 12 kinds of piece");
  fabric.pieces.push_back(p);
}

// Checks every piece against the fabric's final width, and puts long pieces the right way round.
void finish(Fabric& f) {
  const Len w = f.usableWidth();
  if (w < 8 * kInch) fail(f.line, "after trimming selvages and shrinkage, this fabric is narrower than 8 inches");
  if (f.pieces.empty()) fail(f.line, "this fabric has no pieces");
  int total = 0;
  for (auto& p : f.pieces) {
    total += p.count;
    if (p.cut == Cut::Joined) {
      if (p.across > p.along) std::swap(p.across, p.along);  // across = strip width, along = total length
      if (p.across > 12 * kInch || 3 * p.across > w) fail(p.line, "joined strips must be at most 12 inches wide and a third of the usable width");
      if (p.along <= w) {  // short enough to cut in one go: lay it along a strip
        std::swap(p.across, p.along);
        p.cut = Cut::Crosswise;
      }
      continue;
    }
    if (p.cut == Cut::Lengthwise) {
      if (!f.directional && p.across > p.along) std::swap(p.across, p.along);
      if (p.across > w) fail(p.line, "this lengthwise piece is wider than the usable width (" + inches(w) + " inches)");
      continue;
    }
    const bool fits = p.across <= w || (!f.directional && p.along <= w);
    if (!fits) {
      fail(p.line, "this piece is longer than the usable width (" + inches(w) +
                       " inches): mark it 'lengthwise' to cut it along the selvage, or 'join' to piece it from strips");
    }
  }
  if (total > 2000) fail(f.line, "a fabric can have at most 2000 pieces in all");
}

}  // namespace

Quilt parse(std::string_view text) {
  if (text.size() > kMaxInput) fail(0, "the file is larger than 64 KB");
  if (text.substr(0, 3) == "\xEF\xBB\xBF") text.remove_prefix(3);
  checkText(text);

  Quilt q;
  bool sawQuilt = false, sawStraighten = false;
  std::istringstream in{std::string(text)};
  int line = 0;
  for (std::string raw; std::getline(in, raw);) {
    ++line;
    if (raw.size() > 200) fail(line, "is longer than 200 characters");
    if (auto hash = raw.find('#'); hash != std::string::npos) raw.erase(hash);
    auto w = words(raw);
    if (w.empty()) continue;
    const std::string& key = w[0];
    Fabric* f = q.fabrics.empty() ? nullptr : &q.fabrics.back();
    auto needFabric = [&] {
      if (!f) fail(line, "'" + key + "' belongs under a 'fabric' line");
    };
    auto oneValue = [&] {
      if (w.size() != 2) fail(line, "'" + key + "' takes exactly one value");
    };

    if (key == "quilt") {
      if (sawQuilt || f) fail(line, "'quilt' comes once, before the first fabric");
      q.name = checkedName(join(w, 1, w.size()), line, "quilt");
      sawQuilt = true;
    } else if (key == "straighten") {
      oneValue();
      if (sawStraighten || f) fail(line, "'straighten' comes once, before the first fabric");
      q.straighten = length(w[1], 0, 12 * kInch, line, "straighten");
      sawStraighten = true;
    } else if (key == "fabric") {
      if (q.fabrics.size() >= kMaxFabrics) fail(line, "at most 12 fabrics");
      Fabric nf;
      nf.line = line;
      nf.name = checkedName(join(w, 1, w.size()), line, "fabric");
      for (const auto& other : q.fabrics) {
        if (other.name == nf.name) fail(line, "there is already a fabric with that name");
      }
      q.fabrics.push_back(nf);
    } else if (key == "width") {
      needFabric();
      oneValue();
      f->width = length(w[1], 10 * kInch, 120 * kInch, line, "width");
    } else if (key == "selvage") {
      needFabric();
      oneValue();
      f->selvage = length(w[1], 0, 2 * kInch, line, "selvage");
    } else if (key == "shrink") {
      needFabric();
      oneValue();
      auto s = parsePercentTenths(w[1]);
      if (!s) fail(line, "shrink is a percentage from 0% to 10%, like 3% or 2.5%");
      f->shrinkTenths = *s;
    } else if (key == "directional") {
      needFabric();
      if (w.size() != 1) fail(line, "'directional' takes no value");
      f->directional = true;
    } else if (key == "piece") {
      needFabric();
      parsePiece(w, *f, line);
    } else {
      fail(line, "lines start with quilt, straighten, fabric, width, selvage, shrink, directional or piece");
    }
  }
  if (q.fabrics.empty()) fail(0, "the file has no fabrics");
  for (auto& f : q.fabrics) finish(f);
  return q;
}

}  // namespace weftwise
