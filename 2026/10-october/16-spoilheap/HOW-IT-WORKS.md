# How Spoilheap works

A walkthrough so you can explain every part of it.

## 1. The big picture

```
 record.txt ──▶ Record::parse()      strict line-by-line reading: relations, "same", dating clues
                    │
                    ▼
               Matrix                merge "same" numbers (union-find) → a directed graph
                    │                later deposit ──▶ earlier deposit
                    ├─ loops:        Tarjan's strongly connected components; for each tangle,
                    │                the fewest relations to drop (exhaustive up to 4), tie-broken by the dates
                    ├─ redundant:    is the relation implied by another path? (breadth-first search)
                    └─ phases:       longest chain underneath + 1, in topological order
                    │
                    ▼
               Dating                "no earlier than" goes up, "no later than" goes down;
                    │                conflicting pairs → fewest clues to question (König's theorem)
                    ▼
               Report                problems, phases with date windows, tidy-ups, or --dot
```

## 2. File tour

| File | Job |
|---|---|
| `src/Record.php` | The file format, every limit, and clear errors with line numbers |
| `src/Matrix.php` | The graph: merging, loops, the smallest fix, redundant relations, phases |
| `src/Dating.php` | Date windows, conflicting clues, and the minimum set to question |
| `src/Report.php` | The text report and Graphviz DOT |
| `src/Cli.php` | Arguments, safe file reading, exit codes |
| `bin/spoilheap` | A launcher with a fixed autoloader |
| `tests/run.php` | 61 checks, including brute force against the clever algorithm |

## 3. Key ideas

### The Harris matrix is a directed graph
Each deposit is a node. "1001 above 1002" is an edge from the later deposit to the earlier one. A real site can't have a loop (nothing is both over and under something else), so a correct record is a **directed acyclic graph (DAG)**. Two numbers recorded as the "same" deposit are merged first with **union-find**, so relations recorded against either number join up.

### Finding loops: strongly connected components
In a directed graph, a **strongly connected component** is a group of nodes where each can reach every other. Any loop lives entirely inside one, so a component with more than one node is a tangle to fix. Spoilheap uses **Tarjan's algorithm**, one depth-first search in linear time. It's written with an explicit stack instead of recursion, so a 500-layer sequence can't overflow PHP's call stack.

### The fewest relations to re-check
Removing the fewest edges to make a graph acyclic is the **minimum feedback arc set** problem, which is NP-hard. But a single tangle on a dig is usually small. So Spoilheap tries every set of 1 relation, then 2, up to 4, smallest first; the first size that works is provably the minimum. If several sets of that size work, it asks the **finds**: it prefers the fix that leaves the fewest pairs of contradictory dates, because dating evidence is independent of the diggers' notes. Only then does it pick the relation written latest. For a huge tangle it falls back to dropping every *back edge* of a depth-first search, which always gives a valid order, and it says that this list may not be the smallest.

### Dates travel through the sequence
- A find made from 1840 means its layer, **and every layer above it**, formed in 1840 or later (a *terminus post quem*).
- A layer known to be sealed by 1880 means it, **and every layer below it**, formed by 1880 (a *terminus ante quem*).

So each deposit's window is: the latest lower bound from itself and everything underneath, and the earliest upper bound from itself and everything above. Spoilheap works out "everything underneath" for each deposit once, in topological order, then reads every window off it.

### Which clues to question: König's theorem
Two clues conflict when a lower bound sits at or below an upper bound with a smaller year. Draw every conflict as an edge between a lower-bound clue and an upper-bound clue. The graph is **bipartite** (lower bounds on one side, upper bounds on the other), and the fewest clues to question is a **minimum vertex cover**. In general that's NP-hard, but **König's theorem** says that in a bipartite graph it's exactly as big as a **maximum matching**, which augmenting paths find quickly. The cover is then read off by walking alternating paths from the unmatched lower bounds. The tests check the answer against brute force on 60 random sites.

Old finds in later layers (*residual* finds, like a Roman coin in a medieval pit) are normal. Because a find only gives a lower bound, they never cause a conflict, which is the archaeologically right behaviour.

### Phases
A deposit's phase is the length of the longest chain of deposits under it, plus one, so the bottom layers are phase 1. That's a longest-path calculation, easy on a DAG in topological order (Kahn's algorithm).

### PHP features you met here
- **`declare(strict_types=1)`** and typed properties, parameters and return types, which caught a real bug: PHP turns array keys like `"1001"` into the integer 1001. Internal node names get a `g` prefix to keep them strings.
- **`readonly` promoted constructor properties** (`public readonly Record $record`).
- **Generators** (`yield from`) to list combinations without building them all in memory.
- **`match`** expressions for the wording.
- **Unicode regular expressions** (`\p{L}`, the `/u` flag) to allow notes in any script.
- **`php://memory` streams** so the tests can run the command line without files.

## 4. Glossary

| Term | Plain version |
|---|---|
| Context | One recorded layer, cut or fill, with its own number |
| Harris matrix | The diagram of which contexts are earlier and later |
| Terminus post quem (TPQ) | "Formed no earlier than": usually from the latest find in it |
| Terminus ante quem (TAQ) | "Formed no later than": from something that seals it |
| Intrusive find | A later object that worked its way down into an earlier layer |
| Residual find | An older object redeposited in a later layer |
| Feedback arc set | Edges whose removal leaves no cycles |
| Vertex cover | A set of nodes touching every edge |

## 5. Interview questions you might get

**Q: Minimum feedback arc set is NP-hard. Isn't trying combinations too slow?**
A: It's exponential in the *answer size*, not the site size. Real tangles need one or two corrections, and each test of a candidate set is linear. I cap the search at 4 relations and 200,000 combinations, and beyond that use a DFS back-edge method that always gives a valid order but says it might not be minimal. That's an honest trade-off: exact when it's cheap, safe when it isn't.

**Q: Why König's theorem rather than brute force for the dates?**
A: The conflict graph is bipartite by construction, because every conflict is between a lower bound and an upper bound. In bipartite graphs the minimum vertex cover equals the maximum matching, which runs in polynomial time with augmenting paths. So the "fewest clues" answer is exact even with hundreds of clues. I still test it against brute force on random small cases.

**Q: How does it choose between equally small fixes for a loop?**
A: It uses independent evidence. The finds weren't written by the person who wrote the relations, so the fix that leaves the dates most consistent is most likely right. Only if that's tied does it fall back to "the most recent entry", which is a weaker heuristic and is documented as one.

## 6. Ideas to extend it

1. **Probabilities instead of hard bounds:** model find dates as distributions and give each layer a likely date range (Bayesian phasing, as radiocarbon tools do).
2. **Spatial checks:** add plan coordinates and heights, and flag "above" relations between layers that never touch.
3. **A web version** that draws the matrix with the relations to re-check highlighted, for use on a tablet in the trench.
