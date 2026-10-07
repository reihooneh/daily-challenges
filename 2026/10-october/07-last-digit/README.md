# Last Digit 🔢

**Tells you what kind of number you're holding and whether you typed it right, and shows the arithmetic.**

The last digit of a barcode, a bank card, an ISBN or an Australian Business Number isn't information. It's a tiny piece of maths that lets a machine catch your typo before it becomes a failed payment or a parcel sent to the wrong book. Last Digit takes any such number, works out which kinds it could be, checks each one, and walks through the sum.

## What makes it different

Validators usually answer one question about one format: "is this a valid X?". Last Digit starts from the number instead.

- **It identifies.** You don't say what the number is. It tries every kind whose shape fits.
- **It shows its working**, line by line, the way you'd do it by hand.
- **It says exactly what's wrong:** "its last digit should be 5, not 7".
- **It spots the classic slip.** Swapping two neighbouring digits is the most common typing mistake, so it lists the swaps that would make the number valid.
- **A private mode.** `lastdigit -` reads the number at a hidden prompt, keeps it out of your shell history, and shows only its first and last two characters.
- **Australian numbers included:** ABN, ACN, TFN and Medicare, next to the international ones.

## Example

```text
$ lastdigit 978-0-306-40615-7
978-0-306-40615-7   (13 characters)

  VALID    Barcode (EAN / UPC / ISBN-13)
      Multiply the digits by 3 and 1 in turn, starting with 3 next to the check digit:
      9x1 + 7x3 + 8x1 + 0x3 + 3x1 + 0x3 + 6x1 + 4x3 + 0x1 + 6x3 + 1x1 + 5x3 = 93
      The check digit tops the sum up to a multiple of 10: (10 - 3) mod 10 = 7
  not a    Payment card

A valid check digit means the number is well-formed. It does not mean the number exists or belongs to anyone.
```

The same number with two digits swapped:

```text
$ lastdigit 9780306406517
9780306406517   (13 characters)

  invalid  Barcode (EAN / UPC / ISBN-13): its last digit should be 5, not 7
      or characters 9 and 10 were swapped: 9780306460517 would be valid
      or characters 10 and 11 were swapped: 9780306405617 would be valid
      or characters 11 and 12 were swapped: 9780306406157 would be valid
  invalid  Payment card: its last digit should be 1, not 7

Not valid as anything. One wrong or swapped digit is the usual cause.
```

## What it knows

| Kind | The rule |
|---|---|
| Barcodes: EAN-8, UPC-A, EAN-13 / ISBN-13, GTIN-14 | Weights 3 and 1, modulo 10 |
| ISBN-10 | Weights 10 to 2, modulo 11 (`X` means 10) |
| ISSN | Weights 8 to 2, modulo 11 |
| Payment cards (with Visa / Mastercard / Amex detection) | Luhn algorithm |
| IMEI | Luhn algorithm |
| Australian Business Number | Weights 10, 1, 3 ... 19, modulo 89 |
| Australian Company Number | Weights 8 to 1, modulo 10 |
| Australian Tax File Number | Weights 1, 4, 3, 7, 5, 8, 6, 9, 10, modulo 11 |
| Australian Medicare card | Weights 1, 3, 7, 9 twice; the *ninth* digit is the check |
| IBAN | Letters become numbers, modulo 97 |

## Usage

```bash
cd 2026/10-october/07-last-digit
bin/lastdigit "51 824 753 556"      # spaces and hyphens are ignored
bin/lastdigit -                     # hidden prompt, masked output
bin/lastdigit --quiet 4111111111111111
bin/lastdigit --list
```

Exit codes: `0` valid as at least one kind, `1` not valid as any kind, `2` bad input.

## Tech

Bash 4+ and the standard core utilities. All the arithmetic is done by the shell itself; nothing needs installing.

## Tests

```bash
bash tests/run.sh
```

215 checks:

- **Published examples** of every kind validate, and the expected check digit is recomputed correctly.
- **What each scheme promises is measured.** Every digit of a number is changed to every other value, and every neighbouring pair is swapped, to count what slips through. Barcodes, Luhn, ISBN-10, ISSN, TFN, ABN and IBAN catch every single wrong digit. ISBN-10 and IBAN also catch every swap.
- **Known weaknesses are tests too:** Luhn misses the `09` ↔ `90` swap, and barcodes miss swaps of digits that differ by 5.
- **Hostile input:** command substitution, backticks, pipes, redirects, glob characters, escape codes, newlines, look-alike Unicode digits, a 5 MB stream on standard input. A marker file proves nothing was executed.
- `shellcheck` reports nothing on any of the scripts.

## Security

Shell scripts are easy to get wrong with untrusted input, so this one is strict.

- **An allow-list comes first.** Input may contain only letters, digits, spaces and hyphens, and at most 40 characters. Everything else is refused with one fixed message that never repeats what was typed.
- **Input is never code.** There is no `eval`, every variable is quoted, and scheme functions are chosen from a fixed list, never from the input. The tests feed it `$(...)`, backticks, `;`, `|` and `>` and check that no file appears.
- **Private numbers stay private.** With `-`, the number is read without echo, never appears in the process list or shell history, and is masked in the output. Nothing is ever written to disk or sent anywhere: the script makes no network calls and creates no files.
- **Bounded input.** Standard input is read up to 41 characters and no further.
- **No overflow.** The one calculation that could exceed 64 bits (an IBAN is up to a 60-digit number) is done one digit at a time, as in long division.
- **Strict mode:** `set -euo pipefail`, and `shellcheck` clean.

**Known limits, stated honestly:**

- **Valid does not mean real.** A check digit proves a number is well-formed. It cannot tell you that a card, account, business or person exists, and it must never be used to "verify" someone's identity.
- If you pass a number as an argument instead of using `-`, your shell may save it in its history. Use `-` for anything sensitive.
- IBANs are checked by their check digits only, not against each country's length and format rules.
- Check digits catch most typos, not all (see the measured weaknesses above), and they do nothing against deliberate fraud.
- No software can promise it is 100% secure; these are the protections in place.
