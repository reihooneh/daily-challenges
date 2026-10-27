# How Gapkeeper works

A walkthrough so you can explain every part of it.

## 1. The big picture

```
 route log ──▶ log.ts        strict parse → Log { stops, headway, control stops, demand, trips }
                 │
                 ▼
            replay.ts        rule (alpha, cap) → replayed timetable, trip by trip in dispatch order
                 │             · hold at control stops until alpha x H after the bus in front
                 │             · dwell feedback: +dwell x (gap now − gap in the log) at every stop
                 ▼
           headways.ts       gaps per stop → average wait, EWT, bunching, overtakes
                 │
                 ▼
            report.ts        per-stop strips, the 5 x 4 rule grid, the recommendation
```

## 2. File tour

| File | Job |
|---|---|
| `src/log.ts` | The log format, clock times, limits, text-safety checks |
| `src/headways.ts` | Gaps between buses at each stop, waiting-time formulas, bunching and overtakes |
| `src/replay.ts` | Re-runs the day under a holding rule, and the sweep over 20 rules |
| `src/report.ts` | The printed report, including the one-line strip per stop |
| `src/cli.ts` | Bounded, UTF-8-strict reading; `main()` returns an exit code so tests can call it |
| `tests/gapkeeper.test.ts` | 10 tests with `node:test` |

## 3. Key ideas

### Why uneven gaps cost more than they look
Someone turning up at a random moment is more likely to land in a long gap than a short one: in proportion to its length. Then they wait half of it on average. So the average wait is

```
AWT = Σ h² / (2 Σ h)
```

With even gaps of H, that's H/2. With alternating 1- and 15-minute gaps (still averaging 8), it's 7.1 minutes instead of 4. That is the **inspection paradox**. **Excess waiting time** is AWT − H/2, the measure London and other agencies use for frequent routes. The route figure is a demand-weighted average over stops.

### Why bunching grows
A bus with a big gap in front finds more people waiting. It boards more, dwells longer and loses more time, so the gap in front grows. The bus behind finds fewer people, gains time and closes in. This is a positive feedback loop. Gapkeeper models it with one number, `dwell`: extra seconds at a stop per extra second of gap in front. The default, 6 s per minute, is about 2 people a minute at 3 s each.

### Replaying a rule
Trips are replayed in dispatch order. At every stop, a bus's departure is:

1. its logged time, shifted by whatever happened to it upstream;
2. plus `dwell × (gap in front now − gap in front in the log)`, so a bus that was held, and now has a smaller gap in front, dwells less downstream;
3. at a control stop, plus a hold: `min(cap, max(0, leader's departure + alpha·H − ready time))`.

Running times between stops come straight from the log, so the replay respects the real traffic of that day. With alpha = 0 it reproduces the log exactly, and a test checks that.

### Choosing a rule
Each rule is scored as `EWT + ridevalue × extra minutes on board per trip`. Holding harder (alpha near 1, a long cap) evens the gaps but delays the people on the bus. The grid shows both numbers, so a planner can see the trade-off, not just the winner.

### TypeScript features you met here
- **`strict`, `noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`:** array reads are `T | undefined` until checked, which is why the code uses `!` only where an index is known to be in range.
- **Type predicates** (`(t): t is number => t !== null`) to narrow arrays after filtering.
- **`TextDecoder` with `fatal: true`** to refuse invalid UTF-8 instead of silently replacing it.
- **ES modules with NodeNext resolution** (`.js` in import paths) and `node:test` with no test framework to install.

## 4. Interview questions you might get

**Q: Why not just report the average gap between buses?**
A: Because the average gap is the same whether buses are even or bunched. If 16 minutes holds two buses, the average gap is 8 either way. Riders feel the gaps weighted by their length, which is what Σh²/(2Σh) captures. That's why EWT is the agency standard for frequent services.

**Q: How do you know the replay engine is right?**
A: Three checks. With no holding it reproduces the log exactly. A perfectly regular route is never held under any rule. On a bunched route, every hold respects the cap and the target gap and never makes a bus leave early, and the gaps after the control stop become more even.

**Q: What would make this unsafe on real data, and what did you do about it?**
A: Huge or endless input, binary junk, hidden characters, or numbers like `1e309` or `NaN` sneaking into the maths. The reader stops at 256 KB, decodes UTF-8 strictly, and refuses control and direction characters. Every value must match an anchored pattern and a range. Error messages never repeat the input, so a crafted file can't inject terminal escapes into someone's console.

## 5. Ideas to extend it

1. **GTFS-realtime input:** convert a day of vehicle positions into the log format automatically.
2. **Several control stops tuned together:** search alpha and the cap per stop, not one rule for all.
3. **Passenger loads:** with on-board counts, weight the extra ride time by the people actually delayed.
