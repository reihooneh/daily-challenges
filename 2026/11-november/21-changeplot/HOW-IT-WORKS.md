# How Changeplot works

## Architecture

```
changeplot/plot.py      reading the show, finding changes, timing them, assigning dressers
changeplot/__main__.py  the command line report
tests/                  windows, underdressing, brute-force check of the dresser count, hostile input
examples/show.json      a six-scene show with four actors
```

## Key concepts

**Timeline.** Scenes are laid end to end with their gaps, so every scene has a start and end time
in seconds from the top of the show.

**Changes.** Walking each actor's costumes in order and skipping offstage scenes, a change happens
whenever the costume differs from the last one they wore. The window is the time between the end of
the scene they left and the start of the scene they return in.

**How long a change takes.** Putting on the new costume, unless it was underdressed beneath the old
one, when it's only taking the old one off (a third of the old costume's time). With a dresser,
60 % of that.

**Quick and impossible.** A change needs a dresser if its window is under two minutes or under 1.5
times the time alone. It's impossible if even the helped time doesn't fit.

**Dressers as interval scheduling.** A dresser is busy from the actor's exit until the change is done.
Two changes can share a dresser if their busy times don't overlap, with 45 seconds (configurable) to
cross behind the set when they're in different wings. Because the crossing time depends on the pair,
this isn't a plain interval graph where first fit is always optimal, so Changeplot first fits in time
order, then searches exactly for a rota with one dresser fewer, and repeats until none exists. The
search breaks symmetry by never trying two empty dressers for the same change, and stops after
200,000 steps.

## Language features worth noticing

- Frozen dataclasses with properties (`window`, `quick`, `takes`, `spare`) keep each rule in one place.
- The walrus operator in `seconds()` matches and checks in one expression.
- A nested function with `nonlocal` counts search steps, and an exception unwinds the recursion when
  the budget runs out.

## Interview questions

**Why isn't first fit enough?** With equal crossing times everywhere, sorting by start and taking any
free dresser is optimal for interval graphs. Crossing time breaks that: a dresser who just finished
stage left may be free in time for a stage-left change but not a stage-right one, so the order of
choices matters. The exact search proves the count; the test compares it with brute force over every
assignment.

**How do you stop the exact search from running forever?** A step budget. The report says when it
was hit, so the answer is never silently wrong, just possibly not minimal.

**What would you validate in an input file like this?** Shape (objects and lists where expected),
references (every costume an actor wears exists, underdressing refers to real costumes), ranges, and
the text itself, since names end up in a report someone reads in a terminal.

## Extensions

1. Entrances and exits partway through scenes, read from the script's cue lines.
2. Assign named dressers with their own skills (wigs, quick-rig fastenings).
3. Draw the changes on a timeline per wing as SVG for the costume shop wall.
