# Tinselwatt

**Plug in a Christmas light display without tripping a breaker, cooking a cord or leaving the reindeer dark.**

Every December, people string lights across the house with whatever extension cords are in the garage. They plug them into whichever socket is closest, then find out the hard way which circuit the kitchen kettle is on. Advice articles explain the rules (stay under 80% of a breaker for loads left on for hours, use RCD/GFCI outlets outside, don't overload a cord). They leave you to juggle them by hand.

Tinselwatt does the juggling. You describe:
- your circuits, and what's already running on them;
- your outlets, and which have an RCD (GFCI);
- your lights, and where each one plugs in;
- the extension cords you own.

It chooses an outlet and a cord for every light, and proves the arrangement is the best possible:
- the most watts powered;
- then the least cord laid across the yard;
- then the busiest circuit as lightly loaded as it can be.

If something has to stay off, it says why, and which extra cord would fix it.

## Features

- **Hard safety rules, never broken:**
  - circuits within 80% of their breaker, counting what's already on them;
  - sockets within their rating (10 A at 230 V, 15 A at 120 V);
  - each cord carries no more current than it's rated for, and drops at most 3% of the voltage;
  - outdoor lights only on RCD/GFCI-protected outlets;
  - each cord used once, with no cords joined together;
  - a light's chain of strands within its end-to-end limit.
- **Real cord runs:** a cord follows the ground and walls (along x then y, plus 10%) with a metre to spare at the ends, not a straight line through the hedge.
- **Voltage drop from the copper:** each cord's conductor size comes from its rating (0.75 to 2.5 mm²), with resistance there and back.
- **An exact search.** Branch and bound proves the plan is the best possible, and tests check it against trying every arrangement. Identical cords are recognised, so ten 20 m cords don't make the search ten-factorial times slower.
- **Answers you can act on:** "one more 5 m cord (10 A) would power it from outlet porch", or "no circuit or socket within reach has enough spare capacity for it".
- **230 V or 120 V**, so it works in Australia, the UK and Europe, or North America.

## Example

```text
$ bin/tinselwatt examples/porch-120v.txt
Tinselwatt: Maple Street porch (120 V)

Outlet porch-gfci (circuit porch, RCD): 933 W of 1,800 W
  c9-roofline               525 W   6 m cord (13 A), 4.3 m run, 0.6% voltage drop
  mini-lights-bushes        408 W   15 m cord (13 A), 7.6 m run, 1.1% voltage drop

Outlet garage-gfci (circuit garage, RCD): 680 W of 1,800 W
  blow-mold-nativity        360 W   25 m cord (15 A), 16.4 m run, 1.4% voltage drop
  laser-projector            20 W   50 m cord (13 A), 15.3 m run, 0.2% voltage drop
  lit-arch                  300 W   30 m cord (13 A), 23.0 m run, 1.6% voltage drop

Outlet hall (circuit kitchen): 40 W of 1,800 W
  star-tree-topper           40 W   15 m cord (13 A), 2.1 m run, 0.1% voltage drop

Circuits (80% of the breaker, for loads left on for hours):
  porch          15 A breaker: 300 W already on + 933 W of lights = 1,233 W of 1,440 W (86%)
  garage         20 A breaker: 0 W already on + 680 W of lights = 680 W of 1,920 W (35%)
  kitchen        20 A breaker: 1,100 W already on + 40 W of lights = 1,140 W of 1,920 W (59%)

Cord laid: 141.0 m. No cords spare.
Best possible arrangement (178 steps searched).
```

The second example has more lights than cords. Tinselwatt powers what it can and explains the rest:

```text
$ bin/tinselwatt examples/front-yard.txt
...
Left off:
  path-stakes (24 W): every cord that reaches it is already in use; one more 5 m cord (10 A) would power it from outlet porch
  projector (35 W): every cord that reaches it is already in use; one more 10 m cord (10 A) would power it from outlet porch
```

## Writing a display

```text
title: Our place
voltage 230                               # or 120
circuit c1 breaker 16 load 1200           # breaker amps; watts already running during the show
outlet porch circuit c1 at 9 2 rcd        # position in metres; rcd = RCD/GFCI protected
light roofline watts 96 at 3 1 chain-limit 216   # where it plugs in; its chain's end-to-end limit
light candles watts 30 at 6 7 inside      # lights are outside unless marked inside
cord 10 rated 10 count 3                  # length in metres, rated amps, how many you have
```

## Run and test

Needs Ruby 3.1 or later. It has no gems; minitest comes with Ruby.

```bash
bin/tinselwatt examples/front-yard.txt     # exit 0: all lit; 3: some left off; 1: bad file
ruby -w test/test_tinselwatt.rb
```

The tests cover:
- **Reading:** the example is read correctly, and broken or hostile files are refused.
- **Each safety rule:** RCD outdoors, voltage drop, cord reach and rating, and the 80% circuit limit (keeping the most watts it can).
- **The suggested fix:** the extra cord it recommends.
- **The search:** checked against brute force on 120 random displays.
- **Identical cords:** they don't blow up the search.
- **The command line:** exit codes, plus links, folders, oversize and missing files.

## Security

Tinselwatt reads one local text file and prints a plan. No software is perfectly secure; this is how the risks are handled.

- **Bounded input:**
  - the file must be a regular file (not a link or folder), at most 32 KB of valid UTF-8, and at most 400 lines;
  - at most 12 circuits, 12 outlets, 24 lights and 30 cords;
  - every number has a range;
  - names are short lowercase identifiers;
  - control characters and invisible text-direction characters are refused.
- **Errors don't echo the file:** a test checks that a "password" in a bad file never appears in the output.
- **Bounded work:** the search stops after 3 million steps and says if the plan is then only the best found.
- **No risky code:** no `eval`, no shell, no network, no gems, and no file written. It runs clean under `ruby -w`.

**Limits:** Tinselwatt is a planning aid, not an electrician.
- Watts come from the labels, and existing loads are your estimate.
- Breakers and outlets must already be sound and correctly protected.
- Local wiring rules decide what's allowed.
- Outdoor plugs and joins need weatherproof covers whatever the plan says.
- If a breaker trips anyway, stop and have the circuit checked.

More detail: [HOW-IT-WORKS.md](HOW-IT-WORKS.md).
