# Kerbtuck

**Will your car fit that kerbside gap? The smallest gap you can reverse into in one go, and the fewest shuffles for a tighter one.**

Language: TypeScript (strict, no runtime dependencies) · Field: driving / vehicle kinematics and motion planning · Day: 16 November 2026 (evening)

Every driver has stood looking at a gap and wondered. "Your car needs its length plus a metre" is the usual rule of thumb, but it ignores how tightly your car actually turns, and how long its front overhang is. Kerbtuck works it out from the numbers in any car's brochure:

- **The one-go gap:** the shortest gap the car can reverse into in a single smooth move, from a closed-form geometry formula that a simulation in the tests confirms.
- **A plan for this gap:** a motion planner searches every way of reversing and pulling forward on full lock or straight, and finds the one with the fewest gear changes. It writes the result out as goes ("reverse 5.7 m: 0.6 m straight, then 3.0 m on full right lock…"), replays it every 5 cm to prove nothing is touched, and draws it.
- **Compare cars:** see how six common cars fare in the same gap, which helps if you're choosing a car for a street with tight parking.

## Example

```text
$ kerbtuck --car golf --gap 5.4
Kerbtuck: Volkswagen Golf (4.28 m long) into a 5.40 m gap
It can reverse in in one go into a gap of 5.93 m or more (1.65 m more than its length).

It takes 3 goes (2 gear changes):
  Go 1, reverse 5.7 m: 0.6 m straight, then 3.0 m on full right lock, then 0.3 m straight, then 1.8 m on full left lock
  Go 2, forward 0.6 m: 0.6 m on full right lock
  Go 3, reverse 0.6 m: 0.6 m on full left lock

6.9 m of driving; checked every 5 cm for bumps: clear.

                                               . . . .
                                       . . . .
                                   . .
                                  .
                                .
                             ..
  ##########  @@@@@@@@@@@@@@@@@@@@@@@@@@@@@     ###########
  ##########  @@@@@@@@@@@@@@@@@@@@@@@@@@@@@     ###########
  ...
  =========================================================  kerb

$ kerbtuck --compare 5.6
  car                     length  one go needs   in this gap
  Fiat 500                 3.57 m       5.13 m   in one go
  Volkswagen Golf          4.28 m       5.93 m   3 goes (2 gear changes)
  Toyota Corolla hatch     4.38 m       5.90 m   3 goes (2 gear changes)
  Mazda CX-5               4.55 m       6.16 m   4 goes (3 gear changes)
  Tesla Model 3            4.69 m       6.37 m   doesn't fit
  Ford Ranger dual cab     5.37 m       7.06 m   doesn't fit
```

The Corolla is longer than the Golf but needs a slightly shorter one-go gap: its tighter turning circle more than makes up for it.

## Your own car

`examples/my-car.json` shows the format (all lengths in metres; the turning circle is the kerb-to-kerb diameter from the brochure):

```json
{ "name": "My Corolla", "length": 4.375, "width": 1.79, "wheelbase": 2.64, "frontOverhang": 0.93, "turningCircle": 10.4 }
```

```bash
kerbtuck --car-file examples/my-car.json --gap 6.2
```

Built-in cars: `fiat500`, `golf`, `corolla`, `cx5`, `model3`, `ranger` (approximate published figures).

## Build, run and test

```bash
npm ci
npm test                    # compiles, then 7 test groups
npm run lint                # tsc --noEmit (strict, no unchecked indexing)
npm start -- --car golf --gap 5.4
```

The tests include:
- arcs that close after a full circle;
- the outer front wheel tracing the published turning circle;
- the collision check on a rotated corner that a bounding box would get wrong;
- the one-go formula against simulating the car swinging out of the space, for every car (within 2 cm);
- plans in shrinking gaps, each needing as many or more goes, replayed every 5 cm and ending parked;
- no plan for a gap the car's own length;
- hostile car files;
- the command line refusing links, folders and bad numbers.

## Security

Kerbtuck reads at most one small local JSON file and prints text. No software is perfectly secure; this is how the risks are handled.

- **Only plain files:** links and folders are refused, and the file must be under 4 KB.
- **Strict JSON:**
  - one plain object with known keys only, so `__proto__` and anything unexpected are refused;
  - every measurement must be a finite number in a sensible range;
  - names are 1–40 plain characters;
  - the car's geometry must make sense (a rear overhang, a possible turning circle).
- **Safe car names:** a car named on the command line is matched with `hasOwnProperty`, so `--car __proto__` isn't a car.
- **No echo:** error messages never repeat the input.
- **Bounded work:** the planner stops after 400,000 search steps, within a fixed area around the gap. Gaps are limited to 2–15 m.
- **Dependencies:** none at runtime; TypeScript and Node's types are pinned for the build. `npm audit` is clean.

## Limits

- The car is a rectangle on a rear axle that can't slide sideways. Mirrors, tyre width and steering speed are ignored, and you're assumed to steer only while moving.
- The planner works on a 10 cm, 3° grid with 30 cm steps. A very skilled driver may squeeze into a slightly tighter gap than it finds.
- The track (distance between the wheels) is estimated from the body width.
- The parked cars are 4.5 × 1.8 m boxes, 15 cm from the kerb.

More detail: [HOW-IT-WORKS.md](HOW-IT-WORKS.md).
