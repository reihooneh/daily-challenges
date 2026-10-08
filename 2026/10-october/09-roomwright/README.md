# Roomwright 🗝️

**Checks an escape room design before anyone builds it. It finds the moves that can trap a team for good, puzzles nobody can ever solve, and how long the room really takes for a team of each size.**

Escape room designers sketch their puzzles as a chain of locks and keys. Charts like that show what depends on what, but not the nasty case: a key that fits two locks gets used in the wrong one, and the room becomes impossible while the clock is still running. Players call that a softlock. Roomwright reads a plain-text description of a room, tries **every order** in which a team could play, and reports each trap with the shortest sequence of moves that falls into it. It then works out the fastest route and schedules it across the players to show whether a bigger team actually finishes sooner.

## What it finds

- **Traps:** a move after which no order of play can reach the exit, along with the item that was used up and the puzzle that still needed it.
- **Impossible rooms and dead puzzles:** puzzles the team can never solve because what they need can't all be held at once.
- **Timing:** the least-work route, the critical path (no team can beat it), an estimate for every team size, and a text timeline of who does what.
- **Idle players:** the smallest team that finishes just as fast, so you know when a group is too big for the room.
- **Red herrings:** items that nothing needs. These are flagged as notes, because they may be deliberate.

## Example

`examples/clockmaker.room` has one deliberate mistake:

```text
$ ./roomwright examples/clockmaker.room
ROOMWRIGHT  The Clockmaker's Study
4 players, 45 minute limit, 9 puzzles, 11 items
Checked every order of play: 34 possible situations.

Can it be escaped?  yes, but 1 move can make it impossible.

TRAPS (moves after which the team can never get out)
  ! 'cabinet' uses up brass_key, which 'chest' still needs.
      shortest way in: drawer -> cabinet

FASTEST ROUTE  (8 puzzles, 39 minutes of work)
  A  drawer                     5 min   P2, minute 0-5
  B  painting                   6 min   P3, minute 0-6
  C  bookshelf                  7 min   P1, minute 0-7
  D  letter                     4 min   P2, minute 7-11
  E  safe                       3 min   P3, minute 11-14
  F  chest                      4 min   P4, minute 5-9
  G  clock                      8 min   P1, minute 14-22
  H  door                       2 min   P4, minute 22-24

TEAM ESTIMATE
  critical path: bookshelf -> letter -> safe -> clock -> door  (24 min: no team can be faster)
  by team size: 1 -> 39 min   2 -> 25 min   3 -> 24 min   4 -> 24 min
  4 players finish in about 24 minutes, busy 40% of the time.
  A team of 3 is just as fast, so extra players mostly wait. A parallel thread of
  puzzles would give everyone something to do.

  minute 0         10        20
  P1     CCCCCCC.......GGGGGGGG..
  P2     AAAAA..DDDD.............
  P3     BBBBBB.....EEE..........
  P4     .....FFFF.............HH

NOTES
  Red herrings (never needed, fine if deliberate): old_coin

1 problem:
  - Trap: solving 'cabinet' at the wrong time makes the room unwinnable. Give each lock its own key, or stop the key being used up.
```

## Describing a room

```text
title   The Clockmaker's Study
players 4            # default 4, up to 12
limit   45           # minutes, default 60
start   torn_note lamp

#      name      min    needs (* = used up)   gives
puzzle drawer     5   : torn_note          -> brass_key
puzzle chest      4   : brass_key*         -> pendulum
puzzle door       2   : door_code          -> EXIT
```

- A puzzle can be solved once, when the team holds everything it needs.
- An item marked `*` is **used up**, like a key left in a padlock. Without `*`, the item is only looked at (a clue, a torch) and is kept.
- Reaching the special item `EXIT` wins the game.

## Build, run and test

```bash
cd 2026/10-october/09-roomwright
make                                   # builds ./roomwright
./roomwright examples/clockmaker.room
./roomwright --players 6 examples/clockmaker.room
make test                              # unit + command-line tests, with sanitizers
make analyze                           # GCC's static analyser
```

Exit codes: `0` no problems, `1` problems found, `2` the input could not be used.

## Tech

C11 with only the standard library. It builds with `-Wall -Wextra -Wpedantic -Wshadow -Wconversion -Wformat=2 -Werror`, plus `_FORTIFY_SOURCE` and stack protection, under both GCC and Clang.

## Tests

`make test` runs 3,597 unit checks and 31 command-line checks, with AddressSanitizer and UndefinedBehaviorSanitizer catching any memory or arithmetic mistake as it happens:

- **The solver is checked against a slow, obviously-correct search** on 400 random rooms. Each trap it reports is then replayed move by move to confirm that the room really is lost after it.
- **A property from the theory:** without used-up items the team only ever gains things, so traps are impossible. This is tested on 300 random rooms.
- **The scheduler** never beats the critical path, never beats the work divided by the players, never puts one player on two puzzles at once, and makes someone reading a key finish before anyone uses it up.
- **Hostile input:** bad names, markup, terminal escape codes, non-ASCII and hidden NUL bytes, out-of-range numbers, oversized lines and files, too many puzzles or items, and an endless stream from `/dev/zero`.
- **State explosion:** a room with about a billion possible situations is refused quickly instead of eating the machine.

The release build also runs clean under Valgrind.

## Security

- **Bounded everything.** At most 64 KB is read (an endless stream is cut off), lines are at most 200 characters, and a room has at most 62 puzzles, 64 items and 12 players. The search stops at 200,000 states and memory is allocated once, up front, with a fixed size.
- **Allow-listed text.** Only printable ASCII is accepted. Names must match `[a-z][a-z0-9_]{0,23}` and titles use a small set of characters, so nothing printed in the report can carry escape codes or markup.
- **Errors never repeat the input.** They give the line number and the problem (for example "line 7: item 2 is not a valid name"), never the offending text.
- **Careful C.** No `gets`, `strcpy`, `sprintf` or variable format strings; every copy is length-checked; numbers are parsed by hand from at most four digits, so they cannot overflow. Recursion is never used on input data.
- **Checked by tools.** Strict warnings as errors, sanitizers in the tests, GCC's `-fanalyzer`, Valgrind and shellcheck for the test script.

**Known limits, stated honestly:**

- **The timing is a model.** It assumes each puzzle is worked by one player (or one huddle) at a time and takes the minutes you wrote. Real teams get stuck, split up badly and need hints. Use the numbers to compare designs, and confirm with playtests.
- Items are one-of-a-kind: holding two identical keys is not modelled. Give them different names.
- Huge rooms with many independent puzzles hit the 200,000-state limit; split them into stages.
- No software can promise it is 100% secure; these are the protections in place.
