# Tagback

**Estimates how many animals live in a place from a mark-recapture survey, with honest 95% intervals, and tells you when the survey's assumptions have broken, including when "trap-happy" animals are making the count too low.**

Language: JavaScript (Node 22, no runtime dependencies) · Field: ecology / statistics · Day: 21 October 2026

You can't count every frog in a pond. Instead, ecologists catch some, mark them and let them go. Next time, they check what share of the catch is already marked: if a quarter of the frogs caught are marked, and 40 frogs carry marks, there are probably about 160. Repeat this over several nights and the estimate sharpens.

The catch: it only works if every animal is equally likely to be caught. Some animals learn that traps mean food and keep coming back. Others avoid traps entirely. Then the same few animals turn up again and again, and the population looks far smaller than it is. Tagback checks for exactly that.

## Quick start

```bash
npm install          # only for the type checker; the tool itself needs nothing
node bin/tagback.js examples/trap-happy-beetles.txt
npm test             # 32 tests, including simulations with a known population
npm run check        # strict TypeScript checking of the JavaScript
```

```
TAGBACK  Beetle plot B  (6 sessions, 148 animals marked)

Session  Caught  Already marked  Marked at large  Newly marked  Kept
Day 1        67               0                0            67     0
Day 2        59              25               67            34     0
...
Day 6        70              60              138            10     0

Population estimates (95% interval)
  Chapman, first two sessions           156   (130 to 203)
  Schnabel, all sessions                150   (148 to 173)
  Schumacher-Eschmeyer, all sessions    151   (straight-line fit 1.00)
  Chao, uneven catchability             191   (at least this many)

Checks
  ok    233 recaptures in total: enough for the estimates to settle.
  ok    The share of marked animals rises steadily with the number marked (fit 1.00).
  WARN  Some animals are caught far more often than chance allows (trap-happy) and others hardly at all. The estimates above are probably too LOW; see Chao.
        caught once / twice / 3+ times: 47 / 24 / 77  (expected 24.7 / 45.6 / 77.6)

Planning a fresh two-session survey (if the population is about 150)
  within +/-20%: mark 65, then catch 65 (about 28 recaptures expected)
  within +/-10%: mark 92, then catch 92 (about 56 recaptures expected)
```

That example was simulated with **300** beetles, a third of which are ten times easier to catch. The usual estimates all say about 150, with confident intervals, and are wrong. The capture counts give it away: too many beetles caught once and too many caught every time, with too few in between. Chao's estimate (191) is much closer.

## The survey file

```
study Frog pond, spring
session Mon: F001 F002 F003
session Tue: F002 F004 F005!     # ! = caught but not released (kept, or died)
```

One line per session, listing the tags caught. The first time a tag appears, the animal was new and got marked. Options: `--json` prints all the numbers, `--precision 15` adds a ±15% plan, and `-` reads standard input. Exit codes: `0` done, `2` bad input or usage.

## Security

- **Safe file reading:** only regular files are opened, with `O_NOFOLLOW` (symlinks are refused) and checked with `fstat` on the opened file, so directories, `/dev/zero` and pipes are refused. At most 256 KB is read, from a file or standard input, and the text must be valid UTF-8.
- **Strict input:** tags are 1-12 letters, digits or dashes, and names are limited to letters, digits and simple punctuation. Control characters (terminal escape codes) and hidden Unicode direction marks are refused anywhere in the file. Limits on line length (4000), sessions (50), animals per session (2000) and total captures (20,000) keep the work bounded.
- **Clean messages:** errors give a line number and never echo raw input. File names and unknown options are cleaned before printing.
- **Consistency checks:** a tag listed twice in one session, or an animal caught after it was kept, is an error rather than a silently wrong count.
- **No dependencies at run time;** the two dev dependencies (TypeScript and Node's types) are pinned, and `npm audit` reports nothing.

**Known limits:** the estimates assume a *closed* population (no births, deaths or moves during the survey, apart from animals you mark as kept). The straight-line check catches big violations, but not all. Chao's figure is a lower bound, not an exact estimate. The planner assumes equal catchability.

See [HOW-IT-WORKS.md](HOW-IT-WORKS.md) for the walkthrough.
