# How Pacelane works

A walkthrough so you can explain every part of it.

## 1. The big picture

```
 squad.txt ──▶ parse.c    fixed line shapes, hand-written time parser, strict UTF-8 names
                  │
                  ▼
              split.c     sort by pace → cost of every possible lane (a run of neighbours)
                  │                    → dynamic programme over (lanes, swimmers placed)
                  ▼
              report.c    lane sheet: interval, push-off order, rest, finish time
```

## 2. File tour

| File | Job |
|---|---|
| `src/pacelane.h` | Limits, the `Session`, `Lane` and `Split` structs, and the functions between files |
| `src/parse.c` | The squad file, `m:ss.t` times, UTF-8 decoding and the name rules |
| `src/split.c` | A lane's best interval, the exact split, and the equal-lanes comparison |
| `src/report.c` | The printed lane sheet |
| `src/main.c` | Bounded, symlink-free reading and exit codes |
| `tests/test_pacelane.c`, `tests/test_cli.sh` | Unit checks (including every-assignment brute force) and command-line checks |

## 3. Key ideas

### All times in tenths of a second
`1:25.5` becomes the integer `855`. Integers make the arithmetic exact: no floating-point rounding decides which interval wins, and the tests can compare costs with `==`.

### The best interval for one lane
For a lane whose swimmers take `a₁ … a_k` (tenths) per repeat, an interval `T` gives swimmer `i` a rest of `T − aᵢ`. The lane's cost is

```
cost(T) = Σ (T − aᵢ − target)²
```

That's a parabola with its minimum at `T = mean(a) + target`. Two things push `T` up:
- **min-rest:** the slowest must still get it, so `T ≥ max(a) + min_rest`;
- **no jam:** `k` swimmers leaving `gap` apart must all be gone before the leader goes again, so `T ≥ k × gap`.

`T` must also be a multiple of the clock step, so the best `T` is one of three values: the lower limit, or the step just below or just above the parabola's minimum. Only those three are checked.

### The best split: a DP over sorted swimmers
Sort the squad by pace. If every lane holds a run of neighbours, a split is just the places where the lane ropes go. Let `f[l][j]` be the least cost of putting the `j` fastest swimmers into `l` lanes:

```
f[l][j] = min( f[l-1][j],                                    lane l left empty
               min over k = 1..max:  f[l-1][j-k] + cost(j-k, k) )   lane l takes k swimmers
```

The table is at most 13 × 201, and `cost(i, k)` is computed once for each run. Back-pointers (`take[l][j]`) recover the lane ropes.

### Why lanes of neighbours?
It's intuitive (swap a fast swimmer in a slow lane with a slow swimmer in a fast lane and both rests get closer to the target), but the clock rounding and the `k × gap` rule make a clean proof awkward. So the tests check it: on 150+ random squads they try every assignment of swimmers to lanes (up to 3⁷ of them) and confirm the DP's cost always equals the true optimum.

### C techniques you met here
- **A table of settings** (`struct { key, field pointer, range, scale, hint }`) instead of a chain of `if`s.
- **A UTF-8 decoder** that refuses overlong forms, surrogates and code points past U+10FFFF, and counts characters so columns line up.
- **`open(O_NOFOLLOW)` + `fstat` + `S_ISREG`** to refuse symlinks, devices and pipes, and a read loop capped at `MAX_BYTES + 1`.
- **`strtok_r`**, the re-entrant version of `strtok`, for splitting words.

## 4. Interview questions you might get

**Q: Why squared misses rather than absolute ones?**
A: Squares punish one swimmer getting 2 s of rest much more than several getting a little too much. That matches how a set actually goes wrong: the person with no rest falls apart. It also makes the best interval easy to find, because the minimum of a parabola is at the mean.

**Q: What's the complexity, and could it be faster?**
A: Building the run costs is O(n × max × max) and the DP is O(lanes × n × max), at most a few hundred thousand steps. You could compute run costs incrementally with prefix sums of `a` and `a²` (the cost for a given `T` is `k·T² − 2T·Σ(a+target) + Σ(a+target)²`), but at these sizes it's not worth the extra code.

**Q: How do you stop a hostile squad file from breaking the terminal?**
A: Names are decoded as strict UTF-8 and every code point is checked. C0 and C1 controls (which include the ESC that starts terminal escape sequences), zero-width characters, direction overrides like U+202E and the BOM are all refused, and only a small set of ASCII punctuation is allowed. Errors never echo the line, so even a rejected name can't reach the terminal.

## 5. Ideas to extend it

1. **Friends and coaches' rules:** keep two swimmers together, or keep a beginner out of the fast lane, with a DP that tracks those constraints.
2. **Mixed sets:** plan for a whole session (100s, then 50s, then a 400) and choose lanes that suit all of them, since a lane change halfway is chaos.
3. **Learn paces from results:** read the last few sessions' times and update each swimmer's pace, rather than trusting what they say.
