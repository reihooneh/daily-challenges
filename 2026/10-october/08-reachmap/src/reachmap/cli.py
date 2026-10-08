"""Command line: read one layout file safely, print the report."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import TextIO

from reachmap.analysis import analyse
from reachmap.layout import MAX_BYTES, LayoutError, parse
from reachmap.render import text_report


class _Parser(argparse.ArgumentParser):
    def error(self, message: str) -> None:  # type: ignore[override]
        # argparse would echo the bad argument back; keep errors to fixed text.
        raise LayoutError("could not understand the arguments (see --help)")


def read_limited(path: str) -> str:
    if path == "-":
        data = sys.stdin.buffer.read(MAX_BYTES + 1)
    else:
        file = Path(path)
        try:
            if not file.is_file():
                raise LayoutError("cannot read that file")
            with file.open("rb") as handle:
                data = handle.read(MAX_BYTES + 1)
        except (OSError, ValueError):
            raise LayoutError("cannot read that file") from None
    if len(data) > MAX_BYTES:
        raise LayoutError(f"the layout is larger than {MAX_BYTES} bytes")
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        raise LayoutError("the layout is not valid UTF-8 text") from None


def main(argv: list[str] | None = None, out: TextIO | None = None, err: TextIO | None = None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    out = out or sys.stdout
    err = err or sys.stderr
    parser = _Parser(prog="reachmap", description="Check a screen layout for slow, small or out-of-reach targets.")
    parser.add_argument("layout", help="layout JSON file, or - for standard input")
    parser.add_argument("--hand", choices=["right", "left"], default="right", help="which thumb (phones only)")
    try:
        args = parser.parse_args(argv)
        layout = parse(read_limited(args.layout))
    except LayoutError as error:
        err.write(f"reachmap: {error}\n")
        return 2
    report = analyse(layout, args.hand)
    out.write(text_report(layout, report, args.hand))
    return 1 if report.problems else 0
