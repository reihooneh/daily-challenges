#include "padline.hpp"

#include <algorithm>
#include <cctype>
#include <charconv>
#include <cmath>
#include <numbers>
#include <sstream>
#include <utility>

namespace padline {
namespace {

bool number(std::string_view word, double lo, double hi, double& out) {
    if (word.empty() || (!std::isdigit(static_cast<unsigned char>(word.front())) && word.front() != '.')) return false;
    for (char ch : word) {
        if (!std::isdigit(static_cast<unsigned char>(ch)) && ch != '.') return false;  // no signs, exponents, nan, inf
    }
    double v = 0;
    auto [ptr, ec] = std::from_chars(word.data(), word.data() + word.size(), v);
    if (ec != std::errc{} || ptr != word.data() + word.size() || !std::isfinite(v) || v < lo || v > hi) return false;
    out = v;
    return true;
}

std::vector<std::string_view> split(std::string_view line) {
    std::vector<std::string_view> out;
    std::size_t i = 0;
    while (i < line.size()) {
        while (i < line.size() && (line[i] == ' ' || line[i] == '\t')) ++i;
        std::size_t j = i;
        while (j < line.size() && line[j] != ' ' && line[j] != '\t') ++j;
        if (j > i) out.push_back(line.substr(i, j - i));
        i = j;
    }
    return out;
}

// Where you land falling from a hold: a little out from the wall, further from higher up, with a
// spread that grows with height. Weighted by height^1.5 (impact energy, and less control higher up).
void add_hold(std::vector<double>& cell, int cols, int rows, const Hold& h) {
    const double centre_out = 0.45 + 0.22 * h.height;
    const double sx = 0.25 + 0.10 * h.height, so = 0.20 + 0.10 * h.height;
    double weight = std::pow(h.height, 1.5) * (h.crux ? 2.0 : 1.0) * (h.topout ? 1.5 : 1.0);
    weight /= 2 * std::numbers::pi * sx * so;
    for (int r = 0; r < rows; ++r) {
        for (int c = 0; c < cols; ++c) {
            const double x = (c + 0.5) * kCell, y = (r + 0.5) * kCell;
            const double dx = (x - h.x) / sx, dy = (y - centre_out) / so;
            cell[static_cast<std::size_t>(r) * cols + c] += weight * std::exp(-0.5 * (dx * dx + dy * dy)) * kCell * kCell;
        }
    }
}

}  // namespace

std::optional<Problem> parse(std::string_view text, ParseError& error) {
    Problem p;
    if (text.size() > kMaxBytes) {
        error = {0, "the file is larger than 32 KB"};
        return std::nullopt;
    }
    int lineno = 0;
    std::size_t start = 0;
    auto fail = [&](std::string message) {
        error = {lineno, std::move(message)};
        return std::nullopt;
    };
    while (start <= text.size()) {
        std::size_t end = text.find('\n', start);
        if (end == std::string_view::npos) end = text.size();
        std::string_view line = text.substr(start, end - start);
        start = end + 1;
        ++lineno;
        if (line.size() > 200) return fail("the line is too long");
        for (char ch : line) {
            if (static_cast<unsigned char>(ch) < 32 && ch != '\t' && ch != '\r') return fail("the line has a control character");
        }
        if (auto hash = line.find('#'); hash != std::string_view::npos) line = line.substr(0, hash);
        auto w = split(line);
        if (!w.empty() && w.back() == "\r") w.pop_back();
        if (w.empty()) continue;
        if (w[0] == "ground") {
            if (w.size() != 3 || !number(w[1], 1, 20, p.along) || !number(w[2], 1, 10, p.out)) {
                return fail("ground needs its length along the wall (1-20 m) and depth out from it (1-10 m)");
            }
        } else if (w[0] == "hold") {
            Hold h;
            if (w.size() < 3 || !number(w[1], 0, 20, h.x) || !number(w[2], 0.1, 8, h.height)) {
                return fail("hold needs its position along the wall and the height you'd fall from (0.1-8 m)");
            }
            for (std::size_t i = 3; i < w.size(); ++i) {
                if (w[i] == "crux") h.crux = true;
                else if (w[i] == "topout") h.topout = true;
                else return fail("a hold can be marked crux or topout, nothing else");
            }
            if (p.holds.size() >= kMaxHolds) return fail("at most 60 holds");
            p.holds.push_back(h);
        } else if (w[0] == "rock") {
            Rock k;
            if (w.size() != 4 || !number(w[1], 0, 20, k.x) || !number(w[2], 0, 10, k.out) || !number(w[3], 0.05, 2, k.radius)) {
                return fail("rock needs its position along, out from the wall, and radius (0.05-2 m)");
            }
            if (p.rocks.size() >= kMaxRocks) return fail("at most 40 rocks");
            p.rocks.push_back(k);
        } else if (w[0] == "pad") {
            Pad pad;
            double count = 1;
            if (w.size() < 3 || !number(w[1], 0.3, 2.5, pad.length) || !number(w[2], 0.3, 2.5, pad.width)) {
                return fail("pad needs its length and width (0.3-2.5 m)");
            }
            if (w.size() == 4) {
                if (w[3].size() < 2 || w[3][0] != 'x' || !number(w[3].substr(1), 1, 12, count) || count != std::floor(count)) {
                    return fail("a pad count looks like x2");
                }
            } else if (w.size() > 4) {
                return fail("unexpected text after the pad");
            }
            for (int i = 0; i < static_cast<int>(count); ++i) {
                if (p.pads.size() >= kMaxPads) return fail("at most 12 pads");
                std::ostringstream n;
                n << pad.length << " x " << pad.width;
                pad.name = n.str();
                p.pads.push_back(pad);
            }
        } else {
            return fail("unknown keyword (use ground, hold, rock or pad)");
        }
    }
    lineno = 0;
    if (p.along <= 0) return fail("the problem needs a ground line");
    if (p.holds.empty()) return fail("the problem needs at least one hold");
    if (p.pads.empty()) return fail("the problem needs at least one pad");
    for (const auto& h : p.holds) {
        if (h.x > p.along) return fail("a hold is beyond the end of the ground");
    }
    return p;
}

Risk::Risk(const Problem& p)
    : cols_(static_cast<int>(std::lround(p.along / kCell))), rows_(static_cast<int>(std::lround(p.out / kCell))) {
    cell_.assign(static_cast<std::size_t>(cols_) * rows_, 0.0);
    for (const auto& h : p.holds) add_hold(cell_, cols_, rows_, h);
    // Landing on a rock or root is far worse than on flat ground.
    for (int r = 0; r < rows_; ++r) {
        for (int c = 0; c < cols_; ++c) {
            const double x = (c + 0.5) * kCell, y = (r + 0.5) * kCell;
            for (const auto& k : p.rocks) {
                if (std::hypot(x - k.x, y - k.out) <= k.radius) {
                    cell_[static_cast<std::size_t>(r) * cols_ + c] *= 4.0;
                    break;
                }
            }
        }
    }
    prefix_.assign(static_cast<std::size_t>(cols_ + 1) * (rows_ + 1), 0.0);
    for (int r = 0; r < rows_; ++r) {
        for (int c = 0; c < cols_; ++c) {
            const auto idx = [&](int cc, int rr) { return static_cast<std::size_t>(rr) * (cols_ + 1) + cc; };
            prefix_[idx(c + 1, r + 1)] = at(c, r) + prefix_[idx(c, r + 1)] + prefix_[idx(c + 1, r)] - prefix_[idx(c, r)];
        }
    }
    total_ = sum(0, 0, cols_, rows_);
}

double Risk::sum(int c0, int r0, int c1, int r1) const {
    const auto idx = [&](int cc, int rr) { return static_cast<std::size_t>(rr) * (cols_ + 1) + cc; };
    return prefix_[idx(c1, r1)] - prefix_[idx(c0, r1)] - prefix_[idx(c1, r0)] + prefix_[idx(c0, r0)];
}

namespace {

bool overlaps(const Placement& a, const Placement& b) {
    return a.c < b.c + b.w && b.c < a.c + a.w && a.r < b.r + b.h && b.r < a.r + a.h;
}

// The best spot for one pad, given the others already down.
std::optional<Placement> best_spot(const Problem& p, const Risk& risk, int pad, const std::vector<Placement>& others, double& gain) {
    std::optional<Placement> best;
    gain = -1;
    const int a = static_cast<int>(std::lround(p.pads[static_cast<std::size_t>(pad)].length / kCell));
    const int b = static_cast<int>(std::lround(p.pads[static_cast<std::size_t>(pad)].width / kCell));
    for (int turn = 0; turn < 2; ++turn) {
        const int w = turn ? b : a, h = turn ? a : b;
        if (w > risk.cols() || h > risk.rows()) continue;
        for (int r = 0; r + h <= risk.rows(); ++r) {
            for (int c = 0; c + w <= risk.cols(); ++c) {
                Placement cand{pad, c, r, w, h};
                bool clash = false;
                for (const auto& o : others) {
                    if (overlaps(cand, o)) {
                        clash = true;
                        break;
                    }
                }
                if (clash) continue;
                const double g = risk.sum(c, r, c + w, r + h);
                if (g > gain + 1e-12) {
                    gain = g;
                    best = cand;
                }
            }
        }
    }
    return best;
}

}  // namespace

// Every spot for one pad that doesn't overlap the others, best first, at most `keep` of them.
std::vector<std::pair<double, Placement>> spots(const Problem& p, const Risk& risk, int pad, const std::vector<Placement>& others,
                                                std::size_t keep) {
    std::vector<std::pair<double, Placement>> out;
    const int a = static_cast<int>(std::lround(p.pads[static_cast<std::size_t>(pad)].length / kCell));
    const int b = static_cast<int>(std::lround(p.pads[static_cast<std::size_t>(pad)].width / kCell));
    for (int turn = 0; turn < 2; ++turn) {
        const int w = turn ? b : a, h = turn ? a : b;
        for (int r = 0; r + h <= risk.rows(); ++r) {
            for (int c = 0; c + w <= risk.cols(); ++c) {
                Placement cand{pad, c, r, w, h};
                if (std::none_of(others.begin(), others.end(), [&](const Placement& o) { return overlaps(cand, o); })) {
                    out.emplace_back(risk.sum(c, r, c + w, r + h), cand);
                }
            }
        }
    }
    const auto n = std::min(keep, out.size());
    std::partial_sort(out.begin(), out.begin() + static_cast<std::ptrdiff_t>(n), out.end(),
                      [](const auto& x, const auto& y) { return x.first > y.first; });
    out.resize(n);
    return out;
}

double gain_of(const Risk& risk, const Placement& pl) { return risk.sum(pl.c, pl.r, pl.c + pl.w, pl.r + pl.h); }

Plan place(const Problem& p, const Risk& risk) {
    // Biggest pads first: they decide the layout.
    std::vector<int> order(p.pads.size());
    for (std::size_t i = 0; i < order.size(); ++i) order[i] = static_cast<int>(i);
    std::stable_sort(order.begin(), order.end(), [&](int x, int y) {
        return p.pads[static_cast<std::size_t>(x)].length * p.pads[static_cast<std::size_t>(x)].width >
               p.pads[static_cast<std::size_t>(y)].length * p.pads[static_cast<std::size_t>(y)].width;
    });
    Plan plan;
    plan.total = risk.total();
    for (int pad : order) {
        double gain = 0;
        if (auto spot = best_spot(p, risk, pad, plan.placed, gain)) plan.placed.push_back(*spot);
    }
    // Local improvement, repeated while anything helps:
    //  1. lift one pad and put it in the best spot left;
    //  2. lift two pads: try the first in each of its 300 best spots, and the second in its best spot after it.
    for (int round = 0; round < 20; ++round) {
        bool improved = false;
        for (std::size_t i = 0; i < plan.placed.size(); ++i) {
            std::vector<Placement> others = plan.placed;
            others.erase(others.begin() + static_cast<std::ptrdiff_t>(i));
            double gain = 0;
            auto spot = best_spot(p, risk, plan.placed[i].pad, others, gain);
            if (spot && gain > gain_of(risk, plan.placed[i]) + 1e-9) {
                plan.placed[i] = *spot;
                improved = true;
            }
        }
        for (std::size_t i = 0; i < plan.placed.size(); ++i) {
            for (std::size_t j = 0; j < plan.placed.size(); ++j) {
                if (i == j) continue;
                std::vector<Placement> rest;
                for (std::size_t k = 0; k < plan.placed.size(); ++k)
                    if (k != i && k != j) rest.push_back(plan.placed[k]);
                const double now = gain_of(risk, plan.placed[i]) + gain_of(risk, plan.placed[j]);
                double best = now;
                Placement bi = plan.placed[i], bj = plan.placed[j];
                double ceiling = 0;  // the most pad j could cover with pad i out of the way: a valid bound
                best_spot(p, risk, plan.placed[j].pad, rest, ceiling);
                for (const auto& [gi, ci] : spots(p, risk, plan.placed[i].pad, rest, 300)) {
                    if (gi + ceiling <= best) break;  // spots come best first, so none later can beat it
                    rest.push_back(ci);
                    double gj = 0;
                    auto cj = best_spot(p, risk, plan.placed[j].pad, rest, gj);
                    rest.pop_back();
                    if (cj && gi + gj > best + 1e-9) {
                        best = gi + gj;
                        bi = ci;
                        bj = *cj;
                    }
                }
                if (best > now + 1e-9) {
                    plan.placed[i] = bi;
                    plan.placed[j] = bj;
                    improved = true;
                }
            }
        }
        if (!improved) break;
    }
    for (const auto& pl : plan.placed) plan.covered += gain_of(risk, pl);
    return plan;
}

double brute_two(const Problem& p, const Risk& risk) {
    std::vector<Placement> all[2];
    for (int pad = 0; pad < 2; ++pad) {
        const int a = static_cast<int>(std::lround(p.pads[static_cast<std::size_t>(pad)].length / kCell));
        const int b = static_cast<int>(std::lround(p.pads[static_cast<std::size_t>(pad)].width / kCell));
        for (int turn = 0; turn < 2; ++turn) {
            const int w = turn ? b : a, h = turn ? a : b;
            for (int r = 0; r + h <= risk.rows(); ++r) {
                for (int c = 0; c + w <= risk.cols(); ++c) all[pad].push_back({pad, c, r, w, h});
            }
        }
    }
    double best = 0;
    for (const auto& x : all[0]) {
        const double gx = risk.sum(x.c, x.r, x.c + x.w, x.r + x.h);
        for (const auto& y : all[1]) {
            if (overlaps(x, y)) continue;
            best = std::max(best, gx + risk.sum(y.c, y.r, y.c + y.w, y.r + y.h));
        }
    }
    return best;
}

}  // namespace padline
