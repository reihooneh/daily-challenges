# Hellbox

**Set the whole job with the type you own: the fewest formes, the kindest substitutions, and what to buy next.**

Language: Go (standard library only) · Field: letterpress printing / network flows · Day: 16 November 2026 (morning)

A letterpress printer sets text from metal or wood type: one small block, a *sort*, for every letter. A case of type holds a fixed number of each letter, and small fonts run out fast. A poster with four Ws needs four W sorts, and a font of wood type may own one.

Printers deal with it in three ways:

- **Substitute.** Two Vs kerned together make a W. A turned n is a u, a turned p is a d, and a turned comma is an apostrophe.
- **Split the job.** Set some pages, print them, and put the type back in the case (*distribute* it). Then set the next pages. Each round on the press is a *forme*.
- **Buy more type.**

Hellbox works out all three. Give it the case you own and the text you want to print, and it reports:
- whether each page can be set;
- the fewest formes the job needs, given how many pages fit on the press at once;
- which substitutions each forme uses (never one it doesn't need);
- the fewest sorts to buy to print the job in fewer formes.

(The *hellbox* is where printers threw broken and worn type.)

## Features

- **Substitutions as a min-cost flow:** letters flow from what the text needs, through the sorts that can print them, to what the case holds. Each substitution has a cost in looks, so a real letter is always preferred. Substitutions that use two sorts for one letter, such as VV for W, are tried in every combination.
- **Ligatures:** fi, fl, ff, ffi and ffl sorts are used wherever the text allows, which saves an f and an i (and so on) each time.
- **Fewest formes, proved:** for up to 14 pages, a branch-and-bound search tries every grouping, starting from a first-fit plan. Larger jobs use first-fit, checked against a lower bound.
- **A shopping list:** buying a sort is costed far above any substitution, so the same flow finds the fewest sorts to buy. The list covers each forme of a plan that uses the fewest formes the press allows. Type is reused between formes, so you only buy each sort's largest shortfall.
- **Nearly out:** after each forme, it lists the sorts with less than a quarter left.
- **Your own tricks:** add substitutions in a file, such as `€ = C 5`.

## Example

```text
$ ./build/hellbox -forme 2 examples/wood-gothic.txt examples/gig-posters.txt
Hellbox: 4 pages, 125 letters, set from 6-line Gothic wood type (107 sorts)
The press takes 2 pages at a time.

Set it in 4 formes (the fewest possible; 6 settings tried):

1. Friday poster (39 letters)
   W ×1 set as two Vs kerned together
   Nearly out: 0 0/1, H 0/4, L 0/4, W 0/1, A 1/5

2. Saturday poster (29 letters)
   W ×2 set as two Vs kerned together
   Nearly out: 1 0/1, V 0/6, W 0/1, O 1/5

3. Sunday poster (28 letters)
   Every letter is its own sort.
   Nearly out: 2 0/2, N 0/4, S 0/5, Y 0/2

4. Workshop poster (29 letters)
   W ×1 set as two Vs kerned together
   Nearly out: $ 0/1, K 0/1, O 0/5, P 0/3, R 0/4, W 0/1

To set it in 2 formes instead, buy:
  2      ×1
  A      ×1
  L      ×2
  N      ×2
  O      ×2
  R      ×2
  S      ×2
  W      ×3
  Y      ×1
```

Each poster needs almost the whole font, so no two fit together. "WILLOW WEAVERS" has three Ws and the font has one, so two are set as VV, which uses all six Vs.

The second example sets a wedding stationery suite in a small 12 pt Caslon font: `./build/hellbox examples/caslon-12.txt examples/wedding.txt`. It uses fi, fl and ff ligatures, sets a u as a turned n on the invitation, and needs four formes. To get it down to two, the biggest item on the shopping list is six more l sorts.

## Files

- **A case:** one `<glyph> <count>` per line, plus an optional `name ...` line. Comments start with `//`, so `#` can be a glyph.
- **A job:** plain text, with pages separated by lines of `---`. A page may start with `title: ...`. Spaces and line breaks are spacing material, not sorts.
- **Substitutions (optional, `-subs`):** `<glyph> = <sort> [<sort>...] <cost>`, for example `W = V V 3`. `-no-subs` turns the built-in ones off.

## Build, run and test

```bash
make build                                   # build/hellbox
./build/hellbox -forme 4 examples/caslon-12.txt examples/wedding.txt
make test                                    # unit tests with the race detector
make fuzz                                    # 30 s of fuzzing the parsers
make lint                                    # gofmt and go vet
```

The tests include:
- the flow against brute-force enumeration on 300 random cases;
- the planner against every partition of 40 random small jobs;
- the lower bound never exceeding the answer;
- the shopping list making the job fit;
- every sort accounted for;
- hostile files;
- the biggest allowed job staying bounded.

## Security

Hellbox reads three local text files and prints a report. No software is perfectly secure; this is how the risks are handled.

- **Only plain files:** symbolic links, folders and devices are refused. Files are read through a size cap of 256 KB.
- **Strict parsing:**
  - the text must be valid UTF-8, with no NUL bytes or control characters (which also rules out bidirectional-override tricks);
  - lines are at most 4 KB;
  - counts are whole numbers from 0 to 100,000;
  - glyphs are 1 to 3 printable characters;
  - at most 400 sorts, 200 pages and 200 substitutions.
- **No echo:** error messages give the file and line but never repeat the input. Names are filtered to plain characters, and anything unusual in a glyph is shown as `U+XXXX`.
- **Bounded work:**
  - the exact search runs only up to 14 pages, with results cached by page set;
  - multi-sort substitution combinations are capped at 4,000 per forme;
  - the flow is polynomial;
  - a test runs a 40-page job.
- **Checked:** `go vet`, `gofmt`, the race detector and fuzzing of the parsers.

## Limits

- Spacing material (quads, leads) and line-length fitting aren't modelled: Hellbox counts sorts, not the measure.
- A forme holds a fixed number of pages, whatever their size.
- The shopping list groups consecutive pages, which may not be the cheapest grouping.
- How good a turned sort looks depends on the face. The costs are a typical ranking, and you can change them with your own substitutions file.

More detail: [HOW-IT-WORKS.md](HOW-IT-WORKS.md).
