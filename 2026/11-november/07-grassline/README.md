# Grassline

**How much grass to take: where to aim a biased lawn bowl so it draws to the jack, at any length, on any green, with your own bowls.**

Language: PHP 8.3 (no dependencies) · Field: lawn bowls / physics of rolling bodies · Day: 7 November 2026

A lawn bowl is shaped so that it leans as it rolls, and like a gyroscope it slowly turns, curving more and more as it slows. To draw to the jack you aim wide ("take grass") and let it curve in. How wide depends on the bowls, the length of the jack and the speed of the green, and bowlers learn it by feel, one green at a time. Club coaching notes describe manual ways to find the aiming line. Grassline computes it:

- **The physics, in closed form:**
  - the bowl slows at a constant rate (rolling resistance), and its bias turns it at a rate proportional to 1/speed (gyroscopic precession);
  - integrating gives its whole path as a formula, checked in the tests against brute-force Runge–Kutta integration to within 5 mm.
- **The aim:**
  - the angle off the centre line, how far that is to the side at the jack, and where a stare spot 2 m along your line sits;
  - how fast to bowl, how long it takes, and where the bowl is widest (its "shoulder");
  - whether the bowl stays inside the rink.
- **Two facts bowlers know, falling out of the maths:**
  - **the angle of aim is the same at every length** (only the width grows);
  - **a bowl with the right line but the wrong weight still finishes on the line**, just long or short. So line errors and weight errors are separate, and Grassline shows both.
- **Your own bowls:** log a few draws you actually played (jack length and how wide you aimed) and a timed bowl or two. Grassline fits your bowls by least squares and predicts every other length and green speed.
- **The bigger picture:** a table for jacks from 23 to 35 m, the same jack on greens from 10 to 18 seconds, and a picture of the rink with the aiming line and the bowl's path.

## Quick start

```bash
./bin/grassline --jack 27 --green 15                 # medium bias, right-handed forehand
./bin/grassline --hand backhand --bias wide
./bin/grassline --log examples/club-green.txt --jack 29
./bin/grassline --svg > shot.svg                     # a drawing
php tests/run.php                                    # 67 checks
```

```
GRASSLINE  forehand, medium bias, 15.0-second green, jack at 27.0 m

Aim 5.25° right of the centre line:
  2.48 m right of the jack, measured across at the jack
  a stare spot 2.0 m along your line is 18 cm right of the centre line
The bowl leaves the hand at 3.64 m/s, travels 27.11 m in 14.9 s, and is widest (its shoulder) 0.91 m right of centre at 17.08 m up the rink, then curves left onto the jack.

If it goes wrong:
  5% too heavy on the right line: finishes 2.77 m past the jack, still on the centre line
  1° too wide   with the right weight: finishes 0.47 m right of the jack

The same jack on other greens (faster greens, more seconds, need more grass):
  12.0-second green: aim 3.38°, 1.59 m wide at the jack
  16.0-second green: aim 5.97°, 2.82 m wide at the jack
  ...
 25 m |           : oo     .  |
      |           :  o    ..  |
 20 m |           :  oo  ..   |
 ...
```

The rink picture is drawn from above, with the far end at the top. `o` is the bowl, `.` the aiming line, `:` the centre line, `J` the jack and `M` the mat.

Exit code: 0 for a plan, 2 for bad input.

## Calibrating your bowls

```
# examples/club-green.txt
draw 25.0 2.05        # a jack at 25 m needed the aim 2.05 m wide of it
draw 30.0 2.45
timed 27.4 14.6       # a bowl that stopped at 27.4 m took 14.6 s, delivery to rest
green 14.5            # or give the green's speed in seconds instead of timed bowls
```

Green speed is the number of seconds a bowl takes from delivery to rest 30 yards (27.4 m) up the green. In bowls, more seconds means a *faster* (slicker) green.

## Security

Command-line options and the log file are the only input, and both are treated as untrusted:

- **Options:** every number must match a plain decimal pattern (no `1e3`, no negatives), within a range. Names come from fixed lists, and repeated options are refused.
- **The log:**
  - files are limited to 64 KB and read with a bounded `stream_get_contents`;
  - lines are limited to 200 characters, and there are at most 200 shots;
  - each line must be one of three fixed forms, with every number in range;
  - a width impossibly large for its length is refused;
  - invalid UTF-8, control characters and invisible formatting characters (bidirectional overrides, zero-width) are refused.
- **Safe reading:** links and folders are refused, the path is never echoed, and error messages give a line number, not the line.
- **No risky code:** there is no `eval`, no shell and no writing.
- **Safe drawing:** the SVG's title is escaped with `htmlspecialchars`, and everything else in it is computed numbers.
- **Known limits:**
  - the model is an idealised bowl on a flat, uniform green: no wind, no slopes, no "fast hand" or "slow hand" across the rink;
  - real bowls also wobble and fall over at the very end;
  - treat the numbers as a starting line to adjust from, and calibrate with your own shots.

## Files

| File | What it does |
|---|---|
| `src/Physics.php` | The closed-form path, delivery speed, timing, and a Runge–Kutta check |
| `src/Shot.php` | Bowls (presets or fitted) and a draw shot: aim, stare spot, shoulder, errors |
| `src/Log.php` | Reading a log of real shots, and the least-squares fit |
| `src/Report.php` | The plan, the rink picture and the SVG |
| `src/Cli.php` | Options and safe file reading |
| `tests/run.php` | Physics against integration and known results, fitting, hostile logs, the command line |

See [HOW-IT-WORKS.md](HOW-IT-WORKS.md) for the derivation and interview questions.
