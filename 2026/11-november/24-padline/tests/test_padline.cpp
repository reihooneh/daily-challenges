// Tests for Padline. `make test` builds them with AddressSanitizer and UBSan.
#include <cmath>
#include <cstdlib>
#include <cstdio>
#include <random>
#include <string>

#include "../src/padline.hpp"

static int failures = 0, checks = 0;
#define CHECK(cond)                                                          \
    do {                                                                     \
        ++checks;                                                            \
        if (!(cond)) {                                                       \
            ++failures;                                                      \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond);     \
        }                                                                    \
    } while (0)

static padline::Problem must(const std::string& text) {
    padline::ParseError e;
    auto p = padline::parse(text, e);
    if (!p) {
        std::printf("unexpected parse error: line %d: %s\n", e.line, e.message.c_str());
        std::exit(1);
    }
    return *p;
}

static void prefix_sums_match_brute_force() {
    auto p = must("ground 4 3\nhold 1 1.5\nhold 2.5 2.5 crux\nrock 2 1 0.3\npad 1 1\n");
    padline::Risk risk(p);
    std::mt19937 rng(1);
    for (int t = 0; t < 200; ++t) {
        int c0 = static_cast<int>(rng() % 40), c1 = static_cast<int>(rng() % 40);
        int r0 = static_cast<int>(rng() % 30), r1 = static_cast<int>(rng() % 30);
        if (c0 > c1) std::swap(c0, c1);
        if (r0 > r1) std::swap(r0, r1);
        double want = 0;
        for (int r = r0; r < r1; ++r)
            for (int c = c0; c < c1; ++c) want += risk.at(c, r);
        CHECK(std::fabs(want - risk.sum(c0, r0, c1, r1)) < 1e-9);
    }
}

static void rocks_and_cruxes_raise_the_risk() {
    auto plain = must("ground 4 3\nhold 2 2\npad 1 1\n");
    auto rocky = must("ground 4 3\nhold 2 2\nrock 2 1 0.5\npad 1 1\n");
    auto crux = must("ground 4 3\nhold 2 2 crux\npad 1 1\n");
    CHECK(padline::Risk(rocky).total() > padline::Risk(plain).total());
    CHECK(std::fabs(padline::Risk(crux).total() - 2 * padline::Risk(plain).total()) < 1e-9);
}

static void placements_are_sound_and_near_best() {
    std::mt19937 gen(7);
    auto rng = [&gen] { return static_cast<int>(gen() % 1000); };
    for (int t = 0; t < 25; ++t) {
        std::string text = "ground 3 2.5\n";
        const int holds = 1 + rng() % 4;
        for (int i = 0; i < holds; ++i) {
            text += "hold " + std::to_string(0.3 + (rng() % 24) / 10.0) + " " + std::to_string(0.5 + (rng() % 30) / 10.0) + "\n";
        }
        if (rng() % 2) text += "rock " + std::to_string(0.5 + (rng() % 20) / 10.0) + " " + std::to_string(0.5 + (rng() % 10) / 10.0) + " 0.3\n";
        text += "pad 1.2 1.0\npad 0.9 0.6\n";
        auto p = must(text);
        padline::Risk risk(p);
        auto plan = padline::place(p, risk);
        // In bounds, no overlaps, and the covered sum adds up.
        double covered = 0;
        for (std::size_t i = 0; i < plan.placed.size(); ++i) {
            const auto& a = plan.placed[i];
            CHECK(a.c >= 0 && a.r >= 0 && a.c + a.w <= risk.cols() && a.r + a.h <= risk.rows());
            covered += risk.sum(a.c, a.r, a.c + a.w, a.r + a.h);
            for (std::size_t j = i + 1; j < plan.placed.size(); ++j) {
                const auto& b = plan.placed[j];
                CHECK(!(a.c < b.c + b.w && b.c < a.c + a.w && a.r < b.r + b.h && b.r < a.r + a.h));
            }
        }
        CHECK(std::fabs(covered - plan.covered) < 1e-9);
        // Close to the best of every pair of placements.
        const double best = padline::brute_two(p, risk);
        CHECK(plan.covered <= best + 1e-9);
        CHECK(plan.covered >= 0.97 * best);
    }
}

static void hostile_input_is_refused() {
    const char* bad[] = {
        "ground nan 3\nhold 1 1\npad 1 1\n",
        "ground inf 3\nhold 1 1\npad 1 1\n",
        "ground -4 3\nhold 1 1\npad 1 1\n",
        "ground 1e3 3\nhold 1 1\npad 1 1\n",
        "ground 4 3\nhold 1 1 sideways\npad 1 1\n",
        "ground 4 3\nhold 9 1\npad 1 1\n",
        "ground 4 3\nhold 1 1\npad 1 1 x13\n",
        "ground 4 3\nhold 1 1\npad 1 1 x1.5\n",
        "ground 4 3\nhold 1 1\npad 1 1 extra words\n",
        "ground 4 3\nhold 1 1\n",
        "ground 4 3\npad 1 1\n",
        "hold 1 1\npad 1 1\n",
        "ground 4 3\nhold 1 1\npad 1 1\n\x1b[2J\n",
        "ground 4 3\nrm -rf /\n",
    };
    for (const char* text : bad) {
        padline::ParseError e;
        CHECK(!padline::parse(text, e).has_value());
    }
    std::string many = "ground 4 3\npad 1 1\n";
    for (int i = 0; i < 61; ++i) many += "hold 1 1\n";
    padline::ParseError e;
    CHECK(!padline::parse(many, e).has_value() && e.message.find("60") != std::string::npos);
    CHECK(!padline::parse(std::string(40000, '#'), e).has_value());
    CHECK(!padline::parse("ground 4 3\nhold 1 1\npad 1 1\n" + std::string(300, 'x') + "\n", e).has_value() && e.line == 4);
}

int main() {
    prefix_sums_match_brute_force();
    rocks_and_cruxes_raise_the_risk();
    placements_are_sound_and_near_best();
    hostile_input_is_refused();
    if (failures) {
        std::printf("%d of %d checks failed\n", failures, checks);
        return 1;
    }
    std::printf("All %d Padline checks passed.\n", checks);
    return 0;
}
