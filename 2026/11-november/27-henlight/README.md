# Henlight

**A year of coop lighting on a plain plug-in timer: enough light for hens to keep laying through winter, with the fewest trips out to move the pins.**

Hens lay when the days are long: about 14 hours of light keeps them going. In a Sydney winter the
day shrinks below 10 hours, so many keepers add a lamp on a cheap mechanical timer. But sunrise and
sunset drift every day, and daylight saving moves them an hour overnight. A timer set in March is
wrong by May. Henlight works out when to move the pins and where to put them, so the light stays in
range all season with as few changes as possible.

## Features

- **Sunrise and sunset for any place** between 60° south and 60° north, using the NOAA solar
  calculator's formulas, on the local wall clock with Australian, EU or US daylight saving.
- **A gentle start.** Total light rises by at most a set amount a week (30 min by default) until it
  reaches the target, then stays between the target and a ceiling.
- **Morning light only.** The lamp comes on before dawn and goes off after sunrise, so there's no
  dark gap at dawn, and the evening ends at natural dusk when the hens go to roost.
- **The fewest timer changes**, provably: a greedy "furthest reach" plan, checked in the tests
  against dynamic programming over every split.
- **Energy and cost** of the lamp over the season, and a week-by-week chart of daylight and lamp
  light.

## Example

```
$ npm start -- examples/sydney.json
Henlight: Backyard in Sydney (-33.87, 151.21), 1 Mar to 30 Sep 2026
At least 14 h 00 m of light, at most 14 h 30 m, ramping up 30 min a week; timer pins every 15 min.
Daylight goes from 12 h 51 m to a low of 9 h 54 m.

Set the timer 9 times this season:
   1 Mar to 5 Mar   on 06:15, off 07:00      13 h 13 m to 13 h 18 m of light
   6 Mar to 11 Mar  on 05:45, off 07:00      13 h 36 m to 13 h 42 m of light
  12 Mar to 16 Mar  on 05:15, off 07:00      13 h 59 m to 14 h 04 m of light
  17 Mar to 4 Apr   on 04:45, off 07:15      14 h 03 m to 14 h 28 m of light
   5 Apr to 18 Apr  on 03:30, off 06:30      14 h 00 m to 14 h 17 m of light  (clocks changed)
  19 Apr to 19 May  on 03:00, off 06:45      14 h 00 m to 14 h 29 m of light
  20 May to 1 Aug   on 02:45, off 07:15      14 h 08 m to 14 h 30 m of light
   2 Aug to 14 Sep  on 03:15, off 07:00      14 h 01 m to 14 h 30 m of light
  15 Sep to 30 Sep  on 03:45, off 06:00      14 h 01 m to 14 h 11 m of light

The 9 W lamp runs 760 hours over the season: 6.8 kWh, about $2.26.

Light each week (█ daylight, ▒ lamp; one block is 30 min, from 8 h):
   1 Mar  ██████████▒            13 h 18 m
   8 Mar  █████████▒▒            13 h 40 m
  15 Mar  █████████▒▒▒           14 h 00 m
  22 Mar  ████████▒▒▒▒▒          14 h 21 m
  29 Mar  ████████▒▒▒▒           14 h 11 m
   5 Apr  ███████▒▒▒▒▒▒          14 h 17 m
  12 Apr  ███████▒▒▒▒▒           14 h 08 m
  19 Apr  ██████▒▒▒▒▒▒▒          14 h 29 m
  ...
```

Any setting can also be given as a flag, for example
`npm start -- --lat 51.5 --lon -0.13 --utcOffset 0 --dst eu --from 09-15 --to 12-31`.
Run `npm start -- --help` for the full list.

## Run and test

```sh
npm install        # TypeScript and Node types, pinned
npm test           # compiles, then runs the tests
npm start -- examples/sydney.json
```

The tests check:

- sunrise and sunset against published times for Sydney and London at both solstices;
- the 2026 daylight-saving dates for all three rules;
- the greedy plan against dynamic programming on 25 random seasons around the world;
- every planned day: inside its window, lit before dawn, pins on the timer's grid;
- hostile settings.

## Security

- **Settings files.** A settings file must be a regular file (not a link or folder) of at most
  16 KB, holding one JSON object. Unknown keys are refused, so a `"__proto__"` key is rejected
  rather than polluting anything, and keys are copied into an object with no prototype.
- **Checked values.** Every value is checked for type and range:
  - latitude 60° south to 60° north;
  - real calendar dates, in order;
  - timer steps of 5, 10, 15 or 30 minutes;
  - offsets in quarter hours;
  - finite numbers only (`NaN` and `1e999` are refused).
- **Plain-text names.** Names are limited to letters, digits and simple punctuation, so terminal
  escape codes can't reach the output.
- **Nothing runs.** No shell, no `eval`, no network. The work is bounded: at most one year of days,
  times the roughly 41,000 settings a 5-minute timer can hold.
- **Known limits.** The sun times are an approximation, good to a minute or two. Hens respond to
  light intensity as well as hours, and the model counts only hours. Lighting is a choice, not a
  must: a winter break from laying is natural and many keepers prefer it.
