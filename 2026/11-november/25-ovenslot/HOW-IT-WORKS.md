# How Ovenslot works

## Architecture

```
ovenslot/plan.go       parsing and limits, time at temperature, phases, shelves, the search
ovenslot/plan_test.go  plan validity, a full search over random meals, hostile files, the largest meal
cmd/ovenslot/main.go   reading the file safely and printing the timetable
examples/              a Christmas lunch
```

## Key concepts

**Phases, not dishes.** An oven is at one temperature at a time, so a plan is a sequence of phases.
Every dish belongs to one phase, and the phase's temperature must be inside every member's range.
Fewer phases means fewer trips to the dial, so that is what the search minimises first.

**Working backwards.** The last phase ends at serving time (or earlier, if every dish in it needs a
rest). Each dish's latest out-time is serving time minus its minimum rest; its earliest is serving
time minus its maximum wait. The phase starts as late as all its dishes allow, and the one before
it must end early enough for the oven to heat or cool to the next temperature. Scheduling late
keeps food fresh and the oven off.

**Shelves.** Within a phase, dishes are placed least-flexible first. A dish's candidate out-times
are its own latest time and the moments other dishes go in, because those are the only moments
shelf space changes. A dish fits if, at every moment it's in, the space used stays within the
shelves.

**The search.** Dishes are split into k groups in every way (restricted growth strings, so no
grouping is tried twice), for k = 1 to 4, then every order of the groups, then for each group its
coolest, hottest and middle shared temperature. Ten dishes is the limit that keeps this to a few
million schedules.

## Language features worth noticing

- `json.Decoder.DisallowUnknownFields` and `dec.More()` make the parser strict in two lines.
- Recursive closures (`var walk func(i, used int)`) keep the search state local without a struct.
- `sort.SliceStable` with an order key puts same-minute events in kitchen order: things come out
  before the dial turns, and the dial turns before the next dish goes in.

## Interview questions

**1. Why minimise temperature changes before oven time?**
Every change is something the cook has to remember while doing five other things, and a missed
one ruins a dish. Oven time costs a little electricity. So the plan with two changes beats the one
with three even if it runs the oven 20 minutes longer; oven time only breaks ties, and freshness
breaks those.

**2. The search only tries three temperatures per group. Can it miss a plan?**
In principle, yes: a temperature in between could make the timing work when the extremes don't.
The tests run a full search over every 10 °C step on 60 random small meals and check that Best
always finds a plan with as few phases whenever one exists. Narrowing to three keeps the
ten-dish case fast; if the budget is still hit, the user is told.

**3. How would you let a dish change temperature halfway, like a roast that's seared hot and then
finished low?**
Split it into two linked pieces: the same shelf space, the second piece's in-time equal to the
first's out-time, and cooking progress carried across, so the time left at the second temperature
is (1 − done) × TimeAt(T2). The search then assigns the pieces to consecutive phases. The cost is a
bigger search, since a dish now spans groups, so I'd only split dishes that ask for it.
