# Bellshare

**Shares out the bells of a handbell piece among the ringers. Each ringer has two hands, so a ringer whose bells sound three at once can't play their part, and every time a bell has to be put down for another there's a chance of a missed note. Bellshare finds the split of bells that nobody needs three hands for, with the fewest and least rushed bell changes, then lists every change to pencil into the music.**

Language: C++20 (standard library only) · Field: handbell ringing / caching and dynamic programming · Day: 5 November 2026

In a handbell choir each ringer looks after a few neighbouring bells, and the director decides who gets which. The usual way is equal shares (two bells each, or a fixed chart) and then fixing the trouble spots in rehearsal: a ringer who needs three bells on one beat, or who has to swap bells in half a beat. Bellshare works it out from the notes instead:

- **One ringer, played exactly:** for a set of bells it plays the piece with two hands. When a bell is needed that isn't in hand, it puts down the bell not needed for the longest time. This is Belady's rule from computer caching, and it gives the fewest possible changes (the tests check it against trying every choice).
- **Tight changes:** a change is *tight* when the hand had less than `swap` beats free since it last rang. Tight changes count ten times as much as comfortable ones.
- **The best split:** bells stay in pitch order, as in every handbell table layout, and a dynamic program tries every way of cutting the row of bells into one run per ringer. It's checked against brute force over every possible cut.
- **Honest output:**
  - it compares the result with equal shares;
  - when no split works, it says where in the music the three-bell chord is;
  - it lists each change with its measure and beat and how many beats are free.

## Quick start

```bash
make                                   # builds build/bellshare
./build/bellshare examples/evening-chime.txt
make test                              # 712 checks, with AddressSanitizer and UBSan
make lint                              # clang-tidy
```

```
The best split of the bells, in pitch order:
  Ringer  1  C4 E4 F4 G4 A4        10 changes
  Ringer  2  B4 C5                 no changes
  Ringer  3  D5 E5                 no changes
  Ringer  4  F5 G5                 no changes
  Ringer  5  A5 B5 C6 D6           5 changes

In all: 15 bell changes, 0 tight.
An equal share of bells each would give: 23 bell changes, 0 tight.

Bell changes to mark in the music ('TIGHT' means less than 1 beat to do it):
  Ringer  1  m3:1     put down C4   pick up A4    (6 beats free)
  Ringer  1  m4:1     put down A4   pick up F4    (3 beats free)
  ...
```

The split isn't the obvious one. The melody and harmony bells get two each, so those ringers never change bells. The slow bass line and the top bells, where changes have room, take the extra bells.

Exit code: 0 if the piece can be rung, 1 if no split avoids three bells at once (or too many bells for someone), 2 for a bad file.

## The piece file

```
# Comments start with #.
piece Evening Chime
ringers 5
max-bells 5          # most bells one ringer may have (2 to 12, default 6)
swap 1               # beats needed to put a bell down and pick one up (0 to 8, default 1)
time 3/4             # beats in a measure, before the first chord (default 4/4)

1:1 C4 E5 G5         # measure:beat, then the notes that sound together
1:2 C5
1:2.5 D5             # beats can be fractions
```

- **Notes:** written like `C5`, `F#4` or `Bb5`, from C2 to C9; C4 is middle C. A sharp and its matching flat are the same bell.
- **Chords:** each chord must come after the one before it.
- **Durations:** these don't matter here, since only the moment a bell is rung needs a hand.

## Security

The piece file is the only input, and Bellshare treats it as untrusted:

- **Bounded reading:** files over 64 KB are refused before parsing. Lines are limited to 200 characters, chords to 4,000, notes per chord to 12 and ringers to 20, which keeps the dynamic program small (at most 85 bells, C2 to C9).
- **Strict shapes:**
  - each line must be one of six fixed forms, and every number must be in its range;
  - titles are limited to letters, digits and a little punctuation;
  - invalid UTF-8, control characters (such as terminal escape codes) and invisible formatting characters (zero-width and bidirectional overrides) are refused.
- **No echoing:** error messages give the line number and what was expected, never the text of the line or the file's path, so a crafted file can't put anything on your terminal.
- **Files only:** symbolic links, folders and devices are refused. Standard input (`-`) is read with the same limit.
- **Checked memory:** the tests build with AddressSanitizer and UndefinedBehaviorSanitizer, the code builds with `-Wall -Wextra -Wconversion -Werror`, and clang-tidy runs the bugprone, cert and analyzer checks.
- **No network, no writing:** Bellshare opens nothing but the one file you name.

## Files

| File | What it does |
|---|---|
| `src/bellshare.hpp` | The types (Piece, Chord, Load, Assignment) and the functions between them |
| `src/parse.cpp` | Reads and checks the piece file; note names |
| `src/assign.cpp` | Plays one ringer's bells (Belady), the dynamic program, equal shares |
| `src/report.cpp` | The chart and change list; reading files safely; the command line |
| `tests/tests.cpp` | Brute-force checks, hostile input, the command line |
| `examples/evening-chime.txt` | An original sixteen-bar piece for five ringers |

See [HOW-IT-WORKS.md](HOW-IT-WORKS.md) for the design, the algorithms and interview questions.
