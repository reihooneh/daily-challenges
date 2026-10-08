# How Reachmap works

A friendly walkthrough so you can explain every part of it.

## 1. The big picture

```
 layout.json ──▶ layout.py ──▶ a checked Layout (elements + tasks)
                                    │
                                    ▼
                              analysis.py
                     ┌──────────────┼───────────────┐
                     ▼              ▼               ▼
               task times      reach zones      problems
               (Fitts's law)   (thumb model)    (size, gaps, overlap,
                                                 busy-but-hard)
                     └──────────────┼───────────────┘
                                    ▼
                               render.py ──▶ map + table + list
                                    │
                                 cli.py ──▶ exit code 0 / 1 / 2
```

Nothing is drawn on a real screen. A layout is just rectangles, and every question Reachmap asks ("how far?", "how wide?", "do these touch?") is geometry on those rectangles.

## 2. File tour

| File | Job |
|---|---|
| `src/reachmap/layout.py` | Reads the JSON strictly and turns it into `Element`, `Task` and `Layout` objects, or one clear `LayoutError` |
| `src/reachmap/analysis.py` | The human-factors models (Fitts's law, touch sizes, thumb reach) and the checks |
| `src/reachmap/render.py` | The text map of the screen, the task table and the problem list |
| `src/reachmap/cli.py` | Command line: reads at most 100 KB, picks the exit code, keeps errors to one line |
| `examples/chat-app.json` | A chat screen with deliberate mistakes |
| `tests/test_reachmap.py` | 27 tests |

## 3. Key ideas

### Fitts's law
In 1954 Paul Fitts showed that the time to point at something depends on how far away it is (D) and how big it is (W), and only through their ratio:

```
time = a + b × log2(D / W + 1)
```

The `log2(...)` part is the **index of difficulty**, measured in bits. Doubling the distance adds about one bit; doubling the size removes about one. `a` and `b` depend on the person and the device (a thumb is not a mouse), which is why the README says to compare times with each other rather than trust them as stopwatch readings.

### Width depends on direction
Imagine a long, flat search bar. Coming at it sideways, you have its whole length to land on. Coming from below, only its thin height. So `effective_width` draws a line through the button's centre in the direction of travel and measures how much of that line lies inside the rectangle: `min(w / cos θ, h / sin θ)`. Straight sideways gives `w`, straight up gives `h`, and at 45° on a square of side s it gives s√2, the diagonal. There is a test for each.

### Tasks chain together
A task like "Send a reply" is a list of taps. The thumb starts at a resting point (three-quarters across and near the bottom for a right hand), moves to the first target, and each later step starts from where the last one finished. The task time is the sum of the steps, and the step with the most bits is reported as the slowest.

### The thumb model
Holding a phone in one hand, the thumb swings around a pivot near the bottom corner on that side. Reachmap measures each element's distance from that pivot as a share of the screen height:

| Share of height | Zone |
|---|---|
| up to 0.55 | easy |
| up to 0.75 | stretch |
| more | hard (needs a regrip or the other hand) |

That is why the map's shading is a curve, not straight bands. For a left hand the pivot moves to the other corner, which is just a mirror image (and a test checks exactly that).

### The checks
1. **Too small:** under 44 × 44 on a phone (Apple's guideline; Google's is 48 dp) or 24 × 24 on a desktop.
2. **Too close:** on a phone, edges less than 8 apart. `gap_between` works out the horizontal and vertical gaps; if both are negative the rectangles overlap, otherwise the gap is the straight-line distance between the nearest corners or edges (a 3-4-5 triangle in the tests).
3. **Overlap:** two targets sharing space means one tap could mean either.
4. **Busy but hard:** every task adds its `per_day` to each element it taps. An element tapped 5 or more times a day that sits in the hard zone is flagged. This is the check that turns a pile of warnings into priorities.

### Strict parsing (`layout.py`)
Python's `json` module is forgiving in ways that matter here: it accepts `NaN`, lets a later duplicate key silently win, and treats `true` as the number 1. Reachmap hooks into the parser to refuse the first two (`parse_constant`, `object_pairs_hook`) and checks types itself for the third. Anything not on the allow-list (unknown fields, odd characters in ids, elements off the screen) is an error with a location like `element 3.w`, never an echo of the bad text.

## 4. Glossary

| Term | Plain version |
|---|---|
| HCI | Human-computer interaction: studying how people use technology |
| Target | Anything you tap or click |
| Index of difficulty | How hard a target is to hit, in bits |
| Effective width | How big the target is along the path you approach it on |
| Touch target | The tappable area, which can be bigger than the icon you see |
| Point / dp | Device-independent units, so 44 means the same physical size on any phone |
| Lint | Automatically check something for likely mistakes |

### Python features you met here
- **`dataclasses`** for `Element`, `Task`, `Layout` and the reports, including `field(default_factory=dict)`.
- **`json.loads` hooks:** `object_pairs_hook` and `parse_constant`.
- **`re.fullmatch`** so an allow-list has to match the whole string, not just its start.
- **A `src/` layout** with `__main__.py`, so `python -m reachmap` works, plus a `[project.scripts]` entry for an installed `reachmap` command.
- **Subclassing `argparse.ArgumentParser`** to control how errors are printed.
- **Dependency injection for testing:** `main(argv, out, err)` writes to whatever streams it is given, so tests don't need to capture the real terminal.
- **`mypy --strict`, ruff and bandit** together: types, style and security checks.

## 5. Interview questions you might get

**Q: What is Fitts's law, and how did you apply it to a 2D screen?**
A: Movement time grows with log2(distance / width + 1). The original experiments were one-dimensional, so on a screen "width" is ambiguous. I used the width of the target measured along the direction of movement, which is one of the standard 2D extensions. It means a wide button is correctly rated easy from the side and harder from above.

**Q: The times are estimates. Why are they still useful?**
A: Because the constants affect every task the same way, the ranking of tasks and of alternative layouts is much more reliable than the absolute seconds. Reachmap is for finding the worst spots quickly and comparing designs, and the README says to confirm important decisions with real users.

**Q: Why refuse duplicate keys and NaN? They seem harmless.**
A: With a duplicate key, the file a person reads and the data the program uses can differ, which is how checks get quietly bypassed. NaN poisons every comparison: `NaN < 44` is false, so a NaN-sized button would pass the size check. Refusing them makes the input mean exactly one thing.

## 6. Ideas to extend it yourself

1. **Import from a real design:** read the frames from an exported design file or the rectangles from a web page, instead of writing JSON by hand.
2. **Suggest a fix:** search for a rearrangement of the busiest buttons that lowers the total daily time, then show the before and after.
3. **Measure your own constants:** build a small tapping game, time yourself, and fit `a` and `b` to your own thumb.
