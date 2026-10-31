"""Command line: shotwise SHOTS.txt   (or - for standard input)."""

from __future__ import annotations

import sys
from pathlib import Path

from .parse import MAX_BYTES, ShotListError, parse
from .plan import plan
from .report import render

USAGE = """Usage: shotwise SHOTS.txt        (or - to read standard input)

  title Priya and Tom
  minutes 2                          the usual time per shot
  shot Couple alone: Priya, Tom
  shot Grandparents (3): Priya, Tom, Nani, Dada
  leaves Nani at 15                  minutes after the photos start
  arrives Dev at 10
  weight Nani 3                      her waiting counts three times
  first Couple alone
  last Everyone

Exit codes: 0 order printed, 1 no order meets every time (the closest is printed), 2 bad usage or input."""


def read_bounded(path: str) -> str:
    """At most MAX_BYTES + 1 bytes from a regular file or standard input; the path is never echoed."""
    if path == "-":
        data = sys.stdin.buffer.read(MAX_BYTES + 1)
    else:
        p = Path(path)
        if not p.is_file():
            raise ShotListError(0, "the shot list could not be read (it must be a readable file)")
        try:
            with p.open("rb") as f:
                data = f.read(MAX_BYTES + 1)
        except OSError:
            raise ShotListError(0, "the shot list could not be read") from None
    if len(data) > MAX_BYTES:
        raise ShotListError(0, "the file is larger than 32 KB")
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        raise ShotListError(0, "the file must be UTF-8 text") from None


def main(argv: list[str] | None = None) -> int:
    args = sys.argv[1:] if argv is None else argv
    if len(args) != 1 or args[0] in ("-h", "--help"):
        print(USAGE, file=sys.stderr)
        return 2
    try:
        sl = parse(read_bounded(args[0]))
    except ShotListError as e:
        print(f"shotwise: {e}", file=sys.stderr)
        return 2
    pl = plan(sl)
    sys.stdout.write(render(sl, pl))
    return 1 if pl.violations else 0


if __name__ == "__main__":
    sys.exit(main())
