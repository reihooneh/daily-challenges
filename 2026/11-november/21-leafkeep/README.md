# Leafkeep

**Every cup of a gongfu tea session at the same strength, and an honest warning when the leaves are spent.**

In gongfu brewing you steep the same leaves many times, a few seconds to a few minutes each. The
usual advice is "add five or ten seconds each time", but the leaves don't run down evenly: the
surface of the leaf gives up its flavour quickly, the inside only opens as the rolled leaf unfurls,
the water cools in the pot while it steeps, and the wet leaves hold back some of each cup and pass
it into the next. Leafkeep models all of that, takes the strength of your first cup as the target,
and times every later steep to match it.

## Features

- **Equal-strength steep times** for green, white, oolong, black and pu-erh tea, any leaf, water,
  temperature and pot (gaiwan, clay or glass, which cool at different rates).
- **Knows when the leaves are spent**: the session stops when no steep under 15 minutes can reach
  the strength, and shows how many more cups a lighter strength would give.
- **Calibrates to your tea** from refractometer readings (`steep_seconds,tds_percent`), fitting how
  much the leaf holds and how fast both parts of it give it up, then plans with the fitted tea.
- No dependencies beyond the Rust standard library.

## Example

```
$ leafkeep plan --tea oolong --leaf 5 --water 100 --temp 95 --first 20
oolong tea, 5 g in 100 ml at 95 °C. Every cup at 1.5 mg/ml (about 0.15 % TDS).

  #   steep   poured off at   left in the leaves
   1    20 s      92 °C          90 % ███████████████████████████
   2    25 s      91 °C          80 % ████████████████████████
   3    30 s      91 °C          70 % █████████████████████
   4    33 s      90 °C          60 % ██████████████████
   5    37 s      90 °C          50 % ███████████████
   6    42 s      89 °C          40 % ████████████
   7    51 s      88 °C          30 % █████████
   8    1:10      85 °C          20 % ██████
   9    2:06      78 °C          10 % ███

After 9 infusions the leaves can't reach that strength even in 15:00: they're spent.

A lighter cup lasts longer:
   80 % of this strength: 12 infusions
   60 % of this strength: 15+ infusions
```

Fitting a tea from measurements (`examples/oolong-readings.csv`):

```
$ leafkeep calibrate examples/oolong-readings.csv
Fitted to 7 infusions (typical error 0.004 % TDS):
  solubles 34 % of the leaf, surface rate ×1.25, inner rate ×0.89 of the oolong preset

  #   steep   measured   fitted
   1    20 s     0.19 %    0.19 %
   2    25 s     0.16 %    0.17 %
   ...
```

## Run and test

```sh
cargo run --release -- plan --tea puerh --pot clay --first 10
cargo run --release -- calibrate examples/oolong-readings.csv
cargo test
cargo clippy --all-targets -- -D warnings
```

Options: `--tea green|white|oolong|black|puerh`, `--leaf` grams (0.5–30), `--water` ml (30–500),
`--temp` °C (60–100), `--pot gaiwan|clay|glass`, `--first` seconds (2–300), `--cups` (1–30).

## Security

- Every number is range-checked and must be finite; NaN and infinity are refused, as is more leaf
  than the water can wet.
- The readings file must be a regular file under 64 KB with 3 to 40 rows of exactly two numbers;
  anything else is an error naming the line.
- Text echoed back in errors (an unknown tea or option) is stripped of control characters and cut
  short, so a crafted argument can't inject terminal escape sequences.
- `#![forbid(unsafe_code)]` via the crate lints, no dependencies, overflow checks on in release, and
  the search loops are bounded (40 bisection steps, a fixed calibration grid).
- Known limits: the tea presets are typical figures, not measurements of your tea; calibrate for
  numbers you can rely on.
