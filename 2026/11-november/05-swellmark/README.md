# Swellmark

**Finds the joints in a piece of furniture that the seasons will break. Wood swells across its grain in damp weather and shrinks in dry weather, but hardly changes along it. Glue a board's width to another board's length and something gives: a cracked top, a breadboard end pushed off, a panel that splits its frame. Describe the parts and joints in a few lines, give the indoor humidity over a year, and Swellmark checks every joint and tells you what to change, and at what shop humidity it's safe to build.**

Language: Go 1.24 (standard library only) · Field: woodworking / wood science · Day: 5 November 2026 (evening)

Woodworkers know the rule ("allow for movement"), and there are calculators for how much one board moves. What's missing is the check that matters: for *this* design, which joint fails, in which season, and by how much. Swellmark does that:

- **Real wood physics:**
  - the Hailwood–Horrobin sorption model turns air humidity and temperature into the moisture content wood settles at;
  - each species' radial and tangential coefficients turn moisture into millimetres;
  - flat-, quarter- and rift-sawn boards each move differently.
- **Every joint, both seasons:** each joint is checked as the parts try to move against each other, from the humidity the piece was built at out to the dampest and the driest days of the year. Joints of each kind are judged differently:
  - **Rigid joints** (glue, screws, pegs, nails) have a limit on what they can absorb.
  - **Sliding joints** (slots, table buttons, figure-8 fasteners) have their travel checked.
  - **Floating panels** are checked for both swelling past their gap and shrinking out of their grooves.
- **Advice in shop terms:** how big to make the slots, what gap to leave around a panel and how deep to cut the grooves.
- **When to build:** it repeats the check at every shop humidity from 10 % to 90 % and gives the range where no joint fails. A panel fitted tight in a dry winter shop is the one that bursts its frame in summer.

## Quick start

```bash
make build
./build/swellmark examples/hall-table.txt          # with the classic mistakes (exit 1)
./build/swellmark examples/hall-table-fixed.txt    # the same table, done right (exit 0)
make test                                          # unit, property and command-line tests, with -race
make fuzz                                          # 30 s of fuzzing the parser
make lint                                          # gofmt and go vet
```

```
SWELLMARK  Hall table
Indoor humidity over the year: 30 % to 65 % at 20 °C, so the wood's moisture runs from 6.2 % to 12.0 %.
Built at 45 % humidity (8.5 % moisture).

  Verdict  Joint                   Fastening       Along       Moves (damp / dry)    Allows
  FAIL     top + end-left          glue            y 450 mm    +1.92 / -1.26 mm      0.35 mm (rigid)
  FAIL     top + end-right         pegs            y 450 mm    +1.92 / -1.26 mm      0.35 mm (rigid)
  OK       top + apron-front       glue            x 1100 mm   +0.00 / +0.00 mm      0.35 mm (rigid)
  WATCH    top + apron-side        buttons 2       y 400 mm    +1.71 / -1.12 mm      2 mm each way
  WATCH    apron-front + leg       glue            z 90 mm     +0.38 / -0.25 mm      0.35 mm (rigid)
  OK       back-panel + back-rail  floating 6/10   x 400 mm    +3.78 / -2.47 mm      6 mm gap

What to change:
  FAIL  top + end-left (line 17): Glue can't slide, so the joint will crack or tear apart: the parts move
        1.92 mm against each other in the damp season. Fix it at the middle only and let the rest slide
        (slots or elongated holes of at least 2.0 mm each way).
  ...
In all: 2 OK, 2 to watch, 2 failing.
No shop humidity from 10 % to 90 % saves every joint: the design itself has to change.
```

The fixed table (slotted breadboard ends, roomier buttons, a narrower tenon) passes every joint:

```
In all: 6 OK, 0 to watch, 0 failing.
Building at 33–63 % humidity keeps every joint from failing; 42–56 % keeps every joint OK.
```

"Moves" is how far the two parts shift against each other at the far end of the joint, measured from its fixed point. The fixed point is the middle unless the joint is marked `from-end`. For a floating panel it's the panel's whole change in width.

Exit code: 0 if no joint fails, 1 if one does, 2 for a bad file.

## The design file

```
design Hall table
climate 30 to 65            # indoor relative humidity over a year (%)
built-at 45                 # humidity in the shop when it was made (%)
temperature 20              # °C, optional (default 20)
rigid-limit 0.35            # mm a rigid joint can take, optional (see below)
species sapele radial 0.0017 tangential 0.0024   # add a species (change per 1 % moisture)

part top        cherry  flat     grain x  width y       # thickness runs along the third axis
part end-left   cherry  flat     grain y  width x

joint top end-left glue along y 450                     # glue, screws, pegs or nails
joint top apron-side buttons 3 along y 400              # slots, buttons or figure8: travel each way (mm)
joint back-panel back-rail floating 6 depth 10 along x 400   # total gap and groove depth (mm)
joint top cleat screws along y 300 from-end             # fixed at one end, not the middle
```

- **Axes:** x, y and z are the piece's own directions, so a top and an apron can be compared.
- **Built-in species:** ash, beech, birch, cherry, douglas-fir, maple, pine, poplar, red-oak, teak, walnut and white-oak.

### How the verdicts are decided

| Joint | OK | WATCH | FAIL |
|---|---|---|---|
| Rigid | moves ≤ the rigid limit | up to twice the limit | more than twice |
| Sliding | uses ≤ 75 % of the travel | up to all of it | more than the travel |
| Floating | grows into ≤ 75 % of the gap, and keeps ≥ 4.5 mm in each groove | in between | grows past the gap, or keeps less than 3 mm in a groove |

The default rigid limit of 0.35 mm is roughly what a 75 mm (3 inch) cross-grain glue joint in cherry sees in an ordinary year, the width woodworkers traditionally get away with. It's a rule of thumb, not a strength calculation, so `rigid-limit` lets you set your own.

## Security

The design file is the only input, and Swellmark treats it as untrusted:

- **Bounded:** files over 64 KB are refused, with reading cut off at the limit (so an endless stream stops). Lines are limited to 200 characters, parts to 100, joints to 300 and added species to 50.
- **Strict shapes:**
  - every line must be one of eight fixed forms, every number must match a plain decimal pattern and lie in its range, and names are lower-case letters, digits and hyphens;
  - invalid UTF-8, control characters (such as terminal escape codes) and invisible formatting characters (zero-width and bidirectional overrides) are refused.
- **No echoing:** errors give the line number and what was expected, never the line's text or the file's path.
- **Files only:** symbolic links, folders and devices are refused (checked with `Lstat`), and nothing is written.
- **Tested:** `go vet`, `gofmt`, the race detector, tests of malicious input, and a fuzz test that feeds the parser and report random files. The standard library is the only dependency.
- **Known limits:** the wood figures are averages, and real boards vary by perhaps ±20 %. Treat a WATCH as a real warning, and test a cut-off from your own stock if a joint is close.

## Files

| File | What it does |
|---|---|
| `internal/swellmark/wood.go` | Species coefficients, the Hailwood–Horrobin model, which way each cut moves |
| `internal/swellmark/parse.go` | Reads and checks the design file |
| `internal/swellmark/check.go` | Each joint over the year; the safe build humidity |
| `internal/swellmark/report.go` | The table and the advice |
| `internal/swellmark/run.go` | The command line and safe file reading |
| `internal/swellmark/swellmark_test.go` | Worked examples, properties, hostile input, fuzzing, the command line |
| `examples/` | A hall table with the classic mistakes, and the same table fixed |

See [HOW-IT-WORKS.md](HOW-IT-WORKS.md) for the design, the physics and interview questions.
