import itertools
import os
import random
import subprocess
import sys
import unittest
from pathlib import Path

from shotwise.parse import MAX_BYTES, ShotListError, parse
from shotwise.plan import EXACT_MAX, evaluate, exact, greedy, improve, plan
from shotwise.report import render

ROOT = Path(__file__).resolve().parents[1]
EXAMPLE = ROOT / "examples" / "wedding.txt"


def run_cli(*args: str, stdin: bytes = b"") -> subprocess.CompletedProcess[bytes]:
    env = {**os.environ, "PYTHONPATH": str(ROOT / "src")}
    return subprocess.run(
        [sys.executable, "-m", "shotwise.cli", *args], input=stdin, capture_output=True, env=env, cwd=ROOT, check=False
    )


def brute(sl):
    """Least waiting over every order that meets every constraint, or None."""
    best = None
    for order in itertools.permutations(range(len(sl.labels))):
        waiting, broken, _ = evaluate(sl, list(order))
        if not broken and (best is None or waiting < best):
            best = waiting
    return best


def random_list(rng: random.Random, shots: int, people: int, constraints: bool) -> str:
    names = [f"P{i}" for i in range(people)]
    lines = ["minutes 2"]
    for s in range(shots):
        who = rng.sample(names, rng.randint(1, min(4, people)))
        mins = f" ({rng.randint(1, 4)})" if rng.random() < 0.3 else ""
        lines.append(f"shot S{s}{mins}: {', '.join(who)}")
    used = sorted({n for line in lines[1:] for n in line.split(": ")[1].split(", ")})
    if constraints:
        for name in rng.sample(used, min(2, len(used))):
            lines.append(f"weight {name} {rng.randint(1, 4)}")
        if rng.random() < 0.6:
            lines.append(f"leaves {rng.choice(used)} at {rng.randint(4, 14)}")
        if rng.random() < 0.6:
            lines.append(f"arrives {rng.choice(used)} at {rng.randint(0, 8)}")
        pins = rng.sample(range(shots), 2)
        if rng.random() < 0.3:
            lines.append(f"first S{pins[0]}")
        if rng.random() < 0.3:
            lines.append(f"last S{pins[1]}")
    return "\n".join(lines) + "\n"


class Waiting(unittest.TestCase):
    def test_waiting_is_the_gap_between_first_and_last_shot(self):
        sl = parse("shot A: Ann, Bo\nshot B: Bo\nshot C (3): Ann\n")
        # Ann is in A (0-2) and C (4-7), so she waits through B: 2 minutes.
        self.assertEqual(evaluate(sl, [0, 1, 2])[0], 2)
        self.assertEqual(evaluate(sl, [1, 0, 2])[0], 0)
        self.assertEqual(plan(sl).waiting, 0)

    def test_weights_multiply_waiting(self):
        sl = parse("shot A: Nan, Bo\nshot B (5): Bo\nshot C: Nan\nweight Nan 3\n")
        self.assertEqual(evaluate(sl, [0, 1, 2])[0], 15)

    def test_leaving_and_arriving_times(self):
        sl = parse("shot A: Nan\nshot B: Bo\nshot C: Cy\nleaves Nan at 2\narrives Cy at 4\n")
        pl = plan(sl)
        self.assertEqual(pl.order, [0, 1, 2])
        self.assertTrue(pl.exact)
        self.assertEqual(pl.violations, [])

    def test_first_and_last_are_kept(self):
        sl = parse("shot A: Ann\nshot B: Bo\nshot C: Cy\nfirst C\nlast A\n")
        order = plan(sl).order
        self.assertEqual((order[0], order[-1]), (2, 0))

    def test_impossible_times_give_the_closest_order_and_say_why(self):
        sl = parse("shot A (5): Nan\nshot B (5): Nan\nleaves Nan at 6\n")
        pl = plan(sl)
        self.assertFalse(pl.exact)
        self.assertTrue(any("Nan must leave at 0:06" in v for v in pl.violations))
        out = render(sl, pl)
        self.assertIn("No order meets every arrival and leaving time", out)


class AgainstBruteForce(unittest.TestCase):
    def test_exact_matches_every_permutation(self):
        rng = random.Random(11)
        infeasible = 0
        for _ in range(150):
            sl = parse(random_list(rng, rng.randint(2, 7), rng.randint(2, 6), constraints=True))
            want = brute(sl)
            got = exact(sl)
            if want is None:
                infeasible += 1
                self.assertIsNone(got)
            else:
                waiting, broken, _ = evaluate(sl, got)
                self.assertEqual((waiting, broken), (want, []))
        self.assertGreater(infeasible, 5)

    def test_local_search_is_close_on_mid_sized_lists(self):
        rng = random.Random(5)
        for _ in range(15):
            sl = parse(random_list(rng, 9, 7, constraints=False))
            best = evaluate(sl, exact(sl))[0]
            found = evaluate(sl, improve(sl, greedy(sl)))[0]
            self.assertGreaterEqual(found, best)
            self.assertLessEqual(found, best * 1.5 + 4)

    def test_long_lists_use_the_search_and_never_get_worse(self):
        rng = random.Random(3)
        sl = parse(random_list(rng, 40, 30, constraints=False))
        pl = plan(sl)
        self.assertFalse(pl.exact)
        self.assertEqual(sorted(pl.order), list(range(40)))
        self.assertLessEqual(pl.waiting, evaluate(sl, list(range(40)))[0])

    def test_exact_size_limit_runs_quickly(self):
        import time

        rng = random.Random(9)
        sl = parse(random_list(rng, EXACT_MAX, 20, constraints=True))
        start = time.perf_counter()
        plan(sl)
        self.assertLess(time.perf_counter() - start, 30)


class Example(unittest.TestCase):
    def test_wedding(self):
        sl = parse(EXAMPLE.read_text(encoding="utf-8"))
        pl = plan(sl)
        self.assertTrue(pl.exact)
        self.assertEqual(pl.violations, [])
        self.assertEqual(sl.labels[pl.order[0]], "Couple alone")
        self.assertEqual(sl.labels[pl.order[-1]], "Everyone")
        out = render(sl, pl)
        self.assertIn("Waiting: 164 weighted person-minutes, against 228 in the order as written.", out)
        self.assertIn("As written: Nani must leave at 0:16 but is needed until 0:17.", out)
        self.assertIn("free to go: Nani", out)


class Hostile(unittest.TestCase):
    def rejects(self, text: str, want: str):
        with self.assertRaises(ShotListError) as cm:
            parse(text)
        msg = str(cm.exception)
        self.assertIn(want, msg)
        for secret in ("<script>", "rm -rf", "SECRET"):
            self.assertNotIn(secret, msg)

    def test_bad_lines(self):
        self.rejects("", "no shots")
        self.rejects("shot A: <script>\n", "names use letters")
        self.rejects("shot A: Ann\u202eSECRET\n", "names use letters")
        self.rejects("shot A: Ann\x1b[2J\n", "control character")
        self.rejects("shot A: Ann, Ann\n", "listed twice")
        self.rejects("shot A: Ann\nshot A: Bo\n", "same name")
        self.rejects("shot A (99): Ann\n", "from 1 to 30")
        self.rejects("shot A Ann\n", "write a shot like")
        self.rejects("shot A: Ann\nleaves Bo at 5\n", "isn't in any shot")
        self.rejects("shot A: Ann\nleaves Ann at 5\nleaves Ann at 6\n", "twice")
        self.rejects("shot A: Ann\nleaves Ann soon\n", "write it like")
        self.rejects("shot A: Ann\nweight Ann 50\n", "from 1 to 10")
        self.rejects("shot A: Ann\nfirst B\n", "isn't in the list")
        self.rejects("shot A: Ann\nshot B: Bo\nfirst A\nlast A\n", "both first and last")
        self.rejects("shot A: Ann\nrm -rf /\n", "lines start with")
        self.rejects("minutes 0\nshot A: Ann\n", "from 1 to 30")
        self.rejects("title A\ntitle B\nshot A: Ann\n", "comes once")
        self.rejects("shot A: Ann\n" + "#" * 400 + "\n", "longer than 300")
        self.rejects("#\n" * (MAX_BYTES // 2 + 1), "larger than 32 KB")
        self.rejects("".join(f"shot S{i}: Ann\n" for i in range(61)), "at most 60 shots")
        self.rejects("shot A: " + ", ".join(f"P{i}" for i in range(41)) + "\n", "at most 40 people")

    def test_friendly_input(self):
        sl = parse("\ufefftitle Siobhán & Zoë\r\nshot Família (3): Siobhán, Zoë, João\tSilva\n  # a comment\n")
        self.assertEqual(sl.title, "Siobhán & Zoë")
        self.assertEqual(sl.people, ["Siobhán", "Zoë", "João Silva"])
        self.assertEqual(sl.length(0), 3)


class CommandLine(unittest.TestCase):
    def test_exit_codes_and_files(self):
        r = run_cli(str(EXAMPLE))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(run_cli("-", stdin=EXAMPLE.read_bytes()).stdout, r.stdout)
        self.assertEqual(run_cli("-", stdin=b"shot A (5): Nan\nshot B (5): Nan\nleaves Nan at 6\n").returncode, 1)
        self.assertEqual(run_cli().returncode, 2)
        self.assertEqual(run_cli("a", "b").returncode, 2)

    def test_bad_files(self):
        r = run_cli(str(ROOT))
        self.assertEqual(r.returncode, 2)
        self.assertIn(b"could not be read", r.stderr)
        r = run_cli("secret-name-zz.txt")
        self.assertNotIn(b"secret-name", r.stderr)
        r = run_cli("-", stdin=b"#" * 100_000)
        self.assertIn(b"larger than 32 KB", r.stderr)
        r = run_cli("-", stdin=b"shot A: \xff\xfe\n")
        self.assertIn(b"UTF-8", r.stderr)


if __name__ == "__main__":
    unittest.main()
