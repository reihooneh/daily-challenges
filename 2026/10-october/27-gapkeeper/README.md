# Gapkeeper

**Reads a bus route's arrival log, shows how bunching grew stop by stop and how much extra waiting it cost riders, then replays the day with a headway-holding rule to find the setting that cuts waiting most.**

Language: TypeScript (Node 22, no runtime dependencies) · Field: public transport operations · Day: 27 October 2026

"Two buses came at once, then nothing for twenty minutes" is bus bunching. It feeds itself. A bus that falls a little behind finds more people waiting, so it spends longer at each stop and falls further behind. Meanwhile the bus behind it finds the stops empty and catches up. Transit agencies measure the damage as **excess waiting time (EWT)**: how much longer riders wait than an evenly spaced service would make them. The standard fix is holding a bus at a timing point so the gaps even out. Holding costs the people already on board, though, so how hard should you hold?

Gapkeeper answers that from your own data:
- **Waiting:** average wait and EWT at every stop, demand-weighted for the route, with a strip showing where the buses ran each stop through the day.
- **Bunching:** pairs under a quarter of the headway, gaps over 1.75 headways, and buses overtaking each other.
- **Replay:** the logged day re-run under 20 holding rules (how hard to hold × the longest hold allowed). It models the dwell feedback that makes bunching grow, so holding a bus also changes how long it spends at each later stop.
- **Recommendation:** the rule with the best balance of less waiting against extra time on board, with both numbers shown.

## Quick start

```bash
npm install          # TypeScript compiler only (pinned); no runtime dependencies
npm test             # compiles, then 10 tests with node:test
node dist/src/cli.js examples/route-99x.txt
```

```
GAPKEEPER  99X Parramatta Rd westbound
18 trips past 10 stops, scheduled every 8.0 min (an even service means an average wait of 4.0 min).

What riders got: 3.2 min of excess waiting on average (EWT), 44 bunched pairs, 21 long gaps, 0 overtakes.

  Stop               Avg wait  Excess  Buses through the day (▲ = bunched)
  Central                 4.2    +0.2  ■··■··■■···■··■··■··■■···■··■·■··■··■·■··■··■··■
  Broadway                4.9    +0.9  ■·■···■■·····▲···■··■■····■■··■···■·■·■··■···■·■
  Leichhardt              7.8    +3.8  ■·■····▲········▲▲··■■·······▲■····■■·■···■··■·■
  Petersham              11.6    +7.6  ■■······▲············▲▲··········▲··▲··■··■···■■
  Ashfield               15.1   +11.1  ■■·········▲················▲·········▲▲···■···▲
  ...
Replaying the day with holding at Leichhardt
  alpha      cap 1 min     cap 2 min     cap 3 min     cap 5 min
  0.5       2.5 / +0.3    2.1 / +0.5    1.8 / +0.7    1.6 / +0.9
  0.6       2.3 / +0.3    1.9 / +0.5    1.7 / +0.7   *1.4 / +1.1
  ...
Recommendation: hold to 0.6 x headway, capped at 5 min.
  Excess waiting falls from 3.2 to 1.4 min (57% less);
  bunched pairs 44 -> 15; 9 of 18 trips held, 1.3 min each on average;
  riders on board pay 1.1 min more per trip (counted at 0.5 of a waiting minute).
```

The example is a **simulated** morning on a made-up route (not real operator data), generated with the same dwell feedback the replay models.

## The log

```
route 99X Parramatta Rd westbound
headway 8 min                     # the scheduled gap between buses
stops Central, Railway Square, Broadway, Glebe Point Rd, ...
control Leichhardt                # a timing point where buses may be held (one or more)
demand Central 3                  # optional: relative boardings per stop (default 1)
dwell 18 s per min                # extra stop time per extra minute of gap in front (default 6)
ridevalue 0.5                     # a minute on board counts as half a minute of waiting (default)
trip 99X-01 07:00:12 07:03:01 07:06:02 ...   # one time per stop, '-' where the log has none
```

Times are `HH:MM` or `HH:MM:SS`, up to `29:59:59` for service after midnight. Exit codes: `0` report printed, `2` bad usage or input. `-` reads standard input.

## Security

Gapkeeper reads one text file and prints text, so the risks are hostile input and runaway work:

- **Bounded reading:** at most 256 KB, read in a loop that stops just past the limit, so `/dev/zero` or an endless pipe can't fill memory. Only regular files are opened, and the path is never echoed.
- **Strict decoding:** the bytes must be valid UTF-8 (a fatal decoder, not silent replacement). Control characters (terminal escapes), invisible direction marks and zero-width characters are refused.
- **Strict parsing:** every line has a fixed form checked by anchored patterns: names, trip ids, `HH:MM[:SS]` clock times, and plain decimals only, so no `NaN`, `Infinity` or exponents. Everything has a range: headway 2 to 60 min, at most 60 stops and 600 trips, and no trip longer than 4 hours. Times along a trip may not go backwards, and duplicate ids and stop names are refused.
- **No echo:** errors give a line number and never repeat the input.
- **Bounded work:** the replay grid is a fixed 20 rules, each linear in trips × stops; the overtake count is at most 600² × 60 comparisons.
- **No dangerous features:** no `eval`, no shell, and no network. There are no runtime dependencies, and the compiler is pinned. `npm audit` reports 0 vulnerabilities, and `tsc` runs in strict mode (`noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`).

**Known limits:** this is a replay of one logged day with a simple linear dwell model, not a traffic simulation. Real holding changes how riders and drivers behave, and buses can't always wait at every stop. Treat the recommendation as a starting point to trial, then log again.

See [HOW-IT-WORKS.md](HOW-IT-WORKS.md) for the walkthrough.
