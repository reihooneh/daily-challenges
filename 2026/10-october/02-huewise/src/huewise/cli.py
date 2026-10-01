"""Command-line interface for Huewise.

Exit codes: 0 = palette is safe, 1 = collisions found, 2 = bad input.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import TextIO

from . import __version__
from .audit import MAX_COLORS, Report, audit, repaired_palette
from .color import ColorError, contrast_ratio, parse_hex, to_hex
from .cvd import KINDS, simulate

MAX_CSS_BYTES = 1_000_000

# Innermost { ... } blocks, then hex colours inside declaration values. Both
# patterns use simple character classes with no nested repetition, so they run
# in linear time even on hostile input (no "regex denial of service").
_BLOCK = re.compile(r"\{([^{}]*)\}")
_VALUE = re.compile(r":([^;{}]*)")
_HEX_IN_VALUE = re.compile(r"#(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{3})(?![0-9a-fA-F])")


class InputError(Exception):
    """A problem with what the user gave us; shown without a traceback."""


def extract_css_colors(css: str) -> list[str]:
    """Pull unique hex colours out of CSS declarations, in first-seen order.

    Only looks inside `{ }` blocks and after a `:`, so an id selector such as
    `#add` or `#fed` is not mistaken for a colour.
    """
    seen: dict[str, None] = {}
    for block in _BLOCK.finditer(css):
        for value in _VALUE.finditer(block.group(1)):
            for match in _HEX_IN_VALUE.finditer(value.group(1)):
                seen.setdefault(normalize(match.group(0)), None)
    return list(seen)


def normalize(hex_color: str) -> str:
    """Lowercase and expand #abc to #aabbcc so duplicates collapse."""
    h = hex_color.lower()
    return "#" + "".join(ch * 2 for ch in h[1:]) if len(h) == 4 else h


def read_css(path_text: str) -> str:
    path = Path(path_text)
    if not path.is_file():
        raise InputError(f"{path_text}: not a file")
    if path.stat().st_size > MAX_CSS_BYTES:
        raise InputError(f"{path_text}: larger than {MAX_CSS_BYTES // 1000} kB; refusing to read it")
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError as exc:
        raise InputError(f"{path_text}: {exc.strerror}") from exc


def swatch(hex_color: str, enabled: bool) -> str:
    """A small coloured block using 24-bit ANSI colour, if the terminal allows."""
    if not enabled:
        return ""
    r, g, b = (round(c * 255) for c in parse_hex(hex_color))
    return f"\x1b[48;2;{r};{g};{b}m  \x1b[0m "


def render(report: Report, out: TextIO, color: bool) -> None:
    out.write(f"Huewise checked {len(report.colors)} colours against {', '.join(KINDS)}.\n\n")
    if report.ok:
        out.write("✓ No collisions: every clearly different pair stays different.\n")
        return
    out.write(f"✗ {len(report.collisions)} collision{'s' if len(report.collisions) != 1 else ''}:\n\n")
    for c in report.collisions:
        sim_a = _sim_hex(c.a, c.kind)
        sim_b = _sim_hex(c.b, c.kind)
        out.write(
            f"  {swatch(c.a, color)}{c.a}  vs  {swatch(c.b, color)}{c.b}\n"
            f"    typical vision: clearly different (ΔE {c.normal})\n"
            f"    {c.kind}: nearly identical (ΔE {c.simulated}), seen as "
            f"{swatch(sim_a, color)}{sim_a} and {swatch(sim_b, color)}{sim_b}\n"
        )
        if c.b in report.fixes:
            fix = report.fixes[c.b]
            out.write(f"    fix: change {c.b} to {swatch(fix, color)}{fix} (same hue, different lightness)\n")
        elif c.a in report.fixes:
            out.write(f"    fix: already solved by changing {c.a} to {report.fixes[c.a]}\n")
        out.write("\n")
    if report.fixes:
        out.write("Repaired palette: " + " ".join(repaired_palette(report)) + "\n")
    if report.remaining:
        out.write(
            f"{report.remaining} collision{'s' if report.remaining != 1 else ''} cannot be fixed by "
            "lightness alone; choose a different hue for one colour in each pair.\n"
        )
    elif report.fixes:
        out.write("Re-checked: the repaired palette has no collisions.\n")


def _sim_hex(hex_color: str, kind: str) -> str:
    return to_hex(simulate(parse_hex(hex_color), kind))


def to_json(report: Report) -> str:
    return json.dumps(
        {
            "colors": report.colors,
            "ok": report.ok,
            "collisions": [vars(c) for c in report.collisions],
            "fixes": report.fixes,
            "repaired_palette": repaired_palette(report),
            "remaining_after_fixes": report.remaining,
        },
        indent=2,
    )


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="huewise",
        description="Find colours that collide for colour-blind viewers, and suggest fixes.",
    )
    p.add_argument("colors", nargs="*", metavar="COLOR", help="hex colours such as #d62728 or #abc")
    p.add_argument("--css", metavar="FILE", help="read colours from a CSS file instead")
    p.add_argument("--json", action="store_true", help="machine-readable output")
    p.add_argument("--contrast", nargs=2, metavar=("FG", "BG"), help="print the WCAG contrast ratio of two colours")
    p.add_argument("--no-color", action="store_true", help="do not print coloured swatches")
    p.add_argument("--version", action="version", version=f"huewise {__version__}")
    return p


def run(argv: list[str], out: TextIO, err: TextIO) -> int:
    parser = build_parser()
    try:
        args = parser.parse_args(argv)
    except SystemExit as exc:  # argparse exits on --help or bad flags
        return int(exc.code or 0)

    try:
        if args.contrast:
            fg, bg = (parse_hex(c) for c in args.contrast)
            ratio = contrast_ratio(fg, bg)
            grade = "AAA" if ratio >= 7 else "AA" if ratio >= 4.5 else "AA (large text only)" if ratio >= 3 else "fail"
            out.write(f"Contrast {ratio:.2f}:1 — WCAG {grade}\n")
            return 0

        if args.css and args.colors:
            raise InputError("give colours or --css, not both")
        raw = extract_css_colors(read_css(args.css)) if args.css else [normalize_checked(c) for c in args.colors]
        raw = list(dict.fromkeys(raw))  # drop duplicates, keep order
        if len(raw) < 2:
            raise InputError("need at least two colours to compare")
        if len(raw) > MAX_COLORS:
            raise InputError(f"found {len(raw)} colours; the limit is {MAX_COLORS}")

        report = audit(raw, [parse_hex(c) for c in raw])
    except (InputError, ColorError) as exc:
        err.write(f"huewise: {exc}\n")
        return 2

    if args.json:
        out.write(to_json(report) + "\n")
    else:
        use_color = not args.no_color and getattr(out, "isatty", lambda: False)()
        render(report, out, use_color)
    return 0 if report.ok else 1


def normalize_checked(text: str) -> str:
    parse_hex(text)  # raises ColorError with a helpful message if invalid
    return normalize(text)


def main() -> None:
    sys.exit(run(sys.argv[1:], sys.stdout, sys.stderr))
