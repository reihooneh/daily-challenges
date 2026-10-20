"""Round-robin fixtures and the carry-over effect.

A fixture for n teams (n even; an odd league gets a "bye" team) has n - 1 rounds, and in each
round every team plays exactly once. Here a round is a list `opp` where opp[i] is team i's opponent.

Carry-over: if team k plays i in one round and j in the next, then i "carries over" to j. Whatever
state i leaves k in (tired, injured, full of confidence) is what j meets. In a fair fixture no pair
(i, j) gets this much more often than any other. The carry-over effects value is the sum of the
squares of these counts; its smallest possible value is n(n - 1), when every count is exactly 1.
"""

from __future__ import annotations

import math
import random
import time

Round = list[int]  # opp[i] = opponent of team i in this round

# Primitive polynomials for GF(2^k), k = 1..6 (so up to 64 teams).
PRIMITIVE = {1: 0b11, 2: 0b111, 3: 0b1011, 4: 0b10011, 5: 0b100101, 6: 0b1000011}


def circle(n: int) -> list[Round]:
    """The textbook circle method: fix one team, rotate the others. It is known to give the
    *worst* possible carry-over, which is why it is the baseline here."""
    rounds = []
    m = n - 1
    for r in range(m):
        opp = [0] * n
        opp[r], opp[n - 1] = n - 1, r
        for k in range(1, n // 2):
            a, b = (r + k) % m, (r - k) % m
            opp[a], opp[b] = b, a
        rounds.append(opp)
    return rounds


def gf_mul(a: int, b: int, k: int) -> int:
    """Multiply in GF(2^k): polynomials over {0, 1}, reduced by the primitive polynomial."""
    poly, out = PRIMITIVE[k], 0
    while b:
        if b & 1:
            out ^= a
        b >>= 1
        a <<= 1
        if a >> k:
            a ^= poly
    return out


def russell(n: int) -> list[Round]:
    """Russell's (1980) perfectly balanced fixture for n = 2^k teams.

    Teams are the elements of the field GF(2^k). With g a primitive element, round t pairs
    every x with x + g^t (addition is XOR). Then if k meets i in round t and j in round t + 1,
    j - i = g^t (g + 1), which fixes t, and t fixes k: every pair (i, j) is carried over exactly once.
    """
    k = n.bit_length() - 1
    if n < 2 or 1 << k != n or k not in PRIMITIVE:
        raise ValueError("Russell's method needs 2, 4, 8, 16, 32 or 64 teams")
    rounds, a = [], 1
    for _ in range(n - 1):
        rounds.append([x ^ a for x in range(n)])
        a = gf_mul(a, 2, k)  # x (= 2) is a primitive element for these polynomials
    return rounds


def carryover_matrix(rounds: list[Round]) -> list[list[int]]:
    """counts[i][j] = how often a team meets j straight after meeting i (the last round wraps
    round to the first, as in the standard definition)."""
    n, m = len(rounds[0]), len(rounds)
    counts = [[0] * n for _ in range(n)]
    for r in range(m):
        now, nxt = rounds[r], rounds[(r + 1) % m]
        for team in range(n):
            counts[now[team]][nxt[team]] += 1
    return counts


def coe(rounds: list[Round]) -> int:
    """Carry-over effects value: the sum of squared counts. Lower is fairer; n(n - 1) is perfect."""
    return sum(c * c for row in carryover_matrix(rounds) for c in row)


def is_valid(rounds: list[Round]) -> bool:
    """Every round pairs everyone, and every pair meets exactly once."""
    n = len(rounds[0]) if rounds else 0
    if n % 2 or len(rounds) != n - 1:
        return False
    seen = set()
    for opp in rounds:
        if len(opp) != n:
            return False
        for i, j in enumerate(opp):
            if not 0 <= j < n or j == i or opp[j] != i:
                return False
            if i < j:
                if (i, j) in seen:
                    return False
                seen.add((i, j))
    return len(seen) == n * (n - 1) // 2


def _partial_swap(rounds: list[Round], r: int, s: int, team: int) -> None:
    """Partial round swap: the matches of rounds r and s together form even cycles. Swapping
    which round the matches of one cycle are played in gives another valid fixture."""
    a, b = rounds[r], rounds[s]
    cycle, x = [], team
    while True:
        cycle.append(x)
        y = a[x]
        cycle.append(y)
        x = b[y]
        if x == team:
            break
    for t in cycle:
        a[t], b[t] = b[t], a[t]


def improve(rounds: list[Round], seed: int, steps: int = 30_000, ceiling: float = 20.0) -> list[Round]:
    """Simulated annealing on the carry-over value, moving rounds around and swapping parts of
    rounds. The same seed gives the same fixture; `ceiling` seconds is only a safety limit."""
    # Seeded randomness drives the search; it is not used for anything secret.
    rng = random.Random(seed)  # noqa: S311  # nosec B311
    cur = [list(o) for o in rounds]
    n, m = len(cur[0]), len(cur)
    if m < 3:
        return cur
    cur_cost = coe(cur)
    best, best_cost = [list(o) for o in cur], cur_cost
    floor = n * (n - 1)
    deadline = time.monotonic() + ceiling
    temp = max(1.0, cur_cost / 50)
    for step in range(steps):
        if best_cost == floor or (step % 64 == 0 and time.monotonic() > deadline):
            break
        r, s = rng.sample(range(m), 2)
        if rng.random() < 0.5:
            cur[r], cur[s] = cur[s], cur[r]
            undo = ("swap", r, s, 0)
        else:
            team = rng.randrange(n)
            _partial_swap(cur, r, s, team)
            undo = ("partial", r, s, team)
        cost = coe(cur)
        if cost <= cur_cost or rng.random() < math.exp((cur_cost - cost) / temp):
            cur_cost = cost
            if cost < best_cost:
                best, best_cost = [list(o) for o in cur], cost
        elif undo[0] == "swap":
            cur[r], cur[s] = cur[s], cur[r]
        else:
            _partial_swap(cur, r, s, undo[3])  # the same cycle swapped back
        temp = max(0.05, temp * 0.9995)
    return best


def build(n: int, seed: int = 20, steps: int = 30_000) -> tuple[list[Round], str]:
    """The fairest fixture we can find, and how it was made."""
    if n >= 2 and n & (n - 1) == 0:
        return russell(n), "Russell's perfectly balanced construction"
    return improve(circle(n), seed, steps), "simulated annealing from the circle method"
