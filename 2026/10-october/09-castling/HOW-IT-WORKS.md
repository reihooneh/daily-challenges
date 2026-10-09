# How Castling works

A friendly walkthrough so you can explain every part of it.

## 1. The big picture

```
 breakdown ──▶ parse.js ──▶ Play (scenes, cues, change times, together/apart)
                               │
                               ▼
                          timeline.js   puts every entrance and exit on a clock
                               │        and answers "could one actor play A and B?"
                               ▼
                            plan.js     builds the clash graph between roles
                               │
                    ┌──────────┴───────────┐
                    ▼                      ▼
              colour.js               colour.js
            largest clique         smallest colouring
            (why it can't be       (the cast), then the
             any smaller)           safest one of that size
                    └──────────┬───────────┘
                               ▼
                          report.js ──▶ cli.js ──▶ exit code 0 / 1 / 2
```

## 2. File tour

| File | Job |
|---|---|
| `src/parse.js` | Reads the breakdown line by line against allow-lists; errors name the line, never the text |
| `src/timeline.js` | Scene clock, each role's time on stage, and the pair check |
| `src/colour.js` | Exact graph colouring (DSatur branch and bound) and largest clique, both with step budgets |
| `src/plan.js` | Merges planned doubles, builds the clash graph, finds the smallest and then safest cast |
| `src/report.js` | The printed plan and problem list |
| `src/cli.js`, `bin/castling.js` | Arguments, reading at most 64 KB, exit codes |
| `tests/castling.test.js` | 22 tests, including brute-force cross-checks |

## 3. Key ideas

### Casting is graph colouring
Draw a dot for every role, and a line between two roles that one actor *cannot* play. Give each actor a colour. A plan is then a way of colouring the dots so that no line joins two dots of the same colour, and the smallest cast is the fewest colours that works. Mathematicians call that number the **chromatic number**. The famous four-colour map problem is the same question about countries on a map.

### When can one actor play two roles?
`pairing()` takes every moment both roles are on stage, sorts them by time and walks along:

- If the two roles are ever on stage at once, the answer is no.
- Each time the actor would switch from one role to the other, the time offstage (scene changes and intervals included) must be at least the change time of the costume they're getting into. The smallest leftover, the **spare** time, measures how comfortable the double is.

A nice fact makes this efficient: if roles A, B and C are pairwise compatible, one actor can play all three. Any two appearances that are next to each other in the three-role timeline are also next to each other in the timeline for just that pair, so checking pairs is enough.

### Finding the fewest colours exactly (DSatur)
Graph colouring is NP-hard, so there is no known shortcut that is always fast. But casts are small, and a well-guided search is quick:

- **DSatur** colours the most constrained role next: the one whose neighbours already use the most different colours, because it has the fewest choices and fails soonest.
- **Branch and bound:** once a plan with *k* actors is found, any partial plan that already needs *k* is abandoned.
- **Stop early:** the largest clique (a group of roles that all clash with each other) is a lower bound. If the search finds a plan that size, it is provably optimal and stops.

Both searches carry a step budget. If it runs out, the best plan found so far is still returned, and the report says so.

### Safest, not just smallest
There can be many 7-actor plans, and some rely on a 10-second quick change. To find the safest, Castling asks "is there still a 7-actor plan if every change needs at least *t* seconds spare?" Raising *t* only ever adds clashes, so the answer goes from yes to no exactly once. A **binary search** over the spare times that actually occur finds the largest *t* that still works, in a handful of colouring runs.

### Planned doubles and separations
`together a b` is handled before colouring by merging the two roles into one dot (a union-find structure), after checking that the double is actually possible. `apart a b` just adds a line between them.

## 4. Glossary

| Term | Plain version |
|---|---|
| Doubling | One actor playing more than one role |
| Quick change | A costume change with very little time; usually rehearsed with a dresser |
| Graph | Dots (vertices) joined by lines (edges) |
| Chromatic number | The fewest colours that colour a graph with no line joining two of the same colour |
| Clique | A group where every pair is joined: all need different colours |
| Branch and bound | Searching all options but skipping any that can't beat the best found |
| NP-hard | No known method is fast for every input; clever search works well in practice |

### JavaScript features you met here
- **ES modules** (`import`/`export`, `"type": "module"`) and **`node:` built-ins** with no dependencies.
- **JSDoc types checked by `tsc --checkJs --strict`**: type safety without a build step.
- **Closures** for the recursive searches, with shared state like the step budget.
- **`Map` and `Set`**, **destructuring**, spread syntax and **`Array.from`** to build matrices.
- **Regular expressions with capture groups** (`CUE`) to read `mara>2:00<1:30` in one go.
- **`TextDecoder` with `fatal: true`** to reject invalid UTF-8 instead of silently replacing it.
- **`node:test`** and **`node:assert/strict`**, Node's built-in test runner.

## 5. Interview questions you might get

**Q: Graph colouring is NP-hard. Isn't that a problem?**
A: In theory, yes; in practice, casts are small. DSatur branch and bound with a clique lower bound proves the minimum quickly on real plays (60 roles at most), and a step budget guarantees it stops on adversarial input. When the budget runs out the tool still returns a valid plan and says it may not be optimal. Brute-force cross-checks on hundreds of random cases give me confidence that the exact answers are right.

**Q: How does the "safest plan" search work?**
A: Requiring at least *t* seconds of spare time only adds edges to the graph, so whether a *k*-actor plan exists is monotone in *t*. That allows a binary search over the distinct spare values that occur, with one colouring per step. The result maximises the tightest change among plans of the minimum size, and a brute-force test confirms it.

**Q: Why is checking pairs of roles enough?**
A: Because every switch an actor makes is between two consecutive appearances, and those two appearances are also consecutive in the timeline for just that pair of roles. So if every pair of an actor's roles fits, the whole set fits. That turns a question about groups into a graph, which is what makes the colouring approach valid.

## 6. Ideas to extend it yourself

1. **Read a real script:** detect entrances and exits from stage directions (as ACTORS did) and write the breakdown automatically.
2. **Costume-to-costume times:** some changes are quicker than others (a hat versus full make-up); use a matrix of times instead of one per role.
3. **A visual chart:** draw each actor's evening as a timeline, with tight changes in red, as an HTML page with a strict Content-Security-Policy.
