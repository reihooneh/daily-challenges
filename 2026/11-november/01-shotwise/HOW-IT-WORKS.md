# How Shotwise works

A walkthrough so you can explain every part of it.

## 1. The big picture

```
 shots.txt ──▶ parse.py    fixed line patterns → shots, people, times, weights, first/last
                  │
                  ▼
              plan.py      ≤ 16 shots: dynamic programme over subsets (proven best)
                  │        > 16, or impossible times: greedy start + one-shot moves
                  ▼
              report.py    call sheet: start time, who's in it, call in, free to go
```

## 2. File tour

| File | Job |
|---|---|
| `src/shotwise/parse.py` | The shot-list format, name rules and limits |
| `src/shotwise/plan.py` | Waiting and constraint checks, the exact search and the local search |
| `src/shotwise/report.py` | The printed call sheet |
| `src/shotwise/cli.py` | Bounded reading and exit codes |
| `tests/test_shotwise.py` | 14 tests: waiting, constraints, every-permutation checks, hostile input and the command line |

## 3. Key ideas

### The cost of an order
A person must be there from the start of their first shot to the end of their last. Their **waiting** is that span minus the time they're actually in shots. Shotwise minimises the weighted sum over everyone. Film producers know this as the **talent scheduling problem**: actors are paid from the first day they're needed until the last, so the shooting order should keep those spans short. It is NP-hard, so no fast algorithm is known for big instances.

### Why a subset DP is exact
Picture the moment a shot `s` is taken, after a set `S` of shots is done. Who is standing around waiting? Exactly the people who:
- were in some shot in `S` (they've arrived),
- are in some shot not yet taken (they can't leave), and
- are not in `s`.

That depends only on **which** shots are in `S`, not the order they were taken in. So `best[S ∪ {s}] = min(best[S] + length(s) × weight(waiting people))`, filled in for all 2^n sets. Each person-set is a bitmask: "in some shot in S" is an OR of the shots' masks, built for every S from S with its lowest bit removed. Arrival and leaving times fit in too, because the start time of `s` is just the total length of the shots in `S`. With 16 shots that's 65,536 sets and about a million transitions, instead of 16! ≈ 2×10^13 orders.

### When the DP can't be used
For more than 16 shots, or when no order meets every arrival and leaving time, the plan comes from local search:
1. **Greedy:** build the order one shot at a time, picking the shot that keeps the score lowest.
2. **Move one shot:** take any shot out and put it anywhere else. Keep the first move that helps, and repeat until none does or the budget runs out.

The score adds 10,000 for every minute a time limit is missed, so meeting the limits comes first and waiting second. When limits can't all be met, the report lists what the closest order misses.

### Python features you met here
- **Integers as bitsets:** `mask & -mask` isolates the lowest set bit, `bit_length()` gives its index, and `&`, `|`, `^` combine sets of people.
- **`dataclasses`** for plain records, and `str.removeprefix` to drop a byte-order mark.
- **`unicodedata.category`** to refuse control (`Cc`) and invisible format (`Cf`) characters.
- **`itertools.permutations`** as the independent brute force in the tests.

## 4. Interview questions you might get

**Q: Why doesn't the order inside S matter for the next step's cost?**
A: The people waiting during shot `s` are those who have started (in a shot in S), aren't finished (in a shot outside S ∪ {s}) and aren't in `s`. Each of those is a set condition, so any order of S gives the same waiting during `s`. Optimal substructure follows: the best way to finish depends only on S, which is what makes the DP correct.

**Q: How do you know the DP is right?**
A: The tests compare it with brute force over every permutation on 150 random small lists, with random weights, arrival and leaving times and first/last pins, including lists where no order works. Both must agree on the least waiting, and on when no order exists.

**Q: Why the "first improvement" rule in the local search?**
A: Scanning every move and taking the best is O(n²) evaluations per step. Taking the first move that helps is usually faster and reaches a similar local minimum. A fixed evaluation budget keeps the worst case bounded either way.

## 5. Ideas to extend it

1. **Gathering time:** add a minute whenever more than a few people have to be called in, so a big change between shots costs something.
2. **Two photographers:** split the list between two cameras taking shots at the same time, with nobody in two places at once.
3. **A printable call sheet:** a one-page HTML version for the second shooter or the usher calling names.
