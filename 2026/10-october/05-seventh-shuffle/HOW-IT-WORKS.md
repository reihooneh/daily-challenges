# How Seventh Shuffle works

A friendly walkthrough so you can explain every part of it.

## 1. The big picture

```
 deck order (text) ──▶ Deck.parse ──▶ a permutation (validated)
                                            │
                              count rising sequences (r)
                                            │
            for k = 0..20:  how likely is an order with r rising
            sequences after k shuffles, compared with pure chance?
                                            │
                        most likely k  +  strength of evidence
                                            ▼
                                   Verdict ──▶ report + exit code
```

## 2. The one idea everything rests on: rising sequences

Take a new deck: 1, 2, 3, ... 52. Cut it and riffle the halves together. The cards from each half **stay in their original order**, they are just interleaved. So the deck now contains two "threads": if you look for card 1, then 2, then 3 without going backwards, you get through one half before you have to start again from the top.

Each of those threads is a **rising sequence**. A new deck has 1. One riffle gives at most 2, two riffles at most 4, three at most 8: each shuffle can at most double the count. A properly random 52-card deck averages 26.5.

That is the fingerprint. A deck with 8 rising sequences has almost certainly had only three shuffles.

## 3. File tour

| File | Job |
|---|---|
| `Deck.java` | Reads a deck from text and checks it is a complete set |
| `Riffle.java` | The mathematics: rising sequences, likelihoods, distance from random |
| `Shuffler.java` | Simulates a human riffle shuffle |
| `Verdict.java` | Combines the numbers into a conclusion and a readable report |
| `Main.java` | Command line: `check`, `deal`, `table` |
| `tests/seventh/Tests.java` | 27 tests with a tiny built-in runner |

### `Riffle.java`: the formula
Bayer and Diaconis proved that after `k` riffle shuffles of `n` cards, the chance of ending up in one particular order depends *only* on its number of rising sequences `r`:

```
P = C(2^k + n - r, n) / 2^(k·n)          C(a, b) means "a choose b"
```

- **`likelihoodRatio`** divides that by the chance in a perfectly shuffled deck (`1/n!`). A ratio of 1 means "no evidence either way"; a ratio of 10^20 means the order practically shouts "three shuffles".
- **`mostLikelyShuffles`** tries every `k` from 0 to 20 and keeps the best. That is **maximum likelihood estimation**.
- **`distanceFromRandom`** computes **total variation distance**: how far the whole distribution is from uniform. Summing over all 52! orders is impossible, but orders with the same `r` are equally likely, so it sums over `r` = 1..52 and multiplies by how many orders have that `r`. Those counts are the **Eulerian numbers**, built with a simple recurrence.

### `Shuffler.java`: the Gilbert-Shannon-Reeds model
Cut the deck by flipping a coin for each card (so cuts near the middle are most common), then drop cards from the two halves, choosing a half with probability proportional to how many cards it still holds. Studies of real shufflers found this simple model fits well.

### `Verdict.java`: when to accuse
The deck is called under-shuffled only if the evidence ratio is at least 20 to 1. A lower threshold catches more lazy shuffles but accuses more innocent decks. The README table shows the trade-off that results.

### `Deck.java` and `Main.java`
`Deck.parse` is the only code that touches raw input, and it hands back a clean array. `Main.run` takes its input and output streams as parameters, so tests can run the whole command line in memory.

## 4. Key concepts

| Concept | Plain version |
|---|---|
| Permutation | One particular ordering of a set of things |
| Rising sequence | A thread of consecutive cards that survived shuffling in order |
| Likelihood | How probable the evidence is, under a given explanation |
| Maximum likelihood | Pick the explanation that makes the evidence most probable |
| Total variation distance | 0 to 1: how different two probability distributions are |
| Cutoff phenomenon | Mixing that barely progresses, then happens almost all at once |
| CSPRNG | A random generator that can't be predicted (`SecureRandom`) |
| False positive | Flagging a deck that was actually fine |

### Java features you met here
- **`BigInteger` / `BigDecimal`**: numbers with as many digits as needed. `long` overflows past about 9 × 10^18; 52! is about 8 × 10^67.
- **`final` classes with private constructors**: utility classes that can't be instantiated or extended.
- **Checked exceptions** (`InputException`): the compiler forces callers to handle bad input.
- **Switch expressions with arrows** (`case "check" -> ...`): no fall-through bugs.
- **`RandomGenerator` interface**: the shuffler accepts either `SecureRandom` or a seeded `Random` without caring which. This is programming to an interface.
- **Lambdas and a functional interface** (`Check`) in the test runner.
- **try-with-resources**: files are closed automatically, even on error.
- **`-Xlint:all -Werror`**: every compiler warning is a build failure.

## 5. Interview questions you might get

**Q: How can you tell how many times a deck was shuffled from just its order?**
A: A riffle shuffle interleaves two halves without reordering either, so it can at most double the number of rising sequences. I count them, then use the Bayer-Diaconis formula to get the probability of that count after each possible number of shuffles and choose the most likely one. I compare it with the probability under a uniform shuffle to say how strong the evidence is.

**Q: Why BigInteger instead of double?**
A: The quantities are ratios of astronomically large numbers, like binomials of 2^20 choose 52 against 52 factorial. Doubles would overflow or lose all precision in the subtraction inside the distance calculation. With big integers every step is exact, and I only round once, at the end. A test checks that the probabilities of all orders add up to exactly 1, which would be impossible to assert with floating point.

**Q: Why two different random generators?**
A: By default I use `SecureRandom`, because a predictable shuffle is a broken shuffle. But tests and demos need repeatable results, so a seed switches to a seeded generator. The shuffler depends only on the `RandomGenerator` interface, so the choice is made in one place, and the documentation says a seeded deal must not be used for a real game.

## 6. Ideas to extend it yourself

1. **Other shuffles:** model the overhand shuffle and show how much slower it mixes (it needs thousands of passes).
2. **Unknown starting order:** accept a "before" and "after" deck and analyse the permutation between them.
3. **A confidence range:** report every shuffle count that is plausible, not just the single most likely one.
