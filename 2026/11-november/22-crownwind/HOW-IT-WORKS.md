# How Crownwind works

## Architecture

```
src/crownwind.js   parsing and checking, the reserve model, fewest sessions, fewest windings
src/cli.js         the command line report
tests/             the example, automatic wear, brute-force checks, hostile files
examples/          a six-watch collection over two weeks
```

## Key concepts

**Everything in minutes.** The plan starts at a weekday and time; every slot and every stretch of
wear becomes minutes from the start, up to the end of the horizon.

**When a watch stops.** After a full wind a watch runs for its reserve, less the safety margin. An
automatic worn before it stops keeps running and is full when you take it off, so `stopAfter` walks
the wear stretches in order, pushing the stop time on each time a stretch starts before it.

**Fewest sessions.** Repeatedly find the watch that will stop first, hold the session until the
latest slot before that moment, and wind everything. Why it's optimal: winding a watch never makes
it stop sooner, so winding all of them at a session is never worse; and among the slots before the
first deadline, the latest one pushes every watch's next deadline furthest. Any optimal plan can be
swapped, session by session, into this one without adding sessions. The test confirms it against
trying every subset of slots on random collections.

**Fewest windings.** With the sessions fixed, each watch independently gets the same greedy: wind
it at the latest session before it would stop. A watch with a long reserve skips most sessions.

## Language features worth noticing

- `Map` keyed by watch objects tracks each watch's stop time without mutating the parsed plan.
- Unicode property escapes (`\p{L}`) in the name pattern allow names like "Lange 1" or "Zénith".
- `import.meta.url` makes the CLI file both importable (for tests) and runnable.

## Interview questions

**Why is greedy optimal here when it so often isn't?** The problem has the "staying ahead" property:
after k sessions, greedy's watches all have deadlines at least as late as any other plan's after k
sessions, because it waited as long as possible and wound everything. That invariant gives the proof.

**What breaks the greedy?** Costs that differ per session (an inconvenient time), or a limit on how
many watches you can wind at once. Then it becomes a shortest-path problem over (time, deadlines)
states, or an integer programme.

**How do you test an optimality claim?** Against exhaustive search on small random instances,
including the cases where no plan exists: then greedy must also give up.

## Extensions

1. Watch winders: a box that turns automatics on a schedule, as extra free sessions.
2. An `.ics` calendar export with one reminder per session.
3. Learn each watch's real reserve from when it actually stopped.
