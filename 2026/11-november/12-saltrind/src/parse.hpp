// Reading a brining plan: one `brine` line and up to 20 `cheese` lines.
#pragma once

#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

#include "model.hpp"

namespace saltrind {

inline constexpr size_t kMaxFileBytes = 64 * 1024;
inline constexpr size_t kMaxCheeses = 20;

struct Plan {
    double litres = 0;
    double percent = 0;
    double temp = 12;
    bool restore = true;
    std::vector<Wheel> wheels;
};

// A problem with the plan, with the line it's on. Messages never repeat the input.
class PlanError : public std::runtime_error {
public:
    PlanError(int line, const std::string& what)
        : std::runtime_error(line > 0 ? "line " + std::to_string(line) + ": " + what : what) {}
};

Plan parsePlan(std::string_view text);

}  // namespace saltrind
