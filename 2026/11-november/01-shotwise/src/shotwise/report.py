"""The call sheet: shots in order, who to call in before each, and who is free to go after it."""

from __future__ import annotations

import textwrap

from .parse import ShotList
from .plan import Plan, clock, evaluate, timing


def _names(sl: ShotList, people: list[int]) -> str:
    return ", ".join(sl.people[p] for p in sorted(people, key=lambda p: sl.people[p].casefold()))


def render(sl: ShotList, pl: Plan) -> str:
    order = pl.order
    tm = timing(sl, order)
    total = sum(sl.length(s) for s in order)
    listed, listed_broken, _ = evaluate(sl, list(range(len(sl.labels))))
    out = [
        f"SHOTWISE  {sl.title}",
        f"{len(order)} shots, {len(sl.people)} people, {total} minutes of photos.",
    ]
    if pl.violations:
        out.append("No order meets every arrival and leaving time. This is the closest found:")
        out += [f"  ! {v}" for v in pl.violations]
    elif pl.exact:
        out.append("This order keeps everyone waiting least (every order was checked).")
    else:
        out.append("The best order found by searching (too many shots to check every order).")
    out.append(f"Waiting: {pl.waiting} weighted person-minutes, against {listed} in the order as written.")
    out += [f"  As written: {v}." for v in listed_broken]
    out.append("")

    width = len(str(len(order)))
    pad = " " * (width + 8)
    for pos, s in enumerate(order):
        label = sl.labels[s] + (f" ({sl.length(s)} min)" if sl.lengths[s] is not None else "")
        out.append(f"{pos + 1:>{width}}. {clock(tm.starts[pos])}  {label}")
        joining = [p for p in sl.members[s] if tm.first[p] == pos]
        going = [p for p in sl.members[s] if tm.last[p] == pos and pos < len(order) - 1]
        for key, who in (("with", sl.members[s]), ("call in", joining), ("free to go", going)):
            if who:
                text = _names(sl, who) + (f" ({len(who)})" if key == "with" and len(who) > 4 else "")
                out += textwrap.wrap(text, 100, initial_indent=f"{pad}{key + ':':<12}", subsequent_indent=pad + " " * 12)
    out.append(f"{' ' * (width + 2)}{clock(total)}  done")

    waits = []
    for p, name in enumerate(sl.people):
        start = tm.starts[tm.first[p]]
        end = tm.starts[tm.last[p]] + sl.length(order[tm.last[p]])
        own = sum(sl.length(s) for s in order if p in sl.members[s])
        if end - start - own > 0:
            waits.append((end - start - own, name))
    if waits:
        waits.sort(key=lambda w: (-w[0], w[1].casefold()))
        out.append("")
        listed_waits = ", ".join(f"{name} {m} min" for m, name in waits[:8]) + ("" if len(waits) <= 8 else ", ...")
        out.append(f"Waiting between their shots: {listed_waits}")
    else:
        out.append("")
        out.append("Nobody waits between their shots.")
    return "\n".join(out) + "\n"
