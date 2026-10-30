# Loadline

**Sorts a laundry basket into the fewest machine loads that respect every care label (temperature, colour, fabric and new clothes that bleed), allowing for how much less a wool or delicates programme can hold, and proves the count is the fewest possible for small baskets.**

Language: Bash + POSIX awk (no dependencies) · Field: household care / bin packing with conflicts · Day: 30 October 2026

Sorting laundry looks simple until the rules collide. A load runs at the *lowest* temperature any item allows, and on the *gentlest* programme any item needs. Gentle programmes hold far less: a 7 kg drum takes about 3.5 kg on synthetics, 2.4 kg on delicates and 1.75 kg on wool, as machine manuals say. Whites can't go with darks, and a new red hoodie can only go with reds. Loadline turns that into a packing problem and solves it:

- **Every care-label rule:** temperature, programme and colour compatibility, bleeding items, and towels and bedding that should get 60 °C when they can.
- **Fewest loads:** greedy packing by share of the drum, then emptying loads into others where possible, then moving single items to undo compromises without adding a load.
- **Proof for small baskets:** with up to 18 items, a depth-first search checks every way to share them out and proves the plan uses the fewest loads possible. For bigger baskets it states a lower bound instead (by weight per programme, and by colour clashes).
- **Easy to follow:** items stay together when they fit, and big piles split evenly into as few loads as their weight needs. Anything too heavy for the drum gets a note.
- **A rough energy total:** kWh for the whole wash.

## Quick start

```bash
bin/loadline examples/saturday.txt
bash tests/run.sh            # 90 checks, including shellcheck
```

```
LOADLINE  Saturday wash (7 kg machine)
35 pieces, 12.2 kg in 5 loads: the fewest possible without splitting an item (every way to share them out was checked).

Load 1: cotton programme at 40 C, 5.7 of 7.0 kg  ########..
    4 x Bath towels  [cotton, white, up to 60 C]  (wanted 60 C)
    6 x Tea towels  [cotton, white, up to 60 C]  (wanted 60 C)
    2 x Bed sheets  [cotton, light, up to 60 C]  (wanted 60 C)
    5 x Work shirts  [cotton, white, up to 40 C]

Load 2: delicate programme at 30 C, 2.4 of 2.4 kg  ##########
    4 x School uniform  [synthetic, light, up to 40 C]
    5 x Gym gear  [synthetic, bright, up to 40 C]
    1 x Silk blouse  [delicate, light, up to 30 C]

Load 3: cotton programme at 40 C, 2.1 of 7.0 kg  ###.......
    3 x Jeans  [cotton, dark, up to 40 C]

Load 4: wool programme at 30 C, 1.5 of 1.8 kg  #########.
    2 x Black jumpers  [synthetic, dark, up to 30 C]
    2 x Merino base layer  [wool, dark, up to 30 C]

Load 5: cotton programme at 30 C, 0.6 of 7.0 kg  #.........
    1 x New red hoodie  [cotton, red, up to 30 C]  (may bleed: only red with it)

About 2.9 kWh in all (rough figures per wash by temperature).
```

The towels drop to 40 °C here because five loads is the minimum. Washing the work shirts on their own would get the towels their 60 °C at the cost of a sixth load, and the "(wanted 60 C)" notes show where that trade-off is.

## The basket file

```
name Saturday wash
machine 7 kg                                  # the drum's rated cotton load
item Bath towels x 4 0.6 kg cotton white 60 hot
item New red hoodie x 1 0.6 kg cotton red 30 bleeds
#    <name> x <count> <kg each> kg <cotton|synthetic|delicate|wool> <white|light|bright|dark|red> <20|30|40|60|90> [hot] [bleeds]
```

Colours that may share a drum: white with light, light with bright, bright with dark, and dark with red. Exit codes: `0` plan printed, `2` bad usage or input. `-` reads standard input.

## Security

- **Bounded reading:** at most 32 KB, read with `head -c`, so an endless stream is cut off. Only regular files are opened, and the path is never echoed.
- **Strict parsing:** every line must match a fixed pattern. Names allow letters, digits, spaces and `' ( ) . , & / -` only, so `$(reboot)` or `<script>` is refused. The text must be plain ASCII, and control characters (terminal escapes) are refused.
- **No dangerous features:** no `eval`, no `source` of anything built from input, and every variable is quoted. The awk program is a fixed file, receives only validated records on standard input, and never calls `system()`. Scripts run with `set -euo pipefail` and `LC_ALL=C`.
- **Bounded work:** at most 60 items and 200 pieces. The exact search runs only for 18 or fewer units, with a 400,000-node cap.
- **Checked:** `shellcheck` passes on every script (it runs as part of the tests).

**Known limits:** the colour rules and the capacity figures for each programme are typical household guidance; your machine's manual and your clothes' care labels come first. The rough kWh figures are for comparing plans, not for a power bill.

See [HOW-IT-WORKS.md](HOW-IT-WORKS.md) for the walkthrough.
