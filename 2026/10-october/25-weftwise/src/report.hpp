#pragma once

#include <string>
#include <vector>

#include "cutting.hpp"
#include "plan.hpp"

namespace weftwise {

std::string render(const Quilt& quilt, const std::vector<FabricPlan>& plans);

}  // namespace weftwise
