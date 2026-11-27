# How Farswell works

## The physics in one line

In deep water a wave's energy travels at the **group speed** `c_g = g T / (4π)`: a 20 s swell moves at about 15.6 m/s, a 10 s swell at half that. A storm at distance `d` that churns up every period at time `t0` delivers period `T` to a buoy at

```
t = t0 + d / c_g = t0 + 4π d / (g T)
```

Write `f = 1/T` and it becomes a straight line:

```
f = (g / (4π d)) · (t − t0)
```

So at each buoy, **frequency rises linearly with time**. The slope is `g / (4π d)` (a steep line means a near storm) and the line crosses `f = 0` at the storm time `t0`. Walter Munk used this in 1947, and Snodgrass and colleagues in 1966 tracked swell across the Pacific with it. Farswell turns it into a tool.

## Architecture

```
readings.txt ─► Input ─► Physics.fit_buoy (per buoy, robust, flags outliers)
                           │
                           ▼
                   Physics.joint_fit (one t0, a distance per buoy)
                           │            └─► Physics.bootstrap (refits)
                           ▼
                   Geo.locate (great-circle trilateration + directions)
                           │
                           ▼
         Farswell.forecast ─► Render (chart, table, map, forecast)
```

## File tour

| File | What it does |
|---|---|
| `bin/farswell` | Command line: options, bounds on every option, clean error messages and exit codes |
| `lib/Farswell/Input.pm` | Reads a regular file of at most 1 MiB, parses `buoy` lines and readings, validates every number and date |
| `lib/Farswell/Physics.pm` | Group speed, Theil-Sen, the per-buoy fit, the joint fit with a shared storm time, the bootstrap and its seeded generator |
| `lib/Farswell/Geo.pm` | Haversine distance, initial bearing, destination point, and `locate` (grid search over the globe + compass-search refinement) |
| `lib/Farswell.pm` | `analyse` ties it together, turns bootstrap spreads into error bars and warnings; `forecast` predicts a beach |
| `lib/Farswell/Render.pm` | The text chart, map and tables |
| `t/*.t` | 145 tests: physics identities, geometry against known values, trilateration and mirror cases, hostile input, end-to-end recovery of a synthetic storm, the CLI |

## Key concepts

**Theil-Sen regression.** The slope is the median of the slopes between every pair of readings; the intercept is the median of what's left. It tolerates up to about 29% of wild points. Readings further than 3.5 robust standard deviations (1.4826 × the median absolute residual, but never less than 0.002 Hz, roughly a 0.1 s rounding step) are marked as outliers and left out of everything after.

**Joint fit with a shared storm time.** Every buoy saw the same storm, so `t0` is shared. For a fixed `t0`, each buoy's best slope is a one-line formula, `a = Σ f(t−t0) / Σ (t−t0)²` (a line through a fixed point). That leaves a one-dimensional search over `t0`: a 400-step scan over the 20 days before the first reading, then golden-section refinement. If the answer hugs the edge of the window, or the buoys alone disagree by more than 36 hours, Farswell warns that they may be seeing different storms.

**Trilateration on a sphere.** The storm is the point P minimising `Σ ((dist(P, buoyᵢ) − dᵢ) / σᵢ)² + Σ (angle(bearingᵢ(P), dirᵢ) / 12°)²`. A 2° grid over the whole globe finds the basins, a compass search (eight directions, halving the step) polishes the two best distinct ones, and the runner-up is reported if it fits almost as well. With buoys strung along a coast that happens a lot: distance circles cross twice, once out to sea and once on the mirror side. One reported direction settles it.

**Residual bootstrap.** Keep each fitted line, add back that buoy's own residuals drawn at random with replacement, refit the whole chain (joint fit and location). 200 refits give the 90% ranges. The generator is a small seeded xorshift, so the same file always gives the same numbers.

**Perl features used.** Closures (the generator, the map's coordinate functions), anchored regexes as the only parser, `lstat` + `-l _` / `-f _` for safe file checks, `Getopt::Long::GetOptionsFromArray`, `Time::Local::timegm_modern`, `POSIX::strftime`, block `eval` only for catching errors, `Exporter` with explicit export lists.

## Interview questions

**Q: Why fit frequency against time instead of period against time?**
A: Because `1/T` is linear in `t`, while `T` is a hyperbola. A linear model lets us use robust line fitting and read distance and storm time straight off the slope and intercept, and the residuals stay roughly the same size along the line.

**Q: Why Theil-Sen rather than least squares, and what does it cost?**
A: Buoy peak period jumps to a local wind sea or a different swell for hours at a time; least squares lets one such point pull the line badly. Theil-Sen ignores up to ~29% of them. It's O(n²) in the number of readings, which is why the input caps readings at 600 per buoy (about 180,000 pairs).

**Q: Two buoys give two possible storm positions. How do you avoid silently giving the wrong one?**
A: The global grid finds every basin of the misfit, not just the nearest one. The best two distinct minima (more than 1,500 km apart) are both refined, and if the second fits within about two standard deviations of the first it is reported and warned about. A swell direction from any one buoy adds a bearing term that breaks the tie.

## Extension ideas

1. **Moving storms.** Let the source move along a track `P(t)`, so each period comes from where the storm was when it made it; fit a straight-line track by adding two parameters.
2. **Read buoy spectra, not just peak period.** With full spectra every frequency band gives its own arrival time, so one buoy yields dozens of points per hour and can track two swells at once.
3. **Coastline shadowing.** Load a coarse land mask and drop great-circle paths that cross land, so a beach hidden behind an island gets no forecast instead of a wrong one.
