# Sticksmith

**Which hand plays which note? Sticksmith works it out for any drum fill or groove.**

Write out a passage in a few plain lines. Sticksmith picks a hand for every note, the way a teacher would, then tells you:
- the fastest tempo the passage can be played at;
- the exact note where it falls apart beyond that;
- how much better the sticking is than plain alternating.

Drum books print stickings for rudiments, but not for the fill you wrote yourself. Practice apps check the sticking you chose, but don't choose one for you.

## Features

- **A real search, not a rule of thumb.** A dynamic programme considers every way of sticking the passage, and gives the cheapest one that two real hands can play in time. On 540 random passages it matches trying every sticking one by one.
- **Hands with limits:**
  - one hand can only play single strokes so fast;
  - a double (two quick strokes on one drum) has to rebound, and can't become a triple;
  - moving across the kit takes time in proportion to the distance;
  - two drums at once need both hands.
- **Hands with habits:**
  - the right hand stays crossed over to the hi-hat;
  - the lead hand takes the beats, and the weaker hand avoids long reaches to the far side;
  - hands passing over each other in a hurry are avoided.

  Each habit is a cost, so it can be broken when it must be (for example, a left-hand crash because the right can't get there in time).
- **The fastest playable tempo** is found by binary search, re-sticking at every tempo. Sticksmith also names the note where it breaks.
- **A comparison with plain alternating** (R L R L): the hand travel, the crossovers, and its own speed limit.
- **Your kit, your hands:**
  - add or move drums by position;
  - choose right- or left-hand lead;
  - choose beginner, average or fast hands;
  - grids from quarter notes to 32nds, including triplets.

## Example

```text
$ node bin/sticksmith.js examples/rock-fill.txt
Sticksmith: Rock groove into a tom fill
112 bpm · 16th-note grid · right hand leads · average hands

  bar  1  hh+k - hh - | hh+sn - hh - | hh+k - hh+k - | hh+sn - hh -
          R      R      R+L     R      R      R        R+L     R
  bar  2  hh+k - hh - | hh+sn - hh - | sn sn t1 t1 | t2 t2 ft ft
          R      R      R+L     R      R  L  R  L    R  L  R  L
  bar  3  sn t1 t2 ft | sn t1 t2 ft | sn sn t1 t2 | ft ft k ft
          R  R  R  L    R  R  R  L    R  L  R  R    R  L    L
  bar  4  crash+k - hh - | hh+sn - hh - | hh+k - hh+k - | hh+sn - hh -
          R         R      R+L     R      R      R        R+L     R

This sticking: 9.8 m of hand travel, 0 doubles, 0 crossovers, 0 beats on the weaker hand.
Fastest playable tempo: 230 bpm, re-sticking as needed; beyond that, nothing reaches bar 3 · 1.1 in time.
Plain alternating (R L R L): 15.35 m of travel, 6 crossovers, playable up to 197 bpm.
```

What this shows:
- **The groove:** it keeps the right hand on the hi-hat and the left on the backbeat.
- **The fill:** the run around the toms is stuck so the hands never cross.
- **The crash:** the left hand has just hit the floor tom, so it's free to swing to the crash.
- **Against alternating:** about a third less hand travel, and 33 bpm more headroom.

When a passage can't be played, Sticksmith says where:

```text
$ node bin/sticksmith.js examples/gospel-chops.txt --tempo 100
Sticksmith: Six-stroke fill with two floor toms
100 bpm · 16th-triplet-note grid · right hand leads · average hands

Two average hands can't play this at 100 bpm: nothing reaches bar 2 · 1.1 in time.
Fastest playable tempo: 94 bpm, re-sticking as needed; beyond that, nothing reaches bar 2 · 1.1 in time.
Plain alternating can't be played at 100 bpm (stuck at bar 2 · 1.1); playable up to 94 bpm.
```

The fill ends on the second floor tom, far right, and the next bar starts on the crash, far left. At 88 bpm (the file's own tempo), Sticksmith plays the fill as R R L R R L doubles.

## Writing a passage

```text
title: My fill
tempo: 112          # beats per minute, 20-400
grid: 16            # notes per 4/4 bar: 4, 8, 12, 16, 24 or 32
lead: right         # or left
drum ft2 1.05 second floor tom    # add or move a drum: name, position in metres (- is left)
foot cow cowbell pedal            # something played with a foot

bar: hh+k - hh - hh+sn - hh - sn sn t1 t1 t2 t2 ft ft
```

- **One token per grid slot:** `-` is a rest, and `a+b` means two things at once. A `|` between slots is ignored, so you can use it to mark beats.
- **The built-in kit:** `crash hh sn t1 t2 ft ride`, plus the feet `k` (kick) and `hf` (hi-hat foot). Feet are shown but not stuck.
- **Comments:** `#` starts a comment.
- **The chart:** under a two-drum note, `R+L` means the first hand-played drum gets the right hand and the second the left.

## Run and test

```bash
node bin/sticksmith.js examples/rock-fill.txt
node bin/sticksmith.js examples/gospel-chops.txt --player fast --tempo 110
node bin/sticksmith.js examples/rock-fill.txt --json     # everything as data

npm install        # only for the type check (TypeScript, pinned)
npm test           # node:test, no dependencies needed
npm run check      # strict type check of the JSDoc types
```

The tests cover:
- **Brute force:** the search is checked against every possible sticking (540 cases, including impossible ones).
- **Tempo:** playability gets harder as the tempo rises.
- **The usual stickings:** an ordinary groove gets the sticking drummers use.
- **Rolls:** a fast roll needs both hands, and a too-fast one is refused.
- **Crossovers:** a fill that alternating plays with crossed arms gets re-stuck.
- **Left-handed:** a mirrored kit with a left lead gives the mirrored answer.
- **Reach:** a hand can't jump across the kit in a 32nd.
- **The command line:** hostile and broken input.

## Security

Sticksmith reads one local text file and prints a report. No software is perfectly secure; this is how the risks are handled.

- **Bounded input:**
  - **File:** it must be a regular file (not a folder or device), at most 64 KB and valid UTF-8.
  - **Text:** at most 2,000 lines and 64 bars.
  - **Notes:** at most 1,024 hand notes, 16 drums, and 2 hands per note.
  - **Numbers:** every number has a range: tempo 20-400, positions ±2 m, fixed grid sizes.
- **No surprises in text:** control characters and invisible direction-changing characters are refused, so a title can't rewrite your terminal or disguise itself. Drum names are short lowercase identifiers.
- **Errors don't echo the file:** a long or odd token is never repeated back, and a test checks that a "password" in a bad file doesn't appear in the error.
- **Strict options:** they are checked against fixed lists, so `--player __proto__` and `--tempo "120; rm -rf /"` are refused.
- **Bounded search:** at most 60,000 states per note, and the tempo search is a binary search of at most ten runs. A maximum-size passage takes well under a second.
- **No risky code:** no `eval`, no shell and no network; the only file read is the one you name. There are no runtime dependencies. The type checker is a pinned development dependency, and `npm audit` is clean.

**Limits:**
- The hands model (speeds, costs) is a reasonable average, not a measurement of you.
- Real drummers use rebounds, Moeller strokes and body turns that it doesn't model.
- It suggests a sticking; your teacher and your hands get the last word.

## Files

| Path | What it is |
|---|---|
| `src/parse.js` | Reads and validates a passage and the kit |
| `src/stick.js` | The hands model, the search, replaying a sticking, the fastest-tempo search |
| `src/explain.js` | The chart, the practice notes and the comparison |
| `bin/sticksmith.js` | Command line: safe file reading and options |
| `tests/sticksmith.test.js` | Brute force, physics of hands, hostile input |
| `examples/` | A rock fill and a six-stroke fill |

More detail: [HOW-IT-WORKS.md](HOW-IT-WORKS.md).
