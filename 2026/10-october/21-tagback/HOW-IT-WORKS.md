# How Tagback works

A walkthrough so you can explain every part of it.

## 1. The big picture

```
 survey.txt ──▶ parseSurvey         strict line-by-line reading, tags → sessions
                     │
                     ▼
                tally               per session: C caught, R already marked, M marked at large
                     │
        ┌────────────┼──────────────────────┐
        ▼            ▼                      ▼
     chapman      schnabel             schumacher
   (2 sessions)  (all sessions)     (straight-line fit = closure check)
        └────────────┼──────────────────────┘
                     ▼
            captureFrequencies      times each animal was caught vs equal catchability
                     │              (Poisson-binomial + chi-square) → Chao if it fails
                     ▼
              render / toJSON       table, estimates, checks, a plan for next time
```

## 2. File tour

| File | Job |
|---|---|
| `src/survey.js` | The file format, every limit, and the per-session counts |
| `src/estimate.js` | Chapman, Schnabel, Schumacher-Eschmeyer, Chao, the planner, and the maths helpers (chi-square, gamma) |
| `src/checks.js` | The catchability check |
| `src/report.js` | Puts it together and prints it |
| `bin/tagback.js` | Safe file reading and the command-line options |
| `tests/tagback.test.js` | 32 tests: textbook values, simulations with a known population, bad input, the CLI |

## 3. Key ideas

### The Lincoln-Petersen idea
Mark M animals. Later catch C, of which R are marked. If marks are spread evenly, R/C ≈ M/N, so N ≈ M·C/R. That simple ratio is biased upwards when R is small, so Tagback uses **Chapman's** version, N = (M+1)(C+1)/(R+1) − 1, which is close to unbiased once R ≥ 7. Its interval is built on the log scale (Chao 1987), so it never goes below the animals you actually saw and stretches further upwards than downwards, as the real uncertainty does.

### Many sessions: Schnabel and Schumacher-Eschmeyer
With several sessions, each one is another ratio. **Schnabel** pools them: N = ΣC·M / (ΣR + 1). The recaptures ΣR behave like a Poisson count, so when there are fewer than 50 the interval uses the exact Poisson limits (from the chi-square distribution), and otherwise a normal approximation for 1/N.

**Schumacher-Eschmeyer** looks at the same data as a graph: plot the marked share of each catch (R/C) against the number marked so far (M). If the population is closed it's a straight line through the origin with slope 1/N. A weighted regression gives N, and how well the points fit the line (the "fit", a weighted R²) is a check: animals arriving, leaving or losing marks bend the line.

### Equal catchability, and how to test it
If every animal has the same chance pₜ of being caught in session t, the number of times one animal is caught follows a **Poisson-binomial** distribution, computed exactly by a small dynamic programme (add one session at a time; each probability splits into "caught" and "not caught"). Tagback compares how many animals were caught once, twice, or three or more times with what that predicts, using a chi-square statistic. A value above 5.99 (the 95% point with 2 degrees of freedom) fails the check.

Mixed catchability leaves a U shape: too many animals seen once (the shy ones) and too many seen often (the trap-happy ones). The classic estimators then come out too low, because the trap-happy animals keep being "recaptured" and make the marked share look high.

### Chao's lower bound
Animals seen only once (f₁) hint at others never seen at all; animals seen twice (f₂) tell you how quickly the "seen once" group is shrinking. Chao's estimate is S + f₁²/(2f₂), here in its bias-corrected form S + f₁(f₁−1)/(2(f₂+1)). It holds up under uneven catchability, and is best read as a lower bound. In the tests, a simulated population of 300 with trap-happy animals gives a Schnabel estimate around 150, and Chao's is much closer.

### Planning the next survey
With a rough N, marking k and catching k gives about k²/N recaptures. Tagback puts that into Chapman's variance and finds the smallest k whose 95% interval is within ±10% or ±20% of N. It's a guide, not a promise.

### The maths helpers
The chi-square quantile is found by bisection on the regularised incomplete gamma function (a series for small x, a continued fraction for large x), and ln Γ uses the Lanczos approximation. Tests check them against printed tables.

### JavaScript features you met here
- **ES modules** (`import` / `export`) and top-level `await` in the CLI.
- **JSDoc types checked by TypeScript** (`tsc --checkJs --strict`): type safety without a build step.
- **Unicode property escapes** in regular expressions (`\p{L}`, `\p{Cc}`) to accept letters from any language but refuse control characters.
- **`TextDecoder` with `fatal: true`** to reject invalid UTF-8 instead of silently replacing it.
- **`node:test`** and a seeded random generator, so simulation tests give the same result every run.

## 4. Glossary

| Term | Plain version |
|---|---|
| Mark-recapture | Catch, mark, release, catch again, and use the marked share to estimate the total |
| Closed population | Nobody is born, dies, arrives or leaves during the survey |
| Trap-happy / trap-shy | Animals that are more / less likely to be caught than others |
| Recapture | Catching an animal that is already marked |
| 95% interval | A range built so that, over many surveys, it contains the true number 95% of the time |
| Poisson-binomial | The number of successes when each trial has its own probability |

## 5. Interview questions you might get

**Q: Why doesn't the simple M·C/R estimate work well?**
A: It's biased upwards when recaptures are few, and infinite with none. Chapman's adjustment adds one to each count, which makes it nearly unbiased once there are about seven recaptures. Tagback warns when there are fewer.

**Q: How do you know your intervals are right?**
A: By simulation. The tests generate populations of a known size, run the full pipeline 300 times and check that the 95% intervals contain the true value more than 90% of the time, and that the average estimate is within 5% of the truth.

**Q: What breaks these estimates in real life, and what did you do about it?**
A: Unequal catchability and an open population. The Schumacher fit flags open populations; the capture-frequency test flags unequal catchability and then reports Chao's estimate, which is robust to it. Simulations confirm both: the heterogeneity test fires on trap-happy data and stays quiet (at most 15 in 100) on fair data.

## 6. Ideas to extend it

1. **Open populations:** the Jolly-Seber model estimates births and deaths between sessions.
2. **Model selection:** fit the Otis models (M0, Mt, Mb, Mh) by maximum likelihood and compare them by AIC.
3. **Trap locations:** spatial capture-recapture, using where each animal was caught.
