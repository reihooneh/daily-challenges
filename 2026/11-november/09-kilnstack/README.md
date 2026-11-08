# Kilnstack

**Plans how to load a pottery kiln, shelf by shelf: which shelf every piece goes on and where, which posts hold each shelf up, and how many firings it takes.** It also draws a map of every shelf seen from above.

Language: C11 (standard library only) · Field: ceramics / 3D packing · Day: 9 November 2026

Loading a kiln is a puzzle potters solve by hand every week:
- shelves sit on stacks of posts, and you only own a few post sizes;
- glazed pieces must not touch, or they fuse together;
- everything must stay clear of the elements and fit under the lid.

A shelf that's 2 cm taller than it needs to be can cost a whole shelf further up, and a wasted shelf can mean an extra firing. Online kiln calculators estimate shelf usage or firing cost; Kilnstack makes the actual plan.

- **Shelf heights from your posts:** each shelf sits on the shortest stack of up to three posts from the sizes you list that clears its tallest piece plus headroom (`2.5 + 10 + 15 = 27.5 cm`).
- **Tallest first, then fill:** a new shelf takes the tallest piece still waiting, then every shorter piece that fits. When the next shelf wouldn't fit under the lid, that firing is full.
- **Real placement on round shelves:**
  - pieces are circles on half shelves (or full ones), kept clear of the wall, the posts and the gap between the halves;
  - glazed pieces keep a gap between them, and bisque pieces may touch;
  - two placement strategies (outer ring first, and rows from the straight edge) are both tried, and the better plan is kept.
- **Honest numbers:** it shows a lower bound from floor area alone, and how much of the shelf space the pieces really cover.
- **Clear errors:** a piece too wide for your shelves or too tall for the kiln is named, rather than quietly left out.

## Quick start

```bash
make && ./kilnstack examples/studio-glaze.txt
./kilnstack - < examples/studio-glaze.txt
make test       # 279 checks + 9 command checks, with AddressSanitizer and UBSan
make analyze    # GCC's static analyser
```

```
KILNSTACK  glaze firing, 46 cm kiln 66 cm tall, half shelves: 33 pieces in 2 firings on 6 shelves
  By floor area alone they need at least 4 shelves.
  Pieces cover 51% of the shelf space used; glazed pieces kept apart so they can't fuse.

Firing 1: 4 shelves, loaded to 65.9 of 66.0 cm
  Shelf 1 at 4.1 cm, tallest piece 24.0 cm; posts above: 2.5 + 10 + 15 = 27.5 cm
    A Tall vase 14x24   B Tall vase 14x24   C Mug 9x11   D Mug 9x11
    E Mug 9x11   F Mug 9x11   G Mug 9x11   H Mug 9x11
    I Tea bowl 7x7   J Tea bowl 7x7
                    .....ooo.....
                .........ooo.........
             ........IIIIII..GGGGG......
           ..........IIIIII.GGGGGGGG......
          ...AAAAAAA..IIII..GGGGGGGG.......
        ...AAAAAAAAAAA.......GGGGGG..........
        ...AAAAAAAAAAAA...CCCC.....EEEE......
       ooo.AAAAAAAAAAAA.CCCCCCCC.EEEEEEEE..ooo
      .ooo.AAAAAAAAAAA..CCCCCCCC.EEEEEEEE..ooo.
      .......AAAAAAAA....CCCCCC...EEEEEE.......

      .......BBBBBBBB....DDDDDD...FFFFFF.......
      ...
  Shelf 2 at 33.2 cm, tallest piece 11.0 cm; posts above: 2.5 + 10 = 12.5 cm
  Shelf 3 at 47.3 cm, tallest piece 9.0 cm; posts above: 2.5 + 10 = 12.5 cm
  Shelf 4 at 61.4 cm, tallest piece 3.0 cm; top shelf
Firing 2: 2 shelves, loaded to 26.7 of 66.0 cm
```

## The kiln file

```
kiln 46 66            # inside diameter and height, cm
shelves half          # or full
firing glaze          # or bisque (pieces may touch)
shelf 1.6             # shelf thickness
wall 2.5              # clearance from the wall and elements
gap 1.0               # between glazed pieces
headroom 1.5          # above the tallest piece on a shelf
floor 2.5             # posts under the bottom shelf
posts 2.5 5 7.5 10 15 # post heights you own
piece 9 11 12 Mug     # diameter, height, [count], [name]
```

Exit code: 0 for a plan, 2 for a bad file or a piece that can't be loaded.

## Security

The kiln file is untrusted input, and C makes care essential:

- **Bounded reading:** at most 64 KB, read with `read(2)` into a fixed buffer. Lines are capped at 200 characters and copied with explicit lengths. There are at most 300 pieces and 12 post sizes.
- **Strict parsing:**
  - numbers must be plain decimals within a range (no signs, exponents, `nan` or `inf`), checked before `strtod`;
  - only printable ASCII is accepted, so terminal escapes, NUL bytes and non-ASCII are refused;
  - names use a small character set and at most 32 characters.
- **Safe files:** opened with `O_NOFOLLOW`, then `fstat` must show a regular file (not a link, folder or device). Errors give a line number, never the line or the path.
- **No overflow:** all output goes through one bounded `vsnprintf` helper that truncates safely; a test checks it with a 64-byte buffer. There's no `system`, no shell and no dynamic format strings.
- **Checked:**
  - built with `-Wall -Wextra -Wconversion -Werror`, `_FORTIFY_SOURCE` and stack protection;
  - tests run under AddressSanitizer and UndefinedBehaviorSanitizer;
  - `gcc -fanalyzer` is clean;
  - clang-tidy's remaining notes are the Annex K "use `snprintf_s`" advice (not available on glibc) and a `va_list` false positive.
- **Known limits:**
  - the packing is a heuristic, not an optimum (the area bound shows how close it is);
  - pieces are treated as cylinders, so stacking and nesting in a bisque firing aren't modelled, nor are post footprints wider than 3 cm or square shelves;
  - always follow your kiln maker's clearances.

## Files

| File | What it does |
|---|---|
| `src/kilnstack.h` | The kiln, pieces, shelves and plan |
| `src/parse.c` | Strict reading of the kiln file |
| `src/pack.c` | Post stacks, placement on round shelves, shelves and firings |
| `src/report.c` | The plan in words and the shelf maps |
| `src/main.c` | The command and safe reading |
| `tests/test_kilnstack.c` | Parsing, posts, fixed and 120 random kilns checked against every rule |
| `tests/test_cli.sh` | The command, links, folders, size limits, hostile names |
| `examples/studio-glaze.txt` | A studio glaze load |

See [HOW-IT-WORKS.md](HOW-IT-WORKS.md) for the algorithm and interview questions.
