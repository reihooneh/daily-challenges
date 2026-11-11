# How Saltrind works

## 1. Architecture

```
plan.txt ──parsePlan──▶ Plan { brine litres, %, °C, restore; wheels[] }
                              │
                       Brine::make (salt and water in grams)
                              │
                 brineAll: for each batch, in order
                   ├─ Profile(wheel): 40 rings × 20 layers of salt-in-moisture
                   ├─ hour by hour: Profile::step in brine → salt out of the brine, water in
                   ├─ last hour bisected: the minute the average reaches the target
                   ├─ resting: Profile::step sealed until the centre reaches 90 % of the average
                   └─ top the brine back up (if restore)
                              │
                       report: summary, two cut-wheel maps, the average over time
```

## 2. File tour

- **`src/model.hpp`, `src/model.cpp`:**
  - `Wheel` (size, moisture, count, target) and `Brine` (salt and water by mass, with strength, top-up and the surface concentration);
  - `diffusivity`: the diffusion coefficient for a temperature and moisture;
  - `Profile`: the grid, the explicit finite-volume step and its stability limit;
  - `brineAll`: the batches one after another, sharing one brine.
- **`src/parse.hpp`, `src/parse.cpp`:** the plan format: strict numbers, ranges, the 64 KB and 20-batch limits, and errors that never repeat input.
- **`src/report.hpp`, `src/report.cpp`:** the text report, the cut-wheel shading and the chart.
- **`src/main.cpp`:** the command line: plain files only, size check, then parse, model and report.
- **`tests/tests.cpp`:** 11 test groups, 52 checks, built with sanitizers.

## 3. Key concepts, simply

**Salt-in-moisture.** Salt only dissolves in a cheese's water, so cheesemakers measure salt as a percentage of the water, not of the whole cheese. Gouda aims for about 4.5 %. A gram of salt in a wet cheese is less "salty" than in a dry one. Saltrind works in this unit throughout.

**Why a cylinder only needs a slice.** A wheel looks the same from every side, so the salt only depends on the distance from the centre (r) and the height (z). That turns a 3D problem into a 2D one: rings stacked in layers. The top and bottom halves mirror each other, so only the top half is modelled, with no salt crossing the middle.

**Finite volumes.** Each cell is a ring of cheese. Every step, salt flows across each face it shares with a neighbour, in proportion to the face's area and the difference in concentration (Fick's law). The cell's new concentration is its old one plus what flowed in, over its volume. Because each face's flow leaves one cell and enters the other, salt is conserved exactly. Rings further out have bigger faces and volumes, which is how the cylinder's geometry gets in.

**The time step.** This is an explicit scheme: each new value comes from the old ones. It's simple but only stable if no cell can lose more than it has in one step. `maxStep` adds up each cell's outflow coefficients and keeps the step under 0.9 of that limit. A test pushes a high diffusion coefficient on a fine grid and checks no cell ever overshoots.

**The rind.** In brine, a cheese's surface dries and tightens, and water flowing out works against the salt coming in. So salt goes in more slowly than diffusion alone predicts. Saltrind puts a resistance at the face, in series with the half cell between the face and the cell's centre, like two resistors. Its value is set to match common brining times.

**The brine as a tank.** The brine starts with a known mass of salt and water. Whatever salt the wheels take leaves it; 1.6 g of water per gram of salt joins it from the cheese. Its strength, and so the concentration at every cheese face, drops batch by batch.

## 4. Trade-offs

- **Explicit, not implicit:** an implicit scheme (Crank–Nicolson, say) allows bigger steps, but needs a sparse solve every step. At 800 cells the explicit one takes milliseconds per batch, is easy to read, and conserves salt exactly.
- **Fixed grid:** 40 × 20 cells is fine enough to be within 2 % of a grid four times as fine, and keeps the worst case bounded.
- **One fitted number:** the rind conductance is fitted to two well-known brining times, rather than modelling the rind physically (two phases, shrinkage). That's honest about what's known, and the README says so.

## 5. Interview questions

**Q: How do you know the diffusion code is right?**
A: Against the exact answer. For a finite cylinder with its faces at a fixed concentration, the uptake still to come is the product of an infinite cylinder's (a series over the roots of the Bessel function J0) and a slab's (a series in odd multiples of π). The test runs the model with no rind on a fine grid and compares the average at four times, within 1 %. A second test checks that doubling the grid in each direction changes the answer by under 2 %.

**Q: Why is there a bisection in the brining loop?**
A: The loop steps an hour at a time, so it overshoots the target by up to an hour. When an hour overshoots, it restores the saved profile and brine, bisects that hour for the moment the average crosses the target (30 halvings is far below a second), then steps exactly that far. The brine is only charged for the salt actually taken.

**Q: What stops the explicit scheme blowing up?**
A: The step limit. Each cell's new value is a weighted average of itself and its neighbours as long as the outflow weights add up to less than one. `maxStep` computes the largest sum on the grid (the outer cells, with the half-cell faces to the brine, are the worst) and uses 90 % of the allowed step. A test checks the maximum principle: no cell goes above the brine or below the starting salt.

**Q: How do you keep a hostile plan file from doing damage?**
A: The tool only reads, so the risks are resource use and terminal tricks. It refuses anything that isn't a plain file (links, folders, devices) and anything over 64 KB, parses numbers strictly with `from_chars` and range checks, limits batches, and caps the simulated time, so the worst case finishes. Error messages name the line and setting but never echo the value, so escape codes in a file can't reach the terminal.

## 6. Extension ideas

- **Dry salting and floating:** a top face out of the brine (with salt sprinkled on it), turned partway through.
- **Shrinkage:** let the wheel lose water as it brines, so its moisture and size change.
- **Fit the rind from your own cheese:** weigh a wheel before and after brining, and fit the rind conductance to it.
