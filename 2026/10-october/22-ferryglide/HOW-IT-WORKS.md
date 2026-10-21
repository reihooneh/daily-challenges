# How Ferryglide works

A walkthrough so you can explain every part of it.

## 1. The big picture

```
 plan.txt ──▶ PlanParser      strict line forms, ranges, limits → a Plan record
                  │
                  ▼
              Current         the reference station's stream at any minute (rule of cosine)
                  │
              Navigator       per leg: shift and scale the stream, resolve it along and across
                  │           the course, ferry-glide, integrate in 30-second steps
                  ▼
              Planner         every departure in the window → trips → good windows, best trip
                  │
              Report          timeline, windows, the best plan leg by leg
```

## 2. File tour

| File | Job |
|---|---|
| `Plan.java` | Records for the trip, station, table events and legs |
| `PlanParser.java` | The file format: one regular expression per line form, ranges, table checks |
| `Current.java` | The stream between slack and maximum, by the rule of cosine |
| `Navigator.java` | The vector triangle, ferry glide, and running a leg and a trip |
| `Planner.java` | Trying each departure, finding windows and the best trip |
| `Report.java` | The printed plan and the timeline |
| `Main.java` | Safe file reading, strict UTF-8, exit codes |
| `tests/ferryglide/Tests.java` | 132 checks |

## 3. Key ideas

### Current tables and the rule of cosine
A current table lists, for a reference station, the times of slack water and the times and speeds of maximum flood and ebb. Between them the stream is assumed to follow a quarter of a sine wave. From slack at `t0` to a maximum `V` at `t1`, the speed is `V·sin(90° × (t − t0)/(t1 − t0))`. It falls back the same way, as a cosine, to the next slack. Floods count as positive and ebbs as negative, so one signed number describes the stream.

### Secondary stations
Tables don't cover every bay. Instead, other places are given relative to a reference: "the stream turns 20 minutes later and runs at 60% of the speed". Each leg works the same way: its stream at time `t` is `ratio × reference(t − offset)`, flowing towards the leg's flood direction, or the opposite way on the ebb.

### The vector triangle and the ferry glide
Split the stream into two parts: along the course (a = s·cos θ) and across it (c = s·sin θ), where θ is the angle between the stream's direction and the course. To stay on the line you can't let the cross part push you sideways, so you point partly into it. With paddle speed P, the heading turns by `asin(c/P)` and the speed made good along the course is

```
ground speed = √(P² − c²) + a
```

If `|c| ≥ P` the line can't be held at all, however you point. That is a hard failure, as is a ground speed below 0.3 kn ("the current stops you").

### Integrating a leg
The stream changes during a leg, so each leg is paddled in 30-second steps. Each step uses the stream at its midpoint (the midpoint rule) and the last step is cut to the exact distance. A test checks the result against a far finer integration, and another checks that still water gives exactly distance ÷ speed.

### Searching departure times
Leg *n* starts when leg *n − 1* ends, so a departure time fully determines the trip. Ferryglide tries every `step` minutes across the window, marks each trip good (finished, and within both limits) or not, then groups the good ones into windows and picks the quickest. Trying every time is simple, exact, and fast enough: one trip is a few hundred steps per leg.

### Java features you met here
- **Records** (`Plan`, `Leg`, `Trip`) for immutable data with generated `equals` and `toString`.
- **Switch expressions** with arrow cases in the parser's error message.
- **Text blocks** (`"""`) for test plans.
- **`Files.readAttributes(..., NOFOLLOW_LINKS)`** to check what a path *is* before opening it.
- **`CharsetDecoder` with `CodingErrorAction.REPORT`** for strict UTF-8.
- **`Locale.ROOT` formatting** so a decimal point never becomes a comma on a European system.

## 4. Interview questions you might get

**Q: Why can't you just add the current to your paddling speed?**
A: Because currents are vectors. Only the part along your course adds or subtracts. The part across it pushes you off your line, so you have to point into it, and that costs speed: you only make `√(P² − c²)` along the line. A 2 kn cross-current costs a 3 kn paddler about 0.76 kn even though it never pushes against you.

**Q: How do you get the current at an arbitrary time from a table of a few events?**
A: The rule of cosine: a quarter sine from slack up to the maximum and a quarter cosine back down to the next slack, with signs for flood and ebb. It's the standard approximation in navigation, and it's smooth, which the tests check minute by minute. For other places, the table's secondary-station method shifts the reference curve in time and scales it.

**Q: Why brute-force departure times instead of something cleverer?**
A: The trip is fully determined by the departure time and the search space is one-dimensional and small: a few hundred departure times, each costing a few hundred integration steps per leg. It's exact, easy to explain, and lets the report show the whole picture of good and bad windows rather than just one answer.

## 5. Ideas to extend it

1. **Wind against tide:** add a wind forecast and flag legs where wind opposes a strong stream (steep, dangerous waves).
2. **Return trip:** plan out and back together, with a minimum time ashore.
3. **Harmonic predictions:** compute the reference stream from tidal constituents instead of a typed table.
