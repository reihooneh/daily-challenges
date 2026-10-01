import unittest

from huewise.color import (
    RGB,
    ColorError,
    contrast_ratio,
    delta_e,
    from_lab,
    parse_hex,
    relative_luminance,
    to_hex,
    to_lab,
)


class ParseTests(unittest.TestCase):
    def test_parses_long_and_short_hex(self):
        self.assertEqual(parse_hex("#ff0000"), RGB(1.0, 0.0, 0.0))
        self.assertEqual(parse_hex("#F00"), RGB(1.0, 0.0, 0.0))
        self.assertEqual(to_hex(parse_hex("#1f77b4")), "#1f77b4")

    def test_rejects_everything_that_is_not_a_hex_colour(self):
        bad = [
            "",
            "#",
            "red",
            "ff0000",
            "#ff00",
            "#ff00000",
            "#gggggg",
            "#ff0000; rm -rf /",
            "#fff\n#000",
            " #fff",
            "#fff ",
            "<script>",
            "#" + "f" * 5000,
            None,
            123,
        ]
        for value in bad:
            with self.subTest(value=repr(value)[:30]):
                with self.assertRaises(ColorError):
                    parse_hex(value)

    def test_error_message_does_not_echo_huge_input(self):
        with self.assertRaises(ColorError) as ctx:
            parse_hex("x" * 100_000)
        self.assertLess(len(str(ctx.exception)), 200)


class ConversionTests(unittest.TestCase):
    def test_white_and_black_in_lab(self):
        lightness, a, b = to_lab(parse_hex("#ffffff"))
        self.assertAlmostEqual(lightness, 100, places=1)
        self.assertAlmostEqual(a, 0, places=1)
        self.assertAlmostEqual(b, 0, places=1)
        self.assertAlmostEqual(to_lab(parse_hex("#000000"))[0], 0, places=3)

    def test_lab_round_trip(self):
        for h in ["#1f77b4", "#d62728", "#2ca02c", "#808080", "#fedcba"]:
            self.assertEqual(to_hex(from_lab(to_lab(parse_hex(h)))), h)

    def test_wcag_contrast_reference_values(self):
        self.assertAlmostEqual(contrast_ratio(parse_hex("#000"), parse_hex("#fff")), 21.0, places=2)
        self.assertAlmostEqual(contrast_ratio(parse_hex("#fff"), parse_hex("#fff")), 1.0, places=5)
        # #767676 on white is the well-known "just passes AA" grey (4.54:1).
        self.assertAlmostEqual(contrast_ratio(parse_hex("#767676"), parse_hex("#fff")), 4.54, places=2)

    def test_luminance_bounds_and_delta_e(self):
        self.assertEqual(relative_luminance(parse_hex("#000")), 0.0)
        self.assertAlmostEqual(relative_luminance(parse_hex("#fff")), 1.0, places=5)
        self.assertEqual(delta_e(parse_hex("#123456"), parse_hex("#123456")), 0.0)
        self.assertAlmostEqual(delta_e(parse_hex("#000"), parse_hex("#fff")), 100.0, places=0)

    def test_to_hex_clamps_out_of_range_values(self):
        self.assertEqual(to_hex(RGB(1.5, -0.2, 0.5)), "#ff0080")


if __name__ == "__main__":
    unittest.main()
