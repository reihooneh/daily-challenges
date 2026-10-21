# Ferryglide

**Tells a sea kayaker when to leave so the tide helps instead of fights: it paddles every departure time through a multi-leg route, holding a ferry glide across side currents, and shows which windows keep within your limits.**

Language: Java 21 (standard library only) · Field: marine navigation / sea kayaking · Day: 22 October 2026

Tidal streams in channels and harbour entrances can run faster than a kayaker paddles. Leave an hour too early and you fight the flood across the entrance. Leave too late and the ebb pushes you sideways. Paddlers work this out by hand from the current tables, leg by leg, with a pencil.

Ferryglide does the arithmetic for every possible departure time:
- It builds the stream between the table's slack and maximum times using the rule of cosine.
- It shifts and scales the stream for each leg, the way current tables do for secondary stations.
- It solves the vector triangle at each moment. Current along your course speeds you up or slows you down. Current across it means pointing partly upstream (a **ferry glide**) to stay on your line, which costs speed.

## Quick start

```bash
make            # compile (needs a JDK 21)
make test       # 132 checks
./ferryglide examples/the-rip.txt
```

```
FERRYGLIDE  Across the entrance and down to the beach
3 legs, 5.5 nm at 3.5 kn (1h 34m in still water). Leaving between 05:00 and 12:00.

Departure  --------------------################-------
Stream     ffFFFFFFFFFFFFFFFFFFFFfffffff0000eeeeeeEEEE
           05:00                                 12:00
           # good   - over a limit   . won't make it    stream at Entrance reference: F/f flood, E/e ebb, 0 slack

Good times to leave:
  08:20 to 10:55   trip takes 1h 21m to 1h 53m

Best: leave at 10:55, arrive 12:16 (1h 21m, 13 min faster than still water).

  Leg                              Start   End     Steer   Against  Across
  Boat ramp to the entrance mark…  10:55   11:12   120°    0.0 kn   0.0 kn
  Across the entrance              11:12   11:29   228°    0.0 kn   2.0 kn
  Down the coast to the beach      11:29   12:16   140°    0.0 kn   0.0 kn

You'll angle up to 34° into the stream to hold your line ("Steer" is the heading at the start of each leg).
```

Leaving before 08:20 means paddling into more than 1 kn of flood on the last leg. Leaving after 10:55 means a cross-current on the entrance stronger than the 2 kn limit. Crossing the entrance needs a heading of 228° for a course of 200°.

## The plan file

```
trip Across the entrance and down to the beach
paddle 3.5 kn                      # your cruising speed through the water
window 05:00 to 12:00              # when you could leave
limit opposing 1.0 kn              # optional (default 1.5): most current you'll paddle into
limit cross 2.0 kn                 # optional (default 2.0): most current across your course
step 5                             # optional: minutes between departure times tried
station Entrance reference, flood 300     # reference station; the flood sets towards 300°
event 03:40 slack                  # the station's current table: slack, maximum, slack...
event 06:55 flood 2.6
event 10:05 slack
event 13:20 ebb 2.9
leg Across the entrance: 0.9 nm, course 200, offset -10, ratio 1.0
leg Down the coast: 3.4 nm, course 140, offset +25, ratio 0.45, flood 320
```

Each leg's stream is the reference station's, `offset` minutes earlier or later, multiplied by `ratio`, running towards `flood` (the station's direction if not given) on the flood and the opposite way on the ebb. Times can run past midnight. Exit codes: `0` a good departure exists, `1` none in the window, `2` bad input.

The example's current table is invented. For a real trip, use the official predictions for your area. Ferryglide is a planning aid, not a substitute for local knowledge, a forecast, and your own judgement on the water.

## Security

- **Safe file reading:** only regular files are opened (symbolic links, directories and devices such as `/dev/zero` are refused, checked without following links). At most 64 KB is read from a file or standard input, and the text must be valid UTF-8.
- **Strict parsing:** every line must match one of eight exact forms, and every number has a range (paddle 0.5 to 8 kn, distances up to 50 nm, offsets within 3 hours, and so on). Names allow letters, digits and simple punctuation only. Control characters and hidden Unicode direction marks are refused. Limits on lines (200 characters), legs (30) and table events (40) keep the work bounded, and the departure window is capped at 18 hours.
- **Clean messages:** errors give a line number and never echo the input; file names are cleaned before printing.
- **Built with `-Xlint:all -Werror`** and no dependencies.

**Known limits:**
- The stream on each leg is one value everywhere along it. Real streams vary across a channel and speed up around headlands.
- Wind, waves and wind against tide aren't modelled, and they often matter more than the current.
- The rule of cosine is an approximation to the real tidal curve.

See [HOW-IT-WORKS.md](HOW-IT-WORKS.md) for the walkthrough.
