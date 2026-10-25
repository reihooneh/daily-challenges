# Bowball

**Turns a morning of seat racing into a crew selection you can trust: each rower's speed with honest error bars, their chance of making the boat, and the one swap to race next that would settle it fastest.**

Language: Go 1.24 (standard library only) · Field: rowing / statistical design of experiments · Day: 26 October 2026

Seat racing is how rowing coaches pick crews. Two boats race a piece, one rower from each boat swaps, and they race again. The change in the margin says which of the two swapped rowers moves a boat more. On the water it gets messy: the wind shifts, one hull is quicker, crews tire, and after six pieces of crossing swaps it's hard to say who is actually ahead. Bowball takes every piece at once and works it out:

- **Speeds:** each rower's speed in seconds per 1000 m against the rest of their side, with a standard error. It is fitted by least squares on all pieces together, so swaps link up even when two rowers never swapped directly.
- **Hulls:** how much faster or slower each boat is, taken out of everyone's numbers.
- **Chance of a seat:** for every rower, from 20,000 plausible sets of speeds. Sweep boats fill half the seats on each side, and rowers listed as `either` fill whichever side gains most.
- **Close calls:** the pairs either side of the selection line most likely to be the wrong way round.
- **Next swap:** every legal swap for the next piece, scored by how much it would cut the expected number of wrong calls at the selection line. It also checks "race the same crews again".
- **Odd results:** a crab or a steering error gets flagged as a time that doesn't fit the others.

## Quick start

```bash
make build                                  # build/bowball
./build/bowball examples/womens-four.txt
make test                                   # 13 tests, race detector on
make lint                                   # gofmt + go vet
make fuzz                                   # 30 s of fuzzing the parser and report
```

```
BOWBALL  Women's four selection
8 rowers, 8 pieces, 4 seats to fill.
Speed: seconds per 1000 m a rower takes off a crew, compared with the average of their side.
Timing noise: assumed about 0.54 s per 1000 m per crew (too few pieces to estimate it yet).

BOW SIDE                  Speed    +/-   Boat   Chance of a seat
  1. Ava                  +1.27   0.29   in     100%  ##########
  2. Eve                  +1.25   0.39   in     100%  ##########
  3. Dee                  -0.72   0.29            0%  ..........
  4. Hana                 -1.80   0.39            0%  ..........

STROKE SIDE               Speed    +/-   Boat   Chance of a seat
  1. Gia                  +0.87   0.38   in      97%  ##########
  2. Cat                  +0.19   0.27   in      89%  #########.
  3. Bea                  -0.30   0.33           12%  #.........
  4. Fay                  -0.76   0.30            2%  ..........

Hulls (seconds per 1000 m slower than average): Blue -0.56 (+/- 0.25), Red +0.56 (+/- 0.25).

Closest calls at the selection line:
  Cat over Bea: 10% chance that's the wrong way round

Next piece: start from the last piece's Blue and Red crews and
  1. swap Eve (Blue) with Dee (Red)               expected wrong calls 0.17 -> 0.12
  2. swap Eve (Blue) with Ava (Red)               expected wrong calls 0.17 -> 0.12
  3. swap Bea (Blue) with Gia (Red)               expected wrong calls 0.17 -> 0.13
```

In that example every swap after the first piece was the one Bowball suggested from the results so far. The four it picks (Ava, Eve, Cat, Gia) is the right one: the example was simulated from known speeds. The Red hull really was slower, by 0.5 s per 1000 m; Bowball's estimate is 1.1 ± 0.5. `examples/double-sculls.txt` shows a sculling squad with three boats per piece. After four pieces, a lot is still uncertain, and the chances show it.

## The session file

```
squad Women's four selection
seats 4                    # how many make the boat (default: the size of the first boat)
noise 0.6                  # optional starting guess: timing noise per crew, s per 1000 m
rower Ava bow              # side: bow, stroke or either (or none for sculling)
rower Bea stroke
...
piece 1000 m               # 100 to 6000 m; times are scaled to 1000 m
boat Blue 3:19.4 Ava Bea Dee Fay
boat Red  3:19.0 Eve Cat Hana Gia
```

Each piece has 2 to 4 boats with the same number of rowers. The same hull name in two pieces is the same boat. Times are `m:ss.s` or seconds; only the differences within a piece matter, so margins from a stopwatch at the finish work too. Exit codes: `0` report printed, `2` bad usage or input. `-` reads standard input.

## Security

Bowball reads one text file and prints text, so the risks are hostile input and runaway work:

- **Bounded reading:** at most 64 KB from a file or standard input; an endless stream is cut off and reported. Only regular files are opened (folders and devices are refused), and the path is never echoed.
- **Strict parsing:** every line has a fixed form, and numbers must match tight patterns (no signs, exponents, `NaN` or `Inf`) and ranges: times up to an hour, pieces 100 to 6000 m, noise 0.05 to 10 s. Names are one word of letters, digits and `' . -`. There are hard caps: 40 rowers, 60 pieces, 8 hulls, 4 boats a piece and 8 rowers a boat.
- **Clean text:** input must be valid UTF-8. Control characters (terminal escapes), zero-width characters and direction marks are refused, so a file can't print differently from how it reads.
- **No echo:** error messages give a line number and never repeat the input.
- **Bounded work:** the caps keep every matrix at most 108 × 108, and the simulation is a fixed 20,000 draws, so the run time is bounded.
- **Repeatable:** the random draws use a fixed seed, so the same file always gives the same report.
- **Checked:** `go vet` and `gofmt` are clean, the tests run under the race detector, and a fuzz test feeds random files through the parser and the whole report. There are no dependencies beyond the standard library.

**Known limits:** speeds are relative within a side (seat racing never compares bow side with stroke side). The model is additive: it assumes a rower adds the same speed whatever crew they're in, which real crews don't always do. The swap advice plans for uncertainty, not luck: it can't know what the next piece will show. Seat racing is one input to selection, never the whole of it.

See [HOW-IT-WORKS.md](HOW-IT-WORKS.md) for the walkthrough.
