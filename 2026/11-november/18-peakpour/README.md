# Peakpour

**Plans which bottles from your wine cellar to open each month, so each one is drunk inside its drinking window, and tells you how fast you'd need to drink to manage it.**

Language: Bash 5 (plus coreutils) · Field: wine collecting / deadline scheduling · Day: 18 November 2026 (morning)

Every bottle has a drinking window: too early and it's closed and tannic, too late and it's tired. Cellar apps show the windows and a "drink soon" list. They don't answer the planning question: at the pace you actually drink, what should you open each month so that nothing passes its best? And if something will, how much faster would you need to go? Peakpour answers both.

- **A month-by-month plan:** the bottles whose windows close soonest go first. Ties go to the wine with the most bottles left, mixed so a month isn't all one wine.
- **What will be missed:** which bottles pass their best at your pace, and which were already past it before you started.
- **The pace you need:** the fewest bottles a month that opens everything in time. It also shows the tightest stretch that forces it: "3 bottles must be drunk in that one month".
- **No rate given?** It plans at that minimum pace.

## Example

```text
$ bin/peakpour examples/cellar.txt
Peakpour: 31 bottles of 9 wines, 2 a month from Dec 2026

  Dec 2026  Beaujolais 2023 x2
  Jan 2027  Rose 2025 x2
  Feb 2027  Rose 2025 x2
  Mar 2027  Hunter Valley Semillon 2019 x2
  Apr 2027  Hunter Valley Semillon 2019, Margaret River Chardonnay 2022
  ...
  Feb 2028  Rutherglen Muscat (fortified) x2

At 2 a month, 1 bottle will pass its best:
  Beaujolais 2023: 1 of 3, window closes Dec 2026

To open every bottle in time you need 3 a month. The tightest stretch is Dec 2026 to Dec 2026:
  3 bottles must be drunk in that one month.
```

[`examples/big-party.txt`](examples/big-party.txt) bought 24 bottles of rosé for one summer. At 3 a month, 12 will pass their best; it needs 6 a month from November to February.

## The cellar file

```text
start 2026-12                                   the month to plan from (or --start)
rate 2                                          bottles you open a month (or --rate; optional)
Hunter Valley Semillon 2019, 3, 2025, 2027-06   name, bottles, drink from, drink until
```

A year alone means January when it starts a window and December when it ends one. `#` starts a comment.

## Run and test

```bash
bin/peakpour examples/cellar.txt
bin/peakpour examples/cellar.txt --rate 3 --start 2027-01
bin/peakpour - < my-cellar.txt
bash tests/run.sh       # 49 checks
shellcheck -x bin/peakpour lib/*.sh tests/run.sh
```

Exit codes: 0 every bottle opened in its window, 3 some will pass their best, 2 bad usage or input.

The tests:
- **Against an independent answer:** on 60 random small cellars at two drinking rates, the number of bottles the plan misses is checked against the fewest possible. That is worked out separately as a maximum matching between bottles and month slots, using Kuhn's augmenting paths.
- **The pace needed:** at the minimum pace nothing is missed, and at one bottle a month less something is.
- **Hostile input**, the examples, the command line, and the biggest allowed cellar.

## Security

Peakpour reads one text file and prints a plan. No software is perfectly secure; this is what's in place.

- **Data is never run:**
  - every field is matched against an anchored pattern before use, and names allow only letters, digits, spaces and `' ( ) . & / -`;
  - there's no `eval` and no unquoted expansion;
  - numbers go through `10#` so a leading zero can't turn into octal.

  A test feeds a name containing `$(touch ...)` and checks it is refused and nothing ran.
- **Only plain files:** links, folders and devices are refused, and the path is never echoed.
- **Bounded input:**
  - files over 64 KB or lines over 200 characters are refused;
  - so are control characters and invalid UTF-8;
  - at most 200 wines and 2,000 bottles, with windows from 1950 to 2199 and no more than 50 years past the start;
  - 1 to 100 bottles a month.
- **Bounded work:** the plan is O(months × rate × wines) and the pace is O(wines²). The largest allowed cellar takes about 5 seconds.
- `set -euo pipefail`, with every expansion quoted. shellcheck is clean.

**Limits:**
- Windows are only as good as their source (a label, a shop, a critic).
- Every bottle counts the same. "Save the good one for a birthday" isn't modelled.
- It doesn't track what you've already drunk. Edit the counts as you go.

More detail: [HOW-IT-WORKS.md](HOW-IT-WORKS.md).
