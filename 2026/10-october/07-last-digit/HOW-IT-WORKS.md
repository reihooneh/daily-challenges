# How Last Digit works

A friendly walkthrough so you can explain every part of it.

## 1. The big picture

```
 "978-0-306-40615-7"
        │  allow-list check, remove spaces and hyphens, upper-case
        ▼
 "9780306406157"
        │  for each kind of number:
        │     fits_<kind>?   right length and characters
        │     valid_<kind>?  does the check digit agree
        ▼
 passing kinds ──▶ explain_<kind>   show the arithmetic
 failing kinds ──▶ what the digit should have been + swap suggestions
```

## 2. File tour

| File | Job |
|---|---|
| `lib/schemes.sh` | One small group of functions per kind of number. Pure arithmetic. |
| `bin/lastdigit` | Reads and validates input, runs the schemes, prints the report, sets the exit code. |
| `tests/run.sh` | 215 checks, including measuring how many typos each scheme catches. |

### `lib/schemes.sh`: every scheme has the same four functions

```
fits_isbn10      could this be an ISBN-10?   (10 characters, X only at the end)
valid_isbn10     is the check digit right?
expected_isbn10  what should the check digit be?
explain_isbn10   print the working
```

Because every kind follows the same naming pattern, the main script can loop over a list of names (`gtin isbn10 issn card ...`) and call `"fits_$id"`, `"valid_$id"` and so on. Adding a new kind of number means writing four functions and adding one word to the list.

### The three families of check digit

**1. Weighted sum, modulo 10 (barcodes, ACN, Medicare).** Multiply each digit by a weight, add up, and choose the check digit that makes the total a multiple of 10. Barcodes use weights 3, 1, 3, 1...

**2. Weighted sum, modulo 11 or 89 (ISBN-10, ISSN, TFN, ABN).** The same idea with a prime modulus. Primes are stronger: with modulo 11 and all-different weights, *every* single wrong digit and *every* swap changes the remainder. The cost is that the check value can be 10, which ISBN writes as `X`.

**3. Luhn (cards, IMEI).** Double every second digit, and if that gives two digits add them together (16 → 1 + 6 = 7). It catches every single wrong digit and nearly every swap, using only digits 0 to 9.

**IBAN** is its own thing: turn letters into numbers (A = 10 ... Z = 35), and the whole enormous number must leave remainder 1 when divided by 97.

### `mod97`: arithmetic on a number too big to hold
An IBAN can become a 60-digit number, and Bash integers stop at about 19 digits. The trick is the one you use in long division: you never need the whole number, only the remainder so far.

```
remainder = 0
for each digit d:   remainder = (remainder × 10 + d) mod 97
```

### `bin/lastdigit`: the careful part
1. **Allow-list.** `[[ $raw =~ ^[A-Za-z0-9\ -]+$ ]]` must pass before anything else touches the input.
2. **Normalise.** `${raw//[ -]/}` deletes spaces and hyphens; `${n^^}` upper-cases.
3. **Sort the kinds** into `passing` and `failing`.
4. **Report.** If something passed, show its working. If nothing passed, say for each kind what the digit should have been, and try every neighbouring swap to see which would fix it.

## 3. Key concepts

| Concept | Plain version |
|---|---|
| Check digit | An extra digit calculated from the others, so mistakes can be detected |
| Modulo | The remainder after division: 93 mod 10 = 3 |
| Weighted sum | Multiply each digit by a different number before adding, so position matters |
| Transposition | Swapping two neighbouring digits: the most common human typing error |
| Error detection vs correction | A check digit says *something* is wrong, not *what*; that's why the tool lists several possible fixes |
| Allow-list | Accept only known-safe characters and refuse the rest |
| Command injection | Tricking a script into running part of its input as a command |

### Bash features you met here
- **`set -euo pipefail`**: stop on errors, on unset variables, and on failures inside pipelines.
- **`[[ ... =~ regex ]]`** for pattern tests, and **`(( ... ))`** for arithmetic.
- **Parameter expansion:** `${n:i:1}` (one character), `${n: -1}` (the last one), `${raw//[ -]/}` (delete), `${n^^}` (upper-case), `${#n}` (length).
- **Arrays and associative arrays:** `SCHEMES=(...)`, `declare -A SCHEME_NAME=([gtin]="...")`.
- **Calling a function by a computed name:** `"valid_$id" "$n"`. Safe here because `$id` only ever comes from the fixed `SCHEMES` list.
- **`printf -v value '%d' "'$c"`**: the character code of a letter.
- **`read -r -s -n`**: read without backslash tricks, without echo, with a length limit.
- **Process substitution** `< <(command)` to read a command's output line by line.
- **`shellcheck`**: a linter that catches the quoting mistakes that make shell scripts dangerous.

## 4. Interview questions you might get

**Q: Shell scripts are notorious for injection bugs. How did you make this one safe?**
A: Four rules. Input passes an allow-list of letters, digits, spaces and hyphens before anything else. Every expansion is quoted. There is no `eval`, and function names are built only from a hard-coded list, never from input. And error messages never include the input. The tests pass in `$(...)`, backticks, pipes and redirects that try to create a marker file, then assert the file doesn't exist; `shellcheck` is part of the test run.

**Q: Why do some schemes use modulo 11 instead of 10?**
A: Eleven is prime. With a prime modulus and distinct weights, changing any one digit or swapping any two neighbours always changes the remainder, so both kinds of error are always caught. Modulo 10 can't promise that: I measured it, and barcodes miss swaps of digits that differ by five, and Luhn misses 09 ↔ 90. The price of modulo 11 is a check value of 10, which needs an extra symbol like ISBN's X.

**Q: How do you check a 60-digit IBAN in a language with 64-bit integers?**
A: I never build the number. I walk through it one digit at a time keeping only the running remainder: `r = (r × 10 + digit) mod 97`. The remainder is always below 97, so it can't overflow. It's the same reasoning as long division by hand.

## 5. Ideas to extend it yourself

1. **More kinds:** UK NHS numbers, ISRC, VIN (which uses letter values and modulo 11), or the Verhoeff and Damm algorithms that catch *every* swap using only digits.
2. **Country rules for IBANs:** a table of each country's exact length and layout.
3. **Batch mode:** read a column of numbers from a file and report which rows are mistyped.
