"""Text output: the plan, each stop's wait, and the route's profile with the stops marked."""

from __future__ import annotations

from .parse import Ride
from .plan import Plan, Stage, no_stops


def clock(sec: float) -> str:
    sec = round(sec)
    h, rest = divmod(sec, 3600)
    m, s = divmod(rest, 60)
    return f"{h}:{m:02d}:{s:02d}" if h else f"{m}:{s:02d}"


def place(ride: Ride, boundary: int) -> str:
    if boundary == len(ride.segments):
        return "the finish"
    return dict(ride.regroups).get(boundary, f"km {km_at(ride, boundary):.1f}")


def km_at(ride: Ride, boundary: int) -> float:
    return sum(s.km for s in ride.segments[:boundary])


def stage_lines(ride: Ride, plan: Plan, st: Stage) -> list[str]:
    last = plan.riders[st.times.index(st.slowest)].name
    first_i = st.times.index(min(st.times))
    wait = st.slowest - st.times[first_i]
    return [
        f"  {place(ride, st.end)} (km {km_at(ride, st.end):.1f}): last in {last} after {clock(st.slowest)}; "
        f"{plan.riders[first_i].name} waits longest, {clock(wait)}. Biggest gap on the way {clock(st.gap)}."
    ]


def describe(ride: Ride, plan: Plan, title: str) -> list[str]:
    stops = plan.stages[:-1]
    lines = [title]
    if stops:
        names = ", ".join(f"{place(ride, st.end)} (km {km_at(ride, st.end):.1f})" for st in stops)
        lines.append(f"  Regroup {len(stops)} time{'s' if len(stops) != 1 else ''}: {names}.")
    else:
        lines.append("  No regroups needed: the bunch stays within the gap all the way.")
    lines.append(f"  Ride time {clock(plan.duration)}, including {clock(plan.stop_cost)} at each regroup.")
    for st in plan.stages:
        lines += stage_lines(ride, plan, st)
    waits = plan.waiting()
    each = ", ".join(f"{r.name} {clock(w)}" for r, w in zip(plan.riders, waits, strict=True))
    lines.append(f"  Waiting in total: {each}.")
    return lines


def profile(ride: Ride, stops: list[int], width: int = 60, height: int = 8) -> list[str]:
    """Elevation along the route, one column per stretch of road, with the regroups marked."""
    total = ride.km
    heights = [0.0]
    for s in ride.segments:
        heights.append(heights[-1] + s.km * 1000 * s.grade / 100)
    marks = [0.0]
    for s in ride.segments:
        marks.append(marks[-1] + s.km)

    def elevation(x_km: float) -> float:
        for k in range(len(ride.segments)):
            if x_km <= marks[k + 1] or k == len(ride.segments) - 1:
                f = (x_km - marks[k]) / ride.segments[k].km
                return heights[k] + f * (heights[k + 1] - heights[k])
        return heights[-1]

    cols = [elevation((c + 0.5) / width * total) for c in range(width)]
    lo, hi = min(cols), max(cols)
    span = max(hi - lo, 1.0)
    rows = []
    for row in range(height, 0, -1):
        level = lo + span * (row - 0.5) / height
        rows.append("  |" + "".join("#" if h >= level else " " for h in cols))
    stop_row = [" "] * width
    for n, b in enumerate(stops, 1):
        c = min(width - 1, int(km_at(ride, b) / total * width))
        stop_row[c] = str(n % 10)
    rows.append("  +" + "-" * width)
    rows.append("   " + "".join(stop_row).rstrip())
    climb = hi - lo
    rows.insert(
        0, f"  Profile over {total:.1f} km, {climb:.0f} m from the lowest point to the highest; numbers mark the regroups"
    )
    return rows


def report(ride: Ride, plan: Plan | None, split_plans: tuple[Plan, Plan] | None) -> str:
    lines = [f"BUNCHMARK  {ride.name}: {ride.km:.1f} km, {len(ride.riders)} riders, keep the gap within {ride.max_gap:g} min", ""]
    whole = no_stops(ride.riders, ride)
    worst = max(range(len(ride.riders)), key=lambda r: whole.times[r])
    lines.append(
        f"Without regroups the gap would reach {clock(whole.gap)}: {ride.riders[worst].name} would finish "
        f"{clock(whole.slowest - min(whole.times))} after the first rider."
    )
    lines.append("")
    if plan is not None:
        lines += describe(ride, plan, "Plan")
        lines += ["", *profile(ride, [st.end for st in plan.stages[:-1]])]
    else:
        lines.append(f"No plan keeps one bunch within {ride.max_gap:g} min, even stopping at every regroup point.")
        if split_plans is not None:
            a, b = split_plans
            lines.append("Split into two bunches instead:")
            lines.append("")
            lines += describe(ride, a, "Faster bunch: " + ", ".join(r.name for r in a.riders))
            lines.append("")
            lines += describe(ride, b, "Steadier bunch: " + ", ".join(r.name for r in b.riders))
        else:
            lines.append("Add regroup points on the long climbs, or allow a bigger gap.")
    return "\n".join(lines) + "\n"
