# Seventh Shuffle 🃏

**A shuffle detective: give it a deck order and it tells you how many times the deck was really shuffled.**

Most people riffle a deck three or four times and call it shuffled. It isn't. A riffle shuffle leaves fingerprints of the original order in the deck, and mathematicians proved in 1992 that it takes about **seven** riffles before a 52-card deck is properly mixed. Seventh Shuffle reads those fingerprints: type in the order of a deck and it estimates how many shuffles it has had, and whether that was enough.

## What makes it different

The "seven shuffles" result is famous, but it lives in papers and simulations. I couldn't find a tool that turns it around and uses it as a *test* on a real deck.

- **It dates a deck.** From one deck order it works out the most likely number of riffle shuffles, and how strong the evidence is ("10^20 times more likely after 3 shuffles than in a truly random deck").
- **Exact mathematics, not simulation.** It uses the Bayer-Diaconis formula with big-integer arithmetic. The table it prints matches the published values to every digit.
- **A fair, human-like shuffler** for dealing test decks, using the same model of real shuffling the theory is built on.
- **Scriptable.** Exit code `1` means "not shuffled enough".

## Example

A deck that was riffled three times (`examples/three-shuffles.txt`):

```text
$ ./seventh check examples/three-shuffles.txt
Cards:              52
Rising sequences:   8   (a well-shuffled deck of this size averages 26.5)
Fewest shuffles:    3   (each riffle can at most double the rising sequences)
Most likely:        3 riffle shuffles
Evidence:           this order is about 10^20 times more likely after 3 shuffles than in a truly random deck

VERDICT: not shuffled enough. The original order is still showing.
```

The famous curve, computed exactly:

```text
$ ./seventh table
Distance from perfectly random, 52 cards (1 = not random at all, 0 = perfect)

   1 shuffle   1.000  ########################################
   2 shuffles  1.000  ########################################
   3 shuffles  1.000  ########################################
   4 shuffles  1.000  ########################################
   5 shuffles  0.924  #####################################
   6 shuffles  0.614  #########################
   7 shuffles  0.334  #############
   8 shuffles  0.167  #######
   9 shuffles  0.085  ###
  10 shuffles  0.043  ##
  11 shuffles  0.022  #
  12 shuffles  0.011
```

Nothing happens for four shuffles, then the deck mixes quickly. That sudden drop around seven is where the name comes from.

## Commands

| Command | What it does |
|---|---|
| `seventh check FILE` | Analyse a deck order (`-` reads standard input) |
| `seventh deal --shuffles K --cards N` | Print a deck after K riffle shuffles |
| `seventh table --cards N` | Distance from random after 1 to 12 shuffles |

Deck files list cards from the top, as numbers (`3 1 2 5 4`, any size up to 520) or as all 52 cards (`AS 10H QD 7C`). The starting order is 1, 2, 3, ... or a new deck: spades, hearts, diamonds, clubs, each ace to king.

## How accurate is it?

Measured on 4,000 simulated decks per row:

| Riffle shuffles | Flagged as "not shuffled enough" |
|---|---|
| 3 or 4 | 100% |
| 5 | 86% |
| 6 | 23% |
| 7 | 6% |
| 10 or more | about 1% (false alarms) |

It needs odds of at least 20 to 1 before accusing a deck, which is why a truly random deck is flagged only about once in a hundred.

## Tech

Java 17, standard library only (`BigInteger`, `BigDecimal`, `SecureRandom`). No build tool beyond `make` and no test framework to download.

## Build and run

```bash
cd 2026/10-october/05-seventh-shuffle
make
./seventh deal --shuffles 4 | ./seventh check -
```

| Exit code | Meaning |
|---|---|
| `0` | Consistent with a well-shuffled deck (or command finished) |
| `1` | Not shuffled enough |
| `2` | Invalid input |

## Tests

```bash
make test
```

27 tests:

- **The maths is exact:** the ten published distances for 52 cards, probabilities that must add up to exactly 1, known Eulerian numbers and binomials.
- **The simulator is honest:** 200,000 simulated shuffles of a small deck match the formula, and k shuffles never produce more than 2^k rising sequences.
- **The verdicts work:** four-shuffle decks are always caught, and twelve-shuffle decks almost never are.
- **Hostile input:** script tags, shell fragments, terminal escape codes, non-ASCII digits, huge numbers, oversized files, invalid UTF-8 and bad paths all produce a single clean error line.

The code compiles with every compiler warning switched on and treated as an error (`-Xlint:all -Werror`).

## Security

- **Strict input.** A deck must be a complete set: every card exactly once, 2 to 520 cards. Numbers must be plain ASCII digits; card names must match a fixed list. Anything else is rejected.
- **Errors never echo input.** Messages say which position in the list is wrong, never what was typed there, so nothing hostile (such as terminal escape codes) can be reflected to the screen.
- **Bounded work.** Input is capped at 16 KB and only that much is ever read from a file. Deck size and shuffle count have hard limits, and the largest allowed case is tested to finish quickly.
- **Unpredictable by default.** Dealing uses `SecureRandom`. The `--seed` option exists for repeatable demos and is documented as unsuitable for real games, because a seeded deck can be predicted.
- **No overflow.** All counting uses arbitrary-size integers, so the enormous numbers involved (52! has 68 digits) are exact.
- **Nothing dangerous in reach.** No reflection, no deserialisation, no shell commands, no network, no file writes. No dependencies.

**Known limits, stated honestly:**

- The analysis assumes ordinary riffle shuffles starting from a known order. It can't judge overhand shuffles, cuts, or a deck whose starting order it doesn't know.
- It measures one fingerprint (rising sequences). A deck can pass and still be non-random in other ways, and a skilled cheat can stack a deck that looks well mixed. **Passing is not proof of a fair deck.**
- A random deck is wrongly flagged about 1% of the time, and six or seven shuffles often pass, because at that point the evidence in a single deck is weak.
- Not for gambling or anything where money depends on the result.
- No software can promise it is 100% secure; these are the protections in place.
