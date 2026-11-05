# How Swellmark works

Swellmark answers a question every furniture maker has to get right: will this piece survive a year of weather? This file covers the design, the physics, the Go features used, and the questions an interviewer might ask.

## 1. The big picture

```
design file ──Parse──▶ Design (parts with species, cut and axes; joints; climate)
                          │
                          ├─ MoistureAt: humidity ─Hailwood–Horrobin─▶ wood moisture at
                          │              built-at, the driest day and the dampest day
                          │
                          ├─ CheckJoint (each joint):
                          │     coefficient of A along the joint − coefficient of B
                          │     × length from the fixed point × change in moisture
                          │     = how far the parts shift against each other
                          │     → OK / WATCH / FAIL by the kind of joint
                          │
                          ├─ BuildWindows: the same check at every shop humidity 10–90 %
                          │
                          └─ Render: table, advice, build window ──▶ terminal
```

## 2. File tour

- **`wood.go`:**
  - the species table and `EMC()`, the sorption model;
  - `Coefficient()`, which picks longitudinal, radial or tangential for a direction, from the board's grain axis, width axis and cut.
- **`parse.go`:**
  - a line-by-line parser with one small method per line type;
  - `number()` checks the pattern and range;
  - `hidden()` refuses invisible characters;
  - every error is an `*InputError` with a line number.
- **`check.go`:**
  - the `Verdict` type and `CheckJoint()`, which holds all the engineering in about 40 lines;
  - `BuildWindows()` re-runs the check for every build humidity and merges the passes into ranges.
- **`report.go`:** turns results into a fixed-width table and advice sentences; sizes are rounded up to the next half millimetre, because that's what you can mark and cut.
- **`run.go`:** the command line with injected streams (so tests drive it without a subprocess), `Lstat` to refuse links, and `io.LimitReader` to bound input.
- **`swellmark_test.go`:** hand-worked numbers, property tests over 2,000 random joints, a table of hostile inputs, a fuzz target and command-line tests.

## 3. Key ideas

**Wood is a sponge for water vapour, in one direction.** Wood takes on or gives up moisture until it matches the air; this is its *equilibrium moisture content* (EMC). The Hailwood–Horrobin model treats the water as two populations, one bound tightly to the cell walls and one held loosely as a solution, and gives EMC from relative humidity and temperature. With the Wood Handbook's fitted constants, 65 % humidity at 20 °C gives 12.0 %, matching the published tables (the test checks four points).

**Three directions, three rates.** For each 1 % change in moisture, a board changes size by:
- about 0.005 % along the grain;
- about 0.07–0.26 % radially (through the rings);
- about 0.19–0.43 % tangentially (along the rings).

That makes it roughly fifty times more across the grain than along it. Which of the last two a board's *width* gets depends on how it was sawn: flat-sawn widths move tangentially (the most), quarter-sawn widths move radially (the least). `Coefficient()` is a single switch that captures this.

**A joint only cares about the difference.** Two boards joined along an axis each try to change length by `L × c × ΔMC`. If they're the same species with the same orientation, they move together and the joint feels nothing (the test `TestLongGrainToLongGrainNeverMoves`). Where the coefficients differ, the joint has to absorb `(c_A − c_B) × L × ΔMC`. A joint is usually fixed at its middle (one central screw, glue at the centre of a breadboard), so the ends see half the length. That's why `from-end` doubles the movement, and why craftsmen glue only the middle.

**Both seasons, from the day it was built.** Movement is measured from the moisture at build time, so the same table can be fine built in spring and fail built in a dry winter:
- `Damp` is the shift at the dampest day of the year, and `Dry` at the driest; they have opposite signs.
- A floating panel needs the *growth* to fit its gap and the *shrinkage* to leave it in its grooves, so both are checked separately.

**Searching the build humidity.** `BuildWindows` re-runs every joint at each whole humidity from 10 % to 90 % (81 checks per joint) and joins the passing values into ranges. This is cheap enough to do by brute force, and it answers a question no single-board calculator can: "is my shop too dry to fit these panels today?"

**Go features used:**
- small value types (`Result`, `Range`) returned by value;
- an `iota` enum with a `String()` method, so `%v` prints verdicts;
- `strings.Builder` for the report;
- interfaces for I/O (`io.Reader`/`io.Writer`), so `Run` can be tested in memory;
- `t.TempDir()` for the symlink test;
- Go's built-in fuzzing (`testing.F`).

## 4. Interview questions you might get

**Q: How do you test a physics model when you don't have a reference implementation?**
A: In three layers:
- **Known values:** the EMC model matches four points from the Wood Handbook's tables, and one joint is worked by hand from the formula.
- **Properties that must hold:** damper air means wetter wood; swapping a joint's two parts flips the sign but never changes the verdict; and a wider humidity range never makes a joint safer. These run over 2,000 random joints, so they catch mistakes no single example would.
- **Behaviour:** the two example files must give their documented totals.

**Q: Why is there no `if` for each species and joint combination?**
A: Because the model is linear and separable. Every case reduces to "coefficient along this axis", and `Coefficient()` handles that with one switch on grain, width and cut. A joint's movement is just the difference of two coefficients times length times moisture change, so new species are data, not code. The `species` line adds one without touching the program.

**Q: The input is a hand-written file. How did you make the parser safe?**
A: Limits first, then an allow-list:
- size is capped before parsing, via a `LimitReader` so an endless stream is cut off;
- each line must match one of eight fixed forms, and numbers must match `^\d{1,4}(\.\d{1,5})?$` before `ParseFloat`, so there's no `1e9`, `NaN` or hex;
- names come from a small character set, and invisible and control characters are rejected;
- errors never echo the input or the path;
- the fuzz test checks the whole pipeline never panics, whatever the input.

## 5. Ideas to extend it

- **Local climate data:** read a year of hourly humidity (from a home sensor, say) and report the worst week instead of two extremes. This would also capture how slowly thick boards respond, using a time constant per thickness.
- **Finish and sealing:** a good finish slows moisture exchange. Model it as a damped response, so a sealed tabletop sees a narrower range.
- **3D import:** read part sizes and grain directions from a SketchUp or FreeCAD export, find touching faces automatically, and turn each contact into a joint line.
