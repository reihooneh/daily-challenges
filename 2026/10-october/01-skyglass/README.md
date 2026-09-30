# Skyglass 🌗

**The sky over any place on Earth, in your terminal.**

Skyglass works out sunrise, sunset, twilight, day length and the Moon's phase for any location and date, and draws the Moon as it looks tonight. It runs fully offline: everything is calculated from astronomy formulas, with no internet or data files.

## Features

- **Sun:** first light (civil dawn), sunrise, solar noon, sunset, last light and day length
- **Polar days handled:** tells you when there's midnight sun or polar night instead of printing nonsense times
- **Moon:** phase name, percentage lit, age in days, and the dates of the next full and new moon
- **ASCII Moon drawing,** mirrored automatically for the southern hemisphere, where the Moon really does look flipped
- **Correct local time,** including daylight-saving changes, using real time zones
- **Built-in cities** (Sydney, Melbourne, Tehran, London, New York, Tokyo, Reykjavik, Tromsø, Singapore) or any `--lat`/`--lon`
- **Accurate:** matches a published almanac for Sydney to within 2 minutes

## Example

```text
$ skyglass --date 2026-10-01
Skyglass · Sydney · Thu 1 Oct 2026 (UTC+10)

  Sun
  First light   05:07
  Sunrise       05:32
  Solar noon    11:44
  Sunset        17:56
  Last light    18:21
  Day length    12h 23m

  Moon
          ..#######
        ...##########
      ....#############
     ....###############
     ....###############
    .....################
     ....###############
     ....###############
      ....#############
        ...##########
          ..#######
  Waning Gibbous · 79% lit · 19.2 days old
  Next full moon  Mon 26 Oct
  Next new moon   Sun 11 Oct
```

```text
$ skyglass --city tromso --date 2026-12-21 --no-art
Skyglass · Tromsø · Mon 21 Dec 2026 (UTC+1)

  Sun
  The Sun doesn't rise today (polar night).
```

## Tech

Go 1.24, standard library only. Tests use Go's built-in `testing` package.

## Install and run

```bash
cd 2026/10-october/01-skyglass
go run .                                    # Sydney, today
go run . --city london --date 2026-06-21    # any built-in city and date
go run . --lat 48.8566 --lon 2.3522 --tz Europe/Paris
go build -o skyglass .                      # or build a binary
```

| Flag | What it does |
|---|---|
| `--city` | Built-in city (default `sydney`) |
| `--lat`, `--lon` | Any location in degrees (south and west are negative) |
| `--tz` | Time zone for `--lat`/`--lon`, e.g. `Asia/Tehran` (default UTC) |
| `--date` | `YYYY-MM-DD` (default today) |
| `--no-art` | Hide the Moon drawing |

## Tests

```bash
go test ./...
```

13 tests check sunrise and sunset against a published almanac (including across a daylight-saving change), day length at the equator on the equinox, polar night and midnight sun in both hemispheres, Moon phases against the real 2026 eclipses, the phase names, the Moon drawing, and the CLI's error messages. Coverage is about 95%.

## Accuracy

Sun times are within about 2 minutes outside the polar regions. The Moon phase uses the average length of a lunar month, so phase times can be off by up to about half a day, which is fine for a phase name and a drawing.
