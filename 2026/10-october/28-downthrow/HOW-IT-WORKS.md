# How Downthrow works

A walkthrough so you can explain every part of it.

## 1. The big picture

```
 survey.txt ──▶ App.pm      bounded read → strict UTF-8 → Parse.pm (fixed line forms, ranges)
                  │
                  ▼
              Plane.pm     least-squares plane → dip, dip direction, strike, errors, predictions
                  │
                  ▼
              Fault.pm     every split by a straight line → best "stepped plane"
                  │          → 99 simulated unfaulted surveys searched the same way → p-value
                  ▼
              Report.pm    attitude, fault verdict and fan of trends, apparent dips, predictions
```

## 2. File tour

| File | Job |
|---|---|
| `bin/downthrow` | The executable, run under taint mode (`-T`) |
| `lib/Downthrow/App.pm` | Arguments, bounded raw reading, strict UTF-8 decoding, exit codes |
| `lib/Downthrow/Parse.pm` | The survey format and every limit |
| `lib/Downthrow/Plane.pm` | Gaussian elimination, the plane fit, attitude and its errors, apparent dip, predictions |
| `lib/Downthrow/Fault.pm` | The fault search, the bootstrap significance test, the fan of possible trends |
| `lib/Downthrow/Report.pm` | Puts it together; flags a survey slip |
| `t/downthrow.t` | 9 subtests, 66 checks (`prove -l t`) |

## 3. Key ideas

### A plane through boreholes
Each borehole gives (east, north, elevation). The layer is modelled as `z = a + b·x + c·y` and fitted by least squares. The coordinates are centred first, so real map grids (millions of metres) don't swamp the arithmetic. The slopes (b, c) point up the layer, so:

- **dip** = atan(√(b² + c²)), the steepest tilt;
- **dip direction** = the compass direction of −(b, c), the way the layer goes down;
- **strike** = dip direction − 90° (the right-hand rule: face along strike and the layer dips to your right).

Error bars come from the slopes' covariance σ²(XᵀX)⁻¹ by the **delta method**: the error along the gradient gives the dip error, and the error across it, divided by the gradient's length, gives the direction error.

### Apparent dip
A cross-section that isn't along the dip direction sees a gentler slope: `tan(apparent) = tan(dip) · cos(bearing − dip direction)`. That's zero along strike and the full dip down the dip direction.

### The fault model
A vertical fault leaves the same tilted bed on both sides, but one side has moved down by the **throw**: `z = a + b·x + c·y + d·s`, where s is 1 on one side of the fault line and 0 on the other. For each direction θ (every 2°), the points are sorted by distance across a line running along θ, and every gap between neighbours is a candidate fault position. The normal equations need only running sums (Σx, Σxy, …, plus the same sums for one side), so each candidate costs one 4 × 4 solve, not a refit.

### Is the fault real? A bootstrap over the search
Comparing "one plane" with "the best of about 1,000 splits" by an ordinary F-test would almost always find a fault, because searching that many splits guarantees something fits a little better. So Downthrow simulates the null hypothesis. It builds 99 surveys at the same borehole positions from the single-plane fit plus normal noise of its size, runs the identical search on each, and counts how often a fault-free survey yields an F statistic as big as the real one. The p-value `(1 + count) / (1 + 99)` therefore includes the search. A test checks that plain planes rarely get flagged, and that a planted 12 m fault is found with its throw and side.

### Why a fan, not one angle
With few boreholes, many fault lines split the points into the same two groups and fit exactly as well. Downthrow names each split by which points fall on the same side as the first point, finds every direction that produces the winning split, and reports the tightest arc of directions holding them all. In the example it's 174° to 046°. The true trend was 030°.

### Perl features you met here
- **Taint mode (`-T`)**, and validating `$FindBin::RealBin` with a regex before `use lib`.
- **Three-argument `open`** with a `:raw` layer, and `read` in a loop with a byte limit.
- **`Encode::decode` with `FB_CROAK`** for strict UTF-8.
- **Exceptions as hash references** (`die { input => ... }`) to tell input errors apart from bugs.
- **Closures** (the seeded random generator), **`sort` with a custom comparator**, and the **Schwartzian-style** `map → sort → use` pattern for ordering points across a line.
- **In-memory filehandles** (`open my $fh, '<', \$string`) in the tests to drive the command line.

## 4. Interview questions you might get

**Q: Why not just run an F-test between one plane and the best faulted plane?**
A: Because the faulted model was chosen as the best of about 1,000 candidate splits, and the F-test assumes the split was fixed in advance. I simulate fault-free surveys at the same borehole positions, run the same search on each, and compare: the p-value includes the search. The tests show that unfaulted data is rarely flagged.

**Q: How is the dip direction computed, and what's the gotcha?**
A: From the plane's slopes east (b) and north (c): the layer goes down along −(b, c), so the direction is atan2(−b, −c) in compass convention (clockwise from north, so east comes first in atan2). The gotchas are angle wrap-around (a test caught 360° where it should be 0°) and remembering strike's right-hand rule.

**Q: What stops a malicious survey file from doing harm?**
A: Taint mode, three-argument raw `open`, regular files only, a 64 KB read limit, strict UTF-8, anchored patterns for every number and name, and refusal of control and direction characters. Error messages never echo the input. The work is bounded by caps on points, sections, sites and the fault search. There's no shell, no string eval and no network.

## 5. Ideas to extend it

1. **Inclined faults:** let the fault plane dip, so the step depends on depth, which matters for deep boreholes.
2. **Two faults:** search for a second split inside each side, with the same bootstrap logic.
3. **Draw it:** an SVG map of the boreholes, contours of the fitted layer, and the fan of possible fault traces.
