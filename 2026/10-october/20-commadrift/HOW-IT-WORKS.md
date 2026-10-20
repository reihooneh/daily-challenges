# How Commadrift works

A walkthrough so you can explain every part of it.

## 1. The big picture

```
 progression.txt ──▶ parse_piece      strict line-by-line reading, notes → MIDI numbers
                          │
                          ▼
                     identify          which chord is it? root + quality → pure ratios
                          │            dev = pure tuning − equal temperament, per note (cents)
                          ▼
                     strict_offsets    held notes may not move at all → how far the piece drifts
                          │
                     solve_offsets     least squares: small glides vs staying near concert pitch
                          │            → a tridiagonal system, solved in O(n) (Thomas algorithm)
                          ▼
                     report            cents (and Hz) for every note, the largest glide, the drift
```

## 2. File tour

| File | Job |
|---|---|
| `src/drift.h` | Shared types, limits and function declarations |
| `src/parse.c` | The file format, note names, every limit |
| `src/chords.c` | Chord templates and their pure ratios |
| `src/solve.c` | The drift, the least-squares plan, the Thomas algorithm, glides |
| `src/main.c` | Safe file reading and the report |
| `tests/test_drift.c` | 54 unit checks, including that the answer really is a minimum |
| `tests/test_cli.sh` | 13 command-line checks, including attacks |

## 3. Key ideas

### Cents and pure intervals
Pitch is logarithmic: an octave doubles the frequency. A **cent** is 1/1200 of an octave, so an interval with frequency ratio r spans 1200·log₂(r) cents. Equal temperament makes every semitone 100 cents. Pure intervals use small whole-number ratios: a fifth is 3:2 (701.96 cents, 2 cents above the piano's) and a major third is 5:4 (386.31 cents, 13.69 below). For each note of a chord, `dev` stores *pure minus equal-tempered*, in cents, relative to the chord's root.

### Why pure chords drift: the comma pump
Hold one note through each change of C – Am – Dm – G – C and insist it doesn't move. Going round the loop, the pure intervals stack up to four fifths down against two octaves and a major third, and those don't quite agree: (3/2)⁴ / (2² × 5/4) = 81/80, the **syntonic comma**, 21.5 cents. So the final C chord is 21.5 cents lower than the first. `strict_offsets` follows the held notes step by step and reports exactly that; the tests check the value to 0.001 cents.

### The trade-off as least squares
Tune each chord pure and shift the whole chord by an offset oₖ cents from equal temperament. A note held from chord k into chord k+1 then moves by

```
glide = o(k+1) + dev(k+1) − o(k) − dev(k)
```

We pick the offsets that minimise

```
glide weight × Σ glide²   +   drift weight × Σ oₖ²
```

The first term keeps held notes still; the second keeps the whole piece near concert pitch, so the drift is spread out instead of piling up at the end. Both terms are squares, so the cost is a smooth bowl: setting each derivative to zero gives linear equations. Each offset only appears in glides with its neighbours, so each equation involves only oₖ₋₁, oₖ and oₖ₊₁: the matrix is **tridiagonal**.

### The Thomas algorithm
A tridiagonal system can be solved in linear time: one pass forward eliminates the entries below the diagonal, one pass backward substitutes. It's Gaussian elimination that only touches the three bands. The drift term adds a positive number to every diagonal entry, which makes the matrix strictly positive definite, so no pivoting is needed and it can't divide by zero. (That's why a drift weight of 0 is quietly treated as 0.000001.) A test nudges every offset by ±0.5 cents and checks that the cost always goes up, so the answer really is the minimum.

### C features you met here
- **Fixed-size buffers and explicit bounds**: the file goes into a static 16 KB buffer, lines are copied only after checking their length, and every format uses `snprintf`.
- **`open(…, O_NOFOLLOW)` then `fstat`**: checking the file you actually opened, not the path (avoiding a time-of-check/time-of-use race).
- **Static `const` tables** for note names and chord templates, sized with `sizeof TEMPLATES / sizeof TEMPLATES[0]`.
- **`log2`, `pow`, `isfinite`** from `<math.h>`, linked with `-lm`.
- **Sanitizers** (`-fsanitize=address,undefined`) catch out-of-bounds access, use-after-free and undefined behaviour during the tests.

## 4. Glossary

| Term | Plain version |
|---|---|
| Equal temperament | The piano's tuning: every semitone the same size |
| Just (pure) intonation | Intervals from small whole-number frequency ratios; chords stop beating |
| Cent | 1/100 of an equal-tempered semitone |
| Syntonic comma | 81/80, about 21.5 cents: the gap that makes pure tuning drift |
| Common tone | A note held from one chord into the next |
| Tridiagonal matrix | Only the main diagonal and the ones just above and below are non-zero |

## 5. Interview questions you might get

**Q: Why least squares rather than just keeping held notes fixed?**
A: Fixed held notes make the pitch drift by a comma per loop, which a choir can't sustain and an accompanist can't follow. Fixing the pitch instead makes held notes jump. Least squares is the natural way to trade the two off with one knob, and the squared cost gives a linear system with a unique answer.

**Q: How do you solve it, and how fast?**
A: The equations only link neighbouring chords, so the matrix is tridiagonal, and the Thomas algorithm solves it in O(n) time and memory. The drift term makes it positive definite, so no pivoting is needed. A general solver would be O(n³), pointless for this structure.

**Q: How do you keep a C program that parses files safe?**
A: Bound everything: file size, line length, chord count, notes per chord. Copy only after checking lengths, use `snprintf`, avoid dynamic allocation, accept only printable ASCII, and refuse non-regular files using `O_NOFOLLOW` plus `fstat` on the opened descriptor. Then test it with AddressSanitizer and UBSan, compile warnings as errors, and run the static analyser.

## 6. Ideas to extend it

1. **Real-time output:** send the offsets as MIDI pitch bend so a keyboard plays the tuned progression.
2. **Melody aware:** treat melody notes as held-ish too, with their own weight.
3. **Choose ratios:** let users pick 7:4 or 16:9 sevenths, or 7:6 minor thirds, and compare the beat rates.
