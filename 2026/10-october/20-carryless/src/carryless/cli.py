"""Command line: carryless LEAGUE.txt [--seed N] [--csv]

League file:
    league Western Suburbs netball, autumn
    team Rovers
    team Dockers
    share Rovers Dockers        # these two share a ground: never both at home in one round
"""

from __future__ import annotations

import argparse
import csv
import io
import os
import re
import stat
import sys
import unicodedata

from .homeaway import assign, cost, venues
from .schedule import Round, build, carryover_matrix, circle, coe

MAX_BYTES = 16 * 1024
MAX_LINE = 120
MAX_TEAMS = 40
NAME = re.compile(r"[^\W_][\w .'&()-]{0,29}")  # letters/digits in any script, simple punctuation
BIDI = {chr(c) for c in (0x200E, 0x200F, *range(0x202A, 0x202F), *range(0x2066, 0x206A))}  # hidden direction marks


class LeagueError(ValueError):
    pass


def parse(text: str) -> tuple[str, list[str], list[tuple[int, int]]]:
    if len(text.encode("utf-8")) > MAX_BYTES:
        raise LeagueError("the league file is larger than 16 KB")
    league, teams, shares_named = "Unnamed league", [], []
    for n, raw in enumerate(text.splitlines(), 1):
        if len(raw) > MAX_LINE:
            raise LeagueError(f"line {n} is longer than {MAX_LINE} characters")
        if any(unicodedata.category(c) == "Cc" and c != "\t" for c in raw) or any(c in BIDI for c in raw):
            raise LeagueError(f"line {n} contains control or hidden direction characters")
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        word, _, rest = line.partition(" ")
        rest = " ".join(rest.split())
        if word == "league":
            if not NAME.fullmatch(rest[:30]) or len(rest) > 60:
                raise LeagueError(f"line {n}: league names are letters, digits, spaces and simple punctuation")
            league = rest
        elif word == "team":
            if not NAME.fullmatch(rest):
                raise LeagueError(f"line {n}: team names are 1-30 letters, digits, spaces and simple punctuation")
            if rest.casefold() in (t.casefold() for t in teams):
                raise LeagueError(f"line {n}: {rest} is listed twice")
            if len(teams) >= MAX_TEAMS:
                raise LeagueError(f"line {n}: more than {MAX_TEAMS} teams")
            teams.append(rest)
        elif word == "share":
            shares_named.append((n, rest))
        else:
            raise LeagueError(f"line {n}: lines start with league, team or share")
    if len(teams) < 3:
        raise LeagueError("a league needs at least 3 teams")
    lookup = {t.casefold(): i for i, t in enumerate(teams)}
    shares = []
    for n, rest in shares_named:
        pair = _split_pair(rest, lookup)
        if pair is None:
            raise LeagueError(f"line {n}: 'share' needs two different teams from the list")
        shares.append(pair)
    return league, teams, shares


def _split_pair(rest: str, lookup: dict[str, int]) -> tuple[int, int] | None:
    """Team names can contain spaces, so try every split point."""
    words = rest.split(" ")
    for k in range(1, len(words)):
        a, b = " ".join(words[:k]).casefold(), " ".join(words[k:]).casefold()
        if a in lookup and b in lookup and a != b:
            return lookup[a], lookup[b]
    return None


def safe_cell(text: str) -> str:
    """Spreadsheets treat cells starting with = + - @ as formulas; make them plain text."""
    return "'" + text if text[:1] in ("=", "+", "-", "@", "\t", "\r") else text


def report(
    league: str,
    names: list[str],
    rounds: list[Round],
    home: list[list[bool]],
    bye: int | None,
    shares: list[tuple[int, int]],
    how: str,
    source: str,
) -> str:
    n = len(rounds[0])
    real = n - (1 if bye is not None else 0)
    out = io.StringIO()
    w = out.write
    w(f"CARRYLESS  {source}  ({league}: {real} teams, {len(rounds)} rounds)\n\n")
    ours, base, ideal = coe(rounds), coe(circle(n)), n * (n - 1)
    worst = max(max(row) for row in carryover_matrix(rounds))
    worst_base = max(max(row) for row in carryover_matrix(circle(n)))
    w(f"  Carry-over value   {ours}   (perfect would be {ideal}; the usual circle fixture scores {base})\n")
    w(
        f"  Worst pair         at most {worst} team{'s' if worst != 1 else ''} meet the same two opponents back to back,"
        f" in the same order (circle fixture: {worst_base})\n"
    )
    breaks, clashes = cost(rounds, home, bye, shares)
    floor = 0 if bye is not None else n - 2
    w(f"  Home/away breaks   {breaks}   (no fixture of this size can have fewer than {floor})\n")
    if shares:
        w(f"  Shared grounds     {'never both at home' if clashes == 0 else f'{clashes} clash(es) could not be avoided'}\n")
    w(f"  Method             {how}\n\n")
    for r, opp in enumerate(rounds):
        games, rest = [], None
        for i in range(n):
            j = opp[i]
            if i == bye or j == bye:
                if i != bye:
                    rest = names[i]
                continue
            if home[r][i]:
                games.append(f"{names[i]} v {names[j]}")
        line = "   ".join(games) + (f"   (bye: {rest})" if rest else "")
        w(f"  Round {r + 1:<3} {line}\n")
    w("\n  Venues (H home, A away, - bye)\n")
    v = venues(rounds, home, bye)
    width = max(len(t) for t in names)
    for t in range(n):
        if t != bye:
            w(f"  {names[t]:<{width}}  {' '.join(v[t])}\n")
    return out.getvalue()


def to_csv(names: list[str], rounds: list[Round], home: list[list[bool]], bye: int | None) -> str:
    out = io.StringIO()
    wr = csv.writer(out, lineterminator="\r\n")
    wr.writerow(["Round", "Home", "Away"])
    for r, opp in enumerate(rounds):
        for i, j in enumerate(opp):
            if bye not in (i, j) and home[r][i]:
                wr.writerow([r + 1, safe_cell(names[i]), safe_cell(names[j])])
    return out.getvalue()


def read_file(path: str) -> str:
    if path == "-":
        data = sys.stdin.buffer.read(MAX_BYTES + 1)
    else:
        try:
            info = os.lstat(path)
        except OSError:
            raise LeagueError("no such file") from None
        if not stat.S_ISREG(info.st_mode):
            raise LeagueError("not a regular file")
        with open(path, "rb") as fh:
            data = fh.read(MAX_BYTES + 1)
    if len(data) > MAX_BYTES:
        raise LeagueError("the league file is larger than 16 KB")
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        raise LeagueError("the league file is not valid UTF-8") from None


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="carryless", description="Fair round-robin fixtures: low carry-over, few home/away breaks.")
    ap.add_argument("league", help="league file, or - for standard input")
    ap.add_argument("--seed", type=int, default=20, help="random seed (the same seed gives the same fixture)")
    ap.add_argument("--csv", action="store_true", help="print the fixture as CSV instead of the report")
    args = ap.parse_args(argv)
    if not 0 <= args.seed < 2**31:
        print("carryless: --seed must be between 0 and 2147483647", file=sys.stderr)
        return 2
    try:
        league, names, shares = parse(read_file(args.league))
    except LeagueError as e:
        print(f"carryless: {e}", file=sys.stderr)
        return 2
    bye = None
    if len(names) % 2:
        bye = len(names)
        names = [*names, "(bye)"]
    rounds, how = build(len(names), seed=args.seed)
    home = assign(rounds, bye, shares, seed=args.seed)
    source = "standard input" if args.league == "-" else re.sub(r"[^A-Za-z0-9._-]", "?", os.path.basename(args.league))[:60]
    if args.csv:
        sys.stdout.write(to_csv(names, rounds, home, bye))
    else:
        sys.stdout.write(report(league, names, rounds, home, bye, shares, how, source))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
