# Lungful 🫁

**Times a script for reading aloud, and finds the places you'll run out of breath before you record.**

Recording a demo video, a presentation or a podcast intro usually goes like this: write the script, start recording, run out of breath halfway through a long sentence, stumble over "31,742", and discover the introduction was supposed to take 30 seconds and took 50. Lungful catches all of that from the text. It estimates how long each section takes to say, compares it with your target, marks where to breathe in sentences that are too long for one breath, and flags the spots that are hard to say aloud.

## What makes it different

Script timers count words and divide by a speaking rate. Lungful listens to the script the way a voice coach would:

- **Counts syllables, not words.** Speech time follows syllables. A script full of "information technology" takes longer than one full of "the cat sat", even with the same number of words.
- **Reads numbers the way you'll say them.** "222,475" is 15 syllables aloud, "2021" is "twenty twenty-one", "$4.50" is "four dollars fifty", and "NSW" is five syllables because W alone is three.
- **Finds where to breathe.** A stretch longer than one comfortable breath (24 syllables by default) with no comma or full stop gets a breath point, placed before a joint word like *and*, *which* or *because* near the middle, so the meaning survives.
- **Flags tricky spots:** long numbers (with a rounded alternative), piles of acronyms, and tongue-twisting runs of *s* and *sh* sounds.
- **Times each section against its target,** for example an assessment's "1 minute introduction, 2 minute demonstration".

## Example

```text
$ bin/lungful examples/tidepool-demo.md
LUNGFUL  tidepool-demo.md
Speaking at 3.8 syllables a second; a breath every 24 syllables at most

Section        Target  Estimate
Introduction     0:15      0:15   on time
The problem      0:20      0:27   +33% too long, cut about 18 words
Demonstration    0:30      0:31   on time
Conclusion       0:10      0:10   on time
Total            1:15      1:23

BREATHE HERE  (3 stretches too long to say in one breath)
  Introduction, paragraph 2: "...like to thank my supervisor / and the volunteers at the..."
    25 syllables with no comma or full stop. Breathe before "and".
  The problem, paragraph 1: "...of families explore rock pools / without knowing which creatures are..."
    52 syllables with no comma or full stop. Breathe before "without", "and", "to".
  The problem, paragraph 2: "...2023 the NSW coast recorded / 31,742 marine stings..."
    30 syllables with no comma or full stop. Breathe before "31,742".

TRICKY TO SAY
  The problem: "31,742" 12 syllables aloud ("thirty-one thousand seven hundred and forty-two"). Try "about 32,000".
  Demonstration: "She sells seashells" alternating s and sh sounds (a tongue-twister)
  Demonstration: "so she should" alternating s and sh sounds (a tongue-twister)

4 things to fix before recording.
```

Add `--marked` to get the script back with breath marks:

```text
## The problem
Every summer thousands of families explore rock pools / without knowing which creatures are safe to touch / and which ones can hurt them badly enough to need a trip / to the hospital emergency department.
In 2023 the NSW coast recorded / 31,742 marine stings, and most happened in the school holidays.
```

## Writing a script

```markdown
# Introduction [0:30]
Hi, I'm Sam, and this is Tidepool. [ON SCREEN: title card]
(pause)
```

- Headings (`#`, `##` or `###`) start sections. An optional `[m:ss]` sets the target time.
- Text in `[square brackets]` is a direction for you, not something you say.
- `(pause)` or a lone `/` adds a one-second pause.

## Usage

```bash
bin/lungful SCRIPT                       # report
bin/lungful --marked SCRIPT              # report plus the script with breath marks
bin/lungful --rate 3.5 --breath 20 -     # slower speaker, shorter breaths, read standard input
```

`--rate` is syllables a second (default 3.8, a calm presenting pace; conversation is often 4–5). `--breath` is the most syllables you're comfortable saying in one breath (default 24).

Exit codes: `0` ready to record, `1` sections off target or places with nowhere to breathe, `2` the input could not be used.

## Tech

Ruby 3.3, standard library only. Tests use minitest, which comes with Ruby.

## Tests

```bash
ruby -w -Ilib test/test_lungful.rb
```

17 tests with over 2,000 assertions:

- **Syllables:** at least 85% agreement with dictionary counts on 60 common words, including tricky ones like *people*, *beautiful* and *university*.
- **Spoken numbers:** cardinals up to the billions, years read in pairs (*nineteen oh seven*), money, decimals, percentages and spelled-out acronyms.
- **Breath points:** on 300 random sentences, every piece after splitting fits within the breath limit, and joint words near the middle are preferred.
- **Timing:** exactly syllables ÷ rate plus the pauses.
- **Hostile input:** terminal escape codes, right-to-left override and zero-width characters, NUL bytes, invalid UTF-8, oversized files, lines and word counts, too many sections, `/dev/zero`, a directory, and a file name containing escape codes. All are refused or neutralised with one clean error that never repeats the input.

## Security

- **Bounded input:** at most 64 KB is read (an endless stream is cut off), with at most 2,000 characters per line, 12,000 words and 50 sections.
- **Safe to print:** the report repeats your script's words, so control characters, escape codes and invisible characters that reorder text are refused when the script is read. Odd characters in the file name are replaced before it is printed.
- **Errors never repeat the input.**
- **Nothing dangerous in reach:** it only reads the one file named. No network, no shell, no `eval`, no files written, no dependencies.

**Known limits, stated honestly:**

- **Syllable counting is a rule of thumb for English.** It is right most of the time, not always, so treat timings as within about 10%.
- Everyone speaks at their own pace. Time yourself reading one section, then set `--rate` to match.
- Breath points are suggestions; reading a sentence aloud is still the final test.
- No software can promise it is 100% secure; these are the protections in place.
