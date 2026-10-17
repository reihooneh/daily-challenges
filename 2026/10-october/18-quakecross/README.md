# Quakecross

**Locates an earthquake from the times its P and S waves reached three or more seismometers, says how sure it is, and names the station reading that doesn't fit.**

Language: Rust (standard library only) · Field: seismology / numerical optimisation · Day: 18 October 2026

When an earthquake happens, the fast P wave and the slower S wave spread out and reach each seismometer at different times. Working backwards from those arrival times gives where and when the quake happened. Classroom tools do this with "S minus P" circles drawn on a map. Real networks solve it properly, by least squares.

Quakecross does the proper version in one small program. It also does something the circles can't: when one reading is wrong (an S wave picked on noise, a P and S mixed up, a station's clock off by two seconds), it **finds that reading**, leaves it out, and shows how much it had moved the answer.

## Quick start

```bash
cargo run --release -- examples/hunter.txt
cargo test                # 14 test groups
```

```
QUAKECROSS  hunter.txt  (Hunter practice quake: 7 stations, 13 picks; P 6 km/s, S 3.5 km/s)

  Epicentre     32.949°S 151.610°E   (15.7 km W of NEW1)
  Depth         11.9 km (90%: ±1.2 km)
  Origin time   03:14:03.15
  90% error     within 0.6 km along E and 0.4 km across
  Fit           RMS 0.03 s over 12 picks; largest gap between stations 124° (the stations surround it)

PICKS THAT DON'T FIT (left out of the location above)
  line 8   CESS S: arrived 2.36 s later than the other picks predict.
  Likely a P/S mix-up, a pick on noise, or a station clock error. With them included the
  fit was RMS 0.51 s and the epicentre 2.8 km away, at 32.952°S 151.640°E.

PICKS
  Station   Phase  Distance   Arrived       Off by
  NEW1      P        15.7 km  03:14:06.42   -0.01 s
  ...
  CESS      S        26.9 km  03:14:13.92   +2.36 s  << doesn't fit
```

The example is a made-up quake near Newcastle, NSW, at 32.95°S 151.61°E and 11 km deep, with small timing errors and one S pick 2.4 s late. Quakecross recovers the location to within about 0.1 km and finds the bad pick.

## The pick file

```
event Hunter practice quake
velocity p 6.0 s 3.5        # km/s
depth free                  # or a fixed depth in km, e.g. "depth 10"
station NEW1 -32.927 151.776 p 03:14:06.42 s 03:14:08.77
station TARE -31.9 152.46 p 03:14:26.70          # an S time is optional
```

Exit codes: `0` located, `1` located but some picks don't fit, `2` bad input.

## What you get

- **Where and when:** epicentre, depth (fixed or solved for) and origin time.
- **How sure:** a 90% error ellipse (how far and in which direction the epicentre could be off), and the depth uncertainty.
- **Is the network good enough:** the azimuthal gap. Over 180° the quake is outside the stations and the location is much weaker.
- **Bad picks:** up to three readings that don't fit, each with how far off it is, and where the quake would have been placed with them in.

## Security

- **Bounded input:** at most 64 KB, 200 characters a line and 200 stations, read with a hard limit. Only regular files are opened, so `/dev/zero` and directories are refused. The file must be valid UTF-8.
- **Strict parsing:** station names are 1-8 capitals or digits, every number is range-checked (no `NaN`, no `1e308`), and times must be exactly `HH:MM:SS.ss`. Control characters and hidden direction characters are refused, and errors never repeat the input.
- **Bounded work:** a fixed-size grid search and at most 200 refining steps per solve, so no input can make it run for long.
- **Memory-safe by construction:** `unsafe` is forbidden in the crate, there are no dependencies, `cargo clippy -D warnings` is clean, and release builds keep overflow checks on.

**Known limits:** the Earth model is uniform (one P speed and one S speed), and the map is flat, so it suits local and regional quakes (stations within about 1,000 km). Real agencies use layered models. Error estimates assume the model is right and pick errors are about 0.1 s or more.

See [HOW-IT-WORKS.md](HOW-IT-WORKS.md) for the walkthrough.
