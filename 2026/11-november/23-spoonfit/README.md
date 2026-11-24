# Spoonfit

**Scale a recipe, then measure it with the spoons and cups you actually own, in the fewest scoops.**

Halve an American recipe in an Australian kitchen and you get "0.625 cups" and "half a US
tablespoon", measured with an Australian tablespoon that holds 20 ml, not 15. Spoonfit scales each
line, converts it from the recipe's units, and finds the fewest scoops from your own measuring kit
that land within a tolerance: "1/3 cup + 2 tbsp", or "1 tbsp, less 1 tsp" when scooping one back out
saves a scoop.

## Features

- Reads amounts like `2 1/4 cups`, `3 tbsp`, `1/2 tsp`, `15 ml`; passes eggs and pinches through.
- US, Australian and UK spoons and cups (an Australian tablespoon is 20 ml).
- Your own kit (`--kit "1 cup, 1/3 cup, 1 tbsp, 1 tsp"`) or a standard one for your region.
- Tighter tolerance (2 %) for leaveners, salt and yeast; 5 % for everything else.
- The fewest scoops by dynamic programming over volume (checked against a brute force), then the
  smallest error, with "less one scoop" when it helps.

## Example

```
$ java -cp build/classes spoonfit.Main examples/brownies.txt --scale 1.5
Scaled by 1.5, from US measures, with your AU kit (8 measures).

  sugar                          443.6 ml  1 cup + 1/2 cup + 1/4 cup              -1.4%
  butter, melted                 177.4 ml  1/2 cup + 1/4 cup, less 1 tsp          +2.9%
  cocoa powder                   266.2 ml  1 cup + 1 tbsp                         +1.4%
  plain flour                    177.4 ml  1/2 cup + 1/4 cup, less 1 tsp          +2.9%
  baking powder                    1.8 ml  1/4 tsp                                -32.4%  (closest your kit can do)
  salt                             1.8 ml  1/4 tsp                                -32.4%  (closest your kit can do)
  vanilla extract                 14.8 ml  1 tbsp, less 1 tsp                     +1.4%
  2 large eggs                 (not a volume: scale by hand)
```

The Australian kit has no 1/8 teaspoon, so the leaveners can't be measured closely; Spoonfit says so
rather than pretending.

## Build and test

```sh
make            # javac with -Xlint:all -Werror
make run        # the example above
make test       # 2,593 checks, no JUnit needed
```

Java 21, standard library only.

## Security

- The recipe must be a regular file (symlinks not followed) under 32 KB of valid UTF-8, with at
  most 200 lines of at most 200 characters; control characters are refused, so a recipe can't put
  terminal escape sequences in the output.
- Amounts are parsed with a strict pattern, fractions must be proper, and every number is bounded
  (amounts up to 5 litres, a scale of 0.05 to 20, a kit of 1 to 16 measures), which also bounds the
  dynamic programme's size.
- No dependencies, no reflection, no deserialisation.
- Known limits: cups of flour vary with how you fill them; for baking by weight, weigh.
