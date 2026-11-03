# How Rungwise works

A walkthrough so you can explain every part of it.

## 1. The big picture

```
 policy.txt ──▶ policy.rb   ladder (worst → best), premium, excess, accident chance, repair bills
                   │
                   ▼
               model.rb    Markov decision process, solved backwards:
                   │       value[years left][level] and threshold[years left][level]
                   ▼
               report.rb   threshold table, best rule vs simple rules, bonus protection
```

## 2. File tour

| File | Job |
|---|---|
| `lib/rungwise/policy.rb` | The file format, numbers with `$` and `%`, the ladder and its claim rules |
| `lib/rungwise/model.rb` | Log-normal repair bills (closed-form expectations, sampling) and the dynamic programme |
| `lib/rungwise/report.rb` | The printed table and comparisons |
| `bin/rungwise` | Bounded, link-free reading and exit codes |
| `test/test_rungwise.rb` | 12 tests: the distribution, optimality, a simulation check, hostile input, the command line |

## 3. Key ideas

### The decision as a Markov decision process
The state is your rung on the ladder and the years left. Each year:
1. You pay the premium for your rung.
2. With chance p you have an at-fault accident with repair bill D. You choose:
   - **pay it yourself:** cost D, and next year you move one rung up;
   - **claim:** cost the excess, and next year you're on the claim's rung.
3. With no accident, you move one rung up.

Let V[t][l] be the expected cost of the next t years starting on rung l, playing well, with future money discounted by β = 1/(1 + interest). Then

```
claim  ⇔  D > excess + β · (V[t−1][after claim] − V[t−1][one rung up])
```

The right-hand side is the **threshold**: the excess plus what the drop down the ladder will cost you from then on. One subtraction gives the whole decision.

### Solving backwards
V[0][·] = 0 (the policy has ended). From V[t−1] you get every threshold for year t, then V[t] from the expected cost of one year. This is backward induction (Bellman's equation). It takes O(years × levels) steps, instant even for 30 years and 30 levels.

### Log-normal bills in closed form
Repair bills are skewed: lots of small dents, a few huge write-offs. A log-normal distribution with median m and spread σ (the standard deviation of ln D) captures that. The DP needs E[min(D, T)], what you'd pay yourself if you claim everything over T:

```
E[min(D, T)] = e^(μ + σ²/2) · Φ((ln T − μ − σ²)/σ) + T · (1 − Φ((ln T − μ)/σ))
```

where μ = ln m and Φ is the standard normal CDF (`Math.erf` in Ruby). It's exact, so the comparisons between rules aren't blurred by simulation noise. The tests check it against numerical integration.

### Checking the answer three ways
- **Optimality:** the best rule's cost equals evaluating its own thresholds, and no random threshold table (or "always claim", or "never claim") ever does better.
- **Simulation:** simulating 60,000 drivers following the thresholds agrees with the exact expected cost within 2%.
- **Sanity:** in the last year the threshold is the excess, a flat ladder gives the excess every year, and protection never costs more before its price.

### Ruby features you met here
- **`Struct` with `keyword_init`** for plain records, and **endless methods** (`def up(level) = ...`) for one-liners.
- **Blocks as strategies:** `cost_of_rule { |level, years_left| threshold }` evaluates any claiming rule with the same code.
- **`Math.erf`** for the normal CDF, and **`Open3.capture3`** in the tests to run the command line as a user would.

## 4. Interview questions you might get

**Q: Why isn't the threshold just "the extra premium next year"?**
A: Because a claim's cost runs on. Dropping two rungs costs higher premiums for several years while you climb back, and another accident on the way makes it worse. The DP carries all of that in V[t−1][after claim] − V[t−1][one rung up]. In the example that's $1,840 on top of the excess, far more than one year's premium rise.

**Q: Why do the thresholds shrink as the years run out?**
A: The penalty for claiming is future discount lost. With fewer years left there's less of it, and in the final year there's none, so you claim anything over the excess. That's a neat check that the backward induction is right.

**Q: How would you handle two accidents in a year?**
A: Replace "accident or not" with a Poisson number of accidents. Within a year, decide claims one at a time, where the state also counts claims made so far this year (since each one moves the landing rung). The value recursion is the same idea with a slightly bigger state.

## 5. Ideas to extend it

1. **Poisson accidents and repricing:** several accidents a year, and base premiums that rise with inflation or age.
2. **Learning your accident rate:** update the accident chance from your own history with a Beta prior, instead of a single guess.
3. **Compare policies:** run two insurers' ladders side by side to see which is cheaper for your driving over five years.
