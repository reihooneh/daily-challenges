import os
import random
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from carryless.cli import LeagueError, parse, safe_cell, to_csv
from carryless.homeaway import assign, cost, count_breaks, venues
from carryless.schedule import _partial_swap, build, carryover_matrix, circle, coe, gf_mul, improve, is_valid, russell

ROOT = Path(__file__).resolve().parents[1]


def run_cli(*args: str, stdin: bytes = b"") -> subprocess.CompletedProcess[bytes]:
    env = {**os.environ, "PYTHONPATH": str(ROOT / "src")}
    return subprocess.run(
        [sys.executable, "-m", "carryless.cli", *args], input=stdin, capture_output=True, env=env, cwd=ROOT, check=False
    )


class Fixtures(unittest.TestCase):
    def test_circle_is_a_valid_round_robin(self):
        for n in range(2, 22, 2):
            self.assertTrue(is_valid(circle(n)), n)

    def test_validity_check_catches_mistakes(self):
        rounds = circle(6)
        rounds[1] = list(rounds[0])  # the same round twice
        self.assertFalse(is_valid(rounds))
        self.assertFalse(is_valid(circle(6)[:-1]))

    def test_field_has_a_primitive_element(self):
        for k in range(1, 7):
            n, seen, a = 1 << k, set(), 1
            for _ in range(n - 1):
                seen.add(a)
                a = gf_mul(a, 2, k)
            self.assertEqual(seen, set(range(1, n)), k)  # 2 generates every nonzero element
            self.assertEqual(a, 1)

    def test_russell_is_perfectly_balanced(self):
        self.assertTrue(is_valid(russell(2)))  # one round: nothing to carry over
        for n in (4, 8, 16, 32, 64):
            rounds = russell(n)
            self.assertTrue(is_valid(rounds), n)
            counts = carryover_matrix(rounds)
            self.assertTrue(all(counts[i][j] == (i != j) for i in range(n) for j in range(n)), n)
            self.assertEqual(coe(rounds), n * (n - 1))
        with self.assertRaises(ValueError):
            russell(6)

    def test_carryover_counts(self):
        for n in (6, 8, 10):
            counts = carryover_matrix(circle(n))
            self.assertEqual(sum(map(sum, counts)), n * (n - 1))  # one count per team per round
            self.assertTrue(all(counts[i][i] == 0 for i in range(n)))
            self.assertGreaterEqual(coe(circle(n)), n * (n - 1))

    def test_partial_swaps_keep_a_valid_fixture(self):
        rng = random.Random(1)  # noqa: S311
        rounds = circle(12)
        for _ in range(300):
            r, s = rng.sample(range(11), 2)
            _partial_swap(rounds, r, s, rng.randrange(12))
            self.assertTrue(is_valid(rounds))

    def test_search_beats_the_circle_method_and_is_repeatable(self):
        for n in (6, 10, 12):
            a, how = build(n, seed=5, steps=4000)
            b, _ = build(n, seed=5, steps=4000)
            self.assertTrue(is_valid(a))
            self.assertEqual(a, b)
            self.assertIn("annealing", how)
            self.assertLess(coe(a), coe(circle(n)) if n > 6 else coe(circle(n)) + 1)
        self.assertEqual(coe(improve(circle(6), seed=1, steps=3000)), 60)

    def test_powers_of_two_use_russell(self):
        rounds, how = build(16)
        self.assertIn("Russell", how)
        self.assertEqual(coe(rounds), 240)


class HomeAway(unittest.TestCase):
    def test_break_counting(self):
        self.assertEqual(count_breaks(list("HAHAH")), 0)
        self.assertEqual(count_breaks(list("HHAAH")), 2)
        self.assertEqual(count_breaks(list("H-HA")), 1)  # a bye is skipped, not a reset

    def test_every_match_has_one_home_team_and_shares_are_kept(self):
        rounds, _ = build(10, steps=2000)
        shares = [(0, 1), (2, 3)]
        home = assign(rounds, None, shares, seed=3, restarts=4)
        for r, opp in enumerate(rounds):
            for i, j in enumerate(opp):
                self.assertNotEqual(home[r][i], home[r][j])
        breaks, clashes = cost(rounds, home, None, shares)
        self.assertEqual(clashes, 0)
        self.assertGreaterEqual(breaks, 8)

    def test_odd_league_gets_one_bye_each(self):
        rounds, _ = build(8)
        bye = 7
        home = assign(rounds, bye, [], seed=1, restarts=3)
        v = venues(rounds, home, bye)
        for t in range(7):
            self.assertEqual(v[t].count("-"), 1)


class Input(unittest.TestCase):
    def test_parses_a_league(self):
        league, teams, shares = parse("league Test cup\nteam A one\nteam B two\nteam C\nshare A one B two\n")
        self.assertEqual((league, teams, shares), ("Test cup", ["A one", "B two", "C"], [(0, 1)]))

    def test_rejects_bad_files(self):
        cases = {
            "team A\nteam B\n": "at least 3",
            "team A\nteam a\nteam C\n": "twice",
            "team =HYPERLINK(1)\nteam B\nteam C\n": "team names",
            "team <b>\nteam B\nteam C\n": "team names",
            "team A\nteam B\nteam C\nshare A Z\n": "share",
            "team A\nteam B\nteam C\nshare A A\n": "share",
            "team A\x1b[31m\nteam B\nteam C\n": "control",
            "team A‮\nteam B\nteam C\n": "hidden direction",
            "drop table\n": "lines start",
            "team " + "x" * 200 + "\n": "longer",
            "".join(f"team T{i}\n" for i in range(41)): "more than 40",
        }
        for text, want in cases.items():
            with self.assertRaises(LeagueError) as ctx:
                parse(text)
            self.assertIn(want, str(ctx.exception), text[:30])
        with self.assertRaises(LeagueError):
            parse("#" * 20000)

    def test_csv_cells_are_safe(self):
        self.assertEqual(safe_cell("=1+1"), "'=1+1")
        self.assertEqual(safe_cell("Rovers"), "Rovers")
        rounds = circle(4)
        home = [[i < o for i, o in enumerate(opp)] for opp in rounds]
        text = to_csv(["A", "B", "C", "D"], rounds, home, None)
        self.assertTrue(text.startswith("Round,Home,Away\r\n"))
        self.assertEqual(text.count("\r\n"), 7)


class CommandLine(unittest.TestCase):
    def test_example(self):
        out = run_cli("examples/netball.txt")
        self.assertEqual(out.returncode, 0, out.stderr)
        text = out.stdout.decode()
        self.assertIn("10 teams, 9 rounds", text)
        self.assertIn("circle fixture scores 468", text)
        self.assertIn("never both at home", text)

    def test_csv_and_stdin(self):
        out = run_cli("-", "--csv", stdin=b"team A\nteam B\nteam C\n")
        self.assertEqual(out.returncode, 0)
        self.assertEqual(out.stdout.decode().count("\r\n"), 4)  # header + 3 matches (one bye a round)

    def test_refuses_unsafe_inputs(self):
        self.assertEqual(run_cli("/dev/zero").returncode, 2)
        self.assertEqual(run_cli("no/such/file").returncode, 2)
        self.assertEqual(run_cli("-", stdin=b"\xff\xfe").returncode, 2)
        self.assertEqual(run_cli("-", stdin=b"#" * 20000).returncode, 2)
        self.assertEqual(run_cli("examples/netball.txt", "--seed", "-1").returncode, 2)
        with tempfile.TemporaryDirectory() as d:
            link = Path(d) / "link.txt"
            link.symlink_to(ROOT / "examples" / "netball.txt")
            self.assertEqual(run_cli(str(link)).returncode, 2)
        err = run_cli("-", stdin=b"team A\x1b]0;pwned\x07\nteam B\nteam C\n").stderr
        self.assertNotIn(b"\x1b", err)
        self.assertNotIn(b"pwned", err)


if __name__ == "__main__":
    unittest.main()
