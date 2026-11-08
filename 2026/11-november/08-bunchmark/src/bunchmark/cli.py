"""bunchmark RIDE-FILE [--stop-minutes M]   ('-' reads standard input)"""

from __future__ import annotations

import argparse
import os
import stat
import sys

from .parse import MAX_BYTES, RideError, parse
from .plan import best_plan, split
from .report import report


def read(path: str) -> str:
    if path == "-":
        data = sys.stdin.buffer.read(MAX_BYTES + 1)
    else:
        try:
            info = os.lstat(path)
        except OSError:
            raise RideError("couldn't open the ride file (check the name)") from None
        if not stat.S_ISREG(info.st_mode):
            raise RideError("only regular files are read (not links, folders or devices)")
        with open(path, "rb") as f:
            data = f.read(MAX_BYTES + 1)
    if len(data) > MAX_BYTES:
        raise RideError("the ride file is over 64 KB")
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        raise RideError("the ride file isn't valid UTF-8 text") from None


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="bunchmark", description="Plan where a group ride should regroup.")
    p.add_argument("ride", help="ride file, or - for standard input")
    p.add_argument("--stop-minutes", type=float, default=2.0, help="minutes each regroup takes (default 2)")
    args = p.parse_args(argv)
    try:
        if not 0 <= args.stop_minutes <= 30:
            raise RideError("--stop-minutes must be from 0 to 30")
        ride = parse(read(args.ride))
        cost = args.stop_minutes * 60
        plan = best_plan(ride.riders, ride, cost)
        sys.stdout.write(report(ride, plan, None if plan else split(ride, cost)))
    except RideError as e:
        print(f"bunchmark: {e}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
