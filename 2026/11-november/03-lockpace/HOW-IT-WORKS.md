# How Lockpace works

A walkthrough so you can explain every part of it.

## 1. The big picture

```
 room.txt ──▶ parse.js     fixed line shapes → puzzles with times, crews, needs / uses / gives
                 │
                 ▼
             analyse.js    reachable? required? dead ends? → tails (longest chain to the exit)
                 │         → play the room for 2..6 players and for "unlimited"
                 ▼
             report.js     table, timeline, hint deadlines, warnings
```

## 2. File tour

| File | Job |
|---|---|
| `src/parse.js` | The room format, name and item rules, limits |
| `src/analyse.js` | Reachability, the puzzles that matter, tails, dead ends and the simulation |
| `src/report.js` | The table, the per-player timeline and the hint deadlines |
| `bin/lockpace.js` | Bounded, symlink-free reading and exit codes |
| `tests/lockpace.test.js` | Parsing, structure, scheduling invariants on 200 random rooms, hostile input and the command line |

## 3. Key ideas

### A room is a project schedule in disguise
Each puzzle is a **job** with a duration and a crew size. It can start only once the items it needs exist. The players are the **shared resource**. Project managers know this as the *resource-constrained project scheduling problem* (RCPSP): the classic "how long will the build take with 4 workers?" question. It's NP-hard, so Lockpace uses the standard practical method and states a floor to compare against.

### Critical-path list scheduling
1. For every puzzle, compute its **tail**: its own time plus the longest chain of puzzles after it, down to the exit.
2. Play the room as a series of events. Whenever players are free, start every waiting puzzle whose items exist and whose crew fits, **longest tail first**.
3. Jump to the next moment a puzzle finishes, add what it gives, and repeat until the goal item appears.

Starting the longest tail first is what a good team does by instinct: work on whatever is holding up the most.

### The floor no team can beat
Two simple facts give a lower bound:
- **Chain:** even with unlimited players, the room takes at least as long as its longest chain. That's the "unlimited" run.
- **Work:** `k` players can't do more than `k` person-minutes of work a minute, so it takes at least (total person-minutes) / `k`.

The larger of the two is the "At best" column. When the simulation matches it, the result is proven optimal.

### Hint deadlines come from tails
If a puzzle has a tail of 37 minutes, then even with every player helping, starting it later than 60 − 37 = 23 minutes means missing the clock. That makes it a firm, explainable rule for a game master: "if nobody's touched the bookshelf by 23:00, nudge them".

### Dead ends from used-up items
A `uses` item disappears when used. If two puzzles use up the same item and only one exists, a team that uses it in the wrong place can never finish. Lockpace compares how many of each item can exist with how many puzzles use one up.

### JavaScript features you met here
- **Unicode property escapes** (`\p{L}`, `\p{Cc}`, `\p{Cf}` with the `u` flag) to allow letters in any script while refusing control and invisible characters.
- **`TextDecoder` with `fatal: true`** to reject invalid UTF-8 instead of silently replacing bytes.
- **`O_NOFOLLOW`** when opening files from Node, and a manual read loop capped at the limit.
- **JSDoc types checked by `tsc --checkJs --strict`**: type safety without a build step.

## 4. Interview questions you might get

**Q: Why integer tenths of a minute?**
A: Puzzle times like 8.5 minutes become 85, so adding times and comparing finish times is exact. With floating point, 0.1 + 0.2 ≠ 0.3 and two "equal" events could be processed in the wrong order.

**Q: Your scheduler isn't optimal. Why not search for the best schedule?**
A: Scheduling with shared workers is NP-hard, so an exact search can explode on a 60-puzzle room. The list scheduler is linear-ish and well understood. The floor shows when it's already optimal (most of the table here) and how far it could be off when it isn't. For a small room, branch and bound would be a good extension.

**Q: What stops a malicious room file from attacking someone's terminal?**
A: Every line has to match a strict pattern, and names and items can only contain a fixed set of characters. Control characters like ESC (which start terminal escape sequences) and invisible characters like U+202E (which reverses text direction) are refused outright. Error messages never include the input, so even rejected text never reaches the screen.

## 5. Ideas to extend it

1. **Uncertain times:** give each puzzle a range (3–8 min) and run the room many times to show the spread of finish times and the chance of escaping.
2. **Hints in the simulation:** model a hint as cutting a puzzle's time in half after its deadline, to see how many hints a typical team needs.
3. **Exact schedules for small rooms:** branch and bound over the start order, pruned by the floor, to prove the best possible time.
