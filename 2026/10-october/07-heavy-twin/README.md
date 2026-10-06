# Heavy Twin ⚖️

**Predicts the isotope pattern of any molecule, explains every peak, and reads a pattern backwards.**

Most atoms have a heavier twin. One carbon in every ninety is carbon-13; one chlorine in four is chlorine-37. So a pure substance never shows up in a mass spectrometer as one peak: it shows up as a little cluster, and the shape of that cluster is a fingerprint of what's inside. Heavy Twin calculates the cluster from a formula, tells you *why* each peak is there, and can go the other way: from peak heights to "this probably has one bromine and about six carbons".

## What makes it different

Isotope calculators exist as web pages and as parts of big chemistry libraries. Heavy Twin is a small command-line tool built around the reasoning a chemist actually does:

- **It explains, not just calculates.** "M+2 is almost as tall as M: the signature of one bromine-81 atom."
- **It works backwards.** `--read 6.5 97.5` turns two peak heights into clues about the molecule, using the rules taught in organic chemistry.
- **Every peak shows its true mass.** The mass of each peak is carried through the calculation exactly, so M+2 of bromobenzene is 157.9554 (the bromine-81 mass), not "M plus two".
- **It checks its own data.** A test confirms that every element's isotopes average out to the atomic weight on the periodic table.

## Example

```text
$ heavytwin CH2Cl2
Formula:            C H2 Cl2   (5 atoms)
Average mass:       84.932   (what you weigh out on a balance)
Monoisotopic mass:  83.95336   (the M peak: every atom its most common isotope)

Isotope pattern (tallest peak = 100):
  M       83.9534   100.0  ########################################
  M+1     84.9568     1.1
  M+2     85.9504    64.0  ##########################
  M+3     86.9538     0.7
  M+4     87.9475    10.2  ####
  M+5     88.9509     0.1

Why it looks like this:
  - M+1 is mostly carbon-13: 1 carbon x 1.1% = about 1.1%.
  - 2 chlorine atoms give a ladder of peaks two units apart (M, M+2, M+4...).
```

And backwards, from an unknown spectrum where M+1 is 7.6% and M+2 is 32% of M:

```text
$ heavytwin --read 7.6 32
- M+2 is about a third of M (32%): one chlorine atom (expected 32%).
- M+1 is 7.6% of M: about 7 carbon atoms (each adds 1.1%).
These are rules of thumb. They suggest; they do not prove.
```

## Usage

| Command | What it does |
|---|---|
| `heavytwin FORMULA` | Masses, isotope pattern and explanation |
| `heavytwin FORMULA --charge N` | Also show m/z for an ion of charge N (-9 to 9) |
| `heavytwin --read M1 M2` | Interpret M+1 and M+2 heights, given as % of M |
| `heavytwin --elements` | List the 22 supported elements |

Formulas can use brackets, nested brackets and hydrates: `Ca(OH)2`, `K4[Fe(CN)6]`, `CuSO4.5H2O`.

## Tech

PHP 8.1+ with strict types, standard library only. No Composer packages.

## Run it

```bash
cd 2026/10-october/07-heavy-twin
php bin/heavytwin C8H10N4O2
php bin/heavytwin C6H12O6 --charge +1
```

Exit codes: `0` success, `2` the input could not be understood.

## Tests

```bash
php tests/run.php
```

287 checks:

- **The data:** abundances sum to 1 and every element matches its periodic-table weight.
- **Published values:** monoisotopic masses of water, caffeine, glucose, aspirin and salt to five decimal places; the 9:6:1 pattern of two chlorines; the M+1 of a 60-carbon fullerene.
- **The maths:** probabilities always add up to 1, and the fast method agrees with the slow one.
- **Round trips:** predict a pattern, read it back, and the carbon count returns.
- **Hostile input:** script tags, shell fragments, terminal escape codes, look-alike Unicode digits, unbalanced and over-nested brackets, absurd counts.

## Security

- **A character allow-list comes first.** A formula may contain only letters, digits, brackets and a dot. Anything else gets one fixed message, and the input is never printed back, so nothing typed can inject terminal escape codes or markup.
- **Bounded work.** Formulas are capped at 200 characters, 10 levels of brackets and 10,000 atoms. Vanishingly small peaks are pruned at every step, so even the worst-case formula finishes in about a second (there is a test for it).
- **Numbers are validated as text before conversion,** so inputs like `1e999`, `NaN` or `-5` never reach the arithmetic.
- **Nothing dangerous in reach.** No `eval`, no shell commands, no file or network access, no `unserialize`. The class loader uses a fixed list of files and never builds a path from input.
- **No dependencies,** so there is no supply chain to attack.

**Known limits, stated honestly:**

- 22 common elements are supported; others are rejected by name instead of guessed.
- Natural isotope abundances vary slightly between samples, so real spectra differ from the prediction by a little.
- Peaks are grouped by whole mass number. High-resolution instruments can split a single "M+2" into several lines; this tool reports their combined height and average mass.
- `--read` applies rules of thumb to two numbers. It suggests candidates; it cannot identify a compound, and it must not be used for any safety-critical or clinical decision.
- No software can promise it is 100% secure; these are the protections in place.
