import unittest

from huewise.audit import CONFUSABLE, MAX_COLORS, audit, find_collisions, repaired_palette, worst_case_distance
from huewise.color import delta_e, parse_hex
from huewise.cvd import KINDS, MATRICES, simulate


def run(*colors):
    return audit(list(colors), [parse_hex(c) for c in colors])


class SimulationTests(unittest.TestCase):
    def test_matrix_rows_sum_to_one_so_greys_stay_grey(self):
        for kind, matrix in MATRICES.items():
            for row in matrix:
                self.assertAlmostEqual(sum(row), 1.0, places=3, msg=kind)
        for kind in KINDS:
            for grey in ["#000000", "#808080", "#ffffff"]:
                self.assertLess(delta_e(simulate(parse_hex(grey), kind), parse_hex(grey)), 0.5)

    def test_red_and_green_merge_for_red_green_colour_blindness(self):
        red, green = parse_hex("#d62728"), parse_hex("#2ca02c")
        self.assertGreater(delta_e(red, green), 100)
        self.assertLess(delta_e(simulate(red, "deuteranopia"), simulate(green, "deuteranopia")), CONFUSABLE)
        # Tritanopia (blue-yellow) still tells red from green.
        self.assertGreater(delta_e(simulate(red, "tritanopia"), simulate(green, "tritanopia")), 40)

    def test_unknown_deficiency_is_rejected(self):
        with self.assertRaises(ValueError):
            simulate(parse_hex("#fff"), "x-ray vision")


class AuditTests(unittest.TestCase):
    def test_safe_palettes_pass(self):
        self.assertTrue(run("#000000", "#ffffff").ok)
        # Okabe-Ito: the standard palette designed for colour-blind readers.
        okabe_ito = ["#e69f00", "#56b4e9", "#009e73", "#f0e442", "#0072b2", "#d55e00", "#cc79a7", "#000000"]
        self.assertEqual(run(*okabe_ito).remaining, 0)

    def test_default_chart_colours_collide(self):
        report = run("#d62728", "#2ca02c", "#1f77b4", "#ff7f0e")
        self.assertFalse(report.ok)
        pairs = {(c.a, c.b) for c in report.collisions}
        self.assertIn(("#d62728", "#2ca02c"), pairs)

    def test_fixes_are_verified_to_remove_every_collision(self):
        report = run("#d62728", "#2ca02c", "#1f77b4", "#ff7f0e")
        self.assertTrue(report.fixes)
        self.assertEqual(report.remaining, 0)
        repaired = repaired_palette(report)
        self.assertEqual(len(repaired), 4)
        self.assertEqual(find_collisions({c: parse_hex(c) for c in repaired}), [])
        self.assertTrue(run(*repaired).ok)

    def test_fix_keeps_the_hue_recognisable(self):
        report = run("#d62728", "#2ca02c")
        fixed = parse_hex(report.fixes["#2ca02c"])
        self.assertGreater(fixed.g, fixed.r)  # still a green
        self.assertGreater(fixed.g, fixed.b)
        self.assertGreaterEqual(worst_case_distance(parse_hex("#d62728"), fixed), CONFUSABLE)

    def test_similar_colours_are_not_reported_as_collisions(self):
        # Two near-identical blues look alike to everyone; that is not a CVD problem.
        self.assertTrue(run("#1f77b4", "#2078b5").ok)

    def test_too_many_colours_is_refused(self):
        colors = [f"#{i:02x}{i:02x}{i:02x}" for i in range(MAX_COLORS + 1)]
        with self.assertRaises(ValueError):
            run(*colors)


if __name__ == "__main__":
    unittest.main()
