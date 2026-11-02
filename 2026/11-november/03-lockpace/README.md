# Lockpace

**Plays an escape-room design for every team size before it's built. It shows how long each team takes, how much of the hour players spend standing about, the latest moment a game master should step in with a hint, and where the room can strand a team in a dead end.**

Language: JavaScript (Node.js, no runtime dependencies) · Field: escape-room design / project scheduling · Day: 3 November 2026

Escape-room designers sketch a room as a web of puzzles: the bookshelf cipher gives the drawer code, the drawer gives a key, the key opens the clock. Tools exist to draw that web and to check it can be solved. The questions that decide whether a room is *fun* are different:
- How does it play for 2 players compared with 6?
- Do big groups end up watching one person do a puzzle?
- When should the game master send a hint?

Lockpace answers those by playing the room:

- **Every team size:** finish time, a floor no team can beat, the share of the hour players spend idle, and the longest stretch the team spends waiting on a single puzzle.
- **A timeline:** who is doing what, minute by minute, for the team size you choose.
- **Hint deadlines:** for each puzzle, the latest it can start and still beat the clock, even with every player helping. If a team hasn't started it by then, they can't make it without help.
- **Design warnings:**
  - puzzles that can never be solved;
  - puzzles that aren't needed to escape;
  - red-herring items;
  - **dead ends**, where an item that gets used up is wanted by two puzzles, so using it in the wrong place first strands the team;
  - two-person and three-person puzzles that a small team can't do.
- **The sweet spot:** the team size beyond which extra people save less than 5% of the time.

## Quick start

```bash
node bin/lockpace.js examples/clockmaker.txt
npm test                   # 13 tests, including 200 random rooms
npm install && npm run check   # strict TypeScript checking of the JavaScript (dev only)
```

```
LOCKPACE  The Clockmaker's Study
14 puzzles, a 60-minute limit, teams of 2 to 6.

With as many players as it takes: 37:00 (the longest chain of puzzles).

  Team  Finish   At best   Idle   Longest wait on one puzzle
     2  stuck: Grandfather clock needs 3 people
     3   42:00    37:00    13%   2:00 (Pendulum cabinet)
     4   37:00    37:00    26%   5:00 (Grandfather clock)
     5   37:00    37:00    41%   5:00 (Grandfather clock)
     6   37:00    37:00    51%   5:00 (Grandfather clock)

Beyond 4 players, extra people save less than 5% of the time and mostly stand about.

Timeline for 4 players (one column = 1 min, '.' = nothing to do):
  P1  |AAAAAAAAABBBGGGGGGGGGGJJJJJJJJJMMMMMN|
  P2  |CCCCCCC.DDDDDDDD...IIIIIIILLLLLMMMMM.|
  P3  |EEEEEEFFFFFFFHHHHHH............MMMMM.|
  P4  |KKKKKKKKDDDDDDDD.....................|
  A Bookshelf cipher        B Desk drawer             C Portrait eyes
  ...

Hint deadlines: the latest each puzzle can start and still beat 60:00, even with every player helping.
If a team hasn't started a puzzle by then, they can't make it without a hint:
  Bookshelf cipher              23:00
  Portrait eyes                 30:00
  ...
Warnings:
  ! Never used anywhere (red herrings?): old coin.
```

This draft has three problems a designer would want to know about:
- a pair can't finish at all, because the grandfather clock needs three hands;
- after four players, the room has nothing more for people to do;
- the bookshelf cipher is the puzzle to watch, since it must be started by 23:00.

A dead end looks like this:

```
  ! Dead end: Chest and Door each use up the key, but only 1 exists; using it in the wrong place first strands the team.
```

## The room file

```
room The Clockmaker's Study
limit 60                 # minutes
players 2-6              # team sizes to try
show 4                   # which team's timeline to draw
goal freedom             # the item that opens the exit
start torch              # items the room begins with (optional)
puzzle Telescope (8 min, 2 people) needs star chart gives lens
puzzle Grandfather clock (5 min, 3 people) needs pendulum uses safe key gives exit key
```

`needs` items stay put (a code, a clue on the wall). `uses` items are used up (a key left in a lock). `gives` lists what solving the puzzle produces. A puzzle takes its time with exactly its number of people (1 if not given).

Exit codes:
- `0`: some team size beats the clock and there are no dead ends.
- `1`: no team size beats the clock, or a puzzle can never be solved or there's a dead end.
- `2`: bad usage or input.

`-` reads standard input.

## Security

- **Bounded input:** at most 32 KB, read with a hard limit (so an endless pipe is cut off), 200 characters a line, 60 puzzles and 120 items. Only regular files are opened, without following symlinks, and the path is never printed.
- **Strict parsing:** every line must match a fixed pattern and every number has a range. Error messages give the line number and what was expected, never the input.
- **Safe text in the terminal:** names and items are checked against a fixed set of characters (letters in any script, digits and a little punctuation). Control characters (terminal escapes) and invisible formatting characters such as direction overrides are refused. The text is also checked to be valid UTF-8.
- **Bounded work:** each team size is one pass of an event-driven simulation, at most 60 puzzle starts. There is no search that can blow up.
- **No dependencies at run time:** no `eval`, no dynamic `import`, no shell calls. TypeScript (pinned, development only) checks the code in strict mode, and `npm audit` reports nothing.

**Known limits:**
- Real teams don't play like the simulation. They get stuck, split up badly and solve puzzles in a different order. Lockpace's finish times are what a team that always works on the most urgent puzzle would manage, and the floor says what nobody can beat.
- With puzzles that need several people, the simulation's order may not be the best possible: scheduling with shared people is NP-hard. The gap to the floor (5 minutes for 3 players above) shows how much room is left.

See [HOW-IT-WORKS.md](HOW-IT-WORKS.md) for the walkthrough.
