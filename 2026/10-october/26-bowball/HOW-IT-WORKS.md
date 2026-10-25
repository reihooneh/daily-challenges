# How Bowball works

A walkthrough so you can explain every part of it.

## 1. The big picture

```
 session.txt ──▶ parse.go      fixed line forms, ranges, UTF-8 checks → Session { rowers, pieces, boats }
                     │
                     ▼
                  fit.go       one linear model for every boat time → speeds, hulls, noise, covariance
                     │
                     ▼
               selection.go    Select (exact, side-aware) · Chances (20,000 draws) · CutPairs
                     │         NextSwaps: Sherman–Morrison update per candidate swap
                     ▼
                 report.go     tables per side, close calls, advice, odd results
```

## 2. File tour

| File | Job |
|---|---|
| `cmd/bowball/main.go` | Three lines: hands the arguments and streams to `Run` |
| `internal/bowball/run.go` | Bounded reading, regular files only, exit codes |
| `internal/bowball/session.go` | Types: rowers, sides, boats, pieces, the error type |
| `internal/bowball/parse.go` | The file format, limits, and text-safety checks |
| `internal/bowball/linalg.go` | Small dense linear algebra: Gauss–Jordan inverse, Cholesky, normal CDF |
| `internal/bowball/fit.go` | The model and its estimation |
| `internal/bowball/selection.go` | Choosing the boat, selection chances, close calls, next-swap advice |
| `internal/bowball/report.go` | The printed report |
| `internal/bowball/bowball_test.go` | 13 tests, including a refit check of the swap formula and a fuzz test |

## 3. Key ideas

### One model for every boat time
Times are scaled to seconds per 1000 m. For boat *b* in piece *p*:

```
time = piece_p + hull_b − Σ (speed of each rower in the boat) + noise
```

The **piece** term absorbs everything shared by the boats in that piece (wind, stream, tiredness), so only differences within a piece carry information. The **hull** term absorbs a quicker or slower boat. Fitting all pieces at once means information chains through. If Ava swapped with Eve, and Eve later swapped with Dee, Ava and Dee are compared too, and the errors add up correctly.

### Why a little Bayesian prior
After one piece, nobody can be told apart from their crew-mates: the design matrix is **rank-deficient**. Plain least squares would fail. Bowball adds weak normal priors: speeds sd 5 s and hulls sd 3 s per 1000 m, far wider than real differences. This is penalised least squares, or equally the posterior mean. It always has a unique answer, the data swamp the prior as soon as there are swaps, and a rower who hasn't been compared keeps a huge standard error. The report then shows "?" instead of a fake number.

### Noise from the data
Noise is estimated as `σ² = (RSS + ν₀σ₀²) / (spare + ν₀)`. The spare degrees of freedom are the number of times minus the **trace of the hat matrix**, which is how many parameters the data actually pinned down. The guess σ₀ from the file counts as ν₀ = 2 pieces' worth of evidence. With few pieces the answer leans on the guess, and the report says so.

### Chance of a seat
The speeds' uncertainty is a multivariate normal with the fitted covariance. Bowball takes its **Cholesky factor**, draws 20,000 sets of speeds, picks the boat from each, and counts. Picking is exact even with `either` rowers: the either-siders used are always the fastest ones, so it only searches how many go to each side, which takes O(seats²) per draw. The chances add up to exactly the number of seats, and a test checks that.

### Which swap next: experimental design
A wrong call at the selection line is a pair (one in, one out, same side) whose true order is reversed. The probability is `Φ(−Δ / sd)`. Summed over pairs, that gives the **expected number of wrong calls**. For each legal swap, Bowball predicts how the covariance would shrink after one more piece, without knowing its result. The new piece's level cancels in the margin between the two boats, leaving one observation with variance 2σ². The covariance then updates by the **Sherman–Morrison** rank-one formula:

```
Σ' = Σ − (Σd)(Σd)ᵀ / (2σ² + dᵀΣd)
```

Here d says which speeds and hulls the new margin depends on. That's one matrix-vector product per candidate instead of a refit, and a test checks it against a real refit to 10⁻⁶. A second test shows that following the advice settles a simulated selection faster than random swaps.

### Go features you met here
- **`internal/` packages:** the code can't be imported from outside the module; `cmd/` holds the thin binary.
- **`Run(args, stdin, stdout, stderr) int`:** the command line as a testable function.
- **`io.LimitReader`** for bounded input; `os.Stat` + `Mode().IsRegular()` to refuse devices and folders.
- **`math/rand/v2` with a PCG seed** for repeatable simulation.
- **Native fuzzing** (`func FuzzParse(f *testing.F)`) and the race detector (`go test -race`).
- **`regexp`** with anchored patterns for every number, so `strconv` never sees `NaN`, `Inf` or `1e9`.

## 4. Interview questions you might get

**Q: Why not just average each rower's swap margins, like a spreadsheet?**
A: Margins from different swaps share pieces, hulls and crew-mates, so they aren't independent, and averaging double-counts some evidence and ignores the rest. A single linear model with piece and hull effects uses every time once, links rowers who never swapped directly, and gives honest standard errors from the covariance matrix.

**Q: How do you know the swap advice is computed correctly?**
A: The prediction uses Sherman–Morrison on the covariance, which doesn't depend on the times, only on the design. The test builds the hypothetical extra piece as a real session, refits with the noise held fixed, and checks that every pairwise standard error matches the prediction to 10⁻⁶. A separate simulation test shows that advised swaps leave fewer expected wrong calls than random legal swaps.

**Q: What stops a hostile file from causing harm?**
A: The reader takes at most 64 KB, and only from regular files. Every line has a fixed form, and every number matches an anchored pattern and a range, so nothing like `NaN` or `1e308` reaches the maths. Names are restricted, and control and direction characters are refused. Hard caps bound the matrix size and the simulation work. Errors never echo the input. A fuzz test drives random files through the parser and the full report.

## 5. Ideas to extend it

1. **Crew interactions:** add pairwise "these two row well together" terms, with a strong prior so they appear only when the data insist.
2. **Plan a whole session:** search a sequence of swaps (not just the next one) for the fewest pieces to reach a target certainty.
3. **Ergometer scores as a prior:** start each rower's speed from their 2k erg score instead of zero, so day-one advice is sharper.
