# Deckproof

**Proves a self-working card trick really works, every time. Write the trick as a few lines (deal into piles, the spectator points to a pile, gather, cut, perfect-shuffle), say what it promises, and Deckproof plays every choice the spectator could make. It either proves the trick or shows you the exact case where it fails.**

Language: Lua 5.4 (no dependencies) · Field: card magic / permutations · Day: 4 November 2026 (evening)

Self-working tricks are mathematics in disguise: the 21-card trick, perfect shuffles, the spectator's free cut that doesn't actually change anything. Inventing a variation is easy, but checking it by hand means dealing the cards dozens of times, and one case you didn't try is the one that fails on stage. Deckproof checks them all:

- **Every case:** each `choose card`, `choose number` and `cut any` branches over every possible choice, so "works every time" is a proof (for that deck size), not a hope.
- **A real counterexample:** when the trick fails, you get the spectator's choices that break it and where the card ended up instead.
- **Where cards land:** a histogram of the chosen card's final positions, which is often the hint for fixing a variation.
- **The real moves:**
  - dealing face down (each pile reversed) or face up (columns, order kept);
  - picking up the chosen pile on top, in the middle, on the bottom or at any place;
  - perfect in-shuffles and out-shuffles, cuts, dealing a number of cards, reversing the deck;
  - repeats.
- **Promises:** a card at a position (fixed or the spectator's number), on top or bottom, or the whole deck back in order.

## Quick start

```bash
lua deckproof.lua examples/twenty-one.txt
lua test/test_deckproof.lua          # 72 checks
```

```
DECKPROOF  The twenty-one card trick
21 cards, 10 steps once repeats are counted.

WORKS EVERY TIME: all 21 possible cases checked, and every promise holds.

The chosen card always ends 11th from the top.
```

A tempting variation that doesn't work (`examples/two-piles.txt`):

```
DECKPROOF  Two piles, picked on top
20 cards, 10 steps once repeats are counted.

FAILS in 20 of 20 cases (works 0% of the time).

Failing case 1:
  - X is the card at position 1
  => X ends at position 8, not 1
...
Where the chosen card ends (position: cases):
   6: 8  7: 8  8: 4
```

## The trick file

```
trick The twenty-one card trick
deck 21
choose card X            # the spectator thinks of any card
repeat 3
  piles 3                # deal three piles face down (add "faceup" for columns)
  pick X                 # the spectator points to the pile with their card
  gather middle          # top, middle, bottom or a place number
end
expect X at 11           # or: expect X on top / on bottom / at k, expect original
```

Other steps: `choose number k 1..10`, `cut 5`, `cut k`, `cut any`, `deal k` (deal k cards into a pile and put it back on top), `deal-under k`, `faro out`, `faro in`, `reverse`. Exit codes: `0` works every time, `1` fails in some case, `2` bad usage or input. `-` reads standard input.

## Security

- **Bounded input:** at most 16 KB, read with a hard limit, and 200 characters a line. Folders are refused, and the path is never printed.
- **Bounded work:**
  - at most 104 cards;
  - repeats nest at most 4 deep and unroll to at most 2,000 steps;
  - at most 2,000,000 cases are played, and the report says so if the limit is reached.
- **Strict parsing:** every line has a fixed shape, counts are checked against the deck size, and variables must be chosen before use. Errors give the line number and what was expected, never the input.
- **Safe text:** the file must be valid UTF-8, and control characters (terminal escapes) and invisible formatting characters are refused.
- **No code from the file:** a trick is data, never `load`ed or run. The tests run with strict globals, so any accidental global is an error.

**Known limits:**
- Deckproof checks the deck size you give. A trick that works with 21 cards may fail with 24, so try each size you'll use.
- It models what the cards do, not misdirection: a step that needs a sleight still has to be done well.

See [HOW-IT-WORKS.md](HOW-IT-WORKS.md) for the walkthrough.
