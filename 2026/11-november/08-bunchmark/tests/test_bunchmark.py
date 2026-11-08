"""Tests for Bunchmark: the physics, the planner against brute force, parsing and the command."""

from __future__ import annotations

import itertools
import os
import random
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "src"))

from bunchmark.parse import Ride, RideError, Segment, parse  # noqa: E402
from bunchmark.physics import V_MAX, Rider, speed  # noqa: E402
from bunchmark.plan import best_plan, segment_times, split, stage  # noqa: E402
from bunchmark.report import clock, report  # noqa: E402

EXAMPLE = (HERE.parent / "examples" / "harbour-hills.txt").read_text()
MIXED = (HERE.parent / "examples" / "mixed-bunch.txt").read_text()


class Physics(unittest.TestCase):
    def test_flat_speed_matches_the_power_balance(self):
        r = Rider("A", 80, 200)
        v = speed(r, 0)
        # 0.97 * 200 = v * (80 * 9.81 * 0.005) + 0.5 * 1.2 * (0.32 * 0.7) * v^3
        self.assertAlmostEqual(0.97 * 200, v * 80 * 9.81 * 0.005 + 0.5 * 1.2 * 0.32 * 0.7 * v**3, places=6)
        self.assertTrue(9 < v < 12)  # about 36 km/h in a bunch

    def test_steep_climbs_go_by_watts_per_kilo(self):
        light, heavy = Rider("L", 60, 180), Rider("H", 90, 270)  # both 3 W/kg
        self.assertAlmostEqual(speed(light, 10), speed(heavy, 10), delta=0.15)
        self.assertGreater(speed(Rider("S", 60, 240), 8), speed(light, 8))

    def test_descents_are_capped_and_speed_falls_with_gradient(self):
        r = Rider("A", 75, 250)
        self.assertEqual(speed(r, -12), V_MAX)
        speeds = [speed(r, g) for g in range(0, 21, 2)]
        self.assertEqual(speeds, sorted(speeds, reverse=True))


def random_ride(rng: random.Random) -> Ride:
    ride = Ride(max_gap=rng.choice([1.0, 2.0, 3.0]))
    ride.riders = [Rider(f"R{i}", rng.uniform(55, 100), rng.uniform(150, 320)) for i in range(rng.randint(2, 5))]
    km = 0.0
    for k in range(rng.randint(3, 9)):
        s = Segment(rng.uniform(0.5, 4), rng.choice([-6, -2, 0, 2, 4, 6, 8]), km)
        ride.segments.append(s)
        km += s.km
        if k > 0 and rng.random() < 0.6:
            ride.regroups.append((k, f"P{k}"))
    return ride


class Planner(unittest.TestCase):
    def test_the_plan_matches_brute_force_over_every_set_of_stops(self):
        rng = random.Random(8)
        tested = feasible = 0
        for _ in range(300):
            ride = random_ride(rng)
            times = segment_times(ride.riders, ride)
            places = [i for i, _ in ride.regroups]
            best = None
            for n in range(len(places) + 1):
                for chosen in itertools.combinations(places, n):
                    cuts = [0, *chosen, len(ride.segments)]
                    stages = [stage(times, a, b) for a, b in itertools.pairwise(cuts)]
                    if any(s.gap > ride.max_gap * 60 + 1e-9 for s in stages):
                        continue
                    key = (n, sum(s.slowest for s in stages) + n * 120)
                    best = key if best is None or key < best else best
            plan = best_plan(ride.riders, ride, 120)
            tested += 1
            if best is None:
                self.assertIsNone(plan)
                continue
            feasible += 1
            self.assertEqual(plan.stops, best[0])
            self.assertAlmostEqual(plan.duration, best[1], places=6)
            for st in plan.stages:
                self.assertLessEqual(st.gap, ride.max_gap * 60 + 1e-9)
        self.assertGreater(feasible, 50)
        self.assertGreater(tested - feasible, 20)

    def test_bunch_pace_on_the_flat_keeps_gaps_constant(self):
        ride = parse("rider A 70 300\nrider B 70 150\nride 5 0\nride 2 6\nride 5 -1\n")
        t = segment_times(ride.riders, ride)
        self.assertEqual(t[0][0], t[1][0])
        self.assertLess(t[0][1], t[1][1])
        self.assertEqual(t[0][2], t[1][2])
        st = stage(t, 0, 3)
        self.assertAlmostEqual(st.gap, t[1][1] - t[0][1])

    def test_example_plan(self):
        ride = parse(EXAMPLE)
        plan = best_plan(ride.riders, ride)
        self.assertEqual([dict(ride.regroups)[s.end] for s in plan.stages[:-1]], ["Bobbin lookout", "Creek bridge"])
        out = report(ride, plan, None)
        self.assertIn("Regroup 2 times: Bobbin lookout (km 10.5), Creek bridge (km 22.3).", out)
        self.assertIn("Without regroups the gap would reach 5:56", out)

    def test_too_wide_a_spread_splits_the_bunch(self):
        ride = parse(MIXED)
        self.assertIsNone(best_plan(ride.riders, ride))
        a, b = split(ride)
        self.assertEqual({r.name for r in a.riders} | {r.name for r in b.riders}, {r.name for r in ride.riders})
        self.assertTrue(len(a.riders) >= 2 and len(b.riders) >= 2)
        out = report(ride, None, (a, b))
        self.assertIn("Split into two bunches instead", out)

    def test_clock(self):
        self.assertEqual(clock(59.6), "1:00")
        self.assertEqual(clock(3725), "1:02:05")


class Parsing(unittest.TestCase):
    def test_refusals_never_echo_the_line(self):
        bad = {
            "": "at least 2 riders",
            "rider A 70 200\nrider B 70 200\n": "no 'ride' lines",
            "rider A 70 200\nrider a 70 200\nride 1 0\n": "two riders",
            "rider A 70 200\nrider B 70 9999\nride 1 0\n": "power",
            "rider A 70 200\nrider B 70 nan\nride 1 0\n": "plain number",
            "rider A 70 200\nrider B 70 1e3\nride 1 0\n": "plain number",
            "rider A 70 200\nrider B 70 200\nride 1 40\n": "gradient",
            "rider A 70 200\nrider B 70 200\nride 1 0\n$(touch SECRET)\n": "expected route",
            "rider <script>SECRET 70 200\nrider B 70 200\nride 1 0\n": "rider's name",
            "rider A‮SECRET 70 200\nrider B 70 200\nride 1 0\n": "invisible",
            "rider A 70 200\x1b[2J\nrider B 70 200\nride 1 0\n": "control",
            "rider A 70 200\nrider B 70 200\nregroup Early\nride 1 0\n": "between the start and the finish",
            "rider A 70 200\nrider B 70 200\nride 1 0\nregroup Twice\nregroup Twice again\nride 1 0\n": "one per place",
            "rider A 70 200\nrider B 70 200\n" + "ride 80 0\n" * 6: "over 400 km",
            "x" * 300: "longer than 200",
            "# " + "x" * 190 + "\n" * 400 + "x" * 66000: "64 KB",
        }
        for text, msg in bad.items():
            with self.assertRaises(RideError) as cm:
                parse(text)
            self.assertIn(msg, str(cm.exception))
            self.assertNotIn("SECRET", str(cm.exception))

    def test_limits(self):
        many = "".join(f"rider R{i} 70 200\n" for i in range(41)) + "ride 1 0\n"
        with self.assertRaises(RideError):
            parse(many)


class Command(unittest.TestCase):
    def run_cli(self, *args, stdin=""):
        env = {**os.environ, "PYTHONPATH": str(HERE.parent / "src")}
        text = isinstance(stdin, str)
        cmd = [sys.executable, "-m", "bunchmark", *args]
        return subprocess.run(cmd, input=stdin, capture_output=True, text=text, env=env, check=False)

    def test_example_and_stdin(self):
        r = self.run_cli(str(HERE.parent / "examples" / "harbour-hills.txt"))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("BUNCHMARK  Harbour Hills ride: 40.2 km, 6 riders", r.stdout)
        r = self.run_cli("-", "--stop-minutes", "0", stdin=EXAMPLE)
        self.assertIn("including 0:00 at each regroup", r.stdout)

    def test_refusals(self):
        with tempfile.TemporaryDirectory() as d:
            link = Path(d) / "link.txt"
            link.symlink_to(HERE.parent / "examples" / "harbour-hills.txt")
            for args in ([str(link)], [d], [str(Path(d) / "SECRET-missing.txt")], ["-", "--stop-minutes", "99"]):
                r = self.run_cli(*args, stdin=EXAMPLE)
                self.assertEqual(r.returncode, 2, args)
                self.assertNotIn("SECRET", r.stderr)
        r = self.run_cli("-", stdin=b"rider \xff\xfe 70 200\n")
        self.assertEqual(r.returncode, 2)


if __name__ == "__main__":
    unittest.main()
