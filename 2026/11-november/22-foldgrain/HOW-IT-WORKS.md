# How Foldgrain works

## Architecture

```
src/foldgrain.h   the data: a book, the sheets on offer, fold schemes, and a costed option
src/foldgrain.c   parsing the book file, and working out every option
src/main.c        reading the file safely, the table, signatures and the cutting diagram
tests/            the example, a brute-force check of the grain rule, padding, hostile input
```

## Key concepts

**Folding schemes.** A folio is a sheet folded once (4 pages), a quarto twice (8), an octavo three
times (16), a sextodecimo four times (32). Unfolded, the flat sheet holds `cols x rows` pages on each
side: 2x1, 2x2, 4x2 and 4x4. Its width runs across the spine and its height along it.

**The grain rule.** The last fold is the spine, and it runs along the flat sheet's height. So the
flat's height must lie along the parent sheet's grain. That fixes the orientation: the number of
flats per parent sheet is `floor(along_grain / flat_h) x floor(across_grain / flat_w)`, with no
rotating to squeeze in one more. The test compares this with a brute force that tries both
orientations and keeps only grain-correct ones, over a grid of sheet sizes.

**Paper weight.** Folding stiff paper many times leaves a fat, springy fold, so heavier paper rules
out the bigger schemes (octavo over 110 gsm, sextodecimo over 80) and fewer folded sheets nest in one
signature (8 at 80 gsm down to 1 above 200).

**Costing.** Folded sheets per copy are the pages divided by pages per folded sheet, rounded up (the
rest are blanks). Parent sheets are the folded sheets for every copy divided by flats per sheet,
rounded up. Options are sorted by cost, then blanks, then fewer signatures to sew.

## Language features worth noticing

- A table of `const` structs (`FG_SCHEMES_LIST`) drives the planner, so a new fold is one line.
- `strtod` with `errno`, `isfinite` and an end pointer is the safe way to read numbers in C;
  Foldgrain also refuses anything not starting with a digit, so `nan` and `inf` never get that far.
- `qsort` with a comparator that breaks ties deterministically keeps the output stable.

## Interview questions

**Why not let the planner rotate flats to fit more?** It would sometimes fit more pages, and every
rotated flat would make a book that warps and won't open flat. The grain rule is a hard constraint,
so it's built into how flats are counted rather than checked afterwards.

**How do you test a geometric rule like this?** Against an independent brute force: enumerate both
orientations, keep the grain-correct one, count. The test sweeps a grid of sheet sizes and both grain
directions and checks every scheme is listed exactly when it fits.

**What would you change to plan a print run of thousands?** Guillotine layouts that mix flats for
different signatures on one sheet, and the press sheet's gripper margin. The core idea, counting only
grain-correct placements, stays the same.

## Extensions

1. Mixed layouts: different signatures, or covers and endpapers, ganged on one parent sheet.
2. Print the imposition (which page goes where on each side of the flat sheet).
3. Price the offcuts as reusable stock for the next book.
