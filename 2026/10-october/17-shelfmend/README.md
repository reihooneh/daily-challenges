# Shelfmend

**Reads the call numbers on a library shelf in the order they stand, and tells you the fewest books to move to put it right, and exactly where each one goes.**

Language: Bash 5 (plus `sort`, `cut` and `head`) · Field: library science / algorithms · Day: 17 October 2026

Library staff "shelf-read": they walk along a shelf checking that every book is in call-number order. Scanner tools help by comparing each book with the one before it and flagging anything that's lower. But that check is easily fooled. When one book is shelved too early, the *good* book after it looks out of place, so people move books that were fine.

Shelfmend looks at the whole shelf at once. It finds the longest run of books that are already in order. Every other book must move, and that is provably the fewest moves possible. For each one, it says where it goes ("after position 17"), and the order to put back several books that go into the same gap.

## Quick start

```bash
bin/shelfmend examples/qa76.txt
bash tests/run.sh           # 58 checks
```

```
SHELFMEND  qa76.txt  (20 books, Library of Congress)

Move 4 books and the shelf is in order; the other 16 are already in sequence.
(A book-by-book check, comparing each book with the one before it, flags 4 books, and 2 of them are
 actually in the right place: a misplaced book makes the good book after it look wrong.)

TAKE OUT (left to right)                     PUT BACK
  1. position 5     QA76.9 .D3 E57 2016  (Fundamentals of database systems)
     -> after position 17: QA76.9 .D3 D3726 2004  (An introduction to database systems)
  2. position 12    QA76.6 .K64 1997 v.1  (The art of computer programming, vol. 1)
     -> at the start, before position 1: QA76.73 .C15 K47 1988  (The C programming language)
  3. position 14    QA76.6 .K64 1997 v.3  (The art of computer programming, vol. 3)
     -> at the start, before position 1: QA76.73 .C15 K47 1988  (The C programming language)
  4. position 18    QA76.9 .H85 N57 2013  (The design of everyday things)
     -> after position 19: QA76.9 .D3 S5 2020  (Database system concepts)

BOOKS GOING INTO THE SAME GAP (put them back in this order)
  at the start: QA76.6 .K64 1997 v.1, QA76.6 .K64 1997 v.3
```

## The shelf list

One book per line, in the order it stands, left to right. A title after `|` is optional; lines starting with `#` are skipped.

```
QA76.73 .P98 M38 2019 | Python crash course
QA76.9 .D3 E57 2016
823.914 ROW | Harry Potter and the philosopher's stone
```

It reads **Library of Congress** call numbers (class, cutters, year, `v.2`, `c.2`) and **Dewey** numbers with an author mark. Use `--scheme lc` or `--scheme dewey` to insist on one. Exit codes: `0` the shelf is in order, `1` books to move, `2` bad input.

## Getting the order right

The rules that trip people up are built in:

- `QA9` comes before `QA76` (class numbers are whole numbers), but `QA76.73` comes before `QA76.9` (the part after the point is a decimal).
- Cutters are decimals too: `.P98` < `.P983` < `.P99`.
- Nothing comes before something: `.P98` before `.P98 S65`.
- Volumes and copies are numbers: `v.2` before `v.10`.

## Security

- **Bounded input:** at most 1 MB, 20,000 books and 160 characters a line. Only regular files are read (not symlinks or devices, so `/dev/zero` is refused), and reading stops at the limit.
- **Nothing from the file is ever run.** Bash can execute code hidden in an array index inside arithmetic, as in `a[$(command)]`. Shelfmend only does arithmetic on values a regular expression has already proved are digits (and forces base 10 with `10#`), never uses `eval`, and quotes every expansion. The tests feed it `$(...)` and backticks and check that nothing ran.
- **Safe output:** control characters (terminal escapes) and hidden bidirectional characters are refused, error messages never repeat the input, and file names are cleaned before printing.
- **Checked:** `shellcheck` passes on every file.

**Known limits:** shelving rules differ a little between libraries (for example how dates file against second cutters). Shelfmend uses one clear rule, described in `lib/callnumber.sh`. It doesn't read prefixes like `REF` or `FIC`, and positions are as scanned, before anything moves.

See [HOW-IT-WORKS.md](HOW-IT-WORKS.md) for how it works and ideas to extend it.
