#include "model.hpp"

#include <algorithm>
#include <cmath>
#include <numbers>

namespace saltrind {

namespace {
constexpr double kCheeseDensity = 1.07;  // g/cm³
constexpr double kMaxBrineDays = 40;
constexpr double kMaxRestDays = 400;
}  // namespace

double Wheel::volume() const {
    const double r = diameter / 2;
    return std::numbers::pi * r * r * height;
}
double Wheel::mass() const { return volume() * kCheeseDensity; }
double Wheel::water() const { return mass() * moisture / 100; }

Brine Brine::make(double litres, double percent, double temp) {
    // Brine density rises with salt: about 1 + 0.0074 × % (1.20 kg/L when saturated).
    const double grams = litres * 1000 * (1 + 0.0074 * percent);
    Brine b;
    b.salt = grams * percent / 100;
    b.water = grams - b.salt;
    b.temp = temp;
    return b;
}
double Brine::percent() const { return 100 * salt / (salt + water); }
double Brine::litres() const { return (salt + water) / (1000 * (1 + 0.0074 * percent())); }
double Brine::surface() const { return 100 * salt / water; }  // salt per 100 g of water
double Brine::topUp(double p) const {
    const double f = p / 100;
    return std::max(0.0, f * water / (1 - f) - salt);
}

// About 0.22 cm²/day at 10 °C for a semi-hard cheese of 42 % moisture (Geurts and others
// measured 0.1 to 0.4), faster when warmer (activation energy 35 kJ/mol) and when moister.
double diffusivity(double tempC, double moisturePercent) {
    constexpr double kRef = 0.22;
    constexpr double kEaOverR = 35000.0 / 8.314;
    const double t = tempC + 273.15;
    return kRef * std::exp(-kEaOverR * (1 / t - 1 / 283.15)) * (moisturePercent / 42.0);
}

Profile::Profile(const Wheel& w, int rings, int layers)
    : rings_(rings), layers_(layers), R_(w.diameter / 2), h_(w.height / 2),
      dr_(R_ / rings), dz_(h_ / layers), waterPerCm3_(kCheeseDensity * w.moisture / 100),
      c_(static_cast<size_t>(rings * layers), w.start),
      vol_(static_cast<size_t>(rings * layers)),
      next_(static_cast<size_t>(rings * layers)) {
    for (int j = 0; j < layers_; ++j) {
        for (int i = 0; i < rings_; ++i) {
            const double r0 = i * dr_;
            const double r1 = r0 + dr_;
            vol_[static_cast<size_t>(j) * static_cast<size_t>(rings_) + static_cast<size_t>(i)] = std::numbers::pi * (r1 * r1 - r0 * r0) * dz_;
        }
    }
}

double Profile::maxStep(double D) const {
    // Explicit finite volumes are stable while every cell's outflow coefficients sum to < 1.
    double worst = 0;
    for (int i = 0; i < rings_; ++i) {
        const double r0 = i * dr_;
        const double r1 = r0 + dr_;
        const double vol = std::numbers::pi * (r1 * r1 - r0 * r0) * dz_;
        const double out = D * (2 * std::numbers::pi * r1 * dz_ / (dr_ / 2)   // outer face, worst case
                                + 2 * std::numbers::pi * std::max(r0, 0.0) * dz_ / dr_
                                + 3 * std::numbers::pi * (r1 * r1 - r0 * r0) / dz_);  // below + top face
        worst = std::max(worst, out / vol);
    }
    return 0.9 / worst;
}

double Profile::step(double days, double D, double surface, bool inBrine, double rind) {
    const double before = saltGrams();
    // A face cell meets the brine through half a cell of cheese and then the rind, in series.
    const double outerR = rind > 0 ? 1 / ((dr_ / 2) / D + 1 / rind) : D / (dr_ / 2);
    const double outerZ = rind > 0 ? 1 / ((dz_ / 2) / D + 1 / rind) : D / (dz_ / 2);
    double done = 0;
    const double dtMax = maxStep(D);
    const double pi2 = 2 * std::numbers::pi;
    while (done < days - 1e-12) {
        const double dt = std::min(dtMax, days - done);
        for (int j = 0; j < layers_; ++j) {
            for (int i = 0; i < rings_; ++i) {
                const size_t k = static_cast<size_t>(j) * static_cast<size_t>(rings_) + static_cast<size_t>(i);
                const double c = c_[k];
                const double r0 = i * dr_;
                const double r1 = r0 + dr_;
                const double ring = std::numbers::pi * (r1 * r1 - r0 * r0);
                double flux = 0;  // cm³·%/day into the cell
                // Inner ring face.
                if (i > 0) flux += D * pi2 * r0 * dz_ * (c_[k - 1] - c) / dr_;
                // Outer ring face: the next ring, or the brine half a cell away.
                if (i + 1 < rings_) {
                    flux += D * pi2 * r1 * dz_ * (c_[k + 1] - c) / dr_;
                } else if (inBrine) {
                    flux += outerR * pi2 * r1 * dz_ * (surface - c);
                }
                // Layer below (towards the middle; the middle itself is a mirror, so no flux).
                if (j > 0) flux += D * ring * (c_[k - static_cast<size_t>(rings_)] - c) / dz_;
                // Layer above, or the top face in the brine.
                if (j + 1 < layers_) {
                    flux += D * ring * (c_[k + static_cast<size_t>(rings_)] - c) / dz_;
                } else if (inBrine) {
                    flux += outerZ * ring * (surface - c);
                }
                next_[k] = c + dt * flux / vol_[k];
            }
        }
        c_.swap(next_);
        done += dt;
    }
    return saltGrams() - before;
}

double Profile::mean() const {
    double s = 0, v = 0;
    for (size_t k = 0; k < c_.size(); ++k) {
        s += c_[k] * vol_[k];
        v += vol_[k];
    }
    return s / v;
}
double Profile::centre() const { return c_[0]; }
double Profile::lowest() const { return *std::min_element(c_.begin(), c_.end()); }
double Profile::saltGrams() const {
    // Both halves of the wheel: salt-in-moisture % × water in the cell.
    double g = 0;
    for (size_t k = 0; k < c_.size(); ++k) g += c_[k] / 100 * waterPerCm3_ * vol_[k];
    return 2 * g;
}

std::vector<BatchResult> brineAll(const std::vector<Wheel>& wheels, Brine brine, bool restore) {
    std::vector<BatchResult> out;
    const double startPercent = brine.percent();
    for (const Wheel& w : wheels) {
        BatchResult res;
        res.wheel = w;
        res.brineBefore = brine.percent();
        Profile p(w);
        res.rings = p.rings();
        res.layers = p.layers();
        const double D = diffusivity(brine.temp, w.moisture);
        // Brine in steps of an hour (finer near the end, so the stopping time is to the minute).
        double hours = 0;
        res.curve.emplace_back(0, p.mean());
        while (hours < kMaxBrineDays * 24) {
            const Profile saved = p;
            const Brine savedBrine = brine;
            double gained = p.step(1.0 / 24, D, brine.surface(), true, kRind);
            if (p.mean() >= w.target) {
                // Back up and find the minute it crossed.
                p = saved;
                brine = savedBrine;
                double lo = 0, hi = 1;
                for (int it = 0; it < 30; ++it) {
                    const double mid = (lo + hi) / 2;
                    Profile trial = saved;
                    trial.step(mid / 24, D, brine.surface(), true, kRind);
                    (trial.mean() >= w.target ? hi : lo) = mid;
                }
                gained = p.step(hi / 24, D, brine.surface(), true, kRind);
                brine.salt -= gained * w.count;
                brine.water += kWaterPerSalt * gained * w.count;
                hours += hi;
                res.reached = true;
                break;
            }
            brine.salt -= gained * w.count;
            brine.water += kWaterPerSalt * gained * w.count;
            hours += 1;
            res.curve.emplace_back(hours, p.mean());
            if (brine.salt <= 0) break;
        }
        res.curve.emplace_back(hours, p.mean());
        res.hours = hours;
        res.saltPerWheel = p.saltGrams() - Profile(w).saltGrams();
        res.meanAtRemoval = p.mean();
        res.centreAtRemoval = p.centre();
        res.surfaceAtRemoval = p.at(p.rings() - 1, p.layers() - 1);
        for (int j = 0; j < p.layers(); ++j)
            for (int i = 0; i < p.rings(); ++i) res.removal.push_back(p.at(i, j));
        // Resting: sealed faces, salt evens out inside.
        double rest = 0;
        const double target = 0.9 * p.mean();
        const double Drest = diffusivity(brine.temp, w.moisture);
        while (rest < kMaxRestDays && p.lowest() < target) {
            p.step(0.25, Drest, 0, false);
            rest += 0.25;
        }
        res.evened = p.lowest() >= target;
        res.evenDays = rest;
        for (int j = 0; j < p.layers(); ++j)
            for (int i = 0; i < p.rings(); ++i) res.rested.push_back(p.at(i, j));
        res.brineAfter = brine.percent();
        res.topUp = brine.topUp(startPercent);
        if (restore) brine.salt += res.topUp;
        out.push_back(std::move(res));
    }
    return out;
}

}  // namespace saltrind
