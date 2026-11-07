# Queenline

**Reads a beehive's inspection notes and works out what happened to the queen: when she stopped laying, whether the colony swarmed, when the new queen emerges, mates and lays, and when there's no capped brood to treat for varroa mites.**

Language: Bash 5 (with `date`, `grep`, `iconv`, `head`) · Field: beekeeping / reasoning with time intervals · Day: 7 November 2026 (evening)

A beekeeper opens the hive every week or so and notes what's there: eggs, larvae, capped brood, queen cells, perhaps the queen. The queen herself is hard to spot, but her brood is a clock. Eggs hatch on day 3, larvae are capped on day 9, and workers emerge on day 21. Queen cells are capped on day 8 and the queen emerges on day 16. So every observation pins down when eggs were, or weren't, laid.

Bee calculators project forward from one known date, and hive record apps store the notes. Queenline reasons across the whole log:

- **When the old queen stopped laying:** each brood stage seen gives a range in which an egg was laid, and each stage seen absent gives a range in which none was. Together they bracket her last egg.
- **Swarm or loss:** queen cells started while she was still laying mean swarm cells; a swarm seen settles it. Otherwise she was lost or stopped laying.
- **The new queen:** open cells, capped cells, hatched cells and a virgin seen each bound when the first new queen emerges. If no cells were recorded, it estimates emergency cells (10 to 13 days after the loss). From her emergence come the mating flights and the window for her first eggs.
- **The broodless gap:** from 21 days after the old queen's last egg until the day before the new queen's first brood is capped. With no capped brood the mites have nowhere to hide, so this is the time for an oxalic acid treatment.
- **What to do now:**
  - keep the hive closed during mating flights;
  - when to look for eggs;
  - when to treat (after mating, never during it);
  - a test frame of eggs if she has failed, and what to do about laying workers.
- **A timeline:** one column a day, showing inspections, laying, the broodless gap, emergence, mating and the first eggs due.

## Quick start

```bash
./bin/queenline examples/blue-hive.txt
./bin/queenline examples/blue-hive.txt --today 2026-11-12    # plan from another day
bash tests/run.sh                                            # 48 checks, including 150 simulated colonies
shellcheck -x bin/queenline lib/*.sh tests/run.sh
```

```
QUEENLINE  Blue hive: 6 inspections, Sat 3 Oct to Sat 7 Nov

What happened
  The old queen laid her last eggs Sat 10 Oct to Wed 14 Oct: the colony swarmed and the old queen left with it.
  The first new queen emerged (or will emerge) Sat 17 Oct to Sun 25 Oct.
  Mating flights: Thu 22 Oct to Sun 8 Nov.
  Her first eggs are due Sun 8 Nov to Sun 22 Nov (most often about two weeks after she emerges).
  No capped worker brood Wed 4 Nov to Mon 16 Nov: the varroa mites have nowhere to hide.

What to do (as of Sat 7 Nov)
  - Leave the hive closed during mating flights, Sat 7 Nov to Sun 8 Nov: a disturbed virgin can be lost or killed.
  - Look for eggs on Sun 15 Nov or soon after; if there are none by Sun 22 Nov, add a test frame of eggs.
  - Treat for varroa with oxalic acid while there is no capped brood, Mon 9 Nov to Mon 16 Nov (after the mating flights; follow the product's label).

Timeline, Sat 3 Oct to Sun 22 Nov (one column a day; | every week)
  inspections   v      v      v      v      v      v
  queen laying  ========????
  no brood                                      -------------
  new queen                   EEEEEEEEEmmmmmmmmmmmmmmLLLLLLLLLLLLLL
```

Exit code: 0 for a report, 2 for bad input.

## The log

```
hive Blue hive                                   optional, before the first inspection
2026-10-03 eggs larvae capped queen no-cells     the date, then what you saw (any order)
2026-10-10 eggs larvae capped cells-open         # comments are fine
2026-10-17 no-eggs larvae capped cells-capped swarm
```

| Words | Meaning |
|---|---|
| `eggs` `no-eggs` `larvae` `no-larvae` `capped` `no-capped` `no-brood` | worker brood seen, or looked for and not seen |
| `queen` `virgin` | a laying queen or a virgin queen seen |
| `cells-open` `cells-capped` `cells-hatched` `no-cells` | queen cells |
| `drone-laying` | drone brood in worker cells, several eggs to a cell |
| `swarm` | a swarm seen leaving or hanging nearby |

Anything not mentioned is "not recorded", which is different from "not there". Note what you looked for and didn't find (`no-eggs`): that's what pins the dates down.

## Security

The log is the only input, and Queenline treats it as untrusted:

- **Bounded:** at most 64 KB, read with `head -c`, so an endless stream stops. Lines are limited to 200 characters, and there are at most 200 inspections.
- **Strict shapes:**
  - every line is a hive name or an inspection;
  - a date must be a real calendar date from 2000 to 2099 (checked by round trip, so no `2026-02-30` and no `next friday`), in increasing order;
  - every word must come from a fixed list of 16;
  - names use a small character set.
- **Rejected characters:** control characters (such as terminal escapes), invisible formatting characters (bidirectional overrides, zero-width) and invalid UTF-8.
- **Nothing is ever run:**
  - no `eval`;
  - every expansion is quoted;
  - words are matched with `case` against fixed patterns;
  - text is passed to `date` only after passing the date pattern.

  The tests feed in `$(touch SECRET)` and `rm -rf` to check.
- **Safe reading:** the file must be a regular file, not a link or a folder, and errors give a line number, never the line or the path.
- **Clean code:** shellcheck passes on everything.
- **Known limits:**
  - development times vary a day or two with temperature and race;
  - drone brood (24 days) isn't tracked separately;
  - several episodes in one log are read as the latest one;
  - follow the label of any varroa treatment you use.

## Files

| File | What it does |
|---|---|
| `lib/queenline.sh` | Parsing and dates; the inference (`ql_infer`) |
| `lib/report.sh` | The story, the advice and the timeline |
| `bin/queenline` | The command: options and safe reading |
| `tests/run.sh` | Worked examples, 150 simulated colonies, hostile logs, the command line |
| `examples/blue-hive.txt` | A colony that swarmed in October |

See [HOW-IT-WORKS.md](HOW-IT-WORKS.md) for the reasoning and interview questions.
