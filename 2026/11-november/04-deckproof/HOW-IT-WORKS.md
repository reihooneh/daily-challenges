# How Deckproof works

A walkthrough so you can explain every part of it.

## 1. The big picture

```
 trick.txt ──▶ parse.lua    steps, nested repeats unrolled, promises; variables checked
                  │
                  ▼
              run.lua      depth-first search over the spectator's choices:
                  │        choose card / choose number / cut any branch; other steps permute
                  ▼
              report.lua   works every time, or the failing cases, and where the card lands
```

## 2. File tour

| File | Job |
|---|---|
| `deckproof/parse.lua` | The trick format, counts that may be the spectator's number, repeats (unrolled with a limit) and promises |
| `deckproof/run.lua` | The moves as list operations (cut, faro, piles, gather, deal), the search over every choice, and judging the promises |
| `deckproof/report.lua` | The verdict, the failing cases and the landing histogram |
| `deckproof.lua` | Bounded reading and exit codes, with no printing inside so the tests can call it |
| `test/test_deckproof.lua` | 72 checks: moves, shuffle orders, known tricks, case counting, limits, hostile files, the command line |

## 3. Key ideas

### A trick is a permutation with holes in it
Number the cards 1 to n, top first. Almost every move is a fixed rearrangement, a **permutation**:
- a **cut** of c cards is a rotation;
- **dealing c cards** into a pile reverses those c cards;
- a **perfect shuffle** interleaves the two halves.

The spectator's choices are the holes: which card, which number, where to cut. Fill the holes every possible way and you have a finite set of permutations. Check each one and the trick is proved, or you've found the case that breaks it.

### Searching every choice, depth first
`run.lua` walks the steps in order. At a choice it loops over every option, copies the state and carries on, like walking a tree whose leaves are finished performances. Each leaf is judged against the promises. The number of cases is the product of the choices (21 cards × 1 = 21, or 10 cards × 10 numbers × 10 cuts = 1,000), and a hard limit stops runaway files.

### Why the 21-card trick works
Each round, the spectator's pile goes in the middle. With 3 piles of 7, the card's position after a round depends only on where it sat within its pile. That pins it into a smaller and smaller window around the centre: after round 1 it's somewhere in places 8 to 14, after round 2 in places 10 to 12, and after round 3 exactly 11th. Deckproof's landing histogram shows that narrowing if you stop after two rounds: it fails, landing 10th, 11th or 12th.

### Perfect shuffles have an order
An out-faro sends the card at position p (counting from 0) to 2p mod (n − 1). Repeating it k times sends it to 2ᵏp, so the deck comes back when 2ᵏ ≡ 1 (mod n − 1). For 52 cards that first happens at k = 8, the famous eight perfect shuffles. In-faros work modulo n + 1 = 53, where 2 has order 52. The tests check both, and the 10- and 32-card cases too.

### Lua features you met here
- **Integer division `//`** and the `utf8` library (Lua 5.4) for checking text.
- **Errors as tables** (`error({ input = message })`) to tell bad input apart from bugs, caught with `pcall`.
- **Strict globals with a metatable on `_G`**: a tiny linter in the tests.

## 4. Interview questions you might get

**Q: Why depth-first search rather than generating all the cases up front?**
A: Depth-first search holds only one performance in memory at a time, and shares the work of the steps before each choice. With a million cases, building them all first would cost far more memory for nothing.

**Q: How do you stop a malicious trick file from running forever?**
A: Every source of size is bounded:
- the deck has at most 104 cards;
- repeats nest at most 4 deep and unroll to at most 2,000 steps (checked while unrolling, so `repeat 200` inside `repeat 200` fails fast);
- the search stops after 2,000,000 cases and says so.

The file is only ever parsed as data.

**Q: What would change to support "turn over the top card" tricks?**
A: Add an orientation bit to each card and a step that flips it. Then dealing face up versus face down changes orientation as well as order, and a promise could be "every card face down except X". The search and the rest stay the same.

## 5. Ideas to extend it

1. **Sweep deck sizes:** check a trick for every deck size from 10 to 60 and list the sizes where it works.
2. **Search for tricks:** given a set of moves, search for short procedures that always bring a chosen card to a fixed place.
3. **Real cards:** use suits and values, for tricks that spell the card's name or count its value.
