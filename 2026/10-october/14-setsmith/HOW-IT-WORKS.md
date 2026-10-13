# How Setsmith works

A walkthrough so you can explain every part of it.

## 1. The big picture

```
 gig.txt ──▶ Parse()            slot, habits, players, songs; strict and bounded
                │ check()       segues exist, no loops, one opener and one closer
                ▼
            tables()            changeover seconds between every pair of songs,
                │               which pairs may follow each other, music time of every subset
                ▼
            Solve()             dynamic programming over (songs played, last song, hard run)
                │               then the best finish that plays every must
                ▼
            Score()             the chosen order in full: start times, changes, costs
                │
                ▼
            Render()            running order, changeover notes, what was left out, energy arc
```

## 2. File tour

| File | Job |
|---|---|
| `setlist/gig.go` | The gig file format: settings, players, songs. Validation, limits and contradictions |
| `setlist/plan.go` | Changeover times, the target energy arc, the exact optimiser, and `Valid` and `Score` for checking any order |
| `setlist/report.go` | Turns a plan into the stage setlist with notes |
| `main.go` | Command line: bounded reading, safe file name, exit codes 0, 1 and 2 |
| `setlist/setlist_test.go`, `main_test.go` | 15 tests, including the brute-force comparison |

## 3. Key ideas

### What makes a set "good", as one number
Everything becomes points, with one point equal to one second of dead air:

| Cost | Points |
|---|---|
| Changeover between two songs | the slowest player's retune, capo or swap, in seconds |
| Energy | 20 × (song's energy − ideal energy at that moment)² |
| A `want` song left out | 600 (about ten minutes of tuning) |
| A `maybe` song left out | 60 |

Players change at the same time, so a changeover costs the **slowest** player's time, not the sum. A spare instrument turns a 90-second retune into a 15-second swap.

The ideal arc is a simple shape: open at 4, ease down to 2.8 just past halfway, then build to 5 at the end. Its x-axis is *music time*, the song's midpoint divided by the time available, so a long ballad sits where its middle lands.

### Why this is hard
A set is a choice of *which* songs and an *order*. With 12 songs, that's about 1.3 billion ordered selections, so trying them all isn't practical, and simple rules of thumb miss good orders.

### Dynamic programming over subsets
The key observation: once you know **which songs have been played**, **which was last**, and **how many hard songs in a row** you're on, the rest of the set doesn't care about the order before that.
- The next changeover depends only on the last song.
- The energy target for the next song depends only on how much music has been played, which is the subset's total length.
- The belt-limit depends only on the current run.

So `cost[subset][last][run]` = the cheapest way to have played exactly that subset, ending with `last`. Each state tries every unplayed song next. Subsets only grow, so visiting them in numeric order (bitmasks) means every state is final before it's used. That gives 2¹⁶ × 16 × (belt-limit + 1) states and about 16 moves each, a few seconds at most. The same DP technique solves the travelling salesman problem exactly for small sizes (Held-Karp).

At the end, every state that plays all the musts, ends on the closer and isn't mid-segue is a complete set. Add the cost of the songs left out and take the cheapest. Following the stored "came from" pointers backwards gives the order.

### The hard rules, built into the moves
- **Fits the time:** a move is only allowed if the subset's music plus gaps fits the slot minus the reserve. That's a property of the subset alone, so it's exact.
- **Opener / closer:** only the opener may start, and nothing may follow the closer.
- **Segues:** if A runs into B, A's only allowed successor is B and B's only allowed predecessor is A. If either is a must, both are.
- **Belt-limit:** a hard song increments the run and a gentler one resets it. Runs above the limit are never created.

### Trust, but verify
`Valid(order)` and `Score(order)` check and score *any* order, independently of the DP. The test generates 400 random gigs with random tunings, capos, spares, priorities, hard songs, openers, closers and segues. For each one it tries every order of every subset by brute force and checks that `Solve` finds exactly the same best score. It also checks that both agree when a gig is impossible.

## 4. Glossary

| Term | Plain version |
|---|---|
| Running order | The setlist: the songs in the order played |
| Segue | Going straight from one song into the next, with no gap |
| Drop D | Tuning the lowest guitar string down a tone, for heavier riffs |
| Capo | A clamp across the strings that raises a guitar's pitch without retuning |
| Dynamic programming | Solve a big problem by building it from saved answers to smaller ones |
| Bitmask | A number whose binary digits mark which songs are in a set |

### Go features you met here
- **Packages:** `setlist` holds the logic and `main` is a thin command line, so the logic is testable without a terminal.
- **Typed errors** (`*InputError`, `*NoPlanError`) checked with `errors.As`, so the CLI picks exit codes cleanly.
- **`math/bits`** (`OnesCount`, `TrailingZeros`) for fast subset work.
- **`bufio.Scanner` with a buffer limit**, and **`io.LimitReader`**, for bounded input.
- **Table-driven tests**, `t.TempDir()`, and `go test -race`.
- **Closures** (`idx`, `walk`), `iota` enums with a `String()` method, and the `min`/`max` built-ins from Go 1.21.

## 5. Interview questions you might get

**Q: Is the answer really optimal?**
A: Yes, for the scoring model. The DP state captures everything future costs depend on: the subset (which fixes the music time for the energy target and the time check), the last song (for the changeover) and the hard-song run. So keeping only the cheapest path to each state loses nothing. That's the principle of optimality. I didn't just argue it: a test compares the DP with brute force over every order on 400 random gigs, and they always agree.

**Q: How does it scale?**
A: Time and memory are about 2ⁿ × n × (belt-limit + 1) states with n moves each. For 16 songs that's around 5 million states, a few seconds and about 60 MB. Beyond that it grows exponentially, so the file format caps a gig at 16 songs, which is plenty for one set. For bigger lists, I'd use a heuristic like simulated annealing or a MIP solver, and lose the guarantee.

**Q: What would you change in the model?**
A: Two simplifications are documented. First, a player who sits out a song is assumed to retune meanwhile; to model it exactly, the state would need each player's current tuning, which would multiply the states. Second, the energy arc uses music time, not wall-clock time. Both trade a bit of realism for an exact, fast optimiser, and the report shows the real start times anyway.

## 6. Ideas to extend it

1. **Two sets with an interval:** split the list into two arcs, each with its own opener and closer.
2. **Key flow:** add a cost for awkward key jumps between songs, using the circle of fifths.
3. **Learn the energy:** estimate each song's energy from a recording's loudness and tempo instead of typing it in.
