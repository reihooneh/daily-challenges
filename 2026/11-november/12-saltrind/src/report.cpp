#include "report.hpp"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <sstream>

namespace saltrind {

namespace {

constexpr const char* kShades = " .:-=+*#%@";
constexpr double kWeakBrine = 18.0;

std::string fmt(const char* f, double x) {
    char buf[64];
    (void)std::snprintf(buf, sizeof buf, f, x);
    return buf;
}

}  // namespace

std::string duration(double hours) {
    long minutes = std::lround(hours * 60);
    const long days = minutes / (24L * 60);
    minutes -= days * 24L * 60;
    const long h = minutes / 60;
    const long m = minutes % 60;
    char buf[64];
    if (days > 0) (void)std::snprintf(buf, sizeof buf, "%ld d %ld h %02ld min", days, h, m);
    else (void)std::snprintf(buf, sizeof buf, "%ld h %02ld min", h, m);
    return buf;
}

std::string heatMap(const std::vector<double>& cells, int rings, int layers, double top) {
    constexpr int kCols = 40, kRows = 10;
    std::string out;
    for (int row = 0; row < kRows; ++row) {
        // Row 0 is the top face, the last row the wheel's middle.
        const int j = layers - 1 - row * layers / kRows;
        out += "    |";
        for (int col = 0; col < kCols; ++col) {
            const int i = col * rings / kCols;
            const double v = cells[static_cast<size_t>(j) * static_cast<size_t>(rings) + static_cast<size_t>(i)];
            const double f = std::clamp(v / top, 0.0, 1.0);
            out += kShades[static_cast<size_t>(std::lround(f * 9))];
        }
        out += row == 0 ? "|  top face\n" : row == kRows - 1 ? "|  middle\n" : "|\n";
    }
    out += "     centre" + std::string(kCols - 10, ' ') + "rind\n";
    return out;
}

std::string chart(const std::vector<std::pair<double, double>>& curve, double target) {
    constexpr int kCols = 48, kRows = 8;
    if (curve.size() < 2) return "";
    const double tEnd = std::max(curve.back().first, 1e-9);
    const double yTop = std::max(target * 1.1, curve.back().second);
    std::vector<std::string> grid(kRows, std::string(kCols, ' '));
    // Target line.
    const int ty = kRows - 1 - static_cast<int>(std::lround(target / yTop * (kRows - 1)));
    for (int c = 0; c < kCols; ++c) grid[static_cast<size_t>(ty)][static_cast<size_t>(c)] = '-';
    size_t k = 0;
    for (int c = 0; c < kCols; ++c) {
        const double t = tEnd * c / (kCols - 1);
        while (k + 1 < curve.size() && curve[k + 1].first < t) ++k;
        const auto& a = curve[k];
        const auto& b = curve[std::min(k + 1, curve.size() - 1)];
        const double span = b.first - a.first;
        const double y = span > 0 ? a.second + (b.second - a.second) * (t - a.first) / span : a.second;
        const int r = kRows - 1 - static_cast<int>(std::lround(std::clamp(y / yTop, 0.0, 1.0) * (kRows - 1)));
        grid[static_cast<size_t>(r)][static_cast<size_t>(c)] = '*';
    }
    std::string out;
    for (int r = 0; r < kRows; ++r) {
        const double label = yTop * (kRows - 1 - r) / (kRows - 1);
        out += fmt("  %4.1f%% |", label) + grid[static_cast<size_t>(r)] + (r == ty ? "  target\n" : "\n");
    }
    out += "        +" + std::string(kCols, '-') + "\n";
    out += "         0 h" + std::string(kCols - 12, ' ') + fmt("%.0f h\n", tEnd);
    return out;
}

std::string report(const Plan& plan, const std::vector<BatchResult>& results) {
    std::ostringstream o;
    const Brine b = Brine::make(plan.litres, plan.percent, plan.temp);
    o << "Saltrind: " << fmt("%.0f", plan.litres) << " L of " << fmt("%.1f", plan.percent) << " % brine at "
      << fmt("%.0f", plan.temp) << " °C (" << fmt("%.1f", b.salt / 1000) << " kg of salt in "
      << fmt("%.1f", b.water / 1000) << " kg of water)\n";
    o << "Batches go in one after another" << (plan.restore ? ", with the brine topped back up between them.\n" : ", without topping up.\n");

    double totalTopUp = 0;
    for (size_t n = 0; n < results.size(); ++n) {
        const BatchResult& r = results[n];
        const Wheel& w = r.wheel;
        o << "\n" << n + 1 << ". " << w.name << ": " << w.count << (w.count == 1 ? " wheel" : " wheels") << ", "
          << fmt("%.0f", w.diameter) << " × " << fmt("%.0f", w.height) << " cm, " << fmt("%.2f", w.mass() / 1000)
          << " kg each, " << fmt("%.0f", w.moisture) << " % moisture\n";
        if (r.reached) {
            o << "   Brine for " << duration(r.hours) << " to reach " << fmt("%.1f", w.target)
              << " % salt-in-moisture on average.\n";
        } else {
            o << "   The brine could not bring it to " << fmt("%.1f", w.target) << " % (it reached "
              << fmt("%.2f", r.meanAtRemoval) << " % after " << duration(r.hours) << ").\n";
        }
        o << "   Each wheel takes in " << fmt("%.0f", r.saltPerWheel) << " g of salt ("
          << fmt("%.2f", 100 * r.saltPerWheel / w.mass()) << " % of its weight).\n";
        o << "   Coming out: " << fmt("%.1f", r.surfaceAtRemoval) << " % at the rind corner, "
          << fmt("%.2f", r.centreAtRemoval) << " % at the centre.\n";
        if (r.evened) {
            o << "   Resting: the centre reaches 90 % of the average after about " << fmt("%.0f", std::ceil(r.evenDays))
              << (std::ceil(r.evenDays) == 1 ? " day.\n" : " days.\n");
        } else {
            o << "   Resting: the salt is still uneven after " << fmt("%.0f", r.evenDays) << " days.\n";
        }
        o << "   Brine: " << fmt("%.1f", r.brineBefore) << " % → " << fmt("%.1f", r.brineAfter) << " %";
        if (r.topUp > 0.5) o << "; add " << fmt("%.0f", r.topUp) << " g of salt to bring it back";
        o << ".\n";
        if (r.brineAfter < kWeakBrine) {
            o << "   Warning: the brine is below 18 %. Weak brine lets the rind go soft and slimy; top it up"
                 " before the next batch.\n";
        }
        totalTopUp += r.topUp;

        // The rind is far saltier than the rest; shading up to three times the target shows the
        // inside, and anything saltier is the darkest shade.
        const double top = w.target * 3;
        o << "\n   Salt through a cut wheel when it comes out of the brine (darker = saltier, 0 to "
          << fmt("%.0f", top) << " % or more):\n" << heatMap(r.removal, r.rings, r.layers, top);
        o << "\n   After resting:\n" << heatMap(r.rested, r.rings, r.layers, top);
        o << "\n   Average salt-in-moisture while brining:\n" << chart(r.curve, w.target);
    }
    if (plan.restore && results.size() > 1) {
        o << "\nSalt to buy for topping up across all batches: " << fmt("%.0f", totalTopUp) << " g.\n";
    }
    return o.str();
}

}  // namespace saltrind
