# How Huewise works

A friendly walkthrough so you can explain every part of it.

## 1. The big picture

```
"#d62728"  ──parse──▶  sRGB  ──remove gamma──▶  linear RGB
                                                    │
                              apply a 3×3 "missing cone" matrix
                                                    ▼
                           what a colour-blind person sees  ──▶  CIE Lab
                                                                    │
                    compare every pair: far apart normally, close now?  ──▶  COLLISION
                                                                    │
                          nudge lightness until safe, then re-audit  ──▶  FIX
```

## 2. File tour

| File | Job |
|---|---|
| `color.py` | Parses hex colours and converts between sRGB, linear RGB and Lab. Also WCAG contrast. Pure maths. |
| `cvd.py` | The three colour-blindness matrices and `simulate()`. |
| `audit.py` | Finds collisions, suggests fixes, and verifies them. |
| `cli.py` | Reads arguments or a CSS file, prints the report, sets the exit code. |
| `tests/` | 29 tests, one file per module. |

### `color.py`: three colour spaces
- **sRGB** is what a hex code stores. It is *gamma-encoded*: the numbers are bent so more of them describe dark shades, where our eyes are more sensitive.
- **Linear RGB** is real light intensity. You must convert to this before mixing or transforming colours, or the maths gives wrong answers. That's what `srgb_to_linear` does.
- **CIE Lab** rearranges colour so that the straight-line distance between two colours roughly matches how different they *look*. That distance is called **ΔE** ("delta E"). Under 2 is invisible, about 10 is "similar", 20+ is clearly different.

### `cvd.py`: simulating colour blindness
Eyes have three kinds of colour sensors (cones). With deuteranopia the "green" cones are missing, so red and green send almost the same signal to the brain. Researchers (Machado et al., 2009) worked out a 3×3 matrix for each type: multiply a colour by it and you get the colour that person sees. Each row of every matrix adds up to 1, which is why greys stay grey.

### `audit.py`: the linter logic
- **Collision rule:** ΔE ≥ 20 for typical vision **and** ΔE < 10 under some deficiency. The first half matters: two similar blues aren't a colour-blindness bug.
- **Repair:** lightness is the one thing all three deficiencies still see. So `suggest_fix` keeps the hue (Lab's `a` and `b`) and moves lightness (`L`) one step at a time, up and down, taking the first value that is safe against *every* other colour under *every* deficiency. Searching outward from the original means the first answer found is also the smallest change.
- **Verification:** after fixing, it audits the repaired palette again and reports how many collisions remain. A tool should never claim a fix it hasn't checked.

### `cli.py`: input, output and safety
Reads colours from arguments or a CSS file. For CSS it only looks inside `{ }` blocks and after a `:`, so an id selector like `#add` isn't mistaken for a colour. The program lives in `run(argv, out, err)` so tests can call it directly and capture what it prints.

## 3. Key concepts

| Concept | Plain version |
|---|---|
| Gamma | Hex numbers are bent to suit our eyes; undo that before doing maths |
| ΔE | A single number for "how different do two colours look?" |
| Collision | Different for most people, the same for colour-blind people |
| WCAG contrast ratio | 1 to 21; body text needs at least 4.5 |
| ReDoS | A badly written regex can take years on a crafted input, freezing a program |

### Python features you met here
- **`NamedTuple`** (`RGB`): a tuple with named fields, so `rgb.r` works and it still unpacks like `r, g, b = rgb`.
- **`@dataclass`**: classes for holding data without writing `__init__` by hand. `frozen=True` makes `Collision` unchangeable.
- **`itertools.combinations`**: every unordered pair, without writing two nested loops.
- **`zip(..., strict=True)`**: raises an error if two lists differ in length instead of silently dropping values.
- **`dict.fromkeys` / `setdefault`**: removing duplicates while keeping order.
- **Custom exceptions** (`ColorError`, `InputError`): expected problems become clean one-line messages, not tracebacks.

## 4. Interview questions you might get

**Q: How does your tool decide two colours "collide"?**
A: I convert both to CIE Lab and measure ΔE. A collision is a pair with ΔE of at least 20 for typical vision but under 10 after simulating a deficiency. The two thresholds mean I only flag pairs where colour blindness is the cause.

**Q: Why change lightness rather than hue when repairing?**
A: Lightness is perceived by all three types of colour blindness, so a lightness difference is the most reliable fix, and it keeps the brand colour recognisable. I search outward from the original value so the first safe result is the smallest change, then I re-run the audit to confirm it worked.

**Q: Your tool parses untrusted CSS. What could go wrong, and what did you do?**
A: Three things. Huge files could exhaust memory, so I cap file size and colour count. A crafted string could make a regex run for a very long time (ReDoS), so I use patterns with no nested repetition and a test that times them on hostile input. And malformed bytes could crash it, so I decode with replacement and reject anything that isn't an exact hex colour.

## 5. Ideas to extend it yourself

1. **More colour formats:** accept `rgb(214, 39, 40)` and named colours like `crimson`.
2. **Better colour difference:** swap CIE76 for CIEDE2000, which matches perception more closely.
3. **An HTML report** showing each pair side by side, as typical vision and each deficiency see it.
