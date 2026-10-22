# How Crosscue works

A walkthrough so you can explain every part of it.

## 1. The big picture

```
 show.txt ──▶ Parser         fixed line forms, ranges, sizes → Show and Formations
                 │
                 ▼  for each change (formation k → k+1), with everyone where change k−1 left them
             Assignment      1. bottleneck: smallest possible longest walk (binary search + matching)
                 │           2. Hungarian: least total walking among those
                 ▼
             Paths           exact closest approach for every pair → near-misses
                 │           → retime dancers (wait, or arrive early) within their pace
                 ▼
             Report          run sheet per change, warnings, a map of the new formation
```

## 2. File tour

| File | Job |
|---|---|
| `lib/crosscue/parser.rb` | The show file: line forms, ranges, places-versus-dancers checks |
| `lib/crosscue/assignment.rb` | Bottleneck assignment, Kuhn's matching, the Hungarian algorithm |
| `lib/crosscue/paths.rb` | Moves, exact closest approach, near-misses, retiming |
| `lib/crosscue/planner.rb` | Runs each change and carries positions forward |
| `lib/crosscue/report.rb` | The run sheet and the stage map |
| `bin/crosscue` | Safe file reading and exit codes |
| `test/test_crosscue.rb` | 13 tests, 745 assertions, including brute-force checks |

## 3. Key ideas

### Two goals, in order
A change has to fit its counts, and the dancer with the furthest to go decides whether it does. So the first goal is the **bottleneck**: make the longest walk as short as possible. Many assignments usually share that best longest walk; among them we want the least walking in total (less rushing, fewer crossings). That's a lexicographic objective, solved in two stages.

### Stage 1: bottleneck assignment by binary search
Sort all the dancer-to-spot distances. For a threshold T, ask whether every dancer can get a different spot using only walks of length T or less. That is a bipartite matching question, answered with **Kuhn's algorithm** (repeated augmenting paths). The answer flips from "no" to "yes" exactly once as T grows, so binary search over the sorted distances finds the smallest T that works in O(log n²) matchings.

### Stage 2: the Hungarian algorithm
Forbid every walk longer than T (infinite cost), then find the minimum-total assignment. The Hungarian algorithm keeps a "potential" for each row and column and grows an optimal matching one row at a time along shortest augmenting paths, in O(n³). Pinned dancers are handled the same way: every pairing except their own spot is forbidden.

The tests check both stages against **brute force over every permutation** on 60 random cases, some with pins.

### Exact closest approach
Each dancer stands still, then walks a straight line at a steady speed, then stands still. Between the moments when either dancer starts or stops, the gap vector between them changes linearly, so the squared distance is a quadratic in time. Its minimum has a closed form, clamped to the interval. Checking each interval gives the exact closest approach. A test compares it with sampling every 0.001 counts.

A pair only counts as a near-miss if they come closer than `space` *and* closer than where they start and end. Partners dancing side by side aren't flagged.

### Fixing near-misses with timing
For a dancer in a near-miss, try waiting k counts before going, or arriving k counts early, for k = 1, 2, …, but only while the walk still fits at the dancer's pace. Keep the smallest change that clears the dancer's near-misses without creating new ones. If none clears it, keep the change that leaves the most room and try the other dancer next round. Two dancers on crossing paths can need both: one waits, the other hurries.

### Ruby features you met here
- **`Struct` with `keyword_init`** for small data types (`Show`, `Formation`, `Move`) with readable construction.
- **`Array#permutation`, `#combination`, `#each_cons`** for brute-force tests, every pair of dancers, and consecutive time marks.
- **`Integer#fdiv`**: a bug the tests caught was `-32 / 64 == 0` in integer division. `fdiv` always divides as floating point.
- **`File.lstat` and `File::NOFOLLOW`** to check what a path is, then open it without following links.
- **`String#valid_encoding?`** and Unicode property regexes (`\p{Lu}`, `\p{Cc}`) for strict text checks.

## 4. Interview questions you might get

**Q: Why not just minimise the total distance?**
A: Because the change has to fit the music, and the slowest dancer decides that. A minimum-total assignment can leave one dancer with a very long walk to save everyone else a little. So I minimise the maximum first (the bottleneck assignment), then the total among the assignments that achieve that maximum.

**Q: How does the binary search find the bottleneck, and why is it correct?**
A: Feasibility is monotone: if everyone can be matched using walks of at most T, they still can with any larger T. So I binary-search over the sorted distinct distances, testing each threshold with a bipartite matching (augmenting paths). The smallest feasible threshold is the optimum, because the optimum's longest walk is one of those distances.

**Q: How do you know two dancers won't collide?**
A: Their motion is piecewise linear in time, so between the breakpoints where either starts or stops, the squared distance between them is a quadratic with a closed-form minimum. I check every interval, which gives the exact minimum distance rather than a sampled approximation. The tests confirm it against very fine sampling.

## 5. Ideas to extend it

1. **Curved and waypoint paths:** let dancers route around each other, or follow a travelling pattern, instead of only changing timing.
2. **Whole-piece optimisation:** choose assignments for all changes together, so nobody gets stuck with the long walk every time.
3. **Export:** draw each change as an SVG animation that rehearsals can follow count by count.
