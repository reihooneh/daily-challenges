# Tallyhook

**Checks a crochet pattern's stitch counts round by round, before you find the mistake ten rounds in.**

Language: Perl 5 (core modules only) · Field: crochet / pattern verification · Day: 17 November 2026 (morning)

Crochet patterns give a stitch count at the end of each round: "(18)". When a designer's typo or a misread repeat puts that number wrong, you usually find out rounds later, with the wrong count on your hook and no idea where it went astray. Tallyhook reads the pattern as written, in the usual US abbreviations. It works each round into the one before and checks:

- **the count at the end** matches the number the pattern gives;
- **every stitch of the round below is used**, no more and no fewer ("runs out of stitches: needs 1 more", "leaves 2 of the 6 stitches unworked");
- **repeats fit:** a "rep from * around" or "(sc, inc) around" must divide the round exactly, or it reports what's left over;
- **the shape:** whether each round lies flat, cups, ruffles, has straight sides or closes up, compared with how a flat circle grows;
- **stacked increases:** increases landing on top of the last round's, round after round, make a hexagon instead of a ball (a classic amigurumi problem);
- **a silhouette** of the piece drawn from the counts, so a ball pattern looks like a ball.

After a mistake it carries on from the count the pattern meant, so one typo doesn't flag every round after it.

## Example

```text
$ ./bin/tallyhook examples/coaster-typo.txt
Tallyhook: coaster-typo.txt

  round           stitches      shape                  silhouette
  Rnd 1            -> 8      ok  start                                  #######
  Rnd 2          8 -> 16     ok  flat                                #############
  Rnd 3         16 -> 24     ok  flat                             ####################
  Rnd 4         24 -> 32     !!  flat                         ###########################
  Rnd 5         30 -> 36     !!  grows slowly: cups          ##############################
  Rnd 6         40 -> 48     !!  flat                   ########################################

  ok = matches the count the pattern gives; .. = no count given; !! = a problem

3 problems:
  Rnd 4 (line 5): says (30) but makes 32
  Rnd 5 (line 6): says (40) but makes 36
  Rnd 6 (line 7): says (54) but makes 48
```

Round 4 says "sc in next 2 sts, 2 sc in next st" over 24 stitches, which makes 32, not 30. The designer probably meant "sc in next 3 sts". Rounds 5 and 6 are then checked against the counts the pattern meant (30 and 40), and each turns out to be wrong too.

[`examples/ball.txt`](examples/ball.txt) is a classic amigurumi ball: every round checks out, and its silhouette widens, runs straight and closes. It notes that the increases stack from round 3 to round 6, which is why balls made from that kind of pattern come out slightly hexagonal. [`examples/dishcloth.txt`](examples/dishcloth.txt) is worked in rows from a foundation chain.

## What it reads

Lines starting `Rnd`, `Round` or `Row` (also ranges like `Rnds 7-12`). Everything else (notes, "Stuff firmly.") is ignored. It understands:
- **Starts:** magic rings and foundation chains ("sc in 2nd ch from hook and in each ch across").
- **Stitches:** sc, hdc, dc, tr, sl st, with blo/flo.
- **Counts and placements:** "sc in next 3 sts", "3 sc", "sc 3", "sc in each st around".
- **Increases and decreases:** inc, "2 sc in next st", dec, invdec, sc2tog, sc3tog.
- **Skips:** "sk 1".
- **Repeats:**
  - `*...; rep from * around` and `rep from * 5 more times` (6 in all);
  - `*...* around`;
  - `(...) x 6`, `[...] 6 times` and `(...) around`.
- **Ignored:** joins, turns and turning chains, which make no stitches.

## Run and test

```bash
./bin/tallyhook examples/ball.txt
./bin/tallyhook - < my-pattern.txt     # from standard input
prove -l t                              # 8 groups, 265 checks
```

Exit codes: 0 every round works out, 3 a round has a problem, 1 the pattern couldn't be read, 2 usage.

The tests include:
- 22 ways patterns write the same instruction;
- the example ball, row-by-row work and short rows;
- seven kinds of mistake, each with its message;
- staggered increases not being flagged;
- 200 randomly generated patterns whose counts are worked out independently;
- hostile input;
- the real script in taint mode.

## Security

Tallyhook reads one local text file and prints a report. No software is perfectly secure; this is how the risks are handled.

- **Taint mode:** the script runs under `perl -T`, its library path is checked, and there's no `eval` of strings, no shell and no file writing.
- **Only plain files:** links, folders and devices are refused. Files are read raw and capped at 64 KB, then decoded as UTF-8, and invalid UTF-8 is refused.
- **Bounded input:**
  - at most 500 rounds;
  - stitch counts up to 10,000 and repeats up to 1,000;
  - brackets at most 4 deep;
  - NUL bytes are refused.
- **Bounded work:**
  - at most 200,000 stitches worked in a round and 1,000,000 in the whole pattern, so a pattern that doubles every round stops instead of running away;
  - "around" repeats undo a failed try without copying;
  - the stacking check skips rounds with more than 500 increases.
- **Safe messages:** anything quoted back from the pattern (an instruction it can't read) has control characters replaced and is cut to 50 characters, so a file can't send escape codes to your terminal.

## Limits

- US terms only. UK patterns use the same words for different stitches ("dc" means US sc), and Tallyhook can't tell which one a pattern uses.
- Chain spaces and turning chains are not counted as stitches (the usual US convention). Patterns that say "ch 3 counts as a dc" will read one short.
- Stitches worked into chain spaces or other rounds ("in the ch-2 space", "in the round below") aren't supported.

More detail: [HOW-IT-WORKS.md](HOW-IT-WORKS.md).
