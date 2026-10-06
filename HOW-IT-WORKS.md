# How Pick Two works

A walkthrough in plain language, so you can explain every part of it.

## 1. The idea in one paragraph

A timetable is a puzzle: for each class, choose one of its possible times so that nothing overlaps and your wishes hold. A computer can solve that by trying combinations cleverly. The interesting part is what happens when there is **no** solution. Pick Two solves the same puzzle again and again with pieces left out, and from which versions work and which don't it can tell you exactly what is fighting with what, and the least you would have to give up.

## 2. Architecture

```
                     plain text (classes + wishes)
                                  │
                                  ▼
 ┌────────────────────────────────────────────────────────────────┐
 │  internal/planner  (Go, no dependencies)                        │
 │                                                                 │
 │   parse.go ──▶ Problem ──▶ solve.go ──▶ fits? ── yes ──▶ plan   │
 │   (validate)               (search)        │                    │
 │                                            no                   │
 │                                            ▼                    │
 │                                       explain.go                │
 │                              minimal conflict + ways out        │
 │                                                                 │
 │   api.go: one function, Run(text) → Response                    │
 └───────────────┬─────────────────────────────┬──────────────────┘
                 │                             │
        cmd/picktwo (native)            cmd/wasm (WebAssembly)
        prints text or JSON             returns JSON to the page
                                               │
                                     web/worker.js (background thread)
                                               │
                                     web/app.js (draws the result)
```

There is one engine and two thin shells around it. The browser never re-implements any rule in JavaScript; it turns the form into the same text the command-line tool reads and hands it over.

## 3. File tour

| File | Job |
|---|---|
| `internal/planner/model.go` | The data: courses, components, options, meetings, wishes. Also every size limit. |
| `internal/planner/parse.go` | Text to data. The only code that touches raw input. |
| `internal/planner/solve.go` | The search for the best timetable. |
| `internal/planner/explain.go` | The minimal conflict and the ways out. |
| `internal/planner/api.go` | `Run(text)`: parse, solve, explain, and package the answer. |
| `internal/planner/render.go` | The answer as plain text for a terminal. |
| `cmd/picktwo/main.go` | Command line: read a file safely, print, set the exit code. |
| `cmd/wasm/main.go` | The browser entry point: one function, text in, JSON out. |
| `web/state.js` | Form state, share links, layout maths. Pure functions, tested in Node. |
| `web/app.js` | The page: reads the form, calls the worker, draws results. |
| `web/worker.js` | Loads the WebAssembly file and runs it off the main thread. |
| `*_test.go`, `web/tests/`, `scripts/browser-check.py` | Tests at every level. |

## 4. The key ideas, explained simply

### A timetable is a constraint satisfaction problem

Three ingredients:

- **Variables:** things to decide. Here, every class of every course: "COMP1010 Tutorial".
- **Values:** the choices for each. Here, the times it is offered.
- **Constraints:** rules a full set of choices must obey. No overlaps, plus your wishes.

Sudoku, seating plans and exam scheduling are the same kind of problem.

### Backtracking search

Choose a time for the first class. Then the second. If a choice breaks a rule, undo it and try the next one. If a class runs out of choices, go back further. This is **depth-first search with backtracking**, and `descend` in `solve.go` is exactly that loop.

Two things make it fast:

1. **Filter first.** Some wishes rule out a time all by themselves ("no Fridays" removes every Friday option). Those are removed before the search starts. If a class has nothing left, the answer is already "impossible".
2. **Most constrained first.** Classes with the fewest remaining options are decided first. A lecture with one possible time isn't really a choice, and placing it early exposes clashes near the top of the search instead of deep inside it.

### Why stopping early is safe

The search gives up on a branch as soon as a rule breaks, without filling in the rest. That is only correct if adding more classes can never fix a broken rule. Every rule here has that property: more classes can only add overlaps, days, hours, and eat into a lunch break. (This is why "at most N minutes of waiting" is *not* a wish: a later class could fill a gap, so it can't be checked early. Waiting time is minimised instead.)

### Branch and bound: finding the best, not just one

After the first timetable is found, the search continues, looking for a better one: fewer days on campus, then less waiting. To avoid exploring everything, it keeps the best cost so far and skips any branch that can't beat it. Days only ever go up as classes are added, so if a partial timetable already uses as many days as the best complete one, that branch is abandoned. The name for this is **branch and bound**.

### The minimal conflict (why it's impossible)

Suppose the full problem has no solution. Which items are responsible?

```
keep = everything                      (known: impossible)
for each item:
    remove it from keep
    if still impossible:  leave it out  (it wasn't needed for the clash)
    else:                 put it back   (it was needed)
```

What is left at the end is still impossible, and taking away any single member makes it possible. Computer scientists call this a **minimal unsatisfiable subset**. It is the difference between "something is wrong" and "these three things can't all be true".

It costs one solve per item. Those solves stop at the first valid timetable, so they are quick.

### Ways out (what to give up)

A way out is a set of wishes whose removal makes a timetable possible, with nothing in the set that didn't need to go. The search is simple and exact: try each single wish, then each pair, then each triple, skipping any combination that contains an answer already found (if dropping "no Fridays" works, there's no point suggesting "no Fridays and lunch"). Each one that works is then solved properly to show the best timetable you would get.

These are called **minimal correction sets**. Conflicts and corrections are two views of the same thing: every way out has to break every conflict.

### One engine, two targets

Go can compile the same source to a normal program or to **WebAssembly**, a compact binary format browsers can run at near-native speed. `cmd/wasm/main.go` is about 35 lines: it registers one JavaScript-visible function that takes a string and returns a JSON string. Keeping the boundary that narrow means there is only one place where data crosses between languages.

### Staying responsive and bounded

- The engine runs in a **Web Worker**, a background thread, so typing never stutters.
- The solver counts its steps and stops at a budget. If it stops early it says so; it never reports "impossible" unless it really covered everything.
- The page keeps a 20-second timer and terminates the worker if it ever fires.

## 5. Trade-offs I made

| Decision | Why | Cost |
|---|---|---|
| Go compiled to WebAssembly, not a JavaScript rewrite | One engine to test; the CLI and the page can never disagree | A 3.5 MB download (1 MB compressed) |
| A hand-written solver, not a SAT/CP library | Zero dependencies; small enough to explain line by line; easy to bound | Wouldn't scale to a whole university's timetable |
| Plain text as the input format | Quick to type and paste; one parser for CLI and web | Less guided than a form for the class list |
| One minimal conflict, not all of them | One clear reason is easier to act on than five | A second, unrelated conflict only shows after the first is fixed (the ways out do account for all of them) |
| Ways out limited to three wishes | Keeps the worst case small and the advice digestible | Needing four or more falls back to "drop a course" |
| No server, no storage | Nothing to breach, nothing to pay for, works offline once loaded | No saved plans except via share links |
| Fixed work budgets | No input can hang the page | A huge problem can get the answer "couldn't finish" |

## 6. Interview questions you might get

**Q: How does the tool know *why* a timetable is impossible?**
A: It treats the solver as a yes/no oracle. Starting from the full, impossible problem, it removes one course or wish at a time and re-solves. If the problem is still impossible, that item wasn't needed and stays out; otherwise it goes back in. What remains is a minimal unsatisfiable subset: impossible as a whole, possible if you remove any one member. The explainer needs no knowledge of timetables at all, only the ability to ask "is this subset solvable?".

**Q: How do you know your solver is correct?**
A: I wrote a second, deliberately naive implementation in the tests: it enumerates every combination and checks the rules in the simplest way I could, minute by minute for the lunch rule. On 3,000 random problems the real solver must agree with it on feasibility and on the optimal days and waiting time. The explanations are tested against their definitions the same way, and a fuzz test throws arbitrary bytes at the whole pipeline.

**Q: Why WebAssembly instead of just writing it in JavaScript?**
A: I wanted the command-line tool and the web page to be the same program. With a rewrite, every rule exists twice and they drift apart. Compiling one Go package to both targets removes that whole class of bug, and a test loads the real `.wasm` in Node to confirm it matches the native output. The price is download size, which I measured and documented.

**Q: What stops someone from freezing the page with a nasty input?**
A: Three layers. The parser caps everything: courses, options, wishes, bytes. The solver counts steps and stops at a fixed budget, reporting honestly that it didn't finish. And the engine runs in a worker that the page terminates after 20 seconds. There's a test that builds the largest, most awkward input the parser accepts and asserts the work stays inside the budget.

**Q: The search is exponential in the worst case. Why is it fast in practice?**
A: Pruning. Wishes that eliminate options are applied before searching. Variables are ordered so the most constrained are placed first. Every rule can be checked on a partial timetable because adding classes never repairs a violation, so bad branches are cut immediately. And the bound on days cuts branches that can't improve on the best timetable so far. Real timetables have a handful of courses with a few options each, so the examples solve in a few milliseconds.

## 7. Ideas to extend it yourself

1. **Weighted wishes.** Let the user rank wishes, and order the ways out by total importance given up instead of by count. The search stays the same; only the sorting changes.
2. **All conflicts.** Enumerate every minimal conflict (the classic algorithm is called MARCO) and show them as a list, so the user sees the whole picture at once.
3. **Calendar import and export.** Read class times from an `.ics` file and write the chosen timetable back out, so it drops straight into a phone calendar.
