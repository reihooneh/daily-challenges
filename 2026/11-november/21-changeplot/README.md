# Changeplot

**Finds every costume change in a show, which ones are too quick to do alone, which can't be done at all, and the fewest dressers who can cover the rest.**

A costume plot says who wears what in each scene. What it doesn't say is how long each actor really
has between leaving the stage and coming back, or whether one dresser can be in the stage-left wing
helping the leading lady into her ballgown and in the stage-right wing 30 seconds later. Changeplot
works that out from the plot and the running order.

## Features

- **Every change, with its real window**: from the end of the actor's last scene to the start of
  their next, through the gaps and any scenes they sit out.
- **Quick changes** (under two minutes, or under 1.5 times what the change takes alone) get a
  dresser, which speeds them up; **impossible changes**, too short even with help, are flagged with
  how many seconds are missing and what would fix them (pre-set, underdress, a longer gap).
- **Underdressing**: a costume worn under another only needs the outer one taken off.
- **The fewest dressers**, with time to cross behind the set between wings, found by first fit and
  then proven by an exact search that tries one fewer (checked against brute force in the tests).

## Example

```
$ python3 -m changeplot examples/show.json --dressers 1
The Tin Lantern: 6 scenes, 4 actors, 12 costume changes

actor   from        to           off at  window  takes  spare  
Bao     uniform     oilskin        4:30    3:45   24 s   3:21  
Tomas   dock        apron          4:30    20 s   11 s    9 s  quick
Ines    apron       ballgown       8:00    3:35   1:30   2:05  quick
Mara    dock        oilskin        8:00    15 s   14 s    1 s  quick
Tomas   apron       tails          8:00    3:35   1:48   1:47  
Bao     oilskin     tails         10:05    1:30   1:05   25 s  quick
...
Ines    ballgown    oilskin       16:55    20 s   14 s    6 s  quick
Mara    ballgown    nightdress    16:55    20 s   30 s  -10 s  IMPOSSIBLE
Tomas   tails       uniform       16:55    3:40   1:12   2:28  
Mara    nightdress  dock          19:55    40 s   54 s  -14 s  IMPOSSIBLE

Quick changes need 2 dressers, and no fewer can cover them:
  Dresser 1: 4:30 Tomas SR, 8:00 Ines SL, 10:05 Mara SL, 16:55 Ines SL
  Dresser 2: 8:00 Mara SL, 10:05 Bao SR

With 1 dresser you're 1 short.
```

A show is JSON: scenes with lengths and the gap after each, costumes with how many minutes they take
to put on (and what they can be worn under), and each actor's wing and costume per scene (`-` for
offstage). See `examples/show.json`.

## Run and test

```sh
python3 -m changeplot examples/show.json [--dressers N]
python3 -m pytest
ruff check . && mypy changeplot && bandit -r changeplot
```

Python 3.11+, standard library only.

## Security

- The show file must be a regular file under 256 KB and is read with `json.loads` (no `eval` or
  pickle); deeply nested JSON is refused rather than crashing the parser.
- Every field is checked: names match a short allow-list pattern (so a name can't smuggle markup or
  terminal escapes into the report), times must look like `m:ss`, durations are bounded, and limits
  apply to scenes (120), actors (80) and costumes (300).
- The exact dresser search is bounded at 200,000 steps; if it runs out, the report says the count
  may not be the minimum instead of hanging.
- Known limits: change times are what you enter; real ones vary night to night, so leave margin.
