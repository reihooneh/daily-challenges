# How Bellshare works

Bellshare answers one question for a handbell director: who should ring which bells? This file covers the design, the two algorithms it uses, and the questions an interviewer might ask about them.

## 1. The big picture

```
piece file ──parse──▶ Piece (chords: time + bells)
                         │
                         ├─ bellsUsed: every bell in pitch order
                         │
                         ├─ for every run of neighbouring bells i..j:
                         │      play(): two hands through the piece, Belady's rule
                         │      cost = changes + 10 × tight + 1000 × impossible
                         │
                         ├─ best(): dynamic program over cuts of the row into runs
                         ├─ equalSplit(): the usual way, for comparison
                         │
                         └─ render(): chart, totals, change list ──▶ terminal
```

The program has two levels:
- **Inner level:** how well can one ringer manage a given set of bells? This is a caching problem.
- **Outer level:** how should the row of bells be cut between ringers? This is a partition problem.

## 2. File tour

- **`src/bellshare.hpp`:**
  - all the types: a `Piece` is a list of `Chord`s (time in beats plus the bells that sound);
  - a `Load` is what one ringer goes through (changes, tight changes, clashes);
  - an `Assignment` is one run of bells per ringer with its loads and total cost.
- **`src/parse.cpp`:**
  - the line-by-line reader: each line is matched against a small fixed set of shapes;
  - numbers go through `number()` and `whole()`, which check ranges;
  - `hidden()` and `validUtf8()` reject anything that could fool a terminal.
- **`src/assign.cpp`:**
  - `play()` is the two-handed simulation;
  - `best()` is the dynamic program;
  - `equalSplit()` and `evaluate()` build assignments from given runs.
- **`src/report.cpp`:**
  - `render()` writes the chart;
  - `run()` is the command line: argument check, bounded file reading that refuses links, BOM stripping, and exit codes.
- **`tests/tests.cpp`:**
  - hand-worked cases;
  - two brute-force oracles (every hand choice and every cut);
  - hostile files;
  - the command line, including a symlink made at test time.

## 3. Key ideas

**Hands are a cache of size two.** A ringer's two hands hold two bells. Needing a bell that isn't in hand is a cache miss, and putting one down to pick it up is an eviction. Belady showed in 1966 that evicting the item whose next use is furthest away gives the fewest misses when you know the future, and a piece of music *is* the future. `play()` precomputes each bell's ring times and finds the next one with a binary search. There are two extra rules:
- the first two pickups are free, since the ringer starts with empty hands;
- a bell needed in the same chord is never put down.

**Exact fewest, not just good.** Because Belady is optimal, the change count for a set of bells is a true minimum. The test `fewestChanges` checks it by trying both hands at every miss, over 300 random parts.

**Tight changes come from timing, not just counting.** Each hand remembers when it last rang. A change's *room* is the time between that ring and the new bell's ring. If room < `swap`, the change is tight and costs 10 instead of 1. When neither bell in hand is needed again, the tie goes to the hand that has been free longest, which gives the ringer the most room.

**Pitch-order runs keep the search small.** Handbell tables are laid out low to high, and ringers stand in that order, so each ringer gets a contiguous run of bells. With *m* bells and *r* ringers:
- `run[i][j]` is the cost of one ringer taking bells *i..j−1*. There are *O(m²)* runs, each simulated once.
- `dp[k][j]` = min over *i* of `dp[k−1][i] + run[i][j]` is the best way for *k* ringers to cover the first *j* bells, taking *O(r·m²)*.
- Ties go to the plan whose busiest ringer has the fewest bells.

Without the run restriction there would be about *r^m* assignments (5¹⁵ ≈ 30 billion for the example).

**Impossible is a cost, not an error.** Three bells at once, or more than `max-bells`, adds 1000 per problem. The dynamic program still returns the *least bad* plan, and the report says where the three-bell chord is, which is what the director needs to rewrite that bar.

## 4. Interview questions you might get

**Q: Why is Belady's rule optimal, and why can't operating systems use it?**
A: The exchange argument: take any optimal schedule that first differs from Belady by evicting bell *x* instead of the furthest-needed *y*. Swapping the roles of *x* and *y* until *x* is next needed never adds a miss, so Belady is at least as good. Operating systems don't know future page accesses, so they approximate with LRU. Here the whole piece is known, so the optimal rule is usable.

**Q: Why do you need dynamic programming? Couldn't you split greedily?**
A: The cost of a run depends on how its bells interact in the music, which isn't additive per bell. A greedy cut can give one ringer two bells that never clash and leave the next ringer an impossible trio. The DP has optimal substructure: the best plan for the first *j* bells with *k* ringers ends with some run *i..j*, and the part before it must be the best plan for *i* bells with *k−1* ringers. The tests compare it with brute force over every cut.

**Q: How did you make the parser safe to run on a file from anyone?**
A: The parser is limit-first and allow-list:
- it checks size before reading the whole file and line length before parsing;
- a line must match one of six fixed forms, and every number has a range;
- titles are restricted to a safe character set;
- control and bidirectional characters are rejected, so nothing can rewrite the terminal;
- errors never echo input or paths;
- the sanitizer build catches memory mistakes the tests might trigger.

## 5. Ideas to extend it

- **Non-contiguous assignments:** let a ringer take two separate runs (common for bass and treble on a big table) using a small local search after the DP.
- **Four-in-hand and shelley techniques:** allow some ringers to hold two bells in one hand, with a lower cost but a limit on which intervals fit.
- **Read MusicXML:** extract chords from the score directly, instead of typing measure:beat lines.
- **Rehearsal marks:** let the director pin a few bells to a ringer (a soloist, a beginner with only two bells) and solve around them.
