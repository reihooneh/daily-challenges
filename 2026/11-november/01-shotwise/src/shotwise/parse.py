"""The shot-list file: shots and who is in them, plus who arrives late, who must leave early,
and whose waiting matters more.

Every line must match a fixed shape and every number has a range. Error messages give the
line number and what was expected, never the text of the line.
"""

from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass, field

MAX_BYTES = 32 * 1024
MAX_LINE = 300
MAX_SHOTS = 60
MAX_PEOPLE = 150
MAX_IN_SHOT = 40
MAX_MINUTES = 30
MAX_AT = 600

_NAME = re.compile(r"[^\W\d_][\w '.&-]{0,39}")
_SHOT = re.compile(r"shot\s+(?P<label>[^:()]+?)\s*(?:\((?P<min>\d{1,2})\s*(?:min)?\))?\s*:\s*(?P<names>.+)")
_PERSON_AT = re.compile(r"(?P<kind>leaves|arrives)\s+(?P<name>.+?)\s+at\s+(?P<at>\d{1,3})")
_WEIGHT = re.compile(r"weight\s+(?P<name>.+?)\s+(?P<w>\d{1,2})")
_PIN = re.compile(r"(?P<kind>first|last)\s+(?P<label>.+)")


class ShotListError(ValueError):
    """A problem in the file. The message never repeats the input."""

    def __init__(self, line: int, msg: str) -> None:
        super().__init__(f"line {line}: {msg}" if line else msg)


@dataclass
class ShotList:
    title: str = "Group photos"
    minutes: int = 2
    labels: list[str] = field(default_factory=list)
    lengths: list[int | None] = field(default_factory=list)  # None: the default length
    people: list[str] = field(default_factory=list)
    members: list[list[int]] = field(default_factory=list)  # people in each shot
    weights: dict[int, int] = field(default_factory=dict)
    leaves: dict[int, int] = field(default_factory=dict)  # minutes after the start
    arrives: dict[int, int] = field(default_factory=dict)
    first: int | None = None
    last: int | None = None

    def length(self, shot: int) -> int:
        n = self.lengths[shot]
        return self.minutes if n is None else n


def _clean(text: str) -> bool:
    """No control characters and no invisible format characters (direction overrides and the like)."""
    return not any(unicodedata.category(c) in ("Cc", "Cf") for c in text)


def _name(raw: str, line: int, what: str = "names") -> str:
    name = " ".join(raw.split())
    if not _NAME.fullmatch(name) or not _clean(name):
        raise ShotListError(line, f"{what} use letters, digits, spaces and ' . & - (up to 40), starting with a letter")
    return name


def _number(raw: str, line: int, what: str, lo: int, hi: int) -> int:
    n = int(raw)
    if not lo <= n <= hi:
        raise ShotListError(line, f"{what} must be from {lo} to {hi}")
    return n


def parse(text: str) -> ShotList:
    if len(text.encode("utf-8")) > MAX_BYTES:
        raise ShotListError(0, "the file is larger than 32 KB")
    text = text.removeprefix("\ufeff")
    sl = ShotList()
    index: dict[str, int] = {}
    pending: list[tuple[int, str, str, int]] = []  # (line, kind, name, value) resolved once all shots are read
    pins: list[tuple[int, str, str]] = []
    seen_title = False

    for n, raw in enumerate(text.splitlines(), start=1):
        if len(raw) > MAX_LINE:
            raise ShotListError(n, f"is longer than {MAX_LINE} characters")
        if any(unicodedata.category(c) == "Cc" and c not in "\t\r" for c in raw):
            raise ShotListError(n, "contains a control character")
        line = " ".join(raw.split("#", 1)[0].split())
        if not line:
            continue
        head = line.split(" ", 1)[0]
        if head == "title":
            if seen_title or line == "title":
                raise ShotListError(n, "the title comes once, after the word 'title'")
            sl.title = _name(line[6:], n, "the title")
            seen_title = True
        elif head == "minutes":
            m = re.fullmatch(r"minutes (\d{1,2})", line)
            if not m:
                raise ShotListError(n, "write the usual time per shot like 'minutes 2'")
            sl.minutes = _number(m[1], n, "minutes per shot", 1, MAX_MINUTES)
        elif head == "shot":
            m = _SHOT.fullmatch(line)
            if not m:
                raise ShotListError(n, "write a shot like 'shot Bride's family (3): Priya, Tom, Anita'")
            label = _name(m["label"], n, "shot names")
            if label in sl.labels:
                raise ShotListError(n, "two shots have the same name")
            if len(sl.labels) >= MAX_SHOTS:
                raise ShotListError(n, f"at most {MAX_SHOTS} shots")
            who: list[int] = []
            for part in m["names"].split(","):
                name = _name(part, n)
                if name not in index:
                    if len(sl.people) >= MAX_PEOPLE:
                        raise ShotListError(n, f"at most {MAX_PEOPLE} people")
                    index[name] = len(sl.people)
                    sl.people.append(name)
                if index[name] in who:
                    raise ShotListError(n, "someone is listed twice in one shot")
                who.append(index[name])
            if len(who) > MAX_IN_SHOT:
                raise ShotListError(n, f"at most {MAX_IN_SHOT} people in one shot")
            sl.labels.append(label)
            sl.lengths.append(None if m["min"] is None else _number(m["min"], n, "a shot's minutes", 1, MAX_MINUTES))
            sl.members.append(who)
        elif head in ("leaves", "arrives"):
            m = _PERSON_AT.fullmatch(line)
            if not m:
                raise ShotListError(n, f"write it like '{head} Nani at 15' (minutes after the photos start)")
            pending.append((n, head, _name(m["name"], n), _number(m["at"], n, "the time", 0, MAX_AT)))
        elif head == "weight":
            m = _WEIGHT.fullmatch(line)
            if not m:
                raise ShotListError(n, "write it like 'weight Nani 3' (her waiting counts three times)")
            pending.append((n, head, _name(m["name"], n), _number(m["w"], n, "a weight", 1, 10)))
        elif head in ("first", "last"):
            m = _PIN.fullmatch(line)
            if not m:
                raise ShotListError(n, f"write it like '{head} Couple alone'")
            pins.append((n, head, _name(m["label"], n, "shot names")))
        else:
            raise ShotListError(n, "lines start with title, minutes, shot, leaves, arrives, weight, first or last")

    if not sl.labels:
        raise ShotListError(0, "the file has no shots")
    for n, kind, name, value in pending:
        if name not in index:
            raise ShotListError(n, "names someone who isn't in any shot")
        p = index[name]
        target = {"leaves": sl.leaves, "arrives": sl.arrives, "weight": sl.weights}[kind]
        if p in target:
            raise ShotListError(n, f"gives '{kind}' twice for the same person")
        target[p] = value
    for n, kind, label in pins:
        if label not in sl.labels:
            raise ShotListError(n, "names a shot that isn't in the list")
        if getattr(sl, kind) is not None:
            raise ShotListError(n, f"'{kind}' comes once")
        setattr(sl, kind, sl.labels.index(label))
    if sl.first is not None and sl.first == sl.last and len(sl.labels) > 1:
        raise ShotListError(0, "one shot can't be both first and last")
    return sl
