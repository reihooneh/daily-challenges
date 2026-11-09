# How Floatwise works

## 1. Architecture

```
chart.txt ──Main.read (regular file, no links, ≤64 KB, strict UTF-8)──▶ Chart.parse ──▶ Chart (rows bottom first)
                                                                                         │
                                         Planner.floats(): every strand behind every run of other stitches
                                                                                         │
                         for each row: rowOptions = every way to catch its long floats with the fewest catches
                                       (each way is a 64-bit mask of catch columns + its own cost)
                                                                                         │
                         plan(): dynamic programme up the rows; the cost between two rows comes from their masks
                                                                                         │
                     evenlySpaced(): the usual habit, scored the same way (describe)     │
                                                                                         ▼
                                       Report.text (chart, catches, round-by-round)   Report.svg (drawing)
```

## 2. File tour

- **`Chart.java`:** a record holding the title, round or flat, the float limit, the colours and the rows.
  - `parse` validates everything and stores rows bottom first, so index 0 is round 1.
  - `stitchNumber` converts a column to the knitter's count from the right.
- **`Planner.java`:** the core.
  - `floatsInRow` finds strands, cyclically in the round.
  - `catchesNeeded` and `floatOptions` give every minimal way to catch one float.
  - `rowOptions` combines them for a row.
  - `between` prices two neighbouring rows from their masks; `plan` is the dynamic programme.
  - `evenlySpaced` is the comparison; `describe` scores any plan, and the tests use it for brute force.
- **`Report.java`:** the text plan and an escaped, self-contained SVG.
- **`Main.java`:** options, careful reading, and a create-only write.

## 3. Key concepts

**Floats, cyclically.** For each colour in a row, the strand runs from one stitch of that colour to the next, floating behind the stitches between. In the round the chart repeats, so the last stitch of one repeat is followed by the first stitch of the next. The gaps are therefore taken modulo the width, `floorMod(next − cur − 1, width)`, and a lone stitch floats `width − 1` stitches to its twin in the next repeat. Flat rows only have the gaps between stitches.

**The fewest catches.** A catch traps the strand behind one stitch, cutting the float into two pieces. With *k* catches, a float of *L* stitches leaves *L − k* stitches in *k + 1* pieces. Each piece must be at most *m*, so *L − k ≤ m(k + 1)*, which gives *k ≥ (L − m)/(m + 1)*. That simplifies to *k = ⌊L/(m + 1)⌋*. `floatOptions` then enumerates every placement of exactly *k* catches with every piece within *m*, pruning as soon as a piece gets too long.

**Why plan the chart as a whole.** Whether a catch shows depends on the catches above and below it, so rows can't be planned one by one. The interaction is only between neighbouring rows, though. That makes a chain, and a chain can be solved exactly by dynamic programming:
- the state for a row is which way it was caught;
- the cost is the row's own cost plus `between(previous row, this row)`;
- for each way of catching a row, keep the cheapest way to have got there.

This is the Viterbi algorithm over rows, O(rows × options²).

**Bit masks.** A row's catches are a `long` with one bit per column, which is why the width is capped at 64. Stacked catches are `bitCount(below & above)`. Diagonal neighbours are the same against `below` rotated one stitch either way. In the round the rotation wraps, because stitch 1 of one repeat sits next to the last stitch of the previous one. A test covers the 64th bit, where `1L << 63` is negative and `>>>` matters.

**Staying bounded.** A row with several long floats could have very many combinations. If a row has more than 400, each float keeps its best options (by its own cost) until the product fits. The report then says so. Otherwise the answer is exact, and the tests confirm it against brute force on random charts.

**Java features used:**
- records for immutable data, with `List.copyOf` and `Map.copyOf` in a compact constructor;
- switch expressions with arrow labels, and text blocks for the usage message;
- `Long.bitCount` and unsigned shifts for the masks;
- `Files.readAttributes(…, NOFOLLOW_LINKS)` to refuse links;
- `StandardOpenOption.CREATE_NEW` for a write that can't clobber;
- a `CharsetDecoder` set to `REPORT` to reject invalid UTF-8.

## 4. Interview questions

**Q: Why does the dynamic programme give the best plan for the whole chart, not just row by row?**
A: Because the cost splits into terms that each involve only one row or two neighbouring rows. That's a chain-structured problem: given the choice for row *r − 1*, the best choices for rows *r* onward don't depend on anything earlier. So keeping, for every option in row *r*, the cheapest total to reach it loses nothing. If I also penalised catches two rows apart, the state would have to be a pair of rows, and the cost would grow to options³ per step.

**Q: How do you test an optimiser?**
A: Against a slow but obviously correct version:
- **Catches:** for every float length and limit, I brute-force all subsets of stitches. The minimum catch count must match, and the set of valid placements must be exactly the options generated.
- **The plan:** on over a hundred small random charts, I try every combination of row options. The dynamic programme's cost must equal the best.
- **Properties on larger charts:** no float is left over the limit, both plans use the same number of catches, and the plan is never worse than even spacing.

**Q: What would break at scale, and how did you bound it?**
A: The number of ways to catch a row is a product over its floats, so it can explode, and the DP is quadratic in it. I cap each row at 400 options by trimming each float to its best placements. The report then admits that the result is no longer guaranteed optimal. Inputs are capped (64 × 200 stitches, 64 KB), so the worst case runs in about a second and a half.

## 5. Extension ideas

- **Two rounds of memory:** penalise catches two rounds apart too, using pairs of rows as the state, for very fine yarns where those show as well.
- **Carry up the side in flat work:** plan where to twist the strands at the edges, and when to cut a colour that won't be used again for many rows.
- **Read charts from images or spreadsheets:** import a coloured grid (CSV, or a PNG with one pixel per stitch) instead of symbols.
