"""Plain-text output: a small map of the screen and the written report."""

from __future__ import annotations

from reachmap.analysis import Report, reach_zone
from reachmap.layout import Element, Layout

COLUMNS = 26
ZONE_SHADE = {"easy": " ", "stretch": ".", "hard": ":"}


def screen_map(layout: Layout, report: Report, hand: str) -> str:
    rows = max(8, round(COLUMNS * layout.height / layout.width / 2))  # characters are about twice as tall as wide
    cell_w, cell_h = layout.width / COLUMNS, layout.height / rows
    grid = []
    for r in range(rows):
        line = []
        for c in range(COLUMNS):
            probe_x, probe_y = (c + 0.5) * cell_w, (r + 0.5) * cell_h
            mark = " "
            if layout.device == "phone":
                spot = Element("p", "p", probe_x, probe_y, 0.001, 0.001)
                mark = ZONE_SHADE[reach_zone(layout, spot, hand)]
            line.append(mark)
        grid.append(line)

    legend = []
    for number, element in enumerate(layout.elements.values()):
        symbol = chr(ord("A") + number) if number < 26 else "#"
        legend.append(f"  {symbol}  {element.label}  ({report.zones[element.id]})")
        for r in range(rows):
            for c in range(COLUMNS):
                x0, y0 = c * cell_w, r * cell_h
                if (
                    x0 < element.x + element.w
                    and x0 + cell_w > element.x
                    and y0 < element.y + element.h
                    and y0 + cell_h > element.y
                ):
                    grid[r][c] = symbol

    border = "+" + "-" * COLUMNS + "+"
    lines = [border, *("|" + "".join(row) + "|" for row in grid), border]
    if layout.device == "phone":
        lines.append(f"  blank = easy reach   . = stretch   : = hard  ({hand} thumb)")
    return "\n".join([*lines, "", *legend])


def text_report(layout: Layout, report: Report, hand: str) -> str:
    out = [screen_map(layout, report, hand), ""]
    if report.tasks:
        out.append("Tasks, busiest first (Fitts's law estimate; compare them with each other, not with a stopwatch):")
        for task in sorted(report.tasks, key=lambda t: -t.seconds * t.per_day):
            slow = task.slowest
            out.append(
                f"  {task.name:<22} {task.seconds:5.2f} s  {f'x {task.per_day:g}/day':<11} "
                f"slowest step: '{layout.elements[slow.target].label}' ({slow.bits:.1f} bits)"
            )
        out.append("")
    if report.problems:
        out.append(f"{len(report.problems)} problem{'s' if len(report.problems) != 1 else ''}:")
        out.extend(f"  - {problem}" for problem in report.problems)
    else:
        out.append("No problems found: targets are big enough, well spaced, and the busy ones are within reach.")
    return "\n".join(out) + "\n"
