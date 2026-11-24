# How Spoonfit works

## Architecture

```
src/spoonfit/Measures.java  regions, units, reading recipe lines and kits
src/spoonfit/Planner.java   the fewest-scoops dynamic programme and the search within tolerance
src/spoonfit/Main.java      options, reading the file safely, the report
tests/spoonfit/Tests.java   parsing, brute-force checks, plans, end to end, hostile input
```

## Key concepts

**Units differ by country.** A US tablespoon is 14.79 ml, an Australian one 20 ml, a UK one 15 ml;
a US cup is 236.6 ml, the others 250. Each recipe line is converted to millilitres in the recipe's
region, scaled, then matched against measures in your kit's region.

**Coin change on a grid.** Volumes become whole numbers of 0.01 ml. `best[v]` is the fewest scoops
that add to exactly `v`: `best[v] = 1 + min over measures m of best[v - size(m)]`, with `best[0] = 0`.
That's the unbounded coin-change recurrence, and it fills 200,001 entries for up to 2 litres. The
test checks it against trying every combination of counts.

**Within tolerance.** Every exact total between `target x (1 - tol)` and `target x (1 + tol)` is a
candidate; the answer has the fewest scoops, then the smallest error.

**Taking one out.** For each candidate total `v` and each measure `m`, `best[v + m] + 1` scoops reach
`v` by filling to `v + m` and removing `m`. That's how "1 tbsp, less 1 tsp" beats "3 tsp".

## Language features worth noticing

- Records (`Measure`, `Line`, `Plan`, `Scoop`) for immutable data with no boilerplate.
- An enum with fields (`Region`) holding each country's sizes.
- Switch expressions with multiple labels for unit names.
- A strict UTF-8 decoder (`CodingErrorAction.REPORT`) instead of silently replacing bad bytes.

## Interview questions

**Why dynamic programming rather than greedy (largest measure first)?** Greedy fails for measures
that don't divide each other: with 1/3 cup and 1/4 cup, greedy takes 1/3 cup first and can miss
"2 x 1/4 cup" for half a cup. The DP is exact for any kit.

**Why a 0.01 ml grid instead of exact fractions?** Measures like a US tablespoon aren't nice
fractions of a millilitre. At 0.01 ml the rounding is far below what a spoon can measure, and the
array stays small (200,001 ints).

**How would you add weights?** A density table (flour about 0.53 g/ml when spooned, sugar 0.85), so
grams convert to volume and back, with a warning that density depends on how you fill the cup.

## Extensions

1. Densities, so "200 g sugar" becomes cups and spoons.
2. Round the scale itself: suggest 1.4x instead of 1.5x if it makes every line exact.
3. A tiny web page with the kit as tappable chips.
