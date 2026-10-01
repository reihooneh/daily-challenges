# Huewise 🎨

**A linter for colour-blind safety: finds the colour pairs that break, and fixes them.**

About 1 in 12 men and 1 in 200 women have a colour vision deficiency. A red "error" badge and a green "success" badge can look like the same colour to them. Huewise checks a palette (or a CSS file) and reports exactly which pairs collide, shows how those colours are actually seen, and suggests the smallest change that fixes it.

## What makes it different

Colour-blindness *simulators* already exist: they show you a filtered picture and leave the judging to you. Huewise works like a code linter instead:

- It reports **collisions**: pairs that are clearly different to typical vision but nearly identical under a deficiency. Colours that look similar to everyone are ignored, because that's a design choice, not an accessibility bug.
- It **repairs** them, changing only lightness (which every type of colour blindness still perceives) so the hue stays recognisable.
- It **verifies its own repair** by re-auditing the fixed palette before claiming it works.
- It exits with code `1` on collisions, so it can fail a build in CI just like a failing test.

## Features

- Checks protanopia, deuteranopia and tritanopia using the Machado et al. (2009) model
- Reads colours from the command line or straight from a **CSS file**
- Measures difference in CIE Lab, a colour space built to match human perception
- `--contrast` mode for WCAG text contrast (AA / AAA)
- `--json` output for scripts, coloured swatches in a real terminal
- Standard library only: no dependencies to install or trust

## Example

The default red and green of Python's most popular charting library:

```text
$ huewise "#d62728" "#2ca02c" "#1f77b4" "#ff7f0e"
Huewise checked 4 colours against protanopia, deuteranopia, tritanopia.

✗ 2 collisions:

  #d62728  vs  #2ca02c
    typical vision: clearly different (ΔE 119.8)
    deuteranopia: nearly identical (ΔE 7.3), seen as #8b7c1f and #968838
    fix: change #2ca02c to #51be49 (same hue, different lightness)

  #2ca02c  vs  #ff7f0e
    typical vision: clearly different (ΔE 100.6)
    protanopia: nearly identical (ΔE 4.6), seen as #a39119 and #a59100
    fix: already solved by changing #2ca02c to #51be49

Repaired palette: #d62728 #51be49 #1f77b4 #ff7f0e
Re-checked: the repaired palette has no collisions.
```

A stylesheet, and a contrast check:

```text
$ huewise --css styles.css
$ huewise --contrast "#767676" "#ffffff"
Contrast 4.54:1 — WCAG AA
```

The Okabe-Ito palette, the scientific standard for colour-blind-safe charts, passes with no collisions.

## Tech

Python 3.10+, standard library only. Tests use `unittest`. Checked with `ruff` (including its security rules) and `bandit`.

## Install and run

```bash
cd 2026/10-october/02-huewise
PYTHONPATH=src python3 -m huewise "#d62728" "#2ca02c"
# or install the `huewise` command:
pip install .
```

| Exit code | Meaning |
|---|---|
| `0` | No collisions |
| `1` | Collisions found |
| `2` | Invalid input |

## Tests

```bash
PYTHONPATH=src python3 -m unittest discover -s tests
```

29 tests cover colour parsing, Lab round-trips, WCAG reference values, the simulation (greys must stay grey; red and green must merge), collision detection, verified repairs, CSS extraction and hostile inputs.

## Security

Huewise reads untrusted text (colour strings and CSS files), so it is built defensively:

- **Strict input validation:** a colour must match `#rgb` or `#rrggbb` exactly. Anything else is rejected, including shell fragments, script tags and paths.
- **Bounded work:** CSS files over 1 MB are refused and palettes are capped at 64 colours, so a huge input can't exhaust memory or time.
- **No regex denial of service:** the patterns have no nested repetition, and a test feeds them pathological input to prove they stay fast.
- **Nothing dangerous in reach:** no `eval`, no shell commands, no network, no file writes. It only reads the one file you name.
- **Safe failure:** invalid UTF-8 and binary files are handled without crashing, and error messages never echo large or raw input back.
- **No dependencies,** so there is no supply chain to attack.

**Known limits:** this is a simulation of the most common *complete* deficiencies. Real vision varies from person to person, so treat a pass as strong evidence, not a guarantee, and still avoid relying on colour alone (add icons or labels). No software can promise it is 100% secure; these are the protections in place.
