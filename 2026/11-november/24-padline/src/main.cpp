// padline PROBLEM.txt: where to put your crash pads.
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

#include "padline.hpp"

namespace fs = std::filesystem;
using padline::kCell;

static void draw(const padline::Problem& p, const padline::Risk& risk, const padline::Plan& plan) {
    const int cols = risk.cols(), rows = risk.rows();
    std::vector<char> map(static_cast<std::size_t>(cols) * rows, ' ');
    double top = 0;
    for (int r = 0; r < rows; ++r)
        for (int c = 0; c < cols; ++c) top = std::max(top, risk.at(c, r));
    const char shade[] = " .:-=#";
    for (int r = 0; r < rows; ++r) {
        for (int c = 0; c < cols; ++c) {
            // A gentle power curve so the spread of landings shows, not just the hottest spot.
            const double v = std::pow(risk.at(c, r) / top, 0.4);
            const int s = v < 0.12 ? 0 : std::min(5, 1 + static_cast<int>((v - 0.12) / 0.88 * 5));
            map[static_cast<std::size_t>(r) * cols + c] = shade[s];
        }
    }
    for (const auto& k : p.rocks) {
        for (int r = 0; r < rows; ++r)
            for (int c = 0; c < cols; ++c)
                if (std::hypot((c + 0.5) * kCell - k.x, (r + 0.5) * kCell - k.out) <= k.radius) map[static_cast<std::size_t>(r) * cols + c] = 'o';
    }
    for (std::size_t i = 0; i < plan.placed.size(); ++i) {
        const auto& pl = plan.placed[i];
        for (int r = pl.r; r < pl.r + pl.h; ++r)
            for (int c = pl.c; c < pl.c + pl.w; ++c) map[static_cast<std::size_t>(r) * cols + c] = static_cast<char>('A' + i);
    }
    std::printf("\n  boulder %s\n", std::string(static_cast<std::size_t>(cols), '=').c_str());
    for (int r = 0; r < rows; r += 2) {  // two rows of cells per line keeps the map's shape
        std::printf("  %4.1f m  ", r * kCell);
        for (int c = 0; c < cols; ++c) std::putchar(map[static_cast<std::size_t>(r) * cols + c]);
        std::putchar('\n');
    }
    std::printf("\n  Letters are pads; . : - = # is where falls land, densest at #; o is a rock.\n");
}

int main(int argc, char** argv) {
    if (argc != 2) {
        std::fprintf(stderr, "usage: padline PROBLEM.txt\n");
        return 2;
    }
    std::error_code ec;
    const fs::path path(argv[1]);
    if (!fs::is_regular_file(fs::symlink_status(path, ec)) || fs::file_size(path, ec) > padline::kMaxBytes || ec) {
        std::fprintf(stderr, "padline: the problem must be a regular file under 32 KB\n");
        return 2;
    }
    std::ifstream in(path, std::ios::binary);
    std::string text((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
    padline::ParseError err;
    auto problem = padline::parse(text, err);
    if (!problem) {
        if (err.line > 0) std::fprintf(stderr, "padline: line %d: %s\n", err.line, err.message.c_str());
        else std::fprintf(stderr, "padline: %s\n", err.message.c_str());
        return 2;
    }
    const padline::Risk risk(*problem);
    const auto plan = padline::place(*problem, risk);
    std::printf("%zu holds, %zu pads, %.1f x %.1f m of ground.\n", problem->holds.size(), problem->pads.size(), problem->along,
                problem->out);
    std::printf("The pads cover %.0f%% of where falls would land (weighted by height and hazards).\n\n",
                100.0 * plan.covered / plan.total);
    for (std::size_t i = 0; i < plan.placed.size(); ++i) {
        const auto& pl = plan.placed[i];
        std::printf("  %c  %-10s %.1f to %.1f m along the boulder, %.1f to %.1f m out from it\n", static_cast<char>('A' + i),
                    problem->pads[static_cast<std::size_t>(pl.pad)].name.c_str(), pl.c * kCell, (pl.c + pl.w) * kCell, pl.r * kCell,
                    (pl.r + pl.h) * kCell);
    }
    if (plan.placed.size() < problem->pads.size()) std::printf("  (%zu pads didn't fit anywhere useful)\n", problem->pads.size() - plan.placed.size());
    // The worst uncovered spot.
    double worst = 0;
    int wc = 0, wr = 0;
    for (int r = 0; r < risk.rows(); ++r) {
        for (int c = 0; c < risk.cols(); ++c) {
            bool covered = false;
            for (const auto& pl : plan.placed) covered |= c >= pl.c && c < pl.c + pl.w && r >= pl.r && r < pl.r + pl.h;
            if (!covered && risk.at(c, r) > worst) {
                worst = risk.at(c, r);
                wc = c;
                wr = r;
            }
        }
    }
    if (worst > 0) {
        std::printf("\nWorst bare ground: %.1f m along, %.1f m out. Put a spotter there, or another pad.\n", (wc + 0.5) * kCell,
                    (wr + 0.5) * kCell);
    }
    draw(*problem, risk, plan);
    return 0;
}
