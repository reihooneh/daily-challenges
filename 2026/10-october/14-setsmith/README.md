# Setsmith

**Plans a band's running order: which songs to play, and in what order, so the set fits the slot, the energy flows, the singer gets a breather and nobody retunes on stage more than they must.**

Language: Go (standard library only) · Field: live music / exact combinatorial optimisation · Day: 14 October 2026

Every gigging band writes a setlist on the back of a beer mat, and every band learns the same lessons the hard way. Don't put the two drop-D songs at opposite ends, or the guitarist retunes twice in silence. Don't make the singer belt three songs in a row. Open strong, give the room a breather in the middle and finish on the biggest song. And don't plan 50 minutes of music for a 45-minute slot. Setlist apps help you *store* the list. Setsmith *decides* it, weighing all of that at once, and its answer is provably the best for the rules you give it, not a guess.

## Quick start

```bash
go run . examples/pub-gig.txt
go test ./...          # includes a brute-force check of the optimiser
```

```
SETSMITH  pub-gig.txt  (slot 45:00, 10 of 12 songs)

 #  Start  Song            Length  Energy
 1   0:00  Northern Line     3:40  ████·
 2   4:00  Midnight Train    3:20  ████·
           ↳ straight into it
 3   7:40  Last Stop         2:50  █████  (hard on the voice)
           ↳ Mia puts a capo on fret 2 (0:15): a good moment to talk to the crowd
 4  11:05  Saltwater         3:55  ███··
 ...
 6  20:30  Home Again        4:40  █····
           ↳ Mia swaps to the spare in dropD (0:15): a good moment to talk to the crowd
 7  25:45  Static Hearts     3:30  ████·  (hard on the voice)
 ...
10  38:05  Wildfire          3:45  █████  (hard on the voice)

Last note at 41:50 of 45:00: 3:10 for talking, encores and surprises.

LEFT OUT
  Slow Burn (maybe): a maybe, and the set is better without it
  Glasshouse (maybe): a maybe, and the set is better without it

ENERGY  ▆▆█▅▃▂▆▆██   (the ideal shape: ▆▆▆▅▅▅▅▅▆▇)
CHANGES 6, costing 1:30 on stage
SCORE   416  (= 90 s of changes + 206 energy + 120 for songs left out; lower is better)
```

## The gig file

```
slot 45:00            # time on stage
reserve 4:00          # kept back for talking and surprises (default: a tenth of the slot)
gap 0:20              # between any two songs
retune 1:30           # to retune an instrument
capo 0:15             # to put on, move or take off a capo
swap 0:15             # to pick up a spare instrument
belt-limit 2          # most songs that are hard on the voice, in a row

player Mia spare dropD          # Mia has a second guitar kept in drop D

song Northern Line | 3:40 | energy 4 | Mia standard, Theo standard | opener
song Paper Lanterns | 4:20 | energy 2 | Mia standard capo 3, Theo standard
song Undertow      | 4:05 | energy 5 | Mia dropD, Theo dropD | hard must
song Midnight Train | 3:20 | energy 4 | Mia standard | then Last Stop
```

| Part of a song | Meaning |
|---|---|
| `3:40` | Length |
| `energy 1-5` | How intense it is (default 3) |
| `Player tuning [capo N]` | Each player's tuning; anyone not listed is sitting out |
| `must` / `want` / `maybe` | How much it matters (default `want`) |
| `hard` | Hard on the singer's voice |
| `opener` / `closer` | Must start or end the set (and is a must) |
| `then Title` | Runs straight into that song (a segue: always played back to back) |

## How it decides

It scores every possible set (one point = one second of dead air) and finds the lowest:

- **changeover time:** the slowest player's retune, capo move or swap between two songs, since players change at the same time;
- **energy:** distance from the ideal arc of open strong, dip, then build, squared;
- **songs left out:** 600 points for a `want`, 60 for a `maybe`.

The hard rules are never broken: the music fits the slot minus the reserve, every `must` is played, the opener and closer stay in place, segues stay together, and there are never more than `belt-limit` hard songs in a row.

For up to 16 songs it checks every combination exactly, using dynamic programming over the subsets of songs, so the result is the true optimum, not a heuristic's guess. A test compares it with brute force on 400 random gigs. The [walkthrough](HOW-IT-WORKS.md) explains how.

## Security

The gig file might come from anyone in the band chat, so it's treated as untrusted:

- **Bounded:** at most 16 KB, 300 characters a line, 16 songs and 8 players, and every time and number has a range. Reading stops at the limit, so `/dev/zero` or a huge paste is refused, not loaded, and only regular files are opened.
- **Strict text:** titles and names must match an allow-list of characters. Control characters, terminal escape codes and invisible bidirectional characters are refused anywhere in the file, so nothing printed can hijack your terminal. Error messages give a line number and never repeat the input, and the file name is cleaned before printing.
- **Bounded work:** the optimiser's memory and time depend only on the song limit (2¹⁶ subsets), not on anything else in the file.
- **No dependencies:** only Go's standard library. `go vet` and `gofmt` are clean, and the tests also pass under the race detector.

**Known limits:** a player who sits out a song is assumed to get ready meanwhile, and the energy arc uses music time, not changeovers.

## Files

```
main.go                 command line: bounded reading, safe file name, exit codes
setlist/gig.go          the file format, validation and contradictions
setlist/plan.go         changeovers, the energy arc and the exact optimiser
setlist/report.go       the running order, as it would be taped to the stage
setlist/setlist_test.go parser, hostile input, rules, brute-force comparison, speed
main_test.go            the command line
examples/pub-gig.txt
```
