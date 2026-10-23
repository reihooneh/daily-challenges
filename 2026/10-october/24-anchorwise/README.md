# Anchorwise

**Shows how a climbing anchor really shares its load between the pieces, and what happens if one fails: how far the master point drops and how hard that jolts what's left.**

Language: Lua 5.4 (no libraries) · Field: climbing / engineering statics · Day: 24 October 2026

Climbers join two or three pieces of protection into one anchor and hope the load is shared. Whether it is depends on geometry and on how the sling was rigged:
- **Fixed rigging** (a cordelette tied off at the master point) behaves like springs. An arm tied a few millimetres long, or pulling at a different angle, can leave one piece doing most of the work.
- **Sliding rigging** (a sliding X or quad) evens out the tension. But if a piece fails, the master point drops until the sling catches, and that drop shock-loads whatever is left.
- **Wide angles** between the arms multiply the force on every piece.

Anchorwise models both kinds of rigging with real statics and runs the "what if this piece pops?" case for every piece.

## Quick start

```bash
lua anchorwise.lua examples/three-uneven.txt
lua test/test_anchorwise.lua          # 64 checks
```

```
ANCHORWISE  Three pieces, one arm tied long
Fixed (pre-equalized) rigging in nylon cord, 3 pieces, 2.0 kN load straight down.

With everything holding (master point settles at -0.02, -0.72; arms spread 57°):
  Piece                      Load   Share  vs an even split
  Top nut                 1.25 kN   62%  x1.87
  Left cam                0.51 kN   25%  x0.76
  Right cam               0.35 kN   17%  x0.52
  The pieces carry 2.10 kN between them for a 2.0 kN load (5% more: wide angles multiply force).

If one piece fails (the jolt assumes the load falls freely through the drop, so it is an upper estimate):
  Top nut                drops    9 mm, jolt up to about 5.0 kN, then 1.27 kN on the busiest piece
  Left cam               drops   10 mm, jolt up to about 5.1 kN, then 1.99 kN on the busiest piece
  Right cam              drops    6 mm, jolt up to about 4.8 kN, then 1.81 kN on the busiest piece

- One piece takes far more than its share: arms of unequal length or slack in an arm. ...
```

The right arm was tied 2 cm long, so it takes about half its fair share, and the short top arm makes up the difference. `examples/wide-sliding.txt` shows the opposite trade-off: perfectly even tension, but a 94° spread multiplies the load. If a piece fails, the drop to the limiter knot jolts the other piece with up to about 15.7 kN.

## The anchor file

```
anchor Two bolts on the belay ledge
load 2.5 kN                 # straight down; or 'load 2.5 kN at 15' for 15° right of down
rigging fixed nylon         # fixed or sliding; nylon, dyneema or static
master 0 -0.6               # fixed: where the master point is tied (metres; x right, y up)
sling 1.6                   # sliding: the sling's total length through the pieces
limit 0.15                  # sliding, optional: limiter knots this far from the master point
piece Left bolt -0.25 0
piece Right bolt 0.25 0 slack 0.01      # fixed, optional: this arm tied 1 cm long
```

Exit codes: `0` no warnings, `1` warnings to read, `2` bad input. `-` reads standard input.

**This is a teaching model.** It is 2D and assumes ideal knots and no friction, and the material stretch figures are approximate. It is not a substitute for training, a qualified instructor, or a careful check on the rock.

## Security

- **Bounded reading:** at most 16 KB is read, from a file or standard input, so `/dev/zero` or an endless pipe is cut off. Folders and unreadable files are refused. Standard Lua can't tell a symbolic link from a file, so links are followed, but every limit still applies.
- **Strict parsing:**
  - Every line has a fixed form, and every number is a plain decimal with a range: loads 0.1 to 25 kN, positions within 5 m, up to 6 pieces.
  - Names allow letters, digits and simple punctuation only.
  - The text must be valid UTF-8.
  - Control characters (terminal escapes) and hidden Unicode direction marks are refused.
- **Clean messages:** errors give a line number and never echo the input or the file name.
- **Bounded work:** the solvers have iteration caps and step limits, and report when they can't settle instead of looping.
- **No globals:** the tests run with a strict-globals guard (any undeclared global is an error), a stand-in for a linter.

See [HOW-IT-WORKS.md](HOW-IT-WORKS.md) for the walkthrough.
