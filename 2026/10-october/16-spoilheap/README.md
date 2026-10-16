# Spoilheap

**Checks an excavation's layer record before it's too late to go back: finds loops in the sequence, dating clues that can't all be true, and the fewest entries to re-check to fix them.**

Language: PHP 8 (no dependencies) · Field: archaeology / graph algorithms · Day: 16 October 2026

On a dig, every layer (a *context*) gets a number, and the diggers write down which layers lie over which: "1001 above 1002", "1005 cuts 1003". These relations make a Harris matrix, the family tree of the site. Finds give dates: a clay pipe made from 1840 means its layer formed in 1840 or later.

With two notebooks and two weeks of digging, mistakes creep in. One wrong "above" creates a loop where a layer is both over and under another. One intrusive find (something that slipped down a root hole) makes the dates impossible. Drawing tools show you the matrix; Spoilheap **tells you exactly which entries to re-check, and the fewest of them**, while the trench is still open.

## What it does

- **Loops in the sequence:** finds every tangle of contradictory relations and the smallest set of relations whose removal fixes it. When several fixes are equally small, it picks the one the dating evidence agrees with.
- **Impossible dates:** carries "no earlier than" dates (finds) up the sequence and "no later than" dates down it, finds every pair that can't both be true, and the fewest clues to question so all the rest agree. It explains each one in archaeologists' terms (an *intrusive* find, or a disturbed deposit).
- **Phases and date windows** for every layer, latest at the top, with the clues that set each date.
- **Tidy-ups:** relations already implied by others (a Harris matrix leaves them out), layers not linked to anything, and "same" numbers merged into one deposit.
- **Graphviz output** (`--dot`) to draw the cleaned matrix, with the relations to re-check in red.

## Quick start

```bash
php bin/spoilheap examples/hollow-lane.txt
php bin/spoilheap examples/tangled.txt
php bin/spoilheap examples/tangled.txt --dot | dot -Tsvg > matrix.svg   # needs Graphviz
php tests/run.php                                                    # 61 checks
```

```
SPOILHEAP  tangled.txt  (Hollow Lane, trench 2 (both notebooks): 10 contexts, 11 relations, 7 dating clues)

SEQUENCE PROBLEMS
  x 1006, 1007=1010, 1008 and 1009 form a loop: each is recorded as both above and below another.
    Fewest relations to re-check (1):
      line 24   1009 above 1006

DATING PROBLEMS
  x the machine-made nail in 1007 says 1860 or later, the coin of George III date for 1007 says 1790 or earlier, in the same deposit.
  Fewest clues to question (1), then everything else agrees:
    line 25   the machine-made nail in 1007: the find may be intrusive (a later object that worked its way down) or misdated

PHASES (latest at the top)
  Phase 9  1001       after 1840           (clay pipe bowl with a maker's mark)
  Phase 8  1002       1840 to 1880         (clay pipe bowl with a maker's mark; rubble from the 1880 rebuild)
  ...
  Phase 3  1007=1010  1750 to 1790         (coin of George III)
  Phase 2  1008       1690 to 1790         (tin-glazed tile; coin of George III)
  Phase 1  1009       before 1790          (coin of George III)
```

Any of the four relations in that loop would break it. Dropping `1006 above 1007` would put the 1810 bottle seal underneath the 1790 coin, so Spoilheap rules it out. Of the fixes that agree with the dates, it questions the one written last, `1009 above 1006` from the second notebook.

## The record format

```
site Hollow Lane, trench 2
1001 above 1002          # also: over, cuts, fills, seals (left is later)
1003 below 1002          # also: under (left is earlier)
1007 same 1010           # two numbers for one deposit
find 1004 1840 clay pipe bowl        # made no earlier than 1840
before 1002 1880 rubble from the 1880 rebuild   # formed no later than 1880
date 1007 1750 1790 coin of George III          # formed in this range
```

Years are whole numbers; BCE years are negative (`-50` is 50 BCE). Exit codes: `0` consistent, `1` problems found, `2` bad input.

## Security

- **Bounded input:** at most 64 KB, 200 characters a line, 500 contexts, 2,000 relations and 300 clues; years between -10000 and 2100. Only regular files are opened (so `/dev/zero` is refused), and reading stops at the limit.
- **Strict text:** the file must be valid UTF-8. Context names are 1-16 safe characters and notes are letters, digits and simple punctuation, so nothing printed (or written into the DOT file) can carry markup or terminal escape codes. Control characters and hidden bidirectional characters are refused. Errors give a line number and never repeat the input, and the file name is cleaned before printing.
- **Bounded work:** the exact search for loop fixes tries at most 200,000 combinations, then falls back to a method that always works. Deep sequences use loops, not recursion, so they can't overflow the stack.
- **No code from data:** no `eval`, no shell, no `include` of anything built from input (the autoloader has a fixed list of six files), and no dependencies at all.

**Known limits:** Spoilheap checks what's recorded; it can't see the soil. A suggested fix is a list of entries to re-check, not proof of which one is wrong. Date windows are only as good as the finds' date ranges, and a "find" date is a lower bound only (old, *residual* finds in later layers are normal and never flagged).

## Ideas
See [HOW-IT-WORKS.md](HOW-IT-WORKS.md) for how it works and what to build next.
