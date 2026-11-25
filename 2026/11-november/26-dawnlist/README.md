# Dawnlist

**Plans a birding big day: which sites, in what order, and when, to expect the most species by dark.**

On a big day birders try to see as many species as they can between dawn and dusk. The hard part
isn't knowing the sites, it's the clock. A bittern calls at dawn and then goes quiet. The waders on
the mudflats only show within two hours of low tide. Raptors don't get up until the air warms. And
every drive between sites eats time. Dawnlist takes the sites you could visit, the drives between
them and your chance of seeing each bird at each site and time of day. It finds the order and timing
that expects the most species, waiting for a window to open when that's worth it.

## Features

- **Expected species, counted properly.** A bird you might see at two sites counts once. At each
  site, the chance you still need it is multiplied by your chance of missing it there.
- **Time-of-day windows.** A bird can have a better chance in a window (dawn chorus, low tide, dusk)
  and a lower one outside it. The planner can arrive and wait for the window to open.
- **The best order and timing, found exactly.** It uses a depth-first search with a bound on what the
  rest of the day could still add. The tests check, on 40 random days, that the bound never cuts
  off the best answer.
- A comparison with the obvious plan (always the stop with the most species per minute), what each
  stop adds to the day, the birds this route gives no chance at, and the long shots.

## Example

```
$ bin/dawnlist examples/spring-day.txt
Dawnlist: 8 sites, 44 species, 05:00 to 12:00 from home

Expected species: 20.6 of 44 (the best possible order and timing, 7955 partial routes weighed)

  05:15-06:05  Reedy lagoon            15 min drive               +4.6 species
  06:25-07:25  Coastal heath           20 min drive               +3.9 species
  08:00-09:00  Ironbark woodland       35 min drive               +3.3 species
  09:15-09:45  Farm dam                15 min drive               +2.1 species
  10:20-11:05  Tidal mudflats          35 min drive               +4.1 species
  11:20-12:00  Airport grassland       15 min drive               +2.5 species

The stop with the most species per minute, every time, would expect 19.3.

What each stop adds to the day (the plan without it):
  Reedy lagoon           3.4 species
  Coastal heath          3.9 species
  Ironbark woodland      3.3 species
  Farm dam               2.1 species
  Tidal mudflats         4.1 species
  Airport grassland      2.5 species

No chance on this route (no stop has them at those times): Superb Lyrebird, Green Catbird, Wonga
  Pigeon, Eastern Yellow Robin, Large-billed Scrubwren, Pilotbird, Australasian Gannet,
  Short-tailed Shearwater, White-bellied Sea-Eagle, Sooty Oystercatcher, Peregrine Falcon,
  Southern Boobook.

Long shots on this route:
  Stubble Quail              10% chance
  Beautiful Firetail         35% chance
  Rose Robin                 40% chance
  Brown Falcon               45% chance
  Speckled Warbler           45% chance

4 species are 90% likely or better.
```

With only a morning, the best plan skips the rainforest gully: it's rich, but it's a 70-minute stop
a long drive from everything else. It also saves the mudflats for low tide. A day file looks like this:

```
start home 05:00
end 12:00
site lagoon 50 Reedy lagoon                       id, minutes you'll bird there, name
travel home lagoon 15                             minutes between two places, both ways
bird lagoon 0.55 05:00-07:00 Australasian Bittern a better chance in a window
bird lagoon 0.1 Australasian Bittern              the chance at other times
```

The chances in the example are made up. In real life they come from your own notes, or from how
often a species turns up on past checklists for that site.

## Run and test

```sh
bin/dawnlist examples/spring-day.txt
bin/dawnlist - < day.txt            # or read the day from standard input
tests/run.sh                        # hand-worked days, pruned vs full search, the example, hostile input
shellcheck bin/dawnlist tests/run.sh
```

It needs only Bash 4+, awk (mawk or gawk) and coreutils `timeout`.

## Security

- **Safe file reading.** The day file must be a regular file (not a link, folder or device) and is
  read up to 64 KB. Larger files are refused, and the path is never printed back.
- **Nothing is ever executed.** awk only parses the text: there's no `eval` and no `source`, and
  nothing from the file reaches a shell. A bird called `$(reboot)` is refused as a bad name.
- **Strict format checks.** Every line must match a known form. Ids, names, clock times, minutes
  (5–480 at a site, 1–600 driving) and chances (above 0 and at most 1, three decimals, no exponents)
  are all checked. Control characters, including terminal escape codes, are refused, so they can
  never reach your terminal.
- **Bounded work.** At most 12 sites, 120 species, 600 bird lines and 200 travel lines are
  accepted. The search stops after 150,000 partial routes (adjustable with `--budget`), and the whole
  run after 60 seconds. If the search stops early, the plan is still valid, it's never worse than
  the species-per-minute plan, and the report says it may not be the best.
- **Known limits.** Chances are treated as independent between sites. The chance used is the one when
  the visit starts. Drive times don't change with traffic. The plan is only as good as the
  chances you give it.
