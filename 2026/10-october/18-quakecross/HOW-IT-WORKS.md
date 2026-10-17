# How Quakecross works

A walkthrough so you can explain every part of it.

## 1. The big picture

```
 picks.txt ──▶ parse          stations, P and S times, wave speeds, depth: all strictly checked
                  │
                  ▼
             Problem::new     flat map in km around the stations; times across midnight joined up
                  │
                  ▼
             grid search      try a 61 × 61 grid of places (and 5 depths if depth is free);
                  │           for each, the best origin time is just an average
                  ▼
             Levenberg–       refine the best grid point: Gauss–Newton steps on (x, y, [depth,] t0),
             Marquardt        damped whenever a step would make the fit worse
                  │
                  ▼
             find_outliers    leave each pick out in turn; if the rest suddenly fit far better and
                  │           that pick is far off, flag it and repeat (up to 3)
                  ▼
             report           location, 90% ellipse from the covariance, azimuthal gap, residuals
```

## 2. File tour

| File | Job |
|---|---|
| `src/parse.rs` | The pick file format and every limit |
| `src/locate.rs` | The map projection, the solver, the error ellipse, the gap and the outlier search |
| `src/report.rs` | The text report |
| `src/main.rs` | The command line: safe, size-limited reading |
| `tests/quakecross.rs` | Synthetic quakes with known answers, maths checks, bad input and the CLI |

## 3. Key ideas

### The model
In a uniform Earth, a wave leaving the focus at `(x, y, depth)` at time `t0` reaches a station at distance `r` at

```
arrival = t0 + r / v        where r = √((x − xs)² + (y − ys)² + depth²)
```

with `v` = 6.0 km/s for P waves and 3.5 km/s for S waves by default. Every pick gives one equation, and there are 3 unknowns (or 4 with depth). More picks than unknowns means we can't fit them all exactly, so we look for the best compromise: the place and time that make the **sum of squared misfits** smallest (least squares).

### Why a grid search first
The misfit isn't a simple bowl. From a poor starting guess, the standard method can slide into the wrong valley, especially when the quake is outside the network. So Quakecross first tries a 61 × 61 grid of places spanning the network plus 150 km. For any fixed place the best origin time has a closed form (the average of "arrival minus travel time"), so each grid point costs one pass over the picks.

### Gauss–Newton and Levenberg–Marquardt
Near the answer, each arrival time is almost a straight-line function of the unknowns. The **Jacobian** J holds how much each predicted arrival changes when x, y, depth or t0 change; for x it's `(x − xs) / (r·v)`. Solving the **normal equations** `JᵀJ · step = Jᵀ · misfits` gives the step that best reduces the misfit, and repeating converges in a few steps (that's Geiger's method, used since 1910). **Levenberg–Marquardt** adds a damping term `λ·diag(JᵀJ)`: big λ means small, careful steps; small λ means full Gauss–Newton. λ shrinks after a good step and grows after a bad one, which makes it robust. The 3×3 or 4×4 systems are solved with Gaussian elimination with partial pivoting.

### How sure is the location?
At the answer, `(JᵀJ)⁻¹ · σ²` is the **covariance** of the unknowns, where σ² is the pick error (estimated from the misfit, but never below 0.1 s, about the precision of a careful hand pick). The x/y block is a 2×2 matrix; its eigenvectors give the directions of an ellipse and its eigenvalues the variances along them. 90% of a two-dimensional normal distribution lies within √4.605 standard deviations, which gives the **90% error ellipse**. Ellipses are usually long in the direction where the stations are sparse.

### The azimuthal gap
Seen from the epicentre, sort the directions to every station and find the biggest angle with no station in it. Under 180° the stations surround the quake; over 180° it's outside the network, and distance and origin time trade off against each other, so the location is much weaker. Agencies report this number with every quake.

### Finding the pick that doesn't fit
With least squares, one bad pick pulls the whole answer towards it, so its own misfit can look smaller than it really is and the blame spreads onto good picks. Quakecross instead **leaves each pick out in turn** and relocates from the current answer. If, without one pick, the others fit much better (RMS at least halves) and that pick is far off (more than 4 times the others' RMS and over 0.5 s), it's flagged and the search repeats, up to three picks. Leaving out the pick, rather than looking at its residual, is the key idea: it measures what the pick does to everyone else.

### Rust features you met here
- **`Result<T, String>` and `?`** for errors that carry a line number, with no panics on bad input.
- **Iterators** (`map`, `fold`, `min_by`, `windows`, `zip`) for the maths, and `f64::total_cmp` to sort floats safely.
- **`let … else`** to stop the solver cleanly when a system is singular.
- **`#![forbid(unsafe_code)]`** through `[lints.rust]` in Cargo.toml.
- **Integration tests** that run the real binary with `env!("CARGO_BIN_EXE_quakecross")`.

## 4. Glossary

| Term | Plain version |
|---|---|
| P wave / S wave | The first, faster wave (pushes) and the slower one (shakes sideways) |
| Pick | The time someone (or software) marks a wave's arrival on a recording |
| Epicentre / hypocentre | The point on the surface above the quake / the quake's point underground |
| Origin time | When the quake started |
| Residual | Observed minus predicted arrival time |
| RMS | Root mean square of the residuals: a typical misfit |
| Azimuthal gap | The biggest direction, seen from the quake, with no station |

## 5. Interview questions you might get

**Q: Why not just solve the equations directly?**
A: They're nonlinear (there's a square root in the distance), there are more equations than unknowns, and the data has errors. So it's a nonlinear least-squares problem. A grid search gives a safe starting point, and Levenberg–Marquardt refines it quickly. Gauss–Newton alone can diverge from a poor start; the damping makes each step safe.

**Q: How do you find a bad measurement when least squares hides it?**
A: A bad pick drags the solution towards itself, so its own residual shrinks and good picks get blamed. Leave-one-out avoids that: for each pick, relocate without it and see how well the rest fit. A big improvement plus a big misfit for the left-out pick identifies it. It costs one extra solve per pick, which is cheap here because each solve starts from the current answer.

**Q: Where would this model go wrong?**
A: The Earth isn't uniform: waves speed up with depth, so distant stations see "head waves" that arrive earlier than a uniform model predicts, and the error ellipse assumes the model is right. The flat map adds error beyond a few hundred kilometres. The next steps would be a layered velocity model and station corrections.

## 6. Ideas to extend it

1. **A layered Earth:** travel times through flat layers, including head waves, as real local networks use.
2. **Magnitude:** add peak amplitudes per station and compute a local magnitude (Richter's ML).
3. **A browser demo:** compile to WebAssembly and draw the stations, the ellipse and the bad pick on a map.
