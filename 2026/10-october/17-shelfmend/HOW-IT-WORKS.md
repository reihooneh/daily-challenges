# How Shelfmend works

A walkthrough so you can explain every part of it.

## 1. The big picture

```
 shelf.txt ──▶ shelf_read            line by line: limits, refuse control characters,
                   │                 split "call number | title"
                   ▼
              callnumber_key         "QA76.73 .P98 2019" ──▶ "QA  00076 73000000 cP98000000 d2019"
                   │                 a key that sorts correctly byte by byte
                   ▼
              lis_keep               longest run already in order (patience sorting)
                   │                 every other book must move: provably the fewest
                   ▼
              shelf_report           where each book goes (binary search among the books that stay),
                                     books sharing a gap, and the book-by-book comparison
```

## 2. File tour

| File | Job |
|---|---|
| `bin/shelfmend` | Arguments, safe reading of the file or standard input, exit codes |
| `lib/callnumber.sh` | Library of Congress and Dewey call numbers to sort keys |
| `lib/lis.sh` | The longest in-order run, in O(n log n) |
| `lib/report.sh` | Reading the shelf list, and the report |
| `tests/run.sh` | 58 checks, including a brute-force check on 120 random shelves |

## 3. Key ideas

### Turn the rules into a sort key
Call numbers have fiddly rules: some parts are whole numbers, some are decimals, and a shorter call number comes first. Rather than writing a comparison function full of special cases, Shelfmend rewrites each call number once into a **key**: a string where a plain byte-by-byte comparison gives the right order.

| Part | Rule | Encoding |
|---|---|---|
| Class letters `QA` | `Q` < `QA` | pad with spaces to 3 (space is the smallest character) |
| Class number `76` | whole number: 9 < 76 | pad with zeros on the **left** to 5 digits |
| Decimal `.73` | decimal: .73 < .9 | pad with zeros on the **right** to 8 digits |
| Cutter `.P98` | decimal: P98 < P983 < P99 | letter, then digits padded on the right |
| Year, `v.2`, `c.2` | numbers | fixed-width with leading zeros |

Each element starts with a type letter (`c` cutter, `d` year, `v` volume, `x` copy), so at the same position a cutter sorts before a year, and the key stops early when the call number does ("nothing before something"). The script sets `LC_ALL=C` so Bash's `<` compares bytes rather than using language-specific collation.

### The fewest moves: longest increasing subsequence
Books that stay where they are must already be in order relative to each other. So the most books that can stay is the length of the **longest non-decreasing subsequence** of the keys, and the fewest that must move is everything else. Any book that moves can be dropped straight into its right place, so this many moves is always enough.

It's found with **patience sorting**: deal the keys onto piles, each on the leftmost pile whose top is bigger, and keep a link to the top of the pile to its left. The number of piles is the length of the longest run, and following the links back from the last pile gives the run itself. With binary search over the piles that's O(n log n): 5,000 books take a few seconds even when every one is out of place, in plain Bash.

"Non-decreasing" (strictly greater when choosing a pile) matters: two copies of the same book standing together are both in order.

### Where each book goes
For a book that moves, Shelfmend binary-searches the books that stay for the last one whose key is at or below it, and says "put it after that one" (or "at the start"). When several moved books go into the same gap, it sorts them, so you know their order too.

### Why checking each book against its neighbour misleads
A book-by-book check flags every place where a book is lower than the one before it. If book 5 is shelved too early, book 6 (which is fine) is flagged, because it's lower than book 5. The report counts how many flagged books are actually fine, to show why looking at the whole shelf matters.

### Bash features you met here
- **`[[ $s =~ regex ]]` and `BASH_REMATCH`** for parsing, with no external tools.
- **Namerefs** (`local -n arr=$1`) to pass arrays to functions.
- **Associative arrays** (`local -A dest`) for the gap of each moved book.
- **`printf -v`** to format into a variable without a subshell, which keeps 20,000 lines fast.
- **`${var^^}`, `${var//a/b}`, `${var%x}`** for upper-casing and trimming without `sed`.
- **`set -euo pipefail`**, and one trap it sets: a function whose last command is `[[ -n $x ]] && ...` returns false when `x` is empty, which stops the script. The tests caught exactly that.

## 4. Glossary

| Term | Plain version |
|---|---|
| Call number | The label on a book's spine that says where it's shelved |
| Cutter | The letter-and-digits part (`.P98`), usually for the author; read as a decimal |
| Shelf-reading | Walking a shelf to check every book is in order |
| Subsequence | Some of the items, kept in their original order |
| Patience sorting | Dealing items onto piles; the number of piles is the longest increasing run |

## 5. Interview questions you might get

**Q: How do you know the number of moves is the minimum?**
A: Books that aren't moved keep their relative order, so they must already form an in-order subsequence. The most that can stay is the longest such subsequence, so at least n minus that many must move. And that many is enough, because each moved book can go straight into its correct gap among the ones that stay. So the answer is exactly n minus the longest non-decreasing subsequence.

**Q: Why build sort keys instead of a comparison function?**
A: Bash has no custom comparator for `sort`, and calling a function for every comparison is slow. A key moves all the rules into one place and one pass; after that, every comparison is a cheap string comparison, and the same keys work with `sort`, binary search and patience sorting. Databases use the same trick for collation keys.

**Q: What are the security risks in a Bash script that reads a file?**
A: The surprising one is arithmetic: in `(( ))` or `$(( ))`, Bash evaluates array subscripts in a variable's value, so `a[$(rm -rf ~)]` from a file can run a command. Shelfmend only does arithmetic on strings a regex has proved are digits, and adds `10#` so a leading zero isn't read as octal. The others are word splitting and globbing (every expansion is quoted), terminal escape codes in output, and reading from devices; each is handled and tested.

## 6. Ideas to extend it

1. **Barcode mode:** read a scanner's barcode list and look up call numbers from a catalogue export.
2. **Fewest steps, not just fewest books:** plan the moves to minimise walking, or use a cart.
3. **More schemes:** NLM (medicine), UDC, and prefixes such as `REF` and `J`.
