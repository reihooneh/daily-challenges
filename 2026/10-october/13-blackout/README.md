# Blackout

**Checks a crossword grid against the house rules, then finds the fewest squares to change to fix it.**

Language: C++17 · Field: puzzle design / combinatorial search · Day: 13 October 2026

Before anyone writes a single clue, a crossword grid has to follow strict rules. It must look the same upside down, every white square must connect, there can be no two-letter answers, and in a cryptic grid enough letters of each answer must cross other answers. Constructors usually fix a broken grid by trial and error. Blackout reports exactly what is wrong in clue-number language ("32 Across has only 2 letters") and then searches for the **smallest set of squares to change** that makes the grid pass every rule, keeping it symmetrical and never touching squares you've already filled with letters.

## Quick start

```bash
make            # builds ./blackout (g++ or clang++, C++17)
make test       # 1700+ checks, built with AddressSanitizer and UBSan

./blackout examples/sunday-cryptic.txt
./blackout --fix examples/broken-cryptic.txt
./blackout --style american --entries examples/mini-american.txt
```

```
BLACKOUT  broken-cryptic.txt  (15 x 15, cryptic rules)
Black squares: 66 of 225 (29%)   Entries: 40 (21 across, 19 down)

PROBLEMS (5)
  r3 c13 and r13 c3: one is black and the other white, so the grid is not the same upside down.
  1 Across has only 2 letters; entries need at least 3.
  ...

SMALLEST FIX: change 3 squares
  r1 c3 -> white
  r13 c3 -> white
  r15 c13 -> white

  New grid (* newly black, o newly white):
  ..o............
  .#.#.#.#.#.#.#.
  ...
```

## Grid format

One row per line: `#` is a black square, `.` an empty white square, and a letter a white square you've already filled. Between 3 and 25 squares a side.

## The rules

| Rule | American | Cryptic |
|---|---|---|
| Same when turned upside down (180° symmetry) | ✓ | ✓ |
| All white squares connected | ✓ | ✓ |
| No two-letter entries; every white square in some entry | ✓ | ✓ |
| Every square in both an across and a down entry | ✓ | |
| At least half of each entry's letters crossed | | ✓ |
| No two uncrossed letters in a row | | ✓ |

## Options

| Option | Meaning |
|---|---|
| `--style cryptic` / `american` | Which rules to apply (default `cryptic`) |
| `--fix` | Search for the smallest fix |
| `--max 1-4` | Most moves to try (default 3; implies `--fix`) |
| `--entries` | List the clue numbers and answer lengths |

Exit codes: `0` the grid passes, `1` it has problems, `2` bad input.

## How the fix works

A *move* flips a square and its upside-down partner together, so a symmetrical grid stays symmetrical (where a pair is already mismatched, flipping either one alone repairs it). Blackout tries every set of 1 move, then every set of 2, and so on, and stops at the first size that works. So the fix is the smallest one, not just the first one found. Among equal-size fixes it picks the one that changes the number of black squares least. Grids up to 15 × 15 are searched completely; on bigger grids only moves near the problems are tried, and the report says so. A test compares the fixer with a brute force over every one- and two-square change on 400 random grids.

## Security

Grid files come from other people, so Blackout treats them as hostile:

- **Bounded input:** at most 4 KB is read, from a file or standard input, so a huge file or an endless stream such as `/dev/zero` is refused, not loaded. Only regular files are opened.
- **Strict characters:** anything other than `#`, `.`, letters and line endings is rejected, including terminal escape codes, NUL bytes and non-ASCII text. Error messages never repeat the input.
- **Safe output:** the file name is reduced to plain characters before it is printed, so a name containing escape codes can't change your terminal.
- **Bounded work:** grids are at most 25 × 25, the search tries at most a million grids (a few seconds), and the connectivity check uses its own stack instead of recursion, so no input can exhaust memory or the call stack.
- **Memory safety:** the tests are built with AddressSanitizer and UndefinedBehaviorSanitizer, and they include 3,000 random inputs. All indexing goes through bounds-known sizes, and the build treats every warning as an error under both GCC and Clang.

## Files

```
src/grid.*   parsing, numbering and the rules
src/fix.*    the smallest-fix search
src/cli.*    report text and the command line
tests/       test_blackout.cpp
examples/    sunday-cryptic.txt, broken-cryptic.txt, mini-american.txt
```

See [HOW-IT-WORKS.md](HOW-IT-WORKS.md) for a walkthrough.
