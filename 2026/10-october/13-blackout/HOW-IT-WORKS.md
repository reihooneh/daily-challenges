# How Blackout works

A walkthrough so you can explain every part of it.

## 1. The big picture

```
 grid.txt ──▶ parse()          '#', '.', letters; 3-25 a side; 4 KB max
                 │
                 ▼
             measure()         for every square: length of its across run and down run
                 │
                 ▼
             check()           symmetry · connected · no 2-letter entries ·
                 │             American: every square crossed · Cryptic: half crossed, no double unches
                 ▼
     analyse()  /  valid()     full list of problems  /  stop at the first one (fast)
                 │
                 ▼
             findFix()         try every set of 1 move, then 2, 3...; first size that passes wins
                 │
                 ▼
             report            clue numbers, problems in words, the fixed grid
```

## 2. File tour

| File | Job |
|---|---|
| `src/grid.hpp/.cpp` | The `Grid` type, safe parsing, clue numbering and every rule |
| `src/fix.hpp/.cpp` | The smallest-fix search |
| `src/cli.hpp/.cpp` | Turns problems into sentences; the command line, bounded reading and exit codes |
| `src/main.cpp` | Three lines: passes `argv` to `run()` |
| `tests/test_blackout.cpp` | 10 test groups, 1700+ checks, run under sanitizers |

## 3. Key ideas

### Runs make every rule easy
For every white square, `measure()` stores how long the white run is across and down. Everything else follows from those two numbers:

- A square is **in an entry** in a direction if that run is at least 2 long.
- A square is **checked** (crossed) if it is in an entry both ways.
- An entry **starts** where the square before it is black or off the edge.

Clue numbering is the standard rule: go along each row, and give the next number to any square that starts an across or a down entry.

### Symmetry is a one-liner
Store the grid as one row-major array of `rows × cols` squares. Turning it upside down maps square `i` to square `size - 1 - i`. So the symmetry check compares `black(i)` with `black(size - 1 - i)`.

### Connectivity without recursion
A flood fill from the first white square, using an explicit `std::vector` as a stack. If it reaches fewer squares than there are white squares, some are cut off. Recursion would also work, but a 25 × 25 snake-shaped grid could go 600 calls deep. An explicit stack can't overflow.

### One rule engine, two speeds
`check()` is a template that calls a `report` function for each problem; if `report` returns false it stops. `analyse()` passes a function that collects everything. `valid()` passes one that stops at the first problem, which is what the search needs, because it tests up to a million grids.

### The smallest fix: iterative deepening
A **move** flips a square and its partner, so symmetry is kept. The search tries every combination of 1 move, then every combination of 2, and so on. Combinations are generated in lexicographic order with an index array (`pick`), like counting. Because sizes are tried in order, the first size with any valid grid is the minimum. Among fixes of that size, it chooses the one whose black-square count drifts least, so the grid keeps its character.

Cost: a 15 × 15 grid has 113 possible moves. Trying every set of 3 means C(113, 3) ≈ 234,000 grids, which takes under a second. Bigger grids keep only moves within two squares of a problem, and every search stops after a million grids.

Squares holding letters are never moved, because those letters are answers you've already written.

### Testing that the fix really is smallest
On 400 random 4×4 to 6×6 grids, the test flips every single square and every pair of squares by brute force. If flipping `k` squares gives a valid grid, the fixer must find a fix with at most `k` moves. That's an independent check of the move logic.

## 4. Glossary

| Term | Plain version |
|---|---|
| Entry / light | An answer's space in the grid |
| Checked letter | A square in both an across and a down entry |
| Unch | An unchecked square, in only one entry |
| Double unch | Two unchecked squares next to each other in one entry |
| 180° symmetry | The grid looks the same turned upside down |
| Iterative deepening | Try all size-1 answers, then all size-2, and so on |

### C++ features you met here
- **Templates with lambdas** (`check<Report>`) to share one rule engine between two callers.
- **RAII and the standard library**: `std::vector`, `std::string`, `std::ifstream`, `std::filesystem::is_regular_file`.
- **`std::tuple` comparison** for a multi-part score.
- **Structured bindings** (`for (const auto& [name, test] : tests)`).
- **Exceptions** for input errors, caught once in `run()`.
- **Sanitizers** (`-fsanitize=address,undefined`) to catch memory and undefined-behaviour bugs during tests.

## 5. Interview questions you might get

**Q: How do you know the fix is the smallest?**
A: The search is iterative deepening. It tries every set of one move before any set of two, and so on. So the first size where any grid passes is the minimum, as long as the search finishes that size. If it hits its budget it says so. A test checks it against a brute force over every one- and two-square change on random grids.

**Q: Why is a move two squares?**
A: Published grids are symmetrical. If the search flipped single squares, almost every candidate would break symmetry and be rejected. Pairing a square with its partner shrinks the search by about half at each level, and every candidate stays symmetrical.

**Q: What stops a malicious grid file from hurting you?**
A: Input is capped at 4 KB, and only regular files are opened, so `/dev/zero` is refused. Only `#`, `.` and letters are allowed, so escape codes can't reach the terminal. Error messages never repeat input, and the file name is cleaned before it is printed. The work is bounded: at most 25×25, a million grids, and no recursion. The tests run under AddressSanitizer and UBSan, including 3,000 random inputs.

## 6. Ideas to extend it

1. **Word-count and grid-quality scores:** prefer fixes that keep entries long and avoid big blocks of black squares.
2. **Fill check:** with a word list, say whether the fixed grid can still be filled, which is constraint satisfaction with backtracking.
3. **Barred grids:** the Listener-style crosswords that use thick bars instead of black squares.
