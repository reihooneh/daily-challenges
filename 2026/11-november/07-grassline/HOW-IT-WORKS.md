# How Grassline works

Grassline answers the lawn bowler's oldest question, how much grass to take, by solving the bowl's motion exactly, then fitting it to the bowler's own shots.

## 1. The big picture

```
options / log file ──Cli / Log──▶ bowls (bias constant K) + green (deceleration a) + jack length L
                                          │
                       Physics: c = K / a,  aim angle = atan(c / 2),  speed v0 = √(L a √(4 + c²))
                                          │
                       Shot: the path rotated so it ends on the jack; width, stare spot, shoulder,
                             what weight and line errors do
                                          │
                       Report: plan · tables for other lengths and greens · rink picture · SVG
```

## 2. File tour

- **`Physics.php`:** the formulas (section 3).
  - `at()` gives position, speed, time and distance at any point on the path;
  - `rest()` gives where the bowl stops;
  - `decelerationFor()` turns a green's speed in seconds into the deceleration, by bisection;
  - `integrate()` solves the same equations numerically with Runge–Kutta, for the tests.
- **`Shot.php`:**
  - `Bowls` holds the bias constant K, from a preset or a fit;
  - `Shot` rotates the path so it finishes on the jack, then measures it.
  - Samples are spread evenly in distance, so the slow hook at the end isn't crowded with points.
- **`Log.php`:** parses the log strictly, and fits the bowls by least squares.
- **`Report.php`:** the plan, the tables, an ASCII picture of the rink, and the SVG.
- **`Cli.php`:** options with `match`, and bounded reading of the log.

## 3. Key ideas, simply

**Why a bowl curves.** The bowl's running surface is shaped so it leans towards its bias side. Gravity then twists it, and because it's spinning, that twist doesn't tip it over. It turns its direction instead, like a gyroscope (precession). The twist stays the same while the spin falls with speed, so the turning rate is K/v: slow at first, then faster and faster. That's why a bowl runs nearly straight for most of the green and curls in at the end.

**Solving it exactly.** Friction slows the bowl at a constant rate a, so v = v0 − a t. With u = ln(v0/v), the heading is just θ = (K/a) u = c u. Each step forward is v dt = (v0²/a) e^(−2u) du in the direction θ, which integrates in closed form:

```
x = (v0²/a) (2 + e^(−2u) (c sin cu − 2 cos cu)) / (4 + c²)
y = (v0²/a) (c − e^(−2u) (2 sin cu + c cos cu)) / (4 + c²)
```

As the bowl stops (u → ∞) the e^(−2u) terms vanish: it rests at (v0²/a)(2, c)/(4 + c²).

**Two results for free.**
1. The resting point always lies at angle atan(c/2) from the aiming direction, whatever v0 is. So for one set of bowls on one green, **the angle of aim is the same for every length**. The width at the jack is L tan(angle), which grows with length, but the angle doesn't change. (De Mestre noted this in his mathematics of sport.)
2. Every position on the path scales with v0². A bowl 5% too heavy follows a path the same shape, 10.25% bigger, along the same line. **Weight errors stay on line, and line errors stay at length.** Coaches teach the two separately, and this is why.

**Green speed.** In bowls, a green's speed is the seconds a bowl takes to come to rest 30 yards up the green, so more seconds means less friction. The time to rest is v0/a and the path length is v0²/2a. These link the seconds to a, but c = K/a depends on a too, so Grassline solves for a by bisection. Faster greens give a larger c, and so more grass: the table shows aim angles from 2.4° on a 10-second green to 7.5° on an 18-second one.

**Calibrating your bowls.** The model says width = (c/2) × length for every draw on one green, a line through the origin. So the best c is the least-squares slope through the origin: Σ L·W / Σ L². Timed bowls then give a, since T² = L √(4 + c²)/a, and K = c a. The fit is reported with its worst residual, so you can see whether your log is consistent.

**PHP features used:**
- `declare(strict_types=1)` and `readonly` promoted constructor properties.
- `match` as an expression, including `throw` inside it.
- Arrow functions (`fn`), and `array_shift`-based option parsing.
- `stream_get_contents` with a length limit, and `php://memory` streams so the tests drive the command line in-process.

## 4. Interview questions you might get

**Q: You had a differential equation. Why solve it in closed form instead of numerically?**
A: The closed form gives insight a simulation hides. It proves the aim angle doesn't depend on length or weight, which turns into the advice "learn one angle per green". It's also exact and instant, so tables over many lengths and greens cost nothing. I still wrote a Runge–Kutta integrator, but as a test: it checks the formula on 40 random bowls and greens to within 5 mm, which catches algebra slips.

**Q: How do you fit the model to a player's real shots?**
A: Each draw gives a jack length L and the width W the player aimed at. The model predicts W = (c/2)L, so c comes from least squares through the origin, which has the closed form Σ L·W / Σ L². Timed bowls give the deceleration, and together they give K, the bowls' bias constant, which carries over to any other green. The tests generate a log from known bowls and check the fit recovers them, to the rounding of the log.

**Q: What are the model's limits, and how would you test it against reality?**
A: Its limits:
- it assumes a flat, uniform green with no wind, a constant rolling resistance, and ideal precession;
- real bowls wobble, and fall over at the very end, where the model's turning rate grows without bound (though the remaining path is tiny);
- greens are often faster on one side.

To test it, I'd film draws from above at several lengths and compare the measured paths with the formula's shape, especially the shoulder's position. The calibration log is the practical version: if the widths at different lengths don't fall on one line through the origin, the model is missing something on that green.

## 5. Ideas to extend it

- **Slopes and fast hands:** add a constant sideways acceleration for a tilted or uneven rink, and fit it from forehand and backhand draws together.
- **Shots other than draws:** a "weighted" shot meant to finish a metre past the jack, or a drive that should hit a bowl in its path, using the path's speed at each point to show where the bowl is still running straight.
- **A phone page:** enter the jack length and green, see the aim drawn on a photo of the rink, and log your shots during a game to improve the fit.
