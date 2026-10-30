# How Loadline works

A walkthrough so you can explain every part of it.

## 1. The big picture

```
 basket.txt ──▶ bin/loadline (Bash)   bounded read → ASCII and control-character checks → one pattern per line
                       │                → tab-separated records:  M machine title  /  I item fields...
                       ▼
                lib/plan.awk (awk)     units (items, or even chunks of big ones)
                       │                → greedy pack by share of drum → empty small loads into others
                       │                → exact depth-first search if ≤ 18 units (proves the minimum)
                       │                → polish: move units to undo compromises, same number of loads
                       ▼
                    the plan            loads, programmes, temperatures, notes, bound or proof
```

## 2. File tour

| File | Job |
|---|---|
| `bin/loadline` | Arguments, bounded reading, the file format, and handing clean records to awk |
| `lib/plan.awk` | Compatibility rules, packing, exact search, lower bounds and the report |
| `tests/run.sh` | 90 checks in plain Bash, including `shellcheck` |
| `examples/saturday.txt` | A realistic family wash |

## 3. Key ideas

### Laundry as bin packing with conflicts
Each load is a bin, but an odd one. Its **capacity depends on what goes in**: the gentlest fabric present picks the programme, and the programme sets the capacity (100%, 50%, 35% or 25% of the rated drum). Some items **conflict**: colour pairs that run, and bleeding items with anything of another colour. Its **temperature** is the minimum over its items. Plain bin packing is already NP-hard, so the plan is built by heuristics and then checked exactly when the basket is small.

### Greedy, then repair
1. **Units:** an item goes in whole if one load of its own programme can hold it. Otherwise it is split into the fewest *equal* chunks that fit (eight wool jumpers become four and four, not seven and one).
2. **First-fit decreasing:** units are sorted by the share of a drum they use, biggest first. Each goes into the open load where it costs least: losing capacity to a gentler programme is expensive, and dropping a hot item below 60 °C costs a little. A new load is opened only when that is cheaper.
3. **Emptying:** for each load, try to move all its units into the others. If every one finds a home, the load disappears.
4. **Polish:** move single units between loads when that reduces the care-label compromises without opening a load.

### Proving the minimum
For up to 18 units, a **depth-first search** tries every way to share them out: each unit goes into each open load it fits, or into one new load. That last choice removes symmetry, because the loads are interchangeable. A branch stops as soon as it reaches as many loads as the best found so far. If the search finishes within its node cap, the plan is proven to use the fewest loads possible (with items kept together).

### Lower bounds for big baskets
- **Capacity:** every unit fills at least its weight divided by its own programme's capacity, because mixing can only make the capacity smaller. Adding these up gives the minimum number of drums.
- **Colour clashes:** a set of units that clash pairwise needs one load each. The largest such set among the kinds present (there are at most a handful) is found by trying every subset.

The larger of the two is reported. It can sit below the true minimum, and the report says so.

### Bash and awk features you met here
- **`[[ =~ ]]` with `BASH_REMATCH`** to validate and split each line in one step, and **`${var%"${var##*[![:space:]]}"}`** trimming without calling a subprocess.
- **`head -c`** for a hard input limit, and the **trailing `x` trick** (`$(cmd; echo x)`) to keep trailing newlines that command substitution would drop.
- **POSIX awk:** associative arrays as structs (`L[load, k]`), recursion with globals as the stack, and an insertion sort, because POSIX awk has no `asort`.
- **`shellcheck`** clean, with intentional exceptions disabled and explained in place.

## 4. Interview questions you might get

**Q: Why is mixing a wool jumper into a cotton load so costly?**
A: The load must run the wool programme, which holds about a quarter of the drum. One 0.3 kg jumper can shrink a 7 kg load's capacity to 1.75 kg. The cost function weighs capacity lost to a gentler programme much more than anything else, and the polish step moves such units out when another load can take them.

**Q: How do you prove five loads is the minimum?**
A: An exhaustive depth-first search over every way to share the units among loads, with symmetry broken by opening at most one new load at a time, and pruned when a branch can't beat the best. If it completes within the node cap, the greedy answer is certified optimal. If it finds better, that plan is used instead.

**Q: What stops a malicious basket file from running commands?**
A: Each line must match a fixed regular expression, and names are limited to a safe character set. Nothing is evaluated: no `eval`, no unquoted expansion, no `source` of input-derived paths. The awk program is a fixed file that only reads validated tab-separated records and never calls `system()`. The tests feed `$(reboot)` as a name and check that it is refused.

## 5. Ideas to extend it

1. **Several machines and a time limit:** two washers and a dryer, minimising when the last load is dry.
2. **Dryer rules:** "do not tumble dry" items need a line, so plan the washing so the line isn't overloaded.
3. **Care-label symbols:** read the ISO 3758 symbols (as text codes) straight from a photo transcription.
