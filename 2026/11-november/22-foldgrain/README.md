# Foldgrain

**Plans the paper for a handbound book: which sheets to buy, how to cut them and how to fold them, with the grain along every spine.**

Paper has a grain, like wood. Fold across it and the fold cracks; bind a book with the grain running
across the spine and the pages cockle and the book won't lie open. So a bookbinder can't just fit as
many pages on a sheet as possible: every flat sheet has to be cut so that, once folded into a folio,
quarto or octavo, the grain runs parallel to the spine fold. Foldgrain takes the page size, page
count, paper weight and the sheets you can buy, and works out every grain-correct way to make the
book, cheapest first.

## Features

- Folio, quarto, octavo and sextodecimo folds, with the flat sheet's size (plus a trim margin) and
  how many fit on a parent sheet with the grain the right way.
- Paper weight limits: heavy paper won't fold three or four times cleanly, and fewer heavy sheets
  nest in a signature.
- Signatures spread evenly, blank pages counted, parent sheets to buy, cost and offcut waste.
- An ASCII cutting diagram with the grain marked.

## Example

```
$ ./foldgrain examples/journal.txt
192 pages of 140 x 210 mm, 3 copies, on 100 gsm paper.

  paper                  fold          flats  sheets    sigs  blanks     cost  waste
  Fabriano 50x70         octavo            1      36       2       0    86.40    31%
  Fabriano 50x70         quarto            2      36       4       0    86.40    30%
  Fabriano 50x70         folio             4      36       8       0    86.40    29%
  A3 offcuts             folio             1     144       8       0   100.80    50%
  A2 cartridge           quarto            1      72       4       0   136.80    51%
  A2 cartridge           folio             2      72       8       0   136.80    50%

Cheapest: 36 sheets of Fabriano 50x70, cut into 1 flat each (566 x 426 mm), folded as octavo.
  Sew 2 signatures: 6 folded sheets each.

  Fabriano 50x70, grain running down (700 x 500 mm), 1 flat sheet per parent:

  +----------------------------------+........
  | '   '   '   '   '   '   '   '   '|........
  | '   '   '   '   '   '   '   '   '|........
  | '   '   '   '   '   '   '   '   '|........
  | '   '   '   '   '   '   '   '   '|........
  | '   '   '   '   '   '   '   '   '|........
  | '   '   '   '   '   '   '   '   '|........
  | '   '   '   '   '   '   '   '   '|........
  | '   '   '   '   '   '   '   '   '|........
  | '   '   '   '   '   '   '   '   '|........
  | '   '   '   '   '   '   '   '   '|........
  | '   '   '   '   '   '   '   '   '|........
  | '   '   '   '   '   '   '   '   '|........
  +----------------------------------+........
  ............................................
  ............................................

  ' marks the grain, parallel to every spine fold; dots are offcuts.
```

A book file lists `trim W H`, `pages N`, `copies N`, `gsm N`, `margin MM` and one
`sheet NAME W H long|short PRICE` line per paper you can buy (`long` means the grain runs along the
sheet's long side). Quote names with spaces.

## Build and test

```sh
make            # ./foldgrain examples/journal.txt
make test       # built with AddressSanitizer and UBSan
make lint       # clang-tidy (bugprone, cert, clang-analyzer), warnings as errors
```

C11, the standard library and libm, compiled with `-Wall -Wextra -Wpedantic -Wconversion -Werror`.

## Security

- The book must be a regular file under 64 KB; lines are capped at 511 characters, NUL bytes and
  control characters are refused, and every value goes through `strtod` with range checks that
  also reject `nan`, `inf` and signs.
- At most 16 sheet sizes; all buffers are fixed-size and written with bounded `snprintf`.
- Tests run under AddressSanitizer and UndefinedBehaviorSanitizer and include hostile files
  (overlong lines, escape sequences, NUL bytes, huge numbers, stray text).
- Known limits: the fold limits by paper weight are rules of thumb; test-fold your paper.
