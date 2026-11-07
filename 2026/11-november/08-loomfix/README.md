# Loomfix

**Tells you which lighthouse or buoy you're looking at from stopwatch timings of its flashes, says how sure it is, and finds the lights on a chart that a watcher could easily mix up.**

Language: Rust (no dependencies) · Field: marine navigation / statistical pattern matching · Day: 8 November 2026

At night a coast is a scatter of lights, and each one has a rhythm printed on the chart: `Fl(2) W 10s` means two white flashes every 10 seconds. A navigator identifies a light by timing it, usually by tapping a phone stopwatch or counting "one thousand and one...". Timings are rough, though, and the chart gives only the rhythm and period, not how long each flash lasts. So two lights can look the same on a bouncing deck.

Learning aids explain the abbreviations, and light-list apps let you filter by flash count and period you've already worked out. Loomfix starts from the raw taps instead:

- **Identify:** fits your times to every light in the list. For each light it finds the best line-up (when your stopwatch started within the light's period, and how fast your counting ran) and scores it as a likelihood. Your reaction time, the model's uncertainty about flash lengths, stray taps and missed flashes all count. The result is a ranked list with a chance for each light, and a warning when nothing fits well.
- **Audit a chart:** simulates hundreds of watchers timing each light in a list and identifies every simulated watch against the whole list. Each simulated watcher has their own reaction time, a stopwatch or counted seconds, and the odd missed flash, and each simulated light has its own flash lengths. The audit reports which lights get mistaken for which, how often, and whether watching the flash length would tell them apart.
- **Show a rhythm:** draws one period of any character as text.
- **Understands chart abbreviations:** `Fl`, `Fl(2)`, `Fl(2+1)`, `LFl`, `Q`, `Q(3)`, `Q(6)+LFl`, `VQ`, `Oc(2)`, `Iso`, `Mo(A)` and `F`, with colours `W R G Y`. Chart spellings like `Fl(3)R.15s` work too.

## Quick start

```bash
cargo build --release
./target/release/loomfix id examples/kestrel-bay.txt examples/night-watch.txt
./target/release/loomfix audit examples/kestrel-bay.txt --counted
./target/release/loomfix show "Q(6)+LFl 15s"
cargo test                     # 28 tests
cargo clippy --all-targets -- -D warnings
```

The example lights are **invented**, not real navigation data. Always use your official chart and list of lights.

```
$ loomfix id examples/kestrel-bay.txt examples/night-watch.txt
LOOMFIX  7 times over 30 s (stopwatch), colour W

  Most likely: Gannet Rock  Fl(2) W 10s  (100%)
  7 of 7 times paired with its rhythm, 0 flashes missed, typical error 0.06 s

  #   Light                  Character        Chance  Paired  Missed  Stray
  1   Gannet Rock            Fl(2) W 10s        100%     7/7       0      0
  2   East Spit              Q(3) W 10s           0%     7/7       3      0
  3   Black Ledge            Fl(2) W 9s           0%     7/7       1      0
  ...

  One period of Gannet Rock, 0.25 s a column (# on, . off; ^ your 'on' times, v your 'off' times):
    light  ##....##................................
    you    ^     ^
```

```
$ loomfix audit examples/kestrel-bay.txt --counted
  Light                  Character        Named right   Most often taken for
  Gannet Rock            Fl(2) W 10s              71%   Black Ledge (20%)
  Black Ledge            Fl(2) W 9s               42%   Gannet Rock (28%)
  Old Pier               Mo(A) W 8s               86%   Black Ledge (11%)
  South Shoal            Q(6)+LFl W 15s          100%
  ...
Easy to mix up (more than 5% of watches):
  - Black Ledge (Fl(2) W 9s) was taken for Old Pier (Mo(A) W 8s) in 28%
      Tell them apart by flash length: Old Pier stays on for about 1.5 s, Black Ledge for 0.5 s.
  A stopwatch helps tell apart lights whose periods differ by a few percent.
```

With a stopwatch instead of counting, Gannet Rock is named right in 95% of watches and Black Ledge in 89%.

## The files

A list of lights, one per line:

```
Gannet Rock   | Fl(2) W 10s
South Shoal   | Q(6)+LFl W 15s     # comments are fine
```

A watch: a time in seconds per line, each optionally followed by `on` (the default) or `off`. Time the flashes of most lights, and the eclipses (`off`) of occulting ones.

```
timing stopwatch          # or: counted
colour W                  # optional: rules out lights of other colours
watched 0 to 33           # optional: when you started and stopped looking
2.4
3.9
12.5 on
```

Noting `watched` matters. Without it, Loomfix can't tell a flash you missed from one that happened before you started looking.

Exit codes: 0 for a report, 2 for bad input.

## Security

All input is untrusted text:

- **Bounded:** each file is read up to 64 KB and stops there (`Read::take`). Limits are 200 characters a line, 300 lights, 400 times, times from 0 to 3600 s, periods from 0.5 to 120 s, groups from 1 to 9, and simulations from 1 to 5000. That keeps the work for an audit bounded.
- **Strict grammar:**
  - a light's character uses only letters, digits, `( ) + .` and spaces, and must parse completely;
  - times are plain decimal numbers (no `NaN`, `inf` or `1e9`) and must increase;
  - names use a small character set;
  - invalid UTF-8, control characters (such as terminal escapes) and invisible formatting characters are refused.
- **Safe files:**
  - only regular files are opened, not links, folders or devices;
  - error messages give a line number, never the line or the path, so a crafted file can't print itself to your terminal.
- **Memory-safe Rust:** `unsafe_code = "forbid"`, no dependencies, overflow checks on in release builds, and clippy with `-D warnings`.
- **Repeatable:** simulations use a seeded generator, so an audit gives the same report every time.
- **Known limits:**
  - flash lengths are modelled from typical values, so a light whose real flashes are unusually long or short fits less well;
  - sector lights and alternating colours (`Al.WR`) are treated as "any of these colours";
  - the chances assume the light is in your list;
  - this is a learning tool, **not** a navigation aid.

## Files

| File | What it does |
|---|---|
| `src/pattern.rs` | Parses characters; builds each period's on/off edges with their uncertainty |
| `src/fit.rs` | Lines your times up with a light and scores the fit; ranks the lights |
| `src/audit.rs` | Simulated watchers, and which lights get mixed up |
| `src/input.rs` | Strict readers for light lists and watches |
| `src/render.rs` | The text strip of one period, with your times folded onto it |
| `src/rng.rs` | A small seeded random number generator |
| `src/main.rs` | The command line and safe file reading |
| `tests/cli.rs` | The command as a user runs it, including hostile input |

See [HOW-IT-WORKS.md](HOW-IT-WORKS.md) for the model, the fitting and interview questions.
