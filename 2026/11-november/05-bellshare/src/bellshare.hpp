// Bellshare: shares out the bells of a handbell piece among the ringers so that nobody needs
// three hands, and the bell changes are as few and as comfortable as possible.
#pragma once

#include <cstddef>
#include <iosfwd>
#include <limits>
#include <stdexcept>
#include <string>
#include <vector>

namespace bellshare {

constexpr std::size_t kMaxInput = 64 * 1024;
constexpr std::size_t kMaxLine = 200;
constexpr std::size_t kMaxChords = 4000;
constexpr int kMaxRingers = 20;

// A problem in the piece file. The message never repeats the input.
struct InputError : std::runtime_error {
  using std::runtime_error::runtime_error;
};

// One moment in the piece: when (in beats from the start) and which bells sound together.
struct Chord {
  double time = 0;
  std::vector<int> notes;  // MIDI numbers, sorted, no repeats
  int line = 0;
};

struct Piece {
  std::string title = "A handbell piece";
  int ringers = 0;
  int maxBells = 6;           // most bells one ringer may have at their station
  double swapBeats = 1.0;     // beats needed to put one bell down and pick up another
  int beatsPerMeasure = 4;
  std::vector<Chord> chords;  // in time order
};

// Note names: C4 is middle C (MIDI 60); sharps (#) and flats (b) share a bell.
int parseNote(const std::string& text);  // -1 if not a note in C2..C9
std::string noteName(int midi);          // C4, C#4, D4 ...

Piece parse(const std::string& text);

// What ringing a set of bells means for one ringer.
struct Change {
  double time = 0;
  int down = 0;     // bell put down
  int up = 0;       // bell picked up
  double room = 0;  // beats the hand had free to do it
  bool tight = false;
};

struct Load {
  bool possible = true;   // never more than two bells at once
  int clashes = 0;        // moments when three or more of these bells sound together
  double firstClash = 0;  // the first of them
  std::vector<Change> changes;
  int tight = 0;
  int rung = 0;  // strikes
};

// Plays a ringer's bells through the piece with two hands. A hand holds one bell at a time; when
// a bell is needed that isn't in hand, the bell not needed for longest is put down (Belady's rule,
// which gives the fewest changes). A change is tight if the hand had less than swapBeats free.
Load play(const Piece& p, const std::vector<int>& bells);

struct Assignment {
  std::vector<std::vector<int>> ringers;  // each ringer's bells, low to high
  std::vector<Load> loads;
  bool possible = true;
  double cost = std::numeric_limits<double>::infinity();
};

// The cost a plan is judged by: changes, each tight change counting kTightWeight, and anything
// impossible (three bells at once, or more bells than a ringer may have) counting kImpossible.
constexpr double kTightWeight = 10.0;
constexpr double kImpossible = 1000.0;
double cost(const Load& l);

// The best way to split the bells, in pitch order, into one run per ringer (dynamic programming).
Assignment best(const Piece& p);
// Every ringer gets the same number of bells (give or take one), in pitch order.
Assignment equalSplit(const Piece& p);
// Builds an assignment from given runs.
Assignment evaluate(const Piece& p, const std::vector<std::vector<int>>& runs);

std::vector<int> bellsUsed(const Piece& p);
std::string where(const Piece& p, double time);  // "m7:2"

std::string render(const Piece& p);
int run(const std::vector<std::string>& args, std::istream& in, std::ostream& out, std::ostream& err);

}  // namespace bellshare
