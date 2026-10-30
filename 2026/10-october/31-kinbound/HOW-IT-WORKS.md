# How Kinbound works

A walkthrough so you can explain every part of it.

## 1. The big picture

```
 family.txt ──▶ parse.rs    strict line shapes → people, records, rules
                   │
                   ▼
               solve.rs     each record → inequalities  "born(Sarah) − died(Thomas) ≤ 1"
                   │        one graph: a node for year zero, a birth and a death node per person
                   ▼
               graph.rs     Bellman-Ford: negative cycle?  ── yes ─▶ conflict chain
                   │                   │                               │
                   │ no                │                    search: fewest lines to drop
                   ▼                   ▼                               │
               shortest paths from year zero (forwards and backwards) ◀┘
                   │
                   ▼
               report.rs    conflicts, fixes, a table of ranges, and --why chains
```

## 2. File tour

| File | Job |
|---|---|
| `src/parse.rs` | The family file: line shapes, dates ("about 1841", "1840-1842", ...), names, ids, rules and limits |
| `src/graph.rs` | Difference constraints as a graph: negative-cycle detection, shortest paths and path recovery |
| `src/solve.rs` | Turns records into constraints, finds conflicts and the smallest fixes, and computes bounds |
| `src/report.rs` | The printed report and the `--why` explanations |
| `src/lib.rs`, `src/main.rs` | The `run` function, bounded reading and exit codes |
| `tests/kinbound.rs` | 16 tests: records, conflicts, a brute-force cross-check, hostile input and the command line |

## 3. Key ideas

### Every family fact is a difference constraint
Give each person two unknowns, `born(p)` and `died(p)`, plus a fixed `zero` for the year 0. Then every record is one or two inequalities of the form `x − y ≤ c`:

| Record | Constraints |
|---|---|
| `born mary 1815` | `born(mary) − zero ≤ 1815` and `zero − born(mary) ≤ −1815` |
| `census mary 1841 age 25` | `born(mary)` between 1815 and 1816 |
| `mother hannah of mary` | `born(mary) − born(hannah)` between 14 and 50, and `born(mary) − died(hannah) ≤ 0` |
| `father thomas of sarah` | the same with 15 to 80, and `born(sarah) − died(thomas) ≤ 1` |
| every person | `born(p) − died(p) ≤ 0` and `died(p) − born(p) ≤ 105` |

A system like this is a graph: each `x − y ≤ c` is an edge from `y` to `x` with weight `c`. Walking along a path adds the inequalities up, so a path from `zero` to `x` of length `L` proves `x ≤ L`.

### Bounds are shortest paths
- **Latest possible year** of `x` = the shortest path from `zero` to `x`.
- **Earliest possible year** = minus the shortest path from `x` back to `zero` (computed as a shortest path on the reversed edges).

These bounds are *exact*, not just safe: for difference constraints, setting every variable to its shortest-path distance satisfies all the constraints at once, so every year inside a reported range is reachable by some consistent reading of the records. The brute-force test checks exactly this by trying every combination of years in a 26-year window.

### A contradiction is a negative cycle
If a cycle of edges adds up to a negative number, summing its inequalities gives `0 ≤ negative`: impossible. Bellman-Ford finds one: start every node at 0, relax every edge `n` times, and if anything still improves on round `n`, walk back along the "last improved by" pointers `n` steps to land inside the cycle, then follow it round. The cycle's weight is how many years the records miss by.

### The fewest records that must be wrong
Every fix has to remove at least one record from *every* conflict. So the search takes one conflict, tries dropping each of its record lines, looks for the next conflict, and so on, up to 3 lines deep (iterative deepening, so the first fixes found are the smallest). Rules of thumb are never dropped, only records. This is a minimum hitting set, which is NP-hard in general, so the search has a budget of 4,000 consistency checks.

Of several equally small fixes, the one shown is the one that keeps the other ranges narrowest: it throws away the least information.

### Rust features you met here
- **Slice patterns** in `match` (`["about", y]`, `[id, date @ ..]`) make the parser read like the file format.
- **`let ... else`** for early returns, and `Option` combinators (`then_some`, `is_none_or`) instead of sentinel values.
- **Closures as filters** (`&dyn Fn(&Edge) -> bool`) so one Bellman-Ford serves "all records" and "all but these lines".
- **`unsafe_code = "forbid"`** in Cargo's `[lints.rust]`, and `overflow-checks = true` in release builds.

## 4. Interview questions you might get

**Q: Why Bellman-Ford rather than Dijkstra?**
A: The weights are negative ("born at least 14 years later" is `−14`), and Dijkstra's greedy choice is wrong with negative edges. Bellman-Ford handles them and also detects negative cycles, which here are exactly the contradictions. With at most 801 nodes and a few thousand edges it runs in milliseconds.

**Q: How do you know the ranges are the tightest possible, not just valid?**
A: It's a theorem for difference constraints: the shortest-path distances from a source form a feasible solution, and every feasible solution has `x ≤ dist(x)`. So the upper bound is achieved, and by symmetry so is the lower bound. The test suite also checks it by brute force on small random families.

**Q: Why doubt records and not the rules?**
A: Records are what a researcher can recheck: order the certificate, reread the register. The rules are kept fixed so the answer is actionable, but they can be changed in the file, and when no small fix exists the report suggests that a rule may not apply (an adoption, a step-parent).

## 5. Ideas to extend it

1. **GEDCOM import:** read the standard family-tree exchange format, mapping BIRT, DEAT, BAPM, BURI, CENS and FAMC/FAMS to the same constraints.
2. **Months and days:** the same graph works with dates as day numbers, which would let it check a baptism a week after a birth.
3. **Weighted doubt:** give each kind of record a reliability (a civil certificate beats a family Bible) and look for the least-reliable set of records to drop.
