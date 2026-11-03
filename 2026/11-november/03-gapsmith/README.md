# Gapsmith

**Reads a model railway track plan, finds every reversing loop and wye that would short-circuit the track power, and says exactly where to put the insulated rail joiners: the fewest cuts, with each reversing section long enough to hold your longest train. Then it gives the wiring for every piece of track.**

Language: Java 21 (no dependencies) · Field: model railways / signed graphs · Day: 3 November 2026 (evening)

A balloon loop or a wye lets a train turn round. It also brings a rail back to meet the opposite rail, which is a dead short the moment power goes on. The standard fix is a reversing section: cut both rails at each end and feed the section from an auto-reverser that flips its polarity as a train crosses. Getting it right is a classic forum question: where exactly do the gaps go? What if there are two loops? Why does the auto-reverser trip when a long train goes through? Gapsmith answers all three:

- **Finds every short circuit** and shows the loop of joins that causes it, marking where the rails cross.
- **Chooses the cuts:** the fewest auto-reversers first, then the fewest cuts, then the shortest sections. Each section must be longer than your longest train, so a train is never across both gaps at once (the usual cause of an auto-reverser tripping).
- **Handles real layouts:** turnouts, sidings, wyes, and two separate reversing places (a wye and a balloon, say), each with its own auto-reverser.
- **Gives a wiring list:** for every other piece of track, which rail gets the red feeder, so the whole layout agrees.
- **Says when nothing works:** if no section is long enough for your train, it tells you rather than giving a plan that will trip.

## Quick start

```bash
make && ./gapsmith examples/riverside.txt
make test        # 1,000 checks, including every subset of sections on 400 random layouts
```

```
GAPSMITH  Riverside Junction
12 sections (3 turnouts), 13 joins; longest train 1.60 m.

SHORT CIRCUIT: a train going round this loop comes back facing the other way, so its
rails meet the opposite rails somewhere on the way:
  loop3.b / t2.d             rails cross     (line 31)
  loop2.b / loop3.a          rails continue  (line 30)
  loop1.b / loop2.a          rails continue  (line 29)
  t2.s / loop1.a             rails continue  (line 28)

FIX: one reversing section, fed by an auto-reverser
  Sections: loop2, loop3
  Length:   2.20 m, longer than the 1.60 m train, so a train is never across both ends at once
  Cut both rails (insulated joiners) at:
    loop1.b / loop2.a          (line 29)
    loop3.b / t2.d             (line 31)
2 cuts in all: 4 insulated rail joiners.

WIRING: connect the red feeder to the rail named, black to the other.
  m1               left rail, facing from end a to end b
  ...
  t2               left rail, facing from the points (p) towards the frog
  loop2            from the auto-reverser (either way round)
  loop3            from the auto-reverser (either way round)
```

## The layout file

```
layout Riverside Junction
train 1.6 m                 # the longest train (m, cm or mm)
track loop1 1.2 m           # plain track: ends a and b
turnout t2 22 cm            # a turnout: ends p (points), s (straight), d (diverging)
join t2.s loop1.a           # which end meets which
```

A track's rails are named facing from end a to end b, and a turnout's facing from the points. An end that isn't joined is a buffer stop. Exit codes: `0` no cuts needed, `1` cuts needed (or no fix exists), `2` bad usage or input. `-` reads standard input.

## Security

- **Bounded input:** at most 64 KB, read with a hard limit, 200 characters a line and 200 sections. Only regular files are opened, without following symbolic links, and the path is never printed.
- **Strict parsing:** every line has a fixed shape, ids and lengths are checked, and each end can be joined only once. Errors give the line number and what was expected, never the input.
- **Safe text:** the file must be valid UTF-8. Control characters (terminal escapes) and invisible formatting characters such as direction overrides are refused.
- **Bounded work:** the search looks at no more than 300,000 runs of up to 8 sections, and at most 600 for pairs of reversing sections. If it stops at the limit, the report says a better plan may exist.
- **Clean build:** Java with `-Xlint:all -Werror` and no dependencies.

**Known limits:**
- Gapsmith handles the track's two running rails. Power-routing frogs (Electrofrog-style turnouts) need their own frog gaps as well; follow the turnout maker's instructions for those.
- Plan with your real track lengths. A reversing section only just longer than the train leaves no room for error, so allow a margin.

See [HOW-IT-WORKS.md](HOW-IT-WORKS.md) for the walkthrough.
