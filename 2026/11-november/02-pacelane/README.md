# Pacelane

**Splits a swim squad into lanes and gives each lane a send-off interval, so that every swimmer gets as close as possible to the rest the coach wants, never less than a minimum, and the lane never jams at the wall.**

Language: C11 (no dependencies) · Field: swim coaching / optimal partitioning · Day: 2 November 2026

At every masters or club session, the coach sorts swimmers into lanes by eye. Then each lane swims a set "on" an interval read off the pace clock, say 10 × 100 on 1:45. Everyone in a lane leaves on the same interval, so a mixed lane goes wrong both ways: the fast swimmers stand at the wall for 30 seconds while the slowest gets 2 seconds and falls apart. Pacelane does the split properly:

- **The interval for each lane:** a multiple of the pace clock's step (5 s by default), set as close as possible to "average swim time + target rest". It is raised when needed so the slowest still gets the minimum rest, and so that everyone has pushed off (5 s apart) before the leader goes again.
- **The best split:** it minimises the total squared miss from the target rest across the whole squad, choosing lane sizes as well as members. Lanes can be uneven or left free when that suits the squad better.
- **A lane sheet:** each lane's interval, push-off order, every swimmer's rest, and when the lane finishes the set.
- **A comparison:** how much better it is than the usual equal-sized lanes by pace.
- **Real pools:** the number of lanes, the most swimmers a lane can take, metres or yards, any set length, and lane 1 as the fastest or the slowest.

## Quick start

```bash
make && ./pacelane examples/masters.txt
make test        # 62 unit checks and 15 command-line checks, under AddressSanitizer and UBSan
make analyze     # GCC's static analyser
```

```
PACELANE  Tuesday masters
Set: 10 x 100 in a 25 pool, aiming for 15 s rest (never under 5 s), intervals in steps of 5 s.
22 swimmers in 5 of 5 lanes (at most 7 a lane, pushing off 5 s apart).

Lane 1   on 1:35    6 swimmers, set done after 16:04
    Alex Moreau        1:12 /100   rest 23 s
    Bea Okonkwo        1:16 /100   rest 19 s
    Chen Wei           1:18 /100   rest 17 s
    Dana Kowalski      1:21 /100   rest 14 s
    Eli Haddad         1:22 /100   rest 13 s
    Farah Siddiqui     1:24 /100   rest 11 s

Lane 2   on 1:45    6 swimmers, set done after 17:45
    ...
Lane 5   on 2:35    2 swimmers, set done after 25:45
    Uma Rao            2:18 /100   rest 17 s
    Vic Bianchi        2:25 /100   rest 10 s

Typical miss from the target rest: 4.0 s. Equal-sized lanes by pace would give 5.3 s.
Biggest miss: Alex Moreau, 8 s more rest than wanted, in lane 1.
This is the best split into lanes of pace neighbours (every such split was checked).
```

The lanes come out uneven (6, 6, 4, 4, 2): the slow end of the squad is spread out in pace, so it needs smaller lanes to keep everyone's rest close to 15 s.

## The squad file

```
title Tuesday masters
pool 25            # metres or yards
set 10 x 100       # repeats x distance (a whole number of lengths)
lanes 5
max 7              # most swimmers in one lane
rest 15            # seconds of rest wanted on each repeat
min-rest 5         # nobody gets less
gap 5              # seconds between swimmers pushing off
clock 5            # intervals are multiples of this many seconds
lane-1 fastest     # or slowest
swimmer Alex Moreau 1:12      # pace per 100: 1:12, 72 or 1:12.5
```

Exit codes: `0` lanes printed, `2` bad usage or input. `-` reads standard input.

## Security

- **Bounded input:** at most 32 KB, read with a hard limit (so `/dev/zero` or an endless pipe is cut off), 200 characters a line and 200 swimmers. Only regular files are opened, without following symlinks, and the path is never printed.
- **Strict parsing:** every line has a fixed shape and every number a range. Times are parsed by hand with no `atoi` or `scanf`, so no overflow is possible. Error messages give the line number and what was expected, never the input.
- **Safe names:** names are checked as strict UTF-8 (overlong forms and surrogates refused). Control characters, zero-width characters and Unicode direction overrides, which could rewrite the terminal or reorder the sheet, are refused.
- **Memory safety:** fixed-size buffers with explicit bounds and no heap allocation in the program. It builds with `-Wall -Wextra -Wconversion -Werror`, `_FORTIFY_SOURCE` and stack protection, and the tests run under AddressSanitizer and UBSan. GCC `-fanalyzer`, `clang-tidy` (clang-analyzer and bugprone checks) and Valgrind report nothing.
- **Bounded work:** the lane costs and the dynamic programme take at most about 130,000 steps (12 lanes, 200 swimmers, 20 a lane).

**Known limits:**
- Paces are what swimmers say they swim. Pacelane plans with them and doesn't measure them.
- It assumes a lane holds neighbours in pace. Checks against every possible assignment on 150+ random squads found no case where mixing speeds did better, but that is a test, not a proof.

See [HOW-IT-WORKS.md](HOW-IT-WORKS.md) for the walkthrough.
