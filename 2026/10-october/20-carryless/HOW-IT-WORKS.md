# How Carryless works

A walkthrough so you can explain every part of it.

## 1. The big picture

```
 league.txt ──▶ parse            teams, shared grounds; strict limits; odd league → add a "bye" team
                   │
                   ▼
                build            n a power of two?  ──yes──▶ Russell: perfect, from the field GF(2^k)
                   │                    no
                   ▼
                improve          simulated annealing from the circle method:
                   │             move whole rounds, or swap part of two rounds (a "partial round swap")
                   ▼
                assign           home/away: simulated annealing on match orientations,
                   │             minimising breaks, with shared-ground clashes heavily penalised
                   ▼
                report / CSV
```

## 2. File tour

| File | Job |
|---|---|
| `src/carryless/schedule.py` | Circle method, Russell's construction, carry-over counting, the search |
| `src/carryless/homeaway.py` | Venues, breaks, shared grounds and the home/away search |
| `src/carryless/cli.py` | League file parsing, report, CSV, safe file reading |
| `tests/test_carryless.py` | 17 tests: validity, perfect balance, search, home/away, bad input, CLI |

## 3. Key ideas

### A fixture is a 1-factorisation
With n teams (even), a round is a **perfect matching**: everyone plays exactly once. A full round robin splits all n(n−1)/2 pairings into n−1 such rounds; mathematicians call that a **1-factorisation** of the complete graph. In the code a round is a list `opp` where `opp[i]` is team i's opponent. `is_valid` checks that every round pairs everyone and every pairing happens exactly once, and the tests run it on everything Carryless produces.

### The carry-over effect
If team k plays i in round r and j in round r + 1, then i "carries over" to j: j meets k in whatever state i left it. Count, for every ordered pair (i, j), how many teams do this; the last round wraps round to the first, as in the standard definition. That gives an n × n matrix whose entries add up to n(n−1). The **carry-over effects value** is the sum of the squares of the entries. Squares punish concentration, so the smallest possible value, n(n−1), means every entry is exactly 1: perfectly even. The circle method makes some entries as large as n−3, which is where its huge scores come from (468 against an ideal of 90 for 10 teams).

### Russell's perfect fixture (powers of two)
For n = 2^k teams, number them as the elements of the finite field GF(2^k): bit patterns where addition is XOR and multiplication is polynomial multiplication reduced by a fixed *primitive polynomial*. Let g be a generator, so g⁰, g¹, …, g^(n−2) are all the non-zero elements. Round t pairs every team x with x + g^t.

Why is it perfect? If team k meets i in round t and j in round t+1, then i = k + g^t and j = k + g^(t+1), so j − i = g^t (g + 1). In a field you can divide, so g^t = (j − i)/(g + 1) fixes t, and then k = i − g^t is fixed too. Exactly one team carries over from i to j, for every pair. The code checks this for 4 up to 64 teams.

### Everything else: simulated annealing
For other sizes no perfect fixture is known in general, so Carryless searches. It starts from the circle method and makes random changes:
- **Swap two rounds:** the same matches, in a different order.
- **Partial round swap:** put two rounds' matches together and they form even cycles (alternating between the two rounds). Swapping which round one cycle's matches are played in gives a new valid fixture that isn't just a reordering.

A change that lowers the carry-over value is kept. A change that raises it is sometimes kept too, with probability e^(−increase/temperature), and the temperature falls over time. Accepting some bad moves early stops the search getting stuck in a local minimum. The seed makes it repeatable.

### Home and away
Each match then needs a home team. A **break** is two home or two away games in a row. With an even number of teams any round robin has at least n − 2 (only two "home, away, home…" patterns exist, so at most two teams can avoid breaks altogether). Carryless flips the home team of one match at a time, using simulated annealing again. A shared-ground clash costs as much as 1,000 breaks, so in practice there are none. For a fixed set of rounds, minimising breaks is closely related to the max-cut problem, so this is a search, not a guarantee.

### Python features you met here
- **Type hints** with `from __future__ import annotations`, including the alias `Round = list[int]`.
- **`random.Random(seed)`**: a private, seeded generator, so runs are repeatable and nothing else's randomness is affected.
- **`itertools.pairwise`** for consecutive rounds, **`unicodedata.category`** to find control characters in any script.
- **`csv.writer`** for correct quoting, plus a formula guard.
- **`unittest` and `subprocess`** to test the real command line with no extra packages.

## 4. Glossary

| Term | Plain version |
|---|---|
| Round robin | Everyone plays everyone once |
| Circle method | The usual way to draw one: fix a team, rotate the rest |
| Carry-over | Meeting an opponent straight after a particular other team did |
| Break | Two home (or two away) games in a row |
| 1-factorisation | Splitting all pairings into rounds where everyone plays once |
| Finite field GF(2^k) | A number system of 2^k elements where you can add, multiply and divide |
| Simulated annealing | Random search that sometimes accepts a worse step, less often over time |

## 5. Interview questions you might get

**Q: Why does relabelling the teams not help?**
A: Relabelling just permutes the rows and columns of the carry-over matrix, so the sum of squares stays the same. What changes the score is the *order* of the rounds and *which* matchings make up the rounds. That's why the moves are round swaps and partial round swaps.

**Q: How do you know your fixtures are valid?**
A: Every output goes through `is_valid`: n − 1 rounds, each a perfect matching with symmetric opponents, and every pair exactly once. Partial round swaps are tested 300 times in a row on a 12-team fixture and must stay valid after every swap. Russell's fixtures are checked to be perfectly balanced entry by entry.

**Q: Why not optimise carry-over and breaks together?**
A: You could, but they pull against each other: perfectly balanced fixtures tend to need more breaks. Doing it in two stages keeps each search simple and explainable, and the report shows both numbers so a league can judge the trade-off. A combined objective with a weight is the natural next step.

## 6. Ideas to extend it

1. **Double round robins:** mirror the first half with venues swapped, and include carry-over across the halfway point.
2. **Optimise both together:** one search with a weighted score for carry-over and breaks.
3. **More constraints:** unavailable grounds on certain dates, derbies on a chosen round, and no team starting with two away games.
