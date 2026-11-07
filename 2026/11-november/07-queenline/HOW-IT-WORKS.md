# How Queenline works

Queenline treats a beehive as a clock that's read once a week. Brood develops on a fixed timetable, so each note in the log says something about *when* the queen laid. Queenline combines those statements into time windows.

## 1. The big picture

```
log text ──ql_parse──▶ day numbers + per-inspection facts (1 seen, 0 looked and absent, '' not noted)
                              │
                         ql_infer
                              ├─ latest run of no-eggs inspections, and any eggs after it
                              ├─ old queen's last egg:   max(lower bounds) .. min(upper bounds)
                              ├─ swarm or loss:          queen cells before the stop, or a swarm seen
                              ├─ first new queen:        earliest bounds from cells, virgin, new eggs
                              ├─ mating, first eggs due, new eggs seen
                              └─ broodless gap:          last old egg + 21 .. first new egg + 8
                              │
                         ql_report ── story · what to do · timeline
```

## 2. File tour

- **`lib/queenline.sh`:**
  - `ql_day` turns a date into a day number, checking it's real by round trip through `date`, and `ql_fmt` turns a day back into words;
  - `ql_parse` checks the text (size, characters, UTF-8, line shapes, words, date order) and fills parallel arrays;
  - `ql_infer` works out the windows and the colony's state.
- **`lib/report.sh`:** turns the windows into sentences, advice, and a text timeline with one column per day.
- **`bin/queenline`:** options, bounded and safe reading, then parse, infer, report.
- **`tests/run.sh`:** sources the library to test the inference directly, and runs the command for the rest.

## 3. Key ideas

**Brood ages are evidence about when eggs were laid.** If the queen's last egg was on day S, then at an inspection on day d:

| Seen at day d | An egg was laid… | So |
|---|---|---|
| eggs | after d − 3 | S ≥ d − 3 |
| larvae | between d − 9 and d − 3 | S ≥ d − 9 |
| capped brood | between d − 21 and d − 9 | S ≥ d − 21 |
| no eggs | none after d − 3 | S ≤ d − 3 |
| no larvae | none between d − 9 and d − 3 | S ≤ d − 9 (if that is still ≥ the lower bound) |
| no capped brood | none between d − 21 and d − 9 | S ≤ d − 21 (likewise) |

The last egg is somewhere between the largest lower bound and the smallest upper bound. With weekly inspections that's usually a window of 3 to 5 days.

**The first queen out wins.** Several queen cells of different ages are normal, and the first virgin to emerge kills the rest. Each cell observation gives a window for *its* queen's emergence:
- an open cell: 8 to 16 days on;
- a capped cell: 0 to 8 days;
- a hatched cell or a virgin: already out.

The first emergence is the earliest of the lower bounds, and the earliest of the upper bounds. New eggs also cap it, since a queen can't lay until about 10 days after emerging.

**Absence is information.** "No eggs" on a day after the earliest possible laying date moves the window for her first eggs later, because none were laid before that look. If the last egg-free look is already past the latest date (28 days after emerging), the new queen has failed. That's when to add a test frame of eggs: queen cells on it mean the colony is queenless.

**The broodless gap.** All the old brood is out 21 days after the last egg, and the new queen's first brood is capped 9 days after her first egg. Between the two there is no capped worker brood, so varroa mites have nowhere to hide and a single oxalic acid treatment reaches nearly all of them. The window's start uses the *latest* possible last egg, and its end the *earliest* possible first new egg, so the gap Queenline reports is one the colony really has.

**Testing against a simulated hive.** The strongest test doesn't use examples. It simulates 150 colonies:
- each queen lays daily until a random day S;
- a swarm cell started 6 days earlier gives a new queen on S + 10;
- she lays from 10 to 28 days later;
- an inspector looks every 5 to 9 days and writes down exactly what's there.

Every window Queenline infers must contain the true day, and on every day of its broodless gap the simulation must have no capped brood. This test caught an off-by-one: the new queen's first brood is capped on day 9, so the gap ends on day 8.

**Bash features used:**
- `set -euo pipefail`, arrays indexed per inspection, and integer arithmetic for day numbers;
- `[[ =~ ]]` for strict patterns, `case` for words, and parameter expansion for trimming;
- `read -r -a` to split words;
- here-strings, `head -c` for bounded reading, and `mktemp` in the tests;
- shellcheck directives to explain the two places a warning is intended.

## 4. Interview questions you might get

**Q: How do you combine many imprecise observations into one answer?**
A: Each observation is a constraint on an unknown day: "after this", or "not after that". The answer is the intersection of the constraints, a window [max of lower bounds, min of upper bounds]. Two subtleties:
- an absence constraint only applies if it doesn't contradict the presence evidence, so the upper bounds are filtered by the lower bound;
- for "first of several queens to emerge", the right combination is the minimum of each bound, not the intersection, because different cells have different ages.

When the constraints conflict, the report says so instead of inventing a date.

**Q: Why test with a simulation instead of real logs?**
A: Real logs don't come with the true dates, so they can't show a window is right, only that it looks plausible. A simulation knows the truth. It generates the exact observations a careful beekeeper would make and checks that every inferred window contains that truth, across 150 random colonies and inspection schedules. That property is what matters to a beekeeper: if Queenline says "broodless from the 9th to the 16th", it must be true.

**Q: Bash is a risky language for parsing untrusted text. How did you keep it safe?**
A: By never treating data as code:
- no `eval`, and every expansion is quoted;
- input is matched with `[[ =~ ]]` against fixed patterns, or `case` against a fixed word list, before it's used;
- dates reach `date` only after passing a strict pattern, and they're checked by round trip;
- reading is bounded with `head -c`, and control and invisible characters are rejected up front;
- shellcheck runs on everything.

The tests feed in `$(touch SECRET)` and check nothing runs and nothing is echoed.

## 5. Ideas to extend it

- **Temperature-aware timing:** development stretches in a cool hive. Take daily temperatures for the apiary and widen the windows accordingly.
- **Many hives, one apiary:** read a folder of logs and give a weekly plan. Which hives to leave alone (mating), which to treat (broodless), and which to give a test frame, with frames of eggs taken from the strongest colony.
- **Several episodes:** split a season's log at each requeening and report each episode, not just the latest.
