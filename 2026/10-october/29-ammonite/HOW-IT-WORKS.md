# How Ammonite works

A walkthrough so you can explain every part of it.

## 1. The big picture

```
 tank.txt ──▶ Tank::parse     fixed line forms, ranges, UTF-8 and hidden-character checks
                 │
                 ▼
             Planner          for each group in turn: earliest day that stays safe (a forward simulation)
                 │             no safe start? → dose ammonia daily (fishless cycle) until the first fish fit
                 ▼
             Model::run       the nitrogen cycle, 10 steps a day: ammonia → nitrite → nitrate,
                 │             two kinds of bacteria growing, water changes, free-ammonia share
                 ▼
             Report           the "all at once" warning, the plan, a week-by-week table
```

## 2. File tour

| File | Job |
|---|---|
| `bin/ammonite` | The executable: an autoloader that only knows its own classes, then `Cli::run` |
| `src/Cli.php` | Arguments, bounded reading from regular files only, exit codes |
| `src/Tank.php` | The tank file, fish groups, the waste estimate and the free-ammonia equation |
| `src/Model.php` | The nitrogen-cycle simulation |
| `src/Planner.php` | The stocking search and the fishless-cycle fallback |
| `src/Report.php` | The printed plan |
| `tests/run.php` | 95 checks in a tiny runner, so PHP is the only requirement |

## 3. Key ideas

### The nitrogen cycle as two predator–prey pairs
Fish give off ammonia. Ammonia-oxidising bacteria (AOB) eat it and make nitrite. Nitrite-oxidising bacteria (NOB) eat that and make nitrate. Each is a population growing on its food, so the model tracks five numbers: ammonia, nitrite, nitrate, AOB and NOB. Per step:

```
AOB eat     rA = (μA / YA) · AOB · TAN / (KA + TAN)
NOB eat     rN = (μN / YN) · NOB · NO2 / (KN + NO2) / (1 + free NH3 / 0.6)
TAN        += load − rA          NO2 += rA − rN          NO3 += rN
AOB        += YA · rA − decay · AOB                       (and the same for NOB)
```

The fraction `food / (K + food)` is **Monod kinetics**: bacteria eat at nearly full speed when food is plentiful and slow down as it runs short. μ (growth rate) rises 7% per °C and falls in acid water. The NOB term is divided by a free-ammonia factor, a known effect (Anthonisen, 1976) that makes fishless cycles stall when too much ammonia is dosed. A test checks it.

### Why the same ammonia is worse at pH 8
Ammonia in water is split between toxic NH3 and much less toxic NH4+. The share of NH3 follows the Emerson equation: `pKa = 0.09018 + 2729.92 / T(K)`, and `NH3 share = 1 / (1 + 10^(pKa − pH))`. At 25 °C that is 0.56% at pH 7 and 5.4% at pH 8, so the same test-kit reading is ten times as dangerous in hard, alkaline water. The limit is set on free ammonia, not on the total, for that reason.

### How much waste a fish makes
From length: weight ≈ 0.012 × length³ g, fed about 2% of that a day, at 45% protein, 16% nitrogen, with about half excreted as ammonia. A 3 cm neon gives about 0.23 mg/day and a 12 cm pleco about 15 mg/day. Because waste scales with length cubed, one big fish can out-pollute a whole school of small ones.

### Planning by forward simulation
For each group, in the order listed, try day d = (the previous group's day), d + 1, … and simulate the whole tank with the groups so far, watching for six weeks after. The first d where the fish never meet more than the limits is chosen. Earlier fish are protected too, because the check covers everyone in the tank. A test confirms each chosen day is really the earliest: one day sooner breaks the limits.

If even the first group can't go in safely within the window, the planner runs a **fishless cycle**. It doses ammonia equal to the full stock's daily output every day until the first group goes in, and finds the first safe day. Ammonia is only judged once fish are present, because no fish are harmed by a spike in an empty tank.

### Conservation as a test
With no water changes, every milligram of nitrogen that goes in must still be there as ammonia, nitrite or nitrate. The test suite checks this to a millionth of a milligram, which catches any slip in the update equations.

### PHP features you met here
- **`declare(strict_types=1)`**, readonly constructor-promoted properties, the `never` return type, and closures capturing by reference.
- **`preg_match('//u', …)`** to test for valid UTF-8, and Unicode ranges like `\x{202A}` in patterns.
- **Array-shape doc types** (`array{rows: list<…>}`) and integer-keyed arrays as a schedule (`day => [groups]`).
- **`php://memory` streams** in the tests to drive the command line without files.

## 4. Interview questions you might get

**Q: Why does the nitrite peak come after the ammonia peak?**
A: The nitrite eaters (NOB) can only grow once there is nitrite, and nitrite only appears once the ammonia eaters (AOB) have grown. So ammonia rises first, AOB catch up and turn it into nitrite, nitrite rises, then NOB catch up. The model reproduces the textbook curve without being told about it. A test checks the order of the peaks.

**Q: How do you know the plan is the earliest safe one?**
A: The search goes day by day from the earliest possible day, so the first safe day it finds is the earliest. The tests double-check by moving each placed group one day earlier and confirming the simulation then breaks a limit.

**Q: What would you change to make it trustworthy for a real fish shop?**
A: Calibrate the rates from real tank logs (fit μ, K and decay to test-kit readings), let users enter their kit readings so the model corrects itself as the tank cycles, and model feeding more directly. Until then it plans *when to test*, which is how the README presents it.

## 5. Ideas to extend it

1. **Learn from test results:** take daily kit readings and fit the bacteria's growth rates, so the forecast for this particular tank improves.
2. **Plants and nitrate:** model plants taking up ammonia and nitrate, so planted tanks cycle faster.
3. **Saltwater:** use the seawater ammonia equation and marine limits.
