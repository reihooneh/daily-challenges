"""Reading a layout file, treating every byte of it as untrusted.

A layout describes one screen: its size, the tappable elements on it, and the
tasks people do with those elements (a sequence of taps, and how often).
"""

from __future__ import annotations

import json
import math
import re
from dataclasses import dataclass

MAX_BYTES = 100_000
MAX_ELEMENTS = 200
MAX_TASKS = 50
MAX_STEPS = 30
MAX_COORDINATE = 10_000.0
ID_PATTERN = re.compile(r"[a-z][a-z0-9_-]{0,31}")
LABEL_PATTERN = re.compile(r"[\w .,'&()/+-]{0,40}")


class LayoutError(ValueError):
    """The layout file is not usable. The message never quotes the file."""


@dataclass(frozen=True)
class Element:
    id: str
    label: str
    x: float  # left edge
    y: float  # top edge
    w: float
    h: float

    @property
    def centre(self) -> tuple[float, float]:
        return (self.x + self.w / 2, self.y + self.h / 2)


@dataclass(frozen=True)
class Task:
    name: str
    steps: tuple[str, ...]
    per_day: float


@dataclass(frozen=True)
class Layout:
    width: float
    height: float
    device: str  # "phone" or "desktop"
    elements: dict[str, Element]
    tasks: tuple[Task, ...]


def _no_duplicates(pairs: list[tuple[str, object]]) -> dict[str, object]:
    keys = [key for key, _ in pairs]
    if len(keys) != len(set(keys)):
        raise LayoutError("a key appears twice in the same object")
    return dict(pairs)


def _reject_constant(_name: str) -> float:
    # Python's json module accepts NaN and Infinity by default. JSON doesn't.
    raise LayoutError("NaN and Infinity are not valid numbers in a layout")


def _object(value: object, where: str, allowed: set[str], required: set[str]) -> dict[str, object]:
    if not isinstance(value, dict):
        raise LayoutError(f"{where} must be an object")
    unknown = set(value) - allowed
    if unknown:
        # The key names are user text, so report how many, not which.
        raise LayoutError(f"{where} has {len(unknown)} unknown field(s); allowed: {', '.join(sorted(allowed))}")
    missing = required - set(value)
    if missing:
        raise LayoutError(f"{where} is missing: {', '.join(sorted(missing))}")
    return value


def _number(value: object, where: str, low: float, high: float) -> float:
    # bool is a subclass of int in Python, so it has to be excluded by hand.
    if isinstance(value, bool) or not isinstance(value, int | float):
        raise LayoutError(f"{where} must be a number")
    number = float(value)
    if not math.isfinite(number) or not low <= number <= high:
        raise LayoutError(f"{where} must be between {low:g} and {high:g}")
    return number


def _text(value: object, where: str, pattern: re.Pattern[str]) -> str:
    if not isinstance(value, str) or not pattern.fullmatch(value):
        raise LayoutError(f"{where} has characters or a length that is not allowed")
    return value


def parse(text: str) -> Layout:
    if len(text.encode("utf-8", "surrogatepass")) > MAX_BYTES:
        raise LayoutError(f"the layout is larger than {MAX_BYTES} bytes")
    try:
        data = json.loads(text, object_pairs_hook=_no_duplicates, parse_constant=_reject_constant)
    except LayoutError:
        raise
    except (json.JSONDecodeError, RecursionError, UnicodeError) as error:
        line = getattr(error, "lineno", None)
        raise LayoutError("the file is not valid JSON" + (f" (line {line})" if line else "")) from None

    root = _object(data, "the layout", {"screen", "elements", "tasks"}, {"screen", "elements"})
    screen = _object(root["screen"], "screen", {"width", "height", "device"}, {"width", "height"})
    width = _number(screen["width"], "screen.width", 100, MAX_COORDINATE)
    height = _number(screen["height"], "screen.height", 100, MAX_COORDINATE)
    device = screen.get("device", "phone")
    if device not in ("phone", "desktop"):
        raise LayoutError('screen.device must be "phone" or "desktop"')

    raw_elements = root["elements"]
    if not isinstance(raw_elements, list) or not 1 <= len(raw_elements) <= MAX_ELEMENTS:
        raise LayoutError(f"elements must be a list of 1 to {MAX_ELEMENTS} items")
    elements: dict[str, Element] = {}
    for index, raw in enumerate(raw_elements, start=1):
        where = f"element {index}"
        item = _object(raw, where, {"id", "label", "x", "y", "w", "h"}, {"id", "x", "y", "w", "h"})
        element_id = _text(item["id"], f"{where}.id", ID_PATTERN)
        if element_id in elements:
            raise LayoutError(f"{where} reuses an id that is already taken")
        element = Element(
            id=element_id,
            label=_text(item.get("label", element_id), f"{where}.label", LABEL_PATTERN),
            x=_number(item["x"], f"{where}.x", 0, width),
            y=_number(item["y"], f"{where}.y", 0, height),
            w=_number(item["w"], f"{where}.w", 1, width),
            h=_number(item["h"], f"{where}.h", 1, height),
        )
        if element.x + element.w > width + 0.5 or element.y + element.h > height + 0.5:
            raise LayoutError(f"{where} sticks out past the edge of the screen")
        elements[element_id] = element

    raw_tasks = root.get("tasks", [])
    if not isinstance(raw_tasks, list) or len(raw_tasks) > MAX_TASKS:
        raise LayoutError(f"tasks must be a list of at most {MAX_TASKS} items")
    tasks = []
    for index, raw in enumerate(raw_tasks, start=1):
        where = f"task {index}"
        item = _object(raw, where, {"name", "steps", "per_day"}, {"name", "steps"})
        steps = item["steps"]
        if not isinstance(steps, list) or not 1 <= len(steps) <= MAX_STEPS:
            raise LayoutError(f"{where}.steps must be a list of 1 to {MAX_STEPS} element ids")
        for step in steps:
            if not isinstance(step, str) or step not in elements:
                raise LayoutError(f"{where}.steps refers to an element that does not exist")
        tasks.append(
            Task(
                name=_text(item["name"], f"{where}.name", LABEL_PATTERN),
                steps=tuple(steps),
                per_day=_number(item.get("per_day", 1), f"{where}.per_day", 0, 10_000),
            )
        )
    return Layout(width, height, device, elements, tuple(tasks))
