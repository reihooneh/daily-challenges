# How Kilnstack works

## 1. The big picture

```
kiln file ──ks_parse──▶ Kiln (sizes, settings, post sizes, one Piece per piece)
                            │
                        ks_pack ── strategy 0 (outer ring first) ┐
                                └─ strategy 1 (rows from the edge)┴─ keep fewer firings, then shelves
                            │      for each: tallest waiting piece opens a shelf
                            │                 fill it with shorter pieces (first fit)
                            │                 posts = ks_stack(tallest + headroom)
                            │                 next shelf fits under the lid? else new firing
                        ks_report ── words + a 41 × 21 character map per shelf
```

## 2. File tour

- **`kilnstack.h`:** fixed-size structures throughout. The plan is a few parallel arrays indexed by piece (its level, half, x and y), plus an array of levels. There's no allocation apart from one temporary plan.
- **`parse.c`:**
  - splits the text into lines by length, never by trusting a terminator;
  - checks every byte is printable ASCII;
  - tokenises with `strtok_r`;
  - checks numbers with a small hand-written grammar before `strtod`;
  - expands `piece 9 11 12 Mug` into twelve pieces.
- **`pack.c`:**
  - `ks_fits_at` tests one spot against the wall, the split between half shelves, the posts and the other pieces;
  - `place` scans a 0.5 cm grid for the best-scoring spot;
  - `ks_stack` finds the shortest stack of posts;
  - `pack_with` builds shelves and firings;
  - `ks_pack` runs both strategies.
- **`report.c`:** a bounded `put()` helper built on `vsnprintf`, the plan text, and the maps (a character is a piece's letter if its centre is inside that piece's circle).
- **`main.c`:** `open(O_NOFOLLOW)`, `fstat`, then a bounded `read` loop.

## 3. Key ideas

**Shelf packing is two packing problems.**
- **Vertical:** shelves are like the "levels" in a strip-packing algorithm. Sorting by height and opening each shelf with the tallest remaining piece means every shorter piece can join it without making it taller. That's first-fit decreasing height, a classic heuristic for level packing with a known worst-case guarantee in the strip-packing literature.
- **Horizontal:** each shelf is a 2D circle-packing problem in a half disc with holes (the posts). That is NP-hard to do optimally, so Kilnstack uses greedy placement on a grid.

**Two greedy strategies are better than one.** "Nearest the wall" packs rings from the outside in, which suits many small pieces. "Nearest the straight edge, then leftmost" packs rows, which suits a few big pieces on half shelves. Neither wins everywhere. On the example, rows needed 6 shelves where rings needed 8. Running both and keeping the better one costs twice the time (milliseconds) and never does worse.

**Posts are a tiny knapsack.** For a needed height h, it wants the shortest sum of one to three post sizes (repeats allowed) that reaches h, preferring fewer posts on a tie. With at most 12 sizes, trying all 12³ combinations is instant and exact.

**A lower bound keeps it honest.** The pieces' footprints can't overlap, so they need at least ⌈total footprint area ÷ shelf area⌉ shelves. Kilnstack prints that bound and the fill percentage. A random test checks the plan never claims to beat it, which would mean overlapping pieces.

**Testing with a validator, not examples.** `valid()` in the tests re-checks every rule from scratch: inside the wall, on the right half, clear of posts, gaps between pieces, under the lid, and post stacks matching shelf heights. It then runs on 120 random kilns (sizes, shelf types, firing types and piece mixes). Any rule the packer bends shows up as a failure, under AddressSanitizer and UBSan.

**C features used:**
- fixed arrays with explicit bounds, and `size_t` lengths everywhere;
- `strtok_r` (reentrant) and `strspn`;
- variadic functions with `va_list` and a `format(printf)` attribute, so the compiler checks every format string;
- `qsort` with a comparator (and its classic limitation: no context pointer, hence a file-level static);
- struct assignment to copy a plan;
- POSIX `open(O_NOFOLLOW | O_CLOEXEC)`, `fstat` and `read`.

## 4. Interview questions you might get

**Q: Why not just compute the optimal loading?**
A: It contains two NP-hard problems: bin packing over shelves, and packing circles into a region on each shelf. Exact methods would take far too long for a few hundred pieces. So Kilnstack uses well-understood heuristics (first-fit decreasing height, greedy placement with two strategies) and reports a lower bound, so the user can see how much room for improvement there might be. In the example the bound is 4 shelves and the plan uses 6, with pieces covering 51% of the shelf area. Gaps between round pieces make about 70–80% the practical ceiling.

**Q: How do you test code whose correct output you can't write down by hand?**
A: Test the properties instead of the output. A plan is correct if it obeys every physical rule, so the test has its own independent checker for those rules and runs it on fixed cases and on 120 randomly generated kilns. Known-answer tests cover the parts that do have exact answers: post stacks (27 cm needs 2.5 + 10 + 15), a piece too wide for half shelves but fine on a full one, and bisque using no more shelves than glaze.

**Q: What makes this C code safe against a hostile input file?**
A: Several layers:
- **Bounded input:** every input path has a bound (file size, line length, word count, piece count, name length), and lengths are checked before every `memcpy`.
- **Numbers:** they pass a strict grammar before conversion, so `strtod`'s generous parsing (hex floats, `inf`, `nan`) never sees anything odd.
- **Output:** it goes through one bounded helper.
- **Files:** links aren't followed and only regular files are read.
- **Tooling:** sanitizers, the static analyser and `-Werror` with `-Wconversion` catch the rest. A test even feeds a NUL byte mid-line, plus terminal escape codes and a 70 KB file.

## 5. Ideas to extend it

- **Firing compatibility:** give each piece a glaze cone and keep only compatible pieces in one firing; also bias slow-cooling glazes to the bottom shelves.
- **Better 2D packing:** place pieces at positions touching two neighbours (the classic "maximum hole degree" heuristic for circle packing) instead of a grid scan, and try a few random orders.
- **Nesting and stacking in bisque firings:** let small bowls sit inside bigger ones and tiles stand on edge.
