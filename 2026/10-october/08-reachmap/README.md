# Reachmap 👍

**A linter for screen layouts: finds buttons that are too small, too close together or out of thumb reach, and estimates how long each task takes using Fitts's law.**

Designers usually find out that a button is awkward to reach after real people complain. Reachmap catches it earlier. Describe a screen as a list of rectangles plus the tasks people do on it, and it draws a map of where a one-handed thumb can comfortably reach, times every task with Fitts's law, and lists concrete problems with a fix for each.

## What makes it different

Fitts's law calculators take one distance and one width. Accessibility checkers test sizes and contrast. Reachmap joins them up around **tasks**:

- **It weighs problems by how often they happen.** A hard-to-reach button tapped 25 times a day is a problem; a settings link tapped once a month is not.
- **Direction-aware Fitts's law.** A wide, short button is easy to hit coming from the side and much harder coming from above. Reachmap measures the target's width along the actual path of the thumb.
- **Left and right hands.** `--hand left` mirrors the thumb, because roughly one in ten people hold their phone in the other hand.
- **A pass/fail exit code,** so a layout can be checked automatically every time it changes.

## Example

A chat screen with a few classic mistakes (`examples/chat-app.json`):

```text
$ reachmap examples/chat-app.json
+--------------------------+
|::::::::::::::::::::::::::|
|AAAA:::::::::::::::BBBCCCC|
|AAAA:::::::::::::::BBBCCCC|
|ADDDDDDDDDDDDDDDDDDDDDDDDC|
|:DDDDDDDDDDDDDDDDDDDDDDDD:|
|::::::::::::::::::::::::::|
|::::::::::::::::::::::::::|
|:::::::::::::::::.........|
|::::::::::................|
|::::::....................|
|:::.......................|
|..........................|
|..........................|
|................          |
|...........               |
|........                  |
|.....                     |
|...                       |
|..                        |
|                          |
|                          |
|                          |
|                          |
|                          |
|                          |
|EEEEFFFFFFFFFFFFFFFFFFGGGG|
|EEEEFFFFFFFFFFFFFFFFHHGGGG|
|EEEEFFFFFFFFFFFFFFFFHHGGGG|
+--------------------------+
  blank = easy reach   . = stretch   : = hard  (right thumb)

  A  Back  (hard)
  B  Call  (hard)
  C  Chat info  (hard)
  D  Search chat  (hard)
  E  Attach  (easy)
  F  Message box  (easy)
  G  Send  (easy)
  H  Emoji  (easy)

Tasks, busiest first (Fitts's law estimate; compare them with each other, not with a stopwatch):
  Send a reply            0.77 s  x 60/day    slowest step: 'Send' (2.2 bits)
  Go back to chats        0.71 s  x 25/day    slowest step: 'Back' (4.1 bits)
  Send a photo            1.08 s  x 4/day     slowest step: 'Send' (3.1 bits)
  Find a message          1.42 s  x 1/day     slowest step: 'Search chat' (4.1 bits)
  Start a call            0.69 s  x 2/day     slowest step: 'Call' (4.0 bits)

8 problems:
  - 'Back' is 40 x 40, smaller than the 44 x 44 minimum for a touch target.
  - 'Search chat' is 358 x 36, smaller than the 44 x 44 minimum for a touch target.
  - 'Emoji' is 26 x 26, smaller than the 44 x 44 minimum for a touch target.
  - 'Call' and 'Chat info' are only 4 apart; leave at least 8 so a thumb doesn't hit the wrong one.
  - 'Attach' and 'Message box' are only 4 apart; leave at least 8 so a thumb doesn't hit the wrong one.
  - 'Message box' and 'Send' are only 4 apart; leave at least 8 so a thumb doesn't hit the wrong one.
  - 'Message box' and 'Emoji' overlap: a tap there is ambiguous.
  - 'Back' is tapped about 25 times a day but sits in the hard-to-reach zone. Move it lower, towards the thumb.
```

## Describing a layout

```json
{
  "screen": { "width": 390, "height": 844, "device": "phone" },
  "elements": [
    { "id": "send", "label": "Send", "x": 334, "y": 780, "w": 44, "h": 44 }
  ],
  "tasks": [
    { "name": "Send a reply", "steps": ["message", "send"], "per_day": 60 }
  ]
}
```

- Coordinates are in points (or CSS pixels), measured from the top-left corner.
- `device` is `phone` (thumb, 44-point minimum, reach zones) or `desktop` (mouse, 24-pixel minimum, no reach zones).
- A task is the sequence of elements tapped, in order, and roughly how many times a day it happens.

## Usage

```bash
reachmap layout.json                # right thumb
reachmap --hand left layout.json
cat layout.json | reachmap -        # read from standard input
```

Exit codes: `0` no problems, `1` problems found, `2` the layout could not be read.

## Tech

Python 3.10+, standard library only. Checked with ruff (including the security rules), bandit and `mypy --strict`.

## Run it

```bash
cd 2026/10-october/08-reachmap
PYTHONPATH=src python3 -m reachmap examples/chat-app.json
```

## Tests

```bash
PYTHONPATH=src python3 -m unittest discover -s tests
```

27 tests:

- **Fitts's law:** exact values of the formula, bigger and closer is easier, the approach direction changes the effective width (including the diagonal case), and movement time uses the device's constants.
- **Reach:** the corner under the thumb is easy, the far top corner is hard, left and right hands mirror each other exactly, desktops have no reach zones.
- **Geometry:** gaps sideways, vertically and diagonally; touching and overlapping rectangles.
- **Analysis:** the example finds exactly the expected problems, a good layout finds none, task times add up and daily tap counts are right.
- **Hostile input:** broken JSON, 50,000 levels of nesting, NaN and Infinity, duplicate keys, booleans and strings pretending to be numbers, `1e308`, negative sizes, elements off the screen, unknown fields, markup, escape codes and right-to-left override characters in ids and labels, tasks pointing at missing elements, oversized files and too many elements. The largest allowed layout is analysed in well under 5 seconds.
- **Command line:** exit codes, the installed `reachmap` command, and every error is one clean line that never repeats the input.

## Security

- **Strict, bounded parsing.** At most 100 KB is read (the CLI stops reading after that, so a huge file or endless stream can't fill memory). Duplicate keys, `NaN` and `Infinity` are refused instead of silently accepted, and so are unknown fields, so a typo can't quietly disable a check.
- **Every value is type- and range-checked.** `true` is not a number, sizes must be positive, and elements must sit inside the screen. Limits of 200 elements, 50 tasks and 30 steps per task keep the work small.
- **Allow-listed text.** Ids must match `[a-z][a-z0-9_-]{0,31}` and labels may only use letters, digits, spaces and a little punctuation. That keeps terminal escape codes, markup and invisible direction-changing characters out of the report.
- **Errors never repeat the input.** They say what was wrong and where (for example "element 3.w"), not the offending text.
- **Nothing dangerous in reach.** The tool only reads the one file you name. No network, no shell, no `eval`, no `pickle`, no dependencies.

**Known limits, stated honestly:**

- **Fitts's law is a model, not a measurement.** The constants are typical values from published studies. Use the times to compare layouts and tasks with each other, and confirm important decisions by watching real people.
- **The reach zones are a simple geometric model** of one-handed use with the phone held near the bottom. Hands, phone sizes and grips vary, and many people switch to two hands.
- It doesn't check contrast, labels for screen readers or anything else outside geometry. Use an accessibility checker for those.
- No software can promise it is 100% secure; these are the protections in place.
