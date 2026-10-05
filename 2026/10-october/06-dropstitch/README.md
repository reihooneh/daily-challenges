# Dropstitch 🧶

**A linter for knitting patterns: finds the row where the stitch count goes wrong before you knit it.**

A knitting pattern is a program. Each row takes the stitches on your needle, runs a list of instructions over them, and leaves a new number of stitches for the next row. If one row is off by a single stitch, you usually find out twenty rows and three evenings later. Dropstitch reads a written pattern, "knits" it with numbers instead of yarn, and points at the exact row and instruction where it stops adding up.

## What makes it different

Row counters and chart drawing apps exist. I couldn't find a tool that *checks* a written pattern the way a compiler checks code.

- **It understands real pattern language**, not a made-up format: `K2, *YO, K2tog; rep from * to last 2 sts, K2. (24 sts)`
- **It explains the mistake in knitting terms:** "the repeat is 3 stitches wide but has 20 to cover: 2 left over".
- **It checks the designer's own claims.** If a row says `(12 sts)` and the instructions make 11, it says so.
- **It notices missing rows** ("follows row 5: is row 6 missing?").
- **Exit code `1` on problems**, so a designer can check every pattern automatically before publishing.

## Example

`examples/lace-scarf.txt` has a mistake in row 5:

```text
Cast on 24 sts

Row 1 (RS): K2, *YO, K2tog; rep from * to last 2 sts, K2. (24 sts)
Row 2: K2, purl to last 2 sts, K2.
Row 3: K2, *K2tog, YO; rep from * to last 2 sts, K2. (24 sts)
Row 4: K2, purl to last 2 sts, K2.
Row 5: K2, *YO, K2tog, K1; rep from * to last 2 sts, K2.
Row 6: Knit.
```

```text
$ dropstitch examples/lace-scarf.txt
Cast on 24
  ok   Row 1: 24 -> 24 sts
  ok   Row 2: 24 -> 24 sts
  ok   Row 3: 24 -> 24 sts
  ok   Row 4: 24 -> 24 sts
  XX   Row 5 (line 8): 24 sts on the needle
         the repeat is 3 stitches wide but has 20 to cover: 2 left over
  ok   Row 6: 24 -> 24 sts

1 problem found in 1 row. Fix the pattern before you knit it.
```

A correct hat crown (`examples/hat-crown.txt`) ends with `All 14 rows add up. Safe to cast on.`

## What it understands

| You write | Meaning |
|---|---|
| `Cast on 24` / `CO 24` | Starting stitches |
| `Row 3:` · `Round 3:` · `Rows 2 and 4:` · `Rows 5-8:` | Row headers, lists and ranges |
| `K3`, `P2`, `Sl1`, `knit 4` | Plain stitches with a count |
| `YO`, `M1`, `M1L`, `M1R`, `Kfb`, `Pfb` | Increases |
| `K2tog`, `SSK`, `P2tog`, `K3tog`, `SK2P`, `CDD` | Decreases |
| `Knit` · `Purl` · `knit to end` · `purl to last 2 sts` | The rest of the row |
| `*K2, P2; rep from * to end` · `... to last 3 sts` | Repeats along the row |
| `(K1, P1) 3 times` · `[K2tog] twice` · `rep from * 3 more times` | Counted repeats, which can be nested |
| `BO 3` · `bind off 3 sts` | Binding off |
| `(24 sts)` at the end of a row | A claimed count, which is checked |
| `# note` | Comment |

Run `dropstitch --stitches` for the full dictionary.

## Tech

TypeScript in strict mode, compiled for Node.js 20+. **No runtime dependencies.** The only packages are the TypeScript compiler and Node's type definitions, both pinned to exact versions with a lockfile.

## Build and run

```bash
cd 2026/10-october/06-dropstitch
npm ci
npm run build
node dist/src/cli.js examples/lace-scarf.txt
```

| Exit code | Meaning |
|---|---|
| `0` | Every row adds up |
| `1` | Problems found |
| `2` | The pattern could not be read |

## Tests

```bash
npm test
```

30 tests:

- **Knitting rules:** every kind of stitch, "to last N", star repeats, counted repeats, nested repeats, and the three example patterns.
- **The mistakes it exists to catch:** running out of stitches, leftovers, repeats that don't fit, wrong claimed counts, missing rows.
- **Hostile input:** script tags, shell fragments, terminal escape codes, look-alike Unicode letters, JavaScript's built-in property names, million-fold nested repeats, oversized files, invalid UTF-8.

The compiler runs with its strictest settings (`strict`, `noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`, no unused code), and `npm audit` reports 0 vulnerabilities.

## Security

Dropstitch parses untrusted text and prints messages about it, so it is built like any parser that faces the outside world.

- **An allow-list tokenizer.** Only letters, digits and a few punctuation marks get through. Any other character stops the row with "unexpected character" and is never printed, so terminal escape codes or markup in a pattern file cannot reach your screen.
- **Messages are built from vetted pieces.** The only user text ever shown is a stitch word that has already passed the tokenizer (letters and digits, 20 characters at most). Lines that aren't rows are reported by line number only.
- **No repeat can hang the program.** Repeats are computed with multiplication and division, never by looping, so `(K1) 999999 times` nested four deep is answered instantly. A repeat that uses no stitches ("*YO* to end") is refused instead of run forever.
- **Everything is bounded:** file size (200 kB, and only that much is read), line length, number size, row count, nesting depth and stitch count.
- **No regex denial of service.** The main parser is hand-written, and the few regular expressions used for row headers have no nested repetition. A test times them on pathological lines.
- **No prototype tricks.** The stitch dictionary is a `Map`, so words like `constructor` are just unknown stitches.
- **Nothing dangerous in reach.** No `eval`, no shell, no network, no file writes. It reads the one file you name.

**Known limits, stated honestly:**

- It checks stitch **counts**, not whether the fabric will look right. A pattern can add up and still be ugly.
- It knows common flat and in-the-round instructions. Cables, short rows, charts, "at the same time" shaping and multi-size patterns like `K4 (6, 8)` are not supported yet; unknown words are reported, never guessed.
- Binding off is counted as one stitch removed per stitch bound off, which is a simplification.
- No software can promise it is 100% secure; these are the protections in place.
