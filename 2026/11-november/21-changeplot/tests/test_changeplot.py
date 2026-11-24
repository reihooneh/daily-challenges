"""Tests for Changeplot."""

from __future__ import annotations

import itertools
import json
import random
from pathlib import Path

import pytest

from changeplot.__main__ import main, report
from changeplot.plot import HELPED, Change, ShowError, assign, exact, fits, load

EXAMPLE = Path(__file__).resolve().parent.parent / "examples" / "show.json"


def show_text(**over: object) -> str:
    d = json.loads(EXAMPLE.read_text())
    d.update(over)
    return json.dumps(d)


def test_windows_run_from_exit_to_next_entrance() -> None:
    show = load(EXAMPLE.read_text())
    tomas = [c for c in show.changes if c.actor == "Tomas"]
    # dock in scene 1 -> apron in scene 2: off at 4:30, back at 4:50
    assert (tomas[0].exit, tomas[0].entrance) == (270, 290)
    # apron in scene 2 -> tails in scene 4, sitting out the storm: window includes scene 3 and both gaps
    assert tomas[1].window == 15 + 110 + 90


def test_underdressing_and_dressers_speed_changes() -> None:
    show = load(EXAMPLE.read_text())
    mara = {(c.before, c.after): c for c in show.changes if c.actor == "Mara"}
    night = mara[("ballgown", "nightdress")]
    assert night.needs == pytest.approx(150 / 3)  # only taking the ballgown off
    assert night.quick and night.takes == pytest.approx(50 * HELPED)
    assert not night.possible


def test_example_report() -> None:
    text = report(load(EXAMPLE.read_text()), 1)
    assert "Quick changes need 2 dressers, and no fewer can cover them" in text
    assert "1 short" in text
    assert text.count("IMPOSSIBLE") == 2


def brute_force(show, changes) -> int:  # type: ignore[no-untyped-def]
    """The fewest dressers by trying every assignment of changes to k dressers."""
    for k in range(1, len(changes) + 1):
        for labels in itertools.product(range(k), repeat=len(changes)):
            rotas: list[list[Change]] = [[] for _ in range(k)]
            ok = True
            for ch, lab in zip(changes, labels):
                if not fits(show, rotas[lab], ch):
                    ok = False
                    break
                rotas[lab].append(ch)
            if ok:
                return k
    return len(changes)


def test_fewest_dressers_matches_brute_force() -> None:
    rng = random.Random(4)
    base = load(EXAMPLE.read_text())
    for _ in range(60):
        changes = []
        for i in range(rng.randint(1, 6)):
            exit_ = rng.uniform(0, 300)
            changes.append(
                Change(f"a{i}", rng.choice(["SL", "SR"]), "x", "y", exit_, exit_ + 100, rng.uniform(20, 90) / HELPED, "s", "t")
            )
        changes = [c for c in changes if c.quick]
        if not changes:
            continue
        rotas, proven = assign(base, changes)
        assert proven
        assert len(rotas) == brute_force(base, changes)
        assert sorted(id(c) for r in rotas for c in r) == sorted(id(c) for c in changes)
        for r in rotas:
            for a, b in itertools.combinations(r, 2):
                assert fits(base, [a], b)


def test_search_is_bounded() -> None:
    base = load(EXAMPLE.read_text())
    many = [Change(f"a{i}", "SL", "x", "y", 0.0, 100.0, 90.0, "s", "t") for i in range(30)]
    assert exact(base, many, 5, limit=1000) in (None, "timeout")


@pytest.mark.parametrize(
    ("text", "message"),
    [
        ("[]", "JSON object"),
        ("{" * 10000, "valid JSON"),
        (show_text(scenes=[]), "1 to 120"),
        (show_text(scenes=[{"name": "<script>", "length": "1:00"}]), "short name"),
        (show_text(scenes=[{"name": "A", "length": "1:99"}]), "time like"),
        (show_text(scenes=[{"name": "A", "length": "0:00"}]), "some time"),
        (show_text(costumes={"x": {"minutes": float("nan")}}), "costume x"),
        (show_text(costumes={"x": {"minutes": 1, "under": ["ghost"]}}), "isn't a costume"),
        (show_text(actors={"Ana": {"wing": "UP", "wears": []}}), "SL or SR"),
        (show_text(actors={"Ana": {"wears": ["dock"]}}), "each of the 6 scenes"),
        (show_text(actors={"Ana": {"wears": ["robe"] * 6}}), "isn't in the costume list"),
        ("x" * 300_000, "256 KB"),
    ],
)
def test_bad_shows_are_refused(text: str, message: str) -> None:
    with pytest.raises(ShowError, match=message):
        load(text)


def test_cli(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    assert main([str(EXAMPLE)]) == 0
    assert "Dresser 1" in capsys.readouterr().out
    assert main([str(tmp_path)]) == 2
    assert main([str(EXAMPLE), "--dressers", "-3"]) == 2
    bad = tmp_path / "bad.json"
    bad.write_bytes(b"\xff\xfe")
    assert main([str(bad)]) == 2
