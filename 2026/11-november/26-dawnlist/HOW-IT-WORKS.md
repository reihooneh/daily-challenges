# How Dawnlist works

## Architecture

```
bin/dawnlist        Bash: arguments, reading the file safely, the size limit, the time limit
lib/dawnlist.awk    awk: parsing and checking every line, the search, the report
tests/run.sh        hand-worked days, pruned vs unpruned search on random days, the example, hostile files
examples/           a spring morning near the coast
```

Bash does what shells are good at: checking a path, capping input and running a program with a
time limit. Everything that touches the file's contents happens in awk, which can only read text,
so a hostile file has nothing to inject into.

## Key concepts

**Expected species.** For each species, Dawnlist keeps the chance you have *still missed* it. Visiting
a site where your chance of seeing it is `p` adds `missed × p` to the expected count, then multiplies
`missed` by `1 − p`. Summed over species, that's exactly the expected number seen, assuming
sightings at different sites are independent. It's why a second wetland is worth less than the
first: most of its birds are already likely.

**Time windows.** A bird line can carry a window, like `05:00-07:00`. A visit that *starts* inside
the window uses that chance, and one outside it uses the all-day line (or zero). The only times
worth starting a visit are when you arrive, or when one of the site's windows opens. So the search
tries just those and never has to scan every minute.

**Searching exactly.** A route is a sequence of (site, start time) pairs. The search is depth-first:
from where you are, try every next stop you can reach and finish before the day ends. Two things
keep it fast:

1. **A bound.** At each point, the most the rest of the day could add is worked out
   optimistically: every unvisited site you could still get to (by the shortest drive, through any
   other sites) visited at its best time. If even that can't beat the best day found so far, that
   whole branch is skipped. Because no real route can beat the bound, skipping loses nothing. The
   tests check this on 40 random days against a search with the bound turned off.
2. **A good first guess.** The search starts from the plan a hurried birder would make, and it tries
   the stops with the most species per minute first. So strong days are found early and the bound
   cuts harder. On a big, flexible day the search may hit its limit. It then prints the best day
   found and says so.

**Shortest drives.** Not every pair of places has a road listed, and a detour through another site
can be quicker. The bound uses all-pairs shortest drive times (Floyd–Warshall), because a site
reachable only the long way round is still reachable. The first version of the bound skipped such
sites, and the random tests caught it.

## Language features worth noticing

- **awk arrays keyed by tuples** (`tt[a, b]`, `lp[s, k, j]`) act as sparse matrices, with no setup.
- **Local variables in awk** are extra function parameters (`function search(cur, t, ev,   k, arr, …)`),
  which is what makes the recursive search work. Each call has its own candidate list.
- **Undoing instead of copying.** `visit` saves each changed miss chance and `unvisit` restores it,
  so the search never copies the state of all 120 species.
- **Bash:** `set -euo pipefail`, `[[ ! -L $f && -f $f ]]` to refuse links, `head -c` to cap input,
  and `timeout 60` to cap time. `LC_ALL=C` keeps character classes byte-exact.

## Interview questions

**1. Why not just add up each site's species?**
Because birds overlap. Two wetlands might each list fifteen species, but mostly the same fifteen.
Adding them would plan a day of wetlands. The miss-chance product counts a species once, however many
sites give a chance at it. The value of a stop then depends on what came before, which is why the
order matters and a greedy plan falls short (19.3 vs 20.6 in the example).

**2. How do you know the pruning doesn't throw away the best route?**
The bound is an overestimate by construction. It lets every reachable site be visited, at its best
chance, with no travel time between them. A real continuation can only do worse. Pruning a branch
whose overestimate can't beat a day already found is therefore safe. The tests also check it: on
40 random days, the pruned and unpruned searches must find the same expected count. That test is
what found the missing-road bug.

**3. This is NP-hard. What happens with a bigger day?**
It's an orienteering problem with time windows, so the worst case grows factorially. Dawnlist caps
sites at 12 and the search at a budget. It starts from a decent plan and tries good stops first, so a
search that stops early still has a strong, valid day, and it says it may not be the best. For more
sites I'd swap the exact search for a local search (2-opt moves and swaps) or a beam search, and
keep the exact one as a check on small days.

## Extension ideas

- Read chances straight from a CSV of past checklists: the share of checklists at a site, in a time
  band, that recorded the species.
- Let the stay at a site vary: a longer visit raises each chance (`1 − (1 − p)^(minutes / base)`).
- Plan for a team in two cars: split the sites between them to maximise the species either car sees.
