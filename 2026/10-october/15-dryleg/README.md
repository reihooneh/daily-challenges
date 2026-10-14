# Dryleg

**Plans how much water to carry on each stretch of a hot-day hike, without counting on springs that might be dry, and finds the start time that keeps your load lightest.**

Language: Perl 5 (core modules only) · Field: outdoor safety / simulation · Day: 15 October 2026

Water calculators give you one number: "about half a litre to a litre an hour". Real routes have a tank at the start, a spring that's dry by December, a creek that's sometimes a puddle, and a long exposed ridge in the afternoon heat. What you need to know is: **at each source I can actually trust, how much should I fill up?** And how much would starting earlier, in the cool, change that?

Dryleg walks your route minute by minute. It uses Naismith's rule for time, adds up water use as the day's temperature rises and falls, and plans each fill-up to reach the next source you can count on. Seasonal and unreliable sources are treated as a bonus, not a plan. Then it tries every start time from first light and tells you which one makes the heaviest carry lightest.

## Quick start

```bash
perl bin/dryleg examples/ridge-walk.txt
prove -l t/            # tests
```

```
DRYLEG  ridge-walk.txt  (Ironbark Ridge (sample route): 27.5 km, +1130 m, 16 to 34 °C)

Leave 09:00, arrive at Camp about 17:46 (8h46 walking).

  Fill up at        Carry   To reach         Walk   Heat
  Trailhead tank    5.2 L   Hut tank         4h57   21 to 33 °C   << more than you can carry
                            passes Fern Gully spring (seasonal): a bonus if it's flowing, not counted on
  Hut tank          5.5 L   Camp             3h49   33 to 34 °C   << more than you can carry
                            passes Creek crossing (unreliable): a bonus if it's flowing, not counted on

Heaviest carry 5.5 L (you can carry 5.0 L; both include the 0.5 L you keep spare).
You will drink about 9.8 L over the whole walk.

WARNINGS
  - You can't carry enough for the longest dry stretch. Start in the cooler hours, cache water beforehand, carry more bottles, or shorten the day.

Better: leave at 05:50. The heaviest carry drops to 4.9 L (0.6 L lighter) and you arrive about 14:36.
```

## The route file

```
trail Ironbark Ridge
start-time 09:00          # optional: without it, Dryleg plans from the best start
temp 16 34                # the night's low and the afternoon's high, °C
light 05:50               # first light (earliest start Dryleg will suggest)
dark 19:40                # last light
pace 4.0                  # km/h on the flat
capacity 5.0              # litres you can carry
reserve 0.5               # litres you always keep spare
trust reliable            # or: seasonal, to count on seasonal sources too

water Trailhead tank      0.0           reliable
point Lookout             4.5   +380              # km from the start, metres climbed since the last place
water Fern Gully spring   8.0   -210    seasonal
end   Camp               27.5   -300
```

Exit codes: `0` the plan works, `1` you can't carry enough or you'd finish after dark, `2` bad input.

## Security

- **Bounded input:** at most 16 KB, 200 characters a line and 60 places, and every number has a range. Reading stops at the limit, so `/dev/zero` is refused, and only regular files are opened. The file must be valid UTF-8, decoded strictly.
- **Strict text:** names must match an allow-list. Control characters, terminal escape codes and invisible bidirectional characters are refused, so nothing printed can hijack your terminal. Errors give a line number and never repeat the input, and the file name is cleaned before printing.
- **No code from data:** nothing from the file reaches `eval`, `system`, backticks or a shell. Two-argument `open` is never used on a user path.
- **Bounded work:** the simulation is a fixed number of one-minute steps for 60 places, and the start-time search tries at most 53 start times.
- **No dependencies:** only Perl's core modules. The tests also run with warnings enabled (`prove -lw`).

**Known limits:** this is a planning aid built on rules of thumb (Naismith's rule, about half a litre an hour plus more in the heat). It ignores rest stops, wind, humidity and personal differences. **Drink to thirst, never ration, and carry more than the plan on hot days.**
