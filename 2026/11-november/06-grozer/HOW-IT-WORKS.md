# How Grozer works

Grozer turns a glass cutter's rules into geometry, and then searches for the smallest change to a design that obeys them. This file covers the design, the algorithms, the TypeScript features used, and the questions an interviewer might ask.

## 1. The big picture

```
design file ──parse──▶ pieces (outlines made counter-clockwise, checked to be simple)
                          │
                          ├─ problems(): inside corners, deep inside curves  ──▶ must be fixed
                          ├─ warnings(): sharp points, slivers                ──▶ worth knowing
                          │
                          ├─ fix(): iterative deepening on the number of lead lines
                          │     solve(shape, limit):
                          │       no problems? done
                          │       otherwise try each line through the FIRST problem:
                          │         split → both parts still sensible? → solve each part
                          │       keep the plan with the fewest lines, then the least lead
                          │
                          └─ render() text report   or   svg() drawing
```

## 2. File tour

- **`geometry.ts`:** small, pure functions:
  - `cross` (twice the signed area of a triangle) underlies orientation, area, turning and segment tests;
  - `hull` is Andrew's monotone chain;
  - `width` uses the fact that a convex shape is narrowest square to one of its edges;
  - `rayHit` intersects a ray with every edge.
- **`parse.ts`:**
  - the file format, colour table and limits;
  - outlines are normalised to counter-clockwise, so "turns right" always means "inside corner".
- **`check.ts`:**
  - `problems()` and `warnings()` hold the cutting rules;
  - `candidates()` generates lead lines;
  - `split()` cuts an outline along a chord;
  - `fix()` is the search, with memoisation and a node budget.
- **`report.ts`:** groups problems into readable sentences and draws the SVG. The design's y runs up and SVG's runs down, so y is flipped.
- **`cli.ts`:**
  - bounded reading with `O_NOFOLLOW` and a strict UTF-8 decoder;
  - `main` takes its output functions as parameters, so tests drive it without a subprocess.

## 3. Key ideas

**Turning angle tells inside from outside.** Walk round a counter-clockwise outline. At each vertex the path turns left (a convex corner) or right (a reflex, inside corner). `turn()` gets the signed angle from `atan2(cross, dot)` of the two edge vectors. An inside corner is any right turn sharper than `sharp-corner`.

**Curves are measured against the convex hull.** Stretch a rubber band round the piece: that's the convex hull. Wherever the outline leaves the band, it dips inward, and that stretch is an inside curve. Its *mouth* is the hull edge across it, and its *depth* is the furthest point from that edge. A shallow scallop (depth/mouth 0.14 in the example) can be nibbled out with relief scores. A crescent (0.41) can't.

**Why branching on one corner is enough.** A lead line only changes the angle at the vertices it touches. So an inside corner stays an inside corner, in one of the parts, unless some line goes *through* it. Every valid plan therefore contains a line through the first problem corner, and the search only needs to try those lines. The two parts are then solved independently, and the best plan for each combines into the best plan for the whole. This keeps the branching factor to roughly the number of vertices instead of the number of possible chords.

**Iterative deepening finds the fewest lines.** `solve(shape, limit)` is a depth-limited search. Running it with limit 0, 1, 2 ... returns at the first limit that works, which is the minimum number of lines. Within that limit it keeps the plan with the least total lead. Memoising on (outline, limit) stops it re-solving parts it has seen through another order of cuts. A node budget turns a hostile outline (a 20-tooth comb, say) into a quick "too complex" instead of a hang.

**Testing a search by re-applying its answer.** The strongest test doesn't trust the search at all. It takes each plan's lines and replays them on the original piece with its own code: find the part each line's midpoint lies in, add the endpoints as vertices, split. It then checks that every final part has no problems and no sliver. This runs over 150 random skyline-shaped pieces, along with a lower bound: there must be at least half as many lines as inside corners, since one line touches at most two.

**TypeScript features used:**
- **A discriminated union:** `Problem` is a `corner` or a `curve`, and the compiler makes every use check which.
- **Indexed-access checks:** `noUncheckedIndexedAccess` makes every array read possibly `undefined`, which matters in geometry code full of `pts[i + 1]`.
- **`readonly` points**, so nothing mutates a piece behind the search's back.
- **ES modules with `NodeNext` resolution**, and the built-in `node:test` runner, so there are no runtime or test dependencies.

## 4. Interview questions you might get

**Q: What's the complexity of the search, and how do you keep it in bounds?**
A: In the worst case it's exponential: each level tries up to about *n* lines, to a depth of *k* lines. Three things keep it small in practice:
- branching only on lines through the first problem;
- memoising sub-shapes;
- iterative deepening, which never explores deeper than the answer.

For safety there are hard caps: 80 points per piece, at most 8 lines, and a 60,000-node budget per piece. The budget is a correctness feature as much as a speed one: the tool always answers.

**Q: How do you test geometric code where floating point can bite?**
A: Several ways:
- every comparison has an explicit epsilon, and a ray hit near an existing vertex snaps to it (within 0.5 mm);
- the tests use exact cases with known answers (an L must take the 40 mm line, not the 50 or 70 mm ones);
- property tests replay random plans independently;
- a random-input test checks that only `InputError` ever escapes.

**Q: Why normalise outlines to counter-clockwise?**
A: So one rule works everywhere: a right turn is an inside corner. Without it, every function would need to know the orientation, and a clockwise drawing would report every convex corner as a problem. The parser uses the signed area to detect clockwise input and reverses it, after checking the outline doesn't cross itself (where "orientation" would mean nothing).

## 5. Ideas to extend it

- **Whole-panel lead lines:** in a real panel a lead line through one piece usually continues into its neighbour. Read the panel as a planar graph and prefer lines that extend existing ones, so the leading looks deliberate.
- **Sheet nesting:** after splitting, lay the pieces on a sheet of each colour with the grain or streaks aligned, and estimate how much glass to buy.
- **Copper-foil mode:** foiled work tolerates smaller pieces and tighter curves than lead came. Add a preset that loosens the rules and reports the foil length instead of extra lead.
