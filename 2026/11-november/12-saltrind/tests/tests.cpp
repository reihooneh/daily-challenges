// Saltrind's tests: the diffusion model against the exact solution, salt and water bookkeeping,
// the planner's behaviour, and hostile plans.
#include <cmath>
#include <cstdio>
#include <functional>
#include <numbers>
#include <string>
#include <vector>

#include "model.hpp"
#include "parse.hpp"
#include "report.hpp"

using namespace saltrind;

namespace {

int failures = 0;
int checks = 0;

void check(bool ok, const std::string& what) {
    ++checks;
    if (!ok) {
        ++failures;
        std::printf("  FAIL: %s\n", what.c_str());
    }
}

void near(double got, double want, double tol, const std::string& what) {
    check(std::fabs(got - want) <= tol, what + ": got " + std::to_string(got) + ", want " + std::to_string(want));
}

std::string errorOf(const std::string& text) {
    try {
        (void)parsePlan(text);
    } catch (const PlanError& e) {
        return e.what();
    }
    return "";
}

Wheel gouda() {
    Wheel w;
    w.name = "gouda";
    w.diameter = 22;
    w.height = 9;
    w.moisture = 42;
    w.count = 3;
    w.target = 4.5;
    return w;
}

// The exact fraction of the final uptake still to come in a finite cylinder with its surface held
// at a fixed concentration: the product of the infinite cylinder's and the slab's (Crank, ch. 5).
double unaccomplished(double D, double t, double R, double halfHeight) {
    static const double roots[] = {2.404826, 5.520078, 8.653728, 11.791534, 14.930918,
                                   18.071064, 21.211637, 24.352472, 27.493479, 30.634606};
    double cyl = 0;
    for (int n = 1; n <= 400; ++n) {
        // Beyond the tenth, McMahon's expansion gives the roots of J0 to better than 1e-6.
        const double b = (n - 0.25) * std::numbers::pi;
        const double a = n <= 10 ? roots[n - 1] : b + 1 / (8 * b) - 31 / (384 * b * b * b);
        cyl += 4 / (a * a) * std::exp(-a * a * D * t / (R * R));
    }
    double slab = 0;
    for (int n = 0; n < 200; ++n) {
        const double k = (2 * n + 1) * std::numbers::pi;
        slab += 8 / (k * k) * std::exp(-k * k * D * t / (4 * halfHeight * halfHeight));
    }
    return cyl * slab;
}

void testAgainstExact() {
    std::puts("diffusion matches the exact finite-cylinder solution");
    Wheel w = gouda();
    const double D = 0.22, surface = 30;
    for (const double days : {0.5, 1.0, 4.0, 15.0}) {
        Profile p(w, 80, 40);
        p.step(days, D, surface, true);
        const double exact = surface * (1 - unaccomplished(D, days, w.diameter / 2, w.height / 2));
        // Within 1 % of the salt taken in.
        near(p.mean(), exact, 0.01 * exact, "mean after " + std::to_string(days) + " days");
    }
}

void testGridConverges() {
    std::puts("a finer grid gives the same brining time");
    const Wheel w = gouda();
    const double D = diffusivity(12, w.moisture);
    auto timeTo = [&](int rings, int layers) {
        Profile p(w, rings, layers);
        double h = 0;
        while (p.mean() < w.target && h < 1000) {
            p.step(0.25 / 24, D, 29.9, true, kRind);
            h += 0.25;
        }
        return h;
    };
    const double coarse = timeTo(40, 20), fine = timeTo(80, 40);
    near(coarse, fine, 0.02 * fine, "hours on 40 × 20 vs 80 × 40 cells");
}

void testSealedKeepsSalt() {
    std::puts("resting moves salt inside but never loses any, and evens it out");
    Wheel w = gouda();
    Profile p(w);
    p.step(1, 0.22, 30, true, kRind);
    const double salt = p.saltGrams();
    const double spread = 30 - p.lowest();
    p.step(60, 0.22, 0, false);
    near(p.saltGrams(), salt, 1e-9 * salt, "salt in the wheel after 60 sealed days");
    check(30 - p.lowest() < spread, "the least salty spot gets saltier");
}

void testStaysInBounds() {
    std::puts("the explicit scheme is stable: nothing overshoots the brine or drops below the start");
    Wheel w = gouda();
    w.start = 1;
    Profile p(w, 60, 30);
    p.step(3, 0.4, 30, true);
    bool ok = true;
    for (int j = 0; j < p.layers(); ++j)
        for (int i = 0; i < p.rings(); ++i) ok = ok && p.at(i, j) >= 1 - 1e-9 && p.at(i, j) <= 30 + 1e-9;
    check(ok, "every cell between the start and the brine's strength");
}

void testBrineBookkeeping() {
    std::puts("the salt the wheels take is the salt the brine loses");
    const Brine start = Brine::make(40, 23, 12);
    near(start.percent(), 23, 1e-9, "brine strength as made");
    near(start.litres(), 40, 1e-9, "brine volume as made");
    const auto res = brineAll({gouda()}, start, false);
    check(res[0].reached, "the gouda reaches its target");
    near(res[0].meanAtRemoval, 4.5, 0.01, "mean at removal");
    // Rebuild the brine afterwards from the reported strength: salt lost = 3 wheels' uptake.
    const double taken = res[0].saltPerWheel * 3;
    const double salt = start.salt - taken;
    const double water = start.water + kWaterPerSalt * taken;
    near(res[0].brineAfter, 100 * salt / (salt + water), 1e-9, "brine strength afterwards");
    // A wheel's salt is its mean salt-in-moisture times its water.
    near(res[0].saltPerWheel, gouda().water() * res[0].meanAtRemoval / 100, 0.002 * res[0].saltPerWheel,
         "salt per wheel = water × mean");
}

void testTopUp() {
    std::puts("topping up restores the brine exactly");
    Brine b = Brine::make(40, 23, 12);
    b.salt -= 300;
    b.water += 480;
    b.salt += b.topUp(23);
    near(b.percent(), 23, 1e-9, "strength after topping up");
    check(Brine::make(40, 23, 12).topUp(23) < 1e-9, "a full-strength brine needs nothing");
}

void testPlannerBehaviour() {
    std::puts("the planner behaves like brine does");
    const Brine b = Brine::make(40, 23, 12);
    Wheel big = gouda(), small = gouda();
    small.diameter = 10;
    small.height = 5;
    const auto bs = brineAll({big, small}, b, true);
    check(bs[1].hours < bs[0].hours / 2, "a small wheel brines much faster");
    near(bs[1].brineBefore, 23, 1e-9, "topped up between batches");

    Brine warm = b;
    warm.temp = 18;
    check(brineAll({big}, warm, false)[0].hours < bs[0].hours, "warmer brine is faster");
    Brine weak = Brine::make(40, 15, 12);
    check(brineAll({big}, weak, false)[0].hours > bs[0].hours, "weaker brine is slower");

    // Without topping up, each batch weakens the brine and takes longer.
    Brine tub = Brine::make(4, 20, 18);
    Wheel w;
    w.name = "feta";
    w.diameter = 12;
    w.height = 8;
    w.moisture = 55;
    w.count = 2;
    w.target = 6;
    const auto run = brineAll({w, w, w}, tub, false);
    check(run[1].brineBefore < run[0].brineBefore && run[2].hours > run[1].hours && run[1].hours > run[0].hours,
          "a depleting brine slows each batch");
    check(run[2].brineAfter < 18, "and ends weaker than 18 %");
}

void testWeakBrineWarning() {
    std::puts("the report warns about weak brine and never prints raw input");
    const Plan plan = parsePlan("brine litres=4 salt=20 temp=18 restore=no\n"
                                "cheese name=a diameter=12 height=8 moisture=55 count=2 target=6\n"
                                "cheese name=b diameter=12 height=8 moisture=55 count=2 target=6\n");
    const std::string text = report(plan, brineAll(plan.wheels, Brine::make(4, 20, 18), false));
    check(text.find("below 18 %") != std::string::npos, "weak brine warning");
    check(text.find("2. b:") != std::string::npos, "both batches reported");
}

void testParser() {
    std::puts("plans are read strictly, and errors say where without repeating the input");
    const Plan p = parsePlan("# comment\r\nbrine litres=40 salt=23 temp=12  # cellar\r\n"
                             "cheese diameter=22 height=9 moisture=42 count=3 target=4.5\n");
    check(p.wheels.size() == 1 && p.wheels[0].name == "batch-1" && p.restore, "defaults");
    near(p.wheels[0].mass(), std::numbers::pi * 121 * 9 * 1.07, 1e-6, "mass from size");

    const std::string ok = "brine litres=40 salt=23 temp=12\n";
    const std::string c = "cheese diameter=22 height=9 moisture=42 target=4.5";
    const std::vector<std::pair<std::string, std::string>> bad = {
        {"", "needs a brine line"},
        {ok, "at least one cheese"},
        {ok + ok + c, "line 2: there is already a brine line"},
        {ok + "cheez diameter=1\n", "line 2: lines start with"},
        {ok + c + " colour=red\n", "unknown setting"},
        {ok + c + " height=8\n", "height is set twice"},
        {ok + "cheese diameter=22 height=9 moisture=42\n", "a cheese needs target="},
        {ok + c + " count=2.5\n", "whole number"},
        {ok + c + " count=0\n", "count should be between"},
        {ok + "cheese diameter=nan height=9 moisture=42 target=4.5\n", "should be a number"},
        {ok + "cheese diameter=1e999 height=9 moisture=42 target=4.5\n", "should be a number"},
        {ok + "cheese diameter=22x height=9 moisture=42 target=4.5\n", "should be a number"},
        {ok + c + " start=4.5\n", "start should be below target"},
        {ok + c + " name=<script>\n", "name should be"},
        {"brine litres=40 salt=30 temp=12\n" + c, "salt should be between"},
        {"brine litres=1 salt=23 temp=12\n" + c, "more cheese than brine"},
        {"brine litres=40 salt=5 temp=12\ncheese diameter=22 height=9 moisture=42 target=4", "too close"},
        {ok + c + " restore=yes\n", "unknown setting"},
        {ok + std::string(1, '\0'), "not a text file"},
        {std::string(70000, '#'), "larger than 64 KB"},
    };
    for (const auto& [text, want] : bad) {
        const std::string got = errorOf(text);
        check(got.find(want) != std::string::npos, "expected '" + want + "', got '" + got + "'");
    }
    // The error for a hostile value names the setting, not the value.
    const std::string e = errorOf(ok + "cheese diameter=\x1b[2J height=9 moisture=42 target=4.5\n");
    check(e.find('\x1b') == std::string::npos && e.find("diameter") != std::string::npos, "no echo");
    std::string many = ok;
    for (int i = 0; i < 21; ++i) many += "cheese diameter=5 height=3 moisture=42 target=4.5\n";
    check(errorOf(many).find("at most 20") != std::string::npos, "batch limit");
}

void testWorstCaseIsBounded() {
    std::puts("the largest allowed plan still finishes");
    std::string text = "brine litres=5000 salt=26.4 temp=2 restore=no\n";
    for (int i = 0; i < 20; ++i) text += "cheese diameter=60 height=40 moisture=25 count=1 target=10\n";
    const Plan p = parsePlan(text);
    const auto res = brineAll(p.wheels, Brine::make(p.litres, p.percent, p.temp), p.restore);
    check(res.size() == 20, "all batches simulated");
    check(!report(p, res).empty(), "and reported");
}

void testDuration() {
    std::puts("durations read naturally");
    check(duration(3.5) == "3 h 30 min", duration(3.5));
    check(duration(27.25) == "1 d 3 h 15 min", duration(27.25));
}

}  // namespace

int main() {
    const std::vector<std::function<void()>> tests = {
        testAgainstExact, testGridConverges, testSealedKeepsSalt, testStaysInBounds, testBrineBookkeeping,
        testTopUp, testPlannerBehaviour, testWeakBrineWarning, testParser, testWorstCaseIsBounded, testDuration,
    };
    for (const auto& t : tests) t();
    std::printf("\n%d checks, %d failed\n", checks, failures);
    return failures == 0 ? 0 : 1;
}
