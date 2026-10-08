"""The human-factors models, and the checks built on them.

Three ideas from HCI research:

1. Fitts's law: the time to hit a target grows with the logarithm of
   (distance / size). Far and small is slow; near and big is fast.
2. Minimum touch target size: fingers are about 1 cm wide, so platform
   guidelines ask for targets of at least 44 x 44 points (Apple) or
   48 x 48 dp (Google).
3. Thumb reach: holding a phone in one hand, the thumb pivots near the
   bottom corner. Targets far from that pivot need a stretch or a regrip.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

from reachmap.layout import Element, Layout

# Fitts's law constants, MT = A + B * log2(D / W + 1). These depend on the
# person and device; the values below are in the range reported for finger
# touch and for a mouse. Treat the times as relative, not as a stopwatch.
CONSTANTS = {"phone": (0.10, 0.15), "desktop": (0.20, 0.10)}

MIN_TARGET = {"phone": 44.0, "desktop": 24.0}
MIN_GAP = 8.0  # space between neighbouring touch targets


def effective_width(element: Element, from_point: tuple[float, float]) -> float:
    """How wide the target is in the direction you approach it from.

    Approaching a wide button from the side, you have its full width to hit.
    Approaching from above, only its height. For a rectangle, it is the
    length of the line through its centre in the direction of travel.
    """
    cx, cy = element.centre
    dx, dy = cx - from_point[0], cy - from_point[1]
    distance = math.hypot(dx, dy)
    if distance == 0:
        return min(element.w, element.h)
    cos, sin = abs(dx) / distance, abs(dy) / distance
    along_x = element.w / cos if cos > 1e-9 else math.inf
    along_y = element.h / sin if sin > 1e-9 else math.inf
    return min(along_x, along_y)


def index_of_difficulty(element: Element, from_point: tuple[float, float]) -> float:
    """Fitts's index of difficulty, in bits (Shannon formulation)."""
    cx, cy = element.centre
    distance = math.hypot(cx - from_point[0], cy - from_point[1])
    return math.log2(distance / effective_width(element, from_point) + 1)


def movement_time(layout: Layout, element: Element, from_point: tuple[float, float]) -> float:
    a, b = CONSTANTS[layout.device]
    return a + b * index_of_difficulty(element, from_point)


def resting_point(layout: Layout, hand: str) -> tuple[float, float]:
    """Where the thumb or pointer starts before a task."""
    if layout.device == "desktop":
        return (layout.width / 2, layout.height / 2)
    x = layout.width * (0.25 if hand == "left" else 0.75)
    return (x, layout.height * 0.85)


def reach_zone(layout: Layout, element: Element, hand: str) -> str:
    """'easy', 'stretch' or 'hard' for a one-handed phone grip.

    The thumb pivots near the bottom corner on the holding side. The zone
    boundaries are distances from that pivot as a share of the screen height:
    an approximation of published thumb-zone studies, not a measurement.
    """
    if layout.device == "desktop":
        return "easy"
    pivot = (layout.width if hand == "right" else 0.0, layout.height)
    cx, cy = element.centre
    reach = math.hypot(cx - pivot[0], cy - pivot[1]) / layout.height
    if reach <= 0.55:
        return "easy"
    if reach <= 0.75:
        return "stretch"
    return "hard"


@dataclass
class StepReport:
    target: str
    seconds: float
    bits: float


@dataclass
class TaskReport:
    name: str
    per_day: float
    steps: list[StepReport]

    @property
    def seconds(self) -> float:
        return sum(step.seconds for step in self.steps)

    @property
    def slowest(self) -> StepReport:
        return max(self.steps, key=lambda step: step.seconds)


@dataclass
class Report:
    tasks: list[TaskReport] = field(default_factory=list)
    problems: list[str] = field(default_factory=list)
    zones: dict[str, str] = field(default_factory=dict)
    taps_per_day: dict[str, float] = field(default_factory=dict)


def gap_between(a: Element, b: Element) -> float:
    """Distance between the edges of two rectangles (negative if they overlap)."""
    gap_x = max(b.x - (a.x + a.w), a.x - (b.x + b.w))
    gap_y = max(b.y - (a.y + a.h), a.y - (b.y + b.h))
    if gap_x < 0 and gap_y < 0:
        return max(gap_x, gap_y)  # overlapping: how deep, as a negative number
    return math.hypot(max(gap_x, 0.0), max(gap_y, 0.0))


def analyse(layout: Layout, hand: str = "right") -> Report:
    report = Report()
    elements = layout.elements

    for task in layout.tasks:
        position = resting_point(layout, hand)
        steps = []
        for target_id in task.steps:
            target = elements[target_id]
            steps.append(StepReport(target_id, movement_time(layout, target, position), index_of_difficulty(target, position)))
            position = target.centre
            report.taps_per_day[target_id] = report.taps_per_day.get(target_id, 0.0) + task.per_day
        report.tasks.append(TaskReport(task.name, task.per_day, steps))

    for element in elements.values():
        report.zones[element.id] = reach_zone(layout, element, hand)

    minimum = MIN_TARGET[layout.device]
    for element in elements.values():
        if element.w < minimum or element.h < minimum:
            report.problems.append(
                f"'{element.label}' is {element.w:g} x {element.h:g}, smaller than the {minimum:g} x {minimum:g} "
                f"minimum for a {'touch' if layout.device == 'phone' else 'click'} target."
            )

    ordered = sorted(elements.values(), key=lambda e: (e.y, e.x))
    for i, a in enumerate(ordered):
        for b in ordered[i + 1 :]:
            gap = gap_between(a, b)
            if gap < 0:
                report.problems.append(f"'{a.label}' and '{b.label}' overlap: a tap there is ambiguous.")
            elif layout.device == "phone" and gap < MIN_GAP:
                report.problems.append(
                    f"'{a.label}' and '{b.label}' are only {gap:.0f} apart; leave at least {MIN_GAP:g} so a "
                    "thumb doesn't hit the wrong one."
                )

    busiest = sorted(report.taps_per_day.items(), key=lambda item: -item[1])
    for element_id, taps in busiest:
        if report.zones[element_id] == "hard" and taps >= 5:
            report.problems.append(
                f"'{elements[element_id].label}' is tapped about {taps:g} times a day but sits in the hard-to-reach "
                "zone. Move it lower, towards the thumb."
            )
    return report
