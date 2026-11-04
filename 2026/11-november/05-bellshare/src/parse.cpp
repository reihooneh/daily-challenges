// The piece file. Every line has a fixed shape and every number a range; errors give the line
// number and what was expected, never the text of the line.
#include <algorithm>
#include <cctype>
#include <cmath>
#include <regex>
#include <sstream>

#include "bellshare.hpp"

namespace bellshare {
namespace {

[[noreturn]] void fail(int line, const std::string& msg) {
  throw InputError(line > 0 ? "line " + std::to_string(line) + ": " + msg : msg);
}

double number(const std::string& s, int line, const std::string& what, double lo, double hi) {
  static const std::regex kNum(R"(\d{1,3}(\.\d{1,3})?)");
  if (!std::regex_match(s, kNum)) fail(line, what + " must be a number like 2 or 1.5");
  const double v = std::stod(s);
  if (v < lo || v > hi) {
    std::ostringstream o;
    o << what << " must be from " << lo << " to " << hi;
    fail(line, o.str());
  }
  return v;
}

int whole(const std::string& s, int line, const std::string& what, int lo, int hi) {
  const double v = number(s, line, what, lo, hi);
  if (v != std::floor(v)) fail(line, what + " must be a whole number");
  return static_cast<int>(v);
}

// Control characters, and the UTF-8 encodings of invisible formatting characters (zero-width
// spaces and joiners, direction marks and overrides, the byte-order mark).
bool hidden(const std::string& s) {
  for (std::size_t i = 0; i < s.size(); ++i) {
    const auto c = static_cast<unsigned char>(s[i]);
    if ((c < 0x20 && c != '\t') || c == 0x7f) return true;
    if (c == 0xe2 && i + 2 < s.size()) {
      const auto b = static_cast<unsigned char>(s[i + 1]);
      const auto d = static_cast<unsigned char>(s[i + 2]);
      if (b == 0x80 && ((d >= 0x8b && d <= 0x8f) || (d >= 0xaa && d <= 0xae))) return true;
      if (b == 0x81 && d >= 0xa0 && d <= 0xaf) return true;
    }
    if (c == 0xef && i + 2 < s.size() && static_cast<unsigned char>(s[i + 1]) == 0xbb &&
        static_cast<unsigned char>(s[i + 2]) == 0xbf)
      return true;
  }
  return false;
}

bool validUtf8(const std::string& s) {
  std::size_t i = 0;
  while (i < s.size()) {
    const auto c = static_cast<unsigned char>(s[i]);
    std::size_t n = c < 0x80 ? 1 : (c >> 5) == 6 ? 2 : (c >> 4) == 14 ? 3 : (c >> 3) == 30 ? 4 : 0;
    if (n == 0 || i + n > s.size()) return false;
    for (std::size_t k = 1; k < n; ++k)
      if ((static_cast<unsigned char>(s[i + k]) & 0xc0) != 0x80) return false;
    i += n;
  }
  return true;
}

}  // namespace

int parseNote(const std::string& text) {
  static const std::regex kNote(R"(([A-G])([#b]?)([0-9]))");
  std::smatch m;
  if (!std::regex_match(text, m, kNote)) return -1;
  static const int kBase[] = {9, 11, 0, 2, 4, 5, 7};  // A B C D E F G
  int semis = kBase[m[1].str()[0] - 'A'];
  if (m[2] == "#") semis += 1;
  if (m[2] == "b") semis -= 1;
  const int midi = (m[3].str()[0] - '0' + 1) * 12 + semis;
  if (midi < 36 || midi > 120) return -1;  // C2 .. C9: every handbell and handchime made
  return midi;
}

std::string noteName(int midi) {
  static const char* kNames[] = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"};
  return std::string(kNames[midi % 12]) + std::to_string(midi / 12 - 1);
}

Piece parse(const std::string& text) {
  if (text.size() > kMaxInput) fail(0, "the piece file is larger than 64 KB");
  if (!validUtf8(text)) fail(0, "the piece file is not valid UTF-8 text");
  Piece p;
  bool seenTitle = false;
  bool chordsStarted = false;
  std::istringstream in(text);
  std::string raw;
  int n = 0;
  static const std::regex kTitle(R"([A-Za-z0-9][A-Za-z0-9 '.,&()!-]{0,59})");
  static const std::regex kWhen(R"((\d{1,4}):(\d{1,2}(?:\.\d{1,3})?))");
  while (std::getline(in, raw)) {
    ++n;
    if (!raw.empty() && raw.back() == '\r') raw.pop_back();
    if (raw.size() > kMaxLine) fail(n, "is longer than " + std::to_string(kMaxLine) + " characters");
    if (hidden(raw)) fail(n, "contains a control or invisible formatting character");
    std::string line = raw.substr(0, raw.find('#'));
    std::istringstream words(line);
    std::vector<std::string> w;
    for (std::string x; words >> x;) w.push_back(x);
    if (w.empty()) continue;
    const std::string& head = w[0];
    std::smatch when;
    if (head == "piece") {
      std::string title = line.substr(line.find("piece") + 5);
      title.erase(0, title.find_first_not_of(" \t"));
      title.erase(title.find_last_not_of(" \t") + 1);
      if (seenTitle || !std::regex_match(title, kTitle)) fail(n, "the piece's name comes once: letters, digits, spaces and ' . , & ( ) ! - (up to 60)");
      p.title = title;
      seenTitle = true;
    } else if (head == "ringers" && w.size() == 2) {
      p.ringers = whole(w[1], n, "the number of ringers", 1, kMaxRingers);
    } else if (head == "max-bells" && w.size() == 2) {
      p.maxBells = whole(w[1], n, "the most bells for one ringer", 2, 12);
    } else if (head == "swap" && w.size() == 2) {
      p.swapBeats = number(w[1], n, "the beats needed to change a bell", 0, 8);
    } else if (head == "time" && w.size() == 2 && w[1].size() >= 3 && w[1].substr(w[1].size() - 2) == "/4") {
      if (chordsStarted) fail(n, "set the time signature before the first chord");
      p.beatsPerMeasure = whole(w[1].substr(0, w[1].size() - 2), n, "beats in a measure", 1, 12);
    } else if (std::regex_match(head, when, kWhen)) {
      chordsStarted = true;
      const int measure = whole(when[1].str(), n, "a measure number", 1, 9999);
      const double beat = number(when[2].str(), n, "a beat", 1, p.beatsPerMeasure + 0.999);
      Chord c;
      c.time = (measure - 1) * p.beatsPerMeasure + (beat - 1);
      c.line = n;
      if (w.size() < 2) fail(n, "a chord needs at least one note, like '3:1 C5 E5 G5'");
      if (w.size() > 13) fail(n, "at most 12 notes sound at once");
      for (std::size_t i = 1; i < w.size(); ++i) {
        const int midi = parseNote(w[i]);
        if (midi < 0) fail(n, "notes are written like C5, F#4 or Bb5 (C2 to C9)");
        c.notes.push_back(midi);
      }
      std::sort(c.notes.begin(), c.notes.end());
      c.notes.erase(std::unique(c.notes.begin(), c.notes.end()), c.notes.end());
      if (!p.chords.empty() && c.time <= p.chords.back().time) fail(n, "each chord must come after the one before it");
      if (p.chords.size() >= kMaxChords) fail(n, "at most " + std::to_string(kMaxChords) + " chords");
      p.chords.push_back(c);
    } else {
      fail(n, "lines are piece, ringers, max-bells, swap, time or a chord like '3:1 C5 E5 G5'");
    }
  }
  if (p.ringers == 0) fail(0, "say how many ringers there are, like 'ringers 5'");
  if (p.chords.empty()) fail(0, "the piece has no chords");
  return p;
}

}  // namespace bellshare
