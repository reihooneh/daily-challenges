# How Peakpour works

## 1. Architecture

```
cellar.txt ─(bin/peakpour: plain file, 64 KB, --rate, --start)─▶ pp_parse
     start, rate, and per wine: PP_NAME PP_COUNT PP_FROM PP_UNTIL (month numbers)
          │
          ├─▶ pp_need  ── the fewest bottles a month, and the stretch that forces it
          │                (Hall's condition over stretches of months, O(wines²))
          └─▶ pp_plan  ── earliest end of window first, month by month, at that pace
                           PP_PLAN, PP_MISSED, PP_PAST
          ▼
pp_report ── month lines, bottles that pass their best, the pace needed
```

## 2. File tour

| File | What's in it |
|---|---|
| `lib/peakpour.sh` | Month numbers and formatting, parsing with every check, `pp_plan` (earliest deadline first) and `pp_need` (the minimum pace). |
| `lib/report.sh` | `pp_names` ("Shiraz x2, Rose") and the report. |
| `bin/peakpour` | Arguments, safe file reading, overrides and exit codes. |
| `tests/run.sh` | 49 checks, including Kuhn's matching as an independent answer. |

## 3. Key concepts and language features

**Bottles are jobs with deadlines.** Each bottle must be "done" (opened) in some month between its window's start and end, and each month has room for `rate` of them. That's scheduling unit jobs with release times and deadlines. The classic answer is *earliest deadline first*: each month, open the bottles whose windows close soonest.

Why that's optimal: take any plan that opens a bottle with a later deadline while one with an earlier deadline waits. Swapping the two keeps both in their windows, because the waiting bottle was already available and the later one can go where the earlier one went. Repeating the swap turns any successful plan into the EDF plan, so EDF succeeds whenever anything does. The tests go further: they check that EDF misses exactly as few bottles as the best possible plan.

**How fast do you need to drink?** Take any stretch of months [a, b]. The bottles whose whole window lies inside it must all be opened in those months, so you need at least that many bottles ÷ (b − a + 1) a month. The surprise (Hall's theorem, for windows that are intervals) is that the worst stretch is also *enough*: if every stretch passes, a plan exists. So the minimum pace is the maximum over stretches, rounded up.

Checking every stretch naively is slow. Instead, for each possible start month a, sweep the windows in order of their end and keep a running total of the bottles that start at or after a. That's O(wines²) and it names the stretch, which is what makes the result explainable.

**An independent check.** The tests don't trust the theory. They build every bottle and every month slot and find a maximum matching with Kuhn's augmenting paths: for each bottle, try each free slot in its window; if a slot is taken, see whether its bottle can move elsewhere. The size of that matching is the most bottles that can be opened in time, and the plan must miss exactly the rest.

**Bash features:**
- **Months as integers:** year × 12 + month, so all comparisons are `(( ))` arithmetic.
- **Base 10:** `10#$n` makes "08" mean eight, not invalid octal.
- **Parsing:** `IFS=, read -r -a` splits a line into fields, and `[[ =~ ]]` with `BASH_REMATCH` checks them.
- **Sorting:** `mapfile -t` with process substitution reads the windows sorted by `sort -n`.
- **Associative arrays:** `local -A` counts bottles per wine in a month.
- **Safety:** `set -euo pipefail`, and shellcheck with `source-path` so the library and tests are checked together.

## 4. Interview questions

**Q: Why is earliest-deadline-first right here, when greedy algorithms often aren't?**
A: An exchange argument. In any successful plan, if a later-deadline bottle is opened while an earlier-deadline one waits, swapping them is still valid. Both stay within their windows, because the waiting bottle had already become drinkable. So some successful plan is the EDF plan. It relies on every bottle taking exactly one slot; with jobs of different lengths the problem becomes NP-hard.

**Q: How do you prove the "pace needed" is enough, not just necessary?**
A: Necessary is easy: any stretch must hold the bottles that live entirely inside it. Sufficient is Hall's marriage theorem: a matching that covers every bottle exists if every set of bottles has enough slots in its windows. For interval windows, the worst sets are those whose windows fit inside one stretch, so checking stretches is enough. The tests confirm it: at the computed pace EDF misses nothing, and one slower misses something.

**Q: What can go wrong when a shell script reads a user's file, and how is it prevented here?**
A: Several things:
- Word splitting and globbing. Every expansion is quoted.
- Command substitution hidden in data, like `$(...)` or backticks in a wine name. Names must match a strict pattern, and the data is never `eval`ed.
- Leading-zero numbers read as octal. `10#` fixes that.
- Control characters reaching the terminal, which are refused.
- Symlinks and devices, which are refused.
- Huge input, which is capped by size, line length and counts.

shellcheck is clean, and a test proves an injected command doesn't run.

## 5. Extension ideas

- **Peaks, not just windows:** give each wine a best year and plan to open bottles as close to it as possible, using a min-cost flow instead of EDF.
- **Occasions:** reserve particular bottles for dates (a birthday, Christmas) and plan around them.
- **A ledger:** read a log of what was opened, update the counts, and replan.
