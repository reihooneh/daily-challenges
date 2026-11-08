"""Where the bunch should regroup.

Everyone leaves a regroup point together, and each rider rides their own pace until the next
one, where the earlier riders wait for the last. Between two stops the gap (how far in time the
last rider is behind the first, at the same point on the road) must never pass max_gap.

Stopping more often never shortens the ride: the slowest rider's time to the next stop is the
same either way, and every stop costs everyone a little. So the plan is the fewest stops that
keep the gap in bounds, and among those the shortest ride. Every stage depends only on its two
ends, so dynamic programming over the candidate places finds that plan exactly.
"""

from __future__ import annotations

from dataclasses import dataclass

from .parse import Ride
from .physics import CLIMB, Rider, seconds


@dataclass
class Stage:
    start: int  # boundary index (0 = start, len(segments) = finish)
    end: int
    times: list[float]  # seconds for each rider, in rider order
    gap: float  # largest gap anywhere in the stage, seconds

    @property
    def slowest(self) -> float:
        return max(self.times)


@dataclass
class Plan:
    riders: list[Rider]
    stages: list[Stage]
    stop_cost: float  # seconds each regroup stop adds

    @property
    def stops(self) -> int:
        return len(self.stages) - 1

    @property
    def duration(self) -> float:
        return sum(s.slowest for s in self.stages) + self.stops * self.stop_cost

    def waiting(self) -> list[float]:
        """Total seconds each rider spends waiting for others (at stops and the finish)."""
        out = [0.0] * len(self.riders)
        for s in self.stages:
            for r, t in enumerate(s.times):
                out[r] += s.slowest - t
        return out


def segment_times(riders: list[Rider], ride: Ride) -> list[list[float]]:
    """seconds[r][k]: rider r on segment k.

    A bunch rides together wherever it isn't climbing: on flats, rises and descents everyone
    goes at the pace the slowest rider can hold in the draft, so gaps neither open nor close.
    On climbs (CLIMB % and steeper) drafting barely helps and each rider climbs at their own pace.
    """
    out = [[seconds(r, s.km, s.grade) for s in ride.segments] for r in riders]
    for k, s in enumerate(ride.segments):
        if s.grade < CLIMB:
            pace = max(row[k] for row in out)
            for row in out:
                row[k] = pace
    return out


def stage(times: list[list[float]], a: int, b: int) -> Stage:
    cum = [0.0] * len(times)
    gap = 0.0
    for k in range(a, b):
        for r in range(len(times)):
            cum[r] += times[r][k]
        gap = max(gap, max(cum) - min(cum))
    return Stage(a, b, cum, gap)


def best_plan(riders: list[Rider], ride: Ride, stop_cost: float = 120.0) -> Plan | None:
    """The fewest regroups (then the shortest ride) that keep every gap within max_gap; None if
    even stopping at every candidate place leaves a stretch with too big a gap."""
    times = segment_times(riders, ride)
    places = [0] + [i for i, _ in sorted(ride.regroups)] + [len(ride.segments)]
    limit = ride.max_gap * 60 + 1e-9
    # best[j] = (stops, duration, previous place) for reaching place j with everyone together.
    best: list[tuple[int, float, int] | None] = [None] * len(places)
    best[0] = (0, 0.0, -1)
    stages = {}
    for j in range(1, len(places)):
        for i in range(j):
            if best[i] is None:
                continue
            st = stage(times, places[i], places[j])
            if st.gap > limit:
                continue
            stops, dur, _ = best[i]
            cand = (stops + (1 if i > 0 else 0), dur + st.slowest + (stop_cost if i > 0 else 0), i)
            if best[j] is None or cand[:2] < best[j][:2]:
                best[j] = cand
                stages[j] = st
    if best[-1] is None:
        return None
    chain = []
    j = len(places) - 1
    while j > 0:
        chain.append(stages[j])
        j = best[j][2]
    return Plan(riders, chain[::-1], stop_cost)


def no_stops(riders: list[Rider], ride: Ride) -> Stage:
    return stage(segment_times(riders, ride), 0, len(ride.segments))


def split(ride: Ride, stop_cost: float = 120.0) -> tuple[Plan, Plan] | None:
    """When one bunch can't stay together, the best split into a faster and a slower bunch (each
    of two or more riders, by solo time over the route): fewest total stops, then the smallest
    difference between the bunches' ride times."""
    order = sorted(ride.riders, key=lambda r: no_stops([r, r], ride).slowest)
    best = None
    for k in range(2, len(order) - 1):
        a = best_plan(order[:k], ride, stop_cost)
        b = best_plan(order[k:], ride, stop_cost)
        if a is None or b is None:
            continue
        key = (a.stops + b.stops, abs(a.duration - b.duration))
        if best is None or key < best[0]:
            best = (key, (a, b))
    return best[1] if best else None
