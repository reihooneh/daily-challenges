# How Tallyhook works

## 1. Architecture

```
pattern.txt ─(App: plain file, 64 KB, UTF-8)─▶ Parse::parse_pattern
     │   lines "Rnd N:" → split at top-level commas → atoms and groups (a small tree)
     ▼
Count::tally ── for each round (ranges expanded):
     │   work_round: apply the tree to { avail, pos, made, incs, decs }
     │     st:   take k of the round below, make m
     │     each: as many as are left
     │     group × n, or "around": repeat until the round is used up (undo a repeat that doesn't fit)
     │   checks: ran out? left some unworked? count as stated?
     │   shape: compared with a flat circle
     └── stacking: increases on top of the previous round's, three rounds or more
     ▼
Report::report ── table, silhouette, problems, notes
```

## 2. File tour

- **`lib/Tallyhook/Parse.pm`:**
  - reading round headers and stated counts;
  - `split_top` (commas outside brackets);
  - `parse_seq` (stars and brackets into groups);
  - `times_of` (x 6, 6 times, 5 more times, around);
  - `atom` (each kind of instruction);
  - `clean` (safe quoting).
- **`lib/Tallyhook/Count.pm`:** `tally`, `work_round`, `apply`, `around`, `one`, `work`, `shape`, `stacking`.
- **`lib/Tallyhook/Report.pm`:** the table and silhouette.
- **`lib/Tallyhook/App.pm`:** file reading, errors, exit codes. `run` takes its handles as arguments, so tests can call it.
- **`bin/tallyhook`:** a taint-mode wrapper.
- **`t/tallyhook.t`:** eight groups of tests.

## 3. Key concepts and language features

**A round consumes and produces.** Every crochet stitch is worked into some stitches of the round below and leaves some stitches for the round above:

| stitch | works into | makes |
|---|---|---|
| sc | 1 | 1 |
| inc (2 sc in next st) | 1 | 2 |
| dec (sc2tog) | 2 | 1 |
| sk 1 | 1 | 0 |

A round is correct when it consumes exactly the previous round's count, and makes what it says. That is a resource count, like checking a function uses every argument exactly once.

**Repeats are a tiny tree.** "(sc in next 2 sts, inc) x 6" becomes a group node holding two atoms with times = 6. A `*` opens a group that "rep from *" closes, so the parser keeps the index where the star appeared and splices everything after it into a group. Brackets are parsed recursively, with a depth limit.

**"Around" means "until the round runs out".** Its count isn't written down, so Tallyhook repeats the group until the round below is used up. Before each repeat it notes its position. If the repeat would run past the end, it rolls back and reports how many stitches were left over: "after 3 repeats, 1 stitch is left over". The rollback restores a few numbers and truncates the increase lists, without copying them, so even a huge round stays quick.

**Shape from counts alone.** A flat circle of single crochet grows by its starting count every round (6, 12, 18, …), because its circumference grows by 2π × one stitch height. Grow faster and the extra fabric has nowhere to go but out of plane, so it ruffles. Grow slower and it cups into a bowl. Equal counts make a tube; falling counts close it up.

**Stacked increases.** Each increase's position is recorded as a fraction of the way round. If a round's increases sit within a stitch, on average, of the previous round's, and that happens three rounds running, the extra stitches pile up in columns. The circle then grows corners. Rounds that increase in every stitch are skipped, since they have nowhere else to put them.

**Perl features:**
- Recursive regular expressions are avoided in favour of a hand-written bracket splitter, which is easier to bound.
- Exceptions are hash references (`die { line => …, msg => … }`), so errors carry structure and never a stack trace.
- A `local $/` slurp reads the file.
- `use warnings FATAL => 'all'` turns any warning into an error.
- Taint mode (`-T`) refuses to trust anything from outside until it's been checked. The library path is untainted with a strict regex.

## 4. Interview questions

**Q: How do you test a parser for a language as loose as crochet patterns?**
A: In layers:
- a table of 22 different phrasings that should all mean the same count;
- examples with known answers (a ball, a coaster with a deliberate typo, a dishcloth in rows);
- a property test: generate 200 random patterns from random repeats of sc, inc and dec that divide the round, compute each count independently, and check Tallyhook agrees and finds no problems;
- hostile input for the edges: NUL bytes, size limits, unbalanced brackets, absurd counts.

**Q: Why carry on from the stated count after a mistake, rather than from what the round actually made?**
A: The goal is to find every mistake, not just the first. If round 4 makes 32 instead of the stated 30, round 5 was written for 30. Judging it from 32 would report a problem in round 5 that may not exist, and every round after. Starting each round from the count the pattern meant judges each round on its own.

**Q: What's the denial-of-service risk in a text parser like this, and how is it bounded?**
A: The text is small, but the work it describes isn't: "Rnds 2-40: inc around" doubles every round, to about 3 trillion stitches. Tallyhook bounds:
- the input: size, rounds, counts, repeat counts and bracket depth;
- the work: 200,000 stitches per round, 1,000,000 per pattern, and it stops tallying after the limit;
- the algorithms: the "around" rollback doesn't copy lists, and the stacking check skips implausibly large rounds.

A test feeds the doubling pattern and checks it stops quickly.

## 5. Extension ideas

- **UK terms:** a switch (or a guess from the stitch mix) that maps UK dc/htr/tr to US sc/hdc/dc.
- **Chain spaces:** count ch-spaces as places to work into, for granny squares and lace.
- **Suggest the fix:** for a round that's off by a little, search nearby rewrites (one more sc per repeat, one fewer repeat) for the one that gives the stated count.
