# How Tinselwatt works

## 1. Architecture

```
display.txt ──Tinselwatt.read_file (regular file, ≤32 KB)──▶ Display.parse ──▶ Display
                                                                               │ circuits, outlets, lights, cords
                                     Planner#build_options: for each light, every (outlet, cord) that is safe on its own
                                                                               │
                                     Planner#plan: branch and bound over lights (fewest options first)
                                                   + shared limits: circuit 80 %, socket rating, each cord once
                                                                               │
                                                   Plan (choice per light, or why it was left off + remedy)
                                                                               ▼
                                                                         Report.text
```

## 2. File tour

- **`lib/tinselwatt/display.rb`:** the file format.
  - `Display.parse` checks every line and builds `Circuit`, `Outlet`, `Light` and `Cord` structs.
  - `Cord#area` and `Cord#resistance` turn a cord's rating into copper size and ohms.
  - `circuit_watts` is 80% of the breaker; `outlet_watts` is the socket rating.
- **`lib/tinselwatt/planner.rb`:** the search.
  - `build_options` lists what each light could use on its own, and why not if nothing.
  - `search` is the branch and bound.
  - `remedy` explains a light left off for lack of cords or capacity.
  - `cost_of` and `safe?` score and check any arrangement; the tests use them for brute force.
- **`lib/tinselwatt/report.rb`:** the plug-in sheet.
- **`bin/tinselwatt`:** the command line, with exit codes 0 (all lit), 3 (some left off), 1 (bad file) and 2 (usage).

## 3. Key concepts

**Two kinds of rule.** Some rules concern one light at a time:
- an outdoor light needs an RCD outlet;
- a cord must reach, carry the current and keep the voltage drop under 3%.

These are checked once, when each light's options are built. The others are shared:
- a circuit's total load;
- a socket's total load;
- a cord can only be in one place.

These are checked as the search adds each light. Splitting them this way keeps the search's inner loop tiny.

**Voltage drop.** A cord's two conductors each have resistance `ρL/A`, with copper ρ = 0.0172 Ω·mm²/m. The current flows out and back, so the drop is `I × 2ρL/A`. A 1,000 W load at 120 V draws 8.3 A; through 50 m of 1.31 mm² (16 AWG) cord, that's 1.31 Ω and 11 V, which is 9%. Too much, so a test checks it is refused. At 230 V the same power draws half the current, which is why long runs are easier there.

**The objective, in one number.**
- Leaving a light off costs 100,000 plus 10 per watt. That's more than any amount of cord, so the plan always powers the most watts it can.
- Each metre of cord costs 1.
- The busiest circuit's share of its limit (0 to 1) is added last. It breaks ties between plans with the same cord, never outweighing a metre.

So one search answers three questions in order of importance.

**Branch and bound.** Lights are placed one at a time, those with the fewest options first, because they're the most constrained. For each light it tries every option (shortest cord first), then "leave it off". A branch is cut when its cost so far, plus the cheapest each remaining light could possibly cost, can't beat the best complete plan found. That precomputed suffix sum is the `floors` array. The first plans found are good, so the bound bites early.

**Symmetry breaking.** Ten identical 20 m cords would make every arrangement appear 10! times. The search only ever takes the lowest-numbered free cord among identical ones (`@twins`), so each arrangement is explored once. A test with ten identical cords finishes in under 50,000 steps.

**Ruby features used:**
- `Struct` with `keyword_init` for plain data, and methods on a Struct (`Cord#resistance`);
- integer bit masks for the used cords (`@used[i]` reads bit i of an Integer);
- `frozen_string_literal`, `+""` for the report buffer, and `transform_values`, `filter_map` and `sum`;
- minitest and Open3 from the standard library, so there are no gems.

## 4. Interview questions

**Q: Why branch and bound rather than a greedy "biggest light to the emptiest circuit"?**
A: Greedy can paint itself into a corner. It can give the one cord that reaches the far arch to a nearby light that a shorter cord would have served, and then the arch stays dark. This is a generalised assignment problem with capacity constraints, which is NP-hard. But real displays are small (a couple of dozen lights). With a good bound and symmetry breaking, an exact search proves the answer in milliseconds. The tests check that against brute force.

**Q: How do you know the bound is safe to prune with?**
A: It must never overestimate what the remaining lights will cost. For each remaining light I take its cheapest option alone: its shortest usable cord, or zero if it plugs straight in, or the cost of leaving it off if that's lower. I ignore the shared limits, which can only make things more expensive. Their sum is a lower bound, so cutting a branch whose cost so far plus that bound can't beat the best plan never cuts the optimum. The brute-force test would catch it if it did.

**Q: The plan says a circuit is at 86%. Isn't that dangerously close?**
A: It's 86% of the 80% continuous-load limit, so about 69% of the breaker's rating. The 80% rule exists because breakers and wiring heat up under loads left on for hours, and a display runs all evening. If you wanted more margin, you'd change one constant (`circuit_watts`). A useful extension is to report the margin per circuit and let the user ask for, say, 70%.

## 5. Extension ideas

- **Timers and sequences:** lights that never run together (a timer switches the projector off at 10 pm) could share capacity, which needs time slots in the circuit constraint.
- **Daisy chains and splitters:** plan chains of light strands and power boards explicitly, with each segment's limit, instead of one cord per display.
- **A yard sketch:** draw the outlets, lights and chosen cord routes as an SVG, so the plan can be followed outside in the cold.
