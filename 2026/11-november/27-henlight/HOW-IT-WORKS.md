# How Henlight works

## Architecture

```
src/sun.ts      sunrise and sunset (NOAA formulas), daylight-saving rules, the wall clock
src/plan.ts     each day's window of acceptable light, every timer setting, the greedy plan
src/config.ts   settings from flags or a JSON file, all checked
src/cli.ts      the season's days, the plan, the report and chart
src/main.ts     the command line
tests/          sun times, daylight saving, greedy vs dynamic programming, the plan's promises, hostile input
examples/       a Sydney backyard and a London allotment
```

## Key concepts

**The sun.** The fractional year `γ` drives two Fourier series:

- the *equation of time*, how far sundial noon runs ahead of or behind clock noon;
- the sun's *declination*, how far north or south of the equator it sits.

The hour angle at sunrise solves `cos(90.833°) = sin φ sin δ + cos φ cos δ cos h`. The 0.833° is
atmospheric refraction plus the sun's own radius. Sunrise in UTC is then `720 − 4(λ + h) − EoT`
minutes, and the local offset (plus an hour in daylight saving) puts it on the wall clock.

**The window.** Each day gets a range of acceptable total light `[lo, hi]`:

- **While ramping up:** `lo` grows from the first day's daylength by the ramp each week, and `hi` is
  one week's step above it, so the hens are never pushed faster than that.
- **After that:** `[target, most]`.
- **Always:** `hi` is never below natural daylength, because nobody can take daylight away.

**A setting** is "lamp off", or an `on` and an `off` pin on the timer's grid. On a given day it
works if:

- the lamp comes on before sunrise and is still on at sunrise, so there's no dark gap;
- it goes off before sunset;
- the total light, from the lamp coming on until sunset, is inside the day's window.

**Why greedy is optimal.** Whether a setting works on a day depends only on that day. So if a
setting works for days `s..e`, it works for any run inside them. Planning then becomes covering the
season with the fewest runs, where each run must be coverable by a single setting. From the first
unplanned day, take the setting that reaches furthest. Any other plan's first run ends no later, so
by induction the greedy plan is always at least as far along after the same number of changes. The
tests compare it with dynamic programming over every split on 25 random seasons.

**Breaking ties.** Among settings that reach equally far, Henlight takes the one that burns the
lamp least. That saves energy, and means the lamp goes off soon after sunrise.

## Language features worth noticing

- **`exactOptionalPropertyTypes` and `noUncheckedIndexedAccess`.** Every array read is
  `T | undefined` until proven otherwise; the `!` marks are the places where the loop bounds prove
  it.
- **Discriminated unions.** `Setting = { off: true } | { off: false; on; until }`, so the compiler
  insists the lamp-off case is handled everywhere.
- **`Object.create(null)`** for settings read from a file: a JSON `"__proto__"` key becomes a plain
  key, which is then refused as unknown.
- **`node:test` and `node:assert/strict`**: tests with no test framework to install.

## Interview questions

**1. Why is the greedy plan optimal here, when greedy usually isn't?**
Because feasibility is *hereditary*: a setting that works for a run of days works for every shorter
run inside it. With that property, covering a line with the fewest feasible intervals is solved by
"furthest reach first", by a stays-ahead argument. After k changes, the greedy plan has covered at
least as many days as any other plan. Without heredity, greedy can fail. For example, a rule like
"total light must never drop week to week" depends on yesterday's setting. The test against dynamic
programming would catch that if the rules changed.

**2. Daylight saving moves sunrise by an hour. How does the plan cope?**
The timer runs on the wall clock, so each date's sunrise and sunset are computed on that date's
clock (standard offset plus one hour while saving is in force). Nothing special is needed after
that: on the first day of daylight saving the old setting simply stops working, because sunrise
jumps past its off pin. The greedy then starts a new run there. The report marks those runs
"clocks changed".

**3. How would you check the sun times without trusting the same formulas?**
Against published tables: the tests use Sydney and London sunrise and sunset at both 2026
solstices, which cover both hemispheres, summer and winter, and daylight saving on and off. A
4-minute tolerance allows for the approximation. The polar case (no sunset at 80° north in June)
returns null, and the settings refuse latitudes beyond 60°, where the approximation and the
idea of a daily timer both break down.

## Extension ideas

- **Smart plugs:** with a smart plug instead of pins, the plan becomes a daily schedule, and the
  interesting problem turns into smoothing (no change bigger than a few minutes a day).
- **Twilight:** hens see civil twilight. Add it as an option and compare how many changes it saves.
- **Calendar export:** export the timer changes as an iCalendar file, so the reminders arrive on
  the right mornings.
