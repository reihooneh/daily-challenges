# Ammonite

**Plans when to add fish to a new aquarium, so they never swim in toxic ammonia or nitrite. It simulates the bacteria growing in the filter, day by day, and schedules each group of fish for the earliest safe day, or a fishless cycle first if even the first fish wouldn't be safe.**

Language: PHP 8.4 (no dependencies) · Field: fishkeeping / microbial kinetics · Day: 29 October 2026

"New tank syndrome" kills more aquarium fish than anything else. A new filter has almost none of the bacteria that turn fish waste (ammonia) into nitrite and then into fairly harmless nitrate, and they take weeks to grow. Stocking calculators only say how many fish a tank can hold *eventually*. Ammonite answers the question a new fishkeeper actually has: **in what order, and on which days?**

- **Simulates the nitrogen cycle:** ammonia-eating and nitrite-eating bacteria grow on their food (Monod kinetics), faster when warm, slower in acid water. Free ammonia holds back the nitrite stage, which is why over-dosed fishless cycles stall.
- **Works out the toxic share:** how much of the ammonia is in the toxic un-ionised form (NH3) at your temperature and pH, using the Emerson equation. At pH 8 it is ten times what it is at pH 7.
- **Plans the stocking:** each group of fish, in the order you list them, on the earliest day that keeps every fish in the tank within the free ammonia and nitrite limits for the six weeks after.
- **Fishless cycle when needed:** if even the first fish wouldn't be safe, it plans a fishless cycle, dosing ammonia daily until the bacteria can cope, and says for how many days.
- **Your setup:** seeded filters (media from an established tank), weekly water changes, and your own limits.
- **Shows the trouble it avoids:** what would happen if every fish went in on day 0.

## Quick start

```bash
php bin/ammonite examples/community.txt
php tests/run.php            # 95 checks
```

```
AMMONITE  River community 90 L
90 L at 26 °C and pH 7.4: 1.5% of the ammonia is the toxic free form (NH3).
Limits: free ammonia 0.020 mg/L, nitrite 0.50 mg/L (as nitrogen). Filter: new.
The fish will give off about 0.39 mg/L of ammonia a day when all are in.

If every fish went in on day 0:
  free ammonia would reach 0.036 mg/L on day 6 (2 times the limit),
  nitrite would reach 3.9 mg/L on day 13 (8 times the limit).

Plan:
  Day 0   add 12 x Neon tetra (0.031 mg/L of ammonia a day)
  Day 23  add 6 x Cherry barb (0.072 mg/L of ammonia a day)
  Day 28  add 6 x Corydoras (0.12 mg/L of ammonia a day)
  Day 30  add 1 x Bristlenose pleco (0.17 mg/L of ammonia a day)
  With this plan the fish meet at most 0.004 mg/L free ammonia and 0.50 mg/L nitrite.

Week by week:
  Day    Fish Free NH3     Nitrite       Nitrate
  0        12 ..........  ..........     0.000
  14       12 ##........  ##........     0.003
  28       24 #.........  #######...      0.44
  ...
```

The same fish with a seeded filter (`examples/seeded.txt`) can all go in within five days. Five big goldfish in a new tub (`examples/goldfish.txt`) need a 25-day fishless cycle first.

## The tank file

```
tank River community 90 L
volume 90 L
temperature 26 C
ph 7.4
filter new                         # or: filter seeded 0.3  (mg/L of ammonia a day it already clears)
water-change 25% every 7 days      # optional
limits free-ammonia 0.02 nitrite 0.5   # optional, mg/L as nitrogen
fish Neon tetra x 12 length 3      # adult length in cm (waste is estimated from it)
fish Cherry shrimp x 20 waste 0.02 # or give the waste directly, mg of ammonia-nitrogen per animal per day
```

Exit codes: `0` plan printed, `2` bad usage or input. `-` reads standard input.

## Security

- **Bounded reading:** at most 32 KB, from regular files only. Paths containing a NUL byte are refused, and the path is never echoed.
- **Strict parsing:** every line has a fixed form. Numbers are plain decimals (no signs, exponents or `NAN`) within set ranges, and names use a small character set. The text must be valid UTF-8, and control characters (terminal escapes) and invisible direction or zero-width marks are refused.
- **No echo:** errors give a line number and never repeat the input.
- **Bounded work:** at most 20 groups of fish. The planner searches a fixed window of days, and the simulation has a fixed step, so a run takes well under a second.
- **No dangerous features:** `declare(strict_types=1)` everywhere, no `eval`, no shell, no network, no `include` of anything built from input, and an autoloader that only knows its own class names.

**Known limits:** this is a model with typical textbook rates for nitrifying bacteria. Real tanks vary with the filter, the plants, how much is fed and the water chemistry. It plans when to test, not whether to: always check ammonia and nitrite with a test kit before each addition, and never rely on it for fish health in an emergency.

See [HOW-IT-WORKS.md](HOW-IT-WORKS.md) for the walkthrough.
