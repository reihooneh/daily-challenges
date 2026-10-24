# How Weftwise works

A walkthrough so you can explain every part of it.

## 1. The big picture

```
 cutting list ──▶ parse.cpp     fixed line forms, ranges, UTF-8 checks → Quilt { Fabric { Piece } }
                     │
                     ▼          for each fabric:
                 cutting.cpp    1. lengthwise pieces → panels along the selvage
                     │          2. joined lengths  → beside a panel, or crosswise strips + a last part
                     │          3. everything else → strips: greedy plan, LP lower bound, branch and bound
                     ▼
                 report.cpp     strips merged, purchase in yards and metres, proof or gap
```

## 2. File tour

| File | Job |
|---|---|
| `src/measure.*` | Eighths of an inch as integers: parsing `6-1/2`, printing `6½`, yards and metres rounded up |
| `src/plan.hpp` | The data model: quilt, fabrics, pieces, and the error type |
| `src/parse.*` | The file format, every limit, and the text-safety checks |
| `src/cutting.*` | The optimiser: patterns, greedy plan, LP prices, branch and bound, panels, joins, fat quarters |
| `src/report.*` | The printed plan and shopping list |
| `src/app.*` | Bounded reading and exit codes; `run()` takes streams so tests can drive it |
| `tests/tests.cpp` | 90 checks, including 150 random lists compared with an exhaustive solver |

## 3. Key ideas

### The model: two-stage guillotine cutting
A rotary cutter makes straight cuts right across. First you cut **strips** from selvage to selvage. Then you **subcut** each strip along its length. The strip's height is set by its tallest piece, and anything shorter is trimmed. So a plan is a list of strips, each with a height and a set of pieces whose lengths add up to at most the usable width. The goal is the least total height. This is the classic **two-stage cutting-stock problem**, and it is NP-hard in general.

### Patterns
For each possible strip height (every piece dimension), Weftwise lists every **maximal pattern**: a set of pieces that fits, where no further piece would fit. It keeps only patterns whose tallest piece really is that height, because otherwise a lower strip would do the same job. Each piece goes the way round that uses the least of the strip's length, if it is allowed to turn.

### A quick plan: greedy
At each step, try every height. Fill a strip greedily (tallest pieces first) and keep the strip that covers the most piece area per inch of fabric. Repeat until everything is cut. This gives a good plan at once, and an **upper bound**.

### A proof: the LP lower bound
Relax the problem to a linear program: use "x_p strips of pattern p", allowing fractions, and minimise Σ height_p · x_p while covering every demand. This is the **Gilmore–Gomory** relaxation. Weftwise solves it with a small **revised simplex method**: 12 rows at most, with B⁻¹ kept explicitly. Its dual prices y (one per kind of piece) mean "no strip is worth more than its height". By **weak duality**, demand · y is then a lower bound on any plan. The prices are clamped and scaled down to be safe, so floating-point error can't make the bound lie.

### Closing the gap: branch and bound
A depth-first search over "what's left to cut". It branches on the hardest remaining piece (the tallest), trying the patterns that contain it, best-covering first. It prunes when the length so far plus the bound (the larger of the LP prices · remaining, area ÷ width, and the tallest piece) can't beat the best plan. It also remembers each remaining set it has seen. If the search finishes, the plan is **proven optimal** for strip cutting. If it hits its node cap, the report gives the gap to the lower bound instead.

### Long pieces
- **Lengthwise** pieces (borders) go side by side into panels along the selvage, longest first (first-fit decreasing).
- **Joined** lengths use diagonal seams, each costing about one strip width. Cut crosswise, that takes `k = ⌈(L − h)/(W − h)⌉` strips: k − 1 full strips plus a last part, which can share a strip with other pieces. If a panel has room beside it, the long strips are cut from there instead, saving whole strips.

### C++ features you met here
- **Integer units:** `using Len = std::int64_t` for eighths of an inch, with exact arithmetic and no floating-point drift.
- **`std::optional`** for parsers that can fail without exceptions; `InputError` exceptions carry line-numbered messages only.
- **`std::string_view`** for zero-copy parsing; `std::filesystem::is_regular_file` with `std::error_code` (no throwing).
- **Classes with private state** (the solver's patterns, memo and best plan); lambdas with `std::function` in the brute-force test.
- **Sanitizers and `-Wconversion -Wsign-conversion`**: every narrowing is explicit.

## 4. Interview questions you might get

**Q: How do you know your "optimal" claim is true?**
A: Two ways. In the code, a plan is only called optimal if the branch-and-bound search finished, or if the plan equals a proven lower bound. In the tests, 150 random small cutting lists are solved by an independent exhaustive search, which tries every strip height and every filling. The test checks that every plan is valid, never beats the true optimum, has a lower bound no higher than the optimum, and is exactly optimal whenever it says "proven".

**Q: Why is the LP bound valid even though you solve it with floating point?**
A: Weak duality only needs *feasible* dual prices: no strip worth more than its height. After the simplex, I clamp negative prices to zero, compute the largest worth-to-height ratio over all patterns, and divide every price by it, with a tiny margin. Whatever rounding happened, the scaled prices are feasible, so demand · prices is a true lower bound. Then I round it up to the next eighth, because plan lengths are whole eighths.

**Q: How do you stop a hostile cutting list from hanging the program?**
A: Everything is bounded: input size, counts, kinds of piece, the number of patterns enumerated, and the search nodes. When a bound is hit, the program doesn't fail. It falls back to the greedy plan, which always exists, and reports the gap to the lower bound. The tests run a deliberately tiny budget to check that path.

## 5. Ideas to extend it

1. **Three-stage cuts:** stack two short pieces in one slot of a tall strip (a 9½" strip holding two 4½" squares, one above the other).
2. **Scraps beside panels:** use the leftover width beside lengthwise borders for small pieces, not just binding.
3. **Fat-quarter bundles:** given a stack of fat quarters, assign pieces to them so each colour comes from the fewest.
