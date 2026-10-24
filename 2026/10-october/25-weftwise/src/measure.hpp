// Lengths are whole eighths of an inch, the finest mark on a quilting ruler.
// Integers keep every sum exact: no 0.1 + 0.2 surprises in a cutting list.
#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>

namespace weftwise {

using Len = std::int64_t;  // eighths of an inch

constexpr Len kEighth = 1;
constexpr Len kInch = 8;
constexpr Len kYard = 36 * kInch;

// Reads "6.5", "6-1/2", "1/4" or "42". Returns nothing unless the value is a plain
// non-negative number that lands exactly on an eighth of an inch and is at most max.
std::optional<Len> parseInches(std::string_view text, Len max);

// Reads a percentage such as "3%" or "2.5%" into tenths of a percent (0 to 100 tenths = 10%).
std::optional<int> parsePercentTenths(std::string_view text);

// 6.5 inches -> "6½". Whole inches print plainly: "42".
std::string inches(Len eighths);

// A purchase length, rounded up to the next eighth of a yard: "1⅜ yd".
std::string yardsRoundedUp(Len eighths);

// A purchase length, rounded up to the next 10 cm, as shops in metric countries cut: "1.3 m".
std::string metresRoundedUp(Len eighths);

}  // namespace weftwise
