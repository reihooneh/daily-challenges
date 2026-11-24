"""python -m changeplot SHOW.json [--dressers N]"""

from __future__ import annotations

import argparse
import os
import sys

from .plot import MAX_BYTES, Show, ShowError, assign, load


def clock(t: float) -> str:
    t = round(t)
    return f"{t // 60}:{t % 60:02d}"


def span(t: float) -> str:
    sign = "-" if t < 0 else ""
    t = abs(round(t))
    return f"{sign}{t // 60}:{t % 60:02d}" if t >= 60 else f"{sign}{t} s"


def report(show: Show, dressers: int | None) -> str:
    out = [f"{show.title}: {len(show.scenes)} scenes, {len(show.actors)} actors, {len(show.changes)} costume changes", ""]
    impossible = [c for c in show.changes if not c.possible]
    out.append(f"{'actor':<8}{'from':<12}{'to':<12}{'off at':>7}{'window':>8}{'takes':>7}{'spare':>7}  ")
    for c in show.changes:
        flag = "IMPOSSIBLE" if not c.possible else ("quick" if c.quick else "")
        out.append(
            f"{c.actor:<8}{c.before:<12}{c.after:<12}{clock(c.exit):>7}{span(c.window):>8}{span(c.takes):>7}"
            f"{span(c.spare):>7}  {flag}"
        )
    out.append("")
    for c in impossible:
        under = c.before in show.costumes[c.after][1]
        fix = (
            "lengthen the gap or cut the change"
            if under
            else f"pre-set the {c.after} in the {c.wing} wing, underdress it, or lengthen the gap"
        )
        out.append(
            f'! {c.actor} can\'t get from {c.before} into {c.after} between "{c.scene_out}" and '
            f'"{c.scene_in}": {span(-c.spare)} short even with a dresser. To fix: {fix}.'
        )
    need = [c for c in show.changes if c.quick and c.possible]
    if not need:
        out.append("No quick changes: every actor can change on their own.")
        return "\n".join(out)
    rotas, proven = assign(show, need)
    out.append(
        f"Quick changes need {len(rotas)} dresser{'s' if len(rotas) > 1 else ''}"
        f"{'' if proven else ' (the search stopped early: this may not be the fewest)'}"
        f"{', and no fewer can cover them' if proven and len(rotas) > 1 else ''}:"
    )
    for i, rota in enumerate(rotas, 1):
        jobs = ", ".join(f"{clock(c.exit)} {c.actor} {c.wing}" for c in sorted(rota, key=lambda c: c.exit))
        out.append(f"  Dresser {i}: {jobs}")
    if dressers is not None and dressers < len(rotas):
        out.append(f"\nWith {dressers} dresser{'s' if dressers != 1 else ''} you're {len(rotas) - dressers} short.")
    return "\n".join(out)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="changeplot", description="Finds a show's quick changes and plans the dressers.")
    ap.add_argument("show", help="the show as JSON")
    ap.add_argument("--dressers", type=int, help="how many dressers you have")
    a = ap.parse_args(argv)
    try:
        if a.dressers is not None and not 0 <= a.dressers <= 50:
            raise ShowError("--dressers must be between 0 and 50")
        if not os.path.isfile(a.show) or os.path.getsize(a.show) > MAX_BYTES:
            raise ShowError("the show must be a regular file under 256 KB")
        with open(a.show, encoding="utf-8") as f:
            show = load(f.read())
        print(report(show, a.dressers))
        return 0
    except (ShowError, UnicodeDecodeError) as e:
        print(f"changeplot: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
