# How Skyglass works

A friendly walkthrough so you can explain every part of it.

## 1. The big picture

```
main.go  (the CLI)                  sky/  (the maths, no printing)
──────────────────                  ──────────────────────────────
read flags, pick a place            sun.go     Sun(date, lat, lon)
load the real time zone   ───────▶  moon.go    Moon(instant)
print the report          ◀───────  render.go  RenderMoon(phase, ...)
```

Just like Keyglint yesterday, the **calculations are kept separate from input and output**. The `sky` package never prints anything, which makes it easy to test with exact numbers.

## 2. File tour

### `sky/sun.go`: where the Sun is
1. **Where are we in the year?** The date becomes an angle `g` (0 to 2π) called the *fractional year*.
2. **Two numbers from NOAA's formulas:**
   - **Declination:** how far north or south the Sun is overhead. It swings between +23.4° (June) and −23.4° (December), which is why we have seasons.
   - **Equation of time:** how many minutes a sundial runs ahead of or behind a clock. It happens because Earth's orbit is an ellipse and its axis is tilted.
3. **Solar noon** = `720 − 4 × longitude − equation of time` minutes after midnight UTC. The "4" is because Earth turns 1° every 4 minutes.
4. **Sunrise and sunset:** we solve for the *hour angle*, how far the Earth must turn from noon until the Sun is at the horizon. Then sunrise = noon − 4 × hour angle, and sunset = noon + 4 × hour angle.
5. **Why 90.833° and not 90°?** The atmosphere bends light (refraction), and the Sun is a disc, not a dot, so we see it about 0.83° before it's geometrically up.
6. **Polar days:** if the equation for the hour angle has no solution (the cosine would be bigger than 1), the Sun never reaches the horizon, which means polar night or midnight sun.

### `sky/moon.go`: the Moon's phase
We start from one known new moon (6 January 2000) and count how many **synodic months** (29.53 days, one new moon to the next) have passed. The fractional part is the phase: 0 = new, 0.5 = full. The percentage lit is `(1 − cos(2π × phase)) / 2`.

### `sky/render.go`: drawing the Moon
For each row of the circle we find its half-width `w`. The **terminator** (the line between light and dark) sits at `w × cos(2π × phase)`. While the Moon grows (waxing), everything right of that line is lit; while it shrinks (waning), everything left of it. Characters are about twice as tall as they are wide, so each unit uses two columns to keep it round. In the southern hemisphere the whole picture is mirrored.

### `main.go`: the command line
Parses flags, looks up a city or validates custom coordinates, loads a **real IANA time zone** (like `Australia/Sydney`) so daylight saving is automatic, then prints the report. The program lives in `run(args, out, errOut, now)` instead of `main()`, so tests can feed in fake arguments, capture the output and fix "now" to a known date.

## 3. Key concepts

| Concept | Plain version |
|---|---|
| Declination | How far north or south the Sun is overhead today |
| Equation of time | Sundial time minus clock time |
| Hour angle | How far Earth has to turn from noon until the Sun reaches the horizon |
| Refraction | The air bends light, so we see the Sun a bit early |
| Synodic month | 29.53 days from one new moon to the next |
| IANA time zones | Named zones like `Australia/Sydney` that know their own daylight-saving rules |

### Go features you met here
- **Packages:** `sky` is its own package, imported by `main` using the module path in `go.mod`.
- **Multiple return values:** `solarParams` returns two values, and `hourAngle` returns three (`ha, ok, above`). Go uses this instead of exceptions.
- **`iota` enums:** `Normal`, `MidnightSun` and `PolarNight` are numbered automatically.
- **`flag.FlagSet` with `ContinueOnError`:** lets tests run the CLI without the program exiting.
- **`io.Writer`:** `run` writes to any writer, a real terminal or a `bytes.Buffer` in tests.
- **Table-driven tests:** Go's idiomatic style, looping over a list of cases.

### A bug the tests caught
At exactly full moon, the very edge of the drawing came out dark. The check was `x < edge` when it needed `x <= edge`. It's a classic *off-by-one at the boundary* bug, and the test "a full moon should have no dark characters" found it straight away.

## 4. Interview questions you might get

**Q: How did you check the answers are right?**
A: I compared sunrise and sunset against a published almanac for Sydney (within 2 minutes, across a daylight-saving change), checked physical facts like about 12 hours of daylight at the equator on the equinox and polar night at 78°N in December, and tested Moon phases against the 2026 eclipses, which can only happen at full or new moon.

**Q: Why is sunrise calculated at 90.833° instead of 90°?**
A: Atmospheric refraction lifts the Sun's image by about 0.57°, and sunrise is defined by the top edge of the Sun (radius about 0.27°). Together that's about 0.83°.

**Q: What's the limitation of your Moon calculation, and how would you improve it?**
A: It uses the *mean* lunar month, but the Moon's orbit is elliptical, so actual phases can be up to about half a day off. For precision I'd add the main periodic correction terms from Jean Meeus's *Astronomical Algorithms*.

## 5. Ideas to extend it yourself

1. **Golden hour:** add the times when the Sun is 6° above the horizon (photographers love this). It's the same hour-angle formula with a different zenith.
2. **A whole-month calendar** view with a tiny Moon symbol for each day.
3. **Moonrise and moonset:** harder, because the Moon moves quickly across the sky. A great next challenge.
