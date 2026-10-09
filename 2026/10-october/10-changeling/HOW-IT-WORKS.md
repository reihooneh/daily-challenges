# How Changeling works

A walkthrough so you can explain every part of it.

## 1. The big picture

```
 stall file ──▶ Stall.parse()  prices, popularity, customers, how people pay
                     │
                     ▼
              Simulator  generates N days of customers ONCE, from a fixed seed
                     │   (what each buys, the cash total rounded to 5c, what they hand over)
                     ▼
      Planner.plan()  tries floats against those same customers:
                     │     greedy: add the coins/notes that fix the most stuck sales per dollar
                     │     exchanges: swap some of one coin for another while it helps
                     ▼
                Drawer.giveChange()  for every sale: biggest coin first, else exact search
                     │
                     ▼
     Main.report()  float in bank rolls · risk vs a typical float · price nudges
```

## 2. File tour

| File | Job |
|---|---|
| `Money.java` | Cents, Australian denominations, bank roll sizes, 5c cash rounding, formatting |
| `Stall.java` | The stall description and its strict parser |
| `Drawer.java` | The cash drawer: giving change, a fast "is it even possible?" check, and the exact fewest-coins search |
| `Simulator.java` | Generates the simulated days and plays a float through them |
| `Planner.java` | Searches for the best float within the budget |
| `Main.java` | Command line, safe file reading, the report and price nudges |
| `InputException.java` | One-line errors with a line number |
| `tests/changeling/Tests.java` | 81 checks with a tiny built-in test runner |

## 3. Key ideas

### Money is whole cents
`0.1 + 0.2` is not exactly `0.3` in floating point, and a cash tool that drifts by a cent is wrong. Every amount is a `long` number of cents. Australian cash totals are rounded to the nearest 5c (1c and 2c coins were withdrawn in 1992): `(cents + 2) / 5 * 5` rounds 1–2c down and 3–4c up.

### Common random numbers
To compare two floats fairly, they must face the *same* customers. The simulator generates all the days once, from a seed, and every float the planner tries is run against exactly those days. A difference in the result is then caused by the float, not by luck. Statisticians call this "common random numbers", and it is why the search can make fine decisions with only 100 simulated days.

### Giving change: greedy first, exact if needed
With a full drawer, biggest coin first is always right for Australian money. With a *limited* drawer it can fail: to give 60c from one 50c and three 20c, greedy takes the 50c and is stuck, but 20 + 20 + 20 works. So when greedy fails:

1. **Quick no:** if all the coins small enough to use don't add up to the change, give up immediately.
2. **Fast yes/no:** a bit set where bit *k* means "*k* × 5c can be made". Adding a coin shifts the set by its value and ORs it in, 64 amounts per machine word.
3. **Only then, fewest coins:** a bounded knapsack. Each coin's supply is split into bundles of 1, 2, 4, 8… so each bundle is a simple take-or-leave choice, and a table finds the combination with the fewest pieces.

The bit-set step made the whole program about four times faster, because most hard cases are impossible and never reach step 3.

### Searching for the float
There are far too many possible floats to try them all, so the planner searches:

- **Greedy by value for money:** try adding 1, 5 or 20 of each coin or note, and keep the move that removes the most stuck customers *per dollar*. Repeat until nothing helps or the budget is used.
- **Exchanges:** greedy can paint itself into a corner (the budget spent on one roll of $2s when a mix would be better), so it then tries handing back some of one coin and buying another with the money, keeping any exchange that helps.

The result sometimes includes 5c or 10c coins even when prices are in 50c steps. They are not useless: when the 50c coins run out, 20c + 20c + 10c still makes 50c, and the search only keeps them because they rescued real sales.

### Why price nudges work
Every sale that needs change uses coins, and only customers paying exact money bring coins back. A price of $4 paid with a $5 note needs a $1 coin; a price of $5 needs nothing. The nudge check tries the whole dollars either side of each best-selling item's price, re-plans the float, and reports a change only if it really helps.

## 4. Glossary

| Term | Plain version |
|---|---|
| Float | The cash you start the day with, so you can give change |
| Stuck customer | Someone you can't give the right change to, counted as a lost sale |
| Monte Carlo simulation | Answering "what usually happens?" by playing it out many times with random inputs |
| Common random numbers | Testing every option against the same random inputs, so comparisons are fair |
| Knapsack problem | Choosing items with values to hit a target or limit; here, coins to make an amount |
| Greedy algorithm | Always taking the best-looking next step |

### Java features you met here
- **Records** (`Item`, `Payment`, `Result`, `Nudge`) for small immutable data, and **enums** with **switch expressions**.
- **`SplittableRandom`** with a seed for fast, repeatable randomness.
- **Bit manipulation** on `long[]` for the reachability set.
- **`CharsetDecoder` with `CodingErrorAction.REPORT`** to refuse invalid UTF-8 instead of silently replacing it.
- **`InputStream.readNBytes(n)`** to read a bounded amount from a file or standard input.
- **`-Xlint:all -Werror`**: every compiler warning is treated as an error.

## 5. Interview questions you might get

**Q: Why simulate instead of using a formula?**
A: Whether you can give change depends on the order things happen: early customers paying with $50s can drain the drawer before anyone pays exact. A formula for average coin flow misses that. Simulation captures it directly, and common random numbers make comparisons between floats fair with a modest number of simulated days.

**Q: Isn't biggest-coin-first always right for real currencies?**
A: Only with an unlimited supply. With a limited drawer it can fail when a combination exists, for example 60c from one 50c and three 20c. I fall back to an exact bounded-knapsack search, with two cheap checks in front of it, and the tests compare it with brute force on 3,000 random drawers.

**Q: How do you know the search finds a good float?**
A: It is a heuristic, so I test it against alternatives: it must beat the typical even-split float, an empty float, and 40 random floats that spend the same budget. It also stays within budget, and step limits keep its running time bounded.

## 6. Ideas to extend it

1. **Card payments:** let a share of customers pay by card, which needs no change at all, and show how much a card reader shrinks the float.
2. **Time of day:** model a morning rush of $50 notes from the ATM, which drains change early.
3. **Other currencies:** load denominations and rounding rules from a small table (NZD, GBP, EUR).
