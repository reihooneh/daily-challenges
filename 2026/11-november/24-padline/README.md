# Padline

**Where to put your bouldering crash pads so they're under where you'd actually land.**

Outdoors, a fall off a boulder doesn't land at the foot of the wall. The higher you are, the further
out and the more scattered the landing, and a fall from the crux or the top-out matters more than one
from the first move. Pads end up wherever they were dropped, with a gap right under the crux and a
rock beside it. Padline takes the holds along a problem, the rocks on the ground and the pads you've
brought, works out where falls land, and places the pads to cover as much of it as possible.

## Features

- A landing model per hold: further out and more spread from higher up, weighted by height^1.5, twice
  for the crux and 1.5 times for the top-out; rocks and roots make the ground under them four times
  worse.
- Pads placed without overlapping, turned either way, to cover the most risk: biggest first, then
  improved by lifting one pad, or a pair of pads, and putting them down again. Tested to come within
  3 % of trying every pair of placements.
- The worst bare ground left, for a spotter or another pad, and a map of the landing zone.

## Example

```
$ ./padline examples/arete.txt
6 holds, 3 pads, 6.0 x 3.5 m of ground.
The pads cover 63% of where falls would land (weighted by height and hazards).

  A  1.2 x 1    3.5 to 4.5 m along the boulder, 0.5 to 1.7 m out from it
  B  1.2 x 1    2.3 to 3.5 m along the boulder, 0.5 to 1.5 m out from it
  C  1 x 0.6    4.5 to 5.1 m along the boulder, 0.7 to 1.7 m out from it

Worst bare ground: 2.2 m along, 1.0 m out. Put a spotter there, or another pad.

  boulder ============================================================
   0.0 m      ....................................................    
   0.2 m   ......................:::::::::::::::::::::::............  
   0.4 m  .......:::::::::::::::::::::::::::::::::::::::::::::........
   0.6 m  .....::::::::::::::::::BBBBBBBBBBBBAAAAAAAAAA:::::::::......
   0.8 m  .......:::::::::::::::-BBBBBBBBBBBBAAAAAAAAAACCCCCC::::.....
   1.0 m   ...........::::::::::-BBBBBBBBBBBBAAAAAAAAAACCCCCC:::::....
   1.2 m       ...........:::::::BBBBBBBBBBBBAAAAAAAAAACCCCCC:::::....
   1.4 m            ..........:::BBBBBBBBBBBBAAAAAAAAAACCCCCC:::::....
   1.6 m                ..........:::::::::::AAAAAAAAAACCCCCC::::.....
   1.8 m                    ............::::::::::::::::::::::::......
   2.0 m                         ..............::::::::::::::.........
   2.2 m         oooooo               ..............................  
   2.4 m         oooooo                    .......................    
   2.6 m          oooo                           .............        
   2.8 m                                                              
   3.0 m                                                              
   3.2 m                                                              
   3.4 m                                                              

  Letters are pads; . : - = # is where falls land, densest at #; o is a rock.
```

A problem file has `ground ALONG OUT` (metres), `hold ALONG HEIGHT [crux] [topout]` lines, `rock
ALONG OUT RADIUS` lines and `pad LENGTH WIDTH [x2]` lines.

## Build and test

```sh
make            # ./padline examples/arete.txt
make test       # AddressSanitizer and UBSan
make lint       # clang-tidy (bugprone, performance, clang-analyzer), warnings as errors
```

C++20, standard library only, `-Wall -Wextra -Wpedantic -Wconversion -Werror`.

## Security

- The problem must be a regular file (not a symlink) under 32 KB; lines over 200 characters and
  control characters (terminal escapes included) are refused.
- Numbers are read with `std::from_chars` after a digits-and-point-only check, so signs, exponents,
  `nan` and `inf` never get in, and every value has a range.
- At most 60 holds, 40 rocks and 12 pads, and the ground is at most 20 x 10 m, which bounds the grid
  (20,000 cells) and the search.
- Known limits: the landing model is a rule of thumb, not physics; a spotter's eye beats it, and
  pads don't make high falls safe.
