# How Hellbox works

## 1. Architecture

```
case.txt ──ParseCase──▶ Case {glyph → count}
job.txt  ──ParseJob───▶ []Page {letters needed, ligature chances}
subs     ──DefaultSubs / ParseSubs──▶ []Sub {glyph ← sorts, cost}
                              │
            PlanJob ── for each page: Solve(alone)? ── no ──▶ "can't be set" list
                              │ yes
                  branch and bound over groupings (≤ 14 pages) or first-fit
                  each candidate forme checked by Solve (cached by page set)
                              │
            Solve(pages): ligatures → multi-sort subs (enumerated) → min-cost flow
                              │
            Shopping: Solve with buying allowed, per forme → largest shortfall per sort
                              │
                        Report (text)
```

## 2. File tour

- **`internal/hellbox/input.go`:** the three file formats, their limits, page counting (with ligatures found longest-first), the default substitutions, and `Show` for printing glyphs safely.
- **`internal/hellbox/flow.go`:** a min-cost flow (successive shortest paths with Bellman–Ford).
- **`internal/hellbox/setting.go`:** `Solve`, one forme. It applies ligatures, tries counts of the multi-sort substitutions, and builds and reads the flow network.
- **`internal/hellbox/plan.go`:** `PlanJob` (first-fit, branch and bound, the lower bound) and `Shopping`.
- **`internal/hellbox/report.go`:** the text report.
- **`cmd/hellbox/main.go`:** flags, safe file reading, exit codes.
- **Tests:** `internal/hellbox/hellbox_test.go` (brute-force checks, hostile input, fuzzing) and `cmd/hellbox/main_test.go` (the examples, links and folders).

## 3. Key concepts and language features

**Letters as a flow.** Picture three columns: the letters the text needs, the sorts in the case, and pipes between them.
- A needed letter has a pipe to its own sort, which costs nothing.
- It also has a pipe to each substitute, costing the substitute's looks (a turned n for a u costs 2).
- Each sort's pipe to the sink can carry as many as the case holds.

Send all the needed letters through as cheaply as possible. If they all get through, the forme can be set, and the flow on each pipe says exactly what is used. That is a *min-cost flow*. Successive shortest paths solves it: keep sending flow along the cheapest route that still has room, and let earlier choices be undone through reverse edges.

**Why VV is handled separately.** A flow sends one unit in and one unit out. But a W made of VV uses two V sorts for one letter, and an ordinary flow can't express that. Such substitutions are rare, so `Solve` tries each count of them (0, 1, 2, ...), takes those sorts out of the case first, and runs the flow on the rest. The cheapest combination wins.

**Buying as one more pipe.** With buying allowed, each needed letter gets a pipe straight to the sink, costing 10,000. That is more than any amount of substitution, so the cheapest flow buys as few sorts as possible. The same solver then answers "what's the least I can buy?"

**Grouping pages.** Whether pages fit together in a forme isn't additive: substitutions may cover one pair of pages but not another. So the planner asks `Solve` directly.
- It sorts pages biggest first and places each in the first forme where it still fits (first-fit decreasing).
- It then searches every grouping depth-first, never opening a new forme unless that could beat the best plan so far (branch and bound).
- Results are cached by a bitmask of the page set (`map[uint64]bool`), so each group is solved once.

A lower bound shows when first-fit is already the best possible, for bigger jobs. It is the larger of two numbers:
- the number of pages divided by how many fit on the press;
- for each letter, the total needed divided by every sort that can print it (including substitutes).

**Go features.**
- Maps keyed by a `Glyph` string type.
- Closures for the recursive searches (`var walk func(int)`).
- `flag.NewFlagSet` with `ContinueOnError`, so `run` can be tested without exiting.
- `os.Lstat` to see a link rather than follow it.
- Native fuzzing (`FuzzParse`) and the race detector.

## 4. Interview questions

**Q: Why is min-cost flow the right tool for substitutions, rather than a greedy rule?**
A: Greedy decisions interact. Suppose the text needs u and n, and the case is short of u. Greedily setting every u as a turned n can leave too few ns for the ns themselves, while another split works. The flow considers all letters at once and can undo an earlier choice through a reverse edge. A test checks it against brute-force enumeration on 300 random cases.

**Q: How do you know the planner really finds the fewest formes?**
A: Two ways. For up to 14 pages the search is exhaustive: branch and bound only prunes branches that can't beat the best plan found so far. Tests compare it with a separate brute force that tries every partition, on 40 random jobs. For bigger jobs the report only claims "fewest" when first-fit matches the lower bound; otherwise it says what the bound is.

**Q: How do you stop a malicious file making it run forever?**
A: Everything is bounded:
- files are capped at 256 KB, with at most 400 sorts and 200 pages;
- the exact search runs only up to 14 pages;
- multi-sort substitution combinations are capped at 4,000 per forme (with fewer, evenly spread counts beyond that);
- the flow runs in polynomial time.

A test runs the biggest kind of job, and fuzzing feeds the parsers random input.

## 5. Extension ideas

- **Measure the line:** add each sort's set width and the line length (the measure), and check that each line justifies with the spaces available.
- **Several fonts:** let a heading come from a different font or size, sharing figures and punctuation.
- **Best grouping for shopping:** search groupings while buying is allowed, rather than grouping consecutive pages.
