#pragma once

#include <cstddef>
#include <string_view>

#include "plan.hpp"

namespace weftwise {

constexpr std::size_t kMaxInput = 64 * 1024;
constexpr std::size_t kMaxFabrics = 12;
constexpr std::size_t kMaxPieceTypes = 12;  // per fabric
constexpr int kMaxCount = 400;              // of one piece
constexpr std::size_t kMaxName = 60;

// Reads a whole cutting list. Throws InputError with a line number on any problem.
Quilt parse(std::string_view text);

}  // namespace weftwise
