# Shotwise

**Puts a wedding's family photo list in the order that keeps everyone waiting least, respecting who arrives late, who must leave early and whose waiting matters most (grandparents, small children), then prints a call sheet saying who to call in before each shot and who is free to go after it.**

Language: Python 3.10+ (standard library only) · Field: event photography / combinatorial optimisation · Day: 1 November 2026

Family formals are the part of a wedding everyone dreads. The list is written in the order people think of it, so Auntie is in shot 2 and shot 11 and stands around for twenty minutes in between, while Nani's lift leaves before her last shot. Shot-list generators help write the list; Shotwise works out the **order**:

- **Least waiting, proven:** someone has to stay from the start of their first shot to the end of their last. Shotwise minimises the total of that standing about, and for up to 16 shots it checks every possible order (with a dynamic programme, not 16! permutations).
- **Real constraints:** `leaves Nani at 16`, `arrives Ben at 6`, `first Couple alone`, `last Everyone`, and different lengths for big groups.
- **Weights:** `weight Nani 3` makes her waiting count three times, so the plan works hardest for the people who find standing hardest.
- **A call sheet:** for each shot, the start time, who is in it, who to **call in** (their first shot) and who is **free to go** (their last).
- **Honest comparison:** it shows the waiting for the order as written, and any time limit that order would break.
- **Long lists too:** above 16 shots, a greedy start improved by moving one shot at a time (and it says the result is not proven).

## Quick start

```bash
PYTHONPATH=src python3 -m shotwise.cli examples/wedding.txt
PYTHONPATH=src python3 -m unittest discover -s tests     # 14 tests, including a check against every permutation
ruff check . && bandit -r src
```

```
SHOTWISE  Priya and Tom
14 shots, 17 people, 31 minutes of photos.
This order keeps everyone waiting least (every order was checked).
Waiting: 164 weighted person-minutes, against 228 in the order as written.
  As written: Nani must leave at 0:16 but is needed until 0:17.

 1. 0:00  Couple alone
          with:       Priya, Tom
          call in:    Priya, Tom
 2. 0:02  Priya and Kiran
          with:       Kiran, Priya
          call in:    Kiran
 ...
 7. 0:12  Both families (3 min)
          with:       Anita, Arjun, Graham, Grandpa Bill, Helen, Kiran, Lucy, Meera, Nani, Priya,
                      Raj, Sam, Tom (13)
          call in:    Grandpa Bill, Lucy, Sam
          free to go: Nani
 ...
14. 0:27  Everyone (4 min)
          with:       Anita, Arjun, Ben, Chloe, Graham, Grandpa Bill, Helen, Kiran, Lucy, Meera,
                      Ollie, Priya, Raj, Sam, Tom, Zara (16)
    0:31  done

Waiting between their shots: Anita 16 min, Kiran 16 min, Raj 16 min, Graham 14 min, ...
```

One result is surprising: "Priya and Kiran" goes second, not next to the other family shots. Kiran has to stay for "Everyone" at the end anyway, and at 0:02 almost nobody is waiting yet, so doing a small shot early costs less than doing it later while a dozen people stand around.

## The shot list

```
title Priya and Tom
minutes 2                                  # the usual time per shot (1-30)
shot Couple alone: Priya, Tom
shot Both families (3): Priya, Tom, Anita, Raj, ...   # (3) = this shot takes 3 minutes
leaves Nani at 16                          # minutes after the photos start
arrives Ben at 6
weight Nani 3                              # her waiting counts three times (1-10)
first Couple alone
last Everyone
```

Names are matched exactly as written in the shots. Exit codes: `0` order printed, `1` no order meets every time (the closest one is printed with what it misses), `2` bad usage or input. `-` reads standard input.

## Security

- **Bounded input:** at most 32 KB (read with a hard limit, so an endless stream is cut off), 300 characters a line, 60 shots, 150 people and 40 people in a shot. Only regular files are opened, and the path is never echoed.
- **Strict parsing:** every line must match one of a fixed set of patterns, and every number has a range. Error messages give the line number and what was expected, never the line's text.
- **Safe names in the terminal:** names may use letters in any script, digits and `' . & -`. Control characters (terminal escapes) and invisible format characters such as Unicode direction overrides are refused.
- **Bounded work:** the exact search is used only up to 16 shots (2^16 sets), and the local search has a fixed budget of 60,000 evaluations, so even a 60-shot list finishes in a few seconds.
- **No dependencies and nothing dangerous:** no `eval`, `exec`, `pickle` or shell calls. `ruff` (including the flake8-bandit `S` rules) and `bandit` report nothing.

**Known limits:** shots take the same time however long the group takes to gather, and people are assumed to stay put from their first shot to their last (in real life some wander off to the bar). For more than 16 shots the order is very good but not proven the best.

See [HOW-IT-WORKS.md](HOW-IT-WORKS.md) for the walkthrough.
