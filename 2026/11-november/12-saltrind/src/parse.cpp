#include "parse.hpp"

#include <charconv>
#include <cmath>
#include <map>
#include <set>

namespace saltrind {

namespace {

struct Range {
    double lo, hi;
    const char* unit;
};

const std::map<std::string, Range, std::less<>> kBrineKeys = {
    {"litres", {1, 5000, "L"}},
    {"salt", {5, 26.4, "% (26.4 % is saturated)"}},
    {"temp", {2, 25, "°C"}},
};
const std::map<std::string, Range, std::less<>> kCheeseKeys = {
    {"diameter", {2, 60, "cm"}},
    {"height", {1, 40, "cm"}},
    {"moisture", {25, 65, "%"}},
    {"count", {1, 200, "wheels"}},
    {"target", {0.5, 10, "% salt-in-moisture"}},
    {"start", {0, 5, "% salt-in-moisture"}},
};

std::vector<std::string_view> words(std::string_view line) {
    std::vector<std::string_view> out;
    size_t i = 0;
    while (i < line.size()) {
        while (i < line.size() && (line[i] == ' ' || line[i] == '\t')) ++i;
        const size_t s = i;
        while (i < line.size() && line[i] != ' ' && line[i] != '\t') ++i;
        if (i > s) out.push_back(line.substr(s, i - s));
    }
    return out;
}

bool plainName(std::string_view s) {
    if (s.empty() || s.size() > 32) return false;
    for (const char c : s) {
        const bool ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') ||
                        c == '-' || c == '_';
        if (!ok) return false;
    }
    return true;
}

double number(std::string_view v, int line, const std::string& key, const Range& r) {
    double x = 0;
    const auto [end, ec] = std::from_chars(v.data(), v.data() + v.size(), x);
    if (ec != std::errc() || end != v.data() + v.size() || !std::isfinite(x)) {
        throw PlanError(line, key + " should be a number");
    }
    if (x < r.lo || x > r.hi) {
        throw PlanError(line, key + " should be between " + std::to_string(r.lo).substr(0, 6) + " and " +
                                  std::to_string(r.hi).substr(0, 6) + " " + r.unit);
    }
    return x;
}

}  // namespace

Plan parsePlan(std::string_view text) {
    if (text.size() > kMaxFileBytes) throw PlanError(0, "the plan is larger than 64 KB");
    for (const char c : text) {
        if (c == '\0') throw PlanError(0, "the plan is not a text file");
    }
    Plan plan;
    bool haveBrine = false;
    int lineNo = 0;
    size_t pos = 0;
    while (pos <= text.size()) {
        size_t nl = text.find('\n', pos);
        if (nl == std::string_view::npos) nl = text.size();
        std::string_view line = text.substr(pos, nl - pos);
        pos = nl + 1;
        ++lineNo;
        if (const size_t hash = line.find('#'); hash != std::string_view::npos) line = line.substr(0, hash);
        if (!line.empty() && line.back() == '\r') line.remove_suffix(1);
        const auto w = words(line);
        if (w.empty()) continue;

        const bool brine = w[0] == "brine";
        const bool cheese = w[0] == "cheese";
        if (!brine && !cheese) throw PlanError(lineNo, "lines start with 'brine' or 'cheese'");
        if (brine && haveBrine) throw PlanError(lineNo, "there is already a brine line");
        if (cheese && plan.wheels.size() >= kMaxCheeses) throw PlanError(lineNo, "at most 20 cheese lines");

        std::set<std::string, std::less<>> seen;
        Wheel wheel;
        for (size_t k = 1; k < w.size(); ++k) {
            const size_t eq = w[k].find('=');
            if (eq == std::string_view::npos || eq == 0) throw PlanError(lineNo, "write settings as key=value");
            const std::string_view key = w[k].substr(0, eq);
            const std::string_view value = w[k].substr(eq + 1);
            const auto& keys = brine ? kBrineKeys : kCheeseKeys;
            const bool known = keys.count(key) > 0 || (brine && key == "restore") || (cheese && key == "name");
            if (!known) throw PlanError(lineNo, std::string("unknown setting on a ") + (brine ? "brine" : "cheese") + " line");
            const std::string k2(key);
            if (!seen.insert(k2).second) throw PlanError(lineNo, k2 + " is set twice");

            if (key == "restore") {
                if (value != "yes" && value != "no") throw PlanError(lineNo, "restore should be yes or no");
                plan.restore = value == "yes";
            } else if (key == "name") {
                if (!plainName(value)) throw PlanError(lineNo, "name should be 1 to 32 letters, digits, - or _");
                wheel.name = std::string(value);
            } else {
                const double x = number(value, lineNo, k2, keys.find(key)->second);
                if (key == "litres") plan.litres = x;
                else if (key == "salt") plan.percent = x;
                else if (key == "temp") plan.temp = x;
                else if (key == "diameter") wheel.diameter = x;
                else if (key == "height") wheel.height = x;
                else if (key == "moisture") wheel.moisture = x;
                else if (key == "target") wheel.target = x;
                else if (key == "start") wheel.start = x;
                else if (key == "count") {
                    if (x != std::floor(x)) throw PlanError(lineNo, "count should be a whole number");
                    wheel.count = static_cast<int>(x);
                }
            }
        }
        if (brine) {
            for (const char* need : {"litres", "salt", "temp"}) {
                if (seen.count(need) == 0) throw PlanError(lineNo, std::string("the brine needs ") + need + "=");
            }
            haveBrine = true;
        } else {
            for (const char* need : {"diameter", "height", "moisture", "target"}) {
                if (seen.count(need) == 0) throw PlanError(lineNo, std::string("a cheese needs ") + need + "=");
            }
            if (wheel.start >= wheel.target) throw PlanError(lineNo, "start should be below target");
            if (wheel.name.empty()) wheel.name = "batch-" + std::to_string(plan.wheels.size() + 1);
            plan.wheels.push_back(wheel);
        }
    }
    if (!haveBrine) throw PlanError(0, "the plan needs a brine line");
    if (plan.wheels.empty()) throw PlanError(0, "the plan needs at least one cheese line");
    // The brine's surface salt-in-moisture must be well above any target, or brining never finishes.
    const Brine b = Brine::make(plan.litres, plan.percent, plan.temp);
    for (const Wheel& wh : plan.wheels) {
        if (wh.target > 0.5 * b.surface()) throw PlanError(0, "a target is too close to the brine's own strength");
        // Wheels have to fit in the bath: cheese volume no more than the brine's.
        if (wh.volume() * wh.count / 1000 > plan.litres) {
            throw PlanError(0, "batch " + wh.name + " has more cheese than brine; use more brine or fewer wheels");
        }
    }
    return plan;
}

}  // namespace saltrind
