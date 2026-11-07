# How Loomfix works

Identifying a light is a matching problem with three unknowns. Loomfix doesn't know which light it is, when the watcher's stopwatch started within the light's period, or how fast the watcher's "seconds" ran. It treats each light in the list as a hypothesis, finds the best values for the other two unknowns, and compares the hypotheses by likelihood.

## 1. The big picture

```
"Fl(2) W 10s" ──parse──▶ Spec ──build──▶ edges in one period: (time, uncertainty, on/off)
                                               │
your taps ──watch──▶ times, on/off, colour,    │
                     watched-from/to           ▼
                               fit: for each scale on a grid
                                      for each way to line the first taps up with an edge
                                        pair taps with edges one-to-one, closest first
                                        score = Σ log-likelihoods (paired, stray, missed)
                                        slide by the weighted mean difference, rescore
                                      refine the scale near the best
                                               │
                               identify: best fit per light ─▶ softmax ─▶ ranked chances

audit: simulate a watcher on each light (random flash lengths, reaction time,
       counting error, missed flashes) ─▶ identify ─▶ count the mistakes
```

## 2. File tour

- **`src/pattern.rs`:** a small hand-written parser for chart abbreviations, with no regular expressions. It finds the class (`LFl` before `Fl`, and `Fl` before `F`), the group in brackets, an optional `+LFl`, then the colours and the period, separated by spaces or dots. A `Walk` then steps through one period, recording each edge with its uncertainty. Given a random number generator, the same walk draws random flash lengths, which is how the audit makes "real" lights.
- **`src/fit.rs`:** `score` pairs the taps with the edges for one line-up and returns a log-likelihood. `best_phase` searches line-ups at one scale, and `fit` searches scales. `identify` ranks the lights.
- **`src/audit.rs`:** `simulate` produces one watch exactly as the input file would hold it. `audit` identifies thousands of simulated watches, one thread per share of the lights. `longest_on` drives the "tell them apart by flash length" hint.
- **`src/input.rs`, `src/main.rs`:** strict parsing and bounded, link-refusing file reading.
- **`src/render.rs`:** the `##....##` strip, and your taps folded onto it using the fitted phase and scale.

## 3. Key ideas

**Uncertainty that grows along the period.** A chart says `Fl(2) 10s`: two flashes, period 10 s. The period is exact, but the flash length (about 0.5 s) and the gap in the group (about 1 s) are not on the chart. So the first flash is the anchor, with uncertainty 0. The second flash's start depends on one flash length and one gap, so its uncertainty is √(0.2² + 0.4²) ≈ 0.45 s. Each edge's spread adds the spreads of every assumed length before it, the same way independent errors add. When a tap is compared with an edge, the two spreads combine: σ² = (reaction time)² + (scale × edge spread)².

**Likelihood, not "count the flashes".** For one line-up:
- a tap paired with an edge scores a normal log-density, −½z² − ln σ − ln√(2π), plus ln(1 − p_miss);
- a tap with no edge within 4σ is a stray tap, at a fixed small log-density (−5);
- an edge inside the watched time with no tap is a missed flash, scoring ln(0.05);
- a prior on the scale (sd 2% for a stopwatch, 8% for counting) keeps the fit from stretching time freely.

The −ln σ term matters: without it, a vague model (large σ) would explain everything equally well. With it, a sharp prediction that comes true scores higher than a vague one.

**Searching phase and scale cheaply.** Trying every phase in fine steps would be slow, so Loomfix uses the data. A good line-up must put one of the first three taps on some edge of the same kind, so it tries each of those few alignments. After pairing, it slides the phase by the inverse-variance-weighted mean of the paired differences, which is the best shift for those pairs, and rescores. This is one step of the iterative-closest-point idea. Scale is searched on a grid of 41 values, then refined around the best. That cut a 12-light audit from 47 s to about 6 s on two cores.

**One-to-one pairing.** Every tap may claim at most one edge and vice versa, assigned closest first in units of σ. Without this, three quick taps could all "match" the same flash.

**Chances, honestly framed.** If each light in the list was equally likely beforehand, the chance of light i is exp(llᵢ) / Σ exp(llⱼ). The tool computes it with the largest ll subtracted first, so nothing overflows. These chances only compare lights in the list, so Loomfix also checks the best fit on its own terms. If it has stray taps or more than one missed flash in ten, it says that nothing fits well.

**The audit is a confusion matrix by Monte Carlo.** Each simulated watch:
- draws a real light (random flash lengths around the model);
- picks a random starting point and a counting error;
- adds reaction-time noise to each tap and drops some taps;
- then identifies the watch against the full list.

Counting how often light A comes out as B gives the off-diagonal entries of a confusion matrix. Each light gets its own seeded generator, so the report is the same whatever the number of threads.

**Rust features used:**
- enums with `match`, including slice patterns for command-line arguments and file lines (`["watched", a, "to", b]`);
- `Option::is_none_or`, `f64::total_cmp` for sorting floats, `rem_euclid` for folding times into a period, and `partition_point` for binary search in the sorted edge list;
- `std::thread::scope` to borrow the light list in worker threads without `Arc`;
- `Read::take` for bounded input, and `forbid(unsafe_code)`;
- integration tests run the real binary through `env!("CARGO_BIN_EXE_loomfix")`.

## 4. Interview questions you might get

**Q: Why does the likelihood include −ln σ? Isn't a z-score enough?**
A: z-scores alone reward vagueness. A model that says "the flash comes sometime in these 10 seconds" gives every tap a small z. The likelihood is a density, and a wide density is low everywhere: −ln σ is that cost. With it, two lights that both "fit" are compared on how sharply each predicted the taps, which is the right comparison. The same reasoning explains why Bayesian model comparison penalises flexible models.

**Q: How do you avoid searching every phase and every scale?**
A: Use the structure of the problem. In the best line-up, the first tap sits on some edge (or the second or third does, if the first was a stray). So there are only (3 × edges) phases worth starting from. From each start, the best small shift has a closed form, the weighted mean of the paired differences, so one update replaces a fine search. Only the scale is gridded, because it changes which taps pair with which edges. A coarse grid then a fine one costs about 58 evaluations per start.

**Q: The audit says two lights are confused 28% of the time. How would you check that number isn't an artefact?**
A: Several ways:
- **Rerun it:** with a different seed, and with more simulations. The binomial standard error at 200 watches is about 3%.
- **Check monotonicity:** with a stopwatch instead of counting, the confusion between periods 9 s and 10 s should drop, and it does (from 28% to 6%). The integration tests check the report repeats exactly for the same seed.
- **Check the simulator against the input format:** a unit test asserts every simulated watch is valid input with increasing times.
- **Hand-check a confused case:** I did this during development. Short watches that started mid-group were being matched to `Q(6)+LFl`, because a flash before the watcher started looking couldn't count as missed. Adding the optional "watched from/to" window fixed that, and the README now tells users to note it.

## 5. Ideas to extend it

- **Flash lengths as data:** let the watcher tap down and up (`on` and `off`) for every flash, and fit flash lengths as well as onsets. Lights that differ only in flash length could then be told apart.
- **A position fix:** take bearings to two or three identified lights and intersect them, with an error ellipse, to place the boat.
- **Sector lights:** model which colour is seen from which bearing, so the colour you see also tells you where you are.
