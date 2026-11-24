"""Reading a show, finding every costume change, and covering the quick ones with dressers.

Times are seconds from the top of the show. An actor leaves the stage at the end of the last scene
they're in and comes back at the start of the next one, so the window for a change is everything in
between: gaps and any scenes they sit out.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from typing import Any

MAX_SCENES = 120
MAX_ACTORS = 80
MAX_COSTUMES = 300
MAX_BYTES = 256 * 1024
QUICK = 120.0  # a change with a window under two minutes needs a dresser
SPARE = 1.5  # ... as does one with less than 1.5 times the time it takes alone
HELPED = 0.6  # with a dresser, a change takes this share of the time
OFF = "-"
_TIME = re.compile(r"^(\d{1,3}):([0-5]\d)$")
_NAME = re.compile(r"^[\w .,'&()-]{1,40}$")


class ShowError(ValueError):
    """A show file that can't be used, with a message for people."""


@dataclass(frozen=True)
class Change:
    actor: str
    wing: str
    before: str
    after: str
    exit: float  # leaves the stage
    entrance: float  # must be back
    needs: float  # seconds the change takes
    scene_out: str
    scene_in: str

    @property
    def window(self) -> float:
        return self.entrance - self.exit

    @property
    def quick(self) -> bool:
        """Needs a dresser: too little time to change alone with a safe margin."""
        return self.window < max(QUICK, SPARE * self.needs)

    @property
    def takes(self) -> float:
        """How long the change takes as planned: with a dresser if it's quick."""
        return round(self.needs * HELPED, 1) if self.quick else self.needs

    @property
    def spare(self) -> float:
        return self.window - self.takes

    @property
    def possible(self) -> bool:
        return self.spare >= 0


@dataclass
class Show:
    title: str
    scenes: list[tuple[str, float, float]]  # name, start, end
    costumes: dict[str, tuple[float, frozenset[str]]]  # seconds to put on, worn under
    actors: dict[str, tuple[str, list[str]]]  # wing, costume per scene
    crossover: float
    changes: list[Change] = field(default_factory=list)


def seconds(text: Any, what: str) -> float:
    if not isinstance(text, str) or not (m := _TIME.match(text.strip())):
        raise ShowError(f"{what} must be a time like 3:20")
    return int(m.group(1)) * 60 + int(m.group(2))


def name(text: Any, what: str) -> str:
    if not isinstance(text, str) or not _NAME.match(text):
        raise ShowError(f"{what} must be a short name (letters, digits and simple punctuation)")
    return text


def load(text: str) -> Show:
    if len(text.encode()) > MAX_BYTES:
        raise ShowError("the show file is larger than 256 KB")
    try:
        data = json.loads(text)
    except (ValueError, RecursionError) as e:
        raise ShowError("the show file isn't valid JSON") from e
    if not isinstance(data, dict):
        raise ShowError("the show file must be a JSON object")

    raw_scenes = data.get("scenes")
    if not isinstance(raw_scenes, list) or not 1 <= len(raw_scenes) <= MAX_SCENES:
        raise ShowError(f"scenes must list 1 to {MAX_SCENES} scenes")
    scenes = []
    t = 0.0
    for i, s in enumerate(raw_scenes):
        if not isinstance(s, dict):
            raise ShowError(f"scene {i + 1} must be an object")
        length = seconds(s.get("length"), f"scene {i + 1} length")
        if length <= 0:
            raise ShowError(f"scene {i + 1} must last some time")
        scenes.append((name(s.get("name"), f"scene {i + 1} name"), t, t + length))
        t += length + seconds(s.get("gap", "0:00"), f"scene {i + 1} gap")

    raw_costumes = data.get("costumes")
    if not isinstance(raw_costumes, dict) or len(raw_costumes) > MAX_COSTUMES:
        raise ShowError(f"costumes must map at most {MAX_COSTUMES} names to how long they take")
    costumes: dict[str, tuple[float, frozenset[str]]] = {}
    for cname, c in raw_costumes.items():
        name(cname, "a costume")
        if not isinstance(c, dict):
            raise ShowError(f"costume {cname} must be an object")
        minutes = c.get("minutes")
        if isinstance(minutes, bool) or not isinstance(minutes, (int, float)) or not 0.05 <= minutes <= 30:
            raise ShowError(f"costume {cname}: minutes must be between 0.05 and 30")
        under = c.get("under", [])
        if not isinstance(under, list) or not all(isinstance(u, str) for u in under):
            raise ShowError(f"costume {cname}: under must list costume names")
        costumes[cname] = (float(minutes) * 60, frozenset(under))
    for cname, (_, under) in costumes.items():
        for u in under:
            if u not in costumes:
                raise ShowError(f"costume {cname} is worn under {u}, which isn't a costume")

    raw_actors = data.get("actors")
    if not isinstance(raw_actors, dict) or not 1 <= len(raw_actors) <= MAX_ACTORS:
        raise ShowError(f"actors must map 1 to {MAX_ACTORS} names to what they wear")
    actors: dict[str, tuple[str, list[str]]] = {}
    for aname, a in raw_actors.items():
        name(aname, "an actor")
        if not isinstance(a, dict):
            raise ShowError(f"{aname} must be an object")
        wing = a.get("wing", "SL")
        if wing not in ("SL", "SR"):
            raise ShowError(f"{aname}: wing must be SL or SR")
        wears = a.get("wears")
        if not isinstance(wears, list) or len(wears) != len(scenes):
            raise ShowError(f"{aname}: wears must name a costume (or -) for each of the {len(scenes)} scenes")
        for w in wears:
            if w != OFF and w not in costumes:
                raise ShowError(f"{aname} wears {w!s:.40}, which isn't in the costume list")
        actors[aname] = (wing, list(wears))

    crossover = seconds(data.get("crossover", "0:45"), "crossover")
    show = Show(name(data.get("title", "Untitled"), "title"), scenes, costumes, actors, crossover)
    show.changes = find_changes(show)
    return show


def change_time(show: Show, before: str, after: str) -> float:
    """Seconds to go from one costume to another: putting the new one on, unless it was worn
    underneath the old one, when it's only taking the old one off (a third of the time)."""
    put_on, _ = show.costumes[after]
    if before in show.costumes[after][1]:
        return round(show.costumes[before][0] / 3, 1)
    return put_on


def find_changes(show: Show) -> list[Change]:
    out = []
    for actor, (wing, wears) in show.actors.items():
        last = None  # (scene index, costume)
        for i, c in enumerate(wears):
            if c == OFF:
                continue
            if last is not None and last[1] != c:
                j, before = last
                out.append(
                    Change(
                        actor,
                        wing,
                        before,
                        c,
                        show.scenes[j][2],
                        show.scenes[i][1],
                        change_time(show, before, c),
                        show.scenes[j][0],
                        show.scenes[i][0],
                    )
                )
            last = (i, c)
    out.sort(key=lambda ch: (ch.exit, ch.actor))
    return out


# ---------------------------------------------------------------- dressers


def busy(ch: Change) -> tuple[float, float]:
    """When a dresser is tied up: from the actor's exit until the change is done."""
    return ch.exit, ch.exit + ch.takes


def fits(show: Show, rota: list[Change], ch: Change) -> bool:
    """Can a dresser already doing `rota` also do `ch` (with time to cross the stage)?"""
    s, e = busy(ch)
    for other in rota:
        s2, e2 = busy(other)
        travel = 0.0 if other.wing == ch.wing else show.crossover
        if not (e2 + travel <= s or e + travel <= s2):
            return False
    return True


def assign(show: Show, changes: list[Change]) -> tuple[list[list[Change]], bool]:
    """Fewest dressers covering the changes: first fit in time order, then an exact search for a
    rota with one dresser fewer, repeated until none exists. Returns the rotas and whether the
    count is proven to be the minimum (the search is bounded, so a huge show may stay unproven)."""
    order = sorted(changes, key=lambda c: busy(c)[0])
    best: list[list[Change]] = []
    for ch in order:
        for rota in best:
            if fits(show, rota, ch):
                rota.append(ch)
                break
        else:
            best.append([ch])
    while len(best) > 1:
        found = exact(show, order, len(best) - 1)
        if isinstance(found, str):  # the search ran out of steps
            return best, False
        if found is None:
            break
        best = found
    return best, True


def exact(show: Show, changes: list[Change], k: int, limit: int = 200_000) -> list[list[Change]] | str | None:
    """Covers the changes with at most k dressers (bounded backtracking): the rotas, None if it
    can't be done, or "timeout" if the search ran out of steps."""
    rotas: list[list[Change]] = [[] for _ in range(k)]
    steps = 0

    def place(i: int) -> bool:
        nonlocal steps
        steps += 1
        if steps > limit:
            raise TimeoutError
        if i == len(changes):
            return True
        tried_empty = False
        for rota in rotas:
            if not rota:
                if tried_empty:
                    continue  # empty rotas are interchangeable
                tried_empty = True
            if fits(show, rota, changes[i]):
                rota.append(changes[i])
                if place(i + 1):
                    return True
                rota.pop()
        return False

    try:
        return [r for r in rotas if r] if place(0) else None
    except TimeoutError:
        return "timeout"
