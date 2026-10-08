# How Roomwright works

A friendly walkthrough so you can explain every part of it.

## 1. The big picture

```
 room file ──▶ parse.c ──▶ Room (puzzles, items, start)
                               │
                               ▼
                           solve.c   explores EVERY order of play
                      ┌────────┼──────────────┐
                      ▼        ▼              ▼
                can it be    traps        fastest route
                escaped?   (+ shortest      (least total
                            way in)          minutes)
                                              │
                                              ▼
                                        schedule.c  splits the route across players
                                              │
                               report.c ◀─────┘  map, timeline, problems
                                  │
                               main.c  exit code 0 / 1 / 2
```

## 2. File tour

| File | Job |
|---|---|
| `src/room.h` | The data model (`Room`, `Puzzle`, `Analysis`, `Schedule`) and every limit in one place |
| `src/parse.c` | Reads the text format against an allow-list; every error names a line, never the text |
| `src/solve.c` | The state-space search: reachability, traps, and the least-work route |
| `src/schedule.c` | Turns the route into a dependency graph, finds the critical path, and list-schedules it |
| `src/report.c` | Prints the report and the text timeline |
| `src/main.c` | Arguments, reading at most 64 KB, exit codes |
| `tests/test_room.c` | 3,597 unit checks, including random rooms against a slow reference search |
| `tests/test_cli.sh` | 31 command-line checks, including hostile input |

## 3. Key ideas

### A state is two numbers
Everything the team has done fits in two 64-bit integers: `solved` (bit *i* set means puzzle *i* is done) and `inv` (bit *j* set means the team holds item *j*). Solving puzzle *p* is just bit arithmetic:

```c
can solve:  !(solved >> p & 1) && (inv & needs) == needs
afterwards: solved | 1 << p,   (inv & ~consumes) | gives
```

That is why there are at most 62 puzzles and 64 items: they have to fit in the bits.

### Searching every order of play
Starting from the start state, breadth-first search tries every puzzle that can be solved, then every puzzle after that, and so on. A hash table (open addressing, with the splitmix64 mixer to spread similar states apart) makes sure each state is stored once, however many orders lead to it. With 9 puzzles there could be up to 362,880 orders (9 factorial), but the clockmaker room has only 34 distinct situations.

### Why the layers matter
Every move solves exactly one more puzzle, so a state's depth is simply how many puzzles are solved. Breadth-first search therefore visits the states layer by layer, and every move goes from one layer to the next. That gives three things almost for free:

1. **Can the team still win from here?** Walk the states *backwards*. A state wins if it holds EXIT or any move from it leads to a winning state, and those states were already decided because they come later.
2. **Traps.** A trap is a move from a winning state into a losing one. Scanning in breadth-first order means the first time each trap is seen, the route to it is the shortest possible.
3. **The fastest route.** One forward pass of "relaxation" (the core step of Dijkstra's and Bellman-Ford's algorithms) is enough, because the layers are already in a valid order: a so-called topological order.

### Why traps need used-up items
If nothing is ever used up, the team only gains items, so anything solvable now stays solvable later. No move can hurt, and there can be no traps. The tests check this on 300 random rooms. It is also the practical design advice: traps only come from consumable items, so check every `*`.

### From a route to a timeline (`schedule.c`)
A route is a list, but a team works in parallel. Each puzzle depends on whichever earlier puzzle gave it each item. A puzzle that uses an item up also waits for anyone still reading that item. Then:

- **Critical path:** the longest chain of dependencies. No team, however big, can finish faster.
- **List scheduling:** when a player is free, give them the puzzle that can start soonest; on a tie, pick the one with the most work waiting behind it. That is a classic greedy rule, close to optimal for small graphs, and easy to explain.

### Careful C
- `memset` + fixed-size arrays: no structure grows while reading input, so there is nothing to overflow.
- Numbers are parsed by hand from at most four digits, so they can never overflow an `int`.
- `fail()` is marked `format(printf)`, so the compiler checks every error message's format string.
- The only heap memory is allocated once in `room_analyse`, and a single `goto done` frees it on every path.

## 4. Glossary

| Term | Plain version |
|---|---|
| Softlock | The game is still running but can no longer be won |
| State space | Every situation the team could possibly be in |
| BFS | Breadth-first search: explore everything one step away, then two steps, and so on |
| Bitset | Using the bits of an integer as a set of yes/no flags |
| Critical path | The longest chain of tasks that must happen one after another |
| Makespan | How long until the last task finishes |
| Topological order | An ordering where every arrow points forwards |

### C features you met here
- **`uint64_t` bitsets** with `&`, `|`, `~` and shifts, and the `s &= s - 1` trick to count bits.
- **Fixed-size arrays inside structs** and **`static` storage** for the biggest objects (the 64 KB input buffer, the room and the analysis), keeping them off the stack.
- **Open-addressing hash table** written by hand.
- **`goto` for cleanup:** the standard C pattern for freeing resources on every exit path.
- **Variadic functions** (`va_list`) and **compiler attributes** behind a portability macro.
- **Sanitizers** (`-fsanitize=address,undefined`), **`-fanalyzer`** and **Valgrind**: the modern C safety net.

## 5. Interview questions you might get

**Q: How do you know your solver is right?**
A: Three ways. It's cross-checked against a slow, obviously correct recursive search on 400 random rooms. Every trap it reports is replayed independently to confirm the room really is lost. And a theoretical property is tested: without used-up items there can be no traps. All of this runs under AddressSanitizer and UndefinedBehaviorSanitizer.

**Q: The number of orders grows factorially. Why is this fast?**
A: I search states, not orders. Many orders lead to the same (solved, inventory) pair, and the hash table stores each pair once. The worst case is still exponential, so there is a hard cap of 200,000 states, and the tool says honestly when a room is too big and suggests splitting it into stages.

**Q: Why write it in C, and how did you keep it safe?**
A: C makes the bitset state very compact and the search very fast, and it was a chance to practise defensive C. The measures: fixed limits on everything; an allow-list parser that only accepts printable ASCII; no unsafe string functions; hand-written number parsing; one allocation freed on every path; warnings treated as errors; and sanitizers, a static analyser and Valgrind in the test routine.

## 6. Ideas to extend it yourself

1. **Hints:** for any state, print the next puzzle on a winning route. That is exactly what a game master needs during a live game.
2. **Counts of items:** allow "2 x coin" by storing small counters instead of single bits.
3. **Graph export:** write the dependency graph as Graphviz DOT, colouring the trap moves red.
