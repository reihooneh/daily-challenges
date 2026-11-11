// Turning batch results into text: a summary, the salt through a cut wheel, and the mean over time.
#pragma once

#include <string>
#include <vector>

#include "model.hpp"
#include "parse.hpp"

namespace saltrind {

// Salt-in-moisture across half a cut wheel (centre on the left, rind on the right, top face at
// the top, the wheel's middle at the bottom), shaded from 0 to `top` %.
std::string heatMap(const std::vector<double>& cells, int rings, int layers, double top);

// The mean salt-in-moisture through the brining, against the target.
std::string chart(const std::vector<std::pair<double, double>>& curve, double target);

std::string report(const Plan& plan, const std::vector<BatchResult>& results);

// "1 d 3 h 20 min", "4 h 05 min".
std::string duration(double hours);

}  // namespace saltrind
