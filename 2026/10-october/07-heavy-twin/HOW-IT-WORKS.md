# How Heavy Twin works

A friendly walkthrough so you can explain every part of it.

## 1. The big picture

```
 "CH2Cl2" ──▶ Formula::parse ──▶ { C: 1, H: 2, Cl: 2 }
                                        │
            for each element: the distribution of ONE atom
                 Cl = { +0: 75.76%, +2: 24.24% }
                                        │
            raise it to the number of atoms, then combine elements
                         (convolution)
                                        ▼
                 { +0: 57%, +1: 0.6%, +2: 37%, +4: 5.9%, ... }
                                        │
                 scale so the tallest = 100, add explanations
```

`--read` goes the other way with simple arithmetic: divide M+1 by 1.1 to count carbons, and compare M+2 with the known chlorine and bromine ratios.

## 2. File tour

| File | Job |
|---|---|
| `src/Elements.php` | The isotope table: mass and natural abundance of each isotope |
| `src/Formula.php` | Turns `K4[Fe(CN)6]` into atom counts. The only code that reads raw input. |
| `src/Pattern.php` | The calculation: distributions, convolution, masses, explanations |
| `src/Reader.php` | The backwards direction: peak heights to clues |
| `src/Cli.php` | Arguments, the printed report, exit codes |
| `bin/heavytwin` | Six lines that load the classes and start the program |
| `tests/run.php` | 287 checks with a tiny built-in runner |

### `Formula.php`: a recursive descent parser
The grammar is three rules:

```
formula := part ( "." [count] part )*          CuSO4.5H2O
part    := group+
group   := ( Element | "(" part ")" | "[" part "]" ) [count]
```

There is one method per rule. `part()` loops over groups; when it meets an opening bracket it calls *itself* for the inside, then multiplies the result by the number that follows. That self-call is what makes nesting work, and a depth counter stops it at ten levels.

An element symbol is one capital letter optionally followed by one lower-case letter. That simple rule is why `CO` is carbon monoxide and `Co` would be cobalt.

### `Pattern.php`: the heart of it

**One atom.** Chlorine is `{+0: 0.7576, +2: 0.2424}`: 76% of atoms are the light one, 24% are two units heavier.

**Two atoms.** Every combination can happen. Offsets add; probabilities multiply:

```
light + light   +0   0.7576 × 0.7576 = 0.574
light + heavy   +2   0.7576 × 0.2424 = 0.184   ┐ same offset,
heavy + light   +2   0.2424 × 0.7576 = 0.184   ┘ so they add: 0.367
heavy + heavy   +4   0.2424 × 0.2424 = 0.059
```

That gives the famous 9 : 6 : 1 shape of two chlorines. The operation is called a **convolution**, and it is exactly how you multiply two polynomials: `(0.76 + 0.24x²)²`.

**Many atoms.** A protein might have 2,000 carbons. Convolving 2,000 times would be slow, so `power()` uses **exponentiation by squaring**: compute x², x⁴, x⁸... by repeatedly convolving a distribution with itself, and combine the ones that add up to the count. 2,000 atoms need about 11 squarings.

**True masses.** Each peak stores two numbers: its probability, and probability × mass. When two peaks combine, the second number follows the rule `mass_a × p_b + p_a × mass_b`. At the end, dividing gives the exact average mass of everything in that peak, with no extra pass.

**Pruning.** After each step, peaks more than ten billion times smaller than the tallest are dropped. Without this, the list would grow with every atom.

### `Reader.php`: the rules of thumb
- Each carbon adds 1.08% to M+1, so carbons ≈ M+1 ÷ 1.1.
- One chlorine makes M+2 32% of M; one bromine makes it 97%.
- Whatever is left of M+2 after halogens and double carbon-13 is tested against sulfur (4.5% each) and oxygen (0.2% each).

## 3. Key concepts

| Concept | Plain version |
|---|---|
| Isotope | A version of an element with a different number of neutrons, so a different mass |
| Monoisotopic mass | The mass when every atom is its most common isotope: the "M" peak |
| Average mass | The abundance-weighted mean: the number on the periodic table |
| m/z | Mass divided by charge, which is what a mass spectrometer measures |
| Convolution | Combining two distributions by trying every pair: add positions, multiply probabilities |
| Exponentiation by squaring | Reaching the n-th power in about log₂(n) steps instead of n |
| Allow-list | Accept only known-safe characters, reject everything else |

### PHP features you met here
- **`declare(strict_types=1)`**: PHP stops silently converting `"5 apples"` to 5.
- **Namespaces** (`HeavyTwin\Pattern`) and a small **autoloader** with a fixed class map.
- **`final class` with static methods** for stateless helpers, and a **private constructor** on the parser so it can only be used through `Formula::parse()`.
- **Constructor property promotion** and **`readonly`** (`private readonly string $text`).
- **Typed everything**: parameters, returns, nullable types (`?string`).
- **Array destructuring in `foreach`** (`foreach ($a as $offset => [$p, $mass])`).
- **Arrow functions** (`static fn (float $x): bool => ...`) and the **null-coalescing assignment** `??=`.
- **Custom exceptions** for expected problems, turned into one clean line at the edge.
- **Heredoc/nowdoc strings** for the usage text.
- **`proc_open` with an array**, which starts a program without a shell.

## 4. Interview questions you might get

**Q: How do you compute an isotope pattern for a molecule with thousands of atoms?**
A: I treat one atom's isotopes as a small probability distribution and combine atoms by convolution, which is polynomial multiplication. For n identical atoms I use exponentiation by squaring, so the cost grows with log n, not n. After each step I prune peaks far below the tallest so the lists stay short. A test confirms the fast method matches naive repeated convolution, and that probabilities still sum to 1 for a 10,000-atom formula.

**Q: How do you know your isotope data is right?**
A: Three independent checks in the tests. Abundances for each element must sum to 1. The abundance-weighted mean must match the standard atomic weight. And computed monoisotopic masses for known compounds, such as caffeine at 194.08038, must match published values to five decimals. The only tolerance I had to widen was selenium's, whose official weight was revised.

**Q: The tool takes a string from the user. What's your threat model?**
A: The string is the whole attack surface, so it goes through an allow-list before anything else: letters, digits, brackets, dot. Errors never echo the input. Length, nesting depth, counts and total atoms are capped, and pruning bounds the calculation, so no formula can hang it. There's no file, network, shell or `eval` use anywhere, so there is nothing for a malicious input to reach.

## 5. Ideas to extend it yourself

1. **All elements:** load the full NIST table from a data file (validated at start-up by the same tests).
2. **Formula search:** given a measured mass and a tolerance, list the formulas that fit, then rank them by how well their predicted pattern matches.
3. **Fine structure:** keep exact masses separate instead of grouping by whole number, to imitate a high-resolution instrument.
