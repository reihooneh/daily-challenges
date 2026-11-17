# Catchbreath

**Marks where a singer should breathe, so no phrase runs out of air and no breath breaks a phrase in the wrong place.**

Language: PHP 8.3 (no dependencies) · Field: singing / dynamic programming · Day: 17 November 2026 (evening)

Choir directors and singing teachers pencil breath marks into scores: here at the comma, not between "the" and "sound", and somewhere in that long line because nobody can hold it. Catchbreath does that from the lyrics and the rhythm. You give it each syllable and how many beats it lasts, the tempo, and how long you can comfortably sing on one breath. It finds the best set of breath marks and shows how full each phrase gets.

- **Never inside a word.** A breath can only go between words.
- **Rests are free.** A breath in a rest costs nothing and doesn't shorten a note.
- **Good places are cheap.** Full stops, line ends and commas cost less than between ordinary words. After "the", "a", "of" or "my" costs the most, because it cuts a word off from the one it belongs to.
- **Quick breaths take time.** A catch breath steals a little from the note before it. A breath that would swallow a short note altogether is avoided.
- **Each phrase fits one breath.** A phrase near the limit costs a little extra, so plans leave headroom.
- **Some stretches can't be fixed with a breath mark.** A note held longer than one breath gets flagged, with ways to fix it: a bigger breath before it, a faster tempo, a shorter note, or staggered breathing in a choir.

## Example

```text
$ bin/catchbreath examples/amazing-grace.txt
Catchbreath: Amazing Grace  (88 beats a minute, 9 s on one breath)

  Amazing grace! ’ how sweet the sound ’
  That saved a wretch like me! ’
  I once was lost, ’ but now am found, ’
  Was blind, but now I see. ’
  'Twas grace that taught my heart ’ to fear, ’
  And grace my fears relieved; ’
  How precious did that grace ’ appear ’
  The hour I first believed.

11 breaths: 1 in rests, 10 quick catch breaths. Longest phrase 8.2 s (91% of your breath).

  #   phrase                             seconds  of one breath
  1   Amazing grace!                         4.1   45% #########
  2   how sweet the sound                    6.1   68% ##############
  3   That saved a wretch like me!           8.2   91% ##################
  ...
```

At 88 beats a minute, "Amazing grace! how sweet the sound" lasts 10.2 seconds, more than a 9-second breath. Catchbreath splits it at the exclamation mark. "Was blind, but now I see" fits, at 91%, so it stays whole.

The examples use public-domain hymns and songs ("Amazing Grace", John Newton, 1779; "Auld Lang Syne", Robert Burns, 1788). [`examples/held-note.txt`](examples/held-note.txt) has a 14-second held note that no breath mark can fix (exit code 3).

## Writing a song

```text
title: Amazing Grace
tempo: 88        beats per minute (20 to 300)
breath: 9        seconds you can comfortably sing on one breath (2 to 60)
catch: 0.5       beats a quick breath takes from the note before it (0.125 to 2)

A-:1 ma-:2 zing:1 grace!:2 how:1 sweet:2 the:1 sound:5
```

Write each syllable followed by `:` and its beats. A syllable ending in `-` carries on into the next one. `_` is a rest, punctuation stays on its word, each text line is a lyric line, and `#` starts a comment.

## Run and test

```bash
bin/catchbreath examples/amazing-grace.txt
bin/catchbreath examples/auld-lang-syne.txt --breath 8 --tempo 100   # try another singer or tempo
bin/catchbreath - < my-song.txt
php tests/run.php     # 1,091 checks
```

Exit codes: 0 every phrase fits, 3 some stretch is longer than one breath, 1 the song couldn't be read, 2 usage.

The tests:
- check every cost rule;
- compare the plan with **trying every combination of breaths** on 300 random songs;
- refuse bad input: NUL bytes, size, invalid UTF-8, beats out of range, rests inside a word, too many notes;
- check that control characters are never echoed back;
- run the command line, including links and folders;
- run the largest allowed song against a time limit.

## Security

Catchbreath reads one text file and prints a plan. No software is perfectly secure; this is what's in place.

- **Only plain files:** links, folders and missing files are refused, and files are read with a 64 KB cap.
- **Strict reading:** every line is read with anchored regular expressions. There's no `eval`, no `include` of user data, no shell and no unserialise.
- **Bounded input:**
  - text must be valid UTF-8 with no NUL bytes;
  - at most 5,000 notes, each lasting more than 0 and at most 32 beats;
  - tempo, breath and catch must fall in fixed ranges, and so must the values given on the command line.
- **Bounded work:** the planner is O(n²) at worst, and it stops looking back once a phrase can't fit. The largest allowed song plans in well under a second, and a test checks it.
- **Safe output:** text quoted back from the file has control characters replaced and is cut short, so a song can't send escape codes to the terminal.

**Limits:**
- The costs are a reasonable default, not a vocal teacher's judgment. Change them in `src/Planner.php`.
- It doesn't read sheet music (MusicXML); you type the beats.
- It plans for one singer. For a choir, see staggered breathing in the extension ideas.

More detail: [HOW-IT-WORKS.md](HOW-IT-WORKS.md).
