# Castling 🎭

**Works out the smallest cast that can perform a play, and which roles each actor can double, leaving time for every costume change.**

Small theatre companies, school productions and touring shows routinely have one actor play several parts. Working out who can double what is usually done by hand on a scene chart, and the trap is timing: two roles can look compatible because they never share a scene, but there are only 30 seconds of blackout to get out of one costume and into the next. Castling reads a scene breakdown with entrances, exits and change times. It then:

- **Finds the smallest possible cast, and proves it.** It names the group of roles that all clash with each other, which is the clearest reason the cast can't be any smaller.
- **Picks the safest plan of that size.** Of all the plans with the fewest actors, it chooses the one whose tightest costume change has the most time to spare.
- **Flags quick changes** that need a dresser and a rehearsed change.
- **Checks a fixed company size** (`--actors 6`) and says why it isn't enough.
- **Respects the director:** `together ghost gull` for a planned double, and `apart mara nell` for two roles that must be played by different actors.
- **Allows doubling inside a scene.** One character can leave early and another arrive late, so one actor can play both if the change fits.

## What makes it different

The classic tool for this, ACTORS (a research program for analysing doubling in Shakespeare's plays), works from who is on stage together and lists timing as a possible future addition. Castling is built around time: every entrance, exit, blackout and interval is on a clock. Each actor's costume changes are checked against how long they are actually offstage, and among the smallest casts it picks the plan with the most time to spare.

## Example

`examples/lighthouse.play`, an original one-act play:

```text
$ castling examples/lighthouse.play
CASTLING  The Lighthouse Keeper's Daughter
8 scenes, 9 roles, running time 1:03:00 including 1 interval

Smallest cast: 7 actors (proven minimum)
  These 7 all clash with each other, so each needs their own actor:
  keeper, mara, gull+ghost, tobias, nell, fisherman, inspector

Plan for 7 actors (the safest: every costume change has at least 2:00 to spare)
  Actor  1  inspector + widow  2:00 spare  (inspector 6 -> widow 7)
  Actor  2  gull + ghost       12:00 spare  (gull 4 -> ghost 5)
  Actor  3  keeper             no changes
  Actor  4  mara               no changes
  Actor  5  tobias             no changes
  Actor  6  nell               no changes
  Actor  7  fisherman          no changes

No problems found.
```

Flag anything under 2:30 to spare:

```text
$ castling --warn 2:30 examples/lighthouse.play
...
Quick changes (under 2:30 spare): plan a dresser and a rehearsed change
  inspector -> widow before scene 7: 3:30 offstage for a 1:30 change
```

Try a company of six:

```text
$ castling --actors 6 examples/lighthouse.play
...
A cast of 6 is not enough: at least 7 are needed.

1 problem:
  - 6 actors can't cover every role. Cut or merge a role among: keeper, mara, gull+ghost, tobias, nell, fisherman, inspector.
```

## Writing a breakdown

```text
title   The Lighthouse Keeper's Daughter
change  1:30                 # default time to get into a costume
between 0:30                 # blackout between scenes
role ghost change 3:00       # this costume takes longer
scene 2 5:30 : mara<2:00 tobias nell>1:00
interval 15:00
together gull ghost          # a planned double
apart mara nell              # must be different actors
```

- Times are `M` or `M:SS`.
- In a scene, `nell>1:00` enters 1:00 after the scene starts, and `mara<2:00` leaves 2:00 before it ends.
- A change is counted whenever an actor switches from one role to another, using the change time of the role they are getting into.

## Usage

```bash
castling [--actors N] [--warn M:SS] FILE     # FILE can be - for standard input
```

Exit codes: `0` a plan with no problems, `1` problems (too few actors, or quick changes under the warning time, 1:00 by default), `2` the input could not be used.

## Tech

JavaScript (Node.js 20 or later, ES modules), with no runtime dependencies. Types are checked by the TypeScript compiler in strict mode through JSDoc comments (`npm run check`), and the only development dependency is the pinned Node type definitions.

## Run and test

```bash
cd 2026/10-october/09-castling
node bin/castling.js examples/lighthouse.play
npm test            # node:test, no install needed
npm install && npm run check    # optional strict type check (needs tsc installed)
```

22 tests, including:

- **Checked against brute force.** On 200 random plays, Castling's smallest cast and safest plan are compared with an exhaustive search over every way of splitting the roles among actors. On 300 random graphs, the colouring and clique searches are compared with brute force.
- **Every plan is re-verified independently:** each role is cast exactly once, no actor is in two places at once, no change is too quick, and every `together` and `apart` instruction is respected.
- **Graph theory sanity checks:** odd cycles need 3 colours; the Petersen graph needs 3 even though its largest clique is 2, which shows that a clique bound is not always enough on its own.
- **Hostile input:** markup, escape codes, right-to-left override characters, NUL bytes, bad times and labels, path-like labels, impossible entrances, oversized lines and files, too many scenes or roles, non-UTF-8 bytes, and an endless stream from `/dev/zero`.
- **Limits:** the largest allowed play (60 roles, 80 scenes) finishes quickly, and on a hard dense graph the search stops at its step budget but still returns a usable plan.

## Security

- **Bounded input and work.** At most 64 KB is read (the reader stops there, so an endless stream can't fill memory), lines are at most 200 characters, and a play has at most 80 scenes and 60 roles. Both searches have a step budget, so no input can make them run for ever; if the budget is hit, the report says the result may not be optimal.
- **Allow-listed text.** Only printable ASCII is accepted. Role names, scene labels, titles and times each have a strict pattern, so nothing in the report can carry terminal escape codes or markup. Non-UTF-8 input is rejected rather than guessed at.
- **Errors never repeat the input.** They give the line number and the problem, never the offending text.
- **Least privilege.** The tool only reads the one file named, never writes, and uses no network, shell, `eval` or dynamic `import`. There are no runtime dependencies, and the one development dependency is pinned, with `npm audit` clean.

**Known limits, stated honestly:**

- **The plan is only as good as the timings you give it.** Change times vary with the costume, the dresser and the venue. Rehearse every quick change before relying on it.
- An actor is assumed to need the same time to get into a costume whatever they were wearing before.
- It doesn't consider who suits a part (age, voice, singing range). It answers "who *can* play what", and the director still decides who *should*.
- No software can promise it is 100% secure; these are the protections in place.
