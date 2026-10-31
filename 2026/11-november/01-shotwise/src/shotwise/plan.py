"""Choosing the order of shots.

Everyone has to be there from the start of their first shot to the end of their last, so a
person in shots 1 and 9 waits through shots 2 to 8. The total waiting (in person-minutes,
weighted) is what the order changes. This is the "talent scheduling" problem from film
production, and it is NP-hard, so:

* up to EXACT_MAX shots, a dynamic programme over subsets finds the true minimum;
* beyond that, greedy starts are improved by moving one shot at a time (a local search).
"""

from __future__ import annotations

from dataclasses import dataclass

from .parse import ShotList

EXACT_MAX = 16
PENALTY = 10_000  # per minute of a missed arrival or leaving time, in the local search
MAX_EVALUATIONS = 60_000


@dataclass
class Plan:
    order: list[int]
    waiting: int  # weighted person-minutes
    exact: bool  # proven the least possible
    violations: list[str]


@dataclass
class Timing:
    starts: list[int]  # start minute of each shot, by position in the order
    first: dict[int, int]  # person -> position of their first shot
    last: dict[int, int]


def timing(sl: ShotList, order: list[int]) -> Timing:
    starts, t = [], 0
    first: dict[int, int] = {}
    last: dict[int, int] = {}
    for pos, s in enumerate(order):
        starts.append(t)
        t += sl.length(s)
        for p in sl.members[s]:
            first.setdefault(p, pos)
            last[p] = pos
    return Timing(starts, first, last)


def evaluate(sl: ShotList, order: list[int]) -> tuple[int, list[str], int]:
    """Weighted waiting, the broken constraints in words, and how many minutes they miss by."""
    tm = timing(sl, order)
    own = [0] * len(sl.people)
    for s in order:
        for p in sl.members[s]:
            own[p] += sl.length(s)
    waiting, broken, missed = 0, [], 0
    for p, name in enumerate(sl.people):
        start = tm.starts[tm.first[p]]
        end = tm.starts[tm.last[p]] + sl.length(order[tm.last[p]])
        waiting += sl.weights.get(p, 1) * (end - start - own[p])
        if p in sl.leaves and end > sl.leaves[p]:
            broken.append(f"{name} must leave at {clock(sl.leaves[p])} but is needed until {clock(end)}")
            missed += end - sl.leaves[p]
        if p in sl.arrives and start < sl.arrives[p]:
            broken.append(f"{name} arrives at {clock(sl.arrives[p])} but is needed from {clock(start)}")
            missed += sl.arrives[p] - start
    if sl.first is not None and order[0] != sl.first:
        broken.append(f"'{sl.labels[sl.first]}' should be first")
        missed += 1
    if sl.last is not None and order[-1] != sl.last:
        broken.append(f"'{sl.labels[sl.last]}' should be last")
        missed += 1
    return waiting, broken, missed


def clock(minutes: int) -> str:
    return f"{minutes // 60}:{minutes % 60:02d}"


def _window(sl: ShotList, s: int) -> tuple[int, int]:
    """Earliest and latest start for shot s set by its people's arrival and leaving times."""
    lo = max((sl.arrives[p] for p in sl.members[s] if p in sl.arrives), default=0)
    hi = min((sl.leaves[p] - sl.length(s) for p in sl.members[s] if p in sl.leaves), default=10**9)
    return lo, hi


def exact(sl: ShotList) -> list[int] | None:
    """Least-waiting feasible order by dynamic programming over the set of shots already taken.

    The waiting during a shot depends only on which shots came before it, not their order:
    the people waiting are those with a shot already done and a shot still to come who are not
    in this one. So best[S] (the least waiting to take the shots in S first) builds up from
    smaller sets. None if no order meets every time.
    """
    n = len(sl.labels)
    full = (1 << n) - 1
    people = [sum(1 << p for p in sl.members[s]) for s in range(n)]
    lengths = [sl.length(s) for s in range(n)]
    windows = [_window(sl, s) for s in range(n)]
    weight = [sl.weights.get(p, 1) for p in range(len(sl.people))]
    cache: dict[int, int] = {}

    def weighted(mask: int) -> int:
        if mask not in cache:
            total, m = 0, mask
            while m:
                low = m & -m
                total += weight[low.bit_length() - 1]
                m ^= low
            cache[mask] = total
        return cache[mask]

    union = [0] * (full + 1)  # everyone in the shots of a set
    duration = [0] * (full + 1)
    for mask in range(1, full + 1):
        low = mask & -mask
        s = low.bit_length() - 1
        union[mask] = union[mask ^ low] | people[s]
        duration[mask] = duration[mask ^ low] + lengths[s]

    inf = float("inf")
    best: list[float] = [inf] * (full + 1)
    came: list[int] = [-1] * (full + 1)
    best[0] = 0
    for done in range(full + 1):
        if best[done] == inf:
            continue
        start = duration[done]
        for s in range(n):
            bit = 1 << s
            if done & bit:
                continue
            if sl.first is not None and (done == 0) != (s == sl.first):
                continue
            if sl.last is not None and s == sl.last and (done | bit) != full:
                continue
            lo, hi = windows[s]
            if not lo <= start <= hi:
                continue
            nxt = done | bit
            idle = union[done] & union[full ^ nxt] & ~people[s]
            cost = best[done] + lengths[s] * weighted(idle)
            if cost < best[nxt]:
                best[nxt], came[nxt] = cost, s
    if best[full] == inf:
        return None
    order, mask = [], full
    while mask:
        s = came[mask]
        order.append(s)
        mask ^= 1 << s
    return order[::-1]


def _score(sl: ShotList, order: list[int]) -> int:
    waiting, _, missed = evaluate(sl, order)
    return waiting + PENALTY * missed


def greedy(sl: ShotList) -> list[int]:
    """Builds an order one shot at a time, taking the one that adds least to the score so far."""
    left = list(range(len(sl.labels)))
    order: list[int] = []
    while left:
        pick = min(left, key=lambda s: (_score(sl, [*order, s, *[x for x in left if x != s]]), s))
        order.append(pick)
        left.remove(pick)
    return order


def improve(sl: ShotList, order: list[int], budget: int = MAX_EVALUATIONS) -> list[int]:
    """Moves one shot to another position while that lowers the score (first improvement)."""
    best, best_score = list(order), _score(sl, order)
    used, better = 0, True
    while better and used < budget:
        better = False
        for i in range(len(best)):
            for j in range(len(best)):
                if i == j or used >= budget:
                    continue
                trial = best[:i] + best[i + 1 :]
                trial.insert(j, best[i])
                used += 1
                score = _score(sl, trial)
                if score < best_score:
                    best, best_score, better = trial, score, True
                    break
            if better:
                break
    return best


def plan(sl: ShotList) -> Plan:
    n = len(sl.labels)
    if n <= EXACT_MAX:
        order = exact(sl)
        if order is not None:
            waiting, broken, _ = evaluate(sl, order)
            return Plan(order, waiting, True, broken)
    # Too many shots for the exact search, or no order meets every time: find the closest.
    starts = [list(range(n)), greedy(sl)]
    found = [improve(sl, s, MAX_EVALUATIONS // len(starts)) for s in starts]
    order = min(found, key=lambda o: (_score(sl, o), o))
    waiting, broken, _ = evaluate(sl, order)
    return Plan(order, waiting, False, broken)
