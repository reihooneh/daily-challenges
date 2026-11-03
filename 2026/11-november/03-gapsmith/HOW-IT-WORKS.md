# How Gapsmith works

A walkthrough so you can explain every part of it.

## 1. The big picture

```
 layout.txt ──▶ Layout.java    sections (track a/b, turnout p/s/d) and joins
                    │
                    ▼
               Polarity.java   signed graph: each join says "same polarity" or "opposite"
                    │          breadth-first 2-colouring → consistent, or an odd loop
                    ▼
               Planner.java    every connected run of ≤ 8 sections that holds the train
                    │          → one reversing section that fixes everything? else two
                    ▼
               Report.java     the short circuit, the cuts, the wiring list
```

## 2. File tour

| File | Job |
|---|---|
| `src/gapsmith/Layout.java` | The file format, lengths in m/cm/mm, ends and joins, and the rule for whether rails continue or cross |
| `src/gapsmith/Polarity.java` | The signed graph, colouring by breadth-first search, and recovering the odd loop |
| `src/gapsmith/Planner.java` | Enumerating connected runs (the ESU algorithm), checking each, and choosing the best one or two |
| `src/gapsmith/Report.java` | The printed plan |
| `src/gapsmith/Main.java` | Bounded, link-free reading, strict UTF-8 and exit codes |
| `tests/gapsmith/Tests.java` | 1,000 checks: parsing, hostile input, known layouts, brute force on random layouts, the command line |

## 3. Key ideas

### Rails as a signed graph
Give every section a polarity, +1 or −1: which of its two rails is the "red" one. Name each section's rails facing from its start end (a for track, p for a turnout). Then a join between two ends is one of two kinds:
- **Rails continue:** an end meets a start (`main.b` to `t.p`). The left rail meets the left rail, so both sections must have the **same** polarity.
- **Rails cross:** two starts or two ends meet nose to nose (`loop3.b` to `t2.d`). The left rail meets the right rail, so the polarities must be **opposite**.

Sections are vertices and joins are edges labelled "same" or "opposite": a **signed graph**. A wiring exists exactly when the graph is *balanced*, which means every loop has an even number of "opposite" edges. A reversing loop is a loop with an odd number.

### Checking it: 2-colouring by breadth-first search
Start anywhere with +1 and spread out: across a "same" join copy the polarity, across an "opposite" join flip it. If you ever reach a section that already has the wrong polarity, the graph is unbalanced. Following both sections' breadth-first parents back to where they meet gives the odd loop, which the report prints. This is the same algorithm as testing whether a graph is bipartite, and it's O(sections + joins).

### Fixing it: reversing sections
Cutting a join isn't enough on its own, because the track still has to be powered. So a reversing section is a set of sections, gapped off at every boundary join and fed by an auto-reverser that can flip it. A plan works when:
1. **The rest balances:** with the reversing sections removed, the rest of the layout is balanced.
2. **Each section balances inside:** each reversing section is balanced on its own, so it can be fed with one polarity at a time.
3. **Each section holds the train:** each reversing section is longer than the longest train. Otherwise a train bridges both gaps while the reverser is mid-flip, and the reverser trips.

Choosing the fewest edges to make a signed graph balanced (its *frustration index*) is NP-hard in general. But a layout's reversing sections are short runs of track, so Gapsmith searches them completely. It considers every connected run of up to 8 sections, then pairs of separate runs when one isn't enough. It prefers the fewest auto-reversers, then the fewest cuts, then the shortest sections.

### Enumerating connected runs once each: ESU
Listing connected subgraphs naively finds the same set many times. The ESU algorithm (Wernicke, 2006) grows a set only with neighbours numbered higher than its starting vertex, and only through each new vertex's *exclusive* neighbours (ones not already next to the set). That way every connected set is produced exactly once.

### Java features you met here
- **Records** (`Section`, `End`, `Join`, `Plan`) for immutable data with free `equals` and `toString`.
- **Switch expressions** and **text blocks** (the test layouts).
- **`Files.readAttributes(..., NOFOLLOW_LINKS)`** to refuse symbolic links and devices, and a strict `CharsetDecoder` that reports bad UTF-8 instead of replacing it.

## 4. Interview questions you might get

**Q: Why does a wye short-circuit but an oval doesn't?**
A: Going round an oval, every join keeps left rails on the left, so the loop has zero crossings, which is even. A wye's three legs bring a train back facing the other way, which puts exactly one "opposite" join in the loop. An odd number of opposite joins can't be wired consistently. That's the parity argument the 2-colouring checks.

**Q: How do you know the planner finds the best plan?**
A: Within its limits it's exhaustive, and the tests check it against brute force. On 400 random layouts they try every subset of sections as the reversing area and score each by auto-reversers, cuts and length. The planner's answer must match the best one every time.

**Q: Why must the reversing section be longer than the train?**
A: An auto-reverser flips the section's polarity when a wheel bridges a gap and causes a brief short. If the train is longer than the section, its metal wheels or lit coaches bridge both gaps at once. Then it shorts against the main line whichever way the section is set, and the reverser trips over and over.

## 5. Ideas to extend it

1. **Frog gaps:** model power-routing turnouts, whose frogs need their own gaps and polarity switching.
2. **Power districts:** split the wired track into booster districts of balanced current draw, with cuts placed where they're cheap.
3. **Read track-planner files:** import the joins straight from a track-planning program's export, instead of writing them by hand.
