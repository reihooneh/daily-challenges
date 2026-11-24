# How Loadorder works

## Architecture

```
loadorder.lua          the command line and the report (diagram, walls, warnings)
loadorder/parse.lua    reading and checking a move file
loadorder/plan.lua     orientation, walls, balance, and trying other stop orders
test/                  the example's rules, orientation, rebalancing, hostile files
tools/lua.py           runs the scripts on lupa's Lua 5.4 when there's no lua binary
```

## Key concepts

**Walls.** Removalists load floor-to-ceiling walls across the truck, each tied off before the next.
Loadorder treats each wall as a slice of the truck's length: its depth is its deepest item, and it
holds items until their faces (width times height) fill 85 % of the truck's cross-section.

**Last in, first out.** The stops are loaded in reverse: the last stop's walls go in first, against
the cab; the first stop's go in last, by the door. Within one stop, walls are sorted heaviest first,
so weight sits forward.

**Orientation.** Each item tries every way it can sit (only two for upright items) that fits the
truck's width and height, and takes the one using the least length.

**Balance.** The load's centre is the walls' weights times their middles, divided by the total
weight, as a share of the truck length. Too far back makes the steering light; too far forward
overloads the front axle.

**Another order.** If the plan overflows or won't balance, Loadorder tries every order of the stops
(at most 720) and keeps the one that works with the fewest pairs of stops swapped from your order.

## Language features worth noticing

- Modules as tables returned from files, loaded with `require`.
- `pcall` with error tables (`{ line = ..., msg = ... }`) gives line-numbered parse errors without
  exceptions leaking.
- Patterns like `[%z\1-\8\11-\31\127]` reject control characters; `%d+%.?%d*` accepts only plain
  decimals, which keeps `tonumber` from reading `nan` or `0x10`.

## Interview questions

**Why first-fit by depth instead of real 3D bin packing?** Movers build walls, not puzzles, and an
exact 3D pack would be NP-hard and fragile to real item sizes. Sorting deepest first means each
wall's depth comes from its first item and shallower things fill in behind; it's the shape of the
real job.

**How would you check the plan is safe?** The tests check the invariants: every item appears once,
walls never put an earlier stop behind a later one, heavier walls are forward within a stop, nothing
heavy sits on a fragile item, and the balance equals the centre of mass computed independently.

**What if there were 10 stops?** 3.6 million orders is too many to try. Then you'd use the distance
from your planned order as the search order (try one swap, then two) and stop at the first that
works, or solve it as a small integer programme.

## Extensions

1. Axle loads from the truck's wheelbase, against the hire company's limits.
2. A second trip: which walls to leave for it so the first one balances.
3. Print a label per wall to stick on the boxes as they're packed.
