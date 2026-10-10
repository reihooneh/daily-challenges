# How Lungful works

A walkthrough so you can explain every part of it.

## 1. The big picture

```
 script.md ──▶ Script.parse      sections, [m:ss] targets, directions removed
                    │
                    ▼
            phrases_of(line)     split at , ; : . ? ! — and (pause); each phrase knows its pause
                    │
                    ▼
       Spoken.token_syllables    "cat" 1 · "222,475" 15 · "2021" 5 · "NSW" 5
                    │
                    ▼
             Analysis.run        seconds = syllables / rate + pauses
                    │            split_points(): where to breathe in over-long phrases
                    │            tricky_spots(): long numbers, acronym piles, s/sh runs
                    ▼
               Report            table vs targets · BREATHE HERE · TRICKY TO SAY · --marked
```

## 2. File tour

| File | Job |
|---|---|
| `lib/lungful/spoken.rb` | Syllables in a word, and what numbers, money, percentages and acronyms sound like |
| `lib/lungful/script.rb` | Reads the script safely: sections, targets, phrases and pauses |
| `lib/lungful/analysis.rb` | Timing, breath points and tricky spots |
| `lib/lungful/report.rb` | The report and the marked-up script |
| `lib/lungful.rb` | Command line, bounded file reading, exit codes |
| `test/test_lungful.rb` | 17 minitest tests |

## 3. Key ideas

### Why syllables, not words
Speaking rate is fairly steady in syllables per second (often 4 to 5 in conversation, a little slower when presenting), while words vary from one syllable to six. So the estimate is `syllables ÷ rate`, plus a pause for each comma (0.3 s), colon or semicolon (0.4 s), full stop (0.6 s), paragraph or `(pause)` (1 s).

### Counting syllables without a dictionary
English spelling is messy, but a classic rule works most of the time: count the groups of vowels (*com-pu-ter*: o, u, e → 3). The fixes:

- **Silent e:** strip a final *e*, *es* or *ed* after a consonant (*make*, *hoped*), but not *le* (*table* keeps its second syllable).
- **A leading y** is a consonant (*yes*).
- **A short list of exceptions** that the rule gets wrong (*people*, *every*, *beautiful*).

The tests measure it against dictionary counts rather than pretending it is perfect.

### Numbers become words first
A number's length on the page says nothing about how long it takes to say. `Spoken.expand` turns it into the words you'd actually say, then counts their syllables. Four-digit numbers between 1100 and 2099 are read as years, in pairs. Money adds "dollars", and decimals become "point seven". Two- or three-letter acronyms in capitals are spelled out letter by letter. Anything 10 syllables or longer gets a rounded alternative ("about 32,000"), because listeners don't keep exact figures anyway.

### Choosing where to breathe
A phrase over the breath limit is cut in two, then each half is checked again (a recursive divide):

1. Look at word boundaries between 30% and 70% of the way through, by syllables.
2. Prefer one before a **joint word** (*and, but, which, because, when, to…*), since a breath there sounds natural and keeps the meaning.
3. Otherwise cut at the boundary nearest the middle.

The tests check the guarantee on 300 random sentences: after splitting, every piece fits (or is a single word that can't be split).

### Tongue-twisters
Alternating *s* and *sh* (or *ch*, *z*) sounds at the start of three words in a row ("she sells seashells") make the tongue switch position quickly. Lungful looks for runs of three words whose opening sounds are all sibilants, and not all the same one.

## 4. Glossary

| Term | Plain version |
|---|---|
| Syllable | A beat of speech, built around a vowel sound |
| Breath group | The words said on one breath |
| Speaking rate | How fast someone talks, here in syllables per second |
| Sibilant | A hissing sound: s, sh, z, ch |
| Heuristic | A rule of thumb that is usually right |

### Ruby features you met here
- **`Struct` with a block** (`Phrase` with a `syllables` method), and **endless methods** (`def syllables = ...`).
- **Regular expressions** with named and numbered groups, `\A`/`\z` anchors, and Unicode ranges to refuse invisible characters.
- **`module_function`** for modules of plain functions, and **`frozen_string_literal`**.
- **Enumerable**: `each_cons`, `group_by`, `min_by`, `sum`, `count`.
- **Exceptions** for input errors, rescued once in `main` to give a single clean line.
- **Minitest** with `assert_raises`, `assert_in_delta` and a seeded `Random` for repeatable random tests.

## 5. Interview questions you might get

**Q: How accurate is the syllable counter, and how did you check?**
A: It's a vowel-group heuristic with fixes for silent *e*, a leading *y* and a list of exceptions. I don't claim it's perfect: the test compares it with dictionary counts for 60 common words and requires at least 85% agreement. The README says timings are good to about 10%, and suggests calibrating `--rate` by timing yourself on one section.

**Q: Why put breath points before words like "and" or "which"?**
A: They join clauses, so pausing before them follows the sentence's structure and keeps each piece meaningful. If none is near the middle, the tool falls back to the middle word boundary. It recurses until every piece fits, and a randomised test checks that guarantee.

**Q: The report prints the user's own text. How is that safe?**
A: Printing text to a terminal can be dangerous if it contains escape codes, which can change the title, colours or more, or invisible bidirectional characters that make text look different from what it is. The parser refuses control characters and those invisible characters up front, the file name is cleaned before printing, and errors never echo input. There are tests for each case.

## 6. Ideas to extend it

1. **Calibrate from a recording:** time yourself reading one section, and Lungful works out your personal rate.
2. **Pronunciation dictionary:** use the CMU Pronouncing Dictionary for exact syllables when a word is listed, with the rule of thumb as a fallback.
3. **Teleprompter mode:** an HTML page that scrolls the marked script at your measured pace, with a strict Content-Security-Policy.
