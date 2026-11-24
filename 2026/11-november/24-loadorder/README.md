# Loadorder

**How to load a removal truck when it's going to more than one place.**

Moving is rarely one stop. Some things go to storage, the rest to the new place; sometimes a sister's
couch gets dropped off on the way. Load the truck in the wrong order and you're unpacking half of it
on the footpath to reach the storage boxes. Loadorder plans the walls of furniture and boxes from the
cab back, so each stop's things come off first, heavy walls sit forward, fragile boxes go on top, and
the weight is balanced over the axles. If the order you planned to drive in can't balance or fit, it
finds the closest order that does.

## Features

- Walls (tiers) from the cab to the door: the last stop's things at the cab, the first stop's at the door.
- Items stand or lie however takes the least length of truck; `upright` things (fridges, mattresses)
  stay standing; `fragile` ones go on top of their wall.
- Heavier walls towards the cab within each stop's share; the load's balance as a share of the truck
  length, checked against a range (30 % to 55 % by default).
- Anything that doesn't fit, and a different stop order if it would fit and balance, changing as
  few pairs of stops as possible.

## Example

```
$ lua loadorder.lua examples/move.txt
49 items, 928 kg, into a 4.5 m truck. Stops in order:
  1. Self storage, Leichhardt (A)
  2. 14 Wattle St, Marrickville (B)

  cab [BBBBBBB|BBBBBBBBBB|BBBB|BBBBBB|AAAAA|AAAAAAAAA|AAAAAAA|AAA|.] door
                               ^ balance 39%

Load from the cab back (each line is a wall, bottom first):
   1. B  0.00-0.60 m  232 kg  Washing machine, Desk, Clothes boxes x4, Kitchen boxes x8 (fragile, on top)
   2. B  0.60-1.45 m  179 kg  Fridge, Sofa, Kitchen boxes x2 (fragile, on top)
   3. B  1.45-1.80 m   51 kg  Clothes boxes x4, TV (fragile, on top)
   4. B  1.80-2.10 m   45 kg  Bed base
   5. B  2.10-2.35 m   30 kg  Queen mattress
   6. A  2.35-2.80 m  227 kg  Bookshelf, Book boxes x10, Chairs x2
   7. A  2.80-3.55 m  108 kg  Dining table, Book boxes x3, Bikes
   8. A  3.55-4.15 m   38 kg  Bikes, Chairs x4
   9. A  4.15-4.45 m   18 kg  Book boxes

Truck used: 4.45 of 4.50 m. Load balance 39% from the cab (aim for 30% to 55%).
```

A move file has a `truck LENGTH WIDTH HEIGHT` line (metres), optional `balance FROM TO`, one
`stop ID "Address"` per stop in the order you'll visit, and `item "Name" A B HEIGHT KG [upright]
[fragile] [x3] -> STOP` lines.

## Run and test

```sh
lua loadorder.lua examples/move.txt
lua test/test_loadorder.lua
```

Lua 5.4, no libraries. Without a `lua` binary, `python3 tools/lua.py` runs the same scripts on
lupa's embedded Lua 5.4 (`pip install lupa`).

## Security

- The move file is read in binary with a 32 KB cap; lines are capped at 300 characters, and control
  characters (including terminal escape sequences) and markup characters in names are refused.
- Numbers must be plain decimals in range (no `nan`, `inf`, exponents or signs); at most 6 stops (720
  orders to try) and 400 items after expanding counts, so every search is bounded.
- The parser never calls `load` or `dofile` on the input; errors name the line.
- Known limits: walls are planned by face area, not exact 3D packing; leave some slack and strap
  each wall.
