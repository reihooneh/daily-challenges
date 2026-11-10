# Kitewise

**Catches the dog-legs and giveaways in an orienteering course, and says where to move a kite to fix them.**

Language: Lua 5.4 (no dependencies) · Field: orienteering course setting / computational geometry · Day: 11 November 2026 (morning)

In orienteering, a *dog-leg* is a control where the leg out leaves in nearly the direction the leg in arrived. Runners leaving then lead runners arriving straight to the kite: the course gives itself away. Course-setting guides warn about dog-legs, controls placed too close together, and legs that brush past other controls. In the usual tools, though, checking for them is a job for the setter's eye.

Kitewise checks a course for all of them and measures how bad each one is in metres. For controls the setter has marked as movable (because the terrain has other suitable features nearby), it finds where to put them so the problems go away.

## Features

- **Dog-legs, measured, not just flagged.** Two runners the same distance d from a control, one arriving and one leaving, are 2·d·sin(θ/2) apart, where θ is the angle between the legs. Kitewise works out how far out they stay within sight of each other, beyond the first stretch that every control has. A 60° control is clean; a 20° one gives itself away for over 50 m.
- **The usual distance rules,** forest/park or sprint:
  - no two controls closer than 30 m (sprint 15 m);
  - controls within 60 m (sprint 30 m) must be on different kinds of feature.
- **Pass-bys:** a leg that runs within sight of a control that isn't on it.
- **Crossings:** legs that cross, which make the map harder to read.
- **Suggested moves.** Each control marked `move 20` may go anywhere within 20 m on a 5 m grid. Kitewise tries every combination when there are few enough (and says so), otherwise moves one control at a time until nothing improves. It reports what's still left to fix by hand.
- **Leg lengths and course length,** for checking the course is the right size.

## Example

```text
$ lua kitewise.lua examples/park-sprint.txt
Kitewise: Riverside Park sprint, course B
7 controls, 8 legs, 0.87 km in straight lines (sprint distances)

Legs (m): S-31 134, 31-32 114, 32-33 117, 33-34 115, 34-35 106, 35-36 107, 36-37 123, 37-F 54

Problems:
  - dog-leg at 32: the legs in and out meet at 31°, so runners leaving show the control for 13 m beyond the first 15 m
  - dog-leg at 35: the legs in and out meet at 11°, so runners leaving show the control for 60 m beyond the first 15 m
  - 34 and 36 are both on a bench only 21 m apart (under 30 m, they need different features)
  - leg 4 (33 to 34) passes 10 m from 36, within sight
  - legs 5 and 7 cross
  - leg 7 (36 to 37) passes 9 m from 34, within sight

Suggested moves (problem score 602 -> 34):
  - move 33 18 m north-east (to 165, 125)
  - move 35 14 m north-west (to 320, 80)
  - move 36 20 m south (to 245, 115)
Still to fix by hand:
  - dog-leg at 32: the legs in and out meet at 40°, so runners leaving show the control for 7 m beyond the first 15 m
  - dog-leg at 35: the legs in and out meet at 24°, so runners leaving show the control for 21 m beyond the first 15 m
  - dog-leg at 36: the legs in and out meet at 54°, so runners leaving show the control for 1 m beyond the first 15 m
  - legs 5 and 7 cross
```

## Writing a course

Positions are metres east and north on the map (any origin).

```text
title: Riverside Park sprint, course B
sprint                                         # sprint distances (leave out for forest and park)
control S at 0 0 start
control 31 at 120 60 feature bench
control 33 at 150 115 feature statue move 20   # may be moved up to 20 m
control F at 380 230 finish
course S 31 33 F
```

## Run and test

Needs Lua 5.4.

```bash
lua kitewise.lua examples/park-sprint.txt      # exit 3: problems found
lua kitewise.lua examples/forest-clean.txt     # exit 0: clean
lua test/test_kitewise.lua
```

The tests cover:
- **Reading:** the example is read correctly, and broken or hostile files are refused.
- **Geometry:** the dog-leg formula against exact answers (straight back, 60°, 20°), plus crossing and distance tests.
- **Each kind of problem,** found on a course built to have them.
- **The fixer:**
  - moves stay within their limits and on the grid;
  - against brute force on 40 random courses, its exhaustive search is exactly the best, and the one-at-a-time search never beats it.
- **The command line:** exit codes, folders, missing files, a "password" file and an endless input.
- **Globals:** no global variables leak, as a stand-in for luacheck.

## Security

Kitewise reads one course file and prints notes. No software is perfectly secure; this is how the risks are handled.

- **Bounded input:**
  - at most 32 KB is read (an endless input is cut off, not loaded), and it must be valid UTF-8 with at most 500 lines;
  - at most 60 controls and 60 legs;
  - every number has a range;
  - codes and features are short letters and digits;
  - control characters and invisible text-direction characters are refused.
- **Errors name the line, never echo it:** a test checks a "password" file isn't repeated.
- **Bounded work:** exhaustive search only up to 20,000 combinations, then at most 20 rounds of one-at-a-time moves.
- **No risky code:** no `load` of input, no `os.execute`, no network, and no files written.

**Limits:**
- Legs are straight lines. Real runners follow paths and avoid cliffs, so a dog-leg on a winding path may be better or worse than the straight-line measure says.
- "Within sight" is a single distance. Thick forest hides more and open parkland less.
- Kitewise doesn't know the terrain, so it can only move controls where the setter has said other suitable features exist.

More detail: [HOW-IT-WORKS.md](HOW-IT-WORKS.md).
