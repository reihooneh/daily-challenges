# How Dryleg works

A walkthrough so you can explain every part of it.

## 1. The big picture

```
 route.txt ──▶ Route::parse_route()   settings and places, strictly checked
                    │
                    ▼
               Plan::walk(start)      for each leg: Naismith time, then minute by minute:
                    │                 temperature at that moment → litres per hour → litres
                    ▼
               Plan::plan(start)      group legs between sources you can count on;
                    │                 each fill-up = water to the next one + your reserve
                    ▼
               Plan::best_start()     try every start from first light to 13:00
                    │
                    ▼
               Report::render()       fill-up table, warnings, a better start time
```

## 2. File tour

| File | Job |
|---|---|
| `lib/Dryleg/Route.pm` | The route format: settings, places, limits, clear errors |
| `lib/Dryleg/Plan.pm` | Temperature curve, drinking rate, the walk, the carry plan, the best start |
| `lib/Dryleg/Report.pm` | The text report |
| `lib/Dryleg/CLI.pm` | Command line: bounded reading, strict UTF-8, safe file name, exit codes |
| `bin/dryleg` | A three-line launcher |
| `t/dryleg.t` | 9 groups of tests (Test::More) |

## 3. Key ideas

### Time: Naismith's rule
A Scottish mountaineer's rule from 1892 that's still used: walking time = distance ÷ pace, **plus one hour for every 600 m of climbing**. It's simple, well known and close enough for planning.

### Temperature through the day
The day's low comes around dawn (06:00) and the high mid-afternoon (15:00). Between them, Dryleg uses half a cosine wave, so the rise is slow at first, fastest mid-morning and gentle again near the peak, which is roughly what thermometers show. From the high, a slower half-cosine brings it back down to the next dawn. The tests check that it hits the low and the high exactly, only rises in the morning, and joins up smoothly at midnight.

### Water: adding it up minute by minute
The drinking rate depends on the temperature: about **0.5 L an hour up to 20 °C, plus 0.06 L an hour for each degree above**, capped at 1.5 L an hour (about the most the body can absorb). Because the temperature changes as you walk, Dryleg steps through each leg one minute at a time, looks up the temperature at the middle of that minute, and adds up the water. That's a numerical integral (the midpoint rule).

### Planning fill-ups you can trust
The start always counts, and so does every `reliable` source; `seasonal` ones count only if you say `trust seasonal`. `unreliable` ones never count. The legs are grouped between trusted sources. Each fill-up is the water for its group **plus your reserve**, and any untrusted sources passed along the way are listed as a bonus. This is the important safety idea: **never plan on water you might not find.**

### The best start time
Starting earlier means walking the exposed parts in the cool. Dryleg simply tries every quarter-hour from first light to 13:00 and picks the start that:
1. finishes before dark (if any start can), then
2. has the lightest heaviest carry (what your back actually feels), then
3. uses the least water in total, and
4. among equals, starts latest (more sleep).

That's at most 53 tries (usually about 30), each a few thousand minute-steps, which is instant. When the search is this small, brute force is the right tool: simple, and obviously correct.

## 4. Glossary

| Term | Plain version |
|---|---|
| Naismith's rule | Walking time from distance and climb |
| Reserve | Water you never plan to drink, kept for emergencies |
| Seasonal source | Flows at some times of year, not others |
| Midpoint rule | Add up a changing rate by sampling it in the middle of each small step |

### Perl features you met here
- **Modules and `Exporter`**: `Dryleg::Route` etc. export only the functions others need (`@EXPORT_OK`).
- **References and data structures:** routes are hashes of arrays of hashes (`$r->{points}[-1]{km}`).
- **`qr//`** precompiled regexes, `\p{L}` Unicode classes and `\A`/`\z` anchors.
- **`die` and `eval`** for errors. Messages start with `Dryleg::Error:`, so the CLI can tell bad input (exit 2) from a real bug.
- **In-memory filehandles** (`open my $fh, '<', \$string`) so the tests can feed the CLI without files.
- **Strict decoding** with `Encode::decode('UTF-8', $bytes, FB_CROAK)`.

## 5. Interview questions you might get

**Q: Why step minute by minute instead of using an average temperature?**
A: Water use isn't linear in temperature: it's flat up to 20 °C and capped at the top. So the average of the rates isn't the rate at the average temperature. Stepping through the day and summing (a midpoint-rule integral) handles that correctly, and with steps of one minute the error is negligible.

**Q: How do you keep a plan safe if a spring is dry?**
A: Each fill-up only counts on sources you trust. By default that's the start and reliable sources. Seasonal and unreliable ones are listed as "a bonus, not counted on", so each fill-up already covers walking straight past them. That's the conservative choice for safety-critical planning: being wrong in the safe direction costs some weight, being wrong the other way can cost a lot more.

**Q: Why brute force for the start time?**
A: There are at most 53 candidate starts and each simulation is milliseconds, so trying them all is instant, easy to test, and certainly finds the best. An optimiser would add complexity for no gain.

## 6. Ideas to extend it

1. **Use a forecast:** read hourly temperatures from a weather service instead of a low and a high.
2. **GPX import:** read the route and climbs from a GPX track, with water sources as waypoints.
3. **Rest stops and shade:** model breaks, which use less water, and shaded stretches.
