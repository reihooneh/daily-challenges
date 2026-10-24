# Weftwise

**Plans every rotary cut for a quilt and tells you exactly how much of each fabric to buy, mixing piece sizes in shared strips so less fabric goes to waste, and proving when the plan can't be beaten.**

Language: C++20 (standard library only) · Field: quilting / cutting-stock optimisation · Day: 25 October 2026

Quilt patterns usually say "cut five 2½" strips, subcut into squares" for each kind of piece, one after another. That is easy to follow but wastes the end of almost every strip, and the yardage on the pattern is rounded up generously to cover it. Weftwise reads your whole cutting list for one fabric and works out:

- **Shared strips:** which pieces can share a strip, so a strip's leftover end holds pieces that would otherwise need a strip of their own. A shorter piece can go in a taller strip and be trimmed.
- **Turning:** pieces may turn to lie the other way, unless the fabric is **directional** (the print has an up).
- **Long pieces:** borders over the fabric's width are cut **lengthwise** along the selvage. A **joined** length such as binding is pieced from strips with diagonal seams, and is taken from the fabric beside the borders when it fits there.
- **What to buy:** in eighths of a yard and in 10 cm steps, allowing for trimmed selvages, pre-wash **shrinkage** and squaring up the cut end. It also tells you when the cuts fit in a single **fat quarter**.
- **How good the plan is:** either *the least possible* for strip cutting, or *within X" of it*, with a real lower bound behind the claim.

## Quick start

```bash
make                                   # builds build/weftwise
./build/weftwise examples/garden-path.txt
make test                              # 90 checks, built with AddressSanitizer + UBSan
make lint                              # clang-tidy: bugprone, cert, clang-analyzer, performance
```

```
LEAFY PRINT
  42" wide, 41" to cut from after selvages; directional print, so pieces keep their up.
  Buy 1⅛ yd (or 1.0 m): the cuts use 38½", plus ½" to straighten the end.
  38½" of strips: the least possible when cutting in strips.
  Cutting each kind of piece in strips of its own would take 41": this plan saves 2½".

  Cut 7 strips 4½" x the width of the fabric; from each:
      16 x Block side, 2½" x 4½"
      (1" left at the end)
  Cut 1 strip 4½" x the width of the fabric; from it:
      8 x Block side, 2½" x 4½"
      4 x Cornerstone, 2½" x 2½", then trim off the extra height
      (11" left at the end)
  ...
NAVY BORDER
  42" wide, 41" to cut from after selvages; pieces may turn.
  Buy 1⅞ yd (or 1.7 m): the cuts use 64½", plus ½" to straighten the end.
  First, cut a panel 64½" long along the selvage, then from it:
      2 x Border, 4½" wide x 64½" long
      2 x Border top, 4½" wide x 60½" long
      Binding: 5 strips 2½" wide x 64½" long, joined end to end
...
SHOPPING LIST
  Cream background: 2⅛ yd (or 1.9 m)
  Leafy print: 1⅛ yd (or 1.0 m)
  Navy border: 1⅞ yd (or 1.7 m)
```

Cutting the binding from beside the borders saves the eight crosswise strips (20") that it would otherwise take.

## The cutting list

```
quilt Garden Path
straighten 0.5            # optional: extra bought per fabric to square up the end (default ½")

fabric Cream background
width 44                  # selvage to selvage (default 42)
selvage 0.5               # trimmed off each edge (default ½)
shrink 3%                 # optional pre-wash shrinkage, up to 10%
directional               # optional: the print has an up, so pieces never turn
piece Block centre 4.5 x 4.5 count 30
piece Sashing 2.5 x 9.5 count 49
piece Border 4.5 x 64.5 count 2 lengthwise
piece Binding 2.5 x 274 join
```

Sizes are **across x along** the fabric (along = parallel to the selvage, which is "up" on a directional print). They include seam allowances, in inches, written as `6.5`, `6-1/2` or `1/4`, exact to ⅛". Exit codes: `0` plan printed, `2` bad usage or input. `-` reads standard input.

## Security

Weftwise reads one text file and writes text, so the risks are hostile input and runaway work:

- **Bounded reading:** at most 64 KB from a file or standard input; an endless stream is cut off and reported. Only regular files are opened (folders and devices are refused); symbolic links are followed, but every limit still applies.
- **Strict parsing:** every line has a fixed form. Numbers are plain digits with at most four before the point, so they can't overflow, and each has a range (pieces ½" to 600", widths 10" to 120", counts 1 to 400, at most 12 fabrics and 12 kinds of piece each, 2000 pieces per fabric). Names allow letters, digits, spaces and `- ' & ( ) . ,` only.
- **Clean text:** input must be valid UTF-8 (overlong forms and surrogates are refused). Control characters (terminal escapes), invisible zero-width characters and direction marks are refused, so a file can't print differently from how it reads.
- **No echo:** error messages give a line number and never repeat the input or the file name.
- **Bounded work:** the pattern enumeration and the branch-and-bound search have hard caps. When a cap is hit, Weftwise still prints a complete plan and says honestly how far from the best it might be.
- **Exact arithmetic:** all lengths are whole eighths of an inch in 64-bit integers, so sums never drift. The linear-programming bound is the only floating-point step, and it is scaled down to stay valid even if rounding pushes it the wrong way.
- **Checked builds:** the build uses `-Wall -Wextra -Wconversion -Wsign-conversion -Wshadow -Werror`, the tests run under AddressSanitizer and UndefinedBehaviorSanitizer, and `make lint` (clang-tidy) runs clean. There are no dependencies beyond the standard library.

**Known limits:** this is a planning aid, not a guarantee. It models two-stage strip cutting only: it doesn't stack two short pieces in one tall strip slot, and it doesn't use the scrap beside a lengthwise panel for small pieces. Real fabric is often narrower than the label says, so measure yours.

See [HOW-IT-WORKS.md](HOW-IT-WORKS.md) for the walkthrough.
