// Padline: where to put your bouldering crash pads so they cover where you'd actually land.
#pragma once

#include <cstddef>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace padline {

inline constexpr double kCell = 0.1;  // metres per grid cell
inline constexpr std::size_t kMaxHolds = 60;
inline constexpr std::size_t kMaxPads = 12;
inline constexpr std::size_t kMaxRocks = 40;
inline constexpr std::size_t kMaxBytes = 32 * 1024;

struct Hold {
    double x = 0, height = 0;  // along the wall, and how high your feet are when you fall from it
    bool crux = false, topout = false;
};
struct Rock {
    double x = 0, out = 0, radius = 0;  // a rock or root on the ground: along, out from the wall, size
};
struct Pad {
    double length = 0, width = 0;
    std::string name;
};
struct Problem {
    double along = 0, out = 0;  // the ground in front of the boulder
    std::vector<Hold> holds;
    std::vector<Rock> rocks;
    std::vector<Pad> pads;
};

struct ParseError {
    int line;
    std::string message;
};

// Reads a problem description, or says which line is wrong.
std::optional<Problem> parse(std::string_view text, ParseError& error);

// How much a fall onto each ground cell would hurt, summed over every hold you could fall from.
class Risk {
public:
    explicit Risk(const Problem& p);
    [[nodiscard]] int cols() const { return cols_; }
    [[nodiscard]] int rows() const { return rows_; }
    [[nodiscard]] double at(int c, int r) const { return cell_[static_cast<std::size_t>(r) * cols_ + c]; }
    [[nodiscard]] double total() const { return total_; }
    // Sum over a rectangle of cells [c0, c1) x [r0, r1), in O(1) from prefix sums.
    [[nodiscard]] double sum(int c0, int r0, int c1, int r1) const;

private:
    int cols_, rows_;
    std::vector<double> cell_, prefix_;
    double total_ = 0;
};

struct Placement {
    int pad = 0;  // index into Problem::pads
    int c = 0, r = 0, w = 0, h = 0;  // cells: column (along), row (out), width and height
};

struct Plan {
    std::vector<Placement> placed;
    double covered = 0;  // risk under pads
    double total = 0;
};

// Places every pad to cover as much risk as possible without overlapping: greedy, then
// re-placing one pad at a time while that helps.
Plan place(const Problem& p, const Risk& risk);

// The best two-pad placement by trying every pair (for tests).
double brute_two(const Problem& p, const Risk& risk);

}  // namespace padline
