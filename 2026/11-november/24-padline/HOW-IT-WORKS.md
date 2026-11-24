# How Padline works

## Architecture

```
src/padline.hpp   the problem, the risk grid and the plan
src/padline.cpp   parsing, the landing model, prefix sums, placing pads
src/main.cpp      reading the file safely, the report and the map
tests/            prefix sums, risk, placement against brute force, hostile input
```

## Key concepts

**A grid of risk.** The ground in front of the boulder becomes 10 cm cells. Each hold adds a
two-dimensional bell curve of landings: centred a little out from the wall (further from higher up),
wider the higher you are, and scaled by height^1.5 because impact energy and loss of control both
grow with height. The crux counts double and the top-out half again. Cells under a rock count four
times.

**Prefix sums.** Any rectangle's total risk is four lookups into a summed-area table, so trying a
pad in a spot costs O(1). That makes trying every spot for every pad cheap: a few thousand spots each.

**Placing the pads.** Biggest pad first into its best spot, then the next into the best spot that
doesn't overlap, and so on. Greedy alone can paint itself into a corner (the first pad takes the
middle and the next two can't both fit beside it), so two improvement moves repeat while they help:
lift one pad and re-place it; or lift two, try the first in each of its 300 best spots and the
second in its best spot after that, stopping as soon as the first's spots can't beat the current
pair even with the second's best possible spot.

## Language features worth noticing

- `std::from_chars` parses numbers without locales or exceptions.
- `std::optional` for "no spot fits" and for parse results.
- `std::partial_sort` keeps only the best 300 spots without sorting thousands.
- Structured bindings (`auto [gi, ci]`) in the pair search.

## Interview questions

**Why is this hard?** Covering the most weight with non-overlapping rectangles is a packing problem;
in general it's NP-hard. With a handful of pads, local search over a cheap objective gets very close,
and the tests measure how close against exhaustive search for two pads.

**Why prefix sums?** Without them, scoring a 1.2 x 1.0 m pad is 120 cell reads; with them it's four,
whatever the size. The pair search tries hundreds of thousands of spots, so that's the difference
between instant and slow.

**What's the bound in the pair search?** Spots for the first pad come best first. If the first pad's
gain plus the most the second pad could possibly cover (its best spot with the first pad out of the
way) can't beat the current pair, no later spot can either, so the loop stops.

## Extensions

1. Slopes: a downhill landing zone shifts and spreads falls further out.
2. A spotter as a movable "pad" that can cover a narrow zone at the crux only.
3. Read holds from a phone photo by tapping them.
