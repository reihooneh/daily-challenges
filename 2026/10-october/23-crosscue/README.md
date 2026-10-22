# Crosscue

**Works out who walks to which spot when a dance group changes formation, so the longest walk is as short as possible, the change fits the music, and nobody walks into anyone else.**

Language: Ruby 3.3 (standard library only) · Field: dance choreography / assignment problems · Day: 23 October 2026

Choreographers draw formations, a V, two lines, a circle, but the hard part is the change between them. Which dancer takes which spot? With eight dancers there are 40,320 ways to assign them. A poor choice sends someone sprinting across the stage while two others brush shoulders in the middle.

Crosscue chooses the assignment that **minimises the longest walk**, so the change fits the fewest counts. Among the assignments that do that, it picks the one with the least walking in total. It then checks every pair of paths for near-misses and fixes them by changing timing: one dancer waits a beat, or hurries and arrives early. It never asks anyone to walk faster than your pace.

## Quick start

```bash
ruby test/test_crosscue.rb          # 13 tests, 745 assertions
bin/crosscue examples/opening.txt
```

```
Change 1: V -> Two lines, 8 counts (4.0 s)
  Dancer  From         To              Walk   Go on count
  Ava     (5, 6.5)     (4, 5)         1.8 m   1
  Ben     (4, 5.5)     (4, 3)         2.5 m   1
  ...
  Gus     (8, 3.5)     (6, 3)         2.1 m   1 (be there by 5)
  Hana    (5, 2)       (8, 3)         3.2 m   1
  Longest walk 3.2 m (needs 5 counts at your pace); everyone together walks 12.8 m.
  To pass cleanly: Gus arrives by count 5.
   back of the stage
   +-----------------------------------------+
   |        De      Av     Cl      El        |
   |                                         |
   |        Fa      Be     Gu      Ha        |
   +-----------------------------------------+
   audience
```

(Map trimmed here.) Gus and Hana would pass 0.57 m apart, so Gus gets there by count 5 and the gap opens up. Hana is pinned to her spot because she has a solo exit. If a change can't fit its counts, Crosscue says **TOO FAST** and how many counts it needs.

## The show file

```
show Spring recital opening
stage 10 x 8          # metres: width x depth; x from the audience's left, y from the front edge
tempo 120             # counts per minute
pace 1.4              # fastest comfortable walk, metres per second
space 0.6             # closest two moving dancers may pass, metres

formation V           # the first formation names every dancer
  Ava  5.0 6.5
  Hana 5.0 2.0
formation Two lines in 8 counts
  spot 2.0 5.0        # anyone may end here
  Hana 8.0 3.0        # Hana must end here
```

Exit codes: `0` every change fits, `1` a change needs attention, `2` bad input. `-` reads standard input.

## Security

- **Safe file reading:**
  - Only regular files are opened. The path is checked with `lstat` and opened with `O_NOFOLLOW`, so symbolic links, directories and devices are refused.
  - At most 64 KB is read, from a file or standard input.
  - The text must be valid UTF-8.
- **Strict parsing:**
  - Every line has a fixed form, and every number is a plain decimal with a range (no `1e3`, no negatives).
  - Dancer names are one capitalised word.
  - Control characters and hidden Unicode direction marks are refused.
  - Sizes are capped: 200 characters a line, 40 dancers, 12 formations, 64 counts a change.
- **Clean messages:** errors give a line number and never echo the input. File names are cleaned before printing.
- **No dependencies,** and the code and tests run warning-free under `ruby -w`.

**Known limits:**
- Paths are straight lines. Real dancers curve, travel in patterns, and have choreography during the change.
- Near-misses are only fixed by timing. If that isn't enough, Crosscue reports them for you to restage.
- Bodies are treated as points: `space` is the gap you ask for between dancers' centres.

See [HOW-IT-WORKS.md](HOW-IT-WORKS.md) for the walkthrough.
