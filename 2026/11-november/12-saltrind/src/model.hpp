// Salt moving into a wheel of cheese in brine, and out of the brine.
#pragma once

#include <string>
#include <vector>

namespace saltrind {

// One kind of wheel, brined as a batch.
struct Wheel {
    std::string name;
    double diameter = 0;  // cm
    double height = 0;    // cm
    double moisture = 0;  // % of the cheese's weight that is water
    int count = 1;
    double target = 0;    // mean salt-in-moisture to stop at, %
    double start = 0;     // salt-in-moisture before brining, %

    [[nodiscard]] double volume() const;  // cm³
    [[nodiscard]] double mass() const;    // g (cheese is about 1.07 g/cm³)
    [[nodiscard]] double water() const;   // g of water in one wheel
};

// A brine bath: its salt and water, by mass.
struct Brine {
    double salt = 0;   // g
    double water = 0;  // g
    double temp = 12;  // °C

    static Brine make(double litres, double percent, double temp);
    [[nodiscard]] double percent() const;  // salt as % of the brine's weight
    [[nodiscard]] double litres() const;
    // Salt-in-moisture at a cheese surface in equilibrium with this brine, %.
    [[nodiscard]] double surface() const;
    // Grams of salt to add to bring the brine back to `percent`.
    [[nodiscard]] double topUp(double percent) const;
};

// Salt's diffusivity in the cheese's moisture, cm²/day, at a temperature and moisture.
double diffusivity(double tempC, double moisturePercent);

// How easily salt crosses the rind, cm/day. In brine the surface dries and its protein tightens
// into a rind while water flows out against the salt, so salt goes in far more slowly than
// diffusion alone predicts. This value makes a 3.7 kg gouda take about a day and a half in 23 % brine at
// 12 °C and a 12 kg one about three, as in common practice.
inline constexpr double kRind = 0.6;

// Water the cheese gives up to the brine for each gram of salt it takes in.
inline constexpr double kWaterPerSalt = 1.6;

// The salt in one wheel on an axisymmetric grid: cell (i, j) is ring i (from the centre out)
// and layer j (from the middle of the wheel up to its top face; the wheel is symmetric about
// its middle, so only the top half is modelled).
class Profile {
public:
    Profile(const Wheel& w, int rings = 40, int layers = 20);

    // Advances `days` with the faces in brine whose moisture holds `surface` % salt, or sealed
    // (resting). `rind` is the rind's conductance in cm/day (0: no rind, the face is the brine's
    // strength exactly). Returns grams of salt taken in by one wheel.
    double step(double days, double D, double surface, bool inBrine, double rind = 0);
    // Largest stable time step, days.
    [[nodiscard]] double maxStep(double D) const;

    [[nodiscard]] double mean() const;     // mean salt-in-moisture, %
    [[nodiscard]] double centre() const;   // at the very middle, %
    [[nodiscard]] double lowest() const;
    [[nodiscard]] double at(int ring, int layer) const { return c_[static_cast<size_t>(layer) * static_cast<size_t>(rings_) + static_cast<size_t>(ring)]; }
    [[nodiscard]] int rings() const { return rings_; }
    [[nodiscard]] int layers() const { return layers_; }
    [[nodiscard]] double saltGrams() const;  // salt in the whole wheel

private:
    int rings_, layers_;
    double R_, h_, dr_, dz_, waterPerCm3_;
    std::vector<double> c_, vol_, next_;
};

// What happened to one batch.
struct BatchResult {
    Wheel wheel;
    bool reached = false;
    double hours = 0;            // in the brine
    double saltPerWheel = 0;     // g taken in by each wheel
    double meanAtRemoval = 0;
    double centreAtRemoval = 0;
    double surfaceAtRemoval = 0; // the outermost cells
    double evenDays = 0;         // days resting until the middle reaches 90 % of the mean
    bool evened = false;
    double brineBefore = 0;      // brine % when the batch went in
    double brineAfter = 0;
    double topUp = 0;            // g of salt to restore the brine afterwards
    std::vector<double> removal; // profile when it came out (layers × rings)
    std::vector<double> rested;  // profile once even (or after the cap)
    int rings = 0, layers = 0;
    std::vector<std::pair<double, double>> curve; // (hours, mean) while brining
};

// Brines each batch in turn in the same bath (topped back up between batches if `restore`).
std::vector<BatchResult> brineAll(const std::vector<Wheel>& wheels, Brine brine, bool restore);

}  // namespace saltrind
