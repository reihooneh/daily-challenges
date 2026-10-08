import io
import json
import math
import subprocess
import sys
import unittest
from pathlib import Path

from reachmap.analysis import (
    analyse,
    effective_width,
    gap_between,
    index_of_difficulty,
    movement_time,
    reach_zone,
    resting_point,
)
from reachmap.cli import main
from reachmap.layout import Element, LayoutError, parse

EXAMPLE = Path(__file__).resolve().parent.parent / "examples" / "chat-app.json"


def layout_text(elements=None, tasks=None, **screen):
    screen_fields = {"width": 390, "height": 844, "device": "phone", **screen}
    body = {"screen": screen_fields, "elements": elements or [{"id": "ok", "x": 100, "y": 700, "w": 100, "h": 50}]}
    if tasks is not None:
        body["tasks"] = tasks
    return json.dumps(body)


class FittsLaw(unittest.TestCase):
    def test_index_of_difficulty_matches_the_formula(self):
        # A 20-wide target whose centre is 60 away, approached head-on: log2(60/20 + 1) = 2 bits.
        target = Element("t", "t", 70, 0, 20, 20)  # centre (80, 10)
        self.assertAlmostEqual(index_of_difficulty(target, (20, 10)), 2.0)

    def test_bigger_or_closer_is_easier(self):
        start = (0.0, 0.0)
        near_small = Element("a", "a", 100, 0, 20, 20)
        far_small = Element("b", "b", 300, 0, 20, 20)
        far_big = Element("c", "c", 280, 0, 60, 60)
        self.assertLess(index_of_difficulty(near_small, start), index_of_difficulty(far_small, start))
        self.assertLess(index_of_difficulty(far_big, start), index_of_difficulty(far_small, start))

    def test_approach_direction_matters(self):
        # A wide, short button is easy to hit from the side and harder from above.
        button = Element("wide", "wide", 0, 0, 200, 40)  # centre (100, 20)
        self.assertAlmostEqual(effective_width(button, (400, 20)), 200)  # from the side
        self.assertAlmostEqual(effective_width(button, (100, 400)), 40)  # from below
        diagonal = effective_width(button, (100 + 300, 20 + 300))
        self.assertAlmostEqual(diagonal, 40 * math.sqrt(2), places=6)

    def test_starting_on_the_target_is_zero_bits(self):
        target = Element("t", "t", 0, 0, 50, 50)
        self.assertEqual(index_of_difficulty(target, target.centre), 0.0)

    def test_movement_time_uses_the_device_constants(self):
        layout = parse(layout_text())
        target = layout.elements["ok"]
        bits = index_of_difficulty(target, (0, 0))
        self.assertAlmostEqual(movement_time(layout, target, (0, 0)), 0.10 + 0.15 * bits)


class Reach(unittest.TestCase):
    def setUp(self):
        self.layout = parse(layout_text())

    def zone(self, x, y, hand="right"):
        return reach_zone(self.layout, Element("p", "p", x, y, 1, 1), hand)

    def test_bottom_corner_on_the_thumb_side_is_easy(self):
        self.assertEqual(self.zone(330, 780), "easy")

    def test_opposite_top_corner_is_hard(self):
        self.assertEqual(self.zone(10, 40), "hard")
        self.assertEqual(self.zone(370, 40, hand="left"), "hard")

    def test_left_and_right_hands_mirror_each_other(self):
        for x, y in [(20, 500), (200, 300), (350, 100), (100, 800)]:
            self.assertEqual(self.zone(x, y, "right"), self.zone(389 - x, y, "left"))

    def test_desktop_has_no_reach_problem(self):
        desktop = parse(layout_text(device="desktop", width=1440, height=900))
        self.assertEqual(reach_zone(desktop, Element("x", "x", 0, 0, 10, 10), "right"), "easy")
        self.assertEqual(resting_point(desktop, "right"), (720, 450))


class Geometry(unittest.TestCase):
    def test_gaps(self):
        a = Element("a", "a", 0, 0, 10, 10)
        self.assertEqual(gap_between(a, Element("b", "b", 14, 0, 10, 10)), 4)
        self.assertEqual(gap_between(a, Element("c", "c", 0, 13, 10, 10)), 3)
        self.assertEqual(gap_between(a, Element("d", "d", 13, 14, 10, 10)), 5)  # diagonal: 3-4-5
        self.assertLess(gap_between(a, Element("e", "e", 5, 5, 10, 10)), 0)
        self.assertEqual(gap_between(a, Element("f", "f", 10, 0, 10, 10)), 0)  # touching


class Analysis(unittest.TestCase):
    def test_the_example_finds_the_known_problems(self):
        layout = parse(EXAMPLE.read_text())
        problems = "\n".join(analyse(layout).problems)
        for expected in [
            "'Emoji' is 26 x 26, smaller than the 44 x 44",
            "'Message box' and 'Emoji' overlap",
            "'Call' and 'Chat info' are only 4 apart",
            "'Back' is tapped about 25 times a day but sits in the hard-to-reach zone",
        ]:
            self.assertIn(expected, problems)
        self.assertNotIn("'Send' is", problems, "Send is big enough")

    def test_left_handed_users_get_a_different_verdict(self):
        # A button on the left edge, halfway down: a stretch for a right thumb, easy for a left one.
        layout = parse(layout_text(elements=[{"id": "side", "x": 10, "y": 450, "w": 50, "h": 50}]))
        self.assertEqual(analyse(layout, "right").zones["side"], "stretch")
        self.assertEqual(analyse(layout, "left").zones["side"], "easy")

    def test_task_times_add_up_and_count_taps(self):
        layout = parse(EXAMPLE.read_text())
        report = analyse(layout)
        reply = next(t for t in report.tasks if t.name == "Send a reply")
        self.assertEqual([s.target for s in reply.steps], ["message", "send"])
        self.assertAlmostEqual(reply.seconds, sum(s.seconds for s in reply.steps))
        self.assertEqual(report.taps_per_day["send"], 64)  # 60 replies + 4 photos

    def test_a_good_layout_has_no_problems(self):
        text = layout_text(
            elements=[
                {"id": "home", "x": 20, "y": 760, "w": 100, "h": 60},
                {"id": "go", "x": 270, "y": 760, "w": 100, "h": 60},
            ],
            tasks=[{"name": "Go", "steps": ["go"], "per_day": 50}],
        )
        self.assertEqual(analyse(parse(text)).problems, [])


class HostileLayouts(unittest.TestCase):
    def rejected(self, text, expected):
        with self.assertRaises(LayoutError) as caught:
            parse(text)
        self.assertIn(expected, str(caught.exception))
        return str(caught.exception)

    def test_broken_json(self):
        self.rejected("{", "not valid JSON")
        self.rejected("", "not valid JSON")
        self.rejected("[" * 100_001, "larger than")
        # 50,000 levels of nesting would overflow the parser; it is caught and reported, not a crash.
        self.rejected("[" * 50_000 + "]" * 50_000, "not valid JSON")
        self.rejected("[[1]]", "the layout must be an object")

    def test_non_standard_numbers_are_refused(self):
        for constant in ["NaN", "Infinity", "-Infinity"]:
            self.rejected(layout_text().replace('"width": 390', f'"width": {constant}'), "NaN and Infinity")

    def test_duplicate_keys_are_refused(self):
        self.rejected('{"screen": {"width": 390, "width": 1, "height": 844}, "elements": []}', "appears twice")

    def test_types_and_ranges(self):
        self.rejected(layout_text(width=True), "screen.width must be a number")
        self.rejected(layout_text(width="390"), "screen.width must be a number")
        self.rejected(layout_text(width=1e308), "between 100 and 10000")
        self.rejected(layout_text(device="toaster"), 'must be "phone" or "desktop"')
        self.rejected(layout_text(elements=[{"id": "a", "x": -5, "y": 0, "w": 50, "h": 50}]), "element 1.x must be between")
        self.rejected(layout_text(elements=[{"id": "a", "x": 380, "y": 0, "w": 50, "h": 50}]), "sticks out")
        self.rejected(layout_text(elements=[{"id": "a", "x": 0, "y": 0, "w": 0, "h": 50}]), "element 1.w must be between")

    def test_unknown_fields_are_counted_not_echoed(self):
        message = self.rejected(
            json.dumps({"screen": {"width": 390, "height": 844}, "elements": [], "<script>": 1}), "1 unknown field"
        )
        self.assertNotIn("script", message)

    def test_ids_and_labels_are_allow_listed(self):
        for bad_id in ["<b>", "A", "1abc", "a b", "x" * 40, "../etc", "‮evil", ""]:
            message = self.rejected(layout_text(elements=[{"id": bad_id, "x": 0, "y": 0, "w": 50, "h": 50}]), "not allowed")
            self.assertNotIn(bad_id or "\x00", message)
        for bad_label in ["<img src=x onerror=alert(1)>", "\x1b[2Jowned", "a\nb", "x" * 41, "$(id)"]:
            self.rejected(
                layout_text(elements=[{"id": "a", "label": bad_label, "x": 0, "y": 0, "w": 50, "h": 50}]), "not allowed"
            )

    def test_tasks_must_point_at_real_elements(self):
        self.rejected(layout_text(tasks=[{"name": "x", "steps": ["ghost"]}]), "does not exist")
        self.rejected(layout_text(tasks=[{"name": "x", "steps": []}]), "1 to 30")
        self.rejected(layout_text(tasks=[{"name": "x", "steps": ["ok"] * 31}]), "1 to 30")
        self.rejected(layout_text(tasks=[{"name": "x", "steps": [["ok"]]}]), "does not exist")

    def test_size_limits(self):
        many = [{"id": f"e{i}", "x": 0, "y": 0, "w": 5, "h": 5} for i in range(201)]
        self.rejected(layout_text(elements=many), "1 to 200")
        self.rejected(layout_text(elements=[{"id": "a", "x": 0, "y": 0, "w": 5, "h": 5}] * 2), "reuses an id")
        self.rejected(layout_text() + " " * 100_001, "larger than")

    def test_largest_legal_layout_is_quick(self):
        import time

        elements = [{"id": f"e{i}", "x": (i % 10) * 39, "y": (i // 10) * 42, "w": 30, "h": 30} for i in range(200)]
        tasks = [{"name": f"t{i}", "steps": [f"e{(i * 7 + j) % 200}" for j in range(30)], "per_day": 1} for i in range(50)]
        started = time.monotonic()
        report = analyse(parse(layout_text(elements=elements, tasks=tasks)))
        self.assertLess(time.monotonic() - started, 5)
        self.assertGreater(len(report.problems), 0)


class CommandLine(unittest.TestCase):
    def run_main(self, *argv):
        out, err = io.StringIO(), io.StringIO()
        code = main(list(argv), out, err)
        return code, out.getvalue(), err.getvalue()

    def test_report_and_exit_codes(self):
        code, out, err = self.run_main(str(EXAMPLE))
        self.assertEqual(code, 1)
        self.assertEqual(err, "")
        self.assertIn("Send a reply", out)
        self.assertIn("8 problems:", out)
        self.assertIn("blank = easy reach", out)

    def test_bad_input_is_one_clean_line(self):
        for argv in [
            [],
            ["a", "b"],
            ["--hand", "middle", str(EXAMPLE)],
            ["/no/such/file"],
            ["/"],
            ["--bogus"],
            ["../../../etc/shadow/x"],
            ["$(reboot)"],
            ["\x1b]0;owned\x07"],
        ]:
            code, out, err = self.run_main(*argv)
            self.assertEqual(code, 2, argv)
            self.assertEqual(out, "")
            self.assertTrue(err.startswith("reachmap: ") and err.count("\n") == 1, (argv, err))
            self.assertNotIn("reboot", err)
            self.assertNotIn("owned", err)

    def test_main_defaults_to_the_real_arguments(self):
        # The installed `reachmap` command calls main() with no arguments.
        from unittest import mock

        with mock.patch.object(sys, "argv", ["reachmap", str(EXAMPLE)]), mock.patch("sys.stdout", new=io.StringIO()) as out:
            self.assertEqual(main(), 1)
        self.assertIn("Send a reply", out.getvalue())

    def test_the_installed_entry_point_works(self):
        result = subprocess.run(
            [sys.executable, "-m", "reachmap", "-"],
            input=EXAMPLE.read_bytes(),
            capture_output=True,
            env={"PYTHONPATH": str(EXAMPLE.parent.parent / "src")},
            check=False,
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn(b"Message box", result.stdout)
        binary = subprocess.run(
            [sys.executable, "-m", "reachmap", "-"],
            input=b"\xff\xfe{",
            capture_output=True,
            env={"PYTHONPATH": str(EXAMPLE.parent.parent / "src")},
            check=False,
        )
        self.assertEqual(binary.returncode, 2)
        self.assertIn(b"not valid UTF-8", binary.stderr)


if __name__ == "__main__":
    unittest.main()
