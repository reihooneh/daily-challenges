# Trailshunt

**Gets a walking group and its cars to the right ends of a one-way hike, with the least driving.**

A one-way walk ends a long way by road from where it starts. The usual fix is a car shuttle: drive
some cars to the finish, come back crammed into one, start the walk an hour and a half late, and
drive back to the start at the end. The cleverer fix is a key swap: split the group, have half drive
to the finish and walk it backwards, and swap car keys when you meet in the middle. Whether either
works depends on seats, who holds a licence, and which cars go where. Trailshunt works out the best of
each, with step-by-step instructions.

## Features

- **Shuttle**: the fewest cars to park at the finish (they must seat everyone afterwards), a ferry car
  big enough for their drivers, and enough licensed drivers.
- **Key swap**: the fewest cars to take to the finish, and a team split where both teams can drive
  and fit those cars, each team walking as at least a pair, as even as possible, with car owners
  driving their own cars.
- Both checked against brute force over every set of cars and every team split.
- Drives, kilometres and how late the walk starts, for each.

## Example

```
$ ruby bin/trailshunt examples/ridge.json
9 walkers, 4 cars: Bluff Track carpark to Ridge Road gate (38 km, 45 min apart by road).

Shuttle: 6 drives (228 km), and the walk starts 90 min late.
  1. Everyone meets at Bluff Track carpark.
  2. Drive Dev's Outlander, Hiro's van to Ridge Road gate, with Amira's Corolla following.
  3. Leave them there; all 3 drivers come back in Amira's Corolla.
  4. Walk. At Ridge Road gate, Dev's Outlander, Hiro's van (15 seats) drive everyone back to Bluff Track carpark.

Key swap: 2 drives (76 km), and nobody waits.
  1. Hiro, Elif, Finn, Isla drive Hiro's van to Ridge Road gate and walk back towards Bluff Track carpark.
  2. Amira, Ben, Chloe, Dev, Grace start walking from Bluff Track carpark and carry the keys to the cars left there.
  3. Swap keys when you meet.
  4. Amira, Ben, Chloe, Dev, Grace drive Hiro's van back to Bluff Track carpark, where Hiro, Elif, Finn, Isla have finished and every car now is.

Least driving: the key swap.
```

A group is JSON: the trail (start, finish, and the distance and time between them by road), the
walkers (with `"licence": false` for anyone who can't drive) and the cars (seats including the
driver, and optionally the owner). Everyone is assumed to start and end at the start.

## Run and test

```sh
ruby bin/trailshunt examples/ridge.json
ruby -w test/test_trailshunt.rb
```

Ruby 3.1 or later; no gems (minitest and json come with Ruby).

## Security

- The group must be a regular file (not a symlink) under 64 KB of UTF-8, parsed with
  `JSON.parse(create_additions: false, max_nesting: 10)`, so JSON can't create Ruby objects or nest
  deeply.
- Names match a short allow-list pattern, so a name can't carry markup or terminal escapes into the
  printout; numbers must be finite and in range; at most 40 walkers and 14 cars bound the searches.
- No `eval`, shell, network or file writes. Clean under `ruby -w`.
- Known limits: it plans the cars, not the walk; check the trail is passable both ways.
