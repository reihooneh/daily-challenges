# How Kitewise works

## 1. Architecture

```
course.txt ──readLimited (≤32 KB)──▶ parse.lua ──▶ course {controls, order, sprint}
                                                     │
                       check.lua: problems(course, positions) ──▶ issues + one cost
                                                     │
                       fix.lua: movable controls × 5 m grid within their radius
                                exhaustive (≤20,000 combinations) or one-at-a-time descent
                                                     │
                       report.lua: legs, problems in words, suggested moves, what's left
```

## 2. File tour

- **`kitewise.lua`:** the command line. `main(args, stdin)` returns an exit code and the text, so the tests call it directly. A file is read with a byte cap, so a huge file or endless stream is never loaded whole.
- **`kitewise/parse.lua`:** the course format: titles, `sprint`, `control CODE at X Y feature WORDS move R start|finish`, and `course ...`. Every line is checked.
- **`kitewise/check.lua`:** the geometry.
  - `angle`, `doglegLength`, `toSegment` and `crosses` are the measurements.
  - `problems` scores the course at any set of positions.
- **`kitewise/fix.lua`:** `candidates` lists where a movable control may go; `fix` searches.
- **`kitewise/report.lua`:** turns issues into the setter's words, with compass directions for moves.

## 3. Key concepts

**Measuring a dog-leg.** Picture the leg in and the leg out as two rays from the control, with angle θ between them. A runner arriving at distance d and one leaving at distance d are the two ends of an isosceles triangle with apex angle θ, so they are 2·d·sin(θ/2) apart. They can see each other while that is under the sight distance s (30 m in forest, 15 m in sprint), so until d = s / (2 sin(θ/2)), but no further than the shorter leg. Every control is visible within s of itself anyway, so the severity is what lies beyond s. That makes 60° exactly the threshold: 2·sin 30° = 1. Sharper angles leak more, and a leg straight back leaks the whole leg.

**One score for everything.** Each problem has a cost:
- a dog-leg costs its leaked metres;
- controls too close cost 1,000; the same feature too close costs 500;
- a pass-by costs twice how far inside sight distance it comes;
- a crossing costs 5.

The rule-breaking problems dominate, so the fixer clears those first, then shrinks dog-legs. A tiny cost per metre moved means it never moves a control further than it has to.

**Searching moves.** A control allowed to move 20 m has 49 spots on a 5 m grid. Two such controls have 2,401 combinations, which is cheap to try exhaustively, and then the answer is the best possible on that grid. With more movable controls the combinations multiply, so above 20,000 Kitewise uses coordinate descent: each control in turn jumps to its best spot given the others, round after round, until a round changes nothing. Descent can stop at a local best. The tests check it never beats the exhaustive answer, which would mean a bug, and the report says which method was used.

**Lua features used:**
- modules as tables returned from files, found through `package.path` built from the script's own folder;
- `pcall` with error tables (`{input = ...}`), so bad input is told apart from bugs;
- `utf8.len` to validate UTF-8;
- Lua patterns, including byte classes for the invisible direction marks;
- closures for the recursive exhaustive walk;
- a check that no global variable leaks (a snapshot of `_G` before and after the tests).

## 4. Interview questions

**Q: Why measure a dog-leg in metres instead of just "angle under 60°"?**
A: Angle alone ignores leg length. A 30° angle between a 40 m leg and a 300 m leg leaks far less than the same angle between two long legs, because the runners can only be in sight for as long as the shorter leg lasts. Metres also give the fixer something to minimise smoothly: moving a control a few metres can turn a 60 m leak into 7 m, which is real progress, even if the angle stays under 60°.

**Q: When is coordinate descent good enough, and how would you know?**
A: When the problems are mostly local: moving one control only changes its own two legs and nearby controls, so the parts barely interact. But two neighbouring movable controls share a leg, and then descent can stall. I test it against the exhaustive search on random courses (it may tie or lose, never win). The report tells the setter which method produced the answer.

**Q: How would you handle real runners not running straight lines?**
A: Replace the straight leg with the likely route. Rasterise the map into a cost grid (paths fast, thick forest slow, cliffs impassable) and take the cheapest path with Dijkstra. Then measure the dog-leg along the two route polylines: the stretch where the incoming and outgoing routes are within sight distance at the same distance from the control. The rest of Kitewise stays the same, because everything works on "positions → problems → cost".

## 5. Extension ideas

- **Route-based legs:** the least-cost-route idea above, from an OpenStreetMap or ISOM map export.
- **Several courses at once:** check that different courses' controls on the same feature are far enough apart, and that courses sharing a control don't create dog-legs for one another.
- **Leg variety:** score the mix of short and long legs and changes of direction, and suggest which control to move to make a course less monotonous.
