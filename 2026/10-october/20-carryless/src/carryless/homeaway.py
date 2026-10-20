"""Home and away.

Once the rounds are fixed, each match still needs a home team. A team has a *break* when it
plays at home (or away) in two rounds in a row; fans and clubs want as few as possible. With an
even number of teams a single round robin has at least n - 2 breaks; with a bye it can have none.
Teams that share a ground must also never both be at home in the same round.
"""

from __future__ import annotations

import math
import random
import time
from itertools import pairwise

from .schedule import Round

SHARE_PENALTY = 1000  # a shared-ground clash counts as much as 1000 breaks


def venues(rounds: list[Round], home: list[list[bool]], bye: int | None) -> list[list[str]]:
    """venue[team][round] = 'H', 'A' or '-' (a bye). home[r][i] is True when i is at home in round r."""
    n = len(rounds[0])
    out = []
    for team in range(n):
        row = []
        for r, opp in enumerate(rounds):
            if team == bye or opp[team] == bye:
                row.append("-")
            else:
                row.append("H" if home[r][team] else "A")
        out.append(row)
    return out


def count_breaks(seq: list[str]) -> int:
    """Two played rounds in a row at the same venue (a bye in between resets nothing; it is skipped)."""
    played = [v for v in seq if v != "-"]
    return sum(1 for a, b in pairwise(played) if a == b)


def cost(rounds: list[Round], home: list[list[bool]], bye: int | None, shares: list[tuple[int, int]]) -> tuple[int, int]:
    """(breaks, shared-ground clashes)."""
    v = venues(rounds, home, bye)
    breaks = sum(count_breaks(row) for t, row in enumerate(v) if t != bye)
    clashes = sum(1 for a, b in shares for r in range(len(rounds)) if v[a][r] == "H" and v[b][r] == "H")
    return breaks, clashes


def assign(
    rounds: list[Round], bye: int | None, shares: list[tuple[int, int]], seed: int, restarts: int = 12, ceiling: float = 20.0
) -> list[list[bool]]:
    """Local search: flip which team is at home in one match at a time, keeping flips that don't
    make things worse, with random restarts. The same seed gives the same answer; `ceiling`
    seconds is only a safety limit for very large leagues."""
    # Seeded randomness drives the search; it is not used for anything secret.
    rng = random.Random(seed)  # noqa: S311  # nosec B311
    n, m = len(rounds[0]), len(rounds)
    matches = [(r, i) for r in range(m) for i in range(n) if i < rounds[r][i]]
    deadline = time.monotonic() + ceiling
    best, best_score = None, None
    floor = 0 if bye is not None else n - 2  # an odd league can have no breaks at all

    def score(h: list[list[bool]]) -> int:
        b, c = cost(rounds, h, bye, shares)
        return b + SHARE_PENALTY * c

    for restart in range(restarts):
        if restart and time.monotonic() > deadline:
            break
        home = [[False] * n for _ in range(m)]
        for r, i in matches:
            j = rounds[r][i]
            h = rng.random() < 0.5 if restart else (r + i) % 2 == 0
            home[r][i], home[r][j] = h, not h
        current = score(home)
        # Simulated annealing: accept a worse flip now and then, less often as it cools.
        temp = 2.0
        for _ in range(len(matches) * 40):
            r, i = matches[rng.randrange(len(matches))]
            j = rounds[r][i]
            home[r][i], home[r][j] = home[r][j], home[r][i]
            new = score(home)
            if new <= current or rng.random() < math.exp((current - new) / temp):
                current = new
            else:
                home[r][i], home[r][j] = home[r][j], home[r][i]
            temp = max(0.05, temp * 0.995)
            if best_score is None or current < best_score:
                best, best_score = [list(row) for row in home], current
            if best_score <= floor:
                break
        if best_score is not None and best_score <= floor:
            break
    if best is None:  # only if restarts == 0
        raise ValueError("restarts must be at least 1")
    return best
