# Downthrow

**Finds the dip and strike of a buried rock layer from where boreholes met it, and checks whether a hidden fault has broken it. If one has, it gives the throw, which side dropped, and how sure it can honestly be after searching thousands of possible fault lines.**

Language: Perl 5 (core modules only, taint mode) · Field: structural geology · Day: 28 October 2026

Geologists find a buried layer, a coal seam or an aquifer top, by drilling: each borehole gives one point where the hole met the layer. Three points fix a plane (the classic *three-point problem*), and more give a least-squares plane with error bars. But a layer that is cut by a fault isn't one plane. It's one tilted plane stepped down on one side, and a single plane through it shows up as large, patterned misfits. Downthrow looks for that:

- **Dip and strike:** dip, dip direction and strike (right-hand rule) of the best plane, with standard errors and R².
- **Fault search:** every straight vertical fault line, every 2°, through every gap between points. Each split is fitted with "one tilted bed, stepped down on one side", using running sums, so each candidate costs one 4 × 4 solve.
- **Honest significance:** the best of thousands of splits always looks a little better than one plane. So the observed improvement is compared with 99 simulated surveys that have no fault, searched in exactly the same way (a parametric bootstrap), and the p-value accounts for the search.
- **Honest trend:** sparse boreholes often allow a whole fan of fault directions that split the points the same way, so it reports the fan, not a falsely precise single angle.
- **Apparent dip:** how steep the layer looks along any planned cross-section or road cut.
- **Predictions:** the layer's elevation at a new site with a 95% interval, its depth below the ground, which side of the fault the site is on, and a warning where the layer would sit above the ground (eroded away).
- **Survey slips:** a point that's far off the plane the *other* points make is flagged.

## Quick start

```bash
perl -T bin/downthrow examples/ridge-farm.txt
prove -l t                     # 9 subtests, 66 checks
```

```
DOWNTHROW  Ridge Farm boreholes: top of the Ridge coal seam
18 points. Bearings are degrees clockwise from north; elevations in m.

One plane through every point:
  dips 10.5° (± 0.3) towards 244° (WSW, ± 1°); strike 154°
  scatter about the plane: 4.36 m (R² 0.989)

Fault search: every straight fault line every 2°, scored against 99 simulated unfaulted surveys.
  FAULT LIKELY (p = 0.01): trending somewhere between 174° and 046° (the points allow any line in that fan),
  passing near (5089, 8036);
  throw 20.0 m, E side down. Scatter drops from 4.36 to 0.88 m.
  Allowing for the fault, the bed dips 12.1° towards 251° (WSW); strike 161°.

Apparent dip in cross-sections:
  along 070°: 12.1° up
  along 160°: 0.1° up

Predicted top of the Ridge coal seam:
  NewHole-A  at 60.0 m (± 1.9, 95%); about 60.5 m below the ground [upthrown side]
  NewHole-B  at 112.9 m (± 2.1, 95%); that is 14.9 m above the ground, so here it has likely been eroded away [downthrown side]
```

The example is **synthetic**: the bed was built dipping 12° towards 250°, cut by a fault trending 030° with an 18 m throw, plus 0.8 m of noise. A single plane gets the dip wrong (10.5°) and leaves 4 m of scatter. Allowing for the fault recovers 12.1° and drops the scatter to 0.9 m. The true trend, 030°, is inside the reported fan.

## The survey file

```
survey Ridge Farm boreholes
horizon top of the Ridge coal seam
units m                          # m or ft (only used for labels; keep x, y and z in the same unit)
point BH01 5054.8 8335.9 84.12   # id, east, north, elevation of the horizon
section 070                      # optional: apparent dip along this bearing (up to 8)
predict NewHole-A 5000 8300 ground 120.5   # optional: a planned site (ground elevation optional)
```

Exit codes: `0` report printed, `2` bad usage or input. `-` reads standard input.

## Security

Downthrow reads one text file and prints text, so the risks are hostile input and runaway work:

- **Taint mode:** the program runs under Perl's `-T`, so data from outside can't reach a system call without being checked, and even the library path is validated before use.
- **Safe file access:** three-argument `open` in raw mode, regular files only. A name like `|echo pwned` is treated as a missing file, never a command, and the tests check this.
- **Bounded reading:** at most 64 KB from a file or standard input; an endless stream is cut off. The bytes are decoded as UTF-8 strictly (`FB_CROAK`), so invalid input is refused rather than replaced.
- **Strict parsing:** every line has a fixed form. Numbers must be plain decimals (no `NaN`, `Inf` or exponents) within set ranges. Names and ids use a small character set, and duplicate ids and coincident points are refused. Control characters (terminal escapes), zero-width characters and direction marks are refused.
- **No echo:** error messages give a line number and never repeat the input or the file name.
- **Bounded work:** at most 400 points, 8 sections and 50 sites. The fault search runs only for 8 to 120 points, with a fixed 90 directions and 99 simulations, a few seconds at most.
- **No dangerous features:** no string `eval`, no shell and no network. It uses core modules only and runs with `use warnings FATAL => 'all'`.

**Known limits:** one planar layer and at most one straight, vertical fault. Real layers fold, and real faults are inclined and curved. Extrapolating far beyond the boreholes is guesswork, and the widening error bars say so. Use it to plan the next borehole, not to replace one.

See [HOW-IT-WORKS.md](HOW-IT-WORKS.md) for the walkthrough.
