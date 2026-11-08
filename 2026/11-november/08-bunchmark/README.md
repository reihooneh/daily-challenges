# Bunchmark

**Plans where a mixed-ability group ride should regroup.** It simulates every rider over the route from their weight and the power they can hold, and finds the fewest stops that keep the bunch together. If one bunch can't stay together, it finds the best way to split it in two.

Language: Python 3.10+ (standard library only) · Field: cycling / physics simulation and dynamic programming · Day: 8 November 2026 (evening)

Every club ride leader knows the problem. On the flat the bunch sits together, but on every climb the group stretches out, and someone ends up minutes behind and out of sight. The usual fix is "we'll wait at the top", but which tops? Stopping everywhere wastes everyone's time and chills the fast riders. Stopping too rarely leaves the slowest rider alone on a hill.

Route apps plan the road and ride apps record it afterwards. Bunchmark plans the *group*:

- **Every rider simulated:** it solves the cycling power balance (gravity, rolling resistance, air drag) for each rider's steady speed on each stretch. On flats, rises and descents the bunch rides together at the pace the slowest rider can hold in the draft, so gaps stay as they are. On climbs (4% and steeper) everyone climbs at their own pace.
- **The gap rule:** the last rider may never be more than `max_gap` minutes behind the first, anywhere on the road.
- **The fewest regroups, exactly:** a dynamic program over the candidate places (car parks, lookouts, bridges) finds the fewest stops that keep the gap in bounds, then the shortest ride among those. It never stops more often than it must, because extra stops can't make the ride shorter.
- **Who waits:** each stop shows who comes in last, who waits longest and the biggest gap on the way there, plus each rider's total waiting.
- **Splitting the bunch:** if even stopping at every place can't hold the gap, it tries every split into a faster and a steadier bunch (two or more riders each), and plans both.
- **An elevation profile** with the regroups marked.

## Quick start

```bash
PYTHONPATH=src python3 -m bunchmark examples/harbour-hills.txt
PYTHONPATH=src python3 -m bunchmark examples/mixed-bunch.txt          # too wide a spread: splits the bunch
PYTHONPATH=src python3 -m bunchmark - --stop-minutes 5 < examples/harbour-hills.txt
python3 -m unittest discover -s tests                                 # 12 tests, including 300 random rides against brute force
ruff check src tests && bandit -r src
```

```
BUNCHMARK  Harbour Hills ride: 40.2 km, 6 riders, keep the gap within 3 min

Without regroups the gap would reach 5:56: Grace would finish 5:56 after the first rider.

Plan
  Regroup 2 times: Bobbin lookout (km 10.5), Creek bridge (km 22.3).
  Ride time 1:27:54, including 2:00 at each regroup.
  Bobbin lookout (km 10.5): last in Grace after 23:51; Priya waits longest, 1:37. Biggest gap on the way 1:37.
  Creek bridge (km 22.3): last in Grace after 23:54; Priya waits longest, 2:12. Biggest gap on the way 2:12.
  the finish (km 40.2): last in Grace after 36:09; Priya waits longest, 2:07. Biggest gap on the way 2:07.
  Waiting in total: Priya 5:56, Tom 4:52, Mei 2:26, Ollie 1:55, Grace 0:00, Dev 0:38.

  Profile over 40.2 km, 351 m from the lowest point to the highest; numbers mark the regroups
  |                                       #####
  |                  ###                 #########
  |                 #####               #############
  |                ########            ################
  |               ##########        ###########################
  |              ##############################################
  |            ################################################
  |       #####################################################
  +------------------------------------------------------------
                  1                 2
```

The obvious "wait at the top of Bobbin" isn't in the plan. Stopping halfway up at the lookout, then at the creek bridge after the descent, keeps everyone within 3 minutes with the same number of stops, and gets the group home sooner.

## The ride file

```
route Harbour Hills ride
max_gap 3                 # minutes (default 3)
rider Priya 66 235        # name, rider + bike kg, watts held for a few hours
ride 6.0 0.5              # km, gradient %
regroup Lighthouse car park   # a place the bunch could stop, at the distance so far
```

Exit code: 0 for a plan (or a split), 2 for a bad file or option.

## Security

The ride file is untrusted input:

- **Bounded:** at most 64 KB, read with a size cap, and lines of 200 characters. There are at most 40 riders, 300 stretches, 60 regroup places and 400 km, so the planner's work (cubic in the number of places at worst) stays small.
- **Strict shapes:**
  - every line is one of five commands with a fixed number of fields;
  - numbers must be plain decimals in range (no `nan`, `inf` or `1e3`);
  - names use a small character set;
  - control characters, invisible direction marks and invalid UTF-8 are refused.
- **Nothing is executed:** there's no `eval`, no shell and no pickle. Only regular files are opened (not links, folders or devices).
- **Safe errors:** they give a line number, never the line or the path.
- **Checked:** ruff (with the bandit rules) and bandit report nothing.
- **Known limits:**
  - the physics is steady-state (no wind, no acceleration, no fatigue), and "everyone at the slowest pace on the flat" is how a disciplined bunch rides, not every bunch;
  - descents are capped at 55 km/h for safety;
  - real powers vary on the day, so leave a margin in `max_gap`.

## Files

| File | What it does |
|---|---|
| `src/bunchmark/physics.py` | The power balance and each rider's speed on a gradient |
| `src/bunchmark/parse.py` | Strict reading of the ride file |
| `src/bunchmark/plan.py` | Stage times, the dynamic program, splitting the bunch |
| `src/bunchmark/report.py` | The plan in words, and the profile |
| `src/bunchmark/cli.py` | The command: options and safe reading |
| `tests/test_bunchmark.py` | Physics, brute force, refusals, the command |
| `examples/*.txt` | A ride that works as one bunch, and one that needs two |

See [HOW-IT-WORKS.md](HOW-IT-WORKS.md) for the physics, the algorithm and interview questions.
