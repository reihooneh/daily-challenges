# How Bunchmark works

## 1. The big picture

```
ride file ──parse──▶ riders, stretches, candidate places, max_gap
                         │
               physics.speed: each rider's steady speed on each stretch
                         │
               plan.segment_times: on non-climbs everyone takes the bunch pace (the slowest)
                         │
               plan.stage(a, b): everyone leaves a together; times to b, largest gap on the way
                         │
               plan.best_plan: DP over places, fewest stops, then shortest ride
                         │            └─ none fits? plan.split: every faster/steadier split
                         │
               report: stops, who waits, the profile
```

## 2. File tour

- **`physics.py`:**
  - `speed` solves the power balance by bisection;
  - `seconds` turns a stretch into a time.
  - The constants (air density, rolling resistance, drag area, the 30% draft saving, the 55 km/h descent cap) are named at the top.
- **`parse.py`:** a line-by-line reader with a fixed set of commands. It uses full-match regular expressions for numbers and names, and checks limits as it goes.
- **`plan.py`:**
  - `segment_times` builds the time table;
  - `stage` turns two places into a stage;
  - `best_plan` is the dynamic program;
  - `split` tries every way to split the bunch in two.
- **`report.py`:** formats times, the plan and an ASCII elevation profile.
- **`cli.py`:** argparse, plus bounded, link-refusing file reading.

## 3. Key ideas

**The power balance.** At a steady speed v on a slope θ, the power at the pedals (less about 3% lost in the drivetrain) goes on three things:
- lifting the rider and bike: m·g·sin θ·v;
- rolling the tyres: m·g·C_rr·cos θ·v;
- pushing the air: ½·ρ·CdA·v³.

So on a steep climb, speed depends mostly on watts per kilo, and on the flat mostly on watts and air drag. That's why the 95 kg rider who's strong on the flat is the one waiting for on the hills. The equation f(v) = power − v·gravity − ½ρCdA·v³ is concave with f(0) > 0, so it has exactly one positive root, and bisection finds it reliably for downhills too.

**A bunch is a bunch on the flat.** If everyone simply rode their own pace everywhere, the gap would grow all day, and no plan would look possible. Real bunches sit together in the draft on the flat and descend together. So on stretches under 4% everyone takes the slowest rider's drafted pace: gaps neither open nor close. On climbs the draft barely helps, and the gaps open.

**Why the fewest stops is the right goal.** The ride lasts as long as the slowest rider takes, plus the stops. Splitting a stage in two never makes the slowest arrival earlier: max(a + b) ≤ max(a) + max(b), so stopping can only add time. Stops exist for one reason, the gap. So the goal is lexicographic: the fewest stops that keep every gap within the limit, then the shortest ride among those.

**Dynamic programming over places.** Everyone leaves a stop together, so a stage depends only on where it starts and ends. best[j] is the best (stops, time) to reach place j with the bunch together. For each earlier place i whose stage to j keeps the gap in bounds, it tries best[i] + that stage. That's O(places² × stretches × riders), tiny for any real ride. Tuples compare lexicographically in Python, so `cand[:2] < best[j][:2]` is exactly the rule above.

**Testing against brute force.** For 300 random rides (random riders, gradients and candidate places), the test tries every subset of stops, keeps those where every stage stays within the gap, and takes the best (stops, time). The planner must match it exactly, or report "no plan" exactly when no subset works.

**Python features used:**
- dataclasses (frozen for riders);
- `itertools.pairwise` and `combinations` in the tests;
- `zip(strict=True)`;
- regular expressions with `fullmatch`;
- `argparse`, and `os.lstat` with `stat.S_ISREG` for safe file reading;
- `subprocess.run` with a list, never a shell, in the tests.

## 4. Interview questions you might get

**Q: Why is the dynamic program correct?**
A: It relies on optimal substructure. After a regroup, everyone is together and the past no longer matters: the rest of the ride depends only on where you are. So the best plan to place j ends with some last stage (i, j), and the part before it must be a best plan to place i. If it weren't, swapping in a better one would improve the whole. The objective (stops, time) adds up over stages, and tuple comparison respects addition. So taking the minimum over i of best[i] + stage(i, j) is exact.

**Q: How did you make the physics trustworthy?**
A: Several ways:
- **Equation:** a test checks the computed flat speed satisfies the power equation to six decimals.
- **Watts per kilo:** a test checks two riders with the same watts per kilo climb a 10% hill at almost the same speed. That's a known property: gravity dominates there.
- **Monotonic:** speed must fall steadily as the gradient rises.
- **Safety cap:** descents are capped at 55 km/h, a safe speed for a group.
- **Stated assumptions:** steady state, no wind, and typical drag and rolling figures are named constants, documented as limits.

**Q: The split tries every cut of a sorted list. Why is that enough?**
A: It sorts riders by their solo time over the whole route and only tries "the k fastest versus the rest". That isn't every partition (there are 2ⁿ of those), but it's the natural one for a ride. A bunch split that puts a slower rider with the fast group only makes that group's gaps worse, so the useful splits are almost always contiguous in speed. With at most 40 riders it's at most 37 plans, each a fast DP.

## 5. Ideas to extend it

- **Wind:** add a headwind per stretch (from the route's bearing and a forecast). Air drag then uses the air speed, not the ground speed, and sitting in the bunch matters even more on a windy flat.
- **Fatigue:** let each rider's power fade over the ride (a W′-balance model), so late climbs open bigger gaps.
- **GPX import:** read a recorded route, merge points into stretches of steady gradient, and suggest regroup places at the tops of climbs automatically.
