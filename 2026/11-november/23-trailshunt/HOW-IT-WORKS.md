# How Trailshunt works

## Architecture

```
lib/trailshunt.rb   reading and checking a group, the best shuttle, the best key swap
bin/trailshunt      the command line report
test/               the example, brute-force checks, owners, impossible groups, hostile files
examples/           nine walkers and four cars
```

## Key concepts

**Shuttle.** Choose a ferry car and a set of cars to park at the finish. The parked cars must seat
the whole group after the walk; the ferry must seat the parked cars' drivers plus its own on the way
back; and there must be a licensed driver for every car that moves. Drives: each parked car twice
(there and back at the end), plus the ferry there and back. Fewer parked cars is always fewer drives,
so Trailshunt tries the smallest sets first and stops at the first that works.

**Key swap.** Choose cars to take to the finish. The team that drives them there must fit in them and
have a driver for each; so must the team that drives them back at the end. Each team walks as a pair
or more. The cars are the only thing that costs driving (two drives each), so again fewer is better.

**Counting instead of enumerating.** For a key swap, the only things that matter about a team split
are how big the outgoing team is and how many of it can drive. Trying every subset of 40 people is
impossible, but trying every (size, drivers) pair is a few hundred checks. The test confirms it
finds the same answer as trying every split on small groups.

## Language features worth noticing

- `Struct` with `keyword_init` and endless methods (`def legs = ...`) keep the plan types short.
- `combination(k)` from `Array` does the subset search; `filter_map` and `count(&:licence)` read well.
- `JSON.parse(create_additions: false)` turns off the feature that lets JSON name Ruby classes.

## Interview questions

**Why is a key swap so much less driving?** A shuttle moves cars to the finish before the walk and
brings everyone back after, plus a ferry trip. A key swap only moves the cars one team needs, and no
one waits for a car to come back. For nine people it's 2 drives instead of 6.

**When does a key swap fail?** With fewer than four walkers, or when one side can't drive or fit the
cars: two licensed drivers in a group of nine can't split into two teams that each have a driver for
a seven-seater and a hatchback.

**How do you test the "fewest" claims?** Brute force on random small groups: every set of cars and,
for the swap, every split of the people. Both answers must match exactly, including "impossible".

## Extensions

1. Homes in different places: let drivers go home straight from the finish.
2. Public transport: a bus back to the start as a zero-car option.
3. Walking speeds, so the swap point is where the teams really meet.
