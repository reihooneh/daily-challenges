# Carryless

**Builds a fairer round-robin fixture for a sports league: no team keeps meeting its opponents straight after the same other team, home and away are balanced, and clubs that share a ground are never both at home.**

Language: Python 3.10+ (standard library only) · Field: sports scheduling / combinatorics · Day: 20 October 2026

Most local leagues make their draw with the "circle method": fix one team and rotate the rest. It's simple, but it has a hidden unfairness. Suppose Rovers play a bruising match against Dockers. Under the circle method, **the same team keeps playing Rovers the round after Dockers do**, again and again, so one club always meets opponents who've just been through that physical game (or who are flying after beating a weak side). This is the **carry-over effect**, and the circle method is known to give the worst possible version of it.

Carryless builds a fixture where carry-overs are spread as evenly as possible. Then it chooses home and away for every match to keep "breaks" (two home or two away games in a row) low, and never puts two clubs that share a ground at home in the same round.

## Quick start

```bash
PYTHONPATH=src python3 -m carryless.cli examples/netball.txt
PYTHONPATH=src python3 -m carryless.cli examples/netball.txt --csv > fixture.csv
PYTHONPATH=src python3 -m unittest discover -s tests       # 17 tests
```

```
CARRYLESS  netball.txt  (Westside Saturday netball: 10 teams, 9 rounds)

  Carry-over value   128   (perfect would be 90; the usual circle fixture scores 468)
  Worst pair         at most 2 teams meet the same two opponents back to back, in the same order (circle fixture: 7)
  Home/away breaks   16   (no fixture of this size can have fewer than 8)
  Shared grounds     never both at home
  Method             simulated annealing from the circle method

  Round 1   Dockers v Hilltop Hawks   Riverbend v Old Collegians   Saints v Northgate   Wanderers v Parkside   Comets v Rovers
  ...
  Venues (H home, A away, - bye)
  Rovers          A H A H A A H A H
  ...
```

With 4, 8, 16 or 32 teams it uses **Russell's construction**, which is perfectly balanced: every ordered pair of opponents happens back to back exactly once.

## The league file

```
league Westside Saturday netball
team Rovers
team Dockers
team Hilltop Hawks
share Rovers Dockers        # these two share a ground: never both at home in one round
```

An odd number of teams is fine: each team gets one bye. `--seed N` gives a different (but repeatable) fixture; `--csv` prints `Round,Home,Away` rows for a spreadsheet.

## Security

- **Bounded input:** at most 16 KB, 120 characters a line and 40 teams. Only regular files are read (not symlinks or devices, so `/dev/zero` is refused), and reading stops at the limit. The file must be valid UTF-8.
- **Strict names:** team names start with a letter or digit and use only letters, digits, spaces and simple punctuation, so nothing can be a spreadsheet formula. CSV cells are also guarded: anything starting with `=`, `+`, `-` or `@` would be prefixed so spreadsheets show it as text.
- **Safe output:** control characters and hidden bidirectional characters are refused, error messages never repeat the input, and the file name is cleaned before printing.
- **Bounded work:** every search has a fixed number of steps (with a time ceiling as a safety net), so no input can make it run for long.
- **Checked:** `ruff` (including its security rules) and `bandit` report no issues; there are no dependencies.

**Known limits:** for sizes other than powers of two, the carry-over search finds a good fixture, not a proven best one. Home and away are chosen after the rounds are fixed, so the break count is the best the search found for those rounds, which can be above the theoretical minimum of n − 2. It makes single round robins; for a double round robin, play the fixture twice with home and away swapped.

See [HOW-IT-WORKS.md](HOW-IT-WORKS.md) for the walkthrough.
