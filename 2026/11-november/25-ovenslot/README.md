# Ovenslot

**One oven, six dishes, dinner at 18:30: what temperature, what goes in when, and when to turn the dial.**

A roast at 180, potatoes at 220, a pavlova at 120 and Yorkshire puddings that must come out the
moment people sit down. Recipes give each dish its own temperature as if it had the oven to itself.
Ovenslot takes how far each dish can stretch (the lamb is fine anywhere from 160 to 190), how much
shelf it takes, how long it must rest and how long it can wait, and works backwards from serving
time to the fewest temperature changes that get everything to the table on time.

## Features

- Cooking time rescaled for a different temperature (time ∝ 1/(T − 100 °C), a roasting rule of
  thumb), so a dish can share a hotter or cooler oven.
- Phases planned backwards from serving: each dish comes out inside its rest window, the oven
  needs time to heat (10 °C/min) or cool with the door ajar (4 °C/min) between phases, and shelves
  never overfill.
- Searches every grouping of the dishes into 1 to 4 temperatures and every order of those phases;
  keeps the plan with the fewest dial changes, then the least time with the oven on, then the
  freshest food.
- A minute-by-minute timetable, including when to preheat.

## Example

```
$ go run ./cmd/ovenslot examples/christmas.json
6 dishes, 2 shelves, served at 18:30: 3 temperatures, oven on for 209 min.

  15:01  Turn the oven on to 130 °C
  15:12  Pavlova in (at 130 °C instead of 120: 50 min)
  16:02  Pavlova out (148 min before serving)
  16:02  Turn the oven up to 190 °C
  16:08  Roast lamb in (at 190 °C instead of 180: 89 min)
  17:37  Roast lamb out (53 min before serving)
  17:37  Turn the oven up to 220 °C
  17:40  Crispy potatoes in
  17:47  Stuffing in (at 220 °C instead of 180: 23 min)
  17:57  Pumpkin in (at 220 °C instead of 200: 33 min)
  18:10  Stuffing out (20 min before serving)
  18:10  Yorkshire puddings in
  18:30  Yorkshire puddings out, straight to the table
  18:30  Crispy potatoes out, straight to the table
  18:30  Pumpkin out, straight to the table
  18:30  Oven off
  18:30  Serve
```

A meal file is JSON: `serve` ("18:30"), `shelves` (1 to 4) and up to 10 `dishes`, each with
`name`, `temp`, `minutes`, optional `low` and `high` (the range it tolerates), `space` (share of a
shelf), `restMin` and `restMax` (minutes between leaving the oven and serving).

## Build and test

```sh
go run ./cmd/ovenslot examples/christmas.json
go test ./...      # plan checks, a full search over random meals, hostile files
go vet ./...
```

Go 1.22, standard library only.

## Security

- The meal must be a regular file (not a symlink) under 32 KB, and a single JSON value; unknown
  fields are refused rather than ignored, so a typo like `"tmep"` is an error, not a silent default.
- Every number has a range (temperatures 110 to 260 °C, 1 to 600 minutes, at most 10 dishes and 4
  shelves), and JSON can't carry NaN or infinity, so nothing odd reaches the arithmetic.
- Dish names are letters, digits and simple punctuation only, which keeps terminal escape codes
  out of the printed timetable.
- The search is capped at 4 million schedules, so the largest allowed meal can't hang it; if the
  cap is hit, the plan is still valid and the output says a better one may exist.
- Known limits: each dish cooks at a single temperature (it can't start at 180 and finish at 220),
  and the time-and-temperature rule is a guide. Check meat with a thermometer.
