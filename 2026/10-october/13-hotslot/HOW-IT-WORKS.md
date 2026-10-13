# How Hotslot works

A walkthrough so you can explain every part of it.

## 1. The big picture

```
 menu.txt ──▶ Menu.parse        serve time, oven, dishes; strict and bounded
                  │
                  ▼
             prepare()          minutes -> 5-minute slots; each dish's possible finishing slots
                  │
                  ▼
             crowded()          quick proof: is there too much food for the shelves?
                  │ no
                  ▼
             search()           backtracking: a finishing time per dish, freshest first
                  │   ├─ fitsAt()        shelves free, temperature ranges still overlap
                  │   ├─ reachable()     can the oven's temperature get from slot to slot?
                  │   └─ stillPossible() every dish still to place has a time left
                  ▼
             profile()          one temperature per slot: steady, preheat late, off at the end
                  │
                  ▼
             Report             timeline, dish table, or why it's impossible
```

## 2. File tour

| File | Job |
|---|---|
| `hotslot/menu.lua` | Reads the menu safely, with clear errors and limits |
| `hotslot/plan.lua` | The model, the search, the temperature check and the explanations |
| `hotslot/report.lua` | Turns a plan into timeline events and a table |
| `hotslot.lua` | Command line: bounded reading, safe file name, exit codes |
| `test/test_hotslot.lua` | 8 test groups, 331 checks, including a brute force |

## 3. Key ideas

### The model
Time is cut into 5-minute **slots**, counted back from serving. `temps[k]` is the oven temperature at the end of slot `k`. During the slot it moves steadily from `temps[k-1]`, and it can rise at most `heats × 5` degrees or fall at most `cools × 5`.

A dish in the oven for slots `start … finish-1` needs every temperature from the end of slot `start-1` (the oven must be hot when it goes in) to the end of slot `finish-1` to be within `ideal ± tolerance`. Its waiting time, `serve - finish`, must be at least `rest` and at most `rest + hold`.

### Checking the oven: intervals all the way down
Say we've chosen when every dish cooks. Then each slot `k` has an allowed range `[lo_k, hi_k]`, the overlap of the ranges of the dishes inside it. Can the oven follow a path through those ranges?

Start at room temperature. If the oven can be anywhere in `[a, b]` at slot `k-1`, then at slot `k` it can be anywhere in `[a - down, b + up]`, cut down to `[lo_k, hi_k]`. **An interval stays an interval**, so this forward pass is exact and takes one step per slot. If an interval ever becomes empty, the choice is impossible.

To pick actual temperatures, `profile()` walks backwards through those intervals:
- **During cooking:** stay at the same temperature as the next slot if allowed. This means the fewest knob turns.
- **Before the first dish:** be as cold as allowed, so the oven preheats as late as possible.
- **After the last dish:** turn it off.

### The search
Each dish has a few possible finishing slots (one for every 5 minutes of `hold`). Backtracking tries them:

1. **Most constrained first:** dishes with the fewest options and the narrowest temperature range go first, so dead ends show up early.
2. **Freshest first:** options are tried from shortest wait to longest, so good plans are found early.
3. **Pruning:**
   - *bound:* stop exploring when the waiting so far is already worse than the best plan;
   - *temperature check:* after every choice, the oven must still have a workable path;
   - *forward checking:* every dish not yet placed must still have at least one time that fits.
4. The best plan has the least total waiting; ties go to the fewest temperature changes.

### Proving "too much food" without searching
Some menus are impossible just because of shelf space. For each stretch of time from one dish's earliest start to another's latest finish, add up the cooking (shelf × minutes) of the dishes that have to happen inside it. If that is more than `shelves × length`, no plan can exist. This kind of argument is called *energetic reasoning* in scheduling. Without it, the search would spend its whole budget failing.

### Explaining an impossible menu
`explain()` runs the solver on every pair of dishes; pairs that fail on their own "can't share the oven". Then it leaves out each dish in turn, to suggest which one to cook elsewhere.

## 4. Glossary

| Term | Plain version |
|---|---|
| Slot | A 5-minute step of time |
| Tolerance | How far from the ideal temperature a dish can cope with |
| Hold | How long a dish stays good after it has rested |
| Backtracking | Try a choice, go deeper, undo it if it leads nowhere |
| Forward checking | After a choice, make sure every later decision still has an option |
| Energetic reasoning | Showing a schedule is impossible because there isn't enough capacity in some stretch of time |

### Lua features you met here
- **Modules as tables** returned from files, loaded with `require` and `package.path`.
- **Closures**: `fitsAt`, `stillPossible` and `search` share the solver's state without globals.
- **Patterns** (Lua's lightweight regular expressions) for parsing, with `^`/`$` anchors.
- **`error` with a table and `pcall`** to separate bad input (exit 2) from real bugs.
- **Integer division `//`**, from Lua 5.3 on.
- **Colon syntax** (`out:write(...)`): the test harness passes in fake streams with a `write` method.

## 5. Interview questions you might get

**Q: How do you know the plans are right and the best?**
A: Two ways. An independent checker in the tests confirms every plan obeys every rule. On 150 random menus, a brute force tries every combination of finishing times and checks the oven with dynamic programming over every temperature. The solver must agree with it on whether a plan exists and on the least total waiting.

**Q: Why are intervals enough for the temperature check?**
A: The oven's possible temperatures at each step start as one value, room temperature. Widening an interval by the heating and cooling limits gives an interval, and cutting it to the allowed range gives an interval. So the reachable set is always one interval, and two numbers per slot describe it exactly.

**Q: What if the search is too slow?**
A: It's bounded by 100,000 steps and 4 million slot checks. If it hits the limit, it says the plan may not be the freshest. A plan it prints is always valid, because every step is checked as it goes. The shelf-capacity proof removes the worst slow case, where the menu is impossible and the search would otherwise fail slowly.

## 6. Ideas to extend it

1. **Temperature-adjusted cooking times:** a few degrees hotter means a few minutes less.
2. **Stovetop and microwave as extra resources,** with burners as shelves.
3. **A printable or phone timeline** with alarms for each step, served with a strict Content-Security-Policy.
