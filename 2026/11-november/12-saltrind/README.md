# Saltrind

**How long to leave each batch of cheese in the brine, and what each batch does to the brine.**

Language: C++20 (standard library only) · Field: cheesemaking / diffusion modelling · Day: 12 November 2026 (morning)

Brined cheeses (gouda, feta, halloumi, parmesan and many more) get their salt by soaking in a tub of strong brine. How long is the usual guess: a few hours per pound, adjusted by feel. The guess hides three things:

- **Shape matters more than weight.** Salt soaks in through the faces, so a flat wheel salts faster than a tall one of the same weight.
- **The brine gets weaker.** Every wheel takes salt out and gives water back. Without topping up, the second and third batches take longer, and a brine below about 18 % lets the rind go soft.
- **"Done" isn't even.** When a wheel comes out, the rind is very salty and the middle has none yet. The salt evens out over weeks of ripening.

Saltrind models the salt moving into each wheel, cell by cell, and the brine losing salt and gaining water batch by batch. For each batch it says how long to brine, how much salt each wheel takes, how the brine changes, how much salt to add back, and how long the salt takes to even out inside.

## Features

- **A real diffusion model:** the wheel is a cylinder cut into 40 rings and 20 layers (only the top half, since the wheel is symmetric about its middle). Salt moves between cells by Fick's law, and into the faces through the rind from the brine.
- **Checked against the exact answer:** with no rind, the model matches the textbook series solution for a finite cylinder (Crank) within 1 %. A finer grid changes the brining time by less than 2 %.
- **The brine as a tank:** each gram of salt a wheel takes leaves the brine, and 1.6 g of water comes out of the cheese into it. Batches go in one after another, with or without topping up.
- **Temperature and moisture:** salt diffuses faster in warmer brine (activation energy 35 kJ/mol) and in moister cheese.
- **Timing to the minute:** it steps an hour at a time, then bisects the last hour for the moment the wheel's average reaches the target.
- **Pictures in the terminal:** salt through a cut wheel when it comes out and after resting, and the average climbing towards the target.

## Example

```text
$ ./build/saltrind examples/gouda-run.txt
Saltrind: 40 L of 23.0 % brine at 12 °C (10.8 kg of salt in 36.0 kg of water)
Batches go in one after another, with the brine topped back up between them.

1. gouda: 3 wheels, 22 × 9 cm, 3.66 kg each, 42 % moisture
   Brine for 1 d 11 h 09 min to reach 4.5 % salt-in-moisture on average.
   Each wheel takes in 69 g of salt (1.89 % of its weight).
   Coming out: 24.0 % at the rind corner, 0.00 % at the centre.
   Resting: the centre reaches 90 % of the average after about 79 days.
   Brine: 23.0 % → 22.5 %; add 307 g of salt to bring it back.

   Salt through a cut wheel when it comes out of the brine (darker = saltier, 0 to 14 % or more):
    |@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@|  top face
    |***********************************#%@@@|
    |::::::::::::::::::::::::::::::::---=+#@@|
    |..................................::-+%@|
    |                                 ..:-+%@|
    |                                  .:-+%@|
    ...
    |                                  .:-+%@|  middle
     centre                              rind
```

The second example, [`small-tub.txt`](examples/small-tub.txt), brines three pairs of feta-style blocks in 4 L without topping up. Each batch takes longer than the last (36 h, 42 h, 50 h), and Saltrind warns once the brine drops below 18 %.

## Writing a plan

```text
# Lines starting with # are comments.
brine litres=40 salt=23 temp=12 restore=yes      # restore: top up between batches (default yes)
cheese name=gouda diameter=22 height=9 moisture=42 count=3 target=4.5
cheese name=baby-gouda diameter=10 height=5 moisture=43 count=12 target=4.5 start=0
```

- `salt` is the brine's strength by weight (26.4 % is saturated); `temp` is in °C.
- `diameter` and `height` are in cm; `moisture` is the cheese's water content in %.
- `target` is the salt-in-moisture to stop at (salt as a % of the cheese's water, the figure cheesemakers aim for), and `start` is any salt already in the curd.

## Build and run

```bash
make                                    # build/saltrind (warnings are errors)
./build/saltrind examples/gouda-run.txt
make test                               # 52 checks, built with address and undefined-behaviour sanitizers
make lint                               # clang-tidy
```

## Tests

- **Exact solution:** a finite cylinder with its faces held at the brine's strength, against the product of the infinite-cylinder and slab series, at 0.5, 1, 4 and 15 days.
- **Grid independence:** 40 × 20 and 80 × 40 cells give brining times within 2 %.
- **Bookkeeping:** resting never gains or loses salt; the salt the wheels take is exactly what the brine loses; topping up restores the strength exactly.
- **Stability:** no cell ever goes above the brine or below the starting salt.
- **Behaviour:** small wheels, warmer brine and stronger brine are all faster; a depleting brine slows each batch.
- **Hostile plans:** 20 kinds of bad input (unknown keys, duplicates, NaN, infinity, trailing junk, markup in names, NUL bytes, oversized files, more cheese than brine), and a check that errors never repeat the input.
- **Worst case:** the biggest plan the limits allow still finishes.

## Security

Saltrind reads one plan file and prints a report. No software is perfectly secure; this is how the risks are handled.

- **Only plain files:** folders, devices and symbolic links are refused, and anything over 64 KB is refused before it's read.
- **Bounded input:**
  - a brine line and at most 20 cheese lines;
  - every number is parsed strictly (`std::from_chars`, no trailing junk, no NaN or infinity) and has a range;
  - names are 1 to 32 letters, digits, `-` or `_`;
  - NUL bytes are refused.
- **Errors name the line and setting, never the value**, so a hostile file can't put escape codes in your terminal. A test checks it.
- **Bounded work:** grid size is fixed, brining stops at 40 days and resting at 400, and the time step comes from the stability limit. The largest allowed plan is a test.
- **Memory safety:** the tests run under AddressSanitizer and UndefinedBehaviorSanitizer, the build treats warnings (including sign and narrowing conversions) as errors, and clang-tidy's bugprone, CERT and analyzer checks are clean.

## Limits

- **The rind is one number.** How easily salt crosses it (0.6 cm/day) is set so a 3.7 kg gouda takes about a day and a half and a 12 kg one about three, as in common practice. A cheese with a very different rind needs a different value.
- **The cheese doesn't shrink.** Real wheels lose a few percent of their water, and so a little weight, in the brine.
- **Floating wheels:** cheese floats with its top face out of the brine unless turned or salted on top. Saltrind assumes it's fully covered.
- **Not food-safety advice.** Brine hygiene (pH, calcium, cleaning) matters as much as strength.

## Sources

- T. J. Geurts, P. Walstra and H. Mulder, "Transport of salt and water during salting of cheese", *Netherlands Milk and Dairy Journal* (1974): diffusion coefficients of salt in Gouda.
- J. Crank, *The Mathematics of Diffusion*, 2nd ed. (1975), ch. 5: the series solutions for a cylinder and a slab.
- T. P. Guinee and P. F. Fox, "Salt in cheese: physical, chemical and biological aspects", in *Cheese: Chemistry, Physics and Microbiology*: brining practice and salt-in-moisture targets.
- C. Melilli et al., [Influence of brine concentration, brine temperature, and presalting on early gas defects](https://www.iris.unict.it/retrieve/dfe4d227-3c37-bb0a-e053-d805fe0a78d9/Melilli_2004_Influence%20of%20Brine%20Concentration%2c%20Brine%20Temperature%2c%20and%20Presalting.pdf) (2004): how brine strength and temperature change salt uptake.
- [Optimising Cheese Brining Times](https://journal.austms.org.au/ojs/index.php/ANZIAMJ/article/view/9430) (ANZIAM J., MISG 2014): a research model of Gouda brining for a dairy company. Saltrind is a small planning tool with a simpler model, adding the brine's depletion across batches.

More detail: [HOW-IT-WORKS.md](HOW-IT-WORKS.md).
