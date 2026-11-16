# How Kerbtuck works

## 1. Architecture

```
car (preset or JSON) ─checkCar / parseCar─▶ Car ─derive─▶ rear overhang, track, rear-axle turning radius
                                                        │
          scene(car, gap): kerb, rear car, front car (+5 cm clearance)
                        │
     oneMoveGap(car)  ◀─┼─▶  plan(scene): Dijkstra over (x, y, heading, gear) on a grid,
     (closed form)      │     6 moves per state: forward/reverse × right lock/straight/left lock
                        │
                 replay(moves) every 5 cm ─▶ picture() + goes() ─▶ the report
```

## 2. File tour

- **`src/car.ts`:** the `Car` record, six presets, `derive` (turning radius at the rear axle from the published turning circle), and strict checking and parsing of car files.
- **`src/motion.ts`:** `drive` (exact arcs), the car's four corners, and a separating-axis collision test against a box.
- **`src/park.ts`:**
  - the scene;
  - the one-go formula;
  - the `clear` and `parked` tests;
  - the start pose;
  - the planner (with its own binary heap);
  - `replay`.
- **`src/draw.ts`:** the text picture, and grouping moves into goes.
- **`src/cli.ts`, `src/main.ts`:** arguments, safe file reading, the report (`run` is testable without a process).
- **`tests/kerbtuck.test.ts`:** everything above.

## 3. Key concepts and language features

**A car can't slide sideways.** At parking speed, the middle of the rear axle always moves the way the car points. With the wheels turned, it follows a circle whose radius depends only on the wheelbase and the steering angle (the "bicycle model"). So the car's state is just (x, y, heading), and every move is an exact arc: the heading changes by curvature × distance, and the position follows `sin` and `cos` of the heading.

**From the brochure to the turning radius.** Brochures give the kerb-to-kerb turning circle, which the outer front wheel traces. The front wheel is a wheelbase ahead of the rear axle, so outer radius² = wheelbase² + (rear-axle radius + half the track)². Kerbtuck solves that for the rear-axle radius. A test drives the car round on full lock and checks the outer front wheel traces exactly the published circle.

**The one-go formula.** Run the parking backwards: from parked, the car swings out on full lock round a centre point level with its rear axle, out towards the road. Its front kerb-side corner sweeps a circle about that point, and must clear the back of the car in front. That gives:

gap = rear overhang + √(r² − h²)

where r is the corner's distance from the centre, and h is the centre's height above the front car's road-side edge. The test doesn't trust the algebra: it simulates the swing and bisects for the smallest gap that works, for every preset, and the two agree within 2 cm.

**Planning with the fewest gear changes.** A tight gap needs shuffles, and drivers mind the number of gear changes far more than a few extra centimetres. The planner is Dijkstra's algorithm over a grid of positions (10 cm) and headings (3°), with "last gear" as part of the state. Each state can drive 30 cm forward or back, on full right lock, straight, or full left lock.
- The cost is lexicographic: gear changes × 1000, + turns of the wheel × 0.5, + metres driven.
- So the first parked state popped from the queue has the fewest gear changes, and among those the fewest turns of the wheel and the shortest drive.
- Each move is checked at 5 cm steps against the kerb and both cars.
- A replay of the final plan rechecks every 5 cm independently.

**Collision checks.** The car is a rotated rectangle. Comparing bounding boxes would report bumps that didn't happen. The separating-axis test projects both shapes onto each rectangle's edge normals: if any projection has a gap, they don't touch.

**TypeScript features:**
- `strict` with `noUncheckedIndexedAccess` and `exactOptionalPropertyTypes`, so every array access is checked;
- `Record` and indexed types for the presets and limits;
- interfaces for poses and moves;
- a small generic-free binary heap class;
- `node:test`, compiled by `tsc` alongside the source.

## 4. Interview questions

**Q: Why put "last gear" in the search state?**
A: The cost of a move depends on whether it changes direction, which depends on how you arrived. Without the gear in the state, two paths reaching the same pose, one going forward and one reversing, would be merged. The planner could then keep the cheaper one even though the other leads to fewer gear changes later. With it, Dijkstra's guarantee holds again: costs are non-negative, and each state's cost depends only on that state.

**Q: Why is the cost "changes × 1000 + distance" valid for fewest-changes-first?**
A: Any plan is far shorter than 1000 m of driving, so one extra gear change always costs more than any amount of extra distance. Ordering by this single number is the same as ordering by (changes, turns, distance) lexicographically. That lets one ordinary priority queue do it.

**Q: How do you know the plan doesn't clip a bumper between the points you checked?**
A: Three ways:
- moves are checked every 5 cm, and 5 cm of travel moves a corner at most about 5 cm × (distance from the rear axle) × curvature, a few centimetres;
- the parked cars are padded by 5 cm of clearance;
- the final plan is replayed independently from the start every 5 cm, and the report says whether it's clear.

## 5. Extension ideas

- **Measure your street:** take a photo with a known length in it, mark the two cars, and get the gap without a tape measure.
- **Steering while still:** many drivers turn the wheel at a standstill. Add steering-angle states, so the planner can use part-lock arcs and find even tighter gaps.
- **Angle and perpendicular parks:** the same planner, with a different scene and goal.
