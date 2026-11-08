"""Reading a ride file. It is untrusted text: every line has a fixed shape, every number a range.

route Harbour Hills loop
rider Sam 80 230          name, rider + bike kg, watts held for a few hours
ride 4.0 1.5              km, gradient %
regroup Top of Bobbin Head   a place the bunch could stop (at the distance so far)
max_gap 3                 minutes the last rider may fall behind the first (default 3)
"""

from __future__ import annotations

import math
import re
from dataclasses import dataclass, field

from .physics import Rider

MAX_BYTES = 64 * 1024
MAX_LINE = 200
LIMITS = {"segments": 300, "riders": 40, "regroups": 60}
NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9 '\-.&()]{0,39}")
NUMBER = re.compile(r"-?\d{1,4}(\.\d{1,3})?")
BAD_CHARS = re.compile("[\x00-\x08\x0b-\x1f\x7f-\x9f\u200b-\u200f\u202a-\u202e\u2066-\u2069]")


class RideError(ValueError):
    """A problem with the ride file; the message gives a line number, never the line."""


@dataclass
class Segment:
    km: float
    grade: float
    start_km: float


@dataclass
class Ride:
    name: str = "Group ride"
    riders: list[Rider] = field(default_factory=list)
    segments: list[Segment] = field(default_factory=list)
    # (segment index the place comes before, name); index len(segments) is the finish.
    regroups: list[tuple[int, str]] = field(default_factory=list)
    max_gap: float = 3.0

    @property
    def km(self) -> float:
        return sum(s.km for s in self.segments)


def _number(text: str, lo: float, hi: float, what: str, n: int) -> float:
    if not NUMBER.fullmatch(text):
        raise RideError(f"line {n}: {what} must be a plain number")
    v = float(text)
    if not (math.isfinite(v) and lo <= v <= hi):
        raise RideError(f"line {n}: {what} must be from {lo:g} to {hi:g}")
    return v


def _name(text: str, what: str, n: int) -> str:
    text = " ".join(text.split())
    if not NAME.fullmatch(text):
        raise RideError(f"line {n}: {what} must be 1 to 40 letters, digits, spaces or - ' . & ( )")
    return text


def parse(text: str) -> Ride:
    if len(text.encode("utf-8", "surrogatepass")) > MAX_BYTES:
        raise RideError("the ride file is over 64 KB")
    ride = Ride()
    names: set[str] = set()
    for n, raw in enumerate(text.splitlines(), 1):
        if len(raw) > MAX_LINE:
            raise RideError(f"line {n}: longer than {MAX_LINE} characters")
        if BAD_CHARS.search(raw):
            raise RideError(f"line {n}: control or invisible formatting characters")
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        word, _, rest = line.partition(" ")
        parts = rest.split()
        if word == "route" and rest.strip():
            ride.name = _name(rest, "the route name", n)
        elif word == "rider" and len(parts) >= 3:
            name = _name(" ".join(parts[:-2]), "a rider's name", n)
            if name.lower() in names:
                raise RideError(f"line {n}: two riders have this name")
            names.add(name.lower())
            mass = _number(parts[-2], 30, 200, "rider and bike mass (kg)", n)
            power = _number(parts[-1], 40, 600, "power (watts)", n)
            ride.riders.append(Rider(name, mass, power))
        elif word == "ride" and len(parts) == 2:
            km = _number(parts[0], 0.05, 80, "a stretch's length (km)", n)
            grade = _number(parts[1], -20, 25, "a gradient (%)", n)
            ride.segments.append(Segment(km, grade, ride.km))
        elif word == "regroup" and rest.strip():
            ride.regroups.append((len(ride.segments), _name(rest, "a regroup point's name", n)))
        elif word == "max_gap" and len(parts) == 1:
            ride.max_gap = _number(parts[0], 0.5, 60, "max_gap (minutes)", n)
        else:
            raise RideError(f"line {n}: expected route, rider, ride, regroup or max_gap")
        for key, items in (("riders", ride.riders), ("segments", ride.segments), ("regroups", ride.regroups)):
            if len(items) > LIMITS[key]:
                raise RideError(f"at most {LIMITS[key]} {key}")
    if len(ride.riders) < 2:
        raise RideError("a group ride needs at least 2 riders")
    if not ride.segments:
        raise RideError("the route has no 'ride' lines")
    if ride.km > 400:
        raise RideError("the route is over 400 km")
    seen = set()
    for idx, _ in ride.regroups:
        if idx in (0, len(ride.segments)) or idx in seen:
            raise RideError("regroup points must be between the start and the finish, one per place")
        seen.add(idx)
    return ride
