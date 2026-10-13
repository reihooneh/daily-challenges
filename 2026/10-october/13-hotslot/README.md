# Hotslot

**Plans one oven so a whole meal is ready at once: when each dish goes in, when it comes out, and what to set the oven to.**

Language: Lua 5.3+ · Field: cooking / constraint scheduling · Day: 13 October 2026

Recipes assume you have an oven each. On the big day you have one oven, the lamb wants 180°C, the potatoes 200°C, the Yorkshire puddings 220°C, and everything has to land on the table together. Cooking-timer apps count back from the serving time, but they ignore the hard part: **the oven can only be one temperature at a time, it takes time to heat up and cool down, and it only has so many shelves.** Hotslot plans for all of that. It finds when each dish goes in, a temperature every dish in the oven can live with, and the freshest result: the least time any dish sits waiting beyond its resting time.

## Quick start

```bash
lua hotslot.lua examples/christmas.txt      # a plan
lua hotslot.lua examples/dinner-party.txt   # an impossible menu, explained
lua test/test_hotslot.lua                   # 330+ checks
```

No libraries are needed. It's tested on Lua 5.3 and 5.4.

```
HOTSLOT  christmas.txt  (serve at 13:00, one oven with 3 shelves)

TIMELINE
  10:55  Turn the oven on to 190C to preheat
  11:05  Put in: Roast lamb  [oven 190C]
  11:55  Put in: Stuffing  [oven 190C]
  12:10  Put in: Roast potatoes  [oven 190C]
  12:30  Take out: Stuffing, keep warm (30 min until serving)
  12:30  Put in: Honey carrots  [oven 190C]
  12:35  Take out: Roast lamb, rest 20 min, keep warm (5 min until serving)
  12:35  Turn up the oven to 210C
  12:40  Put in: Yorkshire puddings  [oven 210C]
  13:00  Take out: Honey carrots
  ...
  13:00  Serve
```

When a menu can't work, Hotslot says why. It names the pairs of dishes that can't share the oven, which single dish to cook elsewhere, or that there's simply too much food for the shelves:

```
NO PLAN: these dishes can't all be ready on time in one oven.
  Pavlova (115-125C) and Pizza (240-260C) can't share the oven in time.
  Pavlova (115-125C) and Garlic bread (180-220C) can't share the oven in time.

Leave out any one of these and everything else fits (cook it earlier and reheat, or use another oven):
  Pavlova
```

## Menu format

```
serve 13:00                 # when to eat
oven 3 shelves              # 1 to 4 (default 2)
heats 15 per min            # degrees C per minute (default 15)
cools 5 per min             # with the door ajar (default 5)

dish Roast lamb: 180C +-10, 90 min, rest 20, hold 15
```

| Part | Meaning |
|---|---|
| `180C +-10` | Ideal temperature, and how far off it the dish can cope with (`±` and `°C` also work) |
| `90 min` | Cooking time |
| `rest 20` | Must rest at least this long out of the oven |
| `hold 15` | Stays good for this much longer after resting, kept warm |
| `shelves 2` | Shelves it takes up (default 1) |

## How it works (short version)

Time is split into 5-minute slots, counted back from serving. In each slot the oven has one temperature, which must suit every dish inside it. The oven also has to be hot already when a dish goes in, and it can only rise or fall so much in one slot. A backtracking search tries each dish's finishing times, freshest first and most constrained dish first. After every choice it checks that some sequence of oven temperatures still works. Because each slot's allowed temperatures form an interval, that check is a single exact pass. A separate check can prove there are too few shelves without searching at all. The full walkthrough is in [HOW-IT-WORKS.md](HOW-IT-WORKS.md).

**Simplifications:** cooking times are fixed within each dish's tolerance (in a real oven, hotter is a bit faster), and only the oven is planned, not the stovetop.

## Security

A menu file might come from anyone, so it is treated as hostile:

- **Bounded input:** at most 8 KB is read from a file or standard input, so a huge file or an endless stream such as `/dev/zero` is refused, not loaded. There are also limits on lines (200 characters), dishes (15) and every number.
- **Plain text only:** control characters, terminal escape codes, NUL bytes and non-ASCII text are refused, except the `±` and `°` signs, which are converted. Dish names may contain only letters, digits, spaces and `- & ' /`.
- **No code from data:** the menu is parsed with patterns. Nothing from it is passed to `load`, `require`, `os.execute` or `io.popen`.
- **Safe output:** error messages give only a line number and never repeat the input. The file name is reduced to plain characters before it is printed.
- **Bounded work:** the search stops after 100,000 steps or 4 million slot checks, a few seconds at most. If it stops early it says so, and any plan it prints has still been fully checked.

## Testing

`test/test_hotslot.lua` runs 331 checks:

- **Independent rule checker:** every plan, including random ones, is checked against every rule: the temperature path, shelves and waiting times.
- **Brute force comparison:** on 150 random menus, the solver is compared with a brute force that tries every combination of finishing times and checks the oven by dynamic programming over every temperature. Both must agree on whether a plan exists and on the least waiting.
- **Speed and safety:** 15-dish menus finish within the limits, and hostile menus, file names and arguments are handled safely.

## Files

```
hotslot.lua          command line
hotslot/menu.lua     reading and checking the menu
hotslot/plan.lua     the search and the temperature check
hotslot/report.lua   timeline and explanations
test/                test_hotslot.lua
examples/            christmas.txt, dinner-party.txt
```
