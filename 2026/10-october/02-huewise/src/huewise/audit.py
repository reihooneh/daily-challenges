"""Find colour pairs that collide for colour-blind viewers, and repair them.

A *collision* is a pair that looks clearly different to typical vision but
nearly the same under a colour vision deficiency. Those are the pairs that
break charts, status badges and "red means error, green means OK" designs.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from itertools import combinations

from .color import RGB, delta_e, from_lab, parse_hex, to_hex, to_lab
from .cvd import KINDS, simulate

# Two colours count as "clearly different" above DISTINCT and "confusable"
# below CONFUSABLE (CIE76 units). Chosen from common chart-design guidance.
DISTINCT = 20.0
CONFUSABLE = 10.0

MAX_COLORS = 64  # keeps the pairwise check (n^2) small and predictable


@dataclass(frozen=True)
class Collision:
    a: str
    b: str
    kind: str  # which deficiency makes them collide
    normal: float  # delta-E for typical vision
    simulated: float  # delta-E under the deficiency


@dataclass
class Report:
    colors: list[str]
    collisions: list[Collision] = field(default_factory=list)
    fixes: dict[str, str] = field(default_factory=dict)  # original -> suggestion
    remaining: int = 0  # collisions still present after applying the fixes

    @property
    def ok(self) -> bool:
        return not self.collisions


def worst_case_distance(a: RGB, b: RGB) -> float:
    """The smallest distance between two colours across all deficiencies."""
    return min(delta_e(simulate(a, k), simulate(b, k)) for k in KINDS)


def find_collisions(colors: dict[str, RGB]) -> list[Collision]:
    """Check every pair. Reports the single worst deficiency for each pair."""
    found = []
    for (name_a, a), (name_b, b) in combinations(colors.items(), 2):
        normal = delta_e(a, b)
        if normal < DISTINCT:
            continue  # already similar for everyone; not a colour-blindness issue
        kind, sim = min(
            ((k, delta_e(simulate(a, k), simulate(b, k))) for k in KINDS),
            key=lambda pair: pair[1],
        )
        if sim < CONFUSABLE:
            found.append(Collision(name_a, name_b, kind, round(normal, 1), round(sim, 1)))
    return found


def suggest_fix(target: RGB, others: list[RGB]) -> RGB | None:
    """Find the smallest lightness change that separates `target` from `others`.

    Lightness is the one thing every type of colour blindness still sees, so we
    keep the hue and move L* up or down in small steps, taking the first value
    that is safely distinct from every other colour under every deficiency.
    Returns None if no lightness in range works.
    """
    lightness, a, b = to_lab(target)
    for step in range(1, 101):
        for direction in (1, -1):
            candidate_l = lightness + direction * step
            if not 5 <= candidate_l <= 95:
                continue
            candidate = from_lab((candidate_l, a, b))
            if all(worst_case_distance(candidate, o) >= CONFUSABLE + 2 for o in others):
                return candidate
    return None


def audit(hex_colors: list[str], parsed: list[RGB]) -> Report:
    """Run the full check and propose repairs. Inputs are parallel lists."""
    if len(hex_colors) > MAX_COLORS:
        raise ValueError(f"too many colours ({len(hex_colors)}); the limit is {MAX_COLORS}")
    colors = dict(zip(hex_colors, parsed, strict=True))
    report = Report(colors=list(colors))
    report.collisions = find_collisions(colors)

    # Repair one colour from each colliding pair (the second one), checking the
    # suggestion against every other colour, including earlier suggestions.
    current = dict(colors)
    for c in report.collisions:
        if c.b in report.fixes or c.a in report.fixes:
            continue
        others = [rgb for name, rgb in current.items() if name != c.b]
        fixed = suggest_fix(current[c.b], others)
        if fixed is not None:
            report.fixes[c.b] = to_hex(fixed)
            # Re-parse the rounded hex so later checks use exactly what we print.
            current[c.b] = parse_hex(report.fixes[c.b])

    # Never trust a repair without checking it: audit the repaired palette.
    report.remaining = len(find_collisions(current))
    return report


def repaired_palette(report: Report) -> list[str]:
    """The original colours with every suggested fix applied, in order."""
    return [report.fixes.get(c, c) for c in report.colors]
